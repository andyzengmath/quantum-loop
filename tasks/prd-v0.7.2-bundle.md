# PRD: v0.7.2 — patch-tier (N24, G22-second-pass + retrospective)

**Status:** Approved
**Date:** 2026-04-28
**Design doc:** `docs/plans/2026-04-28-v0.7.2-bundle-design.md`
**Source:** `idea-stage/IDEA_REPORT_v12.md` v0.7.2 slate
**Branch (planned):** `ql/v0.7.2-bundle`
**Target version:** 0.7.2 (patch bump from 0.7.1)
**Total effort estimate:** ~1 day

## Section 1: Introduction / Overview

3 stories closing the IDEA_REPORT_v12 v0.7.2 slate. Patch-tier; 1 runtime extension (N24 auto-respawn) + 1 calibration doc (G22 second pass) + retrospective. Eighth multi-cycle populated-CSV run (21 → 24 rows).

## Section 2: Goals

- Close N24 and G22-second-pass from IDEA_REPORT_v12.
- Maintain 0-retry execution record.
- Bump plugin version 0.7.1 → 0.7.2.
- Populate `metrics/pre-impl-review-findings.csv` with ≥3 new rows (total ≥24).
- G30 self-validation re-run (expected: 8th LOW classification).

## Section 3: User Stories

### US-001: N24 — wrap_orchestrator_dispatch auto-respawn

**Acceptance Criteria:**
- [ ] `lib/orchestrator-liveness.sh::wrap_orchestrator_dispatch` gains a `QL_RESPAWN_CMD` env-var check: if non-empty and STALE is detected, execute `bash -c "${QL_RESPAWN_CMD}"` and return its exit code (instead of emitting handoff + returning 1).
- [ ] If `QL_RESPAWN_CMD` is empty or unset AND STALE, behavior is unchanged from v0.7.1: emit handoff message + return 1.
- [ ] Function comment documents `QL_RESPAWN_CMD` contract and explicitly notes it is an operator-controlled env var (trusted invocation, not user input).
- [ ] `tests/test_orchestrator_liveness.sh` adds Test 8: `QL_RESPAWN_CMD="echo respawned"` + stale repo (timeout=2, interval=1) → stdout contains "respawned" AND rc=0. Wall-clock <10s.
- [ ] `tests/test_orchestrator_liveness.sh` adds Test 9: `QL_RESPAWN_CMD=""` (unset) + stale repo (timeout=2, interval=1) → stdout contains "[QL-EXECUTE] orchestrator-stale signal" handoff text AND rc=1. Regression-guards v0.7.1 behavior.
- [ ] Existing 18 assertions remain green; +4 new assertions across Tests 8/9.

### US-002: G22 second calibration pass

**Acceptance Criteria:**
- [ ] `references/severity-rubric-calibration-v0.7.2.md` created with updated empirical tables from `bash references/severity-rubric-calibration-parse.sh` output (post-v0.7.2 advisory hooks; ≥24 rows / ≥53 findings).
- [ ] Doc includes a **bundle-tier comparison section** that separates v0.7.0 (minor-tier) from all other cycles (patch-tier) and compares per-stage severity distributions. Commentary explicitly notes n=1 minor-tier limitation.
- [ ] Doc includes updated drift analysis with "v0.7.2 empirical %" column added to the v0.7.0 drift table.
- [ ] "First minor-tier comparison data point" future-work item from v0.7.0 doc is explicitly closed or updated.
- [ ] `CLAUDE.md` Process references section: `references/severity-rubric-calibration-v0.7.0.md` updated to `references/severity-rubric-calibration-v0.7.2.md`.
- [ ] Grep verification: new doc contains "bundle-tier" and "minor-tier" and "patch-tier" phrases.

### US-003: Retrospective + IDEA_REPORT_v13 + version bump 0.7.1 → 0.7.2

**Acceptance Criteria:**
- [ ] `idea-stage/PIPELINE_REPORT_v13.md` documents v0.7.2 dogfood (3 stories, outcomes, wave plan, G30 result, test-suite delta, codebasePatterns).
- [ ] `idea-stage/IDEA_REPORT_v13.md` lists what's open after v0.7.2 (expected: G19/G21/G24/P5.* defer unchanged; N25+ TBD from v0.7.2 dogfood).
- [ ] `quantum-loop.sh --audit` output captured in retrospective.
- [ ] G30 self-validation captured; `automated:true` recorded.
- [ ] CHANGELOG [0.7.2] entry covering N24 + G22-second-pass.
- [ ] All 4 plugin manifest version fields bumped 0.7.1 → 0.7.2:
  - `.claude-plugin/plugin.json` → `metadata.version` + `plugins[0].version`
  - `.claude-plugin/marketplace.json` → `metadata.version` + `plugins[0].version`
  - `.cursor-plugin/plugin.json` → `metadata.version` (or equivalent field)

## Section 4: Functional Requirements

- **FR-1:** `wrap_orchestrator_dispatch` in `lib/orchestrator-liveness.sh` honors `QL_RESPAWN_CMD`; executes it on STALE when set; falls back to handoff when unset.
- **FR-2:** `tests/test_orchestrator_liveness.sh` Test 8 and Test 9 cover both `QL_RESPAWN_CMD` branches; existing 18 assertions green.
- **FR-3:** `references/severity-rubric-calibration-v0.7.2.md` exists with bundle-tier comparison section and updated drift analysis.
- **FR-4:** `CLAUDE.md` references `v0.7.2` calibration doc (not `v0.7.0`).
- **FR-5:** CSV ≥24 rows; plugin version 0.7.1 → 0.7.2; reviews recorded with `automated:true`.

## Section 5: Non-Goals

- End-to-end test of `QL_RESPAWN_CMD` with a real `claude` CLI invocation — tested with echo stub only (same pattern as N20).
- Changes to `references/finding-severity.md` rubric language — calibration doc is analysis only.
- Bumping to 0.8.0 — patch-tier per agreed framing.

## Section 6: Design Notes

See `docs/plans/2026-04-28-v0.7.2-bundle-design.md` for full per-story design. Key notes:
- `QL_RESPAWN_CMD` uses `bash -c` (not raw eval) and is documented as operator-controlled.
- G22 snapshot timing: advisory hooks fire before quantum.json execution; US-002 captures fresh parse-script output at execution time.

## Section 7: Technical Notes

Cross-platform: bash 4.3+. No new env vars beyond `QL_RESPAWN_CMD`. No schema changes to `quantum.json`. No changes to `metrics/pre-impl-review-findings.csv` format.

## Section 8: Success Metrics

All 3 stories first-attempt PASS; CSV at ≥24 rows; 8th consecutive LOW G30 classification; 19 → 22 total liveness-test assertions.

## Section 9: Open Questions

None.

## Lifecycle Checklist

Standard. No env var changes to existing keys; `QL_RESPAWN_CMD` is new (opt-in, default empty). No breaking changes.

## Next Steps

Advisory hooks → quantum.json → execute → PR → soliton → squash-merge → tag v0.7.2.
