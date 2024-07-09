import gg
import time
import rand
import runtime

const pwidth = 1920

const pheight = 1024

const ntiles = 30

@[heap]
struct AppState {
mut:
	gg          &gg.Context = unsafe { nil }
	istream_idx int
	pixels      [pheight][pwidth]u32
	zoom        f64 = 0.5
	cx          f64 = -0.7
	cy          f64 = 0.27015
	mx          f64 = 0.0
	my          f64 = 0.0
	max_iter    u32 = 255
	volatile action      ActionKind
	//
	work chan Tile = chan Tile{cap: ntiles * ntiles}
	done chan bool = chan bool{cap: ntiles * ntiles}
}

enum ActionKind {
	drawing
	idle
	changed
}

@[direct_array_access]
fn (mut state AppState) draw_tile(yymin int, yymax int, xxmin int, xxmax int) {
	for y in yymin .. yymax {
		if state.action != .drawing {
			return
		}
		for x in xxmin .. xxmax {
			mut zx := 1.5 * (f64(x) - pwidth / 2) / (0.5 * state.zoom * pwidth) + state.mx
			mut zy := 1.0 * (f64(y) - pheight / 2) / (0.5 * state.zoom * pheight) + state.my
			mut i := state.max_iter
			for zx * zx + zy * zy < 4 && i > 1 {
				tmp := zx * zx - zy * zy + state.cx
				zy, zx = 2.0 * zx * zy + state.cy, tmp
				i--
			}
			state.pixels[y][x] = 0xFF_00_00_00 | (i << 21) + (i << 10) + i * 8
		}
	}
}

struct Tile {
	n    int
	ymin int
	ymax int
	xmin int
	xmax int
}

fn (mut state AppState) worker() {
	for {
		tile := <-state.work
		// eprintln('> tile ${tile.n:5}: ${tile.ymin}, ${tile.ymax}, ${tile.xmin}, ${tile.xmax}')
		state.draw_tile(tile.ymin, tile.ymax, tile.xmin, tile.xmax)
		state.done <- true
	}
}

fn (mut state AppState) update() {
	unsafe { vmemset(&state.pixels, 0xFF, sizeof(state.pixels)) }
	mut tasks := []thread{}
	for _ in 0 .. runtime.nr_jobs() {
		tasks << spawn state.worker()
	}
	mut all_tiles := []Tile{cap: ntiles * ntiles}
	for i in 0 .. ntiles {
		for j in 0 .. ntiles {
			all_tiles << Tile{
				n: i * ntiles + j
				ymin: pheight * i / ntiles
				ymax: pheight * (i + 1) / ntiles
				xmin: pwidth * j / ntiles
				xmax: pwidth * (j + 1) / ntiles
			}
		}
	}
	rand.shuffle(mut all_tiles) or {}
	for {
		state.action = .drawing
		sw := time.new_stopwatch()
		for tile in all_tiles {
			state.work <- tile
		}
		for _ in 0 .. ntiles * ntiles {
			_ := <-state.done
		}
		println('> tasks: ${tasks.len}, tiles: ${all_tiles.len}, calculation time: ${sw.elapsed().milliseconds():5}ms, zoom: ${state.zoom:6.3f}, action: ${state.action}')
		state.action = .idle
		time.sleep(10 * time.millisecond)
	}
}

fn (mut state AppState) draw() {
	mut istream_image := state.gg.get_cached_image_by_idx(state.istream_idx)
	istream_image.update_pixel_data(unsafe { &u8(&state.pixels) })
	size := gg.window_size()
	state.gg.draw_image(0, 0, size.width, size.height, istream_image)
}

// gg callbacks:

fn graphics_init(mut state AppState) {
	state.istream_idx = state.gg.new_streaming_image(pwidth, pheight, 4, pixel_format: .rgba8)
}

fn graphics_frame(mut state AppState) {
	state.gg.begin()
	state.draw()
	state.gg.end()
}

fn graphics_scroll(e &gg.Event, mut state AppState) {
	if e.scroll_y < 0 {
		state.zoom -= 0.1
	} else {
		state.zoom += 0.1
	}
	// println('zoom: ${state.zoom}')
	state.action = .changed
}

fn main() {
	mut state := &AppState{}
	state.gg = gg.new_context(
		width: pwidth
		height: pheight
		create_window: true
		window_title: 'Julia Set'
		init_fn: graphics_init
		frame_fn: graphics_frame
		scroll_fn: graphics_scroll
		user_data: state
	)
	spawn state.update()
	state.gg.run()
}
