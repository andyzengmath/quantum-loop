# IDEA_REPORT_v51 — what's open after v0.11.1

**Date:** 2026-05-02
**Source:** v0.11.1 closes N43 (parallel-with-dispatch wrap pattern; deferred MEDIUM since v0.8.1); 44 → 45 consecutive LOW G30.
**Branch:** `ql/v0.11.1-bundle` (release tag v0.11.1 — pending)
**Predecessor:** `idea-stage/IDEA_REPORT_v50.md`

## Closed in v0.11.1

| ID | Story | Notes |
|---|---|---|
| **N43 — Parallel-with-dispatch wrap pattern** | US-001 + US-002 | dispatch_with_parallel_poll; bg-process + commit-poll + kill-cascade; opt-in via QL_PARALLEL_POLL=true |
| Race fix (child exits mid-poll) | self-caught at Test 18 | post-poll kill -0 re-check |
| worktree_path forwarding gap | US-003 architect | inline-fixed (optional 4th arg) |
| Trap RETURN overwrite latent risk | US-003 code-reviewer + security convergent | documentation-fixed (invariant comment) |

## Open: v0.11.x backlog (post-N43 close)

| Item | Severity | Path |
|------|----------|------|
| Real-feature dispatch via `--coordinator` | blocked | operator-queued multi-story feature |
| N48 negative-path test | LOW | v0.11.2 candidate (~10 LOC) |
| **test_orchestrator_liveness.sh split (NOW AT threshold)** | LOW | v0.11.2 candidate (~615 LOC; passed 600 threshold this cycle) |
| N47 — branch cleanup | operator | operator-decision-pending |

## v0.11.2 candidates

The autonomous track has 2 NEW small-tier candidates this cycle:

### Path D: N48 negative-path test
- Add Test 10 to `tests/test_coordinator_e2e.sh` where stub coordinator does NOT violate field-ownership.
- Assert `[FIELD-OWNERSHIP] WARN` does NOT appear in stderr.
- Confirms N48 detection is symmetric (no false positives).
- ~10 LOC test addition.

### Path E: test_orchestrator_liveness.sh split
- Architect's threshold (~600 LOC) crossed at v0.11.1 ship state (~615 LOC, 18 tests).
- Natural split: Tests 14a/14c/15 (N46 respawn) + Tests 16/17/18 (N43 parallel-poll) → `test_dispatch_helpers.sh`. Original file keeps Tests 1-13 (poll_orchestrator_commits + wrap_orchestrator_dispatch).
- ~150 LOC code movement; preserve test count.

### Path B: Real-feature dispatch (UNCHANGED)
- Awaits operator-queued real feature.

## v0.11.0 → v0.11.1 → v0.11.x transition

```
v0.11.0 (FIRST --coordinator dispatch dogfood; N48 closure) ✓
v0.11.1 (N43 parallel-with-dispatch wrap; opt-in default OFF) ✓ ← THIS CYCLE
v0.11.2 (operator decides: Path B OR D OR E)
```

## Recurring observations

- **45 consecutive LOW G30 self-validations** (v0.6.5..v0.11.1).
- **Bundle size sequence: ...3-4-4-4-4-4-4-4-4-4-3-4-4.** v0.11.1 = 4 stories.
- **Manual-takeover streak: maintained through v0.11.1** — operator gate at scope-decision; no autonomous deviation.
- **p013 (operator-staged kickoff): 19 applications.** v0.11.1 operator-staged (Path A choice).
- **p014 (composite review trio): 26 review applications. 13 review-gate catches in 26 applications (~50% career hit-rate).** Pattern crossed 50% threshold for first time.
- **p015 (post-cycle 3-agent doc-vs-code audit): 6 applications**, canonized at 2; 25 gaps closed.
- **p016 (dogfood-driven LOW sweep wave): 1 application**, canonized at 1.

## v0.11.x architectural posture

With N43 closed, only one operator-gated MEDIUM remains in the entire backlog:
- **Real-feature dispatch via `--coordinator`** — blocked-on-operator-feature-queue.

The infrastructure is now genuinely complete. v0.11.0 validated dispatch end-to-end via N48 dogfood; v0.11.1 added pre-emptive stuck-agent detection. Any remaining v0.11.x work is either:
- Operator-staged real-feature dispatch (Path B)
- Sub-priority hardening (Paths D + E)

**Next /loop tick (when scheduled): operator decides v0.11.2 path.**
