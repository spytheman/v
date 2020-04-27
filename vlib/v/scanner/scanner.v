// Copyright (c) 2019-2020 Alexander Medvednikov. All rights reserved.
// Use of this source code is governed by an MIT license
// that can be found in the LICENSE file.
module scanner

import os
import v.token
import v.pref
import v.util

const (
	single_quote = `\'`
	double_quote = `"`
// char used as number separator
	num_sep = `_`
)

pub struct Scanner {
mut:
	file_path                   string
	text                        string
	pos                         int
	line_nr                     int
	last_nl_pos                 int // for calculating column
	is_inside_string            bool
	is_inter_start              bool // for hacky string interpolation TODO simplify
	is_inter_end                bool
	is_debug                    bool
	line_comment                string
	// prev_tok                 TokenKind
	is_started                  bool
	fn_name                     string // needed for @FN
	is_print_line_on_error      bool
	is_print_colored_error      bool
	is_print_rel_paths_on_error bool
	quote                       byte // which quote is used to denote current string: ' or "
	line_ends                   []int // the positions of source lines ends   (i.e. \n signs)
	nr_lines                    int // total number of lines in the source file that were scanned
	is_vh                       bool // Keep newlines
	is_fmt                      bool // Used only for skipping ${} in strings, since we need literal
	// string values when generating formatted code.
	comments_mode               CommentsMode
}

pub enum CommentsMode {
	skip_comments
	parse_comments
}

// new scanner from file.
pub fn new_scanner_file(file_path string, comments_mode CommentsMode) &Scanner {
	if !os.exists(file_path) {
		verror("$file_path doesn't exist")
	}
	raw_text := util.read_file( file_path ) or {
		verror(err)
		return 0
	}
	mut s := new_scanner(raw_text, comments_mode) // .skip_comments)
	// s.init_fmt()
	s.file_path = file_path
	return s
}

// new scanner from string.
pub fn new_scanner(text string, comments_mode CommentsMode) &Scanner {
	s := &Scanner{
		text: text
		is_print_line_on_error: true
		is_print_colored_error: true
		is_print_rel_paths_on_error: true
		is_fmt: util.is_fmt()
		comments_mode: comments_mode
	}
	return s
}

pub fn (s &Scanner) add_fn_main_and_rescan() {
	s.text = 'fn main() {' + s.text + '}'
	s.is_started = false
	s.pos = 0
	s.line_nr = 0
	s.last_nl_pos = 0
}

fn (s &Scanner) new_token(tok_kind token.Kind, lit string, len int) token.Token {
	return token.Token{
		kind: tok_kind
		lit: lit
		line_nr: s.line_nr + 1
		pos: s.pos - len + 1
		len: len
	}
}

fn (s mut Scanner) ident_name() string {
	start := s.pos
	s.pos++
	for s.pos < s.text.len && (util.is_name_char(s.text.str[s.pos]) || s.text.str[s.pos].is_digit()) {
		s.pos++
	}
	name := s.text[start..s.pos]
	s.pos--
	return name
}

fn filter_num_sep(txt byteptr, start int, end int) string {
	unsafe{
		mut b := malloc(end - start + 1) // add a byte for the endstring 0
		mut i := start
		mut i1 := 0
		for i < end {
			if txt[i] != num_sep {
				b[i1] = txt[i]
				i1++
			}
			i++
		}
		b[i1] = 0 // C string compatibility
		return string(b,i1)
	}
}

fn (s mut Scanner) ident_bin_number() string {
	mut has_wrong_digit := false
	mut first_wrong_digit := `\0`
	start_pos := s.pos
	s.pos += 2 // skip '0b'
	for s.pos < s.text.len {
		c := s.text.str[s.pos]
		if !c.is_bin_digit() && c != num_sep {
			if (!c.is_digit() && !c.is_letter()) || s.is_inside_string {
				break
			}
			else if !has_wrong_digit {
				has_wrong_digit = true
				first_wrong_digit = c
			}
		}
		s.pos++
	}
	if start_pos + 2 == s.pos {
		s.error('number part of this binary is not provided')
	}
	else if has_wrong_digit {
		s.error('this binary number has unsuitable digit `${first_wrong_digit.str()}`')
	}
	number := filter_num_sep(s.text.str, start_pos, s.pos)
	s.pos--
	return number
}

fn (s mut Scanner) ident_hex_number() string {
	mut has_wrong_digit := false
	mut first_wrong_digit := `\0`
	start_pos := s.pos
	s.pos += 2 // skip '0x'
	for s.pos < s.text.len {
		c := s.text.str[s.pos]
		if !c.is_hex_digit() && c != num_sep {
			if !c.is_letter() || s.is_inside_string {
				break
			}
			else if !has_wrong_digit {
				has_wrong_digit = true
				first_wrong_digit = c
			}
		}
		s.pos++
	}
	if start_pos + 2 == s.pos {
		s.error('number part of this hexadecimal is not provided')
	}
	else if has_wrong_digit {
		s.error('this hexadecimal number has unsuitable digit `${first_wrong_digit.str()}`')
	}
	number := filter_num_sep(s.text.str, start_pos, s.pos)
	s.pos--
	return number
}

fn (s mut Scanner) ident_oct_number() string {
	mut has_wrong_digit := false
	mut first_wrong_digit := `\0`
	start_pos := s.pos
	s.pos += 2 // skip '0o'
	for s.pos < s.text.len {
		c := s.text.str[s.pos]
		if !c.is_oct_digit() && c != num_sep {
			if (!c.is_digit() && !c.is_letter()) || s.is_inside_string {
				break
			}
			else if !has_wrong_digit {
				has_wrong_digit = true
				first_wrong_digit = c
			}
		}
		s.pos++
	}
	if start_pos + 2 == s.pos {
		s.error('number part of this octal is not provided')
	}
	else if has_wrong_digit {
		s.error('this octal number has unsuitable digit `${first_wrong_digit.str()}`')
	}
	number := filter_num_sep(s.text.str, start_pos, s.pos)
	s.pos--
	return number
}

fn (s mut Scanner) ident_dec_number() string {
	mut has_wrong_digit := false
	mut first_wrong_digit := `\0`
	start_pos := s.pos
	// scan integer part
	for s.pos < s.text.len {
		c := s.text.str[s.pos]
		if !c.is_digit() && c != num_sep {
			if !c.is_letter() || c in [`e`, `E`] || s.is_inside_string {
				break
			}
			else if !has_wrong_digit {
				has_wrong_digit = true
				first_wrong_digit = c
			}
		}
		s.pos++
	}
	mut call_method := false  // true for, e.g., 5.str(), 5.5.str(), 5e5.str()
	mut is_range := false  // true for, e.g., 5..10
	mut is_float_without_fraction := false  // true for, e.g. 5.
	// scan fractional part
	if s.pos < s.text.len && s.text.str[s.pos] == `.` {
		s.pos++
		if s.pos < s.text.len {
			// 5.5, 5.5.str()
			if s.text.str[s.pos].is_digit() {
				for s.pos < s.text.len {
					c := s.text.str[s.pos]
					if !c.is_digit() {
						if !c.is_letter() || c in [`e`, `E`] || s.is_inside_string {
							// 5.5.str()
							if c == `.` && s.pos + 1 < s.text.len && s.text.str[s.pos + 1].is_letter() {
								call_method = true
							}
							break
						}
						else if !has_wrong_digit {
							has_wrong_digit = true
							first_wrong_digit = c
						}
					}
					s.pos++
				}
			}
			else if s.text.str[s.pos] == `.` {
			// 5.. (a range)
				is_range = true
				s.pos--
			}
			else if s.text.str[s.pos] in [`e`, `E`] {
			// 5.e5
			}
			else if s.text.str[s.pos].is_letter() {
			// 5.str()
				call_method = true
				s.pos--
			}
			else if s.text.str[s.pos] != `)` {
			// 5.
				is_float_without_fraction = true
				s.pos--
			}
		}
	}
	// scan exponential part
	mut has_exp := false
	if s.pos < s.text.len && s.text.str[s.pos] in [`e`, `E`] {
		has_exp = true
		s.pos++
		if s.pos < s.text.len && s.text.str[s.pos] in [`-`, `+`] {
			s.pos++
		}
		for s.pos < s.text.len {
			c := s.text.str[s.pos]
			if !c.is_digit() {
				if !c.is_letter() || s.is_inside_string {
					// 5e5.str()
					if c == `.` && s.pos + 1 < s.text.len && s.text.str[s.pos + 1].is_letter() {
						call_method = true
					}
					break
				}
				else if !has_wrong_digit {
					has_wrong_digit = true
					first_wrong_digit = c
				}
			}
			s.pos++
		}
	}
	if has_wrong_digit {
	// error check: wrong digit
		s.error('this number has unsuitable digit `${first_wrong_digit.str()}`')
	}
	else if s.text.str[s.pos - 1] in [`e`, `E`] {
	// error check: 5e
		s.error('exponent has no digits')
	}
	else if s.pos < s.text.len && s.text.str[s.pos] == `.` && !is_range && !is_float_without_fraction && !call_method {
	// error check: 1.23.4, 123.e+3.4
		if has_exp {
			s.error('exponential part should be integer')
		}
		else {
			s.error('too many decimal points in number')
		}
	}
	number := filter_num_sep(s.text.str, start_pos, s.pos)
	s.pos--
	return number
}

fn (s mut Scanner) ident_number() string {
	if s.expect('0b', s.pos) {
		return s.ident_bin_number()
	}
	else if s.expect('0x', s.pos) {
		return s.ident_hex_number()
	}
	else if s.expect('0o', s.pos) {
		return s.ident_oct_number()
	}
	else {
		return s.ident_dec_number()
	}
}

fn (s mut Scanner) skip_whitespace() {
	// NB: this method is a hot path
	stlen := s.text.len
	// if s.is_vh { println('vh') return }
	for s.pos < stlen {
		ch := s.text.str[s.pos]
		if ch == ` ` {
			s.pos++
			continue
		}
		if ch == `\t` {
			s.pos++
			continue
		}
		//
		if ch == `\r` || ch == `\n` {
			if s.is_vh {
				return
			}
			// Count \r\n as one line
			if !s.expect('\r\n', s.pos - 1) {
				s.inc_line_number()
			}
			s.pos++
			continue
		}
		if ch in [`\v`, `\f`, 0x85, 0xa0] {
			s.pos++
			continue
		}
		break
	}
}

fn (s mut Scanner) end_of_file() token.Token {
	s.pos = s.text.len
	s.inc_line_number()
	return s.new_token(.eof, '', 1)
}

pub fn (s mut Scanner) scan() token.Token {
	// if s.comments_mode == .parse_comments {
	// println('\nscan()')
	// }
	// if s.line_comment != '' {
	// s.fgenln('// LC "$s.line_comment"')
	// s.line_comment = ''
	// }
	if s.is_started {
		s.pos++
	}
	s.is_started = true
	if s.pos >= s.text.len {
		return s.end_of_file()
	}
	if !s.is_inside_string {
		s.skip_whitespace()
	}
	// End of $var, start next string
	if s.is_inter_end {
		if s.text.str[s.pos] == s.quote {
			s.is_inter_end = false
			return s.new_token(.string, '', 1)
		}
		s.is_inter_end = false
		ident_string := s.ident_string()
		return s.new_token(.string, ident_string, ident_string.len + 2) // + two quotes
	}
	s.skip_whitespace()
	// end of file
	if s.pos >= s.text.len {
		return s.end_of_file()
	}
	// handle each char
	c := s.text.str[s.pos]
	nextc := if s.pos + 1 < s.text.len { s.text.str[s.pos + 1] } else { `\0` }

	// name or keyword
	if util.is_name_char(c) {
		name := s.ident_name()
		// tmp hack to detect . in ${}
		// Check if not .eof to prevent panic
		next_char := if s.pos + 1 < s.text.len { s.text.str[s.pos + 1] } else { `\0` }
		if token.is_key(name) {
			return s.new_token(token.key_to_token(name), name, name.len)
		}
		// 'asdf $b' => "b" is the last name in the string, dont start parsing string
		// at the next ', skip it
		if s.is_inside_string {
			if next_char == s.quote {
				s.is_inter_end = true
				s.is_inter_start = false
				s.is_inside_string = false
			}
		}
		// end of `$expr`
		// allow `'$a.b'` and `'$a.c()'`
		if s.is_inter_start && next_char != `.` && next_char != `(` {
			s.is_inter_end = true
			s.is_inter_start = false
		}
		if s.pos == 0 && next_char == ` ` {
			// If a single letter name at the start of the file, increment
			// Otherwise the scanner would be stuck at s.pos = 0
			s.pos++
		}
		return s.new_token(.name, name, name.len)
	}
	else if c.is_digit() || (c == `.` && nextc.is_digit()) {
	// `123`, `.123`
		if !s.is_inside_string {
			// In C ints with `0` prefix are octal (in V they're decimal), so discarding heading zeros is needed.
			mut start_pos := s.pos
			for start_pos < s.text.len && s.text.str[start_pos] == `0` {
				start_pos++
			}
			mut prefix_zero_num := start_pos - s.pos // how many prefix zeros should be jumped
			// for 0b, 0o, 0x the heading zero shouldn't be jumped
			if start_pos == s.text.len || (c == `0` && !s.text.str[start_pos].is_digit()) {
				prefix_zero_num--
			}
			s.pos += prefix_zero_num // jump these zeros
		}
		num := s.ident_number()
		return s.new_token(.number, num, num.len)
	}
	// Handle `'$fn()'`
	if c == `)` && s.is_inter_start {
		s.is_inter_end = true
		s.is_inter_start = false
		next_char := if s.pos + 1 < s.text.len { s.text.str[s.pos + 1] } else { `\0` }
		if next_char == s.quote {
			s.is_inside_string = false
		}
		return s.new_token(.rpar, '', 1)
	}
	// all other tokens
	match c {
		`+` {
			if nextc == `+` {
				s.pos++
				return s.new_token(.inc, '', 2)
			}
			else if nextc == `=` {
				s.pos++
				return s.new_token(.plus_assign, '', 2)
			}
			return s.new_token(.plus, '', 1)
		}
		`-` {
			if nextc == `-` {
				s.pos++
				return s.new_token(.dec, '', 2)
			}
			else if nextc == `=` {
				s.pos++
				return s.new_token(.minus_assign, '', 2)
			}
			return s.new_token(.minus, '', 1)
		}
		`*` {
			if nextc == `=` {
				s.pos++
				return s.new_token(.mult_assign, '', 2)
			}
			return s.new_token(.mul, '', 1)
		}
		`^` {
			if nextc == `=` {
				s.pos++
				return s.new_token(.xor_assign, '', 2)
			}
			return s.new_token(.xor, '', 1)
		}
		`%` {
			if nextc == `=` {
				s.pos++
				return s.new_token(.mod_assign, '', 2)
			}
			return s.new_token(.mod, '', 1)
		}
		`?` {
			return s.new_token(.question, '', 1)
		}
		single_quote, double_quote {
			ident_string := s.ident_string()
			return s.new_token(.string, ident_string, ident_string.len + 2) // + two quotes
		}
		`\`` {
			// ` // apostrophe balance comment. do not remove
			ident_char := s.ident_char()
			return s.new_token(.chartoken, ident_char, ident_char.len + 2) // + two quotes
		}
		`(` {
			return s.new_token(.lpar, '', 1)
		}
		`)` {
			return s.new_token(.rpar, '', 1)
		}
		`[` {
			return s.new_token(.lsbr, '', 1)
		}
		`]` {
			return s.new_token(.rsbr, '', 1)
		}
		`{` {
			// Skip { in `${` in strings
			if s.is_inside_string {
				return s.scan()
			}
			return s.new_token(.lcbr, '', 1)
		}
		`$` {
			if s.is_inside_string {
				return s.new_token(.str_dollar, '', 1)
			}
			else {
				return s.new_token(.dollar, '', 1)
			}
		}
		`}` {
			// s = `hello $name !`
			// s = `hello ${name} !`
			if s.is_inside_string {
				s.pos++
				if s.text.str[s.pos] == s.quote {
					s.is_inside_string = false
					return s.new_token(.string, '', 1)
				}
				ident_string := s.ident_string()
				return s.new_token(.string, ident_string, ident_string.len + 2) // + two quotes
			}
			else {
				return s.new_token(.rcbr, '', 1)
			}
		}
		`&` {
			if nextc == `=` {
				s.pos++
				return s.new_token(.and_assign, '', 2)
			}
			if nextc == `&` {
				s.pos++
				return s.new_token(.and, '', 2)
			}
			return s.new_token(.amp, '', 1)
		}
		`|` {
			if nextc == `|` {
				s.pos++
				return s.new_token(.logical_or, '', 2)
			}
			if nextc == `=` {
				s.pos++
				return s.new_token(.or_assign, '', 2)
			}
			return s.new_token(.pipe, '', 1)
		}
		`,` {
			return s.new_token(.comma, '', 1)
		}
		`@` {
			s.pos++
			name := s.ident_name()
			// @FN => will be substituted with the name of the current V function
			// @VEXE => will be substituted with the path to the V compiler
			// @FILE => will be substituted with the path of the V source file
			// @LINE => will be substituted with the V line number where it appears (as a string).
			// @COLUMN => will be substituted with the column where it appears (as a string).
			// @VHASH  => will be substituted with the shortened commit hash of the V compiler (as a string).
			// This allows things like this:
			// println( 'file: ' + @FILE + ' | line: ' + @LINE + ' | fn: ' + @FN)
			// ... which is useful while debugging/tracing
			if name == 'FN' {
				return s.new_token(.string, s.fn_name, 3)
			}
			if name == 'VEXE' {
				vexe := pref.vexe_path()
				return s.new_token(.string, util.cescaped_path(vexe), 5)
			}
			if name == 'FILE' {
				return s.new_token(.string, util.cescaped_path(os.real_path(s.file_path)), 5)
			}
			if name == 'LINE' {
				return s.new_token(.string, (s.line_nr + 1).str(), 5)
			}
			if name == 'COLUMN' {
				return s.new_token(.string, s.current_column().str(), 7)
			}
			if name == 'VHASH' {
				return s.new_token(.string, util.vhash(), 6)
			}
			if !token.is_key(name) {
				s.error('@ must be used before keywords (e.g. `@type string`)')
			}
			return s.new_token(.name, name, name.len)
		}
		/*
	case `\r`:
		if nextc == `\n` {
			s.pos++
			s.last_nl_pos = s.pos
			return s.new_token(.nl, '')
		}
	 }
	case `\n`:
		s.last_nl_pos = s.pos
		return s.new_token(.nl, '')
	 }
	*/

		`.` {
			if nextc == `.` {
				s.pos++
				if s.text.str[s.pos + 1] == `.` {
					s.pos++
					return s.new_token(.ellipsis, '', 3)
				}
				return s.new_token(.dotdot, '', 2)
			}
			return s.new_token(.dot, '', 1)
		}
		`#` {
			start := s.pos + 1
			s.ignore_line()
			if nextc == `!` {
				// treat shebang line (#!) as a comment
				s.line_comment = s.text[start + 1..s.pos].trim_space()
				// s.fgenln('// shebang line "$s.line_comment"')
				return s.scan()
			}
			hash := s.text[start..s.pos].trim_space()
			return s.new_token(.hash, hash, hash.len)
		}
		`>` {
			if nextc == `=` {
				s.pos++
				return s.new_token(.ge, '', 2)
			}
			else if nextc == `>` {
				if s.pos + 2 < s.text.len && s.text.str[s.pos + 2] == `=` {
					s.pos += 2
					return s.new_token(.right_shift_assign, '', 3)
				}
				s.pos++
				return s.new_token(.right_shift, '', 2)
			}
			else {
				return s.new_token(.gt, '', 1)
			}
		}
		0xE2 {
			if nextc == 0x89 && s.text.str[s.pos + 2] == 0xA0 {
			// case `≠`:
				s.pos += 2
				return s.new_token(.ne, '', 3)
			}
			else if nextc == 0x89 && s.text.str[s.pos + 2] == 0xBD {
				s.pos += 2
				return s.new_token(.le, '', 3)
			}
			else if nextc == 0xA9 && s.text.str[s.pos + 2] == 0xBE {
				s.pos += 2
				return s.new_token(.ge, '', 3)
			}
		}
		`<` {
			if nextc == `=` {
				s.pos++
				return s.new_token(.le, '', 2)
			}
			else if nextc == `<` {
				if s.pos + 2 < s.text.len && s.text.str[s.pos + 2] == `=` {
					s.pos += 2
					return s.new_token(.left_shift_assign, '', 3)
				}
				s.pos++
				return s.new_token(.left_shift, '', 2)
			}
			else {
				return s.new_token(.lt, '', 1)
			}
		}
		`=` {
			if nextc == `=` {
				s.pos++
				return s.new_token(.eq, '', 2)
			}
			else if nextc == `>` {
				s.pos++
				return s.new_token(.arrow, '', 2)
			}
			else {
				return s.new_token(.assign, '', 1)
			}
		}
		`:` {
			if nextc == `=` {
				s.pos++
				return s.new_token(.decl_assign, '', 2)
			}
			else {
				return s.new_token(.colon, '', 1)
			}
		}
		`;` {
			return s.new_token(.semicolon, '', 1)
		}
		`!` {
			if nextc == `=` {
				s.pos++
				return s.new_token(.ne, '', 2)
			}
			else if nextc == `i` && s.text.str[s.pos+2] == `n` && s.text.str[s.pos+3].is_space() {
				s.pos += 2
				return s.new_token(.not_in, '', 3)
			}
			else {
				return s.new_token(.not, '', 1)
			}
		}
		`~` {
			return s.new_token(.bit_not, '', 1)
		}
		`/` {
			if nextc == `=` {
				s.pos++
				return s.new_token(.div_assign, '', 2)
			}
			if nextc == `/` {
				start := s.pos + 1
				s.ignore_line()
				s.line_comment = s.text[start + 1..s.pos]
				mut comment := s.line_comment.trim_space()
				s.pos--
				// fix line_nr, \n was read, and the comment is marked
				// on the next line
				s.line_nr--
				if s.comments_mode == .parse_comments {
					// Find out if this comment is on its own line (for vfmt)
					mut is_separate_line_comment := true
					for j := start-2; j >= 0 && s.text.str[j] != `\n`; j-- {
						if s.text.str[j] !in [`\t`, ` `] {
							is_separate_line_comment = false
						}
					}
					if is_separate_line_comment {
						comment = '|' + comment
					}
					return s.new_token(.comment, comment, comment.len + 2)
				}
				// s.fgenln('// ${s.prev_tok.str()} "$s.line_comment"')
				// Skip the comment (return the next token)
				return s.scan()
			}
			// Multiline comments
			if nextc == `*` {
				start := s.pos + 2
				mut nest_count := 1
				// Skip comment
				for nest_count > 0 {
					s.pos++
					if s.pos >= s.text.len {
						s.line_nr--
						s.error('comment not terminated')
					}
					if s.text.str[s.pos] == `\n` {
						s.inc_line_number()
						continue
					}
					if s.expect('/*', s.pos) {
						nest_count++
						continue
					}
					if s.expect('*/', s.pos) {
						nest_count--
					}
				}
				s.pos++
				if s.comments_mode == .parse_comments {
					comment := s.text[start..(s.pos - 1)].trim_space()
					return s.new_token(.comment, comment, comment.len + 4)
				}
				// Skip if not in fmt mode
				return s.scan()
			}
			return s.new_token(.div, '', 1)
		}
		else {}
	}
	$if windows {
		if c == `\0` {
			return s.end_of_file()
		}
	}
	s.error('invalid character `${c.str()}`')
	return s.end_of_file()
}

fn (s &Scanner) current_column() int {
	return s.pos - s.last_nl_pos
}

fn (s &Scanner) count_symbol_before(p int, sym byte) int {
	mut count := 0
	for i := p; i >= 0; i-- {
		if s.text.str[i] != sym {
			break
		}
		count++
	}
	return count
}

fn (s mut Scanner) ident_string() string {
	q := s.text.str[s.pos]
	is_quote := q == single_quote || q == double_quote
	is_raw := is_quote && s.text.str[s.pos - 1] == `r`
	if is_quote && !s.is_inside_string {
		s.quote = q
	}
	// if s.file_path.contains('string_test') {
	// println('\nident_string() at char=${s.text.str[s.pos].str()}')
	// println('linenr=$s.line_nr quote=  $qquote ${qquote.str()}')
	// }
	mut start := s.pos
	s.is_inside_string = false
	slash := `\\`
	for {
		s.pos++
		if s.pos >= s.text.len {
			break
		}
		c := s.text.str[s.pos]
		prevc := s.text.str[s.pos - 1]
		// end of string
		if c == s.quote && (prevc != slash || (prevc == slash && s.text.str[s.pos - 2] == slash)) {
			// handle '123\\'  slash at the end
			break
		}
		if c == `\n` {
			s.inc_line_number()
		}
		// Don't allow \0
		if c == `0` && s.pos > 2 && s.text.str[s.pos - 1] == slash {
			if s.pos < s.text.len - 1 && s.text.str[s.pos + 1].is_digit() {}
			else {
				s.error('0 character in a string literal')
			}
		}
		// Don't allow \x00
		if c == `0` && s.pos > 5 && s.expect('\\x0', s.pos - 3) {
			s.error('0 character in a string literal')
		}
		// ${var} (ignore in vfmt mode)
		if c == `{` && prevc == `$` && !is_raw && !s.is_fmt && s.count_symbol_before(s.pos - 2, slash) % 2 == 0 {
			s.is_inside_string = true
			// so that s.pos points to $ at the next step
			s.pos -= 2
			break
		}
		// $var
		if util.is_name_char(c) && prevc == `$` && !s.is_fmt && !is_raw && s.count_symbol_before(s.pos - 2, slash) % 2 == 0 {
			s.is_inside_string = true
			s.is_inter_start = true
			s.pos -= 2
			break
		}
	}
	mut lit := ''
	if s.text.str[start] == s.quote {
		start++
	}
	mut end := s.pos
	if s.is_inside_string {
		end++
	}
	if start > s.pos {}
	else {
		lit = s.text[start..end]
	}
	return lit
}

fn (s mut Scanner) ident_char() string {
	start := s.pos
	slash := `\\`
	mut len := 0
	for {
		s.pos++
		if s.pos >= s.text.len {
			break
		}
		if s.text.str[s.pos] != slash {
			len++
		}
		double_slash := s.expect('\\\\', s.pos - 2)
		if s.text.str[s.pos] == `\`` && (s.text.str[s.pos - 1] != slash || double_slash) {
			// ` // apostrophe balance comment. do not remove
			if double_slash {
				len++
			}
			break
		}
	}
	len--
	c := s.text[start + 1..s.pos]
	if len != 1 {
		u := c.ustring()
		if u.len != 1 {
			s.error('invalid character literal (more than one character)\n' + 'use quotes for strings, backticks for characters')
		}
	}
	if c == '\\`' {
		return '`'
	}
	// Escapes a `'` character
	return if c == "\'" { '\\' + c } else { c }
}

fn (s &Scanner) expect(want string, start_pos int) bool {
	end_pos := start_pos + want.len
	if start_pos < 0 || start_pos >= s.text.len {
		return false
	}
	if end_pos < 0 || end_pos > s.text.len {
		return false
	}
	for pos in start_pos .. end_pos {
		if s.text.str[pos] != want.str[pos - start_pos] {
			return false
		}
	}
	return true
}

fn (s mut Scanner) debug_tokens() {
	s.pos = 0
	s.is_started = false
	s.is_debug = true
	fname := s.file_path.all_after(os.path_separator)
	println('\n===DEBUG TOKENS $fname===')
	for {
		tok := s.scan()
		tok_kind := tok.kind
		lit := tok.lit
		print(tok_kind.str())
		if lit != '' {
			println(' `$lit`')
		}
		else {
			println('')
		}
		if tok_kind == .eof {
			println('============ END OF DEBUG TOKENS ==================')
			break
		}
	}
}

fn (s mut Scanner) ignore_line() {
	s.eat_to_end_of_line()
	s.inc_line_number()
}

fn (s mut Scanner) eat_to_end_of_line() {
	for s.pos < s.text.len && s.text.str[s.pos] != `\n` {
		s.pos++
	}
}

fn (s mut Scanner) inc_line_number() {
	s.last_nl_pos = s.pos
	s.line_nr++
	s.line_ends << s.pos
	if s.line_nr > s.nr_lines {
		s.nr_lines = s.line_nr
	}
}

pub fn (s &Scanner) error(msg string) {
	pos := token.Position{
		line_nr: s.line_nr
		pos: s.pos
	}
	eprintln(util.formatted_error('error', msg, s.file_path, pos))
	exit(1)
}

pub fn verror(s string) {
	util.verror('scanner error', s)
}
