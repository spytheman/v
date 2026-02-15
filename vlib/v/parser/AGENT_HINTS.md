# Parser Agent Hints

- First run: `./vnew -silent test vlib/v/parser/`
- Then run: `./vnew -silent vlib/v/compiler_errors_test.v`
- If parse error text changed: `./vnew -silent vlib/v/slow_tests/inout/compiler_test.v`
- Rebuild required after edits here: `./v -g -keepc -o ./vnew cmd/v`
- Common hotspots: `vlib/v/parser/parser.v`, `vlib/v/parser/parse_expr.v`
- Keep parser fixes narrow; avoid checker/cgen edits unless required by the repro.
