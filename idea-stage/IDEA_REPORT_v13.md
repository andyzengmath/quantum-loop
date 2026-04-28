# IDEA_REPORT_v13 — what's still open after v0.7.2

**Date:** 2026-04-28
**Source:** `ql/v0.7.2-bundle` dogfood retrospective (US-003)
**Branch:** `ql/v0.7.2-bundle` (release tag v0.7.2)
**Predecessor:** `idea-stage/IDEA_REPORT_v12.md`

## Closed in v0.7.2

| ID | Story | Notes |
|---|---|---|
| **N24** | US-001 | `lib/orchestrator-liveness.sh::wrap_orchestrator_dispatch` QL_RESPAWN_CMD auto-respawn branch. Tests 8+9 (4 new assertions). 18 → 22 liveness tests. |
| **G22 second pass** | US-002 | `references/severity-rubric-calibration-v0.7.2.md` with bundle-tier comparison axis. CLAUDE.md ref updated. |

The **N24 + G22-second-pass cluster** (the v0.7.2 priority list from IDEA_REPORT_v12) is now **fully closed**.

## Persistent canon

p001-p011 unchanged. Source-of-truth: `idea-stage/PIPELINE_REPORT_v7.md` § "codebasePatterns harvested".

## Multi-cycle CSV milestone (24 rows, 57 findings, 8 cycles)

| Cycle | design | prd | plan | total |
|---|---|---|---|---:|
| v0.6.5 | 0/0/0/1 | 0/0/0/4 | 0/0/0/0 | 5 |
| v0.6.6 | 0/0/0/0 | 0/2/4/3 | 0/0/0/1 | 10 |
| v0.6.7 | 0/0/1/2 | 0/0/2/3 | 0/0/0/2 | 10 |
| v0.6.8 | 0/0/1/2 | 0/0/1/2 | 0/0/0/2 | 8 |
| v0.6.9 | 0/0/1/2 | 0/0/1/2 | 0/0/0/2 | 8 |
| v0.7.0 | 0/1/1/1 | 0/0/1/2 | 0/0/0/2 | 8 |
| v0.7.1 | 0/0/0/2 | 0/0/0/1 | 0/0/0/1 | 4 |
| v0.7.2 | 0/0/0/2 | 0/0/0/1 | 0/0/0/1 | 4 |
| **Total** | **0/1/4/12** | **0/2/9/18** | **0/0/0/11** | **57** |

Severity distribution: **0 critical / 3 high / 13 medium / 41 low (0% / 5.3% / 22.8% / 71.9%)**.

Key observations from G22 second calibration pass:
- HIGH under-classification confirmed as **patch-tier-skew**, not rubric miscalibration (minor-tier HIGH 12.5% vs patch-tier 4.1%).
- MEDIUM stable across tiers (~25%) — rubric working as intended.
- plan-review STILL 100% LOW (11/11 rows across 8 cycles).

## Still open after v0.7.2

### G19 / G21 / G24 / P5.B2/B3/B5 / P5.C frontier
**Status:** unchanged from v0.7.0. Defer indefinitely.

## New gaps from v0.7.2 dogfood

### N25 — QL_RESPAWN_CMD not exercised end-to-end in CI
**Surfaced:** N24 ships the auto-respawn branch but tests use `echo respawned` stub. No test exercises a real claude invocation. Future minor-tier cycle could add a smoke-test that verifies the respawn command is a valid CLI invocation form.
**Severity:** LOW (test coverage gap, not a functional bug).
**Path:** Track for a future minor-tier bundle or reactive patch if auto-respawn is adopted by operators.

### N26 — plan-review MEDIUM still not triggered after 8 cycles
**Surfaced:** N18 (v0.7.1) added second MEDIUM example to plan-review rubric. v0.7.1 and v0.7.2 both emitted 1 LOW for plan-review. The example has not surfaced a real MEDIUM across 8 cycles.
**Severity:** LOW (calibration-data observation).
**Path:** Track. A minor-tier cycle with complex multi-wave DAG is the most likely trigger. No rubric action until triggered.

### N27 — G22 third calibration pass needs more minor-tier data
**Surfaced:** G22 second pass had n=1 minor-tier data point. Third calibration pass needs 2-3 minor-tier cycles for statistical comparison.
**Severity:** LOW (calibration-data scarcity).
**Path:** Track for v0.8.0+ retrospective when minor-tier cycles accumulate.

## Recommendation for v0.7.3 or v0.8.0

**v0.7.3 candidate slate (patch-tier):**
The patch-tier backlog is drained again. N25/N26/N27 are observations, not actionable items. A v0.7.3 patch would be purely reactive (soliton finding or operator-discovered issue).

**Suggestion:** Skip v0.7.3 unless a reactive item surfaces. The next substantive cycle is **v0.8.0 minor-tier** with new feature scope (TBD by operator).

**v0.8.0 candidate slate (minor tier):**
1. **New feature** — TBD; would need a feature-driven v0.8.0 PRD authored separately.
2. **G22 third calibration pass** — needs at least 1 more minor-tier data point first (the v0.8.0 release itself would provide that).
3. **QL_RESPAWN_CMD operator docs** — if auto-respawn adoption warrants it.

## Recurring observations

- **8 consecutive LOW-tier self-validations** (v0.6.5..v0.7.2). G30 calibration consistent.
- **6 consecutive manual-takeover cycles** with 0-retry first-attempt PASS. 5-layer recovery infrastructure complete. Auto-respawn requires operator to set QL_RESPAWN_CMD explicitly — manual-takeover may continue until operators adopt it.
- **Bundle size trend: 7-7-7-7-5-6-5-3.** v0.7.2 is the smallest bundle yet (3 stories). Patch-tier track mature.
- **Plan-review 100% LOW (11/11)** across 8 cycles. Second MEDIUM example (N18) not yet triggered.
