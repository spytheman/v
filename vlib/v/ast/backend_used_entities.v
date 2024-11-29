module ast

pub struct BackendUsedEntities {
pub mut:
	fns     map[string]int
	types   map[string]int
	consts  map[string]int
	globals map[string]int
}

pub fn (mut u BackendUsedEntities) merge(source BackendUsedEntities) {
	for k, v in source.fns {
		u.fns[k] += v
	}
	for k, v in source.types {
		u.types[k] += v
	}
	for k, v in source.consts {
		u.consts[k] += v
	}
	for k, v in source.globals {
		u.globals[k] += v
	}
}
