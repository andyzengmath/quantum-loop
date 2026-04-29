# PRD: v0.8.1 — patch-tier (N39 dogfood validation + inline fixes)

**Status:** Approved
**Date:** 2026-04-29
**Design doc:** `docs/plans/2026-04-29-v0.8.1-bundle-design.md`
**Source:** Operator handoff after v0.8.0 N33 closure shipped; pre-flight surfaced 2 inline fixes
**Branch (planned):** `ql/v0.8.1-bundle`
**Target version:** 0.8.1 (patch bump from 0.8.0)
**Total effort estimate:** ~3-5 hours

## Section 1: Introduction / Overview

5-story patch validating v0.8.0's N33 closure (`--coordinator` infrastructure) and shipping 2 inline fixes surfaced during pre-flight. First validation cycle for v0.8.0 architectural work.

## Section 2: Goals

- Run `quantum-loop.sh --coordinator` end-to-end on a small target task; observe whether new infrastructure fires.
- Capture findings: did `wrap_orchestrator_dispatch` fire? did worktree-poll work correctly? did the coordinator stay within bounded context?
- Bump Test 2 wall-clock ceiling 12s → 20s in `tests/test_orchestrator_liveness.sh` (Git Bash jitter).
- Land copilot-hooks defensive flags from stash@{0} (5 flags + paired test updates).
- Bump plugin version 0.8.0 → 0.8.1 (4 manifest fields).
- Populate `metrics/pre-impl-review-findings.csv` with 3 new rows (total ≥40).
- G30 self-validation re-run (expected LOW — small reactive patch).
- Maintain 0-retry execution record under manual takeover (or document if `--coordinator` validation surfaces a real defect).

## Section 3: User Stories

### US-001: Dogfood `--coordinator` end-to-end on a small target task

**Acceptance Criteria:**
- [ ] A throwaway dogfood plan (1 story, 1 task) is authored and executed via `bash quantum-loop.sh --coordinator <plan>`. The target task is small (e.g., a single 1-line comment addition) so dispatch overhead dominates the wall-clock and isolates the infrastructure exercise.
- [ ] The dogfood-quantum.json is NOT committed (stored under `.handoffs/` or `.ql-wt/` which are gitignored) — the cycle artifact is the *findings*, not the dogfood plan itself.
- [ ] Raw observations captured to `idea-stage/dogfood-v0.8.1-findings.md`: which `lib/orchestrator-liveness.sh` functions fired, wall-clock per phase, any unexpected diffs.
- [ ] If `--coordinator` is broken: scope grows; ship a real fix in this story rather than just observing.

### US-002: Capture v0.8.1 dogfood findings

**Acceptance Criteria:**
- [ ] `idea-stage/dogfood-v0.8.1-findings.md` (created in US-001) gains a synthesis section categorizing each observed behavior as WORKED / DEGRADED / BROKEN.
- [ ] At minimum, four claims are evaluated: (a) coordinator agent dispatched; (b) `wrap_orchestrator_dispatch` invoked; (c) worktree-aware poll accurate (or N/A if dogfood not in worktree mode); (d) coordinator context stayed bounded (subjective qualitative read OK).
- [ ] Any DEGRADED/BROKEN findings have a follow-up entry in `idea-stage/IDEA_REPORT_v23.md` with severity classification.

### US-003: Inline fix — Test 2 wall-clock ceiling 12s → 20s

**Acceptance Criteria:**
- [ ] `tests/test_orchestrator_liveness.sh` Test 2 ceiling changed from `<= 12` to `<= 20` (verifiable via grep).
- [ ] Inline comment near the changed line cites `references/test-wallclock-baselines.md` for the Git Bash rationale.
- [ ] Re-running `bash tests/test_orchestrator_liveness.sh` produces 34/34 pass on Git Bash (no Test 2 flake).
- [ ] No other test ceilings touched in this story (sibling tickets remain stable).

### US-004: Inline fix — copilot-hooks defensive flags

**Acceptance Criteria:**
- [ ] `runners/hooks/copilot-hooks.sh::pre_spawn` appends `--autopilot --max-autopilot-continues 0 --no-ask-user --silent --no-color --stream off --no-remote` (verifiable via grep on the new flags).
- [ ] `tests/test_runner.sh` Test "runner_build_cmd_copilot_hook" includes assertions for each new flag (5 new assertions).
- [ ] `bash tests/test_runner.sh` passes (all assertions including the new copilot ones).
- [ ] If copilot binary is present locally, `bash tests/test_copilot_runner_smoke.sh` and `bash tests/test_copilot_dispatch.sh` remain green; if absent, both skip gracefully.
- [ ] Stash@{0} is dropped after successful application (clean stash list).

### US-005: Retrospective + IDEA_REPORT_v23 + version bump 0.8.0 → 0.8.1

**Acceptance Criteria:**
- [ ] `idea-stage/PIPELINE_REPORT_v23.md` documents v0.8.1 dogfood (5 stories, outcomes, wave plan, G30 result, manual-takeover note as 14th consecutive cycle if applicable, dogfood findings synthesis).
- [ ] `idea-stage/IDEA_REPORT_v23.md` lists open after v0.8.1. Specifically: closes N39 (or documents the next-step if dogfood found a defect), confirms or rolls forward N40/N38/copilot-rate-limit.
- [ ] `quantum-loop.sh --audit` captured.
- [ ] G30 self-validation captured; `automated:true` recorded.
- [ ] CHANGELOG [0.8.1] entry covering all 4 implementation stories + the dogfood synthesis.
- [ ] All 4 plugin manifest version fields bumped 0.8.0 → 0.8.1.

## Section 4: Functional Requirements

- **FR-1:** `--coordinator` validated end-to-end on a real (small) target task. Findings documented honestly.
- **FR-2:** Test 2 ceiling tolerant of Git Bash subprocess jitter.
- **FR-3:** Copilot dispatch uses scripting-safe defensive flags by default.
- **FR-4:** CSV ≥40 rows; plugin version 0.8.0 → 0.8.1; reviews recorded with `automated:true`.

## Section 5: Non-Goals

- No removal of `--legacy-orchestrator` default. Promotion is a minor-tier decision deferred to v0.9.0+.
- No new CLI flags or runner integrations.
- No N40 (orchestrator.md ≤700 lines) followup.
- No N38 (codex flag drift) automation.
- No copilot rate-limit observability (environmental).
- No removal of `agents/orchestrator.md` (kept for legacy flow).

## Section 6: Design Notes

See `docs/plans/2026-04-29-v0.8.1-bundle-design.md` for full per-story design.

## Section 7: Technical Notes

Cross-platform: bash 4.3+. No new dependencies. No new env vars or schema changes. Test ceiling bump is test-only. Copilot hook flags only affect copilot dispatch.

## Section 8: Success Metrics

All 5 stories first-attempt PASS; CSV at ≥40 rows; Test 2 stable across 3 consecutive runs; copilot hook smoke/dispatch tests green if binary present; dogfood synthesis produces clear WORKED/DEGRADED/BROKEN verdict for each of the 4 minimum claims.

## Section 9: Open Questions

- Q1: Should the dogfood target be a real lib/orchestrator-liveness.sh comment add, or a self-referential noop (e.g., touch a file under `.handoffs/`)? **Decision in design:** real 1-line comment; the diff itself is verifiable.
- Q2: If `--coordinator` is broken, does v0.8.1 grow to ship the fix, or defer to v0.8.2 reactive? **Decision:** ship the fix in v0.8.1 if scope is bounded (≤2 stories of new work). Defer if it's deeper than that.

## Lifecycle Checklist

Standard. No new dependencies, no schema changes, no breaking CLI changes. Stash@{0} restoration is a one-time activity per US-004.

## Next Steps

Advisory hooks → quantum.json → execute → PR → squash-merge → tag v0.8.1 → GitHub Release.
