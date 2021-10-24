module main

import gg
import os

struct App {
mut:
	image gg.Image
}

fn main() {
	gg.set_context_config(
		bg_color: gg.white
		width: 600
		height: 300
		window_title: 'Rectangles'
		frame_fn: frame
	)
	gg.run(&App{}, fn (mut app App) {
		app.image = gg.new_image(os.resource_abs_path('logo.png'))
	})
}

fn frame(mut app App) {
	gg.begin()
	gg.draw_rect(10, 10, 100, 30, gg.blue)
	gg.draw_empty_rect(110, 150, 80, 40, gg.black)
	gg.draw_image(230, 30, app.image.width, app.image.height, app.image)
	gg.end()
}
