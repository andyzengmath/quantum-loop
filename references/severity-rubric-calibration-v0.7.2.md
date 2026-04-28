# Severity rubric calibration — v0.7.2 second pass (8-cycle / 24-row baseline)

**Date:** 2026-04-28
**Scope:** v0.6.5..v0.7.2 (8 populated cycles, 24 CSV rows / 57 findings)
**Source data:** `metrics/pre-impl-review-findings.csv`
**Companion script:** `references/severity-rubric-calibration-parse.sh`
**Rubric under review:** `references/finding-severity.md`
**Predecessor:** `references/severity-rubric-calibration-v0.7.0.md` (6-cycle / 18-row baseline)

This is the **second calibration pass** of the severity rubric. The v0.7.0 first pass (18 rows, 49 findings) identified mild HIGH under-classification (~8pp below expected) and LOW over-classification (~10pp over), with the caveat that the 5-of-6-cycle patch-tier skew might explain the drift rather than genuine rubric miscalibration. This pass adds 2 more cycles (v0.7.1 patch + v0.7.2 patch advisory hooks) and introduces a **bundle-tier comparison axis** using v0.7.0 as the single minor-tier data point.

## Methodology

Same as v0.7.0 first pass. Run `bash references/severity-rubric-calibration-parse.sh` against the full CSV. Tables below are reproduced directly from the script output. The bundle-tier comparison section manually partitions the 24-row dataset by release tier (minor vs patch).

## Empirical distribution (8-cycle baseline)

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
| 2026-04-28 (v0.7.2) | 2 | 0 | 0 | 0 | 2 |

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
| 2026-04-28 (v0.7.2) | 1 | 0 | 0 | 0 | 1 |

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
| 2026-04-28 (v0.7.2) | 1 | 0 | 0 | 0 | 1 |

**Aggregate (plan):** total=11, critical=0 (0%), high=0 (0%), medium=0 (0%), low=11 (100%)

### All-stages aggregate

57 findings across 8 cycles x 3 stages.

| Severity | Count | Percentage |
|----------|------:|-----------:|
| critical | 0 | 0.0% |
| high | 3 | 5.3% |
| medium | 13 | 22.8% |
| low | 41 | 71.9% |

## Bundle-tier comparison

**Partition:** v0.7.0 = minor-tier (1 cycle). All other cycles = patch-tier (7 cycles: v0.6.5..v0.6.9, v0.7.1, v0.7.2).

**Limitation:** n=1 minor-tier cycle. Results are directional signals, not statistically conclusive. A third calibration pass with 3+ minor-tier cycles would be needed for statistical confidence.

### Patch-tier (7 cycles, 21 rows, 49 findings)

| Stage | total | critical | high | medium | low |
|-------|------:|---------:|-----:|-------:|----:|
| design | 14 | 0 | 0 | 4 | 10 |
| prd | 26 | 0 | 2 | 8 | 16 |
| plan | 9 | 0 | 0 | 0 | 9 |
| **All** | **49** | **0 (0%)** | **2 (4.1%)** | **12 (24.5%)** | **35 (71.4%)** |

### Minor-tier (1 cycle — v0.7.0, 3 rows, 8 findings)

| Stage | total | critical | high | medium | low |
|-------|------:|---------:|-----:|-------:|----:|
| design | 3 | 0 | 1 | 1 | 1 |
| prd | 3 | 0 | 0 | 1 | 2 |
| plan | 2 | 0 | 0 | 0 | 2 |
| **All** | **8** | **0 (0%)** | **1 (12.5%)** | **2 (25.0%)** | **5 (62.5%)** |

### Bundle-tier commentary

The most notable signal is **HIGH severity**: minor-tier produced 12.5% HIGH vs patch-tier 4.1%. This directionally supports the v0.7.0 first-pass hypothesis that the HIGH under-classification (~8pp below expected) was driven by patch-tier-track skew rather than genuine rubric miscalibration. The single minor-tier cycle shows HIGH within the expected 10-15% range.

MEDIUM is stable across tiers (24.5% patch vs 25.0% minor), consistent with the rubric intent that MEDIUM captures incomplete-but-correctable content regardless of bundle size.

LOW is higher for patch-tier (71.4% vs 62.5%), partially offset by fewer HIGH findings in patch-tier bundles. This is expected: smaller, mature patch bundles are structurally cleaner, generating fewer HIGH findings and absorbing the residual into LOW.

## Updated drift analysis

Extending the v0.7.0 drift table with v0.7.2 empirical percentages and bundle-tier-informed verdicts:

| Severity | v0.7.0 empirical % | v0.7.2 empirical % | Expected % | Drift (v0.7.2) | Updated verdict |
|----------|-------------------:|-------------------:|-----------:|---------------:|-----------------|
| critical | 0.0% | 0.0% | 0-5% | within range | OK — unchanged. 0 CRITICAL across 8 cycles consistent with healthy patch-track baseline. |
| high | 6.1% | 5.3% | 10-15% | **-5 to -10 pp** | **Explained by patch-tier skew.** Patch-tier: 4.1% HIGH; minor-tier: 12.5% (within expected). Rubric language is likely correct; the all-cycles aggregate is pulled down by 7:1 patch-to-minor ratio. No rubric edit required. |
| medium | 26.5% | 22.8% | 25-35% | mild under | Slight downward drift. Plan-review STILL 100% LOW (11/11 rows). Patch bundles running cleaner in v0.7.1/v0.7.2 (0 MEDIUM each). No rubric action required. |
| low | 67.3% | 71.9% | 50-60% | **+12 pp** above | Consistent with HIGH under-classification driven by patch-tier skew. LOW share should decrease toward expected range as minor-tier cycles accumulate. |

**Plan-review MEDIUM status:** v0.7.1 N18 shipped a second MEDIUM example in the plan-review rubric row. The v0.7.1 and v0.7.2 plan-review hooks both emitted 1 LOW (not MEDIUM). The example has not yet surfaced a real MEDIUM finding — likely because both cycles had compact, clean DAG structures. A minor-tier cycle with a complex multi-wave DAG is the more likely trigger.

## Future work

1. **Third calibration pass at v0.8.0+ with 2+ minor-tier cycles.** The bundle-tier comparison is currently n=1 minor. Accumulating 2-3 minor-tier data points would allow statistical comparison rather than directional signal. ~~First minor-tier comparison data point — closed with this pass.~~

2. **Plan-review MEDIUM trigger observation.** The N18 second example has not yet surfaced a real MEDIUM in plan-review (11 consecutive LOW across 8 cycles). Track whether a minor-tier cycle with complex DAG structure triggers one. No rubric action yet.

3. **HIGH/LOW boundary re-evaluation at v0.9.0.** If the patch/minor ratio normalizes, re-examine whether the all-stages HIGH/LOW distribution converges toward expected quartiles. Current hypothesis (patch-tier skew) should be tested with more data before any rubric edits.

4. **Critical-tier reservation unchanged.** 0 CRITICAL across 8 cycles expected for a healthy track. No action.

5. **Re-snapshot procedure.** Replace empirical tables with fresh `bash references/severity-rubric-calibration-parse.sh` output at each retrospective. The bundle-tier comparison section requires manual partition (the parse script aggregates all stages only).
