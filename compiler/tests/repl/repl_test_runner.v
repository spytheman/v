/*  -*- Mode: Go; indent-tabs-mode: t; c-basic-offset: 4; tab-width: 4 -*-  */

import flag
import os
import term

struct State {
mut:
	score int
	total int
	debug bool
}

fn (state mut State) test_file(file string){
	if state.debug {
		print('Testing $file: ')
	}
	sfile := os.read_file( file ) or {
		println('error reading file $file')
		exit(1)
	}
	input  := sfile.all_before('===output===\n')
	output := sfile.all_after('===output===\n')
	tmpinfile := 'temporary_repl_input_file'
	os.write_file(tmpinfile, input)
	defer {
		os.rm(tmpinfile)
	}
	mut x := os.exec('./v < $tmpinfile ') or { panic(err) }
	result := x.output.replace('>>> ', '').replace('>>>', '').all_after('Use Ctrl-C or `exit` to exit\n')
	if output == result {
		state.score++
		if state.debug {
			println(term.green('OK'))
		}
	}else{
		if state.debug {
			println(term.red('KO'))
		}else{
			println('Repl test for file: $file failed.')
		}
		println(term.bold(term.white('Input :')))
		println(input)
		println(term.bold(term.white('Got :')))
		println(result)
		println(term.bold(term.white('Expected :')))
		println(output)
	}
	state.total++
}

fn main() {
	mut state := State{}
	
	mut fp := flag.new_flag_parser(os.args)	
	fp.application('repl_test_runner')
	fp.version('v0.0.1')
	fp.description('This tool expects .repl files.\n'+
	               'It runs the V repl with input based on them\n'+
	               'The output from the v repl, is expected to match\n'+
	               ' *exactly* the one from the .repl file.')
	fp.skip_executable()	
	state.debug = fp.bool('d', false, 'Show debug information.')
	if fp.bool('help', false, 'Show usage') {
		println(fp.usage())
		exit(0)
	}
	mut replfiles := fp.finalize() or {
		eprintln(err)
		println(fp.usage())
		exit(1)
	}
	
	//if no specific .repl files are given, assume that ALL should be run
	if replfiles.len == 0 {
		replfiles = os.walk_ext('.', '.repl')
	}
	
	for f in replfiles {
		state.test_file(f)
	}

	result := 'REPL SCORE: ${state.score} / ${state.total}'
	println(term.bold(term.white(result)))
	
	if state.score != state.total {
		exit(1)
	}
}
