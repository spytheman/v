import os
import rand
import cmn

fn run_cmd(cmd string) !os.Result {
	result := cmn.run_in_repo(cmd)
	if result.exit_code != 0 {
		return error('command failed (${result.exit_code}): ${cmd}\n${result.output}')
	}
	return result
}

fn run_cmd_in(dir string, cmd string) !os.Result {
	return run_cmd('cd ${os.quoted_path(dir)} && ${cmd}')
}

fn test_parser_path_suggests_parser_tests() {
	result := run_cmd('./cmd/tools/agents/suggest_tests.vsh --tier targeted vlib/v/parser/parser.v') or {
		panic(err)
	}
	assert result.output.contains('Tier: targeted')
	assert result.output.contains('Rebuild ./vnew: y')
	assert result.output.contains('Timings (ms):')
	assert result.output.contains('owner=parser')
	assert result.output.contains('./vnew -silent vlib/v/compiler_errors_test.v')
}

fn test_fast_tier_prefers_fast_commands() {
	result := run_cmd('./cmd/tools/agents/suggest_tests.vsh --tier fast --impact-mode off cmd/tools/vdoc/vdoc.v') or {
		panic(err)
	}
	assert result.output.contains('Tier: fast')
	assert result.output.contains('./vnew -silent cmd/tools/vdoc/vdoc_test.v')
	assert !result.output.contains('vdoc_file_test.v')
}

fn test_broad_tier_adds_broad_commands() {
	result := run_cmd('./cmd/tools/agents/suggest_tests.vsh --tier broad vlib/v/checker/checker.v') or {
		panic(err)
	}
	assert result.output.contains('Tier: broad')
	assert result.output.contains('./vnew -silent vlib/v/compiler_errors_test.v')
	assert result.output.contains('./vnew -silent test vlib/v/')
}

fn test_markdown_paths_expand_placeholder() {
	result := run_cmd('./cmd/tools/agents/suggest_tests.vsh README.md TESTS.md') or { panic(err) }
	assert result.output.contains('./vnew check-md README.md')
	assert result.output.contains('./vnew check-md TESTS.md')
}

fn test_json_output_mode() {
	result := run_cmd('./cmd/tools/agents/suggest_tests.vsh --json README.md') or { panic(err) }
	assert result.output.contains('"tier":"targeted"')
	assert result.output.contains('"changed_paths":["README.md"]')
	assert result.output.contains('"path_matches"')
	assert result.output.contains('"matched_rules"')
	assert result.output.contains('"confidence"')
	assert result.output.contains('"runtime_band"')
	assert result.output.contains('"why_selected"')
	assert result.output.contains('"dropped_by_budget"')
	assert result.output.contains('"escalation_reason"')
	assert result.output.contains('./vnew check-md README.md')
	assert result.output.contains('"timings_ms":')
}

fn test_agent_mode_output() {
	result := run_cmd('./cmd/tools/agents/suggest_tests.vsh --agent-mode README.md') or {
		panic(err)
	}
	assert result.output.contains('rebuild_vnew: n')
	assert result.output.contains('rebuild_reason: none')
	assert result.output.contains('minimal_tests:')
	assert result.output.contains('- ./vnew check-md README.md')
	assert result.output.contains('escalation_reason: none')
}

fn test_sh_output_mode() {
	result := run_cmd('./cmd/tools/agents/suggest_tests.vsh --format sh README.md') or {
		panic(err)
	}
	golden := os.read_file(cmn.repo_path('cmd/tools/agents/testdata/suggest_sh_readme.golden')) or {
		panic(err)
	}
	assert result.output.trim_space() == golden.trim_space()
}

fn test_default_budget_warning_is_suppressed_without_verbose() {
	result := run_cmd('./cmd/tools/agents/suggest_tests.vsh README.md') or { panic(err) }
	assert !result.output.contains('applied default budget')
}

fn test_verbose_mode_shows_default_budget_warning() {
	result := run_cmd('./cmd/tools/agents/suggest_tests.vsh --verbose README.md') or { panic(err) }
	assert result.output.contains('applied default budget')
}

fn test_max_paths_warning() {
	result := run_cmd('./cmd/tools/agents/suggest_tests.vsh --max-paths-warn 1 README.md TESTS.md') or {
		panic(err)
	}
	assert result.output.contains('Warnings:')
	assert result.output.contains('exceeds warning threshold')
}

fn test_budget_seconds_reduces_suggestions() {
	result := run_cmd('./cmd/tools/agents/suggest_tests.vsh --budget-seconds 100 cmd/v/v.v') or {
		panic(err)
	}
	assert result.output.contains('Budget (s): 100.0')
	assert result.output.contains('within budget 100.0s')
	assert result.output.contains('Suggested test commands:')
}

fn test_multiple_high_risk_rules_promote_to_broad() {
	result := run_cmd('./cmd/tools/agents/suggest_tests.vsh --tier targeted vlib/v/parser/parser.v vlib/v/checker/checker.v') or {
		panic(err)
	}
	assert result.output.contains('Effective tier: broad')
	assert result.output.contains('auto-promoted tier to broad')
	assert result.output.contains('./vnew -silent test vlib/v/')
}

fn test_small_change_lane_caps_auto_promotion_to_targeted() {
	result := run_cmd('./cmd/tools/agents/suggest_tests.vsh --small-change-lane --tier targeted vlib/v/parser/parser.v vlib/v/checker/checker.v') or {
		panic(err)
	}
	assert result.output.contains('Tier: targeted')
	assert !result.output.contains('Effective tier: broad')
	assert result.output.contains('small-change lane kept tier targeted')
	assert !result.output.contains('./vnew -silent test vlib/v/')
}

fn test_small_change_lane_allow_broad_keeps_broad_behavior() {
	result := run_cmd('./cmd/tools/agents/suggest_tests.vsh --small-change-lane --allow-broad --tier targeted vlib/v/parser/parser.v vlib/v/checker/checker.v') or {
		panic(err)
	}
	assert result.output.contains('Effective tier: broad')
	assert result.output.contains('./vnew -silent test vlib/v/')
}

fn test_single_direct_high_risk_with_derived_impacts_stays_targeted() {
	result := run_cmd('./cmd/tools/agents/suggest_tests.vsh --tier targeted vlib/v/checker/checker.v') or {
		panic(err)
	}
	assert result.output.contains('Tier: targeted')
	assert !result.output.contains('Effective tier: broad')
	assert result.output.contains('broad escalation not auto-applied')
	assert result.output.contains('derived impact paths')
}

fn test_impact_mode_basic_adds_related_area() {
	result := run_cmd('./cmd/tools/agents/suggest_tests.vsh --tier targeted vlib/v/parser/parser.v') or {
		panic(err)
	}
	assert result.output.contains('impact map (derived):')
	assert result.output.contains('owner=checker')
	assert result.output.contains('./vnew -silent vlib/v/compiler_errors_test.v')
}

fn test_impact_mode_semantic_uses_imports() {
	tmp := cmn.repo_path(os.join_path('cmd/tools/agents/testdata', 'tmp_semantic_${rand.ulid()}.v'))
	defer {
		os.rm(tmp) or {}
	}
	os.write_file(tmp, 'module main\n\nimport v.checker\n') or { panic(err) }
	result := run_cmd('./cmd/tools/agents/suggest_tests.vsh --impact-mode semantic ${os.quoted_path(tmp)}') or {
		panic(err)
	}
	assert result.output.contains('semantic impact (derived):')
	assert result.output.contains('owner=checker')
}

fn test_human_output_hides_derived_paths_by_default() {
	result := run_cmd('./cmd/tools/agents/suggest_tests.vsh --tier targeted vlib/v/parser/parser.v') or {
		panic(err)
	}
	assert result.output.contains('derived paths hidden:')
	assert !result.output.contains('Derived paths:')
}

fn test_show_derived_paths_flag_includes_derived_section() {
	result := run_cmd('./cmd/tools/agents/suggest_tests.vsh --show-derived-paths --tier targeted vlib/v/parser/parser.v') or {
		panic(err)
	}
	assert result.output.contains('Derived paths:')
	assert result.output.contains('[derived]')
}

fn test_changed_from_and_explicit_paths_conflict() {
	result := cmn.run_in_repo('./cmd/tools/agents/suggest_tests.vsh --changed-from HEAD README.md')
	assert result.exit_code != 0
}

fn test_strict_unmatched_succeeds_with_fallback_rule() {
	result := cmn.run_in_repo('./cmd/tools/agents/suggest_tests.vsh --strict-unmatched unknown_path.xyz')
	assert result.exit_code == 0
	assert result.output.contains('owner=fallback')
	assert result.output.contains('./cmd/tools/agents/bootstrap_check.vsh')
}

fn test_require_non_fallback_fails_when_fallback_rule_selected() {
	result := cmn.run_in_repo('./cmd/tools/agents/suggest_tests.vsh --require-non-fallback unknown_path.xyz')
	assert result.exit_code != 0
	assert result.output.contains('owner=fallback')
}

fn test_fail_below_confidence_fails_for_low_confidence_commands() {
	result := cmn.run_in_repo('./cmd/tools/agents/suggest_tests.vsh --fail-below-confidence 0.95 README.md')
	assert result.exit_code != 0
	assert result.output.contains('./vnew check-md README.md')
}

fn test_explain_match_shows_pattern_owner_per_path() {
	result := run_cmd('./cmd/tools/agents/suggest_tests.vsh --explain-match vlib/v/parser/parser.v') or {
		panic(err)
	}
	assert result.output.contains('Path match details:')
	assert result.output.contains('vlib/v/parser/parser.v: owner=parser pattern=vlib/v/parser/**')
}

fn test_focus_owner_limits_to_selected_owner_rules() {
	result := run_cmd('./cmd/tools/agents/suggest_tests.vsh --focus-owner parser --impact-mode off vlib/v/parser/parser.v vlib/v/checker/checker.v') or {
		panic(err)
	}
	assert result.output.contains('owner=parser')
	assert !result.output.contains('owner=checker')
	assert result.output.contains('./vnew -silent vlib/v/compiler_errors_test.v')
}

fn test_exclude_owner_drops_matching_rules() {
	result := run_cmd('./cmd/tools/agents/suggest_tests.vsh --exclude-owner parser --impact-mode off vlib/v/parser/parser.v') or {
		panic(err)
	}
	assert result.output.contains('Changed paths: 1')
	assert !result.output.contains('owner=parser')
	assert result.output.contains('owner=compiler')
	assert result.output.contains('./vnew -silent test vlib/v/')
}

fn test_max_derived_impacts_limits_expansion() {
	result := run_cmd('./cmd/tools/agents/suggest_tests.vsh --max-derived-impacts 1 vlib/v/parser/parser.v vlib/v/checker/checker.v') or {
		panic(err)
	}
	assert result.output.contains('max-derived-impacts=1')
}

fn test_changed_from_uses_controlled_git_history() {
	tmp := os.join_path(os.vtmp_dir(), 'suggest_tests_repo_${rand.ulid()}')
	os.mkdir_all(tmp) or { panic(err) }
	defer {
		os.rmdir_all(tmp) or {}
	}
	run_cmd_in(tmp, 'git init -q') or { panic(err) }
	run_cmd_in(tmp, 'git config user.email "agent@example.test"') or { panic(err) }
	run_cmd_in(tmp, 'git config user.name "agent"') or { panic(err) }
	run_cmd_in(tmp, 'git config commit.gpgsign false') or { panic(err) }
	os.write_file(os.join_path(tmp, 'a.md'), '# a\n') or { panic(err) }
	run_cmd_in(tmp, 'git add a.md && git commit -q -m "init"') or { panic(err) }
	os.write_file(os.join_path(tmp, 'a.md'), '# a\nupdated\n') or { panic(err) }
	run_cmd_in(tmp, 'git add a.md && git commit -q -m "update"') or { panic(err) }
	script := cmn.repo_path('cmd/tools/agents/suggest_tests.vsh')
	result := run_cmd('GIT_DIR=${os.quoted_path(os.join_path(tmp, '.git'))} GIT_WORK_TREE=${os.quoted_path(tmp)} ${os.quoted_path(script)} --changed-from HEAD~1 --json') or {
		panic(err)
	}
	assert result.output.contains('"changed_paths":["a.md"]')
	assert result.output.contains('./vnew check-md a.md')
}
