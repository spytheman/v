import v.token
import v.token.matching
import benchmark

#include "/v/cleanv/words.c"
#include "/v/cleanv/gperf_words.c"

fn C.vfast_perfect_hash(const_word &char, length usize) C.PerfectKey

struct C.GPerfResult {
	name &char
	code int
}

fn C.in_word_set(const_str &char, len usize) &C.GPerfResult

const max_repetitions = 4_000_000

fn main() {
	mut res := token.Kind{}
	km_trie := token.new_keywords_matcher_trie(token.keywords)
	for kw in ['for', 'val', 'int', 'f32', 'struct', 'return', 'if', 'in', 'as', 'or', 'else',
		'unsafe', 'assert', 'Abc', 'my_identifier', 'a', 'assez', 'returned'] {
		mut bmark := benchmark.start()

		for _ in 0 .. max_repetitions {
			res = token.keywords[kw]
			if int(res) == -2 {
				print('xx')
			}
		}
		bmark.measure('$max_repetitions repetitions of token.keywords["$kw"] = $res')

		for _ in 0 .. max_repetitions {
			res = token.Kind(km_trie.find(kw))
			if int(res) == -2 {
				print('xx')
			}
		}
		bmark.measure('$max_repetitions repetitions of km_trie.find("$kw") = $res')

		for _ in 0 .. max_repetitions {
			res = token.Kind(matching.token_by_keyword(kw))
			if int(res) == -2 {
				print('xx')
			}
		}
		bmark.measure('$max_repetitions repetitions of matching.token_by_keyword("$kw") = $res')

		for _ in 0 .. max_repetitions {
			res = token.Kind(C.vfast_perfect_hash(kw.str, usize(kw.len)))
			if int(res) == -2 {
				print('xx')
			}
		}
		bmark.measure('$max_repetitions repetitions of C.vfast_perfect_hash(kw.str, usize(kw.len)) = $res')

		for _ in 0 .. max_repetitions {
			x := C.in_word_set(kw.str, usize(kw.len))
			if x != unsafe { nil } {
				res = token.Kind(x.code)
			}
			if int(res) == -2 {
				print('xx')
			}
		}
		bmark.measure('$max_repetitions repetitions of C.in_word_set(kw.str, usize(kw.len)) = $res')

		println('--------------------------------')
	}
}
