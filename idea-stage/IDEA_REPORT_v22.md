# IDEA_REPORT_v22 — what's open after v0.8.0

**Date:** 2026-04-28
**Source:** Operator-scoped N33 minor-tier closure (5-agent root-cause synthesis)
**Branch:** `ql/v0.8.0-bundle` (release tag v0.8.0)
**Predecessor:** `idea-stage/IDEA_REPORT_v21.md`

## Closed in v0.8.0

| ID | Story | Notes |
|---|---|---|
| **N33** (cluster) | US-001..US-006 | All 5 root causes addressed: (1) recovery wiring, (2) context-window relief via 13 modules, (3) per-wave coordinator pattern, (4) signal protocol unification, (5) worktree-aware polling |

The **N33 cluster** is now structurally addressed. Whether it works end-to-end requires v0.8.1 dogfood validation.

## Persistent canon

p001-p011 unchanged. Source-of-truth: `idea-stage/PIPELINE_REPORT_v7.md` § "codebasePatterns harvested".

## Still open

### N39 — v0.8.1 dogfood validation (PRIMARY follow-up)
**Status:** new. v0.8.0 ships infrastructure; v0.8.1 should run a real cycle through the `--coordinator` flag and confirm:
- Coordinator agent stays within bounded context per wave
- `wrap_orchestrator_dispatch` actually fires when a stub orchestrator drifts
- Worktree-aware polling correctly detects HEAD advances
- No regression in legacy `--legacy-orchestrator` path
**Severity:** HIGH (required to prove v0.8.0 actually fixed the drift).
**Path:** v0.8.1 patch with a small test-bundle dogfooded through `--coordinator`.

### N40 — orchestrator.md further reduction (≤700 lines target)
**Status:** new. v0.8.0 US-003 reduced 1743 → 1007 lines (42%). The PRD AC was ≤700 (60% reduction). Further reduction requires extracting Step 3B (Parallel Execution) which is core logic.
**Severity:** LOW (cosmetic AC compliance; substantive value already delivered).
**Path:** defer indefinitely unless context-window pressure resurfaces.

### N38 — codex CLI flag drift detection automation
**Status:** unchanged from IDEA_REPORT_v21. LOW.

### Copilot rate-limit observability
**Status:** unchanged. LOW (environmental).

## New gaps from v0.8.0 dogfood

### N41 — coordinator.md to orchestrator.md handoff for legacy paths
**Surfaced:** v0.8.0 ships `--coordinator` as opt-in, `--legacy-orchestrator` as default. Operators who want to migrate need a clear migration story. Currently undocumented.
**Severity:** LOW (documentation gap).
**Path:** Track for v0.8.x retrospective; document in `references/` once v0.8.1 dogfood validates the coordinator path.

## Recommendation for next

**v0.8.1 candidate slate (patch-tier follow-up):**

| Story | Content |
|-------|---------|
| US-001 | N39 dogfood validation — small test-bundle (1-2 stories) through `--coordinator` end-to-end |
| US-002 | Capture v0.8.1 dogfood findings (drift caught? recovery fired? worktree-poll accurate?) |
| US-003 | Soliton-driven inline fixes for any v0.8.0 issues surfaced |
| US-004 | Retrospective + IDEA_REPORT_v23 + version bump 0.8.0 → 0.8.1 |

This is the natural validation cycle for v0.8.0's architectural work. Should be a small reactive patch driven by what the dogfood actually finds.

## Recurring observations

- **16 consecutive LOW G30 self-validations** (v0.6.5..v0.8.0).
- **Bundle size: 7-7-7-7-5-6-5-3-7-3-2-4-3-3-7-7.** v0.8.0 is 7-story (substantive, matches the architectural scope).
- **First minor-tier in 8 cycles.** v0.7.0 (G22 calibration first pass) was a thin minor; v0.8.0 (N33 root-cause closure) is a substantive minor with real architectural changes.
- **Manual-takeover continues to be the de-facto execution mode.** 13 consecutive cycles. v0.8.1 will test whether the new infrastructure actually breaks the streak.
- **First MEDIUM findings in 8+ cycles** (3 medium across design/prd/plan). The advisory rubric is responding to substantive scope — healthy signal.
