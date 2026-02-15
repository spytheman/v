#!/usr/bin/env -S v run

import os
import x.json2

fn main() {
	args := os.args[1..]
	if '--help' in args || '-h' in args {
		print_help()
		return
	}
	path := if args.len > 0 { args[0] } else { '/tmp/agent_run_summary.json' }
	validate_summary(path) or {
		eprintln('Agent run summary schema validation failed:')
		eprintln('  - ${err.msg()}')
		exit(1)
	}
	println('Agent run summary schema validation passed.')
}

fn print_help() {
	println('Usage:')
	println('  ./cmd/tools/agents/validate_agent_run_summary.vsh [path/to/agent_run_summary.json]')
	println('Default path: /tmp/agent_run_summary.json')
}

fn validate_summary(path string) ! {
	content := os.read_file(path) or { return error('failed to read `${path}`: ${err}') }
	root_any := json2.decode[json2.Any](content) or {
		return error('invalid JSON in `${path}`: ${err}')
	}
	root := expect_object(root_any, '${path}: root')!
	require_string(root, 'tier', path)!
	require_string(root, 'effective_tier', path)!
	require_string_array(root, 'changed_paths', path)!
	require_string_array(root, 'matched_paths', path)!
	require_string_array(root, 'unmatched_paths', path)!
	require_bool(root, 'rebuild_vnew', path)!
	require_string(root, 'rebuild_command', path)!
	validate_matched_rules(root, path)!
	validate_suggested(root, path)!
	validate_dropped_by_budget(root, path)!
	require_string_array(root, 'suggested_commands', path)!
	require_string_array(root, 'warnings', path)!
	require_number(root, 'budget_seconds', path)!
	require_number(root, 'runtime_total_sec', path)!
	require_number(root, 'runtime_used_sec', path)!
	validate_timings(root, path)!
}

fn validate_matched_rules(root map[string]json2.Any, path string) ! {
	values := require_array(root, 'matched_rules', path)!
	for i, raw in values {
		item := expect_object(raw, '${path}: matched_rules[${i}]')!
		require_string(item, 'owner', path)!
		require_string(item, 'risk', path)!
		require_string_array(item, 'patterns', path)!
		require_string_array(item, 'matched_paths', path)!
		require_bool(item, 'rebuild_vnew', path)!
	}
}

fn validate_suggested(root map[string]json2.Any, path string) ! {
	values := require_array(root, 'suggested', path)!
	for i, raw in values {
		item := expect_object(raw, '${path}: suggested[${i}]')!
		require_string(item, 'command', path)!
		require_number(item, 'confidence', path)!
		require_string(item, 'confidence_label', path)!
		require_number(item, 'runtime_sec', path)!
		require_string(item, 'why_selected', path)!
		require_bool(item, 'flaky', path)!
		require_string(item, 'flaky_reason', path)!
		require_string(item, 'flaky_issue', path)!
	}
}

fn validate_dropped_by_budget(root map[string]json2.Any, path string) ! {
	values := require_array(root, 'dropped_by_budget', path)!
	for i, raw in values {
		item := expect_object(raw, '${path}: dropped_by_budget[${i}]')!
		require_string(item, 'command', path)!
		require_number(item, 'confidence', path)!
		require_number(item, 'runtime_sec', path)!
		require_string(item, 'why_dropped_by_budget', path)!
	}
}

fn validate_timings(root map[string]json2.Any, path string) ! {
	raw := require_key(root, 'timings_ms', path)!
	timings := expect_object(raw, '${path}: timings_ms')!
	require_number(timings, 'collect', path)!
	require_number(timings, 'match', path)!
	require_number(timings, 'total', path)!
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
