@[params]
struct Params {
	line string = @LINE
	file string = @FILE
	lc   string = @LOCATION
	x    int    = 123
}

@[params]
struct CallSite {
	line string = @LINE @[call_site]
	file string = @FILE @[call_site]
	lc   string = @LOCATION @[call_site]
	x    int    = 123
}

fn f(params Params) (string, string, string) {
	// dump(@LINE) dump(@FILE) dump(@LOCATION) dump(params)
	dump(@LOCATION)
	dump(params.lc)
	return params.file, params.line, params.lc
}

fn g(params CallSite) (string, string, string) {
	// dump(@LINE) dump(@FILE) dump(@LOCATION) dump(params)
	dump(@LOCATION)
	dump(params.lc)
	return params.file, params.line, params.lc
}

fn test_params() {
	dump(@LOCATION)
	eprintln('/////////////////////////////////////////////')
	f()
	f(x: 456)
	f()
	eprintln('/////////////////////////////////////////////')
	g()
	g(x: 456)
	g()
}
