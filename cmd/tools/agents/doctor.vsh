#!/usr/bin/env -S v run

import os
import cmn

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
	checks << check_file('cmd/tools/agents/agent_test_matrix.yaml', 'Restore cmd/tools/agents/agent_test_matrix.yaml.')
	checks << check_file('cmd/tools/agents/suggest_tests.vsh', 'Restore cmd/tools/agents/suggest_tests.vsh.')
	checks << check_tool('git', 'Install git and ensure it is in PATH.')
	checks << check_tool('make', 'Install make and ensure it is in PATH.')
	checks << check_tool(cmn.resolve_cc_tool(), 'Install the C compiler in CC (or `cc`) and ensure it is in PATH.')
	checks << check_file('v', 'Build bootstrap compiler with: make')
	checks << check_file('vnew', 'Build working compiler with: ./v -g -keepc -o ./vnew cmd/v')
	checks << check_vnew_freshness()
	checks << check_cmd('./vnew version', 'Build/fix ./vnew: ./v -g -keepc -o ./vnew cmd/v')
	checks << check_cmd('./cmd/tools/agents/validate_agent_contract.vsh --matrix-only',
		'Fix matrix/schema issues reported by validate_agent_contract.vsh.')
	checks << check_cmd('./cmd/tools/agents/suggest_tests.vsh --tier fast --json README.md',
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
	exists := cmn.file_exists(path)
	return CheckResult{
		name:   'file ${path}'
		ok:     exists
		detail: if exists { 'present' } else { 'missing' }
		remedy: remedy
	}
}

fn check_tool(name string, remedy string) CheckResult {
	available := cmn.command_in_path(name)
	return CheckResult{
		name:   'tool ${name}'
		ok:     available
		detail: if available { 'available' } else { 'not found in PATH' }
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
	vnew_mtime := os.file_last_mod_unix('vnew')
	if os.exists('v') && os.file_last_mod_unix('v') > vnew_mtime {
		return CheckResult{
			name:   'vnew freshness'
			ok:     false
			detail: 'stale because ./v is newer than ./vnew'
			remedy: 'Rebuild ./vnew: ./v -g -keepc -o ./vnew cmd/v'
		}
	}
	changed_paths := cmn.collect_changed_paths() or {
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

fn is_rebuild_trigger_path(path string) bool {
	return path.starts_with('vlib/v/') || path.starts_with('cmd/v/')
		|| path.starts_with('vlib/builtin/') || path.starts_with('vlib/strings/')
		|| path.starts_with('vlib/os/') || path.starts_with('vlib/strconv/')
		|| path.starts_with('vlib/time/')
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
	println('  ./cmd/tools/agents/doctor.vsh')
	println('')
	println('Runs local prerequisite and agent-contract checks in one pass,')
	println('then prints actionable fixes for any failed checks.')
	println('Checks include CC tool availability and whether ./vnew is stale')
	println('for changed compiler/core trigger paths.')
}
