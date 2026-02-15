#!/usr/bin/env -S v run

import os

const canonical_file = 'AGENTS.md'
const banner_files = ['LLMS.md', 'doc/agent_workflow.md', 'doc/agent_bugfix_playbook.md']
const generated_slice_file = 'doc/agent_task_slices.md'
const canonical_line = '- Canonical source: `AGENTS.md`'
const stale_line = 'If anything here differs from `AGENTS.md`, follow `AGENTS.md` and treat this file as stale.'

fn main() {
	mut check_only := false
	mut root := '.'
	mut i := 0
	args := os.args[1..]
	for i < args.len {
		arg := args[i]
		if arg == '--check' {
			check_only = true
			i++
			continue
		}
		if arg == '--root' {
			if i + 1 >= args.len {
				eprintln('Missing value after --root')
				exit(1)
			}
			root = args[i + 1]
			i += 2
			continue
		}
		if arg.starts_with('--root=') {
			root = arg.all_after('--root=')
			i++
			continue
		}
		if arg == '--help' || arg == '-h' {
			print_help()
			return
		}
		eprintln('Unknown option: ${arg}')
		exit(1)
	}
	root_abs := os.real_path(root)
	canonical_path := os.join_path(root_abs, canonical_file)
	if !os.exists(canonical_path) {
		eprintln('Missing ${canonical_file} in ${root_abs}.')
		exit(1)
	}
	mut changed := []string{}
	slice_changed := sync_task_slices_doc(root_abs, check_only) or {
		eprintln(err.msg())
		exit(1)
	}
	if slice_changed {
		changed << generated_slice_file
	}
	for path in banner_files {
		updated := ensure_canonical_banner(root_abs, path, check_only) or {
			eprintln(err.msg())
			exit(1)
		}
		if updated {
			changed << path
		}
	}
	if check_only {
		if changed.len > 0 {
			eprintln('Agent docs out of sync with canonical contract (${canonical_file}):')
			for path in changed {
				eprintln('  - ${path}')
			}
			eprintln('Run: ./cmd/tools/agents/sync_agent_docs.vsh --root ${root_abs}')
			exit(1)
		}
		println('Agent docs sync check passed.')
		return
	}
	if changed.len == 0 {
		println('Agent docs already synchronized.')
		return
	}
	println('Synchronized agent docs:')
	for path in changed {
		println('  - ${path}')
	}
}

fn ensure_canonical_banner(root string, rel_path string, check_only bool) !bool {
	path := os.join_path(root, rel_path)
	if !os.exists(path) {
		return error('Missing ${rel_path} in ${root}.')
	}
	lines := os.read_lines(path) or { return error('Failed to read ${path}: ${err}') }
	mut idx := 0
	for idx < lines.len {
		line := lines[idx]
		if line.starts_with('# ') || line.starts_with('## ') {
			break
		}
		idx++
	}
	body := lines[idx..]
	mut new_header := []string{}
	new_header << '<!-- generated: canonical source is AGENTS.md; run ./cmd/tools/agents/sync_agent_docs.vsh -->'
	new_header << canonical_line
	new_header << '- Drift policy: update `AGENTS.md` first, then run `./cmd/tools/agents/sync_agent_docs.vsh`.'
	new_header << stale_line
	new_header << ''
	mut merged := new_header.clone()
	merged << body
	new_content := merged.join('\n') + '\n'
	old_content := lines.join('\n') + '\n'
	if new_content == old_content {
		return false
	}
	if check_only {
		return true
	}
	os.write_file(path, new_content) or { return error('Failed to write ${path}: ${err}') }
	return true
}

fn sync_task_slices_doc(root string, check_only bool) !bool {
	canonical_path := os.join_path(root, canonical_file)
	canonical := os.read_file(canonical_path) or {
		return error('Failed to read ${canonical_path}: ${err}')
	}
	target_path := os.join_path(root, generated_slice_file)
	body := render_task_slices(canonical)
	content := render_with_canonical_header(body)
	old_content := if os.exists(target_path) {
		os.read_file(target_path) or { '' }
	} else {
		''
	}
	if old_content == content {
		return false
	}
	if check_only {
		return true
	}
	dir := os.dir(target_path)
	if dir != '' {
		os.mkdir_all(dir) or { return error('Failed to create ${dir}: ${err}') }
	}
	os.write_file(target_path, content) or {
		return error('Failed to write ${target_path}: ${err}')
	}
	return true
}

fn render_task_slices(canonical string) string {
	sections := extract_h2_sections(canonical)
	mut out := []string{}
	out << '# Agent Task Slices'
	out << 'Generated from `AGENTS.md` to keep startup context focused by task.'
	out << ''
	append_slice(mut out, 'Bugfix Slice', 'Use this for parser/checker/cgen/runtime bugfixes.',
		[
		'Top Rules',
		'Common Workflow',
		'Build & Rebuild',
		'Testing',
		'Debug',
		'Reporting',
	], sections)
	append_slice(mut out, 'Compiler Slice', 'Use this for compiler internals and diagnostics work.',
		[
		'Top Rules',
		'When to Escalate to Broad',
		'Build & Rebuild',
		'Testing',
		'Compiler Architecture',
		'Error Reporting (checker/parser)',
	], sections)
	append_slice(mut out, 'Docs Slice', 'Use this for docs-only edits and reporting requirements.',
		[
		'Top Rules',
		'Agent Rules',
		'Code Style',
		'Tools',
		'Reporting',
	], sections)
	append_slice(mut out, 'Tools Slice', 'Use this for `cmd/tools/**` changes and validation.',
		[
		'Top Rules',
		'Agent Rules',
		'Testing',
		'Tools',
		'Reporting',
	], sections)
	return out.join('\n') + '\n'
}

fn append_slice(mut out []string, title string, description string, section_names []string, sections map[string]string) {
	out << '## ${title}'
	out << description
	out << ''
	for name in section_names {
		if name !in sections {
			out << '- `${name}`: _Missing from AGENTS.md while generating slices._'
			out << ''
			continue
		}
		summary := section_summary_text(sections[name])
		prefix := '- `${name}`: '
		wrapped := wrap_text_with_prefix(prefix, summary, 100)
		for line in wrapped {
			out << line
		}
	}
	out << ''
}

fn extract_h2_sections(content string) map[string]string {
	lines := content.split_into_lines()
	mut sections := map[string]string{}
	mut current_heading := ''
	mut current_lines := []string{}
	for line in lines {
		if line.starts_with('## ') {
			if current_heading != '' {
				sections[current_heading] = current_lines.join('\n')
			}
			current_heading = line[3..].trim_space()
			current_lines = [line]
			continue
		}
		if current_heading != '' {
			current_lines << line
		}
	}
	if current_heading != '' {
		sections[current_heading] = current_lines.join('\n')
	}
	return sections
}

fn section_summary_text(section string) string {
	lines := section.split_into_lines()
	mut i := 0
	for i < lines.len {
		trimmed := lines[i].trim_space()
		if trimmed == '' || trimmed.starts_with('## ') || trimmed.starts_with('### ') {
			i++
			continue
		}
		if is_table_line(trimmed) {
			i++
			continue
		}
		mut parts := []string{}
		if is_list_item_line(trimmed) {
			parts << list_item_text(trimmed)
			i++
			for i < lines.len {
				next_raw := lines[i]
				next := next_raw.trim_space()
				if next == '' || next.starts_with('## ') || next.starts_with('### ')
					|| is_list_item_line(next) || is_table_line(next) {
					break
				}
				if next_raw.starts_with(' ') || next_raw.starts_with('\t') {
					parts << next
					i++
					continue
				}
				break
			}
		} else {
			parts << trimmed
			i++
			for i < lines.len {
				next := lines[i].trim_space()
				if next == '' || next.starts_with('## ') || next.starts_with('### ')
					|| is_list_item_line(next) || is_table_line(next) {
					break
				}
				parts << next
				i++
			}
		}
		return normalize_spaces(parts.join(' '))
	}
	return '_No summary line found in AGENTS.md._'
}

fn is_table_line(line string) bool {
	return line.starts_with('| ') || line.starts_with('|---')
}

fn is_list_item_line(line string) bool {
	if line.starts_with('* ') || line.starts_with('- ') {
		return true
	}
	mut digits := 0
	for ch in line {
		if ch >= `0` && ch <= `9` {
			digits++
			continue
		}
		break
	}
	if digits == 0 {
		return false
	}
	return line.len > digits + 1 && line[digits] == `.` && line[digits + 1] == ` `
}

fn list_item_text(line string) string {
	if line.starts_with('* ') || line.starts_with('- ') {
		return line[2..].trim_space()
	}
	mut digits := 0
	for ch in line {
		if ch >= `0` && ch <= `9` {
			digits++
			continue
		}
		break
	}
	if digits > 0 && line.len > digits + 1 && line[digits] == `.` && line[digits + 1] == ` ` {
		return line[(digits + 2)..].trim_space()
	}
	return line.trim_space()
}

fn normalize_spaces(input string) string {
	parts := input.split(' ').filter(it != '')
	return parts.join(' ')
}

fn wrap_text_with_prefix(prefix string, text string, width int) []string {
	if text == '' {
		return [prefix.trim_right(' ')]
	}
	words := text.split(' ').filter(it != '')
	if words.len == 0 {
		return [prefix.trim_right(' ')]
	}
	mut lines := []string{}
	continuation := ' '.repeat(prefix.len)
	mut current := prefix
	mut current_len := prefix.len
	for word in words {
		needed := if current_len == prefix.len || current_len == continuation.len {
			word.len
		} else {
			word.len + 1
		}
		if current_len + needed > width && current_len > prefix.len
			&& current_len > continuation.len {
			lines << current
			current = continuation + word
			current_len = continuation.len + word.len
			continue
		}
		if current_len > prefix.len && current_len > continuation.len {
			current += ' '
			current_len++
		}
		current += word
		current_len += word.len
	}
	lines << current
	return lines
}

fn render_with_canonical_header(body string) string {
	mut new_header := []string{}
	new_header << '<!-- generated: canonical source is AGENTS.md; run ./cmd/tools/agents/sync_agent_docs.vsh -->'
	new_header << canonical_line
	new_header << '- Drift policy: update `AGENTS.md` first, then run `./cmd/tools/agents/sync_agent_docs.vsh`.'
	new_header << stale_line
	new_header << ''
	new_header << body.trim_right('\n')
	return new_header.join('\n') + '\n'
}

fn print_help() {
	println('Usage:')
	println('  ./cmd/tools/agents/sync_agent_docs.vsh')
	println('  ./cmd/tools/agents/sync_agent_docs.vsh --check')
	println('  ./cmd/tools/agents/sync_agent_docs.vsh --root /path/to/repo')
}
