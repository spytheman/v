<!-- generated: canonical source is AGENTS.md; run ./cmd/tools/agents/sync_agent_docs.vsh -->
- Canonical source: `AGENTS.md`
- Drift policy: update `AGENTS.md` first, then run `./cmd/tools/agents/sync_agent_docs.vsh`.
If anything here differs from `AGENTS.md`, follow `AGENTS.md` and treat this file as stale.

# Agent Bugfix Playbook

Fast paths for common bugfix tasks in this repository.

## Baseline

```bash
git status
./cmd/tools/agents/bootstrap_check.vsh
./v -g -keepc -o ./vnew cmd/v
```

Use `./vnew` for all commands after bootstrap.

## Triage Loop

1. Reproduce with the smallest failing file or test runner.
2. Change only the minimal files needed.
3. Rebuild `./vnew` when compiler/core triggers apply.
4. Run targeted tests first, then widen only if needed.
5. Report behavior change, tests run, touched files.

## Subsystem Troubleshooting Index

| Subsystem | Typical symptoms | First commands | Target runtime |
| --- | --- | --- | --- |
| Parser (`vlib/v/parser/**`) | Unexpected parse errors, changed token handling | `./vnew -silent test vlib/v/parser/` | ~20s |
| Checker (`vlib/v/checker/**`) | Type resolution regressions, wrong diagnostics | `./vnew -silent test vlib/v/checker/` | ~20s |
| C codegen (`vlib/v/gen/c/**`) | Invalid/generated C mismatch, backend crashes | `./vnew -silent vlib/v/gen/c/coutput_test.v` | ~90s |
| Diagnostics (`vlib/v/slow_tests/inout/**`) | Error text/order formatting drift | `./vnew -silent vlib/v/slow_tests/inout/compiler_test.v` | ~30s |
| REPL (`vlib/v/slow_tests/repl/**`) | Prompt/result mismatches, transcript drift | `./vnew -silent vlib/v/slow_tests/repl/repl_test.v` | ~40s |
| Tools (`cmd/tools/**`) | CLI output/regression in tool behavior | `./vnew -silent test cmd/tools/` | ~20-240s |

Use matrix-derived suggestions for current changes:

```bash
./cmd/tools/agents/suggest_tests.vsh --tier targeted --explain-match
```

Known flaky commands are tracked in `cmd/tools/agents/flaky_tests.yaml`.
If a command is marked flaky, keep it in the run but call out flakiness in the summary.
For quick subsystem orientation, check:
`vlib/v/parser/AGENT_HINTS.md`, `vlib/v/checker/AGENT_HINTS.md`,
`vlib/v/gen/c/AGENT_HINTS.md`, `vlib/v/comptime/AGENT_HINTS.md`,
`cmd/tools/vfmt.AGENT_HINTS.md`, `vlib/os/AGENT_HINTS.md`,
`vlib/strings/AGENT_HINTS.md`, `vlib/strconv/AGENT_HINTS.md`,
`vlib/time/AGENT_HINTS.md`.

## Quick Mappings

### Parser regressions (`vlib/v/parser/**`)

```bash
./v -g -keepc -o ./vnew cmd/v
./vnew -silent test vlib/v/parser/
./vnew -silent vlib/v/compiler_errors_test.v
```

### Checker regressions (`vlib/v/checker/**`)

```bash
./v -g -keepc -o ./vnew cmd/v
./vnew -silent test vlib/v/checker/
./vnew -silent vlib/v/compiler_errors_test.v
```

### C codegen regressions (`vlib/v/gen/c/**`)

```bash
./v -g -keepc -o ./vnew cmd/v
./vnew -silent vlib/v/gen/c/coutput_test.v
./vnew -silent vlib/v/compiler_errors_test.v
```

### Diagnostic text/output changes

```bash
./v -g -keepc -o ./vnew cmd/v
./vnew -silent vlib/v/slow_tests/inout/compiler_test.v
```

### REPL regressions

```bash
./v -g -keepc -o ./vnew cmd/v
./vnew -silent vlib/v/slow_tests/repl/repl_test.v
```

### Tool changes (`cmd/tools/**`)

```bash
./vnew -silent test cmd/tools/
```

For `vdoc`-specific changes:

```bash
./vnew -silent cmd/tools/vdoc/vdoc_test.v
./vnew -silent cmd/tools/vdoc/vdoc_file_test.v
```

## Use the Matrix Helper

Get suggested tests from changed files:

```bash
./cmd/tools/agents/suggest_tests.vsh --tier targeted
```

Fail if any changed path has no rule:

```bash
./cmd/tools/agents/suggest_tests.vsh --strict-unmatched --tier targeted
```

Fail if any changed path uses the fallback rule:

```bash
./cmd/tools/agents/suggest_tests.vsh --require-non-fallback --tier targeted
```

Run suggestions end to end:

```bash
make agent-run ARGS='--tier targeted'
```

## Notes

- Do not update `.out` files unless behavior change is intentional.
- If behavior changed, update docs that expose user-facing output/API.
- Use `./vnew check-md` for touched markdown files.
