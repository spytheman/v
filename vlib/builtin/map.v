// Copyright (c) 2019-2024 Alexander Medvednikov. All rights reserved.
// Use of this source code is governed by an MIT license
// that can be found in the LICENSE file.
@[has_globals]
module builtin

import strings
import strconv

$if !native {
	#include <float.h>
}

// array is a struct, used for denoting all array types in V.
// `.data` is a void pointer to the backing heap memory block,
// which avoids using generics and thus without generating extra
// code for every type.
pub struct array {
pub mut:
	data   voidptr
	offset int // in bytes (should be `usize`), to avoid copying data while making slices, unless it starts changing
	len    int // length of the array in elements.
	cap    int // capacity of the array in elements.
	flags  ArrayFlags
pub:
	element_size int // size in bytes of one element in the array.
}

@[flag]
pub enum ArrayFlags {
	noslices // when <<, `.noslices` will free the old data block immediately (you have to be sure, that there are *no slices* to that specific array). TODO: integrate with reference counting/compiler support for the static cases.
	noshrink // when `.noslices` and `.noshrink` are *both set*, .delete(x) will NOT allocate new memory and free the old. It will just move the elements in place, and adjust .len.
	nogrow   // the array will never be allowed to grow past `.cap`. set `.nogrow` and `.noshrink` for a truly fixed heap array
	nofree   // `.data` will never be freed
}

// Internal function, used by V (`nums := []int`)
fn __new_array(mylen int, cap int, elm_size int) array {
	panic_on_negative_len(mylen)
	panic_on_negative_cap(cap)
	cap_ := if cap < mylen { mylen } else { cap }
	arr := array{
		element_size: elm_size
		data:         vcalloc(u64(cap_) * u64(elm_size))
		len:          mylen
		cap:          cap_
	}
	return arr
}

fn __new_array_with_default(mylen int, cap int, elm_size int, val voidptr) array {
	panic_on_negative_len(mylen)
	panic_on_negative_cap(cap)
	cap_ := if cap < mylen { mylen } else { cap }
	mut arr := array{
		element_size: elm_size
		len:          mylen
		cap:          cap_
	}
	// x := []EmptyStruct{cap:5} ; for clang/gcc with -gc none,
	//    -> sizeof(EmptyStruct) == 0 -> elm_size == 0
	//    -> total_size == 0 -> malloc(0) -> panic;
	//    to avoid it, just allocate a single byte
	total_size := u64(cap_) * u64(elm_size)
	if cap_ > 0 && mylen == 0 {
		arr.data = unsafe { malloc(__at_least_one(total_size)) }
	} else {
		arr.data = vcalloc(total_size)
	}
	if val != 0 {
		mut eptr := &u8(arr.data)
		unsafe {
			if eptr != nil {
				if arr.element_size == 1 {
					byte_value := *(&u8(val))
					for i in 0 .. arr.len {
						eptr[i] = byte_value
					}
				} else {
					for _ in 0 .. arr.len {
						vmemcpy(eptr, val, arr.element_size)
						eptr += arr.element_size
					}
				}
			}
		}
	}
	return arr
}

fn __new_array_with_multi_default(mylen int, cap int, elm_size int, val voidptr) array {
	panic_on_negative_len(mylen)
	panic_on_negative_cap(cap)
	cap_ := if cap < mylen { mylen } else { cap }
	mut arr := array{
		element_size: elm_size
		len:          mylen
		cap:          cap_
	}
	// x := []EmptyStruct{cap:5} ; for clang/gcc with -gc none,
	//    -> sizeof(EmptyStruct) == 0 -> elm_size == 0
	//    -> total_size == 0 -> malloc(0) -> panic;
	//    to avoid it, just allocate a single byte
	total_size := u64(cap_) * u64(elm_size)
	arr.data = vcalloc(__at_least_one(total_size))
	if val != 0 {
		mut eptr := &u8(arr.data)
		unsafe {
			if eptr != nil {
				for i in 0 .. arr.len {
					vmemcpy(eptr, charptr(val) + i * arr.element_size, arr.element_size)
					eptr += arr.element_size
				}
			}
		}
	}
	return arr
}

fn __new_array_with_array_default(mylen int, cap int, elm_size int, val array, depth int) array {
	panic_on_negative_len(mylen)
	panic_on_negative_cap(cap)
	cap_ := if cap < mylen { mylen } else { cap }
	mut arr := array{
		element_size: elm_size
		data:         unsafe { malloc(__at_least_one(u64(cap_) * u64(elm_size))) }
		len:          mylen
		cap:          cap_
	}
	mut eptr := &u8(arr.data)
	unsafe {
		if eptr != nil {
			for _ in 0 .. arr.len {
				val_clone := val.clone_to_depth(depth)
				vmemcpy(eptr, &val_clone, arr.element_size)
				eptr += arr.element_size
			}
		}
	}
	return arr
}

fn __new_array_with_map_default(mylen int, cap int, elm_size int, val map) array {
	panic_on_negative_len(mylen)
	panic_on_negative_cap(cap)
	cap_ := if cap < mylen { mylen } else { cap }
	mut arr := array{
		element_size: elm_size
		data:         unsafe { malloc(__at_least_one(u64(cap_) * u64(elm_size))) }
		len:          mylen
		cap:          cap_
	}
	mut eptr := &u8(arr.data)
	unsafe {
		if eptr != nil {
			for _ in 0 .. arr.len {
				val_clone := val.clone()
				vmemcpy(eptr, &val_clone, arr.element_size)
				eptr += arr.element_size
			}
		}
	}
	return arr
}

// Private function, used by V (`nums := [1, 2, 3]`)
fn new_array_from_c_array(len int, cap int, elm_size int, c_array voidptr) array {
	panic_on_negative_len(len)
	panic_on_negative_cap(cap)
	cap_ := if cap < len { len } else { cap }
	arr := array{
		element_size: elm_size
		data:         vcalloc(u64(cap_) * u64(elm_size))
		len:          len
		cap:          cap_
	}
	// TODO: Write all memory functions (like memcpy) in V
	unsafe { vmemcpy(arr.data, c_array, u64(len) * u64(elm_size)) }
	return arr
}

// Private function, used by V (`nums := [1, 2, 3] !`)
fn new_array_from_c_array_no_alloc(len int, cap int, elm_size int, c_array voidptr) array {
	panic_on_negative_len(len)
	panic_on_negative_cap(cap)
	arr := array{
		element_size: elm_size
		data:         c_array
		len:          len
		cap:          cap
	}
	return arr
}

// ensure_cap increases the `cap` of an array to the required value, if needed.
// It does so by copying the data to a new memory location (creating a clone),
// unless `a.cap` is already large enough.
pub fn (mut a array) ensure_cap(required int) {
	if required <= a.cap {
		return
	}
	if a.flags.has(.nogrow) {
		panic_n('array.ensure_cap: array with the flag `.nogrow` cannot grow in size, array required new size:',
			required)
	}
	mut cap := if a.cap > 0 { i64(a.cap) } else { i64(2) }
	for required > cap {
		cap *= 2
	}
	if cap > max_int {
		if a.cap < max_int {
			// limit the capacity, since bigger values, will overflow the 32bit integer used to store it
			cap = max_int
		} else {
			panic_n('array.ensure_cap: array needs to grow to cap (which is > 2^31):',
				cap)
		}
	}
	new_size := u64(cap) * u64(a.element_size)
	new_data := unsafe { malloc(__at_least_one(new_size)) }
	if a.data != unsafe { nil } {
		unsafe { vmemcpy(new_data, a.data, u64(a.len) * u64(a.element_size)) }
		// TODO: the old data may be leaked when no GC is used (ref-counting?)
		if a.flags.has(.noslices) {
			unsafe {
				free(a.data)
			}
		}
	}
	a.data = new_data
	a.offset = 0
	a.cap = int(cap)
}

// repeat returns a new array with the given array elements repeated given times.
// `cgen` will replace this with an appropriate call to `repeat_to_depth()`
//
// This is a dummy placeholder that will be overridden by `cgen` with an appropriate
// call to `repeat_to_depth()`. However the `checker` needs it here.
pub fn (a array) repeat(count int) array {
	return unsafe { a.repeat_to_depth(count, 0) }
}

// repeat_to_depth is an unsafe version of `repeat()` that handles
// multi-dimensional arrays.
//
// It is `unsafe` to call directly because `depth` is not checked
@[direct_array_access; unsafe]
pub fn (a array) repeat_to_depth(count int, depth int) array {
	if count < 0 {
		panic_n('array.repeat: count is negative:', count)
	}
	mut size := u64(count) * u64(a.len) * u64(a.element_size)
	if size == 0 {
		size = u64(a.element_size)
	}
	arr := array{
		element_size: a.element_size
		data:         vcalloc(size)
		len:          count * a.len
		cap:          count * a.len
	}
	if a.len > 0 {
		a_total_size := u64(a.len) * u64(a.element_size)
		arr_step_size := u64(a.len) * u64(arr.element_size)
		mut eptr := &u8(arr.data)
		unsafe {
			if eptr != nil {
				for _ in 0 .. count {
					if depth > 0 {
						ary_clone := a.clone_to_depth(depth)
						vmemcpy(eptr, &u8(ary_clone.data), a_total_size)
					} else {
						vmemcpy(eptr, &u8(a.data), a_total_size)
					}
					eptr += arr_step_size
				}
			}
		}
	}
	return arr
}

// insert inserts a value in the array at index `i` and increases
// the index of subsequent elements by 1.
//
// This function is type-aware and can insert items of the same
// or lower dimensionality as the original array. That is, if
// the original array is `[]int`, then the insert `val` may be
// `int` or `[]int`. If the original array is `[][]int`, then `val`
// may be `[]int` or `[][]int`. Consider the examples.
//
// Example:
// ```v
// mut a := [1, 2, 4]
// a.insert(2, 3)          // a now is [1, 2, 3, 4]
// mut b := [3, 4]
// b.insert(0, [1, 2])     // b now is [1, 2, 3, 4]
// mut c := [[3, 4]]
// c.insert(0, [1, 2])     // c now is [[1, 2], [3, 4]]
// ```
pub fn (mut a array) insert(i int, val voidptr) {
	if i < 0 || i > a.len {
		panic_n2('array.insert: index out of range (i,a.len):', i, a.len)
	}
	if a.len == max_int {
		panic('array.insert: a.len reached max_int')
	}
	if a.len >= a.cap {
		a.ensure_cap(a.len + 1)
	}
	unsafe {
		vmemmove(a.get_unsafe(i + 1), a.get_unsafe(i), u64((a.len - i)) * u64(a.element_size))
		a.set_unsafe(i, val)
	}
	a.len++
}

// insert_many is used internally to implement inserting many values
// into an the array beginning at `i`.
@[unsafe]
fn (mut a array) insert_many(i int, val voidptr, size int) {
	if i < 0 || i > a.len {
		panic_n2('array.insert_many: index out of range (i,a.len):', i, a.len)
	}
	new_len := i64(a.len) + i64(size)
	if new_len > max_int {
		panic_n('array.insert_many: max_int will be exceeded by a.len:', new_len)
	}
	a.ensure_cap(int(new_len))
	elem_size := a.element_size
	unsafe {
		iptr := a.get_unsafe(i)
		vmemmove(a.get_unsafe(i + size), iptr, u64(a.len - i) * u64(elem_size))
		vmemcpy(iptr, val, u64(size) * u64(elem_size))
	}
	a.len = int(new_len)
}

// prepend prepends one or more elements to an array.
// It is shorthand for `.insert(0, val)`
pub fn (mut a array) prepend(val voidptr) {
	a.insert(0, val)
}

// prepend_many prepends another array to this array.
// NOTE: `.prepend` is probably all you need.
// NOTE: This code is never called in all of vlib
@[unsafe]
fn (mut a array) prepend_many(val voidptr, size int) {
	unsafe { a.insert_many(0, val, size) }
}

// delete deletes array element at index `i`.
// This is exactly the same as calling `.delete_many(i, 1)`.
// NOTE: This function does NOT operate in-place. Internally, it
// creates a copy of the array, skipping over the element at `i`,
// and then points the original variable to the new memory location.
//
// Example:
// ```v
// mut a := ['0', '1', '2', '3', '4', '5']
// a.delete(1) // a is now ['0', '2', '3', '4', '5']
// ```
pub fn (mut a array) delete(i int) {
	a.delete_many(i, 1)
}

// delete_many deletes `size` elements beginning with index `i`
// NOTE: This function does NOT operate in-place. Internally, it
// creates a copy of the array, skipping over `size` elements
// starting at `i`, and then points the original variable
// to the new memory location.
//
// Example:
// ```v
// mut a := [1, 2, 3, 4, 5, 6, 7, 8, 9]
// b := unsafe { a[..9] } // creates a `slice` of `a`, not a clone
// a.delete_many(4, 3) // replaces `a` with a modified clone
// dump(a) // a: [1, 2, 3, 4, 8, 9] // `a` is now different
// dump(b) // b: [1, 2, 3, 4, 5, 6, 7, 8, 9] // `b` is still the same
// ```
pub fn (mut a array) delete_many(i int, size int) {
	if i < 0 || i64(i) + i64(size) > i64(a.len) {
		if size > 1 {
			panic_n3('array.delete: index out of range (i,i+size,a.len):', i, i + size,
				a.len)
		} else {
			panic_n2('array.delete: index out of range (i,a.len):', i, a.len)
		}
	}
	if a.flags.all(.noshrink | .noslices) {
		unsafe {
			vmemmove(&u8(a.data) + u64(i) * u64(a.element_size), &u8(a.data) + u64(i +
				size) * u64(a.element_size), u64(a.len - i - size) * u64(a.element_size))
		}
		a.len -= size
		return
	}
	// Note: if a is [12,34], a.len = 2, a.delete(0)
	// should move (2-0-1) elements = 1 element (the 34) forward
	old_data := a.data
	new_size := a.len - size
	new_cap := if new_size == 0 { 1 } else { new_size }
	a.data = vcalloc(u64(new_cap) * u64(a.element_size))
	unsafe { vmemcpy(a.data, old_data, u64(i) * u64(a.element_size)) }
	unsafe {
		vmemcpy(&u8(a.data) + u64(i) * u64(a.element_size), &u8(old_data) + u64(i +
			size) * u64(a.element_size), u64(a.len - i - size) * u64(a.element_size))
	}
	if a.flags.has(.noslices) {
		unsafe {
			free(old_data)
		}
	}
	a.len = new_size
	a.cap = new_cap
}

// clear clears the array without deallocating the allocated data.
// It does it by setting the array length to `0`
// Example: mut a := [1,2]; a.clear(); assert a.len == 0
pub fn (mut a array) clear() {
	a.len = 0
}

// reset quickly sets the bytes of all elements of the array to 0.
// Useful mainly for numeric arrays. Note, that calling reset()
// is not safe, when your array contains more complex elements,
// like structs, maps, pointers etc, since setting them to 0,
// can later lead to hard to find bugs.
@[unsafe]
pub fn (mut a array) reset() {
	unsafe { vmemset(a.data, 0, a.len * a.element_size) }
}

// trim trims the array length to `index` without modifying the allocated data.
// If `index` is greater than `len` nothing will be changed.
// Example: mut a := [1,2,3,4]; a.trim(3); assert a.len == 3
pub fn (mut a array) trim(index int) {
	if index < a.len {
		a.len = index
	}
}

// drop advances the array past the first `num` elements whilst preserving spare capacity.
// If `num` is greater than `len` the array will be emptied.
// Example:
// ```v
// mut a := [1,2]
// a << 3
// a.drop(2)
// assert a == [3]
// assert a.cap > a.len
// ```
pub fn (mut a array) drop(num int) {
	if num <= 0 {
		return
	}
	n := if num <= a.len { num } else { a.len }
	blen := u64(n) * u64(a.element_size)
	a.data = unsafe { &u8(a.data) + blen }
	a.offset += int(blen) // TODO: offset should become 64bit as well
	a.len -= n
	a.cap -= n
}

// we manually inline this for single operations for performance without -prod
@[inline; unsafe]
fn (a array) get_unsafe(i int) voidptr {
	unsafe {
		return &u8(a.data) + u64(i) * u64(a.element_size)
	}
}

// Private function. Used to implement array[] operator.
fn (a array) get(i int) voidptr {
	$if !no_bounds_checking {
		if i < 0 || i >= a.len {
			panic_n2('array.get: index out of range (i,a.len):', i, a.len)
		}
	}
	unsafe {
		return &u8(a.data) + u64(i) * u64(a.element_size)
	}
}

// Private function. Used to implement x = a[i] or { ... }
fn (a array) get_with_check(i int) voidptr {
	if i < 0 || i >= a.len {
		return 0
	}
	unsafe {
		return &u8(a.data) + u64(i) * u64(a.element_size)
	}
}

// first returns the first element of the `array`.
// If the `array` is empty, this will panic.
// However, `a[0]` returns an error object
// so it can be handled with an `or` block.
pub fn (a array) first() voidptr {
	if a.len == 0 {
		panic('array.first: array is empty')
	}
	return a.data
}

// last returns the last element of the `array`.
// If the `array` is empty, this will panic.
pub fn (a array) last() voidptr {
	if a.len == 0 {
		panic('array.last: array is empty')
	}
	unsafe {
		return &u8(a.data) + u64(a.len - 1) * u64(a.element_size)
	}
}

// pop_left returns the first element of the array and removes it by advancing the data pointer.
// If the `array` is empty, this will panic.
// NOTE: This function:
//   - Reduces both length and capacity by 1
//   - Advances the underlying data pointer by one element
//   - Leaves subsequent elements in-place (no memory copying)
// Sliced views will retain access to the original first element position,
// which is now detached from the array's active memory range.
//
// Example:
// ```v
// mut a := [1, 2, 3, 4, 5]
// b := unsafe { a[..5] } // full slice view
// first := a.pop_left()
//
// // Array now starts from second element
// dump(a) // a: [2, 3, 4, 5]
// assert a.len == 4
// assert a.cap == 4
//
// // Slice retains original memory layout
// dump(b) // b: [1, 2, 3, 4, 5]
// assert b.len == 5
//
// assert first == 1
//
// // Modifications affect both array and slice views
// a[0] = 99
// assert b[1] == 99  // changed in both
// ```
pub fn (mut a array) pop_left() voidptr {
	if a.len == 0 {
		panic('array.pop_left: array is empty')
	}
	first_elem := a.data
	unsafe {
		a.data = &u8(a.data) + u64(a.element_size)
	}
	a.offset += a.element_size
	a.len--
	a.cap--
	return first_elem
}

// pop returns the last element of the array, and removes it.
// If the `array` is empty, this will panic.
// NOTE: this function reduces the length of the given array,
// but arrays sliced from this one will not change. They still
// retain their "view" of the underlying memory.
//
// Example:
// ```v
// mut a := [1, 2, 3, 4, 5, 6, 7, 8, 9]
// b := unsafe{ a[..9] } // creates a "view" (also called a slice) into the same memory
// c := a.pop()
// assert c == 9
// a[1] = 5
// dump(a) // a: [1, 5, 3, 4, 5, 6, 7, 8]
// dump(b) // b: [1, 5, 3, 4, 5, 6, 7, 8, 9]
// assert a.len == 8
// assert b.len == 9
// ```
pub fn (mut a array) pop() voidptr {
	// in a sense, this is the opposite of `a << x`
	if a.len == 0 {
		panic('array.pop: array is empty')
	}
	new_len := a.len - 1
	last_elem := unsafe { &u8(a.data) + u64(new_len) * u64(a.element_size) }
	a.len = new_len
	// Note: a.cap is not changed here *on purpose*, so that
	// further << ops on that array will be more efficient.
	return last_elem
}

// delete_last efficiently deletes the last element of the array.
// It does it simply by reducing the length of the array by 1.
// If the array is empty, this will panic.
// See also: [trim](#array.trim)
pub fn (mut a array) delete_last() {
	if a.len == 0 {
		panic('array.delete_last: array is empty')
	}
	a.len--
}

// slice returns an array using the same buffer as original array
// but starting from the `start` element and ending with the element before
// the `end` element of the original array with the length and capacity
// set to the number of the elements in the slice.
// It will remain tied to the same memory location until the length increases
// (copy on grow) or `.clone()` is called on it.
// If `start` and `end` are invalid this function will panic.
// Alternative: Slices can also be made with [start..end] notation
// Alternative: `.slice_ni()` will always return an array.
fn (a array) slice(start int, _end int) array {
	// WARNNING: The is a temp solution for bootstrap!
	end := if _end == max_i64 || _end == max_i32 { a.len } else { _end } // max_int
	$if !no_bounds_checking {
		if start > end {
			panic('array.slice: invalid slice index (start>end):' + impl_i64_to_string(i64(start)) +
				', ' + impl_i64_to_string(end))
		}
		if end > a.len {
			panic('array.slice: slice bounds out of range (' + impl_i64_to_string(end) + ' >= ' +
				impl_i64_to_string(a.len) + ')')
		}
		if start < 0 {
			panic('array.slice: slice bounds out of range (start<0):' + impl_i64_to_string(start))
		}
	}
	// TODO: integrate reference counting
	// a.flags.clear(.noslices)
	offset := u64(start) * u64(a.element_size)
	data := unsafe { &u8(a.data) + offset }
	l := end - start
	res := array{
		element_size: a.element_size
		data:         data
		offset:       a.offset + int(offset) // TODO: offset should become 64bit
		len:          l
		cap:          l
	}
	return res
}

// slice_ni returns an array using the same buffer as original array
// but starting from the `start` element and ending with the element before
// the `end` element of the original array.
// This function can use negative indexes `a.slice_ni(-3, a.len)`
// that get the last 3 elements of the array otherwise it return an empty array.
// This function always return a valid array.
fn (a array) slice_ni(_start int, _end int) array {
	// a.flags.clear(.noslices)
	// WARNNING: The is a temp solution for bootstrap!
	mut end := if _end == max_i64 || _end == max_i32 { a.len } else { _end } // max_int
	mut start := _start

	if start < 0 {
		start = a.len + start
		if start < 0 {
			start = 0
		}
	}

	if end < 0 {
		end = a.len + end
		if end < 0 {
			end = 0
		}
	}
	if end >= a.len {
		end = a.len
	}

	if start >= a.len || start > end {
		res := array{
			element_size: a.element_size
			data:         a.data
			offset:       0
			len:          0
			cap:          0
		}
		return res
	}

	offset := u64(start) * u64(a.element_size)
	data := unsafe { &u8(a.data) + offset }
	l := end - start
	res := array{
		element_size: a.element_size
		data:         data
		offset:       a.offset + int(offset) // TODO: offset should be 64bit
		len:          l
		cap:          l
	}
	return res
}

// clone_static_to_depth() returns an independent copy of a given array.
// Unlike `clone_to_depth()` it has a value receiver and is used internally
// for slice-clone expressions like `a[2..4].clone()` and in -autofree generated code.
fn (a array) clone_static_to_depth(depth int) array {
	return unsafe { a.clone_to_depth(depth) }
}

// clone returns an independent copy of a given array.
// this will be overwritten by `cgen` with an appropriate call to `.clone_to_depth()`
// However the `checker` needs it here.
pub fn (a &array) clone() array {
	return unsafe { a.clone_to_depth(0) }
}

// recursively clone given array - `unsafe` when called directly because depth is not checked
@[unsafe]
pub fn (a &array) clone_to_depth(depth int) array {
	source_capacity_in_bytes := u64(a.cap) * u64(a.element_size)
	mut arr := array{
		element_size: a.element_size
		data:         vcalloc(source_capacity_in_bytes)
		len:          a.len
		cap:          a.cap
	}
	// Recursively clone-generated elements if array element is array type
	if depth > 0 && a.element_size == sizeof(array) && a.len >= 0 && a.cap >= a.len {
		ar := array{}
		asize := int(sizeof(array))
		for i in 0 .. a.len {
			unsafe { vmemcpy(&ar, a.get_unsafe(i), asize) }
			ar_clone := unsafe { ar.clone_to_depth(depth - 1) }
			unsafe { arr.set_unsafe(i, &ar_clone) }
		}
		return arr
	} else if depth > 0 && a.element_size == sizeof(string) && a.len >= 0 && a.cap >= a.len {
		for i in 0 .. a.len {
			str_ptr := unsafe { &string(a.get_unsafe(i)) }
			str_clone := (*str_ptr).clone()
			unsafe { arr.set_unsafe(i, &str_clone) }
		}
		return arr
	} else {
		if a.data != 0 && source_capacity_in_bytes > 0 {
			unsafe { vmemcpy(&u8(arr.data), a.data, source_capacity_in_bytes) }
		}
		return arr
	}
}

// we manually inline this for single operations for performance without -prod
@[inline; unsafe]
fn (mut a array) set_unsafe(i int, val voidptr) {
	unsafe { vmemcpy(&u8(a.data) + u64(a.element_size) * u64(i), val, a.element_size) }
}

// Private function. Used to implement assignment to the array element.
fn (mut a array) set(i int, val voidptr) {
	$if !no_bounds_checking {
		if i < 0 || i >= a.len {
			panic_n2('array.set: index out of range (i,a.len):', i, a.len)
		}
	}
	unsafe { vmemcpy(&u8(a.data) + u64(a.element_size) * u64(i), val, a.element_size) }
}

fn (mut a array) push(val voidptr) {
	if a.len < 0 {
		panic('array.push: negative len')
	}
	if a.len >= max_int {
		panic('array.push: len bigger than max_int')
	}
	if a.len >= a.cap {
		a.ensure_cap(a.len + 1)
	}
	unsafe { vmemcpy(&u8(a.data) + u64(a.element_size) * u64(a.len), val, a.element_size) }
	a.len++
}

// push_many implements the functionality for pushing another array.
// `val` is array.data and user facing usage is `a << [1,2,3]`
@[unsafe]
pub fn (mut a array) push_many(val voidptr, size int) {
	if size <= 0 || val == unsafe { nil } {
		return
	}
	new_len := i64(a.len) + i64(size)
	if new_len > max_int {
		// string interpolation also uses <<; avoid it, use a fixed string for the panic
		panic('array.push_many: new len exceeds max_int')
	}
	if new_len >= a.cap {
		a.ensure_cap(int(new_len))
	}
	if a.data == val && a.data != 0 {
		// handle `arr << arr`
		copy := a.clone()
		unsafe {
			vmemcpy(&u8(a.data) + u64(a.element_size) * u64(a.len), copy.data, u64(a.element_size) * u64(size))
		}
	} else {
		if a.data != 0 && val != 0 {
			unsafe { vmemcpy(&u8(a.data) + u64(a.element_size) * u64(a.len), val, u64(a.element_size) * u64(size)) }
		}
	}
	a.len = int(new_len)
}

// reverse_in_place reverses existing array data, modifying original array.
pub fn (mut a array) reverse_in_place() {
	if a.len < 2 || a.element_size == 0 {
		return
	}
	unsafe {
		mut tmp_value := malloc(a.element_size)
		for i in 0 .. a.len / 2 {
			vmemcpy(tmp_value, &u8(a.data) + u64(i) * u64(a.element_size), a.element_size)
			vmemcpy(&u8(a.data) + u64(i) * u64(a.element_size), &u8(a.data) +
				u64(a.len - 1 - i) * u64(a.element_size), a.element_size)
			vmemcpy(&u8(a.data) + u64(a.len - 1 - i) * u64(a.element_size), tmp_value,
				a.element_size)
		}
		free(tmp_value)
	}
}

// reverse returns a new array with the elements of the original array in reverse order.
pub fn (a array) reverse() array {
	if a.len < 2 {
		return a
	}
	mut arr := array{
		element_size: a.element_size
		data:         vcalloc(u64(a.cap) * u64(a.element_size))
		len:          a.len
		cap:          a.cap
	}
	for i in 0 .. a.len {
		unsafe { arr.set_unsafe(i, a.get_unsafe(a.len - 1 - i)) }
	}
	return arr
}

// free frees all memory occupied by the array.
@[unsafe]
pub fn (a &array) free() {
	$if prealloc {
		return
	}
	// if a.is_slice {
	// return
	// }
	if a.flags.has(.nofree) {
		return
	}
	mblock_ptr := &u8(u64(a.data) - u64(a.offset))
	if mblock_ptr != unsafe { nil } {
		unsafe { free(mblock_ptr) }
	}
	unsafe {
		a.data = nil
		a.offset = 0
		a.len = 0
		a.cap = 0
	}
}

// Some of the following functions have no implementation in V and exist here
// to expose them to the array namespace. Their implementation is compiler
// specific because of their use of `it` and `a < b` expressions.
// Therefore, the implementation is left to the backend.

// filter creates a new array with all elements that pass the test.
// Ignore the function signature. `filter` does not take an actual callback. Rather, it
// takes an `it` expression.
//
// Certain array functions (`filter` `any` `all`) support a simplified
// domain-specific-language by the backend compiler to make these operations
// more idiomatic to V. These functions are described here, but their implementation
// is compiler specific.
//
// Each function takes a boolean test expression as its single argument.
// These test expressions may use `it` as a pointer to a single element at a time.
//
// Example: a := [10,20,30,3,5,99]; assert a.filter(it < 5) == [3] // create an array of elements less than 5
// Example: a := [10,20,30,3,5,99]; assert a.filter(it % 2 == 1) == [3,5,99] // create an array of only odd elements
// Example: struct Named { name string }; a := [Named{'Abc'}, Named{'Bcd'}, Named{'Az'}]; assert a.filter(it.name[0] == `A`).len == 2
pub fn (a array) filter(predicate fn (voidptr) bool) array

// any tests whether at least one element in the array passes the test.
// Ignore the function signature. `any` does not take an actual callback. Rather, it
// takes an `it` expression.
// It returns `true` if it finds an element passing the test. Otherwise,
// it returns `false`. It doesn't modify the array.
//
// Example: a := [2,3,4]; assert a.any(it % 2 == 1) // 3 is odd, so this will pass
// Example: struct Named { name string }; a := [Named{'Bob'}, Named{'Bilbo'}]; assert a.any(it.name == 'Bob') // the first element will match
pub fn (a array) any(predicate fn (voidptr) bool) bool

// count counts how many elements in array pass the test.
// Ignore the function signature. `count` does not take an actual callback. Rather, it
// takes an `it` expression.
//
// Example: a := [10,3,5,7]; assert a.count(it % 2 == 1) == 3 // will return how many elements are odd
pub fn (a array) count(predicate fn (voidptr) bool) int

// all tests whether all elements in the array pass the test.
// Ignore the function signature. `all` does not take an actual callback. Rather, it
// takes an `it` expression.
// It returns `false` if any element fails the test. Otherwise,
// it returns `true`. It doesn't modify the array.
//
// Example: a := [3,5,7,9]; assert a.all(it % 2 == 1) // will return true if every element is odd
pub fn (a array) all(predicate fn (voidptr) bool) bool

// map creates a new array populated with the results of calling a provided function
// on every element in the calling array.
// It also accepts an `it` expression.
//
// Example:
// ```v
// words := ['hello', 'world']
// r1 := words.map(it.to_upper())
// assert r1 == ['HELLO', 'WORLD']
//
// // map can also accept anonymous functions
// r2 := words.map(fn (w string) string {
// 	return w.to_upper()
// })
// assert r2 == ['HELLO', 'WORLD']
// ```
pub fn (a array) map(callback fn (voidptr) voidptr) array

// sort sorts the array in place.
// Ignore the function signature. Passing a callback to `.sort` is not supported
// for now. Consider using the `.sort_with_compare` method if you need it.
//
// sort can take a boolean test expression as its single argument.
// The expression uses 2 'magic' variables `a` and `b` as pointers to the two elements
// being compared.
//
// Example: mut aa := [5,2,1,10]; aa.sort(); assert aa == [1,2,5,10] // will sort the array in ascending order
// Example: mut aa := [5,2,1,10]; aa.sort(b < a); assert aa == [10,5,2,1] // will sort the array in descending order
// Example: struct Named { name string }; mut aa := [Named{'Abc'}, Named{'Xyz'}]; aa.sort(b.name < a.name); assert aa.map(it.name) == ['Xyz','Abc'] // will sort descending by the .name field
pub fn (mut a array) sort(callback fn (voidptr, voidptr) int)

// sorted returns a sorted copy of the original array. The original array is *NOT* modified.
// See also .sort() .
// Example: assert [9,1,6,3,9].sorted() == [1,3,6,9,9]
// Example: assert [9,1,6,3,9].sorted(b < a) == [9,9,6,3,1]
pub fn (a &array) sorted(callback fn (voidptr, voidptr) int) array

// sort_with_compare sorts the array in-place using the results of the
// given function to determine sort order.
//
// The function should return one of three values:
// - `-1` when `a` should come before `b` ( `a < b` )
// - `1`  when `b` should come before `a` ( `b < a` )
// - `0`  when the order cannot be determined ( `a == b` )
//
// Example:
// ```v
// mut a := ['hi', '1', '5', '3']
// a.sort_with_compare(fn (a &string, b &string) int {
// 		if a < b {
// 			return -1
// 		}
// 		if a > b {
// 			return 1
// 		}
// 		return 0
// })
// assert a == ['1', '3', '5', 'hi']
// ```
pub fn (mut a array) sort_with_compare(callback fn (voidptr, voidptr) int) {
	$if freestanding {
		panic('sort_with_compare does not work with -freestanding')
	} $else {
		unsafe { vqsort(a.data, usize(a.len), usize(a.element_size), callback) }
	}
}

// sorted_with_compare sorts a clone of the array. The original array is not modified.
// It uses the results of the given function to determine sort order.
// See also .sort_with_compare()
pub fn (a &array) sorted_with_compare(callback fn (voidptr, voidptr) int) array {
	$if freestanding {
		panic('sorted_with_compare does not work with -freestanding')
	} $else {
		mut r := a.clone()
		unsafe { vqsort(r.data, usize(r.len), usize(r.element_size), callback) }
		return r
	}
	return array{}
}

// contains determines whether an array includes a certain value among its elements.
// It will return `true` if the array contains an element with this value.
// It is similar to `.any` but does not take an `it` expression.
//
// Example: assert [1, 2, 3].contains(4) == false
pub fn (a array) contains(value voidptr) bool

// index returns the first index at which a given element can be found in the array or `-1` if the value is not found.
pub fn (a array) index(value voidptr) int

@[direct_array_access; unsafe]
pub fn (mut a []string) free() {
	$if prealloc {
		return
	}
	for mut s in a {
		unsafe { s.free() }
	}
	unsafe { (&array(&a)).free() }
}

// The following functions are type-specific functions that apply
// to arrays of different types in different ways.

// str returns a string representation of an array of strings.
// Example: assert ['a', 'b', 'c'].str() == "['a', 'b', 'c']"
@[direct_array_access; manualfree]
pub fn (a []string) str() string {
	mut sb_len := 4 // 2x" + 1x, + 1xspace
	if a.len > 0 {
		// assume that most strings will be ~large as the first
		sb_len += a[0].len
		sb_len *= a.len
	}
	sb_len += 2 // 1x[ + 1x]
	mut sb := strings.new_builder(sb_len)
	sb.write_u8(`[`)
	for i in 0 .. a.len {
		val := a[i]
		sb.write_u8(`'`)
		sb.write_string(val)
		sb.write_u8(`'`)
		if i < a.len - 1 {
			sb.write_string(', ')
		}
	}
	sb.write_u8(`]`)
	res := sb.str()
	unsafe { sb.free() }
	return res
}

// hex returns a string with the hexadecimal representation of the byte elements of the array `b`.
pub fn (b []u8) hex() string {
	if b.len == 0 {
		return ''
	}
	return unsafe { data_to_hex_string(&u8(b.data), b.len) }
}

// copy copies the `src` byte array elements to the `dst` byte array.
// The number of the elements copied is the minimum of the length of both arrays.
// Returns the number of elements copied.
// NOTE: This is not an `array` method. It is a function that takes two arrays of bytes.
// See also: `arrays.copy`.
pub fn copy(mut dst []u8, src []u8) int {
	min := if dst.len < src.len { dst.len } else { src.len }
	if min > 0 {
		unsafe { vmemmove(&u8(dst.data), src.data, min) }
	}
	return min
}

// grow_cap grows the array's capacity by `amount` elements.
// Internally, it does this by copying the entire array to
// a new memory location (creating a clone).
pub fn (mut a array) grow_cap(amount int) {
	new_cap := i64(amount) + i64(a.cap)
	if new_cap > max_int {
		panic_n('array.grow_cap: max_int will be exceeded by new cap:', new_cap)
	}
	a.ensure_cap(int(new_cap))
}

// grow_len ensures that an array has a.len + amount of length
// Internally, it does this by copying the entire array to
// a new memory location (creating a clone) unless the array.cap
// is already large enough.
@[unsafe]
pub fn (mut a array) grow_len(amount int) {
	new_len := i64(amount) + i64(a.len)
	if new_len > max_int {
		panic_n('array.grow_len: max_int will be exceeded by new len:', new_len)
	}
	a.ensure_cap(int(new_len))
	a.len = int(new_len)
}

// pointers returns a new array, where each element
// is the address of the corresponding element in the array.
@[unsafe]
pub fn (a array) pointers() []voidptr {
	mut res := []voidptr{}
	for i in 0 .. a.len {
		unsafe { res << a.get_unsafe(i) }
	}
	return res
}

// vbytes on`voidptr` makes a V []u8 structure from a C style memory buffer.
// NOTE: the data is reused, NOT copied!
@[unsafe]
pub fn (data voidptr) vbytes(len int) []u8 {
	res := array{
		element_size: 1
		data:         data
		len:          len
		cap:          len
	}
	return res
}

// vbytes on `&u8` makes a V []u8 structure from a C style memory buffer.
// NOTE: the data is reused, NOT copied!
@[unsafe]
pub fn (data &u8) vbytes(len int) []u8 {
	return unsafe { voidptr(data).vbytes(len) }
}

// free frees the memory allocated
@[unsafe]
pub fn (data &u8) free() {
	unsafe { free(data) }
}

@[if !no_bounds_checking ?; inline]
fn panic_on_negative_len(len int) {
	if len < 0 {
		panic_n('negative .len:', len)
	}
}

@[if !no_bounds_checking ?; inline]
fn panic_on_negative_cap(cap int) {
	if cap < 0 {
		panic_n('negative .cap:', cap)
	}
}
// non-pub versions of array functions
// that allocale new memory using `GC_MALLOC_ATOMIC()`
// when `-gc boehm_*_opt` is used. These memory areas are not
// scanned for pointers.

////////////// module builtin

fn __new_array_noscan(mylen int, cap int, elm_size int) array {
	panic_on_negative_len(mylen)
	panic_on_negative_cap(cap)
	cap_ := if cap < mylen { mylen } else { cap }
	arr := array{
		element_size: elm_size
		data:         vcalloc_noscan(u64(cap_) * u64(elm_size))
		len:          mylen
		cap:          cap_
	}
	return arr
}

fn __new_array_with_default_noscan(mylen int, cap int, elm_size int, val voidptr) array {
	panic_on_negative_len(mylen)
	panic_on_negative_cap(cap)
	cap_ := if cap < mylen { mylen } else { cap }
	mut arr := array{
		element_size: elm_size
		data:         vcalloc_noscan(u64(cap_) * u64(elm_size))
		len:          mylen
		cap:          cap_
	}
	if val != 0 && arr.data != unsafe { nil } {
		if elm_size == 1 {
			byte_value := *(&u8(val))
			dptr := &u8(arr.data)
			for i in 0 .. arr.len {
				unsafe {
					dptr[i] = byte_value
				}
			}
		} else {
			for i in 0 .. arr.len {
				unsafe { arr.set_unsafe(i, val) }
			}
		}
	}
	return arr
}

fn __new_array_with_multi_default_noscan(mylen int, cap int, elm_size int, val voidptr) array {
	panic_on_negative_len(mylen)
	panic_on_negative_cap(cap)
	cap_ := if cap < mylen { mylen } else { cap }
	mut arr := array{
		element_size: elm_size
		data:         vcalloc_noscan(u64(cap_) * u64(elm_size))
		len:          mylen
		cap:          cap_
	}
	if val != 0 && arr.data != unsafe { nil } {
		for i in 0 .. arr.len {
			unsafe { arr.set_unsafe(i, charptr(val) + i * elm_size) }
		}
	}
	return arr
}

fn __new_array_with_array_default_noscan(mylen int, cap int, elm_size int, val array) array {
	panic_on_negative_len(mylen)
	panic_on_negative_cap(cap)
	cap_ := if cap < mylen { mylen } else { cap }
	mut arr := array{
		element_size: elm_size
		data:         vcalloc_noscan(u64(cap_) * u64(elm_size))
		len:          mylen
		cap:          cap_
	}
	for i in 0 .. arr.len {
		val_clone := val.clone()
		unsafe { arr.set_unsafe(i, &val_clone) }
	}
	return arr
}

// Private function, used by V (`nums := [1, 2, 3]`)
fn new_array_from_c_array_noscan(len int, cap int, elm_size int, c_array voidptr) array {
	panic_on_negative_len(len)
	panic_on_negative_cap(cap)
	cap_ := if cap < len { len } else { cap }
	arr := array{
		element_size: elm_size
		data:         vcalloc_noscan(u64(cap_) * u64(elm_size))
		len:          len
		cap:          cap_
	}
	// TODO: Write all memory functions (like memcpy) in V
	unsafe { vmemcpy(arr.data, c_array, u64(len) * u64(elm_size)) }
	return arr
}

// Private function. Doubles array capacity if needed.
fn (mut a array) ensure_cap_noscan(required int) {
	if required <= a.cap {
		return
	}
	if a.flags.has(.nogrow) {
		panic_n('array.ensure_cap_noscan: array with the flag `.nogrow` cannot grow in size, array required new size:',
			required)
	}
	mut cap := if a.cap > 0 { i64(a.cap) } else { i64(2) }
	for required > cap {
		cap *= 2
	}
	if cap > max_int {
		if a.cap < max_int {
			// limit the capacity, since bigger values, will overflow the 32bit integer used to store it
			cap = max_int
		} else {
			panic_n('array.ensure_cap_noscan: array needs to grow to cap (which is > 2^31):',
				cap)
		}
	}
	new_size := u64(cap) * u64(a.element_size)
	new_data := vcalloc_noscan(new_size)
	if a.data != unsafe { nil } {
		unsafe { vmemcpy(new_data, a.data, u64(a.len) * u64(a.element_size)) }
		// TODO: the old data may be leaked when no GC is used (ref-counting?)
	}
	a.data = new_data
	a.offset = 0
	a.cap = int(cap)
}

// repeat returns a new array with the given array elements repeated given times.
// `cgen` will replace this with an appropriate call to `repeat_to_depth()`

// version of `repeat()` that handles multi dimensional arrays
// `unsafe` to call directly because `depth` is not checked
@[unsafe]
fn (a array) repeat_to_depth_noscan(count int, depth int) array {
	if count < 0 {
		panic_n('array.repeat: count is negative:', count)
	}
	mut size := u64(count) * u64(a.len) * u64(a.element_size)
	if size == 0 {
		size = u64(a.element_size)
	}
	arr := array{
		element_size: a.element_size
		data:         if depth > 0 { vcalloc(size) } else { vcalloc_noscan(size) }
		len:          count * a.len
		cap:          count * a.len
	}
	if a.len > 0 {
		a_total_size := u64(a.len) * u64(a.element_size)
		arr_step_size := u64(a.len) * u64(arr.element_size)
		mut eptr := &u8(arr.data)
		unsafe {
			for _ in 0 .. count {
				if depth > 0 {
					ary_clone := a.clone_to_depth_noscan(depth)
					vmemcpy(eptr, &u8(ary_clone.data), a_total_size)
				} else {
					vmemcpy(eptr, &u8(a.data), a_total_size)
				}
				eptr += arr_step_size
			}
		}
	}
	return arr
}

// insert inserts a value in the array at index `i`
fn (mut a array) insert_noscan(i int, val voidptr) {
	if i < 0 || i > a.len {
		panic_n2('array.insert_noscan: index out of range (i,a.len):', i, a.len)
	}
	if a.len == max_int {
		panic('array.insert_noscan: a.len reached max_int')
	}
	a.ensure_cap_noscan(a.len + 1)
	unsafe {
		vmemmove(a.get_unsafe(i + 1), a.get_unsafe(i), u64(a.len - i) * u64(a.element_size))
		a.set_unsafe(i, val)
	}
	a.len++
}

// insert_many inserts many values into the array from index `i`.
@[unsafe]
fn (mut a array) insert_many_noscan(i int, val voidptr, size int) {
	if i < 0 || i > a.len {
		panic_n2('array.insert_many: index out of range (i, a.len):', i, a.len)
	}
	new_len := i64(a.len) + i64(size)
	if new_len > max_int {
		panic_n('array.insert_many_noscan: max_int will be exceeded by a.len:', new_len)
	}
	a.ensure_cap_noscan(a.len + size)
	elem_size := a.element_size
	unsafe {
		iptr := a.get_unsafe(i)
		vmemmove(a.get_unsafe(i + size), iptr, u64(a.len - i) * u64(elem_size))
		vmemcpy(iptr, val, u64(size) * u64(elem_size))
	}
	a.len += size
}

// prepend prepends one value to the array.
fn (mut a array) prepend_noscan(val voidptr) {
	a.insert_noscan(0, val)
}

// prepend_many prepends another array to this array.
@[unsafe]
fn (mut a array) prepend_many_noscan(val voidptr, size int) {
	unsafe { a.insert_many_noscan(0, val, size) }
}

// pop_left returns the first element of the array and removes it by advancing the data pointer.
fn (mut a array) pop_left_noscan() voidptr {
	if a.len == 0 {
		panic('array.pop_left: array is empty')
	}
	first_elem := a.data
	unsafe {
		a.data = &u8(a.data) + u64(a.element_size)
	}
	a.offset += a.element_size
	a.len--
	a.cap--
	return unsafe { memdup_noscan(first_elem, a.element_size) }
}

// pop returns the last element of the array, and removes it.
fn (mut a array) pop_noscan() voidptr {
	// in a sense, this is the opposite of `a << x`
	if a.len == 0 {
		panic('array.pop: array is empty')
	}
	new_len := a.len - 1
	last_elem := unsafe { &u8(a.data) + u64(new_len) * u64(a.element_size) }
	a.len = new_len
	// Note: a.cap is not changed here *on purpose*, so that
	// further << ops on that array will be more efficient.
	return unsafe { memdup_noscan(last_elem, a.element_size) }
}

// `clone_static_to_depth_noscan()` returns an independent copy of a given array.
// Unlike `clone_to_depth_noscan()` it has a value receiver and is used internally
// for slice-clone expressions like `a[2..4].clone()` and in -autofree generated code.
fn (a array) clone_static_to_depth_noscan(depth int) array {
	return unsafe { a.clone_to_depth_noscan(depth) }
}

// recursively clone given array - `unsafe` when called directly because depth is not checked
@[unsafe]
fn (a &array) clone_to_depth_noscan(depth int) array {
	mut size := u64(a.cap) * u64(a.element_size)
	if size == 0 {
		size++
	}
	mut arr := array{
		element_size: a.element_size
		data:         if depth == 0 { vcalloc_noscan(size) } else { vcalloc(size) }
		len:          a.len
		cap:          a.cap
	}
	// Recursively clone-generated elements if array element is array type
	if depth > 0 {
		for i in 0 .. a.len {
			ar := array{}
			unsafe { vmemcpy(&ar, a.get_unsafe(i), int(sizeof(array))) }
			ar_clone := unsafe { ar.clone_to_depth_noscan(depth - 1) }
			unsafe { arr.set_unsafe(i, &ar_clone) }
		}
		return arr
	} else {
		if a.data != 0 {
			unsafe { vmemcpy(&u8(arr.data), a.data, u64(a.cap) * u64(a.element_size)) }
		}
		return arr
	}
}

fn (mut a array) push_noscan(val voidptr) {
	if a.len < 0 {
		panic('array.push_noscan: negative len')
	}
	if a.len >= max_int {
		panic('array.push_noscan: len bigger than max_int')
	}
	if a.len >= a.cap {
		a.ensure_cap_noscan(a.len + 1)
	}
	unsafe { vmemcpy(&u8(a.data) + u64(a.element_size) * u64(a.len), val, a.element_size) }
	a.len++
}

// push_many implements the functionality for pushing another array.
// `val` is array.data and user facing usage is `a << [1,2,3]`
@[unsafe]
fn (mut a array) push_many_noscan(val voidptr, size int) {
	if size == 0 || val == unsafe { nil } {
		return
	}
	new_len := i64(a.len) + i64(size)
	if new_len > max_int {
		// string interpolation also uses <<; avoid it, use a fixed string for the panic
		panic('array.push_many_noscan: new len exceeds max_int')
	}
	if a.data == val && a.data != 0 {
		// handle `arr << arr`
		copy := a.clone()
		a.ensure_cap_noscan(a.len + size)
		unsafe {
			vmemcpy(a.get_unsafe(a.len), copy.data, u64(a.element_size) * u64(size))
		}
	} else {
		a.ensure_cap_noscan(a.len + size)
		if a.data != 0 && val != 0 {
			unsafe { vmemcpy(a.get_unsafe(a.len), val, u64(a.element_size) * u64(size)) }
		}
	}
	a.len = int(new_len)
}

// reverse returns a new array with the elements of the original array in reverse order.
fn (a array) reverse_noscan() array {
	if a.len < 2 {
		return a
	}
	mut arr := array{
		element_size: a.element_size
		data:         vcalloc_noscan(u64(a.cap) * u64(a.element_size))
		len:          a.len
		cap:          a.cap
	}
	for i in 0 .. a.len {
		unsafe { arr.set_unsafe(i, a.get_unsafe(a.len - 1 - i)) }
	}
	return arr
}

// grow_cap grows the array's capacity by `amount` elements.
fn (mut a array) grow_cap_noscan(amount int) {
	new_cap := i64(amount) + i64(a.cap)
	if new_cap > max_int {
		panic_n('array.grow_cap: max_int will be exceeded by new cap:', new_cap)
	}
	a.ensure_cap_noscan(int(new_cap))
}

// grow_len ensures that an array has a.len + amount of length
@[unsafe]
fn (mut a array) grow_len_noscan(amount int) {
	new_len := i64(amount) + i64(a.len)
	if new_len > max_int {
		panic_n('array.grow_len: max_int will be exceeded by new len:', new_len)
	}
	a.ensure_cap_noscan(int(new_len))
	a.len = int(new_len)
}
///////////// module builtin

// print_backtrace shows a backtrace of the current call stack on stdout.
pub fn print_backtrace() {
	// At the time of backtrace_symbols_fd call, the C stack would look something like this:
	// * print_backtrace_skipping_top_frames
	// * print_backtrace itself
	// * the rest of the backtrace frames
	// => top 2 frames should be skipped, since they will not be informative to the developer
	$if !no_backtrace ? {
		$if freestanding {
			println(bare_backtrace())
		} $else $if native {
			// TODO: native backtrace solution
		} $else $if tinyc {
			C.tcc_backtrace(c'Backtrace')
		} $else $if use_libbacktrace ? {
			// NOTE: TCC doesn't have the unwind library
			print_libbacktrace(1)
		} $else {
			print_backtrace_skipping_top_frames(2)
		}
	}
}

fn eprint_space_padding(output string, max_len int) {
	padding_len := max_len - output.len
	if padding_len > 0 {
		for _ in 0 .. padding_len {
			eprint(' ')
		}
	}
}
///////////// module builtin

// print_backtrace_skipping_top_frames prints the backtrace skipping N top frames.
pub fn print_backtrace_skipping_top_frames(xskipframes int) bool {
	$if no_backtrace ? {
		return false
	} $else {
		skipframes := xskipframes + 2
		$if macos || freebsd || openbsd || netbsd {
			return print_backtrace_skipping_top_frames_bsd(skipframes)
		} $else $if linux {
			return print_backtrace_skipping_top_frames_linux(skipframes)
		} $else {
			println('print_backtrace_skipping_top_frames is not implemented. skipframes: ${skipframes}')
		}
	}
	return false
}

// the functions below are not called outside this file,
// so there is no need to have their twins in builtin_windows.v
@[direct_array_access]
fn print_backtrace_skipping_top_frames_bsd(skipframes int) bool {
	$if no_backtrace ? {
		return false
	} $else {
		$if macos || freebsd || netbsd {
			buffer := [100]voidptr{}
			nr_ptrs := C.backtrace(&buffer[0], 100)
			if nr_ptrs < 2 {
				eprintln('C.backtrace returned less than 2 frames')
				return false
			}
			C.backtrace_symbols_fd(&buffer[skipframes], nr_ptrs - skipframes, 2)
		}
		return true
	}
}

fn C.tcc_backtrace(fmt &char) int
@[direct_array_access]
fn print_backtrace_skipping_top_frames_linux(skipframes int) bool {
	$if android {
		eprintln('On Android no backtrace is available.')
		return false
	}
	$if !glibc {
		eprintln('backtrace_symbols is missing => printing backtraces is not available.')
		eprintln('Some libc implementations like musl simply do not provide it.')
		return false
	}
	$if native {
		eprintln('native backend does not support backtraces yet.')
		return false
	} $else $if no_backtrace ? {
		return false
	} $else {
		$if linux && !freestanding {
			$if tinyc {
				C.tcc_backtrace(c'Backtrace')
				return false
			} $else {
				buffer := [100]voidptr{}
				nr_ptrs := C.backtrace(&buffer[0], 100)
				if nr_ptrs < 2 {
					eprintln('C.backtrace returned less than 2 frames')
					return false
				}
				nr_actual_frames := nr_ptrs - skipframes
				//////csymbols := backtrace_symbols(*voidptr(&buffer[skipframes]), nr_actual_frames)
				csymbols := C.backtrace_symbols(voidptr(&buffer[skipframes]), nr_actual_frames)
				for i in 0 .. nr_actual_frames {
					sframe := unsafe { tos2(&u8(csymbols[i])) }
					executable := sframe.all_before('(')
					addr := sframe.all_after('[').all_before(']')
					beforeaddr := sframe.all_before('[')
					cmd := 'addr2line -e ' + executable + ' ' + addr
					// taken from os, to avoid depending on the os module inside builtin.v
					f := C.popen(&char(cmd.str), c'r')
					if f == unsafe { nil } {
						eprintln(sframe)
						continue
					}
					buf := [1000]u8{}
					mut output := ''
					unsafe {
						bp := &buf[0]
						for C.fgets(&char(bp), 1000, f) != 0 {
							output += tos(bp, vstrlen(bp))
						}
					}
					output = output.trim_chars(' \t\n', .trim_both) + ':'
					if C.pclose(f) != 0 {
						eprintln(sframe)
						continue
					}
					if output in ['??:0:', '??:?:'] {
						output = ''
					}
					// See http://wiki.dwarfstd.org/index.php?title=Path_Discriminators
					// Note: it is shortened here to just d. , just so that it fits, and so
					// that the common error file:lineno: line format is enforced.
					output = output.replace(' (discriminator', ': (d.')
					eprint(output)
					eprint_space_padding(output, 55)
					eprint(' | ')
					eprint(addr)
					eprint(' | ')
					eprintln(beforeaddr)
				}
				if nr_actual_frames > 0 {
					unsafe { C.free(csymbols) }
				}
			}
		}
	}
	return true
}

///////////// module builtin

pub type FnExitCb = fn ()

fn C.atexit(f FnExitCb) int
fn C.strerror(int) &char

// These functions (_vinit, and _vcleanup), are generated by V, and if you have a `module no_main` program,
// you should ensure to call them when appropriate.
fn C._vinit(argc int, argv &&char)

fn C._vcleanup()

fn v_segmentation_fault_handler(signal_number i32) {
	$if freestanding {
		eprintln('signal 11: segmentation fault')
	} $else {
		C.fprintf(C.stderr, c'signal %d: segmentation fault\n', signal_number)
	}
	$if use_libbacktrace ? {
		eprint_libbacktrace(1)
	} $else {
		print_backtrace()
	}
	exit(128 + signal_number)
}

// exit terminates execution immediately and returns exit `code` to the shell.
@[noreturn]
pub fn exit(code int) {
	C.exit(code)
}

// at_exit registers a fn callback, that will be called at normal process termination.
// It returns an error, if the registration was not successful.
// The registered callback functions, will be called either via exit/1,
// or via return from the main program, in the reverse order of their registration.
// The same fn may be registered multiple times.
// Each callback fn will called once for each registration.
pub fn at_exit(cb FnExitCb) ! {
	$if freestanding {
		return error('at_exit not implemented with -freestanding')
	} $else {
		res := C.atexit(cb)
		if res != 0 {
			return error_with_code('at_exit failed', res)
		}
	}
}

// panic_debug private function that V uses for panics, -cg/-g is passed
// recent versions of tcc print nicer backtraces automatically
// Note: the duplication here is because tcc_backtrace should be called directly
// inside the panic functions.
@[noreturn]
fn panic_debug(line_no int, file string, mod string, fn_name string, s string) {
	// Note: the order here is important for a stabler test output
	// module is less likely to change than function, etc...
	// During edits, the line number will change most frequently,
	// so it is last
	$if freestanding {
		bare_panic(s)
	} $else {
		// vfmt off
		// Note: be carefull to not allocate here, avoid string interpolation
		flush_stdout()
		eprintln('================ V panic ================')
		eprint('   module: '); eprintln(mod)
		eprint(' function: '); eprint(fn_name); eprintln('()')
		eprint('  message: '); eprintln(s)
		eprint('     file: '); eprint(file); eprint(':');
	    C.fprintf(C.stderr, c'%d\n', line_no)
		eprint('   v hash: '); eprintln(vcurrent_hash())
		$if !vinix && !native {
			eprint('      pid: '); C.fprintf(C.stderr, c'%p\n', voidptr(v_getpid()))
			eprint('      tid: '); C.fprintf(C.stderr, c'%p\n', voidptr(v_gettid()))
		}
		eprintln('=========================================')
		flush_stdout()
		// vfmt on
		$if native {
			C.exit(1) // TODO: native backtraces
		} $else $if exit_after_panic_message ? {
			C.exit(1)
		} $else $if no_backtrace ? {
			C.exit(1)
		} $else {
			$if tinyc {
				$if panics_break_into_debugger ? {
					break_if_debugger_attached()
				} $else {
					C.tcc_backtrace(c'Backtrace')
				}
				C.exit(1)
			}
			$if use_libbacktrace ? {
				eprint_libbacktrace(1)
			} $else {
				print_backtrace_skipping_top_frames(1)
			}
			$if panics_break_into_debugger ? {
				break_if_debugger_attached()
			}
			C.exit(1)
		}
	}
	C.exit(1)
}

// panic_option_not_set is called by V, when you use option error propagation in your main function.
// It ends the program with a panic.
@[noreturn]
pub fn panic_option_not_set(s string) {
	panic('option not set (' + s + ')')
}

// panic_result_not_set is called by V, when you use result error propagation in your main function
// It ends the program with a panic.
@[noreturn]
pub fn panic_result_not_set(s string) {
	panic('result not set (' + s + ')')
}

pub fn vcurrent_hash() string {
	return @VCURRENTHASH
}

// panic prints a nice error message, then exits the process with exit code of 1.
// It also shows a backtrace on most platforms.
@[noreturn]
pub fn panic(s string) {
	// Note: be careful to not use string interpolation here:
	$if freestanding {
		bare_panic(s)
	} $else {
		// vfmt off
		flush_stdout()
		eprint('V panic: ')
		eprintln(s)
		eprint(' v hash: ')
		eprintln(vcurrent_hash())
		$if !vinix && !native {
			eprint('    pid: '); C.fprintf(C.stderr, c'%p\n', voidptr(v_getpid()))
			eprint('    tid: '); C.fprintf(C.stderr, c'%p\n', voidptr(v_gettid()))
		}
		flush_stdout()
		// vfmt on
		$if native {
			C.exit(1) // TODO: native backtraces
		} $else $if exit_after_panic_message ? {
			C.exit(1)
		} $else $if no_backtrace ? {
			C.exit(1)
		} $else {
			$if tinyc {
				$if panics_break_into_debugger ? {
					break_if_debugger_attached()
				} $else {
					C.tcc_backtrace(c'Backtrace')
				}
				C.exit(1)
			}
			$if use_libbacktrace ? {
				eprint_libbacktrace(1)
			} $else {
				print_backtrace_skipping_top_frames(1)
			}
			$if panics_break_into_debugger ? {
				break_if_debugger_attached()
			}
			C.exit(1)
		}
	}
	C.exit(1)
}

// return a C-API error message matching to `errnum`
pub fn c_error_number_str(errnum int) string {
	mut err_msg := ''
	$if freestanding {
		err_msg = 'error ' + errnum.str()
	} $else {
		$if !vinix {
			c_msg := C.strerror(errnum)
			err_msg = string{
				str:    &u8(c_msg)
				len:    unsafe { C.strlen(c_msg) }
				is_lit: 1
			}
		}
	}
	return err_msg
}

// panic_n prints an error message, followed by the given number, then exits the process with exit code of 1.
@[noreturn]
pub fn panic_n(s string, number1 i64) {
	panic(s + impl_i64_to_string(number1))
}

// panic_n2 prints an error message, followed by the given numbers, then exits the process with exit code of 1.
@[noreturn]
pub fn panic_n2(s string, number1 i64, number2 i64) {
	panic(s + impl_i64_to_string(number1) + ', ' + impl_i64_to_string(number2))
}

// panic_n3 prints an error message, followed by the given numbers, then exits the process with exit code of 1.
@[noreturn]
fn panic_n3(s string, number1 i64, number2 i64, number3 i64) {
	panic(s + impl_i64_to_string(number1) + ', ' + impl_i64_to_string(number2) + ', ' +
		impl_i64_to_string(number3))
}

// panic with a C-API error message matching `errnum`
@[noreturn]
pub fn panic_error_number(basestr string, errnum int) {
	panic(basestr + c_error_number_str(errnum))
}

// eprintln prints a message with a line end, to stderr. Both stderr and stdout are flushed.
pub fn eprintln(s string) {
	if s.str == 0 {
		eprintln('eprintln(NIL)')
		return
	}
	$if builtin_print_use_fprintf ? {
		C.fprintf(C.stderr, c'%.*s\n', s.len, s.str)
		return
	}
	$if freestanding {
		// flushing is only a thing with C.FILE from stdio.h, not on the syscall level
		bare_eprint(s.str, u64(s.len))
		bare_eprint(c'\n', 1)
	} $else $if ios {
		C.WrappedNSLog(s.str)
	} $else {
		flush_stdout()
		flush_stderr()
		// eprintln is used in panics, so it should not fail at all
		$if android && !termux {
			C.android_print(C.stderr, c'%.*s\n', s.len, s.str)
		}
		_writeln_to_fd(2, s)
		flush_stderr()
	}
}

// eprint prints a message to stderr. Both stderr and stdout are flushed.
pub fn eprint(s string) {
	if s.str == 0 {
		eprint('eprint(NIL)')
		return
	}
	$if builtin_print_use_fprintf ? {
		C.fprintf(C.stderr, c'%.*s', s.len, s.str)
		return
	}
	$if freestanding {
		// flushing is only a thing with C.FILE from stdio.h, not on the syscall level
		bare_eprint(s.str, u64(s.len))
	} $else $if ios {
		// TODO: Implement a buffer as NSLog doesn't have a "print"
		C.WrappedNSLog(s.str)
	} $else {
		flush_stdout()
		flush_stderr()
		$if android && !termux {
			C.android_print(C.stderr, c'%.*s', s.len, s.str)
		}
		_write_buf_to_fd(2, s.str, s.len)
		flush_stderr()
	}
}

pub fn flush_stdout() {
	$if freestanding {
		not_implemented := 'flush_stdout is not implemented\n'
		bare_eprint(not_implemented.str, u64(not_implemented.len))
	} $else {
		C.fflush(C.stdout)
	}
}

pub fn flush_stderr() {
	$if freestanding {
		not_implemented := 'flush_stderr is not implemented\n'
		bare_eprint(not_implemented.str, u64(not_implemented.len))
	} $else {
		C.fflush(C.stderr)
	}
}

// unbuffer_stdout will turn off the default buffering done for stdout.
// It will affect all consequent print and println calls, effectively making them behave like
// eprint and eprintln do. It is useful for programs, that want to produce progress bars, without
// cluttering your code with a flush_stdout() call after every print() call. It is also useful for
// programs (sensors), that produce small chunks of output, that you want to be able to process
// immediately.
// Note 1: if used, *it should be called at the start of your program*, before using
// print or println().
// Note 2: most libc implementations, have logic that use line buffering for stdout, when the output
// stream is connected to an interactive device, like a terminal, and otherwise fully buffer it,
// which is good for the output performance for programs that can produce a lot of output (like
// filters, or cat etc), but bad for latency. Normally, it is usually what you want, so it is the
// default for V programs too.
// See https://www.gnu.org/software/libc/manual/html_node/Buffering-Concepts.html .
// See https://pubs.opengroup.org/onlinepubs/9699919799/functions/V2_chap02.html#tag_15_05 .
pub fn unbuffer_stdout() {
	$if freestanding {
		not_implemented := 'unbuffer_stdout is not implemented\n'
		bare_eprint(not_implemented.str, u64(not_implemented.len))
	} $else {
		unsafe { C.setbuf(C.stdout, 0) }
	}
}

// print prints a message to stdout. Note that unlike `eprint`, stdout is not automatically flushed.
@[manualfree]
pub fn print(s string) {
	$if builtin_print_use_fprintf ? {
		C.fprintf(C.stdout, c'%.*s', s.len, s.str)
		return
	}
	$if android && !termux {
		C.android_print(C.stdout, c'%.*s\n', s.len, s.str)
	} $else $if ios {
		// TODO: Implement a buffer as NSLog doesn't have a "print"
		C.WrappedNSLog(s.str)
	} $else $if freestanding {
		bare_print(s.str, u64(s.len))
	} $else {
		_write_buf_to_fd(1, s.str, s.len)
	}
}

// println prints a message with a line end, to stdout. Note that unlike `eprintln`, stdout is not automatically flushed.
@[manualfree]
pub fn println(s string) {
	if s.str == 0 {
		println('println(NIL)')
		return
	}
	$if noprintln ? {
		return
	}
	$if builtin_print_use_fprintf ? {
		C.fprintf(C.stdout, c'%.*s\n', s.len, s.str)
		return
	}
	$if android && !termux {
		C.android_print(C.stdout, c'%.*s\n', s.len, s.str)
		return
	} $else $if ios {
		C.WrappedNSLog(s.str)
		return
	} $else $if freestanding {
		bare_print(s.str, u64(s.len))
		bare_print(c'\n', 1)
		return
	} $else {
		_writeln_to_fd(1, s)
	}
}

@[manualfree]
fn _writeln_to_fd(fd int, s string) {
	$if builtin_writeln_should_write_at_once ? {
		unsafe {
			buf_len := s.len + 1 // space for \n
			mut buf := malloc(buf_len)
			C.memcpy(buf, s.str, s.len)
			buf[s.len] = `\n`
			_write_buf_to_fd(fd, buf, buf_len)
			free(buf)
		}
	} $else {
		lf := u8(`\n`)
		_write_buf_to_fd(fd, s.str, s.len)
		_write_buf_to_fd(fd, &lf, 1)
	}
}

@[manualfree]
fn _write_buf_to_fd(fd int, buf &u8, buf_len int) {
	if buf_len <= 0 {
		return
	}
	mut ptr := unsafe { buf }
	mut remaining_bytes := isize(buf_len)
	mut x := isize(0)
	$if freestanding || vinix || builtin_write_buf_to_fd_should_use_c_write ? {
		unsafe {
			for remaining_bytes > 0 {
				x = C.write(fd, ptr, remaining_bytes)
				ptr += x
				remaining_bytes -= x
			}
		}
	} $else {
		mut stream := voidptr(C.stdout)
		if fd == 2 {
			stream = voidptr(C.stderr)
		}
		unsafe {
			for remaining_bytes > 0 {
				x = isize(C.fwrite(ptr, 1, remaining_bytes, stream))
				ptr += x
				remaining_bytes -= x
			}
		}
	}
}

// v_memory_panic will be true, *only* when a call to malloc/realloc/vcalloc etc could not succeed.
// In that situation, functions that are registered with at_exit(), should be able to limit their
// activity accordingly, by checking this flag.
// The V compiler itself for example registers a function with at_exit(), for showing timers.
// Without a way to distinguish, that we are in a memory panic, that would just display a second panic,
// which would be less clear to the user.
__global v_memory_panic = false

@[noreturn]
fn _memory_panic(fname string, size isize) {
	v_memory_panic = true
	// Note: do not use string interpolation here at all, since string interpolation itself allocates
	eprint(fname)
	eprint('(')
	$if freestanding || vinix {
		eprint('size') // TODO: use something more informative here
	} $else {
		C.fprintf(C.stderr, c'%p', voidptr(size))
	}
	if size < 0 {
		eprint(' < 0')
	}
	eprintln(')')
	panic('memory allocation failure')
}

__global total_m = i64(0)
// malloc dynamically allocates a `n` bytes block of memory on the heap.
// malloc returns a `byteptr` pointing to the memory address of the allocated space.
// unlike the `calloc` family of functions - malloc will not zero the memory block.
@[unsafe]
pub fn malloc(n isize) &u8 {
	$if trace_malloc ? {
		total_m += n
		C.fprintf(C.stderr, c'_v_malloc %6d total %10d\n', n, total_m)
		// print_backtrace()
	}
	if n < 0 {
		_memory_panic(@FN, n)
	} else if n == 0 {
		return &u8(unsafe { nil })
	}
	mut res := &u8(unsafe { nil })
	$if prealloc {
		return unsafe { prealloc_malloc(n) }
	} $else $if gcboehm ? {
		unsafe {
			res = C.GC_MALLOC(n)
		}
	} $else $if freestanding {
		// todo: is this safe to call malloc there? We export __malloc as malloc and it uses dlmalloc behind the scenes
		// so theoretically it is safe
		res = unsafe { __malloc(usize(n)) }
	} $else {
		$if windows {
			// Warning! On windows, we always use _aligned_malloc to allocate memory.
			// This ensures that we can later free the memory with _aligned_free
			// without needing to track whether the memory was originally allocated
			// by malloc or _aligned_malloc.
			res = unsafe { C._aligned_malloc(n, 1) }
		} $else {
			res = unsafe { C.malloc(n) }
		}
	}
	if res == 0 {
		_memory_panic(@FN, n)
	}
	$if debug_malloc ? {
		// Fill in the memory with something != 0 i.e. `M`, so it is easier to spot
		// when the calling code wrongly relies on it being zeroed.
		unsafe { C.memset(res, 0x4D, n) }
	}
	return res
}

@[unsafe]
pub fn malloc_noscan(n isize) &u8 {
	$if trace_malloc ? {
		total_m += n
		C.fprintf(C.stderr, c'malloc_noscan %6d total %10d\n', n, total_m)
		// print_backtrace()
	}
	if n < 0 {
		_memory_panic(@FN, n)
	}
	mut res := &u8(unsafe { nil })
	$if native {
		res = unsafe { C.malloc(n) }
	} $else $if prealloc {
		return unsafe { prealloc_malloc(n) }
	} $else $if gcboehm ? {
		$if gcboehm_opt ? {
			unsafe {
				res = C.GC_MALLOC_ATOMIC(n)
			}
		} $else {
			unsafe {
				res = C.GC_MALLOC(n)
			}
		}
	} $else $if freestanding {
		res = unsafe { __malloc(usize(n)) }
	} $else {
		$if windows {
			// Warning! On windows, we always use _aligned_malloc to allocate memory.
			// This ensures that we can later free the memory with _aligned_free
			// without needing to track whether the memory was originally allocated
			// by malloc or _aligned_malloc.
			res = unsafe { C._aligned_malloc(n, 1) }
		} $else {
			res = unsafe { C.malloc(n) }
		}
	}
	if res == 0 {
		_memory_panic(@FN, n)
	}
	$if debug_malloc ? {
		// Fill in the memory with something != 0 i.e. `M`, so it is easier to spot
		// when the calling code wrongly relies on it being zeroed.
		unsafe { C.memset(res, 0x4D, n) }
	}
	return res
}

@[inline]
fn __at_least_one(how_many u64) u64 {
	// handle the case for allocating memory for empty structs, which have sizeof(EmptyStruct) == 0
	// in this case, just allocate a single byte, avoiding the panic for malloc(0)
	if how_many == 0 {
		return 1
	}
	return how_many
}

// malloc_uncollectable dynamically allocates a `n` bytes block of memory
// on the heap, which will NOT be garbage-collected (but its contents will).
@[unsafe]
pub fn malloc_uncollectable(n isize) &u8 {
	$if trace_malloc ? {
		total_m += n
		C.fprintf(C.stderr, c'malloc_uncollectable %6d total %10d\n', n, total_m)
		// print_backtrace()
	}
	if n < 0 {
		_memory_panic(@FN, n)
	}

	mut res := &u8(unsafe { nil })
	$if prealloc {
		return unsafe { prealloc_malloc(n) }
	} $else $if gcboehm ? {
		unsafe {
			res = C.GC_MALLOC_UNCOLLECTABLE(n)
		}
	} $else $if freestanding {
		res = unsafe { __malloc(usize(n)) }
	} $else {
		$if windows {
			// Warning! On windows, we always use _aligned_malloc to allocate memory.
			// This ensures that we can later free the memory with _aligned_free
			// without needing to track whether the memory was originally allocated
			// by malloc or _aligned_malloc.
			res = unsafe { C._aligned_malloc(n, 1) }
		} $else {
			res = unsafe { C.malloc(n) }
		}
	}
	if res == 0 {
		_memory_panic(@FN, n)
	}
	$if debug_malloc ? {
		// Fill in the memory with something != 0 i.e. `M`, so it is easier to spot
		// when the calling code wrongly relies on it being zeroed.
		unsafe { C.memset(res, 0x4D, n) }
	}
	return res
}

// v_realloc resizes the memory block `b` with `n` bytes.
// The `b byteptr` must be a pointer to an existing memory block
// previously allocated with `malloc` or `vcalloc`.
// Please, see also realloc_data, and use it instead if possible.
@[unsafe]
pub fn v_realloc(b &u8, n isize) &u8 {
	$if trace_realloc ? {
		C.fprintf(C.stderr, c'v_realloc %6d\n', n)
	}
	mut new_ptr := &u8(unsafe { nil })
	$if prealloc {
		unsafe {
			new_ptr = malloc(n)
			C.memcpy(new_ptr, b, n)
		}
		return new_ptr
	} $else $if gcboehm ? {
		new_ptr = unsafe { C.GC_REALLOC(b, n) }
	} $else {
		$if windows {
			// Warning! On windows, we always use _aligned_realloc to reallocate memory.
			// This ensures that we can later free the memory with _aligned_free
			// without needing to track whether the memory was originally allocated
			// by malloc or _aligned_malloc/_aligned_realloc.
			new_ptr = unsafe { C._aligned_realloc(b, n, 1) }
		} $else {
			new_ptr = unsafe { C.realloc(b, n) }
		}
	}
	if new_ptr == 0 {
		_memory_panic(@FN, n)
	}
	return new_ptr
}

// realloc_data resizes the memory block pointed by `old_data` to `new_size`
// bytes. `old_data` must be a pointer to an existing memory block, previously
// allocated with `malloc` or `vcalloc`, of size `old_data`.
// realloc_data returns a pointer to the new location of the block.
// Note: if you know the old data size, it is preferable to call `realloc_data`,
// instead of `v_realloc`, at least during development, because `realloc_data`
// can make debugging easier, when you compile your program with
// `-d debug_realloc`.
@[unsafe]
pub fn realloc_data(old_data &u8, old_size int, new_size int) &u8 {
	$if trace_realloc ? {
		C.fprintf(C.stderr, c'realloc_data old_size: %6d new_size: %6d\n', old_size, new_size)
	}
	$if prealloc {
		return unsafe { prealloc_realloc(old_data, old_size, new_size) }
	}
	$if debug_realloc ? {
		// Note: this is slower, but helps debugging memory problems.
		// The main idea is to always force reallocating:
		// 1) allocate a new memory block
		// 2) copy the old to the new
		// 3) fill the old with 0x57 (`W`)
		// 4) free the old block
		// => if there is still a pointer to the old block somewhere
		//    it will point to memory that is now filled with 0x57.
		unsafe {
			new_ptr := malloc(new_size)
			min_size := if old_size < new_size { old_size } else { new_size }
			C.memcpy(new_ptr, old_data, min_size)
			C.memset(old_data, 0x57, old_size)
			free(old_data)
			return new_ptr
		}
	}
	mut nptr := &u8(unsafe { nil })
	$if gcboehm ? {
		nptr = unsafe { C.GC_REALLOC(old_data, new_size) }
	} $else {
		$if windows {
			// Warning! On windows, we always use _aligned_realloc to reallocate memory.
			// This ensures that we can later free the memory with _aligned_free
			// without needing to track whether the memory was originally allocated
			// by malloc or _aligned_malloc/_aligned_realloc.
			nptr = unsafe { C._aligned_realloc(old_data, new_size, 1) }
		} $else {
			nptr = unsafe { C.realloc(old_data, new_size) }
		}
	}
	if nptr == 0 {
		_memory_panic(@FN, isize(new_size))
	}
	return nptr
}

// vcalloc dynamically allocates a zeroed `n` bytes block of memory on the heap.
// vcalloc returns a `byteptr` pointing to the memory address of the allocated space.
// vcalloc checks for negative values given in `n`.
pub fn vcalloc(n isize) &u8 {
	$if trace_vcalloc ? {
		total_m += n
		C.fprintf(C.stderr, c'vcalloc %6d total %10d\n', n, total_m)
	}
	if n < 0 {
		_memory_panic(@FN, n)
	} else if n == 0 {
		return &u8(unsafe { nil })
	}
	$if prealloc {
		return unsafe { prealloc_calloc(n) }
	} $else $if native {
		return unsafe { C.calloc(1, n) }
	} $else $if gcboehm ? {
		return unsafe { &u8(C.GC_MALLOC(n)) }
	} $else {
		$if windows {
			// Warning! On windows, we always use _aligned_malloc to allocate memory.
			// This ensures that we can later free the memory with _aligned_free
			// without needing to track whether the memory was originally allocated
			// by malloc or _aligned_malloc/_aligned_realloc/_aligned_recalloc.
			ptr := unsafe { C._aligned_malloc(n, 1) }
			if ptr != &u8(unsafe { nil }) {
				unsafe { C.memset(ptr, 0, n) }
			}
			return ptr
		} $else {
			return unsafe { C.calloc(1, n) }
		}
	}
	return &u8(unsafe { nil }) // not reached, TODO: remove when V's checker is improved
}

// special versions of the above that allocate memory which is not scanned
// for pointers (but is collected) when the Boehm garbage collection is used
pub fn vcalloc_noscan(n isize) &u8 {
	$if trace_vcalloc ? {
		total_m += n
		C.fprintf(C.stderr, c'vcalloc_noscan %6d total %10d\n', n, total_m)
	}
	$if prealloc {
		return unsafe { prealloc_calloc(n) }
	} $else $if gcboehm ? {
		if n < 0 {
			_memory_panic(@FN, n)
		}
		$if gcboehm_opt ? {
			res := unsafe { C.GC_MALLOC_ATOMIC(n) }
			unsafe { C.memset(res, 0, n) }
			return &u8(res)
		} $else {
			res := unsafe { C.GC_MALLOC(n) }
			return &u8(res)
		}
	} $else {
		return unsafe { vcalloc(n) }
	}
	return &u8(unsafe { nil }) // not reached, TODO: remove when V's checker is improved
}

// free allows for manually freeing memory allocated at the address `ptr`.
@[unsafe]
pub fn free(ptr voidptr) {
	$if trace_free ? {
		C.fprintf(C.stderr, c'free ptr: %p\n', ptr)
	}
	$if builtin_free_nop ? {
		return
	}
	if ptr == unsafe { 0 } {
		$if trace_free_nulls ? {
			C.fprintf(C.stderr, c'free null ptr\n', ptr)
		}
		$if trace_free_nulls_break ? {
			break_if_debugger_attached()
		}
		return
	}
	$if prealloc {
		return
	} $else $if gcboehm ? {
		// It is generally better to leave it to Boehm's gc to free things.
		// Calling C.GC_FREE(ptr) was tried initially, but does not work
		// well with programs that do manual management themselves.
		//
		// The exception is doing leak detection for manual memory management:
		$if gcboehm_leak ? {
			unsafe { C.GC_FREE(ptr) }
		}
	} $else {
		$if windows {
			// Warning! On windows, we always use _aligned_free to free memory.
			unsafe { C._aligned_free(ptr) }
		} $else {
			C.free(ptr)
		}
	}
}

// memdup dynamically allocates a `sz` bytes block of memory on the heap
// memdup then copies the contents of `src` into the allocated space and
// returns a pointer to the newly allocated space.
@[unsafe]
pub fn memdup(src voidptr, sz isize) voidptr {
	$if trace_memdup ? {
		C.fprintf(C.stderr, c'memdup size: %10d\n', sz)
	}
	if sz == 0 {
		return vcalloc(1)
	}
	unsafe {
		mem := malloc(sz)
		return C.memcpy(mem, src, sz)
	}
}

@[unsafe]
pub fn memdup_noscan(src voidptr, sz isize) voidptr {
	$if trace_memdup ? {
		C.fprintf(C.stderr, c'memdup_noscan size: %10d\n', sz)
	}
	if sz == 0 {
		return vcalloc_noscan(1)
	}
	unsafe {
		mem := malloc_noscan(sz)
		return C.memcpy(mem, src, sz)
	}
}

// memdup_uncollectable dynamically allocates a `sz` bytes block of memory
// on the heap, which will NOT be garbage-collected (but its contents will).
// memdup_uncollectable then copies the contents of `src` into the allocated
// space and returns a pointer to the newly allocated space.
@[unsafe]
pub fn memdup_uncollectable(src voidptr, sz isize) voidptr {
	$if trace_memdup ? {
		C.fprintf(C.stderr, c'memdup_uncollectable size: %10d\n', sz)
	}
	if sz == 0 {
		return vcalloc(1)
	}
	unsafe {
		mem := malloc_uncollectable(sz)
		return C.memcpy(mem, src, sz)
	}
}

// memdup_align dynamically allocates a memory block of `sz` bytes on the heap,
// copies the contents from `src` into the allocated space, and returns a pointer
// to the newly allocated memory. The returned pointer is aligned to the specified `align` boundary.
//   - `align` must be a power of two and at least 1
//   - `sz` must be non-negative
//   - The memory regions should not overlap
@[unsafe]
pub fn memdup_align(src voidptr, sz isize, align isize) voidptr {
	$if trace_memdup ? {
		C.fprintf(C.stderr, c'memdup_align size: %10d align: %10d\n', sz, align)
	}
	if sz == 0 {
		return vcalloc(1)
	}
	n := sz
	$if trace_malloc ? {
		total_m += n
		C.fprintf(C.stderr, c'_v_memdup_align %6d total %10d\n', n, total_m)
		// print_backtrace()
	}
	if n < 0 {
		_memory_panic(@FN, n)
	}
	mut res := &u8(unsafe { nil })
	$if prealloc {
		res = prealloc_malloc_align(n, align)
	} $else $if gcboehm ? {
		unsafe {
			res = C.GC_memalign(align, n)
		}
	} $else $if freestanding {
		// todo: is this safe to call malloc there? We export __malloc as malloc and it uses dlmalloc behind the scenes
		// so theoretically it is safe
		panic('memdup_align is not implemented with -freestanding')
		res = unsafe { __malloc(usize(n)) }
	} $else {
		$if windows {
			// Warning! On windows, we always use _aligned_malloc to allocate memory.
			// This ensures that we can later free the memory with _aligned_free
			// without needing to track whether the memory was originally allocated
			// by malloc or _aligned_malloc.
			res = unsafe { C._aligned_malloc(n, align) }
		} $else {
			res = unsafe { C.aligned_alloc(align, n) }
		}
	}
	if res == 0 {
		_memory_panic(@FN, n)
	}
	$if debug_malloc ? {
		// Fill in the memory with something != 0 i.e. `M`, so it is easier to spot
		// when the calling code wrongly relies on it being zeroed.
		unsafe { C.memset(res, 0x4D, n) }
	}
	return C.memcpy(res, src, sz)
}

// GCHeapUsage contains stats about the current heap usage of your program.
pub struct GCHeapUsage {
pub:
	heap_size      usize
	free_bytes     usize
	total_bytes    usize
	unmapped_bytes usize
	bytes_since_gc usize
}

// gc_heap_usage returns the info about heap usage.
pub fn gc_heap_usage() GCHeapUsage {
	$if gcboehm ? {
		mut res := GCHeapUsage{}
		C.GC_get_heap_usage_safe(&res.heap_size, &res.free_bytes, &res.unmapped_bytes,
			&res.bytes_since_gc, &res.total_bytes)
		return res
	} $else {
		return GCHeapUsage{}
	}
}

// gc_memory_use returns the total memory use in bytes by all allocated blocks.
pub fn gc_memory_use() usize {
	$if gcboehm ? {
		return C.GC_get_memory_use()
	} $else {
		return 0
	}
}

@[inline]
fn v_fixed_index(i int, len int) int {
	$if !no_bounds_checking {
		if i < 0 || i >= len {
			panic('fixed array index out of range (index: ' + i64(i).str() + ', len: ' +
				i64(len).str() + ')')
		}
	}
	return i
}

// NOTE: g_main_argc and g_main_argv are filled in right after C's main start.
// They are used internally by V's builtin; for user code, it is much
// more convenient to just use `os.args` or call `arguments()` instead.

@[markused]
__global g_main_argc = int(0)

@[markused]
__global g_main_argv = unsafe { nil }

@[markused]
__global g_live_reload_info voidptr

// arguments returns the command line arguments, used for starting the current program as a V array of strings.
// The first string in the array (index 0), is the name of the program, used for invoking the program.
// The second string in the array (index 1), if it exists, is the first argument to the program, etc.
// For example, if you started your program as `myprogram -option`, then arguments() will return ['myprogram', '-option'].
// Note: if you `v run file.v abc def`, then arguments() will return ['file', 'abc', 'def'], or ['file.exe', 'abc', 'def'] (on Windows).
pub fn arguments() []string {
	argv := &&u8(g_main_argv)
	mut res := []string{cap: g_main_argc}
	for i in 0 .. g_main_argc {
		$if windows {
			res << unsafe { string_from_wide(&u16(argv[i])) }
		} $else {
			res << unsafe { tos_clone(argv[i]) }
		}
	}
	return res
}

// v_getpid returns a process identifier. It is a number that is guaranteed to
// remain the same while the current process is running. It may or may not be
// equal to the value of v_gettid(). Note: it is *NOT equal on Windows*.
pub fn v_getpid() u64 {
	$if no_getpid ? {
		// support non posix/windows systems that lack process management
		return 0
	} $else $if windows {
		return u64(C.GetCurrentProcessId())
	} $else {
		return u64(C.getpid())
	}
}

// v_gettid retuns a thread identifier. It is a number that is guaranteed to not
// change, while the current thread is running. Different threads, running at
// the same time in the same process, have different thread ids. There is no
// such guarantee for threads running in different processes.
// Important: this will be the same number returned by v_getpid(), but only on
// non windows systems, when the current thread is the main one. It is best to
// *avoid relying on this equivalence*, and use v_gettid and v_getpid only for
// tracing and debugging multithreaded issues, but *NOT for logic decisions*.
pub fn v_gettid() u64 {
	$if no_gettid ? {
		// support non posix/windows systems that lack process management
		return 0
	} $else $if windows {
		return u64(C.GetCurrentThreadId())
	} $else $if linux && !musl ? {
		return u64(C.gettid())
	} $else $if threads {
		return u64(C.pthread_self())
	} $else {
		return v_getpid()
	}
}

///////////// module builtin

// isnil returns true if an object is nil (only for C objects).
@[inline]
pub fn isnil(v voidptr) bool {
	return v == 0
}

struct VCastTypeIndexName {
	tindex int
	tname  string
}

// will be filled in cgen
__global as_cast_type_indexes []VCastTypeIndexName

@[direct_array_access]
fn __as_cast(obj voidptr, obj_type int, expected_type int) voidptr {
	if obj_type != expected_type {
		mut obj_name := as_cast_type_indexes[0].tname.clone()
		mut expected_name := as_cast_type_indexes[0].tname.clone()
		for x in as_cast_type_indexes {
			if x.tindex == obj_type {
				obj_name = x.tname.clone()
			}
			if x.tindex == expected_type {
				expected_name = x.tname.clone()
			}
		}
		panic('as cast: cannot cast `' + obj_name + '` to `' + expected_name + '`')
	}
	return obj
}

// VAssertMetaInfo is used during assertions. An instance of it is filled in by compile time generated code, when an assertion fails.
pub struct VAssertMetaInfo {
pub:
	fpath   string // the source file path of the assertion
	line_nr int    // the line number of the assertion
	fn_name string // the function name in which the assertion is
	src     string // the actual source line of the assertion
	op      string // the operation of the assertion, i.e. '==', '<', 'call', etc ...
	llabel  string // the left side of the infix expressions as source
	rlabel  string // the right side of the infix expressions as source
	lvalue  string // the stringified *actual value* of the left side of a failed assertion
	rvalue  string // the stringified *actual value* of the right side of a failed assertion
	message string // the value of the `message` from `assert cond, message`
	has_msg bool   // false for assertions like `assert cond`, true for `assert cond, 'oh no'`
}

// free frees the memory occupied by the assertion meta data. It is called automatically by
// the code, that V's test framework generates, after all other callbacks have been called.
@[manualfree; unsafe]
pub fn (ami &VAssertMetaInfo) free() {
	unsafe {
		ami.fpath.free()
		ami.fn_name.free()
		ami.src.free()
		ami.op.free()
		ami.llabel.free()
		ami.rlabel.free()
		ami.lvalue.free()
		ami.rvalue.free()
		ami.message.free()
	}
}

fn __print_assert_failure(i &VAssertMetaInfo) {
	eprintln('${i.fpath}:${i.line_nr + 1}: FAIL: fn ${i.fn_name}: assert ${i.src}')
	if i.op.len > 0 && i.op != 'call' {
		if i.llabel == i.lvalue {
			eprintln('   left value: ${i.llabel}')
		} else {
			eprintln('   left value: ${i.llabel} = ${i.lvalue}')
		}
		if i.rlabel == i.rvalue {
			eprintln('  right value: ${i.rlabel}')
		} else {
			eprintln('  right value: ${i.rlabel} = ${i.rvalue}')
		}
	}
	if i.has_msg {
		eprintln('      message: ${i.message}')
	}
}

// FunctionParam holds type information for function and/or method arguments.
pub struct FunctionParam {
pub:
	typ  int
	name string
}

// FunctionData holds information about a parsed function.
pub struct FunctionData {
pub:
	name        string
	attrs       []string
	args        []FunctionParam
	return_type int
	typ         int
}

pub struct VariantData {
pub:
	typ int
}

pub struct EnumData {
pub:
	name  string
	value i64
	attrs []string
}

// FieldData holds information about a field. Fields reside on structs.
pub struct FieldData {
pub:
	name          string // the name of the field f
	typ           int    // the internal TypeID of the field f,
	unaliased_typ int    // if f's type was an alias of int, this will be TypeID(int)

	attrs    []string // the attributes of the field f
	is_pub   bool     // f is in a `pub:` section
	is_mut   bool     // f is in a `mut:` section
	is_embed bool     // f is a embedded struct

	is_shared bool // `f shared Abc`
	is_atomic bool // `f atomic int` , TODO
	is_option bool // `f ?string` , TODO

	is_array  bool // `f []string` , TODO
	is_map    bool // `f map[string]int` , TODO
	is_chan   bool // `f chan int` , TODO
	is_enum   bool // `f Enum` where Enum is an enum
	is_struct bool // `f Abc` where Abc is a struct , TODO
	is_alias  bool // `f MyInt` where `type MyInt = int`, TODO

	indirections u8 // 0 for `f int`, 1 for `f &int`, 2 for `f &&int` , TODO
}

pub enum AttributeKind {
	plain           // [name]
	string          // ['name']
	number          // [123]
	bool            // [true] || [false]
	comptime_define // [if name]	
}

pub struct VAttribute {
pub:
	name    string
	has_arg bool
	arg     string
	kind    AttributeKind
}

///////////// module builtin

// <execinfo.h>
fn C.backtrace(a &voidptr, size int) int
fn C.backtrace_symbols(a &voidptr, size int) &&char
fn C.backtrace_symbols_fd(a &voidptr, size int, fd int)
///////////// module builtin

$if !no_gc_threads ? {
	#flag -DGC_THREADS=1
}

$if use_bundled_libgc ? {
	#flag -DGC_BUILTIN_ATOMIC=1
	#flag -I @VEXEROOT/thirdparty/libgc/include
	#flag @VEXEROOT/thirdparty/libgc/gc.o
}

$if dynamic_boehm ? {
	$if windows {
		$if tinyc {
			#flag -I @VEXEROOT/thirdparty/libgc/include
			#flag -L @VEXEROOT/thirdparty/tcc/lib
			#flag -lgc
		} $else $if msvc {
			#flag -DGC_BUILTIN_ATOMIC=1
			#flag -I @VEXEROOT/thirdparty/libgc/include
		} $else {
			#flag -DGC_WIN32_THREADS=1
			#flag -DGC_BUILTIN_ATOMIC=1
			#flag -I @VEXEROOT/thirdparty/libgc/include
			#flag @VEXEROOT/thirdparty/libgc/gc.o
		}
	} $else {
		$if $pkgconfig('bdw-gc-threaded') {
			#pkgconfig bdw-gc-threaded
		} $else $if $pkgconfig('bdw-gc') {
			#pkgconfig bdw-gc
		} $else {
			$if openbsd || freebsd {
				#flag -I/usr/local/include
				#flag -L/usr/local/lib
			}
			$if freebsd {
				#flag -lgc-threaded
			} $else {
				#flag -lgc
			}
		}
	}
} $else {
	$if macos || linux {
		#flag -DGC_BUILTIN_ATOMIC=1
		#flag -I @VEXEROOT/thirdparty/libgc/include
		$if (prod && !tinyc && !debug) || !(amd64 || arm64 || i386 || arm32 || rv64) {
			// TODO: replace the architecture check with a `!$exists("@VEXEROOT/thirdparty/tcc/lib/libgc.a")` comptime call
			#flag @VEXEROOT/thirdparty/libgc/gc.o
		} $else {
			$if !use_bundled_libgc ? {
				#flag @VEXEROOT/thirdparty/tcc/lib/libgc.a
			}
		}
		$if macos {
			#flag -DMPROTECT_VDB=1
		}
		#flag -ldl
		#flag -lpthread
	} $else $if freebsd {
		// Tested on FreeBSD 13.0-RELEASE-p3, with clang, gcc and tcc
		#flag -DGC_BUILTIN_ATOMIC=1
		#flag -DBUS_PAGE_FAULT=T_PAGEFLT
		$if !tinyc {
			#flag -DUSE_MMAP
			#flag -I @VEXEROOT/thirdparty/libgc/include
			#flag @VEXEROOT/thirdparty/libgc/gc.o
		}
		$if tinyc {
			#flag -I/usr/local/include
			#flag $first_existing("@VEXEROOT/thirdparty/tcc/lib/libgc.a", "/usr/local/lib/libgc-threaded.a", "/usr/lib/libgc-threaded.a")
			#flag -lgc-threaded
		}
		#flag -lpthread
	} $else $if openbsd {
		// Tested on OpenBSD 7.5, with clang, gcc and tcc
		#flag -DGC_BUILTIN_ATOMIC=1
		$if !tinyc {
			#flag -I @VEXEROOT/thirdparty/libgc/include
			#flag @VEXEROOT/thirdparty/libgc/gc.o
		}
		$if tinyc {
			#flag -I/usr/local/include
			#flag $first_existing("/usr/local/lib/libgc.a", "/usr/lib/libgc.a")
			#flag -lgc
		}
		#flag -lpthread
	} $else $if windows {
		#flag -DGC_NOT_DLL=1
		#flag -DGC_WIN32_THREADS=1
		#flag -luser32
		$if tinyc {
			#flag -DGC_BUILTIN_ATOMIC=1
			#flag -I @VEXEROOT/thirdparty/libgc/include
			$if !use_bundled_libgc ? {
				#flag @VEXEROOT/thirdparty/tcc/lib/libgc.a
			}
		} $else $if msvc {
			// Build libatomic_ops
			#flag @VEXEROOT/thirdparty/libatomic_ops/atomic_ops.o
			#flag -I  @VEXEROOT/thirdparty/libatomic_ops

			#flag -I @VEXEROOT/thirdparty/libgc/include
			#flag @VEXEROOT/thirdparty/libgc/gc.o
		} $else {
			#flag -DGC_BUILTIN_ATOMIC=1
			#flag -I @VEXEROOT/thirdparty/libgc/include
			#flag @VEXEROOT/thirdparty/libgc/gc.o
		}
	} $else $if $pkgconfig('bdw-gc') {
		#flag -DGC_BUILTIN_ATOMIC=1
		#pkgconfig bdw-gc
	} $else {
		#flag -DGC_BUILTIN_ATOMIC=1
		#flag -lgc
	}
}

$if gcboehm_leak ? {
	#flag -DGC_DEBUG=1
}

#include <gc.h>

// #include <gc/gc_mark.h>

// replacements for `malloc()/calloc()`, `realloc()` and `free()`
// for use with Boehm-GC
// Do not use them manually. They are automatically chosen when
// compiled with `-gc boehm` or `-gc boehm_leak`.
fn C.GC_MALLOC(n usize) voidptr

fn C.GC_MALLOC_ATOMIC(n usize) voidptr

fn C.GC_MALLOC_UNCOLLECTABLE(n usize) voidptr

fn C.GC_REALLOC(ptr voidptr, n usize) voidptr

fn C.GC_FREE(ptr voidptr)

fn C.GC_memalign(align isize, size isize) voidptr

// explicitly perform garbage collection now! Garbage collections
// are done automatically when needed, so this function is hardly needed
fn C.GC_gcollect()

// functions to temporarily suspend/resume garbage collection
fn C.GC_disable()

fn C.GC_enable()

// returns non-zero if GC is disabled
fn C.GC_is_disabled() int

// protect memory block from being freed before this call
fn C.GC_reachable_here(voidptr)

// gc_is_enabled() returns true, if the GC is enabled at runtime.
// See also gc_disable() and gc_enable().
pub fn gc_is_enabled() bool {
	return 0 == C.GC_is_disabled()
}

// gc_collect explicitly performs a single garbage collection run.
// Note, that garbage collections, are done automatically, when needed in most cases,
// so usually you should NOT need to call gc_collect() often.
// Note that gc_collect() is a NOP with `-gc none`.
pub fn gc_collect() {
	C.GC_gcollect()
}

// gc_enable explicitly enables the GC.
// Note, that garbage collections are done automatically, when needed in most cases,
// and also that by default the GC is on, so you do not need to enable it.
// See also gc_disable() and gc_collect().
// Note that gc_enable() is a NOP with `-gc none`.
pub fn gc_enable() {
	C.GC_enable()
}

// gc_disable explicitly disables the GC. Do not forget to enable it again by calling gc_enable(), when your program is otherwise idle, and can afford it.
// See also gc_enable() and gc_collect().
// Note that gc_disable() is a NOP with `-gc none`.
pub fn gc_disable() {
	C.GC_disable()
}

// gc_check_leaks is useful for leak detection (it does an explicit garbage collections, but only when a program is compiled with `-gc boehm_leak`).
pub fn gc_check_leaks() {
	$if gcboehm_leak ? {
		C.GC_gcollect()
	}
}

fn C.GC_get_heap_usage_safe(pheap_size &usize, pfree_bytes &usize, punmapped_bytes &usize, pbytes_since_gc &usize,
	ptotal_bytes &usize)
fn C.GC_get_memory_use() usize

pub struct C.GC_stack_base {
	mem_base voidptr
	// reg_base voidptr
}

fn C.GC_get_stack_base(voidptr) int
fn C.GC_register_my_thread(voidptr) int
fn C.GC_unregister_my_thread() int

// fn C.GC_get_my_stackbottom(voidptr) voidptr
fn C.GC_set_stackbottom(voidptr, voidptr)

// fn C.GC_push_all_stacks()

fn C.GC_add_roots(voidptr, voidptr)
fn C.GC_remove_roots(voidptr, voidptr)

// fn C.GC_get_push_other_roots() fn()
// fn C.GC_set_push_other_roots(fn())

fn C.GC_get_sp_corrector() fn (voidptr, voidptr)
fn C.GC_set_sp_corrector(fn (voidptr, voidptr))

// FnGC_WarnCB is the type of the callback, that you have to define, if you want to redirect GC warnings and handle them.
// Note: GC warnings are silenced by default. Use gc_set_warn_proc/1 to set your own handler for them.
pub type FnGC_WarnCB = fn (msg &char, arg usize)

fn C.GC_get_warn_proc() FnGC_WarnCB
fn C.GC_set_warn_proc(cb FnGC_WarnCB)

// gc_get_warn_proc returns the current callback fn, that will be used for printing GC warnings.
pub fn gc_get_warn_proc() FnGC_WarnCB {
	return C.GC_get_warn_proc()
}

// gc_set_warn_proc sets the callback fn, that will be used for printing GC warnings.
pub fn gc_set_warn_proc(cb FnGC_WarnCB) {
	C.GC_set_warn_proc(cb)
}

// used by builtin_init:
fn internal_gc_warn_proc_none(msg &char, arg usize) {}

///////////// module builtin

@[markused]
fn builtin_init() {
	$if gcboehm ? {
		$if !gc_warn_on_stderr ? {
			gc_set_warn_proc(internal_gc_warn_proc_none)
		}
	}
}

fn break_if_debugger_attached() {
	unsafe {
		mut ptr := &voidptr(0)
		*ptr = nil
	}
}

@[noreturn]
pub fn panic_lasterr(base string) {
	// TODO: use strerror_r and errno
	panic(base + ' unknown')
}

///////////// module builtin

fn print_libbacktrace(frames_to_skip int) {
}

@[noinline]
fn eprint_libbacktrace(frames_to_skip int) {
}

///////////// module builtin

@[typedef]
pub struct C.FILE {}

// <string.h>
fn C.memcpy(dest voidptr, const_src voidptr, n usize) voidptr

fn C.memcmp(const_s1 voidptr, const_s2 voidptr, n usize) int

fn C.memmove(dest voidptr, const_src voidptr, n usize) voidptr

fn C.memset(str voidptr, c int, n usize) voidptr

@[trusted]
fn C.calloc(int, int) &u8

fn C.atoi(&char) int

fn C.malloc(int) &u8

fn C.realloc(a &u8, b int) &u8

fn C.free(ptr voidptr)

fn C.mmap(addr_length int, length isize, prot int, flags int, fd int, offset u64) voidptr
fn C.mprotect(addr_length int, len isize, prot int) int

fn C.aligned_alloc(align isize, size isize) voidptr

// windows aligned memory functions
fn C._aligned_malloc(size isize, align isize) voidptr
fn C._aligned_free(voidptr)
fn C._aligned_realloc(voidptr, size isize, align isize) voidptr
fn C._aligned_offset_malloc(size isize, align isize, offset isize) voidptr
fn C._aligned_offset_realloc(voidptr, size isize, align isize, offset isize) voidptr
fn C._aligned_msize(voidptr, align isize, offset isize) isize
fn C._aligned_recalloc(voidptr, num isize, size isize, align isize) voidptr

fn C.VirtualAlloc(voidptr, isize, u32, u32) voidptr
fn C.VirtualProtect(voidptr, isize, u32, &u32) bool

@[noreturn; trusted]
fn C.exit(code int)

fn C.qsort(base voidptr, items usize, item_size usize, cb C.qsort_callback_func)

fn C.strlen(s &char) int

@[trusted]
fn C.isdigit(c int) bool

// stdio.h
fn C.popen(c &char, t &char) voidptr

// <libproc.h>
fn C.proc_pidpath(int, voidptr, int) int

fn C.realpath(const_path &char, resolved_path &char) &char

// fn C.chmod(byteptr, mode_t) int
fn C.chmod(path &char, mode u32) int

fn C.printf(const_format &char, opt ...voidptr) int
fn C.dprintf(fd int, const_format &char, opt ...voidptr) int
fn C.fprintf(fstream &C.FILE, const_format &char, opt ...voidptr) int
fn C.sprintf(str &char, const_format &char, opt ...voidptr) int
fn C.snprintf(str &char, size usize, const_format &char, opt ...voidptr) int
fn C.wprintf(const_format &u16, opt ...voidptr) int

// used by Android for (e)println to output to the Android log system / logcat
pub fn C.android_print(fstream voidptr, format &char, opt ...voidptr)

fn C.sscanf(str &char, const_format &char, opt ...voidptr) int
fn C.scanf(const_format &char, opt ...voidptr) int

fn C.puts(msg &char) int
@[trusted]
fn C.abs(f64) f64

fn C.fputs(msg &char, fstream &C.FILE) int

fn C.fflush(fstream &C.FILE) int

// TODO: define args in these functions
fn C.fseek(stream &C.FILE, offset int, whence int) int

fn C.fopen(filename &char, mode &char) &C.FILE

fn C.fileno(&C.FILE) int

fn C.fread(ptr voidptr, item_size usize, items usize, stream &C.FILE) usize

fn C.fwrite(ptr voidptr, item_size usize, items usize, stream &C.FILE) usize

fn C.fclose(stream &C.FILE) int

fn C.pclose(stream &C.FILE) int

fn C.open(path &char, flags int, mode ...int) int
fn C.close(fd int) int

fn C.strrchr(s &char, c int) &char
fn C.strchr(s &char, c int) &char

// process execution, os.process:
@[trusted]
fn C.GetCurrentProcessId() u32
@[trusted]
fn C._getpid() int
@[trusted]
fn C.getpid() int

@[trusted]
fn C.GetCurrentThreadId() u32
@[trusted]
fn C.gettid() u32

@[trusted]
fn C.getuid() int

@[trusted]
fn C.geteuid() int

fn C.system(cmd &char) int

fn C.posix_spawn(child_pid &int, path &char, file_actions voidptr, attrp voidptr, argv &&char, envp &&char) int

fn C.posix_spawnp(child_pid &int, exefile &char, file_actions voidptr, attrp voidptr, argv &&char, envp &&char) int

fn C.execve(cmd_path &char, args voidptr, envs voidptr) int

fn C.execvp(cmd_path &char, args &&char) int

fn C._execve(cmd_path &char, args voidptr, envs voidptr) int

fn C._execvp(cmd_path &char, args &&char) int

fn C.strcmp(s1 &char, s2 &char) int

@[trusted]
fn C.fork() int

fn C.wait(status &int) int

fn C.waitpid(pid int, status &int, options int) int

@[trusted]
fn C.kill(pid int, sig int) int

fn C.setenv(&char, &char, int) int

fn C.unsetenv(&char) int

fn C.access(path &char, amode int) int

fn C.remove(filename &char) int

fn C.rmdir(path &char) int

fn C.chdir(path &char) int

fn C.rewind(stream &C.FILE) int

fn C.ftell(&C.FILE) isize

fn C.stat(&char, voidptr) int

fn C.lstat(path &char, buf &C.stat) int

fn C.statvfs(const_path &char, buf &C.statvfs) int

fn C.rename(old_filename &char, new_filename &char) int

fn C.fgets(str &char, n int, stream &C.FILE) int

fn C.fgetpos(&C.FILE, voidptr) int

@[trusted]
fn C.sigemptyset() int

fn C.getcwd(buf &char, size usize) &char

@[trusted]
fn C.mktime() int

fn C.gettimeofday(tv &C.timeval, tz &C.timezone) int

@[trusted]
fn C.sleep(seconds u32) u32

// fn C.usleep(usec useconds_t) int
@[trusted]
fn C.usleep(usec u32) int

@[typedef]
pub struct C.DIR {
}

fn C.opendir(&char) &C.DIR

fn C.closedir(dirp &C.DIR) int

// fn C.mkdir(path &char, mode mode_t) int
fn C.mkdir(path &char, mode u32) int

// C.rand returns a pseudorandom integer from 0 (inclusive) to C.RAND_MAX (exclusive)
@[trusted]
fn C.rand() int

// C.srand seeds the internal PRNG with the given value.
@[trusted]
fn C.srand(seed u32)

fn C.atof(str &char) f64

@[trusted]
fn C.tolower(c int) int

@[trusted]
fn C.toupper(c int) int

@[trusted]
fn C.isspace(c int) int

fn C.strchr(s &char, c int) &char

@[trusted]
fn C.getchar() int

@[trusted]
fn C.putchar(int) int

fn C.strdup(s &char) &char

fn C.strncasecmp(s &char, s2 &char, n int) int

fn C.strcasecmp(s &char, s2 &char) int

fn C.strncmp(s &char, s2 &char, n int) int

@[trusted]
fn C.strerror(int) &char

@[trusted]
fn C.WIFEXITED(status int) bool

@[trusted]
fn C.WEXITSTATUS(status int) int

@[trusted]
fn C.WIFSIGNALED(status int) bool

@[trusted]
fn C.WTERMSIG(status int) int

@[trusted]
fn C.isatty(fd int) int

fn C.syscall(number int, va ...voidptr) int

fn C.sysctl(name &int, namelen u32, oldp voidptr, oldlenp voidptr, newp voidptr, newlen usize) int

@[trusted]
fn C._fileno(int) int

pub type C.intptr_t = voidptr

fn C._get_osfhandle(fd int) C.intptr_t

fn C.GetModuleFileName(hModule voidptr, lpFilename &u16, nSize u32) u32

fn C.GetModuleFileNameW(hModule voidptr, lpFilename &u16, nSize u32) u32

fn C.CreateFile(lpFilename &u16, dwDesiredAccess u32, dwShareMode u32, lpSecurityAttributes &u16, dwCreationDisposition u32,
	dwFlagsAndAttributes u32, hTemplateFile voidptr) voidptr

fn C.CreateFileW(lpFilename &u16, dwDesiredAccess u32, dwShareMode u32, lpSecurityAttributes &u16, dwCreationDisposition u32,
	dwFlagsAndAttributes u32, hTemplateFile voidptr) voidptr

fn C.GetFinalPathNameByHandleW(hFile voidptr, lpFilePath &u16, nSize u32, dwFlags u32) u32

fn C.CreatePipe(hReadPipe &voidptr, hWritePipe &voidptr, lpPipeAttributes voidptr, nSize u32) bool

fn C.SetHandleInformation(hObject voidptr, dwMask u32, dw_flags u32) bool

fn C.ExpandEnvironmentStringsW(lpSrc &u16, lpDst &u16, nSize u32) u32

fn C.GetComputerNameW(&u16, &u32) bool

fn C.GetUserNameW(&u16, &u32) bool

@[trusted]
fn C.SendMessageTimeout() isize

fn C.SendMessageTimeoutW(hWnd voidptr, msg u32, wParam &u16, lParam &u32, fuFlags u32, uTimeout u32, lpdwResult &u64) isize

fn C.CreateProcessW(lpApplicationName &u16, lpCommandLine &u16, lpProcessAttributes voidptr, lpThreadAttributes voidptr,
	bInheritHandles bool, dwCreationFlags u32, lpEnvironment voidptr, lpCurrentDirectory &u16, lpStartupInfo voidptr,
	lpProcessInformation voidptr) bool

fn C.ReadFile(hFile voidptr, lpBuffer voidptr, nNumberOfBytesToRead u32, lpNumberOfBytesRead &u32, lpOverlapped voidptr) bool

fn C.GetFileAttributesW(lpFileName &u8) u32

fn C.RegQueryValueEx(hKey voidptr, lpValueName &u16, lp_reserved &u32, lpType &u32, lpData &u8, lpcbData &u32) int

fn C.RegQueryValueExW(hKey voidptr, lpValueName &u16, lp_reserved &u32, lpType &u32, lpData &u8, lpcbData &u32) int

fn C.RegOpenKeyEx(hKey voidptr, lpSubKey &u16, ulOptions u32, samDesired u32, phkResult voidptr) int

fn C.RegOpenKeyExW(hKey voidptr, lpSubKey &u16, ulOptions u32, samDesired u32, phkResult voidptr) int

fn C.RegSetValueEx(hKey voidptr, lpValueName &u16, dwType u32, lpData &u16, cbData u32) int

fn C.RegSetValueExW(hKey voidptr, lpValueName &u16, reserved u32, dwType u32, const_lpData &u8, cbData u32) int

fn C.RegCloseKey(hKey voidptr) int

fn C.RemoveDirectory(lpPathName &u16) bool

fn C.RemoveDirectoryW(lpPathName &u16) bool

fn C.GetStdHandle(u32) voidptr

fn C.SetConsoleMode(voidptr, u32) bool

fn C.GetConsoleMode(voidptr, &u32) bool

@[trusted]
fn C.GetCurrentProcessId() u32

// fn C.setbuf()
fn C.setbuf(voidptr, &char)

fn C.SymCleanup(hProcess voidptr)

fn C.MultiByteToWideChar(codePage u32, dwFlags u32, lpMultiMyteStr &char, cbMultiByte int, lpWideCharStr &u16,
	cchWideChar int) int

fn C.wcslen(str voidptr) usize

fn C.WideCharToMultiByte(codePage u32, dwFlags u32, lpWideCharStr &u16, cchWideChar int, lpMultiByteStr &char,
	cbMultiByte int, lpDefaultChar &char, lpUsedDefaultChar &int) int

fn C._wstat(path &u16, buffer &C._stat) int

fn C._wrename(oldname &u16, newname &u16) int

fn C._wfopen(filename &u16, mode &u16) voidptr

fn C._wpopen(command &u16, mode &u16) voidptr

fn C._pclose(stream &C.FILE) int

fn C._wsystem(command &u16) int

fn C._wgetenv(varname &u16) voidptr

fn C._putenv(envstring &char) int
fn C._wputenv(envstring &u16) int

fn C._waccess(path &u16, mode int) int

fn C._wremove(path &u16) int

fn C.ReadConsole(in_input_handle voidptr, out_buffer voidptr, in_chars_to_read u32, out_read_chars &u32,
	in_input_control voidptr) bool

fn C.WriteConsole() voidptr

fn C.WriteFile(hFile voidptr, lpBuffer voidptr, nNumberOfBytesToWrite u32, lpNumberOfBytesWritten &u32, lpOverlapped voidptr) bool

fn C._wchdir(dirname &u16) int

fn C._wgetcwd(buffer &u16, maxlen int) int

fn C._fullpath() int

fn C.GetFullPathName(voidptr, u32, voidptr, voidptr) u32

@[trusted]
fn C.GetCommandLine() voidptr

fn C.LocalFree(voidptr)

fn C.FindFirstFileW(lpFileName &u16, lpFindFileData voidptr) voidptr

fn C.FindFirstFile(lpFileName &u8, lpFindFileData voidptr) voidptr

fn C.FindNextFile(hFindFile voidptr, lpFindFileData voidptr) int

fn C.FindClose(hFindFile voidptr)

// macro
fn C.MAKELANGID(lgid voidptr, srtid voidptr) int

fn C.FormatMessageW(dwFlags u32, lpSource voidptr, dwMessageId u32, dwLanguageId u32, lpBuffer voidptr,
	nSize u32, arguments ...voidptr) u32

fn C.CloseHandle(voidptr) int

fn C.GetExitCodeProcess(hProcess voidptr, lpExitCode &u32)

@[trusted]
fn C.GetTickCount() i64

@[trusted]
fn C.Sleep(dwMilliseconds u32)

fn C.WSAStartup(u16, &voidptr) int

@[trusted]
fn C.WSAGetLastError() int

fn C.closesocket(int) int

fn C.vschannel_init(&C.TlsContext)

fn C.request(&C.TlsContext, int, &u16, &u8, u32, &&u8, fn (voidptr, isize) voidptr) int

fn C.vschannel_cleanup(&C.TlsContext)

fn C.URLDownloadToFile(int, &u16, &u16, int, int)

@[trusted]
fn C.GetLastError() u32

fn C.CreateDirectory(&u8, int) bool

// win crypto
fn C.BCryptGenRandom(int, voidptr, int, int) int

// win synchronization
fn C.CreateMutex(int, bool, &u8) voidptr

fn C.WaitForSingleObject(voidptr, int) int

fn C.ReleaseMutex(voidptr) bool

fn C.CreateEvent(int, bool, bool, &u8) voidptr

fn C.SetEvent(voidptr) int

fn C.CreateSemaphore(voidptr, int, int, voidptr) voidptr

fn C.ReleaseSemaphore(voidptr, int, voidptr) voidptr

fn C.InitializeSRWLock(voidptr)

fn C.AcquireSRWLockShared(voidptr)

fn C.AcquireSRWLockExclusive(voidptr)

fn C.ReleaseSRWLockShared(voidptr)

fn C.ReleaseSRWLockExclusive(voidptr)

// pthread.h
fn C.pthread_self() usize
fn C.pthread_mutex_init(voidptr, voidptr) int

fn C.pthread_mutex_lock(voidptr) int

fn C.pthread_mutex_unlock(voidptr) int

fn C.pthread_mutex_destroy(voidptr) int

fn C.pthread_rwlockattr_init(voidptr) int

fn C.pthread_rwlockattr_setkind_np(voidptr, int) int

fn C.pthread_rwlockattr_setpshared(voidptr, int) int

fn C.pthread_rwlock_init(voidptr, voidptr) int

fn C.pthread_rwlock_rdlock(voidptr) int

fn C.pthread_rwlock_wrlock(voidptr) int

fn C.pthread_rwlock_unlock(voidptr) int

fn C.pthread_condattr_init(voidptr) int

fn C.pthread_condattr_setpshared(voidptr, int) int

fn C.pthread_condattr_destroy(voidptr) int

fn C.pthread_cond_init(voidptr, voidptr) int

fn C.pthread_cond_signal(voidptr) int

fn C.pthread_cond_wait(voidptr, voidptr) int

fn C.pthread_cond_timedwait(voidptr, voidptr, voidptr) int

fn C.pthread_cond_destroy(voidptr) int

fn C.sem_init(voidptr, int, u32) int

fn C.sem_post(voidptr) int

fn C.sem_wait(voidptr) int

fn C.sem_trywait(voidptr) int

fn C.sem_timedwait(voidptr, voidptr) int

fn C.sem_destroy(voidptr) int

// MacOS semaphore functions
@[trusted]
fn C.dispatch_semaphore_create(i64) voidptr

fn C.dispatch_semaphore_signal(voidptr) i64

fn C.dispatch_semaphore_wait(voidptr, u64) i64

@[trusted]
fn C.dispatch_time(u64, i64) u64

fn C.dispatch_release(voidptr)

// file descriptor based reading/writing
fn C.read(fd int, buf voidptr, count usize) int

fn C.write(fd int, buf voidptr, count usize) int

fn C.close(fd int) int

// pipes
fn C.pipe(pipefds &int) int

fn C.dup2(oldfd int, newfd int) int

// used by gl, stbi, freetype
fn C.glTexImage2D()

// used by ios for println
fn C.WrappedNSLog(str &u8)

// absolute value
@[trusted]
fn C.abs(number int) int

fn C.GetDiskFreeSpaceExA(const_path &char, free_bytes_available_to_caller &u64, total_number_of_bytes &u64, total_number_of_free_bytes &u64) bool

fn C.GetNativeSystemInfo(voidptr)

fn C.sysconf(name int) int

// C.SYSTEM_INFO contains information about the current computer system. This includes the architecture and type of the processor, the number of processors in the system, the page size, and other such information.
@[typedef]
pub struct C.SYSTEM_INFO {
	// workaround: v doesn't support a truely C anon union/struct here
	// union {
	dwOemId u32
	// struct {
	wProcessorArchitecture u16
	wReserved              u16
	//	}
	//}
	dwPageSize                  u32
	lpMinimumApplicationAddress voidptr
	lpMaximumApplicationAddress voidptr
	dwActiveProcessorMask       u32
	dwNumberOfProcessors        u32
	dwProcessorType             u32
	dwAllocationGranularity     u32
	wProcessorLevel             u16
	wProcessorRevision          u16
}

fn C.GetSystemInfo(&C.SYSTEM_INFO)

@[typedef]
pub struct C.SRWLOCK {}

///////////// module builtin

// vstrlen returns the V length of the C string `s` (0 terminator is not counted).
// The C string is expected to be a &u8 pointer.
@[inline; unsafe]
pub fn vstrlen(s &u8) int {
	return unsafe { C.strlen(&char(s)) }
}

// vstrlen_char returns the V length of the C string `s` (0 terminator is not counted).
// The C string is expected to be a &char pointer.
@[inline; unsafe]
pub fn vstrlen_char(s &char) int {
	return unsafe { C.strlen(s) }
}

// vmemcpy copies n bytes from memory area src to memory area dest.
// The memory areas *MUST NOT OVERLAP*.  Use vmemmove, if the memory
// areas do overlap. vmemcpy returns a pointer to `dest`.
@[inline; unsafe]
pub fn vmemcpy(dest voidptr, const_src voidptr, n isize) voidptr {
	$if trace_vmemcpy ? {
		C.fprintf(C.stderr, c'vmemcpy dest: %p src: %p n: %6ld\n', dest, const_src, n)
	}
	$if trace_vmemcpy_nulls ? {
		if dest == unsafe { 0 } || const_src == unsafe { 0 } {
			C.fprintf(C.stderr, c'vmemcpy null pointers passed, dest: %p src: %p n: %6ld\n',
				dest, const_src, n)
			print_backtrace()
		}
	}
	if n == 0 {
		return dest
	}
	unsafe {
		return C.memcpy(dest, const_src, n)
	}
}

// vmemmove copies n bytes from memory area `src` to memory area `dest`.
// The memory areas *MAY* overlap: copying takes place as though the bytes
// in `src` are first copied into a temporary array that does not overlap
// `src` or `dest`, and the bytes are then copied from the temporary array
// to `dest`. vmemmove returns a pointer to `dest`.
@[inline; unsafe]
pub fn vmemmove(dest voidptr, const_src voidptr, n isize) voidptr {
	$if trace_vmemmove ? {
		C.fprintf(C.stderr, c'vmemmove dest: %p src: %p n: %6ld\n', dest, const_src, n)
	}
	if n == 0 {
		return dest
	}
	unsafe {
		return C.memmove(dest, const_src, n)
	}
}

// vmemcmp compares the first n bytes (each interpreted as unsigned char)
// of the memory areas s1 and s2. It returns an integer less than, equal to,
// or greater than zero, if the first n bytes of s1 is found, respectively,
// to be less than, to match, or be greater than the first n bytes of s2.
// For a nonzero return value, the sign is determined by the sign of the
// difference between the first pair of bytes (interpreted as unsigned char)
// that differ in s1 and s2.
// If n is zero, the return value is zero.
// Do NOT use vmemcmp to compare security critical data, such as cryptographic
// secrets, because the required CPU time depends on the number of equal bytes.
// You should use a function that performs comparisons in constant time for
// this.
@[inline; unsafe]
pub fn vmemcmp(const_s1 voidptr, const_s2 voidptr, n isize) int {
	$if trace_vmemcmp ? {
		C.fprintf(C.stderr, c'vmemcmp s1: %p s2: %p n: %6ld\n', const_s1, const_s2, n)
	}
	if n == 0 {
		return 0
	}
	unsafe {
		return C.memcmp(const_s1, const_s2, n)
	}
}

// vmemset fills the first `n` bytes of the memory area pointed to by `s`,
// with the constant byte `c`. It returns a pointer to the memory area `s`.
@[inline; unsafe]
pub fn vmemset(s voidptr, c int, n isize) voidptr {
	$if trace_vmemset ? {
		C.fprintf(C.stderr, c'vmemset s: %p c: %d n: %6ld\n', s, c, n)
	}
	$if trace_vmemset_nulls ? {
		if s == unsafe { 0 } {
			C.fprintf(C.stderr, c'vmemset null pointers passed s: %p, c: %6d, n: %6ld\n',
				s, c, n)
			print_backtrace()
		}
	}
	if n == 0 {
		return s
	}
	unsafe {
		return C.memset(s, c, n)
	}
}

type FnSortCB = fn (const_a voidptr, const_b voidptr) int

@[inline; unsafe]
fn vqsort(base voidptr, nmemb usize, size usize, sort_cb FnSortCB) {
	$if trace_vqsort ? {
		C.fprintf(C.stderr, c'vqsort base: %p, nmemb: %6uld, size: %6uld, sort_cb: %p\n',
			base, nmemb, size, sort_cb)
	}
	if nmemb == 0 {
		return
	}
	$if trace_vqsort_nulls ? {
		if base == unsafe { 0 } || u64(sort_cb) == 0 {
			C.fprintf(C.stderr, c'vqsort null pointers passed base: %p, nmemb: %6uld, size: %6uld, sort_cb: %p\n',
				base, nmemb, size, sort_cb)
			print_backtrace()
		}
	}
	C.qsort(base, nmemb, size, voidptr(sort_cb))
}

///////////// module builtin

// ChanState describes the result of an attempted channel transaction.
pub enum ChanState {
	success
	not_ready // push()/pop() would have to wait, but no_block was requested
	closed
}

/*
The following methods are only stubs.
The real implementation is in `vlib/sync/channels.v`
*/

// close closes the channel for further push transactions.
// closed channels cannot be pushed to, however they can be popped
// from as long as there is still objects available in the channel buffer.
pub fn (ch chan) close() {}

// try_pop returns `ChanState.success` if an object is popped from the channel.
// try_pop effectively pops from the channel without waiting for objects to become available.
// Both the test and pop transaction is done atomically.
pub fn (ch chan) try_pop(obj voidptr) ChanState {
	return .success
}

// try_push returns `ChanState.success` if the object is pushed to the channel.
// try_push effectively both push and test if the transaction `ch <- a` succeeded.
// Both the test and push transaction is done atomically.
pub fn (ch chan) try_push(obj voidptr) ChanState {
	return .success
}

// IError holds information about an error instance.
pub interface IError {
	msg() string
	code() int
}

struct _result {
	is_error bool
	err      IError = none__
	// Data is trailing after err
	// and is not included in here but in the
	// derived Result_xxx types
}

fn _result_ok(data voidptr, mut res _result, size int) {
	unsafe {
		*res = _result{}
		// use err to get the end of ResultBase and then memcpy into it
		vmemcpy(&u8(&res.err) + sizeof(IError), data, size)
	}
}

// str returns the message of IError.
pub fn (err IError) str() string {
	return match err {
		None__ {
			'none'
		}
		Error {
			err.msg()
		}
		MessageError {
			(*err).str()
		}
		else {
			'${err.type_name()}: ${err.msg()}'
		}
	}
}

// Error is the empty default implementation of `IError`.
pub struct Error {}

pub fn (err Error) msg() string {
	return ''
}

pub fn (err Error) code() int {
	return 0
}

// MessageError is the default implementation of the `IError` interface that is returned by the `error()` function.
struct MessageError {
pub:
	msg  string
	code int
}

// str returns both the .msg and .code of MessageError, when .code is != 0 .
pub fn (err MessageError) str() string {
	if err.code > 0 {
		return '${err.msg}; code: ${err.code}'
	}
	return err.msg
}

// msg returns only the message of MessageError.
pub fn (err MessageError) msg() string {
	return err.msg
}

// code returns only the code of MessageError.
pub fn (err MessageError) code() int {
	return err.code
}

@[unsafe]
pub fn (err &MessageError) free() {
	unsafe { err.msg.free() }
}

@[if trace_error ?]
fn trace_error(x string) {
	eprintln('> ${@FN} | ${x}')
}

// error returns a default error instance containing the error given in `message`.
// Example: f := fn (ouch bool) ! { if ouch { return error('an error occurred') } }; f(false)!
@[inline]
pub fn error(message string) IError {
	trace_error(message)
	return &MessageError{
		msg: message
	}
}

// error_with_code returns a default error instance containing the given `message` and error `code`.
// Example: f := fn (ouch bool) ! { if ouch { return error_with_code('an error occurred', 1) } }; f(false)!
@[inline]
pub fn error_with_code(message string, code int) IError {
	trace_error('${message} | code: ${code}')
	return &MessageError{
		msg:  message
		code: code
	}
}

// Option is the base of V's internal option return system.
struct Option {
	state u8 // 0 - ok; 2 - none; 1 - ?
	err   IError = none__
	// Data is trailing after err
	// and is not included in here but in the
	// derived Option_xxx types
}

// option is the base of V's internal option return system.
struct _option {
	state u8
	err   IError = none__
	// Data is trailing after err
	// and is not included in here but in the
	// derived _option_xxx types
}

fn _option_none(data voidptr, mut option _option, size int) {
	unsafe {
		*option = _option{
			state: 2
		}
		// use err to get the end of OptionBase and then memcpy into it
		vmemcpy(&u8(&option.err) + sizeof(IError), data, size)
	}
}

fn _option_ok(data voidptr, mut option _option, size int) {
	unsafe {
		*option = _option{}
		// use err to get the end of OptionBase and then memcpy into it
		vmemcpy(&u8(&option.err) + sizeof(IError), data, size)
	}
}

fn _option_clone(current &_option, mut option _option, size int) {
	unsafe {
		*option = _option{
			state: current.state
			err:   current.err
		}
		// use err to get the end of OptionBase and then memcpy into it
		vmemcpy(&u8(&option.err) + sizeof(IError), &u8(&current.err) + sizeof(IError),
			size)
	}
}

//

const none__ = IError(&None__{})

struct None__ {
	Error
}

fn (_ None__) str() string {
	return 'none'
}

// str for none, returns 'none'
pub fn (_ none) str() string {
	return 'none'
}

///////////// module builtin

// input_character gives back a single character, read from the standard input.
// It returns -1 on error (when the input is finished (EOF), on a broken pipe etc).
pub fn input_character() int {
	mut ch := 0
	$if freestanding {
		// TODO
		return -1
	} $else $if vinix {
		// TODO
		return -1
	} $else {
		ch = C.getchar()
		if ch == C.EOF {
			return -1
		}
	}
	return ch
}

// print_character writes the single character `ch` to the standard output.
// It returns -1 on error (when the output is closed, on a broken pipe, etc).
// Note: this function does not allocate memory, unlike `print(ch.ascii_str())`
// which does, and is thus cheaper to call, which is important, if you have
// to output many characters one by one. If you instead want to print entire
// strings at once, use `print(your_string)`.
pub fn print_character(ch u8) int {
	$if android && !termux {
		C.android_print(C.stdout, c'%.*s', 1, voidptr(&ch))
	} $else $if freestanding {
		bare_print(voidptr(&ch), u64(1))
	} $else $if vinix {
		// TODO
		return 0
	} $else {
		x := C.putchar(ch)
		if x == C.EOF {
			return -1
		}
	}
	return ch
}

///////////// module builtin

// str returns a string representation of the given `f64` in a suitable notation.
@[inline]
pub fn (x f64) str() string {
	unsafe {
		f := strconv.Float64u{
			f: x
		}
		if f.u == strconv.double_minus_zero {
			return '-0.0'
		}
		if f.u == strconv.double_plus_zero {
			return '0.0'
		}
	}
	abs_x := f64_abs(x)
	if abs_x >= 0.0001 && abs_x < 1.0e6 {
		return strconv.f64_to_str_l(x)
	} else {
		return strconv.ftoa_64(x)
	}
}

// strg return a `f64` as `string` in "g" printf format.
@[inline]
pub fn (x f64) strg() string {
	if x == 0 {
		return '0.0'
	}
	abs_x := f64_abs(x)
	if abs_x >= 0.0001 && abs_x < 1.0e6 {
		return strconv.f64_to_str_l_with_dot(x)
	} else {
		return strconv.ftoa_64(x)
	}
}

// str returns the value of the `float_literal` as a `string`.
@[inline]
pub fn (d float_literal) str() string {
	return f64(d).str()
}

// strsci returns the `f64` as a `string` in scientific notation with `digit_num` decimals displayed, max 17 digits.
// Example: assert f64(1.234).strsci(3) == '1.234e+00'
@[inline]
pub fn (x f64) strsci(digit_num int) string {
	mut n_digit := digit_num
	if n_digit < 1 {
		n_digit = 1
	} else if n_digit > 17 {
		n_digit = 17
	}
	return strconv.f64_to_str(x, n_digit)
}

// strlong returns a decimal notation of the `f64` as a `string`.
// Example: assert f64(1.23456).strlong() == '1.23456'
@[inline]
pub fn (x f64) strlong() string {
	return strconv.f64_to_str_l(x)
}

/*
-----------------------------------
----- f32 to string functions -----
*/
// str returns a `f32` as `string` in suitable notation.
@[inline]
pub fn (x f32) str() string {
	unsafe {
		f := strconv.Float32u{
			f: x
		}
		if f.u == strconv.single_minus_zero {
			return '-0.0'
		}
		if f.u == strconv.single_plus_zero {
			return '0.0'
		}
	}
	abs_x := f32_abs(x)
	if abs_x >= 0.0001 && abs_x < 1.0e6 {
		return strconv.f32_to_str_l(x)
	} else {
		return strconv.ftoa_32(x)
	}
}

// strg return a `f32` as `string` in "g" printf format
@[inline]
pub fn (x f32) strg() string {
	if x == 0 {
		return '0.0'
	}
	abs_x := f32_abs(x)
	if abs_x >= 0.0001 && abs_x < 1.0e6 {
		return strconv.f32_to_str_l_with_dot(x)
	} else {
		return strconv.ftoa_32(x)
	}
}

// strsci returns the `f32` as a `string` in scientific notation with `digit_num` decimals displayed, max 8 digits.
// Example: assert f32(1.234).strsci(3) == '1.234e+00'
@[inline]
pub fn (x f32) strsci(digit_num int) string {
	mut n_digit := digit_num
	if n_digit < 1 {
		n_digit = 1
	} else if n_digit > 8 {
		n_digit = 8
	}
	return strconv.f32_to_str(x, n_digit)
}

// strlong returns a decimal notation of the `f32` as a `string`.
@[inline]
pub fn (x f32) strlong() string {
	return strconv.f32_to_str_l(x)
}

// f32_abs returns the absolute value of `a` as a `f32` value.
// Example: assert f32_abs(-2.0) == 2.0
@[inline]
pub fn f32_abs(a f32) f32 {
	return if a < 0 { -a } else { a }
}

// f64_abs returns the absolute value of `a` as a `f64` value.
// Example: assert f64_abs(-2.0) == f64(2.0)
@[inline]
pub fn f64_abs(a f64) f64 {
	return if a < 0 { -a } else { a }
}

// f32_min returns the smaller `f32` of input `a` and `b`.
// Example: assert f32_min(2.0,3.0) == 2.0
@[inline]
pub fn f32_min(a f32, b f32) f32 {
	return if a < b { a } else { b }
}

// f32_max returns the larger `f32` of input `a` and `b`.
// Example: assert f32_max(2.0,3.0) == 3.0
@[inline]
pub fn f32_max(a f32, b f32) f32 {
	return if a > b { a } else { b }
}

// f64_min returns the smaller `f64` of input `a` and `b`.
// Example: assert f64_min(2.0,3.0) == 2.0
@[inline]
pub fn f64_min(a f64, b f64) f64 {
	return if a < b { a } else { b }
}

// f64_max returns the larger `f64` of input `a` and `b`.
// Example: assert f64_max(2.0,3.0) == 3.0
@[inline]
pub fn f64_max(a f64, b f64) f64 {
	return if a > b { a } else { b }
}

// eq_epsilon returns true if the `f32` is equal to input `b`.
// using an epsilon of typically 1E-5 or higher (backend/compiler dependent).
// Example: assert f32(2.0).eq_epsilon(2.0)
@[inline]
pub fn (a f32) eq_epsilon(b f32) bool {
	hi := f32_max(f32_abs(a), f32_abs(b))
	delta := f32_abs(a - b)
	$if native {
		if hi > f32(1.0) {
			return delta <= hi * (4 * 1.19209290e-7)
		} else {
			return (1 / (4 * 1.19209290e-7)) * delta <= hi
		}
	} $else {
		if hi > f32(1.0) {
			return delta <= hi * (4 * f32(C.FLT_EPSILON))
		} else {
			return (1 / (4 * f32(C.FLT_EPSILON))) * delta <= hi
		}
	}
}

// eq_epsilon returns true if the `f64` is equal to input `b`.
// using an epsilon of typically 1E-9 or higher (backend/compiler dependent).
// Example: assert f64(2.0).eq_epsilon(2.0)
@[inline]
pub fn (a f64) eq_epsilon(b f64) bool {
	hi := f64_max(f64_abs(a), f64_abs(b))
	delta := f64_abs(a - b)
	$if native {
		if hi > 1.0 {
			return delta <= hi * (4 * 2.2204460492503131e-16)
		} else {
			return (1 / (4 * 2.2204460492503131e-16)) * delta <= hi
		}
	} $else {
		if hi > 1.0 {
			return delta <= hi * (4 * f64(C.DBL_EPSILON))
		} else {
			return (1 / (4 * f64(C.DBL_EPSILON))) * delta <= hi
		}
	}
}

///////////// module builtin

// input_rune returns a single rune from the standart input (an unicode codepoint).
// It expects, that the input is utf8 encoded.
// It will return `none` on EOF.
pub fn input_rune() ?rune {
	x := input_character()
	if x <= 0 {
		return none
	}
	char_len := utf8_char_len(u8(x))
	if char_len == 1 {
		return x
	}
	mut b := u8(x)
	b = b << char_len
	mut res := rune(b)
	mut shift := 6 - char_len
	for i := 1; i < char_len; i++ {
		c := rune(input_character())
		res = rune(res) << shift
		res |= c & 63 // 0x3f
		shift = 6
	}
	return res
}

// InputRuneIterator is an iterator over the input runes.
pub struct InputRuneIterator {}

// next returns the next rune from the input stream.
pub fn (mut self InputRuneIterator) next() ?rune {
	return input_rune()
}

// input_rune_iterator returns an iterator to allow for `for i, r in input_rune_iterator() {`.
// When the input stream is closed, the loop will break.
pub fn input_rune_iterator() InputRuneIterator {
	return InputRuneIterator{}
}

///////////// module builtin

pub struct VContext {
	allocator int
}

pub type byte = u8

// ptr_str returns a string with the address of `ptr`.
pub fn ptr_str(ptr voidptr) string {
	buf1 := u64_to_hex_no_leading_zeros(u64(ptr), 16)
	return buf1
}

// str returns the string equivalent of x.
pub fn (x isize) str() string {
	return i64(x).str()
}

// str returns the string equivalent of x.
pub fn (x usize) str() string {
	return u64(x).str()
}

// str returns a string with the address stored in the pointer cptr.
pub fn (cptr &char) str() string {
	return u64(cptr).hex()
}

// digit pairs in reverse order
const digit_pairs = '00102030405060708090011121314151617181910212223242526272829203132333435363738393041424344454647484940515253545556575859506162636465666768696071727374757677787970818283848586878889809192939495969798999'

pub const min_i8 = i8(-128)
pub const max_i8 = i8(127)

pub const min_i16 = i16(-32768)
pub const max_i16 = i16(32767)

pub const min_i32 = i32(-2147483648)
pub const max_i32 = i32(2147483647)

// -9223372036854775808 is wrong, because C compilers parse literal values
// without sign first, and 9223372036854775808 overflows i64, hence the
// consecutive subtraction by 1
pub const min_i64 = i64(-9223372036854775807 - 1)
pub const max_i64 = i64(9223372036854775807)

pub const min_int = $if new_int ? && x64 { int(min_i64) } $else { int(min_i32) }
pub const max_int = $if new_int ? && x64 { int(max_i64) } $else { int(max_i32) }

pub const min_u8 = u8(0)
pub const max_u8 = u8(255)

pub const min_u16 = u16(0)
pub const max_u16 = u16(65535)

pub const min_u32 = u32(0)
pub const max_u32 = u32(4294967295)

pub const min_u64 = u64(0)
pub const max_u64 = u64(18446744073709551615)

// str_l returns the string representation of the integer nn with max chars.
@[direct_array_access; inline]
fn (nn int) str_l(max int) string {
	// This implementation is the quickest with gcc -O2
	unsafe {
		mut n := i64(nn)
		mut d := 0
		if n == 0 {
			return '0'
		}

		// overflow protect
		$if new_int ? && x64 {
			if n == min_i64 {
				return '-9223372036854775808'
			}
		} $else {
			if n == min_i32 {
				return '-2147483648'
			}
		}

		mut is_neg := false
		if n < 0 {
			n = -n
			is_neg = true
		}
		mut index := max
		mut buf := malloc_noscan(max + 1)
		buf[index] = 0
		index--

		for n > 0 {
			n1 := int(n / 100)
			// calculate the digit_pairs start index
			d = int(u32(int(n) - (n1 * 100)) << 1)
			n = n1
			buf[index] = digit_pairs.str[d]
			index--
			d++
			buf[index] = digit_pairs.str[d]
			index--
		}
		index++
		// remove head zero
		if d < 20 {
			index++
		}
		// Prepend - if it's negative
		if is_neg {
			index--
			buf[index] = `-`
		}
		diff := max - index
		vmemmove(buf, voidptr(buf + index), diff + 1)
		return tos(buf, diff)
	}
}

// str returns the value of the `i8` as a `string`.
// Example: assert i8(-2).str() == '-2'
pub fn (n i8) str() string {
	return int(n).str_l(4)
}

// str returns the value of the `i16` as a `string`.
// Example: assert i16(-20).str() == '-20'
pub fn (n i16) str() string {
	return int(n).str_l(6)
}

// str returns the value of the `u16` as a `string`.
// Example: assert u16(20).str() == '20'
pub fn (n u16) str() string {
	return int(n).str_l(6)
}

pub fn (n i32) str() string {
	return int(n).str_l(11)
}

pub fn (nn int) hex_full() string {
	return u64_to_hex(u64(nn), 8)
}

// str returns the value of the `int` as a `string`.
// Example: assert int(-2020).str() == '-2020'
pub fn (n int) str() string {
	$if new_int ? {
		return impl_i64_to_string(n)
	} $else {
		return n.str_l(11)
	}
}

// str returns the value of the `u32` as a `string`.
// Example: assert u32(20000).str() == '20000'
@[direct_array_access; inline]
pub fn (nn u32) str() string {
	unsafe {
		mut n := nn
		mut d := u32(0)
		if n == 0 {
			return '0'
		}
		max := 10
		mut buf := malloc_noscan(max + 1)
		mut index := max
		buf[index] = 0
		index--
		for n > 0 {
			n1 := n / u32(100)
			d = ((n - (n1 * u32(100))) << u32(1))
			n = n1
			buf[index] = digit_pairs[d]
			index--
			d++
			buf[index] = digit_pairs[d]
			index--
		}
		index++
		// remove head zero
		if d < u32(20) {
			index++
		}
		diff := max - index
		vmemmove(buf, voidptr(buf + index), diff + 1)
		return tos(buf, diff)
	}
}

// str returns the value of the `int_literal` as a `string`.
@[inline]
pub fn (n int_literal) str() string {
	return impl_i64_to_string(n)
}

// str returns the value of the `i64` as a `string`.
// Example: assert i64(-200000).str() == '-200000'
@[inline]
pub fn (nn i64) str() string {
	return impl_i64_to_string(nn)
}

@[direct_array_access]
fn impl_i64_to_string(nn i64) string {
	unsafe {
		mut n := nn
		mut d := i64(0)
		if n == 0 {
			return '0'
		} else if n == min_i64 {
			return '-9223372036854775808'
		}
		max := 20
		mut buf := malloc_noscan(max + 1)
		mut is_neg := false
		if n < 0 {
			n = -n
			is_neg = true
		}
		mut index := max
		buf[index] = 0
		index--
		for n > 0 {
			n1 := n / i64(100)
			d = (u32(n - (n1 * i64(100))) << i64(1))
			n = n1
			buf[index] = digit_pairs[d]
			index--
			d++
			buf[index] = digit_pairs[d]
			index--
		}
		index++
		// remove head zero
		if d < i64(20) {
			index++
		}
		// Prepend - if it's negative
		if is_neg {
			index--
			buf[index] = `-`
		}
		diff := max - index
		vmemmove(buf, voidptr(buf + index), diff + 1)
		return tos(buf, diff)
	}
}

// str returns the value of the `u64` as a `string`.
// Example: assert u64(2000000).str() == '2000000'
@[direct_array_access; inline]
pub fn (nn u64) str() string {
	unsafe {
		mut n := nn
		mut d := u64(0)
		if n == 0 {
			return '0'
		}
		max := 20
		mut buf := malloc_noscan(max + 1)
		mut index := max
		buf[index] = 0
		index--
		for n > 0 {
			n1 := n / 100
			d = ((n - (n1 * 100)) << 1)
			n = n1
			buf[index] = digit_pairs[d]
			index--
			d++
			buf[index] = digit_pairs[d]
			index--
		}
		index++
		// remove head zero
		if d < 20 {
			index++
		}
		diff := max - index
		vmemmove(buf, voidptr(buf + index), diff + 1)
		return tos(buf, diff)
	}
}

// str returns the value of the `bool` as a `string`.
// Example: assert (2 > 1).str() == 'true'
pub fn (b bool) str() string {
	if b {
		return 'true'
	}
	return 'false'
}

// u64_to_hex converts the number `nn` to a (zero padded if necessary) hexadecimal `string`.
@[direct_array_access; inline]
fn u64_to_hex(nn u64, len u8) string {
	mut n := nn
	mut buf := [17]u8{}
	buf[len] = 0
	mut i := 0
	for i = len - 1; i >= 0; i-- {
		d := u8(n & 0xF)
		buf[i] = if d < 10 { d + `0` } else { d + 87 }
		n = n >> 4
	}
	return unsafe { tos(memdup(&buf[0], len + 1), len) }
}

// u64_to_hex_no_leading_zeros converts the number `nn` to hexadecimal `string`.
@[direct_array_access; inline]
fn u64_to_hex_no_leading_zeros(nn u64, len u8) string {
	mut n := nn
	mut buf := [17]u8{}
	buf[len] = 0
	mut i := 0
	for i = len - 1; i >= 0; i-- {
		d := u8(n & 0xF)
		buf[i] = if d < 10 { d + `0` } else { d + 87 }
		n = n >> 4
		if n == 0 {
			break
		}
	}
	res_len := len - i
	return unsafe { tos(memdup(&buf[i], res_len + 1), res_len) }
}

// hex returns the value of the `byte` as a hexadecimal `string`.
// Note that the output is zero padded for values below 16.
// Example: assert u8(2).hex() == '02'
// Example: assert u8(15).hex() == '0f'
// Example: assert u8(255).hex() == 'ff'
pub fn (nn u8) hex() string {
	if nn == 0 {
		return '00'
	}
	return u64_to_hex(nn, 2)
}

// hex returns a hexadecimal representation of `c` (as an 8 bit unsigned number).
// The output is zero padded for values below 16.
// Example: assert char(`A`).hex() == '41'
// Example: assert char(`Z`).hex() == '5a'
// Example: assert char(` `).hex() == '20'
pub fn (c char) hex() string {
	return u8(c).hex()
}

// hex returns a hexadecimal representation of the rune `r` (as a 32 bit unsigned number).
// Example: assert `A`.hex() == '41'
// Example: assert `💣`.hex() == '1f4a3'
pub fn (r rune) hex() string {
	return u32(r).hex()
}

// hex returns the value of the `i8` as a hexadecimal `string`.
// Note that the output is zero padded for values below 16.
// Example: assert i8(8).hex() == '08'
// Example: assert i8(10).hex() == '0a'
// Example: assert i8(15).hex() == '0f'
pub fn (nn i8) hex() string {
	if nn == 0 {
		return '00'
	}
	return u64_to_hex(u64(nn), 2)
}

// hex returns the value of the `u16` as a hexadecimal `string`.
// Note that the output is ***not*** zero padded.
// Example: assert u16(2).hex() == '2'
// Example: assert u16(200).hex() == 'c8'
pub fn (nn u16) hex() string {
	if nn == 0 {
		return '0'
	}
	return u64_to_hex_no_leading_zeros(nn, 4)
}

// hex returns the value of the `i16` as a hexadecimal `string`.
// Note that the output is ***not*** zero padded.
// Example: assert i16(2).hex() == '2'
// Example: assert i16(200).hex() == 'c8'
pub fn (nn i16) hex() string {
	return u16(nn).hex()
}

// hex returns the value of the `u32` as a hexadecimal `string`.
// Note that the output is ***not*** zero padded.
// Example: assert u32(2).hex() == '2'
// Example: assert u32(200).hex() == 'c8'
pub fn (nn u32) hex() string {
	if nn == 0 {
		return '0'
	}
	return u64_to_hex_no_leading_zeros(nn, 8)
}

// hex returns the value of the `int` as a hexadecimal `string`.
// Note that the output is ***not*** zero padded.
// Example: assert int(2).hex() == '2'
// Example: assert int(200).hex() == 'c8'
pub fn (nn int) hex() string {
	return u32(nn).hex()
}

// hex2 returns the value of the `int` as a `0x`-prefixed hexadecimal `string`.
// Note that the output after `0x` is ***not*** zero padded.
// Example: assert int(8).hex2() == '0x8'
// Example: assert int(15).hex2() == '0xf'
// Example: assert int(18).hex2() == '0x12'
pub fn (n int) hex2() string {
	return '0x' + n.hex()
}

// hex returns the value of the `u64` as a hexadecimal `string`.
// Note that the output is ***not*** zero padded.
// Example: assert u64(2).hex() == '2'
// Example: assert u64(2000).hex() == '7d0'
pub fn (nn u64) hex() string {
	if nn == 0 {
		return '0'
	}
	return u64_to_hex_no_leading_zeros(nn, 16)
}

// hex returns the value of the `i64` as a hexadecimal `string`.
// Note that the output is ***not*** zero padded.
// Example: assert i64(2).hex() == '2'
// Example: assert i64(-200).hex() == 'ffffffffffffff38'
// Example: assert i64(2021).hex() == '7e5'
pub fn (nn i64) hex() string {
	return u64(nn).hex()
}

// hex returns the value of the `int_literal` as a hexadecimal `string`.
// Note that the output is ***not*** zero padded.
pub fn (nn int_literal) hex() string {
	return u64(nn).hex()
}

// hex returns the value of the `voidptr` as a hexadecimal `string`.
// Note that the output is ***not*** zero padded.
pub fn (nn voidptr) str() string {
	return '0x' + u64(nn).hex()
}

// hex returns the value of the `byteptr` as a hexadecimal `string`.
// Note that the output is ***not*** zero padded.
// pub fn (nn byteptr) str() string {
pub fn (nn byteptr) str() string {
	return '0x' + u64(nn).hex()
}

pub fn (nn charptr) str() string {
	return '0x' + u64(nn).hex()
}

pub fn (nn u8) hex_full() string {
	return u64_to_hex(u64(nn), 2)
}

pub fn (nn i8) hex_full() string {
	return u64_to_hex(u64(nn), 2)
}

pub fn (nn u16) hex_full() string {
	return u64_to_hex(u64(nn), 4)
}

pub fn (nn i16) hex_full() string {
	return u64_to_hex(u64(nn), 4)
}

pub fn (nn u32) hex_full() string {
	return u64_to_hex(u64(nn), 8)
}

pub fn (nn i64) hex_full() string {
	return u64_to_hex(u64(nn), 16)
}

pub fn (nn voidptr) hex_full() string {
	return u64_to_hex(u64(nn), 16)
}

pub fn (nn int_literal) hex_full() string {
	return u64_to_hex(u64(nn), 16)
}

// hex_full returns the value of the `u64` as a *full* 16-digit hexadecimal `string`.
// Example: assert u64(2).hex_full() == '0000000000000002'
// Example: assert u64(255).hex_full() == '00000000000000ff'
pub fn (nn u64) hex_full() string {
	return u64_to_hex(nn, 16)
}

// str returns the contents of `byte` as a zero terminated `string`.
// See also: [`byte.ascii_str`](#byte.ascii_str)
// Example: assert u8(111).str() == '111'
pub fn (b u8) str() string {
	return int(b).str_l(4)
}

// ascii_str returns the contents of `byte` as a zero terminated ASCII `string` character.
// Example: assert u8(97).ascii_str() == 'a'
pub fn (b u8) ascii_str() string {
	mut str := string{
		str: unsafe { malloc_noscan(2) }
		len: 1
	}
	unsafe {
		str.str[0] = b
		str.str[1] = 0
	}
	return str
}

// str_escaped returns the contents of `byte` as an escaped `string`.
// Example: assert u8(0).str_escaped() == r'`\0`'
@[manualfree]
pub fn (b u8) str_escaped() string {
	str := match b {
		0 {
			r'`\0`'
		}
		7 {
			r'`\a`'
		}
		8 {
			r'`\b`'
		}
		9 {
			r'`\t`'
		}
		10 {
			r'`\n`'
		}
		11 {
			r'`\v`'
		}
		12 {
			r'`\f`'
		}
		13 {
			r'`\r`'
		}
		27 {
			r'`\e`'
		}
		32...126 {
			b.ascii_str()
		}
		else {
			xx := b.hex()
			yy := '0x' + xx
			unsafe { xx.free() }
			yy
		}
	}
	return str
}

// is_capital returns `true`, if the byte is a Latin capital letter.
// Example: assert u8(`H`).is_capital() == true
// Example: assert u8(`h`).is_capital() == false
@[inline]
pub fn (c u8) is_capital() bool {
	return c >= `A` && c <= `Z`
}

// bytestr produces a string from *all* the bytes in the array.
// Note: the returned string will have .len equal to the array.len,
// even when some of the array bytes were `0`.
// If you want to get a V string, that contains only the bytes till
// the first `0` byte, use `tos_clone(&u8(array.data))` instead.
pub fn (b []u8) bytestr() string {
	unsafe {
		buf := malloc_noscan(b.len + 1)
		vmemcpy(buf, b.data, b.len)
		buf[b.len] = 0
		return tos(buf, b.len)
	}
}

// byterune attempts to decode a sequence of bytes, from utf8 to utf32.
// It return the result as a rune.
// It will produce an error, if there are more than four bytes in the array.
pub fn (b []u8) byterune() !rune {
	r := b.utf8_to_utf32()!
	return rune(r)
}

// repeat returns a new string with `count` number of copies of the byte it was called on.
pub fn (b u8) repeat(count int) string {
	if count <= 0 {
		return ''
	} else if count == 1 {
		return b.ascii_str()
	}
	mut bytes := unsafe { malloc_noscan(count + 1) }
	unsafe {
		vmemset(bytes, b, count)
		bytes[count] = 0
	}
	return unsafe { bytes.vstring_with_len(count) }
}

// for atomic ints, internal
fn _Atomic__int_str(x int) string {
	return x.str()
}

// int_min returns the smallest `int` of input `a` and `b`.
// Example: assert int_min(2,3) == 2
@[inline]
pub fn int_min(a int, b int) int {
	return if a < b { a } else { b }
}

// int_max returns the largest `int` of input `a` and `b`.
// Example: assert int_max(2,3) == 3
@[inline]
pub fn int_max(a int, b int) int {
	return if a > b { a } else { b }
}

///////////// module builtin

fn C.wyhash(&u8, u64, u64, &u64) u64

fn C.wyhash64(u64, u64) u64

// fast_string_eq is intended to be fast when
// the strings are very likely to be equal
// TODO: add branch prediction hints
@[inline]
fn fast_string_eq(a string, b string) bool {
	if a.len != b.len {
		return false
	}
	unsafe {
		return C.memcmp(a.str, b.str, b.len) == 0
	}
}

fn map_hash_string(pkey voidptr) u64 {
	key := *unsafe { &string(pkey) }
	// XTODO remove voidptr cast once virtual C.consts can be declared
	return C.wyhash(key.str, u64(key.len), 0, &u64(voidptr(C._wyp)))
}

fn map_hash_int_1(pkey voidptr) u64 {
	return C.wyhash64(*unsafe { &u8(pkey) }, 0)
}

fn map_hash_int_2(pkey voidptr) u64 {
	return C.wyhash64(*unsafe { &u16(pkey) }, 0)
}

fn map_hash_int_4(pkey voidptr) u64 {
	return C.wyhash64(*unsafe { &u32(pkey) }, 0)
}

fn map_hash_int_8(pkey voidptr) u64 {
	return C.wyhash64(*unsafe { &u64(pkey) }, 0)
}

fn map_enum_fn(kind int, esize int) voidptr {
	if kind !in [1, 2, 3] {
		panic('map_enum_fn: invalid kind')
	}
	if esize > 8 || esize < 0 {
		panic('map_enum_fn: invalid esize')
	}
	if kind == 1 {
		if esize > 4 {
			return voidptr(map_hash_int_8)
		}
		if esize > 2 {
			return voidptr(map_hash_int_4)
		}
		if esize > 1 {
			return voidptr(map_hash_int_2)
		}
		if esize > 0 {
			return voidptr(map_hash_int_1)
		}
	}
	if kind == 2 {
		if esize > 4 {
			return voidptr(map_eq_int_8)
		}
		if esize > 2 {
			return voidptr(map_eq_int_4)
		}
		if esize > 1 {
			return voidptr(map_eq_int_2)
		}
		if esize > 0 {
			return voidptr(map_eq_int_1)
		}
	}
	if kind == 3 {
		if esize > 4 {
			return voidptr(map_clone_int_8)
		}
		if esize > 2 {
			return voidptr(map_clone_int_4)
		}
		if esize > 1 {
			return voidptr(map_clone_int_2)
		}
		if esize > 0 {
			return voidptr(map_clone_int_1)
		}
	}
	return unsafe { nil }
}

// Move all zeros to the end of the array and resize array
fn (mut d DenseArray) zeros_to_end() {
	// TODO: alloca?
	mut tmp_value := unsafe { malloc(d.value_bytes) }
	mut tmp_key := unsafe { malloc(d.key_bytes) }
	mut count := 0
	for i in 0 .. d.len {
		if d.has_index(i) {
			// swap (TODO: optimize)
			unsafe {
				if count != i {
					// Swap keys
					C.memcpy(tmp_key, d.key(count), d.key_bytes)
					C.memcpy(d.key(count), d.key(i), d.key_bytes)
					C.memcpy(d.key(i), tmp_key, d.key_bytes)
					// Swap values
					C.memcpy(tmp_value, d.value(count), d.value_bytes)
					C.memcpy(d.value(count), d.value(i), d.value_bytes)
					C.memcpy(d.value(i), tmp_value, d.value_bytes)
				}
			}
			count++
		}
	}
	unsafe {
		free(tmp_value)
		free(tmp_key)
		d.deletes = 0
		// TODO: reallocate instead as more deletes are likely
		free(d.all_deleted)
	}
	d.len = count
	old_cap := d.cap
	d.cap = if count < 8 { 8 } else { count }
	unsafe {
		d.values = realloc_data(d.values, d.value_bytes * old_cap, d.value_bytes * d.cap)
		d.keys = realloc_data(d.keys, d.key_bytes * old_cap, d.key_bytes * d.cap)
	}
}

///////////// module builtin

/*
This is a highly optimized hashmap implementation. It has several traits that
in combination makes it very fast and memory efficient. Here is a short expl-
anation of each trait. After reading this you should have a basic understand-
ing of how it functions:

1. Hash-function: Wyhash. Wyhash is the fastest hash-function for short keys
passing SMHasher, so it was an obvious choice.

2. Open addressing: Robin Hood Hashing. With this method, a hash-collision is
resolved by probing. As opposed to linear probing, Robin Hood hashing has a
simple but clever twist: As new keys are inserted, old keys are shifted arou-
nd in a way such that all keys stay reasonably close to the slot they origin-
ally hash to. A new key may displace a key already inserted if its probe cou-
nt is larger than that of the key at the current position.

3. Memory layout: key-value pairs are stored in a `DenseArray`. This is a dy-
namic array with a very low volume of unused memory, at the cost of more rea-
llocations when inserting elements. It also preserves the order of the key-v-
alues. This array is named `key_values`. Instead of probing a new key-value,
this map probes two 32-bit numbers collectively. The first number has its 8
most significant bits reserved for the probe-count and the remaining 24 bits
are cached bits from the hash which are utilized for faster re-hashing. This
number is often referred to as `meta`. The other 32-bit number is the index
at which the key-value was pushed to in `key_values`. Both of these numbers
are stored in a sparse array `metas`. The `meta`s and `kv_index`s are stored
at even and odd indices, respectively:

metas = [meta, kv_index, 0, 0, meta, kv_index, 0, 0, meta, kv_index, ...]
key_values = [kv, kv, kv, ...]

4. The size of metas is a power of two. This enables the use of bitwise AND
to convert the 64-bit hash to a bucket/index that doesn't overflow metas. If
the size is power of two you can use "hash & (SIZE - 1)" instead of "hash %
SIZE". Modulo is extremely expensive so using '&' is a big performance impro-
vement. The general concern with this approach is that you only make use of
the lower bits of the hash which can cause more collisions. This is solved by
using a well-dispersed hash-function.

5. The hashmap keeps track of the highest probe_count. The trick is to alloc-
ate `extra_metas` > max(probe_count), so you never have to do any bounds-che-
cking since the extra meta memory ensures that a meta will never go beyond
the last index.

6. Cached rehashing. When the `load_factor` of the map exceeds the `max_load_
factor` the size of metas is doubled and all the key-values are "rehashed" to
find the index for their meta's in the new array. Instead of rehashing compl-
etely, it simply uses the cached-hashbits stored in the meta, resulting in
much faster rehashing.
*/
// Number of bits from the hash stored for each entry
const hashbits = 24
// Number of bits from the hash stored for rehashing
const max_cached_hashbits = 16
// Initial log-number of buckets in the hashtable
const init_log_capicity = 5
// Initial number of buckets in the hashtable
const init_capicity = 1 << init_log_capicity
// Maximum load-factor (len / capacity)
const max_load_factor = 0.8
// Initial highest even index in metas
const init_even_index = init_capicity - 2
// Used for incrementing `extra_metas` when max
// probe count is too high, to avoid overflow
const extra_metas_inc = 4
// Bitmask to select all the hashbits
const hash_mask = u32(0x00FFFFFF)
// Used for incrementing the probe-count
const probe_inc = u32(0x01000000)

// DenseArray represents a dynamic array with very low growth factor
struct DenseArray {
	key_bytes   int
	value_bytes int
mut:
	cap     int
	len     int
	deletes u32 // count
	// array allocated (with `cap` bytes) on first deletion
	// has non-zero element when key deleted
	all_deleted &u8 = unsafe { nil }
	keys        &u8 = unsafe { nil }
	values      &u8 = unsafe { nil }
}

@[inline]
fn new_dense_array(key_bytes int, value_bytes int) DenseArray {
	cap := 8
	return DenseArray{
		key_bytes:   key_bytes
		value_bytes: value_bytes
		cap:         cap
		len:         0
		deletes:     0
		all_deleted: unsafe { nil }
		keys:        unsafe { malloc(__at_least_one(u64(cap) * u64(key_bytes))) }
		values:      unsafe { malloc(__at_least_one(u64(cap) * u64(value_bytes))) }
	}
}

@[inline]
fn (d &DenseArray) key(i int) voidptr {
	return unsafe { voidptr(d.keys + i * d.key_bytes) }
}

// for cgen
@[inline]
fn (d &DenseArray) value(i int) voidptr {
	return unsafe { voidptr(d.values + i * d.value_bytes) }
}

@[inline]
fn (d &DenseArray) has_index(i int) bool {
	return d.deletes == 0 || unsafe { d.all_deleted[i] } == 0
}

// Make space to append an element and return index
// The growth-factor is roughly 1.125 `(x + (x >> 3))`
@[inline]
fn (mut d DenseArray) expand() int {
	old_cap := d.cap
	old_key_size := d.key_bytes * old_cap
	old_value_size := d.value_bytes * old_cap
	if d.cap == d.len {
		d.cap += d.cap >> 3
		unsafe {
			d.keys = realloc_data(d.keys, old_key_size, d.key_bytes * d.cap)
			d.values = realloc_data(d.values, old_value_size, d.value_bytes * d.cap)
			if d.deletes != 0 {
				d.all_deleted = realloc_data(d.all_deleted, old_cap, d.cap)
				vmemset(voidptr(d.all_deleted + d.len), 0, d.cap - d.len)
			}
		}
	}
	push_index := d.len
	unsafe {
		if d.deletes != 0 {
			d.all_deleted[push_index] = 0
		}
	}
	d.len++
	return push_index
}

type MapHashFn = fn (voidptr) u64

type MapEqFn = fn (voidptr, voidptr) bool

type MapCloneFn = fn (voidptr, voidptr)

type MapFreeFn = fn (voidptr)

// map is the internal representation of a V `map` type.
pub struct map {
	// Number of bytes of a key
	key_bytes int
	// Number of bytes of a value
	value_bytes int
mut:
	// Highest even index in the hashtable
	even_index u32
	// Number of cached hashbits left for rehashing
	cached_hashbits u8
	// Used for right-shifting out used hashbits
	shift u8
	// Array storing key-values (ordered)
	key_values DenseArray
	// Pointer to meta-data:
	// - Odd indices store kv_index.
	// - Even indices store probe_count and hashbits.
	metas &u32
	// Extra metas that allows for no ranging when incrementing
	// index in the hashmap
	extra_metas     u32
	has_string_keys bool
	hash_fn         MapHashFn
	key_eq_fn       MapEqFn
	clone_fn        MapCloneFn
	free_fn         MapFreeFn
pub mut:
	// Number of key-values currently in the hashmap
	len int
}

@[inline]
fn map_eq_string(a voidptr, b voidptr) bool {
	return fast_string_eq(*unsafe { &string(a) }, *unsafe { &string(b) })
}

@[inline]
fn map_eq_int_1(a voidptr, b voidptr) bool {
	return unsafe { *&u8(a) == *&u8(b) }
}

@[inline]
fn map_eq_int_2(a voidptr, b voidptr) bool {
	return unsafe { *&u16(a) == *&u16(b) }
}

@[inline]
fn map_eq_int_4(a voidptr, b voidptr) bool {
	return unsafe { *&u32(a) == *&u32(b) }
}

@[inline]
fn map_eq_int_8(a voidptr, b voidptr) bool {
	return unsafe { *&u64(a) == *&u64(b) }
}

@[inline]
fn map_clone_string(dest voidptr, pkey voidptr) {
	unsafe {
		s := *&string(pkey)
		(*&string(dest)) = s.clone()
	}
}

@[inline]
fn map_clone_int_1(dest voidptr, pkey voidptr) {
	unsafe {
		*&u8(dest) = *&u8(pkey)
	}
}

@[inline]
fn map_clone_int_2(dest voidptr, pkey voidptr) {
	unsafe {
		*&u16(dest) = *&u16(pkey)
	}
}

@[inline]
fn map_clone_int_4(dest voidptr, pkey voidptr) {
	unsafe {
		*&u32(dest) = *&u32(pkey)
	}
}

@[inline]
fn map_clone_int_8(dest voidptr, pkey voidptr) {
	unsafe {
		*&u64(dest) = *&u64(pkey)
	}
}

@[inline]
fn map_free_string(pkey voidptr) {
	unsafe {
		(*&string(pkey)).free()
	}
}

@[inline]
fn map_free_nop(_ voidptr) {
}

fn new_map(key_bytes int, value_bytes int, hash_fn MapHashFn, key_eq_fn MapEqFn, clone_fn MapCloneFn, free_fn MapFreeFn) map {
	metasize := int(sizeof(u32) * (init_capicity + extra_metas_inc))
	// for now assume anything bigger than a pointer is a string
	has_string_keys := key_bytes > int(sizeof(voidptr))
	return map{
		key_bytes:       key_bytes
		value_bytes:     value_bytes
		even_index:      init_even_index
		cached_hashbits: max_cached_hashbits
		shift:           init_log_capicity
		key_values:      new_dense_array(key_bytes, value_bytes)
		metas:           unsafe { &u32(vcalloc_noscan(metasize)) }
		extra_metas:     extra_metas_inc
		len:             0
		has_string_keys: has_string_keys
		hash_fn:         hash_fn
		key_eq_fn:       key_eq_fn
		clone_fn:        clone_fn
		free_fn:         free_fn
	}
}

fn new_map_init(hash_fn MapHashFn, key_eq_fn MapEqFn, clone_fn MapCloneFn, free_fn MapFreeFn, n int, key_bytes int,
	value_bytes int, keys voidptr, values voidptr) map {
	mut out := new_map(key_bytes, value_bytes, hash_fn, key_eq_fn, clone_fn, free_fn)
	// TODO: pre-allocate n slots
	mut pkey := &u8(keys)
	mut pval := &u8(values)
	for _ in 0 .. n {
		unsafe {
			out.set(pkey, pval)
			pkey = pkey + key_bytes
			pval = pval + value_bytes
		}
	}
	return out
}

fn new_map_update_init(update &map, n int, key_bytes int, value_bytes int, keys voidptr, values voidptr) map {
	mut out := unsafe { update.clone() }
	mut pkey := &u8(keys)
	mut pval := &u8(values)
	for _ in 0 .. n {
		unsafe {
			out.set(pkey, pval)
			pkey = pkey + key_bytes
			pval = pval + value_bytes
		}
	}
	return out
}

// move moves the map to a new location in memory.
// It does this by copying to a new location, then setting the
// old location to all `0` with `vmemset`
pub fn (mut m map) move() map {
	r := *m
	unsafe {
		vmemset(m, 0, int(sizeof(map)))
	}
	return r
}

// clear clears the map without deallocating the allocated data.
// It does it by setting the map length to `0`
// Example: mut m := {'abc': 'xyz', 'def': 'aaa'}; m.clear(); assert m.len == 0
pub fn (mut m map) clear() {
	unsafe {
		if m.key_values.all_deleted != 0 {
			free(m.key_values.all_deleted)
			m.key_values.all_deleted = nil
		}
		vmemset(m.key_values.keys, 0, m.key_values.key_bytes * m.key_values.cap)
		vmemset(m.metas, 0, sizeof(u32) * (m.even_index + 2 + m.extra_metas))
	}
	m.key_values.len = 0
	m.key_values.deletes = 0
	m.even_index = init_even_index
	m.cached_hashbits = max_cached_hashbits
	m.shift = init_log_capicity
	m.len = 0
}

@[inline]
fn (m &map) key_to_index(pkey voidptr) (u32, u32) {
	hash := m.hash_fn(pkey)
	index := hash & m.even_index
	meta := ((hash >> m.shift) & hash_mask) | probe_inc
	return u32(index), u32(meta)
}

@[inline]
fn (m &map) meta_less(_index u32, _metas u32) (u32, u32) {
	mut index := _index
	mut meta := _metas
	for meta < unsafe { m.metas[index] } {
		index += 2
		meta += probe_inc
	}
	return index, meta
}

@[inline]
fn (mut m map) meta_greater(_index u32, _metas u32, kvi u32) {
	mut meta := _metas
	mut index := _index
	mut kv_index := kvi
	for unsafe { m.metas[index] } != 0 {
		if meta > unsafe { m.metas[index] } {
			unsafe {
				tmp_meta := m.metas[index]
				m.metas[index] = meta
				meta = tmp_meta
				tmp_index := m.metas[index + 1]
				m.metas[index + 1] = kv_index
				kv_index = tmp_index
			}
		}
		index += 2
		meta += probe_inc
	}
	unsafe {
		m.metas[index] = meta
		m.metas[index + 1] = kv_index
	}
	probe_count := (meta >> hashbits) - 1
	m.ensure_extra_metas(probe_count)
}

@[inline]
fn (mut m map) ensure_extra_metas(probe_count u32) {
	if (probe_count << 1) == m.extra_metas {
		size_of_u32 := sizeof(u32)
		old_mem_size := (m.even_index + 2 + m.extra_metas)
		m.extra_metas += extra_metas_inc
		mem_size := (m.even_index + 2 + m.extra_metas)
		unsafe {
			x := realloc_data(&u8(m.metas), int(size_of_u32 * old_mem_size), int(size_of_u32 * mem_size))
			m.metas = &u32(x)
			vmemset(m.metas + mem_size - extra_metas_inc, 0, int(sizeof(u32) * extra_metas_inc))
		}
		// Should almost never happen
		if probe_count == 252 {
			panic('Probe overflow')
		}
	}
}

// Insert new element to the map. The element is inserted if its key is
// not equivalent to the key of any other element already in the container.
// If the key already exists, its value is changed to the value of the new element.
fn (mut m map) set(key voidptr, value voidptr) {
	load_factor := f32(u32(m.len) << 1) / f32(m.even_index)
	if load_factor > max_load_factor {
		m.expand()
	}
	mut index, mut meta := m.key_to_index(key)
	index, meta = m.meta_less(index, meta)
	// While we might have a match
	for meta == unsafe { m.metas[index] } {
		kv_index := int(unsafe { m.metas[index + 1] })
		pkey := unsafe { m.key_values.key(kv_index) }
		if m.key_eq_fn(key, pkey) {
			unsafe {
				pval := m.key_values.value(kv_index)
				vmemcpy(pval, value, m.value_bytes)
			}
			return
		}
		index += 2
		meta += probe_inc
	}
	kv_index := m.key_values.expand()
	unsafe {
		pkey := m.key_values.key(kv_index)
		pvalue := m.key_values.value(kv_index)
		m.clone_fn(pkey, key)
		vmemcpy(&u8(pvalue), value, m.value_bytes)
	}
	m.meta_greater(index, meta, u32(kv_index))
	m.len++
}

// Doubles the size of the hashmap
fn (mut m map) expand() {
	old_cap := m.even_index
	m.even_index = ((m.even_index + 2) << 1) - 2
	// Check if any hashbits are left
	if m.cached_hashbits == 0 {
		m.shift += max_cached_hashbits
		m.cached_hashbits = max_cached_hashbits
		m.rehash()
	} else {
		m.cached_rehash(old_cap)
		m.cached_hashbits--
	}
}

// rehash reconstructs the hash table.
// All the elements in the container are rearranged according
// to their hash value into the newly sized key-value container.
// Rehashes are performed when the load_factor is going to surpass
// the max_load_factor in an operation.
fn (mut m map) rehash() {
	meta_bytes := sizeof(u32) * (m.even_index + 2 + m.extra_metas)
	m.reserve(meta_bytes)
}

// reserve memory for the map meta data.
pub fn (mut m map) reserve(meta_bytes u32) {
	unsafe {
		// TODO: use realloc_data here too
		x := v_realloc(&u8(m.metas), int(meta_bytes))
		m.metas = &u32(x)
		vmemset(m.metas, 0, int(meta_bytes))
	}
	for i := 0; i < m.key_values.len; i++ {
		if !m.key_values.has_index(i) {
			continue
		}
		pkey := unsafe { m.key_values.key(i) }
		mut index, mut meta := m.key_to_index(pkey)
		index, meta = m.meta_less(index, meta)
		m.meta_greater(index, meta, u32(i))
	}
}

// cached_rehashd works like rehash. However, instead of rehashing the
// key completely, it uses the bits cached in `metas`.
fn (mut m map) cached_rehash(old_cap u32) {
	old_metas := m.metas
	metasize := int(sizeof(u32) * (m.even_index + 2 + m.extra_metas))
	m.metas = unsafe { &u32(vcalloc(metasize)) }
	old_extra_metas := m.extra_metas
	for i := u32(0); i <= old_cap + old_extra_metas; i += 2 {
		if unsafe { old_metas[i] } == 0 {
			continue
		}
		old_meta := unsafe { old_metas[i] }
		old_probe_count := ((old_meta >> hashbits) - 1) << 1
		old_index := (i - old_probe_count) & (m.even_index >> 1)
		mut index := (old_index | (old_meta << m.shift)) & m.even_index
		mut meta := (old_meta & hash_mask) | probe_inc
		index, meta = m.meta_less(index, meta)
		kv_index := unsafe { old_metas[i + 1] }
		m.meta_greater(index, meta, kv_index)
	}
	unsafe { free(old_metas) }
}

// get_and_set is used for assignment operators. If the argument-key
// does not exist in the map, it's added to the map along with the zero/default value.
// If the key exists, its respective value is returned.
fn (mut m map) get_and_set(key voidptr, zero voidptr) voidptr {
	for {
		mut index, mut meta := m.key_to_index(key)
		for {
			if meta == unsafe { m.metas[index] } {
				kv_index := int(unsafe { m.metas[index + 1] })
				pkey := unsafe { m.key_values.key(kv_index) }
				if m.key_eq_fn(key, pkey) {
					pval := unsafe { m.key_values.value(kv_index) }
					return unsafe { &u8(pval) }
				}
			}
			index += 2
			meta += probe_inc
			if meta > unsafe { m.metas[index] } {
				break
			}
		}
		// Key not found, insert key with zero-value
		m.set(key, zero)
	}
	return unsafe { nil }
}

// If `key` matches the key of an element in the container,
// the method returns a reference to its mapped value.
// If not, a zero/default value is returned.
fn (m &map) get(key voidptr, zero voidptr) voidptr {
	mut index, mut meta := m.key_to_index(key)
	for {
		if meta == unsafe { m.metas[index] } {
			kv_index := int(unsafe { m.metas[index + 1] })
			pkey := unsafe { m.key_values.key(kv_index) }
			if m.key_eq_fn(key, pkey) {
				pval := unsafe { m.key_values.value(kv_index) }
				return unsafe { &u8(pval) }
			}
		}
		index += 2
		meta += probe_inc
		if meta > unsafe { m.metas[index] } {
			break
		}
	}
	return zero
}

// If `key` matches the key of an element in the container,
// the method returns a reference to its mapped value.
// If not, a zero pointer is returned.
// This is used in `x := m['key'] or { ... }`
fn (m &map) get_check(key voidptr) voidptr {
	mut index, mut meta := m.key_to_index(key)
	for {
		if meta == unsafe { m.metas[index] } {
			kv_index := int(unsafe { m.metas[index + 1] })
			pkey := unsafe { m.key_values.key(kv_index) }
			if m.key_eq_fn(key, pkey) {
				pval := unsafe { m.key_values.value(kv_index) }
				return unsafe { &u8(pval) }
			}
		}
		index += 2
		meta += probe_inc
		if meta > unsafe { m.metas[index] } {
			break
		}
	}
	return 0
}

// Checks whether a particular key exists in the map.
fn (m &map) exists(key voidptr) bool {
	mut index, mut meta := m.key_to_index(key)
	for {
		if meta == unsafe { m.metas[index] } {
			kv_index := int(unsafe { m.metas[index + 1] })
			pkey := unsafe { m.key_values.key(kv_index) }
			if m.key_eq_fn(key, pkey) {
				return true
			}
		}
		index += 2
		meta += probe_inc
		if meta > unsafe { m.metas[index] } {
			break
		}
	}
	return false
}

@[inline]
fn (mut d DenseArray) delete(i int) {
	if d.deletes == 0 {
		d.all_deleted = vcalloc(d.cap) // sets to 0
	}
	d.deletes++
	unsafe {
		d.all_deleted[i] = 1
	}
}

// delete removes the mapping of a particular key from the map.
@[unsafe]
pub fn (mut m map) delete(key voidptr) {
	mut index, mut meta := m.key_to_index(key)
	index, meta = m.meta_less(index, meta)
	// Perform backwards shifting
	for meta == unsafe { m.metas[index] } {
		kv_index := int(unsafe { m.metas[index + 1] })
		pkey := unsafe { m.key_values.key(kv_index) }
		if m.key_eq_fn(key, pkey) {
			for (unsafe { m.metas[index + 2] } >> hashbits) > 1 {
				unsafe {
					m.metas[index] = m.metas[index + 2] - probe_inc
					m.metas[index + 1] = m.metas[index + 3]
				}
				index += 2
			}
			m.len--
			m.key_values.delete(kv_index)
			unsafe {
				m.metas[index] = 0
				m.free_fn(pkey)
				// Mark key as deleted
				vmemset(pkey, 0, m.key_bytes)
			}
			if m.key_values.len <= 32 {
				return
			}
			// Clean up key_values if too many have been deleted
			if m.key_values.deletes >= (m.key_values.len >> 1) {
				m.key_values.zeros_to_end()
				m.rehash()
			}
			return
		}
		index += 2
		meta += probe_inc
	}
}

// keys returns all keys in the map.
pub fn (m &map) keys() array {
	mut keys := __new_array(m.len, 0, m.key_bytes)
	mut item := unsafe { &u8(keys.data) }
	if m.key_values.deletes == 0 {
		for i := 0; i < m.key_values.len; i++ {
			unsafe {
				pkey := m.key_values.key(i)
				m.clone_fn(item, pkey)
				item = item + m.key_bytes
			}
		}
		return keys
	}
	for i := 0; i < m.key_values.len; i++ {
		if !m.key_values.has_index(i) {
			continue
		}
		unsafe {
			pkey := m.key_values.key(i)
			m.clone_fn(item, pkey)
			item = item + m.key_bytes
		}
	}
	return keys
}

// values returns all values in the map.
pub fn (m &map) values() array {
	mut values := __new_array(m.len, 0, m.value_bytes)
	mut item := unsafe { &u8(values.data) }

	if m.key_values.deletes == 0 {
		unsafe {
			vmemcpy(item, m.key_values.values, m.value_bytes * m.key_values.len)
		}
		return values
	}

	for i := 0; i < m.key_values.len; i++ {
		if !m.key_values.has_index(i) {
			continue
		}
		unsafe {
			pvalue := m.key_values.value(i)
			vmemcpy(item, pvalue, m.value_bytes)
			item = item + m.value_bytes
		}
	}
	return values
}

// warning: only copies keys, does not clone
@[unsafe]
fn (d &DenseArray) clone() DenseArray {
	res := DenseArray{
		key_bytes:   d.key_bytes
		value_bytes: d.value_bytes
		cap:         d.cap
		len:         d.len
		deletes:     d.deletes
		all_deleted: unsafe { nil }
		values:      unsafe { nil }
		keys:        unsafe { nil }
	}
	unsafe {
		if d.deletes != 0 {
			res.all_deleted = memdup(d.all_deleted, d.cap)
		}
		res.keys = memdup(d.keys, d.cap * d.key_bytes)
		res.values = memdup(d.values, d.cap * d.value_bytes)
	}
	return res
}

// clone returns a clone of the `map`.
@[unsafe]
pub fn (m &map) clone() map {
	metasize := int(sizeof(u32) * (m.even_index + 2 + m.extra_metas))
	res := map{
		key_bytes:       m.key_bytes
		value_bytes:     m.value_bytes
		even_index:      m.even_index
		cached_hashbits: m.cached_hashbits
		shift:           m.shift
		key_values:      unsafe { m.key_values.clone() }
		metas:           unsafe { &u32(malloc_noscan(metasize)) }
		extra_metas:     m.extra_metas
		len:             m.len
		has_string_keys: m.has_string_keys
		hash_fn:         m.hash_fn
		key_eq_fn:       m.key_eq_fn
		clone_fn:        m.clone_fn
		free_fn:         m.free_fn
	}
	unsafe { vmemcpy(res.metas, m.metas, metasize) }
	if !m.has_string_keys {
		return res
	}
	// clone keys
	for i in 0 .. m.key_values.len {
		if !m.key_values.has_index(i) {
			continue
		}
		m.clone_fn(res.key_values.key(i), m.key_values.key(i))
	}
	return res
}

// free releases all memory resources occupied by the `map`.
@[unsafe]
pub fn (m &map) free() {
	unsafe { free(m.metas) }
	unsafe {
		m.metas = nil
	}
	if m.key_values.deletes == 0 {
		for i := 0; i < m.key_values.len; i++ {
			unsafe {
				pkey := m.key_values.key(i)
				m.free_fn(pkey)
				vmemset(pkey, 0, m.key_bytes)
			}
		}
	} else {
		for i := 0; i < m.key_values.len; i++ {
			if !m.key_values.has_index(i) {
				continue
			}
			unsafe {
				pkey := m.key_values.key(i)
				m.free_fn(pkey)
				vmemset(pkey, 0, m.key_bytes)
			}
		}
	}
	unsafe {
		if m.key_values.all_deleted != nil {
			free(m.key_values.all_deleted)
			m.key_values.all_deleted = nil
		}
		if m.key_values.keys != nil {
			free(m.key_values.keys)
			m.key_values.keys = nil
		}
		if m.key_values.values != nil {
			free(m.key_values.values)
			m.key_values.values = nil
		}
		// TODO: the next lines assume that callback functions are static and independent from each particular
		// map instance. Closures may invalidate that assumption, so revisit when RC for closures works.
		m.hash_fn = nil
		m.key_eq_fn = nil
		m.clone_fn = nil
		m.free_fn = nil
	}
}
// "noscan" versions of `map` initialization routines
//
// They are used when the compiler can proof that either the keys or the values or both
// do not contain any pointers. Such objects can be placed in a memory area that is not
// scanned by the garbage collector

///////////// module builtin

@[inline]
fn __malloc_at_least_one(how_many_bytes u64, noscan bool) &u8 {
	if noscan {
		return unsafe { malloc_noscan(__at_least_one(how_many_bytes)) }
	}
	return unsafe { malloc(__at_least_one(how_many_bytes)) }
}

@[inline]
fn new_dense_array_noscan(key_bytes int, key_noscan bool, value_bytes int, value_noscan bool) DenseArray {
	cap := 8
	return DenseArray{
		key_bytes:   key_bytes
		value_bytes: value_bytes
		cap:         cap
		len:         0
		deletes:     0
		all_deleted: unsafe { nil }
		keys:        __malloc_at_least_one(u64(cap) * u64(key_bytes), key_noscan)
		values:      __malloc_at_least_one(u64(cap) * u64(value_bytes), value_noscan)
	}
}

fn new_map_noscan_key(key_bytes int, value_bytes int, hash_fn MapHashFn, key_eq_fn MapEqFn, clone_fn MapCloneFn,
	free_fn MapFreeFn) map {
	metasize := int(sizeof(u32) * (init_capicity + extra_metas_inc))
	// for now assume anything bigger than a pointer is a string
	has_string_keys := key_bytes > sizeof(voidptr)
	return map{
		key_bytes:       key_bytes
		value_bytes:     value_bytes
		even_index:      init_even_index
		cached_hashbits: max_cached_hashbits
		shift:           init_log_capicity
		key_values:      new_dense_array_noscan(key_bytes, true, value_bytes, false)
		metas:           unsafe { &u32(vcalloc_noscan(metasize)) }
		extra_metas:     extra_metas_inc
		len:             0
		has_string_keys: has_string_keys
		hash_fn:         hash_fn
		key_eq_fn:       key_eq_fn
		clone_fn:        clone_fn
		free_fn:         free_fn
	}
}

fn new_map_noscan_value(key_bytes int, value_bytes int, hash_fn MapHashFn, key_eq_fn MapEqFn, clone_fn MapCloneFn,
	free_fn MapFreeFn) map {
	metasize := int(sizeof(u32) * (init_capicity + extra_metas_inc))
	// for now assume anything bigger than a pointer is a string
	has_string_keys := key_bytes > sizeof(voidptr)
	return map{
		key_bytes:       key_bytes
		value_bytes:     value_bytes
		even_index:      init_even_index
		cached_hashbits: max_cached_hashbits
		shift:           init_log_capicity
		key_values:      new_dense_array_noscan(key_bytes, false, value_bytes, true)
		metas:           unsafe { &u32(vcalloc_noscan(metasize)) }
		extra_metas:     extra_metas_inc
		len:             0
		has_string_keys: has_string_keys
		hash_fn:         hash_fn
		key_eq_fn:       key_eq_fn
		clone_fn:        clone_fn
		free_fn:         free_fn
	}
}

fn new_map_noscan_key_value(key_bytes int, value_bytes int, hash_fn MapHashFn, key_eq_fn MapEqFn, clone_fn MapCloneFn,
	free_fn MapFreeFn) map {
	metasize := int(sizeof(u32) * (init_capicity + extra_metas_inc))
	// for now assume anything bigger than a pointer is a string
	has_string_keys := key_bytes > sizeof(voidptr)
	return map{
		key_bytes:       key_bytes
		value_bytes:     value_bytes
		even_index:      init_even_index
		cached_hashbits: max_cached_hashbits
		shift:           init_log_capicity
		key_values:      new_dense_array_noscan(key_bytes, true, value_bytes, true)
		metas:           unsafe { &u32(vcalloc_noscan(metasize)) }
		extra_metas:     extra_metas_inc
		len:             0
		has_string_keys: has_string_keys
		hash_fn:         hash_fn
		key_eq_fn:       key_eq_fn
		clone_fn:        clone_fn
		free_fn:         free_fn
	}
}

fn new_map_init_noscan_key(hash_fn MapHashFn, key_eq_fn MapEqFn, clone_fn MapCloneFn, free_fn MapFreeFn,
	n int, key_bytes int, value_bytes int, keys voidptr, values voidptr) map {
	mut out := new_map_noscan_key(key_bytes, value_bytes, hash_fn, key_eq_fn, clone_fn,
		free_fn)
	// TODO: pre-allocate n slots
	mut pkey := &u8(keys)
	mut pval := &u8(values)
	for _ in 0 .. n {
		unsafe {
			out.set(pkey, pval)
			pkey = pkey + key_bytes
			pval = pval + value_bytes
		}
	}
	return out
}

fn new_map_init_noscan_value(hash_fn MapHashFn, key_eq_fn MapEqFn, clone_fn MapCloneFn, free_fn MapFreeFn,
	n int, key_bytes int, value_bytes int, keys voidptr, values voidptr) map {
	mut out := new_map_noscan_value(key_bytes, value_bytes, hash_fn, key_eq_fn, clone_fn,
		free_fn)
	// TODO: pre-allocate n slots
	mut pkey := &u8(keys)
	mut pval := &u8(values)
	for _ in 0 .. n {
		unsafe {
			out.set(pkey, pval)
			pkey = pkey + key_bytes
			pval = pval + value_bytes
		}
	}
	return out
}

fn new_map_init_noscan_key_value(hash_fn MapHashFn, key_eq_fn MapEqFn, clone_fn MapCloneFn, free_fn MapFreeFn,
	n int, key_bytes int, value_bytes int, keys voidptr, values voidptr) map {
	mut out := new_map_noscan_key_value(key_bytes, value_bytes, hash_fn, key_eq_fn, clone_fn,
		free_fn)
	// TODO: pre-allocate n slots
	mut pkey := &u8(keys)
	mut pval := &u8(values)
	for _ in 0 .. n {
		unsafe {
			out.set(pkey, pval)
			pkey = pkey + key_bytes
			pval = pval + value_bytes
		}
	}
	return out
}

///////////// module builtin

@[typedef]
pub struct C.IError {
	_object voidptr
}

@[unsafe]
pub fn (ie &IError) free() {
	unsafe {
		cie := &C.IError(ie)
		free(cie._object)
	}
}

///////////// module builtin

// reuse_data_as_string provides a way to treat the memory of a []u8 `buffer` as a string value.
// It does not allocate or copy the memory block for the `buffer`, but instead creates a string descriptor,
// that will point to the same memory as the input.
// The intended use of that function, is to allow calling string search methods (defined on string),
// on []u8 values too, without having to copy/allocate by calling .bytestr() (that can be too slow and unnecessary in loops).
// Note: unlike normal V strings, the return value *is not* guaranteed to have a terminating `0` byte,
// since this function does not allocate or modify the input in any way. This is not a problem usually,
// since V methods and functions do not require it, but be careful, if you want to pass that string to call a C. function,
// that expects 0 termination. If you have to do it, make a `tmp := s.clone()` beforehand, and free the cloned `tmp` string
// after you have called the C. function with it.
// The .len field of the result value, will be the same as the buffer.len.
// Note: avoid storing or returning that resulting string,
// and avoid calling the fn with a complex expression (prefer using a temporary variable as an argument).
@[unsafe]
pub fn reuse_data_as_string(buffer []u8) string {
	return string{
		str:    buffer.data
		len:    buffer.len
		is_lit: 1 // prevent freeing the string, since its memory is owned by the input buffer
	}
}

// reuse_string_as_data provides a way to treat the memory of a string `s`, as a []u8 buffer.
// It does not allocate or copy the memory block for the string `s`, but instead creates an array descriptor,
// that will point to the same memory as the input.
// The intended use of that function, is to allow calling array methods (defined on []u8),
// on string values too, without having to copy/allocate by calling .bytes() (that can be too slow and unnecessary in loops).
// Note: since there are no allocations, the buffer *will not* contain the terminating `0` byte, that V strings have usually.
// The .len field of the result value, will be the same as s.len .
// Note: avoid storing or returning that resulting byte buffer,
// and avoid calling the fn with a complex expression (prefer using a temporary variable as an argument).
@[unsafe]
pub fn reuse_string_as_data(s string) []u8 {
	mut res := unsafe {
		array{
			data:         s.str
			len:          s.len
			element_size: 1
			flags:        .nogrow | .noshrink | .nofree // prevent freeing/resizing the array, since its memory is owned by the input string
		}
	}
	return res
}

///////////// module builtin

// This was never working correctly, the issue is now
// fixed however the type checks in checker need to be
// updated. if you uncomment it you will see the issue
// type rune = int

// str converts a rune to string.
pub fn (c rune) str() string {
	return utf32_to_str(u32(c))
}

// string converts a rune array to a string.
@[manualfree]
pub fn (ra []rune) string() string {
	mut sb := strings.new_builder(ra.len)
	sb.write_runes(ra)
	res := sb.str()
	unsafe { sb.free() }
	return res
}

// repeat returns a new string with `count` number of copies of the rune it was called on.
pub fn (c rune) repeat(count int) string {
	if count <= 0 {
		return ''
	} else if count == 1 {
		return c.str()
	}
	mut buffer := [5]u8{}
	res := unsafe { utf32_to_str_no_malloc(u32(c), mut &buffer[0]) }
	return res.repeat(count)
}

// bytes converts a rune to an array of bytes.
@[manualfree]
pub fn (c rune) bytes() []u8 {
	mut res := []u8{cap: 5}
	mut buf := &u8(res.data)
	res.len = unsafe { utf32_decode_to_buffer(u32(c), mut buf) }
	return res
}

// length_in_bytes returns the number of bytes needed to store the code point.
// Returns -1 if the data is not a valid code point.
pub fn (c rune) length_in_bytes() int {
	code := u32(c)
	if code <= 0x7F {
		return 1
	} else if code <= 0x7FF {
		return 2
	} else if 0xD800 <= code && code <= 0xDFFF {
		// between min and max for surrogates
		return -1
	} else if code <= 0xFFFF {
		return 3
	} else if code <= 0x10FFFF {
		// 0x10FFFF is the maximum valid unicode code point
		return 4
	}
	return -1
}

// `to_upper` convert to uppercase mode.
pub fn (c rune) to_upper() rune {
	if c < 0x80 {
		if c >= `a` && c <= `z` {
			return c - 32
		}
		return c
	}
	return c.map_to(.to_upper)
}

// `to_lower` convert to lowercase mode.
pub fn (c rune) to_lower() rune {
	if c < 0x80 {
		if c >= `A` && c <= `Z` {
			return c + 32
		}
		return c
	}
	return c.map_to(.to_lower)
}

// `to_title` convert to title mode.
pub fn (c rune) to_title() rune {
	if c < 0x80 {
		if c >= `a` && c <= `z` {
			return c - 32
		}
		return c
	}
	return c.map_to(.to_title)
}

// `map_to` rune map mode: .to_upper/.to_lower/.to_title
@[direct_array_access]
fn (c rune) map_to(mode MapMode) rune {
	mut start := 0
	mut end := rune_maps.len / rune_maps_columns_in_row
	// Binary search
	for start < end {
		middle := (start + end) / 2
		cur_map := unsafe { &rune_maps[middle * rune_maps_columns_in_row] }
		if c >= u32(unsafe { *cur_map }) && c <= u32(unsafe { *(cur_map + 1) }) {
			offset := if mode in [.to_upper, .to_title] {
				unsafe { *(cur_map + 2) }
			} else {
				unsafe { *(cur_map + 3) }
			}
			if offset == rune_maps_ul {
				// upper, lower, upper, lower, ... sequence
				cnt := (c - unsafe { *cur_map }) % 2
				if mode == .to_lower {
					return c + 1 - cnt
				}
				return c - cnt
			} else if offset == rune_maps_utl {
				// upper, title, lower, upper, title, lower, ... sequence
				cnt := (c - unsafe { *cur_map }) % 3
				if mode == .to_upper {
					return c - cnt
				} else if mode == .to_lower {
					return c + 2 - cnt
				}
				return c + 1 - cnt
			}
			return c + offset
		}
		if c < u32(unsafe { *cur_map }) {
			end = middle
		} else {
			start = middle + 1
		}
	}
	return c
}

///////////// module builtin

enum MapMode {
	to_upper
	to_lower
	to_title
}

// vfmt off
// Quotes from golang source code `src/unicode/tables.go`
/*
struct RuneMap {
	s int // start
	e int // end
	u int // upper offset
	l int // lower offset
}
*/
const rune_maps_columns_in_row = 4
// upper, lower, upper, lower, ... sequence
const rune_maps_ul = -3 // NOTE: this should *NOT* be used anywhere in rune_maps, as a normal offset.
// upper, title, lower, upper, title, lower, ... sequence
const rune_maps_utl = -2 // NOTE: this should *NOT* be used anywhere in rune_maps, as a normal offset.
// The rune_maps table below, has rows, each containing 4 integers, equivalent to the RuneMap struct from above.
// It is represented that way, instead of the more natural array of structs, to save on the .c encoding used for the initialisation.
// The overhead for representing it as an array of structs was ~28KB in .c, while with the flat array of ints, it is ~7.5KB.
// Given that xz can compress it to ~1.8KB, it could be probably represented in an even more compact way...
const rune_maps = [ i32(0xB5), 0xB5, 743, 0, // this being on the same line, is needed as a workaround for a bug in v2's parser
	0xC0, 0xD6, 0, 32,
	0xD8, 0xDE, 0, 32,
	0xE0, 0xF6, -32, 0,
	0xF8, 0xFE, -32, 0,
	0xFF, 0xFF, 121, 0,
	0x100, 0x12F, -3, -3,
	0x130, 0x130, 0, -199,
	0x131, 0x131, -232, 0,
	0x132, 0x137, -3, -3,
	0x139, 0x148, -3, -3,
	0x14A, 0x177, -3, -3,
	0x178, 0x178, 0, -121,
	0x179, 0x17E, -3, -3,
	0x17F, 0x17F, -300, 0,
	0x180, 0x180, 195, 0,
	0x181, 0x181, 0, 210,
	0x182, 0x185, -3, -3,
	0x186, 0x186, 0, 206,
	0x187, 0x188, -3, -3,
	0x189, 0x18A, 0, 205,
	0x18B, 0x18C, -3, -3,
	0x18E, 0x18E, 0, 79,
	0x18F, 0x18F, 0, 202,
	0x190, 0x190, 0, 203,
	0x191, 0x192, -3, -3,
	0x193, 0x193, 0, 205,
	0x194, 0x194, 0, 207,
	0x195, 0x195, 97, 0,
	0x196, 0x196, 0, 211,
	0x197, 0x197, 0, 209,
	0x198, 0x199, -3, -3,
	0x19A, 0x19A, 163, 0,
	0x19C, 0x19C, 0, 211,
	0x19D, 0x19D, 0, 213,
	0x19E, 0x19E, 130, 0,
	0x19F, 0x19F, 0, 214,
	0x1A0, 0x1A5, -3, -3,
	0x1A6, 0x1A6, 0, 218,
	0x1A7, 0x1A8, -3, -3,
	0x1A9, 0x1A9, 0, 218,
	0x1AC, 0x1AD, -3, -3,
	0x1AE, 0x1AE, 0, 218,
	0x1AF, 0x1B0, -3, -3,
	0x1B1, 0x1B2, 0, 217,
	0x1B3, 0x1B6, -3, -3,
	0x1B7, 0x1B7, 0, 219,
	0x1B8, 0x1B9, -3, -3,
	0x1BC, 0x1BD, -3, -3,
	0x1BF, 0x1BF, 56, 0,
	0x1C4, 0x1CC, -2, -2,
	0x1CD, 0x1DC, -3, -3,
	0x1DD, 0x1DD, -79, 0,
	0x1DE, 0x1EF, -3, -3,
	0x1F1, 0x1F3, -2, -2,
	0x1F4, 0x1F5, -3, -3,
	0x1F6, 0x1F6, 0, -97,
	0x1F7, 0x1F7, 0, -56,
	0x1F8, 0x21F, -3, -3,
	0x220, 0x220, 0, -130,
	0x222, 0x233, -3, -3,
	0x23A, 0x23A, 0, 10795,
	0x23B, 0x23C, -3, -3,
	0x23D, 0x23D, 0, -163,
	0x23E, 0x23E, 0, 10792,
	0x23F, 0x240, 10815, 0,
	0x241, 0x242, -3, -3,
	0x243, 0x243, 0, -195,
	0x244, 0x244, 0, 69,
	0x245, 0x245, 0, 71,
	0x246, 0x24F, -3, -3,
	0x250, 0x250, 10783, 0,
	0x251, 0x251, 10780, 0,
	0x252, 0x252, 10782, 0,
	0x253, 0x253, -210, 0,
	0x254, 0x254, -206, 0,
	0x256, 0x257, -205, 0,
	0x259, 0x259, -202, 0,
	0x25B, 0x25B, -203, 0,
	0x25C, 0x25C, 42319, 0,
	0x260, 0x260, -205, 0,
	0x261, 0x261, 42315, 0,
	0x263, 0x263, -207, 0,
	0x265, 0x265, 42280, 0,
	0x266, 0x266, 42308, 0,
	0x268, 0x268, -209, 0,
	0x269, 0x269, -211, 0,
	0x26A, 0x26A, 42308, 0,
	0x26B, 0x26B, 10743, 0,
	0x26C, 0x26C, 42305, 0,
	0x26F, 0x26F, -211, 0,
	0x271, 0x271, 10749, 0,
	0x272, 0x272, -213, 0,
	0x275, 0x275, -214, 0,
	0x27D, 0x27D, 10727, 0,
	0x280, 0x280, -218, 0,
	0x282, 0x282, 42307, 0,
	0x283, 0x283, -218, 0,
	0x287, 0x287, 42282, 0,
	0x288, 0x288, -218, 0,
	0x289, 0x289, -69, 0,
	0x28A, 0x28B, -217, 0,
	0x28C, 0x28C, -71, 0,
	0x292, 0x292, -219, 0,
	0x29D, 0x29D, 42261, 0,
	0x29E, 0x29E, 42258, 0,
	0x345, 0x345, 84, 0,
	0x370, 0x373, -3, -3,
	0x376, 0x377, -3, -3,
	0x37B, 0x37D, 130, 0,
	0x37F, 0x37F, 0, 116,
	0x386, 0x386, 0, 38,
	0x388, 0x38A, 0, 37,
	0x38C, 0x38C, 0, 64,
	0x38E, 0x38F, 0, 63,
	0x391, 0x3A1, 0, 32,
	0x3A3, 0x3AB, 0, 32,
	0x3AC, 0x3AC, -38, 0,
	0x3AD, 0x3AF, -37, 0,
	0x3B1, 0x3C1, -32, 0,
	0x3C2, 0x3C2, -31, 0,
	0x3C3, 0x3CB, -32, 0,
	0x3CC, 0x3CC, -64, 0,
	0x3CD, 0x3CE, -63, 0,
	0x3CF, 0x3CF, 0, 8,
	0x3D0, 0x3D0, -62, 0,
	0x3D1, 0x3D1, -57, 0,
	0x3D5, 0x3D5, -47, 0,
	0x3D6, 0x3D6, -54, 0,
	0x3D7, 0x3D7, -8, 0,
	0x3D8, 0x3EF, -3, -3,
	0x3F0, 0x3F0, -86, 0,
	0x3F1, 0x3F1, -80, 0,
	0x3F2, 0x3F2, 7, 0,
	0x3F3, 0x3F3, -116, 0,
	0x3F4, 0x3F4, 0, -60,
	0x3F5, 0x3F5, -96, 0,
	0x3F7, 0x3F8, -3, -3,
	0x3F9, 0x3F9, 0, -7,
	0x3FA, 0x3FB, -3, -3,
	0x3FD, 0x3FF, 0, -130,
	0x400, 0x40F, 0, 80,
	0x410, 0x42F, 0, 32,
	0x430, 0x44F, -32, 0,
	0x450, 0x45F, -80, 0,
	0x460, 0x481, -3, -3,
	0x48A, 0x4BF, -3, -3,
	0x4C0, 0x4C0, 0, 15,
	0x4C1, 0x4CE, -3, -3,
	0x4CF, 0x4CF, -15, 0,
	0x4D0, 0x52F, -3, -3,
	0x531, 0x556, 0, 48,
	0x561, 0x586, -48, 0,
	0x10A0, 0x10C5, 0, 7264,
	0x10C7, 0x10C7, 0, 7264,
	0x10CD, 0x10CD, 0, 7264,
	0x10D0, 0x10FA, 3008, 0,
	0x10FD, 0x10FF, 3008, 0,
	0x13A0, 0x13EF, 0, 38864,
	0x13F0, 0x13F5, 0, 8,
	0x13F8, 0x13FD, -8, 0,
	0x1C80, 0x1C80, -6254, 0,
	0x1C81, 0x1C81, -6253, 0,
	0x1C82, 0x1C82, -6244, 0,
	0x1C83, 0x1C84, -6242, 0,
	0x1C85, 0x1C85, -6243, 0,
	0x1C86, 0x1C86, -6236, 0,
	0x1C87, 0x1C87, -6181, 0,
	0x1C88, 0x1C88, 35266, 0,
	0x1C90, 0x1CBA, 0, -3008,
	0x1CBD, 0x1CBF, 0, -3008,
	0x1D79, 0x1D79, 35332, 0,
	0x1D7D, 0x1D7D, 3814, 0,
	0x1D8E, 0x1D8E, 35384, 0,
	0x1E00, 0x1E95, -3, -3,
	0x1E9B, 0x1E9B, -59, 0,
	0x1E9E, 0x1E9E, 0, -7615,
	0x1EA0, 0x1EFF, -3, -3,
	0x1F00, 0x1F07, 8, 0,
	0x1F08, 0x1F0F, 0, -8,
	0x1F10, 0x1F15, 8, 0,
	0x1F18, 0x1F1D, 0, -8,
	0x1F20, 0x1F27, 8, 0,
	0x1F28, 0x1F2F, 0, -8,
	0x1F30, 0x1F37, 8, 0,
	0x1F38, 0x1F3F, 0, -8,
	0x1F40, 0x1F45, 8, 0,
	0x1F48, 0x1F4D, 0, -8,
	0x1F51, 0x1F51, 8, 0,
	0x1F53, 0x1F53, 8, 0,
	0x1F55, 0x1F55, 8, 0,
	0x1F57, 0x1F57, 8, 0,
	0x1F59, 0x1F59, 0, -8,
	0x1F5B, 0x1F5B, 0, -8,
	0x1F5D, 0x1F5D, 0, -8,
	0x1F5F, 0x1F5F, 0, -8,
	0x1F60, 0x1F67, 8, 0,
	0x1F68, 0x1F6F, 0, -8,
	0x1F70, 0x1F71, 74, 0,
	0x1F72, 0x1F75, 86, 0,
	0x1F76, 0x1F77, 100, 0,
	0x1F78, 0x1F79, 128, 0,
	0x1F7A, 0x1F7B, 112, 0,
	0x1F7C, 0x1F7D, 126, 0,
	0x1F80, 0x1F87, 8, 0,
	0x1F88, 0x1F8F, 0, -8,
	0x1F90, 0x1F97, 8, 0,
	0x1F98, 0x1F9F, 0, -8,
	0x1FA0, 0x1FA7, 8, 0,
	0x1FA8, 0x1FAF, 0, -8,
	0x1FB0, 0x1FB1, 8, 0,
	0x1FB3, 0x1FB3, 9, 0,
	0x1FB8, 0x1FB9, 0, -8,
	0x1FBA, 0x1FBB, 0, -74,
	0x1FBC, 0x1FBC, 0, -9,
	0x1FBE, 0x1FBE, -7205, 0,
	0x1FC3, 0x1FC3, 9, 0,
	0x1FC8, 0x1FCB, 0, -86,
	0x1FCC, 0x1FCC, 0, -9,
	0x1FD0, 0x1FD1, 8, 0,
	0x1FD8, 0x1FD9, 0, -8,
	0x1FDA, 0x1FDB, 0, -100,
	0x1FE0, 0x1FE1, 8, 0,
	0x1FE5, 0x1FE5, 7, 0,
	0x1FE8, 0x1FE9, 0, -8,
	0x1FEA, 0x1FEB, 0, -112,
	0x1FEC, 0x1FEC, 0, -7,
	0x1FF3, 0x1FF3, 9, 0,
	0x1FF8, 0x1FF9, 0, -128,
	0x1FFA, 0x1FFB, 0, -126,
	0x1FFC, 0x1FFC, 0, -9,
	0x2126, 0x2126, 0, -7517,
	0x212A, 0x212A, 0, -8383,
	0x212B, 0x212B, 0, -8262,
	0x2132, 0x2132, 0, 28,
	0x214E, 0x214E, -28, 0,
	0x2160, 0x216F, 0, 16,
	0x2170, 0x217F, -16, 0,
	0x2183, 0x2184, -3, -3,
	0x24B6, 0x24CF, 0, 26,
	0x24D0, 0x24E9, -26, 0,
	0x2C00, 0x2C2F, 0, 48,
	0x2C30, 0x2C5F, -48, 0,
	0x2C60, 0x2C61, -3, -3,
	0x2C62, 0x2C62, 0, -10743,
	0x2C63, 0x2C63, 0, -3814,
	0x2C64, 0x2C64, 0, -10727,
	0x2C65, 0x2C65, -10795, 0,
	0x2C66, 0x2C66, -10792, 0,
	0x2C67, 0x2C6C, -3, -3,
	0x2C6D, 0x2C6D, 0, -10780,
	0x2C6E, 0x2C6E, 0, -10749,
	0x2C6F, 0x2C6F, 0, -10783,
	0x2C70, 0x2C70, 0, -10782,
	0x2C72, 0x2C73, -3, -3,
	0x2C75, 0x2C76, -3, -3,
	0x2C7E, 0x2C7F, 0, -10815,
	0x2C80, 0x2CE3, -3, -3,
	0x2CEB, 0x2CEE, -3, -3,
	0x2CF2, 0x2CF3, -3, -3,
	0x2D00, 0x2D25, -7264, 0,
	0x2D27, 0x2D27, -7264, 0,
	0x2D2D, 0x2D2D, -7264, 0,
	0xA640, 0xA66D, -3, -3,
	0xA680, 0xA69B, -3, -3,
	0xA722, 0xA72F, -3, -3,
	0xA732, 0xA76F, -3, -3,
	0xA779, 0xA77C, -3, -3,
	0xA77D, 0xA77D, 0, -35332,
	0xA77E, 0xA787, -3, -3,
	0xA78B, 0xA78C, -3, -3,
	0xA78D, 0xA78D, 0, -42280,
	0xA790, 0xA793, -3, -3,
	0xA794, 0xA794, 48, 0,
	0xA796, 0xA7A9, -3, -3,
	0xA7AA, 0xA7AA, 0, -42308,
	0xA7AB, 0xA7AB, 0, -42319,
	0xA7AC, 0xA7AC, 0, -42315,
	0xA7AD, 0xA7AD, 0, -42305,
	0xA7AE, 0xA7AE, 0, -42308,
	0xA7B0, 0xA7B0, 0, -42258,
	0xA7B1, 0xA7B1, 0, -42282,
	0xA7B2, 0xA7B2, 0, -42261,
	0xA7B3, 0xA7B3, 0, 928,
	0xA7B4, 0xA7C3, -3, -3,
	0xA7C4, 0xA7C4, 0, -48,
	0xA7C5, 0xA7C5, 0, -42307,
	0xA7C6, 0xA7C6, 0, -35384,
	0xA7C7, 0xA7CA, -3, -3,
	0xA7D0, 0xA7D1, -3, -3,
	0xA7D6, 0xA7D9, -3, -3,
	0xA7F5, 0xA7F6, -3, -3,
	0xAB53, 0xAB53, -928, 0,
	0xAB70, 0xABBF, -38864, 0,
	0xFF21, 0xFF3A, 0, 32,
	0xFF41, 0xFF5A, -32, 0,
	0x10400, 0x10427, 0, 40,
	0x10428, 0x1044F, -40, 0,
	0x104B0, 0x104D3, 0, 40,
	0x104D8, 0x104FB, -40, 0,
	0x10570, 0x1057A, 0, 39,
	0x1057C, 0x1058A, 0, 39,
	0x1058C, 0x10592, 0, 39,
	0x10594, 0x10595, 0, 39,
	0x10597, 0x105A1, -39, 0,
	0x105A3, 0x105B1, -39, 0,
	0x105B3, 0x105B9, -39, 0,
	0x105BB, 0x105BC, -39, 0,
	0x10C80, 0x10CB2, 0, 64,
	0x10CC0, 0x10CF2, -64, 0,
	0x118A0, 0x118BF, 0, 32,
	0x118C0, 0x118DF, -32, 0,
	0x16E40, 0x16E5F, 0, 32,
	0x16E60, 0x16E7F, -32, 0,
	0x1E900, 0x1E921, 0, 34,
	0x1E922, 0x1E943, -34, 0,
]!
// vfmt on

///////////// module builtin

// B-trees are balanced search trees with all leaves at
// the same level. B-trees are generally faster than
// binary search trees due to the better locality of
// reference, since multiple keys are stored in one node.

// The number for `degree` has been picked through vigor-
// ous benchmarking but can be changed to any number > 1.
// `degree` determines the maximum length of each node.
// TODO: the @[markused] tag here is needed as a workaround for
// compilation with `-cc clang -usecache`; added in https://github.com/vlang/v/pull/25034

@[markused]
const degree = 6
const mid_index = degree - 1
const max_len = 2 * degree - 1
const children_bytes = sizeof(voidptr) * (max_len + 1)

pub struct SortedMap {
	value_bytes int
mut:
	root &mapnode
pub mut:
	len int
}

struct mapnode {
mut:
	children &voidptr
	len      int
	keys     [11]string  // TODO: Should use `max_len`
	values   [11]voidptr // TODO: Should use `max_len`
}

fn new_sorted_map(n int, value_bytes int) SortedMap { // TODO: Remove `n`
	return SortedMap{
		value_bytes: value_bytes
		root:        new_node()
		len:         0
	}
}

fn new_sorted_map_init(n int, value_bytes int, keys &string, values voidptr) SortedMap {
	mut out := new_sorted_map(n, value_bytes)
	for i in 0 .. n {
		unsafe {
			out.set(keys[i], &u8(values) + i * value_bytes)
		}
	}
	return out
}

// The tree is initialized with an empty node as root to
// avoid having to check whether the root is null for
// each insertion.
fn new_node() &mapnode {
	return &mapnode{
		children: unsafe { nil }
		len:      0
	}
}

// This implementation does proactive insertion, meaning
// that splits are done top-down and not bottom-up.
fn (mut m SortedMap) set(key string, value voidptr) {
	mut node := m.root
	mut child_index := 0
	mut parent := &mapnode(unsafe { nil })
	for {
		if node.len == max_len {
			if parent == unsafe { nil } {
				parent = new_node()
				m.root = parent
			}
			parent.split_child(child_index, mut node)
			if key == parent.keys[child_index] {
				unsafe {
					vmemcpy(parent.values[child_index], value, m.value_bytes)
				}
				return
			}
			if key < parent.keys[child_index] {
				node = unsafe { &mapnode(parent.children[child_index]) }
			} else {
				node = unsafe { &mapnode(parent.children[child_index + 1]) }
			}
		}
		mut i := 0
		for i < node.len && key > node.keys[i] {
			i++
		}
		if i != node.len && key == node.keys[i] {
			unsafe {
				vmemcpy(node.values[i], value, m.value_bytes)
			}
			return
		}
		if node.children == unsafe { nil } {
			mut j := node.len - 1
			for j >= 0 && key < node.keys[j] {
				node.keys[j + 1] = node.keys[j]
				node.values[j + 1] = node.values[j]
				j--
			}
			node.keys[j + 1] = key
			unsafe {
				node.values[j + 1] = malloc(m.value_bytes)
				vmemcpy(node.values[j + 1], value, m.value_bytes)
			}
			node.len++
			m.len++
			return
		}
		parent = node
		child_index = i
		node = unsafe { &mapnode(node.children[child_index]) }
	}
}

fn (mut n mapnode) split_child(child_index int, mut y mapnode) {
	mut z := new_node()
	z.len = mid_index
	y.len = mid_index
	for j := mid_index - 1; j >= 0; j-- {
		z.keys[j] = y.keys[j + degree]
		z.values[j] = y.values[j + degree]
	}
	if y.children != unsafe { nil } {
		z.children = unsafe { &voidptr(malloc(int(children_bytes))) }
		for jj := degree - 1; jj >= 0; jj-- {
			unsafe {
				z.children[jj] = y.children[jj + degree]
			}
		}
	}
	unsafe {
		if n.children == nil {
			n.children = &voidptr(malloc(int(children_bytes)))
		}
		n.children[n.len + 1] = n.children[n.len]
	}
	for j := n.len; j > child_index; j-- {
		n.keys[j] = n.keys[j - 1]
		n.values[j] = n.values[j - 1]
		unsafe {
			n.children[j] = n.children[j - 1]
		}
	}
	n.keys[child_index] = y.keys[mid_index]
	n.values[child_index] = y.values[mid_index]
	unsafe {
		n.children[child_index] = voidptr(y)
		n.children[child_index + 1] = voidptr(z)
	}
	n.len++
}

@[direct_array_access]
fn (m SortedMap) get(key string, out voidptr) bool {
	mut node := m.root
	for {
		mut i := node.len - 1
		for i >= 0 && key < node.keys[i] {
			i--
		}
		if i != -1 && key == node.keys[i] {
			unsafe {
				vmemcpy(out, node.values[i], m.value_bytes)
			}
			return true
		}
		if node.children == unsafe { nil } {
			break
		}
		node = unsafe { &mapnode(node.children[i + 1]) }
	}
	return false
}

fn (m SortedMap) exists(key string) bool {
	if m.root == unsafe { nil } { // TODO: find out why root can be nil
		return false
	}
	mut node := m.root
	for {
		mut i := node.len - 1
		for i >= 0 && key < node.keys[i] {
			i--
		}
		if i != -1 && key == node.keys[i] {
			return true
		}
		if node.children == unsafe { nil } {
			break
		}
		node = unsafe { &mapnode(node.children[i + 1]) }
	}
	return false
}

fn (n &mapnode) find_key(k string) int {
	mut idx := 0
	for idx < n.len && n.keys[idx] < k {
		idx++
	}
	return idx
}

fn (mut n mapnode) remove_key(k string) bool {
	idx := n.find_key(k)
	if idx < n.len && n.keys[idx] == k {
		if n.children == unsafe { nil } {
			n.remove_from_leaf(idx)
		} else {
			n.remove_from_non_leaf(idx)
		}
		return true
	} else {
		if n.children == unsafe { nil } {
			return false
		}
		flag := if idx == n.len { true } else { false }
		if unsafe { &mapnode(n.children[idx]) }.len < degree {
			n.fill(idx)
		}

		mut node := &mapnode(unsafe { nil })
		if flag && idx > n.len {
			node = unsafe { &mapnode(n.children[idx - 1]) }
		} else {
			node = unsafe { &mapnode(n.children[idx]) }
		}
		return node.remove_key(k)
	}
}

fn (mut n mapnode) remove_from_leaf(idx int) {
	for i := idx + 1; i < n.len; i++ {
		n.keys[i - 1] = n.keys[i]
		n.values[i - 1] = n.values[i]
	}
	n.len--
}

fn (mut n mapnode) remove_from_non_leaf(idx int) {
	k := n.keys[idx]
	if unsafe { &mapnode(n.children[idx]) }.len >= degree {
		mut current := unsafe { &mapnode(n.children[idx]) }
		for current.children != unsafe { nil } {
			current = unsafe { &mapnode(current.children[current.len]) }
		}
		predecessor := current.keys[current.len - 1]
		n.keys[idx] = predecessor
		n.values[idx] = current.values[current.len - 1]
		mut node := unsafe { &mapnode(n.children[idx]) }
		node.remove_key(predecessor)
	} else if unsafe { &mapnode(n.children[idx + 1]) }.len >= degree {
		mut current := unsafe { &mapnode(n.children[idx + 1]) }
		for current.children != unsafe { nil } {
			current = unsafe { &mapnode(current.children[0]) }
		}
		successor := current.keys[0]
		n.keys[idx] = successor
		n.values[idx] = current.values[0]
		mut node := unsafe { &mapnode(n.children[idx + 1]) }
		node.remove_key(successor)
	} else {
		n.merge(idx)
		mut node := unsafe { &mapnode(n.children[idx]) }
		node.remove_key(k)
	}
}

fn (mut n mapnode) fill(idx int) {
	if idx != 0 && unsafe { &mapnode(n.children[idx - 1]) }.len >= degree {
		n.borrow_from_prev(idx)
	} else if idx != n.len && unsafe { &mapnode(n.children[idx + 1]) }.len >= degree {
		n.borrow_from_next(idx)
	} else if idx != n.len {
		n.merge(idx)
	} else {
		n.merge(idx - 1)
	}
}

fn (mut n mapnode) borrow_from_prev(idx int) {
	mut child := unsafe { &mapnode(n.children[idx]) }
	mut sibling := unsafe { &mapnode(n.children[idx - 1]) }
	for i := child.len - 1; i >= 0; i-- {
		child.keys[i + 1] = child.keys[i]
		child.values[i + 1] = child.values[i]
	}
	if child.children != unsafe { nil } {
		for i := child.len; i >= 0; i-- {
			unsafe {
				child.children[i + 1] = child.children[i]
			}
		}
	}
	child.keys[0] = n.keys[idx - 1]
	child.values[0] = n.values[idx - 1]
	if child.children != unsafe { nil } {
		unsafe {
			child.children[0] = sibling.children[sibling.len]
		}
	}
	n.keys[idx - 1] = sibling.keys[sibling.len - 1]
	n.values[idx - 1] = sibling.values[sibling.len - 1]
	child.len++
	sibling.len--
}

fn (mut n mapnode) borrow_from_next(idx int) {
	mut child := unsafe { &mapnode(n.children[idx]) }
	mut sibling := unsafe { &mapnode(n.children[idx + 1]) }
	child.keys[child.len] = n.keys[idx]
	child.values[child.len] = n.values[idx]
	if child.children != unsafe { nil } {
		unsafe {
			child.children[child.len + 1] = sibling.children[0]
		}
	}
	n.keys[idx] = sibling.keys[0]
	n.values[idx] = sibling.values[0]
	for i := 1; i < sibling.len; i++ {
		sibling.keys[i - 1] = sibling.keys[i]
		sibling.values[i - 1] = sibling.values[i]
	}
	if sibling.children != unsafe { nil } {
		for i := 1; i <= sibling.len; i++ {
			unsafe {
				sibling.children[i - 1] = sibling.children[i]
			}
		}
	}
	child.len++
	sibling.len--
}

fn (mut n mapnode) merge(idx int) {
	mut child := unsafe { &mapnode(n.children[idx]) }
	sibling := unsafe { &mapnode(n.children[idx + 1]) }
	child.keys[mid_index] = n.keys[idx]
	child.values[mid_index] = n.values[idx]
	for i in 0 .. sibling.len {
		child.keys[i + degree] = sibling.keys[i]
		child.values[i + degree] = sibling.values[i]
	}
	if child.children != unsafe { nil } {
		for i := 0; i <= sibling.len; i++ {
			unsafe {
				child.children[i + degree] = sibling.children[i]
			}
		}
	}
	for i := idx + 1; i < n.len; i++ {
		n.keys[i - 1] = n.keys[i]
		n.values[i - 1] = n.values[i]
	}
	for i := idx + 2; i <= n.len; i++ {
		unsafe {
			n.children[i - 1] = n.children[i]
		}
	}
	child.len += sibling.len + 1
	n.len--
	// free(sibling)
}

pub fn (mut m SortedMap) delete(key string) {
	if m.root.len == 0 {
		return
	}

	removed := m.root.remove_key(key)
	if removed {
		m.len--
	}

	if m.root.len == 0 {
		// tmp := t.root
		if m.root.children == unsafe { nil } {
			return
		} else {
			m.root = unsafe { &mapnode(m.root.children[0]) }
		}
		// free(tmp)
	}
}

// Insert all keys of the subtree into array `keys`
// starting at `at`. Keys are inserted in order.
fn (n &mapnode) subkeys(mut keys []string, at int) int {
	mut position := at
	if n.children != unsafe { nil } {
		// Traverse children and insert
		// keys inbetween children
		for i in 0 .. n.len {
			child := unsafe { &mapnode(n.children[i]) }
			position += child.subkeys(mut keys, position)
			keys[position] = n.keys[i]
			position++
		}
		// Insert the keys of the last child
		child := unsafe { &mapnode(n.children[n.len]) }
		position += child.subkeys(mut keys, position)
	} else {
		// If leaf, insert keys
		for i in 0 .. n.len {
			keys[position + i] = n.keys[i]
		}
		position += n.len
	}
	// Return # of added keys
	return position - at
}

pub fn (m &SortedMap) keys() []string {
	mut keys := []string{len: m.len}
	if m.root == unsafe { nil } || m.root.len == 0 {
		return keys
	}
	m.root.subkeys(mut keys, 0)
	return keys
}

fn (mut n mapnode) free() {
	// TODO
}

pub fn (mut m SortedMap) free() {
	if m.root == unsafe { nil } {
		return
	}
	m.root.free()
}

///////////// module builtin

/*
Note: A V string should be/is immutable from the point of view of
    V user programs after it is first created. A V string is
    also slightly larger than the equivalent C string because
    the V string also has an integer length attached.

    This tradeoff is made, since V strings are created just *once*,
    but potentially used *many times* over their lifetime.

    The V string implementation uses a struct, that has a .str field,
    which points to a C style 0 terminated memory block. Although not
    strictly necessary from the V point of view, that additional 0
    is *very useful for C interoperability*.

    The V string implementation also has an integer .len field,
    containing the length of the .str field, excluding the
    terminating 0 (just like the C's strlen(s) would do).

    The 0 ending of .str, and the .len field, mean that in practice:
      a) a V string s can be used very easily, wherever a
         C string is needed, just by passing s.str,
         without a need for further conversion/copying.

      b) where strlen(s) is needed, you can just pass s.len,
         without having to constantly recompute the length of s
         *over and over again* like some C programs do. This is because
         V strings are immutable and so their length does not change.

    Ordinary V code *does not need* to be concerned with the
    additional 0 in the .str field. The 0 *must* be put there by the
    low level string creating functions inside this module.

    Failing to do this will lead to programs that work most of the
    time, when used with pure V functions, but fail in strange ways,
    when used with modules using C functions (for example os and so on).
*/
pub struct string {
pub:
	str &u8 = 0 // points to a C style 0 terminated string of bytes.
	len int // the length of the .str field, excluding the ending 0 byte. It is always equal to strlen(.str).
mut:
	is_lit int
	// NB string.is_lit is an enumeration of the following:
	// .is_lit == 0 => a fresh string, should be freed by autofree
	// .is_lit == 1 => a literal string from .rodata, should NOT be freed
	// .is_lit == -98761234 => already freed string, protects against double frees.
	// ---------> ^^^^^^^^^ calling free on these is a bug.
	// Any other value means that the string has been corrupted.
}

// runes returns an array of all the utf runes in the string `s`
// which is useful if you want random access to them
@[direct_array_access]
pub fn (s string) runes() []rune {
	mut runes := []rune{cap: s.len}
	for i := 0; i < s.len; i++ {
		char_len := utf8_char_len(unsafe { s.str[i] })
		if char_len > 1 {
			end := if s.len - 1 >= i + char_len { i + char_len } else { s.len }
			mut r := unsafe { s[i..end] }
			runes << r.utf32_code()
			i += char_len - 1
		} else {
			runes << unsafe { s.str[i] }
		}
	}
	return runes
}

// cstring_to_vstring creates a new V string copy of the C style string,
// pointed by `s`. This function is most likely what you want to use when
// working with C style pointers to 0 terminated strings (i.e. `char*`).
// It is recommended to use it, unless you *do* understand the implications of
// tos/tos2/tos3/tos4/tos5 in terms of memory management and interactions with
// -autofree and `@[manualfree]`.
// It will panic, if the pointer `s` is 0.
@[unsafe]
pub fn cstring_to_vstring(const_s &char) string {
	return unsafe { tos2(&u8(const_s)) }.clone()
}

// tos_clone creates a new V string copy of the C style string, pointed by `s`.
// See also cstring_to_vstring (it is the same as it, the only difference is,
// that tos_clone expects `&u8`, while cstring_to_vstring expects &char).
// It will panic, if the pointer `s` is 0.
@[unsafe]
pub fn tos_clone(const_s &u8) string {
	return unsafe { tos2(&u8(const_s)) }.clone()
}

// tos creates a V string, given a C style pointer to a 0 terminated block.
// Note: the memory block pointed by s is *reused, not copied*!
// It will panic, when the pointer `s` is 0.
// See also `tos_clone`.
@[unsafe]
pub fn tos(s &u8, len int) string {
	if s == 0 {
		panic('tos(): nil string')
	}
	return string{
		str: unsafe { s }
		len: len
	}
}

// tos2 creates a V string, given a C style pointer to a 0 terminated block.
// Note: the memory block pointed by s is *reused, not copied*!
// It will calculate the length first, thus it is more costly than `tos`.
// It will panic, when the pointer `s` is 0.
// It is the same as `tos3`, but for &u8 pointers, avoiding callsite casts.
// See also `tos_clone`.
@[unsafe]
pub fn tos2(s &u8) string {
	if s == 0 {
		panic('tos2: nil string')
	}
	return string{
		str: unsafe { s }
		len: unsafe { vstrlen(s) }
	}
}

// tos3 creates a V string, given a C style pointer to a 0 terminated block.
// Note: the memory block pointed by s is *reused, not copied*!
// It will calculate the length first, so it is more costly than tos.
// It will panic, when the pointer `s` is 0.
// It is the same as `tos2`, but for &char pointers, avoiding callsite casts.
// See also `tos_clone`.
@[unsafe]
pub fn tos3(s &char) string {
	if s == 0 {
		panic('tos3: nil string')
	}
	return string{
		str: unsafe { &u8(s) }
		len: unsafe { vstrlen_char(s) }
	}
}

// tos4 creates a V string, given a C style pointer to a 0 terminated block.
// Note: the memory block pointed by s is *reused, not copied*!
// It will calculate the length first, so it is more costly than tos.
// It returns '', when given a 0 pointer `s`, it does NOT panic.
// It is the same as `tos5`, but for &u8 pointers, avoiding callsite casts.
// See also `tos_clone`.
@[unsafe]
pub fn tos4(s &u8) string {
	if s == 0 {
		return ''
	}
	return string{
		str: unsafe { s }
		len: unsafe { vstrlen(s) }
	}
}

// tos5 creates a V string, given a C style pointer to a 0 terminated block.
// Note: the memory block pointed by s is *reused, not copied*!
// It will calculate the length first, so it is more costly than tos.
// It returns '', when given a 0 pointer `s`, it does NOT panic.
// It is the same as `tos4`, but for &char pointers, avoiding callsite casts.
// See also `tos_clone`.
@[unsafe]
pub fn tos5(s &char) string {
	if s == 0 {
		return ''
	}
	return string{
		str: unsafe { &u8(s) }
		len: unsafe { vstrlen_char(s) }
	}
}

// vstring converts a C style string to a V string.
// Note: the memory block pointed by `bp` is *reused, not copied*!
// Note: instead of `&u8(arr.data).vstring()`, do use `tos_clone(&u8(arr.data))`.
// Strings returned from this function will be normal V strings beside that,
// (i.e. they would be freed by V's -autofree mechanism, when they are no longer used).
// See also `tos_clone`.
@[unsafe]
pub fn (bp &u8) vstring() string {
	return string{
		str: unsafe { bp }
		len: unsafe { vstrlen(bp) }
	}
}

// vstring_with_len converts a C style 0 terminated string to a V string.
// Note: the memory block pointed by `bp` is *reused, not copied*!
// This method has lower overhead compared to .vstring(), since it
// does not need to calculate the length of the 0 terminated string.
// See also `tos_clone`.
@[unsafe]
pub fn (bp &u8) vstring_with_len(len int) string {
	return string{
		str:    unsafe { bp }
		len:    len
		is_lit: 0
	}
}

// vstring converts a C style string to a V string.
// Note: the memory block pointed by `bp` is *reused, not copied*!
// Strings returned from this function will be normal V strings beside that,
// (i.e. they would be freed by V's -autofree mechanism, when they are
// no longer used).
// Note: instead of `&u8(a.data).vstring()`, use `tos_clone(&u8(a.data))`.
// See also `tos_clone`.
@[unsafe]
pub fn (cp &char) vstring() string {
	return string{
		str:    &u8(cp)
		len:    unsafe { vstrlen_char(cp) }
		is_lit: 0
	}
}

// vstring_with_len converts a C style 0 terminated string to a V string.
// Note: the memory block pointed by `bp` is *reused, not copied*!
// This method has lower overhead compared to .vstring(), since it
// does not calculate the length of the 0 terminated string.
// See also `tos_clone`.
@[unsafe]
pub fn (cp &char) vstring_with_len(len int) string {
	return string{
		str:    &u8(cp)
		len:    len
		is_lit: 0
	}
}

// vstring_literal converts a C style string to a V string.
// Note: the memory block pointed by `bp` is *reused, not copied*!
// NB2: unlike vstring, vstring_literal will mark the string
// as a literal, so it will not be freed by -autofree.
// This is suitable for readonly strings, C string literals etc,
// that can be read by the V program, but that should not be
// managed/freed by it, for example `os.args` is implemented using it.
// See also `tos_clone`.
@[unsafe]
pub fn (bp &u8) vstring_literal() string {
	return string{
		str:    unsafe { bp }
		len:    unsafe { vstrlen(bp) }
		is_lit: 1
	}
}

// vstring_with_len converts a C style string to a V string.
// Note: the memory block pointed by `bp` is *reused, not copied*!
// This method has lower overhead compared to .vstring_literal(), since it
// does not need to calculate the length of the 0 terminated string.
// See also `tos_clone`.
@[unsafe]
pub fn (bp &u8) vstring_literal_with_len(len int) string {
	return string{
		str:    unsafe { bp }
		len:    len
		is_lit: 1
	}
}

// vstring_literal converts a C style string char* pointer to a V string.
// Note: the memory block pointed by `bp` is *reused, not copied*!
// See also `byteptr.vstring_literal` for more details.
// See also `tos_clone`.
@[unsafe]
pub fn (cp &char) vstring_literal() string {
	return string{
		str:    &u8(cp)
		len:    unsafe { vstrlen_char(cp) }
		is_lit: 1
	}
}

// vstring_literal_with_len converts a C style string char* pointer,
// to a V string.
// Note: the memory block pointed by `bp` is *reused, not copied*!
// This method has lower overhead compared to .vstring_literal(), since it
// does not need to calculate the length of the 0 terminated string.
// See also `tos_clone`.
@[unsafe]
pub fn (cp &char) vstring_literal_with_len(len int) string {
	return string{
		str:    &u8(cp)
		len:    len
		is_lit: 1
	}
}

// len_utf8 returns the number of runes contained in the string `s`.
pub fn (s string) len_utf8() int {
	mut l := 0
	mut i := 0
	for i < s.len {
		l++
		i += ((0xe5000000 >> ((unsafe { s.str[i] } >> 3) & 0x1e)) & 3) + 1
	}
	return l
}

// is_pure_ascii returns whether the string contains only ASCII characters.
// Note that UTF8 encodes such characters in just 1 byte:
// 1 byte:  0xxxxxxx
// 2 bytes: 110xxxxx 10xxxxxx
// 3 bytes: 1110xxxx 10xxxxxx 10xxxxxx
// 4 bytes: 11110xxx 10xxxxxx 10xxxxxx 10xxxxxx
@[direct_array_access]
pub fn (s string) is_pure_ascii() bool {
	for i in 0 .. s.len {
		if s[i] >= 0x80 {
			return false
		}
	}
	return true
}

// clone_static returns an independent copy of a given array.
// It should be used only in -autofree generated code.
@[inline]
fn (a string) clone_static() string {
	return a.clone()
}

// option_clone_static returns an independent copy of a given array when lhs is an option type.
// It should be used only in -autofree generated code.
@[inline]
fn (a string) option_clone_static() ?string {
	return ?string(a.clone())
}

// clone returns a copy of the V string `a`.
pub fn (a string) clone() string {
	if a.len <= 0 {
		return ''
	}
	mut b := string{
		str: unsafe { malloc_noscan(a.len + 1) }
		len: a.len
	}
	unsafe {
		vmemcpy(b.str, a.str, a.len)
		b.str[a.len] = 0
	}
	return b
}

// replace_once replaces the first occurrence of `rep` with the string passed in `with`.
pub fn (s string) replace_once(rep string, with string) string {
	idx := s.index_(rep)
	if idx == -1 {
		return s.clone()
	}
	// return s.substr(0, idx) + with + s.substr(idx + rep.len, s.len)
	//
	// Avoid an extra allocation here by using substr_unsafe
	// string_plus copies from both strings via vmemcpy, so it's safe.
	//
	// return s.substr_unsafe(0, idx) + with + s.substr_unsafe(idx + rep.len, s.len)
	return s.substr_unsafe(0, idx).plus_two(with, s.substr_unsafe(idx + rep.len, s.len))
}

const replace_stack_buffer_size = 10
// replace replaces all occurrences of `rep` with the string passed in `with`.
@[direct_array_access; manualfree]
pub fn (s string) replace(rep string, with string) string {
	if s.len == 0 || rep.len == 0 || rep.len > s.len {
		return s.clone()
	}
	if !s.contains(rep) {
		return s.clone()
	}
	mut pidxs_len := 0
	pidxs_cap := s.len / rep.len
	mut stack_idxs := [replace_stack_buffer_size]int{}
	mut pidxs := unsafe { &stack_idxs[0] }
	if pidxs_cap > replace_stack_buffer_size {
		pidxs = unsafe { &int(malloc(int(sizeof(int)) * pidxs_cap)) }
	}
	defer {
		if pidxs_cap > replace_stack_buffer_size {
			unsafe { free(pidxs) }
		}
	}
	mut idx := 0
	for {
		idx = s.index_after_(rep, idx)
		if idx == -1 {
			break
		}
		unsafe {
			pidxs[pidxs_len] = idx
			pidxs_len++
		}
		idx += rep.len
	}
	// Dont change the string if there's nothing to replace
	if pidxs_len == 0 {
		return s.clone()
	}
	// Now we know the number of replacements we need to do and we can calc the len of the new string
	new_len := s.len + pidxs_len * (with.len - rep.len)
	mut b := unsafe { malloc_noscan(new_len + 1) } // add space for the null byte at the end
	// Fill the new string
	mut b_i := 0
	mut s_idx := 0
	for j in 0 .. pidxs_len {
		rep_pos := unsafe { pidxs[j] }
		// copy everything up to piece being replaced
		before_len := rep_pos - s_idx
		unsafe { vmemcpy(&b[b_i], &s.str[s_idx], before_len) }
		b_i += before_len
		s_idx = rep_pos + rep.len // move string index past replacement
		// copy replacement piece
		unsafe { vmemcpy(&b[b_i], &with.str[0], with.len) }
		b_i += with.len
	}
	if s_idx < s.len {
		// if any original after last replacement, copy it
		unsafe { vmemcpy(&b[b_i], &s.str[s_idx], s.len - s_idx) }
	}
	unsafe {
		b[new_len] = 0
		return tos(b, new_len)
	}
}

struct RepIndex {
	idx     int
	val_idx int
}

// replace_each replaces all occurrences of the string pairs given in `vals`.
// Example: assert 'ABCD'.replace_each(['B','C/','C','D','D','C']) == 'AC/DC'
@[direct_array_access]
pub fn (s string) replace_each(vals []string) string {
	if s.len == 0 || vals.len == 0 {
		return s.clone()
	}
	if vals.len % 2 != 0 {
		eprintln('string.replace_each(): odd number of strings')
		return s.clone()
	}
	// `rep` - string to replace
	// `with` - string to replace with
	// Remember positions of all rep strings, and calculate the length
	// of the new string to do just one allocation.
	mut new_len := s.len
	mut idxs := []RepIndex{cap: 6}
	defer { unsafe { idxs.free() } }
	mut idx := 0
	s_ := s.clone()
	for rep_i := 0; rep_i < vals.len; rep_i += 2 {
		// vals: ['rep1, 'with1', 'rep2', 'with2']
		rep := vals[rep_i]
		with := vals[rep_i + 1]

		for {
			idx = s_.index_after_(rep, idx)
			if idx == -1 {
				break
			}
			// The string already found is set to `/del`, to avoid duplicate searches.
			for i in 0 .. rep.len {
				unsafe {
					s_.str[idx + i] = 0
				}
			}
			// We need to remember both the position in the string,
			// and which rep/with pair it refers to.

			idxs << RepIndex{
				idx:     idx
				val_idx: rep_i
			}

			idx += rep.len
			new_len += with.len - rep.len
		}
	}

	// Dont change the string if there's nothing to replace
	if idxs.len == 0 {
		return s.clone()
	}
	idxs.sort(a.idx < b.idx)
	mut b := unsafe { malloc_noscan(new_len + 1) } // add space for 0 terminator
	// Fill the new string
	mut idx_pos := 0
	mut cur_idx := idxs[idx_pos]
	mut b_i := 0
	for i := 0; i < s.len; i++ {
		if i == cur_idx.idx {
			// Reached the location of rep, replace it with "with"
			rep := vals[cur_idx.val_idx]
			with := vals[cur_idx.val_idx + 1]
			for j in 0 .. with.len {
				unsafe {
					b[b_i] = with[j]
				}
				b_i++
			}
			// Skip the length of rep, since we just replaced it with "with"
			i += rep.len - 1
			// Go to the next index
			idx_pos++
			if idx_pos < idxs.len {
				cur_idx = idxs[idx_pos]
			}
		} else {
			// Rep doesnt start here, just copy
			unsafe {
				b[b_i] = s.str[i]
			}
			b_i++
		}
	}
	unsafe {
		b[new_len] = 0
		return tos(b, new_len)
	}
}

// replace_char replaces all occurrences of the character `rep`, with `repeat` x the character passed in `with`.
// Example: assert '\tHello!'.replace_char(`\t`,` `,8) == '        Hello!'
@[direct_array_access]
pub fn (s string) replace_char(rep u8, with u8, repeat int) string {
	$if !no_bounds_checking {
		if repeat <= 0 {
			panic('string.replace_char(): tab length too short')
		}
	}
	if s.len == 0 {
		return s.clone()
	}
	// TODO: Allocating ints is expensive. Should be a stack array
	// - string.replace()
	mut idxs := []int{cap: s.len >> 2}
	defer { unsafe { idxs.free() } }
	// No need to do a contains(), it already traverses the entire string
	for i, ch in s {
		if ch == rep { // Found char? Mark its location
			idxs << i
		}
	}
	if idxs.len == 0 {
		return s.clone()
	}
	// Now we know the number of replacements we need to do and we can calc the len of the new string
	new_len := s.len + idxs.len * (repeat - 1)
	mut b := unsafe { malloc_noscan(new_len + 1) } // add space for the null byte at the end
	// Fill the new string
	mut b_i := 0
	mut s_idx := 0
	for rep_pos in idxs {
		for i in s_idx .. rep_pos { // copy everything up to piece being replaced
			unsafe {
				b[b_i] = s[i]
			}
			b_i++
		}
		s_idx = rep_pos + 1 // move string index past replacement
		for _ in 0 .. repeat { // copy replacement piece
			unsafe {
				b[b_i] = with
			}
			b_i++
		}
	}
	if s_idx < s.len { // if any original after last replacement, copy it
		for i in s_idx .. s.len {
			unsafe {
				b[b_i] = s[i]
			}
			b_i++
		}
	}
	unsafe {
		b[new_len] = 0
		return tos(b, new_len)
	}
}

// normalize_tabs replaces all tab characters with `tab_len` amount of spaces.
// Example: assert '\t\tpop rax\t; pop rax'.normalize_tabs(2) == '    pop rax  ; pop rax'
@[inline]
pub fn (s string) normalize_tabs(tab_len int) string {
	return s.replace_char(`\t`, ` `, tab_len)
}

// expand_tabs replaces tab characters (\t) in the input string with spaces to achieve proper column alignment .
// Example: assert 'AB\tHello!'.expand_tabs(4) == 'AB  Hello!'
pub fn (s string) expand_tabs(tab_len int) string {
	if tab_len <= 0 {
		return s.clone() // Handle invalid tab length
	}
	mut output := strings.new_builder(s.len)
	mut column := 0
	for r in s.runes_iterator() {
		match r {
			`\t` {
				spaces := tab_len - (column % tab_len)
				output.write_string(' '.repeat(spaces))
				column += spaces
			}
			`\n`, `\r` {
				output.write_rune(r)
				column = 0 // Reset on any line break
			}
			else {
				output.write_rune(r)
				column++ // Valid for most chars; consider Unicode wide chars
			}
		}
	}
	return output.str()
}

// bool returns `true` if the string equals the word "true" it will return `false` otherwise.
@[inline]
pub fn (s string) bool() bool {
	return s == 'true' || s == 't' // TODO: t for pg, remove
}

// i8 returns the value of the string as i8 `'1'.i8() == i8(1)`.
@[inline]
pub fn (s string) i8() i8 {
	return i8(strconv.common_parse_int(s, 0, 8, false, false) or { 0 })
}

// i16 returns the value of the string as i16 `'1'.i16() == i16(1)`.
@[inline]
pub fn (s string) i16() i16 {
	return i16(strconv.common_parse_int(s, 0, 16, false, false) or { 0 })
}

// i32 returns the value of the string as i32 `'1'.i32() == i32(1)`.
@[inline]
pub fn (s string) i32() i32 {
	return i32(strconv.common_parse_int(s, 0, 32, false, false) or { 0 })
}

// int returns the value of the string as an integer `'1'.int() == 1`.
@[inline]
pub fn (s string) int() int {
	return int(strconv.common_parse_int(s, 0, 32, false, false) or { 0 })
}

// i64 returns the value of the string as i64 `'1'.i64() == i64(1)`.
@[inline]
pub fn (s string) i64() i64 {
	return strconv.common_parse_int(s, 0, 64, false, false) or { 0 }
}

// f32 returns the value of the string as f32 `'1.0'.f32() == f32(1)`.
@[inline]
pub fn (s string) f32() f32 {
	return f32(strconv.atof64(s, allow_extra_chars: true) or { 0 })
}

// f64 returns the value of the string as f64 `'1.0'.f64() == f64(1)`.
@[inline]
pub fn (s string) f64() f64 {
	return strconv.atof64(s, allow_extra_chars: true) or { 0 }
}

// u8_array returns the value of the hex/bin string as u8 array.
// hex string example: `'0x11223344ee'.u8_array() == [u8(0x11),0x22,0x33,0x44,0xee]`.
// bin string example: `'0b1101_1101'.u8_array() == [u8(0xdd)]`.
// underscore in the string will be stripped.
pub fn (s string) u8_array() []u8 {
	// strip underscore in the string
	mut tmps := s.replace('_', '')
	if tmps.len == 0 {
		return []u8{}
	}
	tmps = tmps.to_lower_ascii()
	if tmps.starts_with('0x') {
		tmps = tmps[2..]
		if tmps.len == 0 {
			return []u8{}
		}
		// make sure every digit is valid hex digit
		if !tmps.contains_only('0123456789abcdef') {
			return []u8{}
		}
		// make sure tmps has even hex digits
		if tmps.len % 2 == 1 {
			tmps = '0' + tmps
		}

		mut ret := []u8{len: tmps.len / 2}
		for i in 0 .. ret.len {
			ret[i] = u8(tmps[2 * i..2 * i + 2].parse_uint(16, 8) or { 0 })
		}
		return ret
	} else if tmps.starts_with('0b') {
		tmps = tmps[2..]
		if tmps.len == 0 {
			return []u8{}
		}
		// make sure every digit is valid binary digit
		if !tmps.contains_only('01') {
			return []u8{}
		}
		// make sure tmps has multiple of 8 binary digits
		if tmps.len % 8 != 0 {
			tmps = '0'.repeat(8 - tmps.len % 8) + tmps
		}

		mut ret := []u8{len: tmps.len / 8}
		for i in 0 .. ret.len {
			ret[i] = u8(tmps[8 * i..8 * i + 8].parse_uint(2, 8) or { 0 })
		}
		return ret
	}
	return []u8{}
}

// u8 returns the value of the string as u8 `'1'.u8() == u8(1)`.
@[inline]
pub fn (s string) u8() u8 {
	return u8(strconv.common_parse_uint(s, 0, 8, false, false) or { 0 })
}

// u16 returns the value of the string as u16 `'1'.u16() == u16(1)`.
@[inline]
pub fn (s string) u16() u16 {
	return u16(strconv.common_parse_uint(s, 0, 16, false, false) or { 0 })
}

// u32 returns the value of the string as u32 `'1'.u32() == u32(1)`.
@[inline]
pub fn (s string) u32() u32 {
	return u32(strconv.common_parse_uint(s, 0, 32, false, false) or { 0 })
}

// u64 returns the value of the string as u64 `'1'.u64() == u64(1)`.
@[inline]
pub fn (s string) u64() u64 {
	return strconv.common_parse_uint(s, 0, 64, false, false) or { 0 }
}

// parse_uint is like `parse_int` but for unsigned numbers
//
// This method directly exposes the `parse_uint` function from `strconv`
// as a method on `string`. For more advanced features,
// consider calling `strconv.common_parse_uint` directly.
@[inline]
pub fn (s string) parse_uint(_base int, _bit_size int) !u64 {
	return strconv.parse_uint(s, _base, _bit_size)
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
//
// This method directly exposes the `parse_int` function from `strconv`
// as a method on `string`. For more advanced features,
// consider calling `strconv.common_parse_int` directly.
@[inline]
pub fn (s string) parse_int(_base int, _bit_size int) !i64 {
	return strconv.parse_int(s, _base, _bit_size)
}

@[direct_array_access]
fn (s string) == (a string) bool {
	if s.str == 0 {
		// should never happen
		panic('string.eq(): nil string')
	}
	if s.len != a.len {
		return false
	}
	unsafe {
		return vmemcmp(s.str, a.str, a.len) == 0
	}
}

// compare returns -1 if `s` < `a`, 0 if `s` == `a`, and 1 if `s` > `a`
@[direct_array_access]
pub fn (s string) compare(a string) int {
	min_len := if s.len < a.len { s.len } else { a.len }
	for i in 0 .. min_len {
		if s[i] < a[i] {
			return -1
		}
		if s[i] > a[i] {
			return 1
		}
	}
	if s.len < a.len {
		return -1
	}
	if s.len > a.len {
		return 1
	}
	return 0
}

@[direct_array_access]
fn (s string) < (a string) bool {
	for i in 0 .. s.len {
		if i >= a.len || s[i] > a[i] {
			return false
		} else if s[i] < a[i] {
			return true
		}
	}
	if s.len < a.len {
		return true
	}
	return false
}

@[direct_array_access]
fn (s string) + (a string) string {
	new_len := a.len + s.len
	mut res := string{
		str: unsafe { malloc_noscan(new_len + 1) }
		len: new_len
	}
	unsafe {
		vmemcpy(res.str, s.str, s.len)
		vmemcpy(res.str + s.len, a.str, a.len)
	}
	unsafe {
		res.str[new_len] = 0 // V strings are not null terminated, but just in case
	}
	return res
}

// for `s + s2 + s3`, an optimization (faster than string_plus(string_plus(s1, s2), s3))
@[direct_array_access]
fn (s string) plus_two(a string, b string) string {
	new_len := a.len + b.len + s.len
	mut res := string{
		str: unsafe { malloc_noscan(new_len + 1) }
		len: new_len
	}
	unsafe {
		vmemcpy(res.str, s.str, s.len)
		vmemcpy(res.str + s.len, a.str, a.len)
		vmemcpy(res.str + s.len + a.len, b.str, b.len)
	}
	unsafe {
		res.str[new_len] = 0 // V strings are not null terminated, but just in case
	}
	return res
}

// split_any splits the string to an array by any of the `delim` chars.
// If the delimiter string is empty then `.split()` is used.
// Example: assert "first row\nsecond row".split_any(" \n") == ['first', 'row', 'second', 'row']
@[direct_array_access]
pub fn (s string) split_any(delim string) []string {
	mut res := []string{}
	unsafe { res.flags.set(.noslices) }
	defer { unsafe { res.flags.clear(.noslices) } }
	mut i := 0
	// check empty source string
	if s.len > 0 {
		// if empty delimiter string using default split
		if delim.len <= 0 {
			return s.split('')
		}
		for index, ch in s {
			for delim_ch in delim {
				if ch == delim_ch {
					res << s[i..index]
					i = index + 1
					break
				}
			}
		}
		if i < s.len {
			res << s[i..]
		}
	}
	return res
}

// rsplit_any splits the string to an array by any of the `delim` chars in reverse order.
// If the delimiter string is empty then `.rsplit()` is used.
// Example: assert "first row\nsecond row".rsplit_any(" \n") == ['row', 'second', 'row', 'first']
@[direct_array_access]
pub fn (s string) rsplit_any(delim string) []string {
	mut res := []string{}
	unsafe { res.flags.set(.noslices) }
	defer { unsafe { res.flags.clear(.noslices) } }
	mut i := s.len - 1
	if s.len > 0 {
		if delim.len <= 0 {
			return s.rsplit('')
		}
		mut rbound := s.len
		for i >= 0 {
			for delim_ch in delim {
				if s[i] == delim_ch {
					res << s[i + 1..rbound]
					rbound = i
					break
				}
			}
			i--
		}
		if rbound > 0 {
			res << s[..rbound]
		}
	}
	return res
}

// split splits the string into an array of strings at the given delimiter.
// If `delim` is empty the string is split by it's characters.
// Example: assert 'DEF'.split('') == ['D','E','F']
// Example: assert 'A B C'.split(' ') == ['A','B','C']
@[inline]
pub fn (s string) split(delim string) []string {
	return s.split_nth(delim, 0)
}

// rsplit splits the string into an array of strings at the given delimiter, starting from the right.
// If `delim` is empty the string is split by it's characters.
// Example: assert 'DEF'.rsplit('') == ['F','E','D']
// Example: assert 'A B C'.rsplit(' ') == ['C','B','A']
@[inline]
pub fn (s string) rsplit(delim string) []string {
	return s.rsplit_nth(delim, 0)
}

// split_once splits the string into a pair of strings at the given delimiter.
// Example:
// ```v
// path, ext := 'file.ts.dts'.split_once('.')?
// assert path == 'file'
// assert ext == 'ts.dts'
pub fn (s string) split_once(delim string) ?(string, string) {
	result := s.split_nth(delim, 2)

	if result.len != 2 {
		return none
	}

	return result[0], result[1]
}

// rsplit_once splits the string into a pair of strings at the given delimiter, starting from the right.
// NOTE: rsplit_once returns the string at the left side of the delimiter as first part of the pair.
// Example:
// ```v
// path, ext := 'file.ts.dts'.rsplit_once('.')?
// assert path == 'file.ts'
// assert ext == 'dts'
// ```
pub fn (s string) rsplit_once(delim string) ?(string, string) {
	result := s.rsplit_nth(delim, 2)

	if result.len != 2 {
		return none
	}

	return result[1], result[0]
}

// split_n splits the string based on the passed `delim` substring.
// It returns the first Nth parts. When N=0, return all the splits.
// The last returned element has the remainder of the string, even if
// the remainder contains more `delim` substrings.
pub fn (s string) split_n(delim string, n int) []string {
	return s.split_nth(delim, n)
}

// split_nth splits the string based on the passed `delim` substring.
// It returns the first Nth parts. When N=0, return all the splits.
// The last returned element has the remainder of the string, even if
// the remainder contains more `delim` substrings.
@[direct_array_access]
pub fn (s string) split_nth(delim string, nth int) []string {
	mut res := []string{}
	unsafe { res.flags.set(.noslices) } // allow freeing of old data during <<
	defer { unsafe { res.flags.clear(.noslices) } }
	match delim.len {
		0 {
			for i, ch in s {
				if nth > 0 && res.len == nth - 1 {
					res << s[i..]
					break
				}
				res << ch.ascii_str()
			}
		}
		1 {
			delim_byte := delim[0]
			mut start := 0
			for i, ch in s {
				if ch == delim_byte {
					if nth > 0 && res.len == nth - 1 {
						break
					}
					res << s.substr(start, i)
					start = i + 1
				}
			}
			if nth < 1 || res.len < nth {
				res << s[start..]
			}
		}
		else {
			mut start := 0
			// Add up to `nth` segments left of every occurrence of the delimiter.
			for i := 0; i + delim.len <= s.len; {
				if unsafe { s.substr_unsafe(i, i + delim.len) } == delim {
					if nth > 0 && res.len == nth - 1 {
						break
					}
					res << s.substr(start, i)
					i += delim.len
					start = i
				} else {
					i++
				}
			}
			// Then add the remaining part of the string as the last segment.
			if nth < 1 || res.len < nth {
				res << s[start..]
			}
		}
	}

	return res
}

// rsplit_nth splits the string based on the passed `delim` substring in revese order.
// It returns the first Nth parts. When N=0, return all the splits.
// The last returned element has the remainder of the string, even if
// the remainder contains more `delim` substrings.
@[direct_array_access]
pub fn (s string) rsplit_nth(delim string, nth int) []string {
	mut res := []string{}
	unsafe { res.flags.set(.noslices) } // allow freeing of old data during <<
	defer { unsafe { res.flags.clear(.noslices) } }
	match delim.len {
		0 {
			for i := s.len - 1; i >= 0; i-- {
				if nth > 0 && res.len == nth - 1 {
					res << s[..i + 1]
					break
				}
				res << s[i].ascii_str()
			}
		}
		1 {
			delim_byte := delim[0]
			mut rbound := s.len
			for i := s.len - 1; i >= 0; i-- {
				if s[i] == delim_byte {
					if nth > 0 && res.len == nth - 1 {
						break
					}
					res << s[i + 1..rbound]
					rbound = i
				}
			}
			if nth < 1 || res.len < nth {
				res << s[..rbound]
			}
		}
		else {
			mut rbound := s.len
			for i := s.len - 1; i >= 0; i-- {
				is_delim := i - delim.len >= 0 && s[i - delim.len..i] == delim
				if is_delim {
					if nth > 0 && res.len == nth - 1 {
						break
					}
					res << s[i..rbound]
					i -= delim.len
					rbound = i
				}
			}
			if nth < 1 || res.len < nth {
				res << s[..rbound]
			}
		}
	}

	return res
}

// split_into_lines splits the string by newline characters.
// newlines are stripped.
// `\r` (MacOS), `\n` (POSIX), and `\r\n` (WinOS) line endings are all supported (including mixed line endings).
// NOTE: algorithm is "greedy", consuming '\r\n' as a single line ending with higher priority than '\r' and '\n' as multiple endings
@[direct_array_access]
pub fn (s string) split_into_lines() []string {
	mut res := []string{}
	if s.len == 0 {
		return res
	}
	unsafe { res.flags.set(.noslices) } // allow freeing of old data during <<
	defer { unsafe { res.flags.clear(.noslices) } }
	cr := `\r`
	lf := `\n`
	mut line_start := 0
	for i := 0; i < s.len; i++ {
		if line_start <= i {
			if s[i] == lf {
				res << if line_start == i { '' } else { s[line_start..i] }
				line_start = i + 1
			} else if s[i] == cr {
				res << if line_start == i { '' } else { s[line_start..i] }
				if (i + 1) < s.len && s[i + 1] == lf {
					line_start = i + 2
				} else {
					line_start = i + 1
				}
			}
		}
	}
	if line_start < s.len {
		res << s[line_start..]
	}
	return res
}

// split_by_space splits the string by whitespace (any of ` `, `\n`, `\t`, `\v`, `\f`, `\r`).
// Repeated, trailing or leading whitespaces will be omitted.
pub fn (s string) split_by_space() []string {
	mut res := []string{}
	unsafe { res.flags.set(.noslices) }
	defer { unsafe { res.flags.clear(.noslices) } }
	for word in s.split_any(' \n\t\v\f\r') {
		if word != '' {
			res << word
		}
	}
	return res
}

// substr returns the string between index positions `start` and `end`.
// Example: assert 'ABCD'.substr(1,3) == 'BC'
@[direct_array_access]
pub fn (s string) substr(start int, _end int) string {
	// WARNNING: The is a temp solution for bootstrap!
	end := if _end == max_i64 || _end == max_i32 { s.len } else { _end } // max_int
	$if !no_bounds_checking {
		if start > end || start > s.len || end > s.len || start < 0 || end < 0 {
			panic('substr(' + impl_i64_to_string(start) + ', ' + impl_i64_to_string(end) +
				') out of bounds (len=' + impl_i64_to_string(s.len) + ') s=' + s)
		}
	}
	len := end - start
	if len == s.len {
		return s.clone()
	}
	mut res := string{
		str: unsafe { malloc_noscan(len + 1) }
		len: len
	}
	unsafe {
		vmemcpy(res.str, s.str + start, len)
		res.str[len] = 0
	}
	return res
}

// substr_unsafe works like substr(), but doesn't copy (allocate) the substring
@[direct_array_access]
pub fn (s string) substr_unsafe(start int, _end int) string {
	end := if _end == 2147483647 { s.len } else { _end } // max_int
	len := end - start
	if len == s.len {
		return s
	}
	return string{
		str: unsafe { s.str + start }
		len: len
	}
}

// version of `substr()` that is used in `a[start..end] or {`
// return an error when the index is out of range
@[direct_array_access]
pub fn (s string) substr_with_check(start int, _end int) !string {
	// WARNNING: The is a temp solution for bootstrap!
	end := if _end == max_i64 || _end == max_i32 { s.len } else { _end } // max_int
	if start > end || start > s.len || end > s.len || start < 0 || end < 0 {
		return error('substr(' + impl_i64_to_string(start) + ', ' + impl_i64_to_string(end) +
			') out of bounds (len=' + impl_i64_to_string(s.len) + ')')
	}
	len := end - start
	if len == s.len {
		return s.clone()
	}
	mut res := string{
		str: unsafe { malloc_noscan(len + 1) }
		len: len
	}
	unsafe {
		vmemcpy(res.str, s.str + start, len)
		res.str[len] = 0
	}
	return res
}

// substr_ni returns the string between index positions `start` and `end` allowing negative indexes
// This function always return a valid string.
@[direct_array_access]
pub fn (s string) substr_ni(_start int, _end int) string {
	mut start := _start
	// WARNNING: The is a temp solution for bootstrap!
	mut end := if _end == max_i64 || _end == max_i32 { s.len } else { _end }

	// borders math
	if start < 0 {
		start = s.len + start
		if start < 0 {
			start = 0
		}
	}

	if end < 0 {
		end = s.len + end
		if end < 0 {
			end = 0
		}
	}
	if end >= s.len {
		end = s.len
	}

	if start > s.len || end < start {
		return ''
	}

	len := end - start

	// string copy
	mut res := string{
		str: unsafe { malloc_noscan(len + 1) }
		len: len
	}
	unsafe {
		vmemcpy(res.str, s.str + start, len)
		res.str[len] = 0
	}
	return res
}

// index returns the position of the first character of the input string.
// It will return `-1` if the input string can't be found.
@[direct_array_access]
fn (s string) index_(p string) int {
	if p.len > s.len || p.len == 0 {
		return -1
	}
	if p.len > 2 {
		return s.index_kmp(p)
	}
	mut i := 0
	for i < s.len {
		mut j := 0
		for j < p.len && unsafe { s.str[i + j] == p.str[j] } {
			j++
		}
		if j == p.len {
			return i
		}
		i++
	}
	return -1
}

// index returns the position of the first character of the first occurrence of the `needle` string in `s`.
// It will return `none` if the `needle` string can't be found in `s`.
pub fn (s string) index(p string) ?int {
	idx := s.index_(p)
	if idx == -1 {
		return none
	}
	return idx
}

// last_index returns the position of the first character of the *last* occurrence of the `needle` string in `s`.
@[inline]
pub fn (s string) last_index(needle string) ?int {
	idx := s.index_last_(needle)
	if idx == -1 {
		return none
	}
	return idx
}

const kmp_stack_buffer_size = 20

// index_kmp does KMP search inside the string `s` for the needle `p`.
// It returns the first found index where the string `p` is found.
// It returns -1, when the needle `p` is not present in `s`.
@[direct_array_access; manualfree]
fn (s string) index_kmp(p string) int {
	if p.len > s.len {
		return -1
	}
	mut stack_prefixes := [kmp_stack_buffer_size]int{}
	mut p_prefixes := unsafe { &stack_prefixes[0] }
	if p.len > kmp_stack_buffer_size {
		p_prefixes = unsafe { &int(vcalloc(p.len * int(sizeof(int)))) }
	}
	defer {
		if p.len > kmp_stack_buffer_size {
			unsafe { free(p_prefixes) }
		}
	}
	mut j := 0
	for i := 1; i < p.len; i++ {
		for unsafe { p.str[j] != p.str[i] } && j > 0 {
			j = unsafe { p_prefixes[j - 1] }
		}
		if unsafe { p.str[j] == p.str[i] } {
			j++
		}
		unsafe {
			p_prefixes[i] = j
		}
	}
	j = 0
	for i in 0 .. s.len {
		for unsafe { p.str[j] != s.str[i] } && j > 0 {
			j = unsafe { p_prefixes[j - 1] }
		}
		if unsafe { p.str[j] == s.str[i] } {
			j++
		}
		if j == p.len {
			return i - p.len + 1
		}
	}
	return -1
}

// index_any returns the position of any of the characters in the input string - if found.
pub fn (s string) index_any(chars string) int {
	for i, ss in s {
		for c in chars {
			if c == ss {
				return i
			}
		}
	}
	return -1
}

// index_last_ returns the position of the last occurrence of the given string `p` in `s`.
@[direct_array_access]
fn (s string) index_last_(p string) int {
	if p.len > s.len || p.len == 0 {
		return -1
	}
	mut i := s.len - p.len
	for i >= 0 {
		mut j := 0
		for j < p.len && unsafe { s.str[i + j] == p.str[j] } {
			j++
		}
		if j == p.len {
			return i
		}
		i--
	}
	return -1
}

// index_after returns the position of the input string, starting search from `start` position.
@[direct_array_access]
pub fn (s string) index_after(p string, start int) ?int {
	if p.len > s.len {
		return none
	}
	mut strt := start
	if start < 0 {
		strt = 0
	}
	if start >= s.len {
		return none
	}
	mut i := strt
	for i < s.len {
		mut j := 0
		mut ii := i
		for j < p.len && unsafe { s.str[ii] == p.str[j] } {
			j++
			ii++
		}
		if j == p.len {
			return i
		}
		i++
	}
	return none
}

// index_after_ returns the position of the input string, starting search from `start` position.
@[direct_array_access]
pub fn (s string) index_after_(p string, start int) int {
	if p.len > s.len {
		return -1
	}
	mut strt := start
	if start < 0 {
		strt = 0
	}
	if start >= s.len {
		return -1
	}
	mut i := strt
	for i < s.len {
		mut j := 0
		mut ii := i
		for j < p.len && unsafe { s.str[ii] == p.str[j] } {
			j++
			ii++
		}
		if j == p.len {
			return i
		}
		i++
	}
	return -1
}

// index_u8 returns the index of byte `c` if found in the string.
// index_u8 returns -1 if the byte can not be found.
@[direct_array_access]
pub fn (s string) index_u8(c u8) int {
	for i, b in s {
		if b == c {
			return i
		}
	}
	return -1
}

// last_index_u8 returns the index of the last occurrence of byte `c` if it was found in the string.
@[direct_array_access; inline]
pub fn (s string) last_index_u8(c u8) int {
	for i := s.len - 1; i >= 0; i-- {
		if s[i] == c {
			return i
		}
	}
	return -1
}

// count returns the number of occurrences of `substr` in the string.
// count returns -1 if no `substr` could be found.
@[direct_array_access]
pub fn (s string) count(substr string) int {
	if s.len == 0 || substr.len == 0 {
		return 0
	}
	if substr.len > s.len {
		return 0
	}

	mut n := 0

	if substr.len == 1 {
		target := substr[0]

		for letter in s {
			if letter == target {
				n++
			}
		}

		return n
	}

	mut i := 0
	for {
		i = s.index_after_(substr, i)
		if i == -1 {
			return n
		}
		i += substr.len
		n++
	}
	return 0 // TODO: can never get here - v doesn't know that
}

// contains_u8 returns `true` if the string contains the byte value `x`.
// See also: [`string.index_u8`](#string.index_u8) , to get the index of the byte as well.
pub fn (s string) contains_u8(x u8) bool {
	for c in s {
		if x == c {
			return true
		}
	}
	return false
}

// contains returns `true` if the string contains `substr`.
// See also: [`string.index`](#string.index)
pub fn (s string) contains(substr string) bool {
	if substr.len == 0 {
		return true
	}
	if substr.len == 1 {
		return s.contains_u8(unsafe { substr.str[0] })
	}
	return s.index_(substr) != -1
}

// contains_any returns `true` if the string contains any chars in `chars`.
pub fn (s string) contains_any(chars string) bool {
	for c in chars {
		if s.contains_u8(c) {
			return true
		}
	}
	return false
}

// contains_only returns `true`, if the string contains only the characters in `chars`.
pub fn (s string) contains_only(chars string) bool {
	if chars.len == 0 {
		return false
	}
	for ch in s {
		mut res := 0
		for i := 0; i < chars.len && res == 0; i++ {
			res += int(ch == unsafe { chars.str[i] })
		}
		if res == 0 {
			return false
		}
	}
	return true
}

// contains_any_substr returns `true` if the string contains any of the strings in `substrs`.
pub fn (s string) contains_any_substr(substrs []string) bool {
	if substrs.len == 0 {
		return true
	}
	for sub in substrs {
		if s.contains(sub) {
			return true
		}
	}
	return false
}

// starts_with returns `true` if the string starts with `p`.
@[direct_array_access]
pub fn (s string) starts_with(p string) bool {
	if p.len > s.len {
		return false
	} else if unsafe { vmemcmp(s.str, p.str, p.len) == 0 } {
		return true
	}
	return false
}

// ends_with returns `true` if the string ends with `p`.
@[direct_array_access]
pub fn (s string) ends_with(p string) bool {
	if p.len > s.len {
		return false
	} else if unsafe { vmemcmp(s.str + s.len - p.len, p.str, p.len) == 0 } {
		return true
	}
	return false
}

// to_lower_ascii returns the string in all lowercase characters.
// It is faster than `s.to_lower()`, but works only when the input
// string `s` is composed *entirely* from ASCII characters.
// Use `s.to_lower()` instead, if you are not sure.
@[direct_array_access]
pub fn (s string) to_lower_ascii() string {
	unsafe {
		mut b := malloc_noscan(s.len + 1)
		for i in 0 .. s.len {
			if s.str[i] >= `A` && s.str[i] <= `Z` {
				b[i] = s.str[i] + 32
			} else {
				b[i] = s.str[i]
			}
		}
		b[s.len] = 0
		return tos(b, s.len)
	}
}

// to_lower returns the string in all lowercase characters.
// Example: assert 'Hello V'.to_lower() == 'hello v'
@[direct_array_access]
pub fn (s string) to_lower() string {
	if s.is_pure_ascii() {
		return s.to_lower_ascii()
	}
	mut runes := s.runes()
	for i in 0 .. runes.len {
		runes[i] = runes[i].to_lower()
	}
	return runes.string()
}

// is_lower returns `true`, if all characters in the string are lowercase.
// It only works when the input is composed entirely from ASCII characters.
// Example: assert 'hello developer'.is_lower() == true
@[direct_array_access]
pub fn (s string) is_lower() bool {
	if s == '' || s[0].is_digit() {
		return false
	}
	for i in 0 .. s.len {
		if s[i] >= `A` && s[i] <= `Z` {
			return false
		}
	}
	return true
}

// to_upper_ascii returns the string in all UPPERCASE characters.
// It is faster than `s.to_upper()`, but works only when the input
// string `s` is composed *entirely* from ASCII characters.
// Use `s.to_upper()` instead, if you are not sure.
@[direct_array_access]
pub fn (s string) to_upper_ascii() string {
	unsafe {
		mut b := malloc_noscan(s.len + 1)
		for i in 0 .. s.len {
			if s.str[i] >= `a` && s.str[i] <= `z` {
				b[i] = s.str[i] - 32
			} else {
				b[i] = s.str[i]
			}
		}
		b[s.len] = 0
		return tos(b, s.len)
	}
}

// to_upper returns the string in all uppercase characters.
// Example: assert 'Hello V'.to_upper() == 'HELLO V'
@[direct_array_access]
pub fn (s string) to_upper() string {
	if s.is_pure_ascii() {
		return s.to_upper_ascii()
	}
	mut runes := s.runes()
	for i in 0 .. runes.len {
		runes[i] = runes[i].to_upper()
	}
	return runes.string()
}

// is_upper returns `true` if all characters in the string are uppercase.
// It only works when the input is composed entirely from ASCII characters.
// See also: [`byte.is_capital`](#byte.is_capital)
// Example: assert 'HELLO V'.is_upper() == true
@[direct_array_access]
pub fn (s string) is_upper() bool {
	if s == '' || s[0].is_digit() {
		return false
	}
	for i in 0 .. s.len {
		if s[i] >= `a` && s[i] <= `z` {
			return false
		}
	}
	return true
}

// capitalize returns the string with the first character capitalized.
// Example: assert 'hello'.capitalize() == 'Hello'
@[direct_array_access]
pub fn (s string) capitalize() string {
	if s.len == 0 {
		return ''
	}
	if s.len == 1 {
		return s[0].ascii_str().to_upper()
	}
	r := s.runes()
	letter := r[0].str()
	uletter := letter.to_upper()
	rrest := r[1..]
	srest := rrest.string()
	res := uletter + srest
	return res
}

// uncapitalize returns the string with the first character uncapitalized.
// Example: assert 'Hello, Bob!'.uncapitalize() == 'hello, Bob!'
@[direct_array_access]
pub fn (s string) uncapitalize() string {
	if s.len == 0 {
		return ''
	}
	if s.len == 1 {
		return s[0].ascii_str().to_lower()
	}
	r := s.runes()
	letter := r[0].str()
	lletter := letter.to_lower()
	rrest := r[1..]
	srest := rrest.string()
	res := lletter + srest
	return res
}

// is_capital returns `true`, if the first character in the string `s`,
// is a capital letter, and the rest are NOT.
// Example: assert 'Hello'.is_capital() == true
// Example: assert 'HelloWorld'.is_capital() == false
@[direct_array_access]
pub fn (s string) is_capital() bool {
	if s.len == 0 || !(s[0] >= `A` && s[0] <= `Z`) {
		return false
	}
	for i in 1 .. s.len {
		if s[i] >= `A` && s[i] <= `Z` {
			return false
		}
	}
	return true
}

// starts_with_capital returns `true`, if the first character in the string `s`,
// is a capital letter, even if the rest are not.
// Example: assert 'Hello'.starts_with_capital() == true
// Example: assert 'Hello. World.'.starts_with_capital() == true
@[direct_array_access]
pub fn (s string) starts_with_capital() bool {
	if s.len == 0 || !s[0].is_capital() {
		return false
	}
	return true
}

// title returns the string with each word capitalized.
// Example: assert 'hello v developer'.title() == 'Hello V Developer'
pub fn (s string) title() string {
	words := s.split(' ')
	mut tit := []string{}
	for word in words {
		tit << word.capitalize()
	}
	title := tit.join(' ')
	return title
}

// is_title returns true if all words of the string are capitalized.
// Example: assert 'Hello V Developer'.is_title() == true
pub fn (s string) is_title() bool {
	words := s.split(' ')
	for word in words {
		if !word.is_capital() {
			return false
		}
	}
	return true
}

// find_between returns the string found between `start` string and `end` string.
// Example: assert 'hey [man] how you doin'.find_between('[', ']') == 'man'
pub fn (s string) find_between(start string, end string) string {
	start_pos := s.index_(start)
	if start_pos == -1 {
		return ''
	}
	// First get everything to the right of 'start'
	val := s[start_pos + start.len..]
	end_pos := val.index_(end)
	if end_pos == -1 {
		return ''
	}
	return val[..end_pos]
}

// trim_space strips any of ` `, `\n`, `\t`, `\v`, `\f`, `\r` from the start and end of the string.
// Example: assert ' Hello V '.trim_space() == 'Hello V'
@[inline]
pub fn (s string) trim_space() string {
	return s.trim(' \n\t\v\f\r')
}

// trim_space_left strips any of ` `, `\n`, `\t`, `\v`, `\f`, `\r` from the start of the string.
// Example: assert ' Hello V '.trim_space_left() == 'Hello V '
@[inline]
pub fn (s string) trim_space_left() string {
	return s.trim_left(' \n\t\v\f\r')
}

// trim_space_right strips any of ` `, `\n`, `\t`, `\v`, `\f`, `\r` from the end of the string.
// Example: assert ' Hello V '.trim_space_right() == ' Hello V'
@[inline]
pub fn (s string) trim_space_right() string {
	return s.trim_right(' \n\t\v\f\r')
}

// trim strips any of the characters given in `cutset` from the start and end of the string.
// Example: assert ' ffHello V ffff'.trim(' f') == 'Hello V'
pub fn (s string) trim(cutset string) string {
	if s == '' || cutset == '' {
		return s.clone()
	}
	if cutset.is_pure_ascii() {
		return s.trim_chars(cutset, .trim_both)
	} else {
		return s.trim_runes(cutset, .trim_both)
	}
}

// trim_indexes gets the new start and end indices of a string when any of the characters given in `cutset` were stripped from the start and end of the string. Should be used as an input to `substr()`. If the string contains only the characters in `cutset`, both values returned are zero.
// Example: left, right := '-hi-'.trim_indexes('-'); assert left == 1; assert right == 3
@[direct_array_access]
pub fn (s string) trim_indexes(cutset string) (int, int) {
	mut pos_left := 0
	mut pos_right := s.len - 1
	mut cs_match := true
	for pos_left <= s.len && pos_right >= -1 && cs_match {
		cs_match = false
		for cs in cutset {
			if s[pos_left] == cs {
				pos_left++
				cs_match = true
				break
			}
		}
		for cs in cutset {
			if s[pos_right] == cs {
				pos_right--
				cs_match = true
				break
			}
		}
		if pos_left > pos_right {
			return 0, 0
		}
	}
	return pos_left, pos_right + 1
}

enum TrimMode {
	trim_left
	trim_right
	trim_both
}

@[direct_array_access]
fn (s string) trim_chars(cutset string, mode TrimMode) string {
	mut pos_left := 0
	mut pos_right := s.len - 1
	mut cs_match := true
	for pos_left <= s.len && pos_right >= -1 && cs_match {
		cs_match = false
		if mode in [.trim_left, .trim_both] {
			for cs in cutset {
				if s[pos_left] == cs {
					pos_left++
					cs_match = true
					break
				}
			}
		}
		if mode in [.trim_right, .trim_both] {
			for cs in cutset {
				if s[pos_right] == cs {
					pos_right--
					cs_match = true
					break
				}
			}
		}
		if pos_left > pos_right {
			return ''
		}
	}
	return s.substr(pos_left, pos_right + 1)
}

@[direct_array_access]
fn (s string) trim_runes(cutset string, mode TrimMode) string {
	s_runes := s.runes()
	mut pos_left := 0
	mut pos_right := s_runes.len - 1
	mut cs_match := true
	for pos_left <= s_runes.len && pos_right >= -1 && cs_match {
		cs_match = false
		if mode in [.trim_left, .trim_both] {
			for cs in cutset.runes_iterator() {
				if s_runes[pos_left] == cs {
					pos_left++
					cs_match = true
					break
				}
			}
		}
		if mode in [.trim_right, .trim_both] {
			for cs in cutset.runes_iterator() {
				if s_runes[pos_right] == cs {
					pos_right--
					cs_match = true
					break
				}
			}
		}
		if pos_left > pos_right {
			return ''
		}
	}
	return s_runes[pos_left..pos_right + 1].string()
}

// trim_left strips any of the characters given in `cutset` from the left of the string.
// Example: assert 'd Hello V developer'.trim_left(' d') == 'Hello V developer'
@[direct_array_access]
pub fn (s string) trim_left(cutset string) string {
	if s == '' || cutset == '' {
		return s.clone()
	}
	if cutset.is_pure_ascii() {
		return s.trim_chars(cutset, .trim_left)
	} else {
		return s.trim_runes(cutset, .trim_left)
	}
}

// trim_right strips any of the characters given in `cutset` from the right of the string.
// Example: assert ' Hello V d'.trim_right(' d') == ' Hello V'
@[direct_array_access]
pub fn (s string) trim_right(cutset string) string {
	if s.len < 1 || cutset.len < 1 {
		return s.clone()
	}
	if cutset.is_pure_ascii() {
		return s.trim_chars(cutset, .trim_right)
	} else {
		return s.trim_runes(cutset, .trim_right)
	}
}

// trim_string_left strips `str` from the start of the string.
// Example: assert 'WorldHello V'.trim_string_left('World') == 'Hello V'
pub fn (s string) trim_string_left(str string) string {
	if s.starts_with(str) {
		return s[str.len..]
	}
	return s.clone()
}

// trim_string_right strips `str` from the end of the string.
// Example: assert 'Hello VWorld'.trim_string_right('World') == 'Hello V'
pub fn (s string) trim_string_right(str string) string {
	if s.ends_with(str) {
		return s[..s.len - str.len]
	}
	return s.clone()
}

// compare_strings returns `-1` if `a < b`, `1` if `a > b` else `0`.
pub fn compare_strings(a &string, b &string) int {
	return match true {
		a < b { -1 }
		a > b { 1 }
		else { 0 }
	}
}

// compare_strings_by_len returns `-1` if `a.len < b.len`, `1` if `a.len > b.len` else `0`.
fn compare_strings_by_len(a &string, b &string) int {
	return match true {
		a.len < b.len { -1 }
		a.len > b.len { 1 }
		else { 0 }
	}
}

// compare_lower_strings returns the same as compare_strings but converts `a` and `b` to lower case before comparing.
fn compare_lower_strings(a &string, b &string) int {
	aa := a.to_lower()
	bb := b.to_lower()
	return compare_strings(&aa, &bb)
}

// sort_ignore_case sorts the string array using case insensitive comparing.
@[inline]
pub fn (mut s []string) sort_ignore_case() {
	s.sort_with_compare(compare_lower_strings)
}

// sort_by_len sorts the string array by each string's `.len` length.
@[inline]
pub fn (mut s []string) sort_by_len() {
	s.sort_with_compare(compare_strings_by_len)
}

// str returns a copy of the string
@[inline]
pub fn (s string) str() string {
	return s.clone()
}

// at returns the byte at index `idx`.
// Example: assert 'ABC'.at(1) == u8(`B`)
fn (s string) at(idx int) u8 {
	$if !no_bounds_checking {
		if idx < 0 || idx >= s.len {
			panic_n2('string index out of range(idx,s.len):', idx, s.len)
		}
	}
	return unsafe { s.str[idx] }
}

// version of `at()` that is used in `a[i] or {`
// return an error when the index is out of range
fn (s string) at_with_check(idx int) ?u8 {
	if idx < 0 || idx >= s.len {
		return none
	}
	unsafe {
		return s.str[idx]
	}
}

// Check if a string is an octal value. Returns 'true' if it is, or 'false' if it is not
@[direct_array_access]
pub fn (str string) is_oct() bool {
	mut i := 0

	if str.len == 0 {
		return false
	}

	if str[i] == `0` {
		i++
	} else if str[i] == `-` || str[i] == `+` {
		i++

		if i < str.len && str[i] == `0` {
			i++
		} else {
			return false
		}
	} else {
		return false
	}

	if i < str.len && str[i] == `o` {
		i++
	} else {
		return false
	}

	if i == str.len {
		return false
	}

	for i < str.len {
		if str[i] < `0` || str[i] > `7` {
			return false
		}
		i++
	}

	return true
}

// is_bin returns `true` if the string is a binary value.
@[direct_array_access]
pub fn (str string) is_bin() bool {
	mut i := 0

	if str.len == 0 {
		return false
	}

	if str[i] == `0` {
		i++
	} else if str[i] == `-` || str[i] == `+` {
		i++

		if i < str.len && str[i] == `0` {
			i++
		} else {
			return false
		}
	} else {
		return false
	}

	if i < str.len && str[i] == `b` {
		i++
	} else {
		return false
	}

	if i == str.len {
		return false
	}

	for i < str.len {
		if str[i] < `0` || str[i] > `1` {
			return false
		}
		i++
	}

	return true
}

// is_hex returns 'true' if the string is a hexadecimal value.
@[direct_array_access]
pub fn (str string) is_hex() bool {
	mut i := 0

	if str.len == 0 {
		return false
	}

	if str[i] == `0` {
		i++
	} else if str[i] == `-` || str[i] == `+` {
		i++

		if i < str.len && str[i] == `0` {
			i++
		} else {
			return false
		}
	} else {
		return false
	}

	if i < str.len && str[i] == `x` {
		i++
	} else {
		return false
	}

	if i == str.len {
		return false
	}

	for i < str.len {
		// TODO: remove this workaround for v2's parser
		// vfmt off
		if (str[i] < `0` || str[i] > `9`) && 
		    ((str[i] < `a` || str[i] > `f`) && (str[i] < `A` || str[i] > `F`)) {
			return false
		}
		// vfmt on
		i++
	}

	return true
}

// Check if a string is an integer value. Returns 'true' if it is, or 'false' if it is not
@[direct_array_access]
pub fn (str string) is_int() bool {
	mut i := 0

	if str.len == 0 {
		return false
	}

	if (str[i] != `-` && str[i] != `+`) && (!str[i].is_digit()) {
		return false
	} else {
		i++
	}

	if i == str.len && (!str[i - 1].is_digit()) {
		return false
	}

	for i < str.len {
		if str[i] < `0` || str[i] > `9` {
			return false
		}
		i++
	}

	return true
}

// is_space returns `true` if the byte is a white space character.
// The following list is considered white space characters: ` `, `\t`, `\n`, `\v`, `\f`, `\r`, 0x85, 0xa0
// Example: assert u8(` `).is_space() == true
@[inline]
pub fn (c u8) is_space() bool {
	// 0x85 is NEXT LINE (NEL)
	// 0xa0 is NO-BREAK SPACE
	return c == 32 || (c > 8 && c < 14) || c == 0x85 || c == 0xa0
}

// is_digit returns `true` if the byte is in range 0-9 and `false` otherwise.
// Example: assert u8(`9`).is_digit() == true
@[inline]
pub fn (c u8) is_digit() bool {
	return c >= `0` && c <= `9`
}

// is_hex_digit returns `true` if the byte is either in range 0-9, a-f or A-F and `false` otherwise.
// Example: assert u8(`F`).is_hex_digit() == true
@[inline]
pub fn (c u8) is_hex_digit() bool {
	return c.is_digit() || (c >= `a` && c <= `f`) || (c >= `A` && c <= `F`)
}

// is_oct_digit returns `true` if the byte is in range 0-7 and `false` otherwise.
// Example: assert u8(`7`).is_oct_digit() == true
@[inline]
pub fn (c u8) is_oct_digit() bool {
	return c >= `0` && c <= `7`
}

// is_bin_digit returns `true` if the byte is a binary digit (0 or 1) and `false` otherwise.
// Example: assert u8(`0`).is_bin_digit() == true
@[inline]
pub fn (c u8) is_bin_digit() bool {
	return c == `0` || c == `1`
}

// is_letter returns `true` if the byte is in range a-z or A-Z and `false` otherwise.
// Example: assert u8(`V`).is_letter() == true
@[inline]
pub fn (c u8) is_letter() bool {
	return (c >= `a` && c <= `z`) || (c >= `A` && c <= `Z`)
}

// is_alnum returns `true` if the byte is in range a-z, A-Z, 0-9 and `false` otherwise.
// Example: assert u8(`V`).is_alnum() == true
@[inline]
pub fn (c u8) is_alnum() bool {
	return (c >= `a` && c <= `z`) || (c >= `A` && c <= `Z`) || (c >= `0` && c <= `9`)
}

// free allows for manually freeing the memory occupied by the string
@[manualfree; unsafe]
pub fn (s &string) free() {
	$if prealloc {
		return
	}
	if s.is_lit == -98761234 {
		double_free_msg := unsafe { &u8(c'double string.free() detected\n') }
		double_free_msg_len := unsafe { vstrlen(double_free_msg) }
		$if freestanding {
			bare_eprint(double_free_msg, u64(double_free_msg_len))
		} $else {
			_write_buf_to_fd(1, double_free_msg, double_free_msg_len)
		}
		return
	}
	if s.is_lit == 1 || s.str == 0 {
		return
	}
	unsafe {
		// C.printf(c's: %x %s\n', s.str, s.str)
		free(s.str)
		s.str = nil
	}
	s.is_lit = -98761234
}

// before returns the contents before `sub` in the string.
// If the substring is not found, it returns the full input string.
// Example: assert '23:34:45.234'.before('.') == '23:34:45'
// Example: assert 'abcd'.before('.') == 'abcd'
// TODO: deprecate and remove either .before or .all_before
pub fn (s string) before(sub string) string {
	pos := s.index_(sub)
	if pos == -1 {
		return s.clone()
	}
	return s[..pos]
}

// all_before returns the contents before `sub` in the string.
// If the substring is not found, it returns the full input string.
// Example: assert '23:34:45.234'.all_before('.') == '23:34:45'
// Example: assert 'abcd'.all_before('.') == 'abcd'
pub fn (s string) all_before(sub string) string {
	// TODO: remove dup method
	pos := s.index_(sub)
	if pos == -1 {
		return s.clone()
	}
	return s[..pos]
}

// all_before_last returns the contents before the last occurrence of `sub` in the string.
// If the substring is not found, it returns the full input string.
// Example: assert '23:34:45.234'.all_before_last(':') == '23:34'
// Example: assert 'abcd'.all_before_last('.') == 'abcd'
pub fn (s string) all_before_last(sub string) string {
	pos := s.index_last_(sub)
	if pos == -1 {
		return s.clone()
	}
	return s[..pos]
}

// all_after returns the contents after `sub` in the string.
// If the substring is not found, it returns the full input string.
// Example: assert '23:34:45.234'.all_after('.') == '234'
// Example: assert 'abcd'.all_after('z') == 'abcd'
pub fn (s string) all_after(sub string) string {
	pos := s.index_(sub)
	if pos == -1 {
		return s.clone()
	}
	return s[pos + sub.len..]
}

// all_after_last returns the contents after the last occurrence of `sub` in the string.
// If the substring is not found, it returns the full input string.
// Example: assert '23:34:45.234'.all_after_last(':') == '45.234'
// Example: assert 'abcd'.all_after_last('z') == 'abcd'
pub fn (s string) all_after_last(sub string) string {
	pos := s.index_last_(sub)
	if pos == -1 {
		return s.clone()
	}
	return s[pos + sub.len..]
}

// all_after_first returns the contents after the first occurrence of `sub` in the string.
// If the substring is not found, it returns the full input string.
// Example: assert '23:34:45.234'.all_after_first(':') == '34:45.234'
// Example: assert 'abcd'.all_after_first('z') == 'abcd'
pub fn (s string) all_after_first(sub string) string {
	pos := s.index_(sub)
	if pos == -1 {
		return s.clone()
	}
	return s[pos + sub.len..]
}

// after returns the contents after the last occurrence of `sub` in the string.
// If the substring is not found, it returns the full input string.
// Example: assert '23:34:45.234'.after(':') == '45.234'
// Example: assert 'abcd'.after('z') == 'abcd'
// TODO: deprecate either .all_after_last or .after
@[inline]
pub fn (s string) after(sub string) string {
	return s.all_after_last(sub)
}

// after_char returns the contents after the first occurrence of `sub` character in the string.
// If the substring is not found, it returns the full input string.
// Example: assert '23:34:45.234'.after_char(`:`) == '34:45.234'
// Example: assert 'abcd'.after_char(`:`) == 'abcd'
pub fn (s string) after_char(sub u8) string {
	mut pos := -1
	for i, c in s {
		if c == sub {
			pos = i
			break
		}
	}
	if pos == -1 {
		return s.clone()
	}
	return s[pos + 1..]
}

// join joins a string array into a string using `sep` separator.
// Example: assert ['Hello','V'].join(' ') == 'Hello V'
pub fn (a []string) join(sep string) string {
	if a.len == 0 {
		return ''
	}
	mut len := 0
	for val in a {
		len += val.len + sep.len
	}
	len -= sep.len
	// Allocate enough memory
	mut res := string{
		str: unsafe { malloc_noscan(len + 1) }
		len: len
	}
	mut idx := 0
	for i, val in a {
		unsafe {
			vmemcpy(voidptr(res.str + idx), val.str, val.len)
			idx += val.len
		}
		// Add sep if it's not last
		if i != a.len - 1 {
			unsafe {
				vmemcpy(voidptr(res.str + idx), sep.str, sep.len)
				idx += sep.len
			}
		}
	}
	unsafe {
		res.str[res.len] = 0
	}
	return res
}

// join_lines joins a string array into a string using a `\n` newline delimiter.
@[inline]
pub fn (s []string) join_lines() string {
	return s.join('\n')
}

// reverse returns a reversed string.
// Example: assert 'Hello V'.reverse() == 'V olleH'
@[direct_array_access]
pub fn (s string) reverse() string {
	if s.len == 0 || s.len == 1 {
		return s.clone()
	}
	mut res := string{
		str: unsafe { malloc_noscan(s.len + 1) }
		len: s.len
	}
	for i := s.len - 1; i >= 0; i-- {
		unsafe {
			res.str[s.len - i - 1] = s[i]
		}
	}
	unsafe {
		res.str[res.len] = 0
	}
	return res
}

// limit returns a portion of the string, starting at `0` and extending for a given number of characters afterward.
// 'hello'.limit(2) => 'he'
// 'hi'.limit(10) => 'hi'
pub fn (s string) limit(max int) string {
	u := s.runes()
	if u.len <= max {
		return s.clone()
	}
	return u[0..max].string()
}

// hash returns an integer hash of the string.
pub fn (s string) hash() int {
	mut h := u32(0)
	if h == 0 && s.len > 0 {
		for c in s {
			h = h * 31 + u32(c)
		}
	}
	return int(h)
}

// bytes returns the string converted to a byte array.
pub fn (s string) bytes() []u8 {
	if s.len == 0 {
		return []
	}
	mut buf := []u8{len: s.len}
	unsafe { vmemcpy(buf.data, s.str, s.len) }
	return buf
}

// repeat returns a new string with `count` number of copies of the string it was called on.
@[direct_array_access]
pub fn (s string) repeat(count int) string {
	if count <= 0 {
		return ''
	} else if count == 1 {
		return s.clone()
	}
	mut ret := unsafe { malloc_noscan(s.len * count + 1) }
	for i in 0 .. count {
		unsafe {
			vmemcpy(ret + i * s.len, s.str, s.len)
		}
	}
	new_len := s.len * count
	unsafe {
		ret[new_len] = 0
	}
	return unsafe { ret.vstring_with_len(new_len) }
}

// fields returns a string array of the string split by `\t` and ` ` .
// Example: assert '\t\tv = v'.fields() == ['v', '=', 'v']
// Example: assert '  sss   ssss'.fields() == ['sss', 'ssss']
pub fn (s string) fields() []string {
	mut res := []string{}
	unsafe { res.flags.set(.noslices) }
	defer { unsafe { res.flags.clear(.noslices) } }
	mut word_start := 0
	mut word_len := 0
	mut is_in_word := false
	mut is_space := false
	for i, c in s {
		is_space = c in [32, 9, 10]
		if !is_space {
			word_len++
		}
		if !is_in_word && !is_space {
			word_start = i
			is_in_word = true
			continue
		}
		if is_space && is_in_word {
			res << s[word_start..word_start + word_len]
			is_in_word = false
			word_len = 0
			word_start = 0
			continue
		}
	}
	if is_in_word && word_len > 0 {
		// collect the remainder word at the end
		res << s[word_start..s.len]
	}
	return res
}

// strip_margin allows multi-line strings to be formatted in a way that removes white-space
// before a delimiter. By default `|` is used.
// Note: the delimiter has to be a byte at this time. That means surrounding
// the value in ``.
//
// See also: string.trim_indent()
//
// Example:
// ```v
// st := 'Hello there,
//        |  this is a string,
//        |  Everything before the first | is removed'.strip_margin()
//
// assert st == 'Hello there,
//   this is a string,
//   Everything before the first | is removed'
// ```
@[inline]
pub fn (s string) strip_margin() string {
	return s.strip_margin_custom(`|`)
}

// strip_margin_custom does the same as `strip_margin` but will use `del` as delimiter instead of `|`
@[direct_array_access]
pub fn (s string) strip_margin_custom(del u8) string {
	mut sep := del
	if sep.is_space() {
		println('Warning: `strip_margin` cannot use white-space as a delimiter')
		println('    Defaulting to `|`')
		sep = `|`
	}
	// don't know how much space the resulting string will be, but the max it
	// can be is this big
	mut ret := unsafe { malloc_noscan(s.len + 1) }
	mut count := 0
	for i := 0; i < s.len; i++ {
		if s[i] in [10, 13] {
			unsafe {
				ret[count] = s[i]
			}
			count++
			// CRLF
			if s[i] == 13 && i < s.len - 1 && s[i + 1] == 10 {
				unsafe {
					ret[count] = s[i + 1]
				}
				count++
				i++
			}
			for s[i] != sep {
				i++
				if i >= s.len {
					break
				}
			}
		} else {
			unsafe {
				ret[count] = s[i]
			}
			count++
		}
	}
	unsafe {
		ret[count] = 0
		return ret.vstring_with_len(count)
	}
}

// trim_indent detects a common minimal indent of all the input lines,
// removes it from every line and also removes the first and the last
// lines if they are blank (notice difference blank vs empty).
//
// Note that blank lines do not affect the detected indent level.
//
// In case if there are non-blank lines with no leading whitespace characters
// (no indent at all) then the common indent is 0, and therefore this function
// doesn't change the indentation.
//
// Example:
// ```v
// st := '
//      Hello there,
//      this is a string,
//      all the leading indents are removed
//      and also the first and the last lines if they are blank
// '.trim_indent()
//
// assert st == 'Hello there,
// this is a string,
// all the leading indents are removed
// and also the first and the last lines if they are blank'
// ```
pub fn (s string) trim_indent() string {
	mut lines := s.split_into_lines()

	mut min_common_indent := int(max_int) // max int
	for line in lines {
		if line.is_blank() {
			continue
		}
		line_indent := line.indent_width()
		if line_indent < min_common_indent {
			min_common_indent = line_indent
		}
	}

	// trim first line if it's blank
	if lines.len > 0 && lines.first().is_blank() {
		lines = unsafe { lines[1..] }
	}

	// trim last line if it's blank
	if lines.len > 0 && lines.last().is_blank() {
		lines = unsafe { lines[..lines.len - 1] }
	}

	mut trimmed_lines := []string{cap: lines.len}

	for line in lines {
		if line.is_blank() {
			trimmed_lines << line
			continue
		}

		trimmed_lines << line[min_common_indent..]
	}

	return trimmed_lines.join('\n')
}

// indent_width returns the number of spaces or tabs at the beginning of the string.
// Example: assert '  v'.indent_width() == 2
// Example: assert '\t\tv'.indent_width() == 2
pub fn (s string) indent_width() int {
	for i, c in s {
		if !c.is_space() {
			return i
		}
	}

	return 0
}

// is_blank returns true if the string is empty or contains only white-space.
// Example: assert ' '.is_blank()
// Example: assert '\t'.is_blank()
// Example: assert 'v'.is_blank() == false
pub fn (s string) is_blank() bool {
	if s.len == 0 {
		return true
	}

	for c in s {
		if !c.is_space() {
			return false
		}
	}

	return true
}

// match_glob matches the string, with a Unix shell-style wildcard pattern.
// Note: wildcard patterns are NOT the same as regular expressions.
//   They are much simpler, and do not allow backtracking, captures, etc.
//   The special characters used in shell-style wildcards are:
// `*` - matches everything
// `?` - matches any single character
// `[seq]` - matches any of the characters in the sequence
// `[^seq]` - matches any character that is NOT in the sequence
//   Any other character in `pattern`, is matched 1:1 to the corresponding
// character in `name`, including / and \.
//   You can wrap the meta-characters in brackets too, i.e. `[?]` matches `?`
// in the string, and `[*]` matches `*` in the string.
// Example: assert 'ABCD'.match_glob('AB*')
// Example: assert 'ABCD'.match_glob('*D')
// Example: assert 'ABCD'.match_glob('*B*')
// Example: assert !'ABCD'.match_glob('AB')
@[direct_array_access]
pub fn (name string) match_glob(pattern string) bool {
	// Initial port based on https://research.swtch.com/glob.go
	// See also https://research.swtch.com/glob
	mut px := 0
	mut nx := 0
	mut next_px := 0
	mut next_nx := 0
	plen := pattern.len
	nlen := name.len
	for px < plen || nx < nlen {
		if px < plen {
			c := pattern[px]
			match c {
				`?` {
					// single-character wildcard
					if nx < nlen {
						px++
						nx++
						continue
					}
				}
				`*` {
					// zero-or-more-character wildcard
					// Try to match at nx.
					// If that doesn't work out, restart at nx+1 next.
					next_px = px
					next_nx = nx + 1
					px++
					continue
				}
				`[` {
					if nx < nlen {
						wanted_c := name[nx]
						mut bstart := px
						mut is_inverted := false
						mut inner_match := false
						mut inner_idx := bstart + 1
						mut inner_c := 0
						if inner_idx < plen {
							inner_c = pattern[inner_idx]
							if inner_c == `^` {
								is_inverted = true
								inner_idx++
							}
						}
						for ; inner_idx < plen; inner_idx++ {
							inner_c = pattern[inner_idx]
							if inner_c == `]` {
								break
							}
							if inner_c == wanted_c {
								inner_match = true
								for px < plen && pattern[px] != `]` {
									px++
								}
								break
							}
						}
						if is_inverted {
							if inner_match {
								return false
							} else {
								px = inner_idx
							}
						}
					}
					px++
					nx++
					continue
				}
				else {
					// an ordinary character
					if nx < nlen && name[nx] == c {
						px++
						nx++
						continue
					}
				}
			}
		}
		if 0 < next_nx && next_nx <= nlen {
			// A mismatch, try restarting:
			px = next_px
			nx = next_nx
			continue
		}
		return false
	}
	// Matched all of `pattern` to all of `name`
	return true
}

// is_ascii returns true if all characters belong to the US-ASCII set ([` `..`~`])
@[direct_array_access; inline]
pub fn (s string) is_ascii() bool {
	for i := 0; i < s.len; i++ {
		if s[i] < u8(` `) || s[i] > u8(`~`) {
			return false
		}
	}
	return true
}

// is_identifier checks if a string is a valid identifier (starts with letter/underscore, followed by letters, digits, or underscores)
@[direct_array_access]
pub fn (s string) is_identifier() bool {
	if s.len == 0 {
		return false
	}
	if !(s[0].is_letter() || s[0] == `_`) {
		return false
	}
	for i := 1; i < s.len; i++ {
		c := s[i]
		if !(c.is_letter() || c.is_digit() || c == `_`) {
			return false
		}
	}
	return true
}

// camel_to_snake convert string from camelCase to snake_case
// Example: assert 'Abcd'.camel_to_snake() == 'abcd'
// Example: assert 'aaBB'.camel_to_snake() == 'aa_bb'
// Example: assert 'BBaa'.camel_to_snake() == 'bb_aa'
// Example: assert 'aa_BB'.camel_to_snake() == 'aa_bb'
@[direct_array_access]
pub fn (s string) camel_to_snake() string {
	if s.len == 0 {
		return ''
	}
	if s.len == 1 {
		return s.to_lower_ascii()
	}
	mut b := unsafe { malloc_noscan(2 * s.len + 1) }
	// Rather than checking whether the iterator variable is > 1 inside the loop,
	// handle the first two chars separately to reduce load.
	mut pos := 2
	mut prev_is_upper := false
	unsafe {
		if s[0].is_capital() {
			b[0] = s[0] + 32
			b[1] = if s[1].is_capital() {
				prev_is_upper = true
				s[1] + 32
			} else {
				s[1]
			}
		} else {
			b[0] = s[0]
			if s[1].is_capital() {
				prev_is_upper = true
				if s[0] != `_` && s.len > 2 && !s[2].is_capital() {
					b[1] = `_`
					b[2] = s[1] + 32
					pos = 3
				} else {
					b[1] = s[1] + 32
				}
			} else {
				b[1] = s[1]
			}
		}
	}
	for i := 2; i < s.len; i++ {
		c := s[i]
		c_is_upper := c.is_capital()
		// Cases: `aBcd == a_bcd` || `ABcd == ab_cd`
		// TODO: remove this workaround for v2's parser
		// vfmt off
		if ((c_is_upper && !prev_is_upper) ||
			(!c_is_upper && prev_is_upper && s[i - 2].is_capital())) && 
			c != `_` {
			unsafe {
				if b[pos - 1] != `_` {
					b[pos] = `_`
					pos++
				}
			}
		}
		// vfmt on
		lower_c := if c_is_upper { c + 32 } else { c }
		unsafe {
			b[pos] = lower_c
		}
		prev_is_upper = c_is_upper
		pos++
	}
	unsafe {
		b[pos] = 0
	}
	return unsafe { tos(b, pos) }
}

// snake_to_camel convert string from snake_case to camelCase
// Example: assert 'abcd'.snake_to_camel() == 'Abcd'
// Example: assert 'ab_cd'.snake_to_camel() == 'AbCd'
// Example: assert '_abcd'.snake_to_camel() == 'Abcd'
// Example: assert '_abcd_'.snake_to_camel() == 'Abcd'
@[direct_array_access]
pub fn (s string) snake_to_camel() string {
	if s.len == 0 {
		return ''
	}
	if s.len == 1 {
		return s
	}
	mut need_upper := true
	mut upper_c := `_`
	mut b := unsafe { malloc_noscan(s.len + 1) }
	mut i := 0
	for c in s {
		upper_c = if c >= `a` && c <= `z` { c - 32 } else { c }
		if c == `_` {
			need_upper = true
		} else if need_upper {
			unsafe {
				b[i] = upper_c
			}
			i++
			need_upper = false
		} else {
			unsafe {
				b[i] = c
			}
			i++
		}
	}
	unsafe {
		b[i] = 0
	}
	return unsafe { tos(b, i) }
}

@[params]
pub struct WrapConfig {
pub:
	width int    = 80
	end   string = '\n'
}

// wrap wraps the string `s` when each line exceeds the width specified in `width` .
// (default value is 80), and will use `end` (default value is '\n') as a line break.
// Example: assert 'Hello, my name is Carl and I am a delivery'.wrap(width: 20) == 'Hello, my name is\nCarl and I am a\ndelivery'
pub fn (s string) wrap(config WrapConfig) string {
	if config.width <= 0 {
		return ''
	}
	words := s.fields()
	if words.len == 0 {
		return ''
	}
	mut sb := strings.new_builder(s.len)
	sb.write_string(words[0])
	mut space_left := config.width - words[0].len
	for i in 1 .. words.len {
		word := words[i]
		if word.len + 1 > space_left {
			sb.write_string(config.end)
			sb.write_string(word)
			space_left = config.width - word.len
		} else {
			sb.write_string(' ')
			sb.write_string(word)
			space_left -= 1 + word.len
		}
	}
	return sb.str()
}

// hex returns a string with the hexadecimal representation of the bytes of the string `s` .
pub fn (s string) hex() string {
	if s == '' {
		return ''
	}
	return unsafe { data_to_hex_string(&u8(s.str), s.len) }
}

@[unsafe]
fn data_to_hex_string(data &u8, len int) string {
	mut hex := malloc_noscan(u64(len) * 2 + 1)
	mut dst := 0
	for c in 0 .. len {
		b := data[c]
		n0 := b >> 4
		n1 := b & 0xF
		hex[dst] = if n0 < 10 { n0 + `0` } else { n0 + `W` }
		hex[dst + 1] = if n1 < 10 { n1 + `0` } else { n1 + `W` }
		dst += 2
	}
	hex[dst] = 0
	return tos(hex, dst)
}

pub struct RunesIterator {
mut:
	s string
	i int
}

// runes_iterator creates an iterator over all the runes in the given string `s`.
// It can be used in `for r in s.runes_iterator() {`, as a direct substitute to
// calling .runes(): `for r in s.runes() {`, which needs an intermediate allocation
// of an array.
pub fn (s string) runes_iterator() RunesIterator {
	return RunesIterator{
		s: s
		i: 0
	}
}

// next is the method that will be called for each iteration in `for r in s.runes_iterator() {` .
pub fn (mut ri RunesIterator) next() ?rune {
	if ri.i >= ri.s.len {
		return none
	}
	char_len := utf8_char_len(unsafe { ri.s.str[ri.i] })
	if char_len == 1 {
		res := unsafe { ri.s.str[ri.i] }
		ri.i++
		return res
	}
	start := &u8(unsafe { &ri.s.str[ri.i] })
	len := if ri.s.len - 1 >= ri.i + char_len { char_len } else { ri.s.len - ri.i }
	ri.i += char_len
	if char_len > 4 {
		return 0
	}
	return rune(impl_utf8_to_utf32(start, len))
}

///////////// module builtin

// byteptr.vbytes() - makes a V []u8 structure from a C style memory buffer. Note: the data is reused, NOT copied!
@[reused; unsafe]
pub fn (data byteptr) vbytes(len int) []u8 {
	return unsafe { voidptr(data).vbytes(len) }
}

// vstring converts a C style string to a V string. Note: the string data is reused, NOT copied.
// strings returned from this function will be normal V strings beside that (i.e. they would be
// freed by V's -autofree mechanism, when they are no longer used).
@[reused; unsafe]
pub fn (bp byteptr) vstring() string {
	return string{
		str: bp
		len: unsafe { vstrlen(bp) }
	}
}

// vstring_with_len converts a C style string to a V string.
// Note: the string data is reused, NOT copied.
@[reused; unsafe]
pub fn (bp byteptr) vstring_with_len(len int) string {
	return string{
		str:    bp
		len:    len
		is_lit: 0
	}
}

// vstring converts C char* to V string.
// Note: the string data is reused, NOT copied.
@[reused; unsafe]
pub fn (cp charptr) vstring() string {
	return string{
		str:    byteptr(cp)
		len:    unsafe { vstrlen_char(cp) }
		is_lit: 0
	}
}

// vstring_with_len converts C char* to V string.
// Note: the string data is reused, NOT copied.
@[reused; unsafe]
pub fn (cp charptr) vstring_with_len(len int) string {
	return string{
		str:    byteptr(cp)
		len:    len
		is_lit: 0
	}
}

// vstring_literal converts a C style string to a V string.
// Note: the string data is reused, NOT copied.
// NB2: unlike vstring, vstring_literal will mark the string
// as a literal, so it will not be freed by autofree.
// This is suitable for readonly strings, C string literals etc,
// that can be read by the V program, but that should not be
// managed by it, for example `os.args` is implemented using it.
@[reused; unsafe]
pub fn (bp byteptr) vstring_literal() string {
	return string{
		str:    bp
		len:    unsafe { vstrlen(bp) }
		is_lit: 1
	}
}

// vstring_with_len converts a C style string to a V string.
// Note: the string data is reused, NOT copied.
@[reused; unsafe]
pub fn (bp byteptr) vstring_literal_with_len(len int) string {
	return string{
		str:    bp
		len:    len
		is_lit: 1
	}
}

// vstring_literal converts C char* to V string.
// See also vstring_literal defined on byteptr for more details.
// Note: the string data is reused, NOT copied.
@[reused; unsafe]
pub fn (cp charptr) vstring_literal() string {
	return string{
		str:    byteptr(cp)
		len:    unsafe { vstrlen_char(cp) }
		is_lit: 1
	}
}

// vstring_literal_with_len converts C char* to V string.
// See also vstring_literal_with_len defined on byteptr.
// Note: the string data is reused, NOT copied.
@[reused; unsafe]
pub fn (cp charptr) vstring_literal_with_len(len int) string {
	return string{
		str:    byteptr(cp)
		len:    len
		is_lit: 1
	}
}

///////////// module builtin

// This file contains V functions for string interpolation

// StrIntpType is an enumeration of all the supported format types (max 32 types)
pub enum StrIntpType {
	si_no_str = 0 // no parameter to print only fix string
	si_c
	si_u8
	si_i8
	si_u16
	si_i16
	si_u32
	si_i32
	si_u64
	si_i64
	si_e32
	si_e64
	si_f32
	si_f64
	si_g32
	si_g64
	si_s
	si_p
	si_r
	si_vp
}

pub fn (x StrIntpType) str() string {
	return match x {
		.si_no_str { 'no_str' }
		.si_c { 'c' }
		.si_u8 { 'u8' }
		.si_i8 { 'i8' }
		.si_u16 { 'u16' }
		.si_i16 { 'i16' }
		.si_u32 { 'u32' }
		.si_i32 { 'i32' }
		.si_u64 { 'u64' }
		.si_i64 { 'i64' }
		.si_f32 { 'f32' }
		.si_f64 { 'f64' }
		.si_g32 { 'f32' } // g32 format use f32 data
		.si_g64 { 'f64' } // g64 format use f64 data
		.si_e32 { 'f32' } // e32 format use f32 data
		.si_e64 { 'f64' } // e64 format use f64 data
		.si_s { 's' }
		.si_p { 'p' }
		.si_r { 'r' } // repeat string
		.si_vp { 'vp' }
	}
}

// StrIntpMem is a union of data used by StrIntpData
pub union StrIntpMem {
pub mut:
	d_c   u32
	d_u8  u8
	d_i8  i8
	d_u16 u16
	d_i16 i16
	d_u32 u32
	d_i32 i32
	d_u64 u64
	d_i64 i64
	d_f32 f32
	d_f64 f64
	d_s   string
	d_r   string
	d_p   voidptr
	d_vp  voidptr
}

@[inline]
fn fabs32(x f32) f32 {
	return if x < 0 { -x } else { x }
}

@[inline]
fn fabs64(x f64) f64 {
	return if x < 0 { -x } else { x }
}

@[inline]
fn abs64(x i64) u64 {
	return if x < 0 { u64(-x) } else { u64(x) }
}

//  u32/u64 bit compact format
//___     32      24      16       8
//___      |       |       |       |
//_3333333333222222222211111111110000000000
//_9876543210987654321098765432109876543210
//_nPPPPPPPPBBBBWWWWWWWWWWTDDDDDDDSUAA=====
// = data type  5 bit  max 32 data type
// A align      2 bit  Note: for now only 1 used!
// U uppercase  1 bit  0 do nothing, 1 do to_upper()
// S sign       1 bit  show the sign if positive
// D decimals   7 bit  number of decimals digit to show
// T tail zeros 1 bit  1 remove tail zeros, 0 do nothing
// W Width     10 bit  number of char for padding and indentation
// B num base   4 bit  start from 2, 0 for base 10
// P pad char 1/8 bit  padding char (in u32 format reduced to 1 bit as flag for `0` padding)
//     --------------
//     TOTAL:  39/32 bit
//---------------------------------------

// convert from data format to compact u64
pub fn get_str_intp_u64_format(fmt_type StrIntpType, in_width int, in_precision int, in_tail_zeros bool,
	in_sign bool, in_pad_ch u8, in_base int, in_upper_case bool) u64 {
	width := if in_width != 0 { abs64(in_width) } else { u64(0) }
	align := if in_width > 0 { u64(1 << 5) } else { u64(0) } // two bit 0 .left 1 .right, for now we use only one
	upper_case := if in_upper_case { u64(1 << 7) } else { u64(0) }
	sign := if in_sign { u64(1 << 8) } else { u64(0) }
	precision := if in_precision != 987698 {
		(u64(in_precision & 0x7F) << 9)
	} else {
		u64(0x7F) << 9
	}
	tail_zeros := if in_tail_zeros { u32(1) << 16 } else { u32(0) }
	base := u64(u32(in_base & 0xf) << 27)
	res := u64((u64(fmt_type) & 0x1F) | align | upper_case | sign | precision | tail_zeros | (u64(width & 0x3FF) << 17) | base | (u64(in_pad_ch) << 31))
	return res
}

// convert from data format to compact u32
pub fn get_str_intp_u32_format(fmt_type StrIntpType, in_width int, in_precision int, in_tail_zeros bool,
	in_sign bool, in_pad_ch u8, in_base int, in_upper_case bool) u32 {
	width := if in_width != 0 { abs64(in_width) } else { u32(0) }
	align := if in_width > 0 { u32(1 << 5) } else { u32(0) } // two bit 0 .left 1 .right, for now we use only one
	upper_case := if in_upper_case { u32(1 << 7) } else { u32(0) }
	sign := if in_sign { u32(1 << 8) } else { u32(0) }
	precision := if in_precision != 987698 {
		(u32(in_precision & 0x7F) << 9)
	} else {
		u32(0x7F) << 9
	}
	tail_zeros := if in_tail_zeros { u32(1) << 16 } else { u32(0) }
	base := u32(u32(in_base & 0xf) << 27)
	res := u32((u32(fmt_type) & 0x1F) | align | upper_case | sign | precision | tail_zeros | (u32(width & 0x3FF) << 17) | base | (u32(in_pad_ch & 1) << 31))
	return res
}

// convert from struct to formatted string
@[manualfree]
fn (data &StrIntpData) process_str_intp_data(mut sb strings.Builder) {
	x := data.fmt
	typ := unsafe { StrIntpType(x & 0x1F) }
	align := int((x >> 5) & 0x01)
	upper_case := ((x >> 7) & 0x01) > 0
	sign := int((x >> 8) & 0x01)
	precision := int((x >> 9) & 0x7F)
	tail_zeros := ((x >> 16) & 0x01) > 0
	width := int(i16((x >> 17) & 0x3FF))
	mut base := int(x >> 27) & 0xF
	fmt_pad_ch := u8((x >> 31) & 0xFF)

	// no string interpolation is needed, return empty string
	if typ == .si_no_str {
		return
	}

	// if width > 0 { println("${x.hex()} Type: ${x & 0x7F} Width: ${width} Precision: ${precision} align:${align}") }

	// manage base if any
	if base > 0 {
		base += 2 // we start from 2, 0 == base 10
	}

	// mange pad char, for now only 0 allowed
	mut pad_ch := u8(` `)
	if fmt_pad_ch > 0 {
		// pad_ch = fmt_pad_ch
		pad_ch = `0`
	}

	len0_set := if width > 0 { width } else { -1 }
	len1_set := if precision == 0x7F { -1 } else { precision }
	sign_set := sign == 1

	mut bf := strconv.BF_param{
		pad_ch:       pad_ch     // padding char
		len0:         len0_set   // default len for whole the number or string
		len1:         len1_set   // number of decimal digits, if needed
		positive:     true       // mandatory: the sign of the number passed
		sign_flag:    sign_set   // flag for print sign as prefix in padding
		align:        .left      // alignment of the string
		rm_tail_zero: tail_zeros // false // remove the tail zeros from floats
	}

	// align
	if fmt_pad_ch == 0 || pad_ch == `0` {
		match align {
			0 { bf.align = .left }
			1 { bf.align = .right }
			// 2 { bf.align = .center }
			else { bf.align = .left }
		}
	} else {
		bf.align = .right
	}

	unsafe {
		// strings
		if typ == .si_s {
			if upper_case {
				s := data.d.d_s.to_upper()
				if width == 0 {
					sb.write_string(s)
				} else {
					strconv.format_str_sb(s, bf, mut sb)
				}
				s.free()
			} else {
				if width == 0 {
					sb.write_string(data.d.d_s)
				} else {
					strconv.format_str_sb(data.d.d_s, bf, mut sb)
				}
			}
			return
		}

		if typ == .si_r {
			if width > 0 {
				if upper_case {
					s := data.d.d_s.to_upper()
					for _ in 1 .. (1 + (if width > 0 {
						width
					} else {
						0
					})) {
						sb.write_string(s)
					}
					s.free()
				} else {
					for _ in 1 .. (1 + (if width > 0 {
						width
					} else {
						0
					})) {
						sb.write_string(data.d.d_s)
					}
				}
			}
			return
		}

		// signed int
		if typ in [.si_i8, .si_i16, .si_i32, .si_i64] {
			mut d := data.d.d_i64
			if typ == .si_i8 {
				d = i64(data.d.d_i8)
			} else if typ == .si_i16 {
				d = i64(data.d.d_i16)
			} else if typ == .si_i32 {
				d = i64(data.d.d_i32)
			}

			if base == 0 {
				if width == 0 {
					d_str := d.str()
					sb.write_string(d_str)
					d_str.free()
					return
				}
				if d < 0 {
					bf.positive = false
				}
				strconv.format_dec_sb(abs64(d), bf, mut sb)
			} else {
				// binary, we use 3 for binary
				if base == 3 {
					base = 2
				}
				mut absd, mut write_minus := d, false
				if d < 0 && pad_ch != ` ` {
					absd = -d
					write_minus = true
				}
				mut hx := strconv.format_int(absd, base)
				if upper_case {
					tmp := hx
					hx = hx.to_upper()
					tmp.free()
				}
				if write_minus {
					sb.write_u8(`-`)
					bf.len0-- // compensate for the `-` above
				}
				if width == 0 {
					sb.write_string(hx)
				} else {
					strconv.format_str_sb(hx, bf, mut sb)
				}
				hx.free()
			}
			return
		}

		// unsigned int and pointers
		if typ in [.si_u8, .si_u16, .si_u32, .si_u64] {
			mut d := data.d.d_u64
			if typ == .si_u8 {
				d = u64(data.d.d_u8)
			} else if typ == .si_u16 {
				d = u64(data.d.d_u16)
			} else if typ == .si_u32 {
				d = u64(data.d.d_u32)
			}
			if base == 0 {
				if width == 0 {
					d_str := d.str()
					sb.write_string(d_str)
					d_str.free()
					return
				}
				strconv.format_dec_sb(d, bf, mut sb)
			} else {
				// binary, we use 3 for binary
				if base == 3 {
					base = 2
				}
				mut hx := strconv.format_uint(d, base)
				if upper_case {
					tmp := hx
					hx = hx.to_upper()
					tmp.free()
				}
				if width == 0 {
					sb.write_string(hx)
				} else {
					strconv.format_str_sb(hx, bf, mut sb)
				}
				hx.free()
			}
			return
		}

		// pointers
		if typ == .si_p {
			mut d := data.d.d_u64
			base = 16 // TODO: **** decide the behaviour of this flag! ****
			if base == 0 {
				if width == 0 {
					d_str := d.str()
					sb.write_string(d_str)
					d_str.free()
					return
				}
				strconv.format_dec_sb(d, bf, mut sb)
			} else {
				mut hx := strconv.format_uint(d, base)
				if upper_case {
					tmp := hx
					hx = hx.to_upper()
					tmp.free()
				}
				if width == 0 {
					sb.write_string(hx)
				} else {
					strconv.format_str_sb(hx, bf, mut sb)
				}
				hx.free()
			}
			return
		}

		// default settings for floats
		mut use_default_str := false
		if width == 0 && precision == 0x7F {
			bf.len1 = 3
			use_default_str = true
		}
		if bf.len1 < 0 {
			bf.len1 = 3
		}

		match typ {
			// floating point
			.si_f32 {
				$if !nofloat ? {
					if use_default_str {
						mut f := data.d.d_f32.str()
						if upper_case {
							tmp := f
							f = f.to_upper()
							tmp.free()
						}
						sb.write_string(f)
						f.free()
					} else {
						if data.d.d_f32 < 0 {
							bf.positive = false
						}
						mut f := strconv.format_fl(data.d.d_f32, bf)
						if upper_case {
							tmp := f
							f = f.to_upper()
							tmp.free()
						}
						sb.write_string(f)
						f.free()
					}
				}
			}
			.si_f64 {
				$if !nofloat ? {
					if use_default_str {
						mut f := data.d.d_f64.str()
						if upper_case {
							tmp := f
							f = f.to_upper()
							tmp.free()
						}
						sb.write_string(f)
						f.free()
					} else {
						if data.d.d_f64 < 0 {
							bf.positive = false
						}
						f_union := strconv.Float64u{
							f: data.d.d_f64
						}
						if f_union.u == strconv.double_minus_zero {
							bf.positive = false
						}

						mut f := strconv.format_fl(data.d.d_f64, bf)
						if upper_case {
							tmp := f
							f = f.to_upper()
							tmp.free()
						}
						sb.write_string(f)
						f.free()
					}
				}
			}
			.si_g32 {
				if use_default_str {
					$if !nofloat ? {
						mut f := data.d.d_f32.strg()
						if upper_case {
							tmp := f
							f = f.to_upper()
							tmp.free()
						}
						sb.write_string(f)
						f.free()
					}
				} else {
					// Manage +/-0
					if data.d.d_f32 == strconv.single_plus_zero {
						tmp_str := '0'
						strconv.format_str_sb(tmp_str, bf, mut sb)
						tmp_str.free()
						return
					}
					if data.d.d_f32 == strconv.single_minus_zero {
						tmp_str := '-0'
						strconv.format_str_sb(tmp_str, bf, mut sb)
						tmp_str.free()
						return
					}
					// Manage +/-INF
					if data.d.d_f32 == strconv.single_plus_infinity {
						mut tmp_str := '+inf'
						if upper_case {
							tmp_str = '+INF'
						}
						strconv.format_str_sb(tmp_str, bf, mut sb)
						tmp_str.free()
					}
					if data.d.d_f32 == strconv.single_minus_infinity {
						mut tmp_str := '-inf'
						if upper_case {
							tmp_str = '-INF'
						}
						strconv.format_str_sb(tmp_str, bf, mut sb)
						tmp_str.free()
					}

					if data.d.d_f32 < 0 {
						bf.positive = false
					}
					d := fabs32(data.d.d_f32)
					if d < 999_999.0 && d >= 0.00001 {
						mut f := strconv.format_fl(data.d.d_f32, bf)
						if upper_case {
							tmp := f
							f = f.to_upper()
							tmp.free()
						}
						sb.write_string(f)
						f.free()
						return
					}
					// NOTE: For 'g' and 'G' bf.len1 is the maximum number of significant digits.
					// Not like 'e' or 'E', which is the number of digits after the decimal point.
					bf.len1--
					mut f := strconv.format_es(data.d.d_f32, bf)
					if upper_case {
						tmp := f
						f = f.to_upper()
						tmp.free()
					}
					sb.write_string(f)
					f.free()
				}
			}
			.si_g64 {
				if use_default_str {
					$if !nofloat ? {
						mut f := data.d.d_f64.strg()
						if upper_case {
							tmp := f
							f = f.to_upper()
							tmp.free()
						}
						sb.write_string(f)
						f.free()
					}
				} else {
					// Manage +/-0
					if data.d.d_f64 == strconv.double_plus_zero {
						tmp_str := '0'
						strconv.format_str_sb(tmp_str, bf, mut sb)
						tmp_str.free()
						return
					}
					if data.d.d_f64 == strconv.double_minus_zero {
						tmp_str := '-0'
						strconv.format_str_sb(tmp_str, bf, mut sb)
						tmp_str.free()
						return
					}
					// Manage +/-INF
					if data.d.d_f64 == strconv.double_plus_infinity {
						mut tmp_str := '+inf'
						if upper_case {
							tmp_str = '+INF'
						}
						strconv.format_str_sb(tmp_str, bf, mut sb)
						tmp_str.free()
					}
					if data.d.d_f64 == strconv.double_minus_infinity {
						mut tmp_str := '-inf'
						if upper_case {
							tmp_str = '-INF'
						}
						strconv.format_str_sb(tmp_str, bf, mut sb)
						tmp_str.free()
					}

					if data.d.d_f64 < 0 {
						bf.positive = false
					}
					d := fabs64(data.d.d_f64)
					if d < 999_999.0 && d >= 0.00001 {
						mut f := strconv.format_fl(data.d.d_f64, bf)
						if upper_case {
							tmp := f
							f = f.to_upper()
							tmp.free()
						}
						sb.write_string(f)
						f.free()
						return
					}
					// NOTE: For 'g' and 'G' bf.len1 is the maximum number of significant digits
					// Not like 'e' or 'E', which is the number of digits after the decimal point.
					bf.len1--
					mut f := strconv.format_es(data.d.d_f64, bf)
					if upper_case {
						tmp := f
						f = f.to_upper()
						tmp.free()
					}
					sb.write_string(f)
					f.free()
				}
			}
			.si_e32 {
				$if !nofloat ? {
					if use_default_str {
						mut f := data.d.d_f32.str()
						if upper_case {
							tmp := f
							f = f.to_upper()
							tmp.free()
						}
						sb.write_string(f)
						f.free()
					} else {
						if data.d.d_f32 < 0 {
							bf.positive = false
						}
						mut f := strconv.format_es(data.d.d_f32, bf)
						if upper_case {
							tmp := f
							f = f.to_upper()
							tmp.free()
						}
						sb.write_string(f)
						f.free()
					}
				}
			}
			.si_e64 {
				$if !nofloat ? {
					if use_default_str {
						mut f := data.d.d_f64.str()
						if upper_case {
							tmp := f
							f = f.to_upper()
							tmp.free()
						}
						sb.write_string(f)
						f.free()
					} else {
						if data.d.d_f64 < 0 {
							bf.positive = false
						}
						mut f := strconv.format_es(data.d.d_f64, bf)
						if upper_case {
							tmp := f
							f = f.to_upper()
							tmp.free()
						}
						sb.write_string(f)
						f.free()
					}
				}
			}
			// runes
			.si_c {
				ss := utf32_to_str(data.d.d_c)
				sb.write_string(ss)
				ss.free()
			}
			// v pointers
			.si_vp {
				ss := u64(data.d.d_vp).hex()
				sb.write_string(ss)
				ss.free()
			}
			else {
				sb.write_string('***ERROR!***')
			}
		}
	}
}

// StrIntpCgenData is a storing struct used by cgen
pub struct StrIntpCgenData {
pub:
	str string
	fmt string
	d   string
}

// StrIntpData is a LOW LEVEL struct, passed to V in the C code
pub struct StrIntpData {
pub:
	str string
	// fmt     u64  // expanded version for future use, 64 bit
	fmt u32
	d   StrIntpMem
}

// str_intp is the main entry point for string interpolation
@[direct_array_access; manualfree]
pub fn str_intp(data_len int, input_base &StrIntpData) string {
	mut res := strings.new_builder(64)
	for i := 0; i < data_len; i++ {
		data := unsafe { &input_base[i] }
		// avoid empty strings
		if data.str.len != 0 {
			res.write_string(data.str)
		}
		// skip empty data
		if data.fmt != 0 {
			data.process_str_intp_data(mut res)
		}
	}
	ret := res.str()
	unsafe { res.free() }
	return ret
}

// The consts here are utilities for the compiler's "auto_str_methods.v".
// They are used to substitute old _STR calls.
// FIXME: this const is not released from memory => use a precalculated string const for now.
// si_s_code = "0x" + int(StrIntpType.si_s).hex() // code for a simple string.
pub const si_s_code = '0xfe10'
pub const si_g32_code = '0xfe0e'
pub const si_g64_code = '0xfe0f'

@[inline]
pub fn str_intp_sq(in_str string) string {
	return 'builtin__str_intp(2, _MOV((StrIntpData[]){{_S("\'"), ${si_s_code}, {.d_s = ${in_str}}},{_S("\'"), 0, {.d_c = 0 }}}))'
}

@[inline]
pub fn str_intp_rune(in_str string) string {
	return 'builtin__str_intp(2, _MOV((StrIntpData[]){{_S("\`"), ${si_s_code}, {.d_s = ${in_str}}},{_S("\`"), 0, {.d_c = 0 }}}))'
}

@[inline]
pub fn str_intp_g32(in_str string) string {
	return 'builtin__str_intp(1, _MOV((StrIntpData[]){{_SLIT0, ${si_g32_code}, {.d_f32 = ${in_str} }}}))'
}

@[inline]
pub fn str_intp_g64(in_str string) string {
	return 'builtin__str_intp(1, _MOV((StrIntpData[]){{_SLIT0, ${si_g64_code}, {.d_f64 = ${in_str} }}}))'
}

// str_intp_sub replace %% with the in_str
@[manualfree]
pub fn str_intp_sub(base_str string, in_str string) string {
	index := base_str.index('%%') or {
		eprintln('No string interpolation %% parameters')
		exit(1)
	}
	// return base_str[..index] + in_str + base_str[index+2..]
	unsafe {
		st_str := base_str[..index]
		if index + 2 < base_str.len {
			en_str := base_str[index + 2..]
			res_str := 'builtin__str_intp(2, _MOV((StrIntpData[]){{_S("${st_str}"), ${si_s_code}, {.d_s = ${in_str} }},{_S("${en_str}"), 0, {.d_c = 0}}}))'
			st_str.free()
			en_str.free()
			return res_str
		}
		res2_str := 'builtin__str_intp(1, _MOV((StrIntpData[]){{_S("${st_str}"), ${si_s_code}, {.d_s = ${in_str} }}}))'
		st_str.free()
		return res2_str
	}
}

///////////// module builtin

const cp_acp = 0
const cp_utf8 = 65001

@[params]
pub struct ToWideConfig {
	from_ansi bool
}

// to_wide returns a pointer to an UTF-16 version of the string receiver.
// In V, strings are encoded using UTF-8 internally, but on windows most APIs,
// that accept strings, need them to be in UTF-16 encoding.
// The returned pointer of .to_wide(), has a type of &u16, and is suitable
// for passing to Windows APIs that expect LPWSTR or wchar_t* parameters.
// See also MultiByteToWideChar ( https://learn.microsoft.com/en-us/windows/win32/api/stringapiset/nf-stringapiset-multibytetowidechar )
// See also builtin.wchar.from_string/1, for a version, that produces a
// platform dependant L"" C style wchar_t* wide string.
pub fn (_str string) to_wide(param ToWideConfig) &u16 {
	$if windows {
		unsafe {
			src_encoding := if param.from_ansi { cp_acp } else { cp_utf8 }
			num_chars := (C.MultiByteToWideChar(src_encoding, 0, &char(_str.str), _str.len,
				0, 0))
			mut wstr := &u16(malloc_noscan((num_chars + 1) * 2)) // sizeof(wchar_t)
			if wstr != 0 {
				C.MultiByteToWideChar(src_encoding, 0, &char(_str.str), _str.len, wstr,
					num_chars)
				C.memset(&u8(wstr) + num_chars * 2, 0, 2)
			}
			return wstr
		}
	} $else {
		srunes := _str.runes()
		unsafe {
			mut result := &u16(vcalloc_noscan((srunes.len + 1) * 2))
			for i, r in srunes {
				result[i] = u16(r)
			}
			result[srunes.len] = 0
			return result
		}
	}
}

// string_from_wide creates a V string, encoded in UTF-8, given a windows
// style string encoded in UTF-16. Note that this function first searches
// for the string terminator 0 character, and is thus slower, while more
// convenient compared to string_from_wide2/2 (you have to know the length
// in advance to use string_from_wide2/2).
// See also builtin.wchar.to_string/1, for a version that eases working with
// the platform dependent &wchar_t L"" strings.
@[manualfree; unsafe]
pub fn string_from_wide(_wstr &u16) string {
	$if windows {
		unsafe {
			wstr_len := C.wcslen(_wstr)
			return string_from_wide2(_wstr, int(wstr_len))
		}
	} $else {
		mut i := 0
		for unsafe { _wstr[i] } != 0 {
			i++
		}
		return unsafe { string_from_wide2(_wstr, i) }
	}
}

// string_from_wide2 creates a V string, encoded in UTF-8, given a windows
// style string, encoded in UTF-16. It is more efficient, compared to
// string_from_wide, but it requires you to know the input string length,
// and to pass it as the second argument.
// See also builtin.wchar.to_string2/2, for a version that eases working
// with the platform dependent &wchar_t L"" strings.
@[manualfree; unsafe]
pub fn string_from_wide2(_wstr &u16, len int) string {
	$if windows {
		unsafe {
			num_chars := C.WideCharToMultiByte(cp_utf8, 0, _wstr, len, 0, 0, 0, 0)
			mut str_to := malloc_noscan(num_chars + 1)
			if str_to != 0 {
				C.WideCharToMultiByte(cp_utf8, 0, _wstr, len, &char(str_to), num_chars,
					0, 0)
				C.memset(str_to + num_chars, 0, 1)
			}
			return tos2(str_to)
		}
	} $else {
		mut sb := strings.new_builder(len)
		for i := 0; i < len; i++ {
			u := unsafe { rune(_wstr[i]) }
			sb.write_rune(u)
		}
		res := sb.str()
		unsafe { sb.free() }
		return res
	}
}

// wide_to_ansi create an ANSI string, given a windows style string, encoded in UTF-16.
// It use CP_ACP, which is ANSI code page identifier, as dest encoding.
// NOTE: It return a vstring(encoded in UTF-8) []u8 under Linux.
pub fn wide_to_ansi(_wstr &u16) []u8 {
	$if windows {
		num_bytes := C.WideCharToMultiByte(cp_acp, 0, _wstr, -1, 0, 0, 0, 0)
		if num_bytes != 0 {
			mut str_to := []u8{len: num_bytes}
			C.WideCharToMultiByte(cp_acp, 0, _wstr, -1, &char(str_to.data), str_to.len,
				0, 0)
			return str_to
		} else {
			return []u8{}
		}
	} $else {
		s := unsafe { string_from_wide(_wstr) }
		mut str_to := []u8{len: s.len + 1}
		unsafe { vmemcpy(str_to.data, s.str, s.len) }
		return str_to
	}
	return []u8{} // TODO: remove this, bug?
}

///////////// module builtin

// utf8_char_len returns the length in bytes of a UTF-8 encoded codepoint that starts with the byte `b`.
pub fn utf8_char_len(b u8) int {
	return ((0xe5000000 >> ((b >> 3) & 0x1e)) & 3) + 1
}

// Convert utf32 to utf8
// utf32 == Codepoint
pub fn utf32_to_str(code u32) string {
	unsafe {
		mut buffer := malloc_noscan(5)
		res := utf32_to_str_no_malloc(code, mut buffer)
		if res.len == 0 {
			// the buffer was not used at all
			free(buffer)
		}
		return res
	}
}

@[manualfree; unsafe]
pub fn utf32_to_str_no_malloc(code u32, mut buf &u8) string {
	unsafe {
		len := utf32_decode_to_buffer(code, mut buf)
		if len == 0 {
			return ''
		}
		buf[len] = 0
		return tos(buf, len)
	}
}

@[manualfree; unsafe]
pub fn utf32_decode_to_buffer(code u32, mut buf &u8) int {
	unsafe {
		icode := int(code) // Prevents doing casts everywhere
		mut buffer := &u8(buf)
		if icode <= 127 {
			// 0x7F
			buffer[0] = u8(icode)
			return 1
		} else if icode <= 2047 {
			// 0x7FF
			buffer[0] = 192 | u8(icode >> 6) // 0xC0 - 110xxxxx
			buffer[1] = 128 | u8(icode & 63) // 0x80 - 0x3F - 10xxxxxx
			return 2
		} else if icode <= 65535 {
			// 0xFFFF
			buffer[0] = 224 | u8(icode >> 12) // 0xE0 - 1110xxxx
			buffer[1] = 128 | (u8(icode >> 6) & 63) // 0x80 - 0x3F - 10xxxxxx
			buffer[2] = 128 | u8(icode & 63) // 0x80 - 0x3F - 10xxxxxx
			return 3
		}
		// 0x10FFFF
		else if icode <= 1114111 {
			buffer[0] = 240 | u8(icode >> 18) // 0xF0 - 11110xxx
			buffer[1] = 128 | (u8(icode >> 12) & 63) // 0x80 - 0x3F - 10xxxxxx
			buffer[2] = 128 | (u8(icode >> 6) & 63) // 0x80 - 0x3F - 10xxxxxx
			buffer[3] = 128 | u8(icode & 63) // 0x80 - 0x3F - 10xxxxxx
			return 4
		}
	}
	return 0
}

// Convert utf8 to utf32
// the original implementation did not check for
// valid utf8 in the string, and could result in
// values greater than the utf32 spec
// it has been replaced by `utf8_to_utf32` which
// has an option return type.
//
// this function is left for backward compatibility
// it is used in vlib/builtin/string.v,
// and also in vlib/v/gen/c/cgen.v
pub fn (_rune string) utf32_code() int {
	if _rune.len > 4 {
		return 0
	}
	return int(impl_utf8_to_utf32(&u8(_rune.str), _rune.len))
}

// convert array of utf8 bytes to single utf32 value
// will error if more than 4 bytes are submitted
pub fn (_bytes []u8) utf8_to_utf32() !rune {
	if _bytes.len > 4 {
		return error('attempted to decode too many bytes, utf-8 is limited to four bytes maximum')
	}
	return impl_utf8_to_utf32(&u8(_bytes.data), _bytes.len)
}

@[direct_array_access]
fn impl_utf8_to_utf32(_bytes &u8, _bytes_len int) rune {
	if _bytes_len == 0 {
		return 0
	}
	// return ASCII unchanged
	if _bytes_len == 1 {
		return unsafe { rune(_bytes[0]) }
	}
	mut b := u8(int(unsafe { _bytes[0] }))
	b = b << _bytes_len
	mut res := rune(b)
	mut shift := 6 - _bytes_len
	for i := 1; i < _bytes_len; i++ {
		c := rune(unsafe { _bytes[i] })
		res = rune(res) << shift
		res |= c & 63 // 0x3f
		shift = 6
	}
	return res
}

// Calculate string length for formatting, i.e. number of "characters"
// This is simplified implementation. if you need specification compliant width,
// use utf8.east_asian.display_width.
pub fn utf8_str_visible_length(s string) int {
	mut l := 0
	mut ul := 1
	for i := 0; i < s.len; i += ul {
		c := unsafe { s.str[i] }
		ul = ((0xe5000000 >> ((unsafe { s.str[i] } >> 3) & 0x1e)) & 3) + 1
		if i + ul > s.len { // incomplete UTF-8 sequence
			return l
		}
		l++
		// avoid the match if not needed
		if ul == 1 {
			continue
		}
		// recognize combining characters and wide characters
		match ul {
			2 {
				r := u64((u16(c) << 8) | unsafe { s.str[i + 1] })
				if r >= 0xcc80 && r < 0xcdb0 {
					// diacritical marks
					l--
				}
			}
			3 {
				r := u64((u32(c) << 16) | unsafe { (u32(s.str[i + 1]) << 8) | s.str[i + 2] })
				// diacritical marks extended
				// diacritical marks supplement
				// diacritical marks for symbols
				// TODO: remove this workaround for v2's parser
				// vfmt off
				if (r >= 0xe1aab0 && r <= 0xe1ac7f) ||
				    (r >= 0xe1b780 && r <= 0xe1b87f) ||
					(r >= 0xe28390 && r <= 0xe2847f) ||
					(r >= 0xefb8a0 && r <= 0xefb8af) {
					// diacritical marks
					l--
				}
				// Hangru
				// CJK Unified Ideographics
				// Hangru
				// CJK
				else if (r >= 0xe18480 && r <= 0xe1859f) ||
					(r >= 0xe2ba80 && r <= 0xe2bf95) ||
					(r >= 0xe38080 && r <= 0xe4b77f) ||
					(r >= 0xe4b880 && r <= 0xea807f) ||
					(r >= 0xeaa5a0 && r <= 0xeaa79f) ||
					(r >= 0xeab080 && r <= 0xed9eaf) ||
					(r >= 0xefa480 && r <= 0xefac7f) ||
					(r >= 0xefb8b8 && r <= 0xefb9af) {
					// half marks
					l++
				}
				// vfmt on
			}
			4 {
				r := u64((u32(c) << 24) | unsafe {
					(u32(s.str[i + 1]) << 16) | (u32(s.str[i + 2]) << 8) | s.str[i + 3]
				})
				// Enclosed Ideographic Supplement
				// Emoji
				// CJK Unified Ideographs Extension B-G
				// TODO: remove this workaround for v2's parser
				// vfmt off
				if (r >= 0xf09f8880 && r <= 0xf09f8a8f) ||
					(r >= 0xf09f8c80 && r <= 0xf09f9c90) ||
					(r >= 0xf09fa490 && r <= 0xf09fa7af) ||
					(r >= 0xf0a08080 && r <= 0xf180807f) {
					l++
				}
				// vfmt on
			}
			else {}
		}
	}
	return l
}

// string_to_ansi_not_null_terminated returns an ANSI version of the string `_str`.
// NOTE: This is most useful for converting a vstring to an ANSI string under Windows.
// NOTE: The ANSI string return is not null-terminated, then you can use `os.write_file_array` write an ANSI file.
pub fn string_to_ansi_not_null_terminated(_str string) []u8 {
	wstr := _str.to_wide()
	mut ansi := wide_to_ansi(wstr)
	if ansi.len > 0 {
		unsafe { ansi.len-- } // remove tailing zero
	}
	return ansi
}
