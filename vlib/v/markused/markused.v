// Copyright (c) 2019-2024 Alexander Medvednikov. All rights reserved.
// Use of this source code is governed by an MIT license that can be found in the LICENSE file.
module markused

import v.ast
import v.util
import v.pref

// mark_used walks the AST, starting at main() and marks all used fns transitively
pub fn mark_used(mut table ast.Table, mut pref_ pref.Preferences, ast_files []&ast.File, stage_label string) {
	mut all_fns, all_consts, all_globals := all_fn_const_and_global(ast_files)
	util.timing_start(stage_label)
	defer {
		util.timing_measure(stage_label)
	}
	mut all_fn_root_names := []string{}
	all_fn_root_names << 'main.main'
	all_fn_root_names << table.backend_used.fns.keys()
	//	all_fn_root_names << 'init_global_allocator'
	//	all_fn_root_names << 'builtin_init'
	for k, mut mfn in all_fns {
		// public/exported functions can not be skipped,
		// especially when producing a shared library:
		if mfn.is_pub && pref_.is_shared {
			all_fn_root_names << k
			continue
		}
		if pref_.prealloc && k.starts_with('prealloc_') {
			all_fn_root_names << k
			continue
		}
	}

	// handle interface implementation methods:
	for isym in table.type_symbols {
		if isym.kind != .interface {
			continue
		}
		if isym.info !is ast.Interface {
			// Do not remove this check, isym.info could be &IError.
			continue
		}
		interface_info := isym.info as ast.Interface
		if interface_info.methods.len == 0 {
			continue
		}
		for itype in interface_info.types {
			ptype := itype.set_nr_muls(1)
			ntype := itype.set_nr_muls(0)
			interface_types := [ptype, ntype]
			for method in interface_info.methods {
				for typ in interface_types {
					interface_implementation_method_name := '${int(typ)}.${method.name}'
					$if trace_skip_unused_interface_methods ? {
						eprintln('>> isym.name: ${isym.name} | interface_implementation_method_name: ${interface_implementation_method_name}')
					}
					all_fn_root_names << interface_implementation_method_name
				}
			}
		}
	}

	mut walker := Walker.new(
		table:       table
		files:       ast_files
		all_fns:     all_fns
		all_consts:  all_consts
		all_globals: all_globals
		pref:        pref_
	)
	walker.mark_markused_fn_decls() // tagged with `@[markused]`
	walker.mark_markused_consts() // tagged with `@[markused]`
	walker.mark_markused_globals() // tagged with `@[markused]`
	walker.mark_exported_fns()
	walker.mark_veb_actions()
	walker.mark_root_fns(all_fn_root_names)

	$if trace_skip_unused_fn_names ? {
		for key, _ in walker.used_fns {
			println('> used fn key: ${key}')
		}
	}

	for kcon, con in all_consts {
		if pref_.is_shared && con.is_pub {
			walker.mark_const_as_used(kcon)
		}
		if !pref_.is_shared && con.is_pub && con.name.starts_with('main.') {
			walker.mark_const_as_used(kcon)
		}
	}

	table.used_features.used_fns = walker.used_fns.move()
	table.used_features.used_consts = walker.used_consts.move()
	table.used_features.used_globals = walker.used_globals.move()

	$if trace_skip_unused ? {
		eprintln('>> t.used_fns: ${table.used_features.used_fns.keys()}')
		eprintln('>> t.used_consts: ${table.used_features.used_consts.keys()}')
		eprintln('>> t.used_globals: ${table.used_features.used_globals.keys()}')
		eprintln('>> walker.table.used_features.used_maps: ${walker.table.used_features.used_maps}')
	}
}

fn all_fn_const_and_global(ast_files []&ast.File) (map[string]ast.FnDecl, map[string]ast.ConstField, map[string]ast.GlobalField) {
	util.timing_start(@METHOD)
	defer {
		util.timing_measure(@METHOD)
	}
	mut all_fns := map[string]ast.FnDecl{}
	mut all_consts := map[string]ast.ConstField{}
	mut all_globals := map[string]ast.GlobalField{}
	for i in 0 .. ast_files.len {
		file := ast_files[i]
		for node in file.stmts {
			match node {
				ast.FnDecl {
					fkey := node.fkey()
					all_fns[fkey] = node
				}
				ast.ConstDecl {
					for cfield in node.fields {
						ckey := cfield.name
						all_consts[ckey] = cfield
					}
				}
				ast.GlobalDecl {
					for gfield in node.fields {
						gkey := gfield.name
						all_globals[gkey] = gfield
					}
				}
				else {}
			}
		}
	}
	return all_fns, all_consts, all_globals
}

fn mark_all_methods_used(mut table ast.Table, mut all_fn_root_names []string, typ ast.Type) {
	sym := table.sym(typ)
	for method in sym.methods {
		all_fn_root_names << '${int(typ)}.${method.name}'
	}
}

fn handle_vweb(mut table ast.Table, mut all_fn_root_names []string, result_name string, filter_name string,
	context_name string) {
	// handle vweb magic router methods:
	result_type_idx := table.find_type(result_name)
	if result_type_idx != 0 {
		all_fn_root_names << filter_name
		typ_vweb_context := table.find_type(context_name).set_nr_muls(1)
		mark_all_methods_used(mut table, mut all_fn_root_names, typ_vweb_context)
		for vgt in table.used_features.used_veb_types {
			sym_app := table.sym(vgt)
			for m in sym_app.methods {
				mut skip := true
				if m.name == 'before_request' {
					// TODO: handle expansion of method calls in generic functions in a more universal way
					skip = false
				}
				if m.return_type == result_type_idx {
					skip = false
				}
				if skip {
					continue
				}
				pvgt := vgt.set_nr_muls(1)
				// eprintln('vgt: $vgt | pvgt: $pvgt | sym_app.name: $sym_app.name | m.name: $m.name')
				all_fn_root_names << '${int(pvgt)}.${m.name}'
			}
		}
	}
}
