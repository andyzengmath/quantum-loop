# PRD: v0.9.0 — minor-tier (N42 — real per-wave coordinator dispatch)

**Status:** Approved
**Date:** 2026-04-29
**Design doc:** `docs/plans/2026-04-29-v0.9.0-bundle-design.md`
**Source:** Operator-scoped post-v0.8.4 close; 3 architect agents designed the sub-problems
**Branch (planned):** `ql/v0.9.0-bundle`
**Target version:** 0.9.0 (minor bump from 0.8.4) — first minor since v0.8.0
**Total effort estimate:** ~6-10 hours

## Section 1: Introduction / Overview

7-story minor cycle replacing single-spawn dispatch with coordinator-driven per-wave dispatch when operators opt in via `--coordinator`. v0.8.x closed the N33 anti-pattern at 4 layers + verified all v0.9.0 prerequisites; v0.9.0 ships the actual cure.

**Architectural newness justifying minor-tier:** new CLI behavior path (`--coordinator` actually does something different from `--legacy-orchestrator` for the first time), new dispatch architecture in the sequential path, new function (`lib/dag-query.sh::next_wave`), and runtime field-ownership enforcement.

## Section 2: Goals

- Amend `agents/coordinator.md:25` to align with field-ownership contract.
- Wire `COORDINATOR_MODE=true` to invoke `spawn_coordinator` at `quantum-loop.sh:1515`.
- Add `lib/dag-query.sh::next_wave` thin composer with 3-way exit code.
- Replace v0.8.3 placeholder WAVE_PASSED/WAVE_FAILED case branches with per-story aggregation.
- Enforce `--coordinator --parallel` mutual exclusion at parse time (hard exit, not warn).
- Ship real-fire integration tests that EXERCISE the dispatch path (not presence-only).
- Bump plugin version 0.8.4 → 0.9.0 (4 manifest fields).
- Populate `metrics/pre-impl-review-findings.csv` with 3 new rows (total ≥52).

## Section 3: User Stories

### US-000: Amend agents/coordinator.md:25 to align with field-ownership contract

**Acceptance Criteria:**
- [ ] `agents/coordinator.md` line 25 (Scope step 4) no longer instructs the coordinator to "set each story's status to passed or failed". Replaced with: "Update each story's `review.specCompliance` and `review.codeQuality` fields based on signals. Do NOT write `stories[].status` — the parent shell owns that field per the field-ownership contract below."
- [ ] Cross-reference between line 25 and the field-ownership contract section (line 105+) added.

### US-001: Inner-dispatch replacement when COORDINATOR_MODE=true

**Acceptance Criteria:**
- [ ] `quantum-loop.sh` adds an outer `if [[ "$COORDINATOR_MODE" == "true" ]]` gate around the spawn block (lines 1515-1532). The new path computes `WAVE_STORIES` from `next_wave quantum.json`, builds `COORD_CMD` via `spawn_coordinator`, and evals it synchronously.
- [ ] Pre-marking: ALL wave stories get `status="in_progress"` + `startedAt` set BEFORE the coordinator spawn (not just one).
- [ ] The `*)` unknown-signal case branch at `quantum-loop.sh:1625+` is gated for coordinator mode: applies retry accounting to ALL `WAVE_STORY_IDS` (not undefined `$STORY_ID`).
- [ ] The `ql_wrap_subagent_dispatch` soft-fire at `quantum-loop.sh:1573-1577` is skipped under `COORDINATOR_MODE=true` (coordinator handles internal retries).
- [ ] `--legacy-orchestrator` path is byte-for-byte unchanged (verifiable via diff against v0.8.4 baseline minus the new outer gate).
- [ ] `bash -n quantum-loop.sh` passes.

### US-002: lib/dag-query.sh::next_wave thin composer + tests

**Acceptance Criteria:**
- [ ] `lib/dag-query.sh` adds a `next_wave [quantum_json_path]` function. Signature: stdout = JSON array of eligible story IDs (no group, just the next wave). Exit codes: 0=wave found, 1=COMPLETE (all passed), 2=BLOCKED (no eligible).
- [ ] Function body composes existing `get_executable_stories` + `filter_file_conflicts` (no logic duplication).
- [ ] New `tests/test_next_wave.sh` with 8 cases: happy path, COMPLETE, BLOCKED, file-conflict reduces wave, multi-dependency gate, in_progress exclusion, in_progress file conflict, empty stories array.
- [ ] All 8 tests pass.

### US-003: Per-story aggregation in WAVE_PASSED/WAVE_FAILED case branches

**Acceptance Criteria:**
- [ ] `quantum-loop.sh` `WAVE_PASSED)` branch: bulk-updates ALL wave stories to `status="passed"` via single jq expression that uses `WAVE_STORY_IDS` array.
- [ ] `WAVE_FAILED)` branch: per-story outcome derived from `review.specCompliance.status` AND `review.codeQuality.status`. Stories with both = "passed" → status=passed; else status=failed + retries.attempts++ + failureLog append.
- [ ] No reference to scalar `$STORY_ID` in either branch (use `WAVE_STORY_IDS` array).
- [ ] Existing test_signal_parsing.sh continues to pass (parser unchanged).

### US-004: CLI guard for --coordinator --parallel

**Acceptance Criteria:**
- [ ] `quantum-loop.sh:672-674` v0.8.1 warning replaced with hard exit (`exit 1`) when both `COORDINATOR_MODE=true` and `PARALLEL_MODE=true`.
- [ ] Error message references `agents/coordinator.md` § "Interaction with --parallel".
- [ ] Test in US-005 case 3 verifies the rejection.

### US-005: Real-fire integration tests for coordinator dispatch

**Acceptance Criteria:**
- [ ] New `tests/test_coordinator_e2e.sh` invokes `quantum-loop.sh --coordinator` against a 2-story stub plan.
- [ ] Test 1: WAVE_PASSED happy path — both stories' status = passed, iteration = 1.
- [ ] Test 2: WAVE_FAILED with partial pass — coordinator writes `review.specCompliance.status="passed"` for US-A only, emits WAVE_FAILED. Assert: US-A status=passed, US-B status=failed, US-B retries.attempts=1.
- [ ] Test 3: `--coordinator --parallel` rejection — exit code 1 + ERROR message.
- [ ] Test 4: COMPLETE path — all stories already passed → COMPLETE signal.
- [ ] All 4 tests pass on fresh checkout.

### US-006: Retrospective + IDEA_REPORT_v27 + version bump 0.8.4 → 0.9.0

**Acceptance Criteria:**
- [ ] `idea-stage/PIPELINE_REPORT_v27.md` documents v0.9.0 (7 stories, outcomes, architectural shift).
- [ ] `idea-stage/IDEA_REPORT_v27.md` lists open after v0.9.0. Confirms manual-takeover streak break (or honest acknowledgement if not).
- [ ] CHANGELOG [0.9.0] entry covering all 6 implementation stories + the architectural rationale.
- [ ] All 4 plugin manifest version fields bumped 0.8.4 → 0.9.0.
- [ ] G30 self-validation captured.

## Section 4: Functional Requirements

- **FR-1:** `--coordinator` actually invokes `spawn_coordinator` at the dispatch decision point.
- **FR-2:** `next_wave` returns parallel-safe eligible story IDs with 3-way exit code.
- **FR-3:** WAVE_PASSED/WAVE_FAILED apply per-story status aggregation (multi-story update).
- **FR-4:** `--coordinator --parallel` rejected at parse time.
- **FR-5:** Integration tests exercise the actual dispatch path (not presence-only).
- **FR-6:** CSV ≥52 rows; plugin version 0.8.4 → 0.9.0; reviews recorded with `automated:true`.

## Section 5: Non-Goals

- No N43 (parallel-with-dispatch wrap pattern); defer to v0.9.1+.
- No N46 (respawn output re-parsing); defer.
- No outer-loop replacement; architect-recommended for v0.10.0.
- No coordinator agent context refactoring; existing definition sufficient.

## Section 6: Design Notes

See `docs/plans/2026-04-29-v0.9.0-bundle-design.md`.

## Section 7: Technical Notes

Cross-platform: bash 4.3+, PowerShell 5.1+. No new dependencies. New CLI-rejection path. New function in lib/. New test file. No schema changes.

## Section 8: Success Metrics

All 7 stories first-attempt PASS; CSV at ≥52 rows; integration tests exercise actual dispatch (not presence-only); manual-takeover streak break (target).

## Section 9: Open Questions

- Q1: Should US-005 stubs use `spawn_coordinator` directly or override via `QL_RESPAWN_CMD`? **Decision in design:** override `spawn_coordinator` via test-mode env var or stub the CLI binary.
- Q2: Should the field-ownership snapshot-diff guard ship in v0.9.0 or defer? **Decision:** defer to v0.9.1 if v0.9.0 ships clean; document as recommended in retrospective.

## Lifecycle Checklist

Standard. New CLI rejection path. New function in lib/. New test file. No schema changes.

## Next Steps

Advisory hooks → quantum.json → execute → PR → squash-merge → tag v0.9.0 → GitHub Release.
