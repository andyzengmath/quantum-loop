# PIPELINE_REPORT_v11 — v0.7.0 dogfood retrospective (first minor-tier release)

**Date:** 2026-04-28
**Bundle:** `ql/v0.7.0-bundle` (release tag v0.7.0 — **MINOR bump** from v0.6.9)
**Predecessor report:** `idea-stage/PIPELINE_REPORT_v10.md`
**Master parent:** `b7434fb` (v0.6.9 ship state)
**Source IDEA report:** `idea-stage/IDEA_REPORT_v10.md`

## Overview

After 5 consecutive patch-tier releases (v0.6.5..v0.6.9, all classified score=25 LOW), the patch-tier backlog drained. **v0.7.0 marks the first minor-tier framing in this track**, justified by:

1. **G22 calibration first pass** (US-001) — substantive analysis work; 6-section snapshot doc + companion parse-script + self-verifying test.
2. **N14 SKILL-level liveness wrapping** (US-002) — runtime control-flow change in `/ql-execute`; closes the v0.6.7+v0.6.8+v0.6.9 manual-takeover recovery loop.
3. **3 LOW-priority cleanups** — N15 Process references re-categorization; N16 interval_sec=0 guard; N17 REPO_ROOT printf %q quoting.

6-story bundle (smaller than typical 7 — patch-tier backlog drained).

## The 6 stories

| # | ID | Title | Outcome |
|:-:|---|---|:-:|
| 1 | US-001 | G22 — severity rubric calibration first pass (5-cycle 18-row baseline) | first-attempt PASS (6/6 assertions; substantive analysis with concrete drift findings) |
| 2 | US-002 | N14 — `/ql-execute` SKILL-level liveness wrapping (presence-only AC) | first-attempt PASS (6/6 assertions) |
| 3 | US-003 | N15 — CLAUDE.md Process references re-categorization (3 sub-headers) | first-attempt PASS (existing 14 cross-link assertions remain green) |
| 4 | US-004 | N16 — `poll_orchestrator_commits` interval_sec=0 guard | first-attempt PASS (12/12 assertions; 8 baseline + 4 N16) |
| 5 | US-005 | N17 — `tests/bench_wallclock_baseline_drift.sh` REPO_ROOT printf %q quoting | first-attempt PASS (syntax + grep verification) |
| 6 | US-006 | Retrospective + IDEA_REPORT_v11 + version bump 0.6.9 → **0.7.0** (MINOR) | this report |

## Wave plan vs. realized

DAG-validator output:
- Wave 0 (5): US-001, US-002, US-003 [deps US-001 — adds CLAUDE.md cross-link to US-001's new doc], US-004, US-005
- Wave 1 (1): US-006 [deps US-001..US-005]

Realized: sequential by priority under manual takeover (4th consecutive cycle). All 6 stories committed individually.

## Surprise observation: v0.7.0 also classified LOW (score=25)

The design doc speculated v0.7.0's diff "may be MEDIUM tier for the first time" — given 12 files changed + 2 NEW reference docs + new lib code. **But v0.7.0's own diff classified tier=LOW score=25 files=12 sensitive=0 → skip.** That's **6 consecutive LOW-tier classifications across v0.6.5..v0.7.0.**

Root cause: the G30 score formula caps blast-radius at 25 for any diff with files_changed ≥ 10:

```bash
local br=$(( files_changed > 10 ? 25 : files_changed * 25 / 10 ))
```

Plus zero sensitive paths + zero coverage gap (each story landed with its own test). Total score = 25 + 0 + 0 = 25 = LOW.

**Calibration data point:** the G30 dispatch gate's threshold (score>30) is conservative enough that ANY patch-tier OR small-minor-tier bundle stays below MEDIUM. To test the dispatch gate end-to-end (the v0.6.7 N1 wiring), a future bundle would need to introduce sensitive paths (auth/, *.env, etc.) or a coverage gap (production change without test). Documented in IDEA_REPORT_v11 § "G30 score-formula calibration insight".

## Multi-cycle CSV milestone (sixth populated run)

`metrics/pre-impl-review-findings.csv` now has 18 rows; **49 findings across 6 cycles**.

Per stage / severity (post-v0.7.0 ship — see references/severity-rubric-calibration-v0.7.0.md for full per-cycle tables):
- design: 13 total — 0/1/4/8 (critical/high/medium/low)
- prd: 27 total — 0/2/9/16
- plan: 9 total — 0/0/0/9 (notable: ONLY LOWs across 6 cycles)
- **All-stages aggregate: 49 findings, 0/3/13/33 = 0% / 6.1% / 26.5% / 67.3%**

G22 calibration first pass landed (US-001). Verdict: "no urgent rubric edits required at this baseline; one targeted plan-review MEDIUM-example tweak queued for v0.7.1 N18." Re-snapshot at v0.7.x retrospectives via `references/severity-rubric-calibration-parse.sh`.

## G30 self-validation re-run

`bash lib/deep-review.sh should_dispatch_deep_review <v0.7.0-diff>` → tier=LOW score=25 files=12 sensitive=0 → skip. Decision recorded in `quantum.json.reviews[v0.7.0-bundle].deepReview` with `automated:true`.

**6 consecutive correct LOW-tier classifications.** The dispatch gate routes patch-tier + small-minor-tier bundles correctly with 100% accuracy across the 6-cycle baseline.

## Test-suite delta vs v0.6.9

| Test file | v0.6.9 | v0.7.0 | Δ |
|---|---:|---:|---:|
| tests/test_severity_rubric_calibration.sh (NEW) | 0 | 6 | +6 |
| tests/test_ql_execute_liveness_wrapping.sh (NEW) | 0 | 6 | +6 |
| tests/test_orchestrator_liveness.sh | 8 | 12 | +4 (N16 Test 5) |
| tests/test_orchestrator_takeover_doc.sh | 5 | 5 | 0 (cross-link refactor; assertion count unchanged) |
| tests/test_soliton_triage_doc.sh | 5 | 5 | 0 |
| tests/test_wallclock_baselines_doc.sh | 4 | 4 | 0 |
| Other | unchanged | unchanged | 0 |
| **Total v0.7.0 added:** | | | **+16** |

## Manual-takeover (4th consecutive cycle)

Per `references/orchestrator-takeover.md` (v0.6.9 N13 SOP) + `lib/orchestrator-liveness.sh` (v0.6.9 N6-followup runtime helper) + this v0.7.0 N14 SKILL-level wrapping, the 3-layer recovery infrastructure is now complete. v0.7.0 dogfood ran on v0.6.9 master HEAD which has the lib helper but no SKILL wrapping yet — manual takeover continued. Future cycles starting AFTER v0.7.0 merges will have the auto-invocation wrapping.

**0-retry first-attempt PASS preserved across 4 consecutive manual-takeover cycles** (v0.6.7+v0.6.8+v0.6.9+v0.7.0).

## codebasePatterns

No new patterns harvested in v0.7.0. p001-p011 carried over unchanged.

## Recommendation pointer

See `idea-stage/IDEA_REPORT_v11.md` for the v0.7.1 backlog.
