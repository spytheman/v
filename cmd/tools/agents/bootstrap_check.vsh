#!/usr/bin/env -S v run

import os
import cmn

const agent_policy_path = 'cmd/tools/agents/agent_policy_min.yaml'

struct AgentPolicy {
mut:
	required_files     []string
	required_tools     []string
	rebuild_triggers   []string
	build_vnew_command string
	check_vnew_command string
	next_commands      []string
}

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
	policy := load_policy(agent_policy_path) or {
		warnings << 'failed to parse ${agent_policy_path}: ${err}; using built-in defaults'
		default_policy()
	}
	for path in policy.required_files {
		check_file(path, mut failures)
	}
	for tool in policy.required_tools {
		if tool == 'cc' {
			check_tool(cmn.resolve_cc_tool(), mut warnings)
			continue
		}
		check_tool(tool, mut failures)
	}
	if !os.exists('v') {
		failures << './v is missing. Build it first with: make'
	} else {
		println('[ok] Found ./v')
	}
	if !os.exists('vnew') {
		if build_missing {
			println('[run] ${policy.build_vnew_command}')
			build_result := os.execute(policy.build_vnew_command)
			if build_result.exit_code != 0 {
				failures << 'Failed to build ./vnew automatically.'
			} else {
				println('[ok] Built ./vnew')
			}
		} else {
			failures << './vnew is missing. Build it with: ${policy.build_vnew_command}'
		}
	} else {
		println('[ok] Found ./vnew')
	}
	if os.exists('vnew') {
		stale_info := check_vnew_freshness(policy)
		if stale_info.stale {
			if rebuild_stale {
				println('[stale] ./vnew is stale: ${stale_info.reason}')
				println('[run] ${policy.build_vnew_command}')
				rebuild_result := os.execute(policy.build_vnew_command)
				if rebuild_result.exit_code != 0 {
					failures << 'Failed to rebuild stale ./vnew automatically.'
				} else {
					println('[ok] Rebuilt ./vnew (stale reason: ${stale_info.reason})')
				}
			} else {
				failures << './vnew is stale: ${stale_info.reason}. Rebuild with: ${policy.build_vnew_command}'
			}
		} else {
			println('[ok] ./vnew freshness: ${stale_info.reason}')
		}
		version_result := os.execute(policy.check_vnew_command)
		if version_result.exit_code != 0 {
			failures << './vnew exists but failed to run: ${policy.check_vnew_command}'
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
	for command in policy.next_commands {
		println('  ${command}')
	}
}

struct StaleInfo {
	stale  bool
	reason string
}

fn check_vnew_freshness(policy AgentPolicy) StaleInfo {
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
	changed_paths := cmn.collect_changed_paths() or {
		return StaleInfo{
			stale:  false
			reason: 'skipped (unable to read git changes)'
		}
	}
	mut trigger_paths := []string{}
	for path in changed_paths {
		if is_rebuild_trigger_path(path, policy) && is_v_source_path(path) && os.exists(path) {
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

fn is_rebuild_trigger_path(path string, policy AgentPolicy) bool {
	for pattern in policy.rebuild_triggers {
		if cmn.pattern_matches_path(pattern, path) {
			return true
		}
	}
	return false
}

fn is_v_source_path(path string) bool {
	return path.ends_with('.v') || path.ends_with('.vsh') || path.ends_with('.vv')
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

fn load_policy(path string) !AgentPolicy {
	if !os.exists(path) {
		return error('missing ${path}')
	}
	lines := os.read_lines(path)!
	mut policy := AgentPolicy{}
	mut section := ''
	for raw in lines {
		line := raw.trim_space()
		if line == '' || line.starts_with('#') {
			continue
		}
		if line == 'required_files:' || line == 'required_tools:' || line == 'rebuild_triggers:'
			|| line == 'commands:' || line == 'next_commands:' {
			section = line[..line.len - 1]
			continue
		}
		if line.starts_with('- ') {
			item := line.all_after('- ').trim_space()
			if section == 'required_files' {
				policy.required_files << item
			} else if section == 'required_tools' {
				policy.required_tools << item
			} else if section == 'rebuild_triggers' {
				policy.rebuild_triggers << item
			} else if section == 'next_commands' {
				policy.next_commands << item
			}
			continue
		}
		if line.contains(':') && section == 'commands' {
			key := line.all_before(':').trim_space()
			value := line.all_after(':').trim_space()
			if key == 'build_vnew' {
				policy.build_vnew_command = value
			} else if key == 'check_vnew' {
				policy.check_vnew_command = value
			}
		}
	}
	if policy.required_files.len == 0 {
		return error('required_files is empty')
	}
	if policy.required_tools.len == 0 {
		return error('required_tools is empty')
	}
	if policy.rebuild_triggers.len == 0 {
		return error('rebuild_triggers is empty')
	}
	if policy.build_vnew_command == '' || policy.check_vnew_command == '' {
		return error('commands section is incomplete')
	}
	if policy.next_commands.len == 0 {
		return error('next_commands is empty')
	}
	return policy
}

fn default_policy() AgentPolicy {
	return AgentPolicy{
		required_files:     [
			'v.mod',
			'AGENTS.md',
			'LLMS.md',
			'cmd/tools/agents/agent_policy_min.yaml',
			'cmd/tools/agents/agent_test_matrix.yaml',
			'cmd/tools/agents/suggest_tests.vsh',
			'cmd/tools/agents/bootstrap_check.vsh',
			'cmd/tools/agents/validate_agent_contract.vsh',
			'cmd/tools/agents/sync_agent_docs.vsh',
		]
		required_tools:     ['git', 'make', 'cc']
		rebuild_triggers:   [
			'vlib/v/**',
			'cmd/v/**',
			'vlib/builtin/**',
			'vlib/strings/**',
			'vlib/os/**',
			'vlib/strconv/**',
			'vlib/time/**',
		]
		build_vnew_command: './v -g -keepc -o ./vnew cmd/v'
		check_vnew_command: './vnew version'
		next_commands:      [
			'./cmd/tools/agents/suggest_tests.vsh',
			'./cmd/tools/agents/sync_agent_docs.vsh --check',
			'make agent-check VEXE=./vnew local=1',
		]
	}
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
