module executable

pub fn (r mut Reloads) v_load_so(soname string) {
	cpath := './$soname'
	if !isnil( r.live_lib ) {
		C.FreeLibrary( r.live_lib )
	}
	r.live_lib = voidptr( C.LoadLibraryA(cpath.str) )
	if isnil( r.live_lib ){
		println('open failed')
		exit(1);
	}
	r.callback( r.load_fns_cb )
}
