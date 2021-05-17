module main

import os
import time
import benchmark

// This file will get compiled as a part of the same module,
// in which a given _test.v file is, when v is given -stats argument
// The methods defined here are called back by the test program's
// main function, so that customizing the look & feel of the results
// is easier, done in normal V code, instead of in embedded C ...

const inner_indent = '     '

struct BenchedTests {
mut:
	bench          benchmark.Benchmark
	oks            i64
	fails          i64
	test_suit_file string
	step_func_name string
}

// ///////////////////////////////////////////////////////////////////
// Called at the start of the test program produced by `v -stats file_test.v`
fn start_testing(total_number_of_tests int, vfilename string) BenchedTests {
	println('Running tests in: $vfilename')
	mut benched_tests_res := BenchedTests{
		bench: benchmark.new_benchmark()
		test_suit_file: vfilename
	}
	benched_tests_res.bench.set_total_expected_steps(total_number_of_tests)
	return benched_tests_res
}

// Called before each test_ function, defined in file_test.v
fn (mut b BenchedTests) testing_step_start(stepfunc string) {
	b.step_func_name = stepfunc.replace_each(['main__', '', '__', '.'])
	b.oks = C.g_test_oks
	b.fails = C.g_test_fails
	b.bench.step()
}

fn (mut b BenchedTests) print_step_message(label string, msg string, step_duration time.Duration) {
	measure_msg := b.bench.step_message_with_label_and_duration(label, msg, step_duration)
	println(inner_indent + measure_msg + b.step_func_name + '()')
}

// Called after each test_ function, defined in file_test.v
fn (mut b BenchedTests) testing_step_end() {
	step_duration := b.bench.step_timer.elapsed()
	ok_diff := C.g_test_oks - b.oks
	fail_diff := C.g_test_fails - b.fails
	// ////////////////////////////////////////////////////////////////
	if ok_diff == 0 && fail_diff == 0 {
		b.bench.neither_fail_nor_ok()
		b.print_step_message(benchmark.b_ok, ' --NO-- asserts | ', step_duration)
		return
	}
	// ////////////////////////////////////////////////////////////////
	if ok_diff > 0 {
		b.bench.ok_many(ok_diff)
	}
	if fail_diff > 0 {
		b.bench.fail_many(fail_diff)
	}
	// ////////////////////////////////////////////////////////////////
	if ok_diff > 0 && fail_diff == 0 {
		b.print_step_message(benchmark.b_ok, nasserts(ok_diff), step_duration)
		return
	}
	if fail_diff > 0 {
		b.print_step_message(benchmark.b_fail, nasserts(fail_diff), step_duration)
		return
	}
}

// Called at the end of the test program produced by `v -stats file_test.v`
fn (mut b BenchedTests) end_testing() {
	b.bench.stop()
	println(inner_indent + b.bench.total_message('running V tests in "' +
		os.file_name(b.test_suit_file) + '"'))
}

// ///////////////////////////////////////////////////////////////////
fn nasserts(n i64) string {
	if n == 1 {
		return '${n:7} assert  | '
	}
	return '${n:7} asserts | '
}
