module flag

// module flag for command-line flag parsing
//
// - parsing flags like '--flag' or '--stuff=things' or '--things stuff'
// - handles bool, int, float and string args
// - is able to print usage
// - handled unknown arguments as error
//
// Usage example:
//
//  ```v
//  module main
//
//  import os
//  import flag
//
//  fn main() {
//  	mut fp := flag.new_flag_parser(os.args)
//  	fp.application('flag_example_tool')
//  	fp.version('v0.0.0')
//  	fp.description('This tool is only designed to show how the flag lib is working')
//
//  	fp.skip_executable()
//
//  	an_int := fp.int('an_int', 0, 0o666, 'some int to define 0o666 is default')
//  	a_bool := fp.bool('a_bool', 0, false, 'some \'real\' flag')
//  	a_float := fp.float('a_float', 0, 1.0, 'also floats')
//  	a_string := fp.string('a_string', `a`, 'no text', 'finally, some text with "a" an abbreviation')
//
//  	additional_args := fp.finalize() or {
//  		eprintln(err)
//  		println(fp.usage())
//  		return
//  	}
//
//  	println('
//  		  an_int: $an_int
//  		  a_bool: $a_bool
//  		 a_float: $a_float
//  		a_string: \'$a_string\'
//  	')
//  	println(additional_args.join_lines())
//  }
//  ```

// data object storing information about a defined flag
pub struct Flag {
	pub:
	name     string // name as it appears on command line
	abbr     byte   // shortcut
	usage    string // help message
	val_desc string // something like '<arg>' that appears in usage,
	// and also the default value, when the flag is not given
}

pub fn (f Flag) str() string {
	return ''
	+'    flag:\n'
	+'            name: $f.name\n'
	+'            abbr: $f.abbr\n'
	+'            usag: $f.usage\n'
	+'            desc: $f.val_desc'
}
pub fn (af []Flag) str() string {
	mut res := []string{}
	res << '\n  []Flag = ['
	for f in af {
		res << f.str()
	}
	res << '  ]'
	return res.join('\n')
}
//
pub struct FlagParser {
	pub mut:
	args  []string                  // the arguments to be parsed
	max_free_args int
	flags []Flag                    // registered flags

	application_name        string
	application_version     string
	application_description string

	min_free_args int
	args_description        string
}

pub const (
	// used for formating usage message
	space = '                            '
	UNDERLINE = '-----------------------------------------------'
	MAX_ARGS_NUMBER = 4048
)

// create a new flag set for parsing command line arguments
// TODO use INT_MAX some how
pub fn new_flag_parser(args []string) &FlagParser {
	return &FlagParser{args: args.clone(), max_free_args: MAX_ARGS_NUMBER}
}

// change the application name to be used in 'usage' output
pub fn (fs mut FlagParser) application(name string) {
	fs.application_name = name
}

// change the application version to be used in 'usage' output
pub fn (fs mut FlagParser) version(vers string) {
	fs.application_version = vers
}

// change the application version to be used in 'usage' output
pub fn (fs mut FlagParser) description(desc string) {
	fs.application_description = desc
}

// in most cases you do not need the first argv for flag parsing
pub fn (fs mut FlagParser) skip_executable() {
	fs.args.delete(0)
}

// private helper to register a flag
fn (fs mut FlagParser) add_flag(name string, abbr byte, usage string, desc string) {
	fs.flags << Flag{
		name: name,
		abbr: abbr,
		usage: usage,
		val_desc: desc
	}
}

// private: general parsing a single argument
//  - search args for existence
//    if true
//      extract the defined value as string
//    else
//      return an (dummy) error -> argument is not defined
//
//  - the name, usage are registered
//  - found arguments and corresponding values are removed from args list
fn (fs mut FlagParser) parse_value(longhand string, shorthand byte) []string {
	full := '--$longhand'
	mut found_entries := []string{}
	mut to_delete := []int{}
	mut should_skip_one := false
	for i, arg in fs.args {
		if should_skip_one {
			should_skip_one = false
			continue
		}
		if arg == '--' {
			//End of input. We're done here.
			break
		}
		if arg[0] != `-` {
			continue
		}
		if (arg.len == 2 && arg[0] == `-` && arg[1] == shorthand ) || arg == full {
			if i+1 >= fs.args.len {
				panic("Missing argument for '$longhand'")
			}
			nextarg := fs.args[i+1]
			if nextarg.len > 2 && nextarg[..2] == '--' {
				//It could be end of input (--) or another argument (--abc).
				//Both are invalid so die.
				panic("Missing argument for '$longhand'")
			}
			found_entries << fs.args[i+1]
			to_delete << i
			to_delete << i+1
			should_skip_one = true
			continue
		}
		if arg.len > full.len+1 && arg[..full.len+1] == '$full=' {
			found_entries << arg[full.len+1..]
			to_delete << i
			continue
		}
	}
	for i, del in to_delete {
		//i entrys are deleted so it's shifted left i times.
		fs.args.delete(del - i)
	}
	return found_entries
}

// special parsing for bool values
// see also: parse_value
//
// special: it is allowed to define bool flags without value
// -> '--flag' is parsed as true
// -> '--flag' is equal to '--flag=true'
fn (fs mut FlagParser) parse_bool_value(longhand string, shorthand byte) ?string {
	full := '--$longhand'
	for i, arg in fs.args {
		if arg == '--' {
			//End of input. We're done.
			break
		}
		if arg.len == 0 {
			continue
		}
		if arg[0] != `-` {
			continue
		}
		if ( arg.len == 2 && arg[0] == `-` && arg[1] == shorthand ) || arg == full {
			if fs.args.len > i+1 && (fs.args[i+1] in ['true', 'false'])  {
				val := fs.args[i+1]
				fs.args.delete(i+1)
				fs.args.delete(i)
				return val
			} else {
				fs.args.delete(i)
				return 'true'
			}
		}
		if arg.len > full.len+1 && arg[..full.len+1] == '$full=' {
			// Flag abc=true
			val := arg[full.len+1..]
			fs.args.delete(i)
			return val
		}
		if arg[0] == `-` && arg[1] != `-` && arg.index_byte(shorthand) != -1 {
			// -abc is equivalent to -a -b -c
			return 'true'
		}
	}
	return error("parameter '$longhand' not found")
}

// bool_opt returns an optional that returns the value associated with the flag.
// In the situation that the flag was not provided, it returns null.
pub fn (fs mut FlagParser) bool_opt(name string, abbr byte, usage string) ?bool {
	fs.add_flag(name, abbr, usage, '<bool>')
	parsed := fs.parse_bool_value(name, abbr) or {
		return error("parameter '$name' not provided")
	}
	return parsed == 'true'
}

// defining and parsing a bool flag
//  if defined
//      the value is returned (true/false)
//  else
//      the default value is returned
// version with abbr
//TODO error handling for invalid string to bool conversion
pub fn (fs mut FlagParser) bool(name string, abbr byte, bdefault bool, usage string) bool {
	value := fs.bool_opt(name, abbr, usage) or {
		return bdefault
	}
	return value
}

// int_multi returns all instances of values associated with the flags provided
// In the case that none were found, it returns an empty array.
pub fn (fs mut FlagParser) int_multi(name string, abbr byte, usage string) []int {
	fs.add_flag(name, abbr, usage, '<multiple ints>')
	parsed := fs.parse_value(name, abbr)
	mut value := []int{}
	for val in parsed {
		value << val.int()
	}
	return value
}

// int_opt returns an optional that returns the value associated with the flag.
// In the situation that the flag was not provided, it returns null.
pub fn (fs mut FlagParser) int_opt(name string, abbr byte, usage string) ?int {
	fs.add_flag(name, abbr, usage, '<int>')
	parsed := fs.parse_value(name, abbr)
	if parsed.len == 0 {
		return error("parameter '$name' not provided")
	}
	return parsed[0].int()
}

// defining and parsing an int flag
//  if defined
//      the value is returned (int)
//  else
//      the default value is returned
// version with abbr
//TODO error handling for invalid string to int conversion
pub fn (fs mut FlagParser) int(name string, abbr byte, idefault int, usage string) int {
	value := fs.int_opt(name, abbr, usage) or {
		return idefault
	}
	return value
}

// float_multi returns all instances of values associated with the flags provided
// In the case that none were found, it returns an empty array.
pub fn (fs mut FlagParser) float_multi(name string, abbr byte, usage string) []f64 {
	fs.add_flag(name, abbr, usage, '<multiple floats>')
	parsed := fs.parse_value(name, abbr)
	mut value := []f64{}
	for val in parsed {
		value << val.f64()
	}
	return value
}

// float_opt returns an optional that returns the value associated with the flag.
// In the situation that the flag was not provided, it returns null.
pub fn (fs mut FlagParser) float_opt(name string, abbr byte, usage string) ?f64 {
	fs.add_flag(name, abbr, usage, '<float>')
	parsed := fs.parse_value(name, abbr)
	if parsed.len == 0 {
		return error("parameter '$name' not provided")
	}
	return parsed[0].f64()
}

// defining and parsing a float flag
//  if defined
//      the value is returned (float)
//  else
//      the default value is returned
// version with abbr
//TODO error handling for invalid string to float conversion
pub fn (fs mut FlagParser) float(name string, abbr byte, fdefault f64, usage string) f64 {
	value := fs.float_opt(name, abbr, usage) or {
		return fdefault
	}
	return value
}

// string_multi returns all instances of values associated with the flags provided
// In the case that none were found, it returns an empty array.
pub fn (fs mut FlagParser) string_multi(name string, abbr byte, usage string) []string {
	fs.add_flag(name, abbr, usage, '<multiple floats>')
	return fs.parse_value(name, abbr)
}

// string_opt returns an optional that returns the value associated with the flag.
// In the situation that the flag was not provided, it returns null.
pub fn (fs mut FlagParser) string_opt(name string, abbr byte, usage string) ?string {
	fs.add_flag(name, abbr, usage, '<string>')
	parsed := fs.parse_value(name, abbr)
	if parsed.len == 0 {
		return error("parameter '$name' not provided")
	}
	return parsed[0]
}

// defining and parsing a string flag
//  if defined
//      the value is returned (string)
//  else
//      the default value is returned
// version with abbr
pub fn (fs mut FlagParser) string(name string, abbr byte, sdefault string, usage string) string {
	value := fs.string_opt(name, abbr, usage) or {
		return sdefault
	}
	return value
}

pub fn (fs mut FlagParser) limit_free_args_to_at_least(n int) {
	if n > MAX_ARGS_NUMBER {
		panic('flag.limit_free_args_to_at_least expect n to be smaller than $MAX_ARGS_NUMBER')
	}
	if n <= 0 {
		panic('flag.limit_free_args_to_at_least expect n to be a positive number')
	}
	fs.min_free_args = n
}

pub fn (fs mut FlagParser) limit_free_args_to_exactly(n int) {
	if n > MAX_ARGS_NUMBER {
		panic('flag.limit_free_args_to_exactly expect n to be smaller than $MAX_ARGS_NUMBER')
	}
	if n < 0 {
		panic('flag.limit_free_args_to_exactly expect n to be a non negative number')
	}
	fs.min_free_args = n
	fs.max_free_args = n
}

// this will cause an error in finalize() if free args are out of range
// (min, ..., max)
pub fn (fs mut FlagParser) limit_free_args(min, max int) {
	if min > max {
		panic('flag.limit_free_args expect min < max, got $min >= $max')
	}
	fs.min_free_args = min
	fs.max_free_args = max
}

pub fn (fs mut FlagParser) arguments_description(description string){
	fs.args_description = description
}

// collect all given information and
pub fn (fs FlagParser) usage() string {

	positive_min_arg := ( fs.min_free_args > 0 )
	positive_max_arg := ( fs.max_free_args > 0 && fs.max_free_args != MAX_ARGS_NUMBER )
	no_arguments := ( fs.min_free_args == 0 && fs.max_free_args == 0 )

	mut adesc := if fs.args_description.len > 0 { fs.args_description } else { '[ARGS]' }
	if no_arguments { adesc = '' }

	mut use := ''
	if fs.application_version != '' {
		use += '$fs.application_name $fs.application_version\n'
		use += '$UNDERLINE\n'
	}
	use += 'Usage: ${fs.application_name} [options] $adesc\n'
	use += '\n'
	if fs.application_description != '' {
		use += 'Description:\n'
		use += '$fs.application_description'
		use += '\n\n'
	}

	// show a message about the [ARGS]:
	if positive_min_arg || positive_max_arg || no_arguments {
		if no_arguments {
			use += 'This application does not expect any arguments\n\n'
			goto end_of_arguments_handling
		}
		mut s:= []string{}
		if positive_min_arg { s << 'at least $fs.min_free_args' }
		if positive_max_arg { s << 'at most $fs.max_free_args' }
		if positive_min_arg && positive_max_arg && fs.min_free_args == fs.max_free_args {
			s = ['exactly $fs.min_free_args']
		}
		sargs := s.join(' and ')
		use += 'The arguments should be $sargs in number.\n\n'
	}
	end_of_arguments_handling:

	if fs.flags.len > 0 {
		use += 'Options:\n'
		for f in fs.flags {
			mut onames := []string{}
			if f.abbr != 0 {
				onames << '-${f.abbr.str()}'
			}
			if f.name != '' {
				if !f.val_desc.contains('<bool>') {
					onames << '--${f.name} $f.val_desc'
				}else{
					onames << '--${f.name}'
				}
			}
			option_names := '  ' + onames.join(', ')
			mut xspace := ''
			if option_names.len > space.len-2 {
				xspace = '\n${space}'
			} else {
				xspace = space[option_names.len..]
			}
			use += '${option_names}${xspace}${f.usage}\n'
		}
	}

	return use
}

// finalize argument parsing -> call after all arguments are defined
//
// all remaining arguments are returned in the same order they are defined on
// command line
//
// if additional flag are found (things starting with '--') an error is returned
// error handling is up to the application developer
pub fn (fs FlagParser) finalize() ?[]string {
	for a in fs.args {
		if a.len >= 2 && a[..2] == '--' {
			return error('Unknown argument \'${a[2..]}\'')
		}
	}
	if fs.args.len < fs.min_free_args && fs.min_free_args > 0 {
		return error('Expected at least ${fs.min_free_args} arguments, but given $fs.args.len')
	}
	if fs.args.len > fs.max_free_args && fs.max_free_args > 0 {
		return error('Expected at most ${fs.max_free_args} arguments, but given $fs.args.len')
	}
	if fs.args.len > 0 && fs.max_free_args == 0 && fs.min_free_args == 0 {
		return error('Expected no arguments, but given $fs.args.len')
	}
	return fs.args
}
