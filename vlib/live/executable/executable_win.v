module executable



pub fn (r mut Reloads) load_so(soname) int {
	cpath := './$soname'
	if !isnil( r.live_lib ) {
		C.FreeLibrary( r.live_lib )
	}
	r.live_lib = voidptr( C.LoadLibraryA(cpath.str) )
	if isnil( r.live_lib ){
		println('open failed')
		exit(1);
	}
	for so_fn in r.fns {
		GetProcAddress(r.live_lib, so_fn.str)
	}
	return 1;
}
