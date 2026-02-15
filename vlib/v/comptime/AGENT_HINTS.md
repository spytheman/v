# Comptime Agent Hints

- First run: `./vnew -silent test vlib/v/tests/`
- Add targeted comptime checks under `vlib/v/tests/` as needed.
- For parser/checker fallout: `./vnew -silent vlib/v/compiler_errors_test.v`
- Rebuild required after edits here: `./v -g -keepc -o ./vnew cmd/v`
- Common pitfall: validate `$if`/`$for` semantics and avoid runtime/comptime mixups.
