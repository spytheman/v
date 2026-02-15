<!-- generated: canonical source is AGENTS.md; run ./cmd/tools/agents/sync_agent_docs.vsh -->
- Canonical source: `AGENTS.md`
- Drift policy: update `AGENTS.md` first, then run `./cmd/tools/agents/sync_agent_docs.vsh`.
If anything here differs from `AGENTS.md`, follow `AGENTS.md` and treat this file as stale.

# Agent Task Slices
Generated from `AGENTS.md` to keep startup context focused by task.

## Bugfix Slice
Use this for parser/checker/cgen/runtime bugfixes.

- `Top Rules`: Use `./v` only to build `./vnew`; use `./vnew` for everything else.
- `Common Workflow`: Before work: `git status`; ensure `./vnew` exists; rebuild if needed. If
                     `./vnew` is missing, see Quick Start or Build & Rebuild.
- `Build & Rebuild`: Initial build (only if `./v` is missing): `make` (Windows: `make.bat`).
- `Testing`: Run:
- `Debug`: See what the C compiler is doing:
- `Reporting`: When a summary is required (see Agent Rules), it must include:

## Compiler Slice
Use this for compiler internals and diagnostics work.

- `Top Rules`: Use `./v` only to build `./vnew`; use `./vnew` for everything else.
- `When to Escalate to Broad`: Use broad validation when one or more of the following is true:
- `Build & Rebuild`: Initial build (only if `./v` is missing): `make` (Windows: `make.bat`).
- `Testing`: Run:
- `Compiler Architecture`: The V compiler has the following stages, orchestrated by the `v.builder`
                           module: `v.scanner` -> `v.parser` -> `v.checker` -> `v.transformer` ->
                           `v.markused` -> `v.gen.c` Their corresponding folders are:
                           vlib/v/scanner, vlib/v/parser, vlib/v/checker, vlib/v/transformer,
                           vlib/v/markused, vlib/v/gen/c . There are additional subsystems
                           (supporting or optional compiler modules) like v.comptime, v.generics,
                           v.pref, v.reflection, v.callgraph, etc.
- `Error Reporting (checker/parser)`: Error: `c.error('message', pos)` - hard error, stops
                                      compilation.

## Docs Slice
Use this for docs-only edits and reporting requirements.

- `Top Rules`: Use `./v` only to build `./vnew`; use `./vnew` for everything else.
- `Agent Rules`: All commands assume the repo root as the working directory. The default location is
                 `/opt/v`, but this may differ in your environment. If a command fails due to
                 missing paths, verify with `pwd` and adjust accordingly. Use a per-command workdir
                 only when a task requires a subdir.
- `Code Style`: Comments: add succinct comments only when code is not self-explanatory. Do not
                delete existing comments unless they are incorrect; you may fix grammar or spelling
                without changing meaning. Add V doc comments right before each new or modified
                public function or method. The V doc comments should start with the name of the fn,
                example: `// the_name does ...`
- `Tools`: Note: if a rule overlaps with Testing, follow Testing.
- `Reporting`: When a summary is required (see Agent Rules), it must include:

## Tools Slice
Use this for `cmd/tools/**` changes and validation.

- `Top Rules`: Use `./v` only to build `./vnew`; use `./vnew` for everything else.
- `Agent Rules`: All commands assume the repo root as the working directory. The default location is
                 `/opt/v`, but this may differ in your environment. If a command fails due to
                 missing paths, verify with `pwd` and adjust accordingly. Use a per-command workdir
                 only when a task requires a subdir.
- `Testing`: Run:
- `Tools`: Note: if a rule overlaps with Testing, follow Testing.
- `Reporting`: When a summary is required (see Agent Rules), it must include:
