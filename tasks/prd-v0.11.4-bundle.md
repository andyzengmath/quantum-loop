# PRD: v0.11.4 — patch-tier (emit_terminal_signal coverage + Path E test split)

**Status:** Operator-approved. Closes the LAST autonomous-tier MEDIUM from comprehensive review.
**Date:** 2026-05-03
**Predecessor:** `tasks/prd-v0.11.3-bundle.md`.
**Branch:** `ql/v0.11.4-bundle`.
**Target version:** 0.11.3 → 0.11.4 (patch).
**Total effort:** ~1.5 hours.

## Section 1: Introduction / Overview

4-story patch closing 2 items from the post-v0.11.1 comprehensive review:
1. **`emit_terminal_signal` direct test coverage** — last MEDIUM autonomous-tier gap (architect flag; called from 5 sites; zero direct tests; formatting regression silently breaks parent-agent signal parsing).
2. **Path E: `tests/test_orchestrator_liveness.sh` split** — file at ~615 LOC (over the architect's 600 threshold).

## Section 2: Goals

- Add direct test coverage for `lib/loop-helpers.sh::emit_terminal_signal` in NEW `tests/test_loop_helpers.sh`.
- Split `tests/test_orchestrator_liveness.sh` into 2 cohesive files preserving test count + numbering scheme.
- 29th p014 review.
- Bump 0.11.3 → 0.11.4.
- 48 consecutive LOW G30.
- **After this cycle: autonomous backlog from comprehensive review COMPLETELY CLOSED.**

## Section 3: User Stories

### US-001: `emit_terminal_signal` direct test coverage

**Acceptance Criteria:**
- [ ] New `tests/test_loop_helpers.sh` (does not require any external CLI; pure shell-function tests).
- [ ] Sources `lib/loop-helpers.sh` directly; invokes `emit_terminal_signal` with various signal names + messages.
- [ ] **6 tests covering function contract:**
  - Test 1: required signal-name arg — call without args fails (`${1:?...}`).
  - Test 2: signal-only call — output contains `<quantum>SIGNAL</quantum>`.
  - Test 3: signal + message call — output contains both signal and message.
  - Test 4: separator wrapping — output starts and ends with `===========================================` line.
  - Test 5: all 4 production signal names (COMPLETE, BLOCKED, MAX_ITERATIONS, plus an arbitrary one) emit correctly.
  - Test 6: no side effects — `set -uo pipefail` + invocation returns rc=0; doesn't exit, doesn't modify env.
- [ ] `bash -n tests/test_loop_helpers.sh` clean.
- [ ] `bash tests/test_loop_helpers.sh` rc=0; 6/6.

### US-002: Path E split — `tests/test_orchestrator_liveness.sh` → 2 files

**Acceptance Criteria:**
- [ ] **Original file (`tests/test_orchestrator_liveness.sh`)** retains Tests 1-13 (poll_orchestrator_commits + wrap_orchestrator_dispatch base behavior). Should be ~30 tests after split.
- [ ] **NEW `tests/test_dispatch_helpers.sh`** contains Tests 14-18 (N46 respawn re-parse + N43 parallel-poll dispatch). Renumbered to start at Test 1 in the new file. Should be ~16 tests.
- [ ] Both files independently runnable: `bash tests/test_orchestrator_liveness.sh` rc=0; `bash tests/test_dispatch_helpers.sh` rc=0.
- [ ] **Total test count preserved:** original 46 = ~30 (orchestrator-liveness) + ~16 (dispatch-helpers).
- [ ] Both files share same framework boilerplate (assert, assert_emits, mktemp -d setup, etc.).
- [ ] `bash -n` clean on both files.
- [ ] No production code changes — pure test-file refactor.

### US-003: Multi-perspective post-merge review (29th application)

**Acceptance Criteria:**
- [ ] 3 reviewer agents (architect + code-reviewer + security) invoked in parallel.
- [ ] Architect specifically: validate Test 6 actually proves "no side effects" (not just "doesn't crash"); validate split preserves coverage (no test deleted).
- [ ] No score-≥85 finding deferred.

### US-004: Retrospective + IDEA_REPORT_v54 + version bump 0.11.3 → 0.11.4

**Acceptance Criteria:**
- [ ] `idea-stage/PIPELINE_REPORT_v54.md` documents v0.11.4 (4 stories) + closes comprehensive-review autonomous backlog completely.
- [ ] `idea-stage/IDEA_REPORT_v54.md` rolling forward state. Only Path B (operator-queued) + structural-debt remain.
- [ ] `CHANGELOG.md [0.11.4]` entry.
- [ ] 4 plugin manifest version fields bumped 0.11.3 → 0.11.4.
- [ ] G30 self-validation (48th consecutive LOW expected).

## Section 4: Functional Requirements

- **FR-1:** `emit_terminal_signal` test does NOT require any production code changes.
- **FR-2:** Path E split preserves all 46 existing tests (no deletion or merging).
- **FR-3:** Both split files independently runnable + share consistent framework.
- **FR-4:** Plugin version 0.11.3 → 0.11.4 (4 fields).

## Section 5: Non-Goals

- No `run_iteration_loop` / `run_parallel_mode` decomposition (HIGH structural debt; future architectural cycle).
- No Path B real-feature dispatch (operator-queued).
- No pre-Path-B field-ownership policy decision (asynchronous architectural decision; not blocking v0.11.4).

## Section 6: Design Notes

**emit_terminal_signal output format (from `lib/loop-helpers.sh:342-349`):**
```
<newline>
===========================================
  <quantum>$signal</quantum>
  $message              # only when message non-empty
===========================================
```

**Path E split rationale:** the architect's 600-LOC threshold was hit at v0.11.1 ship (file grew from ~495 to ~615 LOC with the +120 LOC for Tests 16/17/18 N43 parallel-poll). Natural split:
- **Tests 1-13** = `poll_orchestrator_commits` core behavior + `wrap_orchestrator_dispatch` base wrap (no respawn). All pre-N46 work.
- **Tests 14-18** = N46 respawn re-parse (Tests 14a/14b/14c/15) + N43 parallel-poll dispatch (Tests 16/17/18). All v0.10.11+ work.

The split aligns with code architecture (orchestrator-liveness has 4 functions; the split file groups by function-clusters).

## Section 7: Technical Notes

Bash 4.3+. No new dependencies.

## Section 8: Success Metrics

- All 4 stories first-attempt PASS.
- NEW: `tests/test_loop_helpers.sh` 6/6.
- Split: `tests/test_orchestrator_liveness.sh` ~30/30 + `tests/test_dispatch_helpers.sh` ~16/16.
- Total: 8 test suites; 211 tests (was 7 suites × 205 at v0.11.3; +6 from emit_terminal_signal tests; split is structural so test count unchanged).
- 48 consecutive LOW G30.
- **Comprehensive-review autonomous backlog: COMPLETELY CLOSED post-v0.11.4.**
