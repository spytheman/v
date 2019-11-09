module builtin

#include <dbghelp.h>
#flag windows -l dbghelp

pub struct SymbolInfo {
	pub mut:
	f_size_of_struct     u32
	f_type_index         u32      // Type Index of symbol
	f_reserved           [2]u64
	f_index              u32
	f_size               u32
	f_mod_base           u64      // Base Address of module comtaining this symbol
	f_flags              u32
	f_value              u64      // Value of symbol, ValuePresent should be 1
	f_address            u64         // Address of symbol including base address of module
	f_register           u32      // register holding value or pointer to value
	f_scope              u32      // scope of the symbol
	f_tag                u32      // pdb classification
	f_name_len           u32      // Actual length of name
	f_max_name_len       u32
	f_name               byte
}

pub struct SymbolInfoContainer {
	pub mut:
	syminfo SymbolInfo
	f_name_rest [254]char
}

fn C.SymSetOptions(symoptions u32) u32 // returns the current options mask
fn C.GetCurrentProcess() voidptr // returns handle
fn C.SymInitialize(h_process voidptr, p_user_search_path byteptr, b_invade_process int) int
fn C.CaptureStackBackTrace(frames_to_skip u32, frames_to_capture u32, p_backtrace voidptr, p_backtrace_hash voidptr) u16
fn C.SymFromAddr(h_process voidptr, address u64, p_displacement voidptr, p_symbol voidptr) int

const (
	SYMOPT_DEBUG = 0x80000000
	SYMOPT_UNDNAME = 0x00000002
	SYMOPT_LOAD_LINES = 0x00000010
)

fn print_backtrace_skipping_top_frames_msvc(skipframes int){
	println('print_backtrace_skipping_top_frames_msvc $skipframes')
	handle := C.GetCurrentProcess()
	options := C.SymSetOptions(SYMOPT_DEBUG | SYMOPT_LOAD_LINES | SYMOPT_UNDNAME)	
	syminitok := C.SymInitialize( handle, 0, 1)
	if syminitok != 1 {
		println('Failed getting process: Aborting backtrace.\n')
		return
	}
	mut sic := SymbolInfoContainer{} 
	mut si := &sic.syminfo
	si.f_size_of_struct = sizeof(SymbolInfo)  // Note: C.SYMBOL_INFO is 88
	si.f_max_name_len = sizeof(SymbolInfoContainer) - sizeof(SymbolInfo) - 1
	fname := *char( &si.f_name )

	backtraces := [100]voidptr
	frames := int( C.CaptureStackBackTrace(skipframes + 1, 100, backtraces, 0) )
	for i:=0; i < frames; i++ {
		// fugly pointer arithmetics follows ...
		s := *voidptr( u64(backtraces) + u64(i*sizeof(voidptr)) )
		symfa_ok := C.SymFromAddr( handle, *s, 0, si )
		if (symfa_ok == 1) {
			println('NameLen: ${si.f_name_len:3d} | ' + tos3(fname) )
		} else {
			// https://docs.microsoft.com/en-us/windows/win32/debug/system-error-codes
			cerr := int(C.GetLastError())
			println('   SymFromAddr failure: $cerr (Note: 87 = The parameter is incorrect)')  // 87 = The parameter is incorrect.
		} 
	}
	C.SymCleanup(handle)
}

fn print_backtrace_skipping_top_frames_mingw(skipframes int){
	println('TODO: print_backtrace_skipping_top_frames_mingw $skipframes')
}

