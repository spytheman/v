// Copyright (c) 2019 Alexander Medvednikov. All rights reserved.
// Use of this source code is governed by an MIT license
// that can be found in the LICENSE file.
module main

import (
	os
	os.cmdline
	filepath
	compiler
)

struct FormatOptions {
	is_w       bool
	is_diff    bool
	is_verbose bool
	is_all     bool
}

fn main() {
	toolexe := os.executable()
	compiler.set_vroot_folder(filepath.dir(filepath.dir(toolexe)))
	args := compiler.env_vflags_and_os_args()
	foptions := FormatOptions{
		is_w: '-w' in args
		is_diff: '-diff' in args
		is_verbose: '-verbose' in args || '--verbose' in args
		is_all: '-all' in args || '--all' in args
	}
	possible_files := cmdline.only_non_options(cmdline.after(args, ['fmt']))
	if foptions.is_verbose {
		eprintln('vfmt toolexe: $toolexe')
		eprintln('vfmt args: ' + os.args.str())
		eprintln('vfmt env_vflags_and_os_args: ' + args.str())
		eprintln('vfmt possible_files: ' + possible_files.str())
	}
	mut files := []string
	for file in possible_files {
		if !os.exists(file) {
			compiler.verror('"$file" does not exist.')
		}
		if !file.ends_with('.v') {
			compiler.verror('v fmt can only be used on .v files.\nOffending file: "$file" .')
		}
		files << file
	}
	if files.len == 0 {
		usage()
		exit(0)
	}
	for file in files {
		foptions.format_file(os.realpath(file))
	}
}

fn (foptions &FormatOptions) format_file(file string) {
	tmpfolder := os.tmpdir()
	mut compiler_params := []string
	
	mut cfile := file	
	mut mod_folder_parent := tmpfolder
	fcontent := os.read_file(file) or {
		return
	}
	is_test_file := file.ends_with('_test.v')
	is_module_file := fcontent.contains('module ') && !fcontent.contains('module main')
	use_tmp_main_program := is_module_file && !is_test_file
	
	mod_folder := filepath.basedir(file)
	mut mod_name := 'main'
	if is_module_file {
		mod_name = filepath.filename(mod_folder)
	}
	if use_tmp_main_program {
		// TODO: remove the need for this
		// This makes a small program that imports the module,
		// so that the module files will get processed by the
		// vfmt implementation.
		mod_folder_parent = filepath.basedir( mod_folder )
		main_program_content := 'import ${mod_name} \n fn main(){} \n'
		main_program_file := filepath.join( tmpfolder,'vfmt_tmp_${mod_name}_program.v')
		if os.exists(main_program_file){
			os.rm(main_program_file)
		}
		os.write_file(main_program_file, main_program_content)
		cfile = main_program_file
		compiler_params << ['-user_mod_path', mod_folder_parent]
	}
	compiler_params << cfile

	if foptions.is_verbose {
		eprintln('vfmt format_file: file: $file')
		eprintln('vfmt format_file: cfile: $cfile')
		eprintln('vfmt format_file: is_test_file: $is_test_file')
		eprintln('vfmt format_file: is_module_file: $is_module_file')
		eprintln('vfmt format_file: mod_name: $mod_name')
		eprintln('vfmt format_file: mod_folder: $mod_folder')
		eprintln('vfmt format_file: mod_folder_parent: $mod_folder_parent')
		eprintln('vfmt format_file: use_tmp_main_program: $use_tmp_main_program')
		eprintln('vfmt format_file: compiler_params: $compiler_params')
		eprintln('-------------------------------------------')
	}
	
	formatted_file_path := foptions.compile_file(file, compiler_params )
	
	if use_tmp_main_program {
		os.rm(cfile)
	}

	if formatted_file_path.len == 0 { return }
	
	if foptions.is_diff {
		diff_cmd := find_working_diff_command() or {
			eprintln('No working "diff" CLI command found.')
			return
		}
		os.system('$diff_cmd "$formatted_file_path" "$file" ')
		return
	}
	if foptions.is_w {
		os.mv_by_cp(formatted_file_path, file) or {
			panic(err)
		}
		eprintln('Reformatted file in place: $file .')
	}
	else {
		content := os.read_file(formatted_file_path) or {
			panic(err)
		}
		print(content)
	}
}

fn usage() {
	print('Usage: tools/vfmt [flags] path_to_source.v [path_to_other_source.v]
Formats the given V source files, and prints their formatted source to stdout.
Options:
  -diff display only diffs between the formatted source and the original source.
  -w    write result to (source) file(s) instead of to stdout.
')
}

fn find_working_diff_command() ?string {
	for diffcmd in ['colordiff', 'diff', 'colordiff.exe', 'diff.exe'] {
		p := os.exec('$diffcmd --version') or {
			continue
		}
		if p.exit_code == 0 {
			return diffcmd
		}
	}
	return error('no working diff command found')
}


fn (foptions &FormatOptions) compile_file(file string, compiler_params []string) string {
	mut v := compiler.new_v_compiler_with_args(compiler_params)
	v.v_fmt_file = file
	if foptions.is_all {
		v.v_fmt_all = true
	}
	v.compile()
	return v.v_fmt_file_result
}
	
