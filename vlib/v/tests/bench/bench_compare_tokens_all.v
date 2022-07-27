import v.token
import benchmark
import v.token.matching

#include "/v/cleanv/words.c"
#include "/v/cleanv/gperf_words.c"

fn C.vfast_perfect_hash(const_word &char, length usize) C.PerfectKey

struct C.GPerfResult {
	name &char
	code int
}

fn C.in_word_set(const_str &char, len usize) &C.GPerfResult

const max_repetitions = 500_000

const words = ['for', 'val', 'int', 'f32', 'struct', 'return', 'if', 'in', 'as', 'or', 'else',
	'unsafe', 'return', 'assert', 'Abc', 'my_identifier', 'a', 'assez', 'returned']

fn main() {
	mut res := u64(0)
	km_trie := token.new_keywords_matcher_trie(token.keywords)
	mut bmark := benchmark.start()

	res = 0
	for _ in 0 .. max_repetitions {
		for kw in words {
			res += u64(token.keywords[kw])
		}
	}
	bmark.measure('sum: $res, $max_repetitions repetitions of token.keywords')

	res = 0
	for _ in 0 .. max_repetitions {
		for kw in words {
			res += u64(km_trie.find(kw))
		}
	}
	bmark.measure('sum: $res, $max_repetitions repetitions of km_trie.find')

	res = 0
	for _ in 0 .. max_repetitions {
		for kw in words {
			res += u64(matching.token_by_keyword(kw))
		}
	}
	bmark.measure('sum: $res, $max_repetitions repetitions of matching.token_by_keyword')

	res = 0
	for _ in 0 .. max_repetitions {
		for kw in words {
			res += u64(C.vfast_perfect_hash(kw.str, kw.len))
		}
	}
	bmark.measure('sum: $res, $max_repetitions repetitions of C.vfast_perfect_hash')

	res = 0
	for _ in 0 .. max_repetitions {
		for kw in words {
			x := C.in_word_set(kw.str, usize(kw.len))
			if x != unsafe { nil } {
				res += u64(x.code)
			}
		}
	}
	bmark.measure('sum: $res, $max_repetitions repetitions of C.in_word_set')
}
