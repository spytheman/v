import os
import flag
import scripting
import vgit

const (
	tool_version     = '0.0.5'
	tool_description = '  Checkout an old V and compile it as it was on specific commit.
|     This tool is useful, when you want to discover when something broke.
|     It is also useful, when you just want to experiment with an older historic V.
|
|     The VCOMMIT argument can be a git commitish like HEAD or master and so on.
|     When oldv is used with git bisect, you probably want to give HEAD. For example:
|       ## Setup:
|          git bisect start
|          git bisect bad
|          git checkout known_good_commit
|          git bisect good
|              ## -> git will automatically checkout a middle commit between the bad and the good
|
|       ## Manual inspection loop:
|          cmd/tools/oldv --bisect --command="run commands in oldv folder, to verify if the commit is good or bad"
|              ## See what the result is, and either do: ...
|          git bisect good
|              ## ... or do:
|          git bisect bad
|              ## Now you just repeat the above steps in the manual inspection loop, each time running oldv
|              ## with the same command, then mark the result as good or bad,
|              ## until you find the commit, where the problem first occurred.
|
|       ## Automatic bisect mode, for finding regressions:
|              ## The setup is the same as above, but you can do everything automatically, with a single command.
|              ## To do that, you have to be sure, that you have a *reliable* script command, that can be run each time,
|              ## without user intervention, and whose exit code is 0 when the commit is good, and non 0, when it is bad.
|              ## In this case, to save you some interaction time, you can let the tool run the bisecting loop for you with:
|          cmd/tools/oldv -a --command="run command that exits with 0 for good commits"
|
|       ## Cleanup:
|              ## When you finish (in both manual or automatic mode), do not forget to:
|          git bisect reset
|       
|'.strip_margin()
)

struct Context {
mut:
	vgo           vgit.VGitOptions
	vgcontext     vgit.VGitContext
	commit_v      string = 'master' // the commit from which you want to produce a working v compiler (this may be a commit-ish too)
	commit_v_hash string // this will be filled from the commit-ish commit_v using rev-list. It IS a commit hash.
	path_v        string // the full path to the v folder inside workdir.
	path_vc       string // the full path to the vc folder inside workdir.
	cmd_to_run    string // the command that you want to run *in* the oldv repo
	cc            string = 'cc' // the C compiler to use for bootstrapping.
	cleanup       bool   // should the tool run a cleanup first
	use_cache     bool   // use local cached copies for --vrepo and --vcrepo in
	fresh_tcc     bool   // do use `make fresh_tcc`
	is_bisect     bool   // bisect mode; usage: `cmd/tools/oldv -b -c './v run bug.v'`
	auto_bisect   bool   // auto bisect mode; it requires that the command/script exits with 0 for good commits, and != 0 for bad ones.
	// In this mode, oldv will run the script command repeatedly doing either `git bisect good` or `git bisect bad` based on its exit code.
	// Oldv will stop, when the bisection ends. This mode is very convenient for finding regressions, where some code did compile at some
	// known point in the past, but stopped to compile after that.
	// usage: `cmd/tools/oldv -a -c './v run bug.v'`
	auto_ibisect bool // auto inverted bisect mode; similar to auto_bisect, but if the script command exits with 0, do `git bisect bad`,
	// and if it exits with !=0, do `git bisect good` (inverse mode).
}

fn (mut c Context) compile_oldv_if_needed() {
	c.vgcontext = vgit.VGitContext{
		workdir: c.vgo.workdir
		v_repo_url: c.vgo.v_repo_url
		vc_repo_url: c.vgo.vc_repo_url
		cc: c.cc
		commit_v: c.commit_v
		path_v: c.path_v
		path_vc: c.path_vc
		make_fresh_tcc: c.fresh_tcc
	}
	c.vgcontext.compile_oldv_if_needed()
	c.commit_v_hash = c.vgcontext.commit_v__hash
	if !os.exists(c.vgcontext.vexepath) && c.cmd_to_run.len > 0 {
		// Note: 125 is a special code, that git bisect understands as 'skip this commit'.
		// it is used to inform git bisect that the current commit leads to a build failure.
		exit(125)
	}
}

fn (mut c Context) auto_bisect_loop() {
	os.setenv('VCOLORS', 'always', true)
	oldv_exe := os.executable()
	subcmd := "${os.quoted_path(oldv_exe)} --bisect --command '${c.cmd_to_run}'"
	g_label := if c.auto_bisect { 'good' } else { 'bad' }
	b_label := if c.auto_bisect { 'bad' } else { 'good' }
	mut step := 0
	for {
		step++
		println('>>>>> auto bisecting step: ${step:3} | command: ${subcmd}')
		res := os.execute(subcmd)
		println(res.output)
		git_bisect_cmd := 'git bisect ' + if res.exit_code == 0 { g_label } else { b_label }
		println('>>>>>>>>> git command: ${git_bisect_cmd}')
		git_bisect_res := os.execute(git_bisect_cmd)
		println(git_bisect_res.output)
		if !git_bisect_res.output.starts_with('Bisecting:') {
			break
		}
		println('----------------------------------------------------------------------------------')
	}
	exit(0)
}

const cache_oldv_folder = os.join_path(os.cache_dir(), 'oldv')

const cache_oldv_folder_v = os.join_path(cache_oldv_folder, 'v')

const cache_oldv_folder_vc = os.join_path(cache_oldv_folder, 'vc')

fn sync_cache() {
	scripting.verbose_trace(@FN, 'start')
	if !os.exists(cache_oldv_folder) {
		scripting.verbose_trace(@FN, 'creating ${cache_oldv_folder}')
		scripting.mkdir_all(cache_oldv_folder) or {
			scripting.verbose_trace(@FN, '## failed.')
			exit(1)
		}
	}
	scripting.chdir(cache_oldv_folder)
	for reponame in ['v', 'vc'] {
		repofolder := os.join_path(cache_oldv_folder, reponame)
		if !os.exists(repofolder) {
			scripting.verbose_trace(@FN, 'cloning to ${repofolder}')
			mut repo_options := ''
			if reponame == 'vc' {
				repo_options = '--filter=blob:none'
			}
			scripting.exec('git clone ${repo_options} --quiet https://github.com/vlang/${reponame} ${repofolder}') or {
				scripting.verbose_trace(@FN, '## error during clone: ${err}')
				exit(1)
			}
		}
		scripting.chdir(repofolder)
		scripting.exec('git pull --quiet') or {
			scripting.verbose_trace(@FN, 'pulling to ${repofolder}')
			scripting.verbose_trace(@FN, '## error during pull: ${err}')
			exit(1)
		}
	}
	scripting.verbose_trace(@FN, 'done')
}

fn main() {
	scripting.used_tools_must_exist(['git', 'cc'])
	//
	// Resetting VEXE here allows for `v run cmd/tools/oldv.v'.
	// the parent V would have set VEXE, which later will
	// affect the V's run from the tool itself.
	os.setenv('VEXE', '', true)
	//
	mut context := Context{}
	context.vgo.workdir = cache_oldv_folder
	mut fp := flag.new_flag_parser(os.args)
	fp.application(os.file_name(os.executable()))
	fp.version(tool_version)
	fp.description(tool_description)
	fp.arguments_description('VCOMMIT')
	fp.skip_executable()
	context.use_cache = fp.bool('cache', `u`, true, 'Use a cache of local repositories for --vrepo and --vcrepo in \$HOME/.cache/oldv/')
	if context.use_cache {
		context.vgo.v_repo_url = cache_oldv_folder_v
		context.vgo.vc_repo_url = cache_oldv_folder_vc
	} else {
		context.vgo.v_repo_url = 'https://github.com/vlang/v'
		context.vgo.vc_repo_url = 'https://github.com/vlang/vc'
	}
	should_sync := fp.bool('cache-sync', `s`, false, 'Update the local cache')
	context.is_bisect = fp.bool('bisect', `b`, false, 'Bisect mode. Use the current commit in the repo where oldv is.')
	context.auto_bisect = fp.bool('auto-bisect', `a`, false, 'Auto bisect mode. Run the script command repeatedly, and do `git bisect good` for exit code 0, and `git bisect bad` for anything else. Implies -b. Useful for finding regressions, where something worked before, but it now does not.')
	context.auto_ibisect = fp.bool('auto-ibisect', `i`, false, 'Auto inverse bisect mode. Run the script command repeatedly, and do `git bisect bad` for exit code 0, and `git bisect good` for anything else. Implies -b. Useful for finding when exactly something started working.')
	if context.auto_bisect || context.auto_ibisect {
		context.is_bisect = true
	}
	if !should_sync && !context.is_bisect {
		fp.limit_free_args(1, 1)!
	}
	////
	context.cleanup = fp.bool('clean', 0, false, 'Clean before running (slower).')
	context.fresh_tcc = fp.bool('fresh_tcc', 0, true, 'Do `make fresh_tcc` when preparing a V compiler.')
	context.cmd_to_run = fp.string('command', `c`, '', 'Command to run in the old V repo.\n')
	commits := vgit.add_common_tool_options(mut context.vgo, mut fp)
	if should_sync {
		sync_cache()
		exit(0)
	}
	if context.use_cache {
		if !os.is_dir(cache_oldv_folder_v) || !os.is_dir(cache_oldv_folder_vc) {
			sync_cache()
		}
	}
	if commits.len > 0 {
		context.commit_v = commits[0]
		if context.is_bisect {
			eprintln('In bisect mode, you should not pass any commits, since oldv will use the current one.')
			exit(2)
		}
	} else {
		context.commit_v = scripting.run('git rev-list -n1 HEAD')
	}
	scripting.cprintln('#################  context.commit_v: ${context.commit_v} #####################')
	context.path_v = vgit.normalized_workpath_for_commit(context.vgo.workdir, context.commit_v)
	context.path_vc = vgit.normalized_workpath_for_commit(context.vgo.workdir, 'vc')
	if !os.is_dir(context.vgo.workdir) {
		eprintln('Work folder: ${context.vgo.workdir} , does not exist.')
		exit(2)
	}
	ecc := os.getenv('CC')
	if ecc != '' {
		context.cc = ecc
	}
	if context.auto_bisect || context.auto_ibisect {
		context.auto_bisect_loop()
	}
	if context.cleanup {
		scripting.rmrf(context.path_v)
		scripting.rmrf(context.path_vc)
	}
	context.compile_oldv_if_needed()
	scripting.chdir(context.path_v)
	shorter_hash := context.commit_v_hash[0..10]
	scripting.cprintln('#     v commit hash: ${shorter_hash} | folder: ${context.path_v}')
	if context.cmd_to_run.len > 0 {
		scripting.cprintln_strong('#           command: ${context.cmd_to_run:-34s}')
		cmdres := os.execute_or_exit(context.cmd_to_run)
		if cmdres.exit_code != 0 {
			scripting.cprintln_strong('#         exit code: ${cmdres.exit_code:-4d}')
		}
		scripting.cprint_strong('#            result: ')
		print(cmdres.output)
		if !cmdres.output.ends_with('\n') {
			println('')
		}
		exit(cmdres.exit_code)
	}
}
