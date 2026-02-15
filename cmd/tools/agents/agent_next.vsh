#!/usr/bin/env -S v run

import os

const max_next_commands = 3

fn main() {
	args := os.args[1..]
	if '--help' in args || '-h' in args {
		print_help()
		return
	}
	mut escaped := []string{}
	for arg in args {
		escaped << os.quoted_path(arg)
	}
	mut suggest_cmd := './cmd/tools/agents/suggest_tests.vsh --format sh --tier targeted'
	if escaped.len > 0 {
		suggest_cmd += ' ' + escaped.join(' ')
	}
	result := os.execute(suggest_cmd)
	if result.exit_code != 0 {
		eprintln('Failed to compute next commands:')
		eprintln(result.output)
		exit(result.exit_code)
	}
	commands := extract_commands(result.output)
	if commands.len == 0 {
		println('Next commands: none')
		return
	}
	println('Next ${if commands.len < max_next_commands { commands.len } else { max_next_commands }} command(s):')
	for i, command in commands {
		if i >= max_next_commands {
			break
		}
		println('${i + 1}. ${command}')
	}
}

fn extract_commands(output string) []string {
	mut commands := []string{}
	for raw in output.split_into_lines() {
		line := raw.trim_space()
		if line == '' || line.starts_with('#') {
			continue
		}
		if line.starts_with('set -') {
			continue
		}
		commands << line
	}
	return commands
}

fn print_help() {
	println('Usage:')
	println('  ./cmd/tools/agents/agent_next.vsh [--changed-from <rev> | changed_file ...]')
	println('')
	println('Prints the next 1-3 shell commands for a targeted bugfix loop.')
	println('Internally runs:')
	println('  ./cmd/tools/agents/suggest_tests.vsh --format sh --tier targeted [args]')
}
