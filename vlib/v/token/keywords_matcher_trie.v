module token

enum TrieNodeKind {
	normal
	suffix
}

[heap]
pub struct TrieNode {
mut:
	children       [123]&TrieNode
	nchildren      int
	node_kind      TrieNodeKind
	is_end_of_word bool
	value          int
	prefix         string
	suffix         string	
	min_len        int = 999999
	max_len        int
	keywords       []string
}

pub fn new_trie_node(prefix string) &TrieNode {
	return &TrieNode{
		prefix: prefix
	}
}

__global ncount = 0

pub fn (node &TrieNode) show(level int) {
	ncount++
	eprintln('> level: ${level:2} | node: ${ptr_str(node)} | kind: ${node.node_kind:10} | value: ${node.value:12} | minl: ${node.min_len:2} | maxl: ${node.max_len:2} | is_end_of_word: ${int(node.is_end_of_word)} | nchildren: ${node.nchildren:2} | prefix: `${node.prefix}` | suffix: `${node.suffix}` keywords: $node.keywords')
	for x in node.children {
		if x != unsafe { nil } {
			x.show(level + 1)
		}
	}
}

pub fn (mut node TrieNode) add_word(word string, value int, word_idx int) {
	if node.max_len < word.len {
		node.max_len = word.len
	}
	if node.min_len > word.len {
		node.min_len = word.len
	}
	node.keywords << word
	first := u8(word[word_idx] or {
		node.is_end_of_word = true
		node.value = value
		return
	})
	// eprintln('>> node: ${ptr_str(node)} | first: $first | word_idx: $word_idx')
	mut child_node := node.children[first]
	if child_node == unsafe { nil } {
		child_node = new_trie_node(word#[..word_idx + 1])
		node.nchildren++
		node.children[first] = child_node
	}
	child_node.add_word(word, value, word_idx + 1)
}

[direct_array_access]
pub fn (root &TrieNode) find(word string) int {
	if word.len > root.max_len || word.len < root.min_len {
		return -1
	}
	mut node := unsafe { &TrieNode(root) }
	mut idx := 0
	for {
		// eprintln('> match_keyword: `${word:20}` | node: ${ptr_str(node)} | node.prefix: ${node.prefix:15} | idx: ${idx:3}')
		if node.node_kind == .suffix {
			eprintln('> word: $word | $word.len | $node.min_len <= $word.len <= $node.max_len')
			mut remaining := word.len - idx
			if remaining != node.suffix.len {
				return -1
			}
			mut sidx := 0 
			for remaining > 0 {
				 eprintln('>> idx: $idx | c: ${word[idx]} | ${word[idx].ascii_str()} | remaining: $remaining ')
				if word[idx] != node.suffix[sidx] {
					dump(idx)
					exit(1)
					return -1
				}
				idx++
				sidx++
				remaining--
			}
			// dump(idx)
			// dump(word)
			// dump(word#[..idx])
			// dump(word#[idx..])
			// dump(node.suffix#[0..1])
			// node.show(0)
			return node.value			
		}
		if idx == word.len {
			if node.is_end_of_word {
				// node.show(0)
				return node.value
			}
			return -1
		}
		c := word[idx]
		child := node.children[c]
		if child == unsafe { nil } {
			return -1
		}
		node = child
		idx++
	}
	return -1
}

pub fn (node &TrieNode) find_first_leaf_value() int {
	res := node.value
	for c in node.children {
		if c != unsafe { nil } {
			return c.find_first_leaf_value()
		}
	}
	return res
}

pub fn (mut node TrieNode) prune() {
	// if true { return }
	if node.keywords.len == 1 {
		node.suffix = node.keywords[0]#[node.prefix.len..]
		node.value = node.find_first_leaf_value()
		println('> prunning at node ${ptr_str(node)} prefix: $node.prefix | suffix: $node.suffix | value: ${token.Kind(node.value)} | keywords: $node.keywords')
		node.nchildren = 0
		node.is_end_of_word = true
		node.node_kind = .suffix
		for idx, _ in node.children {
			node.children[idx] = unsafe { nil }
		}		
		node.show(0)
		return
	}
	for mut child in node.children {
		if child != unsafe { nil } {
			child.prune()
		}
	}
}

pub fn new_keywords_matcher<T>(kw_map map[string]T) &TrieNode {
	mut root := new_trie_node('')
	for k, v in kw_map {
		root.add_word(k, v, 0)
	}
	ncount = 0 root.show(0) dump(ncount)
	eprintln('---------------------------------')
	root.prune()
	eprintln('---------------------------------')
	ncount = 0 root.show(0) dump(ncount)
	return root
}
