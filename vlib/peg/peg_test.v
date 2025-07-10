// Copyright (c) 2025 Delyan Angelov. All rights reserved.
// Use of this source code is governed by an MIT license
// that can be found in the LICENSE file.
import peg

fn test_match_prefix_string() {
	assert peg.match('hello', 'hello')? == 5
	assert peg.match('he', 'hello')? == 2
	assert peg.match('hello', 'hi') == none
}

fn test_match_len() {
	assert peg.match(1, 'hi')? == 1
	assert peg.match(2, 'hi')? == 2
	assert peg.match(1, '') == none
	assert peg.match(0, '')? == 0
	assert peg.match(0, 'abc')? == 0
}

fn test_match_range() {
	assert peg.match(peg.range('AZ'), 'F')? == 1
	assert peg.match(peg.range('AZ'), 'A')? == 1
	assert peg.match(peg.range('AZ'), 'Z')? == 1
	assert peg.match(peg.range('AZ'), '-') == none
	assert peg.match(peg.range('AZ'), 'f') == none
	assert peg.match(peg.range('AZ'), 'a') == none
	assert peg.match(peg.range('AZ'), 'z') == none
	assert peg.match(peg.range('az'), 'f')? == 1
	assert peg.match(peg.range('az'), 'a')? == 1
	assert peg.match(peg.range('az'), 'z')? == 1
}

fn test_match_set() {
	assert peg.match(peg.set('AZ'), 'F') == none
	assert peg.match(peg.set('AZ'), 'A')? == 1
	assert peg.match(peg.set('AZ'), 'Z')? == 1
	assert peg.match(peg.set('ABCDEFGHIJKLMNOPQRSTUVWXYZ'), 'F')? == 1
}

fn test_match_seq() {
	assert peg.match(peg.seq('ab', 'c', 'd'), 'abcd')? == 4
	assert peg.match(peg.seq('ab', 'c', 'd'), 'zabcd') == none
	assert peg.match(peg.seq('ab', 'c', 'd'), 'abc') == none
	assert peg.match(peg.seq('abc'), 'abc')? == 3
}

fn test_match_choice() {
	assert peg.match(peg.choice('abcd', 'ab', 'd'), 'abcd')? == 4
	assert peg.match(peg.choice('abcd', 'ab', 'd'), 'ab')? == 2
	assert peg.match(peg.choice('abcd', 'ab', 'd'), 'dzzz')? == 1
}
