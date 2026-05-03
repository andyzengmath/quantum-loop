# IDEA_REPORT_v53 — what's open after v0.11.3

**Date:** 2026-05-03
**Source:** v0.11.3 closes copilot-hooks::post_output coverage gap (MEDIUM from comprehensive review) + filters 1 false positive (build_coordinator_prompt already covered); 46 → 47 consecutive LOW G30.
**Branch:** `ql/v0.11.3-bundle` (release tag v0.11.3 — pending)
**Predecessor:** `idea-stage/IDEA_REPORT_v52.md`

## Closed in v0.11.3

| ID | Story | Notes |
|---|---|---|
| copilot-hooks::post_output coverage | US-001 | NEW tests/test_copilot_hooks.sh; 11 tests; all 5 regex patterns + 4 Retry-After cases + 2 negative |
| build_coordinator_prompt content (false positive) | US-001 filter | Already covered at test_coordinator_dispatch.sh:99-106 Test 7; documented for future-audit calibration |

## Comprehensive-review backlog status

Of 6 findings surfaced post-v0.11.1:
- v0.11.2 closed 5 (1 N48 negative-path + 4 CLAUDE.md doc gaps).
- v0.11.3 closed 1 (copilot-hooks coverage) + filtered 1 (build_coordinator_prompt false positive).
- **Comprehensive review backlog: 6/6 disposed** (5 closed, 1 filtered).

## Open: v0.11.x backlog (post-v0.11.3)

### Operator-decision items

| Item | Severity | Path |
|------|----------|------|
| **Path B: Real-feature dispatch via `--coordinator`** | blocked | operator-queued multi-story feature |
| **Pre-Path-B: field-ownership WARN→FAIL escalation policy** | operator-decision | architectural; pre-real-feature decision |
| N47 — branch cleanup | operator | operator-decision-pending |

### Autonomously-achievable backlog (v0.11.4 candidates)

| Item | Severity | Effort |
|------|----------|--------|
| `emit_terminal_signal` direct test coverage | MEDIUM (architect's comprehensive-review flag; called from 5 sites; zero direct tests) | ~80 LOC fixture-driven tests |
| Path E: test_orchestrator_liveness.sh split (~615 LOC at threshold) | LOW | ~150 LOC code movement |
| Single-quote fragility in test_copilot_hooks.sh (convergent v0.11.3 review LOW) | LOW | ~5 LOC; positional-arg pattern |

### Architectural debt (deferred)

| Item | Severity | Path |
|------|----------|------|
| `run_iteration_loop` 471-LOC decomposition | HIGH structural | future architectural cycle (high regression risk) |
| `run_parallel_mode` 379-LOC decomposition | MEDIUM | future |

## v0.11.4 recommendation

**Recommended autonomous path:** v0.11.4 = `emit_terminal_signal` direct test coverage. This is the last MEDIUM-severity coverage gap from the comprehensive review, called from 5 sites across `iteration-loop.sh` and `parallel-mode.sh`. A formatting regression would silently break parent-agent signal parsing.

**Alternative:** hold for Path B (operator-queued real feature). Pre-Path-B field-ownership escalation policy decision should happen first.

**Bundle scope option for v0.11.4:** combine `emit_terminal_signal` test (US-001) + Path E test file split (US-002) + 29th p014 review + retro = 4 stories. The two work items don't conflict; both are test-tier work in the same review surface.

## Recurring observations

- **47 consecutive LOW G30 self-validations** (v0.6.5..v0.11.3).
- **Bundle size sequence: ...3-4-4-4-4-4-4-4-4-4-3-4-4-4-4-3.** v0.11.3 = 3 stories (scope reduced via false-positive filter; v0.11.2 was 4).
- **Manual-takeover streak: maintained through v0.11.3** — operator gate at scope-decision per cycle.
- **p013 (operator-staged kickoff): 21 applications.** v0.11.3 operator-staged.
- **p014 (composite review trio): 28 review applications. 15 review-gate catches in 28 applications (~54% career hit-rate; up from 52% at v0.11.2).** Pattern climbing past 50% threshold for the 3rd consecutive cycle.
- **p015 (post-cycle 3-agent doc-vs-code audit): 6 applications**, canonized at 2; 25 gaps closed.
- **p016 (dogfood-driven LOW sweep wave): 1 application**, canonized at 1.
- **p017 candidate (comprehensive review at major version boundaries):** 1 application (post-v0.11.1; surfaced 6 findings, 5 real + 1 false positive). Canonization at 2 applications per established convention.

## v0.11.3 → v0.11.x transition

```
v0.11.0 (FIRST --coordinator dispatch dogfood; N48 closure) ✓
v0.11.1 (N43 parallel-with-dispatch wrap pattern; opt-in) ✓
v0.11.2 (D-medium: N48 symmetry + CLAUDE.md docs from comprehensive review) ✓
v0.11.3 (copilot-hooks::post_output coverage; comprehensive-review backlog 6/6 disposed) ✓ ← THIS CYCLE
v0.11.4 (operator decides: emit_terminal_signal coverage + Path E split, OR Path B real-feature, OR pre-Path-B policy)
```

**Operator decision required for v0.11.4 path.**
