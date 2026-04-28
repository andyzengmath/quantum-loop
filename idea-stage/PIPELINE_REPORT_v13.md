# PIPELINE_REPORT_v13 — v0.7.2 dogfood retrospective

**Date:** 2026-04-28
**Bundle:** `ql/v0.7.2-bundle` (release tag v0.7.2)
**Predecessor report:** `idea-stage/PIPELINE_REPORT_v12.md`
**Master parent:** `a9794f2` (v0.7.1 ship state)
**Source IDEA report:** `idea-stage/IDEA_REPORT_v12.md`

## Overview

v0.7.2 closes the IDEA_REPORT_v12 v0.7.2 slate (N24 auto-respawn + G22 second calibration pass). Patch-tier; 3-story compact bundle. **Eighth multi-cycle populated-CSV release** (21 → 24 rows).

## The 3 stories

| # | ID | Title | Outcome |
|:-:|---|---|:-:|
| 1 | US-001 | N24 — `wrap_orchestrator_dispatch` QL_RESPAWN_CMD auto-respawn (lib + 2 tests) | first-attempt PASS (22/22 = 18 baseline + 4 N24) |
| 2 | US-002 | G22 second calibration pass — `references/severity-rubric-calibration-v0.7.2.md` + CLAUDE.md ref | first-attempt PASS |
| 3 | US-003 | Retrospective + IDEA_REPORT_v13 + version bump 0.7.1 → 0.7.2 | this report |

## Wave plan vs. realized

DAG-validator not invoked (3-story bundle, trivial DAG). Wave 0 (2): US-001, US-002 (parallel-safe, no file conflicts). Wave 1 (1): US-003 [deps: US-001, US-002]. Realized sequential by priority under manual takeover (6th consecutive cycle).

## G30 self-validation — 8th consecutive LOW

`bash lib/deep-review.sh score <base> <head> | bash lib/deep-review.sh tier` → **score=10 tier=LOW files=4 sensitive=0 → skip**. Decision recorded in quantum.json `reviews` with `automated:true`.

Note: v0.7.2 diff (4 files) scores 10 — lower than v0.7.1 (10 files, score=25). The blast-radius formula scales with files_changed below the 10-file cap; 4 files x~2.5 = 10.

## Multi-cycle CSV milestone (eighth populated run)

`metrics/pre-impl-review-findings.csv` → 24 rows. Advisory hook findings for v0.7.2: design=2 (0/0/0/2), prd=1 (0/0/0/1), plan=1 (0/0/0/1) — all LOW as expected for a compact patch-tier bundle.

All-stages aggregate (via `bash references/severity-rubric-calibration-parse.sh`): 57 findings across 8 cycles. 0 critical / 3 high / 13 medium / 41 low (0% / 5.3% / 22.8% / 71.9%). LOW share at 71.9%; HIGH at 5.3% — consistent with patch-tier-skew hypothesis confirmed in G22 second pass.

## Test-suite delta vs v0.7.1

| Test file | v0.7.1 | v0.7.2 | delta |
|---|---:|---:|---:|
| tests/test_orchestrator_liveness.sh | 18 | 22 | +4 (Tests 8+9 N24) |
| Other | unchanged | unchanged | 0 |
| **Total v0.7.2 added:** | | | **+4** |

Full audit: `bash quantum-loop.sh --audit` → 6/7 OK, 1 FAIL (branches-remote environmental artifact, unchanged from v0.7.1).

## Manual-takeover (6th consecutive cycle)

v0.7.2 dogfood ran with v0.7.1 master HEAD. The wrap_orchestrator_dispatch function (N20) and QL_RESPAWN_CMD extension (N24) are now both present, but the SKILL operator still invoked manual takeover — QL_RESPAWN_CMD requires operator to set the env var explicitly. The 5-layer recovery infrastructure is now complete:

| Layer | Version | Mechanism |
|---|---|---|
| Prose | v0.6.8 | orchestrator.md self-monitoring guard |
| Lib helper | v0.6.9 | poll_orchestrator_commits() |
| SKILL prose | v0.7.0 | ql-execute SKILL.md liveness gate |
| Callable fn | v0.7.1 | wrap_orchestrator_dispatch() |
| Auto-respawn | v0.7.2 | QL_RESPAWN_CMD branch |

**0-retry first-attempt PASS preserved across 6 consecutive manual-takeover cycles** (v0.6.7..v0.7.2).

## codebasePatterns

No new patterns harvested in v0.7.2. p001-p011 carried over unchanged.

## Recommendation pointer

See `idea-stage/IDEA_REPORT_v13.md` for v0.8.0+ backlog.
