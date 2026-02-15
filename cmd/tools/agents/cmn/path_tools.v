module cmn

import os

pub fn normalize_path(path string) string {
	mut normalized := path.trim_space()
	for normalized.starts_with('./') {
		normalized = normalized[2..]
	}
	return normalized
}

pub fn pattern_matches_path(pattern string, path string) bool {
	if pattern.ends_with('/**') {
		prefix := pattern[..pattern.len - 3]
		if path.starts_with(prefix) {
			return true
		}
	}
	if path.match_glob(pattern) {
		return true
	}
	if !pattern.contains('/') {
		return os.file_name(path).match_glob(pattern)
	}
	return false
}

pub fn resolve_cc_tool() string {
	cc := os.getenv_opt('CC') or { 'cc' }
	cc_token := cc.split_any(' \t').filter(it != '')
	return if cc_token.len > 0 { cc_token[0] } else { 'cc' }
}

pub fn collect_changed_paths() ![]string {
	commands := [
		'git diff --name-only',
		'git diff --cached --name-only',
		'git ls-files --others --exclude-standard',
	]
	mut paths := []string{}
	mut seen := map[string]bool{}
	mut command_ok := false
	for command in commands {
		result := os.execute(command)
		if result.exit_code != 0 {
			continue
		}
		command_ok = true
		for line in result.output.split_into_lines() {
			path := normalize_path(line)
			if path == '' || path in seen {
				continue
			}
			seen[path] = true
			paths << path
		}
	}
	if !command_ok {
		return error('git commands failed')
	}
	return paths
}
