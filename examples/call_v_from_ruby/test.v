// Note: compile this with `v -d no_backtrace -shared test.v`
module test

import math

@[export: 'square']
fn square(i int) int {
        return i * i
}

@[export: 'sqrt_of_sum_of_squares']
fn sqrt_of_sum_of_squares(x f64, y f64) f64 {
        return math.sqrt(x * x + y * y)
}

// you do not have to use the same name in the export attribute
@[export: 'process_v_string_cstrings']
fn work(input &char) &char {
        s := unsafe { input.vstring_literal() }
        eprintln(s.len)
        eprintln(s)
        // println(s.is_lit)
        return 'v ${s} v'.str
}

// you do not have to use the same name in the export attribute
@[export: 'process_v_string']
fn work2(s string) string {
        ps := unsafe { voidptr(&s) }
        eprintln('> v      &s: ${ps}')
        eprintln('> v   s.str: ${voidptr(s.str)}')
        eprintln('> v   s.len: ${voidptr(s.len)}')
        res := 'v ${s} v'
        pres := unsafe{ voidptr(&res) }
        eprintln('> v    &res: ${pres}')
        eprintln('> v res.str: ${voidptr(res.str)}')
        eprintln('> v res.len: ${voidptr(res.len)}')
        return res
}
