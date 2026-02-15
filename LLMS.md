# LLMS.md

AI-focused operating guide for the V repository.

This file is intentionally short. It captures the default workflow and constraints for
LLM agents making changes in this repo.

## Repository Profile

- Project: V programming language (compiler + stdlib + tools)
- Entrypoint: `cmd/v/v.v`
- Compiler modules: `vlib/v/`
- Tools: `cmd/tools/`
- Stdlib: `vlib/`

Compiler pipeline (high level):
`scanner -> parser -> checker -> transformer -> markused -> gen/c`

## Bootstrap (Local Agent Workflow)

From repo root:

1. Build bootstrap compiler if needed: `make` (if `./v` is missing)
2. Build working compiler: `./v -g -keepc -o ./vnew cmd/v`
3. Use `./vnew` for all other tasks

Examples:

- Run file: `./vnew run examples/hello_world.v`
- Test dir: `./vnew -silent test vlib/v/`
- Format V file: `./vnew fmt -w path/to/file.v`
- Check markdown: `./vnew check-md path/to/file.md`

## Non-Negotiable Rules

- Do not overwrite the working `./v` binary.
- Never run `./v self` without `-o`.
- Use `./v` only to build `./vnew`; use `./vnew` for everything else.
- Put V flags after `./vnew` and before subcommands/files.
  - Correct: `./vnew -g run file.v`
  - Wrong: `./vnew run file.v -g`
- Keep changes tightly scoped to the user request.
- Do not modify `thirdparty/` unless explicitly requested.
- Ask before touching `ci/` or `Dockerfile*`.

## Rebuild Triggers

Rebuild `./vnew` after changes in:

- `vlib/v/`
- `cmd/v/`
- Core modules: `builtin`, `strings`, `os`, `strconv`, `time`

Rebuild command:

`./v -g -keepc -o ./vnew cmd/v`

## Test Selection (Minimums)

Start with the smallest relevant tests.

- Docs only (`.md`): `./vnew check-md file.md`
- Compiler changes (`vlib/v/`, `cmd/v/`):
  - `./vnew -silent vlib/v/compiler_errors_test.v`
  - `./vnew -silent test vlib/v/`
- Parser-only (`vlib/v/parser/`): `./vnew -silent test vlib/v/parser/`
- Checker-only (`vlib/v/checker/`): `./vnew -silent test vlib/v/checker/`
- C codegen (`vlib/v/gen/c/`): `./vnew -silent vlib/v/gen/c/coutput_test.v`
- Diagnostic/output text changes:
  - `./vnew -silent vlib/v/slow_tests/inout/compiler_test.v`
- Tool changes (`cmd/tools/`): run the tool-specific test if it exists.

Avoid `./vnew test-all` unless explicitly requested or needed for broad changes.

## Formatting and Style

- Format touched `.v` and `.vsh` files: `./vnew fmt -w <file>`
- Check touched markdown files: `./vnew check-md <file.md>`
- Keep markdown lines <= 100 chars.
- Add doc comments before each new or modified public function/method.
- Avoid `unsafe` unless required; keep unsafe scopes minimal and justified.

## V-Specific Footguns

- Module name must match directory name.
- Prefer platform/backend split files (`*.c.v`, `*.js.v`, etc.) for large env-specific code.
- Use comptime constructs correctly:
  - `$if` for compile-time conditions
  - `$for` for compile-time reflection loops
- Do not update `.out` files unless behavior change is intentional.

## Minimal Debug Toolkit

- V line info: `-g`
- Keep generated C: `-keepc`
- C line info: `-cg`
- Show C compiler command: `-showcc`
- Show C compiler output: `-show-c-output`

Useful combo for tricky failures:
`./vnew -keepc -cg run file.v`

## Change Reporting Template

When finishing substantial work, report:

- Behavior change: `none` or a short exact description
- Tests run: list exact commands (or `Not run` + reason)
- Touched files: explicit paths
- Any unrelated repo changes noticed

## Canonical References

Use these as source of truth when unsure:

- `AGENTS.md` (agent workflow and local overrides)
- `TESTS.md` (test taxonomy and runners)
- `CONTRIBUTING.md` (repo conventions and architecture context)
