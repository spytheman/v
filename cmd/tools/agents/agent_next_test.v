import os
import cmn

fn test_agent_next_help() {
	script := cmn.repo_path('cmd/tools/agents/agent_next.vsh')
	result := cmn.run_in_repo('${os.quoted_path(script)} --help')
	assert result.exit_code == 0
	assert result.output.contains('Usage:')
	assert result.output.contains('agent_next.vsh')
}

fn test_agent_next_prints_three_commands_max() {
	script := cmn.repo_path('cmd/tools/agents/agent_next.vsh')
	result := cmn.run_in_repo('${os.quoted_path(script)} vlib/v/parser/parser.v')
	assert result.exit_code == 0
	assert result.output.contains('Next ')
	assert result.output.contains('1. ')
	lines := result.output.split_into_lines().filter(it.starts_with('1. ') || it.starts_with('2. ')
		|| it.starts_with('3. ') || it.starts_with('4. '))
	assert lines.len > 0
	assert lines.len <= 3
	assert !result.output.contains('4. ')
}
