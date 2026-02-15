# Cgen Agent Hints

- First run: `./vnew -silent vlib/v/gen/c/coutput_test.v`
- Then run: `./vnew -silent vlib/v/compiler_errors_test.v`
- For wider compiler confidence: `./vnew -silent test vlib/v/`
- Rebuild required after edits here: `./v -g -keepc -o ./vnew cmd/v`
- Debug path: use `-keepc -cg` and inspect generated C for mismatch points.
