PEG is shorthand for "Parsing Expression Grammar", which is a formalism for recognizing
languages (and generating parsers for them from the description).

PEGs are easier to write than custom parsers, and more powerful than regular expressions.
PEGs can produce grammars, that are easy to understand and fast.
PEGs can also be compiled to a bytecode format, that can be then reused for parsing
many input strings.

The implementation in this `peg` module, is inspired by the following articles/papers:
- http://bford.info/pub/lang/peg.pdf
- https://bakpakin.com/writing/how-janets-peg-works.html
