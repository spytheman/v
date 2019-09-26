module executable

#include <dlfcn.h>

pub fn (r mut Reloads) load_so(soname) int {
	cpath := './$soname'
	if !isnil( r.live_lib ) {
		C.dlclose( r.live_lib )
	}
	r.live_lib = voidptr( C.dlopen(cpath.str, C.RTLD_LAZY) )
	if isnil( r.live_lib ){
		println('open failed')
		exit(1);
	}
	for so_fn in r.fns {
		C.dlsym( r.live_lib, so_fn.str )
	}
	return 1;
}
