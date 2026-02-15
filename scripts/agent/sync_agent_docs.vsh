#!/usr/bin/env -S v run

import os

const canonical_file = 'AGENTS.md'
const derived_files = ['LLMS.md', 'doc/agent_workflow.md', 'doc/agent_bugfix_playbook.md']
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
	for path in derived_files {
		updated := ensure_canonical_banner(root_abs, path) or {
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
			eprintln('Run: ./scripts/agent/sync_agent_docs.vsh --root ${root_abs}')
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

fn ensure_canonical_banner(root string, rel_path string) !bool {
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
	new_header << '<!-- generated: canonical source is AGENTS.md; run ./scripts/agent/sync_agent_docs.vsh -->'
	new_header << canonical_line
	new_header << '- Drift policy: update `AGENTS.md` first, then run `./scripts/agent/sync_agent_docs.vsh`.'
	new_header << stale_line
	new_header << ''
	mut merged := new_header.clone()
	merged << body
	new_content := merged.join('\n') + '\n'
	old_content := lines.join('\n') + '\n'
	if new_content == old_content {
		return false
	}
	os.write_file(path, new_content) or { return error('Failed to write ${path}: ${err}') }
	return true
}

fn print_help() {
	println('Usage:')
	println('  ./scripts/agent/sync_agent_docs.vsh')
	println('  ./scripts/agent/sync_agent_docs.vsh --check')
	println('  ./scripts/agent/sync_agent_docs.vsh --root /path/to/repo')
}
