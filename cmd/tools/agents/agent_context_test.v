import os
import cmn

fn test_agent_context_for_readme() {
	script := cmn.repo_path('cmd/tools/agents/agent_context.vsh')
	result := cmn.run_in_repo('${os.quoted_path(script)} README.md')
	assert result.exit_code == 0
	golden_path := cmn.repo_path('cmd/tools/agents/testdata/agent_context_readme.golden')
	golden := os.read_file(golden_path) or { panic(err) }
	assert result.output.trim_space() == golden.trim_space()
}

fn test_agent_context_no_semantic_impact_flag() {
	script := cmn.repo_path('cmd/tools/agents/agent_context.vsh')
	result := cmn.run_in_repo('${os.quoted_path(script)} --no-semantic-impact vlib/v/checker/checker.v')
	assert result.exit_code == 0
	assert !result.output.contains('semantic impact:')
}
