import cmn

fn test_validate_agent_contract_script_passes() {
	result := cmn.run_in_repo('./cmd/tools/agents/validate_agent_contract.vsh')
	assert result.exit_code == 0
	assert result.output.contains('Agent contract validation passed.')
}

fn test_validate_matrix_only_passes_for_repo_matrix() {
	result := cmn.run_in_repo('./cmd/tools/agents/validate_agent_contract.vsh --matrix-only --matrix cmd/tools/agents/agent_test_matrix.yaml')
	assert result.exit_code == 0
}

fn test_validate_matrix_only_fails_for_invalid_schema() {
	result := cmn.run_in_repo('./cmd/tools/agents/validate_agent_contract.vsh --matrix-only --matrix cmd/tools/agents/testdata/invalid_schema_missing_broad.yaml')
	assert result.exit_code != 0
	assert result.output.contains('must define exactly one `broad_tests:` block')
}

fn test_validate_matrix_only_fails_for_invalid_order() {
	result := cmn.run_in_repo('./cmd/tools/agents/validate_agent_contract.vsh --matrix-only --matrix cmd/tools/agents/testdata/invalid_order.yaml')
	assert result.exit_code != 0
	assert result.output.contains('must be before')
}

fn test_validate_matrix_only_fails_for_invalid_command_path() {
	result := cmn.run_in_repo('./cmd/tools/agents/validate_agent_contract.vsh --matrix-only --matrix cmd/tools/agents/testdata/invalid_command_path.yaml')
	assert result.exit_code != 0
	assert result.output.contains('missing path')
}
