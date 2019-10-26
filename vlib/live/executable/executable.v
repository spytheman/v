module executable

// Put here stuff that will be defined and loaded only in the main executable, and NOT in the shared library.

import os
import time

const (
	shared_lib_reloader_info = Reloads{}
)

fn start_reloading_thread() {
	println('Starting live reload monitoring thread...')

	/*
	live_fn_mutex_ptr = &live_fn_mutex;
	char *live_library_name = "message.so";
	load_so(live_library_name);
	pthread_t _thread_so;
	pthread_create(&_thread_so , NULL, &reload_so, live_library_name);
	*/	
}

pub fn version() string { return '0.0.1' }

pub fn (r mut Reloads) watch_and_reload(){
	r.check_period = 100
	mut last := os.file_last_mod_unix(r.source_file)
	for {
		// TODO use inotify
		now := os.file_last_mod_unix(r.source_file)
		if (now != last) {
			last = now
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
	new_so_base = '.tmp.${r.n}.${r.source_file_base}'
	
	//  if windows {
	//		// We have to make this directory becuase windows WILL NOT do it for us
	//		os.mkdir(new_so_base.all_before_last(os.PathSeparator))
	//	}
	
	//	$if msvc {
	//		new_so_name = '$new_so_base.dll'
	//	} $else {
	//		new_so_name = '$new_so_base.so'
	//	}
	
	compile_cmd = '${r.vexe} ${r.vexe_options} -o $new_so_base -shared -shared_live ${r.source_file}'
	os.system(compile_cmd)
	
	if !os.file_exists(new_so_name) {
		eprintln('Errors while compiling ${r.source_file}')
		return
	}
	
	r.log('reload_so locking...')
	C.pthread_mutex_lock(r.live_mutex_ptr)
	r.log('reload_so locked')
	
	r.live_lib = 0         // hack: force skipping dlclose/1, the code may be still used...
	r.v_load_so(new_so_name)
	// removing the .so file from the filesystem after dlopen-ing it is safe, since it will still be mapped in memory.
	os.rm(new_so_name)
	//if(0 == rename(new_so_name, "${so_name}")){
	//	load_so("${so_name}")
	//}
	
	r.log('reload_so unlocking...')
	C.pthread_mutex_unlock(r.live_mutex_ptr)
	r.log('reload_so unlocked')			
}

fn (r mut Reloads) log(msg string){
	eprintln('>> live_fn_mutex: ' + ptr_str(r.live_mutex_ptr) + ' | ${msg} ')
}

pub fn (r mut Reloads) callback( cbfunc fn() ){
	println('r.Reloads callback to ' + ptr_str(cbfunc))
	cbfunc()
}
