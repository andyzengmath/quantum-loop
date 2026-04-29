# IDEA_REPORT_v24 — what's open after v0.8.2

**Date:** 2026-04-29
**Source:** v0.8.2 closes the v0.8.1 multi-perspective review findings + lays v0.9.0 N42 prerequisites
**Branch:** `ql/v0.8.2-bundle` (release tag v0.8.2 — pending)
**Predecessor:** `idea-stage/IDEA_REPORT_v23.md`

## Closed in v0.8.2

| ID | Story | Notes |
|---|---|---|
| **CRLF on .sh files** | US-001 | dos2unix + .gitattributes; v0.8.1 review-caught CRITICAL |
| **Test 5 wall-clock flake** | US-003 | Ceiling 6 → 10s; 4th wall-clock-jitter calibration in the v0.7.x→v0.8.x track |
| **Signal-protocol gap (v0.9.0 N42 prereq)** | US-002 | runner_parse_output now recognizes 6 signals; v0.9.0 N42 can wire spawn_coordinator confidently |
| **--coordinator --parallel undefined** | US-004 | Documented as mutually exclusive in agents/coordinator.md; v0.9.0 will enforce at CLI parse |
| **quantum.json dual-writer** | US-004 | Field-ownership boundary documented in agents/coordinator.md |

## Persistent canon

p001-p011 unchanged. p012 (anti-presence-only AC) reinforced — ships the 3rd regression test (signal parser). Defer p013 candidate (multi-layer defect retrospective insight) until empirically proven reusable.

## Still open

### N42 — Real per-wave coordinator dispatch (PRIMARY follow-up; v0.9.0 candidate)

**Status:** unchanged from IDEA_REPORT_v23 — but **prerequisites are now MET.** Architect recommended "replace inner dispatch" approach (~30 LOC delta in the spawn-decision branch) over "replace outer loop" (~150 LOC, defer to v0.10.0). v0.8.2 ships the signal-protocol extension and architectural-debt docs that v0.9.0 will rely on.
**Severity:** HIGH for the architectural goal (breaking the manual-takeover streak; 15 consecutive cycles); LOW for current production stability (legacy single-spawn path still works).
**Path:** v0.9.0 minor-tier — see "v0.9.0 candidate slate" below.

### N43 — Parallel-with-dispatch wrap pattern (vs current post-dispatch)

**Status:** unchanged. Architect recommends deferring to v0.9.1+ after N42 stabilizes. Background-process supervision in shell is fragile on Git Bash; intersects N42's design.
**Severity:** MEDIUM (current wire is reachable but reactive — can't pre-empt a stuck agent).

### N40, N38, copilot rate-limit observability, N41

All unchanged. LOW priority; deferred indefinitely or carried as background tasks.

### N44 — CSV/PIPELINE_REPORT count reconciliation

**Status:** unchanged from IDEA_REPORT_v23. LOW (cosmetic). Investigate during a future housekeeping cycle.

### N45 — External-helper working-tree noise

**Status:** unchanged. Recurring (now observed in v0.8.0, v0.8.1, v0.8.2). LOW (operational hygiene; modifications are usually beneficial). Documenting helper identity is a v0.9.x housekeeping candidate.

### N46 — QL_RESPAWN_CMD respawn-output not re-parsed

**Status:** unchanged from IDEA_REPORT_v23. MEDIUM. Path: v0.9.0 alongside N42 (proper fix: capture respawn output, re-feed through runner_parse_output).

### N47 — branch-cleanup hygiene (NEW)

**Status:** new. Each cycle since v0.7.2 has produced a dedicated bundle branch (`ql/v0.7.X-bundle`, `ql/v0.8.X-bundle`). After squash-merge to master, these branches accumulate locally and remotely. Audit shows 12 local + 12 remote vs target ≤10. Operator-driven decision (destructive — `git branch -D` and `git push --delete origin <branch>`).
**Severity:** LOW (purely hygiene; doesn't affect production behavior).
**Path:** v0.8.x retrospective housekeeping cycle, OR per-cycle cleanup once an N+2 release ships (e.g., delete v0.8.0 bundles when v0.8.2 ships). Operator's choice.

## Recommendation for next

**v0.9.0 candidate slate (minor-tier — first architectural work since v0.8.0; first cycle to actually try to break the manual-takeover streak):**

| Story | Content |
|-------|---------|
| US-001 | N42a — Plumb COORDINATOR_MODE=true to invoke `spawn_coordinator` at the dispatch decision point in quantum-loop.sh (~line 1497, "replace inner dispatch" approach). Architect-recommended scope (~30 LOC). |
| US-002 | DAG + wave-eligibility logic (`lib/dag-query.sh::next_wave` if not already defined) — reads quantum.json, determines stories eligible for the next wave, hands story IDs to spawn_coordinator. |
| US-003 | Coordinator output capture: re-feed coordinator stdout through `runner_parse_output` so `WAVE_PASSED`/`WAVE_FAILED` (now recognized post-v0.8.2) drive the case statement; map to story-status updates per the field-ownership contract from v0.8.2 US-004. |
| US-004 | CLI guard: enforce `--coordinator --parallel` mutually-exclusive at parse time per v0.8.2 US-004 doc. |
| US-005 | Real-fire integration tests for the wave-driven inner dispatch (NOT presence-only — actually invoke `quantum-loop.sh --coordinator` against a 2-story stub plan and assert per-wave behavior including signal recognition). |
| US-006 | Retrospective + IDEA_REPORT_v25 + version bump 0.8.2 → 0.9.0 |

**Backward compatibility:** `--legacy-orchestrator` continues to be the default for v0.9.0; per-wave dispatch is opt-in via `--coordinator`. Promote default only after ≥3 cycles validate the coordinator path.

**Honest risk for v0.9.0:** the inner-dispatch replacement is the architect's preferred scope (~30 LOC) but the architect also flagged that `--coordinator --parallel` rejection is policy that v0.9.0 must enforce. If the integration test (US-005) reveals that even the 30-LOC delta has an unexpected interaction (e.g., quantum.json mutation race during coordinator execution), the cycle may need US-007 or grow scope. Plan US-005 to be the bottom-up integration smoke; defer scope-grow to v0.9.1 if uncovered late.

## Recurring observations

- **18 consecutive LOW G30 self-validations** (v0.6.5..v0.8.2). The rubric continues to correctly identify cosmetic vs sensitive changes.
- **Bundle size: 7-7-7-7-5-6-5-3-7-3-2-4-3-3-7-7-5-5.** v0.8.1 + v0.8.2 are paired 5-story patches (validation found defects → reactive fix → docs). v0.8.0 was the architectural minor; v0.9.0 will be the next.
- **Manual-takeover streak: 15 consecutive cycles.** v0.9.0 N42 is the explicit target for breaking this. v0.8.2 just laid the prerequisites.
- **Three-layered defect** (N33 root cause #1) closed across v0.7.x → v0.8.0 → v0.8.1 → v0.8.2. Each layer caught by a different validation pattern. The operator-confirmed lesson: ACs that say "verifiable via grep" must specify *what* the grep should find — definition, caller, signal consumer, or all three.
- **First cycle where every story passes first-attempt 5-in-a-row.** All 5 v0.8.2 stories shipped with 0 retries. Clean reactive cycle.

## v0.8.x track close (provisional)

v0.8.x is structurally complete: v0.8.0 architectural minor, v0.8.1 validation patch, v0.8.2 reactive review-fix patch. v0.9.0 N42 should be the next minor cycle. If v0.9.0 surfaces unexpected scope, v0.8.3 reactive remains an option but operator should default to v0.9.0 cadence.
