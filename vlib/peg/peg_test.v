// Copyright (c) 2025 Delyan Angelov. All rights reserved.
// Use of this source code is governed by an MIT license
// that can be found in the LICENSE file.
import peg

fn test_match() {
	assert peg.match('hello', 'hello')? == []
	assert peg.match('hello', 'hi') == none
	assert peg.match(1, 'hi')? == []
	assert peg.match(1, '') == none
	assert peg.match(peg.range('AZ'), 'F')? == []
	assert peg.match(peg.range('AZ'), '-') == none
	assert peg.match(peg.set('AZ'), 'F') == none
	assert peg.match(peg.set('ABCDEFGHIJKLMNOPQRSTUVWXYZ'), 'F')? == []
}
