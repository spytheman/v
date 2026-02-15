#!/usr/bin/env -S v run

import os

const required_tiers = ['fast', 'targeted', 'broad']
const required_runtime_bands = ['tiny', 'short', 'medium', 'long', 'xlong']

struct ValidateOptions {
mut:
	matrix_path string = 'cmd/tools/agents/agent_test_matrix.yaml'
	matrix_only bool
}

struct RuleSchema {
mut:
	paths          int
	rebuild_vnew   int
	owner          int
	risk           int
	tests          int
	fast_tests     int
	targeted_tests int
	broad_tests    int
}

fn main() {
	args := os.args[1..]
	if '--help' in args || '-h' in args {
		print_help()
		return
	}
	options := parse_options(args) or {
		eprintln(err.msg())
		exit(1)
	}
	mut errors := []string{}
	validate_matrix(options.matrix_path, mut errors)
	validate_agent_policy(mut errors)
	if !options.matrix_only {
		validate_docs(mut errors)
		validate_no_runtime_artifacts(mut errors)
	}
	if errors.len > 0 {
		eprintln('Agent contract validation failed:')
		for issue in errors {
			eprintln('  - ${issue}')
		}
		exit(1)
	}
	println('Agent contract validation passed.')
}

fn parse_options(args []string) !ValidateOptions {
	mut options := ValidateOptions{}
	mut i := 0
	for i < args.len {
		arg := args[i]
		if arg == '--matrix' {
			if i + 1 >= args.len {
				return error('Missing value after --matrix')
			}
			options.matrix_path = args[i + 1]
			i += 2
			continue
		}
		if arg.starts_with('--matrix=') {
			options.matrix_path = arg.all_after('--matrix=')
			i++
			continue
		}
		if arg == '--matrix-only' {
			options.matrix_only = true
			i++
			continue
		}
		return error('Unknown option: ${arg}')
	}
	return options
}

fn print_help() {
	println('Usage:')
	println('  ./cmd/tools/agents/validate_agent_contract.vsh [--matrix path/to/matrix.yaml] [--matrix-only]')
}

fn validate_matrix(path string, mut errors []string) {
	if !os.exists(path) {
		errors << 'Missing ${path}'
		return
	}
	lines := os.read_lines(path) or {
		errors << 'Failed to read ${path}: ${err}'
		return
	}
	content := lines.join('\n')
	if !content.contains('version: 2') {
		errors << '${path}: expected `version: 2`.'
	}
	if !content.contains('default_compiler: ./vnew') {
		errors << '${path}: expected `default_compiler: ./vnew`.'
	}
	if !content.contains('rules:') {
		errors << '${path}: missing `rules`.'
	}
	validate_tier_header(path, lines, mut errors)
	validate_default_budget_header(path, lines, mut errors)
	validate_runtime_band_header(path, lines, mut errors)
	validate_placeholders(path, lines, mut errors)
	validate_rule_schema(path, lines, mut errors)
	validate_command_references(path, lines, mut errors)
	check_rule_order(path, lines, mut errors)
	validate_minimum_top_level_coverage(path, lines, mut errors)
	validate_flaky_registry(mut errors)
}

fn validate_agent_policy(mut errors []string) {
	path := 'cmd/tools/agents/agent_policy_min.yaml'
	if !os.exists(path) {
		errors << 'Missing ${path}'
		return
	}
	lines := os.read_lines(path) or {
		errors << 'Failed to read ${path}: ${err}'
		return
	}
	content := lines.join('\n')
	for required in ['version:', 'required_files:', 'required_tools:', 'rebuild_triggers:',
		'commands:', 'build_vnew:', 'check_vnew:', 'next_commands:'] {
		if !content.contains(required) {
			errors << '${path}: missing `${required}`'
		}
	}
}

fn validate_default_budget_header(path string, lines []string, mut errors []string) {
	mut in_budget := false
	mut found := map[string]bool{}
	for raw in lines {
		line := raw.trim_space()
		if line == 'default_budget_seconds:' {
			in_budget = true
			continue
		}
		if !in_budget {
			continue
		}
		if line == '' || line.starts_with('#') {
			continue
		}
		if line.starts_with('runtime_band_seconds:') || line.starts_with('rules:') {
			break
		}
		if !line.contains(':') {
			continue
		}
		key := line.all_before(':').trim_space()
		found[key] = true
	}
	for tier in required_tiers {
		if tier !in found {
			errors << '${path}: default_budget_seconds missing `${tier}`.'
		}
	}
}

fn validate_runtime_band_header(path string, lines []string, mut errors []string) {
	mut in_bands := false
	mut found := map[string]bool{}
	for raw in lines {
		line := raw.trim_space()
		if line == 'runtime_band_seconds:' {
			in_bands = true
			continue
		}
		if !in_bands {
			continue
		}
		if line == '' || line.starts_with('#') {
			continue
		}
		if line.starts_with('rules:') {
			break
		}
		if !line.contains(':') {
			continue
		}
		key := line.all_before(':').trim_space()
		found[key] = true
	}
	for band in required_runtime_bands {
		if band !in found {
			errors << '${path}: runtime_band_seconds missing `${band}`.'
		}
	}
}

fn validate_tier_header(path string, lines []string, mut errors []string) {
	mut in_available_tiers := false
	mut found := map[string]bool{}
	for raw in lines {
		line := raw.trim_space()
		if line == 'available_tiers:' {
			in_available_tiers = true
			continue
		}
		if !in_available_tiers {
			continue
		}
		if !line.starts_with('- ') {
			break
		}
		found[line.all_after('- ').trim_space()] = true
	}
	for tier in required_tiers {
		if tier !in found {
			errors << '${path}: available_tiers missing `${tier}`.'
		}
	}
}

fn validate_placeholders(path string, lines []string, mut errors []string) {
	mut has_unresolved_placeholder := false
	for raw in lines {
		line := raw.trim_space()
		if !line.contains('<') || !line.contains('>') {
			continue
		}
		if line.contains('<touched-md-file>') {
			continue
		}
		has_unresolved_placeholder = true
		break
	}
	if has_unresolved_placeholder {
		errors << '${path}: contains unresolved placeholders (`<...>`).'
	}
}

fn validate_rule_schema(path string, lines []string, mut errors []string) {
	mut in_rules := false
	mut rule_idx := -1
	mut current := RuleSchema{}
	mut has_rule := false
	for raw in lines {
		line := raw.trim_space()
		if !in_rules {
			if line == 'rules:' {
				in_rules = true
			}
			continue
		}
		if line.starts_with('helper_target:') || line.starts_with('suggest_command:') {
			break
		}
		if line == '- paths:' {
			if has_rule {
				check_one_rule_schema(path, rule_idx, current, mut errors)
			}
			rule_idx++
			current = RuleSchema{}
			current.paths++
			has_rule = true
			continue
		}
		if line.starts_with('rebuild_vnew:') {
			current.rebuild_vnew++
			continue
		}
		if line.starts_with('owner:') {
			current.owner++
			continue
		}
		if line.starts_with('risk:') {
			current.risk++
			continue
		}
		if line == 'tests:' {
			current.tests++
			continue
		}
		if line == 'fast_tests:' {
			current.fast_tests++
			continue
		}
		if line == 'targeted_tests:' {
			current.targeted_tests++
			continue
		}
		if line == 'broad_tests:' {
			current.broad_tests++
			continue
		}
	}
	if has_rule {
		check_one_rule_schema(path, rule_idx, current, mut errors)
	}
	if rule_idx < 0 {
		errors << '${path}: expected at least one rule.'
	}
}

fn check_one_rule_schema(path string, index int, rule RuleSchema, mut errors []string) {
	prefix := '${path}: rule #${index + 1}'
	if rule.paths != 1 {
		errors << '${prefix} must define exactly one `paths:` block.'
	}
	if rule.rebuild_vnew != 1 {
		errors << '${prefix} must define exactly one `rebuild_vnew:` field.'
	}
	if rule.owner != 1 {
		errors << '${prefix} must define exactly one `owner:` field.'
	}
	if rule.risk != 1 {
		errors << '${prefix} must define exactly one `risk:` field.'
	}
	if rule.fast_tests != 1 {
		errors << '${prefix} must define exactly one `fast_tests:` block.'
	}
	if rule.targeted_tests != 1 {
		errors << '${prefix} must define exactly one `targeted_tests:` block.'
	}
	if rule.broad_tests != 1 {
		errors << '${prefix} must define exactly one `broad_tests:` block.'
	}
	if rule.tests > 0 {
		errors << '${prefix} should not use legacy `tests:` in schema v2.'
	}
}

fn validate_command_references(path string, lines []string, mut errors []string) {
	repo_root := os.getwd()
	mut in_rules := false
	mut in_command_block := false
	mut rule_idx := 0
	for raw in lines {
		line := raw.trim_space()
		if !in_rules {
			if line == 'rules:' {
				in_rules = true
			}
			continue
		}
		if line.starts_with('helper_target:') || line.starts_with('suggest_command:') {
			break
		}
		if line == '- paths:' {
			rule_idx++
			in_command_block = false
			continue
		}
		if line in ['fast_tests:', 'targeted_tests:', 'broad_tests:'] {
			in_command_block = true
			continue
		}
		if line == 'paths:' || line.starts_with('rebuild_vnew:') || line.starts_with('owner:')
			|| line == 'tests:' {
			in_command_block = false
			continue
		}
		if line.starts_with('risk:') {
			in_command_block = false
			risk := unquote(line.all_after(':')).trim_space()
			if risk !in ['low', 'medium', 'high'] {
				errors << '${path}: rule #${rule_idx} risk must be one of `low|medium|high`.'
			}
			continue
		}
		if in_command_block && line.starts_with('- ') {
			entry := line.all_after('- ').trim_space()
			if !(entry.starts_with('{') && entry.ends_with('}')) {
				errors << '${path}: rule #${rule_idx} command entry must use inline map `{ command: ..., confidence: ..., runtime_sec: ..., runtime_band: ... }`.'
				continue
			}
			command := parse_inline_field(entry, 'command')
			if command == '' {
				errors << '${path}: rule #${rule_idx} command entry is missing `command`.'
				continue
			}
			confidence := parse_inline_field(entry, 'confidence')
			if confidence == '' {
				errors << '${path}: rule #${rule_idx} command entry is missing `confidence`.'
				continue
			}
			confidence_value := confidence.f64()
			if confidence_value < 0.0 || confidence_value > 1.0 {
				errors << '${path}: rule #${rule_idx} confidence must be between 0 and 1.'
			}
			runtime_sec := parse_inline_field(entry, 'runtime_sec')
			if runtime_sec == '' {
				errors << '${path}: rule #${rule_idx} command entry is missing `runtime_sec`.'
				continue
			}
			runtime_value := runtime_sec.f64()
			if runtime_value < 0 {
				errors << '${path}: rule #${rule_idx} runtime_sec must be >= 0.'
			}
			runtime_band := parse_inline_field(entry, 'runtime_band')
			if runtime_band == '' {
				errors << '${path}: rule #${rule_idx} command entry is missing `runtime_band`.'
				continue
			}
			if runtime_band !in required_runtime_bands {
				errors << '${path}: rule #${rule_idx} runtime_band must be one of `${required_runtime_bands.join('|')}`.'
			}
			validate_command_reference(path, repo_root, rule_idx, command, mut errors)
		}
	}
}

fn validate_command_reference(path string, repo_root string, rule_idx int, command string, mut errors []string) {
	if command.contains('<') && command.contains('>') {
		return
	}
	tokens := command.split_any(' \t').filter(it != '')
	if tokens.len == 0 {
		errors << '${path}: rule #${rule_idx} contains an empty command.'
		return
	}
	first := tokens[0]
	if first == 'make' {
		return
	}
	if first.starts_with('./') || first.starts_with('/') {
		exec_path := if first.starts_with('./') {
			os.join_path(repo_root, first[2..])
		} else {
			first
		}
		if !os.exists(exec_path) {
			errors << '${path}: rule #${rule_idx} command points to missing path `${first}`.'
			return
		}
		if !os.is_executable(exec_path) {
			errors << '${path}: rule #${rule_idx} command target is not executable `${first}`.'
		}
	}
}

fn check_rule_order(path string, lines []string, mut errors []string) {
	mut current_rule := -1
	mut rule_by_pattern := map[string]int{}
	for raw in lines {
		line := raw.trim_space()
		if line == '- paths:' {
			current_rule++
			continue
		}
		if !line.starts_with('- ') {
			continue
		}
		pattern := parse_pattern_line(line)
		if pattern == '' {
			continue
		}
		if pattern !in rule_by_pattern {
			rule_by_pattern[pattern] = current_rule
		}
	}
	order_assert(path, 'cmd/tools/vdoc/**', 'cmd/tools/**', rule_by_pattern, mut errors)
	order_assert(path, 'cmd/tools/vfmt*', 'cmd/tools/**', rule_by_pattern, mut errors)
	order_assert(path, 'vlib/v/parser/**', 'vlib/v/**', rule_by_pattern, mut errors)
	order_assert(path, 'vlib/v/checker/**', 'vlib/v/**', rule_by_pattern, mut errors)
	order_assert(path, 'vlib/v/gen/c/**', 'vlib/v/**', rule_by_pattern, mut errors)
}

fn validate_minimum_top_level_coverage(path string, lines []string, mut errors []string) {
	required := ['.github/workflows/**', 'ci/**', 'examples/**', 'tutorials/**']
	mut present := map[string]bool{}
	for raw in lines {
		line := raw.trim_space()
		if !line.starts_with('- ') {
			continue
		}
		pattern := parse_pattern_line(line)
		if pattern in required {
			present[pattern] = true
		}
	}
	for pattern in required {
		if pattern !in present {
			errors << '${path}: missing required top-level coverage rule `${pattern}`.'
		}
	}
}

fn order_assert(path string, specific string, broad string, rule_by_pattern map[string]int, mut errors []string) {
	if specific !in rule_by_pattern || broad !in rule_by_pattern {
		return
	}
	if rule_by_pattern[specific] > rule_by_pattern[broad] {
		errors << '${path}: `${specific}` must be before `${broad}`.'
	}
}

fn validate_docs(mut errors []string) {
	check_doc('README.md', ['AGENTS.md', 'LLMS.md', './vnew', 'agent-preflight'], mut
		errors)
	check_doc('CONTRIBUTING.md', ['./vnew'], mut errors)
	check_doc('TESTS.md', ['make agent-check VEXE=./vnew'], mut errors)
	check_doc('doc/agent_workflow.md', ['--changed-from', '--json', '--format',
		'cmd/tools/agents/agent_test_matrix.yaml'], mut errors)
	check_doc('AGENTS.md', ['## When to Escalate to Broad', 'two or more high-risk owners',
		'diagnostics/output text changes', 'repl behavior changes', 'fallback rule matched'], mut
		errors)
	check_not_contains('README.md', ['\n$ v self\n'], mut errors)
}

fn validate_flaky_registry(mut errors []string) {
	path := 'cmd/tools/agents/flaky_tests.yaml'
	if !os.exists(path) {
		errors << 'Missing ${path}'
		return
	}
	lines := os.read_lines(path) or {
		errors << 'Failed to read ${path}: ${err}'
		return
	}
	content := lines.join('\n')
	if !content.contains('version:') {
		errors << '${path}: missing `version:`.'
	}
	if !content.contains('entries:') {
		errors << '${path}: missing `entries:`.'
	}
	mut entry_index := 0
	mut has_active_entry := false
	mut current_has_match := false
	mut current_has_reason := false
	mut current_has_issue := false
	for raw in lines {
		line := raw.trim_space()
		if line.starts_with('- match:') {
			if has_active_entry {
				check_flaky_entry_schema(path, entry_index, current_has_match, current_has_reason,
					current_has_issue, mut errors)
			}
			entry_index++
			has_active_entry = true
			current_has_match = true
			current_has_reason = false
			current_has_issue = false
			continue
		}
		if !has_active_entry {
			continue
		}
		if line.starts_with('match:') {
			current_has_match = true
			continue
		}
		if line.starts_with('reason:') {
			current_has_reason = unquote(line.all_after(':')).trim_space() != ''
			continue
		}
		if line.starts_with('issue:') {
			current_has_issue = unquote(line.all_after(':')).trim_space() != ''
			continue
		}
	}
	if has_active_entry {
		check_flaky_entry_schema(path, entry_index, current_has_match, current_has_reason,
			current_has_issue, mut errors)
	}
}

fn validate_no_runtime_artifacts(mut errors []string) {
	pattern := os.join_path('scripts', 'agent', 'tmp.*')
	artifacts := os.glob(pattern) or { []string{} }
	if artifacts.len == 0 {
		return
	}
	errors << 'runtime artifacts found under cmd/tools/agents/: ${artifacts.join(', ')}'
	errors << 'clean with: rm -f cmd/tools/agents/tmp.*'
}

fn check_flaky_entry_schema(path string, index int, has_match bool, has_reason bool, has_issue bool, mut errors []string) {
	prefix := '${path}: entry #${index}'
	if !has_match {
		errors << '${prefix} must define non-empty `match:`.'
	}
	if !has_reason {
		errors << '${prefix} must define non-empty `reason:`.'
	}
	if !has_issue {
		errors << '${prefix} must define non-empty `issue:`.'
	}
}

fn parse_pattern_line(line string) string {
	entry := line.all_after('- ').trim_space()
	if entry.starts_with('{') && entry.ends_with('}') {
		return parse_inline_field(entry, 'command')
	}
	return unquote(entry)
}

fn parse_inline_field(entry string, field string) string {
	mut body := entry.trim_space()
	if body.starts_with('{') && body.ends_with('}') {
		body = body[1..body.len - 1]
	}
	parts := body.split(',')
	for raw_part in parts {
		part := raw_part.trim_space()
		if !part.contains(':') {
			continue
		}
		key := part.all_before(':').trim_space()
		if key != field {
			continue
		}
		return unquote(part.all_after(':'))
	}
	return ''
}

fn check_doc(path string, required []string, mut errors []string) {
	if !os.exists(path) {
		errors << 'Missing ${path}'
		return
	}
	content := os.read_file(path) or {
		errors << 'Failed to read ${path}: ${err}'
		return
	}
	for marker in required {
		if !content.contains(marker) {
			errors << '${path}: missing required marker `${marker}`.'
		}
	}
}

fn check_not_contains(path string, forbidden []string, mut errors []string) {
	content := os.read_file(path) or { return }
	for marker in forbidden {
		if content.contains(marker) {
			errors << '${path}: contains forbidden snippet `${marker.trim_space()}`.'
		}
	}
}

fn unquote(value string) string {
	mut result := value.trim_space()
	if result.len >= 2 && ((result[0] == `"` && result[result.len - 1] == `"`)
		|| (result[0] == `'` && result[result.len - 1] == `'`)) {
		result = result[1..result.len - 1]
	}
	return result
}
