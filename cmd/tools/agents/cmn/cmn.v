module cmn

import os

pub fn repo_root() string {
	return @VEXEROOT
}

pub fn repo_path(rel string) string {
	return os.join_path(repo_root(), rel)
}

pub fn run_in_repo(cmd string) os.Result {
	root := repo_root()
	return os.execute('cd ${os.quoted_path(root)} && ${cmd}')
}

pub fn run_in_repo_ok(cmd string) !os.Result {
	result := run_in_repo(cmd)
	if result.exit_code != 0 {
		return error('command failed (${result.exit_code}): ${cmd}\n${result.output}')
	}
	return result
}
