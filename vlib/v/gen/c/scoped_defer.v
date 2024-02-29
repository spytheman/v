module c

import v.token

enum LeaveScopeKind {
	returns
	fn_ends
	propagates
	block_ends
	loops
	l_continues
	l_breaks
}

fn (mut g Gen) on_leave_current_scope(kind LeaveScopeKind, pos token.Pos) {
	$if trace_cgen_on_leave_scope ? {
		g.writeln('\t// ${g.scope_leaves:5} on_leave_current_scope ${kind:-13}, line_nr: ${
			pos.line_nr + 1:5}, pos: ${pos.pos:5}, ...${g.file.path#[-30..]:30}')
	}
	g.scope_leaves++
}
