// Copyright (c) 2025 Delyan Angelov. All rights reserved.
// Use of this source code is governed by an MIT license
// that can be found in the LICENSE file.
@[has_globals]
module counters

import sync.stdatomic

__global g_counters = new_counters()

@[heap]
pub struct Counters {
mut:
	values map[string]&stdatomic.AtomicVal[i64]
}

fn new_counters() &Counters {
	return &Counters{
		values: map[string]&stdatomic.AtomicVal[i64]{}
	}
}

pub fn get_counters() &Counters {
	return g_counters
}

pub fn inc(key string) i64 {
	return g_counters.inc(key)
}

pub fn dec(key string) i64 {
	return g_counters.dec(key)
}

pub fn get(key string) i64 {
	return g_counters.get(key)
}

pub fn (mut c Counters) inc(name string) i64 {
	mut counter := c.get_counter_for_key(name)
	counter.add(1)
	return counter.load()
}

pub fn (mut c Counters) dec(name string) i64 {
	mut counter := c.get_counter_for_key(name)
	counter.sub(1)
	return counter.load()
}

pub fn (mut c Counters) get(name string) i64 {
	mut counter := c.get_counter_for_key(name)
	return counter.load()
}

pub fn (mut c Counters) get_counter_for_key(name string) &stdatomic.AtomicVal[i64] {
	if name !in c.values {
		c.values[name] = stdatomic.new_atomic(i64(0))
	}
	return unsafe { c.values[name] }
}

pub fn show(really bool) {
	if !really {
		return
	}
	keys := g_counters.values.keys().sorted()
	for key in keys {
		println('> v.counter ${key} = ${g_counters.get(key)}')
	}
}
