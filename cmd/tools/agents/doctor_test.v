import os

fn test_agent_doctor_help() {
	result := os.execute('./cmd/tools/agents/doctor.vsh --help')
	assert result.exit_code == 0
	assert result.output.contains('Usage:')
	assert result.output.contains('doctor.vsh')
}

fn test_agent_doctor_runs() {
	result := os.execute('./cmd/tools/agents/doctor.vsh')
	assert result.output.contains('Agent doctor report:')
	assert result.output.contains('tool cc')
	assert result.output.contains('vnew freshness')
	assert result.output.contains('Doctor result:')
}
