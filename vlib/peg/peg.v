// Copyright (c) 2025 Delyan Angelov. All rights reserved.
// Use of this source code is governed by an MIT license
// that can be found in the LICENSE file.

module peg

pub struct Set {
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

pub type FnCondition = fn (input string, start int) bool

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
	| Choice
	| Seq
	| Between
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
	mut charset := []u8{}
	for r in ss {
		b1 := r[0]
		b2 := r[1]
		for b in b1 .. (b2 + 1) {
			charset << b
		}
	}
	return Set{
		bytes: charset
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

// One big difference between PEGs, and more traditional parser generators, like
// the ones used by YACC and Bison, is the ordered choice operator. Its ordered
// property, means that all PEGs are *deterministic* - if they match a string,
// they will match it in *one way* only.
// This also means, that there is a direct correspondence between a PEG, and a
// parser. This is very convenient, when writing PEGs, as the specification and
// the parser can often be *one and the same* .
// Traditional parser generators in contrast are non-deterministic, and thus you
// need to specify additional rules to resolve ambiguities.
pub fn choice(exprs ...PEG) PEG {
	return Choice{
		exprs: exprs
	}
}

pub fn any_(expr PEG) PEG {
	return at_least(0, expr)
}

pub fn some(expr PEG) PEG {
	return at_least(1, expr)
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

pub struct MatchContext {
}

pub fn (mut ctx MatchContext) reset() {}

pub fn (mut ctx MatchContext) match(expr PEG, input string, spos int) ?int {
	if spos < 0 {
		return none
	}
	b := spos
	match expr {
		int {
			if expr >= 0 {
				// check if there are at least `expr` characters left in the input:
				if b + expr <= input.len {
					return expr
				}
			} else {
				// check if there are NOT |expr| characters left in the input, but do not advance:
				plen := -expr
				if b + plen > input.len {
					return 0
				}
			}
		}
		string {
			if b < input.len && input[b..].starts_with(expr) {
				return expr.len
			}
		}
		Set {
			if b < input.len && input[b] in expr.bytes {
				return 1
			}
		}
		bool {
			// true always matches. Does not advance any characters. Epsilon in NFA.
			// false never matches. Does not advance any characters. Equivalent to peg.not(peg.true()) .
			return if expr { 0 } else { none }
		}
		rune {
			if expr < 127 && b < input.len && input[b] == expr {
				return 1
			}
			partial := expr.str()
			if b + partial.len <= input.len && input[b..].starts_with(partial) {
				return partial.len
			}
		}
		Not {
			ctx.match(expr.expr, input, b) or { return 0 }
		}
		Choice {
			for e in expr.exprs {
				r := ctx.match(e, input, b) or { continue }
				return r
			}
		}
		Seq {
			mut total := 0
			mut start := b
			for e in expr.exprs {
				total += ctx.match(e, input, start) or { return none }
				start = b + total
			}
			return total
		}
		Between {
			mut c := 0
			mut total := 0
			mut start := b
			for c <= expr.max {
				total += ctx.match(expr.expr, input, start) or {
					return if c >= expr.min && c <= expr.max { total } else { none }
				}
				c++
				start = b + total
			}
		}
		AtLeast {
			mut c := 0
			mut total := 0
			mut start := b
			for {
				total += ctx.match(expr.expr, input, start) or {
					return if c >= expr.n { total } else { none }
				}
				c++
				start = b + total
			}
		}
		AtMost {
			mut c := 0
			mut total := 0
			mut start := b
			for {
				total += ctx.match(expr.expr, input, start) or {
					return if c <= expr.n { total } else { none }
				}
				c++
				start = b + total
			}
		}
		Repeat {
			mut total := 0
			mut start := b
			for c := 0; true; c++ {
				total += ctx.match(expr.expr, input, start) or {
					return if c == expr.n { total } else { none }
				}
				start = b + total
			}
		}
		If {
			if expr.cond(input, b) {
				return ctx.match(expr.expr, input, b)
			}
		}
		IfNot {
			if !expr.cond(input, b) {
				return ctx.match(expr.expr, input, b)
			}
		}
		Look {
			beoffset := b + expr.offset
			if beoffset < input.len {
				_ := ctx.match(expr.expr, input, beoffset) or { return none }
				return 0
			}
			return none
		}
		To, Thru, BackMatch, SubWindow, Split {}
		// else {}
	}
	return none
}

@[params]
pub struct MatchParams {
pub:
	start int
}

pub fn match(expr PEG, input string, params MatchParams) ?int {
	mut ctx := MatchContext{}
	return ctx.match(expr, input, params.start)
}
