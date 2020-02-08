module vgit

import os
import flag
import filepath
import scripting

const (
	remote_v_repo_url = 'https://github.com/vlang/v'
	remote_vc_repo_url = 'https://github.com/vlang/vc'
)

pub fn check_v_commit_timestamp_before_self_rebuilding(v_timestamp int) {
	if v_timestamp >= 1561805697 {
		return
	}
	eprintln('##################################################################')
	eprintln('# WARNING: v self rebuilding, before 5b7a1e8 (2019-06-29 12:21)  #')
	eprintln('#          required the v executable to be built *inside*        #')
	eprintln('#          the toplevel compiler/ folder.                        #')
	eprintln('#                                                                #')
	eprintln('#          That is not supported by this tool.                   #')
	eprintln('#          You will have to build it manually there.             #')
	eprintln('##################################################################')
}

pub fn validate_commit_exists(commit string) {
	if commit.len == 0 {
		return
	}
	cmd := "git cat-file -t \'$commit\' "
	if !scripting.exit_0_status(cmd) {
		eprintln('Commit: "$commit" does not exist in the current repository.')
		exit(3)
	}
}

pub fn line_to_timestamp_and_commit(line string) (int,string) {
	parts := line.split(' ')
	return parts[0].int(),parts[1]
}

pub fn normalized_workpath_for_commit(workdir string, commit string) string {
	nc := 'v_at_' + commit.replace('^', '_').replace('-', '_').replace('/', '_')
	return os.realpath(workdir + os.path_separator + nc)
}

pub fn prepare_vc_source(vcdir string, cdir string, commit string) (string,string) {
	scripting.chdir(cdir)
	// Building a historic v with the latest vc is not always possible ...
	// It is more likely, that the vc *at the time of the v commit*,
	// or slightly before that time will be able to build the historic v:
	vline := scripting.run('git rev-list -n1 --timestamp "$commit" ')
	v_timestamp,v_commithash := vgit.line_to_timestamp_and_commit(vline)
	vgit.check_v_commit_timestamp_before_self_rebuilding(v_timestamp)
	scripting.chdir(vcdir)
	scripting.run('git checkout master')
	vcbefore := scripting.run('git rev-list HEAD -n1 --timestamp --before=$v_timestamp ')
	_,vccommit_before := vgit.line_to_timestamp_and_commit(vcbefore)
	scripting.run('git checkout "$vccommit_before" ')
	scripting.run('wc *.c')
	scripting.chdir(cdir)
	return v_commithash,vccommit_before
}

pub fn clone_or_pull( remote_git_url string, local_worktree_path string ) {
	// NB: after clone_or_pull, the current repo branch is === HEAD === master
	if os.is_dir( local_worktree_path ) && os.is_dir(filepath.join(local_worktree_path,'.git')) {
		// Already existing ... Just pulling in this case is faster usually.
		scripting.run('git -C "$local_worktree_path"  checkout --quiet master')
		scripting.run('git -C "$local_worktree_path"  pull     --quiet ')
	} else {
		// Clone a fresh
		scripting.run('git clone --quiet "$remote_git_url"  "$local_worktree_path" ')
	}
}	

//

pub struct VGitContext {
pub:
	cc          string = 'cc'     // what compiler to use
	workdir     string = '/tmp'   // the base working folder
	commit_v    string = 'master' // the commit-ish that needs to be prepared
	path_v      string // where is the local working copy v repo
	path_vc     string // where is the local working copy vc repo
	v_repo_url  string // the remote v repo URL
	vc_repo_url string // the remote vc repo URL
pub mut:
	// these will be filled by vgitcontext.compile_oldv_if_needed()
	commit_v__hash string // the git commit of the v repo that should be prepared
	commit_vc_hash string // the git commit of the vc repo, corresponding to commit_v__hash
	vexename string // v or v.exe
	vexepath string // the full absolute path to the prepared v/v.exe
	vvlocation string // v.v or compiler/ or vlib/cmd/v, depending on v version
}

pub fn (vgit_context mut VGitContext) compile_oldv_if_needed() {
	vgit_context.vexename = if os.user_os() == 'windows' { 'v.exe' } else { 'v' }
	vgit_context.vexepath = os.realpath( filepath.join(vgit_context.path_v, vgit_context.vexename) )
	mut command_for_building_v_from_c_source := ''
	mut command_for_selfbuilding := ''
	if 'windows' == os.user_os() {
		command_for_building_v_from_c_source = '$vgit_context.cc -std=c99 -municode -w -o cv.exe  "$vgit_context.path_vc/v_win.c" '
		command_for_selfbuilding = './cv.exe -o $vgit_context.vexename {SOURCE}'
	}
	else {
		command_for_building_v_from_c_source = '$vgit_context.cc -std=gnu11 -w -o cv "$vgit_context.path_vc/v.c"  -lm'
		command_for_selfbuilding = './cv -o $vgit_context.vexename {SOURCE}'
	}
	scripting.chdir(vgit_context.workdir)
	clone_or_pull( vgit_context.v_repo_url,  vgit_context.path_v )
	clone_or_pull( vgit_context.vc_repo_url, vgit_context.path_vc )
	
	scripting.chdir(vgit_context.path_v)
	scripting.run('git checkout $vgit_context.commit_v')
	v_commithash,vccommit_before := vgit.prepare_vc_source(vgit_context.path_vc, vgit_context.path_v, vgit_context.commit_v)
	vgit_context.commit_v__hash = v_commithash
	vgit_context.commit_vc_hash = vccommit_before
	if os.exists('vlib/cmd/v') {
		vgit_context.vvlocation = 'vlib/cmd/v'
	} else {
		vgit_context.vvlocation = if os.exists('v.v') { 'v.v' } else { 'compiler' }
	}
	if os.is_dir(vgit_context.path_v) && os.exists(vgit_context.vexepath) {
		// already compiled, so no need to compile v again
		return
	}
	// Recompilation is needed. Just to be sure, clean up everything first.
	scripting.run('git clean -xf')
	scripting.run(command_for_building_v_from_c_source)
	build_cmd := command_for_selfbuilding.replace('{SOURCE}', vgit_context.vvlocation)
	scripting.run(build_cmd)
	
	// At this point, there exists a file vgit_context.vexepath
	// which should be a valid working V executable.
}

pub fn add_common_tool_options<T>(context mut T, fp mut flag.FlagParser) []string {
	tdir := os.tmpdir()
	context.workdir = os.realpath(fp.string_('workdir', `w`, tdir, 'A writable base folder. Default: $tdir'))
	context.v_repo_url = fp.string('vrepo', vgit.remote_v_repo_url, 'The url of the V repository. You can clone it locally too. See also --vcrepo below.')
	context.vc_repo_url = fp.string('vcrepo', vgit.remote_vc_repo_url, 'The url of the vc repository. You can clone it
${flag.SPACE}beforehand, and then just give the local folder 
${flag.SPACE}path here. That will eliminate the network ops 
${flag.SPACE}done by this tool, which is useful, if you want
${flag.SPACE}to script it/run it in a restrictive vps/docker.
')
	context.show_help = fp.bool_('help', `h`, false, 'Show this help screen.')
	context.verbose = fp.bool_('verbose', `v`, false, 'Be more verbose.')

	if (context.show_help) {
		println(fp.usage())
		exit(0)
	}

	if context.verbose {
		scripting.set_verbose(true)
	}
	
	if os.is_dir(context.v_repo_url) {
		context.v_repo_url = os.realpath( context.v_repo_url )
	}
	
	if os.is_dir(context.vc_repo_url) {
		context.vc_repo_url = os.realpath( context.vc_repo_url )
	}

	commits := fp.finalize() or {
		eprintln('Error: ' + err)
		exit(1)
	}
	for commit in commits {
		vgit.validate_commit_exists(commit)
	}
	
	return commits
}
