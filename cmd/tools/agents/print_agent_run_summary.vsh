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
	print_summary(path) or {
		eprintln('Failed to print agent run summary:')
		eprintln('  - ${err.msg()}')
		exit(1)
	}
}

fn print_help() {
	println('Usage:')
	println('  ./cmd/tools/agents/print_agent_run_summary.vsh [path/to/agent_run_summary.json]')
	println('Default path: /tmp/agent_run_summary.json')
}

fn print_summary(path string) ! {
	content := os.read_file(path) or { return error('failed to read `${path}`: ${err}') }
	root_any := json2.decode[json2.Any](content) or {
		return error('invalid JSON in `${path}`: ${err}')
	}
	root := expect_object(root_any, '${path}: root')!
	tier := require_string(root, 'tier', path)!
	effective_tier := require_string(root, 'effective_tier', path)!
	rebuild := require_bool(root, 'rebuild_vnew', path)!
	warnings := require_string_array(root, 'warnings', path)!
	suggested_commands := require_string_array(root, 'suggested_commands', path)!
	runtime_total := require_number(root, 'runtime_total_sec', path)!
	runtime_used := require_number(root, 'runtime_used_sec', path)!
	owners := extract_unique_owners(root, path)!
	println('Agent run summary:')
	println('  tier=${tier} effective_tier=${effective_tier}')
	println('  owners=' + owners.join(', '))
	println('  suggested_commands=${suggested_commands.len} runtime_total_sec=${runtime_total} runtime_used_sec=${runtime_used}')
	println('  rebuild_vnew=' + if rebuild { 'y' } else { 'n' } + ' warnings=' + warnings.len.str())
	if warnings.len > 0 {
		sample_count := if warnings.len > 3 { 3 } else { warnings.len }
		println('  warning_samples=' + warnings[..sample_count].join(' | '))
	}
}

fn extract_unique_owners(root map[string]json2.Any, path string) ![]string {
	values := require_array(root, 'matched_rules', path)!
	mut seen := map[string]bool{}
	mut owners := []string{}
	for i, raw in values {
		item := expect_object(raw, '${path}: matched_rules[${i}]')!
		owner := require_string(item, 'owner', path)!
		if owner in seen {
			continue
		}
		seen[owner] = true
		owners << owner
	}
	if owners.len == 0 {
		return ['none']
	}
	return owners
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
