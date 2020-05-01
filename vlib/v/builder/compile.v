// Copyright (c) 2019-2020 Alexander Medvednikov. All rights reserved.
// Use of this source code is governed by an MIT license
// that can be found in the LICENSE file.
module builder

import benchmark
import os
import v.pref
import v.util
import strings

fn get_vtmp_folder() string {
	vtmp := os.join_path(os.temp_dir(), 'v')
	if !os.is_dir(vtmp) {
		os.mkdir(vtmp) or {
			panic(err)
		}
	}
	return vtmp
}

fn get_vtmp_filename(base_file_name, postfix string) string {
	vtmp := get_vtmp_folder()
	return os.real_path(os.join_path(vtmp, os.file_name(os.real_path(base_file_name)) + postfix))
}

pub fn compile(command string, pref &pref.Preferences) {
	// Construct the V object from command line arguments
	mut b := new_builder(pref)
	if pref.is_verbose {
		println('builder.compile() pref:')
		// println(pref)
	}
	mut tmark := benchmark.new_benchmark()
	match pref.backend {
		.c { b.compile_c() }
		.js { b.compile_js() }
		.x64 { b.compile_x64() }
	}
	if pref.is_stats {
		tmark.stop()
		println('compilation took: ' + tmark.total_duration().str() + 'ms')
	}
	if pref.is_test || pref.is_run {
		b.run_compiled_executable_and_exit()
	}
	// v.finalize_compilation()
}

fn (mut b Builder) run_compiled_executable_and_exit() {
	if b.pref.is_verbose {
		println('============ running $b.pref.out_name ============')
	}
	mut cmd := '"${b.pref.out_name}"'
	for arg in b.pref.run_args {
		// Determine if there are spaces in the parameters
		if arg.index_byte(` `) > 0 {
			cmd += ' "' + arg + '"'
		} else {
			cmd += ' ' + arg
		}
	}
	if b.pref.is_verbose {
		println('command to run executable: $cmd')
	}
	if b.pref.is_test {
		ret := os.system(cmd)
		if ret != 0 {
			exit(1)
		}
	}
	if b.pref.is_run {
		ret := os.system(cmd)
		// TODO: make the runner wrapping as transparent as possible
		// (i.e. use execve when implemented). For now though, the runner
		// just returns the same exit code as the child process.
		exit(ret)
	}
	exit(0)
}

// 'strings' => 'VROOT/vlib/strings'
// 'installed_mod' => '~/.vmodules/installed_mod'
// 'local_mod' => '/path/to/current/dir/local_mod'
fn (mut v Builder) set_module_lookup_paths() {
	// Module search order:
	// 0) V test files are very commonly located right inside the folder of the
	// module, which they test. Adding the parent folder of the module folder
	// with the _test.v files, *guarantees* that the tested module can be found
	// without needing to set custom options/flags.
	// 1) search in the *same* directory, as the compiled final v program source
	// (i.e. the . in `v .` or file.v in `v file.v`)
	// 2) search in the modules/ in the same directory.
	// 3) search in the provided paths
	// By default, these are what (3) contains:
	// 3.1) search in vlib/
	// 3.2) search in ~/.vmodules/ (i.e. modules installed with vpm)
	v.module_search_paths = []
	if v.pref.is_test {
		v.module_search_paths << os.base_dir(v.compiled_dir) // pdir of _test.v
	}
	v.module_search_paths << v.compiled_dir
	x := os.join_path(v.compiled_dir, 'modules')
	if v.pref.is_verbose {
		println('x: "$x"')
	}
	v.module_search_paths << os.join_path(v.compiled_dir, 'modules')
	v.module_search_paths << v.pref.lookup_path
	if v.pref.is_verbose {
		v.log('v.module_search_paths:')
		println(v.module_search_paths)
	}
}

pub fn (v Builder) get_builtin_files() []string {
	if v.pref.build_mode == .build_module && v.pref.path == 'vlib/builtin' { // .contains('builtin/' +  location {
		// We are already building builtin.o, no need to import them again
		if v.pref.is_verbose {
			println('skipping builtin modules for builtin.o')
		}
		return []
	}
	// println('get_builtin_files() lookuppath:')
	// println(v.pref.lookup_path)
	// Lookup for built-in folder in lookup path.
	// Assumption: `builtin/` folder implies usable implementation of builtin
	for location in v.pref.lookup_path {
		if !os.exists(os.join_path(location, 'builtin')) {
			continue
		}
		if v.pref.is_bare {
			return v.v_files_from_dir(os.join_path(location, 'builtin', 'bare'))
		}
		$if js {
			return v.v_files_from_dir(os.join_path(location, 'builtin', 'js'))
		}
		return v.v_files_from_dir(os.join_path(location, 'builtin'))
	}
	// Panic. We couldn't find the folder.
	verror('`builtin/` not included on module lookup path.
Did you forget to add vlib to the path? (Use @vlib for default vlib)')
	panic('Unreachable code reached.')
}

pub fn (v Builder) get_user_files() []string {
	mut dir := v.pref.path
	v.log('get_v_files($dir)')
	// Need to store user files separately, because they have to be added after
	// libs, but we dont know	which libs need to be added yet
	mut user_files := []string{}
	// See cmd/tools/preludes/README.md for more info about what preludes are
	vroot := os.dir(pref.vexe_path())
	preludes_path := os.join_path(vroot, 'cmd', 'tools', 'preludes')
	if v.pref.is_livemain {
		user_files << os.join_path(preludes_path, 'live_main.v')
	}
	if v.pref.is_liveshared {
		user_files << os.join_path(preludes_path, 'live_shared.v')
	}
	if v.pref.is_test {
		user_files << os.join_path(preludes_path, 'tests_assertions.v')
	}
	if v.pref.is_test && v.pref.is_stats {
		user_files << os.join_path(preludes_path, 'tests_with_stats.v')
	}
	if v.pref.is_prof {
		user_files << os.join_path(preludes_path, 'profiled_program.v')
	}
	is_test := dir.ends_with('_test.v')
	if v.pref.is_run && is_test {
		println('use `v x_test.v` instead of `v run x_test.v`')
		exit(1)
	}
	mut is_internal_module_test := false
	if is_test {
		tcontent := os.read_file(dir) or {
			panic('$dir does not exist')
		}
		slines := tcontent.trim_space().split_into_lines()
		for sline in slines {
			line := sline.trim_space()
			if line.len > 2 {
				if line[0] == `/` && line[1] == `/` {
					continue
				}
				if line.starts_with('module ') && !line.starts_with('module main') {
					is_internal_module_test = true
					break
				}
			}
		}
	}
	if is_internal_module_test {
		// v volt/slack_test.v: compile all .v files to get the environment
		single_test_v_file := os.real_path(dir)
		if v.pref.is_verbose {
			v.log('> Compiling an internal module _test.v file $single_test_v_file .')
			v.log('> That brings in all other ordinary .v files in the same module too .')
		}
		user_files << single_test_v_file
		dir = os.base_dir(single_test_v_file)
	}
	is_real_file := os.exists(dir) && !os.is_dir(dir)
	if is_real_file && (dir.ends_with('.v') || dir.ends_with('.vsh')) {
		single_v_file := dir
		// Just compile one file and get parent dir
		user_files << single_v_file
		if v.pref.is_verbose {
			v.log('> just compile one file: "${single_v_file}"')
		}
	} else {
		if v.pref.is_verbose {
			v.log('> add all .v files from directory "${dir}" ...')
		}
		// Add .v files from the directory being compiled
		user_files << v.v_files_from_dir(dir)
	}
	if user_files.len == 0 {
		println('No input .v files')
		exit(1)
	}
	if v.pref.is_verbose {
		v.log('user_files: $user_files')
	}
	return user_files
}
