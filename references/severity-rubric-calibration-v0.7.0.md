# Severity rubric calibration — v0.7.0 first pass (5-cycle / 18-row baseline)

**Date:** 2026-04-28
**Scope:** v0.6.5..v0.7.0 (6 populated cycles by ship time, 18 CSV rows / 49 findings)
**Source data:** `metrics/pre-impl-review-findings.csv`
**Companion script:** `references/severity-rubric-calibration-parse.sh`
**Rubric under review:** `references/finding-severity.md`

This is the **first calibration pass** of the severity rubric defined in `references/finding-severity.md` against empirical data accumulated across the v0.6.5..v0.7.0 release track. Per IDEA_REPORT_v10's recommendation, the patch-tier baseline is now stable enough (5 consecutive LOW-tier patch releases + the v0.7.0 minor-tier framing) for a meaningful first comparison.

## Methodology

The companion parse-script `references/severity-rubric-calibration-parse.sh` reads `metrics/pre-impl-review-findings.csv` (advisory pre-impl-review hook ledger) and emits per-stage histograms by cycle:

```bash
$ bash references/severity-rubric-calibration-parse.sh
```

The script aggregates by `stage` (design / prd / plan) using awk. Each row in the CSV records one advisory-hook invocation (3 per release cycle: design / prd / plan). Severity columns: `critical | high | medium | low`. The script outputs 3 sub-tables (one per stage) plus an all-stages aggregate.

The rubric authority `references/finding-severity.md` documents qualitative criteria for each severity tier per stage. It does NOT pre-specify expected quantile percentages, so this calibration pass is **qualitative drift analysis** rather than statistical histogram-comparison. Future calibration passes (v0.7.x+) can quantify expected distributions if drift is significant enough to motivate it.

## Empirical distribution

The numbers below are reproduced directly from the parse-script output. Re-running `bash references/severity-rubric-calibration-parse.sh` against an updated CSV produces an updated table — the doc is designed to be re-snapshotted at v0.7.x ship time.

### design

| Date | total | critical | high | medium | low |
|------|------:|---------:|-----:|-------:|----:|
| 2026-04-27 (v0.6.5) | 1 | 0 | 0 | 0 | 1 |
| 2026-04-27 (v0.6.6) | 0 | 0 | 0 | 0 | 0 |
| 2026-04-28 (v0.6.7) | 3 | 0 | 0 | 1 | 2 |
| 2026-04-28 (v0.6.8) | 3 | 0 | 0 | 1 | 2 |
| 2026-04-28 (v0.6.9) | 3 | 0 | 0 | 1 | 2 |
| 2026-04-28 (v0.7.0) | 3 | 0 | 1 | 1 | 1 |

**Aggregate (design):** total=13, critical=0 (0%), high=1 (8%), medium=4 (31%), low=8 (62%)

### prd

| Date | total | critical | high | medium | low |
|------|------:|---------:|-----:|-------:|----:|
| 2026-04-27 (v0.6.5) | 4 | 0 | 0 | 0 | 4 |
| 2026-04-27 (v0.6.6) | 9 | 0 | 2 | 4 | 3 |
| 2026-04-28 (v0.6.7) | 5 | 0 | 0 | 2 | 3 |
| 2026-04-28 (v0.6.8) | 3 | 0 | 0 | 1 | 2 |
| 2026-04-28 (v0.6.9) | 3 | 0 | 0 | 1 | 2 |
| 2026-04-28 (v0.7.0) | 3 | 0 | 0 | 1 | 2 |

**Aggregate (prd):** total=27, critical=0 (0%), high=2 (7%), medium=9 (33%), low=16 (59%)

### plan

| Date | total | critical | high | medium | low |
|------|------:|---------:|-----:|-------:|----:|
| 2026-04-27 (v0.6.5) | 0 | 0 | 0 | 0 | 0 |
| 2026-04-28 (v0.6.6) | 1 | 0 | 0 | 0 | 1 |
| 2026-04-28 (v0.6.7) | 2 | 0 | 0 | 0 | 2 |
| 2026-04-28 (v0.6.8) | 2 | 0 | 0 | 0 | 2 |
| 2026-04-28 (v0.6.9) | 2 | 0 | 0 | 0 | 2 |
| 2026-04-28 (v0.7.0) | 2 | 0 | 0 | 0 | 2 |

**Aggregate (plan):** total=9, critical=0 (0%), high=0 (0%), medium=0 (0%), low=9 (100%)

### All-stages aggregate

49 findings across 6 cycles × 3 stages × varying counts.

| Severity | Count | Percentage |
|----------|------:|-----------:|
| critical | 0 | 0.0% |
| high | 3 | 6.1% |
| medium | 13 | 26.5% |
| low | 33 | 67.3% |

## Expected distribution

`references/finding-severity.md` documents qualitative rubric per stage but does NOT specify expected quantile percentages. The implicit assumption from the rubric language: **critical** is reserved for missing-section / blocking gaps; **high** for vague-but-bounded ACs; **medium** for incomplete-but-functional content; **low** for convention drift / non-blocking style issues.

Operator's working assumption (informally agreed on across v0.6.x retrospectives):
- critical: rare; primarily missing-section / blocking gaps. Expected ~0-5% of findings.
- high: testability or coherence gaps that would propagate downstream. Expected ~10-15% of findings.
- medium: incomplete-but-correctable. Expected ~25-35% of findings.
- low: convention drift / nice-to-have polish. Expected ~50-60% of findings.

These rough quartiles are NOT prescriptive; they're the operator's mental model going into this calibration pass. The empirical distribution will calibrate them.

## Drift analysis

Comparing empirical (above) against expected:

| Severity | Empirical % | Expected % (operator mental model) | Drift | Verdict |
|----------|------------:|-----------------------------------:|------:|---------|
| critical | 0.0% | 0-5% | within range | OK — patch-tier bundles structurally avoid missing-section / blocking gaps. The 5-cycle baseline successfully isolated this signal. |
| high | 6.1% | 10-15% | **-4 to -9 pp** below expected | **Mild under-classification.** All 3 HIGHs across 49 findings came from prd-review (2 from v0.6.6 / 1 from v0.7.0 design). May reflect operators' calibration toward MEDIUM for findings that ARE testability gaps but feel "fixable inline." |
| medium | 26.5% | 25-35% | within range | OK — center-of-distribution working as intended. |
| low | 67.3% | 50-60% | **+7 to +17 pp** above expected | **Mild over-classification.** LOW absorbs the residual when borderline findings get classified down rather than up. Consistent with HIGH under-classification (downstream offset). |

**Stage-specific observations:**

- **plan-review has emitted ONLY LOW findings** across all 6 cycles (9/9 = 100% LOW). Expected: at least some MEDIUM findings should occur (e.g., DAG mis-serialization, file-conflict-not-flagged). The reviewer prompt may be over-classifying plan-review findings down. Investigate `agents/spec-reviewer.md` plan-review section for severity guidance — possible language tweak.
- **prd-review carries the bulk** (27/49 = 55% of all findings) and shows the most varied distribution. This matches the rubric's intent (PRD ACs are where testability gaps surface).
- **design-review distribution is balanced** with 1 HIGH (the v0.7.0 deferred-SKILL-existence decision — appropriately classified given it would have caused 0.5-1d scope creep if option (b) had been chosen wrong).

## Rubric language updates

Based on the drift analysis above, the v0.7.0 calibration pass recommends the following changes to `references/finding-severity.md`:

**No urgent rubric edits required at this baseline.** The HIGH under-classification (~10pp under) and LOW over-classification (~10pp over) are mild and could reflect the patch-tier-track skew (5 of 6 cycles were patch-tier — naturally cluster low-severity). A second calibration pass at v0.7.x with at least 1 minor-tier comparison data point will distinguish patch-tier-skew from genuine rubric miscalibration.

**However, one targeted tweak IS recommended for plan-review:** because plan-review has emitted 0 MEDIUM findings across 6 cycles, the rubric's plan-review MEDIUM example may not be reading clearly enough for operators to invoke. Consider adding a second example to the `plan-review` MEDIUM row in `references/finding-severity.md` next time the rubric is updated — a sample MEDIUM finding from real operator usage (e.g., "single-story wave warning that masks a real bottleneck"). Out of scope for v0.7.0 itself; queued for v0.7.1 N18.

## Future work

Track in v0.7.x cycles:

1. **First minor-tier comparison data point.** v0.7.0 itself adds 3 rows; subsequent minor-tier bundles (v0.8.0+) will add bundle-tier-comparison data. Goal: at v0.7.3 / v0.8.0, run a second calibration pass with both patch-tier (now ~6+ cycles) and minor-tier (1-2 cycles) baselines, comparing distributions.

2. **plan-review MEDIUM example refinement.** Per drift-analysis above, propose for v0.7.1 N18: add a second MEDIUM example to `references/finding-severity.md` plan-review row so operators have a clearer pattern to invoke.

3. **HIGH/LOW boundary calibration.** The mild drift (HIGH -8pp, LOW +10pp) may settle as more cycles ship. Re-run this calibration at v0.7.5 / v0.8.0 retrospective. If drift persists or grows, propose explicit quartile percentages in the rubric.

4. **Critical-tier reservation.** 0 CRITICAL findings across 6 cycles is the expected state for a healthy patch-tier track. If a future cycle produces a CRITICAL finding, document it as a calibration data point — CRITICAL should remain rare; clustering would indicate either over-classification or genuine systemic issues.

5. **Re-snapshot procedure.** This doc is designed to be re-snapshotted (not amended) at v0.7.x retrospectives. Replace the empirical-distribution tables with fresh parse-script output; preserve drift-analysis structure; update the date + scope. The companion script makes this a 1-command refresh.
