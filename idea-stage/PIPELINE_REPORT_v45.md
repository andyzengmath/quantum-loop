# PIPELINE_REPORT_v45 — v0.10.11 retrospective (N46 closure: respawn output re-parsing)

**Date:** 2026-05-02
**Bundle:** `ql/v0.10.11-bundle` (release tag v0.10.11 — pending push/PR/merge/tag/release)
**Predecessor report:** `idea-stage/PIPELINE_REPORT_v44.md`
**Master parent:** `4c7f0d5` (v0.10.10 ship state)
**Source:** `tasks/prd-v0.10.11-bundle.md` (auto-approved per `/loop` step 4-5; recommended in IDEA_REPORT_v44 as next autonomous candidate per architect's p015 4th-application audit).

## Overview

4-story patch closing **N46** (`QL_RESPAWN_CMD` respawn-output not re-parsed; documented limitation since v0.8.1 / US-006). Code change: ~30 LOC in `lib/orchestrator-liveness.sh` + 3 new tests. **39th consecutive LOW G30 self-validation.**

## The 4 stories

| # | ID | Title | Outcome |
|:-:|---|---|:-:|
| 0 | (cycle setup) | chore: v0.10.11 cycle kickoff (PRD only) | committed at `e73ce59` |
| 1 | US-001 + US-002 | N46 closure (respawn re-parsing in wrap_orchestrator_dispatch) + 3 new tests | first-attempt PASS at `5d86598` |
| 2 | US-003 | 20th p014 review trio (REVISE→SHIP; 2 MEDIUM + 2 LOW inline-fixed) | committed at `855d511` |
| 3 | US-004 | Retrospective + IDEA_REPORT_v45 + version bump 0.10.10 → 0.10.11 | this report |

## US-001 deep-dive: N46 closure

`lib/orchestrator-liveness.sh::wrap_orchestrator_dispatch` (around lines 122-150) replaces the previous `bash -c "${QL_RESPAWN_CMD}"; rc=$?` pattern with a tee-and-capture pattern that re-feeds output through `runner_parse_output`:

```bash
# (final form post-review-fixes)
respawn_rc=$(
  set +e
  bash -c "${QL_RESPAWN_CMD}" 2>&1 | tee "$respawn_tmpfile" >&2
  printf '%s' "${PIPESTATUS[0]}"
)
respawn_out=$(cat "$respawn_tmpfile")
if type runner_parse_output >/dev/null 2>&1; then
  : "${RUNNER_HEURISTIC_FALLBACK:=false}"
  runner_parse_output "$respawn_out" "$respawn_rc" "${worktree_path:-.}"
fi
```

**Subshell-isolation rationale:** the production shell runs `set -euo pipefail` (`quantum-loop.sh:2`). A bare `bash -c | tee` pipeline with `pipefail` would abort on respawn rc!=0 BEFORE `PIPESTATUS[0]` could be read, leaking the tmpfile and silently skipping the re-parse — a partial regression from pre-patch behavior. The subshell `set +e` isolates errexit locally; rc is captured via `printf` to subshell stdout = `$()` capture into respawn_rc.

**Defensive default:** `RUNNER_HEURISTIC_FALLBACK` defaults to `false` if unset (production sets it via `runner_load` before reaching here; the default avoids unbound-var abort under `set -u` for standalone callers).

**Tmpfile hardening:** `chmod 600` immediately after `mktemp` (security MEDIUM fix); `trap 'rm -f "$tmpfile"' RETURN` ensures cleanup on abort/SIGTERM.

## Multi-perspective review synthesis (US-003; 20th p014 application)

| Reviewer | Verdict | Score | Key findings |
|---|---|---:|---|
| **Architect** | REVISE → SHIP | 72 → ≥85 | **1 MEDIUM (inline-fixed):** original `bash -c \| tee + PIPESTATUS` pattern aborts under `set -euo pipefail` on respawn rc!=0 (function never reaches PIPESTATUS read). Replaced with subshell `set +e` pattern. **1 LOW (inline-fixed):** added Test 14c — respawn rc!=0 under set -e propagates correctly. |
| **Code-reviewer** | SHIP | 95 | **0 MEDIUM.** **1 LOW (inline-fixed):** trap-based tmpfile cleanup added for SIGTERM safety. Pattern correctness verified empirically; variable scoping clean; quoting safe. Tests deterministic. |
| **Security** | SHIP | 92 | **1 MEDIUM (inline-fixed):** Git Bash `mktemp` creates mode 644 (default umask 0022) — added explicit `chmod 600` to close co-tenant tmpfile-readable window. **1 LOW (inline-fixed):** trap RETURN cleanup. |

**7th p014 catch in 20 applications career; ~35% career hit-rate.** Pattern p014 stable. Convergent finding (architect + security on tmpfile hygiene; architect + code-reviewer on trap cleanup) strengthened confidence. All score-≥85 inline-fixable findings closed in this commit.

## Test-suite delta vs v0.10.10

`tests/test_orchestrator_liveness.sh`: 13 → 16 tests (+3): Test 14a (SIGNAL_RESULT update), Test 14b (SIGNAL_CONFIDENCE update), Test 14c (rc!=0 propagation under set -e), Test 15 (graceful no-runner-parse-output).

Counter ran from 34 → 38 (was 34 pre-patch including 2 sub-asserts each on Tests 12-13).

5 baseline suites green: test_signal_parsing 15/15, test_coordinator_e2e 21/21, test_dag_query 44/44, test_json_atomic 35/35, test_next_wave 18/18 = 133.

## v0.10.11 fixes shipped + deferrals

### Closed

| Finding | Severity | Source | Resolution |
|---|---|---|---|
| N46 — respawn output not re-parsed | MEDIUM | tracked since v0.8.1 / US-006 | US-001 (subshell-isolated tee + runner_parse_output) |
| `set -e` + pipefail abort regression | MEDIUM | US-003 architect | inline-fixed |
| tmpfile mode 644 on Git Bash | MEDIUM | US-003 security | inline-fixed |
| no trap-based tmpfile cleanup | LOW | US-003 architect + code-reviewer + security | inline-fixed |
| no rc!=0 test under set -e | LOW | US-003 architect | inline-fixed (Test 14c) |

### Deferred (unchanged from v0.10.10)

| Finding | Severity | Path |
|---|---|---|
| N43 — Parallel-with-dispatch wrap | MEDIUM | v0.11.x (operator-gated) |
| N48 stub-coordinator test coverage | MEDIUM (sub-threshold) | v0.11.0 dogfood |
| N47 — branch cleanup | operator | operator-decision-pending |
| OSC sequence body residue | LOW | future hardening |
| Retry-After multi-line edge cases | LOW | future hardening |

## G30 self-validation — 39th consecutive LOW

Patch-tier delta: ~30 LOC code change + ~80 LOC tests + retro + version bump. **39 consecutive LOW** (v0.6.5..v0.10.11).

## Manual-takeover streak

v0.10.11 driven via autonomous /loop cron pattern. **Streak: PARTIALLY BROKEN through v0.10.11** — 13 consecutive cycles with 1 operator gate (at v0.10.6 wave plan approval).

## codebasePatterns

p001-p016 carried forward. **17 named patterns canonized** as of v0.10.11. No new pattern additions this cycle.

## Recommendation pointer

See `idea-stage/IDEA_REPORT_v45.md`. With N46 closed, the autonomously-achievable backlog is largely exhausted. **v0.11.0 remains operator-gated** for first `--coordinator` dispatch. Next autonomous candidate: limited pure-housekeeping items (N43 only if architecturally feasible without operator presence — which review found it is NOT; OSC body strip + Retry-After multi-line are sub-priority). Possible idle-tick scenario.
