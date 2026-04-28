# PIPELINE_REPORT_v14 — v0.7.3 dogfood retrospective

**Date:** 2026-04-28
**Bundle:** `ql/v0.7.3-bundle` (release tag v0.7.3)
**Predecessor report:** `idea-stage/PIPELINE_REPORT_v13.md`
**Master parent:** `be8292f` (v0.7.2 ship state)
**Source:** Internal code review of v0.7.2 (3 test-adequacy gaps surfaced)

## Overview

v0.7.3 closes N28 (3 test-adequacy gaps from internal code review of v0.7.2) + housekeeping (commit missed v0.7.2 design+PRD). Patch-tier; **2-story bundle — smallest yet**. **Ninth multi-cycle populated-CSV release** (24 → 27 rows). **First v0.7.x cycle triggered by internal code review** (prior cycles: operator-driven or soliton-driven).

## The 2 stories

| # | ID | Title | Outcome |
|:-:|---|---|:-:|
| 1 | US-001 | N28 — test-adequacy fixes (Tests 8+10 diagnostic-log + Test 10 wall-clock) | first-attempt PASS (27/27 = 24 baseline + 3 N28) |
| 2 | US-002 | Housekeeping + retrospective + IDEA_REPORT_v14 + version bump 0.7.2 → 0.7.3 | this report |

## Wave plan vs. realized

DAG-validator not invoked (2-story bundle, trivial linear DAG). Wave 0: US-001. Wave 1: US-002 [deps: US-001]. Realized sequential under manual takeover (7th consecutive cycle).

## G30 self-validation — 9th consecutive LOW

`bash lib/deep-review.sh score <base> <head> | bash lib/deep-review.sh tier` after US-001 → **score=2 tier=LOW files=1 sensitive=0 → skip**. After full v0.7.3 diff (US-001+US-002): expected ~10-15 score still LOW (docs+manifests don't add sensitive paths). Recorded with `automated:true`.

Note: v0.7.3 is the smallest cycle by file count (1 file changed in US-001, ~7-9 total including manifests + retrospective docs). 9 consecutive LOW classifications.

## Multi-cycle CSV milestone (ninth populated run)

`metrics/pre-impl-review-findings.csv` → 27 rows. Advisory hook findings for v0.7.3: design=2 (0/0/0/2), prd=1 (0/0/0/1), plan=1 (0/0/0/1) — all LOW as expected for a compact reactive bundle.

All-stages aggregate (post-v0.7.3): 61 findings across 9 cycles. 0 critical / 3 high / 13 medium / 45 low (0% / 4.9% / 21.3% / 73.8%). LOW share continues to rise (71.9% → 73.8%) consistent with patch-tier-track maturity confirmed in G22 v0.7.2 calibration.

## Test-suite delta vs v0.7.2

| Test file | v0.7.2 | v0.7.3 | delta |
|---|---:|---:|---:|
| tests/test_orchestrator_liveness.sh | 24 | 27 | +3 (Test 8 +1 / Test 10 +2 N28) |
| Other | unchanged | unchanged | 0 |
| **Total v0.7.3 added:** | | | **+3** |

## Manual-takeover (7th consecutive cycle)

v0.7.3 dogfood ran with v0.7.2 master HEAD which has the full 5-layer recovery infrastructure (prose / lib helper / SKILL prose / callable function / QL_RESPAWN_CMD auto-respawn). Manual takeover continued because no operator set `QL_RESPAWN_CMD` for the v0.7.3 cycle (the env var is opt-in by design; default behavior is the v0.7.1 handoff path).

**0-retry first-attempt PASS preserved across 7 consecutive manual-takeover cycles** (v0.6.7..v0.7.3).

## Internal-review trigger source — calibration data point

v0.7.3 is the **first cycle triggered by internal code review** (vs operator-driven scope or soliton-driven post-merge feedback). Worth noting:

- The 3 N28 gaps were all in **tests written during the v0.7.2 cycle itself** (Tests 8/10) plus the soliton-fix additions to those tests. They were not caught by the v0.7.2 soliton review (which focused on the lib code) or by the spec/quality gates.
- The trigger came from a comprehensive code review pass over the just-merged v0.7.2 diff — exactly the kind of review the user asked for after merge.
- Cost: 1 reactive cycle (this one). Benefit: closed 3 gaps that would have stayed open until next minor-tier diff exercised the diagnostic paths.
- Recommendation for future cycles: track internal-review-driven cycles separately from soliton/operator/reactive sources for trigger calibration.

## codebasePatterns

No new patterns harvested in v0.7.3. p001-p011 carried over unchanged.

## Recommendation pointer

See `idea-stage/IDEA_REPORT_v14.md` for v0.8.0+ backlog.
