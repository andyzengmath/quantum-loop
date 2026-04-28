# IDEA_REPORT_v14 — what's still open after v0.7.3

**Date:** 2026-04-28
**Source:** `ql/v0.7.3-bundle` dogfood retrospective (US-002)
**Branch:** `ql/v0.7.3-bundle` (release tag v0.7.3)
**Predecessor:** `idea-stage/IDEA_REPORT_v13.md`

## Closed in v0.7.3

| ID | Story | Notes |
|---|---|---|
| **N28** | US-001 | 3 test-adequacy fixes from internal code review of v0.7.2: Test 8 +1 assertion (respawn-trigger diagnostic), Test 10 +2 assertions (wall-clock guard + failing-respawn diagnostic). 24 → 27 liveness tests. |
| **v0.7.2 housekeeping** | US-002 | `docs/plans/2026-04-28-v0.7.2-bundle-design.md` + `tasks/prd-v0.7.2-bundle.md` committed (were authored in v0.7.2 cycle but never staged). |

The **N28 cluster** (the v0.7.3 priority list from internal code review of v0.7.2) is now **fully closed**.

## Persistent canon

p001-p011 unchanged. Source-of-truth: `idea-stage/PIPELINE_REPORT_v7.md` § "codebasePatterns harvested".

## Multi-cycle CSV milestone (27 rows, 61 findings, 9 cycles)

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
| v0.7.3 | 0/0/0/2 | 0/0/0/1 | 0/0/0/1 | 4 |
| **Total** | **0/1/4/14** | **0/2/9/19** | **0/0/0/12** | **61** |

Severity distribution: **0 critical / 3 high / 13 medium / 45 low (0% / 4.9% / 21.3% / 73.8%)**.

Trends:
- LOW share rising (71.9% → 73.8%). Expected — the last 3 cycles (v0.7.1/v0.7.2/v0.7.3) each emitted 4 LOW + 0 above-LOW findings.
- HIGH stable at 3 across all 9 cycles (no new HIGH since v0.7.0).
- plan-review continues 100% LOW (12/12 rows across 9 cycles). N18 second-example trigger still pending.

## Still open after v0.7.3

### G19 / G21 / G24 / P5.B2/B3/B5 / P5.C frontier
**Status:** unchanged. Defer indefinitely until minor-tier scope.

### N25 — QL_RESPAWN_CMD not exercised end-to-end in CI
**Status:** unchanged from IDEA_REPORT_v13. No e2e test of a real claude invocation. Defer.

### N26 — plan-review MEDIUM still not triggered
**Status:** unchanged. 12 consecutive LOW across 9 cycles. Defer until minor-tier with complex DAG.

### N27 — G22 third calibration pass needs more minor-tier data
**Status:** unchanged. n=1 minor-tier still. Defer to v0.8.0+ retrospective.

## New gaps from v0.7.3 dogfood

### N29 — internal-review trigger source not formally tracked
**Surfaced:** v0.7.3 is the first cycle triggered by internal code review. Trigger sources have informally been: operator-driven (most cycles), soliton-driven (post-merge inline fixes), internal-review-driven (v0.7.3). PIPELINE_REPORT_v14 documents this as a calibration data point but no structured tracking exists.
**Severity:** LOW (process observation).
**Path:** Track. Future cycles could add a `trigger_source` field to retrospectives. Defer until 2-3 more internal-review or soliton-driven cycles ship — sample size matters.

### N30 — design+PRD housekeeping pattern needs a checklist guard
**Surfaced:** v0.7.2 cycle inadvertently shipped without committing the design doc and PRD (caught in v0.7.3). Every prior cycle from v0.7.0 onward committed these. The miss was operator-attention level — no automated guard.
**Severity:** LOW (process gap).
**Path:** Add a pre-commit / pre-tag checklist guard that verifies `docs/plans/<date>-vX.Y.Z-bundle-design.md` and `tasks/prd-vX.Y.Z-bundle.md` exist in the merge commit when shipping a release. Track for future minor-tier or reactive cycle.

## Recommendation for v0.7.4 or v0.8.0

**v0.7.4 candidate slate (patch-tier):** drained again. N25/N26/N27/N29/N30 are observations or deferred. No actionable v0.7.4.

**Suggestion:** Skip v0.7.4 unless reactive trigger surfaces. Next substantive cycle is **v0.8.0 minor-tier** with operator-provided feature scope.

**v0.8.0 candidate slate (minor tier):**
1. **New feature** — TBD; needs feature-driven PRD.
2. **G22 third calibration pass** — needs minor-tier data point.
3. **N30 release-doc checklist guard** — small but architecturally substantive (CI-side check or pre-commit hook).

## Recurring observations

- **9 consecutive LOW-tier self-validations** (v0.6.5..v0.7.3). G30 calibration consistent.
- **7 consecutive manual-takeover cycles** with 0-retry first-attempt PASS. 5-layer recovery infra fully shipped; QL_RESPAWN_CMD requires opt-in.
- **Bundle size trend: 7-7-7-7-5-6-5-3-2.** v0.7.3 is the smallest yet. Patch-tier track is fully drained.
- **Plan-review 100% LOW (12/12)** across 9 cycles.
- **Trigger sources: operator-driven (most), soliton-driven (post-merge), internal-review-driven (v0.7.3).** Three distinct triggers exercised across the 9-cycle history.
