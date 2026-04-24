# Design: `quantum-loop.sh --audit` flag

**Date:** 2026-04-24
**Status:** Approved
**Approach:** 2 — Per-metric helpers + driver (inline in quantum-loop.sh)

## Overview

A read-only `--audit` flag on `quantum-loop.sh` that prints the five measurement metrics from `idea-stage/IDEA_REPORT.md §6` (local-branch count, remote-branch count, orphan worktree count, README conflict-marker count, CPC-variant file count, test-suite green status) and exits with status 0 when every metric meets its target, 1 otherwise.

IDEA_REPORT §6 lists these metrics as the evidence base for whether the plan's improvements actually worked. A `--audit` flag makes the check routine: anyone can run it post-merge, on a schedule, in CI, or during code review — and get an at-a-glance snapshot of repo hygiene without remembering the individual commands.

Inline in `quantum-loop.sh` following the existing arg-parsing pattern (`--max-iterations`, `--parallel`, etc.). Implemented via a 20-line `do_audit()` driver that dispatches to six `_audit_<metric>()` helper functions. Thresholds overridable via `QL_AUDIT_*` env vars matching the repo's existing env-tunable convention. Output is human-readable with failure drill-down; exit code is machine-actionable.

**Out of scope for v1:** auto-fixing issues, JSON output, multi-repo audit, historical trend tracking.

**User-facing command:** `./quantum-loop.sh --audit` — no other args accepted on this path; combined flags exit 2.

## User Experience

**Invocation:** `./quantum-loop.sh --audit`. Combined with other flags → `Error: --audit is exclusive and takes no other arguments` + exit 2.

**Happy-path output** (all metrics on target):

```
=== Quantum-loop audit ===
branches-local:    1 (target ≤10)      OK
branches-remote:   1 (target ≤10)      OK
orphan-worktrees:  0 (target 0)        OK
readme-conflicts:  0 (target 0)        OK
cpc-files:         0 (target 0)        OK
test-suites:       54/54 passed        OK

Summary: 6/6 metrics on target.
```
Exit code: **0**

**Failure output** (drill-down on offending metrics, caps at first 3 names with `(+N)`):

```
=== Quantum-loop audit ===
branches-local:    1 (target ≤10)      OK
branches-remote:   15 (target ≤10)     FAIL — 5 over
                   └─ stale: ql/old-feat-1, ql/old-feat-2, ql/dead-branch (+2)
orphan-worktrees:  0 (target 0)        OK
readme-conflicts:  0 (target 0)        OK
cpc-files:         2 (target 0)        FAIL
                   └─ files: plugin-CPC-andyz-ZH84K.json, CHANGELOG-CPC-andyz-ZH84K.md
test-suites:       52/54 passed        FAIL — 2 red
                   └─ failing: test_spawn, test_timeout

Summary: 3/6 metrics off target.
```
Exit code: **1**

**Environment overrides** (defaults from IDEA_REPORT §6):
- `QL_AUDIT_BRANCH_MAX=10`
- `QL_AUDIT_ORPHAN_MAX=0`
- `QL_AUDIT_CONFLICT_MAX=0`
- `QL_AUDIT_CPC_MAX=0`
- `QL_AUDIT_TEST_GLOB="tests/test_*.sh"`

**Runtime target:** <5s on a clean repo. Test-suite status grepped from the most-recent `.omc/phase-*-evidence/` dir (cached evidence); audit never re-runs the test suite itself.

**Help integration:** `--audit` listed in `--help` output with a one-line description.

## Data Model

**No persistent state** — the audit is read-only and stateless. No file writes. No `quantum.json` mutations. No side-files.

**In-memory row shape** (emitted by each helper on stdout):

```
<name>|<value>|<target>|<status>|<drill>
```

- `name` — kebab-case metric id
- `value` — numeric count or summary string
- `target` — human-readable target expression
- `status` — `OK` | `FAIL`
- `drill` — comma-separated detail list when `status=FAIL`, empty when `OK`

`do_audit()` collects rows into `AUDIT_RESULTS=()`, iterates twice (render, then tally any-fail for exit code).

**Threshold read-once at driver entry:**

```bash
local BRANCH_MAX="${QL_AUDIT_BRANCH_MAX:-10}"
local ORPHAN_MAX="${QL_AUDIT_ORPHAN_MAX:-0}"
local CONFLICT_MAX="${QL_AUDIT_CONFLICT_MAX:-0}"
local CPC_MAX="${QL_AUDIT_CPC_MAX:-0}"
local TEST_GLOB="${QL_AUDIT_TEST_GLOB:-tests/test_*.sh}"
```

**Test-suite source:** grep over the most-recent `.omc/phase-*-evidence/*.log`. If no evidence dir exists, metric reports `unknown` with status `FAIL`.

**No schema changes.** No new files. Backward compatible — existing flags behave identically.

## Architecture

**File scope:** `quantum-loop.sh` only. No new libs, no deletions, no edits elsewhere.

**Function layout** (added to `quantum-loop.sh`):

| Function | Purpose |
|----------|---------|
| `do_audit()` | Driver (~20 lines). Enforces exclusive-flag guard. Calls helpers in order. Renders rows. Returns exit code. |
| `_audit_branches_local()` | `git branch` minus master/HEAD |
| `_audit_branches_remote()` | `git branch -r` minus master/HEAD |
| `_audit_orphan_worktrees()` | `ls -d .claude/worktrees/agent-*` count |
| `_audit_readme_conflicts()` | `grep -c "^<<<<<<<\|^=======\|^>>>>>>>" README.md` |
| `_audit_cpc_files()` | `find . -maxdepth 3 -name "*-CPC-*"` |
| `_audit_test_suites()` | Grep most-recent `.omc/phase-*-evidence/` for `=== Results:... failed ===` |
| `_audit_format_row()` | Shared output formatter |

**Call graph:**

```
main arg-loop --audit
    ↓
do_audit()
    ↓  (exclusive-flag guard)
    ↓  loop over [helpers] → capture pipe rows
    ↓
_audit_format_row() per row
    ↓
summary line + exit 0 or 1
```

**Test-mode guard** (one sentinel near the top of `quantum-loop.sh`):

```bash
[[ "${QL_AUDIT_TEST_MODE:-0}" == "1" ]] && return 0 2>/dev/null
```

Tests source the script with `QL_AUDIT_TEST_MODE=1` to reach internal helpers without triggering the main arg-loop.

**Error handling:** each helper must succeed under `set -euo pipefail`. Helpers that might return empty wrap in `{ cmd 2>/dev/null ; } || true` — avoid the `grep -c ... || echo 0` anti-pattern (Phase 24 / #38 lesson).

## Edge Cases & Error Handling

| Edge case | Behavior |
|-----------|----------|
| Empty / new repo | All helpers return 0 / OK; test-suites reports `unknown`/FAIL with `no evidence logs found` |
| Missing `git` binary | Git-dependent helpers report `unknown` / FAIL with drill `git unavailable` |
| 10,000+ branches | Drill caps at first 5 names + `(+N more)` |
| `.omc/phase-*-evidence/` with malformed logs | Grep for literal `=== Results:` line; anything else ignored; log-with-no-result-line → 0/0 + `unknown` |
| Running from inside a worktree (`.ql-wt/<story>`) | Print warning (`Warning: running --audit from inside a worktree — metrics are worktree-local`); do not abort |
| `--audit` + another flag | Exit 2 with `Error: --audit is exclusive and takes no other arguments` |
| Shell-injection via `QL_AUDIT_TEST_GLOB` | Validate `^[A-Za-z0-9._/*-]+$` at entry; on mismatch exit 2 |
| Colors / TTY detection | Plain text only — no ANSI |

## Testing Strategy

**Test file:** `tests/test_audit.sh` (matches sibling naming).

**Per-metric unit tests (7):**

| Test | Setup | Assertion |
|------|-------|-----------|
| `_audit_branches_local` clean repo | fresh repo | value=0, status=OK |
| `_audit_branches_local` over threshold | 12 extra branches | value=12, status=FAIL, drill has names |
| `_audit_orphan_worktrees` detects agent-* | `mkdir .claude/worktrees/agent-foo` | value=1, status=FAIL |
| `_audit_readme_conflicts` flags markers | README with `<<<<<<<` | value=3, status=FAIL |
| `_audit_cpc_files` finds CPC variants | touch `plugin-CPC-xyz.json` | value=1, status=FAIL |
| `_audit_test_suites` parses evidence | seeded `.omc/phase-99-evidence/` log | value=1/1 passed, status=OK |
| `_audit_format_row` OK and FAIL shapes | sample pipe rows | matches UX section format exactly |

**Integration test (1):** end-to-end on clean repo — assert exit 0 and each metric name + `OK` in output.

**Negative integration tests (2):**
- `--audit` combined with `--parallel` → exit 2 + clear error
- `--audit` with 12 branches present → exit 1

**Env-override test (1):** seed 12 branches, set `QL_AUDIT_BRANCH_MAX=20`, assert exit 0.

**Coverage target: 11 tests, runtime <3s.** Test harness sources `quantum-loop.sh` with `QL_AUDIT_TEST_MODE=1` for unit tests; integration tests invoke the script normally.

File picked up automatically by existing `for t in tests/test_*.sh` loop.

## Open Questions

None. All design questions resolved during brainstorming.

## Next Steps

Run `/quantum-loop:ql-spec` to generate a formal Product Requirements Document from this design.
