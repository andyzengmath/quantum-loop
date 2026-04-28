# IDEA_REPORT_v11 — what's still open after v0.7.0

**Date:** 2026-04-28
**Source:** `ql/v0.7.0-bundle` dogfood retrospective (US-006)
**Branch:** `ql/v0.7.0-bundle` (release tag v0.7.0 — first MINOR bump in 5 cycles)
**Predecessor:** `idea-stage/IDEA_REPORT_v10.md`

## Closed in v0.7.0

| ID | Story | Notes |
|---|---|---|
| **G22** | US-001 | First calibration pass landed. `references/severity-rubric-calibration-v0.7.0.md` (NEW, ~150 lines, 6 sections) + `references/severity-rubric-calibration-parse.sh` (NEW, awk-based CSV parser) + `tests/test_severity_rubric_calibration.sh` (NEW, 6 assertions). Aggregate verdict: "no urgent rubric edits at this baseline; plan-review MEDIUM-example tweak queued for v0.7.1 N18." |
| **N14** | US-002 | `skills/ql-execute/SKILL.md` `## Orchestrator liveness gate` subsection wraps orchestrator dispatch with `poll_orchestrator_commits`. Honors `QL_LIVENESS_ENABLE` env var (default true; false preserves v0.6.9 semantics). Handoff message structure: pointer to `references/orchestrator-takeover.md` + numbered recovery steps + exit rc=1 (orchestrator-stale). 6 presence-only assertions in `tests/test_ql_execute_liveness_wrapping.sh`. Closes the 3-layer recovery infrastructure (N6 prose / N6-followup lib / N14 SKILL). |
| **N15** | US-003 | CLAUDE.md `## Process references` re-categorized into 3 `### ` sub-headers: Orchestrator-related / Test-related / Process-related. 4 entries placed in natural categories. Existing 14 cross-link assertions remain green. |
| **N16** | US-004 | `poll_orchestrator_commits` adds `if (( interval_sec <= 0 ))` fail-fast guard at top of function. Test 5 (4 new assertions): exit 1 + ERROR log within 2s + no STALE log on guard path. v0.6.9 PR #70 soliton conf-82 carry-over closed. |
| **N17** | US-005 | `tests/bench_wallclock_baseline_drift.sh` replaces `eval "(cd '$REPO_ROOT' && $cmd)"` with `printf '(cd %q && %s)' ...` form. Defensive against future relocations to single-quote-containing paths. v0.6.9 PR #70 soliton conf-65 carry-over closed. |

The **G22 / N14 / N15 / N16 / N17 cluster** (the v0.7.0 priority list from IDEA_REPORT_v10) is now **fully closed**. 5 of 6 stories shipped first-attempt PASS; US-006 retrospective is this report.

## Persistent canon

**Codebase patterns p001-p011** verbatim definitions remain at `idea-stage/PIPELINE_REPORT_v7.md` § "codebasePatterns harvested" — durable single source-of-truth across cycles. v0.7.0 carried over unchanged.

## G30 score-formula calibration insight

**6 consecutive LOW-tier classifications** across v0.6.5..v0.7.0 — including v0.7.0's own minor-tier diff. Root cause: blast-radius caps at 25 for files_changed ≥ 10:

```bash
local br=$(( files_changed > 10 ? 25 : files_changed * 25 / 10 ))
```

Plus 0 sensitive paths + 0 coverage gap → total score = 25 = LOW.

**Implication for v0.7.x calibration:** to exercise the dispatch gate's MEDIUM/HIGH/CRITICAL branches end-to-end (the v0.6.7 N1 wiring), a future bundle needs to introduce non-zero sensitive_hits OR prod_without_test signals. Pure file-count-driven scoring caps at 25 for small bundles.

This is **calibration data, not a bug.** The conservative threshold means patch-tier and small-minor-tier bundles correctly skip the deep-review pipeline; only diffs that genuinely touch sensitive surfaces or have coverage gaps trigger the gate.

## Multi-cycle CSV milestone (18 rows, 49 findings, 6 cycles)

| Cycle | design | prd | plan | total |
|---|---|---|---|---:|
| v0.6.5 | 0/0/0/1 | 0/0/0/4 | 0/0/0/0 | 5 |
| v0.6.6 | 0/0/0/0 | 0/2/4/3 | 0/0/0/1 | 10 |
| v0.6.7 | 0/0/1/2 | 0/0/2/3 | 0/0/0/2 | 10 |
| v0.6.8 | 0/0/1/2 | 0/0/1/2 | 0/0/0/2 | 8 |
| v0.6.9 | 0/0/1/2 | 0/0/1/2 | 0/0/0/2 | 8 |
| v0.7.0 | 0/1/1/1 | 0/0/1/2 | 0/0/0/2 | 8 |
| **Total** | **0/1/4/8** | **0/2/9/16** | **0/0/0/9** | **49** |

Severity distribution: **0 critical / 3 high / 13 medium / 33 low (0.0% / 6.1% / 26.5% / 67.3%)**. See `references/severity-rubric-calibration-v0.7.0.md` for full drift-analysis.

## Still open after v0.7.0

### G19 — 3-SKILL-wrapper centralization
**Status:** unchanged. Defer indefinitely (no 4th pre-impl-review stage materialized).

### G21 — metrics CSV rotation
**Status:** premature. v0.7.0 ships at 18 rows.

### G24 — audit relative-path inconsistency
**Status:** unchanged.

### P5.B2 / B3 / B5 + P5.C frontier
**Status:** unchanged.

## New gaps from v0.7.0 dogfood

### N18 — plan-review MEDIUM example missing in `references/finding-severity.md`
**Surfaced:** v0.7.0 G22 calibration first pass — plan-review has emitted ONLY LOW findings across 6 cycles (9/9 = 100%). Operators may not invoke MEDIUM because the rubric example doesn't read clearly enough.
**Severity:** LOW (rubric refinement).
**Path:** v0.7.1 candidate. Add a second MEDIUM example to `references/finding-severity.md` plan-review row drawn from real operator usage (e.g., "single-story wave warning that masks a real bottleneck"). 0.1 stories.

### N19 — G30 dispatch gate has not been end-to-end exercised at MEDIUM+ tier
**Surfaced:** v0.7.0 LOW classification despite minor-tier framing. The full deep-review pipeline (v0.6.6 G30 + v0.6.7 N1 wiring) has only been documented; never RUN end-to-end in a real cycle.
**Severity:** LOW (test coverage gap; not a bug).
**Path:** v0.7.x candidate. Either (a) seed a future cycle's diff with a fixture that introduces non-zero sensitive_hits (e.g., a doc edit at `references/auth/...`), OR (b) add a `--force-dispatch` test fixture to `tests/test_deep_review_dispatch.sh` that exercises the full reviewer-dispatch chain. Option (b) is cleaner test coverage; option (a) is real-world signal. 0.5 stories for either.

### N20 — N14 SKILL wrapping isn't auto-tested at runtime
**Surfaced:** v0.7.0 US-002 shipped with PRESENCE-ONLY AC (matches v0.6.8 N6 pattern). The wrapping prose IS in skills/ql-execute/SKILL.md, but no test EXERCISES the env-var conditional or the handoff message structure inside the SKILL.
**Severity:** LOW (test coverage gap).
**Path:** v0.7.x candidate. Extract the wrapping logic into `lib/orchestrator-liveness.sh::wrap_orchestrator_dispatch()` (testable function) and reference from SKILL.md. Adds 0.25 stories.

## Recommendation for v0.7.1 or v0.7.x

**v0.7.1 candidate slate (patch-tier — bench-test track):**
1. **N18** — plan-review MEDIUM example refinement (LOW; tiny doc edit; 0.1 stories).
2. **N19** — G30 dispatch gate end-to-end test fixture (LOW but high-value; 0.5 stories).
3. **N20** — N14 SKILL wrapping runtime extraction (LOW; 0.25 stories).
4. Plus retrospective.

That's a 4-story v0.7.1 bundle (3 substantive + retrospective). Comparable to v0.6.9's 5-story shape.

**v0.8.0+ candidate slate (later-minor-tier):**
- **G22 second calibration pass** at v0.8.0 with bundle-tier comparison data (1-2 minor-tier cycles by then).
- **G19 / P5.B2/B3/B5 / P5.C frontier** — same triage as prior cycles.

## Recurring observations

- **First minor-tier framing** in this release track. v0.7.0 ships substantive G22 calibration + N14 SKILL-level runtime change. Future bundles can be either patch-tier (cleanups) or minor-tier (substantive) per their actual scope.
- **6 consecutive LOW-tier self-validations.** The G30 dispatch gate at threshold score>30 is conservative — only sensitive-path or coverage-gap diffs trigger it. Calibration data, not bug.
- **0-retry execution record extends to v0.7.0** under manual takeover (4th consecutive cycle).
- **N6/N6-followup/N14 3-layer recovery loop is now complete.** v0.6.8 prose advisory + v0.6.9 lib helper + v0.7.0 SKILL wrapping. Future orchestrator failures: `/ql-execute` auto-detects + emits handoff + parent agent reads `references/orchestrator-takeover.md` SOP and continues manually.
- **Bundle size pattern: 7-7-7-7-5-6.** v0.6.5..v0.6.8 stable at 7 stories; v0.6.9 dropped to 5 (patch backlog drained); v0.7.0 at 6 (mix of substantive + cleanup). v0.7.1 candidate slate is 4 stories.
