// Copyright (c) 2019 Alexander Medvednikov. All rights reserved.
// Use of this source code is governed by an MIT license
// that can be found in the LICENSE file.

module compiler

import os
import filepath

pub const (
	v_modules_path = os.home_dir() + '.vmodules'
)

// Holds import information scoped to the parsed file
struct ImportTable {
mut:
	imports        map[string]string // alias => module
	used_imports   []string          // alias
	import_tok_idx map[string]int    // module => idx
}

// Once we have a module format we can read from module file instead
// this is not optimal
fn (table &Table) qualify_module(mod string, file_path string) string {
	for m in table.imports {
		if m.contains('.') && m.contains(mod) {
			m_parts := m.split('.')
			m_path := m_parts.join(os.path_separator)
			if mod == m_parts[m_parts.len-1] && file_path.contains(m_path) {
				return m
			}
		}
	}
	return mod
}

fn new_import_table() ImportTable {
	return ImportTable{
		imports:   map[string]string
	}
}

fn (p mut Parser) register_import(mod string, tok_idx int) {
	p.register_import_alias(mod, mod, tok_idx)
}

fn (p mut Parser) register_import_alias(alias string, mod string, tok_idx int) {
	// NOTE: come back here
	// if alias in it.imports && it.imports[alias] == mod {}
	if alias in p.import_table.imports && p.import_table.imports[alias] != mod {
		p.error('cannot import $mod as $alias: import name $alias already in use')
	}
	if mod.contains('.internal.') {
		mod_parts := mod.split('.')
		mut internal_mod_parts := []string
		for part in mod_parts {
			if part == 'internal' { break }
			internal_mod_parts << part
		}
		internal_parent := internal_mod_parts.join('.')
		if !p.mod.starts_with(internal_parent) {
			p.error('module $mod can only be imported internally by libs')
		}
	}
	p.import_table.imports[alias] = mod
	p.import_table.import_tok_idx[mod] = tok_idx
}

fn (it &ImportTable) get_import_tok_idx(mod string) int {
	return it.import_tok_idx[mod]
}

fn (it &ImportTable) known_import(mod string) bool {
	return mod in it.imports || it.is_aliased(mod)
}

fn (it &ImportTable) known_alias(alias string) bool {
	return alias in it.imports
}

fn (it &ImportTable) is_aliased(mod string) bool {
	for _, val in it.imports {
		if val == mod {
			return true
		}
	}
	return false
}

fn (it &ImportTable) resolve_alias(alias string) string {
	return it.imports[alias]
}

fn (it mut ImportTable) register_used_import(alias string) {
	if !(alias in it.used_imports) {
		it.used_imports << alias
	}
}

fn (it &ImportTable) is_used_import(alias string) bool {
	return alias in it.used_imports
}

// should module be accessable
pub fn (p &Parser) is_mod_in_scope(mod string) bool {
	mut mods_in_scope := ['', 'builtin', 'main', p.mod]
	for _, m in p.import_table.imports {
		mods_in_scope << m
	}
	return mod in mods_in_scope
}

// return resolved dep graph (order deps)
pub fn (v &V) resolve_deps() &DepGraph {
	graph := v.import_graph()
	deps_resolved := graph.resolve()
	if !deps_resolved.acyclic {
		verror('import cycle detected between the following modules: \n' + deps_resolved.display_cycles())
	}
	return deps_resolved
}

// graph of all imported modules
pub fn(v &V) import_graph() &DepGraph {
	mut graph := new_dep_graph()
	for p in v.parsers {
		mut deps := []string
		for _, m in p.import_table.imports {
			deps << m
		}
		graph.add(p.mod, deps)
	}
	return graph
}

// get ordered imports (module speficic dag method)
pub fn(graph &DepGraph) imports() []string {
	mut mods := []string
	for node in graph.nodes {
		mods << node.name
	}
	return mods
}

[inline] fn (v &V) module_path(mod string) string {
	// submodule support
	return mod.replace('.', os.path_separator)
}

// 'strings' => 'VROOT/vlib/strings'
// 'installed_mod' => '~/.vmodules/installed_mod'
// 'local_mod' => '/path/to/current/dir/local_mod'
fn (v &V) find_module_path(mod string) ?string {
	// Module search order:
	// 1) search in the *same* directory, as the compiled final target (i.e. `.` or `file.v`)
	// 2) search in the current work dir (this preserves existing behaviour)
	// 3) search in vlib/
	// 4) search in ~/.vmodules/ (i.e. modules installed with vpm)
	mod_path := v.module_path(mod)
	mut tried_paths := []string
	tried_paths << filepath.join(v.compiled_dir, mod_path)
	tried_paths << filepath.join(os.getwd(), mod_path)
	tried_paths << filepath.join(v.lang_dir, 'vlib', mod_path)
	tried_paths << filepath.join(v_modules_path, mod_path)
	for try_path in tried_paths {
		if v.pref.is_verbose { println('  >> trying to find $mod in $try_path ...') }
		if os.dir_exists(try_path) { 
			return try_path 
		}
	}
	return error('module "$mod" not found')
}

[inline] fn mod_gen_name(mod string) string {
	return mod.replace('.', '_dot_')
}

[inline] fn mod_gen_name_rev(mod string) string {
	return mod.replace('_dot_', '.')
}
