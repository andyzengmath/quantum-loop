# PRD: v0.9.5 — patch-tier (decomposition + parent-side guard + ADR)

**Status:** Approved
**Date:** 2026-05-01
**Design doc:** `docs/plans/2026-05-01-v0.9.5-bundle-design.md`
**Source:** `idea-stage/v0.10.0-design-spike-2026-05-01.md` (3-architect spike synthesis post-v0.9.4 ship; tier rebased v0.10.0 minor → v0.9.5 patch).
**Branch:** `ql/v0.9.5-bundle`
**Target version:** 0.9.5 (patch from 0.9.4)
**Total effort:** ~5 hours

## Section 1: Introduction / Overview

5-story patch implementing the v0.10.0 spike synthesis findings — decomposition refactor + parent-side `guard_head_advance` defense-in-depth + ADR documenting outer-loop architecture. Patch-tier per operator memory ("default to patch unless genuinely architectural"). Spike showed work is mechanical refactor + small defense + docs; not architectural.

## Section 2: Goals

- Decompose `quantum-loop.sh` (1837 LOC) into 4 files (main + 3 new libs); main → ~330 LOC.
- Add parent-side `guard_head_advance` check at `quantum-loop.sh:~1672` (defense-in-depth; closes "LLM instruction-following dependency" gap from arc audit).
- Author ADR-001 documenting cron `/loop` as canonical outer-loop architecture; remove "daemon-style runner" from forward docs.
- 7th application of multi-perspective post-merge review pattern.
- Bump 0.9.4 → 0.9.5 (4 manifest fields).
- CSV ≥67 rows.

## Section 3: User Stories

### US-001: Decompose `quantum-loop.sh`

**Acceptance Criteria:**
- [ ] New files: `lib/audit.sh` (~420 LOC), `lib/iteration-loop.sh` (~400 LOC), `lib/loop-helpers.sh` (~300 LOC). Each with source guard + header comments documenting required globals.
- [ ] `quantum-loop.sh` reduced from 1837 → ~330-400 LOC. Contains: shebang, defaults, CLI parsing, dependency checks, sourcing block, pre-loop setup, mode dispatch.
- [ ] Loop body in `lib/iteration-loop.sh` wrapped in `run_iteration_loop()` function.
- [ ] Parallel-mode block stays in `quantum-loop.sh` (deferred to v0.10.0+).
- [ ] `bash -n quantum-loop.sh` clean.
- [ ] All 6 v0.9.x test suites green: `test_next_wave.sh` 18/18, `test_coordinator_e2e.sh` 18/18, `test_signal_parsing.sh` 15/15, `test_orchestrator_liveness.sh` 34/34, `test_quantum_loop_recovery.sh` 5/5, `test_coordinator_dispatch.sh` 7/7, `test_dag_query.sh` 44/44, `test_coordinator_guard.sh` 8/8, `test_quantum_validate.sh` 11/11.
- [ ] `bash quantum-loop.sh --audit` returns same output as before extraction.

### US-002: Parent-side `guard_head_advance` + Test 8

**Acceptance Criteria:**
- [ ] HEAD capture at `quantum-loop.sh` (or wherever the coordinator branch lives post-decomposition) before `eval "$COORD_CMD"`.
- [ ] Guard invocation after `runner_parse_output` + timeout override; on failure: print ERROR pattern `Parent-side HEAD guard fired` + force `SIGNAL_RESULT="WAVE_FAILED"`.
- [ ] New Test 8 in `tests/test_coordinator_e2e.sh` with new stub mode `head_reset` (does `git reset --hard HEAD~1`; echoes WAVE_PASSED). Asserts: ERROR pattern present + per-story aggregation marks both stories failed.
- [ ] Test count: 18/18 → 21/21 (+3 from Test 8 asserts).
- [ ] `bash -n quantum-loop.sh` clean.

### US-003: ADR-001 outer-loop architecture decision record

**Acceptance Criteria:**
- [ ] `references/adr-001-outer-loop-architecture.md` (NEW) with sections: Status, Context, Decision, Consequences, Triggers for revisit.
- [ ] Decision documented: cron `/loop` is canonical; no persistent daemon will be built.
- [ ] `idea-stage/IDEA_REPORT_v31.md` (or v32 if newer) updated with ADR reference.
- [ ] grep negative test: no "daemon-style runner" mentions in forward-looking docs (`idea-stage/IDEA_REPORT_v31.md` or v32).
- [ ] `CLAUDE.md` Process references "Coordinator-related" subsection optionally cross-references the ADR.

### US-004: Multi-perspective post-merge review (7th application)

**Acceptance Criteria:**
- [ ] 3 reviewer agents invoked in parallel: architect + code-reviewer + security.
- [ ] Findings logged in retrospective.
- [ ] Synthesis section: which findings addressed inline + which deferred.
- [ ] No score-≥85 finding deferred.

### US-005: Retrospective + IDEA_REPORT_v32 + version bump 0.9.4 → 0.9.5

**Acceptance Criteria:**
- [ ] `idea-stage/PIPELINE_REPORT_v32.md` documents v0.9.5 (5 stories, US-004 review synthesis, decomposition outcomes).
- [ ] `idea-stage/IDEA_REPORT_v32.md` rolling forward state. Documents v0.9.x track structurally CLOSED; future work is v0.9.6 housekeeping or v0.10.0 feature work.
- [ ] `CHANGELOG.md [0.9.5]` entry.
- [ ] 4 plugin manifest version fields bumped 0.9.4 → 0.9.5.
- [ ] G30 self-validation captured.

## Section 4: Functional Requirements

- **FR-1:** Decomposition is behavior-preserving (no logic changes; all tests pass).
- **FR-2:** Parent-side guard defense-in-depth keeps LLM-side instruction; both layers active.
- **FR-3:** ADR-001 sufficient documentation; no further "daemon-style runner" planning.
- **FR-4:** US-004 review surfaces no blocking findings (or all addressed inline).
- **FR-5:** CSV ≥67 rows; plugin version 0.9.4 → 0.9.5.

## Section 5: Non-Goals

- No daemon implementation (per ADR-001).
- No parallel-mode decomposition (v0.10.0+).
- No `json_atomic_update` migration or `exit_complete`/`exit_blocked` helper extraction (deferred).
- No N40, N43, N46, N47-N50.
- No real-feature dogfood.
- No PowerShell parity.

## Section 6: Design Notes

See `docs/plans/2026-05-01-v0.9.5-bundle-design.md` and `idea-stage/v0.10.0-design-spike-2026-05-01.md`.

## Section 7: Technical Notes

Bash 4.3+. No new dependencies. No schema changes. Mechanical refactor preserves all existing behaviors. New ADR convention introduced (`references/adr-NNN-*.md`).

## Section 8: Success Metrics

- All 5 stories first-attempt PASS.
- CSV ≥67 rows.
- `quantum-loop.sh` LOC reduced from 1837 → ≤400.
- 9 test suites green (124+3 = ~127 assertions).
- `references/adr-001-outer-loop-architecture.md` present.

## Section 9: Open Questions

- **Q1:** Should US-001 also extract parallel-mode block? **Decision:** No — defer to v0.10.0+. Scope creep risk; v0.9.5 stays focused.
- **Q2:** Should US-002 replace LLM-side guard instruction with parent-side only? **Decision:** No — keep both layers per spike-3 recommendation (per-story attribution from LLM; instruction-independence from parent).
- **Q3:** Tier — patch (0.9.5) or minor (0.10.0)? **Decision:** patch (0.9.5) per operator memory + spike conclusion.
