module sharedlib

struct Reloads {
	load_fns_cb    fn()
	// A pointer to the C function that will actually call dlsym/GetProcAddress
	live_mutex_ptr voidptr   // A pointer to the global reloader mutex.
	fns []string             // The functions for which the reloader should call
                             // dlsym/GetProcAddress
	////////////////////////////////////////////////////////////////////////////
mut:
	live_lib voidptr         // Used to store the result of dlopen/LoadLibraryA .
	////////////////////////////////////////////////////////////////////////////
pub:	
	source_file string       // Source file that should be monitored for changes.
	source_file_base string  // The name of the source file without the .v extension.
	vexe string              // The absolute path to the v executable that
                             // should be used for recompiling.
	vexe_options string      // The executable options to be passed to the v executable
	////////////////////////////////////////////////////////////////////////////
	n int                    // How many reloads were done so far.
	check_period int         // How often to check for source changes.
}
