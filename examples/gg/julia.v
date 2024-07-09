import gg
import time

const pwidth = 1920

const pheight = 1080

struct AppState {
mut:
	gg          &gg.Context = unsafe { nil }
	istream_idx int
	pixels      [pheight][pwidth]u32
	zoom        f64 = 1.0
	cx          f64 = -0.7
	cy          f64 = 0.27015
	mx          f64 = 0.0
	my          f64 = 0.0
	max_iter    u32 = 255
	volatile action      ActionKind
}

enum ActionKind {
	drawing
	idle
	changed
}

@[direct_array_access]
fn (mut state AppState) update() {
	unsafe { vmemset(&state.pixels, 0xFF, sizeof(state.pixels)) }

	for {
		state.action = .drawing
		sw := time.new_stopwatch()
		for y in 0 .. pheight {
			if state.action != .drawing {
				break
			}
			for x in 0 .. pwidth {
				mut zx := 1.5 * (x - pwidth / 2) / (0.5 * state.zoom * pwidth) + state.mx
				mut zy := 1.0 * (y - pheight / 2) / (0.5 * state.zoom * pheight) + state.my
				mut i := state.max_iter
				for zx * zx + zy * zy < 4 && i > 1 {
					tmp := zx * zx - zy * zy + state.cx
					zy, zx = 2.0 * zx * zy + state.cy, tmp
					i--
				}
				state.pixels[y][x] = 0xFF_00_00_00 | (i << 21) + (i << 10) + i * 8
			}
		}
		println('> calculation time: ${sw.elapsed().milliseconds():5}ms, zoom: ${state.zoom:6.3f}, action: ${state.action}')
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
