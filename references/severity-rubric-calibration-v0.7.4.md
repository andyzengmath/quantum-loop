# Severity rubric calibration — v0.7.4 third pass (8-committed-cycle / 24-row baseline)

**Date:** 2026-04-28
**Scope:** 8 committed-CSV cycles (v0.6.5..v0.7.1 + v0.7.4), 24 rows / 58 findings
**Source data:** `metrics/pre-impl-review-findings.csv`
**Companion script:** `references/severity-rubric-calibration-parse.sh`
**Rubric under review:** `references/finding-severity.md`
**Predecessors:** `references/severity-rubric-calibration-v0.7.0.md` (1st pass), `references/severity-rubric-calibration-v0.7.2.md` (2nd pass)

This is the **third calibration pass**. Two important discoveries this cycle:

1. **CSV-commit discovery (process gap):** v0.7.2 and v0.7.3 fired their advisory hooks but the CSV updates were never staged/committed before the squash-merge. Master's `metrics/pre-impl-review-findings.csv` last commit is `a9794f2` (v0.7.1). v0.7.4 brings the committed CSV to 24 rows (21 from v0.6.5..v0.7.1 + 3 from v0.7.4 hooks). The retrospective IDEA_REPORT_v15 captures this as a process gap to fix.
2. **9-cycle vs 8-cycle reconciliation:** the PRD AC referenced "9-cycle" assuming v0.7.2/v0.7.3 rows existed. In practice the committed CSV has 8 cycles' worth of rows. This doc reports the honest 8-cycle figure.

## Methodology

Same as v0.7.0/v0.7.2 passes. Run `bash references/severity-rubric-calibration-parse.sh` against the committed CSV. The bundle-tier comparison section manually partitions cycles by release tier.

## Empirical distribution (8-committed-cycle baseline)

### design

| Date | total | critical | high | medium | low |
|------|------:|---------:|-----:|-------:|----:|
| 2026-04-27 (v0.6.5) | 1 | 0 | 0 | 0 | 1 |
| 2026-04-27 (v0.6.6) | 0 | 0 | 0 | 0 | 0 |
| 2026-04-28 (v0.6.7) | 3 | 0 | 0 | 1 | 2 |
| 2026-04-28 (v0.6.8) | 3 | 0 | 0 | 1 | 2 |
| 2026-04-28 (v0.6.9) | 3 | 0 | 0 | 1 | 2 |
| 2026-04-28 (v0.7.0) | 3 | 0 | 1 | 1 | 1 |
| 2026-04-28 (v0.7.1) | 2 | 0 | 0 | 0 | 2 |
| 2026-04-28 (v0.7.4) | 2 | 0 | 0 | 0 | 2 |

**Aggregate (design):** total=17, critical=0 (0%), high=1 (5.9%), medium=4 (23.5%), low=12 (70.6%)

### prd

| Date | total | critical | high | medium | low |
|------|------:|---------:|-----:|-------:|----:|
| 2026-04-27 (v0.6.5) | 4 | 0 | 0 | 0 | 4 |
| 2026-04-27 (v0.6.6) | 9 | 0 | 2 | 4 | 3 |
| 2026-04-28 (v0.6.7) | 5 | 0 | 0 | 2 | 3 |
| 2026-04-28 (v0.6.8) | 3 | 0 | 0 | 1 | 2 |
| 2026-04-28 (v0.6.9) | 3 | 0 | 0 | 1 | 2 |
| 2026-04-28 (v0.7.0) | 3 | 0 | 0 | 1 | 2 |
| 2026-04-28 (v0.7.1) | 1 | 0 | 0 | 0 | 1 |
| 2026-04-28 (v0.7.4) | 1 | 0 | 0 | 0 | 1 |

**Aggregate (prd):** total=29, critical=0 (0%), high=2 (6.9%), medium=9 (31.0%), low=18 (62.1%)

### plan

| Date | total | critical | high | medium | low |
|------|------:|---------:|-----:|-------:|----:|
| 2026-04-27 (v0.6.5) | 0 | 0 | 0 | 0 | 0 |
| 2026-04-28 (v0.6.6) | 1 | 0 | 0 | 0 | 1 |
| 2026-04-28 (v0.6.7) | 2 | 0 | 0 | 0 | 2 |
| 2026-04-28 (v0.6.8) | 2 | 0 | 0 | 0 | 2 |
| 2026-04-28 (v0.6.9) | 2 | 0 | 0 | 0 | 2 |
| 2026-04-28 (v0.7.0) | 2 | 0 | 0 | 0 | 2 |
| 2026-04-28 (v0.7.1) | 1 | 0 | 0 | 0 | 1 |
| 2026-04-28 (v0.7.4) | 2 | 0 | 0 | 0 | 2 |

**Aggregate (plan):** total=12, critical=0 (0%), high=0 (0%), medium=0 (0%), low=12 (100%)

### All-stages aggregate

58 findings across 8 committed cycles x 3 stages.

| Severity | Count | Percentage |
|----------|------:|-----------:|
| critical | 0 | 0.0% |
| high | 3 | 5.2% |
| medium | 13 | 22.4% |
| low | 42 | 72.4% |

## Bundle-tier comparison

**Partition:** v0.7.0 = minor-tier (1 cycle). All other committed cycles = patch-tier (7 cycles: v0.6.5..v0.6.9, v0.7.1, v0.7.4).

**Limitation:** still n=1 minor-tier cycle. v0.7.2 and v0.7.3 minor-tier comparison was not added because (a) both were patch-tier anyway, and (b) their advisory hook rows never made it to the committed CSV. Minor-tier-rich data still pending v0.8.0+.

### Patch-tier (7 committed cycles, 21 rows, 50 findings)

| Stage | total | critical | high | medium | low |
|-------|------:|---------:|-----:|-------:|----:|
| design | 14 | 0 | 0 | 4 | 10 |
| prd | 26 | 0 | 2 | 8 | 16 |
| plan | 10 | 0 | 0 | 0 | 10 |
| **All** | **50** | **0 (0%)** | **2 (4.0%)** | **12 (24.0%)** | **36 (72.0%)** |

### Minor-tier (1 cycle — v0.7.0, 3 rows, 8 findings)

Unchanged from v0.7.2 snapshot:

| Stage | total | critical | high | medium | low |
|-------|------:|---------:|-----:|-------:|----:|
| design | 3 | 0 | 1 | 1 | 1 |
| prd | 3 | 0 | 0 | 1 | 2 |
| plan | 2 | 0 | 0 | 0 | 2 |
| **All** | **8** | **0 (0%)** | **1 (12.5%)** | **2 (25.0%)** | **5 (62.5%)** |

### Bundle-tier commentary

The patch-tier-skew hypothesis from v0.7.2 holds: patch-tier HIGH=4.0% vs minor-tier HIGH=12.5%. The ratio worsens slightly (was 4.1% in v0.7.2 second pass) because the v0.7.4 patch added 2 LOW design findings + 1 LOW prd + 2 LOW plan. Patch bundles continue to skew LOW.

## Plan-review MEDIUM trigger watch

**Status:** still 0 MEDIUM findings in plan-review across **all 8 committed cycles** (12/12 = 100% LOW for plan-review). v0.7.1 N18 shipped a second MEDIUM example in the rubric in March, but it has not yet triggered in any subsequent cycle.

**v0.7.4 plan-review hook details:** emitted 2 LOW findings (ac-coverage-gap on T-007-3 G30 verification + missing-wiring-task observation on US-005's foundation-only deferral). Neither was MEDIUM-worthy: both were process notes about deliberately-deferred items, not real DAG-mis-serialization or single-story-wave bottleneck triggers.

**Updated hypothesis:** the rubric's plan-review MEDIUM examples may be too specific to scenarios that don't surface in compact patch bundles. The single-story-wave-bottleneck example (added in N18) requires a wave structure where a single-story wave masks a bottleneck — but compact 4-7-story bundles tend to have either fully-parallel (no bottleneck) or sequential (no masking) waves. A complex multi-wave minor-tier cycle is the most likely trigger. Watch for a v0.8.0 minor-tier release with multi-wave DAG.

## Updated drift analysis

| Severity | v0.7.0 % | v0.7.2 % | v0.7.4 % | Expected % | Drift (v0.7.4) | Updated verdict |
|----------|---------:|---------:|---------:|-----------:|---------------:|-----------------|
| critical | 0.0% | 0.0% | 0.0% | 0-5% | within range | OK — unchanged. 0 CRITICAL across 8 cycles consistent with healthy patch-track baseline. |
| high | 6.1% | 5.3% | 5.2% | 10-15% | **-5 to -10 pp** | **Continued patch-tier skew.** Patch-tier alone is 4.0% HIGH; minor-tier alone is 12.5%. All-cycles aggregate dragged down by 7:1 patch-to-minor ratio. **No rubric edit required**, but v0.8.0 minor-tier releases will be the test of whether the rubric language is correct or under-classifying. |
| medium | 26.5% | 22.8% | 22.4% | 25-35% | mild under | Slight downward drift (was 22.8% in v0.7.2). Plan-review still 100% LOW. v0.7.4 added 0 new MEDIUM. No rubric action required. |
| low | 67.3% | 71.9% | 72.4% | 50-60% | **+12 pp** above | LOW share continuing to grow as patch bundles get cleaner. Will reverse as minor-tier cycles accumulate. |

## Future work

1. **Fix the CSV-commit process gap.** v0.7.2 and v0.7.3 hooks fired but never committed. Action item for v0.7.5+: either add the CSV to a post-hook git-add reminder in the design doc template, or include `git status metrics/pre-impl-review-findings.csv` in the audit checklist.

2. **Fourth calibration pass at v0.8.0+ with 2+ minor-tier cycles.** Bundle-tier comparison still n=1 minor — same conclusion as v0.7.2.

3. **Plan-review MEDIUM trigger watch continues.** 12/12 LOW across all committed cycles. The N18 second example has not triggered. Monitor v0.8.0+ multi-wave bundles.

4. **HIGH/LOW boundary re-evaluation deferred to v0.9.0.** Current hypothesis (patch-tier skew) holds across 3 calibration passes. v0.8.0+ minor-tier data will test or invalidate it.

5. **Critical-tier reservation unchanged.** 0 CRITICAL across 8 committed cycles. No action.

6. **Re-snapshot procedure unchanged.** Replace empirical tables with fresh `bash references/severity-rubric-calibration-parse.sh` output at each retrospective. Bundle-tier comparison requires manual partition (the parse script aggregates all stages only).
