// Copyright (c) 2019-2024 Alexander Medvednikov. All rights reserved.
// Use of this source code is governed by an MIT license
// that can be found in the LICENSE file.
module strings

// strings.Builder is used to efficiently append many strings to a large
// dynamically growing buffer, then use the resulting large string. Using
// a string builder is much better for performance/memory usage than doing
// constantly string concatenation.
pub type Builder = []u8

// new_builder returns a new string builder, with an initial capacity of `initial_size`.
pub fn new_builder(initial_size int) Builder {
	mut res := Builder([]u8{cap: initial_size})
	unsafe { res.flags.set(.noslices) }
	return res
}

// reuse_as_plain_u8_array allows using the Builder instance as a plain []u8 return value.
// It is useful, when you have accumulated data in the builder, that you want to
// pass/access as []u8 later, without copying or freeing the buffer.
// NB: you *should NOT use* the string builder instance after calling this method.
// Use only the return value after calling this method.
@[unsafe]
pub fn (mut b Builder) reuse_as_plain_u8_array() []u8 {
	unsafe { b.flags.clear(.noslices) }
	return *b
}

// write_ptr writes `len` bytes provided byteptr to the accumulated buffer
@[unsafe]
pub fn (mut b Builder) write_ptr(ptr &u8, len int) {
	if len == 0 {
		return
	}
	unsafe { b.push_many(ptr, len) }
}

// write_rune appends a single rune to the accumulated buffer
@[manualfree]
pub fn (mut b Builder) write_rune(r rune) {
	mut buffer := [5]u8{}
	res := unsafe { utf32_to_str_no_malloc(u32(r), mut &buffer[0]) }
	if res.len == 0 {
		return
	}
	unsafe { b.push_many(res.str, res.len) }
}

// write_runes appends all the given runes to the accumulated buffer.
pub fn (mut b Builder) write_runes(runes []rune) {
	mut buffer := [5]u8{}
	for r in runes {
		res := unsafe { utf32_to_str_no_malloc(u32(r), mut &buffer[0]) }
		if res.len == 0 {
			continue
		}
		unsafe { b.push_many(res.str, res.len) }
	}
}

// write_u8 appends a single `data` byte to the accumulated buffer
@[inline]
pub fn (mut b Builder) write_u8(data u8) {
	b << data
}

// write_byte appends a single `data` byte to the accumulated buffer
@[inline]
pub fn (mut b Builder) write_byte(data u8) {
	b << data
}

// write_decimal appends a decimal representation of the number `n` into the builder `b`,
// without dynamic allocation. The higher order digits come first, i.e. 6123 will be written
// with the digit `6` first, then `1`, then `2` and `3` last.
@[direct_array_access]
pub fn (mut b Builder) write_decimal(n i64) {
	if n == 0 {
		b.write_u8(0x30)
		return
	}
	if n == min_i64 {
		b.write_string(n.str())
		return
	}

	mut buf := [25]u8{}
	mut x := if n < 0 { -n } else { n }
	mut i := 24
	for x != 0 {
		nextx := x / 10
		r := x % 10
		buf[i] = u8(r) + 0x30
		x = nextx
		i--
	}
	if n < 0 {
		buf[i] = `-`
		i--
	}
	unsafe { b.write_ptr(&buf[i + 1], 24 - i) }
}

// write implements the io.Writer interface, that is why it returns how many bytes were written to the string builder.
pub fn (mut b Builder) write(data []u8) !int {
	if data.len == 0 {
		return 0
	}
	b << data
	return data.len
}

// drain_builder writes all of the `other` builder content, then re-initialises
// `other`, so that the `other` strings builder is ready to receive new content.
@[manualfree]
pub fn (mut b Builder) drain_builder(mut other Builder, other_new_cap int) {
	if other.len > 0 {
		b << *other
	}
	unsafe { other.free() }
	other = new_builder(other_new_cap)
}

// byte_at returns a byte, located at a given index `i`.
// Note: it can panic, if there are not enough bytes in the strings builder yet.
@[inline]
pub fn (b &Builder) byte_at(n int) u8 {
	return unsafe { (&[]u8(b))[n] }
}

// write appends the string `s` to the buffer
@[expand_simple_interpolation; inline]
pub fn (mut b Builder) write_string(s string) {
	if s.len == 0 {
		return
	}
	unsafe { b.push_many(s.str, s.len) }
	// for c in s {
	// b.buf << c
	// }
	// b.buf << []u8(s)  // TODO
}

// write_string2 appends the strings `s1` and `s2` to the buffer.
@[inline]
pub fn (mut b Builder) write_string2(s1 string, s2 string) {
	if s1.len != 0 {
		unsafe { b.push_many(s1.str, s1.len) }
	}
	if s2.len != 0 {
		unsafe { b.push_many(s2.str, s2.len) }
	}
}

// go_back discards the last `n` bytes from the buffer.
pub fn (mut b Builder) go_back(n int) {
	b.trim(b.len - n)
}

// spart returns a part of the buffer as a string
@[inline]
pub fn (b &Builder) spart(start_pos int, n int) string {
	unsafe {
		mut x := malloc_noscan(n + 1)
		vmemcpy(x, &u8(b.data) + start_pos, n)
		x[n] = 0
		return tos(x, n)
	}
}

// cut_last cuts the last `n` bytes from the buffer and returns them.
pub fn (mut b Builder) cut_last(n int) string {
	cut_pos := b.len - n
	res := b.spart(cut_pos, n)
	b.trim(cut_pos)
	return res
}

// cut_to cuts the string after `pos` and returns it.
// if `pos` is superior to builder length, returns an empty string
// and cancel further operations
pub fn (mut b Builder) cut_to(pos int) string {
	if pos > b.len {
		return ''
	}
	return b.cut_last(b.len - pos)
}

// go_back_to resets the buffer to the given position `pos`.
// Note: pos should be < than the existing buffer length.
pub fn (mut b Builder) go_back_to(pos int) {
	b.trim(pos)
}

// writeln appends the string `s`, and then a newline character.
@[inline]
pub fn (mut b Builder) writeln(s string) {
	// for c in s {
	// b.buf << c
	// }
	if s != '' {
		unsafe { b.push_many(s.str, s.len) }
	}
	// b.buf << []u8(s)  // TODO
	b << u8(`\n`)
}

// writeln2 appends two strings: `s1` + `\n`, and `s2` + `\n`, to the buffer.
@[inline]
pub fn (mut b Builder) writeln2(s1 string, s2 string) {
	if s1 != '' {
		unsafe { b.push_many(s1.str, s1.len) }
	}
	b << u8(`\n`)
	if s2 != '' {
		unsafe { b.push_many(s2.str, s2.len) }
	}
	b << u8(`\n`)
}

// last_n(5) returns 'world'
// buf == 'hello world'
pub fn (b &Builder) last_n(n int) string {
	if n > b.len {
		return ''
	}
	return b.spart(b.len - n, n)
}

// after(6) returns 'world'
// buf == 'hello world'
pub fn (b &Builder) after(n int) string {
	if n >= b.len {
		return ''
	}
	return b.spart(n, b.len - n)
}

// str returns a copy of all of the accumulated buffer content.
// Note: after a call to b.str(), the builder b will be empty, and could be used again.
// The returned string *owns* its own separate copy of the accumulated data that was in
// the string builder, before the .str() call.
pub fn (mut b Builder) str() string {
	b << u8(0)
	bcopy := unsafe { &u8(memdup_noscan(b.data, b.len)) }
	s := unsafe { bcopy.vstring_with_len(b.len - 1) }
	b.clear()
	return s
}

// ensure_cap ensures that the buffer has enough space for at least `n` bytes by growing the buffer if necessary.
pub fn (mut b Builder) ensure_cap(n int) {
	// code adapted from vlib/builtin/array.v
	if n <= b.cap {
		return
	}

	new_data := vcalloc(n * b.element_size)
	if b.data != unsafe { nil } {
		unsafe { vmemcpy(new_data, b.data, b.len * b.element_size) }
		// TODO: the old data may be leaked when no GC is used (ref-counting?)
		if b.flags.has(.noslices) {
			unsafe { free(b.data) }
		}
	}
	unsafe {
		b.data = new_data
		b.offset = 0
		b.cap = n
	}
}

// grow_len grows the length of the buffer by `n` bytes if necessary
@[unsafe]
pub fn (mut b Builder) grow_len(n int) {
	if n <= 0 {
		return
	}

	new_len := b.len + n
	b.ensure_cap(new_len)
	unsafe {
		b.len = new_len
	}
}

// free frees the memory block, used for the buffer.
// Note: do not use the builder, after a call to free().
@[unsafe]
pub fn (mut b Builder) free() {
	if b.data != 0 {
		unsafe { free(b.data) }
		unsafe {
			b.data = nil
		}
	}
}

// write_repeated_rune appends multiple copies of the same rune to the accumulated buffer
@[direct_array_access]
pub fn (mut b Builder) write_repeated_rune(r rune, count int) {
	if count <= 0 {
		return
	}

	// Convert rune to UTF-8 bytes once
	mut buffer := [5]u8{}
	res := unsafe { utf32_to_str_no_malloc(u32(r), mut &buffer[0]) }
	if res.len == 0 {
		return
	}

	if res.len == 1 {
		b.ensure_cap(b.len + count)
		unsafe {
			vmemset(&u8(b.data) + b.len, buffer[0], count)
			b.len += count
		}
		return
	} else {
		total_needed := count * res.len
		b.ensure_cap(b.len + total_needed)

		mut dest := unsafe { &u8(b.data) + b.len }
		for _ in 0 .. count {
			unsafe {
				vmemcpy(dest, res.str, res.len)
				dest += res.len
			}
		}
		unsafe {
			b.len += total_needed
		}
	}
}

// IndentParam holds configuration parameters for the indent() function
@[params]
pub struct IndentParam {
pub mut:
	block_start    rune = `{` // Character that starts a new block (+ indent)
	block_end      rune = `}` // Character that ends a new block (- indent)
	indent_char    rune = ` ` // Character used for indentation (space or tab)
	indent_count   int  = 4   // Number of indent_char per indentation level
	starting_level int // Initial indentation level (0 = no initial indent)
}

// IndentState represents the current parsing state of the indent() function
enum IndentState {
	normal    // Normal state, processing regular characters
	in_string // Inside a string literal, ignoring formatting characters
}

// indent formats a string by applying structured indentation based on block delimiters.
// It processes the input string `s` and writes the formatted output to the `Builder` `b`.
// The function preserves content inside string literals (both single and double quotes) and
// configures indentation behavior through the `param` structure.
//
// Key behaviors:
// 1. Removes existing indentation at the beginning of lines.
// 2. Applies new indentation based on block nesting levels.
// 3. Ignores block delimiters and formatting characters inside string literals.
// 4. Keeps empty blocks (e.g., {}) on the same line.
// 5. Inserts newlines after `block_start` and before `block_end` (except for empty blocks).
// 6. Maintains existing line breaks from the input.
//
// Example:
// ```v
// import strings
// input := 'User{name:"John" settings:{theme:"dark"}}'
// mut b := strings.new_builder(64)
// b.indent(input, indent_count: 2)
// println(b.str()) // Formatted output: 'User{\n  name:"John" settings:{\n    theme:"dark"\n  }\n}'
// ```
@[direct_array_access]
pub fn (mut b Builder) indent(s string, param IndentParam) {
	if s.len == 0 {
		return
	}

	mut state := IndentState.normal
	mut indent_level := param.starting_level
	mut string_char := `\0`
	mut at_line_start := true
	for i := 0; i < s.len; i++ {
		c := s[i]
		match state {
			// Normal state: process characters outside of string literals
			.normal {
				match c {
					`"`, `'` { // Note: quote characters for editor display "
						state = .in_string
						string_char = c
						// Add indentation if at the start of a line
						if at_line_start {
							b.write_repeated_rune(param.indent_char, indent_level * param.indent_count)
							at_line_start = false
						}
						// Write the opening quote
						b.write_rune(c)
					}
					param.block_start {
						// Start of a new block
						// Add indentation if at the start of a line
						if at_line_start {
							b.write_repeated_rune(param.indent_char, indent_level * param.indent_count)
							at_line_start = false
						}

						// Write the block start character
						b.write_rune(c)

						// Check for empty block (e.g., {})
						// Empty blocks stay on the same line
						if i + 1 < s.len && s[i + 1] == param.block_end {
							b.write_rune(param.block_end)
							i++
						} else {
							// Non-empty block: increase indentation and add newline
							indent_level++
							b.write_rune(`\n`)
							at_line_start = true
						}
					}
					param.block_end {
						// End of a block
						// Decrease indentation level (but not below 0)
						if indent_level > 0 {
							indent_level--
						}

						// If not at the start of a line, add a newline
						if !at_line_start {
							b.write_rune(`\n`)
						}

						// Add indentation for the block end
						b.write_repeated_rune(param.indent_char, indent_level * param.indent_count)
						at_line_start = false

						b.write_rune(c)
					}
					` `, `\t`, `\r`, `\n` {
						// Whitespace characters
						// Only write whitespace if not at the start of a line
						if !at_line_start {
							b.write_rune(c)
						}

						// Newline resets the line start flag
						if c == `\n` {
							at_line_start = true
						}
					}
					else {
						// Any other character
						// Add indentation if at the start of a line
						if at_line_start {
							b.write_repeated_rune(param.indent_char, indent_level * param.indent_count)
							at_line_start = false
						}
						b.write_rune(c)
					}
				}
			}
			.in_string {
				// Inside a string literal: preserve all characters as-is
				b.write_rune(c)

				// Check for string termination
				// The character must match the opening quote and not be escaped
				if c == string_char {
					if s[i - 1] != `\\` {
						state = .normal
						string_char = `\0`
					}
				}
			}
		}
	}
}

@[inline]
fn min(a int, b int, c int) int {
	mut m := a
	if b < m {
		m = b
	}
	if c < m {
		m = c
	}
	return m
}

@[inline]
fn max2(a int, b int) int {
	if a < b {
		return b
	}
	return a
}

@[inline]
fn min2(a int, b int) int {
	if a < b {
		return a
	}
	return b
}

@[inline]
fn abs2(a int, b int) int {
	if a < b {
		return b - a
	}
	return a - b
}

// levenshtein_distance uses the Levenshtein Distance algorithm to calculate
// the distance between between two strings `a` and `b` (lower is closer).
@[direct_array_access]
pub fn levenshtein_distance(a string, b string) int {
	if a.len == 0 {
		return b.len
	}
	if b.len == 0 {
		return a.len
	}
	if a == b {
		return 0
	}
	mut row := []int{len: a.len + 1, init: index}
	for i := 1; i < b.len + 1; i++ {
		mut prev := i
		for j := 1; j < a.len + 1; j++ {
			mut current := row[j - 1] // match
			if b[i - 1] != a[j - 1] {
				// insertion, substitution, deletion
				current = min(row[j - 1] + 1, prev + 1, row[j] + 1)
			}
			row[j - 1] = prev
			prev = current
		}
		row[a.len] = prev
	}
	return row[a.len]
}

// levenshtein_distance_percentage uses the Levenshtein Distance algorithm to calculate how similar two strings are as a percentage (higher is closer).
pub fn levenshtein_distance_percentage(a string, b string) f32 {
	d := levenshtein_distance(a, b)
	l := if a.len >= b.len { a.len } else { b.len }
	return (1.00 - f32(d) / f32(l)) * 100.00
}

// dice_coefficient implements the Sørensen–Dice coefficient.
// It finds the similarity between two strings, and returns a coefficient
// between 0.0 (not similar) and 1.0 (exact match).
pub fn dice_coefficient(s1 string, s2 string) f32 {
	if s1.len == 0 || s2.len == 0 {
		return 0.0
	}
	if s1 == s2 {
		return 1.0
	}
	if s1.len < 2 || s2.len < 2 {
		return 0.0
	}
	a := if s1.len > s2.len { s1 } else { s2 }
	b := if a == s1 { s2 } else { s1 }
	mut first_bigrams := map[string]int{}
	for i in 0 .. a.len - 1 {
		bigram := a[i..i + 2]
		q := if bigram in first_bigrams { first_bigrams[bigram] + 1 } else { 1 }
		first_bigrams[bigram] = q
	}
	mut intersection_size := 0
	for i in 0 .. b.len - 1 {
		bigram := b[i..i + 2]
		count := if bigram in first_bigrams { first_bigrams[bigram] } else { 0 }
		if count > 0 {
			first_bigrams[bigram] = count - 1
			intersection_size++
		}
	}
	return (2.0 * f32(intersection_size)) / (f32(a.len) + f32(b.len) - 2)
}

// hamming_distance uses the Hamming Distance algorithm to calculate
// the distance between two strings `a` and `b` (lower is closer).
@[direct_array_access]
pub fn hamming_distance(a string, b string) int {
	if a.len == 0 && b.len == 0 {
		return 0
	}
	mut match_len := min2(a.len, b.len)
	mut diff_count := abs2(a.len, b.len)
	for i in 0 .. match_len {
		if a[i] != b[i] {
			diff_count++
		}
	}
	return diff_count
}

// hamming_similarity uses the Hamming Distance algorithm to calculate the distance between two strings `a` and `b`.
// It returns a coefficient between 0.0 (not similar) and 1.0 (exact match).
pub fn hamming_similarity(a string, b string) f32 {
	l := max2(a.len, b.len)
	if l == 0 {
		// Both are empty strings, should return 1.0
		return 1.0
	}
	d := hamming_distance(a, b)
	return 1.00 - f32(d) / f32(l)
}

// jaro_similarity uses the Jaro Distance algorithm to calculate
// the distance between two strings `a` and `b`.
// It returns a coefficient between 0.0 (not similar) and 1.0 (exact match).
@[direct_array_access]
pub fn jaro_similarity(a string, b string) f64 {
	a_len := a.len
	b_len := b.len
	if a_len == 0 && b_len == 0 {
		// Both are empty strings, should return 1.0
		return 1.0
	}
	if a_len == 0 || b_len == 0 {
		return 0
	}

	// Maximum distance upto which matching is allowed
	match_distance := max2(a_len, b_len) / 2 - 1

	mut a_matches := []bool{len: a_len}
	mut b_matches := []bool{len: b_len}
	mut matches := 0
	mut transpositions := 0.0

	// Traverse through the first string
	for i in 0 .. a_len {
		start := max2(0, i - match_distance)
		end := min2(b_len, i + match_distance + 1)
		for k in start .. end {
			// If there is a match
			if b_matches[k] {
				continue
			}
			if a[i] != b[k] {
				continue
			}
			a_matches[i] = true
			b_matches[k] = true
			matches++
			break
		}
	}
	// If there is no match
	if matches == 0 {
		return 0
	}
	mut k := 0
	// Count number of occurrences where two characters match but
	// there is a third matched character in between the indices
	for i in 0 .. a_len {
		if !a_matches[i] {
			continue
		}
		// Find the next matched character in second string
		for !b_matches[k] {
			k++
		}
		if a[i] != b[k] {
			transpositions++
		}
		k++
	}
	transpositions /= 2
	return (matches / f64(a_len) + matches / f64(b_len) + (matches - transpositions) / matches) / 3
}

// jaro_winkler_similarity uses the Jaro Winkler Distance algorithm to calculate
// the distance between two strings `a` and `b`.
// It returns a coefficient between 0.0 (not similar) and 1.0 (exact match).
// The scaling factor(`p=0.1`) in Jaro-Winkler gives higher weight to prefix
// similarities, making it especially effective for cases where slight misspellings
// or prefixes are common.
@[direct_array_access]
pub fn jaro_winkler_similarity(a string, b string) f64 {
	// Maximum of 4 characters are allowed in prefix
	mut lmax := min2(4, min2(a.len, b.len))
	mut l := 0
	for i in 0 .. lmax {
		if a[i] == b[i] {
			l++
		}
	}
	js := jaro_similarity(a, b)
	// select a multiplier (Winkler suggested p=0.1) for the relative importance of the prefix for the word similarity
	p := 0.1
	ws := js + f64(l) * p * (1 - js)
	return ws
}

// strings.repeat - fill a string with `n` repetitions of the character `c`
@[direct_array_access]
pub fn repeat(c u8, n int) string {
	if n <= 0 {
		return ''
	}
	mut bytes := unsafe { malloc_noscan(n + 1) }
	unsafe {
		C.memset(bytes, c, n)
		bytes[n] = 0
	}
	return unsafe { bytes.vstring_with_len(n) }
}

// strings.repeat_string - gives you `n` repetitions of the substring `s`
// Note: strings.repeat, that repeats a single byte, is between 2x
// and 24x faster than strings.repeat_string called for a 1 char string.
@[direct_array_access]
pub fn repeat_string(s string, n int) string {
	if n <= 0 || s.len == 0 {
		return ''
	}
	slen := s.len
	blen := slen * n
	mut bytes := unsafe { malloc_noscan(blen + 1) }
	for bi in 0 .. n {
		bislen := bi * slen
		for si in 0 .. slen {
			unsafe {
				bytes[bislen + si] = s[si]
			}
		}
	}
	unsafe {
		bytes[blen] = 0
	}
	return unsafe { bytes.vstring_with_len(blen) }
}

// find_between_pair_byte returns the string found between the pair of marks defined
// by `start` and `end`.
// As opposed to the `find_between`, `all_after*`, `all_before*` methods defined on the
// `string` type, this function can extract content between *nested* marks in `input`.
// If `start` and `end` marks are nested in `input`, the characters
// between the *outermost* mark pair is returned. It is expected that `start` and `end`
// marks are *balanced*, meaning that the amount of `start` marks equal the
// amount of `end` marks in the `input`. An empty string is returned otherwise.
// Using two identical marks as `start` and `end` results in undefined output behavior.
// find_between_pair_byte is the fastest in the find_between_pair_* family of functions.
// Example: assert strings.find_between_pair_u8('(V) (NOT V)',`(`,`)`) == 'V'
// Example: assert strings.find_between_pair_u8('s {X{Y}} s',`{`,`}`) == 'X{Y}'
pub fn find_between_pair_u8(input string, start u8, end u8) string {
	mut marks := 0
	mut start_index := -1
	for i, b in input {
		if b == start {
			if start_index == -1 {
				start_index = i + 1
			}
			marks++
			continue
		}
		if start_index > 0 {
			if b == end {
				marks--
				if marks == 0 {
					return input[start_index..i]
				}
			}
		}
	}
	return ''
}

// find_between_pair_rune returns the string found between the pair of marks defined by `start` and `end`.
// As opposed to the `find_between`, `all_after*`, `all_before*` methods defined on the
// `string` type, this function can extract content between *nested* marks in `input`.
// If `start` and `end` marks are nested in `input`, the characters
// between the *outermost* mark pair is returned. It is expected that `start` and `end`
// marks are *balanced*, meaning that the amount of `start` marks equal the
// amount of `end` marks in the `input`. An empty string is returned otherwise.
// Using two identical marks as `start` and `end` results in undefined output behavior.
// find_between_pair_rune is inbetween the fastest and slowest in the find_between_pair_* family of functions.
// Example: assert strings.find_between_pair_rune('(V) (NOT V)',`(`,`)`) == 'V'
// Example: assert strings.find_between_pair_rune('s {X{Y}} s',`{`,`}`) == 'X{Y}'
pub fn find_between_pair_rune(input string, start rune, end rune) string {
	mut marks := 0
	mut start_index := -1
	runes := input.runes()
	for i, r in runes {
		if r == start {
			if start_index == -1 {
				start_index = i + 1
			}
			marks++
			continue
		}
		if start_index > 0 {
			if r == end {
				marks--
				if marks == 0 {
					return runes[start_index..i].string()
				}
			}
		}
	}
	return ''
}

// find_between_pair_string returns the string found between the pair of marks defined by `start` and `end`.
// As opposed to the `find_between`, `all_after*`, `all_before*` methods defined on the
// `string` type, this function can extract content between *nested* marks in `input`.
// If `start` and `end` marks are nested in `input`, the characters
// between the *outermost* mark pair is returned. It is expected that `start` and `end`
// marks are *balanced*, meaning that the amount of `start` marks equal the
// amount of `end` marks in the `input`. An empty string is returned otherwise.
// Using two identical marks as `start` and `end` results in undefined output behavior.
// find_between_pair_string is the slowest in the find_between_pair_* function family.
// Example: assert strings.find_between_pair_string('/*V*/ /*NOT V*/','/*','*/') == 'V'
// Example: assert strings.find_between_pair_string('s {{X{{Y}}}} s','{{','}}') == 'X{{Y}}'
pub fn find_between_pair_string(input string, start string, end string) string {
	mut start_index := -1
	mut marks := 0
	start_runes := start.runes()
	end_runes := end.runes()
	runes := input.runes()
	mut i := 0
	for ; i < runes.len; i++ {
		start_slice := runes#[i..i + start_runes.len]
		if start_slice == start_runes {
			i = i + start_runes.len - 1
			if start_index < 0 {
				start_index = i + 1
			}
			marks++
			continue
		}
		if start_index > 0 {
			end_slice := runes#[i..i + end_runes.len]
			if end_slice == end_runes {
				marks--
				if marks == 0 {
					return runes[start_index..i].string()
				}
				i = i + end_runes.len - 1
				continue
			}
		}
	}
	return ''
}

// split_capital returns an array containing the contents of `s` split by capital letters.
// Example: assert strings.split_capital('XYZ') == ['X', 'Y', 'Z']
// Example: assert strings.split_capital('XYStar') == ['X', 'Y', 'Star']
pub fn split_capital(s string) []string {
	mut res := []string{}
	mut word_start := 0
	for idx, c in s {
		if c.is_capital() {
			if word_start != idx {
				res << s#[word_start..idx]
			}
			word_start = idx
			continue
		}
	}
	if word_start != s.len {
		res << s#[word_start..]
	}
	return res
}
