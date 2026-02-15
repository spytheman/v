# Checker Agent Hints

- First run: `./vnew -silent test vlib/v/checker/`
- Then run: `./vnew -silent vlib/v/compiler_errors_test.v`
- If diagnostics changed: `./vnew -silent vlib/v/slow_tests/inout/compiler_test.v`
- Rebuild required after edits here: `./v -g -keepc -o ./vnew cmd/v`
- Common hotspots: `vlib/v/checker/fn.v`, `vlib/v/checker/assign.v`, `vlib/v/checker/errors.v`
- If output files differ, update `.out` only for intended behavior changes.
