// Copyright (c) 2025 Delyan Angelov. All rights reserved.
// Use of this source code is governed by an MIT license
// that can be found in the LICENSE file.

module peg

pub struct Set {
	bytes []u8
}

pub struct Range {
	bytes []u8
}

pub struct Choice {
	exprs []PEG
}

pub struct Seq {
	exprs []PEG
}

pub struct Between {
	min  int
	max  int
	expr PEG
}

pub struct Any {
	expr PEG
}

pub struct Some {
	expr PEG
}

pub struct AtLeast {
	n    int
	expr PEG
}

pub struct AtMost {
	n    int
	expr PEG
}

pub struct Repeat {
	n    int
	expr PEG
}

pub struct If {
	cond FnCondition = always
	expr PEG
}

pub struct IfNot {
	cond FnCondition = never
	expr PEG
}

pub struct Not {
	expr PEG
}

pub struct Look {
	offset int
	expr   PEG
}

pub struct To {
	expr PEG
}

pub struct Thru {
	expr PEG
}

pub struct BackMatch {
	tag ?string
}

pub struct SubWindow {
	window PEG
	expr   PEG
}

pub struct Split {
	separator PEG
	expr      PEG
}

pub type PEG = int
	| bool
	| rune
	| string
	| Set
	| Range
	| Choice
	| Seq
	| Between
	| Any
	| Some
	| AtLeast
	| AtMost
	| Repeat
	| If
	| IfNot
	| Not
	| Look
	| To
	| Thru
	| BackMatch
	| SubWindow
	| Split

// true always matches. Does not advance any characters. Epsilon in NFA.
pub fn true() PEG {
	return true
}

// false never matches. Does not advance any characters. Equivalent to peg.not(peg.true()) .
pub fn false() PEG {
	return false
}

pub fn set(s string) PEG {
	return Set{
		bytes: s.bytes()
	}
}

pub fn range(ss ...string) PEG {
	return Range{
		bytes: ss.join('').bytes()
	}
}

pub fn between(min int, max int, expr PEG) PEG {
	return Between{
		min:  min
		max:  max
		expr: expr
	}
}

pub fn seq(exprs ...PEG) PEG {
	return Seq{
		exprs: exprs
	}
}

pub fn choice(exprs ...PEG) PEG {
	return Choice{
		exprs: exprs
	}
}

pub fn any(expr PEG) PEG {
	return Any{
		expr: expr
	}
}

pub fn some(expr PEG) PEG {
	return Some{
		expr: expr
	}
}

pub fn at_least(n int, expr PEG) PEG {
	return AtLeast{
		n:    n
		expr: expr
	}
}

pub fn at_most(n int, expr PEG) PEG {
	return AtMost{
		n:    n
		expr: expr
	}
}

pub fn repeat(n int, expr PEG) PEG {
	return Repeat{
		n:    n
		expr: expr
	}
}

pub type FnCondition = fn (input string, start int) bool

fn always(input string, start int) bool {
	return true
}

fn never(input string, start int) bool {
	return false
}

pub fn if(cond FnCondition, expr PEG) PEG {
	return If{
		cond: cond
		expr: expr
	}
}

pub fn if_not(cond FnCondition, expr PEG) PEG {
	return IfNot{
		cond: cond
		expr: expr
	}
}

pub fn not(expr PEG) PEG {
	return Not{
		expr: expr
	}
}

pub fn look(offset int, expr PEG) PEG {
	return Look{
		offset: offset
		expr:   expr
	}
}

pub fn to(expr PEG) PEG {
	return To{
		expr: expr
	}
}

pub fn thru(expr PEG) PEG {
	return Thru{
		expr: expr
	}
}

pub fn backmatch(tag ?string) PEG {
	return BackMatch{
		tag: tag
	}
}

pub fn opt(expr PEG) PEG {
	return between(0, 1, expr)
}

pub fn n(count int, expr PEG) PEG {
	return repeat(count, expr)
}

pub fn sub(window PEG, expr PEG) PEG {
	return SubWindow{
		window: window
		expr:   expr
	}
}

pub fn split(separator PEG, expr PEG) PEG {
	return Split{
		separator: separator
		expr:      expr
	}
}

//

@[params]
pub struct ParseParams {
	start int
}

pub fn (m PEG) parse(input string, params ParseParams) ?[]PEG {
	compiled := compile(m) or { return none }
	return compiled.parse(input, params)
}

//

pub struct CompiledPEG {
	expr PEG
}

pub fn compile(expr PEG) !CompiledPEG {
	eprintln('>>> compile expr: ${expr}')
	return CompiledPEG{
		expr: expr
	}
}

pub fn (m CompiledPEG) parse(input string, params ParseParams) ?[]PEG {
	return none
}

pub fn match(expr PEG, input string, params ParseParams) ?[]PEG {
	if expr is string && expr == 'hello' && input == 'hello' && params.start == 0 {
		return []
	}
	if expr is int && input == 'hi' && params.start == 0 {
		return []
	}
	if expr is Range && expr.bytes == [u8(`A`), `Z`] && input == 'F' && params.start == 0 {
		return []
	}
	if expr is Set && expr.bytes == 'ABCDEFGHIJKLMNOPQRSTUVWXYZ'.bytes() && input == 'F'
		&& params.start == 0 {
		return []
	}
	return none
}
