module main

import gg
import gx
import sokol.sgl
import sokol.sapp
import rand
import math

const (
	start_boids          = 100
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
	position Vector2D
	r        f32
}

fn (mut app App) click(x f32, y f32, btn gg.MouseButton, _ voidptr) {
	match btn {
		.left {
			if app.boids.len + left_click_new_boids > max_boids {
				return
			}
			for _ in 0 .. left_click_new_boids {
				mut boid := new_boid()
				boid.position.x = x
				boid.position.y = y
				app.boids << boid
			}
		}
		.right {
			c := Click{
				position: Vector2D{x, y}
				r: right_click_radius
			}
			app.right_clicks << c
			for mut b in app.boids {
				d := c.position - b.position
				distance := d.length()
				if distance != 0 && distance < c.r {
					b.acceleration = d.divide_by(distance)
				}
			}
		}
		else {}
	}
}

fn (mut app App) key_down(key gg.KeyCode, modifier gg.Modifier, x voidptr) {
	match key {
		.escape { app.gg.quit() }
		.c { app.boids = [] }
		else {}
	}
}

fn (mut app App) frame() {
	app.width = sapp.width()
	app.height = sapp.height()
	app.update()
	//
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
		app.gg.draw_circle_filled(c.position.x, c.position.y, c.r, right_click_color)
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
		r := b.size + f
		sgl.push_matrix()
		sgl.translate(b.position.x, b.position.y, 0)
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
		b.angle = f32(math.atan2(b.velocity.y, b.velocity.x)) + math.pi_2
	}
}

fn (mut app App) move() {
	for mut b in app.boids {
		b.velocity += b.acceleration
		b.position += b.velocity
	}
}

fn (mut app App) limit_speeds() {
	for mut b in app.boids {
		if b.acceleration.is_zero() {
			continue
		}
		if b.velocity.magnitude2() > max_speed2 {
			b.velocity = b.velocity.limit_to(max_speed)
			b.acceleration = Vector2D{0, 0}
		}
	}
}

fn (mut app App) wrap_around_borders() {
	for mut b in app.boids {
		if b.position.x < -b.size {
			b.position.x = app.width + b.size
		}
		if b.position.y < -b.size {
			b.position.y = app.height + b.size
		}
		if b.position.x > app.width + b.size {
			b.position.x = -b.size
		}
		if b.position.y > app.height + b.size {
			b.position.y = -b.size
		}
	}
}

//

struct Vector2D {
mut:
	x f32
	y f32
}

fn (a Vector2D) is_zero() bool {
	return a.x == 0 && a.y == 0
}

fn (a Vector2D) magnitude2() f32 {
	return a.x * a.x + a.y * a.y
}

fn (a Vector2D) limit_to(max_speed f32) Vector2D {
	t := f32(math.atan2(a.y, a.x))
	return Vector2D{math.cosf(t) * max_speed, math.sinf(t) * max_speed}
}

fn (a Vector2D) + (b Vector2D) Vector2D {
	return Vector2D{a.x + b.x, a.y + b.y}
}

fn (a Vector2D) - (b Vector2D) Vector2D {
	return Vector2D{a.x - b.x, a.y - b.y}
}

fn (a Vector2D) length() f32 {
	return math.sqrtf(math.powf(a.x, 2) + math.powf(a.y, 2))
}

fn (a Vector2D) divide_by(piece f32) Vector2D {
	return Vector2D{f32(a.x / piece), f32(a.y / piece)}
}

//

struct Boid {
mut:
	position     Vector2D
	velocity     Vector2D
	acceleration Vector2D
	size         f32 = 6.0
	angle        f32 = 0.0
	color        gx.Color
}

fn new_boid() Boid {
	return Boid{
		position: Vector2D{rand.f32() * (win_width - 20) + 10, rand.f32() * (win_height - 20) + 10}
		velocity: Vector2D{f32_around_zero(), f32_around_zero()}
		acceleration: Vector2D{0.02 * f32_around_zero(), 0.02 * f32_around_zero()}
		size: rand.f32() * 2 + 4
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
