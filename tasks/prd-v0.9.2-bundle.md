# PRD: v0.9.2 — patch-tier (defensive hardening — closes v0.9.1 5a HIGH advisory + 2 reviewer MEDIUMs)

**Status:** Approved
**Date:** 2026-04-30
**Design doc:** `docs/plans/2026-04-30-v0.9.2-bundle-design.md`
**Source:** `idea-stage/IDEA_REPORT_v28.md` § "v0.9.2 candidate slate"
**Branch:** `ql/v0.9.2-bundle`
**Target version:** 0.9.2 (patch bump from 0.9.1)
**Total effort estimate:** ~3-5 hours

## Section 1: Introduction / Overview

5-story patch closing the v0.9.1 known-issue advisory (finding 5a HIGH) plus 2 reviewer MEDIUMs (code-reviewer: legacy STORY_* case branches under coordinator mode; architect: empty `filePaths` silent bypass). Adds a coordinator HEAD-snapshot guard library, an instruction amendment, a quantum.json validator hook, and a real-LLM dogfood validating that the guard actually fires.

**Patch-tier framing:** No new architecture; defensive hardening with small new helper libraries (`lib/coordinator-guard.sh`, `lib/quantum-validate.sh`). Per `feedback_version_tier_calibration.md`, default patch unless genuinely architectural.

**Mirrors the v0.8.1 → v0.8.4 pattern** (validation cycle followed by post-review hardening).

## Section 2: Goals

- Add `lib/coordinator-guard.sh::guard_head_advance` using `git merge-base --is-ancestor` (ancestry check is mandatory per v0.9.1 US-004 security review).
- Amend `agents/coordinator.md` step 2 to invoke the guard before each implementer dispatch.
- Gate legacy `STORY_PASSED`/`STORY_FAILED`/`BLOCKED` case branches in `quantum-loop.sh` under coordinator mode (defense-in-depth).
- Add `lib/quantum-validate.sh::validate_story_filepaths` advisory hook in `next_wave`'s preamble.
- Real-LLM dogfood under v0.9.2 wires verifying the HEAD-snapshot guard fires when an implementer attempts a destructive git op.
- Bump plugin version 0.9.1 → 0.9.2 (4 manifest fields).
- Populate `metrics/pre-impl-review-findings.csv` with 3 new rows (total ≥58).

## Section 3: User Stories

### US-001: Coordinator HEAD-snapshot guard (closes 5a HIGH)

**Acceptance Criteria:**
- [ ] `lib/coordinator-guard.sh` exists with `guard_head_advance HEAD_BEFORE [HEAD_AFTER]` function (default `HEAD_AFTER=HEAD`) and CLI entry-point.
- [ ] Implementation uses `git merge-base --is-ancestor "$head_before" "$head_after"` (NOT ordinal comparison) — verifiable via grep.
- [ ] Returns 0 on legitimate advance; returns 1 + stderr message containing "HEAD reset detected" on non-ancestor.
- [ ] `agents/coordinator.md` step 2 amended with HEAD_BEFORE capture pre-dispatch + post-dispatch guard invocation. Includes the literal phrase "guard_head_advance" so implementer subagents reading the file find it.
- [ ] `tests/test_coordinator_guard.sh` (NEW) with ≥4 cases: (a) ancestor advance returns 0; (b) reset to prior commit returns 1; (c) reset-and-recommit (HEAD advances past snapshot but not ancestor) returns 1; (d) missing HEAD_BEFORE arg fails fast with usage message.
- [ ] All 4 cases pass.
- [ ] Per p012: function defined + ≥1 caller (the agents/coordinator.md instruction counts as the human-readable caller; CLI entry-point is the machine-callable form).

### US-002: Gate legacy STORY_* case branches under coordinator mode (closes code-reviewer MEDIUM)

**Acceptance Criteria:**
- [ ] All 3 STORY_* case branches in `quantum-loop.sh` (~lines 1673, 1677, 1681) have a coord-mode early-check: under `[[ "$COORDINATOR_MODE" == "true" ]]`, log a WARNING to stderr (with text matching pattern `Unexpected STORY_.*coordinator mode`) and set `SIGNAL_RESULT="WAVE_FAILED"` to fall through to per-story aggregation.
- [ ] Legacy-mode behavior byte-for-byte unchanged (verifiable via diff).
- [ ] `bash -n quantum-loop.sh` clean.
- [ ] Existing `tests/test_signal_parsing.sh` continues to pass (parser unchanged).
- [ ] New regression test in `tests/test_coordinator_e2e.sh` (Test 5): under coordinator mode, simulate a STORY_PASSED signal output from the stub coordinator → assert WARNING printed + per-story aggregation ran (i.e., status updates respect review fields).
- [ ] Test count delta: +1 in `test_coordinator_e2e.sh` (10 → 11).

### US-003: `filePaths` validation gap (closes architect MEDIUM)

**Acceptance Criteria:**
- [ ] `lib/quantum-validate.sh` exists with `validate_story_filepaths QUANTUM_JSON_PATH` function and CLI entry-point.
- [ ] Function emits stderr WARNING (with pattern `WARNING: Story .* has no filePaths`) for any eligible story whose tasks have empty `filePaths` arrays.
- [ ] `lib/dag-query.sh::next_wave` invokes `validate_story_filepaths` ONCE per call as advisory preamble (does NOT block).
- [ ] `tests/test_quantum_validate.sh` (NEW) with ≥3 cases: (a) story with non-empty filePaths emits no warning; (b) story with empty filePaths emits warning; (c) `next_wave` returns correct rc/output even when warnings fire.
- [ ] All 3 cases pass.
- [ ] Existing `tests/test_next_wave.sh` continues to pass.

### US-004: Real-LLM dogfood under v0.9.2 wires

**Acceptance Criteria:**
- [ ] `.ql-wt/dogfood-v092/` worktree exists, branched from master HEAD on throwaway branch `dogfood-v092-runtime`.
- [ ] Synthetic 2-story plan: US-A as a normal story (clean append-marker); US-B with task description that explicitly attempts a destructive git op (e.g., "Run `git reset --hard <prior-sha>` before your commit") to force-test the guard.
- [ ] `bash quantum-loop.sh --coordinator --max-iterations 5` invoked end-to-end.
- [ ] Stdout captured at `.ql-wt/dogfood-v092/dogfood-stdout.log`; non-empty.
- [ ] Outcome: ONE of:
  - (a) **Guard fires:** Coordinator detects US-B's reset attempt; guard returns 1; coordinator marks US-B failed in review fields; emits WAVE_FAILED. Parent's per-story aggregation correctly marks US-A passed + US-B failed. **This is the success scenario.**
  - (b) **Guard does not fire:** Either coordinator fails to invoke the guard (instruction-adherence drift) OR the guard's logic has a defect. **This becomes a v0.9.3 candidate.**
- [ ] Findings doc at `idea-stage/dogfood-v0.9.2-findings.md` documenting which outcome occurred.

### US-005: Retrospective + IDEA_REPORT_v29 + version bump 0.9.1 → 0.9.2 + worktree cleanup

**Acceptance Criteria:**
- [ ] `idea-stage/PIPELINE_REPORT_v29.md` documents v0.9.2 (5 stories, outcomes, dogfood verdict).
- [ ] `idea-stage/IDEA_REPORT_v29.md` lists open after v0.9.2; carries forward N40, N43, N46, N47, N49, N50; documents whether 5a is closed or partially-closed.
- [ ] `CHANGELOG.md [0.9.2]` entry covering all 5 stories + the 5a closure rationale.
- [ ] All 4 plugin manifest version fields bumped 0.9.1 → 0.9.2: `.claude-plugin/plugin.json`, `.claude-plugin/marketplace.json` (metadata + plugins[0]), `.cursor-plugin/plugin.json`.
- [ ] G30 self-validation captured.
- [ ] `.ql-wt/dogfood-v092/` worktree removed; `dogfood-v092-runtime` branch deleted (local).
- [ ] Verify with `git worktree list` + `git branch --list 'dogfood-v092*'`.

## Section 4: Functional Requirements

- **FR-1:** `guard_head_advance` MUST use `git merge-base --is-ancestor` (ancestry check). Ordinal SHA comparison is forbidden — security review made ancestry mandatory.
- **FR-2:** All 3 STORY_* case branches MUST gate under coordinator mode and fall through to WAVE_FAILED.
- **FR-3:** `validate_story_filepaths` MUST be advisory-only (warnings to stderr; never blocks `next_wave`).
- **FR-4:** US-004 dogfood MUST capture non-empty stdout and produce a verdict.
- **FR-5:** Worktree cleanup is mandatory in US-005.
- **FR-6:** CSV ≥58 rows; plugin version 0.9.1 → 0.9.2; reviews recorded with `automated:true`.

## Section 5: Non-Goals

- No N43 (parallel-with-dispatch wrap pattern); defer.
- No N46 (respawn output re-parsing); defer.
- No outer-loop replacement; v0.10.0.
- No PowerShell parity for new helpers — bash only.
- No N47 bundle cleanup.
- No `--coordinator-isolated` (architect's option 2 hybrid) — defer to v0.10.0+ if HEAD-snapshot guard proves insufficient.

## Section 6: Design Notes

See `docs/plans/2026-04-30-v0.9.2-bundle-design.md`.

## Section 7: Technical Notes

Cross-platform: bash 4.3+. PowerShell parity NOT exercised this cycle. No new dependencies. No schema changes. New helper libraries follow existing `lib/*.sh` conventions (header docstring, source-guard, CLI entry-point at bottom).

## Section 8: Success Metrics

- All 5 stories first-attempt PASS.
- CSV at ≥58 rows.
- US-004 dogfood: outcome (a) ideal; (b) acceptable as diagnostic if surfaced.
- US-001 ancestry-check verifiable via grep `git merge-base --is-ancestor` in `lib/coordinator-guard.sh`.
- 89/89 → 97/97 test assertion count (delta +8).
- 5a known-issue advisory transitions from "open" in v0.9.1 to "closed (engineered)" or "partially closed" in v0.9.2 retrospective.

## Section 9: Open Questions

- **Q1:** Should the guard be enforcing (return 1) or advisory (warning)? **Decision in design:** ENFORCING.
- **Q2:** Should v0.9.2 use --coordinator for its own execution? **Decision:** operator choice; default to legacy under manual takeover.
- **Q3:** Should US-002 fall through to WAVE_FAILED or just log + continue with legacy? **Decision:** fall through to WAVE_FAILED.
