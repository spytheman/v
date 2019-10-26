module compiler

import os
import time

fn (v &V) generate_hotcode_reloading_preambule_files() []string {
	mut live_files := []string		
	if v.pref.is_live {
		live_files << v.vlib(['live', 'executable_preambule.v'])
	}
	if v.pref.is_live_so {
		live_files << v.vlib(['live', 'sharedlib_preambule.v'])
	}	
	println('including live preambule files: $live_files')
	return live_files
}


fn (v &V) generate_hotcode_reloading_compiler_flags() []string {
	mut a := []string
	if v.pref.is_live || v.pref.is_so {
		// See 'man dlopen', and test running a GUI program compiled with -live
		if (v.os == .linux || os.user_os() == 'linux'){
			a << '-rdynamic'
		}
		if (v.os == .mac || os.user_os() == 'mac'){
			a << '-flat_namespace'
		}
	}
	return a
}


fn (v &V) generate_hotcode_reloading_declarations() {
	mut cgen := v.cgen
	cgen.genln('')
	cgen.genln('// live reloading declarations start:')
	if v.os == .windows {
		if v.pref.is_live {
			cgen.genln('HANDLE live_fn_mutex = 0;')
		}
		if v.pref.is_live_so {
			cgen.genln('HANDLE live_fn_mutex;')
		}
	} else {
		if v.pref.is_live {
			cgen.genln('pthread_mutex_t live_fn_mutex = PTHREAD_MUTEX_INITIALIZER;')
		}
		if v.pref.is_live_so {
			cgen.genln('pthread_mutex_t live_fn_mutex;')
		}
	}
	if v.pref.is_live && v.os == .windows {	
		cgen.genln('void live_load_all_function_symbols(void);')
		cgen.genln('void pthread_mutex_lock(HANDLE *m);')
		cgen.genln('void pthread_mutex_unlock(HANDLE *m);')
	}
	
	cgen.genln('// live reloading declarations end.')
	cgen.genln('')	
}


fn (v &V) generate_hotcode_reloading_main_caller() {
	if !v.pref.is_live { return }
	mut cgen := v.cgen	
	cgen.genln('')	
	mut file := os.realpath(v.dir)
	file_base := os.filename(v.dir).replace('.v', '')
	
	mut so_name := file_base + '.so'
	if v.os == .windows && v.pref.ccompiler == 'msvc' {
		so_name := file_base + '.dll'
	}	
	
	mut vexe := vexe_path()	
	if os.user_os() == 'windows' {
		vexe = cescaped_path(vexe)
		file = cescaped_path(file)
	}
	mut msvc := ''
	if v.pref.ccompiler == 'msvc' {
		msvc = '-cc msvc'
	}	
	so_debug_flag := if v.pref.is_debug { '-g' } else { '' }	
	vexe_options := cescaped_quotes('$msvc $so_debug_flag')
	///////////////////////////////////////////////////////////////////	
	reloader := 'live_dot_executable__shared_lib_reloader_info'
	cgen.genln('  ${reloader}.source_file  = tos2("$file"); ')
	cgen.genln('  ${reloader}.check_period = 100; ')
	cgen.genln('  ${reloader}.vexe         = tos2("$vexe"); ')
	cgen.genln('  ${reloader}.vexe_options = tos2("$vexe_options"); ')
	cgen.genln('  ${reloader}.live_mutex_ptr = &live_fn_mutex; ')
	cgen.genln('  ${reloader}.load_fns_cb    = live_load_all_function_symbols; ')
	for i, so_fn in cgen.so_fns {
		fi := i + 99999
		cgen.genln('  _PUSH(& ${reloader}.fns , ( /*typ = array_string   tmp_typ=string*/ tos3("$so_fn") ), tmp${fi}, string) ; ')
	}
	// We are in live code reload mode, so start the .so loader in the background
	cgen.genln('  live_dot_executable__start_reloading_thread(); ')
	cgen.genln('')

	if(false){
	///////////////////////////////////////////////////////////////////	
	if v.os == .windows {
		// windows:
		cgen.genln('  char *live_library_name = "$so_name";')
		cgen.genln('  live_fn_mutex = CreateMutexA(0, 0, 0);')
		cgen.genln('  load_so(live_library_name);')
		cgen.genln('  unsigned long _thread_so;')
		cgen.genln('  _thread_so = CreateThread(0, 0, (LPTHREAD_START_ROUTINE)&reload_so, 0, 0, 0);')
	} else {
		// unix:
		cgen.genln('  char *live_library_name = "$so_name";')
		cgen.genln('  load_so(live_library_name);')
		cgen.genln('  pthread_t _thread_so;')
		cgen.genln('  pthread_create(&_thread_so , NULL, &reload_so, live_library_name);')
	}
	}
}

fn (v &V) generate_hot_reload_code() {
	mut cgen := v.cgen
	
	// Hot code reloading
	if v.pref.is_live {
		mut file := os.realpath(v.dir)
		file_base := os.filename(file).replace('.v', '')
		so_name := file_base + '.so'
		// Need to build .so file before building the live application
		// The live app needs to load this .so file on initialization.
		mut vexe := os.args[0]
		
		if os.user_os() == 'windows' {
			vexe = cescaped_path(vexe)
			file = cescaped_path(file)
		}
		
		mut msvc := ''
		if v.pref.ccompiler == 'msvc' {
			msvc = '-cc msvc'
		}
		
		so_debug_flag := if v.pref.is_debug { '-g' } else { '' }		
		cmd_compile_shared_library := '$vexe $msvc $so_debug_flag -o $file_base -shared -live_so $file'
		if v.pref.show_c_cmd {
			println(cmd_compile_shared_library)
		}
		ticks := time.ticks()
		os.system(cmd_compile_shared_library)
		diff := time.ticks() - ticks
		println('compiling shared library took $diff ms')
		println('=========\n')

		cgen.genln('void live_load_all_function_symbols(void){')
		for so_fn in cgen.so_fns {
			if v.os != .windows {
				cgen.genln('$so_fn = dlsym(live_dot_executable__shared_lib_reloader_info.live_lib, "$so_fn");  ')
			}else{
				cgen.genln('$so_fn = (voidptr*)GetProcAddress(live_dot_executable__shared_lib_reloader_info.live_lib, "$so_fn");  ')
			}			
		}
		cgen.genln('}')
		
		if v.os == .windows {
			cgen.genln('
                void pthread_mutex_lock(HANDLE *m) {
                    WaitForSingleObject(*m, INFINITE);
                }

                void pthread_mutex_unlock(HANDLE *m) {
                    ReleaseMutex(*m);
                }

            ')
		}
		
		cgen.genln('
void lfnmutex_print(char *s){
	if(0){
		fflush(stderr);
		fprintf(stderr,">> live_fn_mutex: %p | %s\\n", &live_fn_mutex, s);
		fflush(stderr);
	}
}
')

		if v.os != .windows {
			cgen.genln('
#include <dlfcn.h>
void* live_lib=0;
int load_so(byteptr path) {
	char cpath[1024];
	sprintf(cpath,"./%s", path);
	//printf("load_so %s\\n", cpath);
	if (live_lib) dlclose(live_lib);
	live_lib = dlopen(cpath, RTLD_LAZY);
	if (!live_lib) {
		puts("open failed");
		exit(1);
		return 0;
	}
')
			for so_fn in cgen.so_fns {
				cgen.genln('$so_fn = dlsym(live_lib, "$so_fn");  ')
			}
		}
		else {
			cgen.genln('

void* live_lib=0;
int load_so(byteptr path) {
	char cpath[1024];
	sprintf(cpath, "./%s", path);
	if (live_lib) FreeLibrary(live_lib);
	live_lib = LoadLibraryA(cpath);
	if (!live_lib) {
		puts("open failed");
		exit(1);
		return 0;
	}
')

			for so_fn in cgen.so_fns {
				cgen.genln('$so_fn = (void *)GetProcAddress(live_lib, "$so_fn");  ')
			}
		}

		mut c_code_before_reload_mutex_unlocking := ''
		mut c_code_after_reload_mutex_unlocking  := ''
		
		cgen.genln('return 1;')
		cgen.genln('
}
')

		
		cgen.genln('
int _live_reloads = 0;
void reload_so() {
	char new_so_base[1024];
	char new_so_name[1024];
	char compile_cmd[1024];
	int last = os__file_last_mod_unix(tos2("$file"));
	while (1) {
		// TODO use inotify
		int now = os__file_last_mod_unix(tos2("$file"));
		if (now != last) {
			last = now;
			_live_reloads++;

			//v -o bounce -shared bounce.v
			sprintf(new_so_base, ".tmp.%d.${file_base}", _live_reloads);
			#ifdef _WIN32
			// We have to make this directory becuase windows WILL NOT
			// do it for us
			os__mkdir(string_all_before_last(tos2(new_so_base), tos2("/")));
			#endif
			#ifdef _MSC_VER
			sprintf(new_so_name, "%s.dll", new_so_base);
			#else
			sprintf(new_so_name, "%s.so", new_so_base);
			#endif
			sprintf(compile_cmd, "$vexe $msvc -o %s -shared -live_so $file", new_so_base);
			os__system(tos2(compile_cmd));

			if( !os__file_exists(tos2(new_so_name)) ) {
				fprintf(stderr, "Errors while compiling $file\\n");
				continue;
			}

			lfnmutex_print("reload_so locking...");
			pthread_mutex_lock(&live_fn_mutex);
			lfnmutex_print("reload_so locked");

			live_lib = 0; // hack: force skipping dlclose/1, the code may be still used...
			load_so(new_so_name);
			#ifndef _WIN32
			unlink(new_so_name); // removing the .so file from the filesystem after dlopen-ing it is safe, since it will still be mapped in memory.
			#else
			_unlink(new_so_name);
			#endif
			//if(0 == rename(new_so_name, "${so_name}")){
			//	load_so("${so_name}");
			//}

			$c_code_before_reload_mutex_unlocking

			lfnmutex_print("reload_so unlocking...");
			pthread_mutex_unlock(&live_fn_mutex);
			lfnmutex_print("reload_so unlocked");

			$c_code_after_reload_mutex_unlocking

		}
		time__sleep_ms(100);
	}
}
' )
	}

	if v.pref.is_so {
		cgen.genln(' int load_so(byteptr path) { return 0; }')
	}
}
