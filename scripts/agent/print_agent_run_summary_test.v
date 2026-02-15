import os

fn test_print_agent_run_summary_passes_for_valid_fixture() {
	result := os.execute('./scripts/agent/print_agent_run_summary.vsh scripts/agent/testdata/valid_agent_run_summary.json')
	assert result.exit_code == 0
	assert result.output.contains('Agent run summary:')
	assert result.output.contains('tier=targeted effective_tier=targeted')
	assert result.output.contains('owners=docs')
	assert result.output.contains('suggested_commands=1')
}

fn test_print_agent_run_summary_fails_for_invalid_fixture() {
	result := os.execute('./scripts/agent/print_agent_run_summary.vsh scripts/agent/testdata/invalid_agent_run_summary_missing_runtime.json')
	assert result.exit_code != 0
	assert result.output.contains('missing required field `runtime_used_sec`')
}
