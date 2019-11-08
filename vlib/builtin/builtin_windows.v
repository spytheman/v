module builtin

pub struct SymbolInfo {
pub mut:
    f_size_of_struct 	u16
    f_type_index  	 	u16      // Type Index of symbol
    f_reserved		[2]u64
    f_index		u16
    f_size		u16
    f_mod_base 	u64      // Base Address of module comtaining this symbol
    f_flags		u16
    f_value     		u64      // Value of symbol, ValuePresent should be 1
    f_address      	u64    	 // Address of symbol including base address of module
    f_register    	u16      // register holding value or pointer to value
    f_scope   		u16      // scope of the symbol
    f_tag        		u16      // pdb classification
    f_name_len   		u16      // Actual length of name
    f_max_name_len	u16
    f_name     		[]string // CHAR[] Name of symbol
}


fn print_backtrace_skipping_top_frames_msvc(skipframes int){
	println('print_backtrace_skipping_top_frames_msvc $skipframes')
}

fn print_backtrace_skipping_top_frames_mingw(skipframes int){
	println('print_backtrace_skipping_top_frames_mingw $skipframes')
}
