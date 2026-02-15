<!-- generated: canonical source is AGENTS.md; run ./cmd/tools/agents/sync_agent_docs.vsh -->
- Canonical source: `AGENTS.md`
- Drift policy: update `AGENTS.md` first, then run `./cmd/tools/agents/sync_agent_docs.vsh`.
If anything here differs from `AGENTS.md`, follow `AGENTS.md` and treat this file as stale.

# Agent Task Slices
Generated from `AGENTS.md` to keep startup context focused by task.

## Bugfix Slice
Use this for parser/checker/cgen/runtime bugfixes.

- `Top Rules` summary: Use `./v` only to build `./vnew`; use `./vnew` for all other tasks.
- `Top Rules` action: Use `./v` only to build `./vnew`; use `./vnew` for everything else.
- `Top Rules` action: Put all V flags immediately after `./vnew` and before the subcommand/file,
                      e.g. `./vnew -g run file.v` (not `./vnew run file.v -g`); flags after the
                      subcommand are passed to that subcommand.
- `Common Workflow` summary: Use this order: verify state, edit, rebuild if needed, format, then run
                             targeted tests.
- `Common Workflow` action: Before work: `git status`; ensure `./vnew` exists; rebuild if needed. If
                            `./vnew` is missing, see Quick Start or Build & Rebuild.
- `Common Workflow` action: If compiler sources or core modules changed, rebuild `./vnew` with `./v
                            -g -keepc -o ./vnew cmd/v` (see Build & Rebuild).
- `Build & Rebuild` summary: Rebuild `./vnew` after compiler/core changes with `./v -g -keepc -o
                             ./vnew cmd/v`.
- `Build & Rebuild` action: Build `./vnew` (debug-friendly, recommended for agent workflows): `./v
                            -g -keepc -o ./vnew cmd/v`
- `Build & Rebuild` action: Never run `./v self` directly; only build `./vnew` with the commands
                            above.
- `Testing` summary: Start from the smallest relevant tests and escalate when change scope or
                     triggers require it.
- `Testing` action: File (shows test output): `./vnew path/to/file_test.v`.
- `Testing` action: File (test runner report only): `./vnew test path/to/file_test.v`.
- `Debug` summary: Use compiler debug flags (`-keepc`, `-cg`, trace flags) to localize
                   parser/checker/cgen issues.
- `Debug` action: `./vnew -o ./w -d trace_checker cmd/v`
- `Debug` action: JS/native/wasm: prefer small, focused test files with `-b js|native|wasm` and
                  `-show-c-output` where applicable; avoid broad `-b <backend> test vlib/`.
- `Reporting` summary: Final summaries must include behavior change, tests run, and touched files.
- `Reporting` action: Docs-only changes: run `./vnew check-md file.md`; no other tests required
                      unless a test explicitly reads those docs. No rebuild is needed unless
                      compiler or core modules changed.
- `Reporting` action: For docs-only, explicitly mention `check-md` in the summary.

## Compiler Slice
Use this for compiler internals and diagnostics work.

- `Top Rules` summary: Use `./v` only to build `./vnew`; use `./vnew` for all other tasks.
- `Top Rules` action: Use `./v` only to build `./vnew`; use `./vnew` for everything else.
- `Top Rules` action: Put all V flags immediately after `./vnew` and before the subcommand/file,
                      e.g. `./vnew -g run file.v` (not `./vnew run file.v -g`); flags after the
                      subcommand are passed to that subcommand.
- `When to Escalate to Broad` summary: Escalate for multi-owner high-risk changes, diagnostics
                                       changes, REPL changes, or fallback matches.
- `When to Escalate to Broad` action: Commands omit `./vnew` for brevity; assume the `./vnew`
                                      prefix.
- `Build & Rebuild` summary: Rebuild `./vnew` after compiler/core changes with `./v -g -keepc -o
                             ./vnew cmd/v`.
- `Build & Rebuild` action: Build `./vnew` (debug-friendly, recommended for agent workflows): `./v
                            -g -keepc -o ./vnew cmd/v`
- `Build & Rebuild` action: Never run `./v self` directly; only build `./vnew` with the commands
                            above.
- `Testing` summary: Start from the smallest relevant tests and escalate when change scope or
                     triggers require it.
- `Testing` action: File (shows test output): `./vnew path/to/file_test.v`.
- `Testing` action: File (test runner report only): `./vnew test path/to/file_test.v`.
- `Compiler Architecture` summary: Compiler pipeline: scanner -> parser -> checker -> transformer ->
                                   markused -> gen.c.
- `Error Reporting (checker/parser)` summary: Use checker diagnostics helpers (`c.error`, `c.warn`,
                                              `c.note`) with source positions.

## Docs Slice
Use this for docs-only edits and reporting requirements.

- `Top Rules` summary: Use `./v` only to build `./vnew`; use `./vnew` for all other tasks.
- `Top Rules` action: Use `./v` only to build `./vnew`; use `./vnew` for everything else.
- `Top Rules` action: Put all V flags immediately after `./vnew` and before the subcommand/file,
                      e.g. `./vnew -g run file.v` (not `./vnew run file.v -g`); flags after the
                      subcommand are passed to that subcommand.
- `Agent Rules` summary: Keep scope tight; ask before wide refactors or major behavior changes.
- `Agent Rules` action: Run build, test, and format commands without asking for permission. These
                        are validation steps, not code changes. Only ask about edit scope, not about
                        running `fmt`, targeted tests, or `check-md`.
- `Agent Rules` action: New file checklist: format with `./vnew fmt -w`, add doc comments for any
                        public functions, run `./vnew check-md` for markdown files, and keep
                        Markdown lines <= 100 chars. Add or update tests when introducing a new
                        public API.
- `Code Style` summary: Use minimal comments, keep markdown <=100 chars, and add V doc comments for
                        public APIs.
- `Tools` summary: Use `agent-context`, `fmt`, and `check-md` on touched files before final
                   reporting.
- `Tools` action: Agent execution context: `make agent-context local=1
                  FILES='path/to/changed_file.v'` (builds a compact summary with owner/risk, rebuild
                  need, and minimal tests).
- `Tools` action: Format: `./vnew fmt -w <file>` for touched `.v` and `.vsh` files. Format only
                  touched files unless explicitly asked to reformat broader scope.
- `Reporting` summary: Final summaries must include behavior change, tests run, and touched files.
- `Reporting` action: Docs-only changes: run `./vnew check-md file.md`; no other tests required
                      unless a test explicitly reads those docs. No rebuild is needed unless
                      compiler or core modules changed.
- `Reporting` action: For docs-only, explicitly mention `check-md` in the summary.

## Tools Slice
Use this for `cmd/tools/**` changes and validation.

- `Top Rules` summary: Use `./v` only to build `./vnew`; use `./vnew` for all other tasks.
- `Top Rules` action: Use `./v` only to build `./vnew`; use `./vnew` for everything else.
- `Top Rules` action: Put all V flags immediately after `./vnew` and before the subcommand/file,
                      e.g. `./vnew -g run file.v` (not `./vnew run file.v -g`); flags after the
                      subcommand are passed to that subcommand.
- `Agent Rules` summary: Keep scope tight; ask before wide refactors or major behavior changes.
- `Agent Rules` action: Run build, test, and format commands without asking for permission. These
                        are validation steps, not code changes. Only ask about edit scope, not about
                        running `fmt`, targeted tests, or `check-md`.
- `Agent Rules` action: New file checklist: format with `./vnew fmt -w`, add doc comments for any
                        public functions, run `./vnew check-md` for markdown files, and keep
                        Markdown lines <= 100 chars. Add or update tests when introducing a new
                        public API.
- `Testing` summary: Start from the smallest relevant tests and escalate when change scope or
                     triggers require it.
- `Testing` action: File (shows test output): `./vnew path/to/file_test.v`.
- `Testing` action: File (test runner report only): `./vnew test path/to/file_test.v`.
- `Tools` summary: Use `agent-context`, `fmt`, and `check-md` on touched files before final
                   reporting.
- `Tools` action: Agent execution context: `make agent-context local=1
                  FILES='path/to/changed_file.v'` (builds a compact summary with owner/risk, rebuild
                  need, and minimal tests).
- `Tools` action: Format: `./vnew fmt -w <file>` for touched `.v` and `.vsh` files. Format only
                  touched files unless explicitly asked to reformat broader scope.
- `Reporting` summary: Final summaries must include behavior change, tests run, and touched files.
- `Reporting` action: Docs-only changes: run `./vnew check-md file.md`; no other tests required
                      unless a test explicitly reads those docs. No rebuild is needed unless
                      compiler or core modules changed.
- `Reporting` action: For docs-only, explicitly mention `check-md` in the summary.
