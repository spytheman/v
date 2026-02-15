import os
import cmn

fn test_print_agent_run_summary_passes_for_valid_fixture() {
	script := cmn.repo_path('cmd/tools/agents/print_agent_run_summary.vsh')
	fixture := cmn.repo_path('cmd/tools/agents/testdata/valid_agent_run_summary.json')
	result := cmn.run_in_repo('${os.quoted_path(script)} ${os.quoted_path(fixture)}')
	assert result.exit_code == 0
	assert result.output.contains('Agent run summary:')
	assert result.output.contains('tier=targeted effective_tier=targeted')
	assert result.output.contains('owners=docs')
	assert result.output.contains('suggested_commands=1')
}

fn test_print_agent_run_summary_fails_for_invalid_fixture() {
	script := cmn.repo_path('cmd/tools/agents/print_agent_run_summary.vsh')
	fixture := cmn.repo_path('cmd/tools/agents/testdata/invalid_agent_run_summary_missing_runtime.json')
	result := cmn.run_in_repo('${os.quoted_path(script)} ${os.quoted_path(fixture)}')
	assert result.exit_code != 0
	assert result.output.contains('missing required field `runtime_used_sec`')
}
