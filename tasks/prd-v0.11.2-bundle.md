# PRD: v0.11.2 — patch-tier (D-medium: N48 negative-path test + CLAUDE.md doc updates)

**Status:** Operator-approved D-medium scope (post-comprehensive-review). Closes 5 findings.
**Date:** 2026-05-02
**Predecessor:** `tasks/prd-v0.11.1-bundle.md`.
**Branch:** `ql/v0.11.2-bundle`.
**Target version:** 0.11.1 → 0.11.2 (patch).
**Total effort:** ~1 hour.

## Section 1: Introduction / Overview

4-story patch closing 5 findings from the post-v0.11.1 comprehensive review:
1. **N48 negative-path test** — pairs with v0.11.0 Test 9 (positive); confirms detection symmetry.
2. **CLAUDE.md `iteration-loop.sh:~212` line refs stale** (HIGH-1; v0.11.1 wire shifted dispatch to ~224/~227).
3. **CLAUDE.md missing `QL_PARALLEL_POLL` env var docs** (MEDIUM-1).
4. **CLAUDE.md missing `dispatch_with_parallel_poll` reference** (MEDIUM-2).
5. **Platform Notes missing trap-RETURN-nesting invariant** (MEDIUM-3).

## Section 2: Goals

- Add Test 10 (N48 negative-path) to `tests/test_coordinator_e2e.sh`.
- Update CLAUDE.md "Coordinator-related" section with v0.11.1 surface (line refs + 2 new bullets).
- Add Platform Notes entry for trap-RETURN-nesting invariant.
- 27th p014 review.
- Bump 0.11.1 → 0.11.2.
- 46 consecutive LOW G30.

## Section 3: User Stories

### US-001: N48 negative-path test (Test 10)

**Acceptance Criteria:**
- [ ] New Test 10 added to `tests/test_coordinator_e2e.sh` after Test 9 (before "=== Results:" line).
- [ ] Reuses existing `passed` stub mode (line 97-106) — already field-ownership-compliant by design (writes only `review.*` fields, never touches `.stories[].status`). No new stub mode required.
- [ ] 4 sub-asserts:
  - **Positive control:** `assert_contains "Test 10: stdout mentions Wave PASSED" "Wave (wave-1) PASSED" "$OUT"` (matches Test 1's assertion).
  - **Negative — WARN absence:** assert `[FIELD-OWNERSHIP] WARN` does NOT appear in `$OUT`. Pattern: `! grep -qF "[FIELD-OWNERSHIP] WARN"`.
  - **Negative — before:/after: absence:** assert `before:` JSON line does NOT appear (negative side-effect of WARN absence).
  - **Status correctness:** `assert_eq "Test 10: US-A status=passed" "passed" "$US_A_STATUS"` AND `US-B status=passed`.
- [ ] Test counter increments: 27 → 31 (4 new sub-asserts; matches positive Test 9's 6-assert structure but smaller scope since the "no-op" case has fewer state-changes to verify).
- [ ] `bash -n tests/test_coordinator_e2e.sh` clean.
- [ ] `bash tests/test_coordinator_e2e.sh` rc=0; 31/31.

### US-002: CLAUDE.md doc updates (4 gaps)

**Acceptance Criteria:**
- [ ] **Edit 1 (HIGH-1):** CLAUDE.md lines 263-264 — bump line refs:
  - `lib/iteration-loop.sh:~212` → `lib/iteration-loop.sh:~224` (timeout-guarded dispatch; v0.11.1 wire-insertion shifted).
  - `line 215` → `line 227` (no-timeout fallback).
- [ ] **Edit 2 (MEDIUM-1 + MEDIUM-2):** Add new bullet(s) to "Coordinator-related" section documenting:
  - `QL_PARALLEL_POLL` env var (default `false`; v0.11.1 / US-002).
  - `QL_PARALLEL_POLL_TIMEOUT_S` (default 600s).
  - `QL_PARALLEL_POLL_INTERVAL_S` (default 60s).
  - Wire site: `lib/iteration-loop.sh:247-253`.
  - Explicit clarification: this is for LEGACY (non-coordinator) dispatch path; coordinator uses `QL_COORDINATOR_TIMEOUT_S` instead.
  - `lib/orchestrator-liveness.sh::dispatch_with_parallel_poll` function reference (signature, opt-in gate, race-fix note).
- [ ] **Edit 3 (MEDIUM-3):** CLAUDE.md "Platform Notes" section — add trap-RETURN-nesting invariant entry. Cross-reference inline invariant comment at `lib/orchestrator-liveness.sh:~211`.

### US-003: Multi-perspective post-merge review (27th application)

**Acceptance Criteria:**
- [ ] 3 reviewer agents (architect + code-reviewer + security) invoked in parallel.
- [ ] No score-≥85 finding deferred.

### US-004: Retrospective + IDEA_REPORT_v52 + version bump 0.11.1 → 0.11.2

**Acceptance Criteria:**
- [ ] `idea-stage/PIPELINE_REPORT_v52.md` documents v0.11.2 (4 stories) + comprehensive-review credit (5 findings closed).
- [ ] `idea-stage/IDEA_REPORT_v52.md` rolling forward state. Remaining v0.11.x backlog: Path B (operator-queued), Path E (test file split when worth it), copilot-hooks coverage (v0.11.3 candidate), pre-Path-B field-ownership escalation policy.
- [ ] `CHANGELOG.md [0.11.2]` entry.
- [ ] 4 plugin manifest version fields bumped 0.11.1 → 0.11.2.
- [ ] G30 self-validation (46th consecutive LOW expected).

## Section 4: Functional Requirements

- **FR-1:** Test 10 reuses existing `passed` stub mode; no new stub authoring.
- **FR-2:** CLAUDE.md "Coordinator-related" section now accurately reflects both coordinator (`QL_COORDINATOR_TIMEOUT_S`) and legacy non-coordinator (`QL_PARALLEL_POLL`) dispatch paths.
- **FR-3:** Platform Notes documents trap-RETURN-nesting as a project-wide bash invariant.
- **FR-4:** Plugin version 0.11.1 → 0.11.2 (4 fields).

## Section 5: Non-Goals

- No copilot-hooks::post_output test coverage (deferred to v0.11.3 per critic recommendation; ~150 LOC own cycle).
- No build_coordinator_prompt content assertions (deferred to v0.11.3).
- No Path E test file split (deferred; file at ~615 LOC = AT threshold but not OVER critical mass).
- No field-ownership WARN→FAIL escalation policy decision (pre-Path-B operator-decision item; separate from D-medium).
- No `run_iteration_loop` / `run_parallel_mode` decomposition (architect HIGH structural debt; future architectural cycle).

## Section 6: Design Notes

**Test 10 negative-path design rationale:** The positive Test 9 (v0.11.0) validates that the v0.10.8 N48 WARN fires when contract is violated. Test 10's job is to validate that the WARN does NOT fire when contract is respected — proving N48 detection is symmetric (no false positives). Without Test 10, N48 could in principle be over-firing (e.g., always WARNing regardless of actual violation) and Test 9 would still pass. Together they form a complete observational pair.

**CLAUDE.md "Coordinator-related" naming:** technically the section name is becoming a misnomer with `QL_PARALLEL_POLL` (non-coordinator). Consider renaming to "Dispatch helpers" in a future cycle — for v0.11.2, keep the name and add explicit "(non-coordinator)" qualifiers in the new bullets to disambiguate.

## Section 7: Technical Notes

Markdown-only (CLAUDE.md) + bash test addition (~30 LOC). No new dependencies.

## Section 8: Success Metrics

- All 4 stories first-attempt PASS.
- `tests/test_coordinator_e2e.sh`: 27 → 31 tests (+4 sub-asserts in Test 10).
- 6 baseline test suites green: 15+31+44+39+18+46 = 193.
- 46 consecutive LOW G30.
- 5 comprehensive-review findings closed (1 N48 coverage gap + 4 doc gaps).
