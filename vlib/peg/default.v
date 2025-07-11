// Copyright (c) 2025 Delyan Angelov. All rights reserved.
// Use of this source code is governed by an MIT license
// that can be found in the LICENSE file.

module peg

pub const d = range('09')
pub const a = range('az', 'AZ')
pub const w = range('az', 'AZ', '09')
pub const s = set(' \t\r\n\0\f\v')
pub const h = range('09', 'af', 'AF')
pub const nd = not(d)
pub const na = not(a)
pub const nw = not(w)
pub const ns = not(s)
pub const nh = not(h)
pub const sd = some(d)
pub const sa = some(a)
pub const sw = some(w)
pub const ss = some(s)
pub const sh = some(h)
pub const ad = any_(d)
pub const aa = any_(a)
pub const aw = any_(w)
pub const as = any_(s)
pub const ah = any_(h)
