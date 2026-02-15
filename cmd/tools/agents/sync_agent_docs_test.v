import os
import rand
import cmn

fn test_sync_agent_docs_check_fails_before_sync() {
	tmp := prepare_sync_fixture() or { panic(err) }
	defer {
		os.rmdir_all(tmp) or {}
	}
	script := cmn.repo_path('cmd/tools/agents/sync_agent_docs.vsh')
	result := os.execute('${os.quoted_path(script)} --root ${os.quoted_path(tmp)} --check')
	assert result.exit_code != 0
	assert result.output.contains('Agent docs out of sync with canonical contract')
	assert result.output.contains('LLMS.md')
	assert result.output.contains('doc/agent_task_slices.md')
}

fn test_sync_agent_docs_rewrites_from_template_to_golden() {
	tmp := prepare_sync_fixture() or { panic(err) }
	defer {
		os.rmdir_all(tmp) or {}
	}
	script := cmn.repo_path('cmd/tools/agents/sync_agent_docs.vsh')
	result := os.execute('${os.quoted_path(script)} --root ${os.quoted_path(tmp)}')
	assert result.exit_code == 0
	assert result.output.contains('Synchronized agent docs:')
	got := os.read_file(os.join_path(tmp, 'LLMS.md')) or { panic(err) }
	expected := os.read_file(cmn.repo_path('cmd/tools/agents/testdata/sync_agent_docs_llms.golden')) or {
		panic(err)
	}
	assert got == expected
	slices := os.read_file(os.join_path(tmp, 'doc', 'agent_task_slices.md')) or { panic(err) }
	assert slices.contains('# Agent Task Slices')
	assert slices.contains('- Canonical source: `AGENTS.md`')
	assert slices.contains('## Bugfix Slice')
	assert slices.contains('_Missing from AGENTS.md while generating slices._')
	assert slices.contains('## Docs Slice')
	check := os.execute('${os.quoted_path(script)} --root ${os.quoted_path(tmp)} --check')
	assert check.exit_code == 0
	assert check.output.contains('Agent docs sync check passed.')
}

fn prepare_sync_fixture() !string {
	tmp := os.join_path(os.vtmp_dir(), 'sync_agent_docs_${rand.ulid()}')
	os.mkdir_all(os.join_path(tmp, 'doc'))!
	os.write_file(os.join_path(tmp, 'AGENTS.md'), '# AGENTS\ncanonical\n')!
	llms := os.read_file(cmn.repo_path('cmd/tools/agents/testdata/sync_agent_docs_llms.input'))!
	workflow := os.read_file(cmn.repo_path('cmd/tools/agents/testdata/sync_agent_docs_workflow.input'))!
	playbook := os.read_file(cmn.repo_path('cmd/tools/agents/testdata/sync_agent_docs_playbook.input'))!
	os.write_file(os.join_path(tmp, 'LLMS.md'), llms)!
	os.write_file(os.join_path(tmp, 'doc', 'agent_workflow.md'), workflow)!
	os.write_file(os.join_path(tmp, 'doc', 'agent_bugfix_playbook.md'), playbook)!
	return tmp
}
