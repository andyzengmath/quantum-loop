# PIPELINE_REPORT_v51 — v0.11.1 retrospective (N43 closure: parallel-with-dispatch wrap pattern)

**Date:** 2026-05-02
**Bundle:** `ql/v0.11.1-bundle` (release tag v0.11.1 — pending push/PR/merge/tag/release)
**Predecessor report:** `idea-stage/PIPELINE_REPORT_v50.md`
**Master parent:** `55c0b16` (v0.11.0 ship state)
**Source:** `tasks/prd-v0.11.1-bundle.md` (operator-approved Path A; architectural follow-on to v0.11.0 first-dispatch milestone).

## Overview

4-story patch closing **N43** (parallel-with-dispatch wrap pattern; deferred MEDIUM since v0.8.1; tracked through 8+ IDEA_REPORTs). Adds `dispatch_with_parallel_poll` function: spawns CMD in background, polls commits in foreground via existing `poll_orchestrator_commits`, kills child on STALE detection. Opt-in via `QL_PARALLEL_POLL=true` env var (default OFF for backwards compat on Git Bash). **45th consecutive LOW G30 self-validation.**

## The 4 stories

| # | ID | Title | Outcome |
|:-:|---|---|:-:|
| 0 | (cycle setup) | chore: v0.11.1 cycle kickoff (PRD only) | committed at `efd8085` |
| 1 | US-001 + US-002 | dispatch_with_parallel_poll function + opt-in wire + Tests 16/17/18 | first-attempt PASS at `95a91bc` (race fix discovered + applied during testing) |
| 2 | US-003 | 26th p014 review trio (SHIP; 2 MEDIUM inline-fixed) | committed at `ce2ca3c` |
| 3 | US-004 | Retrospective + IDEA_REPORT_v51 + version bump 0.11.0 → 0.11.1 | this report |

## US-001 + US-002 deep-dive: N43 implementation

**Function added (`lib/orchestrator-liveness.sh::dispatch_with_parallel_poll`):**
- Signature: `dispatch_with_parallel_poll TIMEOUT_SEC INTERVAL_SEC CMD [WORKTREE_PATH]`.
- Spawns `bash -c "$cmd" >"$tmpfile" 2>&1 &`; captures `$!` as child_pid.
- Outer loop while `kill -0 child_pid`: invoke `poll_orchestrator_commits` (blocking up to TIMEOUT_SEC).
  - On commit (return 0): reset base_sha + continue (commit-progress = liveness signal).
  - On STALE (return 1): re-check `kill -0` (race fix; see below); if alive, emit STALE log + kill cascade.
- Kill cascade: SIGTERM → 2s grace → SIGKILL.
- Final `wait child_pid 2>/dev/null` captures rc; `cat tmpfile` emits captured output.

**Wire site:** `lib/iteration-loop.sh:247-253` (legacy non-coordinator dispatch). Gated on `QL_PARALLEL_POLL=true`. Coordinator mode NOT wired (already has `QL_COORDINATOR_TIMEOUT_S` wallclock kill via `timeout(1)`).

**Race fix (discovered via Test 18):**
Initial implementation had a subtle race: child can complete DURING `poll_orchestrator_commits` blocking window. The outer loop's `kill -0` gate only checks before each poll iteration, so a child that exits mid-poll would be incorrectly classified as STALE — leading to spurious STALE log + wasted kill cascade against an already-dead PID.

**Fix:** Added post-poll `kill -0` re-check before STALE log + kill cascade. If child already dead, skip kill and let `wait` capture rc cleanly.

**Smoke results:**
- Clean completion: 1s, rc=0, output captured ✓
- STALE-kill: 5s wallclock (= 2s timeout + 2s SIGTERM grace + ~1s wait overhead), rc=143 (SIGTERM), STALE log emitted ✓
- Commit-progress reset: 4s wallclock, rc=0, "new commit" log + no STALE log ✓

## Multi-perspective review synthesis (US-003; 26th p014 application)

| Reviewer | Verdict | Score | Key findings |
|---|---|---:|---|
| **Architect** | SHIP | 91 | **1 MEDIUM (inline-fixed):** missing `worktree_path` forwarding to `poll_orchestrator_commits` + `git rev-parse`. Currently safe (no worktree caller), but future-proofs against worktree wire site. Added optional 4th arg. |
| **Code-reviewer** | SHIP | 93 | **1 MEDIUM (documentation-fixed):** trap RETURN overwrite latent risk. `wrap_orchestrator_dispatch` and `dispatch_with_parallel_poll` both use trap RETURN; bash REPLACES traps. Currently safe (mutually exclusive call sites). Added explicit non-nesting invariant comment. Convergent finding with security. |
| **Security** | SHIP | 92 | **Same MEDIUM (convergent with code-reviewer):** trap nesting risk; classified as latent + non-active. **1 LOW:** PID reuse theoretical risk (microsecond window; 32k+ PID space; standard Unix pattern). No action. |

**13th p014 catch in 26 applications career; ~50% career hit-rate (climbing).**
Convergent finding (code-reviewer + security on trap nesting) strengthened confidence; both flagged as latent-not-active per current call graph; documentation invariant added.

## Test-suite delta vs v0.11.0

`tests/test_orchestrator_liveness.sh`: 38 → 46 tests (+8 sub-asserts across Tests 16/17/18).
6 baseline suites: 15+27+44+39+18+46 = **189 total** (+8 vs v0.11.0).

## v0.11.1 fixes shipped + deferrals

### Closed

| Finding | Severity | Source | Resolution |
|---|---|---|---|
| **N43 — Parallel-with-dispatch wrap pattern** | MEDIUM (deferred since v0.8.1) | wave plan | US-001 + US-002 |
| Test 18 race: child exits during poll window | MEDIUM (caught during testing) | self-discovered | inline-fixed (post-poll kill -0 re-check) |
| worktree_path forwarding gap | MEDIUM (review caught) | architect | inline-fixed |
| Trap RETURN overwrite latent risk | MEDIUM (review caught) | code-reviewer + security convergent | documentation-fixed (invariant comment) |

### Deferred (unchanged)

| Finding | Severity | Path |
|---|---|---|
| Real-feature dogfood via `--coordinator` | blocked | operator-queued multi-story feature |
| N48 negative-path test | LOW | future hardening |
| N47 — branch cleanup | operator | operator-decision-pending |
| test_orchestrator_liveness.sh split | LOW | defer; trigger ~600 LOC; currently ~605 LOC POST-v0.11.1 (now AT threshold) |

### New (post-v0.11.1)

**test_orchestrator_liveness.sh has crossed 600 LOC threshold** (was ~495 pre-v0.11.1; +120 with Tests 16/17/18 = ~615). Per architect's prior defer note, this is now actionable for v0.11.x.

## G30 self-validation — 45th consecutive LOW

Patch-tier delta: ~70 LOC core code + ~7 LOC wire + ~120 LOC tests + retro + version bump. **45 consecutive LOW** (v0.6.5..v0.11.1).

## Manual-takeover streak

v0.11.1 driven via operator-staged scope (Path A choice from v0.11.0 ship summary). **Streak: maintained through v0.11.1** — operator gate at scope-decision (no autonomous deviation).

## Lessons learned

**Race condition in bg-process supervision:** initial implementation passed clean-completion + STALE-kill smoke tests but failed Test 18 (commit-progress reset). Root cause: blocking nature of `poll_orchestrator_commits` allowed child to exit mid-poll without being detected by the outer loop. Standard pattern for bg-process supervision in shell: re-check liveness at every transition point, not just loop-head. Added to `dispatch_with_parallel_poll` via post-poll `kill -0` check.

**Trap RETURN nesting fragility:** convergent code-reviewer + security finding surfaced an architectural-tier constraint not visible from looking at `dispatch_with_parallel_poll` in isolation. Both functions in `lib/orchestrator-liveness.sh` use trap RETURN for tmpfile cleanup; bash semantics mean the second trap silently replaces the first. Currently safe but documented as invariant for future maintainers. Demonstrates p014's value for cross-cutting concerns visible only in inter-function context.

## codebasePatterns

p001-p016 carried forward. **17 named patterns canonized** as of v0.11.1. No new pattern additions; this cycle exercises existing infrastructure (race-fix idiom + trap-invariant documentation).

## Recommendation pointer

See `idea-stage/IDEA_REPORT_v51.md`. **N43 closed.** Next operator-gated candidate (per IDEA_REPORT_v50:Path B/C):
- **Path B:** Real-feature dispatch via `--coordinator` (operator-queued multi-story feature) — UNCHANGED.
- **Path C:** N48 negative-path test (verify WARN does NOT fire when contract respected) — small, ~10 LOC.
- **NEW: test_orchestrator_liveness.sh split** (~615 LOC; crossed 600 threshold this cycle).

**Operator decision required for v0.11.2.**
