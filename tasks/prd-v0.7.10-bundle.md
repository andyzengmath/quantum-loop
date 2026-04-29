# PRD: v0.7.10 — patch-tier (N35 real-task dispatch + smoke→dispatch reframe)

**Status:** Approved
**Date:** 2026-04-28
**Design doc:** `docs/plans/2026-04-28-v0.7.10-bundle-design.md`
**Source:** `idea-stage/IDEA_REPORT_v20.md` v0.9.0 candidate N35 (descoped to v0.7.10 patch)
**Branch (planned):** `ql/v0.7.10-bundle`
**Target version:** 0.7.10 (patch bump from 0.7.9)
**Total effort estimate:** ~75-90 min

## Section 1: Introduction / Overview

7 stories closing N35 (real-task dispatch beyond version probe) + smoke→dispatch reframe. Patch-tier; operator-driven extension of v0.7.4 N5 + v0.7.7 N30 multi-runner foundation. Eleventh multi-cycle populated-CSV run.

## Section 2: Goals

- Add `runner_dispatch <runner_name> <prompt>` wrapper in `lib/runner.sh`.
- Add real-task dispatch tests for codex + copilot (skip-aware on missing binaries).
- Add multi-runner E2E dispatch test exercising claude+codex+copilot.
- Reframe smoke/dispatch test layers in documentation.
- Maintain 0-retry execution record.
- Bump plugin version 0.7.9 → 0.7.10.
- Populate `metrics/pre-impl-review-findings.csv` with ≥3 new rows.
- G30 self-validation re-run (expected: 15th consecutive LOW).

## Section 3: User Stories

### US-001: `runner_dispatch` wrapper + unit tests

**Acceptance Criteria:**
- [ ] `lib/runner.sh` adds `runner_dispatch <runner_name> <prompt>` function. Calls `runner_load` + `runner_build_cmd`, evaluates the command, returns the runner's exit code. Stdout is the runner's stdout; stderr passes through.
- [ ] `tests/test_runner_dispatch.sh` (new) creates a mock manifest pointing `binary: "echo"`, dispatches a prompt → expects output containing the prompt text, rc=0.
- [ ] Mock manifest is created in a tmp dir and removed on test exit (no permanent fixture).
- [ ] Existing tests (`test_runner.sh`, `test_runner_load.sh`, `test_runner_integration.sh`) continue to pass.

### US-002: Codex real-task dispatch test

**Acceptance Criteria:**
- [ ] `tests/test_codex_dispatch.sh` (new) sources `lib/runner.sh`, dispatches `runner_dispatch codex "Reply with the word OK"`.
- [ ] If `command -v codex` fails → SKIP entire test with informational message; rc=0.
- [ ] If codex is installed → assert rc=0 from dispatch, assert stdout is non-empty, wall-clock ≤60s.
- [ ] Test header comments document the smoke/dispatch layer distinction.

### US-003: Copilot real-task dispatch test

**Acceptance Criteria:**
- [ ] `tests/test_copilot_dispatch.sh` (new) mirrors US-002 for copilot.
- [ ] If `command -v copilot` fails → SKIP; rc=0.
- [ ] If installed → assert rc=0 + non-empty stdout + wall-clock ≤60s.

### US-004: Multi-runner E2E dispatch test

**Acceptance Criteria:**
- [ ] `tests/test_multi_runner_dispatch_e2e.sh` (new) iterates over `claude codex copilot`.
- [ ] For each runner: skip if binary not installed (increment `skipped` counter); else dispatch tiny prompt and assert rc=0 + non-empty stdout (increment `dispatched` counter).
- [ ] Final assertion: `dispatched + skipped == 3`. Tally printed at end.
- [ ] Wall-clock ≤180s overall (3 runners × 60s each).

### US-005: Documentation refresh

**Acceptance Criteria:**
- [ ] `CLAUDE.md` Process references area gains a "Multi-runner test layers" subsection distinguishing **smoke** (version-probe, health check) from **dispatch** (real-task end-to-end) test classes.
- [ ] `lib/runner.sh` header comment adds a 2-line note about `runner_dispatch` as the dispatch entry-point.
- [ ] Grep verification: CLAUDE.md contains "smoke" and "dispatch" sections; `lib/runner.sh` head contains `runner_dispatch`.

### US-006: Smoke→dispatch reframe

**Acceptance Criteria:**
- [ ] `tests/test_codex_runner_smoke.sh` header comment updated to clarify smoke = health-check layer (binary present + manifest loadable), dispatch tests cover behavioral verification.
- [ ] `tests/test_copilot_runner_smoke.sh` same update.
- [ ] No behavioral test changes — pure documentation. Existing assertion counts unchanged.

### US-007: Retrospective + IDEA_REPORT_v21 + version bump 0.7.9 → 0.7.10

**Acceptance Criteria:**
- [ ] `idea-stage/PIPELINE_REPORT_v21.md` documents v0.7.10 dogfood.
- [ ] `idea-stage/IDEA_REPORT_v21.md` lists open after v0.7.10 (expected: N33 worktree drift carry-over; N35 closed).
- [ ] `quantum-loop.sh --audit` captured.
- [ ] G30 self-validation captured; `automated:true` recorded.
- [ ] CHANGELOG [0.7.10] entry covering all 6 stories.
- [ ] All 4 plugin manifest version fields bumped 0.7.9 → 0.7.10.

## Section 4: Functional Requirements

- **FR-1:** `runner_dispatch <name> <prompt>` exists in `lib/runner.sh`; loads manifest + builds + executes via eval; returns runner's rc; emits stdout.
- **FR-2:** Codex/Copilot dispatch tests skip silently when binary not installed; assert rc=0 + non-empty output when binary present.
- **FR-3:** E2E test verifies dispatched + skipped == 3 invariant.
- **FR-4:** CLAUDE.md documents smoke vs dispatch layer distinction.
- **FR-5:** CSV ≥33 rows; plugin version 0.7.9 → 0.7.10; reviews recorded with `automated:true`.

## Section 5: Non-Goals

- Worktree subagent drift root-cause investigation (N33 still defers to v0.9.0+).
- New runner additions beyond claude/codex/copilot.
- Bumping to 0.8.0 — patch-tier per agreed framing.
- Rewriting `lib/spawn.sh` to use `runner_dispatch` (existing callers unchanged).

## Section 6: Design Notes

See `docs/plans/2026-04-28-v0.7.10-bundle-design.md` for full per-story design.

## Section 7: Technical Notes

Cross-platform: bash 4.3+. No new dependencies. Optional CLIs gate via skip-aware tests. No schema changes; no breaking changes.

## Section 8: Success Metrics

All 7 stories first-attempt PASS; CSV at ≥33 rows; 15th consecutive LOW G30 classification; runner test suite gains 4 new test files (dispatch unit + codex + copilot + E2E).

## Section 9: Open Questions

None.

## Lifecycle Checklist

Standard. New env vars: none. No schema changes; no breaking changes.

## Next Steps

Advisory hooks → quantum.json → execute → PR → squash-merge → tag v0.7.10.
