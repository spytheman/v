// Copyright (c) 2019-2024 Alexander Medvednikov. All rights reserved.
// Use of this source code is governed by an MIT license
// that can be found in the LICENSE file.
module bits

fn C._umul128(x u64, y u64, result_hi &u64) u64
fn C._addcarry_u64(carry_in u8, a u64, b u64, out &u64) u8
fn C._udiv128(hi u64, lo u64, y u64, rem &u64) u64

// mul_64 returns the 128-bit product of x and y: (hi, lo) = x * y
// with the product bits' upper half returned in hi and the lower
// half returned in lo.
//
// This function's execution time does not depend on the inputs.
@[inline]
pub fn mul_64(x u64, y u64) (u64, u64) {
	mut hi := u64(0)
	mut lo := u64(0)
	$if amd64 {
		asm amd64 {
			mulq rdx
			; =a (lo)
			  =d (hi)
			; a (x)
			  d (y)
			; cc
		}
		return hi, lo
	}
	// cross compile
	return mul_64_default(x, y)
}

// mul_add_64 returns the 128-bit result of x * y + z: (hi, lo) = x * y + z
// with the result bits' upper half returned in hi and the lower
// half returned in lo.
@[inline]
pub fn mul_add_64(x u64, y u64, z u64) (u64, u64) {
	mut hi := u64(0)
	mut lo := u64(0)
	$if amd64 {
		asm amd64 {
			mulq rdx
			addq rax, z
			adcq rdx, 0
			; =a (lo)
			  =d (hi)
			; a (x)
			  d (y)
			  r (z)
			; cc
		}
		return hi, lo
	}
	// cross compile
	return mul_add_64_default(x, y, z)
}

// div_64 returns the quotient and remainder of (hi, lo) divided by y:
// quo = (hi, lo)/y, rem = (hi, lo)%y with the dividend bits' upper
// half in parameter hi and the lower half in parameter lo.
// div_64 panics for y == 0 (division by zero) or y <= hi (quotient overflow).
@[inline]
pub fn div_64(hi u64, lo u64, y1 u64) (u64, u64) {
	mut y := y1
	if y == 0 {
		panic(overflow_error)
	}
	if y <= hi {
		panic(overflow_error)
	}

	mut quo := u64(0)
	mut rem := u64(0)
    $if amd64 {
		asm amd64 {
			div y
			; =a (quo)
			  =d (rem)
			; d (hi)
			  a (lo)
			  r (y)
			; cc
		}
		return quo, rem
	}
	// cross compile
	return div_64_default(hi, lo, y1)
}

fn C.__builtin_clz(x u32) int
fn C.__builtin_clzll(x u64) int
fn C.__lzcnt(x u32) int
fn C.__lzcnt64(x u64) int

// --- LeadingZeros ---
// leading_zeros_8 returns the number of leading zero bits in x; the result is 8 for x == 0.
@[inline]
pub fn leading_zeros_8(x u8) int {
	if x == 0 {
		return 8
	}
    $if !tinyc {
		return C.__builtin_clz(x) - 24
	}
	return leading_zeros_8_default(x)
}

// leading_zeros_16 returns the number of leading zero bits in x; the result is 16 for x == 0.
@[inline]
pub fn leading_zeros_16(x u16) int {
	if x == 0 {
		return 16
	}
    $if !tinyc {
		return C.__builtin_clz(x) - 16
	}
	return leading_zeros_16_default(x)
}

// leading_zeros_32 returns the number of leading zero bits in x; the result is 32 for x == 0.
@[inline]
pub fn leading_zeros_32(x u32) int {
	if x == 0 {
		return 32
	}
    $if !tinyc {
		return C.__builtin_clz(x)
	}
	return leading_zeros_32_default(x)
}

// leading_zeros_64 returns the number of leading zero bits in x; the result is 64 for x == 0.
@[inline]
pub fn leading_zeros_64(x u64) int {
	if x == 0 {
		return 64
	}
    $if !tinyc {
		return C.__builtin_clzll(x)
	}
	return leading_zeros_64_default(x)
}

fn C.__builtin_ctz(x u32) int
fn C.__builtin_ctzll(x u64) int
fn C._BitScanForward(pos &int, x u32) u8
fn C._BitScanForward64(pos &int, x u64) u8

// --- TrailingZeros ---
// trailing_zeros_8 returns the number of trailing zero bits in x; the result is 8 for x == 0.
@[inline]
pub fn trailing_zeros_8(x u8) int {
	if x == 0 {
		return 8
	}
    $if !tinyc {
		return C.__builtin_ctz(x)
	}
	return trailing_zeros_8_default(x)
}

// trailing_zeros_16 returns the number of trailing zero bits in x; the result is 16 for x == 0.
@[inline]
pub fn trailing_zeros_16(x u16) int {
	if x == 0 {
		return 16
	}
    $if !tinyc {
		return C.__builtin_ctz(x)
	}
	return trailing_zeros_16_default(x)
}

// trailing_zeros_32 returns the number of trailing zero bits in x; the result is 32 for x == 0.
@[inline]
pub fn trailing_zeros_32(x u32) int {
	if x == 0 {
		return 32
	}
    $if !tinyc {
		return C.__builtin_ctz(x)
	}
	return trailing_zeros_32_default(x)
}

// trailing_zeros_64 returns the number of trailing zero bits in x; the result is 64 for x == 0.
@[inline]
pub fn trailing_zeros_64(x u64) int {
	if x == 0 {
		return 64
	}
    $if !tinyc {
		return C.__builtin_ctzll(x)
	}
	return trailing_zeros_64_default(x)
}

fn C.__builtin_popcount(x u32) int
fn C.__builtin_popcountll(x u64) int
fn C.__popcnt(x u32) int
fn C.__popcnt64(x u64) int

// --- OnesCount ---
// ones_count_8 returns the number of one bits ("population count") in x.
@[inline]
pub fn ones_count_8(x u8) int {
    $if !tinyc {
		return C.__builtin_popcount(x)
	}
	return ones_count_8_default(x)
}

// ones_count_16 returns the number of one bits ("population count") in x.
@[inline]
pub fn ones_count_16(x u16) int {
    $if !tinyc {
		return C.__builtin_popcount(x)
	}
	return ones_count_16_default(x)
}

// ones_count_32 returns the number of one bits ("population count") in x.
@[inline]
pub fn ones_count_32(x u32) int {
    $if !tinyc {
		return C.__builtin_popcount(x)
	}
	return ones_count_32_default(x)
}

// ones_count_64 returns the number of one bits ("population count") in x.
@[inline]
pub fn ones_count_64(x u64) int {
    $if !tinyc {
		return C.__builtin_popcountll(x)
	}
	return ones_count_64_default(x)
}

// See http://supertech.csail.mit.edu/papers/debruijn.pdf
const de_bruijn32 = u32(0x077CB531)
const de_bruijn32tab = [u8(0), 1, 28, 2, 29, 14, 24, 3, 30, 22, 20, 15, 25, 17, 4, 8, 31, 27, 13,
	23, 21, 19, 16, 7, 26, 12, 18, 6, 11, 5, 10, 9]!
const de_bruijn64 = u64(0x03f79d71b4ca8b09)
const de_bruijn64tab = [u8(0), 1, 56, 2, 57, 49, 28, 3, 61, 58, 42, 50, 38, 29, 17, 4, 62, 47,
	59, 36, 45, 43, 51, 22, 53, 39, 33, 30, 24, 18, 12, 5, 63, 55, 48, 27, 60, 41, 37, 16, 46,
	35, 44, 21, 52, 32, 23, 11, 54, 26, 40, 15, 34, 20, 31, 10, 25, 14, 19, 9, 13, 8, 7, 6]!

const m0 = u64(0x5555555555555555) // 01010101 ...

const m1 = u64(0x3333333333333333) // 00110011 ...

const m2 = u64(0x0f0f0f0f0f0f0f0f) // 00001111 ...

const m3 = u64(0x00ff00ff00ff00ff) // etc.

const m4 = u64(0x0000ffff0000ffff)

@[inline]
fn leading_zeros_8_default(x u8) int {
	return 8 - len_8(x)
}

@[inline]
fn leading_zeros_16_default(x u16) int {
	return 16 - len_16(x)
}

@[inline]
fn leading_zeros_32_default(x u32) int {
	return 32 - len_32(x)
}

@[inline]
fn leading_zeros_64_default(x u64) int {
	return 64 - len_64(x)
}

@[direct_array_access; inline]
fn trailing_zeros_8_default(x u8) int {
	return int(ntz_8_tab[x])
}

@[direct_array_access; ignore_overflow; inline]
fn trailing_zeros_16_default(x u16) int {
	if x == 0 {
		return 16
	}
	// see comment in trailing_zeros_64
	return int(de_bruijn32tab[u32(x & -x) * de_bruijn32 >> (32 - 5)])
}

@[direct_array_access; ignore_overflow; inline]
fn trailing_zeros_32_default(x u32) int {
	if x == 0 {
		return 32
	}
	// see comment in trailing_zeros_64
	return int(de_bruijn32tab[(x & -x) * de_bruijn32 >> (32 - 5)])
}

@[direct_array_access; ignore_overflow; inline]
fn trailing_zeros_64_default(x u64) int {
	if x == 0 {
		return 64
	}
	// If popcount is fast, replace code below with return popcount(^x & (x - 1)).
	//
	// x & -x leaves only the right-most bit set in the word. Let k be the
	// index of that bit. Since only a single bit is set, the value is two
	// to the power of k. Multiplying by a power of two is equivalent to
	// left shifting, in this case by k bits. The de Bruijn (64 bit) constant
	// is such that all six bit, consecutive substrings are distinct.
	// Therefore, if we have a left shifted version of this constant we can
	// find by how many bits it was shifted by looking at which six bit
	// substring ended up at the top of the word.
	// (Knuth, volume 4, section 7.3.1)
	return int(de_bruijn64tab[(x & -x) * de_bruijn64 >> (64 - 6)])
}

@[direct_array_access; inline]
fn ones_count_8_default(x u8) int {
	return int(pop_8_tab[x])
}

@[direct_array_access; inline]
fn ones_count_16_default(x u16) int {
	return int(pop_8_tab[x >> 8] + pop_8_tab[x & u16(0xff)])
}

@[direct_array_access; inline]
fn ones_count_32_default(x u32) int {
	return int(pop_8_tab[x >> 24] + pop_8_tab[(x >> 16) & 0xff] + pop_8_tab[(x >> 8) & 0xff] +
		pop_8_tab[x & u32(0xff)])
}

fn ones_count_64_default(x u64) int {
	// Implementation: Parallel summing of adjacent bits.
	// See "Hacker's Delight", Chap. 5: Counting Bits.
	// The following pattern shows the general approach:
	//
	// x = x>>1&(m0&m) + x&(m0&m)
	// x = x>>2&(m1&m) + x&(m1&m)
	// x = x>>4&(m2&m) + x&(m2&m)
	// x = x>>8&(m3&m) + x&(m3&m)
	// x = x>>16&(m4&m) + x&(m4&m)
	// x = x>>32&(m5&m) + x&(m5&m)
	// return int(x)
	//
	// Masking (& operations) can be left away when there's no
	// danger that a field's sum will carry over into the next
	// field: Since the result cannot be > 64, 8 bits is enough
	// and we can ignore the masks for the shifts by 8 and up.
	// Per "Hacker's Delight", the first line can be simplified
	// more, but it saves at best one instruction, so we leave
	// it alone for clarity.
	mut y := ((x >> u64(1)) & (m0 & max_u64)) + (x & (m0 & max_u64))
	y = ((y >> u64(2)) & (m1 & max_u64)) + (y & (m1 & max_u64))
	y = ((y >> 4) + y) & (m2 & max_u64)
	y += y >> 8
	y += y >> 16
	y += y >> 32
	return int(y) & ((1 << 7) - 1)
}

const n8 = u8(8)
const n16 = u16(16)
const n32 = u32(32)
const n64 = u64(64)

// --- RotateLeft ---
// rotate_left_8 returns the value of x rotated left by (k mod 8) bits.
// To rotate x right by k bits, call rotate_left_8(x, -k).
//
// This function's execution time does not depend on the inputs.
@[inline]
pub fn rotate_left_8(x u8, k int) u8 {
	s := u8(k) & (n8 - u8(1))
	return (x << s) | (x >> (n8 - s))
}

// rotate_left_16 returns the value of x rotated left by (k mod 16) bits.
// To rotate x right by k bits, call rotate_left_16(x, -k).
//
// This function's execution time does not depend on the inputs.
@[inline]
pub fn rotate_left_16(x u16, k int) u16 {
	s := u16(k) & (n16 - u16(1))
	return (x << s) | (x >> (n16 - s))
}

// rotate_left_32 returns the value of x rotated left by (k mod 32) bits.
// To rotate x right by k bits, call rotate_left_32(x, -k).
//
// This function's execution time does not depend on the inputs.
@[inline]
pub fn rotate_left_32(x u32, k int) u32 {
	s := u32(k) & (n32 - u32(1))
	return (x << s) | (x >> (n32 - s))
}

// rotate_left_64 returns the value of x rotated left by (k mod 64) bits.
// To rotate x right by k bits, call rotate_left_64(x, -k).
//
// This function's execution time does not depend on the inputs.
@[inline]
pub fn rotate_left_64(x u64, k int) u64 {
	s := u64(k) & (n64 - u64(1))
	return (x << s) | (x >> (n64 - s))
}

// --- Reverse ---
// reverse_8 returns the value of x with its bits in reversed order.
@[direct_array_access; inline]
pub fn reverse_8(x u8) u8 {
	return rev_8_tab[x]
}

// reverse_16 returns the value of x with its bits in reversed order.
@[direct_array_access; inline]
pub fn reverse_16(x u16) u16 {
	return u16(rev_8_tab[x >> 8]) | (u16(rev_8_tab[x & u16(0xff)]) << 8)
}

// reverse_32 returns the value of x with its bits in reversed order.
@[inline]
pub fn reverse_32(x u32) u32 {
	mut y := (((x >> u32(1)) & (m0 & max_u32)) | ((x & (m0 & max_u32)) << 1))
	y = (((y >> u32(2)) & (m1 & max_u32)) | ((y & (m1 & max_u32)) << u32(2)))
	y = (((y >> u32(4)) & (m2 & max_u32)) | ((y & (m2 & max_u32)) << u32(4)))
	return reverse_bytes_32(u32(y))
}

// reverse_64 returns the value of x with its bits in reversed order.
@[inline]
pub fn reverse_64(x u64) u64 {
	mut y := (((x >> u64(1)) & (m0 & max_u64)) | ((x & (m0 & max_u64)) << 1))
	y = (((y >> u64(2)) & (m1 & max_u64)) | ((y & (m1 & max_u64)) << 2))
	y = (((y >> u64(4)) & (m2 & max_u64)) | ((y & (m2 & max_u64)) << 4))
	return reverse_bytes_64(y)
}

// --- ReverseBytes ---
// reverse_bytes_16 returns the value of x with its bytes in reversed order.
//
// This function's execution time does not depend on the inputs.
@[inline]
pub fn reverse_bytes_16(x u16) u16 {
	return (x >> 8) | (x << 8)
}

// reverse_bytes_32 returns the value of x with its bytes in reversed order.
//
// This function's execution time does not depend on the inputs.
@[inline]
pub fn reverse_bytes_32(x u32) u32 {
	y := (((x >> u32(8)) & (m3 & max_u32)) | ((x & (m3 & max_u32)) << u32(8)))
	return u32((y >> 16) | (y << 16))
}

// reverse_bytes_64 returns the value of x with its bytes in reversed order.
//
// This function's execution time does not depend on the inputs.
@[inline]
pub fn reverse_bytes_64(x u64) u64 {
	mut y := (((x >> u64(8)) & (m3 & max_u64)) | ((x & (m3 & max_u64)) << u64(8)))
	y = (((y >> u64(16)) & (m4 & max_u64)) | ((y & (m4 & max_u64)) << u64(16)))
	return (y >> 32) | (y << 32)
}

// --- Len ---
// len_8 returns the minimum number of bits required to represent x; the result is 0 for x == 0.
@[direct_array_access]
pub fn len_8(x u8) int {
	return int(len_8_tab[x])
}

// len_16 returns the minimum number of bits required to represent x; the result is 0 for x == 0.
@[direct_array_access; ignore_overflow]
pub fn len_16(x u16) int {
	mut y := x
	mut n := 0
	if y >= 1 << 8 {
		y >>= 8
		n = 8
	}
	return n + int(len_8_tab[y])
}

// len_32 returns the minimum number of bits required to represent x; the result is 0 for x == 0.
@[direct_array_access; ignore_overflow]
pub fn len_32(x u32) int {
	mut y := x
	mut n := 0
	if y >= (1 << 16) {
		y >>= 16
		n = 16
	}
	if y >= (1 << 8) {
		y >>= 8
		n += 8
	}
	return n + int(len_8_tab[y])
}

// len_64 returns the minimum number of bits required to represent x; the result is 0 for x == 0.
@[direct_array_access]
pub fn len_64(x u64) int {
	mut y := x
	mut n := 0
	if y >= u64(1) << u64(32) {
		y >>= 32
		n = 32
	}
	if y >= u64(1) << u64(16) {
		y >>= 16
		n += 16
	}
	if y >= u64(1) << u64(8) {
		y >>= 8
		n += 8
	}
	return n + int(len_8_tab[y])
}

// --- Add with carry ---
// Add returns the sum with carry of x, y and carry: sum = x + y + carry.
// The carry input must be 0 or 1; otherwise the behavior is undefined.
// The carryOut output is guaranteed to be 0 or 1.
// add_32 returns the sum with carry of x, y and carry: sum = x + y + carry.
// The carry input must be 0 or 1; otherwise the behavior is undefined.
// The carryOut output is guaranteed to be 0 or 1.
// This function's execution time does not depend on the inputs.
@[ignore_overflow]
pub fn add_32(x u32, y u32, carry u32) (u32, u32) {
	sum64 := u64(x) + u64(y) + u64(carry)
	sum := u32(sum64)
	carry_out := u32(sum64 >> 32)
	return sum, carry_out
}

// add_64 returns the sum with carry of x, y and carry: sum = x + y + carry.
// The carry input must be 0 or 1; otherwise the behavior is undefined.
// The carryOut output is guaranteed to be 0 or 1.
// This function's execution time does not depend on the inputs.
@[ignore_overflow]
pub fn add_64(x u64, y u64, carry u64) (u64, u64) {
	sum := x + y + carry
	// The sum will overflow if both top bits are set (x & y) or if one of them
	// is (x | y), and a carry from the lower place happened. If such a carry
	// happens, the top bit will be 1 + 0 + 1 = 0 (&^ sum).
	carry_out := ((x & y) | ((x | y) & ~sum)) >> 63
	return sum, carry_out
}

// --- Subtract with borrow ---
// Sub returns the difference of x, y and borrow: diff = x - y - borrow.
// The borrow input must be 0 or 1; otherwise the behavior is undefined.
// The borrowOut output is guaranteed to be 0 or 1.
// sub_32 returns the difference of x, y and borrow, diff = x - y - borrow.
// The borrow input must be 0 or 1; otherwise the behavior is undefined.
// The borrowOut output is guaranteed to be 0 or 1.
// This function's execution time does not depend on the inputs.
@[ignore_overflow]
pub fn sub_32(x u32, y u32, borrow u32) (u32, u32) {
	diff := x - y - borrow
	// The difference will underflow if the top bit of x is not set and the top
	// bit of y is set (^x & y) or if they are the same (^(x ^ y)) and a borrow
	// from the lower place happens. If that borrow happens, the result will be
	// 1 - 1 - 1 = 0 - 0 - 1 = 1 (& diff).
	borrow_out := ((~x & y) | (~(x ^ y) & diff)) >> 31
	return diff, borrow_out
}

// sub_64 returns the difference of x, y and borrow: diff = x - y - borrow.
// The borrow input must be 0 or 1; otherwise the behavior is undefined.
// The borrowOut output is guaranteed to be 0 or 1.
// This function's execution time does not depend on the inputs.
@[ignore_overflow]
pub fn sub_64(x u64, y u64, borrow u64) (u64, u64) {
	diff := x - y - borrow
	// See Sub32 for the bit logic.
	borrow_out := ((~x & y) | (~(x ^ y) & diff)) >> 63
	return diff, borrow_out
}

// --- Full-width multiply ---

@[markused]
pub const two32 = u64(0x100000000)
const mask32 = two32 - 1
const overflow_error = 'Overflow Error'
const divide_error = 'Divide Error'

// mul_32 returns the 64-bit product of x and y: (hi, lo) = x * y
// with the product bits' upper half returned in hi and the lower
// half returned in lo.
//
// This function's execution time does not depend on the inputs.
@[inline]
pub fn mul_32(x u32, y u32) (u32, u32) {
	return mul_32_default(x, y)
}

@[inline]
fn mul_32_default(x u32, y u32) (u32, u32) {
	tmp := u64(x) * u64(y)
	hi := u32(tmp >> 32)
	lo := u32(tmp)
	return hi, lo
}

fn mul_64_default(x u64, y u64) (u64, u64) {
	x0 := x & mask32
	x1 := x >> 32
	y0 := y & mask32
	y1 := y >> 32
	w0 := x0 * y0
	t := x1 * y0 + (w0 >> 32)
	mut w1 := t & mask32
	w2 := t >> 32
	w1 += x0 * y1
	hi := x1 * y1 + w2 + (w1 >> 32)
	lo := x * y
	return hi, lo
}

// mul_add_32 returns the 64-bit result of x * y + z: (hi, lo) = x * y + z
// with the result bits' upper half returned in hi and the lower
// half returned in lo.
@[inline]
pub fn mul_add_32(x u32, y u32, z u32) (u32, u32) {
	return mul_add_32_default(x, y, z)
}

@[inline]
fn mul_add_32_default(x u32, y u32, z u32) (u32, u32) {
	tmp := u64(x) * u64(y) + u64(z)
	hi := u32(tmp >> 32)
	lo := u32(tmp)
	return hi, lo
}

@[inline]
fn mul_add_64_default(x u64, y u64, z u64) (u64, u64) {
	h, l := mul_64(x, y)
	lo := l + z
	hi := h + u64(lo < l)
	return hi, lo
}

// --- Full-width divide ---
// div_32 returns the quotient and remainder of (hi, lo) divided by y:
// quo = (hi, lo)/y, rem = (hi, lo)%y with the dividend bits' upper
// half in parameter hi and the lower half in parameter lo.
// div_32 panics for y == 0 (division by zero) or y <= hi (quotient overflow).
@[inline]
pub fn div_32(hi u32, lo u32, y u32) (u32, u32) {
	return div_32_default(hi, lo, y)
}

fn div_32_default(hi u32, lo u32, y u32) (u32, u32) {
	if y != 0 && y <= hi {
		panic(overflow_error)
	}
	z := (u64(hi) << 32) | u64(lo)
	quo := u32(z / u64(y))
	rem := u32(z % u64(y))
	return quo, rem
}

fn div_64_default(hi u64, lo u64, y1 u64) (u64, u64) {
	mut y := y1
	if y == 0 {
		panic(overflow_error)
	}
	if y <= hi {
		panic(overflow_error)
	}
	s := u32(leading_zeros_64(y))
	y <<= s
	yn1 := y >> 32
	yn0 := y & mask32
	ss1 := (hi << s)
	xxx := 64 - s
	mut ss2 := lo >> xxx
	if xxx == 64 {
		// in Go, shifting right a u64 number, 64 times produces 0 *always*.
		// See https://go.dev/ref/spec
		// > The shift operators implement arithmetic shifts if the left operand
		// > is a signed integer and logical shifts if it is an unsigned integer.
		// > There is no upper limit on the shift count.
		// > Shifts behave as if the left operand is shifted n times by 1 for a shift count of n.
		// > As a result, x << 1 is the same as x*2 and x >> 1 is the same as x/2
		// > but truncated towards negative infinity.
		//
		// In V, that is currently left to whatever C is doing, which is apparently a NOP.
		// This function was a direct port of https://cs.opensource.google/go/go/+/refs/tags/go1.17.6:src/math/bits/bits.go;l=512,
		// so we have to use the Go behaviour.
		// TODO: reconsider whether we need to adopt it for our shift ops, or just use function wrappers that do it.
		ss2 = 0
	}
	un32 := ss1 | ss2
	un10 := lo << s
	un1 := un10 >> 32
	un0 := un10 & mask32
	mut q1 := un32 / yn1
	mut rhat := un32 - (q1 * yn1)
	for q1 >= two32 || (q1 * yn0) > ((two32 * rhat) + un1) {
		q1--
		rhat += yn1
		if rhat >= two32 {
			break
		}
	}
	un21 := (un32 * two32) + (un1 - (q1 * y))
	mut q0 := un21 / yn1
	rhat = un21 - q0 * yn1
	for q0 >= two32 || (q0 * yn0) > ((two32 * rhat) + un0) {
		q0--
		rhat += yn1
		if rhat >= two32 {
			break
		}
	}
	qq := ((q1 * two32) + q0)
	rr := ((un21 * two32) + un0 - (q0 * y)) >> s
	return qq, rr
}

// rem_32 returns the remainder of (hi, lo) divided by y. Rem32 panics
// for y == 0 (division by zero) but, unlike Div32, it doesn't panic
// on a quotient overflow.
pub fn rem_32(hi u32, lo u32, y u32) u32 {
	return u32(((u64(hi) << 32) | u64(lo)) % u64(y))
}

// rem_64 returns the remainder of (hi, lo) divided by y. Rem64 panics
// for y == 0 (division by zero) but, unlike div_64, it doesn't panic
// on a quotient overflow.
pub fn rem_64(hi u64, lo u64, y u64) u64 {
	// We scale down hi so that hi < y, then use div_64 to compute the
	// rem with the guarantee that it won't panic on quotient overflow.
	// Given that
	// hi ≡ hi%y    (mod y)
	// we have
	// hi<<64 + lo ≡ (hi%y)<<64 + lo    (mod y)
	_, rem := div_64(hi % y, lo, y)
	return rem
}

// normalize returns a normal number y and exponent exp
// satisfying x == y × 2**exp. It assumes x is finite and non-zero.
pub fn normalize(x f64) (f64, int) {
	smallest_normal := 2.2250738585072014e-308 // 2**-1022
	if (if x > 0.0 {
		x
	} else {
		-x
	}) < smallest_normal {
		return x * (u64(1) << u64(52)), -52
	}
	return x, 0
}

const ntz_8_tab = [u8(0x08), 0x00, 0x01, 0x00, 0x02, 0x00, 0x01, 0x00, 0x03, 0x00, 0x01, 0x00,
	0x02, 0x00, 0x01, 0x00, 0x04, 0x00, 0x01, 0x00, 0x02, 0x00, 0x01, 0x00, 0x03, 0x00, 0x01, 0x00,
	0x02, 0x00, 0x01, 0x00, 0x05, 0x00, 0x01, 0x00, 0x02, 0x00, 0x01, 0x00, 0x03, 0x00, 0x01, 0x00,
	0x02, 0x00, 0x01, 0x00, 0x04, 0x00, 0x01, 0x00, 0x02, 0x00, 0x01, 0x00, 0x03, 0x00, 0x01, 0x00,
	0x02, 0x00, 0x01, 0x00, 0x06, 0x00, 0x01, 0x00, 0x02, 0x00, 0x01, 0x00, 0x03, 0x00, 0x01, 0x00,
	0x02, 0x00, 0x01, 0x00, 0x04, 0x00, 0x01, 0x00, 0x02, 0x00, 0x01, 0x00, 0x03, 0x00, 0x01, 0x00,
	0x02, 0x00, 0x01, 0x00, 0x05, 0x00, 0x01, 0x00, 0x02, 0x00, 0x01, 0x00, 0x03, 0x00, 0x01, 0x00,
	0x02, 0x00, 0x01, 0x00, 0x04, 0x00, 0x01, 0x00, 0x02, 0x00, 0x01, 0x00, 0x03, 0x00, 0x01, 0x00,
	0x02, 0x00, 0x01, 0x00, 0x07, 0x00, 0x01, 0x00, 0x02, 0x00, 0x01, 0x00, 0x03, 0x00, 0x01, 0x00,
	0x02, 0x00, 0x01, 0x00, 0x04, 0x00, 0x01, 0x00, 0x02, 0x00, 0x01, 0x00, 0x03, 0x00, 0x01, 0x00,
	0x02, 0x00, 0x01, 0x00, 0x05, 0x00, 0x01, 0x00, 0x02, 0x00, 0x01, 0x00, 0x03, 0x00, 0x01, 0x00,
	0x02, 0x00, 0x01, 0x00, 0x04, 0x00, 0x01, 0x00, 0x02, 0x00, 0x01, 0x00, 0x03, 0x00, 0x01, 0x00,
	0x02, 0x00, 0x01, 0x00, 0x06, 0x00, 0x01, 0x00, 0x02, 0x00, 0x01, 0x00, 0x03, 0x00, 0x01, 0x00,
	0x02, 0x00, 0x01, 0x00, 0x04, 0x00, 0x01, 0x00, 0x02, 0x00, 0x01, 0x00, 0x03, 0x00, 0x01, 0x00,
	0x02, 0x00, 0x01, 0x00, 0x05, 0x00, 0x01, 0x00, 0x02, 0x00, 0x01, 0x00, 0x03, 0x00, 0x01, 0x00,
	0x02, 0x00, 0x01, 0x00, 0x04, 0x00, 0x01, 0x00, 0x02, 0x00, 0x01, 0x00, 0x03, 0x00, 0x01, 0x00,
	0x02, 0x00, 0x01, 0x00]!
const pop_8_tab = [u8(0x00), 0x01, 0x01, 0x02, 0x01, 0x02, 0x02, 0x03, 0x01, 0x02, 0x02, 0x03,
	0x02, 0x03, 0x03, 0x04, 0x01, 0x02, 0x02, 0x03, 0x02, 0x03, 0x03, 0x04, 0x02, 0x03, 0x03, 0x04,
	0x03, 0x04, 0x04, 0x05, 0x01, 0x02, 0x02, 0x03, 0x02, 0x03, 0x03, 0x04, 0x02, 0x03, 0x03, 0x04,
	0x03, 0x04, 0x04, 0x05, 0x02, 0x03, 0x03, 0x04, 0x03, 0x04, 0x04, 0x05, 0x03, 0x04, 0x04, 0x05,
	0x04, 0x05, 0x05, 0x06, 0x01, 0x02, 0x02, 0x03, 0x02, 0x03, 0x03, 0x04, 0x02, 0x03, 0x03, 0x04,
	0x03, 0x04, 0x04, 0x05, 0x02, 0x03, 0x03, 0x04, 0x03, 0x04, 0x04, 0x05, 0x03, 0x04, 0x04, 0x05,
	0x04, 0x05, 0x05, 0x06, 0x02, 0x03, 0x03, 0x04, 0x03, 0x04, 0x04, 0x05, 0x03, 0x04, 0x04, 0x05,
	0x04, 0x05, 0x05, 0x06, 0x03, 0x04, 0x04, 0x05, 0x04, 0x05, 0x05, 0x06, 0x04, 0x05, 0x05, 0x06,
	0x05, 0x06, 0x06, 0x07, 0x01, 0x02, 0x02, 0x03, 0x02, 0x03, 0x03, 0x04, 0x02, 0x03, 0x03, 0x04,
	0x03, 0x04, 0x04, 0x05, 0x02, 0x03, 0x03, 0x04, 0x03, 0x04, 0x04, 0x05, 0x03, 0x04, 0x04, 0x05,
	0x04, 0x05, 0x05, 0x06, 0x02, 0x03, 0x03, 0x04, 0x03, 0x04, 0x04, 0x05, 0x03, 0x04, 0x04, 0x05,
	0x04, 0x05, 0x05, 0x06, 0x03, 0x04, 0x04, 0x05, 0x04, 0x05, 0x05, 0x06, 0x04, 0x05, 0x05, 0x06,
	0x05, 0x06, 0x06, 0x07, 0x02, 0x03, 0x03, 0x04, 0x03, 0x04, 0x04, 0x05, 0x03, 0x04, 0x04, 0x05,
	0x04, 0x05, 0x05, 0x06, 0x03, 0x04, 0x04, 0x05, 0x04, 0x05, 0x05, 0x06, 0x04, 0x05, 0x05, 0x06,
	0x05, 0x06, 0x06, 0x07, 0x03, 0x04, 0x04, 0x05, 0x04, 0x05, 0x05, 0x06, 0x04, 0x05, 0x05, 0x06,
	0x05, 0x06, 0x06, 0x07, 0x04, 0x05, 0x05, 0x06, 0x05, 0x06, 0x06, 0x07, 0x05, 0x06, 0x06, 0x07,
	0x06, 0x07, 0x07, 0x08]!
const rev_8_tab = [u8(0x00), 0x80, 0x40, 0xc0, 0x20, 0xa0, 0x60, 0xe0, 0x10, 0x90, 0x50, 0xd0,
	0x30, 0xb0, 0x70, 0xf0, 0x08, 0x88, 0x48, 0xc8, 0x28, 0xa8, 0x68, 0xe8, 0x18, 0x98, 0x58, 0xd8,
	0x38, 0xb8, 0x78, 0xf8, 0x04, 0x84, 0x44, 0xc4, 0x24, 0xa4, 0x64, 0xe4, 0x14, 0x94, 0x54, 0xd4,
	0x34, 0xb4, 0x74, 0xf4, 0x0c, 0x8c, 0x4c, 0xcc, 0x2c, 0xac, 0x6c, 0xec, 0x1c, 0x9c, 0x5c, 0xdc,
	0x3c, 0xbc, 0x7c, 0xfc, 0x02, 0x82, 0x42, 0xc2, 0x22, 0xa2, 0x62, 0xe2, 0x12, 0x92, 0x52, 0xd2,
	0x32, 0xb2, 0x72, 0xf2, 0x0a, 0x8a, 0x4a, 0xca, 0x2a, 0xaa, 0x6a, 0xea, 0x1a, 0x9a, 0x5a, 0xda,
	0x3a, 0xba, 0x7a, 0xfa, 0x06, 0x86, 0x46, 0xc6, 0x26, 0xa6, 0x66, 0xe6, 0x16, 0x96, 0x56, 0xd6,
	0x36, 0xb6, 0x76, 0xf6, 0x0e, 0x8e, 0x4e, 0xce, 0x2e, 0xae, 0x6e, 0xee, 0x1e, 0x9e, 0x5e, 0xde,
	0x3e, 0xbe, 0x7e, 0xfe, 0x01, 0x81, 0x41, 0xc1, 0x21, 0xa1, 0x61, 0xe1, 0x11, 0x91, 0x51, 0xd1,
	0x31, 0xb1, 0x71, 0xf1, 0x09, 0x89, 0x49, 0xc9, 0x29, 0xa9, 0x69, 0xe9, 0x19, 0x99, 0x59, 0xd9,
	0x39, 0xb9, 0x79, 0xf9, 0x05, 0x85, 0x45, 0xc5, 0x25, 0xa5, 0x65, 0xe5, 0x15, 0x95, 0x55, 0xd5,
	0x35, 0xb5, 0x75, 0xf5, 0x0d, 0x8d, 0x4d, 0xcd, 0x2d, 0xad, 0x6d, 0xed, 0x1d, 0x9d, 0x5d, 0xdd,
	0x3d, 0xbd, 0x7d, 0xfd, 0x03, 0x83, 0x43, 0xc3, 0x23, 0xa3, 0x63, 0xe3, 0x13, 0x93, 0x53, 0xd3,
	0x33, 0xb3, 0x73, 0xf3, 0x0b, 0x8b, 0x4b, 0xcb, 0x2b, 0xab, 0x6b, 0xeb, 0x1b, 0x9b, 0x5b, 0xdb,
	0x3b, 0xbb, 0x7b, 0xfb, 0x07, 0x87, 0x47, 0xc7, 0x27, 0xa7, 0x67, 0xe7, 0x17, 0x97, 0x57, 0xd7,
	0x37, 0xb7, 0x77, 0xf7, 0x0f, 0x8f, 0x4f, 0xcf, 0x2f, 0xaf, 0x6f, 0xef, 0x1f, 0x9f, 0x5f, 0xdf,
	0x3f, 0xbf, 0x7f, 0xff]!
const len_8_tab = [u8(0x00), 0x01, 0x02, 0x02, 0x03, 0x03, 0x03, 0x03, 0x04, 0x04, 0x04, 0x04,
	0x04, 0x04, 0x04, 0x04, 0x05, 0x05, 0x05, 0x05, 0x05, 0x05, 0x05, 0x05, 0x05, 0x05, 0x05, 0x05,
	0x05, 0x05, 0x05, 0x05, 0x06, 0x06, 0x06, 0x06, 0x06, 0x06, 0x06, 0x06, 0x06, 0x06, 0x06, 0x06,
	0x06, 0x06, 0x06, 0x06, 0x06, 0x06, 0x06, 0x06, 0x06, 0x06, 0x06, 0x06, 0x06, 0x06, 0x06, 0x06,
	0x06, 0x06, 0x06, 0x06, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07,
	0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07,
	0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07,
	0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07,
	0x07, 0x07, 0x07, 0x07, 0x08, 0x08, 0x08, 0x08, 0x08, 0x08, 0x08, 0x08, 0x08, 0x08, 0x08, 0x08,
	0x08, 0x08, 0x08, 0x08, 0x08, 0x08, 0x08, 0x08, 0x08, 0x08, 0x08, 0x08, 0x08, 0x08, 0x08, 0x08,
	0x08, 0x08, 0x08, 0x08, 0x08, 0x08, 0x08, 0x08, 0x08, 0x08, 0x08, 0x08, 0x08, 0x08, 0x08, 0x08,
	0x08, 0x08, 0x08, 0x08, 0x08, 0x08, 0x08, 0x08, 0x08, 0x08, 0x08, 0x08, 0x08, 0x08, 0x08, 0x08,
	0x08, 0x08, 0x08, 0x08, 0x08, 0x08, 0x08, 0x08, 0x08, 0x08, 0x08, 0x08, 0x08, 0x08, 0x08, 0x08,
	0x08, 0x08, 0x08, 0x08, 0x08, 0x08, 0x08, 0x08, 0x08, 0x08, 0x08, 0x08, 0x08, 0x08, 0x08, 0x08,
	0x08, 0x08, 0x08, 0x08, 0x08, 0x08, 0x08, 0x08, 0x08, 0x08, 0x08, 0x08, 0x08, 0x08, 0x08, 0x08,
	0x08, 0x08, 0x08, 0x08, 0x08, 0x08, 0x08, 0x08, 0x08, 0x08, 0x08, 0x08, 0x08, 0x08, 0x08, 0x08,
	0x08, 0x08, 0x08, 0x08]!

// f32_bits returns the IEEE 754 binary representation of f,
// with the sign bit of f and the result in the same bit position.
// f32_bits(f32_from_bits(x)) == x.
@[inline]
pub fn f32_bits(f f32) u32 {
	p := *unsafe { &u32(&f) }
	return p
}

// f32_from_bits returns the floating-point number corresponding
// to the IEEE 754 binary representation b, with the sign bit of b
// and the result in the same bit position.
// f32_from_bits(f32_bits(x)) == x.
@[inline]
pub fn f32_from_bits(b u32) f32 {
	p := *unsafe { &f32(&b) }
	return p
}

// f64_bits returns the IEEE 754 binary representation of f,
// with the sign bit of f and the result in the same bit position,
// and f64_bits(f64_from_bits(x)) == x.
@[inline]
pub fn f64_bits(f f64) u64 {
	p := *unsafe { &u64(&f) }
	return p
}

// f64_from_bits returns the floating-point number corresponding
// to the IEEE 754 binary representation b, with the sign bit of b
// and the result in the same bit position.
// f64_from_bits(f64_bits(x)) == x.
@[inline]
pub fn f64_from_bits(b u64) f64 {
	p := *unsafe { &f64(&b) }
	return p
}
