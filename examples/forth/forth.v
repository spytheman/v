// Copyright (c) 2025 Delyan Angelov. All rights reserved. Use of this source
// code is governed by an MIT license that can be found in the LICENSE file.

// A simple mini Forth interpreter in V . See https://www.forth.com/starting-forth/
// for lots of examples, and explanations about the Forth concepts and syntax.
// TODO: add words for looping.
// TODO: add words for user input.
// TODO: add words for reading/writing RAM, not just the stack.
import os
import readline
import term

type ForthCB = fn (mut f Forth)

struct Forth {
mut:
	stack           []i64              // Data stack
	words           map[string]ForthCB // Dictionary
	compiling       bool               // Compilation flag, true in `: word ... ;`
	current_word    string             // Word being defined in `: word ... ;`
	current_def     []string           // Current definition in `: word w1 w2 ... wN ;`
	string_literals map[string]string  // String storage for `." some string "`
	if_stack        []bool             // Conditional stack
	else_seen       []bool             // Else tracking
	skip_exec       bool               // Skip execution flag
}

fn (mut f Forth) push(n i64) {
	f.stack << n
}

fn (mut f Forth) pop() !i64 {
	if f.stack.len == 0 {
		return error('Stack underflow')
	}
	return f.stack.pop()
}

fn (mut f Forth) pop2() !(i64, i64) {
	b := f.pop() or { return error('Stack underflow') }
	a := f.pop() or {
		f.push(b)
		return error('Stack underflow')
	}
	return a, b
}

fn (mut f Forth) define(name string, action ForthCB) {
	f.words[name.to_lower()] = action
}

fn (mut f Forth) define_2(name string, op fn (a i64, b i64) i64) {
	action := fn [op] (mut f Forth) {
		a, b := f.pop2() or {
			eprintln('Error: ${err}')
			return
		}
		f.push(op(a, b))
	}
	f.words[name.to_lower()] = action
}

fn (mut f Forth) execute(word string) {
	if word.trim_space() == '' {
		return
	}
	if f.compiling && word != ';' {
		f.current_def << word
		return
	}
	if f.skip_exec && !f.compiling && word != 'else' && word != 'then' {
		return
	}
	if word in f.words {
		f.words[word](mut f)
	} else if word.is_int() {
		f.push(word.i64())
	} else {
		eprintln("Error: Unknown word '${word}'")
	}
}

fn (mut f Forth) interpret(input string) {
	words := input.split_any(' \n').map(it.trim_space()).filter(it != '')
	mut i := 0
	for i < words.len {
		word := words[i].to_lower()
		// Handle : word (start definition)
		if word == ':' && i + 1 < words.len {
			if f.compiling {
				eprintln('Error: Cannot nest word definitions')
				i += 2
				continue
			}
			f.compiling = true
			f.current_def = []string{}
			f.current_word = words[i + 1]
			i += 2
			continue
		}
		// Handle `forget wordname`
		if word == 'forget' && i + 1 < words.len {
			if f.compiling {
				eprintln('Error: Cannot use FORGET while compiling')
			} else {
				word_to_forget := words[i + 1]
				if word_to_forget in f.words {
					f.words.delete(word_to_forget)
				} else {
					eprintln("Error: Word '${word_to_forget}' not found")
				}
			}
			i += 2
			continue
		}
		// Handle ." word (print string)
		if word == '."' {
			mut string_parts := []string{}
			mut found_end := false
			mut j := i + 1
			for j < words.len {
				next := words[j]
				if next.ends_with('"') {
					string_parts << next.substr(0, next.len - 1)
					found_end = true
					break
				} else {
					string_parts << next
				}
				j++
			}
			if found_end {
				text := string_parts.join(' ')
				if f.compiling {
					id := f.string_literals.len.str()
					f.string_literals[id] = text
					f.current_def << 'print_string'
					f.current_def << id
				} else if !f.skip_exec {
					print(text)
				}
				i = j + 1
			} else {
				eprintln('Error: Missing closing quote for ."')
				i++
			}
			continue
		}
		f.execute(word)
		i++
	}
}

fn (mut forth Forth) define_builtin_words() {
	forth.define('page', |f| term.clear())
	forth.define('bye', |f| exit(0))
	forth.define('cr', |f| println(''))
	// Control flow
	forth.define('if', fn (mut f Forth) {
		condition := f.pop() or {
			eprintln('Error: Stack underflow (IF)')
			return
		}
		f.if_stack << (condition != 0)
		f.else_seen << false
		f.skip_exec = condition == 0
	})
	forth.define('else', fn (mut f Forth) {
		if f.if_stack.len > 0 {
			f.skip_exec = !f.skip_exec
			f.else_seen[f.else_seen.len - 1] = true
		} else {
			eprintln('Error: ELSE without IF')
		}
	})
	forth.define('then', fn (mut f Forth) {
		if f.if_stack.len > 0 {
			f.if_stack.pop()
			f.else_seen.pop()
			f.skip_exec = false
			if f.if_stack.len > 0 && !f.else_seen[f.else_seen.len - 1] {
				f.skip_exec = !f.if_stack[f.if_stack.len - 1]
			}
		} else {
			eprintln('Error: THEN without IF')
		}
	})
	// Help and dictionary
	forth.define('help', fn (mut f Forth) {
		println("Mini Forth REPL - 'bye' to exit, 'words' for commands, '.s' for stack")
		println('Arithmetic: + - * / mod | Comparison: = < > <= >= <>')
		println('Stack: dup swap drop clear rot over 2dup nip tuck')
		println('\nExamples:')
		println('  5 10 + .                      # Add and print')
		println('  5 10 < if 7 else 42 then .    # Conditional')
		println('  : square dup * ;              # Define word')
		println('  ." Hello, World!"             # Print string')
		println('  cr                            # Print a new line')
	})
	forth.define('words', |f| println(f.words.keys().sorted().join(' ')))
	// Comparison
	forth.define_2('=', |a, b| if a == b { 1 } else { 0 })
	forth.define_2('<', |a, b| if a < b { 1 } else { 0 })
	forth.define_2('>', |a, b| if a > b { 1 } else { 0 })
	forth.define_2('<=', |a, b| if a <= b { 1 } else { 0 })
	forth.define_2('>=', |a, b| if a >= b { 1 } else { 0 })
	forth.define_2('<>', |a, b| if a != b { 1 } else { 0 })
	// Arithmetic
	forth.define_2('+', |a, b| a + b)
	forth.define_2('-', |a, b| a - b)
	forth.define_2('*', |a, b| a * b)
	forth.define('/', fn (mut f Forth) {
		b := f.pop() or {
			eprintln('Error: Stack underflow')
			return
		}
		if b == 0 {
			eprintln('Error: Division by zero')
			f.push(b)
			return
		}
		a := f.pop() or {
			eprintln('Error: Stack underflow')
			f.push(b)
			return
		}
		f.push(a / b)
	})
	forth.define('mod', fn (mut f Forth) {
		b := f.pop() or {
			eprintln('Error: Stack underflow')
			return
		}
		if b == 0 {
			eprintln('Error: Modulo by zero')
			f.push(b)
			return
		}
		a := f.pop() or {
			eprintln('Error: Stack underflow')
			f.push(b)
			return
		}
		f.push(a % b)
	})
	// Stack manipulation
	forth.define('clear', fn (mut f Forth) {
		f.stack.clear()
	})
	forth.define('depth', fn (mut f Forth) {
		f.push(f.stack.len)
	})
	forth.define('dup', fn (mut f Forth) {
		a := f.pop() or {
			eprintln('Error: Stack underflow')
			return
		}
		f.push(a)
		f.push(a)
	})
	forth.define('swap', fn (mut f Forth) {
		a, b := f.pop2() or {
			eprintln('Error: ${err}')
			return
		}
		f.push(b)
		f.push(a)
	})
	forth.define('drop', fn (mut f Forth) {
		_ := f.pop() or {
			eprintln('Error: Stack underflow')
			return
		}
	})
	forth.define('rot', fn (mut f Forth) {
		if f.stack.len < 3 {
			eprintln('Error: Stack underflow (need 3 items for rot)')
			return
		}
		c := f.pop() or { return }
		b := f.pop() or { return }
		a := f.pop() or { return }
		f.push(b)
		f.push(c)
		f.push(a)
	})
	forth.define('over', fn (mut f Forth) {
		if f.stack.len < 2 {
			eprintln('Error: Stack underflow (need 2 items for over)')
			return
		}
		b := f.pop() or { return }
		a := f.pop() or { return }
		f.push(a)
		f.push(b)
		f.push(a)
	})
	// More stack operations
	forth.define('2dup', fn (mut f Forth) {
		if f.stack.len < 2 {
			eprintln('Error: Stack underflow (need 2 items for 2dup)')
			return
		}
		b := f.pop() or { return }
		a := f.pop() or { return }
		f.push(a)
		f.push(b)
		f.push(a)
		f.push(b)
	})
	forth.define('nip', fn (mut f Forth) {
		if f.stack.len < 2 {
			eprintln('Error: Stack underflow (need 2 items for nip)')
			return
		}
		b := f.pop() or { return }
		_ := f.pop() or { return }
		f.push(b)
	})
	forth.define('tuck', fn (mut f Forth) {
		if f.stack.len < 2 {
			eprintln('Error: Stack underflow (need 2 items for tuck)')
			return
		}
		b := f.pop() or { return }
		a := f.pop() or { return }
		f.push(b)
		f.push(a)
		f.push(b)
	})
	// Output
	forth.define('.', fn (mut f Forth) {
		a := f.pop() or {
			eprintln('Error: Stack underflow')
			return
		}
		print(a)
		print(' ')
	})
	forth.define('.literals', fn (mut f Forth) {
		print('<')
		print(f.string_literals.len)
		print('>')
		println('')
		for k, v in f.string_literals {
			println('> k: ${k} | literal: ${v}')
		}
	})
	forth.define('.s', fn (mut f Forth) {
		print('<')
		print(f.stack.len)
		print('> ')
		for n in f.stack {
			print(n)
			print(' ')
		}
	})
	// Word definition
	forth.define(':', fn (mut f Forth) {
		eprintln('Error: ":" should be followed by a word name')
	})
	forth.define(';', fn (mut f Forth) {
		if !f.compiling {
			eprintln('Error: Not in compilation mode')
			return
		}
		name := f.current_word
		definition := f.current_def.clone()
		string_literals := f.string_literals.clone()
		f.define(name, fn [definition, string_literals] (mut f Forth) {
			old_skip_exec := f.skip_exec
			old_if_stack_len := f.if_stack.len
			old_else_seen_len := f.else_seen.len
			for i := 0; i < definition.len; i++ {
				word := definition[i]
				if word == 'print_string' && i + 1 < definition.len {
					id := definition[i + 1]
					if !f.skip_exec {
						if lit := string_literals[id] {
							print(lit)
						}
					}
					i++
				} else {
					f.execute(word)
				}
			}
			f.skip_exec = old_skip_exec
			for f.if_stack.len > old_if_stack_len {
				f.if_stack.pop()
			}
			for f.else_seen.len > old_else_seen_len {
				f.else_seen.pop()
			}
		})
		f.compiling = false
		f.current_word = ''
		f.current_def = []string{}
	})
	forth.define('forget', |f| eprintln('Error: FORGET should be followed by a word name'))
}

fn (mut f Forth) repl() {
	mut reader := readline.Readline{}
	for {
		line := reader.read_line('') or { break }
		input := line.trim_space()
		if input == '' {
			continue
		}
		f.interpret(input)
		println(' ok')
	}
}

fn Forth.new() Forth {
	mut forth := Forth{}
	forth.define_builtin_words()
	return forth
}

fn main() {
	mut forth := Forth.new()
	files := os.args#[1..]
	if files.len == 0 {
		forth.interpret('help')
		forth.repl()
	} else {
		for f in files {
			content := os.read_file(f) or {
				eprintln('Error: could not read file: `${f}`')
				continue
			}
			forth.interpret(content)
		}
	}
}
