# IDEA_REPORT_v25 — what's open after v0.8.3

**Date:** 2026-04-29
**Source:** Multi-perspective post-v0.8.2 review found the 4th layer of the N33 anti-pattern; v0.8.3 closes it
**Branch:** `ql/v0.8.3-bundle` (release tag v0.8.3 — pending)
**Predecessor:** `idea-stage/IDEA_REPORT_v24.md`

## Closed in v0.8.3

| ID | Story | Notes |
|---|---|---|
| **N33 root-cause #1 (4th layer)** | US-001 + US-002 + US-003 | All parallel signal-wire sites closed: signal-heuristics regex + case switch + source gate + PowerShell mirror + test tightening |
| **`lib/signal-heuristics.sh` regex gap** | US-001 (HIGH from v0.8.2 review) | extended to 6 signals |
| **`quantum-loop.sh` case switch missing WAVE_***  | US-001 (HIGH from architect) | explicit branches added |
| **`lib/spawn.sh` source gate scoped only to PARALLEL** | US-001 (MEDIUM from architect) | extended to COORDINATOR_MODE |
| **PowerShell parity** | US-002 (MEDIUM from code-reviewer) | quantum-loop.ps1 mirrored |
| **Trivially-passing negative tests** | US-003 (LOW from code-reviewer) | non-exact-confidence guards added |

The **N33 cluster is now FULLY CLOSED across all 4 anti-pattern layers.** v0.9.0 N42 prerequisites are genuinely complete; no further parallel wire sites have been discovered after the multi-perspective review.

## Persistent canon

p001-p011 unchanged. p012 (anti-presence-only AC) reinforced at 4 layers — strongest pattern in the codebase. Defer p013 candidate (multi-cycle layered-defect retrospective insight) until empirically proven reusable across an architectural cycle.

## Still open

### N42 — Real per-wave coordinator dispatch (PRIMARY follow-up; v0.9.0 candidate)

**Status:** unchanged from IDEA_REPORT_v24 — but **prerequisites are now FULLY MET.** All 4 layers of the N33 anti-pattern closed. Architect-recommended scope: replace inner dispatch (~30 LOC) > replace outer loop (~150 LOC; defer to v0.10.0).
**Severity:** HIGH for the architectural goal (breaking the manual-takeover streak; 16 consecutive cycles); LOW for current production stability (legacy single-spawn path still works).
**Path:** v0.9.0 minor-tier — see "v0.9.0 candidate slate" below.

### N43 — Parallel-with-dispatch wrap pattern (vs current post-dispatch)

**Status:** unchanged. Architect recommends deferring to v0.9.1+ after N42 stabilizes.
**Severity:** MEDIUM.

### N40, N38, copilot rate-limit observability, N41, N44, N45, N46, N47

All unchanged from IDEA_REPORT_v24. LOW priority; deferred indefinitely or carried as background tasks. **N47 (branch-cleanup hygiene)** is now operator-decision-pending at 13+ local + 13+ remote bundle branches.

## Recommendation for next

**v0.9.0 candidate slate (minor-tier — first architectural work since v0.8.0):**

| Story | Content |
|-------|---------|
| US-001 | N42a — Replace inner dispatch when COORDINATOR_MODE=true: invoke `spawn_coordinator wave_id story_ids prd_path quantum_path` instead of the per-iteration single-spawn (`claude --print` or `eval "$RUNNER_CMD"`). Architect-recommended ~30 LOC delta in the dispatch decision branch (`quantum-loop.sh:1496-1510`). |
| US-002 | DAG + wave-eligibility logic. If `lib/dag-query.sh::next_wave` doesn't exist, add it (read quantum.json, return parallel-safe story IDs whose `dependsOn` are all `passed`). v0.8.3 already wired the source gate so the function is loadable under COORDINATOR_MODE. |
| US-003 | Coordinator output capture: re-feed coordinator stdout through `runner_parse_output` so WAVE_PASSED/WAVE_FAILED (now recognized end-to-end post-v0.8.3) drive the case statement; map to story-status updates per the field-ownership contract from v0.8.2 US-004. |
| US-004 | CLI guard: enforce `--coordinator --parallel` mutually-exclusive at parse time per v0.8.2 US-004 doc. Exit with explicit error message. |
| US-005 | Real-fire integration tests for the wave-driven inner dispatch. NOT presence-only — actually invoke `quantum-loop.sh --coordinator` against a 2-story stub plan and assert per-wave behavior including signal recognition + retry accounting. |
| US-006 | Retrospective + IDEA_REPORT_v26 + version bump 0.8.3 → 0.9.0 |

**Backward compatibility:** `--legacy-orchestrator` continues to be the default for v0.9.0; per-wave dispatch is opt-in via `--coordinator`. Promote default only after ≥3 cycles validate the coordinator path.

**Honest risk for v0.9.0:** the inner-dispatch replacement is the architect's preferred scope (~30 LOC) but has interactions:
- Quantum.json mutation race during synchronous coordinator execution (architect-flagged, mitigated by sequential dispatch).
- Coordinator subagent context bounds — the agent definition currently has 80→118 lines (v0.8.2 added 38 lines of policy docs); should be re-checked for v0.9.0 to ensure context budget remains reasonable.
- Real-fire integration test design (US-005) — must NOT be presence-only; the v0.8.3 retrospective has burned that lesson home.

## Recurring observations

- **19 consecutive LOW G30 self-validations** (v0.6.5..v0.8.3).
- **Bundle size: 7-7-7-7-5-6-5-3-7-3-2-4-3-3-7-7-5-5-4.** v0.8.2 was 5-story; v0.8.3 is 4-story (smallest in the v0.8.x track). Pure reactive hotfix.
- **N33 anti-pattern layered closure: 4 layers across v0.8.0 → v0.8.3.** Each cycle's review surfaced one more parallel site. After v0.8.3, no more parallel sites discovered.
- **Manual-takeover streak: 16 consecutive cycles.** v0.9.0 N42 is the explicit empirical break point.
- **First cycle where the multi-perspective review is now a STANDARD post-merge step**, not an ad-hoc one. v0.8.1, v0.8.2, v0.8.3 all surfaced findings via the architect/code-reviewer/security trio. Strong validation pattern.

## v0.8.x track close (final)

**v0.8.x is now structurally + functionally complete:**
- v0.8.0 architectural minor (N33 cluster infrastructure)
- v0.8.1 validation patch (dogfood found 2 inert pieces; wired them)
- v0.8.2 review-fix patch (fixed primary signal regex + CRLF + ceilings + docs)
- v0.8.3 4th-layer closure patch (closed parallel signal-wire sites)

v0.9.0 N42 is the next minor cycle and the first cycle to actually try to break the manual-takeover streak. All prerequisites are met.
