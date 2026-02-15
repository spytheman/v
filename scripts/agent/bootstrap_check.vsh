#!/usr/bin/env -S v run

import os

fn main() {
	args := os.args[1..]
	if '--help' in args || '-h' in args {
		print_help()
		return
	}
	build_missing := '--build-missing' in args
	mut failures := []string{}
	mut warnings := []string{}
	check_file('v.mod', mut failures)
	check_file('AGENTS.md', mut failures)
	check_file('LLMS.md', mut failures)
	check_file('agent_test_matrix.yaml', mut failures)
	check_file('scripts/agent/suggest_tests.vsh', mut failures)
	check_file('scripts/agent/bootstrap_check.vsh', mut failures)
	check_file('scripts/agent/validate_agent_contract.vsh', mut failures)
	check_file('scripts/agent/sync_agent_docs.vsh', mut failures)
	check_tool('git', mut failures)
	check_tool('make', mut failures)
	cc := os.getenv_opt('CC') or { 'cc' }
	check_tool(cc.split(' ')[0], mut warnings)
	if !os.exists('v') {
		failures << './v is missing. Build it first with: make'
	} else {
		println('[ok] Found ./v')
	}
	if !os.exists('vnew') {
		if build_missing {
			println('[run] ./v -g -keepc -o ./vnew cmd/v')
			build_result := os.execute('./v -g -keepc -o ./vnew cmd/v')
			if build_result.exit_code != 0 {
				failures << 'Failed to build ./vnew automatically.'
			} else {
				println('[ok] Built ./vnew')
			}
		} else {
			failures << './vnew is missing. Build it with: ./v -g -keepc -o ./vnew cmd/v'
		}
	} else {
		println('[ok] Found ./vnew')
	}
	if os.exists('vnew') {
		version_result := os.execute('./vnew version')
		if version_result.exit_code != 0 {
			failures << './vnew exists but failed to run: ./vnew version'
		} else {
			println('[ok] ./vnew runs (${version_result.output.trim_space()})')
		}
	}
	if failures.len > 0 {
		eprintln('\nBootstrap check failed (${failures.len} issue(s)):')
		for message in failures {
			eprintln('  - ${message}')
		}
		if warnings.len > 0 {
			eprintln('\nWarnings:')
			for message in warnings {
				eprintln('  - ${message}')
			}
		}
		exit(1)
	}
	println('\nBootstrap check passed.')
	if warnings.len > 0 {
		println('Warnings:')
		for message in warnings {
			println('  - ${message}')
		}
	}
	println('\nNext commands:')
	println('  ./scripts/agent/suggest_tests.vsh')
	println('  ./scripts/agent/sync_agent_docs.vsh --check')
	println('  make agent-check VEXE=./vnew local=1')
}

fn check_file(path string, mut failures []string) {
	if os.exists(path) {
		println('[ok] Found ${path}')
		return
	}
	failures << 'Missing required file: ${path}'
}

fn check_tool(name string, mut issues []string) {
	if name == '' {
		return
	}
	result := os.execute('command -v ${name} >/dev/null 2>&1')
	if result.exit_code == 0 {
		println('[ok] Tool available: ${name}')
		return
	}
	issues << 'Tool not found in PATH: ${name}'
}

fn print_help() {
	println('Usage:')
	println('  ./scripts/agent/bootstrap_check.vsh [--build-missing]')
	println('')
	println('Checks:')
	println('  - repo marker files')
	println('  - key tools (git, make, cc)')
	println('  - ./v and ./vnew presence and ./vnew execution')
	println('')
	println('Options:')
	println('  --build-missing   build ./vnew automatically if it is missing')
}
