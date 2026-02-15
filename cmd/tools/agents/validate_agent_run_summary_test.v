import os

fn test_validate_agent_run_summary_passes_for_valid_fixture() {
	result := os.execute('./cmd/tools/agents/validate_agent_run_summary.vsh cmd/tools/agents/testdata/valid_agent_run_summary.json')
	assert result.exit_code == 0
	assert result.output.contains('validation passed')
}

fn test_validate_agent_run_summary_fails_for_missing_required_field() {
	result := os.execute('./cmd/tools/agents/validate_agent_run_summary.vsh cmd/tools/agents/testdata/invalid_agent_run_summary_missing_runtime.json')
	assert result.exit_code != 0
	assert result.output.contains('missing required field `runtime_used_sec`')
}
