import v.token

fn main() {
	// println('%{')
	// println('%}')
	println('struct GPerfResult')
	println('  {')
	println('  const char* name;')
	println('  int code;')
	println('  };')
	println('%%')
	for k, v in token.keywords {
		println('$k, ${int(v)}')
	}
	println('%%')
}
