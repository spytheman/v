<!-- generated: canonical source is AGENTS.md; run ./scripts/agent/sync_agent_docs.vsh -->
- Canonical source: `AGENTS.md`
- Drift policy: update `AGENTS.md` first, then run `./scripts/agent/sync_agent_docs.vsh`.
If anything here differs from `AGENTS.md`, follow `AGENTS.md` and treat this file as stale.

# Agent Workflow

Practical workflow for AI agents working in this repository.

## Goals

- Use the smallest safe change set.
- Run the smallest relevant validation set.
- Keep reporting deterministic and reproducible.

## One Command

```bash
make agent-run ARGS='--tier targeted'
```

This runs bootstrap checks, fails on unmatched paths, and executes suggested
commands. It also fails on fallback matches, validates the run-summary schema,
and writes a JSON artifact to
`/tmp/agent_run_summary.json` (override with `AGENT_ARTIFACT=...`).

## Preflight

Run fast bootstrap + contract + smoke checks:

```bash
make agent-preflight VEXE=./vnew
```

Deterministic local/CI parity smoke target:

```bash
make agent-smoke VEXE=./vnew local=1
```

One-shot local diagnostics with actionable fixes:

```bash
make agent-doctor
```

## Bootstrap

```bash
git status
./scripts/agent/bootstrap_check.vsh
./v -g -keepc -o ./vnew cmd/v
```

Use `./vnew` for build, test, and formatting commands after bootstrap.

## Suggest Tests

Use the matrix-driven suggester:

```bash
./scripts/agent/suggest_tests.vsh --tier targeted
```

### Inputs

- Explicit files:
  `./scripts/agent/suggest_tests.vsh --tier fast vlib/v/parser/parser.v`
- From a base revision:
  `./scripts/agent/suggest_tests.vsh --changed-from origin/master --tier broad`
- JSON output for tool integration:
  `./scripts/agent/suggest_tests.vsh --json --tier targeted`
- Shell command block output:
  `./scripts/agent/suggest_tests.vsh --format sh --tier targeted`
- Large diff guardrails:
  `./scripts/agent/suggest_tests.vsh --max-paths-warn 150 --max-paths-limit 1000`
- Fail on unmatched paths:
  `./scripts/agent/suggest_tests.vsh --strict-unmatched --changed-from origin/master`
- Fail if any file falls back to the catch-all matrix rule:
  `./scripts/agent/suggest_tests.vsh --require-non-fallback --changed-from origin/master`
- Explain exactly which matrix rule pattern matched each changed path:
  `./scripts/agent/suggest_tests.vsh --explain-match --tier targeted`
- Impact-aware expansion (basic ownership map):
  `./scripts/agent/suggest_tests.vsh --impact-mode basic --tier targeted`
- Time-budgeted command selection:
  `./scripts/agent/suggest_tests.vsh --budget-seconds 600 --tier targeted`

Human and JSON outputs include timing telemetry for collection/matching/total durations.
JSON output now also includes `effective_tier`, `risk`, runtime estimates,
`why_selected`, and `why_dropped_by_budget`.

## Validation Targets

- Baseline:
  `make agent-check VEXE=./vnew local=1`
- Agent contract:
  `make agent-contract-check VEXE=./vnew local=1`
- Suggestion helper:
  `make agent-suggest ARGS='--tier targeted'`
- End-to-end:
  `make agent-run ARGS='--tier targeted'`

## Matrix and Contract

- Rule source: `agent_test_matrix.yaml`
- Contract validator: `scripts/agent/validate_agent_contract.vsh`
- Doc sync check: `scripts/agent/sync_agent_docs.vsh --check`
- CI workflow: `.github/workflows/agent_contract_ci.yml`
- CI enforces `--require-non-fallback` for agent-contract smoke coverage.
- Each matrix rule now carries an `owner` hint.
- Test commands are inline objects with numeric `confidence`.
- Known flaky command patterns are tracked in `scripts/agent/flaky_tests.yaml`.
- `cmd/tools/**` now has finer-grained rules for `vtimeout`, `vcomplete`,
  `vvet`, `vcheck-md`, `vpm`, `vcreate`, and `vast` before the generic
  tools fallback.

## Failure Runbook

Use this compact map for common agent-tooling failures.

| Symptom | First command | Expected signal |
| --- | --- | --- |
| Contract check fails | `./scripts/agent/validate_agent_contract.vsh` | `Agent contract validation passed.` |
| Doc sync mismatch | `./scripts/agent/sync_agent_docs.vsh --check` | `Agent docs sync check passed.` |
| Suggestion mismatch/unmatched paths | `./scripts/agent/suggest_tests.vsh --tier targeted --strict-unmatched --explain-match` | no `Unmatched paths` section |
| Fallback rule unexpectedly selected | `./scripts/agent/suggest_tests.vsh --tier targeted --require-non-fallback <paths>` | exits 0 and no fallback warning |
| Summary JSON invalid | `./scripts/agent/validate_agent_run_summary.vsh /tmp/agent_run_summary.json` | schema validation passed |
| Runtime artifact cleanliness failure | `make agent-artifact-clean-check` | exits 0 with no output |
| Full quick parity check | `make agent-smoke VEXE=./vnew local=1` | ends with `Agent smoke passed.` |

## Bugfix Playbook

For common parser/checker/cgen regressions and minimal validation sets, use:
`doc/agent_bugfix_playbook.md`.

## Reporting Template

When summarizing work, include:

1. Behavior change.
2. Tests run (or skipped with reason).
3. Touched files.
