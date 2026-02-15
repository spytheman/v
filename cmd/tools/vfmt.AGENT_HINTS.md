# Vfmt Agent Hints

- First run: `./vnew -silent vlib/v/fmt/fmt_test.v`
- Then run: `./vnew -silent vlib/v/fmt/fmt_keep_test.v`
- Optional broader check: `./vnew -silent vlib/v/fmt/fmt_vlib_test.v`
- If formatter behavior changed, update expectations intentionally and explain why.
- Rebuild required when edits touch compiler-side formatter internals in `vlib/v/fmt/**`.
