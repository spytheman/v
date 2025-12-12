module strings

// Builder is used to efficiently append many strings to a large buffer.
@[deprecated: 'use the builtin StringBuilder instead']
@[deprecated_after: '2026-09-12']
pub type Builder = []u8

// new_builder returns a new string builder, with an initial capacity of `initial_size`.
@[deprecated: 'use the builtin `new_string_builder(cap: size)` instead']
@[deprecated_after: '2026-09-12']
pub fn new_builder(initial_size int) StringBuilder {
   return new_string_builder(cap: initial_size)
}
