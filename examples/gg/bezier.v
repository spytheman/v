module main

import gg

const points = [f32(200.0), 200.0, 200.0, 100.0, 400.0, 100.0, 400.0, 300.0]

struct App {
mut:
	gg &gg.Context
}

fn main() {
	mut app := &App{
		gg: 0
	}
	app.gg = gg.new_context(
		bg_color: gg.rgb(174, 198, 255)
		width: 600
		height: 400
		window_title: 'Cubic Bézier curve'
		frame_fn: frame
		user_data: app
	)
	app.gg.run()
}

fn frame(mut app App) {
	app.gg.begin()
	app.gg.draw_cubic_bezier(points, gg.blue)
	app.gg.end()
}
