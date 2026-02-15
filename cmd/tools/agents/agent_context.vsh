#!/usr/bin/env -S v run

import os
import x.json2

fn main() {
	args := os.args[1..]
	if '--help' in args || '-h' in args {
		print_help()
		return
	}
	suggest_cmd := build_suggest_command(args)
	result := os.execute(suggest_cmd)
	if result.exit_code != 0 {
		eprintln('Failed to build agent context (suggest_tests failed):')
		eprintln(result.output)
		exit(result.exit_code)
	}
	print_context(result.output) or {
		eprintln('Failed to build agent context:')
		eprintln('  - ${err.msg()}')
		exit(1)
	}
}

fn build_suggest_command(args []string) string {
	parsed := parse_context_args(args)
	mut escaped := []string{}
	for arg in parsed.forwarded_args {
		escaped << os.quoted_path(arg)
	}
	mut cmd := './cmd/tools/agents/suggest_tests.vsh --json --explain-match --impact-mode ${parsed.impact_mode}'
	if escaped.len > 0 {
		cmd += ' ' + escaped.join(' ')
	}
	return cmd
}

struct ParsedContextArgs {
mut:
	forwarded_args []string
	impact_mode    string = 'semantic'
}

fn parse_context_args(args []string) ParsedContextArgs {
	mut parsed := ParsedContextArgs{}
	mut i := 0
	for i < args.len {
		arg := args[i]
		if arg == '--no-semantic-impact' {
			if parsed.impact_mode == 'semantic' {
				parsed.impact_mode = 'basic'
			}
			i++
			continue
		}
		if arg == '--impact-mode' {
			if i + 1 < args.len {
				parsed.impact_mode = args[i + 1]
				parsed.forwarded_args << arg
				parsed.forwarded_args << args[i + 1]
				i += 2
				continue
			}
		}
		if arg.starts_with('--impact-mode=') {
			parsed.impact_mode = arg.all_after('--impact-mode=')
		}
		parsed.forwarded_args << arg
		i++
	}
	return parsed
}

fn print_context(payload string) ! {
	root_any := json2.decode[json2.Any](payload) or { return error('invalid JSON: ${err}') }
	root := expect_object(root_any, 'context payload')!

	tier := require_string(root, 'tier', 'context payload')!
	effective_tier := require_string(root, 'effective_tier', 'context payload')!
	rebuild := require_bool(root, 'rebuild_vnew', 'context payload')!
	rebuild_command := require_string(root, 'rebuild_command', 'context payload')!
	escalation_reason := require_string(root, 'escalation_reason', 'context payload')!
	runtime_total := require_number(root, 'runtime_total_sec', 'context payload')!
	runtime_used := require_number(root, 'runtime_used_sec', 'context payload')!
	changed_paths_raw := require_string_array(root, 'changed_paths', 'context payload')!
	warnings := require_string_array(root, 'warnings', 'context payload')!
	owners := extract_owner_risk_pairs(root, 'context payload')!
	suggested := extract_suggested(root, 'context payload')!
	mut changed_paths := []string{}
	mut derived_paths := []string{}
	for path in changed_paths_raw {
		if is_derived_impact_path(path) {
			derived_paths << path
		} else {
			changed_paths << path
		}
	}
	mut derived_warnings := []string{}
	mut normal_warnings := []string{}
	for warning in warnings {
		if warning.starts_with('impact map:')
			|| warning.starts_with('impact map (derived):') || warning.starts_with('semantic impact:')
			|| warning.starts_with('semantic impact (derived):') {
			derived_warnings << warning
		} else {
			normal_warnings << warning
		}
	}

	println('Agent context:')
	println('  tier=${tier} effective_tier=${effective_tier} rebuild_vnew=${if rebuild {
		`y`
	} else {
		`n`
	}}')
	if rebuild {
		println('  rebuild_command=${rebuild_command}')
	}
	println('  changed_paths=${changed_paths.len} derived=${derived_paths.len} owners=' +
		if owners.len == 0 { 'none' } else { owners.join(', ') })
	println('  runtime_estimate_sec total=${runtime_total} selected=${runtime_used}')
	println('  escalation_reason=${escalation_reason}')

	println('')
	println('Changed paths:')
	if changed_paths.len == 0 {
		println('  - none')
	} else {
		for path in changed_paths {
			println('  - ${path}')
		}
	}
	if derived_paths.len > 0 {
		println('')
		println('Derived impact paths:')
		for path in derived_paths {
			println('  - ${path}')
		}
	}
	if derived_warnings.len > 0 {
		println('')
		println('Derived impact notes:')
		for warning in derived_warnings {
			println('  - ${warning}')
		}
	}

	println('')
	println('Minimal validation commands:')
	if suggested.len == 0 {
		println('  - none')
	} else {
		for line in suggested {
			println('  - ${line}')
		}
	}

	if normal_warnings.len > 0 {
		println('')
		println('Warnings:')
		for warning in normal_warnings {
			println('  - ${warning}')
		}
	}
}

fn is_derived_impact_path(path string) bool {
	return path.contains('/__impact__.')
}

fn extract_owner_risk_pairs(root map[string]json2.Any, path string) ![]string {
	values := require_array(root, 'matched_rules', path)!
	mut seen := map[string]bool{}
	mut out := []string{}
	for i, raw in values {
		item := expect_object(raw, '${path}: matched_rules[${i}]')!
		owner := require_string(item, 'owner', path)!
		risk := require_string(item, 'risk', path)!
		label := '${owner}:${risk}'
		if label in seen {
			continue
		}
		seen[label] = true
		out << label
	}
	return out
}

fn extract_suggested(root map[string]json2.Any, path string) ![]string {
	values := require_array(root, 'suggested', path)!
	mut lines := []string{}
	for i, raw in values {
		item := expect_object(raw, '${path}: suggested[${i}]')!
		command := require_string(item, 'command', path)!
		confidence := require_number(item, 'confidence', path)!
		runtime_sec := require_number(item, 'runtime_sec', path)!
		lines << '[${confidence:.2f} ~${runtime_sec}s] ${command}'
	}
	return lines
}

fn require_key(obj map[string]json2.Any, key string, path string) !json2.Any {
	if key !in obj {
		return error('${path}: missing required field `${key}`')
	}
	return obj[key] or { return error('${path}: missing required field `${key}`') }
}

fn require_string(obj map[string]json2.Any, key string, path string) !string {
	value := require_key(obj, key, path)!
	match value {
		string {
			return value
		}
		else {
			return error('${path}: `${key}` must be a string')
		}
	}
}

fn require_bool(obj map[string]json2.Any, key string, path string) !bool {
	value := require_key(obj, key, path)!
	match value {
		bool {
			return value
		}
		else {
			return error('${path}: `${key}` must be a boolean')
		}
	}
}

fn require_number(obj map[string]json2.Any, key string, path string) !f64 {
	value := require_key(obj, key, path)!
	match value {
		f64, f32, i64, int, i32, i16, i8, u64, u32, u16, u8 {
			return f64(value)
		}
		else {
			return error('${path}: `${key}` must be numeric')
		}
	}
}

fn require_array(obj map[string]json2.Any, key string, path string) ![]json2.Any {
	value := require_key(obj, key, path)!
	match value {
		[]json2.Any {
			return value
		}
		else {
			return error('${path}: `${key}` must be an array')
		}
	}
}

fn require_string_array(obj map[string]json2.Any, key string, path string) ![]string {
	values := require_array(obj, key, path)!
	mut out := []string{}
	for i, raw in values {
		match raw {
			string {
				out << raw
			}
			else {
				return error('${path}: `${key}[${i}]` must be a string')
			}
		}
	}
	return out
}

fn expect_object(value json2.Any, ctx string) !map[string]json2.Any {
	match value {
		map[string]json2.Any {
			return value
		}
		else {
			return error('${ctx} must be an object')
		}
	}
}

fn print_help() {
	println('Usage:')
	println('  ./cmd/tools/agents/agent_context.vsh [--tier ...] [--changed-from ...] [paths ...]')
	println('  ./cmd/tools/agents/agent_context.vsh --no-semantic-impact [--tier ...] [paths ...]')
	println('')
	println('Builds a compact, execution-ready context summary by calling suggest_tests.')
	println('Defaults to: --json --explain-match --impact-mode semantic')
	println('--no-semantic-impact switches the default to --impact-mode basic for faster loops.')
}
