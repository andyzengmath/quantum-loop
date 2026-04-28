# PRD: v0.7.3 — patch-tier (N28 reactive + housekeeping + retrospective)

**Status:** Approved
**Date:** 2026-04-28
**Design doc:** `docs/plans/2026-04-28-v0.7.3-bundle-design.md`
**Source:** Internal code review of v0.7.2 (3 test-adequacy gaps)
**Branch (planned):** `ql/v0.7.3-bundle`
**Target version:** 0.7.3 (patch bump from 0.7.2)
**Total effort estimate:** ~0.5 day

## Section 1: Introduction / Overview

2-story reactive patch closing 3 test-adequacy gaps surfaced by internal code review of v0.7.2 + housekeeping commit for missed v0.7.2 design+PRD + retrospective. Ninth multi-cycle populated-CSV run (24 → 27 rows). First v0.7.x cycle triggered by internal code review (vs operator-driven or soliton-driven).

## Section 2: Goals

- Close N28 (3 test-adequacy gaps from v0.7.2 internal code review).
- Commit v0.7.2 design+PRD that were never staged.
- Bump plugin version 0.7.2 → 0.7.3.
- Populate `metrics/pre-impl-review-findings.csv` with ≥3 new rows (total ≥27).
- G30 self-validation re-run (expected: 9th consecutive LOW).

## Section 3: User Stories

### US-001: N28 — test-adequacy fixes

**Acceptance Criteria:**
- [ ] `tests/test_orchestrator_liveness.sh` Test 8 gains a 4th assertion greping `out8` for the literal substring `[QL-EXECUTE] orchestrator-stale — respawning via QL_RESPAWN_CMD`.
- [ ] `tests/test_orchestrator_liveness.sh` Test 10 gains wall-clock capture (`t0=$(date +%s)` before the command, `t1=$(date +%s); elapsed=$((t1 - t0))` after) and asserts `(( elapsed <= 10 ))` with a TOTAL++ counter.
- [ ] `tests/test_orchestrator_liveness.sh` Test 10 gains an assertion greping `out10` for the literal substring `QL_RESPAWN_CMD exited 42 — respawn may have failed`.
- [ ] Existing 24 assertions remain green; +3 new assertions across Tests 8 and 10.
- [ ] Final test count: 27/27 PASS.

### US-002: Housekeeping + retrospective + version bump 0.7.2 → 0.7.3

**Acceptance Criteria:**
- [ ] `docs/plans/2026-04-28-v0.7.2-bundle-design.md` committed (housekeeping — was authored but missed in v0.7.2 commit set).
- [ ] `tasks/prd-v0.7.2-bundle.md` committed (housekeeping — same as above).
- [ ] `idea-stage/PIPELINE_REPORT_v14.md` documents v0.7.3 dogfood (2 stories, internal-review trigger source, G30 result, test-suite delta).
- [ ] `idea-stage/IDEA_REPORT_v14.md` lists what's open after v0.7.3 (expected: G19/G21/G24/P5.* unchanged; N25/N26/N27 carry over; N28 closed).
- [ ] `quantum-loop.sh --audit` output captured.
- [ ] G30 self-validation captured; `automated:true` recorded.
- [ ] CHANGELOG [0.7.3] entry covering N28 + housekeeping note.
- [ ] All 4 plugin manifest version fields bumped 0.7.2 → 0.7.3.

## Section 4: Functional Requirements

- **FR-1:** `tests/test_orchestrator_liveness.sh` Test 8 has 4 assertions (was 3).
- **FR-2:** `tests/test_orchestrator_liveness.sh` Test 10 has 3 assertions (was 1).
- **FR-3:** Total liveness test count: 27/27 PASS (24 → 27).
- **FR-4:** `docs/plans/2026-04-28-v0.7.2-bundle-design.md` and `tasks/prd-v0.7.2-bundle.md` exist in master tree.
- **FR-5:** CSV ≥27 rows; plugin version 0.7.2 → 0.7.3; reviews recorded with `automated:true`.

## Section 5: Non-Goals

- Adding wall-clock guards to Tests 9 (current `2>&1` pattern + `|| rc=$?` is already robust against hangs in the handoff path).
- Changing the lib `wrap_orchestrator_dispatch` function — purely test-side fixes.
- Bumping to 0.8.0 — patch-tier per strict semver.

## Section 6: Design Notes

See `docs/plans/2026-04-28-v0.7.3-bundle-design.md` for full per-story design.

## Section 7: Technical Notes

Cross-platform: bash 4.3+. No new env vars. No schema changes. No breaking changes.

## Section 8: Success Metrics

All 2 stories first-attempt PASS; CSV at ≥27 rows; 9th consecutive LOW G30 classification; 24 → 27 liveness-test assertions.

## Section 9: Open Questions

None.

## Lifecycle Checklist

Standard. No env var changes; no schema changes; no breaking changes.

## Next Steps

Advisory hooks → quantum.json → execute → PR → soliton → squash-merge → tag v0.7.3.
