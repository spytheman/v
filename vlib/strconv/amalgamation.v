module strconv

import strings
import math.bits

// Copyright (c) 2019-2024 Dario Deledda. All rights reserved.
// Use of this source code is governed by an MIT license
// that can be found in the LICENSE file.
//
// This file contains utilities for converting a string to a f64 variable.
// IEEE 754 standard is used.
// Know limitation: limited to 18 significant digits
//
// The code is inspired by:
// Grzegorz Kraszewski krashan@teleinfo.pb.edu.pl
// URL: http://krashan.ppa.pl/articles/stringtofloat/
// Original license: MIT
// 96 bit operation utilities
//
// Note: when u128 will be available, these function can be refactored.

// f32 constants
pub const single_plus_zero = u32(0x0000_0000)
pub const single_minus_zero = u32(0x8000_0000)
pub const single_plus_infinity = u32(0x7F80_0000)
pub const single_minus_infinity = u32(0xFF80_0000)

// f64 constants
pub const digits = 18
pub const double_plus_zero = u64(0x0000000000000000)
pub const double_minus_zero = u64(0x8000000000000000)
pub const double_plus_infinity = u64(0x7FF0000000000000)
pub const double_minus_infinity = u64(0xFFF0000000000000)

// char constants
pub const c_dpoint = `.`
pub const c_plus = `+`
pub const c_minus = `-`
pub const c_zero = `0`
pub const c_nine = `9`
pub const c_ten = u32(10)

// right logical shift 96 bit
fn lsr96(s2 u32, s1 u32, s0 u32) (u32, u32, u32) {
	mut r0 := u32(0)
	mut r1 := u32(0)
	mut r2 := u32(0)
	r0 = (s0 >> 1) | ((s1 & u32(1)) << 31)
	r1 = (s1 >> 1) | ((s2 & u32(1)) << 31)
	r2 = s2 >> 1
	return r2, r1, r0
}

// left logical shift 96 bit
fn lsl96(s2 u32, s1 u32, s0 u32) (u32, u32, u32) {
	mut r0 := u32(0)
	mut r1 := u32(0)
	mut r2 := u32(0)
	r2 = (s2 << 1) | ((s1 & (u32(1) << 31)) >> 31)
	r1 = (s1 << 1) | ((s0 & (u32(1) << 31)) >> 31)
	r0 = s0 << 1
	return r2, r1, r0
}

// sum on 96 bit
fn add96(s2 u32, s1 u32, s0 u32, d2 u32, d1 u32, d0 u32) (u32, u32, u32) {
	mut w := u64(0)
	mut r0 := u32(0)
	mut r1 := u32(0)
	mut r2 := u32(0)
	w = u64(s0) + u64(d0)
	r0 = u32(w)
	w >>= 32
	w += u64(s1) + u64(d1)
	r1 = u32(w)
	w >>= 32
	w += u64(s2) + u64(d2)
	r2 = u32(w)
	return r2, r1, r0
}

// subtraction on 96 bit
fn sub96(s2 u32, s1 u32, s0 u32, d2 u32, d1 u32, d0 u32) (u32, u32, u32) {
	mut w := u64(0)
	mut r0 := u32(0)
	mut r1 := u32(0)
	mut r2 := u32(0)
	w = u64(s0) - u64(d0)
	r0 = u32(w)
	w >>= 32
	w += u64(s1) - u64(d1)
	r1 = u32(w)
	w >>= 32
	w += u64(s2) - u64(d2)
	r2 = u32(w)
	return r2, r1, r0
}

// Utility functions
fn is_digit(x u8) bool {
	return x >= c_zero && x <= c_nine
}

fn is_space(x u8) bool {
	return x == `\t` || x == `\n` || x == `\v` || x == `\f` || x == `\r` || x == ` `
}

fn is_exp(x u8) bool {
	return x == `E` || x == `e`
}

// Possible parser return values.
enum ParserState {
	ok             // parser finished OK
	pzero          // no digits or number is smaller than +-2^-1022
	mzero          // number is negative, module smaller
	pinf           // number is higher than +HUGE_VAL
	minf           // number is lower than -HUGE_VAL
	invalid_number // invalid number, used for '#@%^' for example
	extra_char     // extra char after number
}

// parser tries to parse the given string into a number
// FIXME: need one char after the last char of the number
@[direct_array_access]
fn parser(s string) (ParserState, PrepNumber) {
	mut digx := 0
	mut result := ParserState.ok
	mut expneg := false
	mut expexp := 0
	mut i := 0
	mut pn := PrepNumber{}

	// skip spaces
	for i < s.len && s[i].is_space() {
		i++
	}

	// check negatives
	if s[i] == `-` {
		pn.negative = true
		i++
	}

	// positive sign ignore it
	if s[i] == `+` {
		i++
	}

	// read mantissa
	for i < s.len && s[i].is_digit() {
		// println("$i => ${s[i]}")
		if digx < digits {
			pn.mantissa *= 10
			pn.mantissa += u64(s[i] - c_zero)
			digx++
		} else if pn.exponent < 2147483647 {
			pn.exponent++
		}
		i++
	}

	// read mantissa decimals
	if i < s.len && s[i] == `.` {
		i++
		for i < s.len && s[i].is_digit() {
			if digx < digits {
				pn.mantissa *= 10
				pn.mantissa += u64(s[i] - c_zero)
				pn.exponent--
				digx++
			}
			i++
		}
	}

	// read exponent
	if i < s.len && (s[i] == `e` || s[i] == `E`) {
		i++
		if i < s.len {
			// esponent sign
			if s[i] == c_plus {
				i++
			} else if s[i] == c_minus {
				expneg = true
				i++
			}

			for i < s.len && s[i].is_digit() {
				if expexp < 214748364 {
					expexp *= 10
					expexp += int(s[i] - c_zero)
				}
				i++
			}
		}
	}

	if expneg {
		expexp = -expexp
	}
	pn.exponent += expexp
	if pn.mantissa == 0 {
		if pn.negative {
			result = .mzero
		} else {
			result = .pzero
		}
	} else if pn.exponent > 309 {
		if pn.negative {
			result = .minf
		} else {
			result = .pinf
		}
	} else if pn.exponent < -328 {
		if pn.negative {
			result = .mzero
		} else {
			result = .pzero
		}
	}
	if i == 0 && s.len > 0 {
		return ParserState.invalid_number, pn
	}
	if i != s.len {
		return ParserState.extra_char, pn
	}
	return result, pn
}

// converter returns a u64 with the bit image of the f64 number
fn converter(mut pn PrepNumber) u64 {
	mut binexp := 92
	// s0,s1,s2 are the parts of a 96-bit precision integer
	mut s2 := u32(0)
	mut s1 := u32(0)
	mut s0 := u32(0)
	// q0,q1,q2 are the parts of a 96-bit precision integer
	mut q2 := u32(0)
	mut q1 := u32(0)
	mut q0 := u32(0)
	// r0,r1,r2 are the parts of a 96-bit precision integer
	mut r2 := u32(0)
	mut r1 := u32(0)
	mut r0 := u32(0)

	mask28 := u32(u64(0xF) << 28)
	mut result := u64(0)
	// working on 3 u32 to have 96 bit precision
	s0 = u32(pn.mantissa & u64(0x00000000FFFFFFFF))
	s1 = u32(pn.mantissa >> 32)
	s2 = u32(0)
	// so we take the decimal exponent off
	for pn.exponent > 0 {
		q2, q1, q0 = lsl96(s2, s1, s0) // q = s * 2
		r2, r1, r0 = lsl96(q2, q1, q0) // r = s * 4 <=> q * 2
		s2, s1, s0 = lsl96(r2, r1, r0) // s = s * 8 <=> r * 2
		s2, s1, s0 = add96(s2, s1, s0, q2, q1, q0) // s = (s * 8) + (s * 2) <=> s*10
		pn.exponent--
		for (s2 & mask28) != 0 {
			q2, q1, q0 = lsr96(s2, s1, s0)
			binexp++
			s2 = q2
			s1 = q1
			s0 = q0
		}
	}
	for pn.exponent < 0 {
		for !((s2 & (u32(1) << 31)) != 0) {
			q2, q1, q0 = lsl96(s2, s1, s0)
			binexp--
			s2 = q2
			s1 = q1
			s0 = q0
		}
		q2 = s2 / c_ten
		r1 = s2 % c_ten
		r2 = (s1 >> 8) | (r1 << 24)
		q1 = r2 / c_ten
		r1 = r2 % c_ten
		r2 = ((s1 & u32(0xFF)) << 16) | (s0 >> 16) | (r1 << 24)
		r0 = r2 / c_ten
		r1 = r2 % c_ten
		q1 = (q1 << 8) | ((r0 & u32(0x00FF0000)) >> 16)
		q0 = r0 << 16
		r2 = (s0 & u32(0xFFFF)) | (r1 << 16)
		q0 |= r2 / c_ten
		s2 = q2
		s1 = q1
		s0 = q0
		pn.exponent++
	}
	// C.printf(c"mantissa before normalization: %08x%08x%08x binexp: %d \n", s2,s1,s0,binexp)
	// normalization, the 28 bit in s2 must the leftest one in the variable
	if s2 != 0 || s1 != 0 || s0 != 0 {
		for (s2 & mask28) == 0 {
			q2, q1, q0 = lsl96(s2, s1, s0)
			binexp--
			s2 = q2
			s1 = q1
			s0 = q0
		}
	}

	// Handle subnormal (denormalized) numbers - very small numbers near zero
	//
	// Normal floats have an implicit leading 1 bit in their mantissa (like 1.xxxxx).
	// When numbers get too small (binexp < -1022), we can't represent them normally.
	// Instead, we use subnormals: set exponent to 0 and shift the mantissa right,
	// losing precision gradually. This prevents abrupt underflow to zero.
	//
	// Example: 1.23e-308 is smaller than the minimum normal float, so we:
	// 1. Keep the normalized mantissa from s2 and s1
	// 2. Shift it right to "denormalize" it (the leading 1 moves into the mantissa)
	// 3. Round correctly using the bits that were shifted out
	// 4. Return with exponent = 0 (subnormal marker)
	if binexp < -1022 && (s2 | s1) != 0 {
		shift := -1022 - binexp
		if shift > 60 {
			return if pn.negative { double_minus_zero } else { double_plus_zero }
		}
		shifted := ((u64(s2) << 32) | u64(s1)) >> u32(shift)
		q := (shifted >> 8) +
			u64((shifted >> 7) & 1 != 0 && ((shifted & 0x7F) != 0 || (shifted >> 8) & 1 != 0))
		return (q & 0x000FFFFFFFFFFFFF) | (u64(pn.negative) << 63)
	}

	// rounding if needed
	/*
	* "round half to even" algorithm
	* Example for f32, just a reminder
	*
	* If bit 54 is 0, round down
	* If bit 54 is 1
	*	If any bit beyond bit 54 is 1, round up
	*	If all bits beyond bit 54 are 0 (meaning the number is halfway between two floating-point numbers)
	*		If bit 53 is 0, round down
	*		If bit 53 is 1, round up
	*/
	/*
	test case 1 complete
	s2=0x1FFFFFFF
	s1=0xFFFFFF80
	s0=0x0
	*/

	/*
	test case 1 check_round_bit
	s2=0x18888888
	s1=0x88888880
	s0=0x0
	*/

	/*
	test case  check_round_bit + normalization
	s2=0x18888888
	s1=0x88888F80
	s0=0x0
	*/

	// C.printf(c"mantissa before rounding: %08x%08x%08x binexp: %d \n", s2,s1,s0,binexp)
	// s1 => 0xFFFFFFxx only F are represented
	nbit := 7
	check_round_bit := u32(1) << u32(nbit)
	check_round_mask := u32(0xFFFFFFFF) << u32(nbit)
	if (s1 & check_round_bit) != 0 {
		// C.printf(c"need round!! check mask: %08x\n", s1 & ~check_round_mask )
		if (s1 & ~check_round_mask) != 0 {
			// C.printf(c"Add 1!\n")
			s2, s1, s0 = add96(s2, s1, s0, 0, check_round_bit, 0)
		} else {
			// C.printf(c"All 0!\n")
			if (s1 & (check_round_bit << u32(1))) != 0 {
				// C.printf(c"Add 1 form -1 bit control!\n")
				s2, s1, s0 = add96(s2, s1, s0, 0, check_round_bit, 0)
			}
		}
		s1 = s1 & check_round_mask
		s0 = u32(0)
		// recheck normalization
		if s2 & (mask28 << u32(1)) != 0 {
			// C.printf(c"Renormalize!!\n")
			q2, q1, q0 = lsr96(s2, s1, s0)
			binexp++
			// dump(binexp)
			s2 = q2
			s1 = q1
			s0 = q0
		}
	}
	// tmp := ( u64(s2 & ~mask28) << 24) | ((u64(s1) + u64(128)) >> 8)
	// C.printf(c"mantissa after rounding : %08x %08x %08x binexp: %d \n", s2,s1,s0,binexp)
	// C.printf(c"Tmp result: %016x\n",tmp)
	// end rounding
	// offset the binary exponent IEEE 754
	binexp += 1023
	if binexp > 2046 {
		if pn.negative {
			result = double_minus_infinity
		} else {
			result = double_plus_infinity
		}
	} else if binexp < 1 {
		// Should not reach here for subnormals anymore (handled earlier)
		// This is now only for true zeros
		if pn.negative {
			result = double_minus_zero
		} else {
			result = double_plus_zero
		}
	} else if s2 != 0 {
		mut q := u64(0)
		binexs2 := u64(binexp) << 52
		q = (u64(s2 & ~mask28) << 24) | ((u64(s1) + u64(128)) >> 8) | binexs2
		if pn.negative {
			q |= (u64(1) << 63)
		}
		result = q
	}
	return result
}

@[params]
pub struct AtoF64Param {
pub:
	allow_extra_chars bool // allow extra characters after number
}

// atof64 parses the string `s`, and if possible, converts it into a f64 number
pub fn atof64(s string, param AtoF64Param) !f64 {
	if s.len == 0 {
		return error('expected a number found an empty string')
	}
	mut res := Float64u{}
	res_parsing, mut pn := parser(s)
	match res_parsing {
		.ok {
			res.u = converter(mut pn)
		}
		.pzero {
			res.u = double_plus_zero
		}
		.mzero {
			res.u = double_minus_zero
		}
		.pinf {
			res.u = double_plus_infinity
		}
		.minf {
			res.u = double_minus_infinity
		}
		.extra_char {
			if param.allow_extra_chars {
				res.u = converter(mut pn)
			} else {
				return error('extra char after number')
			}
		}
		.invalid_number {
			return error('not a number')
		}
	}
	return unsafe { res.f }
}

/*
atof util

Copyright (c) 2019 Dario Deledda. All rights reserved.
Use of this source code is governed by an MIT license
that can be found in the LICENSE file.

This file contains utilities for convert a string in a f64 variable in a very quick way
IEEE 754 standard is used

Know limitation:
- round to 0 approximation
- loos of precision with big exponents
*/

// atof_quick return a f64 number from a string in a quick way
@[direct_array_access]
pub fn atof_quick(s string) f64 {
	mut f := Float64u{} // result
	mut sign := f64(1.0) // result sign
	mut i := 0 // index
	// skip white spaces
	for i < s.len && s[i] == ` ` {
		i++
	}
	// check sign
	if i < s.len {
		if s[i] == `-` {
			sign = -1.0
			i++
		} else if s[i] == `+` {
			i++
		}
	}
	// infinite
	if s[i] == `i` && i + 2 < s.len && s[i + 1] == `n` && s[i + 2] == `f` {
		if sign > 0.0 {
			f.u = double_plus_infinity
		} else {
			f.u = double_minus_infinity
		}
		return unsafe { f.f }
	}
	// skip zeros
	for i < s.len && s[i] == `0` {
		i++
		// we have a zero, manage it
		if i >= s.len {
			if sign > 0.0 {
				f.u = double_plus_zero
			} else {
				f.u = double_minus_zero
			}
			return unsafe { f.f }
		}
	}
	// integer part
	for i < s.len && (s[i] >= `0` && s[i] <= `9`) {
		f.f *= f64(10.0)
		f.f += f64(s[i] - `0`)
		i++
	}
	// decimal point
	if i < s.len && s[i] == `.` {
		i++
		mut frac_mul := f64(0.1)
		for i < s.len && (s[i] >= `0` && s[i] <= `9`) {
			f.f += f64(s[i] - `0`) * frac_mul
			frac_mul *= f64(0.1)
			i++
		}
	}
	// exponent management
	if i < s.len && (s[i] == `e` || s[i] == `E`) {
		i++
		mut exp := 0
		mut exp_sign := 1
		// negative exponent
		if i < s.len {
			if s[i] == `-` {
				exp_sign = -1
				i++
			} else if s[i] == `+` {
				i++
			}
		}
		// skip zeros
		for i < s.len && s[i] == `0` {
			i++
		}
		for i < s.len && (s[i] >= `0` && s[i] <= `9`) {
			exp *= 10
			exp += int(s[i] - `0`)
			i++
		}
		if exp_sign == 1 {
			if exp > pos_exp.len {
				if sign > 0 {
					f.u = double_plus_infinity
				} else {
					f.u = double_minus_infinity
				}
				return unsafe { f.f }
			}
			tmp_mul := Float64u{
				u: pos_exp[exp]
			}
			// C.printf("exp: %d  [0x%016llx] %f,",exp,pos_exp[exp],tmp_mul)
			f.f = unsafe { f.f * tmp_mul.f }
		} else {
			if exp > neg_exp.len {
				if sign > 0 {
					f.u = double_plus_zero
				} else {
					f.u = double_minus_zero
				}
				return unsafe { f.f }
			}
			tmp_mul := Float64u{
				u: neg_exp[exp]
			}

			// C.printf("exp: %d  [0x%016llx] %f,",exp,pos_exp[exp],tmp_mul)
			f.f = unsafe { f.f * tmp_mul.f }
		}
	}
	unsafe {
		f.f = f.f * sign
		return f.f
	}
}

// positive exp of 10 binary form
const pos_exp = [u64(0x3ff0000000000000), u64(0x4024000000000000), u64(0x4059000000000000),
	u64(0x408f400000000000), u64(0x40c3880000000000), u64(0x40f86a0000000000),
	u64(0x412e848000000000), u64(0x416312d000000000), u64(0x4197d78400000000),
	u64(0x41cdcd6500000000), u64(0x4202a05f20000000), u64(0x42374876e8000000),
	u64(0x426d1a94a2000000), u64(0x42a2309ce5400000), u64(0x42d6bcc41e900000),
	u64(0x430c6bf526340000), u64(0x4341c37937e08000), u64(0x4376345785d8a000),
	u64(0x43abc16d674ec800), u64(0x43e158e460913d00), u64(0x4415af1d78b58c40),
	u64(0x444b1ae4d6e2ef50), u64(0x4480f0cf064dd592), u64(0x44b52d02c7e14af6),
	u64(0x44ea784379d99db4), u64(0x45208b2a2c280291), u64(0x4554adf4b7320335),
	u64(0x4589d971e4fe8402), u64(0x45c027e72f1f1281), u64(0x45f431e0fae6d721),
	u64(0x46293e5939a08cea), u64(0x465f8def8808b024), u64(0x4693b8b5b5056e17),
	u64(0x46c8a6e32246c99c), u64(0x46fed09bead87c03), u64(0x4733426172c74d82),
	u64(0x476812f9cf7920e3), u64(0x479e17b84357691b), u64(0x47d2ced32a16a1b1),
	u64(0x48078287f49c4a1d), u64(0x483d6329f1c35ca5), u64(0x48725dfa371a19e7),
	u64(0x48a6f578c4e0a061), u64(0x48dcb2d6f618c879), u64(0x4911efc659cf7d4c),
	u64(0x49466bb7f0435c9e), u64(0x497c06a5ec5433c6), u64(0x49b18427b3b4a05c),
	u64(0x49e5e531a0a1c873), u64(0x4a1b5e7e08ca3a8f), u64(0x4a511b0ec57e649a),
	u64(0x4a8561d276ddfdc0), u64(0x4ababa4714957d30), u64(0x4af0b46c6cdd6e3e),
	u64(0x4b24e1878814c9ce), u64(0x4b5a19e96a19fc41), u64(0x4b905031e2503da9),
	u64(0x4bc4643e5ae44d13), u64(0x4bf97d4df19d6057), u64(0x4c2fdca16e04b86d),
	u64(0x4c63e9e4e4c2f344), u64(0x4c98e45e1df3b015), u64(0x4ccf1d75a5709c1b),
	u64(0x4d03726987666191), u64(0x4d384f03e93ff9f5), u64(0x4d6e62c4e38ff872),
	u64(0x4da2fdbb0e39fb47), u64(0x4dd7bd29d1c87a19), u64(0x4e0dac74463a989f),
	u64(0x4e428bc8abe49f64), u64(0x4e772ebad6ddc73d), u64(0x4eacfa698c95390c),
	u64(0x4ee21c81f7dd43a7), u64(0x4f16a3a275d49491), u64(0x4f4c4c8b1349b9b5),
	u64(0x4f81afd6ec0e1411), u64(0x4fb61bcca7119916), u64(0x4feba2bfd0d5ff5b),
	u64(0x502145b7e285bf99), u64(0x50559725db272f7f), u64(0x508afcef51f0fb5f),
	u64(0x50c0de1593369d1b), u64(0x50f5159af8044462), u64(0x512a5b01b605557b),
	u64(0x516078e111c3556d), u64(0x5194971956342ac8), u64(0x51c9bcdfabc1357a),
	u64(0x5200160bcb58c16c), u64(0x52341b8ebe2ef1c7), u64(0x526922726dbaae39),
	u64(0x529f6b0f092959c7), u64(0x52d3a2e965b9d81d), u64(0x53088ba3bf284e24),
	u64(0x533eae8caef261ad), u64(0x53732d17ed577d0c), u64(0x53a7f85de8ad5c4f),
	u64(0x53ddf67562d8b363), u64(0x5412ba095dc7701e), u64(0x5447688bb5394c25),
	u64(0x547d42aea2879f2e), u64(0x54b249ad2594c37d), u64(0x54e6dc186ef9f45c),
	u64(0x551c931e8ab87173), u64(0x5551dbf316b346e8), u64(0x558652efdc6018a2),
	u64(0x55bbe7abd3781eca), u64(0x55f170cb642b133f), u64(0x5625ccfe3d35d80e),
	u64(0x565b403dcc834e12), u64(0x569108269fd210cb), u64(0x56c54a3047c694fe),
	u64(0x56fa9cbc59b83a3d), u64(0x5730a1f5b8132466), u64(0x5764ca732617ed80),
	u64(0x5799fd0fef9de8e0), u64(0x57d03e29f5c2b18c), u64(0x58044db473335def),
	u64(0x583961219000356b), u64(0x586fb969f40042c5), u64(0x58a3d3e2388029bb),
	u64(0x58d8c8dac6a0342a), u64(0x590efb1178484135), u64(0x59435ceaeb2d28c1),
	u64(0x59783425a5f872f1), u64(0x59ae412f0f768fad), u64(0x59e2e8bd69aa19cc),
	u64(0x5a17a2ecc414a03f), u64(0x5a4d8ba7f519c84f), u64(0x5a827748f9301d32),
	u64(0x5ab7151b377c247e), u64(0x5aecda62055b2d9e), u64(0x5b22087d4358fc82),
	u64(0x5b568a9c942f3ba3), u64(0x5b8c2d43b93b0a8c), u64(0x5bc19c4a53c4e697),
	u64(0x5bf6035ce8b6203d), u64(0x5c2b843422e3a84d), u64(0x5c6132a095ce4930),
	u64(0x5c957f48bb41db7c), u64(0x5ccadf1aea12525b), u64(0x5d00cb70d24b7379),
	u64(0x5d34fe4d06de5057), u64(0x5d6a3de04895e46d), u64(0x5da066ac2d5daec4),
	u64(0x5dd4805738b51a75), u64(0x5e09a06d06e26112), u64(0x5e400444244d7cab),
	u64(0x5e7405552d60dbd6), u64(0x5ea906aa78b912cc), u64(0x5edf485516e7577f),
	u64(0x5f138d352e5096af), u64(0x5f48708279e4bc5b), u64(0x5f7e8ca3185deb72),
	u64(0x5fb317e5ef3ab327), u64(0x5fe7dddf6b095ff1), u64(0x601dd55745cbb7ed),
	u64(0x6052a5568b9f52f4), u64(0x60874eac2e8727b1), u64(0x60bd22573a28f19d),
	u64(0x60f2357684599702), u64(0x6126c2d4256ffcc3), u64(0x615c73892ecbfbf4),
	u64(0x6191c835bd3f7d78), u64(0x61c63a432c8f5cd6), u64(0x61fbc8d3f7b3340c),
	u64(0x62315d847ad00087), u64(0x6265b4e5998400a9), u64(0x629b221effe500d4),
	u64(0x62d0f5535fef2084), u64(0x630532a837eae8a5), u64(0x633a7f5245e5a2cf),
	u64(0x63708f936baf85c1), u64(0x63a4b378469b6732), u64(0x63d9e056584240fe),
	u64(0x64102c35f729689f), u64(0x6444374374f3c2c6), u64(0x647945145230b378),
	u64(0x64af965966bce056), u64(0x64e3bdf7e0360c36), u64(0x6518ad75d8438f43),
	u64(0x654ed8d34e547314), u64(0x6583478410f4c7ec), u64(0x65b819651531f9e8),
	u64(0x65ee1fbe5a7e7861), u64(0x6622d3d6f88f0b3d), u64(0x665788ccb6b2ce0c),
	u64(0x668d6affe45f818f), u64(0x66c262dfeebbb0f9), u64(0x66f6fb97ea6a9d38),
	u64(0x672cba7de5054486), u64(0x6761f48eaf234ad4), u64(0x679671b25aec1d89),
	u64(0x67cc0e1ef1a724eb), u64(0x680188d357087713), u64(0x6835eb082cca94d7),
	u64(0x686b65ca37fd3a0d), u64(0x68a11f9e62fe4448), u64(0x68d56785fbbdd55a),
	u64(0x690ac1677aad4ab1), u64(0x6940b8e0acac4eaf), u64(0x6974e718d7d7625a),
	u64(0x69aa20df0dcd3af1), u64(0x69e0548b68a044d6), u64(0x6a1469ae42c8560c),
	u64(0x6a498419d37a6b8f), u64(0x6a7fe52048590673), u64(0x6ab3ef342d37a408),
	u64(0x6ae8eb0138858d0a), u64(0x6b1f25c186a6f04c), u64(0x6b537798f4285630),
	u64(0x6b88557f31326bbb), u64(0x6bbe6adefd7f06aa), u64(0x6bf302cb5e6f642a),
	u64(0x6c27c37e360b3d35), u64(0x6c5db45dc38e0c82), u64(0x6c9290ba9a38c7d1),
	u64(0x6cc734e940c6f9c6), u64(0x6cfd022390f8b837), u64(0x6d3221563a9b7323),
	u64(0x6d66a9abc9424feb), u64(0x6d9c5416bb92e3e6), u64(0x6dd1b48e353bce70),
	u64(0x6e0621b1c28ac20c), u64(0x6e3baa1e332d728f), u64(0x6e714a52dffc6799),
	u64(0x6ea59ce797fb817f), u64(0x6edb04217dfa61df), u64(0x6f10e294eebc7d2c),
	u64(0x6f451b3a2a6b9c76), u64(0x6f7a6208b5068394), u64(0x6fb07d457124123d),
	u64(0x6fe49c96cd6d16cc), u64(0x7019c3bc80c85c7f), u64(0x70501a55d07d39cf),
	u64(0x708420eb449c8843), u64(0x70b9292615c3aa54), u64(0x70ef736f9b3494e9),
	u64(0x7123a825c100dd11), u64(0x7158922f31411456), u64(0x718eb6bafd91596b),
	u64(0x71c33234de7ad7e3), u64(0x71f7fec216198ddc), u64(0x722dfe729b9ff153),
	u64(0x7262bf07a143f6d4), u64(0x72976ec98994f489), u64(0x72cd4a7bebfa31ab),
	u64(0x73024e8d737c5f0b), u64(0x7336e230d05b76cd), u64(0x736c9abd04725481),
	u64(0x73a1e0b622c774d0), u64(0x73d658e3ab795204), u64(0x740bef1c9657a686),
	u64(0x74417571ddf6c814), u64(0x7475d2ce55747a18), u64(0x74ab4781ead1989e),
	u64(0x74e10cb132c2ff63), u64(0x75154fdd7f73bf3c), u64(0x754aa3d4df50af0b),
	u64(0x7580a6650b926d67), u64(0x75b4cffe4e7708c0), u64(0x75ea03fde214caf1),
	u64(0x7620427ead4cfed6), u64(0x7654531e58a03e8c), u64(0x768967e5eec84e2f),
	u64(0x76bfc1df6a7a61bb), u64(0x76f3d92ba28c7d15), u64(0x7728cf768b2f9c5a),
	u64(0x775f03542dfb8370), u64(0x779362149cbd3226), u64(0x77c83a99c3ec7eb0),
	u64(0x77fe494034e79e5c), u64(0x7832edc82110c2f9), u64(0x7867a93a2954f3b8),
	u64(0x789d9388b3aa30a5), u64(0x78d27c35704a5e67), u64(0x79071b42cc5cf601),
	u64(0x793ce2137f743382), u64(0x79720d4c2fa8a031), u64(0x79a6909f3b92c83d),
	u64(0x79dc34c70a777a4d), u64(0x7a11a0fc668aac70), u64(0x7a46093b802d578c),
	u64(0x7a7b8b8a6038ad6f), u64(0x7ab137367c236c65), u64(0x7ae585041b2c477f),
	u64(0x7b1ae64521f7595e), u64(0x7b50cfeb353a97db), u64(0x7b8503e602893dd2),
	u64(0x7bba44df832b8d46), u64(0x7bf06b0bb1fb384c), u64(0x7c2485ce9e7a065f),
	u64(0x7c59a742461887f6), u64(0x7c9008896bcf54fa), u64(0x7cc40aabc6c32a38),
	u64(0x7cf90d56b873f4c7), u64(0x7d2f50ac6690f1f8), u64(0x7d63926bc01a973b),
	u64(0x7d987706b0213d0a), u64(0x7dce94c85c298c4c), u64(0x7e031cfd3999f7b0),
	u64(0x7e37e43c8800759c), u64(0x7e6ddd4baa009303), u64(0x7ea2aa4f4a405be2),
	u64(0x7ed754e31cd072da), u64(0x7f0d2a1be4048f90), u64(0x7f423a516e82d9ba),
	u64(0x7f76c8e5ca239029), u64(0x7fac7b1f3cac7433), u64(0x7fe1ccf385ebc8a0)]!
// negative exp of 10 binary form
const neg_exp = [u64(0x3ff0000000000000), u64(0x3fb999999999999a), u64(0x3f847ae147ae147b),
	u64(0x3f50624dd2f1a9fc), u64(0x3f1a36e2eb1c432d), u64(0x3ee4f8b588e368f1),
	u64(0x3eb0c6f7a0b5ed8d), u64(0x3e7ad7f29abcaf48), u64(0x3e45798ee2308c3a),
	u64(0x3e112e0be826d695), u64(0x3ddb7cdfd9d7bdbb), u64(0x3da5fd7fe1796495),
	u64(0x3d719799812dea11), u64(0x3d3c25c268497682), u64(0x3d06849b86a12b9b),
	u64(0x3cd203af9ee75616), u64(0x3c9cd2b297d889bc), u64(0x3c670ef54646d497),
	u64(0x3c32725dd1d243ac), u64(0x3bfd83c94fb6d2ac), u64(0x3bc79ca10c924223),
	u64(0x3b92e3b40a0e9b4f), u64(0x3b5e392010175ee6), u64(0x3b282db34012b251),
	u64(0x3af357c299a88ea7), u64(0x3abef2d0f5da7dd9), u64(0x3a88c240c4aecb14),
	u64(0x3a53ce9a36f23c10), u64(0x3a1fb0f6be506019), u64(0x39e95a5efea6b347),
	u64(0x39b4484bfeebc2a0), u64(0x398039d665896880), u64(0x3949f623d5a8a733),
	u64(0x3914c4e977ba1f5c), u64(0x38e09d8792fb4c49), u64(0x38aa95a5b7f87a0f),
	u64(0x38754484932d2e72), u64(0x3841039d428a8b8f), u64(0x380b38fb9daa78e4),
	u64(0x37d5c72fb1552d83), u64(0x37a16c262777579c), u64(0x376be03d0bf225c7),
	u64(0x37364cfda3281e39), u64(0x3701d7314f534b61), u64(0x36cc8b8218854567),
	u64(0x3696d601ad376ab9), u64(0x366244ce242c5561), u64(0x362d3ae36d13bbce),
	u64(0x35f7624f8a762fd8), u64(0x35c2b50c6ec4f313), u64(0x358dee7a4ad4b81f),
	u64(0x3557f1fb6f10934c), u64(0x352327fc58da0f70), u64(0x34eea6608e29b24d),
	u64(0x34b8851a0b548ea4), u64(0x34839dae6f76d883), u64(0x344f62b0b257c0d2),
	u64(0x34191bc08eac9a41), u64(0x33e41633a556e1ce), u64(0x33b011c2eaabe7d8),
	u64(0x3379b604aaaca626), u64(0x3344919d5556eb52), u64(0x3310747ddddf22a8),
	u64(0x32da53fc9631d10d), u64(0x32a50ffd44f4a73d), u64(0x3270d9976a5d5297),
	u64(0x323af5bf109550f2), u64(0x32059165a6ddda5b), u64(0x31d1411e1f17e1e3),
	u64(0x319b9b6364f30304), u64(0x316615e91d8f359d), u64(0x3131ab20e472914a),
	u64(0x30fc45016d841baa), u64(0x30c69d9abe034955), u64(0x309217aefe690777),
	u64(0x305cf2b1970e7258), u64(0x3027288e1271f513), u64(0x2ff286d80ec190dc),
	u64(0x2fbda48ce468e7c7), u64(0x2f87b6d71d20b96c), u64(0x2f52f8ac174d6123),
	u64(0x2f1e5aacf2156838), u64(0x2ee8488a5b445360), u64(0x2eb36d3b7c36a91a),
	u64(0x2e7f152bf9f10e90), u64(0x2e48ddbcc7f40ba6), u64(0x2e13e497065cd61f),
	u64(0x2ddfd424d6faf031), u64(0x2da97683df2f268d), u64(0x2d745ecfe5bf520b),
	u64(0x2d404bd984990e6f), u64(0x2d0a12f5a0f4e3e5), u64(0x2cd4dbf7b3f71cb7),
	u64(0x2ca0aff95cc5b092), u64(0x2c6ab328946f80ea), u64(0x2c355c2076bf9a55),
	u64(0x2c0116805effaeaa), u64(0x2bcb5733cb32b111), u64(0x2b95df5ca28ef40d),
	u64(0x2b617f7d4ed8c33e), u64(0x2b2bff2ee48e0530), u64(0x2af665bf1d3e6a8d),
	u64(0x2ac1eaff4a98553d), u64(0x2a8cab3210f3bb95), u64(0x2a56ef5b40c2fc77),
	u64(0x2a225915cd68c9f9), u64(0x29ed5b561574765b), u64(0x29b77c44ddf6c516),
	u64(0x2982c9d0b1923745), u64(0x294e0fb44f50586e), u64(0x29180c903f7379f2),
	u64(0x28e33d4032c2c7f5), u64(0x28aec866b79e0cba), u64(0x2878a0522c7e7095),
	u64(0x2843b374f06526de), u64(0x280f8587e7083e30), u64(0x27d9379fec069826),
	u64(0x27a42c7ff0054685), u64(0x277023998cd10537), u64(0x2739d28f47b4d525),
	u64(0x2704a8729fc3ddb7), u64(0x26d086c219697e2c), u64(0x269a71368f0f3047),
	u64(0x2665275ed8d8f36c), u64(0x2630ec4be0ad8f89), u64(0x25fb13ac9aaf4c0f),
	u64(0x25c5a956e225d672), u64(0x2591544581b7dec2), u64(0x255bba08cf8c979d),
	u64(0x25262e6d72d6dfb0), u64(0x24f1bebdf578b2f4), u64(0x24bc6463225ab7ec),
	u64(0x2486b6b5b5155ff0), u64(0x24522bc490dde65a), u64(0x241d12d41afca3c3),
	u64(0x23e7424348ca1c9c), u64(0x23b29b69070816e3), u64(0x237dc574d80cf16b),
	u64(0x2347d12a4670c123), u64(0x23130dbb6b8d674f), u64(0x22de7c5f127bd87e),
	u64(0x22a8637f41fcad32), u64(0x227382cc34ca2428), u64(0x223f37ad21436d0c),
	u64(0x2208f9574dcf8a70), u64(0x21d3faac3e3fa1f3), u64(0x219ff779fd329cb9),
	u64(0x216992c7fdc216fa), u64(0x2134756ccb01abfb), u64(0x21005df0a267bcc9),
	u64(0x20ca2fe76a3f9475), u64(0x2094f31f8832dd2a), u64(0x2060c27fa028b0ef),
	u64(0x202ad0cc33744e4b), u64(0x1ff573d68f903ea2), u64(0x1fc1297872d9cbb5),
	u64(0x1f8b758d848fac55), u64(0x1f55f7a46a0c89dd), u64(0x1f2192e9ee706e4b),
	u64(0x1eec1e43171a4a11), u64(0x1eb67e9c127b6e74), u64(0x1e81fee341fc585d),
	u64(0x1e4ccb0536608d61), u64(0x1e1708d0f84d3de7), u64(0x1de26d73f9d764b9),
	u64(0x1dad7becc2f23ac2), u64(0x1d779657025b6235), u64(0x1d42deac01e2b4f7),
	u64(0x1d0e3113363787f2), u64(0x1cd8274291c6065b), u64(0x1ca3529ba7d19eaf),
	u64(0x1c6eea92a61c3118), u64(0x1c38bba884e35a7a), u64(0x1c03c9539d82aec8),
	u64(0x1bcfa885c8d117a6), u64(0x1b99539e3a40dfb8), u64(0x1b6442e4fb671960),
	u64(0x1b303583fc527ab3), u64(0x1af9ef3993b72ab8), u64(0x1ac4bf6142f8eefa),
	u64(0x1a90991a9bfa58c8), u64(0x1a5a8e90f9908e0d), u64(0x1a253eda614071a4),
	u64(0x19f0ff151a99f483), u64(0x19bb31bb5dc320d2), u64(0x1985c162b168e70e),
	u64(0x1951678227871f3e), u64(0x191bd8d03f3e9864), u64(0x18e6470cff6546b6),
	u64(0x18b1d270cc51055f), u64(0x187c83e7ad4e6efe), u64(0x1846cfec8aa52598),
	u64(0x18123ff06eea847a), u64(0x17dd331a4b10d3f6), u64(0x17a75c1508da432b),
	u64(0x1772b010d3e1cf56), u64(0x173de6815302e556), u64(0x1707eb9aa8cf1dde),
	u64(0x16d322e220a5b17e), u64(0x169e9e369aa2b597), u64(0x16687e92154ef7ac),
	u64(0x16339874ddd8c623), u64(0x15ff5a549627a36c), u64(0x15c91510781fb5f0),
	u64(0x159410d9f9b2f7f3), u64(0x15600d7b2e28c65c), u64(0x1529af2b7d0e0a2d),
	u64(0x14f48c22ca71a1bd), u64(0x14c0701bd527b498), u64(0x148a4cf9550c5426),
	u64(0x14550a6110d6a9b8), u64(0x1420d51a73deee2d), u64(0x13eaee90b964b047),
	u64(0x13b58ba6fab6f36c), u64(0x13813c85955f2923), u64(0x134b9408eefea839),
	u64(0x1316100725988694), u64(0x12e1a66c1e139edd), u64(0x12ac3d79c9b8fe2e),
	u64(0x12769794a160cb58), u64(0x124212dd4de70913), u64(0x120ceafbafd80e85),
	u64(0x11d72262f3133ed1), u64(0x11a281e8c275cbda), u64(0x116d9ca79d89462a),
	u64(0x1137b08617a104ee), u64(0x1102f39e794d9d8b), u64(0x10ce5297287c2f45),
	u64(0x1098421286c9bf6b), u64(0x1063680ed23aff89), u64(0x102f0ce4839198db),
	u64(0x0ff8d71d360e13e2), u64(0x0fc3df4a91a4dcb5), u64(0x0f8fcbaa82a16121),
	u64(0x0f596fbb9bb44db4), u64(0x0f245962e2f6a490), u64(0x0ef047824f2bb6da),
	u64(0x0eba0c03b1df8af6), u64(0x0e84d6695b193bf8), u64(0x0e50ab877c142ffa),
	u64(0x0e1aac0bf9b9e65c), u64(0x0de5566ffafb1eb0), u64(0x0db111f32f2f4bc0),
	u64(0x0d7b4feb7eb212cd), u64(0x0d45d98932280f0a), u64(0x0d117ad428200c08),
	u64(0x0cdbf7b9d9cce00d), u64(0x0ca65fc7e170b33e), u64(0x0c71e6398126f5cb),
	u64(0x0c3ca38f350b22df), u64(0x0c06e93f5da2824c), u64(0x0bd25432b14ecea3),
	u64(0x0b9d53844ee47dd1), u64(0x0b677603725064a8), u64(0x0b32c4cf8ea6b6ec),
	u64(0x0afe07b27dd78b14), u64(0x0ac8062864ac6f43), u64(0x0a9338205089f29c),
	u64(0x0a5ec033b40fea93), u64(0x0a2899c2f6732210), u64(0x09f3ae3591f5b4d9),
	u64(0x09bf7d228322baf5), u64(0x098930e868e89591), u64(0x0954272053ed4474),
	u64(0x09201f4d0ff10390), u64(0x08e9cbae7fe805b3), u64(0x08b4a2f1ffecd15c),
	u64(0x0880825b3323dab0), u64(0x084a6a2b85062ab3), u64(0x081521bc6a6b555c),
	u64(0x07e0e7c9eebc444a), u64(0x07ab0c764ac6d3a9), u64(0x0775a391d56bdc87),
	u64(0x07414fa7ddefe3a0), u64(0x070bb2a62fe638ff), u64(0x06d62884f31e93ff),
	u64(0x06a1ba03f5b21000), u64(0x066c5cd322b67fff), u64(0x0636b0a8e891ffff),
	u64(0x060226ed86db3333), u64(0x05cd0b15a491eb84), u64(0x05973c115074bc6a),
	u64(0x05629674405d6388), u64(0x052dbd86cd6238d9), u64(0x04f7cad23de82d7b),
	u64(0x04c308a831868ac9), u64(0x048e74404f3daadb), u64(0x04585d003f6488af),
	u64(0x04237d99cc506d59), u64(0x03ef2f5c7a1a488e), u64(0x03b8f2b061aea072),
	u64(0x0383f559e7bee6c1), u64(0x034feef63f97d79c), u64(0x03198bf832dfdfb0),
	u64(0x02e46ff9c24cb2f3), u64(0x02b059949b708f29), u64(0x027a28edc580e50e),
	u64(0x0244ed8b04671da5), u64(0x0210be08d0527e1d), u64(0x01dac9a7b3b7302f),
	u64(0x01a56e1fc2f8f359), u64(0x017124e63593f5e1), u64(0x013b6e3d22865634),
	u64(0x0105f1ca820511c3), u64(0x00d18e3b9b374169), u64(0x009c16c5c5253575),
	u64(0x0066789e3750f791), u64(0x0031fa182c40c60d), u64(0x000730d67819e8d2),
	u64(0x0000b8157268fdaf), u64(0x000012688b70e62b), u64(0x000001d74124e3d1),
	u64(0x0000002f201d49fb), u64(0x00000004b6695433), u64(0x0000000078a42205),
	u64(0x000000000c1069cd), u64(0x000000000134d761), u64(0x00000000001ee257),
	u64(0x00000000000316a2), u64(0x0000000000004f10), u64(0x00000000000007e8),
	u64(0x00000000000000ca), u64(0x0000000000000014), u64(0x0000000000000002)]!


// Copyright (c) 2019-2024 Alexander Medvednikov. All rights reserved.
// Use of this source code is governed by an MIT license
// that can be found in the LICENSE file.
// TODO: use options, or some way to return default with error.
// int_size is the size in bits of an int or uint value.
// int_size = 32 << (~u32(0) >> 63)
// max_u64 = u64(u64(1 << 63) - 1)
const int_size = 32

@[inline]
pub fn byte_to_lower(c u8) u8 {
	return c | 32
}

// common_parse_uint is called by parse_uint and allows the parsing
// to stop on non or invalid digit characters and return with an error
pub fn common_parse_uint(s string, _base int, _bit_size int, error_on_non_digit bool, error_on_high_digit bool) !u64 {
	result, err := common_parse_uint2(s, _base, _bit_size)
	// TODO: error_on_non_digit and error_on_high_digit have no difference
	if err != 0 && (error_on_non_digit || error_on_high_digit) {
		match err {
			-1 { return error('common_parse_uint: wrong base ${_base} for ${s}') }
			-2 { return error('common_parse_uint: wrong bit size ${_bit_size} for ${s}') }
			-3 { return error('common_parse_uint: integer overflow ${s}') }
			else { return error('common_parse_uint: syntax error ${s}') }
		}
	}
	return result
}

// the first returned value contains the parsed value,
// the second returned value contains the error code (0 = OK, >1 = index of first non-parseable character + 1, -1 = wrong base, -2 = wrong bit size, -3 = overflow)
@[direct_array_access]
pub fn common_parse_uint2(s string, _base int, _bit_size int) (u64, int) {
	if s == '' {
		return u64(0), 1
	}

	mut bit_size := _bit_size
	mut base := _base
	mut start_index := 0

	if base == 0 {
		// Look for octal, binary and hex prefix.
		base = 10
		if s[0] == `0` {
			ch := if s.len > 1 { s[1] | 32 } else { `0` }
			if s.len >= 3 {
				if ch == `b` {
					base = 2
					start_index += 2
				} else if ch == `o` {
					base = 8
					start_index += 2
				} else if ch == `x` {
					base = 16
					start_index += 2
				}

				// check for underscore after the base prefix
				if s[start_index] == `_` {
					start_index++
				}
			}
			// manage leading zeros in decimal base's numbers
			// otherwise it is an octal for C compatibility
			// TODO: Check if this behaviour is logically right
			else if s.len >= 2 && (s[1] >= `0` && s[1] <= `9`) {
				base = 10
				start_index++
			} else {
				base = 8
				start_index++
			}
		}
	}

	if bit_size == 0 {
		bit_size = int_size
	} else if bit_size < 0 || bit_size > 64 {
		return u64(0), -2
	}
	// Cutoff is the smallest number such that cutoff*base > maxUint64.
	// Use compile-time constants for common cases.
	cutoff := max_u64 / u64(base) + u64(1)
	max_val := if bit_size == 64 { max_u64 } else { (u64(1) << u64(bit_size)) - u64(1) }
	basem1 := base - 1

	mut n := u64(0)
	for i in start_index .. s.len {
		mut c := s[i]

		// manage underscore inside the number
		if c == `_` {
			if i == start_index || i >= (s.len - 1) {
				// println("_ limit")
				return u64(0), 1
			}
			if s[i - 1] == `_` || s[i + 1] == `_` {
				// println("_ *2")
				return u64(0), 1
			}

			continue
		}

		mut sub_count := 0

		// get the 0-9 digit
		c -= 48 // subtract the rune `0`

		// check if we are in the superior base rune interval [A..Z]
		if c >= 17 { // (65 - 48)
			sub_count++
			c -= 7 // subtract the `A` - `0` rune to obtain the value of the digit

			// check if we are in the superior base rune interval [a..z]
			if c >= 42 { // (97 - 7 - 48)
				sub_count++
				c -= 32 // subtract the `a` - `0` rune to obtain the value of the digit
			}
		}

		// check for digit over base
		if c > basem1 || (sub_count == 0 && c > 9) {
			return n, i + 1
		}

		// check if we are in the cutoff zone
		if n >= cutoff {
			// n*base overflows
			// return error('parse_uint: range error $s')
			return max_val, -3
		}
		n *= u64(base)
		n1 := n + u64(c)
		if n1 < n || n1 > max_val {
			// n+v overflows
			// return error('parse_uint: range error $s')
			return max_val, -3
		}
		n = n1
	}
	return n, 0
}

// parse_uint is like parse_int but for unsigned numbers.
pub fn parse_uint(s string, _base int, _bit_size int) !u64 {
	return common_parse_uint(s, _base, _bit_size, true, true)
}

// common_parse_int is called by parse int and allows the parsing
// to stop on non or invalid digit characters and return with an error
@[direct_array_access]
pub fn common_parse_int(_s string, base int, _bit_size int, error_on_non_digit bool, error_on_high_digit bool) !i64 {
	if _s == '' {
		// return error('parse_int: syntax error $s')
		return i64(0)
	}
	mut bit_size := _bit_size
	if bit_size == 0 {
		bit_size = int_size
	}
	mut s := _s
	// Pick off leading sign.
	mut neg := false
	if s[0] == `+` {
		// s = s[1..]
		unsafe {
			s = tos(s.str + 1, s.len - 1)
		}
	} else if s[0] == `-` {
		neg = true
		// s = s[1..]
		unsafe {
			s = tos(s.str + 1, s.len - 1)
		}
	}

	// Convert unsigned and check range.
	// un := parse_uint(s, base, bit_size) or {
	// return i64(0)
	// }
	un := common_parse_uint(s, base, bit_size, error_on_non_digit, error_on_high_digit)!
	if un == 0 {
		return i64(0)
	}
	// TODO: check should u64(bit_size-1) be size of int (32)?
	cutoff := u64(1) << u64(bit_size - 1)
	if !neg && un >= cutoff {
		// return error('parse_int: range error $s0')
		return i64(cutoff - u64(1))
	}
	if neg && un > cutoff {
		// return error('parse_int: range error $s0')
		return -i64(cutoff)
	}
	return if neg { -i64(un) } else { i64(un) }
}

// parse_int interprets a string s in the given base (0, 2 to 36) and
// bit size (0 to 64) and returns the corresponding value i.
//
// If the base argument is 0, the true base is implied by the string's
// prefix: 2 for "0b", 8 for "0" or "0o", 16 for "0x", and 10 otherwise.
// Also, for argument base 0 only, underscore characters are permitted
// as defined by the Go syntax for integer literals.
//
// The bitSize argument specifies the integer type
// that the result must fit into. Bit sizes 0, 8, 16, 32, and 64
// correspond to int, int8, int16, int32, and int64.
// If bitSize is below 0 or above 64, an error is returned.
pub fn parse_int(_s string, base int, _bit_size int) !i64 {
	return common_parse_int(_s, base, _bit_size, true, true)
}

// atoi_common_check perform basics check on string to parse:
// Test emptiness, + or - sign presence, presence of digit after signs and no
// underscore as first character.
// returns +1 or -1 depending on sign, and s first digit index or an error.
@[direct_array_access]
fn atoi_common_check(s string) !(i64, int) {
	if s == '' {
		return error('strconv.atoi: parsing "": empty string')
	}

	mut start_idx := 0
	mut sign := i64(1)

	if s[0] == `-` || s[0] == `+` {
		start_idx++
		if s[0] == `-` {
			sign = -1
		}
	}

	if s.len - start_idx < 1 {
		return error('strconv.atoi: parsing "${s}": no number after sign')
	}

	if s[start_idx] == `_` || s[s.len - 1] == `_` {
		return error('strconv.atoi: parsing "${s}": values cannot start or end with underscores')
	}
	return sign, start_idx
}

// atoi_common performs computation for all i8, i16 and i32 type, excluding i64.
// Parse values, and returns consistent error message over differents types.
// s is string to parse, type_min/max are respective types min/max values.
@[direct_array_access]
fn atoi_common(s string, type_min i64, type_max i64) !i64 {
	mut sign, mut start_idx := atoi_common_check(s)!
	mut x := i64(0)
	mut underscored := false
	for i in start_idx .. s.len {
		c := s[i] - `0`
		if c == 47 { // 47 = Ascii(`_`) -  ascii(`0`) = 95 - 48.
			if underscored == true { // Two consecutives underscore
				return error('strconv.atoi: parsing "${s}": consecutives underscores are not allowed')
			}
			underscored = true
			continue // Skip underscore
		} else {
			if c > 9 {
				return error('strconv.atoi: parsing "${s}": invalid radix 10 character')
			}
			underscored = false
			x = (x * 10) + (c * sign)
			if sign == 1 && x > type_max {
				return error('strconv.atoi: parsing "${s}": integer overflow')
			} else {
				if x < type_min {
					return error('strconv.atoi: parsing "${s}": integer underflow')
				}
			}
		}
	}
	return x
}

// atoi is equivalent to parse_int(s, 10, 0), converted to type int.
// It follows V scanner as much as observed.
pub fn atoi(s string) !int {
	return int(atoi_common(s, i64_min_int32, i64_max_int32)!)
}

// atoi8 is equivalent to atoi(s), converted to type i8.
// returns an i8 [-128 .. 127] or an error.
pub fn atoi8(s string) !i8 {
	return i8(atoi_common(s, min_i8, max_i8)!)
}

// atoi16 is equivalent to atoi(s), converted to type i16.
// returns an i16 [-32678 .. 32767] or an error.
pub fn atoi16(s string) !i16 {
	return i16(atoi_common(s, min_i16, max_i16)!)
}

// atoi32 is equivalent to atoi(s), converted to type i32.
// returns an i32 [-2147483648 .. 2147483647] or an error.
pub fn atoi32(s string) !i32 {
	return i32(atoi_common(s, min_i32, max_i32)!)
}

// atoi64 converts radix 10 string to i64 type.
// returns an i64 [-9223372036854775808 .. 9223372036854775807] or an error.
@[direct_array_access]
pub fn atoi64(s string) !i64 {
	mut sign, mut start_idx := atoi_common_check(s)!
	mut x := i64(0)
	mut underscored := false
	for i in start_idx .. s.len {
		c := s[i] - `0`
		if c == 47 { // 47 = Ascii(`_`) -  ascii(`0`) = 95 - 48.
			if underscored == true { // Two consecutives underscore
				return error('strconv.atoi64: parsing "${s}": consecutives underscores are not allowed')
			}
			underscored = true
			continue // Skip underscore
		} else {
			if c > 9 {
				return error('strconv.atoi64: parsing "${s}": invalid radix 10 character')
			}
			underscored = false
			x = safe_mul10_64bits(x) or { return error('strconv.atoi64: parsing "${s}": ${err}') }
			x = safe_add_64bits(x, int(c * sign)) or {
				return error('strconv.atoi64: parsing "${s}": ${err}')
			}
		}
	}
	return x
}

// safe_add64 performs a signed 64 bits addition and returns an error
// in case of overflow or underflow.
@[inline]
fn safe_add_64bits(a i64, b i64) !i64 {
	if a > 0 && b > (max_i64 - a) {
		return error('integer overflow')
	} else if a < 0 && b < (min_i64 - a) {
		return error('integer underflow')
	}
	return a + b
}

// safe_mul10 performs a * 10 multiplication and returns an error
// in case of overflow or underflow.
@[inline]
fn safe_mul10_64bits(a i64) !i64 {
	if a > 0 && a > (max_i64 / 10) {
		return error('integer overflow')
	}
	if a < 0 && a < (min_i64 / 10) {
		return error('integer underflow')
	}
	return a * 10
}

const i64_min_int32 = i64(-2147483647) - 1 // msvc has a bug that treats just i64(min_int) as 2147483648 :-(; this is a workaround for it
const i64_max_int32 = i64(2147483646) + 1
// Copyright (c) 2019-2024 V language community. All rights reserved.
// Use of this source code is governed by an MIT license
// that can be found in the LICENSE file.

// atou_common_check perform basics check on unsigned string to parse.
// Test emptiness, + sign presence, absence of minus sign, presence of digit after
// signs and no underscore as first character.
// returns s first digit index or an error.
@[direct_array_access]
fn atou_common_check(s string) !int {
	if s == '' {
		return error('strconv.atou: parsing "": empty string')
	}

	mut start_idx := 0

	if s[0] == `-` {
		return error('strconv.atou: parsing "{s}" : negative value')
	}

	if s[0] == `+` {
		start_idx++
	}

	if s.len - start_idx < 1 {
		return error('strconv.atou: parsing "${s}": no number after sign')
	}

	if s[start_idx] == `_` || s[s.len - 1] == `_` {
		return error('strconv.atou: parsing "${s}": values cannot start or end with underscores')
	}
	return start_idx
}

// atou_common performs computation for all u8, u16 and u32 type, excluding i64.
// Parse values, and returns consistent error message over differents types.
// s is string to parse, max is respective types max value.
@[direct_array_access]
fn atou_common(s string, type_max u64) !u64 {
	mut start_idx := atou_common_check(s)!
	mut x := u64(0)
	mut underscored := false
	for i in start_idx .. s.len {
		c := s[i] - `0`
		if c == 47 { // 47 = Ascii(`_`) -  ascii(`0`) = 95 - 48.
			if underscored == true { // Two consecutives underscore
				return error('strconv.atou: parsing "${s}": consecutives underscores are not allowed')
			}
			underscored = true
			continue // Skip underscore
		} else {
			if c > 9 {
				return error('strconv.atou: parsing "${s}": invalid radix 10 character')
			}
			underscored = false

			oldx := x
			x = (x * 10) + u64(c)
			if x > type_max || oldx > x {
				return error('strconv.atou: parsing "${s}": integer overflow')
			}
		}
	}
	return x
}

// atou8 is equivalent to parse_uint(s, 10, 0), converted to type u8.
// It returns u8 in range [0..255] or an Error.
pub fn atou8(s string) !u8 {
	return u8(atou_common(s, max_u8)!)
}

// atou16 is equivalent to parse_uint(s, 10, 0), converted to type u16.
// It returns u16 in range [0..65535] or an Error.
pub fn atou16(s string) !u16 {
	return u16(atou_common(s, max_u16)!)
}

// atou is equivalent to parse_uint(s, 10, 0), converted to type u32.
pub fn atou(s string) !u32 {
	return u32(atou_common(s, max_u32)!)
}

// atou32 is identical to atou. Here to provide a symmetrical API with atoi/atoi32
// It returns u32 in range [0..4294967295] or an Error.
pub fn atou32(s string) !u32 {
	return u32(atou_common(s, max_u32)!)
}

// atou64 is equivalent to parse_uint(s, 10, 0), converted to type u64.
// It returns u64 in range [0..18446744073709551615] or an Error.
pub fn atou64(s string) !u64 {
	return u64(atou_common(s, max_u64)!)
}

/*=============================================================================

f32 to string

Copyright (c) 2019-2024 Dario Deledda. All rights reserved.
Use of this source code is governed by an MIT license
that can be found in the LICENSE file.

This file contains the f32 to string functions

These functions are based on the work of:
Publication:PLDI 2018: Proceedings of the 39th ACM SIGPLAN
Conference on Programming Language Design and ImplementationJune 2018
Pages 270–282 https://doi.org/10.1145/3192366.3192369

inspired by the Go version here:
https://github.com/cespare/ryu/tree/ba56a33f39e3bbbfa409095d0f9ae168a595feea

=============================================================================*/

// pow of ten table used by n_digit reduction
const ten_pow_table_32 = [
	u32(1),
	u32(10),
	u32(100),
	u32(1000),
	u32(10000),
	u32(100000),
	u32(1000000),
	u32(10000000),
	u32(100000000),
	u32(1000000000),
]!

//=============================================================================
// Conversion Functions
//=============================================================================
const mantbits32 = u32(23)
const expbits32 = u32(8)
const bias32 = 127 // f32 exponent bias

const maxexp32 = 255

// max 46 char
// -3.40282346638528859811704183484516925440e+38
@[direct_array_access]
pub fn (d Dec32) get_string_32(neg bool, i_n_digit int, i_pad_digit int) string {
	n_digit := i_n_digit + 1
	pad_digit := i_pad_digit + 1
	mut out := d.m
	// mut out_len      := decimal_len_32(out)
	mut out_len := dec_digits(out)
	out_len_original := out_len

	mut fw_zeros := 0
	if pad_digit > out_len {
		fw_zeros = pad_digit - out_len
	}

	mut buf := []u8{len: int(out_len + 5 + 1 + 1)} // sign + mant_len + . +  e + e_sign + exp_len(2) + \0}
	mut i := 0

	if neg {
		if buf.data != 0 {
			// The buf.data != 0 check here, is needed for clean compilation
			// with `-cc gcc -cstrict -prod`. Without it, gcc produces:
			// error: potential null pointer dereference
			buf[i] = `-`
		}
		i++
	}

	mut disp := 0
	if out_len <= 1 {
		disp = 1
	}

	if n_digit < out_len {
		// println("orig: ${out_len_original}")
		out += ten_pow_table_32[out_len - n_digit - 1] * 5 // round to up
		out /= ten_pow_table_32[out_len - n_digit]
		out_len = n_digit
	}

	y := i + out_len
	mut x := 0
	for x < (out_len - disp - 1) {
		buf[y - x] = `0` + u8(out % 10)
		out /= 10
		i++
		x++
	}

	// no decimal digits needed, end here
	if i_n_digit == 0 {
		unsafe {
			buf[i] = 0
			return tos(&u8(&buf[0]), i)
		}
	}

	if out_len >= 1 {
		buf[y - x] = `.`
		x++
		i++
	}

	if y - x >= 0 {
		buf[y - x] = `0` + u8(out % 10)
		i++
	}

	for fw_zeros > 0 {
		buf[i] = `0`
		i++
		fw_zeros--
	}

	buf[i] = `e`
	i++

	mut exp := d.e + out_len_original - 1
	if exp < 0 {
		buf[i] = `-`
		i++
		exp = -exp
	} else {
		buf[i] = `+`
		i++
	}

	// Always print two digits to match strconv's formatting.
	d1 := exp % 10
	d0 := exp / 10
	buf[i] = `0` + u8(d0)
	i++
	buf[i] = `0` + u8(d1)
	i++
	buf[i] = 0

	return unsafe {
		tos(&u8(&buf[0]), i)
	}
}

fn f32_to_decimal_exact_int(i_mant u32, exp u32) (Dec32, bool) {
	mut d := Dec32{}
	e := exp - bias32
	if e > mantbits32 {
		return d, false
	}
	shift := mantbits32 - e
	mant := i_mant | 0x0080_0000 // implicit 1
	// mant := i_mant | (1 << mantbits32) // implicit 1
	d.m = mant >> shift
	if (d.m << shift) != mant {
		return d, false
	}
	for (d.m % 10) == 0 {
		d.m /= 10
		d.e++
	}
	return d, true
}

fn f32_to_decimal(mant u32, exp u32) Dec32 {
	mut e2 := 0
	mut m2 := u32(0)
	if exp == 0 {
		// We subtract 2 so that the bounds computation has
		// 2 additional bits.
		e2 = 1 - bias32 - int(mantbits32) - 2
		m2 = mant
	} else {
		e2 = int(exp) - bias32 - int(mantbits32) - 2
		m2 = (u32(1) << mantbits32) | mant
	}
	even := (m2 & 1) == 0
	accept_bounds := even

	// Step 2: Determine the interval of valid decimal representations.
	mv := u32(4 * m2)
	mp := u32(4 * m2 + 2)
	mm_shift := bool_to_u32(mant != 0 || exp <= 1)
	mm := u32(4 * m2 - 1 - mm_shift)

	mut vr := u32(0)
	mut vp := u32(0)
	mut vm := u32(0)
	mut e10 := 0
	mut vm_is_trailing_zeros := false
	mut vr_is_trailing_zeros := false
	mut last_removed_digit := u8(0)

	if e2 >= 0 {
		q := log10_pow2(e2)
		e10 = int(q)
		k := pow5_inv_num_bits_32 + pow5_bits(int(q)) - 1
		i := -e2 + int(q) + k

		vr = mul_pow5_invdiv_pow2(mv, q, i)
		vp = mul_pow5_invdiv_pow2(mp, q, i)
		vm = mul_pow5_invdiv_pow2(mm, q, i)
		if q != 0 && (vp - 1) / 10 <= vm / 10 {
			// We need to know one removed digit even if we are not
			// going to loop below. We could use q = X - 1 above,
			// except that would require 33 bits for the result, and
			// we've found that 32-bit arithmetic is faster even on
			// 64-bit machines.
			l := pow5_inv_num_bits_32 + pow5_bits(int(q - 1)) - 1
			last_removed_digit = u8(mul_pow5_invdiv_pow2(mv, q - 1, -e2 + int(q - 1) + l) % 10)
		}
		if q <= 9 {
			// The largest power of 5 that fits in 24 bits is 5^10,
			// but q <= 9 seems to be safe as well. Only one of mp,
			// mv, and mm can be a multiple of 5, if any.
			if mv % 5 == 0 {
				vr_is_trailing_zeros = multiple_of_power_of_five_32(mv, q)
			} else if accept_bounds {
				vm_is_trailing_zeros = multiple_of_power_of_five_32(mm, q)
			} else if multiple_of_power_of_five_32(mp, q) {
				vp--
			}
		}
	} else {
		q := log10_pow5(-e2)
		e10 = int(q) + e2
		i := -e2 - int(q)
		k := pow5_bits(i) - pow5_num_bits_32
		mut j := int(q) - k
		vr = mul_pow5_div_pow2(mv, u32(i), j)
		vp = mul_pow5_div_pow2(mp, u32(i), j)
		vm = mul_pow5_div_pow2(mm, u32(i), j)
		if q != 0 && ((vp - 1) / 10) <= vm / 10 {
			j = int(q) - 1 - (pow5_bits(i + 1) - pow5_num_bits_32)
			last_removed_digit = u8(mul_pow5_div_pow2(mv, u32(i + 1), j) % 10)
		}
		if q <= 1 {
			// {vr,vp,vm} is trailing zeros if {mv,mp,mm} has at
			// least q trailing 0 bits. mv = 4 * m2, so it always
			// has at least two trailing 0 bits.
			vr_is_trailing_zeros = true
			if accept_bounds {
				// mm = mv - 1 - mm_shift, so it has 1 trailing 0 bit
				// if mm_shift == 1.
				vm_is_trailing_zeros = mm_shift == 1
			} else {
				// mp = mv + 2, so it always has at least one
				// trailing 0 bit.
				vp--
			}
		} else if q < 31 {
			vr_is_trailing_zeros = multiple_of_power_of_two_32(mv, q - 1)
		}
	}

	// Step 4: Find the shortest decimal representation
	// in the interval of valid representations.
	mut removed := 0
	mut out := u32(0)
	if vm_is_trailing_zeros || vr_is_trailing_zeros {
		// General case, which happens rarely (~4.0%).
		for vp / 10 > vm / 10 {
			vm_is_trailing_zeros = vm_is_trailing_zeros && (vm % 10) == 0
			vr_is_trailing_zeros = vr_is_trailing_zeros && last_removed_digit == 0
			last_removed_digit = u8(vr % 10)
			vr /= 10
			vp /= 10
			vm /= 10
			removed++
		}
		if vm_is_trailing_zeros {
			for vm % 10 == 0 {
				vr_is_trailing_zeros = vr_is_trailing_zeros && last_removed_digit == 0
				last_removed_digit = u8(vr % 10)
				vr /= 10
				vp /= 10
				vm /= 10
				removed++
			}
		}
		if vr_is_trailing_zeros && last_removed_digit == 5 && (vr % 2) == 0 {
			// Round even if the exact number is .....50..0.
			last_removed_digit = 4
		}
		out = vr
		// We need to take vr + 1 if vr is outside bounds
		// or we need to round up.
		if (vr == vm && (!accept_bounds || !vm_is_trailing_zeros)) || last_removed_digit >= 5 {
			out++
		}
	} else {
		// Specialized for the common case (~96.0%). Percentages below
		// are relative to this. Loop iterations below (approximately):
		// 0: 13.6%, 1: 70.7%, 2: 14.1%, 3: 1.39%, 4: 0.14%, 5+: 0.01%
		for vp / 10 > vm / 10 {
			last_removed_digit = u8(vr % 10)
			vr /= 10
			vp /= 10
			vm /= 10
			removed++
		}
		// We need to take vr + 1 if vr is outside bounds
		// or we need to round up.
		out = vr + bool_to_u32(vr == vm || last_removed_digit >= 5)
	}

	return Dec32{
		m: out
		e: e10 + removed
	}
}

//=============================================================================
// String Functions
//=============================================================================

// f32_to_str returns a `string` in scientific notation with max `n_digit` after the dot.
pub fn f32_to_str(f f32, n_digit int) string {
	mut u1 := Uf32{}
	u1.f = f
	u := unsafe { u1.u }

	neg := (u >> (mantbits32 + expbits32)) != 0
	mant := u & ((u32(1) << mantbits32) - u32(1))
	exp := (u >> mantbits32) & ((u32(1) << expbits32) - u32(1))

	// println("${neg} ${mant} e ${exp-bias32}")

	// Exit early for easy cases.
	if exp == maxexp32 || (exp == 0 && mant == 0) {
		return get_string_special(neg, exp == 0, mant == 0)
	}

	mut d, ok := f32_to_decimal_exact_int(mant, exp)
	if !ok {
		// println("with exp form")
		d = f32_to_decimal(mant, exp)
	}

	// println("${d.m} ${d.e}")
	return d.get_string_32(neg, n_digit, 0)
}

// f32_to_str_pad returns a `string` in scientific notation with max `n_digit` after the dot.
pub fn f32_to_str_pad(f f32, n_digit int) string {
	mut u1 := Uf32{}
	u1.f = f
	u := unsafe { u1.u }

	neg := (u >> (mantbits32 + expbits32)) != 0
	mant := u & ((u32(1) << mantbits32) - u32(1))
	exp := (u >> mantbits32) & ((u32(1) << expbits32) - u32(1))

	// println("${neg} ${mant} e ${exp-bias32}")

	// Exit early for easy cases.
	if exp == maxexp32 || (exp == 0 && mant == 0) {
		return get_string_special(neg, exp == 0, mant == 0)
	}

	mut d, ok := f32_to_decimal_exact_int(mant, exp)
	if !ok {
		// println("with exp form")
		d = f32_to_decimal(mant, exp)
	}

	// println("${d.m} ${d.e}")
	return d.get_string_32(neg, n_digit, n_digit)
}

/*=============================================================================

f64 to string

Copyright (c) 2019-2024 Dario Deledda. All rights reserved.
Use of this source code is governed by an MIT license
that can be found in the LICENSE file.

This file contains the f64 to string functions

These functions are based on the work of:
Publication:PLDI 2018: Proceedings of the 39th ACM SIGPLAN
Conference on Programming Language Design and ImplementationJune 2018
Pages 270–282 https://doi.org/10.1145/3192366.3192369

inspired by the Go version here:
https://github.com/cespare/ryu/tree/ba56a33f39e3bbbfa409095d0f9ae168a595feea

=============================================================================*/

@[direct_array_access]
fn (d Dec64) get_string_64(neg bool, i_n_digit int, i_pad_digit int) string {
	mut n_digit := if i_n_digit < 1 { 1 } else { i_n_digit + 1 }
	pad_digit := i_pad_digit + 1
	mut out := d.m
	mut d_exp := d.e
	// mut out_len      := decimal_len_64(out)
	mut out_len := dec_digits(out)
	out_len_original := out_len

	mut fw_zeros := 0
	if pad_digit > out_len {
		fw_zeros = pad_digit - out_len
	}

	mut buf := []u8{len: (out_len + 6 + 1 + 1 + fw_zeros)} // sign + mant_len + . +  e + e_sign + exp_len(2) + \0}
	mut i := 0

	if neg {
		buf[i] = `-`
		i++
	}

	mut disp := 0
	if out_len <= 1 {
		disp = 1
	}

	// rounding last used digit
	if n_digit < out_len {
		// println("out:[$out]")
		out += ten_pow_table_64[out_len - n_digit - 1] * 5 // round to up
		out /= ten_pow_table_64[out_len - n_digit]
		// println("out1:[$out] ${d.m / ten_pow_table_64[out_len - n_digit ]}")
		// fix issue #22424
		out_div := d.m / ten_pow_table_64[out_len - n_digit]
		if out_div < out && dec_digits(out_div) < dec_digits(out) {
			// from `99` to `100`, will need d_exp+1
			d_exp++
			n_digit++
		}

		// println("cmp: ${d.m/ten_pow_table_64[out_len - n_digit ]} ${out/ten_pow_table_64[out_len - n_digit ]}")

		out_len = n_digit
		// println("orig: ${out_len_original} new len: ${out_len} out:[$out]")
	}

	y := i + out_len
	mut x := 0
	for x < (out_len - disp - 1) {
		buf[y - x] = `0` + u8(out % 10)
		out /= 10
		i++
		x++
	}

	// fix issue #22424
	// no decimal digits needed, end here
	// if i_n_digit == 0 {
	//	unsafe {
	//		buf[i] = 0
	//		return tos(&u8(&buf[0]), i)
	//	}
	//}

	if out_len >= 1 {
		buf[y - x] = `.`
		x++
		i++
	}

	if y - x >= 0 {
		buf[y - x] = `0` + u8(out % 10)
		i++
	}

	for fw_zeros > 0 {
		buf[i] = `0`
		i++
		fw_zeros--
	}

	buf[i] = `e`
	i++

	mut exp := d_exp + out_len_original - 1
	if exp < 0 {
		buf[i] = `-`
		i++
		exp = -exp
	} else {
		buf[i] = `+`
		i++
	}

	// Always print at least two digits to match strconv's formatting.
	d2 := exp % 10
	exp /= 10
	d1 := exp % 10
	d0 := exp / 10
	if d0 > 0 {
		buf[i] = `0` + u8(d0)
		i++
	}
	buf[i] = `0` + u8(d1)
	i++
	buf[i] = `0` + u8(d2)
	i++
	buf[i] = 0

	return unsafe {
		tos(&u8(&buf[0]), i)
	}
}

@[ignore_overflow]
fn f64_to_decimal_exact_int(i_mant u64, exp u64) (Dec64, bool) {
	mut d := Dec64{}
	e := exp - bias64
	if e > mantbits64 {
		return d, false
	}
	shift := mantbits64 - e
	mant := i_mant | u64(0x0010_0000_0000_0000) // implicit 1
	// mant  := i_mant | (1 << mantbits64) // implicit 1
	d.m = mant >> shift
	if (d.m << shift) != mant {
		return d, false
	}

	for (d.m % 10) == 0 {
		d.m /= 10
		d.e++
	}
	return d, true
}

fn f64_to_decimal(mant u64, exp u64) Dec64 {
	mut e2 := 0
	mut m2 := u64(0)
	if exp == 0 {
		// We subtract 2 so that the bounds computation has
		// 2 additional bits.
		e2 = 1 - bias64 - int(mantbits64) - 2
		m2 = mant
	} else {
		e2 = int(exp) - bias64 - int(mantbits64) - 2
		m2 = (u64(1) << mantbits64) | mant
	}
	even := (m2 & 1) == 0
	accept_bounds := even

	// Step 2: Determine the interval of valid decimal representations.
	mv := u64(4 * m2)
	mm_shift := bool_to_u64(mant != 0 || exp <= 1)

	// Step 3: Convert to a decimal power base uing 128-bit arithmetic.
	mut vr := u64(0)
	mut vp := u64(0)
	mut vm := u64(0)
	mut e10 := 0
	mut vm_is_trailing_zeros := false
	mut vr_is_trailing_zeros := false

	if e2 >= 0 {
		// This expression is slightly faster than max(0, log10Pow2(e2) - 1).
		q := log10_pow2(e2) - bool_to_u32(e2 > 3)
		e10 = int(q)
		k := pow5_inv_num_bits_64 + pow5_bits(int(q)) - 1
		i := -e2 + int(q) + k

		mul := *(&Uint128(&pow5_inv_split_64_x[q * 2]))
		vr = mul_shift_64(u64(4) * m2, mul, i)
		vp = mul_shift_64(u64(4) * m2 + u64(2), mul, i)
		vm = mul_shift_64(u64(4) * m2 - u64(1) - mm_shift, mul, i)
		if q <= 21 {
			// This should use q <= 22, but I think 21 is also safe.
			// Smaller values may still be safe, but it's more
			// difficult to reason about them. Only one of mp, mv,
			// and mm can be a multiple of 5, if any.
			if mv % 5 == 0 {
				vr_is_trailing_zeros = multiple_of_power_of_five_64(mv, q)
			} else if accept_bounds {
				// Same as min(e2 + (^mm & 1), pow5Factor64(mm)) >= q
				// <=> e2 + (^mm & 1) >= q && pow5Factor64(mm) >= q
				// <=> true && pow5Factor64(mm) >= q, since e2 >= q.
				vm_is_trailing_zeros = multiple_of_power_of_five_64(mv - 1 - mm_shift,
					q)
			} else if multiple_of_power_of_five_64(mv + 2, q) {
				vp--
			}
		}
	} else {
		// This expression is slightly faster than max(0, log10Pow5(-e2) - 1).
		q := log10_pow5(-e2) - bool_to_u32(-e2 > 1)
		e10 = int(q) + e2
		i := -e2 - int(q)
		k := pow5_bits(i) - pow5_num_bits_64
		j := int(q) - k
		mul := *(&Uint128(&pow5_split_64_x[i * 2]))
		vr = mul_shift_64(u64(4) * m2, mul, j)
		vp = mul_shift_64(u64(4) * m2 + u64(2), mul, j)
		vm = mul_shift_64(u64(4) * m2 - u64(1) - mm_shift, mul, j)
		if q <= 1 {
			// {vr,vp,vm} is trailing zeros if {mv,mp,mm} has at least q trailing 0 bits.
			// mv = 4 * m2, so it always has at least two trailing 0 bits.
			vr_is_trailing_zeros = true
			if accept_bounds {
				// mm = mv - 1 - mmShift, so it has 1 trailing 0 bit iff mmShift == 1.
				vm_is_trailing_zeros = (mm_shift == 1)
			} else {
				// mp = mv + 2, so it always has at least one trailing 0 bit.
				vp--
			}
		} else if q < 63 { // TODO(ulfjack/cespare): Use a tighter bound here.
			// We need to compute min(ntz(mv), pow5Factor64(mv) - e2) >= q - 1
			// <=> ntz(mv) >= q - 1 && pow5Factor64(mv) - e2 >= q - 1
			// <=> ntz(mv) >= q - 1 (e2 is negative and -e2 >= q)
			// <=> (mv & ((1 << (q - 1)) - 1)) == 0
			// We also need to make sure that the left shift does not overflow.
			vr_is_trailing_zeros = multiple_of_power_of_two_64(mv, q - 1)
		}
	}

	// Step 4: Find the shortest decimal representation
	// in the interval of valid representations.
	mut removed := 0
	mut last_removed_digit := u8(0)
	mut out := u64(0)
	// On average, we remove ~2 digits.
	if vm_is_trailing_zeros || vr_is_trailing_zeros {
		// General case, which happens rarely (~0.7%).
		for {
			vp_div_10 := vp / 10
			vm_div_10 := vm / 10
			if vp_div_10 <= vm_div_10 {
				break
			}
			vm_mod_10 := vm % 10
			vr_div_10 := vr / 10
			vr_mod_10 := vr % 10
			vm_is_trailing_zeros = vm_is_trailing_zeros && vm_mod_10 == 0
			vr_is_trailing_zeros = vr_is_trailing_zeros && last_removed_digit == 0
			last_removed_digit = u8(vr_mod_10)
			vr = vr_div_10
			vp = vp_div_10
			vm = vm_div_10
			removed++
		}
		if vm_is_trailing_zeros {
			for {
				vm_div_10 := vm / 10
				vm_mod_10 := vm % 10
				if vm_mod_10 != 0 {
					break
				}
				vp_div_10 := vp / 10
				vr_div_10 := vr / 10
				vr_mod_10 := vr % 10
				vr_is_trailing_zeros = vr_is_trailing_zeros && last_removed_digit == 0
				last_removed_digit = u8(vr_mod_10)
				vr = vr_div_10
				vp = vp_div_10
				vm = vm_div_10
				removed++
			}
		}
		if vr_is_trailing_zeros && last_removed_digit == 5 && (vr % 2) == 0 {
			// Round even if the exact number is .....50..0.
			last_removed_digit = 4
		}
		out = vr
		// We need to take vr + 1 if vr is outside bounds
		// or we need to round up.
		if (vr == vm && (!accept_bounds || !vm_is_trailing_zeros)) || last_removed_digit >= 5 {
			out++
		}
	} else {
		// Specialized for the common case (~99.3%).
		// Percentages below are relative to this.
		mut round_up := false
		for vp / 100 > vm / 100 {
			// Optimization: remove two digits at a time (~86.2%).
			round_up = (vr % 100) >= 50
			vr /= 100
			vp /= 100
			vm /= 100
			removed += 2
		}
		// Loop iterations below (approximately), without optimization above:
		// 0: 0.03%, 1: 13.8%, 2: 70.6%, 3: 14.0%, 4: 1.40%, 5: 0.14%, 6+: 0.02%
		// Loop iterations below (approximately), with optimization above:
		// 0: 70.6%, 1: 27.8%, 2: 1.40%, 3: 0.14%, 4+: 0.02%
		for vp / 10 > vm / 10 {
			round_up = (vr % 10) >= 5
			vr /= 10
			vp /= 10
			vm /= 10
			removed++
		}
		// We need to take vr + 1 if vr is outside bounds
		// or we need to round up.
		out = vr + bool_to_u64(vr == vm || round_up)
	}

	return Dec64{
		m: out
		e: e10 + removed
	}
}

//=============================================================================
// String Functions
//=============================================================================

// f64_to_str returns `f` as a `string` in scientific notation with max `n_digit` digits after the dot.
pub fn f64_to_str(f f64, n_digit int) string {
	mut u1 := Uf64{}
	u1.f = f
	u := unsafe { u1.u }

	neg := (u >> (mantbits64 + expbits64)) != 0
	mant := u & ((u64(1) << mantbits64) - u64(1))
	exp := (u >> mantbits64) & ((u64(1) << expbits64) - u64(1))
	// println("s:${neg} mant:${mant} exp:${exp} float:${f} byte:${u1.u:016lx}")

	// Exit early for easy cases.
	if exp == maxexp64 || (exp == 0 && mant == 0) {
		return get_string_special(neg, exp == 0, mant == 0)
	}

	mut d, ok := f64_to_decimal_exact_int(mant, exp)
	if !ok {
		// println("to_decimal")
		d = f64_to_decimal(mant, exp)
	}
	// println("${d.m} ${d.e}")
	return d.get_string_64(neg, n_digit, 0)
}

// f64_to_str returns `f` as a `string` in scientific notation with max `n_digit` digits after the dot.
pub fn f64_to_str_pad(f f64, n_digit int) string {
	mut u1 := Uf64{}
	u1.f = f
	u := unsafe { u1.u }

	neg := (u >> (mantbits64 + expbits64)) != 0
	mant := u & ((u64(1) << mantbits64) - u64(1))
	exp := (u >> mantbits64) & ((u64(1) << expbits64) - u64(1))
	// unsafe { println("s:${neg} mant:${mant} exp:${exp} float:${f} byte:${u1.u:016x}") }

	// Exit early for easy cases.
	if exp == maxexp64 || (exp == 0 && mant == 0) {
		return get_string_special(neg, exp == 0, mant == 0)
	}

	mut d, ok := f64_to_decimal_exact_int(mant, exp)
	if !ok {
		// println("to_decimal")
		d = f64_to_decimal(mant, exp)
	}
	// println("DEBUG: ${d.m} ${d.e}")
	return d.get_string_64(neg, n_digit, n_digit)
}

// pow of ten table used by n_digit reduction
const ten_pow_table_64 = [
	u64(1),
	u64(10),
	u64(100),
	u64(1000),
	u64(10000),
	u64(100000),
	u64(1000000),
	u64(10000000),
	u64(100000000),
	u64(1000000000),
	u64(10000000000),
	u64(100000000000),
	u64(1000000000000),
	u64(10000000000000),
	u64(100000000000000),
	u64(1000000000000000),
	u64(10000000000000000),
	u64(100000000000000000),
	u64(1000000000000000000),
	u64(10000000000000000000),
]!

//=============================================================================
// Conversion Functions
//=============================================================================
const mantbits64 = u32(52)
const expbits64 = u32(11)
const bias64 = 1023 // f64 exponent bias

const maxexp64 = 2047


/*
printf/sprintf V implementation

Copyright (c) 2020 Dario Deledda. All rights reserved.
Use of this source code is governed by an MIT license
that can be found in the LICENSE file.

This file contains the printf/sprintf functions
*/

// Align_text is used to describe the different ways to align a text - left, right and center
pub enum Align_text {
	right = 0
	left
	center
}

// Float conversion utility

// rounding value
const dec_round = [
	f64(0.5),
	0.05,
	0.005,
	0.0005,
	0.00005,
	0.000005,
	0.0000005,
	0.00000005,
	0.000000005,
	0.0000000005,
	0.00000000005,
	0.000000000005,
	0.0000000000005,
	0.00000000000005,
	0.000000000000005,
	0.0000000000000005,
	0.00000000000000005,
	0.000000000000000005,
	0.0000000000000000005,
	0.00000000000000000005,
	0.000000000000000000005,
	0.0000000000000000000005,
	0.00000000000000000000005,
	0.000000000000000000000005,
	0.0000000000000000000000005,
	0.00000000000000000000000005,
	0.000000000000000000000000005,
	0.0000000000000000000000000005,
	0.00000000000000000000000000005,
	0.000000000000000000000000000005,
	0.0000000000000000000000000000005,
	0.00000000000000000000000000000005,
	0.000000000000000000000000000000005,
	0.0000000000000000000000000000000005,
	0.00000000000000000000000000000000005,
	0.000000000000000000000000000000000005,
]!

// Single format functions

// BF_param is used for describing the formatting options for a single interpolated value
pub struct BF_param {
pub mut:
	pad_ch       u8   = u8(` `) // padding char
	len0         int  = -1      // default len for whole the number or string
	len1         int  = 6       // number of decimal digits, if needed
	positive     bool = true    // mandatory: the sign of the number passed
	sign_flag    bool // flag for print sign as prefix in padding
	align        Align_text = .right // alignment of the string
	rm_tail_zero bool // remove the tail zeros from floats
}

// format_str returns the `s` formatted, according to the options set in `p`.
@[manualfree]
pub fn format_str(s string, p BF_param) string {
	if p.len0 <= 0 {
		return s.clone()
	}
	dif := p.len0 - utf8_str_visible_length(s)
	if dif <= 0 {
		return s.clone()
	}
	mut res := strings.new_builder(s.len + dif)
	defer {
		unsafe { res.free() }
	}
	if p.align == .right {
		for i1 := 0; i1 < dif; i1++ {
			res.write_u8(p.pad_ch)
		}
	}
	res.write_string(s)
	if p.align == .left {
		for i1 := 0; i1 < dif; i1++ {
			res.write_u8(p.pad_ch)
		}
	}
	return res.str()
}
/*=============================================================================
Copyright (c) 2019-2024 Dario Deledda. All rights reserved.
Use of this source code is governed by an MIT license
that can be found in the LICENSE file.

This file contains string interpolation V functions
=============================================================================*/

// format_str_sb is a `strings.Builder` version of `format_str`.
pub fn format_str_sb(s string, p BF_param, mut sb strings.Builder) {
	if p.len0 <= 0 {
		sb.write_string(s)
		return
	}
	dif := p.len0 - utf8_str_visible_length(s)
	if dif <= 0 {
		sb.write_string(s)
		return
	}

	if p.align == .right {
		for i1 := 0; i1 < dif; i1++ {
			sb.write_u8(p.pad_ch)
		}
	}
	sb.write_string(s)
	if p.align == .left {
		for i1 := 0; i1 < dif; i1++ {
			sb.write_u8(p.pad_ch)
		}
	}
}

const max_size_f64_char = 512 // the f64 max representation is -36,028,797,018,963,968e1023, 21 chars, but alignment padding requires more

// digit pairs in reverse order
const digit_pairs = '00102030405060708090011121314151617181910212223242526272829203132333435363738393041424344454647484940515253545556575859506162636465666768696071727374757677787970818283848586878889809192939495969798999'

// format_dec_sb formats an u64 using a `strings.Builder`.
@[direct_array_access]
pub fn format_dec_sb(d u64, p BF_param, mut res strings.Builder) {
	mut n_char := dec_digits(d)
	sign_len := if !p.positive || p.sign_flag { 1 } else { 0 }
	number_len := sign_len + n_char
	dif := p.len0 - number_len
	mut sign_written := false

	if p.align == .right {
		if p.pad_ch == `0` {
			if p.positive {
				if p.sign_flag {
					res.write_u8(`+`)
					sign_written = true
				}
			} else {
				res.write_u8(`-`)
				sign_written = true
			}
		}
		// write the pad chars
		for i1 := 0; i1 < dif; i1++ {
			res.write_u8(p.pad_ch)
		}
	}

	if !sign_written {
		// no pad char, write the sign before the number
		if p.positive {
			if p.sign_flag {
				res.write_u8(`+`)
			}
		} else {
			res.write_u8(`-`)
		}
	}

	/*
	// Legacy version
	// max u64 18446744073709551615 => 20 byte
	mut buf := [32]u8{}
	mut i := 20
	mut d1 := d
	for i >= (21 - n_char) {
		buf[i] = u8(d1 % 10) + `0`
		d1 = d1 / 10
		i--
	}
	i++
	*/

	//===========================================
	// Speed version
	// max u64 18446744073709551615 => 20 byte
	mut buf := [32]u8{}
	mut i := 20
	mut n := d
	mut d_i := u64(0)
	if n > 0 {
		for n > 0 {
			n1 := n / 100
			// calculate the digit_pairs start index
			d_i = (n - (n1 * 100)) << 1
			n = n1
			unsafe {
				buf[i] = digit_pairs.str[d_i]
			}
			i--
			d_i++
			unsafe {
				buf[i] = digit_pairs.str[d_i]
			}
			i--
		}
		i++
		// remove head zero
		if d_i < 20 {
			i++
		}
		unsafe { res.write_ptr(&buf[i], n_char) }
	} else {
		// we have a zero no need of more code!
		res.write_u8(`0`)
	}
	//===========================================

	if p.align == .left {
		for i1 := 0; i1 < dif; i1++ {
			res.write_u8(p.pad_ch)
		}
	}
	return
}

// f64_to_str_lnd1 formats a f64 to a `string` with `dec_digit` digits after the dot.
@[direct_array_access; manualfree]
pub fn f64_to_str_lnd1(f f64, dec_digit int) string {
	unsafe {
		// we add the rounding value
		s := f64_to_str(f + dec_round[dec_digit], 18)
		// check for +inf -inf Nan
		if s.len > 2 && (s[0] == `n` || s[1] == `i`) {
			return s
		}

		m_sgn_flag := false
		mut sgn := 1
		mut b := [26]u8{}
		mut d_pos := 1
		mut i := 0
		mut i1 := 0
		mut exp := 0
		mut exp_sgn := 1

		mut dot_res_sp := -1

		// get sign and decimal parts
		for c in s {
			match c {
				`-` {
					sgn = -1
					i++
				}
				`+` {
					sgn = 1
					i++
				}
				`0`...`9` {
					b[i1] = c
					i1++
					i++
				}
				`.` {
					if sgn > 0 {
						d_pos = i
					} else {
						d_pos = i - 1
					}
					i++
				}
				`e` {
					i++
					break
				}
				else {
					s.free()
					return '[Float conversion error!!]'
				}
			}
		}
		b[i1] = 0

		// get exponent
		if s[i] == `-` {
			exp_sgn = -1
			i++
		} else if s[i] == `+` {
			exp_sgn = 1
			i++
		}

		mut c := i
		for c < s.len {
			exp = exp * 10 + int(s[c] - `0`)
			c++
		}

		// allocate exp+32 chars for the return string
		// mut res := []u8{len:exp+32,init:`0`}
		mut res := []u8{len: exp + 40, init: 0}
		mut r_i := 0 // result string buffer index

		// println("s:${sgn} b:${b[0]} es:${exp_sgn} exp:${exp}")

		// s no more needed
		s.free()

		if sgn == 1 {
			if m_sgn_flag {
				res[r_i] = `+`
				r_i++
			}
		} else {
			res[r_i] = `-`
			r_i++
		}

		i = 0
		if exp_sgn >= 0 {
			for b[i] != 0 {
				res[r_i] = b[i]
				r_i++
				i++
				if i >= d_pos && exp >= 0 {
					if exp == 0 {
						dot_res_sp = r_i
						res[r_i] = `.`
						r_i++
					}
					exp--
				}
			}
			for exp >= 0 {
				res[r_i] = `0`
				r_i++
				exp--
			}
			// println("exp: $exp $r_i $dot_res_sp")
		} else {
			mut dot_p := true
			for exp > 0 {
				res[r_i] = `0`
				r_i++
				exp--
				if dot_p {
					dot_res_sp = r_i
					res[r_i] = `.`
					r_i++
					dot_p = false
				}
			}
			for b[i] != 0 {
				res[r_i] = b[i]
				r_i++
				i++
			}
		}

		// no more digits needed, stop here
		if dec_digit <= 0 {
			// C.printf(c'f: %f, i: %d, res.data: %p | dot_res_sp: %d | *(res.data): %s \n', f, i, res.data, dot_res_sp, res.data)
			if dot_res_sp < 0 {
				dot_res_sp = i + 1
			}
			tmp_res := tos(res.data, dot_res_sp).clone()
			res.free()
			return tmp_res
		}

		// println("r_i-d_pos: ${r_i - d_pos}")
		if dot_res_sp >= 0 {
			r_i = dot_res_sp + dec_digit + 1
			res[r_i] = 0
			for c1 in 1 .. dec_digit + 1 {
				if res[r_i - c1] == 0 {
					res[r_i - c1] = `0`
				}
			}
			// println("result: [${tos(&res[0],r_i)}]")
			tmp_res := tos(res.data, r_i).clone()
			res.free()
			return tmp_res
		} else {
			if dec_digit > 0 {
				mut c1 := 0
				res[r_i] = `.`
				r_i++
				for c1 < dec_digit {
					res[r_i] = `0`
					r_i++
					c1++
				}
				res[r_i] = 0
			}
			tmp_res := tos(res.data, r_i).clone()
			res.free()
			return tmp_res
		}
	}
}

// format_fl is a `strings.Builder` version of format_fl.
@[direct_array_access; manualfree]
pub fn format_fl(f f64, p BF_param) string {
	unsafe {
		mut fs := f64_to_str_lnd1(if f >= 0.0 { f } else { -f }, p.len1)

		// error!!
		if fs[0] == `[` {
			return fs
		}

		if p.rm_tail_zero {
			tmp := fs
			fs = remove_tail_zeros(fs)
			tmp.free()
		}

		mut buf := [max_size_f64_char]u8{} // write temp float buffer in stack
		mut out := [max_size_f64_char]u8{} // out buffer
		mut buf_i := 0 // index temporary string
		mut out_i := 0 // index output string

		mut sign_len_diff := 0
		if p.pad_ch == `0` {
			if p.positive {
				if p.sign_flag {
					out[out_i] = `+`
					out_i++
					sign_len_diff = -1
				}
			} else {
				out[out_i] = `-`
				out_i++
				sign_len_diff = -1
			}
		} else {
			if p.positive {
				if p.sign_flag {
					buf[buf_i] = `+`
					buf_i++
				}
			} else {
				buf[buf_i] = `-`
				buf_i++
			}
		}

		// copy the float
		vmemcpy(&buf[buf_i], fs.str, fs.len)
		buf_i += fs.len

		// make the padding if needed
		dif := p.len0 - buf_i + sign_len_diff
		if p.align == .right {
			for i1 := 0; i1 < dif; i1++ {
				out[out_i] = p.pad_ch
				out_i++
			}
		}
		vmemcpy(&out[out_i], &buf[0], buf_i)
		out_i += buf_i
		if p.align == .left {
			for i1 := 0; i1 < dif; i1++ {
				out[out_i] = p.pad_ch
				out_i++
			}
		}
		out[out_i] = 0

		// return and free
		tmp := fs
		fs = tos_clone(&out[0])
		tmp.free()
		return fs
	}
}

// format_es returns a f64 as a `string` formatted according to the options set in `p`.
@[direct_array_access; manualfree]
pub fn format_es(f f64, p BF_param) string {
	unsafe {
		mut fs := f64_to_str_pad(if f > 0 { f } else { -f }, p.len1)
		if p.rm_tail_zero {
			tmp := fs
			fs = remove_tail_zeros(fs)
			tmp.free()
		}

		mut buf := [max_size_f64_char]u8{} // write temp float buffer in stack
		mut out := [max_size_f64_char]u8{} // out buffer
		mut buf_i := 0 // index temporary string
		mut out_i := 0 // index output string

		mut sign_len_diff := 0
		if p.pad_ch == `0` {
			if p.positive {
				if p.sign_flag {
					out[out_i] = `+`
					out_i++
					sign_len_diff = -1
				}
			} else {
				out[out_i] = `-`
				out_i++
				sign_len_diff = -1
			}
		} else {
			if p.positive {
				if p.sign_flag {
					buf[buf_i] = `+`
					buf_i++
				}
			} else {
				buf[buf_i] = `-`
				buf_i++
			}
		}

		// copy the float
		vmemcpy(&buf[buf_i], fs.str, fs.len)
		buf_i += fs.len

		// make the padding if needed
		dif := p.len0 - buf_i + sign_len_diff
		if p.align == .right {
			for i1 := 0; i1 < dif; i1++ {
				out[out_i] = p.pad_ch
				out_i++
			}
		}
		vmemcpy(&out[out_i], &buf[0], buf_i)
		out_i += buf_i
		if p.align == .left {
			for i1 := 0; i1 < dif; i1++ {
				out[out_i] = p.pad_ch
				out_i++
			}
		}
		out[out_i] = 0

		// return and free
		tmp := fs
		fs = tos_clone(&out[0])
		tmp.free()
		return fs
	}
}

// remove_tail_zeros strips trailing zeros from `s` and return the resulting `string`.
@[direct_array_access]
pub fn remove_tail_zeros(s string) string {
	unsafe {
		mut buf := malloc_noscan(s.len + 1)
		mut i_d := 0
		mut i_s := 0

		// skip spaces
		for i_s < s.len && s[i_s] !in [`-`, `+`] && (s[i_s] > `9` || s[i_s] < `0`) {
			buf[i_d] = s[i_s]
			i_s++
			i_d++
		}
		// sign
		if i_s < s.len && s[i_s] in [`-`, `+`] {
			buf[i_d] = s[i_s]
			i_s++
			i_d++
		}

		// integer part
		for i_s < s.len && s[i_s] >= `0` && s[i_s] <= `9` {
			buf[i_d] = s[i_s]
			i_s++
			i_d++
		}

		// check decimals
		if i_s < s.len && s[i_s] == `.` {
			mut i_s1 := i_s + 1
			mut sum := 0
			mut i_s2 := i_s1 // last non-zero index after `.`
			for i_s1 < s.len && s[i_s1] >= `0` && s[i_s1] <= `9` {
				sum += s[i_s1] - u8(`0`)
				if s[i_s1] != `0` {
					i_s2 = i_s1
				}
				i_s1++
			}
			// decimal part must be copied
			if sum > 0 {
				for c_i in i_s .. i_s2 + 1 {
					buf[i_d] = s[c_i]
					i_d++
				}
			}
			i_s = i_s1
		}

		if i_s < s.len && s[i_s] != `.` {
			// check exponent
			for {
				buf[i_d] = s[i_s]
				i_s++
				i_d++
				if i_s >= s.len {
					break
				}
			}
		}

		buf[i_d] = 0
		return tos(buf, i_d)
	}
}

/*
f32/f64 ftoa functions

Copyright (c) 2019-2024 Dario Deledda. All rights reserved.
Use of this source code is governed by an MIT license
that can be found in the LICENSE file.

This file contains the f32/f64 ftoa functions

These functions are based on the work of:
Publication:PLDI 2018: Proceedings of the 39th ACM SIGPLAN
Conference on Programming Language Design and ImplementationJune 2018
Pages 270–282 https://doi.org/10.1145/3192366.3192369

inspired by the Go version here:
https://github.com/cespare/ryu/tree/ba56a33f39e3bbbfa409095d0f9ae168a595feea
*/

// ftoa_64 returns a string in scientific notation with max 17 digits after the dot.
// Example: assert strconv.ftoa_64(123.1234567891011121) == '1.2312345678910111e+02'
@[inline]
pub fn ftoa_64(f f64) string {
	return f64_to_str(f, 17)
}

// ftoa_long_64 returns `f` as a `string` in decimal notation with a maximum of 17 digits after the dot.
// Example: assert strconv.f64_to_str_l(123.1234567891011121) == '123.12345678910111'
@[inline]
pub fn ftoa_long_64(f f64) string {
	return f64_to_str_l(f)
}

// ftoa_32 returns a `string` in scientific notation with max 8 digits after the dot.
// Example: assert strconv.ftoa_32(34.1234567) == '3.4123455e+01'
@[inline]
pub fn ftoa_32(f f32) string {
	return f32_to_str(f, 8)
}

// ftoa_long_32 returns `f` as a `string` in decimal notation with a maximum of 8 digits after the dot.
// Example: assert strconv.ftoa_long_32(0.1234567901) == '0.12345679'
@[inline]
pub fn ftoa_long_32(f f32) string {
	return f32_to_str_l(f)
}

const base_digits = '0123456789abcdefghijklmnopqrstuvwxyz'

// format_int returns the string representation of the number n in base `radix`
// for digit values > 10, this function uses the small latin leters a-z.
@[direct_array_access; manualfree]
pub fn format_int(n i64, radix int) string {
	unsafe {
		if radix < 2 || radix > 36 {
			panic_n('invalid radix, it should be => 2 and <= 36, actual:', radix)
		}
		if n == 0 {
			return '0'
		}
		mut n_copy := n
		mut have_minus := false
		if n < 0 {
			have_minus = true
			n_copy = -n_copy
		}
		mut res := ''
		for n_copy != 0 {
			tmp_0 := res
			bdx := int(n_copy % radix)
			tmp_1 := base_digits[bdx].ascii_str()
			res = tmp_1 + res
			tmp_0.free()
			tmp_1.free()
			// res = base_digits[n_copy % radix].ascii_str() + res
			n_copy /= radix
		}
		if have_minus {
			final_res := '-' + res
			res.free()
			return final_res
		}
		return res
	}
}

// format_uint returns the string representation of the number n in base `radix`
// for digit values > 10, this function uses the small latin leters a-z.
@[direct_array_access; manualfree]
pub fn format_uint(n u64, radix int) string {
	unsafe {
		if radix < 2 || radix > 36 {
			panic_n('invalid radix, it should be => 2 and <= 36, actual:', radix)
		}
		if n == 0 {
			return '0'
		}
		mut n_copy := n
		mut res := ''
		uradix := u64(radix)
		for n_copy != 0 {
			tmp_0 := res
			tmp_1 := base_digits[n_copy % uradix].ascii_str()
			res = tmp_1 + res
			tmp_0.free()
			tmp_1.free()
			// res = base_digits[n_copy % uradix].ascii_str() + res
			n_copy /= uradix
		}
		return res
	}
}

// The structure is filled by parser, then given to converter.
pub struct PrepNumber {
pub mut:
	negative bool // 0 if positive number, 1 if negative
	exponent int  // power of 10 exponent
	mantissa u64  // integer mantissa
}

// dec32 is a floating decimal type representing m * 10^e.
struct Dec32 {
mut:
	m u32
	e int
}

// dec64 is a floating decimal type representing m * 10^e.
struct Dec64 {
mut:
	m u64
	e int
}

struct Uint128 {
mut:
	lo u64
	hi u64
}

// support union for convert f32 to u32
union Uf32 {
mut:
	f f32
	u u32
}

// support union for convert f64 to u64
union Uf64 {
mut:
	f f64
	u u64
}

pub union Float64u {
pub mut:
	f f64
	u u64
}

pub union Float32u {
pub mut:
	f f32
	u u32
}

const pow5_num_bits_32 = 61
const pow5_inv_num_bits_32 = 59
const pow5_num_bits_64 = 121
const pow5_inv_num_bits_64 = 122

const powers_of_10 = [
	u64(1e0),
	u64(1e1),
	u64(1e2),
	u64(1e3),
	u64(1e4),
	u64(1e5),
	u64(1e6),
	u64(1e7),
	u64(1e8),
	u64(1e9),
	u64(1e10),
	u64(1e11),
	u64(1e12),
	u64(1e13),
	u64(1e14),
	u64(1e15),
	u64(1e16),
	u64(1e17),
	// We only need to find the length of at most 17 digit numbers.
]!

const pow5_split_32 = [
	u64(1152921504606846976),
	u64(1441151880758558720),
	u64(1801439850948198400),
	u64(2251799813685248000),
	u64(1407374883553280000),
	u64(1759218604441600000),
	u64(2199023255552000000),
	u64(1374389534720000000),
	u64(1717986918400000000),
	u64(2147483648000000000),
	u64(1342177280000000000),
	u64(1677721600000000000),
	u64(2097152000000000000),
	u64(1310720000000000000),
	u64(1638400000000000000),
	u64(2048000000000000000),
	u64(1280000000000000000),
	u64(1600000000000000000),
	u64(2000000000000000000),
	u64(1250000000000000000),
	u64(1562500000000000000),
	u64(1953125000000000000),
	u64(1220703125000000000),
	u64(1525878906250000000),
	u64(1907348632812500000),
	u64(1192092895507812500),
	u64(1490116119384765625),
	u64(1862645149230957031),
	u64(1164153218269348144),
	u64(1455191522836685180),
	u64(1818989403545856475),
	u64(2273736754432320594),
	u64(1421085471520200371),
	u64(1776356839400250464),
	u64(2220446049250313080),
	u64(1387778780781445675),
	u64(1734723475976807094),
	u64(2168404344971008868),
	u64(1355252715606880542),
	u64(1694065894508600678),
	u64(2117582368135750847),
	u64(1323488980084844279),
	u64(1654361225106055349),
	u64(2067951531382569187),
	u64(1292469707114105741),
	u64(1615587133892632177),
	u64(2019483917365790221),
]!

const pow5_inv_split_32 = [
	u64(576460752303423489),
	u64(461168601842738791),
	u64(368934881474191033),
	u64(295147905179352826),
	u64(472236648286964522),
	u64(377789318629571618),
	u64(302231454903657294),
	u64(483570327845851670),
	u64(386856262276681336),
	u64(309485009821345069),
	u64(495176015714152110),
	u64(396140812571321688),
	u64(316912650057057351),
	u64(507060240091291761),
	u64(405648192073033409),
	u64(324518553658426727),
	u64(519229685853482763),
	u64(415383748682786211),
	u64(332306998946228969),
	u64(531691198313966350),
	u64(425352958651173080),
	u64(340282366920938464),
	u64(544451787073501542),
	u64(435561429658801234),
	u64(348449143727040987),
	u64(557518629963265579),
	u64(446014903970612463),
	u64(356811923176489971),
	u64(570899077082383953),
	u64(456719261665907162),
	u64(365375409332725730),
]!

const pow5_split_64_x = [
	u64(0x0000000000000000),
	u64(0x0100000000000000),
	u64(0x0000000000000000),
	u64(0x0140000000000000),
	u64(0x0000000000000000),
	u64(0x0190000000000000),
	u64(0x0000000000000000),
	u64(0x01f4000000000000),
	u64(0x0000000000000000),
	u64(0x0138800000000000),
	u64(0x0000000000000000),
	u64(0x0186a00000000000),
	u64(0x0000000000000000),
	u64(0x01e8480000000000),
	u64(0x0000000000000000),
	u64(0x01312d0000000000),
	u64(0x0000000000000000),
	u64(0x017d784000000000),
	u64(0x0000000000000000),
	u64(0x01dcd65000000000),
	u64(0x0000000000000000),
	u64(0x012a05f200000000),
	u64(0x0000000000000000),
	u64(0x0174876e80000000),
	u64(0x0000000000000000),
	u64(0x01d1a94a20000000),
	u64(0x0000000000000000),
	u64(0x012309ce54000000),
	u64(0x0000000000000000),
	u64(0x016bcc41e9000000),
	u64(0x0000000000000000),
	u64(0x01c6bf5263400000),
	u64(0x0000000000000000),
	u64(0x011c37937e080000),
	u64(0x0000000000000000),
	u64(0x016345785d8a0000),
	u64(0x0000000000000000),
	u64(0x01bc16d674ec8000),
	u64(0x0000000000000000),
	u64(0x01158e460913d000),
	u64(0x0000000000000000),
	u64(0x015af1d78b58c400),
	u64(0x0000000000000000),
	u64(0x01b1ae4d6e2ef500),
	u64(0x0000000000000000),
	u64(0x010f0cf064dd5920),
	u64(0x0000000000000000),
	u64(0x0152d02c7e14af68),
	u64(0x0000000000000000),
	u64(0x01a784379d99db42),
	u64(0x4000000000000000),
	u64(0x0108b2a2c2802909),
	u64(0x9000000000000000),
	u64(0x014adf4b7320334b),
	u64(0x7400000000000000),
	u64(0x019d971e4fe8401e),
	u64(0x0880000000000000),
	u64(0x01027e72f1f12813),
	u64(0xcaa0000000000000),
	u64(0x01431e0fae6d7217),
	u64(0xbd48000000000000),
	u64(0x0193e5939a08ce9d),
	u64(0x2c9a000000000000),
	u64(0x01f8def8808b0245),
	u64(0x3be0400000000000),
	u64(0x013b8b5b5056e16b),
	u64(0x0ad8500000000000),
	u64(0x018a6e32246c99c6),
	u64(0x8d8e640000000000),
	u64(0x01ed09bead87c037),
	u64(0xb878fe8000000000),
	u64(0x013426172c74d822),
	u64(0x66973e2000000000),
	u64(0x01812f9cf7920e2b),
	u64(0x403d0da800000000),
	u64(0x01e17b84357691b6),
	u64(0xe826288900000000),
	u64(0x012ced32a16a1b11),
	u64(0x622fb2ab40000000),
	u64(0x0178287f49c4a1d6),
	u64(0xfabb9f5610000000),
	u64(0x01d6329f1c35ca4b),
	u64(0x7cb54395ca000000),
	u64(0x0125dfa371a19e6f),
	u64(0x5be2947b3c800000),
	u64(0x016f578c4e0a060b),
	u64(0x32db399a0ba00000),
	u64(0x01cb2d6f618c878e),
	u64(0xdfc9040047440000),
	u64(0x011efc659cf7d4b8),
	u64(0x17bb450059150000),
	u64(0x0166bb7f0435c9e7),
	u64(0xddaa16406f5a4000),
	u64(0x01c06a5ec5433c60),
	u64(0x8a8a4de845986800),
	u64(0x0118427b3b4a05bc),
	u64(0xad2ce16256fe8200),
	u64(0x015e531a0a1c872b),
	u64(0x987819baecbe2280),
	u64(0x01b5e7e08ca3a8f6),
	u64(0x1f4b1014d3f6d590),
	u64(0x0111b0ec57e6499a),
	u64(0xa71dd41a08f48af4),
	u64(0x01561d276ddfdc00),
	u64(0xd0e549208b31adb1),
	u64(0x01aba4714957d300),
	u64(0x828f4db456ff0c8e),
	u64(0x010b46c6cdd6e3e0),
	u64(0xa33321216cbecfb2),
	u64(0x014e1878814c9cd8),
	u64(0xcbffe969c7ee839e),
	u64(0x01a19e96a19fc40e),
	u64(0x3f7ff1e21cf51243),
	u64(0x0105031e2503da89),
	u64(0x8f5fee5aa43256d4),
	u64(0x014643e5ae44d12b),
	u64(0x7337e9f14d3eec89),
	u64(0x0197d4df19d60576),
	u64(0x1005e46da08ea7ab),
	u64(0x01fdca16e04b86d4),
	u64(0x8a03aec4845928cb),
	u64(0x013e9e4e4c2f3444),
	u64(0xac849a75a56f72fd),
	u64(0x018e45e1df3b0155),
	u64(0x17a5c1130ecb4fbd),
	u64(0x01f1d75a5709c1ab),
	u64(0xeec798abe93f11d6),
	u64(0x013726987666190a),
	u64(0xaa797ed6e38ed64b),
	u64(0x0184f03e93ff9f4d),
	u64(0x1517de8c9c728bde),
	u64(0x01e62c4e38ff8721),
	u64(0xad2eeb17e1c7976b),
	u64(0x012fdbb0e39fb474),
	u64(0xd87aa5ddda397d46),
	u64(0x017bd29d1c87a191),
	u64(0x4e994f5550c7dc97),
	u64(0x01dac74463a989f6),
	u64(0xf11fd195527ce9de),
	u64(0x0128bc8abe49f639),
	u64(0x6d67c5faa71c2456),
	u64(0x0172ebad6ddc73c8),
	u64(0x88c1b77950e32d6c),
	u64(0x01cfa698c95390ba),
	u64(0x957912abd28dfc63),
	u64(0x0121c81f7dd43a74),
	u64(0xbad75756c7317b7c),
	u64(0x016a3a275d494911),
	u64(0x298d2d2c78fdda5b),
	u64(0x01c4c8b1349b9b56),
	u64(0xd9f83c3bcb9ea879),
	u64(0x011afd6ec0e14115),
	u64(0x50764b4abe865297),
	u64(0x0161bcca7119915b),
	u64(0x2493de1d6e27e73d),
	u64(0x01ba2bfd0d5ff5b2),
	u64(0x56dc6ad264d8f086),
	u64(0x01145b7e285bf98f),
	u64(0x2c938586fe0f2ca8),
	u64(0x0159725db272f7f3),
	u64(0xf7b866e8bd92f7d2),
	u64(0x01afcef51f0fb5ef),
	u64(0xfad34051767bdae3),
	u64(0x010de1593369d1b5),
	u64(0x79881065d41ad19c),
	u64(0x015159af80444623),
	u64(0x57ea147f49218603),
	u64(0x01a5b01b605557ac),
	u64(0xb6f24ccf8db4f3c1),
	u64(0x01078e111c3556cb),
	u64(0xa4aee003712230b2),
	u64(0x014971956342ac7e),
	u64(0x4dda98044d6abcdf),
	u64(0x019bcdfabc13579e),
	u64(0xf0a89f02b062b60b),
	u64(0x010160bcb58c16c2),
	u64(0xacd2c6c35c7b638e),
	u64(0x0141b8ebe2ef1c73),
	u64(0x98077874339a3c71),
	u64(0x01922726dbaae390),
	u64(0xbe0956914080cb8e),
	u64(0x01f6b0f092959c74),
	u64(0xf6c5d61ac8507f38),
	u64(0x013a2e965b9d81c8),
	u64(0x34774ba17a649f07),
	u64(0x0188ba3bf284e23b),
	u64(0x01951e89d8fdc6c8),
	u64(0x01eae8caef261aca),
	u64(0x40fd3316279e9c3d),
	u64(0x0132d17ed577d0be),
	u64(0xd13c7fdbb186434c),
	u64(0x017f85de8ad5c4ed),
	u64(0x458b9fd29de7d420),
	u64(0x01df67562d8b3629),
	u64(0xcb7743e3a2b0e494),
	u64(0x012ba095dc7701d9),
	u64(0x3e5514dc8b5d1db9),
	u64(0x017688bb5394c250),
	u64(0x4dea5a13ae346527),
	u64(0x01d42aea2879f2e4),
	u64(0xb0b2784c4ce0bf38),
	u64(0x01249ad2594c37ce),
	u64(0x5cdf165f6018ef06),
	u64(0x016dc186ef9f45c2),
	u64(0xf416dbf7381f2ac8),
	u64(0x01c931e8ab871732),
	u64(0xd88e497a83137abd),
	u64(0x011dbf316b346e7f),
	u64(0xceb1dbd923d8596c),
	u64(0x01652efdc6018a1f),
	u64(0xc25e52cf6cce6fc7),
	u64(0x01be7abd3781eca7),
	u64(0xd97af3c1a40105dc),
	u64(0x01170cb642b133e8),
	u64(0x0fd9b0b20d014754),
	u64(0x015ccfe3d35d80e3),
	u64(0xd3d01cde90419929),
	u64(0x01b403dcc834e11b),
	u64(0x6462120b1a28ffb9),
	u64(0x01108269fd210cb1),
	u64(0xbd7a968de0b33fa8),
	u64(0x0154a3047c694fdd),
	u64(0x2cd93c3158e00f92),
	u64(0x01a9cbc59b83a3d5),
	u64(0x3c07c59ed78c09bb),
	u64(0x010a1f5b81324665),
	u64(0x8b09b7068d6f0c2a),
	u64(0x014ca732617ed7fe),
	u64(0x2dcc24c830cacf34),
	u64(0x019fd0fef9de8dfe),
	u64(0xdc9f96fd1e7ec180),
	u64(0x0103e29f5c2b18be),
	u64(0x93c77cbc661e71e1),
	u64(0x0144db473335deee),
	u64(0x38b95beb7fa60e59),
	u64(0x01961219000356aa),
	u64(0xc6e7b2e65f8f91ef),
	u64(0x01fb969f40042c54),
	u64(0xfc50cfcffbb9bb35),
	u64(0x013d3e2388029bb4),
	u64(0x3b6503c3faa82a03),
	u64(0x018c8dac6a0342a2),
	u64(0xca3e44b4f9523484),
	u64(0x01efb1178484134a),
	u64(0xbe66eaf11bd360d2),
	u64(0x0135ceaeb2d28c0e),
	u64(0x6e00a5ad62c83907),
	u64(0x0183425a5f872f12),
	u64(0x0980cf18bb7a4749),
	u64(0x01e412f0f768fad7),
	u64(0x65f0816f752c6c8d),
	u64(0x012e8bd69aa19cc6),
	u64(0xff6ca1cb527787b1),
	u64(0x017a2ecc414a03f7),
	u64(0xff47ca3e2715699d),
	u64(0x01d8ba7f519c84f5),
	u64(0xbf8cde66d86d6202),
	u64(0x0127748f9301d319),
	u64(0x2f7016008e88ba83),
	u64(0x017151b377c247e0),
	u64(0x3b4c1b80b22ae923),
	u64(0x01cda62055b2d9d8),
	u64(0x250f91306f5ad1b6),
	u64(0x012087d4358fc827),
	u64(0xee53757c8b318623),
	u64(0x0168a9c942f3ba30),
	u64(0x29e852dbadfde7ac),
	u64(0x01c2d43b93b0a8bd),
	u64(0x3a3133c94cbeb0cc),
	u64(0x0119c4a53c4e6976),
	u64(0xc8bd80bb9fee5cff),
	u64(0x016035ce8b6203d3),
	u64(0xbaece0ea87e9f43e),
	u64(0x01b843422e3a84c8),
	u64(0x74d40c9294f238a7),
	u64(0x01132a095ce492fd),
	u64(0xd2090fb73a2ec6d1),
	u64(0x0157f48bb41db7bc),
	u64(0x068b53a508ba7885),
	u64(0x01adf1aea12525ac),
	u64(0x8417144725748b53),
	u64(0x010cb70d24b7378b),
	u64(0x651cd958eed1ae28),
	u64(0x014fe4d06de5056e),
	u64(0xfe640faf2a8619b2),
	u64(0x01a3de04895e46c9),
	u64(0x3efe89cd7a93d00f),
	u64(0x01066ac2d5daec3e),
	u64(0xcebe2c40d938c413),
	u64(0x014805738b51a74d),
	u64(0x426db7510f86f518),
	u64(0x019a06d06e261121),
	u64(0xc9849292a9b4592f),
	u64(0x0100444244d7cab4),
	u64(0xfbe5b73754216f7a),
	u64(0x01405552d60dbd61),
	u64(0x7adf25052929cb59),
	u64(0x01906aa78b912cba),
	u64(0x1996ee4673743e2f),
	u64(0x01f485516e7577e9),
	u64(0xaffe54ec0828a6dd),
	u64(0x0138d352e5096af1),
	u64(0x1bfdea270a32d095),
	u64(0x018708279e4bc5ae),
	u64(0xa2fd64b0ccbf84ba),
	u64(0x01e8ca3185deb719),
	u64(0x05de5eee7ff7b2f4),
	u64(0x01317e5ef3ab3270),
	u64(0x0755f6aa1ff59fb1),
	u64(0x017dddf6b095ff0c),
	u64(0x092b7454a7f3079e),
	u64(0x01dd55745cbb7ecf),
	u64(0x65bb28b4e8f7e4c3),
	u64(0x012a5568b9f52f41),
	u64(0xbf29f2e22335ddf3),
	u64(0x0174eac2e8727b11),
	u64(0x2ef46f9aac035570),
	u64(0x01d22573a28f19d6),
	u64(0xdd58c5c0ab821566),
	u64(0x0123576845997025),
	u64(0x54aef730d6629ac0),
	u64(0x016c2d4256ffcc2f),
	u64(0x29dab4fd0bfb4170),
	u64(0x01c73892ecbfbf3b),
	u64(0xfa28b11e277d08e6),
	u64(0x011c835bd3f7d784),
	u64(0x38b2dd65b15c4b1f),
	u64(0x0163a432c8f5cd66),
	u64(0xc6df94bf1db35de7),
	u64(0x01bc8d3f7b3340bf),
	u64(0xdc4bbcf772901ab0),
	u64(0x0115d847ad000877),
	u64(0xd35eac354f34215c),
	u64(0x015b4e5998400a95),
	u64(0x48365742a30129b4),
	u64(0x01b221effe500d3b),
	u64(0x0d21f689a5e0ba10),
	u64(0x010f5535fef20845),
	u64(0x506a742c0f58e894),
	u64(0x01532a837eae8a56),
	u64(0xe4851137132f22b9),
	u64(0x01a7f5245e5a2ceb),
	u64(0x6ed32ac26bfd75b4),
	u64(0x0108f936baf85c13),
	u64(0x4a87f57306fcd321),
	u64(0x014b378469b67318),
	u64(0x5d29f2cfc8bc07e9),
	u64(0x019e056584240fde),
	u64(0xfa3a37c1dd7584f1),
	u64(0x0102c35f729689ea),
	u64(0xb8c8c5b254d2e62e),
	u64(0x014374374f3c2c65),
	u64(0x26faf71eea079fb9),
	u64(0x01945145230b377f),
	u64(0xf0b9b4e6a48987a8),
	u64(0x01f965966bce055e),
	u64(0x5674111026d5f4c9),
	u64(0x013bdf7e0360c35b),
	u64(0x2c111554308b71fb),
	u64(0x018ad75d8438f432),
	u64(0xb7155aa93cae4e7a),
	u64(0x01ed8d34e547313e),
	u64(0x326d58a9c5ecf10c),
	u64(0x013478410f4c7ec7),
	u64(0xff08aed437682d4f),
	u64(0x01819651531f9e78),
	u64(0x3ecada89454238a3),
	u64(0x01e1fbe5a7e78617),
	u64(0x873ec895cb496366),
	u64(0x012d3d6f88f0b3ce),
	u64(0x290e7abb3e1bbc3f),
	u64(0x01788ccb6b2ce0c2),
	u64(0xb352196a0da2ab4f),
	u64(0x01d6affe45f818f2),
	u64(0xb0134fe24885ab11),
	u64(0x01262dfeebbb0f97),
	u64(0x9c1823dadaa715d6),
	u64(0x016fb97ea6a9d37d),
	u64(0x031e2cd19150db4b),
	u64(0x01cba7de5054485d),
	u64(0x21f2dc02fad2890f),
	u64(0x011f48eaf234ad3a),
	u64(0xaa6f9303b9872b53),
	u64(0x01671b25aec1d888),
	u64(0xd50b77c4a7e8f628),
	u64(0x01c0e1ef1a724eaa),
	u64(0xc5272adae8f199d9),
	u64(0x01188d357087712a),
	u64(0x7670f591a32e004f),
	u64(0x015eb082cca94d75),
	u64(0xd40d32f60bf98063),
	u64(0x01b65ca37fd3a0d2),
	u64(0xc4883fd9c77bf03e),
	u64(0x0111f9e62fe44483),
	u64(0xb5aa4fd0395aec4d),
	u64(0x0156785fbbdd55a4),
	u64(0xe314e3c447b1a760),
	u64(0x01ac1677aad4ab0d),
	u64(0xaded0e5aaccf089c),
	u64(0x010b8e0acac4eae8),
	u64(0xd96851f15802cac3),
	u64(0x014e718d7d7625a2),
	u64(0x8fc2666dae037d74),
	u64(0x01a20df0dcd3af0b),
	u64(0x39d980048cc22e68),
	u64(0x010548b68a044d67),
	u64(0x084fe005aff2ba03),
	u64(0x01469ae42c8560c1),
	u64(0x4a63d8071bef6883),
	u64(0x0198419d37a6b8f1),
	u64(0x9cfcce08e2eb42a4),
	u64(0x01fe52048590672d),
	u64(0x821e00c58dd309a7),
	u64(0x013ef342d37a407c),
	u64(0xa2a580f6f147cc10),
	u64(0x018eb0138858d09b),
	u64(0x8b4ee134ad99bf15),
	u64(0x01f25c186a6f04c2),
	u64(0x97114cc0ec80176d),
	u64(0x0137798f428562f9),
	u64(0xfcd59ff127a01d48),
	u64(0x018557f31326bbb7),
	u64(0xfc0b07ed7188249a),
	u64(0x01e6adefd7f06aa5),
	u64(0xbd86e4f466f516e0),
	u64(0x01302cb5e6f642a7),
	u64(0xace89e3180b25c98),
	u64(0x017c37e360b3d351),
	u64(0x1822c5bde0def3be),
	u64(0x01db45dc38e0c826),
	u64(0xcf15bb96ac8b5857),
	u64(0x01290ba9a38c7d17),
	u64(0xc2db2a7c57ae2e6d),
	u64(0x01734e940c6f9c5d),
	u64(0x3391f51b6d99ba08),
	u64(0x01d022390f8b8375),
	u64(0x403b393124801445),
	u64(0x01221563a9b73229),
	u64(0x904a077d6da01956),
	u64(0x016a9abc9424feb3),
	u64(0x745c895cc9081fac),
	u64(0x01c5416bb92e3e60),
	u64(0x48b9d5d9fda513cb),
	u64(0x011b48e353bce6fc),
	u64(0x5ae84b507d0e58be),
	u64(0x01621b1c28ac20bb),
	u64(0x31a25e249c51eeee),
	u64(0x01baa1e332d728ea),
	u64(0x5f057ad6e1b33554),
	u64(0x0114a52dffc67992),
	u64(0xf6c6d98c9a2002aa),
	u64(0x0159ce797fb817f6),
	u64(0xb4788fefc0a80354),
	u64(0x01b04217dfa61df4),
	u64(0xf0cb59f5d8690214),
	u64(0x010e294eebc7d2b8),
	u64(0x2cfe30734e83429a),
	u64(0x0151b3a2a6b9c767),
	u64(0xf83dbc9022241340),
	u64(0x01a6208b50683940),
	u64(0x9b2695da15568c08),
	u64(0x0107d457124123c8),
	u64(0xc1f03b509aac2f0a),
	u64(0x0149c96cd6d16cba),
	u64(0x726c4a24c1573acd),
	u64(0x019c3bc80c85c7e9),
	u64(0xe783ae56f8d684c0),
	u64(0x0101a55d07d39cf1),
	u64(0x616499ecb70c25f0),
	u64(0x01420eb449c8842e),
	u64(0xf9bdc067e4cf2f6c),
	u64(0x019292615c3aa539),
	u64(0x782d3081de02fb47),
	u64(0x01f736f9b3494e88),
	u64(0x4b1c3e512ac1dd0c),
	u64(0x013a825c100dd115),
	u64(0x9de34de57572544f),
	u64(0x018922f31411455a),
	u64(0x455c215ed2cee963),
	u64(0x01eb6bafd91596b1),
	u64(0xcb5994db43c151de),
	u64(0x0133234de7ad7e2e),
	u64(0x7e2ffa1214b1a655),
	u64(0x017fec216198ddba),
	u64(0x1dbbf89699de0feb),
	u64(0x01dfe729b9ff1529),
	u64(0xb2957b5e202ac9f3),
	u64(0x012bf07a143f6d39),
	u64(0x1f3ada35a8357c6f),
	u64(0x0176ec98994f4888),
	u64(0x270990c31242db8b),
	u64(0x01d4a7bebfa31aaa),
	u64(0x5865fa79eb69c937),
	u64(0x0124e8d737c5f0aa),
	u64(0xee7f791866443b85),
	u64(0x016e230d05b76cd4),
	u64(0x2a1f575e7fd54a66),
	u64(0x01c9abd04725480a),
	u64(0x5a53969b0fe54e80),
	u64(0x011e0b622c774d06),
	u64(0xf0e87c41d3dea220),
	u64(0x01658e3ab7952047),
	u64(0xed229b5248d64aa8),
	u64(0x01bef1c9657a6859),
	u64(0x3435a1136d85eea9),
	u64(0x0117571ddf6c8138),
	u64(0x4143095848e76a53),
	u64(0x015d2ce55747a186),
	u64(0xd193cbae5b2144e8),
	u64(0x01b4781ead1989e7),
	u64(0xe2fc5f4cf8f4cb11),
	u64(0x0110cb132c2ff630),
	u64(0x1bbb77203731fdd5),
	u64(0x0154fdd7f73bf3bd),
	u64(0x62aa54e844fe7d4a),
	u64(0x01aa3d4df50af0ac),
	u64(0xbdaa75112b1f0e4e),
	u64(0x010a6650b926d66b),
	u64(0xad15125575e6d1e2),
	u64(0x014cffe4e7708c06),
	u64(0x585a56ead360865b),
	u64(0x01a03fde214caf08),
	u64(0x37387652c41c53f8),
	u64(0x010427ead4cfed65),
	u64(0x850693e7752368f7),
	u64(0x014531e58a03e8be),
	u64(0x264838e1526c4334),
	u64(0x01967e5eec84e2ee),
	u64(0xafda4719a7075402),
	u64(0x01fc1df6a7a61ba9),
	u64(0x0de86c7008649481),
	u64(0x013d92ba28c7d14a),
	u64(0x9162878c0a7db9a1),
	u64(0x018cf768b2f9c59c),
	u64(0xb5bb296f0d1d280a),
	u64(0x01f03542dfb83703),
	u64(0x5194f9e568323906),
	u64(0x01362149cbd32262),
	u64(0xe5fa385ec23ec747),
	u64(0x0183a99c3ec7eafa),
	u64(0x9f78c67672ce7919),
	u64(0x01e494034e79e5b9),
	u64(0x03ab7c0a07c10bb0),
	u64(0x012edc82110c2f94),
	u64(0x04965b0c89b14e9c),
	u64(0x017a93a2954f3b79),
	u64(0x45bbf1cfac1da243),
	u64(0x01d9388b3aa30a57),
	u64(0x8b957721cb92856a),
	u64(0x0127c35704a5e676),
	u64(0x2e7ad4ea3e7726c4),
	u64(0x0171b42cc5cf6014),
	u64(0x3a198a24ce14f075),
	u64(0x01ce2137f7433819),
	u64(0xc44ff65700cd1649),
	u64(0x0120d4c2fa8a030f),
	u64(0xb563f3ecc1005bdb),
	u64(0x016909f3b92c83d3),
	u64(0xa2bcf0e7f14072d2),
	u64(0x01c34c70a777a4c8),
	u64(0x65b61690f6c847c3),
	u64(0x011a0fc668aac6fd),
	u64(0xbf239c35347a59b4),
	u64(0x016093b802d578bc),
	u64(0xeeec83428198f021),
	u64(0x01b8b8a6038ad6eb),
	u64(0x7553d20990ff9615),
	u64(0x01137367c236c653),
	u64(0x52a8c68bf53f7b9a),
	u64(0x01585041b2c477e8),
	u64(0x6752f82ef28f5a81),
	u64(0x01ae64521f7595e2),
	u64(0x8093db1d57999890),
	u64(0x010cfeb353a97dad),
	u64(0xe0b8d1e4ad7ffeb4),
	u64(0x01503e602893dd18),
	u64(0x18e7065dd8dffe62),
	u64(0x01a44df832b8d45f),
	u64(0x6f9063faa78bfefd),
	u64(0x0106b0bb1fb384bb),
	u64(0x4b747cf9516efebc),
	u64(0x01485ce9e7a065ea),
	u64(0xde519c37a5cabe6b),
	u64(0x019a742461887f64),
	u64(0x0af301a2c79eb703),
	u64(0x01008896bcf54f9f),
	u64(0xcdafc20b798664c4),
	u64(0x0140aabc6c32a386),
	u64(0x811bb28e57e7fdf5),
	u64(0x0190d56b873f4c68),
	u64(0xa1629f31ede1fd72),
	u64(0x01f50ac6690f1f82),
	u64(0xa4dda37f34ad3e67),
	u64(0x013926bc01a973b1),
	u64(0x0e150c5f01d88e01),
	u64(0x0187706b0213d09e),
	u64(0x919a4f76c24eb181),
	u64(0x01e94c85c298c4c5),
	u64(0x7b0071aa39712ef1),
	u64(0x0131cfd3999f7afb),
	u64(0x59c08e14c7cd7aad),
	u64(0x017e43c8800759ba),
	u64(0xf030b199f9c0d958),
	u64(0x01ddd4baa0093028),
	u64(0x961e6f003c1887d7),
	u64(0x012aa4f4a405be19),
	u64(0xfba60ac04b1ea9cd),
	u64(0x01754e31cd072d9f),
	u64(0xfa8f8d705de65440),
	u64(0x01d2a1be4048f907),
	u64(0xfc99b8663aaff4a8),
	u64(0x0123a516e82d9ba4),
	u64(0x3bc0267fc95bf1d2),
	u64(0x016c8e5ca239028e),
	u64(0xcab0301fbbb2ee47),
	u64(0x01c7b1f3cac74331),
	u64(0x1eae1e13d54fd4ec),
	u64(0x011ccf385ebc89ff),
	u64(0xe659a598caa3ca27),
	u64(0x01640306766bac7e),
	u64(0x9ff00efefd4cbcb1),
	u64(0x01bd03c81406979e),
	u64(0x23f6095f5e4ff5ef),
	u64(0x0116225d0c841ec3),
	u64(0xecf38bb735e3f36a),
	u64(0x015baaf44fa52673),
	u64(0xe8306ea5035cf045),
	u64(0x01b295b1638e7010),
	u64(0x911e4527221a162b),
	u64(0x010f9d8ede39060a),
	u64(0x3565d670eaa09bb6),
	u64(0x015384f295c7478d),
	u64(0x82bf4c0d2548c2a3),
	u64(0x01a8662f3b391970),
	u64(0x51b78f88374d79a6),
	u64(0x01093fdd8503afe6),
	u64(0xe625736a4520d810),
	u64(0x014b8fd4e6449bdf),
	u64(0xdfaed044d6690e14),
	u64(0x019e73ca1fd5c2d7),
	u64(0xebcd422b0601a8cc),
	u64(0x0103085e53e599c6),
	u64(0xa6c092b5c78212ff),
	u64(0x0143ca75e8df0038),
	u64(0xd070b763396297bf),
	u64(0x0194bd136316c046),
	u64(0x848ce53c07bb3daf),
	u64(0x01f9ec583bdc7058),
	u64(0x52d80f4584d5068d),
	u64(0x013c33b72569c637),
	u64(0x278e1316e60a4831),
	u64(0x018b40a4eec437c5),
]!

const pow5_inv_split_64_x = [
	u64(0x0000000000000001),
	u64(0x0400000000000000),
	u64(0x3333333333333334),
	u64(0x0333333333333333),
	u64(0x28f5c28f5c28f5c3),
	u64(0x028f5c28f5c28f5c),
	u64(0xed916872b020c49c),
	u64(0x020c49ba5e353f7c),
	u64(0xaf4f0d844d013a93),
	u64(0x0346dc5d63886594),
	u64(0x8c3f3e0370cdc876),
	u64(0x029f16b11c6d1e10),
	u64(0xd698fe69270b06c5),
	u64(0x0218def416bdb1a6),
	u64(0xf0f4ca41d811a46e),
	u64(0x035afe535795e90a),
	u64(0xf3f70834acdae9f1),
	u64(0x02af31dc4611873b),
	u64(0x5cc5a02a23e254c1),
	u64(0x0225c17d04dad296),
	u64(0xfad5cd10396a2135),
	u64(0x036f9bfb3af7b756),
	u64(0xfbde3da69454e75e),
	u64(0x02bfaffc2f2c92ab),
	u64(0x2fe4fe1edd10b918),
	u64(0x0232f33025bd4223),
	u64(0x4ca19697c81ac1bf),
	u64(0x0384b84d092ed038),
	u64(0x3d4e1213067bce33),
	u64(0x02d09370d4257360),
	u64(0x643e74dc052fd829),
	u64(0x024075f3dceac2b3),
	u64(0x6d30baf9a1e626a7),
	u64(0x039a5652fb113785),
	u64(0x2426fbfae7eb5220),
	u64(0x02e1dea8c8da92d1),
	u64(0x1cebfcc8b9890e80),
	u64(0x024e4bba3a487574),
	u64(0x94acc7a78f41b0cc),
	u64(0x03b07929f6da5586),
	u64(0xaa23d2ec729af3d7),
	u64(0x02f394219248446b),
	u64(0xbb4fdbf05baf2979),
	u64(0x025c768141d369ef),
	u64(0xc54c931a2c4b758d),
	u64(0x03c7240202ebdcb2),
	u64(0x9dd6dc14f03c5e0b),
	u64(0x0305b66802564a28),
	u64(0x4b1249aa59c9e4d6),
	u64(0x026af8533511d4ed),
	u64(0x44ea0f76f60fd489),
	u64(0x03de5a1ebb4fbb15),
	u64(0x6a54d92bf80caa07),
	u64(0x0318481895d96277),
	u64(0x21dd7a89933d54d2),
	u64(0x0279d346de4781f9),
	u64(0x362f2a75b8622150),
	u64(0x03f61ed7ca0c0328),
	u64(0xf825bb91604e810d),
	u64(0x032b4bdfd4d668ec),
	u64(0xc684960de6a5340b),
	u64(0x0289097fdd7853f0),
	u64(0xd203ab3e521dc33c),
	u64(0x02073accb12d0ff3),
	u64(0xe99f7863b696052c),
	u64(0x033ec47ab514e652),
	u64(0x87b2c6b62bab3757),
	u64(0x02989d2ef743eb75),
	u64(0xd2f56bc4efbc2c45),
	u64(0x0213b0f25f69892a),
	u64(0x1e55793b192d13a2),
	u64(0x0352b4b6ff0f41de),
	u64(0x4b77942f475742e8),
	u64(0x02a8909265a5ce4b),
	u64(0xd5f9435905df68ba),
	u64(0x022073a8515171d5),
	u64(0x565b9ef4d6324129),
	u64(0x03671f73b54f1c89),
	u64(0xdeafb25d78283421),
	u64(0x02b8e5f62aa5b06d),
	u64(0x188c8eb12cecf681),
	u64(0x022d84c4eeeaf38b),
	u64(0x8dadb11b7b14bd9b),
	u64(0x037c07a17e44b8de),
	u64(0x7157c0e2c8dd647c),
	u64(0x02c99fb46503c718),
	u64(0x8ddfcd823a4ab6ca),
	u64(0x023ae629ea696c13),
	u64(0x1632e269f6ddf142),
	u64(0x0391704310a8acec),
	u64(0x44f581ee5f17f435),
	u64(0x02dac035a6ed5723),
	u64(0x372ace584c1329c4),
	u64(0x024899c4858aac1c),
	u64(0xbeaae3c079b842d3),
	u64(0x03a75c6da27779c6),
	u64(0x6555830061603576),
	u64(0x02ec49f14ec5fb05),
	u64(0xb7779c004de6912b),
	u64(0x0256a18dd89e626a),
	u64(0xf258f99a163db512),
	u64(0x03bdcf495a9703dd),
	u64(0x5b7a614811caf741),
	u64(0x02fe3f6de212697e),
	u64(0xaf951aa00e3bf901),
	u64(0x0264ff8b1b41edfe),
	u64(0x7f54f7667d2cc19b),
	u64(0x03d4cc11c5364997),
	u64(0x32aa5f8530f09ae3),
	u64(0x0310a3416a91d479),
	u64(0xf55519375a5a1582),
	u64(0x0273b5cdeedb1060),
	u64(0xbbbb5b8bc3c3559d),
	u64(0x03ec56164af81a34),
	u64(0x2fc916096969114a),
	u64(0x03237811d593482a),
	u64(0x596dab3ababa743c),
	u64(0x0282c674aadc39bb),
	u64(0x478aef622efb9030),
	u64(0x0202385d557cfafc),
	u64(0xd8de4bd04b2c19e6),
	u64(0x0336c0955594c4c6),
	u64(0xad7ea30d08f014b8),
	u64(0x029233aaaadd6a38),
	u64(0x24654f3da0c01093),
	u64(0x020e8fbbbbe454fa),
	u64(0x3a3bb1fc346680eb),
	u64(0x034a7f92c63a2190),
	u64(0x94fc8e635d1ecd89),
	u64(0x02a1ffa89e94e7a6),
	u64(0xaa63a51c4a7f0ad4),
	u64(0x021b32ed4baa52eb),
	u64(0xdd6c3b607731aaed),
	u64(0x035eb7e212aa1e45),
	u64(0x1789c919f8f488bd),
	u64(0x02b22cb4dbbb4b6b),
	u64(0xac6e3a7b2d906d64),
	u64(0x022823c3e2fc3c55),
	u64(0x13e390c515b3e23a),
	u64(0x03736c6c9e606089),
	u64(0xdcb60d6a77c31b62),
	u64(0x02c2bd23b1e6b3a0),
	u64(0x7d5e7121f968e2b5),
	u64(0x0235641c8e52294d),
	u64(0xc8971b698f0e3787),
	u64(0x0388a02db0837548),
	u64(0xa078e2bad8d82c6c),
	u64(0x02d3b357c0692aa0),
	u64(0xe6c71bc8ad79bd24),
	u64(0x0242f5dfcd20eee6),
	u64(0x0ad82c7448c2c839),
	u64(0x039e5632e1ce4b0b),
	u64(0x3be023903a356cfa),
	u64(0x02e511c24e3ea26f),
	u64(0x2fe682d9c82abd95),
	u64(0x0250db01d8321b8c),
	u64(0x4ca4048fa6aac8ee),
	u64(0x03b4919c8d1cf8e0),
	u64(0x3d5003a61eef0725),
	u64(0x02f6dae3a4172d80),
	u64(0x9773361e7f259f51),
	u64(0x025f1582e9ac2466),
	u64(0x8beb89ca6508fee8),
	u64(0x03cb559e42ad070a),
	u64(0x6fefa16eb73a6586),
	u64(0x0309114b688a6c08),
	u64(0xf3261abef8fb846b),
	u64(0x026da76f86d52339),
	u64(0x51d691318e5f3a45),
	u64(0x03e2a57f3e21d1f6),
	u64(0x0e4540f471e5c837),
	u64(0x031bb798fe8174c5),
	u64(0xd8376729f4b7d360),
	u64(0x027c92e0cb9ac3d0),
	u64(0xf38bd84321261eff),
	u64(0x03fa849adf5e061a),
	u64(0x293cad0280eb4bff),
	u64(0x032ed07be5e4d1af),
	u64(0xedca240200bc3ccc),
	u64(0x028bd9fcb7ea4158),
	u64(0xbe3b50019a3030a4),
	u64(0x02097b309321cde0),
	u64(0xc9f88002904d1a9f),
	u64(0x03425eb41e9c7c9a),
	u64(0x3b2d3335403daee6),
	u64(0x029b7ef67ee396e2),
	u64(0x95bdc291003158b8),
	u64(0x0215ff2b98b6124e),
	u64(0x892f9db4cd1bc126),
	u64(0x035665128df01d4a),
	u64(0x07594af70a7c9a85),
	u64(0x02ab840ed7f34aa2),
	u64(0x6c476f2c0863aed1),
	u64(0x0222d00bdff5d54e),
	u64(0x13a57eacda3917b4),
	u64(0x036ae67966562217),
	u64(0x0fb7988a482dac90),
	u64(0x02bbeb9451de81ac),
	u64(0xd95fad3b6cf156da),
	u64(0x022fefa9db1867bc),
	u64(0xf565e1f8ae4ef15c),
	u64(0x037fe5dc91c0a5fa),
	u64(0x911e4e608b725ab0),
	u64(0x02ccb7e3a7cd5195),
	u64(0xda7ea51a0928488d),
	u64(0x023d5fe9530aa7aa),
	u64(0xf7310829a8407415),
	u64(0x039566421e7772aa),
	u64(0x2c2739baed005cde),
	u64(0x02ddeb68185f8eef),
	u64(0xbcec2e2f24004a4b),
	u64(0x024b22b9ad193f25),
	u64(0x94ad16b1d333aa11),
	u64(0x03ab6ac2ae8ecb6f),
	u64(0xaa241227dc2954db),
	u64(0x02ef889bbed8a2bf),
	u64(0x54e9a81fe35443e2),
	u64(0x02593a163246e899),
	u64(0x2175d9cc9eed396a),
	u64(0x03c1f689ea0b0dc2),
	u64(0xe7917b0a18bdc788),
	u64(0x03019207ee6f3e34),
	u64(0xb9412f3b46fe393a),
	u64(0x0267a8065858fe90),
	u64(0xf535185ed7fd285c),
	u64(0x03d90cd6f3c1974d),
	u64(0xc42a79e57997537d),
	u64(0x03140a458fce12a4),
	u64(0x03552e512e12a931),
	u64(0x02766e9e0ca4dbb7),
	u64(0x9eeeb081e3510eb4),
	u64(0x03f0b0fce107c5f1),
	u64(0x4bf226ce4f740bc3),
	u64(0x0326f3fd80d304c1),
	u64(0xa3281f0b72c33c9c),
	u64(0x02858ffe00a8d09a),
	u64(0x1c2018d5f568fd4a),
	u64(0x020473319a20a6e2),
	u64(0xf9ccf48988a7fba9),
	u64(0x033a51e8f69aa49c),
	u64(0xfb0a5d3ad3b99621),
	u64(0x02950e53f87bb6e3),
	u64(0x2f3b7dc8a96144e7),
	u64(0x0210d8432d2fc583),
	u64(0xe52bfc7442353b0c),
	u64(0x034e26d1e1e608d1),
	u64(0xb756639034f76270),
	u64(0x02a4ebdb1b1e6d74),
	u64(0x2c451c735d92b526),
	u64(0x021d897c15b1f12a),
	u64(0x13a1c71efc1deea3),
	u64(0x0362759355e981dd),
	u64(0x761b05b2634b2550),
	u64(0x02b52adc44bace4a),
	u64(0x91af37c1e908eaa6),
	u64(0x022a88b036fbd83b),
	u64(0x82b1f2cfdb417770),
	u64(0x03774119f192f392),
	u64(0xcef4c23fe29ac5f3),
	u64(0x02c5cdae5adbf60e),
	u64(0x3f2a34ffe87bd190),
	u64(0x0237d7beaf165e72),
	u64(0x984387ffda5fb5b2),
	u64(0x038c8c644b56fd83),
	u64(0xe0360666484c915b),
	u64(0x02d6d6b6a2abfe02),
	u64(0x802b3851d3707449),
	u64(0x024578921bbccb35),
	u64(0x99dec082ebe72075),
	u64(0x03a25a835f947855),
	u64(0xae4bcd358985b391),
	u64(0x02e8486919439377),
	u64(0xbea30a913ad15c74),
	u64(0x02536d20e102dc5f),
	u64(0xfdd1aa81f7b560b9),
	u64(0x03b8ae9b019e2d65),
	u64(0x97daeece5fc44d61),
	u64(0x02fa2548ce182451),
	u64(0xdfe258a51969d781),
	u64(0x0261b76d71ace9da),
	u64(0x996a276e8f0fbf34),
	u64(0x03cf8be24f7b0fc4),
	u64(0xe121b9253f3fcc2a),
	u64(0x030c6fe83f95a636),
	u64(0xb41afa8432997022),
	u64(0x02705986994484f8),
	u64(0xecf7f739ea8f19cf),
	u64(0x03e6f5a4286da18d),
	u64(0x23f99294bba5ae40),
	u64(0x031f2ae9b9f14e0b),
	u64(0x4ffadbaa2fb7be99),
	u64(0x027f5587c7f43e6f),
	u64(0x7ff7c5dd1925fdc2),
	u64(0x03feef3fa6539718),
	u64(0xccc637e4141e649b),
	u64(0x033258ffb842df46),
	u64(0xd704f983434b83af),
	u64(0x028ead9960357f6b),
	u64(0x126a6135cf6f9c8c),
	u64(0x020bbe144cf79923),
	u64(0x83dd685618b29414),
	u64(0x0345fced47f28e9e),
	u64(0x9cb12044e08edcdd),
	u64(0x029e63f1065ba54b),
	u64(0x16f419d0b3a57d7d),
	u64(0x02184ff405161dd6),
	u64(0x8b20294dec3bfbfb),
	u64(0x035a19866e89c956),
	u64(0x3c19baa4bcfcc996),
	u64(0x02ae7ad1f207d445),
	u64(0xc9ae2eea30ca3adf),
	u64(0x02252f0e5b39769d),
	u64(0x0f7d17dd1add2afd),
	u64(0x036eb1b091f58a96),
	u64(0x3f97464a7be42264),
	u64(0x02bef48d41913bab),
	u64(0xcc790508631ce850),
	u64(0x02325d3dce0dc955),
	u64(0xe0c1a1a704fb0d4d),
	u64(0x0383c862e3494222),
	u64(0x4d67b4859d95a43e),
	u64(0x02cfd3824f6dce82),
	u64(0x711fc39e17aae9cb),
	u64(0x023fdc683f8b0b9b),
	u64(0xe832d2968c44a945),
	u64(0x039960a6cc11ac2b),
	u64(0xecf575453d03ba9e),
	u64(0x02e11a1f09a7bcef),
	u64(0x572ac4376402fbb1),
	u64(0x024dae7f3aec9726),
	u64(0x58446d256cd192b5),
	u64(0x03af7d985e47583d),
	u64(0x79d0575123dadbc4),
	u64(0x02f2cae04b6c4697),
	u64(0x94a6ac40e97be303),
	u64(0x025bd5803c569edf),
	u64(0x8771139b0f2c9e6c),
	u64(0x03c62266c6f0fe32),
	u64(0x9f8da948d8f07ebd),
	u64(0x0304e85238c0cb5b),
	u64(0xe60aedd3e0c06564),
	u64(0x026a5374fa33d5e2),
	u64(0xa344afb9679a3bd2),
	u64(0x03dd5254c3862304),
	u64(0xe903bfc78614fca8),
	u64(0x031775109c6b4f36),
	u64(0xba6966393810ca20),
	u64(0x02792a73b055d8f8),
	u64(0x2a423d2859b4769a),
	u64(0x03f510b91a22f4c1),
	u64(0xee9b642047c39215),
	u64(0x032a73c7481bf700),
	u64(0xbee2b680396941aa),
	u64(0x02885c9f6ce32c00),
	u64(0xff1bc53361210155),
	u64(0x0206b07f8a4f5666),
	u64(0x31c6085235019bbb),
	u64(0x033de73276e5570b),
	u64(0x27d1a041c4014963),
	u64(0x0297ec285f1ddf3c),
	u64(0xeca7b367d0010782),
	u64(0x021323537f4b18fc),
	u64(0xadd91f0c8001a59d),
	u64(0x0351d21f3211c194),
	u64(0xf17a7f3d3334847e),
	u64(0x02a7db4c280e3476),
	u64(0x279532975c2a0398),
	u64(0x021fe2a3533e905f),
	u64(0xd8eeb75893766c26),
	u64(0x0366376bb8641a31),
	u64(0x7a5892ad42c52352),
	u64(0x02b82c562d1ce1c1),
	u64(0xfb7a0ef102374f75),
	u64(0x022cf044f0e3e7cd),
	u64(0xc59017e8038bb254),
	u64(0x037b1a07e7d30c7c),
	u64(0x37a67986693c8eaa),
	u64(0x02c8e19feca8d6ca),
	u64(0xf951fad1edca0bbb),
	u64(0x023a4e198a20abd4),
	u64(0x28832ae97c76792b),
	u64(0x03907cf5a9cddfbb),
	u64(0x2068ef21305ec756),
	u64(0x02d9fd9154a4b2fc),
	u64(0x19ed8c1a8d189f78),
	u64(0x0247fe0ddd508f30),
	u64(0x5caf4690e1c0ff26),
	u64(0x03a66349621a7eb3),
	u64(0x4a25d20d81673285),
	u64(0x02eb82a11b48655c),
	u64(0x3b5174d79ab8f537),
	u64(0x0256021a7c39eab0),
	u64(0x921bee25c45b21f1),
	u64(0x03bcd02a605caab3),
	u64(0xdb498b5169e2818e),
	u64(0x02fd735519e3bbc2),
	u64(0x15d46f7454b53472),
	u64(0x02645c4414b62fcf),
	u64(0xefba4bed545520b6),
	u64(0x03d3c6d35456b2e4),
	u64(0xf2fb6ff110441a2b),
	u64(0x030fd242a9def583),
	u64(0x8f2f8cc0d9d014ef),
	u64(0x02730e9bbb18c469),
	u64(0xb1e5ae015c80217f),
	u64(0x03eb4a92c4f46d75),
	u64(0xc1848b344a001acc),
	u64(0x0322a20f03f6bdf7),
	u64(0xce03a2903b3348a3),
	u64(0x02821b3f365efe5f),
	u64(0xd802e873628f6d4f),
	u64(0x0201af65c518cb7f),
	u64(0x599e40b89db2487f),
	u64(0x0335e56fa1c14599),
	u64(0xe14b66fa17c1d399),
	u64(0x029184594e3437ad),
	u64(0x81091f2e7967dc7a),
	u64(0x020e037aa4f692f1),
	u64(0x9b41cb7d8f0c93f6),
	u64(0x03499f2aa18a84b5),
	u64(0xaf67d5fe0c0a0ff8),
	u64(0x02a14c221ad536f7),
	u64(0xf2b977fe70080cc7),
	u64(0x021aa34e7bddc592),
	u64(0x1df58cca4cd9ae0b),
	u64(0x035dd2172c9608eb),
	u64(0xe4c470a1d7148b3c),
	u64(0x02b174df56de6d88),
	u64(0x83d05a1b1276d5ca),
	u64(0x022790b2abe5246d),
	u64(0x9fb3c35e83f1560f),
	u64(0x0372811ddfd50715),
	u64(0xb2f635e5365aab3f),
	u64(0x02c200e4b310d277),
	u64(0xf591c4b75eaeef66),
	u64(0x0234cd83c273db92),
	u64(0xef4fa125644b18a3),
	u64(0x0387af39371fc5b7),
	u64(0x8c3fb41de9d5ad4f),
	u64(0x02d2f2942c196af9),
	u64(0x3cffc34b2177bdd9),
	u64(0x02425ba9bce12261),
	u64(0x94cc6bab68bf9628),
	u64(0x039d5f75fb01d09b),
	u64(0x10a38955ed6611b9),
	u64(0x02e44c5e6267da16),
	u64(0xda1c6dde5784dafb),
	u64(0x02503d184eb97b44),
	u64(0xf693e2fd58d49191),
	u64(0x03b394f3b128c53a),
	u64(0xc5431bfde0aa0e0e),
	u64(0x02f610c2f4209dc8),
	u64(0x6a9c1664b3bb3e72),
	u64(0x025e73cf29b3b16d),
	u64(0x10f9bd6dec5eca4f),
	u64(0x03ca52e50f85e8af),
	u64(0xda616457f04bd50c),
	u64(0x03084250d937ed58),
	u64(0xe1e783798d09773d),
	u64(0x026d01da475ff113),
	u64(0x030c058f480f252e),
	u64(0x03e19c9072331b53),
	u64(0x68d66ad906728425),
	u64(0x031ae3a6c1c27c42),
	u64(0x8711ef14052869b7),
	u64(0x027be952349b969b),
	u64(0x0b4fe4ecd50d75f2),
	u64(0x03f97550542c242c),
	u64(0xa2a650bd773df7f5),
	u64(0x032df7737689b689),
	u64(0xb551da312c31932a),
	u64(0x028b2c5c5ed49207),
	u64(0x5ddb14f4235adc22),
	u64(0x0208f049e576db39),
	u64(0x2fc4ee536bc49369),
	u64(0x034180763bf15ec2),
	u64(0xbfd0bea92303a921),
	u64(0x029acd2b63277f01),
	u64(0x9973cbba8269541a),
	u64(0x021570ef8285ff34),
	u64(0x5bec792a6a42202a),
	u64(0x0355817f373ccb87),
	u64(0xe3239421ee9b4cef),
	u64(0x02aacdff5f63d605),
	u64(0xb5b6101b25490a59),
	u64(0x02223e65e5e97804),
	u64(0x22bce691d541aa27),
	u64(0x0369fd6fd64259a1),
	u64(0xb563eba7ddce21b9),
	u64(0x02bb31264501e14d),
	u64(0xf78322ecb171b494),
	u64(0x022f5a850401810a),
	u64(0x259e9e47824f8753),
	u64(0x037ef73b399c01ab),
	u64(0x1e187e9f9b72d2a9),
	u64(0x02cbf8fc2e1667bc),
	u64(0x4b46cbb2e2c24221),
	u64(0x023cc73024deb963),
	u64(0x120adf849e039d01),
	u64(0x039471e6a1645bd2),
	u64(0xdb3be603b19c7d9a),
	u64(0x02dd27ebb4504974),
	u64(0x7c2feb3627b0647c),
	u64(0x024a865629d9d45d),
	u64(0x2d197856a5e7072c),
	u64(0x03aa7089dc8fba2f),
	u64(0x8a7ac6abb7ec05bd),
	u64(0x02eec06e4a0c94f2),
	u64(0xd52f05562cbcd164),
	u64(0x025899f1d4d6dd8e),
	u64(0x21e4d556adfae8a0),
	u64(0x03c0f64fbaf1627e),
	u64(0xe7ea444557fbed4d),
	u64(0x0300c50c958de864),
	u64(0xecbb69d1132ff10a),
	u64(0x0267040a113e5383),
	u64(0xadf8a94e851981aa),
	u64(0x03d8067681fd526c),
	u64(0x8b2d543ed0e13488),
	u64(0x0313385ece6441f0),
	u64(0xd5bddcff0d80f6d3),
	u64(0x0275c6b23eb69b26),
	u64(0x892fc7fe7c018aeb),
	u64(0x03efa45064575ea4),
	u64(0x3a8c9ffec99ad589),
	u64(0x03261d0d1d12b21d),
	u64(0xc8707fff07af113b),
	u64(0x0284e40a7da88e7d),
	u64(0x39f39998d2f2742f),
	u64(0x0203e9a1fe2071fe),
	u64(0x8fec28f484b7204b),
	u64(0x033975cffd00b663),
	u64(0xd989ba5d36f8e6a2),
	u64(0x02945e3ffd9a2b82),
	u64(0x47a161e42bfa521c),
	u64(0x02104b66647b5602),
	u64(0x0c35696d132a1cf9),
	u64(0x034d4570a0c5566a),
	u64(0x09c454574288172d),
	u64(0x02a4378d4d6aab88),
	u64(0xa169dd129ba0128b),
	u64(0x021cf93dd7888939),
	u64(0x0242fb50f9001dab),
	u64(0x03618ec958da7529),
	u64(0x9b68c90d940017bc),
	u64(0x02b4723aad7b90ed),
	u64(0x4920a0d7a999ac96),
	u64(0x0229f4fbbdfc73f1),
	u64(0x750101590f5c4757),
	u64(0x037654c5fcc71fe8),
	u64(0x2a6734473f7d05df),
	u64(0x02c5109e63d27fed),
	u64(0xeeb8f69f65fd9e4c),
	u64(0x0237407eb641fff0),
	u64(0xe45b24323cc8fd46),
	u64(0x038b9a6456cfffe7),
	u64(0xb6af502830a0ca9f),
	u64(0x02d6151d123fffec),
	u64(0xf88c402026e7087f),
	u64(0x0244ddb0db666656),
	u64(0x2746cd003e3e73fe),
	u64(0x03a162b4923d708b),
	u64(0x1f6bd73364fec332),
	u64(0x02e7822a0e978d3c),
	u64(0xe5efdf5c50cbcf5b),
	u64(0x0252ce880bac70fc),
	u64(0x3cb2fefa1adfb22b),
	u64(0x03b7b0d9ac471b2e),
	u64(0x308f3261af195b56),
	u64(0x02f95a47bd05af58),
	u64(0x5a0c284e25ade2ab),
	u64(0x0261150630d15913),
	u64(0x29ad0d49d5e30445),
	u64(0x03ce8809e7b55b52),
	u64(0x548a7107de4f369d),
	u64(0x030ba007ec9115db),
	u64(0xdd3b8d9fe50c2bb1),
	u64(0x026fb3398a0dab15),
	u64(0x952c15cca1ad12b5),
	u64(0x03e5eb8f434911bc),
	u64(0x775677d6e7bda891),
	u64(0x031e560c35d40e30),
	u64(0xc5dec645863153a7),
	u64(0x027eab3cf7dcd826),
]!

/*
f32/f64 to string utilities

Copyright (c) 2019-2024 Dario Deledda. All rights reserved.
Use of this source code is governed by an MIT license
that can be found in the LICENSE file.

This file contains the f32/f64 to string utilities functions

These functions are based on the work of:
Publication:PLDI 2018: Proceedings of the 39th ACM SIGPLAN
Conference on Programming Language Design and ImplementationJune 2018
Pages 270–282 https://doi.org/10.1145/3192366.3192369

inspired by the Go version here:
https://github.com/cespare/ryu/tree/ba56a33f39e3bbbfa409095d0f9ae168a595feea
*/

/*
f64 to string with string format
*/

// TODO: Investigate precision issues
// f32_to_str_l returns `f` as a `string` in decimal notation with a maximum of 8 digits after the dot.
// Example: assert strconv.f32_to_str_l(0.1234567891) == '0.12345679'
// Example: assert strconv.f32_to_str_l(34.1234567891) == '34.123455'
@[manualfree]
pub fn f32_to_str_l(f f32) string {
	s := f32_to_str(f, 8)
	res := fxx_to_str_l_parse(s)
	unsafe { s.free() }
	return res
}

// f32_to_str_l_with_dot returns `f` as a `string` in decimal notation with a maximum of 8 digits after the dot.
// If the decimal digits after the dot are zero, a '.0' is appended for clarity.
//
// Example: assert strconv.f32_to_str_l_with_dot(34.2) == '34.2'
@[manualfree]
pub fn f32_to_str_l_with_dot(f f32) string {
	s := f32_to_str(f, 8)
	res := fxx_to_str_l_parse_with_dot(s)
	unsafe { s.free() }
	return res
}

// f64_to_str_l returns `f` as a `string` in decimal notation with a maximum of 18 digits after the dot.
//
// Example: assert strconv.f64_to_str_l(123.1234567891011121) == '123.12345678910111'
@[manualfree]
pub fn f64_to_str_l(f f64) string {
	s := f64_to_str(f, 18)
	res := fxx_to_str_l_parse(s)
	unsafe { s.free() }
	return res
}

// f64_to_str_l_with_dot returns `f` as a `string` in decimal notation with a maximum of 18 digits after the dot.
// If the decimal digits after the dot are zero, a '.0' is appended for clarity.
//
// Example: assert strconv.f64_to_str_l_with_dot(34.7) == '34.7'
@[manualfree]
pub fn f64_to_str_l_with_dot(f f64) string {
	s := f64_to_str(f, 18)
	res := fxx_to_str_l_parse_with_dot(s)
	unsafe { s.free() }
	return res
}

// fxx_to_str_l_parse returns a `string` in decimal notation converted from a
// floating-point `string` in scientific notation.
//
// Example: assert strconv.fxx_to_str_l_parse('34.22e+00') == '34.22'
@[direct_array_access; manualfree]
pub fn fxx_to_str_l_parse(s string) string {
	// check for +inf -inf Nan
	if s.len > 2 && (s[0] == `n` || s[1] == `i`) {
		return s.clone()
	}

	m_sgn_flag := false
	mut sgn := 1
	mut b := [26]u8{}
	mut d_pos := 1
	mut i := 0
	mut i1 := 0
	mut exp := 0
	mut exp_sgn := 1

	// get sign and decimal parts
	for c in s {
		if c == `-` {
			sgn = -1
			i++
		} else if c == `+` {
			sgn = 1
			i++
		} else if c >= `0` && c <= `9` {
			b[i1] = c
			i1++
			i++
		} else if c == `.` {
			if sgn > 0 {
				d_pos = i
			} else {
				d_pos = i - 1
			}
			i++
		} else if c == `e` {
			i++
			break
		} else {
			return 'Float conversion error!!'
		}
	}
	b[i1] = 0

	// get exponent
	if s[i] == `-` {
		exp_sgn = -1
		i++
	} else if s[i] == `+` {
		exp_sgn = 1
		i++
	}

	mut c := i
	for c < s.len {
		exp = exp * 10 + int(s[c] - `0`)
		c++
	}

	// allocate exp+32 chars for the return string
	mut res := []u8{len: exp + 32, init: 0}
	mut r_i := 0 // result string buffer index

	// println("s:${sgn} b:${b[0]} es:${exp_sgn} exp:${exp}")

	if sgn == 1 {
		if m_sgn_flag {
			res[r_i] = `+`
			r_i++
		}
	} else {
		res[r_i] = `-`
		r_i++
	}

	i = 0
	if exp_sgn >= 0 {
		for b[i] != 0 {
			res[r_i] = b[i]
			r_i++
			i++
			if i >= d_pos && exp >= 0 {
				if exp == 0 {
					res[r_i] = `.`
					r_i++
				}
				exp--
			}
		}
		for exp >= 0 {
			res[r_i] = `0`
			r_i++
			exp--
		}
	} else {
		mut dot_p := true
		for exp > 0 {
			res[r_i] = `0`
			r_i++
			exp--
			if dot_p {
				res[r_i] = `.`
				r_i++
				dot_p = false
			}
		}
		for b[i] != 0 {
			res[r_i] = b[i]
			r_i++
			i++
		}
	}

	// Add a zero after the dot from the numbers like 2.
	if r_i > 1 && res[r_i - 1] == `.` {
		res[r_i] = `0`
		r_i++
	} else if `.` !in res {
		// If there is no dot, add it with a zero
		res[r_i] = `.`
		r_i++
		res[r_i] = `0`
		r_i++
	}

	res[r_i] = 0
	return unsafe { tos(res.data, r_i) }
}

// fxx_to_str_l_parse_with_dot returns a `string` in decimal notation converted from a
// floating-point `string` in scientific notation.
// If the decimal digits after the dot are zero, a '.0' is appended for clarity.
//
// Example: assert strconv.fxx_to_str_l_parse_with_dot ('34.e+01') == '340.0'
@[direct_array_access; manualfree]
pub fn fxx_to_str_l_parse_with_dot(s string) string {
	// check for +inf -inf Nan
	if s.len > 2 && (s[0] == `n` || s[1] == `i`) {
		return s.clone()
	}

	m_sgn_flag := false
	mut sgn := 1
	mut b := [26]u8{}
	mut d_pos := 1
	mut i := 0
	mut i1 := 0
	mut exp := 0
	mut exp_sgn := 1

	// get sign and decimal parts
	for c in s {
		if c == `-` {
			sgn = -1
			i++
		} else if c == `+` {
			sgn = 1
			i++
		} else if c >= `0` && c <= `9` {
			b[i1] = c
			i1++
			i++
		} else if c == `.` {
			if sgn > 0 {
				d_pos = i
			} else {
				d_pos = i - 1
			}
			i++
		} else if c == `e` {
			i++
			break
		} else {
			return 'Float conversion error!!'
		}
	}
	b[i1] = 0

	// get exponent
	if s[i] == `-` {
		exp_sgn = -1
		i++
	} else if s[i] == `+` {
		exp_sgn = 1
		i++
	}

	mut c := i
	for c < s.len {
		exp = exp * 10 + int(s[c] - `0`)
		c++
	}

	// allocate exp+32 chars for the return string
	mut res := []u8{len: exp + 32, init: 0}
	mut r_i := 0 // result string buffer index

	// println("s:${sgn} b:${b[0]} es:${exp_sgn} exp:${exp}")

	if sgn == 1 {
		if m_sgn_flag {
			res[r_i] = `+`
			r_i++
		}
	} else {
		res[r_i] = `-`
		r_i++
	}

	i = 0
	if exp_sgn >= 0 {
		for b[i] != 0 {
			res[r_i] = b[i]
			r_i++
			i++
			if i >= d_pos && exp >= 0 {
				if exp == 0 {
					res[r_i] = `.`
					r_i++
				}
				exp--
			}
		}
		for exp >= 0 {
			res[r_i] = `0`
			r_i++
			exp--
		}
	} else {
		mut dot_p := true
		for exp > 0 {
			res[r_i] = `0`
			r_i++
			exp--
			if dot_p {
				res[r_i] = `.`
				r_i++
				dot_p = false
			}
		}
		for b[i] != 0 {
			res[r_i] = b[i]
			r_i++
			i++
		}
	}

	// Add a zero after the dot from the numbers like 2.
	if r_i > 1 && res[r_i - 1] == `.` {
		res[r_i] = `0`
		r_i++
	} else if `.` !in res {
		// If there is no dot, add it with a zero
		res[r_i] = `.`
		r_i++
		res[r_i] = `0`
		r_i++
	}

	res[r_i] = 0
	return unsafe { tos(res.data, r_i) }
}

// general utilities

// General Utilities
@[if debug_strconv ?]
fn assert1(t bool, msg string) {
	if !t {
		panic(msg)
	}
}

@[inline]
fn bool_to_int(b bool) int {
	if b {
		return 1
	}
	return 0
}

@[inline]
fn bool_to_u32(b bool) u32 {
	if b {
		return u32(1)
	}
	return u32(0)
}

@[inline]
fn bool_to_u64(b bool) u64 {
	if b {
		return u64(1)
	}
	return u64(0)
}

fn get_string_special(neg bool, expZero bool, mantZero bool) string {
	if !mantZero {
		return 'nan'
	}
	if !expZero {
		if neg {
			return '-inf'
		} else {
			return '+inf'
		}
	}
	if neg {
		return '-0e+00'
	}
	return '0e+00'
}

/*
32 bit functions
*/

fn mul_shift_32(m u32, mul u64, ishift int) u32 {
	// QTODO
	// assert ishift > 32

	hi, lo := bits.mul_64(u64(m), mul)
	shifted_sum := (lo >> u64(ishift)) + (hi << u64(64 - ishift))
	assert1(shifted_sum <= 2147483647, 'shiftedSum <= math.max_u32')
	return u32(shifted_sum)
}

@[direct_array_access; inline]
fn mul_pow5_invdiv_pow2(m u32, q u32, j int) u32 {
	assert1(q < pow5_inv_split_32.len, 'q < pow5_inv_split_32.len')
	return mul_shift_32(m, pow5_inv_split_32[q], j)
}

@[direct_array_access; inline]
fn mul_pow5_div_pow2(m u32, i u32, j int) u32 {
	assert1(i < pow5_split_32.len, 'i < pow5_split_32.len')
	return mul_shift_32(m, pow5_split_32[i], j)
}

fn pow5_factor_32(i_v u32) u32 {
	mut v := i_v
	for n := u32(0); true; n++ {
		q := v / 5
		r := v % 5
		if r != 0 {
			return n
		}
		v = q
	}
	return v
}

// multiple_of_power_of_five_32 reports whether v is divisible by 5^p.
fn multiple_of_power_of_five_32(v u32, p u32) bool {
	return pow5_factor_32(v) >= p
}

// multiple_of_power_of_two_32 reports whether v is divisible by 2^p.
fn multiple_of_power_of_two_32(v u32, p u32) bool {
	return u32(bits.trailing_zeros_32(v)) >= p
}

// log10_pow2 returns floor(log_10(2^e)).
fn log10_pow2(e int) u32 {
	// The first value this approximation fails for is 2^1651
	// which is just greater than 10^297.
	assert1(e >= 0, 'e >= 0')
	assert1(e <= 1650, 'e <= 1650')
	return (u32(e) * 78913) >> 18
}

// log10_pow5 returns floor(log_10(5^e)).
fn log10_pow5(e int) u32 {
	// The first value this approximation fails for is 5^2621
	// which is just greater than 10^1832.
	assert1(e >= 0, 'e >= 0')
	assert1(e <= 2620, 'e <= 2620')
	return (u32(e) * 732923) >> 20
}

// pow5_bits returns ceil(log_2(5^e)), or else 1 if e==0.
fn pow5_bits(e int) int {
	// This approximation works up to the point that the multiplication
	// overflows at e = 3529. If the multiplication were done in 64 bits,
	// it would fail at 5^4004 which is just greater than 2^9297.
	assert1(e >= 0, 'e >= 0')
	assert1(e <= 3528, 'e <= 3528')
	return int(((u32(e) * 1217359) >> 19) + 1)
}

/*
64 bit functions
*/

fn shift_right_128(v Uint128, shift int) u64 {
	// The shift value is always modulo 64.
	// In the current implementation of the 64-bit version
	// of Ryu, the shift value is always < 64.
	// (It is in the range [2, 59].)
	// Check this here in case a future change requires larger shift
	// values. In this case this function needs to be adjusted.
	assert1(shift < 64, 'shift < 64')
	return (v.hi << u64(64 - shift)) | (v.lo >> u32(shift))
}

fn mul_shift_64(m u64, mul Uint128, shift int) u64 {
	hihi, hilo := bits.mul_64(m, mul.hi)
	lohi, _ := bits.mul_64(m, mul.lo)
	mut sum := Uint128{
		lo: lohi + hilo
		hi: hihi
	}
	if sum.lo < lohi {
		sum.hi++ // overflow
	}
	return shift_right_128(sum, shift - 64)
}

fn pow5_factor_64(v_i u64) u32 {
	mut v := v_i
	for n := u32(0); true; n++ {
		q := v / 5
		r := v % 5
		if r != 0 {
			return n
		}
		v = q
	}
	return u32(0)
}

fn multiple_of_power_of_five_64(v u64, p u32) bool {
	return pow5_factor_64(v) >= p
}

fn multiple_of_power_of_two_64(v u64, p u32) bool {
	return u32(bits.trailing_zeros_64(v)) >= p
}

// dec_digits return the number of decimal digit of an u64
pub fn dec_digits(n u64) int {
	if n <= 9_999_999_999 { // 1-10
		if n <= 99_999 { // 5
			if n <= 99 { // 2
				if n <= 9 { // 1
					return 1
				} else {
					return 2
				}
			} else {
				if n <= 999 { // 3
					return 3
				} else {
					if n <= 9999 { // 4
						return 4
					} else {
						return 5
					}
				}
			}
		} else {
			if n <= 9_999_999 { // 7
				if n <= 999_999 { // 6
					return 6
				} else {
					return 7
				}
			} else {
				if n <= 99_999_999 { // 8
					return 8
				} else {
					if n <= 999_999_999 { // 9
						return 9
					}
					return 10
				}
			}
		}
	} else {
		if n <= 999_999_999_999_999 { // 5
			if n <= 999_999_999_999 { // 2
				if n <= 99_999_999_999 { // 1
					return 11
				} else {
					return 12
				}
			} else {
				if n <= 9_999_999_999_999 { // 3
					return 13
				} else {
					if n <= 99_999_999_999_999 { // 4
						return 14
					} else {
						return 15
					}
				}
			}
		} else {
			if n <= 99_999_999_999_999_999 { // 7
				if n <= 9_999_999_999_999_999 { // 6
					return 16
				} else {
					return 17
				}
			} else {
				if n <= 999_999_999_999_999_999 { // 8
					return 18
				} else {
					if n <= 9_999_999_999_999_999_999 { // 9
						return 19
					}
					return 20
				}
			}
		}
	}
}
/*=============================================================================
Copyright (c) 2019-2024 Dario Deledda. All rights reserved.
Use of this source code is governed by an MIT license
that can be found in the LICENSE file.

This file contains string interpolation V functions
=============================================================================*/

enum Char_parse_state {
	start
	norm_char
	field_char
	pad_ch
	len_set_start
	len_set_in
	check_type
	check_float
	check_float_in
	reset_params
}

// v_printf prints a sprintf-like formatted `string` to the terminal.
// The format string `str` can be constructed at runtime.
// Note, that this function is unsafe.
// In most cases, you are better off using V's string interpolation,
// when your format string is known at compile time.
@[unsafe]
pub fn v_printf(str string, pt ...voidptr) {
	print(unsafe { v_sprintf(str, ...pt) })
}

// v_sprintf returns a sprintf-like formatted `string`.
// The format string `str` can be constructed at runtime.
// Note, that this function is unsafe.
// In most cases, you are better off using V's string interpolation,
// when your format string is known at compile time.
// Example:
// ```v
// x := 3.141516
// assert unsafe{strconv.v_sprintf('aaa %G', x)} == 'aaa 3.141516'
// ```
@[direct_array_access; manualfree; unsafe]
pub fn v_sprintf(str string, pt ...voidptr) string {
	mut res := strings.new_builder(pt.len * 16)
	defer {
		unsafe { res.free() }
	}

	mut i := 0 // main string index
	mut p_index := 0 // parameter index
	mut sign := false // sign flag
	mut align := Align_text.right
	mut len0 := -1 // forced length, if -1 free length
	mut len1 := -1 // decimal part for floats
	def_len1 := 6 // default value for len1
	mut pad_ch := u8(` `) // pad char

	// prefix chars for Length field
	mut ch1 := `0` // +1 char if present else `0`
	mut ch2 := `0` // +2 char if present else `0`

	mut status := Char_parse_state.norm_char
	for i < str.len {
		if status == .reset_params {
			sign = false
			align = .right
			len0 = -1
			len1 = -1
			pad_ch = ` `
			status = .norm_char
			ch1 = `0`
			ch2 = `0`
			continue
		}

		ch := str[i]
		if ch != `%` && status == .norm_char {
			res.write_u8(ch)
			i++
			continue
		}
		if ch == `%` && status == .field_char {
			status = .norm_char
			res.write_u8(ch)
			i++
			continue
		}
		if ch == `%` && status == .norm_char {
			status = .field_char
			i++
			continue
		}

		// single char, manage it here
		if ch == `c` && status == .field_char {
			v_sprintf_panic(p_index, pt.len)
			d1 := unsafe { *(&u8(pt[p_index])) }
			res.write_u8(d1)
			status = .reset_params
			p_index++
			i++
			continue
		}

		// pointer, manage it here
		if ch == `p` && status == .field_char {
			v_sprintf_panic(p_index, pt.len)
			res.write_string('0x')
			res.write_string(ptr_str(unsafe { pt[p_index] }))
			status = .reset_params
			p_index++
			i++
			continue
		}

		if status == .field_char {
			mut fc_ch1 := `0`
			mut fc_ch2 := `0`
			if (i + 1) < str.len {
				fc_ch1 = str[i + 1]
				if (i + 2) < str.len {
					fc_ch2 = str[i + 2]
				}
			}
			if ch == `+` {
				sign = true
				i++
				continue
			} else if ch == `-` {
				align = .left
				i++
				continue
			} else if ch in [`0`, ` `] {
				if align == .right {
					pad_ch = ch
				}
				i++
				continue
			} else if ch == `'` {
				i++
				continue
			} else if ch == `.` && fc_ch1 >= `1` && fc_ch1 <= `9` {
				status = .check_float
				i++
				continue
			}
			// manage "%.*s" precision field
			else if ch == `.` && fc_ch1 == `*` && fc_ch2 == `s` {
				v_sprintf_panic(p_index, pt.len)
				len := unsafe { *(&int(pt[p_index])) }
				p_index++
				v_sprintf_panic(p_index, pt.len)
				mut s := unsafe { *(&string(pt[p_index])) }
				s = s[..len]
				p_index++
				res.write_string(s)
				status = .reset_params
				i += 3
				continue
			}
			status = .len_set_start
			continue
		}

		if status == .len_set_start {
			if ch >= `1` && ch <= `9` {
				len0 = int(ch - `0`)
				status = .len_set_in
				i++
				continue
			}
			if ch == `.` {
				status = .check_float
				i++
				continue
			}
			status = .check_type
			continue
		}

		if status == .len_set_in {
			if ch >= `0` && ch <= `9` {
				len0 *= 10
				len0 += int(ch - `0`)
				i++
				continue
			}
			if ch == `.` {
				status = .check_float
				i++
				continue
			}
			status = .check_type
			continue
		}

		if status == .check_float {
			if ch >= `0` && ch <= `9` {
				len1 = int(ch - `0`)
				status = .check_float_in
				i++
				continue
			}
			status = .check_type
			continue
		}

		if status == .check_float_in {
			if ch >= `0` && ch <= `9` {
				len1 *= 10
				len1 += int(ch - `0`)
				i++
				continue
			}
			status = .check_type
			continue
		}

		if status == .check_type {
			if ch == `l` {
				if ch1 == `0` {
					ch1 = `l`
					i++
					continue
				} else {
					ch2 = `l`
					i++
					continue
				}
			} else if ch == `h` {
				if ch1 == `0` {
					ch1 = `h`
					i++
					continue
				} else {
					ch2 = `h`
					i++
					continue
				}
			}
			// signed integer
			else if ch in [`d`, `i`] {
				mut d1 := u64(0)
				mut positive := true

				// println("$ch1 $ch2")
				match ch1 {
					// h for 16 bit int
					// hh for 8 bit int
					`h` {
						if ch2 == `h` {
							v_sprintf_panic(p_index, pt.len)
							x := unsafe { *(&i8(pt[p_index])) }
							positive = if x >= 0 { true } else { false }
							d1 = if positive { u64(x) } else { u64(-x) }
						} else {
							x := unsafe { *(&i16(pt[p_index])) }
							positive = if x >= 0 { true } else { false }
							d1 = if positive { u64(x) } else { u64(-x) }
						}
					}
					// l  i64
					// ll i64 for now
					`l` {
						// placeholder for future 128bit integer code
						/*
						if ch2 == `l` {
							v_sprintf_panic(p_index, pt.len)
							x := *(&i128(pt[p_index]))
							positive = if x >= 0 { true } else { false }
							d1 = if positive { u128(x) } else { u128(-x) }
						} else {
							v_sprintf_panic(p_index, pt.len)
							x := *(&i64(pt[p_index]))
							positive = if x >= 0 { true } else { false }
							d1 = if positive { u64(x) } else { u64(-x) }
						}
						*/
						v_sprintf_panic(p_index, pt.len)
						x := unsafe { *(&i64(pt[p_index])) }
						positive = if x >= 0 { true } else { false }
						d1 = if positive { u64(x) } else { u64(-x) }
					}
					// default int
					else {
						v_sprintf_panic(p_index, pt.len)
						x := unsafe { *(&int(pt[p_index])) }
						positive = if x >= 0 { true } else { false }
						d1 = if positive { u64(x) } else { u64(-x) }
					}
				}
				tmp := format_dec_old(d1,
					pad_ch:    pad_ch
					len0:      len0
					len1:      0
					positive:  positive
					sign_flag: sign
					align:     align
				)
				res.write_string(tmp)
				unsafe { tmp.free() }
				status = .reset_params
				p_index++
				i++
				ch1 = `0`
				ch2 = `0`
				continue
			}
			// unsigned integer
			else if ch == `u` {
				mut d1 := u64(0)
				positive := true
				v_sprintf_panic(p_index, pt.len)
				match ch1 {
					// h for 16 bit unsigned int
					// hh for 8 bit unsigned int
					`h` {
						if ch2 == `h` {
							d1 = u64(unsafe { *(&u8(pt[p_index])) })
						} else {
							d1 = u64(unsafe { *(&u16(pt[p_index])) })
						}
					}
					// l  u64
					// ll u64 for now
					`l` {
						// placeholder for future 128bit integer code
						/*
						if ch2 == `l` {
							d1 = u128(*(&u128(pt[p_index])))
						} else {
							d1 = u64(*(&u64(pt[p_index])))
						}
						*/
						d1 = u64(unsafe { *(&u64(pt[p_index])) })
					}
					// default int
					else {
						d1 = u64(unsafe { *(&u32(pt[p_index])) })
					}
				}

				tmp := format_dec_old(d1,
					pad_ch:    pad_ch
					len0:      len0
					len1:      0
					positive:  positive
					sign_flag: sign
					align:     align
				)
				res.write_string(tmp)
				unsafe { tmp.free() }
				status = .reset_params
				p_index++
				i++
				continue
			}
			// hex
			else if ch in [`x`, `X`] {
				v_sprintf_panic(p_index, pt.len)
				mut s := ''
				match ch1 {
					// h for 16 bit int
					// hh fot 8 bit int
					`h` {
						if ch2 == `h` {
							x := unsafe { *(&i8(pt[p_index])) }
							s = x.hex()
						} else {
							x := unsafe { *(&i16(pt[p_index])) }
							s = x.hex()
						}
					}
					// l  i64
					// ll i64 for now
					`l` {
						// placeholder for future 128bit integer code
						/*
						if ch2 == `l` {
							x := *(&i128(pt[p_index]))
							s = x.hex()
						} else {
							x := *(&i64(pt[p_index]))
							s = x.hex()
						}
						*/
						x := unsafe { *(&i64(pt[p_index])) }
						s = x.hex()
					}
					else {
						x := unsafe { *(&int(pt[p_index])) }
						s = x.hex()
					}
				}

				if ch == `X` {
					tmp := s
					s = s.to_upper()
					unsafe { tmp.free() }
				}

				tmp := format_str(s,
					pad_ch:    pad_ch
					len0:      len0
					len1:      0
					positive:  true
					sign_flag: false
					align:     align
				)
				res.write_string(tmp)
				unsafe { tmp.free() }
				unsafe { s.free() }
				status = .reset_params
				p_index++
				i++
				continue
			}

			// float and double
			if ch in [`f`, `F`] {
				$if !nofloat ? {
					v_sprintf_panic(p_index, pt.len)
					x := unsafe { *(&f64(pt[p_index])) }
					positive := x >= f64(0.0)
					len1 = if len1 >= 0 { len1 } else { def_len1 }
					s := format_fl_old(f64(x),
						pad_ch:    pad_ch
						len0:      len0
						len1:      len1
						positive:  positive
						sign_flag: sign
						align:     align
					)
					if ch == `F` {
						tmp := s.to_upper()
						res.write_string(tmp)
						unsafe { tmp.free() }
					} else {
						res.write_string(s)
					}
					unsafe { s.free() }
				}
				status = .reset_params
				p_index++
				i++
				continue
			} else if ch in [`e`, `E`] {
				$if !nofloat ? {
					v_sprintf_panic(p_index, pt.len)
					x := unsafe { *(&f64(pt[p_index])) }
					positive := x >= f64(0.0)
					len1 = if len1 >= 0 { len1 } else { def_len1 }
					s := format_es_old(f64(x),
						pad_ch:    pad_ch
						len0:      len0
						len1:      len1
						positive:  positive
						sign_flag: sign
						align:     align
					)
					if ch == `E` {
						tmp := s.to_upper()
						res.write_string(tmp)
						unsafe { tmp.free() }
					} else {
						res.write_string(s)
					}
					unsafe { s.free() }
				}
				status = .reset_params
				p_index++
				i++
				continue
			} else if ch in [`g`, `G`] {
				$if !nofloat ? {
					v_sprintf_panic(p_index, pt.len)
					x := unsafe { *(&f64(pt[p_index])) }
					positive := x >= f64(0.0)
					mut s := ''
					tx := fabs(x)
					if tx < 999_999.0 && tx >= 0.00001 {
						// println("Here g format_fl [$tx]")
						len1 = if len1 >= 0 { len1 + 1 } else { def_len1 }
						tmp := s
						s = format_fl_old(x,
							pad_ch:       pad_ch
							len0:         len0
							len1:         len1
							positive:     positive
							sign_flag:    sign
							align:        align
							rm_tail_zero: true
						)
						unsafe { tmp.free() }
					} else {
						len1 = if len1 >= 0 { len1 + 1 } else { def_len1 }
						tmp := s
						s = format_es_old(x,
							pad_ch:       pad_ch
							len0:         len0
							len1:         len1
							positive:     positive
							sign_flag:    sign
							align:        align
							rm_tail_zero: true
						)
						unsafe { tmp.free() }
					}
					if ch == `G` {
						tmp := s.to_upper()
						res.write_string(tmp)
						unsafe { tmp.free() }
					} else {
						res.write_string(s)
					}
					unsafe { s.free() }
				}
				status = .reset_params
				p_index++
				i++
				continue
			}
			// string
			else if ch == `s` {
				v_sprintf_panic(p_index, pt.len)
				s1 := unsafe { *(&string(pt[p_index])) }
				pad_ch = ` `
				tmp := format_str(s1,
					pad_ch:    pad_ch
					len0:      len0
					len1:      0
					positive:  true
					sign_flag: false
					align:     align
				)
				res.write_string(tmp)
				unsafe { tmp.free() }
				status = .reset_params
				p_index++
				i++
				continue
			}
		}

		status = .reset_params
		p_index++
		i++
	}

	if p_index != pt.len {
		panic_n2('% conversion specifiers number mismatch (expected %, given args)', p_index,
			pt.len)
	}

	return res.str()
}

@[inline]
fn v_sprintf_panic(idx int, len int) {
	if idx >= len {
		panic_n2('% conversion specifiers number mismatch (expected %, given args)', idx + 1,
			len)
	}
}

fn fabs(x f64) f64 {
	if x < 0.0 {
		return -x
	}
	return x
}

// strings.Builder version of format_fl
@[direct_array_access; manualfree]
pub fn format_fl_old(f f64, p BF_param) string {
	unsafe {
		mut s := ''
		// mut fs := "1.2343"
		mut fs := f64_to_str_lnd1(if f >= 0.0 { f } else { -f }, p.len1)
		// println("Dario")
		// println(fs)

		// error!!
		if fs[0] == `[` {
			s.free()
			return fs
		}

		if p.rm_tail_zero {
			tmp := fs
			fs = remove_tail_zeros_old(fs)
			tmp.free()
		}
		mut res := strings.new_builder(if p.len0 > fs.len { p.len0 } else { fs.len })
		defer {
			res.free()
		}

		mut sign_len_diff := 0
		if p.pad_ch == `0` {
			if p.positive {
				if p.sign_flag {
					res.write_u8(`+`)
					sign_len_diff = -1
				}
			} else {
				res.write_u8(`-`)
				sign_len_diff = -1
			}
			tmp := s
			s = fs.clone()
			tmp.free()
		} else {
			if p.positive {
				if p.sign_flag {
					tmp := s
					s = '+' + fs
					tmp.free()
				} else {
					tmp := s
					s = fs.clone()
					tmp.free()
				}
			} else {
				tmp := s
				s = '-' + fs
				tmp.free()
			}
		}

		dif := p.len0 - s.len + sign_len_diff

		if p.align == .right {
			for i1 := 0; i1 < dif; i1++ {
				res.write_u8(p.pad_ch)
			}
		}
		res.write_string(s)
		if p.align == .left {
			for i1 := 0; i1 < dif; i1++ {
				res.write_u8(p.pad_ch)
			}
		}

		s.free()
		fs.free()
		return res.str()
	}
}

@[manualfree]
fn format_es_old(f f64, p BF_param) string {
	unsafe {
		mut s := ''
		mut fs := f64_to_str_pad(if f > 0 { f } else { -f }, p.len1)
		if p.rm_tail_zero {
			tmp := fs
			fs = remove_tail_zeros_old(fs)
			tmp.free()
		}
		mut res := strings.new_builder(if p.len0 > fs.len { p.len0 } else { fs.len })
		defer {
			res.free()
			fs.free()
			s.free()
		}

		mut sign_len_diff := 0
		if p.pad_ch == `0` {
			if p.positive {
				if p.sign_flag {
					res.write_u8(`+`)
					sign_len_diff = -1
				}
			} else {
				res.write_u8(`-`)
				sign_len_diff = -1
			}
			tmp := s
			s = fs.clone()
			tmp.free()
		} else {
			if p.positive {
				if p.sign_flag {
					tmp := s
					s = '+' + fs
					tmp.free()
				} else {
					tmp := s
					s = fs.clone()
					tmp.free()
				}
			} else {
				tmp := s
				s = '-' + fs
				tmp.free()
			}
		}

		dif := p.len0 - s.len + sign_len_diff
		if p.align == .right {
			for i1 := 0; i1 < dif; i1++ {
				res.write_u8(p.pad_ch)
			}
		}
		res.write_string(s)
		if p.align == .left {
			for i1 := 0; i1 < dif; i1++ {
				res.write_u8(p.pad_ch)
			}
		}
		return res.str()
	}
}

fn remove_tail_zeros_old(s string) string {
	mut i := 0
	mut last_zero_start := -1
	mut dot_pos := -1
	mut in_decimal := false
	mut prev_ch := u8(0)
	for i < s.len {
		ch := unsafe { s.str[i] }
		if ch == `.` {
			in_decimal = true
			dot_pos = i
		} else if in_decimal {
			if ch == `0` && prev_ch != `0` {
				last_zero_start = i
			} else if ch >= `1` && ch <= `9` {
				last_zero_start = -1
			} else if ch == `e` {
				break
			}
		}
		prev_ch = ch
		i++
	}

	mut tmp := ''
	if last_zero_start > 0 {
		if last_zero_start == dot_pos + 1 {
			tmp = s[..dot_pos] + s[i..]
		} else {
			tmp = s[..last_zero_start] + s[i..]
		}
	} else {
		tmp = s.clone()
	}
	if unsafe { tmp.str[tmp.len - 1] } == `.` {
		return tmp[..tmp.len - 1]
	}
	return tmp
}

// max int64 9223372036854775807
@[manualfree]
pub fn format_dec_old(d u64, p BF_param) string {
	mut s := ''
	mut res := strings.new_builder(20)
	defer {
		unsafe { res.free() }
		unsafe { s.free() }
	}
	mut sign_len_diff := 0
	if p.pad_ch == `0` {
		if p.positive {
			if p.sign_flag {
				res.write_u8(`+`)
				sign_len_diff = -1
			}
		} else {
			res.write_u8(`-`)
			sign_len_diff = -1
		}
		tmp := s
		s = d.str()
		unsafe { tmp.free() }
	} else {
		if p.positive {
			if p.sign_flag {
				tmp := s
				s = '+' + d.str()
				unsafe { tmp.free() }
			} else {
				tmp := s
				s = d.str()
				unsafe { tmp.free() }
			}
		} else {
			tmp := s
			s = '-' + d.str()
			unsafe { tmp.free() }
		}
	}
	dif := p.len0 - s.len + sign_len_diff

	if p.align == .right {
		for i1 := 0; i1 < dif; i1++ {
			res.write_u8(p.pad_ch)
		}
	}
	res.write_string(s)
	if p.align == .left {
		for i1 := 0; i1 < dif; i1++ {
			res.write_u8(p.pad_ch)
		}
	}
	return res.str()
}
