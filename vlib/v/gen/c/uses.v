module c

fn (mut g Gen) fuse(name string) {
	g.used_entities.fns[name] = 1
}

fn (mut g Gen) tuse(name string) {
	g.used_entities.types[name] = 1
}

fn (mut g Gen) cuse(name string) {
	g.used_entities.consts[name] = 1
}

fn (mut g Gen) guse(name string) {
	g.used_entities.globals[name] = 1
}

fn (mut g Gen) finalise_usage() {
	// g.report_used_kind('used_fns', g.used_entities.fns)
	//	g.report_used_kind('used_types', g.used_entities.types)
	// g.report_used_kind('used_consts', g.used_entities.consts)
	// g.report_used_kind('used_globals', g.used_entities.globals)
	g.table.backend_used = g.used_entities
}

fn (mut g Gen) report_used_kind(label string, m map[string]int) {
	if m.len > 0 {
		println('> cgen ${label}: ${m.keys()}')
	}
}
