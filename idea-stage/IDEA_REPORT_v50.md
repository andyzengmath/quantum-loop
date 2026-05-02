# IDEA_REPORT_v50 — what's open after v0.11.0

**Date:** 2026-05-02
**Source:** v0.11.0 closes N48 stub-coordinator test coverage via FIRST `--coordinator` dispatch on live repo since v0.9.0 N42 wires; 43 → 44 consecutive LOW G30.
**Branch:** `ql/v0.11.0-bundle` (release tag v0.11.0 — pending)
**Predecessor:** `idea-stage/IDEA_REPORT_v49.md`

## Closed in v0.11.0

| ID | Story | Notes |
|---|---|---|
| **N48 stub-coordinator test coverage** | US-001 + US-002 | first `--coordinator` dispatch on live repo; 6/6 sub-asserts PASS first-attempt |
| PRD counter off-by-one | US-003 review | inline-fixed (5→6 new asserts) |

## Milestone reached: v0.11.0 entry

The 15-cycle hardening arc (v0.10.6..v0.10.15) culminated in the FIRST actual `--coordinator` dispatch on the live repo passing all assertions on first attempt. Every infrastructure piece prepared during the arc participated and functioned correctly:
- N42 wires (v0.9.0) — coordinator dispatch path
- coordinator-guard HEAD-snapshot (v0.9.2) — destructive-reset detection
- QL_COORDINATOR_TIMEOUT_S (v0.9.3) — wallclock kill ceiling
- HEAD-guard reset detection (v0.9.5) — parent-side observability
- N48 FIELD-OWNERSHIP WARN (v0.10.8) — field-ownership contract observability
- 7 wave-cycle hardening items (v0.10.6..v0.10.9)

## v0.11.1+ candidates (operator-gated; await operator decision)

### Path A: N43 implementation (parallel-with-dispatch wrap pattern)

**Status:** Operator-gated MEDIUM. Genuinely architectural work.
- Spawn implementer in background.
- Poll commits in foreground.
- Kill implementer on STALE pre-respawn.
- Test under multiple scenarios (Git Bash bg-process fragility known).

**Effort:** ~100-150 LOC. Risk: MEDIUM-HIGH (bg-process supervision).

### Path B: Real-feature dispatch via `--coordinator`

**Status:** Blocked-on-operator-feature-queue. Awaits operator-queued feature with multi-story decomposition appropriate for coordinator dispatch.

**Effort:** Variable (depends on feature scope).

### Path C: Negative-path test for N48

**Status:** LOW (pre-existing gap surfaced in v0.11.0 architect review).
- Add Test 10 where stub coordinator does NOT violate field-ownership; assert WARN does NOT fire.
- Confirms N48 detection is symmetric (no false positives).

**Effort:** ~10 LOC test addition.

## v0.11.x backlog (post-v0.11.0)

| Item | Severity | Path |
|------|----------|------|
| N43 — Parallel-with-dispatch wrap | MEDIUM | v0.11.1 candidate (operator decides scope) |
| N47 — branch cleanup | operator | operator-decision-pending |
| test_orchestrator_liveness.sh split | LOW | defer; trigger at ~600 LOC |
| N48 negative-path test | LOW (new) | v0.11.x or future hardening |

## Recurring observations

- **44 consecutive LOW G30 self-validations** (v0.6.5..v0.11.0).
- **Bundle size sequence: ...3-4-4-4-4-4-4-4-4-4-3-4.** v0.11.0 = 4 stories.
- **Manual-takeover streak: BROKEN at v0.11.0** — operator gate for v0.11.0 entry decision (N48 vs N43 vs real-feature).
- **p013 (operator-staged kickoff): 18 applications.** v0.11.0 is operator-staged (operator approved scope); v0.10.10..v0.10.15 were autonomous-kickoff deviations (do NOT count toward p013).
- **p014 (composite review trio): 25 review applications. 12 review-gate catches in 25 applications (~48% career hit-rate; up from 46% at v0.10.15).**
- **p015 (post-cycle 3-agent doc-vs-code audit): 6 applications**, canonized at 2; 25 gaps closed.
- **p016 (dogfood-driven LOW sweep wave): 1 application**, canonized at 1.

## v0.11.0 → v0.11.x transition

```
v0.10.6..v0.10.15 (15-cycle hardening arc) ✓
v0.11.0 (FIRST --coordinator dispatch dogfood; N48 closure) ✓ ← THIS CYCLE
v0.11.1 (operator decides: N43 OR real-feature OR N48 negative-path)
```

**Operator decision required for v0.11.1.** Recommended path: N43 (architectural; lowest-residual-risk operator-gated MEDIUM); Path C (negative-path) as v0.11.0.1 hotfix if operator wants symmetric N48 coverage immediately.
