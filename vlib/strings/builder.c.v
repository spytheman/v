// Copyright (c) 2019-2020 Alexander Medvednikov. All rights reserved.
// Use of this source code is governed by an MIT license
// that can be found in the LICENSE file.
module strings

pub struct Builder {
	// TODO
pub mut:
	buf          []byte
	str_calls    int
	len          int
	initial_size int = 1
}

pub fn new_builder(initial_size int) Builder {
	return Builder{
		//buf: make(0, initial_size)
		buf: []byte{cap: initial_size}
		str_calls: 0
		len: 0
		initial_size: initial_size
	}
}

pub fn (b mut Builder) write_bytes(bytes byteptr, howmany int) {
	b.buf.push_many(bytes, howmany)
	b.len += howmany
}

pub fn (b mut Builder) write_b(data byte) {
	b.buf << data
	b.len++
}

pub fn (b mut Builder) write(s string) {
	if s == '' {
		return
	}
	b.buf.push_many(s.str, s.len)
	// for c in s {
	// b.buf << c
	// }
	// b.buf << []byte(s)  // TODO
	b.len += s.len
}

pub fn (b mut Builder) go_back(n int) {
	b.buf.trim(b.buf.len-n)
	b.len -= n
}

pub fn (b mut Builder) go_back_to(pos int) {
	b.buf.trim(pos)
	b.len = pos
}

pub fn (b mut Builder) writeln(s string) {
	// for c in s {
	// b.buf << c
	// }
	b.buf.push_many(s.str, s.len)
	// b.buf << []byte(s)  // TODO
	b.buf << `\n`
	b.len += s.len + 1
}

// buf == 'hello world'
// last_n(5) returns 'world'
pub fn (b &Builder) last_n(n int) string {
	if n > b.len {
		return ''
	}
	buf := b.buf[b.len-n..]
	return string(buf.clone())
}

// buf == 'hello world'
// after(6) returns 'world'
pub fn (b &Builder) after(n int) string {
	if n >= b.len {
		return ''
	}
	buf := b.buf[n..]
	mut copy := buf.clone()
	copy << `\0`
	return string(copy)
}

// NB: in order to avoid memleaks and additional memory copies, after a call to b.str(),
// the builder b will be empty. The returned string *owns* the accumulated data so far.
pub fn (b mut Builder) str() string {
	b.str_calls++
	if b.str_calls > 1 {
		panic('builder.str() should be called just once.\n' +
			'If you want to reuse a builder, call b.free() first.')
	}
	b.buf << `\0`
	s := string(b.buf,b.len)
	bis := b.initial_size
	b.buf = []byte{cap: bis}
	b.len = 0
	return s
}

pub fn (b mut Builder) free() {
	unsafe{
		free(b.buf.data)
	}
	//b.buf = []byte{cap: b.initial_size}
	b.len = 0
	b.str_calls = 0
}
