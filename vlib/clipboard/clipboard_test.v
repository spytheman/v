import clipboard

fn run_test(is_primary bool) {
	eprintln('${@FN} is_primary: $is_primary start')
	defer {
		eprintln('${@FN} is_primary: $is_primary done')
	}
	mut cb := if is_primary { clipboard.new_primary() } else { clipboard.new() }
	if !cb.is_available() {
		eprintln('cb is not available')
		return
	}
	eprintln(@LINE)
	assert cb.check_ownership() == false
	eprintln(@LINE)
	assert cb.copy('I am a good boy!') == true
	eprintln(@LINE)
	// assert cb.check_ownership() == true TODO
	assert cb.paste() == 'I am a good boy!'
	eprintln(@LINE)
	cb.clear_all()
	eprintln(@LINE)
	assert cb.paste().len <= 0
	eprintln(@LINE)
	cb.destroy()
	eprintln(@LINE)
}

fn test_primary() {
	run_test(true)
}

fn test_clipboard() {
	run_test(false)
}
