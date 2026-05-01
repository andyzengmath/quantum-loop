# PRD: v0.10.0 — minor-tier (PARALLEL_MODE extraction + housekeeping)

**Status:** Approved
**Date:** 2026-05-01
**Design doc:** `docs/plans/2026-05-01-v0.10.0-bundle-design.md`
**Source:** `idea-stage/IDEA_REPORT_v33.md` § "v0.10.0 candidate slate" + v0.9.6 US-004 deferred findings.
**Branch:** `ql/v0.10.0-bundle`
**Target version:** 0.10.0 (minor from 0.9.6)
**Total effort:** ~5–7 hours

## Section 1: Introduction / Overview

6-story minor cycle closing the LAST audit MEDIUM (PARALLEL_MODE block extraction) plus housekeeping (jq stderr hardening, p013/p014 canonization, real-feature dogfood). The minor-tier framing honors the architectural milestone: "decomposition complete + ADR-001 baked in" — every block in `quantum-loop.sh` is now in its own lib file.

## Section 2: Goals

- Extract PARALLEL_MODE block (quantum-loop.sh:394-784) into `lib/parallel-mode.sh` wrapped in `run_parallel_mode()`. `quantum-loop.sh` 793 → ~400-450 LOC.
- Migrate 8 deferred `jq+tmp+mv` sites (now in extracted block) to `json_atomic_update_args`.
- Migrate 1 deferred COMPLETE/BLOCKED print pair (now in extracted block) to `emit_terminal_signal`.
- `2>/dev/null` symmetric hardening: capture jq stderr in error messages for both `json_atomic_update` + `json_atomic_update_args`.
- Real-feature dogfood (operator decides feature; if no scope ready, US-003 defers to v0.10.1).
- p013 + p014 canonization in CLAUDE.md.
- 9th application of multi-perspective post-merge review pattern.
- Bump 0.9.6 → 0.10.0 (4 manifest fields).
- 28 consecutive LOW G30 self-validation.

## Section 3: User Stories

### US-001: Extract PARALLEL_MODE block + migrate deferred jq/signal sites

**Acceptance Criteria:**

T-001-1 (mechanical extraction):
- [ ] New file `lib/parallel-mode.sh` with source guard (`_QL_PARALLEL_MODE_LIB`), header comment documenting required globals, and the entire current `quantum-loop.sh:394-784` body wrapped in `run_parallel_mode()` function.
- [ ] `quantum-loop.sh` lines 394-784 replaced by 1 `source` + 1 conditional `run_parallel_mode` invocation.
- [ ] `quantum-loop.sh` LOC: 793 → ≤ 450.
- [ ] `lib/parallel-mode.sh` LOC: 380 ≤ X ≤ 500 (extraction overhead).
- [ ] `bash -n quantum-loop.sh` clean.
- [ ] `bash -n lib/parallel-mode.sh` clean.
- [ ] Manual smoke test: `bash quantum-loop.sh --parallel --max-parallel 1 --max-iterations 0` runs the parallel-mode entry without crashing (no agents to dispatch on iteration 0; immediate exit acceptable).
- [ ] Manual Ctrl-C smoke test: kick a parallel-mode run, send SIGINT, verify reaper trap still cleans up.

T-001-2 (jq migration):
- [ ] All `jq <expr> <path> > <path>.tmp && mv <path>.tmp <path>` instances in `lib/parallel-mode.sh` replaced with `json_atomic_update_args` calls.
- [ ] `grep -E 'quantum\.json\.tmp' lib/parallel-mode.sh` returns 0 hits (post-migration).
- [ ] Pre-extraction site count was 8 (per IDEA_REPORT_v32 deferred list); post-migration count must be ≥ 8 helper invocations OR a smaller count if some sites consolidate.

T-001-3 (signal-pair migration):
- [ ] `lib/parallel-mode.sh` previously containing the `quantum-loop.sh:467+476` COMPLETE/BLOCKED print pair now uses `emit_terminal_signal "COMPLETE" ...` / `emit_terminal_signal "BLOCKED" ...`.
- [ ] After migration: `grep -E 'printf .*<quantum>(COMPLETE|BLOCKED)</quantum>' lib/parallel-mode.sh` returns 0 raw printf hits.
- [ ] All 9 test suites green.

### US-002: 2>/dev/null symmetric hardening of json_atomic_update + json_atomic_update_args

**Acceptance Criteria:**
- [ ] `json_atomic_update` jq invocation captures stderr (via mktemp tmp file or local). On empty-output failure, error message includes the captured jq stderr (if non-empty) in format: `ERROR: json_atomic_update: jq filter produced empty output (jq stderr: <captured>)`.
- [ ] `json_atomic_update_args` updated symmetrically.
- [ ] tmp file cleanup via `trap ... RETURN` (or equivalent) — no leaked tmp files on success or failure.
- [ ] `tests/test_json_atomic.sh` adds ≥ 2 test cases (1 for each helper) covering: malformed `--argjson` value triggers a jq error which appears in our error message.
- [ ] Existing 28/28 tests still pass.
- [ ] `bash -n lib/json-atomic.sh` clean.

### US-003: Real-feature dogfood (deferable)

**Acceptance Criteria:**
- [ ] If operator provides feature scope before US-003 execution: dispatch a small (1-3 story) feature bundle through `quantum-loop.sh --coordinator`; observe end-to-end through the decomposed + guarded outer loop; capture findings.
- [ ] If no operator scope ready by US-003 execution time: US-003 status = `deferred` with reason logged in `quantum.json.progress`; US-006 retrospective notes the deferral; cycle still ships.
- [ ] **This story has zero blocking ACs for v0.10.0 ship.**

### US-004: p013 + p014 canonization in CLAUDE.md

**Acceptance Criteria:**
- [ ] CLAUDE.md gains a new section `## Process patterns` (or extends `## Process references`) documenting:
  - **p013** — Operator-staged cycle kickoff. 7 applications (v0.9.0..v0.9.6). Pattern: operator pre-commits design + PRD + advisory hooks before autonomous loop fires.
  - **p014** — Composite review trio (architect + code-reviewer + security). 8 applications post-v0.8.x. Pre-cycle architect-design + post-cycle 3-reviewer trio.
- [ ] Both entries reference the canonical retrospective(s) where the pattern's track record is recorded.
- [ ] No existing CLAUDE.md content removed/altered (additive only).

### US-005: Multi-perspective post-merge review (9th application)

**Acceptance Criteria:**
- [ ] 3 reviewer agents invoked in parallel: architect + code-reviewer + security.
- [ ] Findings logged in retrospective.
- [ ] Synthesis section: which findings addressed inline + which deferred.
- [ ] No score-≥85 finding deferred.
- [ ] PARALLEL_MODE extraction reviewed for trap-handler correctness, global-contract preservation, conditional-source ordering.

### US-006: Retrospective + IDEA_REPORT_v34 + version bump 0.9.6 → 0.10.0

**Acceptance Criteria:**
- [ ] `idea-stage/PIPELINE_REPORT_v34.md` documents v0.10.0 (6 stories incl. US-003 status).
- [ ] `idea-stage/IDEA_REPORT_v34.md` rolling forward state. v0.9.x audit closure complete; future cycles are feature-work or LOW housekeeping.
- [ ] `CHANGELOG.md [0.10.0]` entry documenting: PARALLEL_MODE extraction; jq stderr hardening; pattern canonization; review verdicts.
- [ ] 4 plugin manifest version fields bumped 0.9.6 → 0.10.0.
- [ ] G30 self-validation captured (28th consecutive LOW expected).

## Section 4: Functional Requirements

- **FR-1:** Behavior preservation — `quantum-loop.sh --parallel` end-to-end behavior unchanged.
- **FR-2:** `lib/parallel-mode.sh` MUST be sourced AFTER `lib/json-atomic.sh` and AFTER `lib/loop-helpers.sh` (uses both).
- **FR-3:** jq stderr capture in US-002 must be cleanup-safe (no tmp file leaks on any return path).
- **FR-4:** US-003 is non-blocking — clean-deferral path documented.
- **FR-5:** US-005 review surfaces no blocking findings (or all addressed inline).
- **FR-6:** Plugin version 0.9.6 → 0.10.0 (4 fields).

## Section 5: Non-Goals

- No new PARALLEL_MODE test suite (rely on existing helper-lib coverage + manual smoke).
- No PowerShell parity.
- No new runner support.
- No `quantum.json` schema changes.
- No multi-machine dispatch (per ADR-001 trigger 4).
- No N40, N43, N46, N47-N50.
- No daemon-style work (per ADR-001).

## Section 6: Design Notes

See `docs/plans/2026-05-01-v0.10.0-bundle-design.md` for full block-extraction plan, global-contract handling, decision points, and risk mitigations.

## Section 7: Technical Notes

Bash 4.3+. New lib `lib/parallel-mode.sh` follows existing `lib/iteration-loop.sh` pattern (function-wrapped body + source guard + header documenting required globals). Migration uses helpers shipped in v0.9.6 (`json_atomic_update_args`, `emit_terminal_signal`).

## Section 8: Success Metrics

- All blocking stories (US-001/002/004/005/006) first-attempt PASS.
- US-003 clean-deferral acceptable (no v0.10.0 ship blocker).
- `quantum-loop.sh` LOC ≤ 450 (was 793).
- `lib/parallel-mode.sh` 380 ≤ LOC ≤ 500.
- 0 `quantum.json.tmp` references in `lib/parallel-mode.sh` post-migration.
- 0 raw `printf ... <quantum>(COMPLETE|BLOCKED)</quantum>` in `lib/parallel-mode.sh` post-migration.
- 9 test suites green; `test_json_atomic.sh` 28 → 30+ (+2 stderr-capture asserts).
- 28 consecutive LOW G30 self-validation.

## Section 9: Open Questions

- **Q1:** Tier — minor (0.10.0) or patch (0.9.7)? **Decision:** minor (0.10.0). PARALLEL_MODE extraction is the architectural-milestone closure for the decomposition arc.
- **Q2:** US-003 real-feature dogfood — block v0.10.0 ship if no feature scope? **Decision:** No. Clean-deferral path; cycle ships even if US-003 defers.
- **Q3:** PARALLEL_MODE testing — add new e2e suite? **Decision:** No. Existing helper-lib tests + manual Ctrl-C smoke + behavior-preservation manual test cover this. New e2e too costly for the cycle.
- **Q4:** p013/p014 canonization location — CLAUDE.md or new `references/codebase-patterns.md`? **Decision:** CLAUDE.md `## Process references` (process patterns belong with process docs).
- **Q5:** Should jq stderr capture introduce a new `mktemp` tmp file per call? **Decision:** Yes; cheap; matches existing project pattern. Use `trap ... RETURN` for cleanup.
