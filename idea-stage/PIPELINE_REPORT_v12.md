# PIPELINE_REPORT_v12 — v0.7.1 dogfood retrospective

**Date:** 2026-04-28
**Bundle:** `ql/v0.7.1-bundle` (release tag v0.7.1)
**Predecessor report:** `idea-stage/PIPELINE_REPORT_v11.md`
**Master parent:** `e77033d` (v0.7.0 ship state)
**Source IDEA report:** `idea-stage/IDEA_REPORT_v11.md`

## Overview

v0.7.1 closes the v0.7.0 IDEA_REPORT_v11 v0.7.1 slate (4 substantive items + retrospective). Patch-tier; 5-story compact bundle. **Seventh multi-cycle populated-CSV release** (18 → 21 rows).

## The 5 stories

| # | ID | Title | Outcome |
|:-:|---|---|:-:|
| 1 | US-001 | N19 — G30 dispatch gate end-to-end MEDIUM-tier fixture in `tests/test_deep_review_dispatch.sh` (Test 8) | first-attempt PASS (19/19 = 15 baseline + 4 N19) |
| 2 | US-002 | N20 — `wrap_orchestrator_dispatch` runtime extraction (lib/SKILL/2 tests) | first-attempt PASS (18/18 + 6/6) |
| 3 | US-003 | N18 — plan-review MEDIUM second example in `references/finding-severity.md` | first-attempt PASS |
| 4 | US-004 | N21 — parse-script aggregate suppress zero-row line | first-attempt PASS (rows counter + early exit; 6/6 calibration tests preserved) |
| 5 | US-005 | Retrospective + IDEA_REPORT_v12 + version bump 0.7.0 → 0.7.1 | this report |

## Wave plan vs. realized

DAG-validator output: Wave 0 (4): US-001, US-002, US-003, US-004 (all parallel-safe). Wave 1 (1): US-005 [deps all]. Realized sequential by priority under manual takeover (5th consecutive cycle).

## G30 self-validation — 7th consecutive LOW

`bash lib/deep-review.sh should_dispatch_deep_review <v0.7.1-diff>` → **tier=LOW score=25 files=10 sensitive=0 → skip**. Decision recorded in `quantum.json.reviews[v0.7.1-bundle].deepReview` with `automated:true`.

Note: v0.7.1's diff is smaller (10 files) than v0.7.0's (12 files), but blast-radius score is identical (25) because the formula caps at 25 for files_changed ≥ 10. Same calibration insight from PIPELINE_REPORT_v11.

**Notable:** the N19 fixture (US-001) now exercises the MEDIUM-tier dispatch path end-to-end via synthetic patch — closing the v0.7.0 PIPELINE_REPORT_v11 § "G30 score-formula calibration insight" gap (test coverage of MEDIUM/HIGH/CRITICAL branches).

## Multi-cycle CSV milestone (seventh populated run)

`metrics/pre-impl-review-findings.csv` → 21 rows. Aggregate (recomputed via `bash references/severity-rubric-calibration-parse.sh`):

- design: 13+0/0/0/2 = 15 total — 0/1/4/10 (critical/high/medium/low) — wait, v0.7.1 design row was 0/0/0/2.
- prd: 27+1 = 28 total — 0/2/9/17 — wait, v0.7.1 prd was 0/0/0/1.
- plan: 9+1 = 10 total — 0/0/0/10 — v0.7.1 plan was 0/0/0/1.

**Total post-v0.7.1: 53 findings across 7 cycles.** 0 critical / 3 high / 13 medium / 37 low. LOW share now 70 % (37/53). plan-review STILL emits 100 % LOW (10/10). v0.7.1 N18 (plan-review MEDIUM second example) ships in this very bundle — future cycles will calibrate whether the second example surfaces MEDIUM findings.

## Test-suite delta vs v0.7.0

| Test file | v0.7.0 | v0.7.1 | Δ |
|---|---:|---:|---:|
| tests/test_deep_review_dispatch.sh | 15 | 19 | +4 (Test 8 N19 fixture) |
| tests/test_orchestrator_liveness.sh | 12 | 18 | +6 (Tests 6 + 7 N20) |
| tests/test_ql_execute_liveness_wrapping.sh | 6 | 6 | 0 (Test 6 grep updated to wrap_orchestrator_dispatch) |
| Other | unchanged | unchanged | 0 |
| **Total v0.7.1 added:** | | | **+10** |

## Manual-takeover (5th consecutive cycle)

v0.7.1 dogfood ran on v0.7.0 master HEAD which has the wrap_orchestrator_dispatch SKILL.md prose but no parent-side wrapper script — manual takeover continued. The 3-layer recovery infrastructure (v0.6.8 prose / v0.6.9 lib / v0.7.0 SKILL) + v0.7.1's testable-extraction (N20 wrap_orchestrator_dispatch function) are now complete. Future SKILL operators have a directly-callable function.

**0-retry first-attempt PASS preserved across 5 consecutive manual-takeover cycles** (v0.6.7+v0.6.8+v0.6.9+v0.7.0+v0.7.1).

## codebasePatterns

No new patterns harvested in v0.7.1. p001-p011 carried over.

## Recommendation pointer

See `idea-stage/IDEA_REPORT_v12.md` for v0.7.x backlog.
