# IDEA_REPORT_v26 — what's open after v0.8.4 (final v0.8.x close)

**Date:** 2026-04-29
**Source:** v0.8.4 closes all residual v0.8.3 review findings; v0.8.x track FULLY CLOSED.
**Branch:** `ql/v0.8.4-bundle` (release tag v0.8.4 — pending)
**Predecessor:** `idea-stage/IDEA_REPORT_v25.md`

## Closed in v0.8.4

| ID | Story | Notes |
|---|---|---|
| **PS WAVE_FAILED retry accounting** | US-001 (MEDIUM) | Mirrors bash semantics; closes infinite-retry loop in PS path |
| **PS $storyId defense-in-depth** | US-002 (LOW) | Validates `^[A-Za-z0-9_-]+$` before jq interpolation |
| **lib/spawn.sh source guard** | US-003 (LOW) | `_QL_SPAWN_SH` guard added; comment now accurate |
| **CLAUDE.md/ql-execute SKILL/preamble.md/templates docs** | US-004 (cosmetic) | All 4 sites reference WAVE_* signals with appropriate scoping context |

## v0.8.x track FULLY CLOSED — 5-cycle saga complete

| Cycle | Theme |
|---|---|
| v0.8.0 (e743000, minor) | N33 closure infrastructure |
| v0.8.1 (b1ac946, patch) | Dogfood — wired inert pieces |
| v0.8.2 (1076eef, patch) | Review hotfix — primary signal regex |
| v0.8.3 (a11e5c2, patch) | 4th-layer hotfix — parallel consumer sites |
| v0.8.4 (pending) | Final hotfix — residual polish |

**Zero deferred findings.** All multi-perspective post-merge reviews across v0.8.0 → v0.8.4 are closed.

## Persistent canon

p001-p011 unchanged. **p012 (anti-presence-only AC) is now formalized** as a 5-step checklist (see PIPELINE_REPORT_v26 § codebasePatterns). Validated at 4 layers across 5 cycles.

## Still open

### N42 — Real per-wave coordinator dispatch (v0.9.0 candidate; PRIMARY follow-up)

**Status:** All prerequisites met after v0.8.4. Architect-recommended scope: replace inner dispatch (~30 LOC) > replace outer loop (~150 LOC; defer to v0.10.0).
**Severity:** HIGH for the architectural goal (breaking the manual-takeover streak; 17 consecutive cycles); LOW for production stability (legacy single-spawn path works).
**Path:** v0.9.0 minor-tier — see "v0.9.0 candidate slate" below.

### N43 — Parallel-with-dispatch wrap pattern

**Status:** unchanged. Defer to v0.9.1+ after N42 stabilizes. Background-process supervision in shell is fragile on Git Bash; intersects N42's design.
**Severity:** MEDIUM.

### N40, N38, copilot rate-limit observability, N41, N44, N45, N46, N47

All unchanged. LOW priority. **N47 (branch-cleanup hygiene)** now at 14+ local + 14+ remote bundle branches (v0.7.x..v0.8.4).

## Recommendation for next

**v0.9.0 candidate slate (minor-tier — first architectural work since v0.8.0; first cycle to actually try to break the manual-takeover streak):**

| Story | Content |
|-------|---------|
| US-001 | N42a — Plumb COORDINATOR_MODE=true to invoke `spawn_coordinator` at the dispatch decision point in quantum-loop.sh (~line 1497). Architect-recommended ~30 LOC delta. |
| US-002 | DAG + wave-eligibility logic — add `lib/dag-query.sh::next_wave` (does not exist; required for v0.9.0). |
| US-003 | Coordinator output capture: re-feed coordinator stdout through `runner_parse_output`; **per-story status aggregation** from coordinator's wave output (replaces v0.8.3's single-story-progressing placeholder). |
| US-004 | CLI guard: enforce `--coordinator --parallel` mutually-exclusive at parse time per v0.8.2 US-004 doc. |
| US-005 | Real-fire integration tests for the wave-driven inner dispatch (NOT presence-only — actually invoke `quantum-loop.sh --coordinator` against a 2-story stub plan and assert per-wave behavior including signal recognition + retry accounting). |
| US-006 | Retrospective + IDEA_REPORT_v27 + version bump 0.8.4 → 0.9.0 |

**Backward compatibility:** `--legacy-orchestrator` continues to be the default for v0.9.0; per-wave dispatch is opt-in via `--coordinator`. Promote default only after ≥3 cycles validate the coordinator path.

**Honest risk for v0.9.0:**
- Inner-dispatch replacement is the architect's preferred scope (~30 LOC) but has interactions: quantum.json mutation race during synchronous coordinator execution; respawn output not re-parsed (N46 intersection); coordinator subagent context bounds.
- Real-fire integration test design (US-005) — must NOT be presence-only; the v0.8.x retrospective has burned that lesson home four times.

## Recurring observations

- **20 consecutive LOW G30 self-validations** (v0.6.5..v0.8.4).
- **Bundle size: 7-7-7-7-5-6-5-3-7-3-2-4-3-3-7-7-5-5-4-4.** v0.8.4 is the smallest patch in the v0.8.x track (4 stories — pure residual polish).
- **N33 anti-pattern fully closed** at 4 layers across 5 cycles; p012 formalized.
- **Manual-takeover streak: 17 consecutive cycles.** v0.9.0 N42 is the explicit empirical break point.
- **Multi-perspective review pattern STANDARDIZED** — 4 cycles validated (post-v0.8.1, post-v0.8.2, post-v0.8.3, post-v0.8.4). Reviewer trio catches one anti-pattern layer per cycle until exhausted; v0.8.4's review confirmed exhaustion (no 5th layer).

## v0.8.x track close (FINAL)

**v0.8.x is structurally + functionally complete with ZERO deferred findings.** v0.9.0 N42 should be the next minor cycle. The cycle is bounded (~30 LOC inner-dispatch replacement + 5 supporting stories + 1 housekeeping). All prerequisites verified.

Operator should scope v0.9.0 N42 explicitly. Patch-tier reactive loop should remain stopped until v0.9.0 ships and a new dogfood cycle (v0.9.1) emerges.
