module main

import gg
import gx
import sokol.sgl
import sokol.sapp
import rand
import math

const (
	start_boids          = 500
	left_click_new_boids = 100
	max_boids            = 16000
	win_width            = 800
	win_height           = 600
	max_speed            = 3.5
	max_speed2           = max_speed * max_speed
	max_force            = 0.03
	right_click_color    = gx.rgba(250, 250, 250, 64)
	right_click_radius   = 200
)

fn main() {
	mut app := &App{}
	mut context := gg.new_context(
		bg_color: gx.rgb(10, 10, 64)
		width: win_width
		height: win_height
		window_title: 'Flocking Boids'
		sample_count: 2 // use multisampling/antialiasing for the triangle sides
		user_data: app
		frame_fn: app.frame
		click_fn: app.click
		keydown_fn: app.key_down
	)
	app.gg = context
	app.init_boids()
	context.run()
}

[heap]
struct App {
mut:
	boids        []Boid
	right_clicks []Click
	gg           &gg.Context = unsafe { nil }
	width        f32
	height       f32
}

fn (mut app App) init_boids() {
	for _ in 0 .. start_boids {
		app.boids << new_boid()
	}
}

struct Click {
mut:
	x f32
	y f32
	r f32
}

fn (mut app App) click(x f32, y f32, btn gg.MouseButton, _ voidptr) {
	match btn {
		.left {
			if app.boids.len + left_click_new_boids > max_boids {
				return
			}
			for _ in 0 .. left_click_new_boids {
				mut boid := new_boid()
				boid.x = x
				boid.y = y
				app.boids << boid
			}
		}
		.middle {
			app.boids = []
		}
		.right {
			c := Click{
				x: x
				y: y
				r: right_click_radius
			}
			app.right_clicks << c
			for mut b in app.boids {
				dx := c.x - b.x
				dy := c.y - b.y
				d := math.pow(math.pow(dx, 2) + math.pow(dy, 2), 0.5)
				if d != 0 && d < c.r {
					b.ax = f32(dx / d)
					b.ay = f32(dy / d)
				}
			}
		}
		else {}
	}
}

fn (mut app App) frame() {
	app.width = sapp.width()
	app.height = sapp.height()
	app.update()

	app.gg.begin()
	app.draw_boids()
	app.draw_right_clicks()
	app.draw_top_banner()
	app.gg.end()
}

fn (mut app App) draw_top_banner() {
	for _ in 0 .. 2 {
		app.gg.draw_rect_filled(25, 1, 620, 18, right_click_color)
	}
	app.gg.draw_text_def(30, 3, 'Boids: ${app.boids.len:05}. Esc to exit. Left click creates more boids. Right click attracts near boids.')
}

fn (mut app App) draw_right_clicks() {
	for c in app.right_clicks {
		app.gg.draw_circle_filled(c.x, c.y, c.r, right_click_color)
	}
}

const sinf_wave = make_wave()

const period = 60

fn make_wave() []f32 {
	mut res := []f32{}
	for f in 0 .. period {
		res << math.sinf(math.tau * (f32(f) / period))
	}
	return res
}

fn (mut app App) draw_boids() {
	for idx, mut b in app.boids {
		f := sinf_wave[(int(app.gg.frame) + idx) % period]
		r := b.r + f
		sgl.push_matrix()
		sgl.translate(b.x, b.y, 0)
		sgl.rotate(b.angle, 0, 0, 1.0)
		app.gg.draw_triangle_filled(0, -r * 2, -r, r * 2, r, r * 2, b.color)
		sgl.pop_matrix()
	}
}

fn (mut app App) update() {
	app.move()
	app.limit_speeds()
	app.orient_towards_velocity_vector()
	app.wrap_around_borders()
	app.attract_to_right_click_zones()
}

fn (mut app App) attract_to_right_click_zones() {
	if app.right_clicks.len == 0 {
		return
	}
	for mut c in app.right_clicks {
		c.r -= 5
	}
	app.right_clicks = app.right_clicks.filter(it.r > 0)
}

fn (mut app App) orient_towards_velocity_vector() {
	for mut b in app.boids {
		b.angle = f32(math.atan2(b.vy, b.vx)) + math.pi_2
	}
}

fn (mut app App) move() {
	for mut b in app.boids {
		b.vx += b.ax
		b.vy += b.ay
		//
		b.x += b.vx
		b.y += b.vy
	}
}

fn (mut app App) limit_speeds() {
	for mut b in app.boids {
		if b.ax == 0 && b.ay == 0 {
			continue
		}
		if b.vx * b.vx + b.vy * b.vy > max_speed2 {
			t := math.atan2(b.vy, b.vx)
			b.vx = f32(math.cos(t) * max_speed)
			b.vy = f32(math.sin(t) * max_speed)
			b.ax = 0
			b.ay = 0
		}
	}
}

fn (mut app App) wrap_around_borders() {
	for mut b in app.boids {
		if b.x < -b.r {
			b.x = app.width + b.r
		}
		if b.y < -b.r {
			b.y = app.height + b.r
		}
		if b.x > app.width + b.r {
			b.x = -b.r
		}
		if b.y > app.height + b.r {
			b.y = -b.r
		}
	}
}

struct Boid {
mut:
	x     f32 // position
	y     f32
	vx    f32 // velocity
	vy    f32
	ax    f32 // acceleration
	ay    f32
	r     f32      = 6.0 // size
	angle f32      = 0.0
	color gx.Color = gx.blue
}

fn new_boid() Boid {
	return Boid{
		x: rand.f32() * (win_width - 20) + 10
		y: rand.f32() * (win_height - 20) + 10
		r: rand.f32() * 2 + 4
		vx: f32_around_zero()
		vy: f32_around_zero()
		ax: 0.02 * f32_around_zero()
		ay: 0.02 * f32_around_zero()
		angle: rand.f32() * math.tau
		color: gx.rgb(rcolor(), rcolor(), rcolor())
	}
}

fn f32_around_zero() f32 {
	return 0.5 - rand.f32()
}

fn rcolor() u8 {
	return u8(127 + 127 * rand.f32())
}

fn (mut app App) key_down(key gg.KeyCode, modifier gg.Modifier, x voidptr) {
	match key {
		.escape { app.gg.quit() }
		else {}
	}
}
