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
	for mod in args {
		table := table.new_table()
		println(doc.doc(mod, table))
	}
}
