module gg

import gx

pub const white = gx.white

pub const blue = gx.blue

pub const black = gx.black

const old_context = &Context(0)

[unsafe]
fn ctx(p &Context) &Context {
	mut static context := &Context(0)
	if p != 0 {
		context = p
	}
	return context
}

[unsafe]
fn cfg(p &Config) &Config {
	mut static c := &Config(0)
	if p != 0 {
		unsafe {
			c = &Config{}
			vmemcpy(c, p, int(sizeof(Config)))
		}
	}
	return c
}

//

pub fn set_context_config(c Config) {
	unsafe {
		cfg(&c)
	}
}

pub type FnAfterContext = fn (app voidptr)

pub fn run(app voidptr, cb FnAfterContext) {
	config := *(unsafe { cfg(&Config(0)) })
	mut c := new_context(Config{ ...config, user_data: app })
	unsafe { ctx(c) }
	cb(app)
	c.run()
}

pub fn new_image(file string) Image {
	mut c := unsafe { ctx(gg.old_context) }
	return c.create_image(file)
}

[inline]
pub fn begin() {
	unsafe { ctx(gg.old_context).begin() }
}

[inline]
pub fn end() {
	unsafe { ctx(gg.old_context).end() }
}

[inline]
pub fn draw_rect(x f32, y f32, w f32, h f32, c gx.Color) {
	unsafe { ctx(gg.old_context).draw_rect(x, y, w, h, c) }
}

[inline]
pub fn draw_empty_rect(x f32, y f32, w f32, h f32, c gx.Color) {
	unsafe { ctx(gg.old_context).draw_empty_rect(x, y, w, h, c) }
}

[inline]
pub fn draw_image(x f32, y f32, width f32, height f32, img_ &Image) {
	unsafe { ctx(gg.old_context).draw_image(x, y, width, height, img_) }
}
