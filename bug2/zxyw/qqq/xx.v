module qqq

// pub fn iwidget(x Widget) Widget { return x }
pub interface Layout {
	get_state() voidptr
	size() (int, int)
	// on_click(ClickFn)
	unfocus_all()
	// on_mousemove(MouseMoveFn)
	draw()
	resize(w int, h int)
}
	
pub fn ilayout(x Layout) Layout {
	return x
}
											
