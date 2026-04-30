# PRD: v0.9.4 — patch-tier (housekeeping from v0.9.x audit)

**Status:** Approved
**Date:** 2026-04-30
**Design doc:** `docs/plans/2026-04-30-v0.9.4-bundle-design.md`
**Source:** `idea-stage/v0.9.x-arc-audit-2026-04-30.md` (3-agent audit findings).
**Branch:** `ql/v0.9.4-bundle`
**Target version:** 0.9.4 (patch from 0.9.3)
**Total effort:** ~3-4 hours

## Section 1: Introduction / Overview

6-story patch closing 1 HIGH (multi-story log under coord mode) + 2 MEDIUM (doc gaps; test coverage) surfaced by the post-v0.9.3 audit. Last housekeeping cycle before v0.10.0 design phase (architect-recommended outer-loop replacement).

## Section 2: Goals

- Purge stale references in `agents/coordinator.md`.
- Fix HIGH log issue (`quantum-loop.sh:1544-1548` shows only first wave story under coord mode).
- Document `QL_COORDINATOR_TIMEOUT_S` + new helper libs in `CLAUDE.md`.
- Add `next_wave` test coverage to `tests/test_dag_query.sh`.
- Multi-perspective post-merge review (6th application).
- Bump 0.9.3 → 0.9.4.
- CSV ≥64 rows.

## Section 3: User Stories

### US-001: agents/coordinator.md cleanup

**Acceptance Criteria:**
- [ ] `agents/coordinator.md` L73 ("v0.8.1 will dogfood") rewritten in past tense or removed.
- [ ] L89 + L98 ("v0.9.0 N42 will enforce") rewritten in past tense.
- [ ] L121-122 Forward References updated to point at `IDEA_REPORT_v30.md` or remove N42 references (shipped).
- [ ] L85 Liveness section corrected: notes that `ql_wrap_subagent_dispatch` is gated OFF under `--coordinator` mode since v0.9.0; cross-references `QL_COORDINATOR_TIMEOUT_S` (v0.9.3) as the operational alternative.
- [ ] No grep hits for `will dogfood\|will enforce` in `agents/coordinator.md` (forward-tense for shipped work).

### US-002: HIGH log fix (quantum-loop.sh per-story metadata under coord mode)

**Acceptance Criteria:**
- [ ] `quantum-loop.sh:1544-1548` (the `Story:` and `Attempt:` printf block) is gated under `if [[ "$COORDINATOR_MODE" != "true" ]]; then ... fi`.
- [ ] Legacy mode behavior byte-for-byte unchanged (verifiable via diff against v0.9.3 baseline).
- [ ] Coordinator mode now skips the misleading per-story metadata print; relies on line 1591 wave-summary message.
- [ ] `bash -n quantum-loop.sh` clean.
- [ ] Existing `test_coordinator_e2e.sh` continues to pass (18/18).

### US-003: Document QL_COORDINATOR_TIMEOUT_S

**Acceptance Criteria:**
- [ ] `CLAUDE.md` documents `QL_COORDINATOR_TIMEOUT_S` env var (default 1800s; configures wallclock timeout under `--coordinator`).
- [ ] `CLAUDE.md` lists `lib/coordinator-guard.sh` (with one-line description) under Process references or new "Coordinator helpers" subsection.
- [ ] `CLAUDE.md` lists `lib/quantum-validate.sh` (with one-line description).
- [ ] grep `QL_COORDINATOR_TIMEOUT_S` `CLAUDE.md` returns at least 1 match.

### US-004: Test coverage — next_wave + integration

**Acceptance Criteria:**
- [ ] `tests/test_dag_query.sh` adds ≥4 new `next_wave` cases (happy path / COMPLETE / BLOCKED / preamble-hook stderr capture).
- [ ] All existing `test_dag_query.sh` cases continue to pass.
- [ ] `tests/test_coordinator_e2e.sh` continues 18/18.
- [ ] `tests/test_next_wave.sh` continues 18/18 (separate file; pre-existing).

### US-005: Multi-perspective post-merge review

**Acceptance Criteria:**
- [ ] 3 parallel reviewer agents invoked (architect + code-reviewer + security).
- [ ] Findings logged in retrospective.
- [ ] No score-≥85 finding deferred.

### US-006: Retrospective + IDEA_REPORT_v31 + version bump 0.9.3 → 0.9.4

**Acceptance Criteria:**
- [ ] `idea-stage/PIPELINE_REPORT_v31.md` documents v0.9.4 (6 stories, US-005 review synthesis).
- [ ] `idea-stage/IDEA_REPORT_v31.md` rolling forward state. v0.10.0 candidate slate refined.
- [ ] `CHANGELOG.md [0.9.4]` entry.
- [ ] 4 plugin manifest version fields bumped 0.9.3 → 0.9.4.
- [ ] G30 self-validation captured.

## Section 4: Functional Requirements

- **FR-1:** Doc cleanup must update agents/coordinator.md only; no behavioral change.
- **FR-2:** US-002 log gate must be conditional only; no removal of the legacy print.
- **FR-3:** US-003 must document operator-facing API (env var + helper libs).
- **FR-4:** US-004 test additions must not break existing tests (regression-guard).
- **FR-5:** CSV ≥64 rows; plugin version 0.9.3 → 0.9.4.

## Section 5: Non-Goals

- No structural refactors (json_atomic_update migration, exit_complete/exit_blocked helpers) — defer to v0.10.0.
- No real-feature dogfood — defer to v0.10.0 validation.
- No N46 / N43 / N47-N50 work.
- No PowerShell parity.

## Section 6: Design Notes

See `docs/plans/2026-04-30-v0.9.4-bundle-design.md`.

## Section 7: Technical Notes

Bash 4.3+. No new dependencies. No schema changes. Pure cleanup + 1 log gate + test additions.

## Section 8: Success Metrics

- All 6 stories first-attempt PASS.
- CSV at ≥64 rows.
- Test count: 116 → 120+ (≥4 added).
- US-001 grep negative test: no `will dogfood\|will enforce` in agents/coordinator.md.
- US-003 grep positive test: `QL_COORDINATOR_TIMEOUT_S` in CLAUDE.md.

## Section 9: Open Questions

- **Q1:** Should US-001 also condense the 29-line comment block at quantum-loop.sh:1664-1692 (code-reviewer LOW)? **Decision:** No — defer to v0.10.0 alongside structural refactors. v0.9.4 stays focused on docs + 1 log gate + tests.
- **Q2:** Should US-003 cross-reference all v0.9.x changes in CLAUDE.md? **Decision:** No — only the operator-facing surface (env var + helper lib pointers). Keep CLAUDE.md focused.
