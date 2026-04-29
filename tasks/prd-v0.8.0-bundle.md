# PRD: v0.8.0 — minor-tier (N33 orchestrator drift root-cause closure)

**Status:** Approved
**Date:** 2026-04-28
**Design doc:** `docs/plans/2026-04-28-v0.8.0-bundle-design.md`
**Source:** Operator-scoped N33 closure (informed by 5-agent root-cause research)
**Branch (planned):** `ql/v0.8.0-bundle`
**Target version:** 0.8.0 (minor bump from 0.7.10) — first minor since v0.7.0
**Total effort estimate:** ~5-8 hours

## Section 1: Introduction / Overview

7 stories closing N33 (12+ cycles of orchestrator drift requiring manual takeover). Minor-tier; first new architectural concept since v0.7.4 N5 multi-runner foundation. Twelfth multi-cycle populated-CSV run.

## Section 2: Goals

- Wire dormant recovery infrastructure (`wrap_orchestrator_dispatch`, `poll_orchestrator_commits`) into `quantum-loop.sh` so STALE detection actually fires.
- Make `poll_orchestrator_commits` worktree-aware to eliminate false-positive STALE in worktree mode.
- Reduce `agents/orchestrator.md` from ~39,900 tokens to ≤15,000 tokens via modularization.
- Introduce per-wave coordinator pattern (`agents/coordinator.md`) — fresh subagent context per wave.
- Unify signal handling — orchestrator/coordinator use shared `runner_parse_output` instead of ad-hoc grep.
- Add integration tests validating the recovery infrastructure end-to-end.
- Maintain 0-retry execution record (manual takeover acceptable for this cycle; coordinator dogfood deferred to v0.8.1).
- Bump plugin version 0.7.10 → 0.8.0 (first minor in 8 cycles).
- Populate `metrics/pre-impl-review-findings.csv` with ≥3 new rows (total ≥36).
- G30 self-validation re-run (expected: LOW or first MEDIUM — substantive change).

## Section 3: User Stories

### US-001: Wire recovery infrastructure into `quantum-loop.sh`

**Acceptance Criteria:**
- [ ] `quantum-loop.sh` sources `lib/orchestrator-liveness.sh` (verifiable via grep).
- [ ] `quantum-loop.sh` invokes `wrap_orchestrator_dispatch` around the orchestrator-spawn call (verifiable via grep).
- [ ] Wrapping respects `QL_LIVENESS_ENABLE=false` (skip behavior preserved).
- [ ] Existing `quantum-loop.sh --audit` continues to work unchanged.
- [ ] No regressions in `tests/test_audit.sh`.

### US-002: Worktree-aware `poll_orchestrator_commits`

**Acceptance Criteria:**
- [ ] `lib/orchestrator-liveness.sh::poll_orchestrator_commits` accepts an optional 4th arg `WORKTREE_PATH`. When set and not `.`, polling uses `git -C "$WORKTREE_PATH" rev-parse HEAD`.
- [ ] Default behavior (no 4th arg) preserved exactly.
- [ ] `wrap_orchestrator_dispatch` accepts an optional 3rd arg `WORKTREE_PATH` that propagates to `poll_orchestrator_commits`.
- [ ] `tests/test_orchestrator_liveness.sh` adds Test 11 (worktree-path STALE in tmp worktree → handoff + rc=1) and Test 12 (worktree-path LIVE when worktree's HEAD advances → rc=0).
- [ ] Existing 22 assertions in `tests/test_orchestrator_liveness.sh` remain green.

### US-003: Modularize `agents/orchestrator.md`

**Acceptance Criteria:**
- [ ] At least 6 of these optional sections extracted to `agents/orchestrator-modules/<module>.md`: slop-cleanup, dead-code-detection, intent-graph, skeleton-drift, type-audit, hyclone, constant-scan, tracecoder.
- [ ] Each extracted section in `orchestrator.md` is replaced by a ≤4-line reference stub pointing to the module file with a guard condition (e.g., "if `lib/dead-code.sh` is sourced...").
- [ ] `agents/orchestrator.md` line count after modularization ≤ 700 lines (down from ~1,743). Token estimate ≤ 15,000.
- [ ] All cross-references in `orchestrator.md` resolve to existing files (no dangling pointers).
- [ ] Existing `tests/test_orchestrator_*.sh` continue to pass (presence-checks for module references, not content).

### US-004: Per-wave coordinator pattern

**Acceptance Criteria:**
- [ ] `agents/coordinator.md` (NEW) defines a thin agent handling exactly ONE wave per invocation. Document scope, inputs (wave ID, story IDs), output signals (`WAVE_PASSED` / `WAVE_FAILED` / `BLOCKED`).
- [ ] `lib/spawn.sh` adds `spawn_coordinator(wave_id)` helper (or equivalent) that builds a coordinator command with the focused prompt.
- [ ] `quantum-loop.sh` adds a `--coordinator` flag (opt-in for v0.8.0; default still `--legacy-orchestrator`). When `--coordinator` is set, the wave loop is shell-driven: read quantum.json → pick next eligible wave → spawn coordinator → aggregate result → loop.
- [ ] Backward compatibility: `--legacy-orchestrator` (default) preserves existing single-spawn behavior. The new flag is opt-in for v0.8.0 dogfood validation in v0.8.1.
- [ ] Tests in `tests/test_coordinator_dispatch.sh` verify the coordinator agent file exists, has required sections, and `spawn_coordinator` builds a non-empty command.

### US-005: Signal protocol unification

**Acceptance Criteria:**
- [ ] `lib/runner.sh` adds `runner_parse_subagent_output(agent_id)` wrapper that retrieves `TaskOutput` for an agent_id and feeds through `runner_parse_output`. (Or document that callers should use `runner_parse_output` directly with captured output.)
- [ ] `agents/orchestrator.md` signal-handling section updated to instruct the LLM to use the shared parsing path (cite the lib function).
- [ ] `agents/coordinator.md` includes the same signal section so both agents share the canonical pattern.
- [ ] Test verifies the orchestrator/coordinator agent file references the canonical signal-parsing function (presence check via grep).

### US-006: Integration tests

**Acceptance Criteria:**
- [ ] `tests/test_quantum_loop_recovery.sh` (NEW) — invokes a thin reproduction of `quantum-loop.sh`'s orchestrator-wrapping with a stub orchestrator that exits without committing; asserts STALE detection within ≤15s, handoff message on stdout, rc=1.
- [ ] `tests/test_coordinator_dispatch.sh` (NEW) — verifies `agents/coordinator.md` exists, contains expected sections (Inputs, Output Signals, Scope), and `lib/spawn.sh::spawn_coordinator` produces a non-empty command.
- [ ] `tests/test_orchestrator_liveness.sh` worktree-path tests (Test 11 + 12 from US-002) green.
- [ ] All existing tests (98+) continue to pass.

### US-007: Retrospective + IDEA_REPORT_v22 + version bump 0.7.10 → 0.8.0

**Acceptance Criteria:**
- [ ] `idea-stage/PIPELINE_REPORT_v22.md` documents v0.8.0 dogfood (7 stories, outcomes, wave plan, G30 result, test-suite delta, manual-takeover note as 13th consecutive cycle).
- [ ] `idea-stage/IDEA_REPORT_v22.md` lists open after v0.8.0. Specifically calls out v0.8.1 dogfood validation as the next concrete step.
- [ ] `quantum-loop.sh --audit` captured.
- [ ] G30 self-validation captured; `automated:true` recorded.
- [ ] CHANGELOG [0.8.0] entry covering all 6 implementation stories + the architectural rationale.
- [ ] All 4 plugin manifest version fields bumped 0.7.10 → 0.8.0.

## Section 4: Functional Requirements

- **FR-1:** `quantum-loop.sh` integrates `wrap_orchestrator_dispatch` so STALE detection fires in production.
- **FR-2:** `poll_orchestrator_commits` honors a worktree path argument for accurate polling.
- **FR-3:** `agents/orchestrator.md` modularized to ≤15k tokens via extracted optional sections.
- **FR-4:** `agents/coordinator.md` and `--coordinator` flag enable per-wave subagent dispatch.
- **FR-5:** Signal handling uses canonical `runner_parse_output` path across orchestrator + coordinator.
- **FR-6:** Integration tests validate auto-recovery end-to-end (stub-driven, not real cycle).
- **FR-7:** CSV ≥36 rows; plugin version 0.7.10 → 0.8.0; reviews recorded with `automated:true`.

## Section 5: Non-Goals

- Full dogfood cycle running through coordinator pattern (deferred to v0.8.1).
- Removing `agents/orchestrator.md` (kept for legacy flow).
- N38 codex CLI flag drift detection (LOW, separate cycle).
- Copilot rate-limit observability (environmental, separate cycle).
- New runner integrations.
- Refactoring `lib/spawn.sh` implementer-spawn logic (works fine; only adding coordinator).

## Section 6: Design Notes

See `docs/plans/2026-04-28-v0.8.0-bundle-design.md` for full per-story design.

## Section 7: Technical Notes

Cross-platform: bash 4.3+. No new dependencies. New env vars: `QL_LIVENESS_ENABLE` (existing, now exercised), no new ones. No schema changes to manifests or quantum.json. New CLI flag `--coordinator` is opt-in.

## Section 8: Success Metrics

All 7 stories first-attempt PASS; CSV at ≥36 rows; orchestrator.md ≤15k tokens; +3 new test files; backward compatibility verified via legacy-flag tests; integration test confirms auto-recovery fires (first time in 12 cycles).

## Section 9: Open Questions

None.

## Lifecycle Checklist

Standard. New CLI flag (opt-in) — no breaking changes. New agent file (`agents/coordinator.md`) — additive. Modularization preserves cross-references.

## Next Steps

Advisory hooks → quantum.json → execute → PR → squash-merge → tag v0.8.0.
