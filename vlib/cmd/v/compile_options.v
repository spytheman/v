// Copyright (c) 2019-2020 Alexander Medvednikov. All rights reserved.
// Use of this source code is governed by an MIT license
// that can be found in the LICENSE file.
module main

import (
	compiler
	filepath
	os
	os.cmdline
	v.pref
)

pub fn new_v(args []string) &compiler.V {
	// Create modules dirs if they are missing
	if !os.is_dir(compiler.v_modules_path) {
		os.mkdir(compiler.v_modules_path)or{
			panic(err)
		}
		os.mkdir('$compiler.v_modules_path${os.path_separator}cache')or{
			panic(err)
		}
	}
	vroot := filepath.dir(vexe_path())
	// optional, custom modules search path
	user_mod_path := cmdline.option(args, '-user_mod_path', '')
	vlib_path := cmdline.option(args, '-vlib-path', '')
	vpath := cmdline.option(args, '-vpath', '')
	target_os := cmdline.option(args, '-os', '')
	if target_os == 'msvc' {
		// notice that `-os msvc` became `-cc msvc`
		println('V error: use the flag `-cc msvc` to build using msvc')
		os.flush_stdout()
		exit(1)
	}
	mut out_name := cmdline.option(args, '-o', '')
	mut dir := args.last()
	if 'run' in args {
		args_after_run := cmdline.only_non_options( cmdline.after(args,['run']) )
		dir = if args_after_run.len>0 { args_after_run[0] } else { '' }
	}
	if dir == 'v.v' {
		println('looks like you are trying to build V with an old command')
		println('use `v -o v vlib/cmd/v` instead of `v -o v v.v`')
		exit(1)
	}
	if dir.ends_with(os.path_separator) {
		dir = dir.all_before_last(os.path_separator)
	}
	if dir.starts_with('.$os.path_separator') {
		dir = dir[2..]
	}
	if args.len < 2 {
		dir = ''
	}

	// build mode
	mut build_mode := pref.BuildMode.default_mode
	mut mod := ''
	joined_args := args.join(' ')
	if joined_args.contains('build module ') {
		build_mode = .build_module
		os.chdir(vroot)
		// v build module ~/v/os => os.o
		mod_path := if dir.contains('vlib') { dir.all_after('vlib' + os.path_separator) } else if dir.starts_with('.\\') || dir.starts_with('./') { dir[2..] } else if dir.starts_with(os.path_separator) { dir.all_after(os.path_separator) } else { dir }
		mod = mod_path.replace(os.path_separator, '.')
		println('Building module "${mod}" (dir="$dir")...')
		// out_name = '$TmpPath/vlib/${base}.o'
		if !out_name.ends_with('.c') {
			out_name = mod
		}
		// Cross compiling? Use separate dirs for each os
		/*
		if target_os != os.user_os() {
			os.mkdir('$TmpPath/vlib/$target_os') or { panic(err) }
			out_name = '$TmpPath/vlib/$target_os/${base}.o'
			println('target_os=$target_os user_os=${os.user_os()}')
			println('!Cross compiling $out_name')
		}
		*/

	}
	is_test := dir.ends_with('_test.v')
	is_script := dir.ends_with('.v') || dir.ends_with('.vsh')
	if is_script && !os.exists(dir) {
		println('`$dir` does not exist')
		exit(1)
	}
	// `v -o dir/exec`, create "dir/" if it doesn't exist
	if out_name.contains(os.path_separator) {
		d := out_name.all_before_last(os.path_separator)
		if !os.is_dir(d) {
			println('creating a new directory "$d"')
			os.mkdir(d)or{
				panic(err)
			}
		}
	}

	// println('VROOT=$vroot')
	cflags := cmdline.many_values(args, '-cflags').join(' ')

	defines := cmdline.many_values(args, '-d')
	compile_defines, compile_defines_all := parse_defines( defines )

	rdir := os.realpath(dir)
	rdir_name := filepath.filename(rdir)
	if '-bare' in args {
		println('V error: use -freestanding instead of -bare')
		os.flush_stdout()
		exit(1)
	}
	is_repl := '-repl' in args
	ccompiler := cmdline.option(args, '-cc', '')
	mut pref := &pref.Preferences{
		os: pref.os_from_string(target_os)
		is_test: is_test
		is_script: is_script
		is_so: '-shared' in args
		is_solive: '-solive' in args
		is_prod: '-prod' in args
		is_verbose: '-verbose' in args || '--verbose' in args
		is_debug: '-g' in args || '-cg' in args
		is_vlines: '-g' in args && !('-cg' in args)
		is_keep_c: '-keep_c' in args
		is_pretty_c: '-pretty_c' in args
		is_cache: '-cache' in args
		is_stats: '-stats' in args
		obfuscate: '-obf' in args
		is_prof: '-prof' in args
		is_live: '-live' in args
		sanitize: '-sanitize' in args
		// nofmt: '-nofmt' in args

		show_c_cmd: '-show_c_cmd' in args
		translated: 'translated' in args
		is_run: 'run' in args
		autofree: '-autofree' in args
		compress: '-compress' in args
		enable_globals: '--enable-globals' in args
		fast: '-fast' in args
		is_bare: '-freestanding' in args
		x64: '-x64' in args
		output_cross_c: '-output-cross-platform-c' in args
		prealloc: '-prealloc' in args
		is_repl: is_repl
		build_mode: build_mode
		cflags: cflags
		ccompiler: ccompiler
		building_v: !is_repl && (rdir_name == 'compiler' || rdir_name == 'v.v' || rdir_name == 'vfmt.v' || rdir_name == 'vlib/cmd/v' || dir.contains('vlib'))
		// is_fmt: comptime_define == 'vfmt'

		user_mod_path: user_mod_path
		vlib_path: vlib_path
		vpath: vpath
		v2: '-v2' in args
		vroot: vroot
		out_name: out_name
		path: dir
		compile_defines: compile_defines
		compile_defines_all: compile_defines_all
		mod: mod
	}
	if pref.is_verbose || pref.is_debug {
		println('C compiler=$pref.ccompiler')
	}
	$if !linux {
		if pref.is_bare && !out_name.ends_with('.c') {
			println('V error: -freestanding only works on Linux for now')
			os.flush_stdout()
			exit(1)
		}
	}
	pref.fill_with_defaults()

	// v.exe's parent directory should contain vlib
	if !os.is_dir(pref.vlib_path) || !os.is_dir(pref.vlib_path + os.path_separator + 'builtin') {
		// println('vlib not found, downloading it...')
		/*
		ret := os.system('git clone --depth=1 https://github.com/vlang/v .')
		if ret != 0 {
			println('failed to `git clone` vlib')
			println('make sure you are online and have git installed')
			exit(1)
		}
		*/
		println('vlib not found. It should be next to the V executable.')
		println('Go to https://vlang.io to install V.')
		println('(os.executable=${os.executable()} vlib_path=$pref.vlib_path vexe_path=${vexe_path()}')
		exit(1)
	}

	return compiler.new_v(pref)
}

fn find_c_compiler_thirdparty_options(args []string) string {
	mut cflags := cmdline.many_values(args,'-cflags')
	$if !windows {
		cflags << '-fPIC'
	}
	if '-m32' in args {
		cflags << '-m32'
	}
	return cflags.join(' ')
}

fn final_target_out_name(out_name string) string {
	$if windows {
		return out_name.replace('/', '\\') + '.exe'
	}
	return if out_name.starts_with('/') { out_name } else { './' + out_name }
}

fn parse_defines(defines []string) ([]string,[]string) {
	// '-d abc -d xyz=1 -d qwe=0' should produce:
	// compile_defines:      ['abc','xyz']
	// compile_defines_all   ['abc','xyz','qwe']
	mut compile_defines := []string
	mut compile_defines_all := []string
	for dfn in defines {
		dfn_parts := dfn.split('=')
		if dfn_parts.len == 1 {
			compile_defines << dfn
			compile_defines_all << dfn
			continue
		}
		if dfn_parts.len == 2 {
			compile_defines_all << dfn_parts[0]
			if dfn_parts[1] == '1' {
				compile_defines << dfn_parts[0]
			}
		}
	}
	return compile_defines, compile_defines_all
}

