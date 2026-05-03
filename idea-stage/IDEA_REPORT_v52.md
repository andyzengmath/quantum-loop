# IDEA_REPORT_v52 — what's open after v0.11.2

**Date:** 2026-05-02
**Source:** v0.11.2 closes 5 findings from post-v0.11.1 comprehensive review (D-medium scope: N48 negative-path + CLAUDE.md doc updates); 45 → 46 consecutive LOW G30.
**Branch:** `ql/v0.11.2-bundle` (release tag v0.11.2 — pending)
**Predecessor:** `idea-stage/IDEA_REPORT_v51.md`

## Closed in v0.11.2

| ID | Story | Notes |
|---|---|---|
| N48 negative-path test (Test 10) | US-001 | Symmetric to v0.11.0 Test 9; reuses `passed` stub mode |
| CLAUDE.md line refs stale (HIGH-1) | US-002 edit 1 | iteration-loop.sh:~212/~215 → ~224/~227 |
| QL_PARALLEL_POLL env var undocumented (MEDIUM-1) | US-002 edit 2 | New bullet in Coordinator-related |
| dispatch_with_parallel_poll unreferenced (MEDIUM-2) | US-002 edit 3 | New bullet with signature + race-fix note |
| Trap-RETURN-nesting invariant uncanonized (MEDIUM-3) | US-002 edit 4 | New Platform Notes entry |

## Open: v0.11.x backlog (post-v0.11.2)

### Operator-decision items

| Item | Severity | Path |
|------|----------|------|
| **Path B: Real-feature dispatch via `--coordinator`** | blocked | operator-queued multi-story feature |
| **Pre-Path-B: field-ownership WARN→FAIL escalation policy** | operator-decision | architectural; should v0.10.8 N48 WARN escalate before Path B? |
| N47 — branch cleanup | operator | operator-decision-pending |

### Autonomously-achievable backlog (v0.11.3 candidates)

| Item | Severity | Effort |
|------|----------|--------|
| copilot-hooks::post_output test coverage | MEDIUM (real coverage gap) | ~150 LOC; 6 tests; own cycle |
| build_coordinator_prompt content assertions | LOW-MEDIUM | ~30 LOC; 2-3 tests; could fold with above |
| `emit_terminal_signal` direct test coverage | MEDIUM (called from 5 sites; zero direct tests) | future fixture-driven test cycle |
| Path E: test_orchestrator_liveness.sh split | LOW | ~615 LOC; at threshold but not over critical mass |

### Architectural debt (deferred to future cycles)

| Item | Severity | Path |
|------|----------|------|
| `run_iteration_loop` 471-LOC decomposition | HIGH structural | future architectural cycle (high regression risk) |
| `run_parallel_mode` 379-LOC decomposition | MEDIUM | future |

## v0.11.3 recommendation

If operator wants to continue autonomous progression: **bundle copilot-hooks::post_output coverage + build_coordinator_prompt content assertions** as v0.11.3 (4-5 stories, ~180 LOC). Both are real coverage gaps surfaced by the comprehensive review.

Alternative: hold for Path B (operator-queued real feature).

## Recurring observations

- **46 consecutive LOW G30 self-validations** (v0.6.5..v0.11.2).
- **Bundle size sequence: ...3-4-4-4-4-4-4-4-4-4-3-4-4-4-4.** v0.11.2 = 4 stories.
- **Manual-takeover streak: maintained through v0.11.2** — 2 operator gates this cycle (Path A→D-medium scope choice + scope expansion approval after comprehensive review).
- **p013 (operator-staged kickoff): 20 applications.** v0.11.2 operator-staged.
- **p014 (composite review trio): 27 review applications. 14 review-gate catches in 27 applications (~52% career hit-rate; up from 50% at v0.11.1).** Pattern climbing past 50% threshold.
  - Note: v0.11.2's code-reviewer agent timed out twice; 2-of-3 reviewer coverage with architect+security convergence accepted.
- **p015 (post-cycle 3-agent doc-vs-code audit): 6 applications**, canonized at 2; 25 gaps closed.
- **p016 (dogfood-driven LOW sweep wave): 1 application**, canonized at 1.
- **NEW pattern candidate (post-v0.11.1):** comprehensive review at major version boundaries — see PIPELINE_REPORT_v52 lessons-learned. May warrant canonization as p017 if applied 2+ times.

## v0.11.2 → v0.11.x transition

```
v0.11.0 (FIRST --coordinator dispatch dogfood; N48 closure) ✓
v0.11.1 (N43 parallel-with-dispatch wrap pattern; opt-in) ✓
v0.11.2 (D-medium: N48 symmetry + CLAUDE.md docs from comprehensive review) ✓ ← THIS CYCLE
v0.11.3 (operator decides: Path B real-feature OR copilot-hooks coverage)
```

**Operator decision required for v0.11.3.** Pre-Path-B item (field-ownership escalation policy) should be decided before any operator-queued real feature.
