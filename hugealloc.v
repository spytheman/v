struct AppState {
mut:
	pixels  [1024][1024]u32
}

fn main() {
	base1 := 0
    base2 := 0
	mut state := &AppState{}
	base3 := 0
	state.pixels[0][0] = 123
	eprintln('> pixels[0][0]: ${state.pixels[0][0]}')
	eprintln('> base1: ${voidptr(&base1)} | diff: 0')
	eprintln('> base2: ${voidptr(&base2)} | diff: ${u64(&base1) - u64(&base2)}')
	eprintln('> base3: ${voidptr(&base3)} | diff: ${u64(&base2) - u64(&base3)}')
}
