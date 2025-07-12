import peg { choice, e, grammar, rule, seq, some }

fn test_main_rule() {
	assert peg.match({
		':main': e('')
	}, '')? == 0

	assert peg.match({
		':main': e(1)
	}, 'a')? == 1

	assert peg.match({
		':main': rule(':fun')
		':fun':  1
	}, 'a')? == 1

	assert peg.match({
		':main':    rule(':another')
		':another': rule(':fun')
		':fun':     1
	}, 'a')? == 1

	assert peg.match({
		':main':  some(rule(':fun'))
		':fun':   choice(rule(':play'), rule(':relax'))
		':play':  '1'
		':relax': '0'
	}, '0110111001')? == 10

	grammar := grammar({
		':main': seq('(', rule(':b'), ')') // :b wrapped in ()
		':b':    seq('b', choice(rule(':a'), 0), 'b') // :a or nothing, wrapped in lowercase 'b'
		':a':    seq('a', rule(':b'), 'a') // :b wrapped in lowercase 'a'
	})
	assert peg.match(grammar, '(bb)')? == 4
	assert peg.match(grammar, '(babbab)')? == 8
	assert peg.match(grammar, '(baab)') == none
}
