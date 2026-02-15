#!/usr/bin/env -S v run

import os
import time
import cmn

const valid_tiers = ['fast', 'targeted', 'broad']
const valid_formats = ['human', 'json', 'sh', 'agent']
const valid_impact_modes = ['off', 'basic', 'semantic']
const default_max_paths_warn = 200
const default_max_paths_limit = 4000
const flaky_registry_path = 'cmd/tools/agents/flaky_tests.yaml'
const default_runtime_band_seconds = {
	'tiny':   5.0
	'short':  20.0
	'medium': 90.0
	'long':   300.0
	'xlong':  1200.0
}

struct CommandSpec {
	command      string
	confidence   f64
	runtime_sec  f64
	runtime_band string
}

struct Rule {
mut:
	paths          []string
	owner          string = 'unassigned'
	risk           string = 'medium'
	rebuild_vnew   bool
	tests          []CommandSpec
	fast_tests     []CommandSpec
	targeted_tests []CommandSpec
	broad_tests    []CommandSpec
}

struct FlakyEntry {
mut:
	pattern string
	reason  string
	issue   string
}

struct RuleMatchSummary {
	owner         string
	risk          string
	patterns      []string
	matched_paths []string
	rebuild_vnew  bool
}

struct PathMatchDetail {
	path    string
	owner   string
	pattern string
}

struct SuggestedCommand {
mut:
	command          string
	confidence       f64
	confidence_label string
	runtime_sec      f64
	runtime_band     string
	why_selected     string
	flaky            bool
	flaky_reason     string
	flaky_issue      string
}

struct DroppedBudgetCommand {
	command               string
	confidence            f64
	runtime_sec           f64
	why_dropped_by_budget string
}

struct SuggestOptions {
mut:
	tier                  string = 'targeted'
	output_format         string = 'human'
	changed_from          string
	verbose               bool
	show_derived_paths    bool
	strict_unmatched      bool
	require_non_fallback  bool
	explain_match         bool
	paths                 []string
	max_paths_warn        int = default_max_paths_warn
	max_paths_limit       int = default_max_paths_limit
	budget_seconds        f64
	budget_explicit       bool
	impact_mode           string = 'semantic'
	fail_below_confidence f64
	small_change_lane     bool
	allow_broad           bool
	focus_owners          []string
	exclude_owners        []string
	max_derived_impacts   int = 100
}

struct SuggestResult {
	tier               string
	effective_tier     string
	changed_paths      []string
	matched_paths      []string
	unmatched_paths    []string
	path_matches       []PathMatchDetail
	rebuild_vnew       bool
	rebuild_command    string
	matched_rules      []RuleMatchSummary
	suggested          []SuggestedCommand
	dropped_by_budget  []DroppedBudgetCommand
	suggested_commands []string
	warnings           []string
	budget_seconds     f64
	runtime_total_sec  f64
	runtime_used_sec   f64
	escalation_reason  string
	collect_ms         int
	match_ms           int
	total_ms           int
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
	total_sw := time.new_stopwatch()
	collect_sw := time.new_stopwatch()
	raw_paths := collect_changed_paths(options) or {
		eprintln(err.msg())
		exit(1)
	}
	collect_ms := int(collect_sw.elapsed().milliseconds())
	initial_paths, mut warnings := apply_path_guardrails(raw_paths, options)
	mut changed_paths := initial_paths.clone()
	mut derived_count := 0
	if options.impact_mode in ['basic', 'semantic'] {
		remaining := if options.max_derived_impacts - derived_count > 0 {
			options.max_derived_impacts - derived_count
		} else {
			0
		}
		expanded_paths, impact_warnings, added := apply_impact_map(changed_paths, remaining)
		changed_paths = expanded_paths.clone()
		warnings << impact_warnings
		derived_count += added
	}
	if options.impact_mode == 'semantic' {
		remaining := if options.max_derived_impacts - derived_count > 0 {
			options.max_derived_impacts - derived_count
		} else {
			0
		}
		expanded_paths, semantic_warnings, added := apply_import_impact_map(changed_paths,
			remaining)
		changed_paths = expanded_paths.clone()
		warnings << semantic_warnings
		derived_count += added
	}
	if changed_paths.len == 0 {
		empty := SuggestResult{
			tier:           options.tier
			effective_tier: options.tier
			warnings:       warnings
		}
		print_result(empty, options)
		return
	}
	matrix_path := 'cmd/tools/agents/agent_test_matrix.yaml'
	rules := parse_rules(matrix_path) or {
		eprintln('Failed to parse cmd/tools/agents/agent_test_matrix.yaml: ${err}')
		exit(1)
	}
	if rules.len == 0 {
		eprintln('No rules found in cmd/tools/agents/agent_test_matrix.yaml.')
		exit(1)
	}
	flaky_entries := parse_flaky_registry(flaky_registry_path) or {
		warnings << 'failed to parse ${flaky_registry_path}: ${err}'
		[]FlakyEntry{}
	}
	mut selected_rule_indexes := []int{}
	mut selected_rule_seen := map[string]bool{}
	mut direct_rule_indexes := []int{}
	mut direct_rule_seen := map[string]bool{}
	mut rule_matched_paths := map[string][]string{}
	mut matched_path_seen := map[string]bool{}
	mut matched_rule_by_path := map[string]int{}
	mut matched_pattern_by_path := map[string]string{}
	mut unmatched_paths := []string{}
	match_sw := time.new_stopwatch()
	for path in initial_paths {
		for i, rule in rules {
			if !owner_allowed(rule.owner, options.focus_owners, options.exclude_owners) {
				continue
			}
			if first_matching_pattern(rule, path) != '' {
				key := i.str()
				if key !in direct_rule_seen {
					direct_rule_seen[key] = true
					direct_rule_indexes << i
				}
				break
			}
		}
	}
	for path in changed_paths {
		mut matched := false
		for i, rule in rules {
			if !owner_allowed(rule.owner, options.focus_owners, options.exclude_owners) {
				continue
			}
			matching_pattern := first_matching_pattern(rule, path)
			if matching_pattern != '' {
				key := i.str()
				if !selected_rule_seen[key] {
					selected_rule_seen[key] = true
					selected_rule_indexes << i
				}
				mut matched_paths_for_rule := rule_matched_paths[key] or { []string{} }
				if path !in matched_paths_for_rule {
					matched_paths_for_rule << path
					rule_matched_paths[key] = matched_paths_for_rule
				}
				matched_path_seen[path] = true
				matched_rule_by_path[path] = i
				matched_pattern_by_path[path] = matching_pattern
				matched = true
				break
			}
		}
		if !matched {
			unmatched_paths << path
		}
	}
	md_paths := changed_paths.filter(it.ends_with('.md'))
	mut command_details := []SuggestedCommand{}
	mut command_index := map[string]int{}
	mut flaky_warning_seen := map[string]bool{}
	mut needs_rebuild := false
	mut matched_rules := []RuleMatchSummary{}
	mut high_risk_rules := 0
	mut high_risk_direct_rules := 0
	mut fallback_paths := []string{}
	mut fallback_seen := map[string]bool{}
	mut escalation_reason := 'none'
	for index in selected_rule_indexes {
		if rules[index].risk == 'high' {
			high_risk_rules++
		}
	}
	for index in direct_rule_indexes {
		if rules[index].risk == 'high' {
			high_risk_direct_rules++
		}
	}
	mut requested_tier := options.tier
	if options.small_change_lane && !options.allow_broad && options.tier == 'broad' {
		requested_tier = 'targeted'
		warnings << 'small-change lane capped requested tier `broad` to `targeted` (use --allow-broad to opt in)'
	}
	mut effective_tier := requested_tier
	if requested_tier != 'broad' && high_risk_direct_rules >= 2 {
		if options.small_change_lane && !options.allow_broad {
			escalation_reason = 'broad recommended due to ${high_risk_direct_rules} direct high-risk areas; capped to targeted by small-change lane'
			warnings << 'small-change lane kept tier targeted despite ${high_risk_direct_rules} direct high-risk areas (use --allow-broad to opt in)'
		} else {
			effective_tier = 'broad'
			escalation_reason = 'auto-promoted to broad due to ${high_risk_direct_rules} direct high-risk areas'
			warnings << 'auto-promoted tier to broad due to ${high_risk_direct_rules} direct high-risk areas'
		}
	}
	if requested_tier != 'broad' && high_risk_direct_rules < 2 && high_risk_rules >= 2 {
		warnings << 'broad escalation not auto-applied: ${high_risk_direct_rules} direct high-risk area(s); additional high-risk matches are derived impact paths'
	}
	for index in selected_rule_indexes {
		rule := rules[index]
		if rule.rebuild_vnew {
			needs_rebuild = true
		}
		rule_key := index.str()
		if rule.owner == 'fallback' {
			for path in rule_matched_paths[rule_key] or { []string{} } {
				if path in fallback_seen {
					continue
				}
				fallback_seen[path] = true
				fallback_paths << path
			}
		}
		matched_rules << RuleMatchSummary{
			owner:         rule.owner
			risk:          rule.risk
			patterns:      rule.paths.clone()
			matched_paths: rule_matched_paths[rule_key] or { []string{} }
			rebuild_vnew:  rule.rebuild_vnew
		}
		for spec in tests_for_tier(rule, effective_tier) {
			expanded_commands := expand_template_command(spec.command, md_paths)
			for command in expanded_commands {
				if command == '' {
					continue
				}
				mut detail := SuggestedCommand{
					command:          command
					confidence:       spec.confidence
					confidence_label: confidence_label(spec.confidence)
					runtime_sec:      spec.runtime_sec
					runtime_band:     normalized_runtime_band(spec.runtime_band, spec.runtime_sec)
					why_selected:     'selected by matched rule at tier `${effective_tier}`'
				}
				for entry in flaky_entries {
					if !command_matches_pattern(entry.pattern, command) {
						continue
					}
					detail.flaky = true
					detail.flaky_reason = entry.reason
					detail.flaky_issue = entry.issue
					warning_key := command + '|' + entry.reason
					if warning_key !in flaky_warning_seen {
						flaky_warning_seen[warning_key] = true
						warnings << 'known flaky: ${command} (${entry.reason})'
					}
					break
				}
				if command in command_index {
					i := command_index[command]
					if detail.confidence > command_details[i].confidence {
						command_details[i] = detail
					}
					continue
				}
				command_index[command] = command_details.len
				command_details << detail
			}
		}
	}
	mut effective_budget := options.budget_seconds
	if !options.budget_explicit {
		default_budget := parse_default_budget_seconds(matrix_path, effective_tier) or { 0.0 }
		if default_budget > 0 {
			effective_budget = default_budget
			if options.verbose {
				warnings << 'applied default budget ${effective_budget}s for tier `${effective_tier}`'
			}
		}
	}
	mut commands := []string{}
	for detail in command_details {
		commands << detail.command
	}
	total_runtime := sum_runtime(command_details)
	selected_budget, dropped_commands, used_runtime := apply_budget(command_details, effective_budget)
	command_details = selected_budget.clone()
	mut dropped_by_budget := []DroppedBudgetCommand{}
	for dropped in dropped_commands {
		dropped_by_budget << DroppedBudgetCommand{
			command:               dropped.command
			confidence:            dropped.confidence
			runtime_sec:           command_runtime(dropped)
			why_dropped_by_budget: 'excluded to satisfy budget ${effective_budget}s after higher score selections'
		}
	}
	if effective_budget > 0 {
		for i, item in command_details {
			mut selected := item
			selected.why_selected = 'kept by confidence/runtime ranking within budget ${effective_budget}s'
			command_details[i] = selected
		}
	}
	if dropped_commands.len > 0 {
		warnings << 'budget ${effective_budget}s kept ${command_details.len}/${commands.len} suggested command(s)'
	}
	if fallback_paths.len > 0 {
		if escalation_reason == 'none' {
			escalation_reason = 'fallback rule matched ${fallback_paths.len} path(s)'
		}
		warnings << 'fallback rule matched ${fallback_paths.len} path(s): ${fallback_paths.join(', ')}'
	}
	commands = command_details.map(it.command)
	mut matched_paths := []string{}
	for path in changed_paths {
		if matched_path_seen[path] {
			matched_paths << path
		}
	}
	mut path_matches := []PathMatchDetail{}
	if options.explain_match {
		for path in changed_paths {
			if path !in matched_rule_by_path {
				continue
			}
			rule_index := matched_rule_by_path[path]
			path_matches << PathMatchDetail{
				path:    path
				owner:   rules[rule_index].owner
				pattern: matched_pattern_by_path[path] or { '' }
			}
		}
	}
	result := SuggestResult{
		tier:               options.tier
		effective_tier:     effective_tier
		changed_paths:      changed_paths
		matched_paths:      matched_paths
		unmatched_paths:    unmatched_paths
		path_matches:       path_matches
		rebuild_vnew:       needs_rebuild
		rebuild_command:    './v -g -keepc -o ./vnew cmd/v'
		matched_rules:      matched_rules
		suggested:          command_details
		dropped_by_budget:  dropped_by_budget
		suggested_commands: commands
		warnings:           warnings
		budget_seconds:     effective_budget
		runtime_total_sec:  total_runtime
		runtime_used_sec:   used_runtime
		escalation_reason:  escalation_reason
		collect_ms:         collect_ms
		match_ms:           int(match_sw.elapsed().milliseconds())
		total_ms:           int(total_sw.elapsed().milliseconds())
	}
	mut below_confidence := []string{}
	if options.fail_below_confidence > 0 {
		for item in result.suggested {
			if item.confidence < options.fail_below_confidence {
				below_confidence << '${item.command} (${item.confidence.str()})'
			}
		}
	}
	print_result(result, options)
	if options.strict_unmatched && result.unmatched_paths.len > 0 {
		eprintln('strict-unmatched: ${result.unmatched_paths.len} unmatched path(s) found')
		exit(2)
	}
	if options.require_non_fallback && fallback_paths.len > 0 {
		eprintln('require-non-fallback: fallback rule matched path(s): ${fallback_paths.join(', ')}')
		exit(3)
	}
	if below_confidence.len > 0 {
		eprintln('fail-below-confidence: threshold ${options.fail_below_confidence.str()} not met by ${below_confidence.len} command(s): ${below_confidence.join(', ')}')
		exit(4)
	}
}

fn parse_options(args []string) !SuggestOptions {
	mut options := SuggestOptions{}
	mut i := 0
	for i < args.len {
		arg := args[i]
		if arg == '--tier' {
			if i + 1 >= args.len {
				return error('Missing value after --tier')
			}
			options.tier = args[i + 1]
			i += 2
			continue
		}
		if arg.starts_with('--tier=') {
			options.tier = arg.all_after('--tier=')
			i++
			continue
		}
		if arg == '--changed-from' {
			if i + 1 >= args.len {
				return error('Missing value after --changed-from')
			}
			options.changed_from = args[i + 1]
			i += 2
			continue
		}
		if arg.starts_with('--changed-from=') {
			options.changed_from = arg.all_after('--changed-from=')
			i++
			continue
		}
		if arg == '--json' {
			options.output_format = 'json'
			i++
			continue
		}
		if arg == '--verbose' {
			options.verbose = true
			i++
			continue
		}
		if arg == '--show-derived-paths' {
			options.show_derived_paths = true
			i++
			continue
		}
		if arg == '--format' {
			if i + 1 >= args.len {
				return error('Missing value after --format')
			}
			options.output_format = args[i + 1]
			i += 2
			continue
		}
		if arg.starts_with('--format=') {
			options.output_format = arg.all_after('--format=')
			i++
			continue
		}
		if arg == '--strict-unmatched' {
			options.strict_unmatched = true
			i++
			continue
		}
		if arg == '--require-non-fallback' {
			options.require_non_fallback = true
			i++
			continue
		}
		if arg == '--small-change-lane' {
			options.small_change_lane = true
			i++
			continue
		}
		if arg == '--allow-broad' {
			options.allow_broad = true
			i++
			continue
		}
		if arg == '--focus-owner' {
			if i + 1 >= args.len {
				return error('Missing value after --focus-owner')
			}
			options.focus_owners = parse_owner_list(args[i + 1])
			i += 2
			continue
		}
		if arg.starts_with('--focus-owner=') {
			options.focus_owners = parse_owner_list(arg.all_after('--focus-owner='))
			i++
			continue
		}
		if arg == '--exclude-owner' {
			if i + 1 >= args.len {
				return error('Missing value after --exclude-owner')
			}
			options.exclude_owners = parse_owner_list(args[i + 1])
			i += 2
			continue
		}
		if arg.starts_with('--exclude-owner=') {
			options.exclude_owners = parse_owner_list(arg.all_after('--exclude-owner='))
			i++
			continue
		}
		if arg == '--max-derived-impacts' {
			if i + 1 >= args.len {
				return error('Missing value after --max-derived-impacts')
			}
			options.max_derived_impacts = args[i + 1].int()
			i += 2
			continue
		}
		if arg.starts_with('--max-derived-impacts=') {
			options.max_derived_impacts = arg.all_after('--max-derived-impacts=').int()
			i++
			continue
		}
		if arg == '--explain-match' {
			options.explain_match = true
			i++
			continue
		}
		if arg == '--budget-seconds' {
			if i + 1 >= args.len {
				return error('Missing value after --budget-seconds')
			}
			options.budget_seconds = args[i + 1].f64()
			options.budget_explicit = true
			i += 2
			continue
		}
		if arg.starts_with('--budget-seconds=') {
			options.budget_seconds = arg.all_after('--budget-seconds=').f64()
			options.budget_explicit = true
			i++
			continue
		}
		if arg == '--agent-mode' {
			options.output_format = 'agent'
			i++
			continue
		}
		if arg == '--fail-below-confidence' {
			if i + 1 >= args.len {
				return error('Missing value after --fail-below-confidence')
			}
			options.fail_below_confidence = args[i + 1].f64()
			i += 2
			continue
		}
		if arg.starts_with('--fail-below-confidence=') {
			options.fail_below_confidence = arg.all_after('--fail-below-confidence=').f64()
			i++
			continue
		}
		if arg == '--impact-mode' {
			if i + 1 >= args.len {
				return error('Missing value after --impact-mode')
			}
			options.impact_mode = args[i + 1]
			i += 2
			continue
		}
		if arg.starts_with('--impact-mode=') {
			options.impact_mode = arg.all_after('--impact-mode=')
			i++
			continue
		}
		if arg == '--max-paths-warn' {
			if i + 1 >= args.len {
				return error('Missing value after --max-paths-warn')
			}
			options.max_paths_warn = args[i + 1].int()
			i += 2
			continue
		}
		if arg.starts_with('--max-paths-warn=') {
			options.max_paths_warn = arg.all_after('--max-paths-warn=').int()
			i++
			continue
		}
		if arg == '--max-paths-limit' {
			if i + 1 >= args.len {
				return error('Missing value after --max-paths-limit')
			}
			options.max_paths_limit = args[i + 1].int()
			i += 2
			continue
		}
		if arg.starts_with('--max-paths-limit=') {
			options.max_paths_limit = arg.all_after('--max-paths-limit=').int()
			i++
			continue
		}
		options.paths << arg
		i++
	}
	if options.tier !in valid_tiers {
		return error('Invalid tier `${options.tier}`. Valid tiers: ${valid_tiers.join(', ')}')
	}
	if options.output_format !in valid_formats {
		return error('Invalid format `${options.output_format}`. Valid formats: ${valid_formats.join(', ')}')
	}
	if options.changed_from != '' && options.paths.len > 0 {
		return error('Use either explicit paths or `--changed-from`, not both.')
	}
	if options.max_paths_warn < 0 || options.max_paths_limit < 0 {
		return error('`--max-paths-warn` and `--max-paths-limit` must be >= 0.')
	}
	if options.max_derived_impacts < 0 {
		return error('`--max-derived-impacts` must be >= 0.')
	}
	if options.budget_seconds < 0 {
		return error('`--budget-seconds` must be >= 0.')
	}
	if options.fail_below_confidence < 0 || options.fail_below_confidence > 1 {
		return error('`--fail-below-confidence` must be in [0, 1].')
	}
	if options.impact_mode !in valid_impact_modes {
		return error('Invalid impact mode `${options.impact_mode}`. Valid impact modes: ${valid_impact_modes.join(', ')}')
	}
	return options
}

fn print_help() {
	println('Usage:')
	println('  ./cmd/tools/agents/suggest_tests.vsh [--tier fast|targeted|broad] [--json]')
	println('  ./cmd/tools/agents/suggest_tests.vsh [--format human|json|sh|agent]')
	println('  ./cmd/tools/agents/suggest_tests.vsh --agent-mode [--tier ...]')
	println('  ./cmd/tools/agents/suggest_tests.vsh --changed-from <rev> [--tier ...] [--format ...]')
	println('  ./cmd/tools/agents/suggest_tests.vsh [changed_file ...]')
	println('')
	println('Guardrails:')
	println('  --max-paths-warn <n>    warn if changed path count > n (default: ${default_max_paths_warn})')
	println('  --max-paths-limit <n>   truncate path set to n (default: ${default_max_paths_limit}, 0 disables)')
	println('  --budget-seconds <n>    keep highest-value commands within runtime budget')
	println('  --verbose               include non-critical planning warnings')
	println('  --show-derived-paths    display synthetic impact paths in human output')
	println('  --fail-below-confidence <n>  fail when selected command confidence is below n')
	println('  --impact-mode <mode>    impact expansion mode: off|basic|semantic (default: semantic)')
	println('  --strict-unmatched      exit non-zero when unmatched paths are present')
	println('  --require-non-fallback  exit non-zero when fallback rule is selected')
	println('  --small-change-lane     cap to targeted tier unless --allow-broad is provided')
	println('  --allow-broad           allow broad tier when using --small-change-lane')
	println('  --focus-owner <a,b>     include only matched rules owned by listed owner(s)')
	println('  --exclude-owner <a,b>   exclude matched rules owned by listed owner(s)')
	println('  --max-derived-impacts <n>  cap synthetic impact expansions (default: 100)')
	println('  --explain-match         show matching owner/pattern per changed path')
	println('')
	println('Without paths, changed files are read from:')
	println('  1. git diff --name-only')
	println('  2. git diff --cached --name-only')
	println('  3. git ls-files --others --exclude-standard')
	println('')
	println('Rules source: cmd/tools/agents/agent_test_matrix.yaml')
}

fn print_result(result SuggestResult, options SuggestOptions) {
	match options.output_format {
		'json' {
			println(to_json(result))
		}
		'sh' {
			print_sh_result(result)
		}
		'agent' {
			print_agent_result(result)
		}
		else {
			print_human_result(result, options.show_derived_paths)
		}
	}
}

fn print_human_result(result SuggestResult, show_derived_paths bool) {
	mut direct_changed_paths := []string{}
	mut derived_changed_paths := []string{}
	for path in result.changed_paths {
		if is_derived_impact_path(path) {
			derived_changed_paths << path
		} else {
			direct_changed_paths << path
		}
	}
	println('Tier: ${result.tier}')
	if result.effective_tier != '' && result.effective_tier != result.tier {
		println('Effective tier: ${result.effective_tier}')
	}
	println('Changed paths: ${direct_changed_paths.len}')
	for path in direct_changed_paths {
		marker := if path in result.matched_paths { '+' } else { '-' }
		println('  ${marker} ${path}')
	}
	if derived_changed_paths.len > 0 {
		if show_derived_paths {
			println('\nDerived paths:')
			for path in derived_changed_paths {
				marker := if path in result.matched_paths { '+' } else { '-' }
				println('  ${marker} ${path} [derived]')
			}
		} else {
			println('  (derived paths hidden: ${derived_changed_paths.len}; use --show-derived-paths to display)')
		}
	}
	mut unmatched_paths := result.unmatched_paths.clone()
	if !show_derived_paths {
		unmatched_paths = unmatched_paths.filter(!is_derived_impact_path(it))
	}
	if unmatched_paths.len > 0 {
		println('\nUnmatched paths:')
		for path in unmatched_paths {
			println('  - ${path}')
		}
	}
	if result.matched_rules.len > 0 {
		println('\nMatched rules:')
		for rule in result.matched_rules {
			mut matched_paths := rule.matched_paths.clone()
			if !show_derived_paths {
				matched_paths = matched_paths.filter(!is_derived_impact_path(it))
			}
			matched_display := if matched_paths.len > 0 {
				matched_paths.join(', ')
			} else if rule.matched_paths.len > 0 {
				'[derived-only hidden]'
			} else {
				''
			}
			println('  - owner=${rule.owner} risk=${rule.risk} patterns=${rule.patterns.join(', ')} matched=${matched_display}')
		}
	}
	if result.path_matches.len > 0 {
		println('\nPath match details:')
		for item in result.path_matches {
			println('  - ${item.path}: owner=${item.owner} pattern=${item.pattern}')
		}
	}
	if result.warnings.len > 0 {
		println('\nWarnings:')
		for warning in result.warnings {
			println('  - ${warning}')
		}
	}
	println('\nTimings (ms): collect=${result.collect_ms}, match=${result.match_ms}, total=${result.total_ms}')
	println('\nRebuild ./vnew: ${if result.rebuild_vnew { `y` } else { `n` }}')
	if result.rebuild_vnew {
		println('  ${result.rebuild_command}')
	}
	if result.suggested.len == 0 {
		println('\nNo test commands suggested.')
		return
	}
	if result.budget_seconds > 0 {
		println('Budget (s): ${result.budget_seconds} estimated_total=${result.runtime_total_sec} selected_total=${result.runtime_used_sec}')
	}
	println('\nSuggested test commands:')
	for item in result.suggested {
		mut suffix := ''
		if item.flaky {
			suffix = ' (known flaky: ${item.flaky_reason})'
		}
		println('  [${item.confidence.str()} ${item.confidence_label} ~${item.runtime_sec}s] ${item.command}${suffix}')
		println('    why_selected: ${item.why_selected}')
	}
	if result.dropped_by_budget.len > 0 {
		println('\nDropped by budget:')
		for dropped in result.dropped_by_budget {
			println('  - ${dropped.command}')
			println('    why_dropped_by_budget: ${dropped.why_dropped_by_budget}')
		}
	}
}

fn print_sh_result(result SuggestResult) {
	println('#!/usr/bin/env bash')
	println('set -euo pipefail')
	println('# tier: ${result.tier}')
	println('# changed_paths: ${result.changed_paths.len}')
	for warning in result.warnings {
		println('# warning: ${warning}')
	}
	if result.rebuild_vnew {
		println(result.rebuild_command)
	}
	for command in result.suggested_commands {
		println(command)
	}
}

fn print_agent_result(result SuggestResult) {
	println('rebuild_vnew: ${if result.rebuild_vnew { `y` } else { `n` }}')
	println('rebuild_reason: ${if result.rebuild_vnew {
		'matched rebuild-trigger owner(s): ' + rebuild_owners(result.matched_rules)
	} else {
		'none'
	}}')
	println('minimal_tests:')
	for command in result.suggested_commands {
		println('- ${command}')
	}
	println('escalation_reason: ${result.escalation_reason}')
}

fn collect_changed_paths(options SuggestOptions) ![]string {
	mut paths := []string{}
	if options.paths.len > 0 {
		for raw_path in options.paths {
			path := cmn.normalize_path(raw_path)
			if path != '' && path !in paths {
				paths << path
			}
		}
		return paths
	}
	if options.changed_from == '' {
		return cmn.collect_changed_paths()
	}
	result := os.execute(changed_from_command(options.changed_from))
	if result.exit_code == 0 {
		for line in result.output.split_into_lines() {
			path := cmn.normalize_path(line)
			if path != '' && path !in paths {
				paths << path
			}
		}
	}
	default_paths := cmn.collect_changed_paths() or { []string{} }
	for path in default_paths {
		if path !in paths {
			paths << path
		}
	}
	return paths
}

fn changed_from_command(rev string) string {
	if rev.contains('..') {
		return 'git diff --name-only ${rev}'
	}
	return 'git diff --name-only ${rev}...HEAD'
}

fn apply_path_guardrails(paths []string, options SuggestOptions) ([]string, []string) {
	mut warnings := []string{}
	mut filtered := paths.clone()
	if options.max_paths_warn > 0 && filtered.len > options.max_paths_warn {
		warnings << 'changed path count (${filtered.len}) exceeds warning threshold (${options.max_paths_warn})'
	}
	if options.max_paths_limit > 0 && filtered.len > options.max_paths_limit {
		warnings << 'changed path count (${filtered.len}) exceeds limit (${options.max_paths_limit}); truncating'
		filtered = filtered[..options.max_paths_limit].clone()
	}
	return filtered, warnings
}

fn parse_rules(path string) ![]Rule {
	lines := os.read_lines(path)!
	mut rules := []Rule{}
	mut in_rules := false
	mut active_rule := Rule{}
	mut has_active_rule := false
	mut section := ''
	for line_raw in lines {
		line := line_raw.trim_space()
		if line == '' || line.starts_with('#') {
			continue
		}
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
			if has_active_rule {
				rules << active_rule
			}
			active_rule = Rule{}
			has_active_rule = true
			section = 'paths'
			continue
		}
		if line.starts_with('owner:') {
			active_rule.owner = unquote(line.all_after(':'))
			section = ''
			continue
		}
		if line.starts_with('risk:') {
			active_rule.risk = unquote(line.all_after(':'))
			section = ''
			continue
		}
		if line.starts_with('rebuild_vnew:') {
			active_rule.rebuild_vnew = line.all_after(':').trim_space() == 'true'
			section = ''
			continue
		}
		if line == 'tests:' {
			section = 'tests'
			continue
		}
		if line == 'fast_tests:' {
			section = 'fast_tests'
			continue
		}
		if line == 'targeted_tests:' {
			section = 'targeted_tests'
			continue
		}
		if line == 'broad_tests:' {
			section = 'broad_tests'
			continue
		}
		if !line.starts_with('- ') {
			continue
		}
		value := line.all_after('- ').trim_space()
		if section == 'paths' {
			active_rule.paths << parse_path_item(value)
			continue
		}
		if section in ['tests', 'fast_tests', 'targeted_tests', 'broad_tests'] {
			spec := parse_command_spec(value, default_confidence_for_section(section)) or {
				return error('invalid command entry `${value}`: ${err}')
			}
			if section == 'tests' {
				active_rule.tests << spec
			} else if section == 'fast_tests' {
				active_rule.fast_tests << spec
			} else if section == 'targeted_tests' {
				active_rule.targeted_tests << spec
			} else {
				active_rule.broad_tests << spec
			}
		}
	}
	if has_active_rule {
		rules << active_rule
	}
	return rules
}

fn parse_path_item(value string) string {
	trimmed := value.trim_space()
	if trimmed.starts_with('{') && trimmed.ends_with('}') {
		fields := parse_inline_fields(trimmed)
		if 'command' in fields {
			return fields['command']
		}
	}
	return unquote(value)
}

fn parse_command_spec(value string, default_confidence f64) !CommandSpec {
	trimmed := value.trim_space()
	if !(trimmed.starts_with('{') && trimmed.ends_with('}')) {
		return CommandSpec{
			command:      unquote(trimmed)
			confidence:   default_confidence
			runtime_sec:  0.0
			runtime_band: 'medium'
		}
	}
	fields := parse_inline_fields(trimmed)
	if 'command' !in fields {
		return error('missing `command` field')
	}
	mut confidence := default_confidence
	mut runtime_sec := 0.0
	mut runtime_band := ''
	if 'confidence' in fields {
		confidence = fields['confidence'].f64()
	}
	if 'runtime_sec' in fields {
		runtime_sec = fields['runtime_sec'].f64()
	}
	if 'runtime_band' in fields {
		runtime_band = fields['runtime_band']
	}
	if confidence < 0.0 || confidence > 1.0 {
		return error('confidence must be between 0 and 1')
	}
	if runtime_sec < 0.0 {
		return error('runtime_sec must be >= 0')
	}
	return CommandSpec{
		command:      fields['command']
		confidence:   confidence
		runtime_sec:  runtime_sec
		runtime_band: normalized_runtime_band(runtime_band, runtime_sec)
	}
}

fn normalized_runtime_band(runtime_band string, runtime_sec f64) string {
	if runtime_band in default_runtime_band_seconds {
		return runtime_band
	}
	if runtime_sec <= 5 {
		return 'tiny'
	}
	if runtime_sec <= 30 {
		return 'short'
	}
	if runtime_sec <= 120 {
		return 'medium'
	}
	if runtime_sec <= 600 {
		return 'long'
	}
	return 'xlong'
}

fn parse_inline_fields(value string) map[string]string {
	mut fields := map[string]string{}
	mut body := value.trim_space()
	if body.starts_with('{') && body.ends_with('}') {
		body = body[1..body.len - 1]
	}
	for part in split_inline_map_parts(body) {
		if !part.contains(':') {
			continue
		}
		key := part.all_before(':').trim_space()
		val := unquote(part.all_after(':'))
		fields[key] = val
	}
	return fields
}

fn split_inline_map_parts(value string) []string {
	mut parts := []string{}
	mut current := ''
	mut in_quote := false
	mut quote_char := ` `
	for ch in value {
		if in_quote {
			current += ch.ascii_str()
			if ch == quote_char {
				in_quote = false
			}
			continue
		}
		if ch == `"` || ch == `'` {
			in_quote = true
			quote_char = ch
			current += ch.ascii_str()
			continue
		}
		if ch == `,` {
			part := current.trim_space()
			if part != '' {
				parts << part
			}
			current = ''
			continue
		}
		current += ch.ascii_str()
	}
	part := current.trim_space()
	if part != '' {
		parts << part
	}
	return parts
}

fn default_confidence_for_section(section string) f64 {
	if section == 'fast_tests' {
		return 0.90
	}
	if section == 'broad_tests' {
		return 0.60
	}
	return 0.75
}

fn tests_for_tier(rule Rule, tier string) []CommandSpec {
	legacy := rule.tests.clone()
	targeted := if rule.targeted_tests.len > 0 { rule.targeted_tests.clone() } else { legacy }
	if tier == 'targeted' {
		return targeted
	}
	if tier == 'fast' {
		if rule.fast_tests.len > 0 {
			return rule.fast_tests.clone()
		}
		if targeted.len > 0 {
			return [targeted[0]]
		}
		return []CommandSpec{}
	}
	mut broad := targeted.clone()
	mut seen := map[string]bool{}
	for item in broad {
		seen[item.command] = true
	}
	if rule.broad_tests.len > 0 {
		for item in rule.broad_tests {
			if item.command in seen {
				continue
			}
			seen[item.command] = true
			broad << item
		}
	}
	return broad
}

fn expand_template_command(command string, md_paths []string) []string {
	if !command.contains('<touched-md-file>') {
		return [command]
	}
	mut expanded := []string{}
	for md_path in md_paths {
		expanded << command.replace('<touched-md-file>', md_path)
	}
	return expanded
}

fn apply_impact_map(paths []string, limit int) ([]string, []string, int) {
	// Basic ownership map for cross-module regressions that often co-occur.
	impact_map := {
		'vlib/v/parser/**':  ['vlib/v/checker/__impact__.v']
		'vlib/v/checker/**': ['vlib/v/parser/__impact__.v']
		'vlib/v/gen/c/**':   ['vlib/v/slow_tests/inout/__impact__.vv']
		'cmd/tools/vfmt*':   ['vlib/v/fmt/__impact__.v']
		'cmd/tools/vdoc/**': ['vlib/v/fmt/__impact__.v']
	}
	mut expanded := paths.clone()
	mut warnings := []string{}
	mut added := 0
	for path in paths {
		for pattern, related_paths in impact_map {
			if !cmn.pattern_matches_path(pattern, path) {
				continue
			}
			for related in related_paths {
				if related in expanded {
					continue
				}
				if added >= limit {
					warnings << 'impact map expansion reached max-derived-impacts=${limit}; skipping further derived paths'
					return expanded, warnings, added
				}
				expanded << related
				warnings << 'impact map (derived): ${path} -> ${related}'
				added++
			}
		}
	}
	return expanded, warnings, added
}

fn apply_import_impact_map(paths []string, limit int) ([]string, []string, int) {
	module_impacts := {
		'v.parser':   'vlib/v/parser/__impact__.v'
		'v.checker':  'vlib/v/checker/__impact__.v'
		'v.gen.c':    'vlib/v/gen/c/__impact__.v'
		'v.fmt':      'vlib/v/fmt/__impact__.v'
		'v.comptime': 'vlib/v/comptime/__impact__.v'
		'builtin':    'vlib/builtin/__impact__.v'
		'strings':    'vlib/strings/__impact__.v'
		'os':         'vlib/os/__impact__.v'
		'strconv':    'vlib/strconv/__impact__.v'
		'time':       'vlib/time/__impact__.v'
	}
	mut expanded := paths.clone()
	mut warnings := []string{}
	mut added := 0
	for path in paths {
		if !(path.ends_with('.v') || path.ends_with('.vsh') || path.ends_with('.vv')) {
			continue
		}
		if !os.exists(path) {
			continue
		}
		lines := os.read_lines(path) or { continue }
		for line in lines {
			trimmed := line.trim_space()
			if !trimmed.starts_with('import ') {
				continue
			}
			imported_mod := trimmed.all_after('import ').all_before(' {').trim_space()
			if imported_mod == '' {
				continue
			}
			for prefix, hint_path in module_impacts {
				if !(imported_mod == prefix || imported_mod.starts_with(prefix + '.')) {
					continue
				}
				if hint_path in expanded {
					break
				}
				if added >= limit {
					warnings << 'semantic impact expansion reached max-derived-impacts=${limit}; skipping further derived paths'
					return expanded, warnings, added
				}
				expanded << hint_path
				warnings << 'semantic impact (derived): ${path} imports ${imported_mod} -> ${hint_path}'
				added++
				break
			}
		}
	}
	return expanded, warnings, added
}

fn sum_runtime(commands []SuggestedCommand) f64 {
	mut total := 0.0
	for command in commands {
		total += command_runtime(command)
	}
	return total
}

fn command_runtime(command SuggestedCommand) f64 {
	if command.runtime_sec > 0 {
		return command.runtime_sec
	}
	if command.runtime_band in default_runtime_band_seconds {
		return default_runtime_band_seconds[command.runtime_band]
	}
	return 60.0
}

fn apply_budget(commands []SuggestedCommand, budget_seconds f64) ([]SuggestedCommand, []SuggestedCommand, f64) {
	if budget_seconds <= 0 {
		return commands.clone(), []SuggestedCommand{}, sum_runtime(commands)
	}
	mut remaining := commands.clone()
	mut selected := []SuggestedCommand{}
	mut used := 0.0
	for remaining.len > 0 {
		best := pick_best_index(remaining)
		candidate := remaining[best]
		remaining.delete(best)
		candidate_runtime := command_runtime(candidate)
		if used + candidate_runtime <= budget_seconds || selected.len == 0 {
			selected << candidate
			used += candidate_runtime
		}
	}
	mut selected_map := map[string]bool{}
	for item in selected {
		selected_map[item.command] = true
	}
	mut dropped := []SuggestedCommand{}
	for item in commands {
		if item.command in selected_map {
			continue
		}
		dropped << item
	}
	return selected, dropped, used
}

fn pick_best_index(commands []SuggestedCommand) int {
	mut best_idx := 0
	mut best_score := -1.0
	for i, item in commands {
		runtime := command_runtime(item)
		score := item.confidence / runtime
		best_runtime := command_runtime(commands[best_idx])
		if score > best_score {
			best_score = score
			best_idx = i
			continue
		}
		if score == best_score && item.confidence > commands[best_idx].confidence {
			best_idx = i
			continue
		}
		if score == best_score && item.confidence == commands[best_idx].confidence
			&& runtime < best_runtime {
			best_idx = i
		}
	}
	return best_idx
}

fn parse_flaky_registry(path string) ![]FlakyEntry {
	if !os.exists(path) {
		return []FlakyEntry{}
	}
	lines := os.read_lines(path)!
	mut in_entries := false
	mut entries := []FlakyEntry{}
	mut active := FlakyEntry{}
	mut has_active := false
	for raw in lines {
		line := raw.trim_space()
		if line == '' || line.starts_with('#') {
			continue
		}
		if line == 'entries:' {
			in_entries = true
			continue
		}
		if !in_entries {
			continue
		}
		if line.starts_with('- match:') {
			if has_active {
				entries << active
			}
			active = FlakyEntry{}
			has_active = true
			active.pattern = unquote(line.all_after(':'))
			continue
		}
		if !has_active {
			continue
		}
		if line.starts_with('match:') {
			active.pattern = unquote(line.all_after(':'))
			continue
		}
		if line.starts_with('reason:') {
			active.reason = unquote(line.all_after(':'))
			continue
		}
		if line.starts_with('issue:') {
			active.issue = unquote(line.all_after(':'))
			continue
		}
	}
	if has_active {
		entries << active
	}
	return entries.filter(it.pattern != '')
}

fn confidence_label(confidence f64) string {
	if confidence >= 0.85 {
		return 'high'
	}
	if confidence >= 0.70 {
		return 'medium'
	}
	return 'low'
}

fn command_matches_pattern(pattern string, command string) bool {
	if pattern == '' {
		return false
	}
	if pattern.contains('*') || pattern.contains('?') {
		return command.match_glob(pattern)
	}
	return command == pattern
}

fn rule_matches_path(rule Rule, path string) bool {
	return first_matching_pattern(rule, path) != ''
}

fn first_matching_pattern(rule Rule, path string) string {
	for pattern in rule.paths {
		if cmn.pattern_matches_path(pattern, path) {
			return pattern
		}
	}
	return ''
}

fn is_derived_impact_path(path string) bool {
	return path.contains('/__impact__.')
}

fn unquote(value string) string {
	mut result := value.trim_space()
	if result.len >= 2 && ((result[0] == `"` && result[result.len - 1] == `"`)
		|| (result[0] == `'` && result[result.len - 1] == `'`)) {
		result = result[1..result.len - 1]
	}
	return result
}

fn parse_default_budget_seconds(path string, tier string) !f64 {
	lines := os.read_lines(path)!
	mut in_budget := false
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
		if line.starts_with('rules:') {
			break
		}
		if !line.contains(':') {
			continue
		}
		key := line.all_before(':').trim_space()
		value := line.all_after(':').trim_space()
		if key == tier {
			return value.f64()
		}
	}
	return error('default budget not set for tier `${tier}`')
}

fn parse_owner_list(raw string) []string {
	return raw.split(',')
		.map(it.trim_space())
		.filter(it != '')
}

fn owner_allowed(owner string, focus []string, excluded []string) bool {
	if owner in excluded {
		return false
	}
	if focus.len == 0 {
		return true
	}
	return owner in focus
}

fn rebuild_owners(rules []RuleMatchSummary) string {
	mut owners := []string{}
	for rule in rules {
		if !rule.rebuild_vnew {
			continue
		}
		if rule.owner in owners {
			continue
		}
		owners << rule.owner
	}
	if owners.len == 0 {
		return 'none'
	}
	return owners.join(', ')
}

fn to_json(result SuggestResult) string {
	mut fields := []string{}
	fields << '"tier":"' + json_escape(result.tier) + '"'
	fields << '"changed_paths":' + json_array(result.changed_paths)
	fields << '"effective_tier":"' + json_escape(result.effective_tier) + '"'
	fields << '"matched_paths":' + json_array(result.matched_paths)
	fields << '"unmatched_paths":' + json_array(result.unmatched_paths)
	fields << '"path_matches":' + json_path_matches(result.path_matches)
	fields << '"rebuild_vnew":' + result.rebuild_vnew.str()
	fields << '"rebuild_command":"' + json_escape(result.rebuild_command) + '"'
	fields << '"matched_rules":' + json_matched_rules(result.matched_rules)
	fields << '"suggested":' + json_suggested_commands(result.suggested)
	fields << '"dropped_by_budget":' + json_dropped_by_budget(result.dropped_by_budget)
	fields << '"suggested_commands":' + json_array(result.suggested_commands)
	fields << '"warnings":' + json_array(result.warnings)
	fields << '"budget_seconds":' + result.budget_seconds.str()
	fields << '"runtime_total_sec":' + result.runtime_total_sec.str()
	fields << '"runtime_used_sec":' + result.runtime_used_sec.str()
	fields << '"escalation_reason":"' + json_escape(result.escalation_reason) + '"'
	fields << '"timings_ms":{"collect":' + result.collect_ms.str() + ',"match":' +
		result.match_ms.str() + ',"total":' + result.total_ms.str() + '}'
	return '{' + fields.join(',') + '}'
}

fn json_matched_rules(rules []RuleMatchSummary) string {
	mut items := []string{}
	for rule in rules {
		items << '{"owner":"' + json_escape(rule.owner) + '","patterns":' +
			json_array(rule.patterns) + ',"matched_paths":' + json_array(rule.matched_paths) +
			',"risk":"' + json_escape(rule.risk) + '","rebuild_vnew":' + rule.rebuild_vnew.str() +
			'}'
	}
	return '[' + items.join(',') + ']'
}

fn json_path_matches(path_matches []PathMatchDetail) string {
	mut items := []string{}
	for item in path_matches {
		items << '{"path":"' + json_escape(item.path) + '","owner":"' + json_escape(item.owner) +
			'","pattern":"' + json_escape(item.pattern) + '"}'
	}
	return '[' + items.join(',') + ']'
}

fn json_suggested_commands(commands []SuggestedCommand) string {
	mut items := []string{}
	for item in commands {
		items << '{"command":"' + json_escape(item.command) + '","confidence":' +
			item.confidence.str() + ',"confidence_label":"' + json_escape(item.confidence_label) +
			'","runtime_sec":' + item.runtime_sec.str() + ',"runtime_band":"' +
			json_escape(item.runtime_band) + '","why_selected":"' + json_escape(item.why_selected) +
			'","flaky":' + item.flaky.str() + ',"flaky_reason":"' + json_escape(item.flaky_reason) +
			'","flaky_issue":"' + json_escape(item.flaky_issue) + '"}'
	}
	return '[' + items.join(',') + ']'
}

fn json_dropped_by_budget(commands []DroppedBudgetCommand) string {
	mut items := []string{}
	for item in commands {
		items << '{"command":"' + json_escape(item.command) + '","confidence":' +
			item.confidence.str() + ',"runtime_sec":' + item.runtime_sec.str() +
			',"why_dropped_by_budget":"' + json_escape(item.why_dropped_by_budget) + '"}'
	}
	return '[' + items.join(',') + ']'
}

fn json_array(values []string) string {
	mut items := []string{}
	for value in values {
		items << '"' + json_escape(value) + '"'
	}
	return '[' + items.join(',') + ']'
}

fn json_escape(s string) string {
	mut out := s.replace('\\', '\\\\')
	out = out.replace('"', '\\"')
	out = out.replace('\n', '\\n')
	out = out.replace('\r', '\\r')
	out = out.replace('\t', '\\t')
	return out
}
