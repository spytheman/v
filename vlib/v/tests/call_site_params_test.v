@[params]
struct Params {
	line string = @LINE
	file string = @FILE
	loc  string = @LOCATION
	x    int    = 123
}

@[params]
struct CallSite {
	line string = @LINE @[call_site]
	file string = @FILE @[call_site]
	loc  string = @LOCATION @[call_site]
	x    int    = 123
}

fn f(params Params) (string, string, string) {
	// dump(@LINE) dump(@FILE) dump(@LOCATION) dump(params)
	dump(@LOCATION)
	dump(params.loc)
	return params.file, params.line, params.loc
}

fn g(params CallSite) (string, string, string) {
	// dump(@LINE) dump(@FILE) dump(@LOCATION) dump(params)
	dump(@LOCATION)
	dump(params.loc)
	return params.file, params.line, params.loc
}

fn test_params() {
	dump(@LOCATION)
	f()
	f(x: 456)
	f()
	//
	g()
	g(x: 456)
	g()
}
