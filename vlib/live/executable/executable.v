module executable

fn lfnmutex_print(s byteptr){
	lfm := C.live_fn_mutex
	eprintln('>> live_fn_mutex: $lfm | $s ')
}

pub fn (r mut Reloads) watch_and_reload(){
	r.check_period = 100
	mut last := os.file_last_mod_unix(r.file)
	for {
		// TODO use inotify
		now := os.file_last_mod_unix(r.file)
		if (now != last) {
			last = now;
			r.n++			
			r.reload_once()
		}
		time.sleep_ms(r.check_period)
	}
}

fn (r mut Reloads) reload_once() {
	mut new_so_base := ''
	mut new_so_name := ''
	mut compile_cmd := ''
	
	//v -o bounce -shared bounce.v
	new_so_base = '.tmp.${r.n}.${r.file_base}'
	
	$if windows {
		// We have to make this directory becuase windows WILL NOT
		// do it for us
		os.mkdir(new_so_base.all_before_last(os.PathSeparator))
	}
	
	$if msvc {
		new_so_name = '$new_so_base.dll'
	} $else {
		new_so_name = '$new_so_base.so'
	}
	
	compile_cmd := '${r.vexe} ${r.vexe_options} -o $new_so_base -shared ${r.file}'
	os.system(compile_cmd)
	
	if !os.file_exists(new_so_name) {
		eprintln('Errors while compiling $file')
		continue;
	}
	
	lfnmutex_print('reload_so locking...')
	C.pthread_mutex_lock(&live_fn_mutex)
	lfnmutex_print('reload_so locked')
	
	r.live_lib = 0; // hack: force skipping dlclose/1, the code may be still used...
	load_so(new_so_name);
	// removing the .so file from the filesystem after dlopen-ing it is safe, since it will still be mapped in memory.
	os.rm(new_so_name)
	//if(0 == rename(new_so_name, "${so_name}")){
	//	load_so("${so_name}");
	//}
	
	lfnmutex_print('reload_so unlocking...')
	C.pthread_mutex_unlock(&live_fn_mutex)
	lfnmutex_print('reload_so unlocked')			
}

