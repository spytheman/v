module builtin

#include <dbghelp.h>
#flag windows -l dbghelp

pub struct SymbolInfo {
pub mut:
	f_size_of_struct     u32
	f_type_index         u32      // Type Index of symbol
	f_reserved           voidptr
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
	f_name               byteptr     // CHAR[] Name of symbol
}

fn C.SymSetOptions(u32) u32
fn C.GetCurrentProcess() voidptr

const (
	SYMOPT_DEBUG = 0x80000000
	SYMOPT_UNDNAME = 0x00000002
	SYMOPT_LOAD_LINES = 0x00000010
)

fn print_backtrace_skipping_top_frames_msvc(skipframes int){
	println('print_backtrace_skipping_top_frames_msvc $skipframes')
	print_backtrace_skipping_top_frames_win(skipframes)
}

fn print_backtrace_skipping_top_frames_mingw(skipframes int){
	println('print_backtrace_skipping_top_frames_mingw $skipframes')
	print_backtrace_skipping_top_frames_win(skipframes)
}



fn print_backtrace_skipping_top_frames_win(skipframes int){
	stack := [100]byteptr
	//		stack := [100]u64
	handle := C.GetCurrentProcess()
	println( 'HANDLE: $handle')

	//options := C.SymSetOptions(C.SYMOPT_DEBUG | C.SYMOPT_LOAD_LINES | C.SYMOPT_UNDNAME | C.SYMOPT_ALLOW_ZERO_ADDRESS | C.SYMOPT_CASE_INSENSITIVE)
	options := C.SymSetOptions(SYMOPT_DEBUG | SYMOPT_LOAD_LINES | SYMOPT_UNDNAME)
	println('options= ${options}')

	//		mut success := C.SymInitialize(handle, C.NULL, 1)
	mut success := C.SymInitialize(C.GetCurrentProcess(), 0, 1)
	println('SymInitialize Success= ${int(success)} handle= ${handle} = ${C.GetCurrentProcess()}')

	if (success != 1) {
		println('Failed getting process: Aborting backtrace.\n')
		return
	}

	frames := C.CaptureStackBackTrace(0, 100, stack, 0)
	println('Nb frames= ${int(frames)}')

	println('Sizes of Symbol_Info= ${sizeof(SymbolInfo)}  string= ${sizeof(string)}')

	for i:=0; i < frames; i++
	{
		println(' Stack[ ${i.str()} ] = "${u64(stack[i])}"')

		mut symbol_info := SymbolInfo{}
		symbol_info.f_size_of_struct = sizeof(SymbolInfo) // Note: C.SYMBOL_INFO is 88
		symbol_info.f_max_name_len= 1024
		symbol_info.f_name = calloc(1024)

		// https://docs.microsoft.com/en-us/windows/win32/api/dbghelp/nf-dbghelp-symfromaddr
	//			success = C.SymFromAddr(C.GetCurrentProcess(), u64(stack[i]), 0, &symbol_info)
		success = C.SymFromAddr(C.GetCurrentProcess(), u64(stack[i]), 0, &symbol_info)

		if (success == 1) {
			println('   SymFromAddr success: ${int(success)} ')
			println('        SizeOfStruct: ${symbol_info.f_size_of_struct}')
			println('        Address: $symbol_info.f_address')
			println('        NameLen: ' + ptr_str(symbol_info.f_name_len))
			println('        Name: ' + ptr_str(symbol_info.f_name))
		}
	  	else {
			// https://docs.microsoft.com/en-us/windows/win32/debug/system-error-codes
			println('   SymFromAddr failure: ${C.GetLastError()}  (Note: 87 = The parameter is incorrect)')  // 87 = The parameter is incorrect.
		} 
	}

	C.SymCleanup(handle)

}

