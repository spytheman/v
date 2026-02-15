<!-- generated: canonical source is AGENTS.md; run ./cmd/tools/agents/sync_agent_docs.vsh -->
- Canonical source: `AGENTS.md`
- Drift policy: update `AGENTS.md` first, then run `./cmd/tools/agents/sync_agent_docs.vsh`.
If anything here differs from `AGENTS.md`, follow `AGENTS.md` and treat this file as stale.

# LLMS.md
Fast operating contract for AI agents in this V repo.
This file is a compact execution index, not a second policy source.

## Quick Scan
- Canonical source: `AGENTS.md`
- Read gate: `Top Rules`, `Build & Rebuild`, `Testing`, `Reporting`
- Bootstrap: `git status` -> build `./vnew` -> use `./vnew` only
- Safety: never overwrite `./v`; never run `./v self` without `-o`
- Done means: change done, checks run, tests run/justified, summary complete

## Canonical Sources and Precedence
1. Source of truth: `AGENTS.md`
2. Test selection details: `TESTS.md`
3. Contribution workflow: `CONTRIBUTING.md`
If anything here differs from `AGENTS.md`, follow `AGENTS.md` and treat this file as stale.

## Mandatory Read Gate
Read these `AGENTS.md` sections before editing:
1. `Top Rules`
2. `Build & Rebuild`
3. `Testing`
4. `Reporting`
If time is tight, read those four sections only, then proceed.

## Purpose and Size Budget
Use `LLMS.md` for low-context startup. Keep only:
- Stable invariants that rarely change
- A minimal execution loop
- High-risk safety constraints
- Pointers to canonical sections for details
Do not copy long or fast-changing policy from `AGENTS.md`.
Target size: about 120 lines; if this file grows, move detail back to `AGENTS.md`.

## 30-Second Bootstrap
Run from repo root:
1. `git status`
2. If `./v` is missing: `make`
3. Build compiler: `./v -g -keepc -o ./vnew cmd/v`
4. Use `./vnew` for all subsequent work

Flag placement is strict:
- Correct: `./vnew -g run file.v`
- Wrong: `./vnew run file.v -g`

## Non-Negotiable Invariants
- Never overwrite the working `./v` binary
- Never run `./v self` without `-o`
- Use `./v` only to build `./vnew`; use `./vnew` for everything else
- Do not edit unrelated files
- Do not touch `thirdparty/` unless explicitly requested
- Ask before touching `ci/` or `Dockerfile*`

## Ask-First Gates
If uncertain, ask instead of guessing.

| Situation | Ask first? |
| --- | --- |
| >5 files or multiple root dirs (`cmd/`, `vlib/`, `doc/`, `examples/`) | Yes |
| Large user-visible behavior change | Yes |
| Running `./vnew test-all` without explicit request | Yes |
| Unclear whether change is "large" | Yes |

## Minimal Execution Loop
1. Confirm repo state with `git status`
2. Make the smallest change set that solves the request
3. Rebuild `./vnew` only if rebuild triggers apply
4. Format touched files and run markdown checks for touched docs
5. Run the smallest relevant tests for changed scope
6. Report behavior change, tests run, and touched files
For edge cases, defer to `AGENTS.md` `Build & Rebuild`, `Testing`, and `Reporting`.

## Rebuild and Validation Contract
Rebuild `./vnew` after changes in:
- `vlib/v/`
- `cmd/v/`
- Core modules: `builtin`, `strings`, `os`, `strconv`, `time`
Rebuild command: `./v -g -keepc -o ./vnew cmd/v`

Validation contract:
- Start with smallest relevant tests
- Escalate only when change scope requires broader coverage
- Use `AGENTS.md` `Testing` for trigger-specific commands

## Formatting and Reporting Contract
- Format touched `.v` and `.vsh`: `./vnew fmt -w <file>`
- Check touched markdown: `./vnew check-md <file.md>`
- Keep markdown lines at or below 100 chars
- Add doc comments for new or modified public functions and methods
- Do not update `.out` files unless behavior change is intentional

For substantial work, report in this order:
`Behavior change` -> `Tests run` -> `Touched files` -> `Unrelated changes`

## Done Criteria
Checklist:
- Requested change is implemented
- Required formatting/checks are run
- Relevant tests are run, or skipped with a reason
- Summary includes behavior change, tests, and touched files

## Anti-Drift Rule
`LLMS.md` must stay small and stable.
Update `AGENTS.md` first when policy changes.
Update this file only when a stable invariant, command, or section pointer changes.
If content starts churning, remove it from `LLMS.md` and keep it only in `AGENTS.md`.

## One-Line Principle
Prefer small, correct, reversible changes with targeted validation.
