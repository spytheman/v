import gg

fn test_hex() {
	// valid colors
	a := gg.hex(0x6c5ce7ff)
	b := gg.rgba(108, 92, 231, 255)
	assert a.eq(b)
	// doesn't give right value with short hex value
	short := gg.hex(0xfff)
	assert !short.eq(gg.white)
}

fn test_add() {
	a := gg.rgba(100, 100, 100, 100)
	b := gg.rgba(100, 100, 100, 100)
	r := gg.rgba(200, 200, 200, 200)
	assert (a + b).eq(r)
}

fn test_sub() {
	a := gg.rgba(100, 100, 100, 100)
	b := gg.rgba(100, 100, 100, 100)
	r := gg.rgba(0, 0, 0, 0)
	assert (a - b).eq(r)
}

fn test_mult() {
	a := gg.rgba(10, 10, 10, 10)
	b := gg.rgba(10, 10, 10, 10)
	r := gg.rgba(100, 100, 100, 100)
	assert (a * b).eq(r)
}

fn test_div() {
	a := gg.rgba(100, 100, 100, 100)
	b := gg.rgba(10, 10, 10, 10)
	r := gg.rgba(10, 10, 10, 10)
	assert (a / b).eq(r)
}

fn test_rgba8() {
	assert gg.white.rgba8() == -1
	assert gg.black.rgba8() == 255
	assert gg.red.rgba8() == -16776961
	assert gg.green.rgba8() == 16711935
	assert gg.blue.rgba8() == 65535
}

fn test_bgra8() {
	assert gg.white.bgra8() == -1
	assert gg.black.bgra8() == 255
	assert gg.red.bgra8() == 65535
	assert gg.green.bgra8() == 16711935
	assert gg.blue.bgra8() == -16776961
}

fn test_abgr8() {
	assert gg.white.abgr8() == -1
	assert gg.black.abgr8() == -16777216
	assert gg.red.abgr8() == -16776961
	assert gg.green.abgr8() == -16711936
	assert gg.blue.abgr8() == -65536
}
