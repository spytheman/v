#!/usr/bin/env -S v run

import os

struct CheckResult {
	name   string
	ok     bool
	detail string
	remedy string
}

fn main() {
	args := os.args[1..]
	if '--help' in args || '-h' in args {
		print_help()
		return
	}
	mut checks := []CheckResult{}
	checks << check_file('v.mod', 'Run from repo root.')
	checks << check_file('AGENTS.md', 'Sync repository agent docs.')
	checks << check_file('LLMS.md', 'Regenerate or restore LLMS.md.')
	checks << check_file('agent_test_matrix.yaml', 'Restore agent_test_matrix.yaml.')
	checks << check_file('scripts/agent/suggest_tests.vsh', 'Restore scripts/agent/suggest_tests.vsh.')
	checks << check_tool('git', 'Install git and ensure it is in PATH.')
	checks << check_tool('make', 'Install make and ensure it is in PATH.')
	checks << check_tool(resolve_cc_tool(), 'Install the C compiler in CC (or `cc`) and ensure it is in PATH.')
	checks << check_file('v', 'Build bootstrap compiler with: make')
	checks << check_file('vnew', 'Build working compiler with: ./v -g -keepc -o ./vnew cmd/v')
	checks << check_vnew_freshness()
	checks << check_cmd('./vnew version', 'Build/fix ./vnew: ./v -g -keepc -o ./vnew cmd/v')
	checks << check_cmd('./scripts/agent/validate_agent_contract.vsh --matrix-only', 'Fix matrix/schema issues reported by validate_agent_contract.vsh.')
	checks << check_cmd('./scripts/agent/suggest_tests.vsh --tier fast --json README.md',
		'Fix suggest_tests script/matrix and re-run with README.md.')

	mut failed := 0
	println('Agent doctor report:')
	for check in checks {
		if check.ok {
			println('  [ok] ${check.name}: ${check.detail}')
			continue
		}
		failed++
		println('  [fix] ${check.name}: ${check.detail}')
		println('        remedy: ${check.remedy}')
	}
	if failed > 0 {
		println('\nDoctor result: ${failed} issue(s) found.')
		exit(1)
	}
	println('\nDoctor result: all checks passed.')
}

fn check_file(path string, remedy string) CheckResult {
	return CheckResult{
		name:   'file ${path}'
		ok:     os.exists(path)
		detail: if os.exists(path) { 'present' } else { 'missing' }
		remedy: remedy
	}
}

fn check_tool(name string, remedy string) CheckResult {
	result := os.execute('command -v ${name} >/dev/null 2>&1')
	return CheckResult{
		name:   'tool ${name}'
		ok:     result.exit_code == 0
		detail: if result.exit_code == 0 { 'available' } else { 'not found in PATH' }
		remedy: remedy
	}
}

fn check_vnew_freshness() CheckResult {
	if !os.exists('vnew') {
		return CheckResult{
			name:   'vnew freshness'
			ok:     false
			detail: 'cannot evaluate: ./vnew is missing'
			remedy: 'Build working compiler with: ./v -g -keepc -o ./vnew cmd/v'
		}
	}
	changed_paths := collect_changed_paths() or {
		return CheckResult{
			name:   'vnew freshness'
			ok:     true
			detail: 'skipped (unable to read git changes)'
			remedy: ''
		}
	}
	mut trigger_paths := []string{}
	for path in changed_paths {
		if is_rebuild_trigger_path(path) && os.exists(path) {
			trigger_paths << path
		}
	}
	if trigger_paths.len == 0 {
		return CheckResult{
			name:   'vnew freshness'
			ok:     true
			detail: 'fresh (no compiler/core rebuild-trigger changes)'
			remedy: ''
		}
	}
	vnew_mtime := os.file_last_mod_unix('vnew')
	mut stale_paths := []string{}
	for path in trigger_paths {
		if os.file_last_mod_unix(path) > vnew_mtime {
			stale_paths << path
		}
	}
	if stale_paths.len == 0 {
		return CheckResult{
			name:   'vnew freshness'
			ok:     true
			detail: 'fresh for ${trigger_paths.len} rebuild-trigger path(s)'
			remedy: ''
		}
	}
	preview := stale_paths[..if stale_paths.len < 3 { stale_paths.len } else { 3 }].join(', ')
	return CheckResult{
		name:   'vnew freshness'
		ok:     false
		detail: 'stale for ${stale_paths.len} rebuild-trigger path(s) (e.g. ${preview})'
		remedy: 'Rebuild ./vnew: ./v -g -keepc -o ./vnew cmd/v'
	}
}

fn collect_changed_paths() ![]string {
	commands := [
		'git diff --name-only',
		'git diff --cached --name-only',
		'git ls-files --others --exclude-standard',
	]
	mut paths := []string{}
	mut seen := map[string]bool{}
	mut command_ok := false
	for command in commands {
		result := os.execute(command)
		if result.exit_code != 0 {
			continue
		}
		command_ok = true
		for line in result.output.split_into_lines() {
			path := normalize_path(line)
			if path == '' || path in seen {
				continue
			}
			seen[path] = true
			paths << path
		}
	}
	if !command_ok {
		return error('git commands failed')
	}
	return paths
}

fn is_rebuild_trigger_path(path string) bool {
	return path.starts_with('vlib/v/') || path.starts_with('cmd/v/')
		|| path.starts_with('vlib/builtin/') || path.starts_with('vlib/strings/')
		|| path.starts_with('vlib/os/') || path.starts_with('vlib/strconv/')
		|| path.starts_with('vlib/time/')
}

fn normalize_path(path string) string {
	mut normalized := path.trim_space()
	for normalized.starts_with('./') {
		normalized = normalized[2..]
	}
	return normalized
}

fn resolve_cc_tool() string {
	cc := os.getenv_opt('CC') or { 'cc' }
	cc_token := cc.split_any(' \t').filter(it != '')
	return if cc_token.len > 0 { cc_token[0] } else { 'cc' }
}

fn check_cmd(command string, remedy string) CheckResult {
	result := os.execute(command)
	return CheckResult{
		name:   command
		ok:     result.exit_code == 0
		detail: if result.exit_code == 0 { 'ok' } else { 'exit code ${result.exit_code}' }
		remedy: remedy
	}
}

fn print_help() {
	println('Usage:')
	println('  ./scripts/agent/doctor.vsh')
	println('')
	println('Runs local prerequisite and agent-contract checks in one pass,')
	println('then prints actionable fixes for any failed checks.')
	println('Checks include CC tool availability and whether ./vnew is stale')
	println('for changed compiler/core trigger paths.')
}
