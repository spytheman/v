module live

struct Reloads {
mut:
	check_period int
	n int
	vexe string
	vexe_options string
	file string
	file_base string
	live_lib voidptr
	fns []string
}
