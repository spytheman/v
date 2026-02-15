#!/usr/bin/env -S v run

import os

fn main() {
	args := os.args[1..]
	if '--help' in args || '-h' in args {
		print_help()
		return
	}
	build_missing := '--build-missing' in args
	rebuild_stale := '--rebuild-stale' in args
	mut failures := []string{}
	mut warnings := []string{}
	check_file('v.mod', mut failures)
	check_file('AGENTS.md', mut failures)
	check_file('LLMS.md', mut failures)
	check_file('cmd/tools/agents/agent_test_matrix.yaml', mut failures)
	check_file('cmd/tools/agents/suggest_tests.vsh', mut failures)
	check_file('cmd/tools/agents/bootstrap_check.vsh', mut failures)
	check_file('cmd/tools/agents/validate_agent_contract.vsh', mut failures)
	check_file('cmd/tools/agents/sync_agent_docs.vsh', mut failures)
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
		stale_info := check_vnew_freshness()
		if stale_info.stale {
			if rebuild_stale {
				println('[stale] ./vnew is stale: ${stale_info.reason}')
				println('[run] ./v -g -keepc -o ./vnew cmd/v')
				rebuild_result := os.execute('./v -g -keepc -o ./vnew cmd/v')
				if rebuild_result.exit_code != 0 {
					failures << 'Failed to rebuild stale ./vnew automatically.'
				} else {
					println('[ok] Rebuilt ./vnew (stale reason: ${stale_info.reason})')
				}
			} else {
				failures << './vnew is stale: ${stale_info.reason}. Rebuild with: ./v -g -keepc -o ./vnew cmd/v'
			}
		} else {
			println('[ok] ./vnew freshness: ${stale_info.reason}')
		}
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
	println('  ./cmd/tools/agents/suggest_tests.vsh')
	println('  ./cmd/tools/agents/sync_agent_docs.vsh --check')
	println('  make agent-check VEXE=./vnew local=1')
}

struct StaleInfo {
	stale  bool
	reason string
}

fn check_vnew_freshness() StaleInfo {
	if !os.exists('vnew') {
		return StaleInfo{
			stale:  false
			reason: 'skipped (./vnew missing)'
		}
	}
	vnew_mtime := os.file_last_mod_unix('vnew')
	if os.exists('v') && os.file_last_mod_unix('v') > vnew_mtime {
		return StaleInfo{
			stale:  true
			reason: './v is newer than ./vnew'
		}
	}
	changed_paths := collect_changed_paths() or {
		return StaleInfo{
			stale:  false
			reason: 'skipped (unable to read git changes)'
		}
	}
	mut trigger_paths := []string{}
	for path in changed_paths {
		if is_rebuild_trigger_path(path) && os.exists(path) {
			trigger_paths << path
		}
	}
	if trigger_paths.len == 0 {
		return StaleInfo{
			stale:  false
			reason: 'fresh (no rebuild-trigger changes in working tree)'
		}
	}
	mut stale_paths := []string{}
	for path in trigger_paths {
		if os.file_last_mod_unix(path) > vnew_mtime {
			stale_paths << path
		}
	}
	if stale_paths.len == 0 {
		return StaleInfo{
			stale:  false
			reason: 'fresh for ${trigger_paths.len} rebuild-trigger path(s)'
		}
	}
	preview := stale_paths[..if stale_paths.len < 3 { stale_paths.len } else { 3 }].join(', ')
	return StaleInfo{
		stale:  true
		reason: '${stale_paths.len} newer rebuild-trigger path(s) (e.g. ${preview})'
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
	println('  ./cmd/tools/agents/bootstrap_check.vsh [--build-missing] [--rebuild-stale]')
	println('')
	println('Checks:')
	println('  - repo marker files')
	println('  - key tools (git, make, cc)')
	println('  - ./v and ./vnew presence and ./vnew execution')
	println('')
	println('Options:')
	println('  --build-missing   build ./vnew automatically if it is missing')
	println('  --rebuild-stale   rebuild ./vnew automatically when stale triggers are newer')
}
