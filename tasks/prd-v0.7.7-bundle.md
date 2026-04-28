# PRD: v0.7.7 — patch-tier (N30 first multi-runner end-to-end smoke validation)

**Status:** Approved
**Date:** 2026-04-28
**Design:** `docs/plans/2026-04-28-v0.7.7-bundle-design.md`
**Branch:** `ql/v0.7.7-bundle`
**Target version:** 0.7.7 (PATCH — first patch in v0.7.x track post-N30)

## Section 1: Overview

4-story patch-tier bundle — first end-to-end smoke validation of codex + copilot CLI runners against the existing multi-runner infrastructure (`runners/*.json` + `runners/hooks/*-hooks.sh` + `lib/runner.sh`). Closes N30 (v0.7.7 anchor) from IDEA_REPORT_v17. Eleventh multi-cycle populated-CSV run (27 → 30 rows).

## Section 2: Goals

- Close N30 (multi-runner first integration).
- Bump 0.7.6 → 0.7.7 (PATCH — first since v0.7.0).
- 12th LOW G30 self-validation expected.
- Add 13 new test assertions (5+5+3) across 2 new test files + 1 extended.

## Section 3: User Stories

### US-001: Codex CLI real smoke test

**Description:** As a developer evaluating codex as an alternative runner, I want a smoke test confirming `runner_load runners/codex.json` + `_provider_version codex` work end-to-end against the installed codex CLI.

**Acceptance Criteria:**
- [ ] NEW `tests/test_codex_runner_smoke.sh`. Detects `codex` CLI via `command -v codex`. Skip-pass with WARN if absent.
- [ ] If present: sources `lib/runner.sh`, invokes `runner_load runners/codex.json`, asserts `RUNNER_NAME=codex` + `RUNNER_BINARY=codex` + `RUNNER_TIER=tested`.
- [ ] Invokes `_provider_version codex`; asserts output is non-empty.
- [ ] Wall-clock ≤15s ceiling.
- [ ] Existing tests remain green.
- [ ] Typecheck/lint passes.

### US-002: Copilot CLI real smoke test

**Description:** As a developer evaluating copilot as an experimental runner, I want the same smoke validation pattern for copilot.

**Acceptance Criteria:**
- [ ] NEW `tests/test_copilot_runner_smoke.sh`. Mirrors US-001 structure.
- [ ] Asserts `RUNNER_NAME=copilot` + `RUNNER_BINARY=copilot` + `RUNNER_TIER=experimental`.
- [ ] `_provider_version copilot` non-empty.
- [ ] Wall-clock ≤15s.
- [ ] Typecheck/lint passes.

### US-003: Routing E2E with codex+copilot

**Description:** As a developer using per-role provider routing, I want a routing snapshot that includes all 3 runners (claude+codex+copilot) so multi-runner dispatch is regression-guarded.

**Acceptance Criteria:**
- [ ] `tests/test_routing_e2e.sh` adds Test 5: `resolve_routing claude codex copilot` against live env.
- [ ] If all 3 CLIs present: asserts JSON has 3 distinct providers AND `versions.codex` non-empty AND `versions.copilot` non-empty.
- [ ] If any CLI missing: skip-pass with WARN.
- [ ] Existing 6 assertions remain green; +3 new.
- [ ] Typecheck/lint passes.

### US-004: Retrospective + IDEA_REPORT_v18 + version bump 0.7.6 → 0.7.7

**Acceptance Criteria:**
- [ ] `idea-stage/PIPELINE_REPORT_v18.md` documents v0.7.7 dogfood.
- [ ] `idea-stage/IDEA_REPORT_v18.md` lists what's open after v0.7.7.
- [ ] G30 self-validation captured `automated:true`.
- [ ] CHANGELOG `[0.7.7]` entry — explicitly framed as PATCH; documents codex+copilot end-to-end validation.
- [ ] All 4 plugin manifest fields bumped 0.7.6 → 0.7.7.

## Section 4: Functional Requirements

- **FR-1:** `tests/test_codex_runner_smoke.sh` exists; codex-present path asserts manifest + version.
- **FR-2:** `tests/test_copilot_runner_smoke.sh` exists; copilot-present path asserts manifest + version.
- **FR-3:** `tests/test_routing_e2e.sh` Test 5 covers 3-runner routing snapshot.
- **FR-4:** Plugin version 0.7.7; CHANGELOG `[0.7.7]` PATCH entry.
- **FR-5:** CSV ≥30 rows; reviews `automated:true`.

## Section 5: Non-Goals

- **NG-1:** Reconciling v0.7.4 `lib/multi-runner-manifest.sh` (yaml schema) with runners/*.json (deferred — no functional issue).
- **NG-2:** Real multi-step task dispatch via codex/copilot (not just version probe; deferred to v0.9.0+).
- **NG-3:** Promoting copilot from `tier: experimental` to `tier: tested` (needs more cycles of real-task usage).
- **NG-4:** Adding gemini-cli or other runners (out of scope — codex + copilot only per operator).
- **NG-5:** Worktree subagent drift root-cause (N33 deferred).

## Section 6-8: Design / Technical / Success Metrics

Cross-platform: bash 4.3+, Git Bash. CLI presence via `command -v`. Wall-clock ceilings handle CLI cold-start.

Success: 4/4 first-attempt PASS; CSV ≥30 rows; 12th LOW G30; v0.7.7 tagged + pushed.

## Section 9: Open Questions

None.

## Lifecycle Checklist

- First-run: smoke tests skip-pass cleanly when CLIs absent; never block.
- Returning-user: existing tests unchanged.
- Update: 4 manifest version fields + CHANGELOG.
- Error recovery: skip-pass on missing CLI; rc=1 only on real failure (assertion mismatch).
- No-data: smoke tests output a clear PASS/FAIL message either way.
- Uninstall/disable: revert via git; no persistent state.

## Next Steps

Advisory hooks → quantum.json → execute → soliton + copilot review → squash-merge → tag v0.7.7.
