import os
import cmn

fn test_validate_agent_run_summary_passes_for_valid_fixture() {
	script := cmn.repo_path('cmd/tools/agents/validate_agent_run_summary.vsh')
	fixture := cmn.repo_path('cmd/tools/agents/testdata/valid_agent_run_summary.json')
	result := cmn.run_in_repo('${os.quoted_path(script)} ${os.quoted_path(fixture)}')
	assert result.exit_code == 0
	assert result.output.contains('validation passed')
}

fn test_validate_agent_run_summary_fails_for_missing_required_field() {
	script := cmn.repo_path('cmd/tools/agents/validate_agent_run_summary.vsh')
	fixture := cmn.repo_path('cmd/tools/agents/testdata/invalid_agent_run_summary_missing_runtime.json')
	result := cmn.run_in_repo('${os.quoted_path(script)} ${os.quoted_path(fixture)}')
	assert result.exit_code != 0
	assert result.output.contains('missing required field `runtime_used_sec`')
}
