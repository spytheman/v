module builtin

pub fn dump_implementation[T](path string, line int, sexpr string, expr T) T {
	eprint('[')
	eprint(path)
	eprint(':')
	eprint(line)
	eprint('] ')
	eprint(sexpr)
	eprint(': ')
	//	eprintln(expr)
	eprintln(typeof(expr).name)
	return expr
}
