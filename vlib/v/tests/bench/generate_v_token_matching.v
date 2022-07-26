import v.token

fn main() {
	km_trie := token.new_keywords_matcher_trie(token.keywords)
	println('')
	println('module matching')
	println('[direct_array_access]')
	println('pub fn token_by_keyword(word string) int {')
	println('\twlen := word.len')
	println('\tif wlen < $km_trie.min_len || wlen > $km_trie.max_len { return -1 }')
	println('\tmut cptr := unsafe{ word.str }')
	println('\tmatch wlen {')
	for idx, t in km_trie.nodes {
		if idx < km_trie.min_len || idx > km_trie.max_len || t == unsafe { nil } {
			continue
		}
		// println('// > idx: $idx | ptr_str: ${ptr_str(t)}')
		generate_matcher_for_trie_node(idx, t)
	}
	println('\t\telse{}')
	println('\t}')
	println('\treturn -1')
	println('}')
	println('')
}

fn generate_matcher_for_trie_node(idx int, t &token.TrieNode) {
	println('\t\t$idx {')
	for c, t1 in t.children {
		if t1 != unsafe { nil } {
			gen_trie_node(t1, idx, u8(c), 0)
		}
	}
	println('\t\t}')
}

fn gen_trie_node(t &token.TrieNode, idx int, node_char u8, level int) {
	indent := '\t'.repeat(level + 3)
	// println('>>>>> idx: $idx | level: $level')
	println('${indent}if *cptr == $node_char { // `$node_char.ascii_str()`')
	if idx - 1 == level {
		println('$indent\treturn $t.value // ${token.Kind(t.value)}')
		println('$indent}')
		return
	}
	println('$indent\tunsafe { cptr++ }')
	for c, t1 in t.children {
		if t1 != unsafe { nil } {
			gen_trie_node(t1, idx, u8(c), level + 1)
		}
	}
	println('$indent\treturn -1')
	println('$indent}')
}
