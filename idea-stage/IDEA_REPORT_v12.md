# IDEA_REPORT_v12 — what's still open after v0.7.1

**Date:** 2026-04-28
**Source:** `ql/v0.7.1-bundle` dogfood retrospective (US-005)
**Branch:** `ql/v0.7.1-bundle` (release tag v0.7.1)
**Predecessor:** `idea-stage/IDEA_REPORT_v11.md`

## Closed in v0.7.1

| ID | Story | Notes |
|---|---|---|
| **N19** | US-001 | Test 8 (4 new assertions) in `tests/test_deep_review_dispatch.sh`. Synthesizes patch with sensitive_hits=2 (auth/login.js + .env) → should_dispatch_deep_review returns 0 (dispatch); dispatch_set MEDIUM returns 4 canonical reviewer agent names. 15 → 19 dispatch tests. |
| **N20** | US-002 | `lib/orchestrator-liveness.sh::wrap_orchestrator_dispatch` (NEW) extracts v0.7.0 N14 SKILL.md inline wrapping logic. Honors QL_LIVENESS_ENABLE; on STALE emits canonical handoff message + returns 1. SKILL.md replaces inline conditional with `wrap_orchestrator_dispatch || exit 1`. Tests 6 + 7 (6 new assertions) cover opt-out + stale-with-handoff. 12 → 18 liveness tests. |
| **N18** | US-003 | `references/finding-severity.md` plan-review MEDIUM row gains second example: single-story-wave-bottleneck-masked. Closes v0.7.0 G22 calibration insight that plan-review emitted ONLY LOW (9/9) — original example didn't read clearly enough. |
| **N21** | US-004 | `references/severity-rubric-calibration-parse.sh` per-stage aggregate awk adds `rows++` counter and `if (rows == 0) exit`. Suppresses spurious `**Aggregate**: total=0` line on stages with no rows. v0.7.0 PR #71 soliton conf-75 sub-threshold carry-over closed. |

The **N18-N21 cluster** (the v0.7.1 priority list from IDEA_REPORT_v11) is now **fully closed**. 4 of 5 stories shipped first-attempt PASS; US-005 retrospective is this report.

## Persistent canon

p001-p011 unchanged. Source-of-truth: `idea-stage/PIPELINE_REPORT_v7.md` § "codebasePatterns harvested".

## Multi-cycle CSV milestone (21 rows, 53 findings, 7 cycles)

| Cycle | design | prd | plan | total |
|---|---|---|---|---:|
| v0.6.5 | 0/0/0/1 | 0/0/0/4 | 0/0/0/0 | 5 |
| v0.6.6 | 0/0/0/0 | 0/2/4/3 | 0/0/0/1 | 10 |
| v0.6.7 | 0/0/1/2 | 0/0/2/3 | 0/0/0/2 | 10 |
| v0.6.8 | 0/0/1/2 | 0/0/1/2 | 0/0/0/2 | 8 |
| v0.6.9 | 0/0/1/2 | 0/0/1/2 | 0/0/0/2 | 8 |
| v0.7.0 | 0/1/1/1 | 0/0/1/2 | 0/0/0/2 | 8 |
| v0.7.1 | 0/0/0/2 | 0/0/0/1 | 0/0/0/1 | 4 |
| **Total** | **0/1/4/10** | **0/2/8/17** | **0/0/0/10** | **53** |

Severity distribution: **0 critical / 3 high / 12 medium / 38 low (0% / 5.7% / 22.6% / 71.7%)**.

**Trend observations:**
- LOW share rising slightly (67% → 70% → 72%). Fewer MEDIUMs as later cycles ship cleaner planning artifacts.
- plan-review STILL emits 100% LOW. v0.7.1 N18 second example just shipped — v0.7.2+ will calibrate.
- 0 CRITICAL across 7 cycles holds.
- HIGH stable at 3 (2 from v0.6.6 prd, 1 from v0.7.0 design).

## Still open after v0.7.1

### G19 / G21 / G24 / P5.B2/B3/B5 / P5.C frontier
**Status:** unchanged from v0.7.0.

## New gaps from v0.7.1 dogfood

### N22 — bundle size shrinking trend
**Surfaced:** v0.7.0 6 stories → v0.7.1 5 stories. Both smaller than the v0.6.5..v0.6.8 7-story shape. Patch-tier backlog increasingly drained; future patch releases will be ≤4-5 stories until a substantive minor-tier item surfaces.
**Severity:** LOW (process observation, not a bug).
**Path:** no action. Document trend; future cycles either bundle multiple small items into a 4-5 story patch release, or bundle into a substantive minor-tier release (v0.7.2 with 2+ minor-tier items, OR v0.8.0 if the next cycle has a substantive change).

### N23 — bundle-tier comparison data still pending
**Surfaced:** v0.7.0 was the first minor-tier release; G22 second calibration pass at v0.8.0 needs at least 1 more minor-tier comparison data point. v0.7.1 is patch-tier; doesn't add comparison data.
**Severity:** LOW (calibration-data scarcity).
**Path:** track v0.8.0 framing decision. The G22 second-pass needs a minor-tier release with substantive scope (not just calibration analysis) to populate the comparison axis.

## Recommendation for v0.7.2 or v0.8.0

**v0.7.2 candidate slate (patch-tier — minimal):**
The patch-tier backlog is essentially drained. Candidates:
- N22 / N23 are observations, not actionable items.
- Carry-overs (G19/G21/G24/P5.*) all defer indefinitely.

**Suggestion:** v0.7.2 may skip — the next substantive cycle is v0.8.0 minor-tier framing for G22 calibration second pass + bundle-tier comparison. If a v0.7.x patch is needed, it would be reactive (responding to a soliton finding or operator-discovered issue).

**v0.8.0 candidate slate (minor tier):**
1. **G22 second calibration pass** — at v0.7.x retrospective, re-snapshot `references/severity-rubric-calibration-v0.7.0.md` with bundle-tier comparison data (assuming at least 1 more minor-tier release lands).
2. **Substantive new features** — TBD; would need a feature-driven v0.8.0 PRD authored separately.

## Recurring observations

- **7 consecutive LOW-tier self-validations** (v0.6.5..v0.7.1). G30 calibration consistent.
- **5 consecutive manual-takeover cycles** with 0-retry first-attempt PASS. The 3-layer recovery infrastructure (v0.6.8 prose / v0.6.9 lib / v0.7.0 SKILL / v0.7.1 testable-extraction) is now complete; future cycles can validate runtime stale-detection in unattended runs.
- **Bundle size shrinking 7-7-7-7-5-6-5.** Patch-tier track maturity. v0.7.x patch releases are now 4-5 stories. v0.8.0+ should be the next substantive framing.
- **Bundle composition stabilizing.** v0.7.x bundles are predominantly cleanup + test-coverage + small lib extractions. Substantive feature work would move to minor-tier.
