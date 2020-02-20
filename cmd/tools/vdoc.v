// Copyright (c) 2019-2020 Alexander Medvednikov. All rights reserved.
// Use of this source code is governed by an MIT license
// that can be found in the LICENSE file.
module main

import (
	os
	os.cmdline
	v.table
	v.doc
)

fn main(){
	args := cmdline.options_after(os.args, ['doc'])
	if args.len != 1 {
		usage()
		exit(0)
	}
	mod := args[0]
	table := table.new_table()
	println(doc.doc(mod, table))
}

fn usage(){
	print('Usage: 
a) v doc <module>
   Show documentation for the given module.

b) [wip] v doc
   Show documentation for current module (the one in the working folder).

c) [wip] v doc <ModuleName> <SymbolName>
   Show documentation *only* for the specific SymbolName from module ModuleName. 
   SymbolName is a module top level entity like a function, a const, an enum, a struct, a type and so on.
')
}
