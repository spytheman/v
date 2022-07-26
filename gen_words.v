import v.token

fn main() {
	println('= -1')
	for k, v in token.keywords {
		println('$k = ${int(v)}')
	}
}
