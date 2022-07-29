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

	res = 0
	for _ in 0 .. max_repetitions {
		for kw in words {
			res += u64(match_keyword_token2(kw))
		}
	}
	bmark.measure('sum: $res, $max_repetitions repetitions of match_keyword_token2')
}

pub fn match_keyword_token2(name string) token.Kind {
	if name.len < 2 || name.len > 10 {
		return .unknown
	}
	mut cptr := unsafe { name.str }
	mut hash := u16(*cptr << 1)
	max := if name.len > 6 { 6 } else { name.len }
	for _ in 0 .. max {
		hash += *cptr
		unsafe { cptr++ }
	}
	match name.len {
		2 {
			match hash {
				406 { return if name == 'as' { .key_as } else { .unknown } }
				416 { return if name == 'fn' { .key_fn } else { .unknown } }
				420 { return if name == 'go' { .key_go } else { .unknown } }
				417 { return if name == 'if' { .key_if } else { .unknown } }
				425 { return if name == 'in' { .key_in } else { .unknown } }
				430 { return if name == 'is' { .key_is } else { .unknown } }
				447 { return if name == 'or' { .key_orelse } else { .unknown } }
				else { return .unknown }
			}
		}
		3 {
			match hash {
				515 { return if name == 'asm' { .key_asm } else { .unknown } }
				531 { return if name == 'for' { .key_for } else { .unknown } }
				560 { return if name == 'mut' { .key_mut } else { .unknown } }
				543 { return if name == 'nil' { .key_nil } else { .unknown } }
				551 { return if name == 'pub' { .key_pub } else { .unknown } }
				else { return .unknown }
			}
		}
		4 {
			match hash {
				638 { return if name == 'dump' { .key_dump } else { .unknown } }
				627 { return if name == 'else' { .key_else } else { .unknown } }
				639 { return if name == 'enum' { .key_enum } else { .unknown } }
				647 { return if name == 'goto' { .key_goto } else { .unknown } }
				641 { return if name == 'lock' { .key_lock } else { .unknown } }
				652 { return if name == 'none' { .key_none } else { .unknown } }
				680 { return if name == 'true' { .key_true } else { .unknown } }
				682 { return if name == 'type' { .key_type } else { .unknown } }
				else { return .unknown }
			}
		}
		5 {
			match hash {
				713 { return if name == 'break' { .key_break } else { .unknown } }
				749 { return if name == 'const' { .key_const } else { .unknown } }
				718 { return if name == 'defer' { .key_defer } else { .unknown } }
				727 { return if name == 'false' { .key_false } else { .unknown } }
				743 { return if name == 'match' { .key_match } else { .unknown } }
				767 { return if name == 'rlock' { .key_rlock } else { .unknown } }
				787 { return if name == 'union' { .key_union } else { .unknown } }
				else { return .unknown }
			}
		}
		6 {
			match hash {
				852 { return if name == 'assert' { .key_assert } else { .unknown } }
				831 { return if name == 'atomic' { .key_atomic } else { .unknown } }
				877 { return if name == 'import' { .key_import } else { .unknown } }
				864 { return if name == 'module' { .key_module } else { .unknown } }
				900 { return if name == 'return' { .key_return } else { .unknown } }
				870 { return if name == 'select' { .key_select } else { .unknown } }
				861 { return if name == 'shared' { .key_shared } else { .unknown } }
				886 { return if name == 'sizeof' { .key_sizeof } else { .unknown } }
				878 { return if name == 'static' { .key_static } else { .unknown } }
				907 { return if name == 'struct' { .key_struct } else { .unknown } }
				895 { return if name == 'typeof' { .key_typeof } else { .unknown } }
				876 { return if name == 'unsafe' { .key_unsafe } else { .unknown } }
				else { return .unknown }
			}
		}
		8 {
			match hash {
				800 { return if name == '__global' { .key_global } else { .unknown } }
				814 { return if name == '_likely_' { .key_likely } else { .unknown } }
				849 { return if name == 'continue' { .key_continue } else { .unknown } }
				891 { return if name == 'volatile' { .key_volatile } else { .unknown } }
				else { return .unknown }
			}
		}
		9 {
			match hash {
				858 { return if name == 'interface' { .key_interface } else { .unknown } }
				863 { return if name == 'isreftype' { .key_isreftype } else { .unknown } }
				else { return .unknown }
			}
		}
		10 {
			match hash {
				810 { return if name == '__offsetof' { .key_offsetof } else { .unknown } }
				832 { return if name == '_unlikely_' { .key_unlikely } else { .unknown } }
				else { return .unknown }
			}
		}
		else {
			return .unknown
		}
	}
}
