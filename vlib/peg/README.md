PEG is shorthand for "Parsing Expression Grammar", which is a formalism for recognizing
languages (and generating parsers for them from the description).

PEGs can produce grammars, that are easy to understand and fast.
PEGs are easier to write than custom parsers, and more powerful than regular expressions.

The implementation in this `peg` module, is inspired by the following articles/papers:
- http://bford.info/pub/lang/peg.pdf
- https://bakpakin.com/writing/how-janets-peg-works.html

PEGs work on string inputs. Use `unsafe{reuse_data_as_string(bytes)}` to get a string from a `[]u8`.
Note: no special meaning is given to the 0 byte, if it is present in the input string.

```v
import peg { PEG, between, choice, compile, range, seq }

fn ip_address_peg() PEG {
	pdig := range('09')
	p04 := range('04')
	p05 := range('05')
	pbyte := choice(seq('25', p05), seq('2', p04, pdig), seq('1', pdig, pdig), between(1,
		2, pdig))
	return seq(pbyte, '.', pbyte, '.', pbyte)
}

ip_address := compile(ip_address_peg())!
println(ip_address.parse('0.0.0.0')) // []
println(ip_address.parse('elephant')) // none
println(ip_address.parse('256.0.0.0')) // none
println(ip_address.parse('0.0.0.0more text')) // []
```

API
===
PEGs can be compiled ahead of time with peg.compile/1, if a PEG will be reused many times.

Primitive patterns
==================
Larger patterns are built up with primitive patterns.
The primitives are individual runes, string literals, or a given number of characters.

Combining patterns
==================
PEGs try to match an input text with a pattern in a greedy manner.
In other words, if a rule fails to match, that rule will fail, and not try again.

The only backtracking provided in a PEG is provided by the choice(x, y, z ...) fn,
which will try rules in order until one succeeds, and the whole pattern succeeds.
If no sub-pattern succeeds, then the whole pattern fails. Note: the order of `x` `y` `z`,
in the choice() call **does** matter. If `y` matches everything that `z`
matches, `z` will never succeed.
