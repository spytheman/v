// Copyright (c) 2025 Delyan Angelov. All rights reserved.
// Use of this source code is governed by an MIT license
// that can be found in the LICENSE file.
import peg

fn test_match_prefix_string() {
	assert peg.match('hello', 'hello')? == 5
	assert peg.match('he', 'hello')? == 2
	assert peg.match('hello', 'hi') == none
	assert peg.match('e', 'hello') == none
	assert peg.match('e', 'hello', start: -1) == none
	assert peg.match('e', 'hello', start: 0) == none
	assert peg.match('e', 'hello', start: 1)? == 1
	assert peg.match('e', 'hello', start: 2) == none
	assert peg.match('e', 'hello', start: 3) == none
	assert peg.match('e', 'hello', start: 4) == none
	assert peg.match('e', 'hello', start: 5) == none
	assert peg.match('e', 'hello', start: 6) == none
	assert peg.match('ll', 'hello', start: 0) == none
	assert peg.match('ll', 'hello', start: 1) == none
	assert peg.match('ll', 'hello', start: 2)? == 2
	assert peg.match('ll', 'hello', start: 3) == none
}

fn test_match_len() {
	assert peg.match(1, 'hi')? == 1
	assert peg.match(2, 'hi')? == 2
	assert peg.match(1, '') == none
	assert peg.match(0, '')? == 0
	assert peg.match(0, 'abc')? == 0
	//
	assert peg.match(-1, '')? == 0
	assert peg.match(-2, '')? == 0
	assert peg.match(-1, 'cat') == none
	assert peg.match(-2, 'o')? == 0
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

fn test_match_date() {
	digit := peg.range('09')
	day := peg.seq(digit, digit)
	month := day
	year := peg.seq(digit, digit, digit, digit)
	iso_date := peg.seq(year, '-', month, '-', day)
	assert peg.match(iso_date, '2025-07-10')? == 10
	assert peg.match(iso_date, '201-07-10') == none
}

fn test_match_date_with_digit_represented_with_a_charset() {
	digit := peg.set('0123456789')
	day := peg.seq(digit, digit)
	month := day
	year := peg.seq(digit, digit, digit, digit)
	iso_date := peg.seq(year, '-', month, '-', day)
	assert peg.match(iso_date, '2025-07-10')? == 10
	assert peg.match(iso_date, '201-07-10') == none
}

fn test_match_date_with_digit_represented_with_d_and_repeat() {
	d2 := peg.repeat(2, peg.d)
	iso_date := peg.seq(peg.repeat(4, peg.d), '-', d2, '-', d2)
	assert peg.match(iso_date, '2025-07-10')? == 10
	assert peg.match(iso_date, '201-07-10') == none
}
