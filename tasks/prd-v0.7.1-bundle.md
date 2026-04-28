# PRD: v0.7.1 — patch-tier (N18, N19, N20, N21 + retrospective)

**Status:** Approved
**Date:** 2026-04-28
**Design doc:** `docs/plans/2026-04-28-v0.7.1-bundle-design.md`
**Source:** `idea-stage/IDEA_REPORT_v11.md` v0.7.1 slate
**Branch (planned):** `ql/v0.7.1-bundle`
**Target version:** 0.7.1 (patch bump from 0.7.0)
**Total effort estimate:** ~1 day

## Section 1: Introduction / Overview

5 stories closing the v0.7.0 IDEA_REPORT_v11 v0.7.1 slate. Patch-tier; mostly small cleanups + 1 high-value test-coverage story (N19). Seventh multi-cycle populated-CSV run (18 → 21 rows).

## Section 2: Goals

- Close N18, N19, N20, N21 from IDEA_REPORT_v11.
- Maintain 0-retry execution record.
- Bump plugin version 0.7.0 → 0.7.1.
- Populate `metrics/pre-impl-review-findings.csv` with ≥3 new rows (total ≥21).
- G30 self-validation re-run (expected: 7th LOW classification).

## Section 3: User Stories

### US-001: N19 — G30 dispatch gate end-to-end test fixture

**Acceptance Criteria:**
- [ ] `tests/test_deep_review_dispatch.sh` adds Test 8: synthesize a patch with sensitive_hits=2 (paths matching `*.env` + `auth/`) → `should_dispatch_deep_review` returns 0 (dispatch).
- [ ] Test 8 invokes `dispatch_set MEDIUM` and asserts the returned reviewer JSON list contains 4 specific agent names: `oh-my-claudecode:code-reviewer`, `soliton:synthesizer`, `oh-my-claudecode:security-reviewer`, `oh-my-claudecode:test-engineer`.
- [ ] Existing 15 assertions remain green.
- [ ] +3 new assertions in Test 8.

### US-002: N20 — N14 SKILL wrapping runtime extraction

**Acceptance Criteria:**
- [ ] `lib/orchestrator-liveness.sh` adds `wrap_orchestrator_dispatch [timeout_sec] [interval_sec]` function that honors `QL_LIVENESS_ENABLE=false` (silent skip, returns 0) OR invokes `poll_orchestrator_commits` and emits handoff message + returns 1 on STALE.
- [ ] `skills/ql-execute/SKILL.md` `## Orchestrator liveness gate` subsection updated to reference `wrap_orchestrator_dispatch` (replaces inline bash example with function-call form).
- [ ] `tests/test_orchestrator_liveness.sh` adds Test 6 (QL_LIVENESS_ENABLE=false → silent rc=0) and Test 7 (use timeout=2 interval=1 against a stale tmp repo → handoff message on stdout + rc=1; wall-clock <10s on Git Bash per Test 2 pattern).
- [ ] Existing 12 assertions remain green; +4 new assertions across Tests 6/7.
- [ ] Existing `tests/test_ql_execute_liveness_wrapping.sh` (presence-only) updated to grep for `wrap_orchestrator_dispatch` (function reference replaces inline `poll_orchestrator_commits` invocation).

### US-003: N18 — plan-review MEDIUM second example

**Acceptance Criteria:**
- [ ] `references/finding-severity.md` plan-review MEDIUM row gains a second worked example: "single-story wave warning that masks a real bottleneck (e.g., wave-1 = US-003 alone, where US-003 actually depends on a delayed library feature in US-001 — the warning is real but currently informational)."
- [ ] Existing rubric tests (if any) still pass.
- [ ] Grep verification: MEDIUM row in plan-review section contains both the original example AND the new "single-story wave" phrase.

### US-004: N21 — parse-script aggregate suppress zero-row

**Acceptance Criteria:**
- [ ] `references/severity-rubric-calibration-parse.sh` adds a `rows` counter to the per-stage aggregate awk; suppresses the `**Aggregate**:` line when `rows == 0`.
- [ ] `bash references/severity-rubric-calibration-parse.sh` against current CSV: still produces non-empty output (all 3 stages have rows today); aggregate lines still print.
- [ ] Manual verification step (NOT permanent automated test): operator filters the CSV to remove all `prd` rows, re-runs the parse-script, confirms the `**Aggregate**: total=0` line for prd is suppressed. Mirrors v0.6.6 G34 / v0.7.0 G22 manual-verification framing.
- [ ] `tests/test_severity_rubric_calibration.sh` 6/6 assertions remain green.

### US-005: Retrospective + IDEA_REPORT_v12 + version bump 0.7.0 → 0.7.1

**Acceptance Criteria:**
- [ ] `idea-stage/PIPELINE_REPORT_v12.md` documents v0.7.1 dogfood.
- [ ] `idea-stage/IDEA_REPORT_v12.md` lists open after v0.7.1.
- [ ] `quantum-loop.sh --audit` captured.
- [ ] G30 self-validation captured; `automated:true` recorded.
- [ ] CHANGELOG [0.7.1] entry.
- [ ] All 4 plugin manifest version fields bumped 0.7.0 → 0.7.1.

## Section 4: Functional Requirements

- **FR-1:** `tests/test_deep_review_dispatch.sh` Test 8 fixture exercises MEDIUM-tier dispatch chain.
- **FR-2:** `wrap_orchestrator_dispatch` function exists in `lib/orchestrator-liveness.sh`; honors `QL_LIVENESS_ENABLE`.
- **FR-3:** `references/finding-severity.md` plan-review MEDIUM row has 2 worked examples.
- **FR-4:** `references/severity-rubric-calibration-parse.sh` suppresses zero-row aggregate.
- **FR-5:** CSV ≥21 rows; plugin version 0.7.0 → 0.7.1; reviews recorded with `automated:true`.

## Section 5: Non-Goals

- Changes to v0.7.0 G22 calibration verdict — re-snapshot at v0.7.x retrospective when minor-tier comparison data accumulates.
- Bumping to 0.8.0 — patch-tier per strict semver.

## Section 6-8: Design / Technical / Success Metrics

Mirrors v0.6.5..v0.7.0 patch-tier patterns. Quality gates: typecheck/lint/full test suite. Cross-platform: bash 4.3+. Success: all 5 stories pass; CSV at 21 rows; 7th consecutive LOW G30 classification.

## Section 9: Open Questions

None.

## Lifecycle Checklist

Standard. No env var changes; no schema changes; no breaking changes.

## Next Steps

Advisory hooks → quantum.json → execute → PR → soliton → squash-merge → tag v0.7.1.
