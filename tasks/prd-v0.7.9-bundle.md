# PRD: v0.7.9 — patch-tier reactive (multi-runner-manifest hardening)

**Status:** Approved
**Date:** 2026-04-28
**Design doc:** `docs/plans/2026-04-28-v0.7.9-bundle-design.md`
**Source:** External code review of `lib/multi-runner-manifest.sh` (operator-driven reactive)
**Branch (planned):** `ql/v0.7.9-bundle`
**Target version:** 0.7.9 (patch bump from 0.7.8)
**Total effort estimate:** ~30-40 min

## Section 1: Introduction / Overview

3 stories closing 6 issues from external code review of `lib/multi-runner-manifest.sh` (v0.7.4 shipment). Patch-tier; operator-driven reactive (not autonomous loop). Tenth multi-cycle populated-CSV run.

## Section 2: Goals

- Close all 6 review issues (4 user-noticeable improvements + 2 nitpicks).
- Add backend-selection test coverage (Issue 5).
- Maintain 0-retry execution record.
- Bump plugin version 0.7.8 → 0.7.9.
- Populate `metrics/pre-impl-review-findings.csv` with ≥3 new rows.
- G30 self-validation re-run (expected: 14th consecutive LOW).

## Section 3: User Stories

### US-001: Multi-runner-manifest hardening (Issues 1, 2, 3, 4, 6)

**Acceptance Criteria:**
- [ ] **Issue 1:** `lib/multi-runner-manifest.sh::parse_manifest` distinguishes empty-yq-success from parse-failure. Empty/null yq output → stderr "is empty or has no top-level structure" + rc=1; "yq failed to parse" only on actual parse error.
- [ ] **Issue 2:** Python backend captures stderr to a tmpfile separately from stdout. Stdout alone is forwarded to caller; stderr is forwarded only on rc≠0.
- [ ] **Issue 3:** Shell parser strips leading whitespace before pattern matching. Tab-indented and 3-space-indented manifests parse correctly.
- [ ] **Issue 4:** Shell parser rtrims trailing whitespace from each field value (`name`, `command`, `version_flag`).
- [ ] **Issue 6:** `validate_manifest` distinguishes jq exit codes. rc=1 → "input missing .runners array (or wrong type)"; rc≥2 → "malformed JSON input".
- [ ] All existing 6 tests in `tests/test_multi_runner_manifest.sh` continue to pass.

### US-002: Backend-selection tests (Issue 5)

**Acceptance Criteria:**
- [ ] `lib/multi-runner-manifest.sh::parse_manifest` honors `MR_DISABLE_YQ=1` (skip yq backend) and `MR_DISABLE_PYTHON=1` (skip python backend) env vars. Default behavior unchanged when unset/empty.
- [ ] `lib/multi-runner-manifest.sh::parse_manifest` emits `[manifest] backend: <name>\n` to stderr when `MR_DEBUG=1`, where `<name>` ∈ {yq, python, shell}.
- [ ] `tests/test_multi_runner_manifest.sh` adds Test 7: default env + `MR_DEBUG=1` → debug emits `backend: yq` (skip if yq not installed).
- [ ] `tests/test_multi_runner_manifest.sh` adds Test 8: `MR_DISABLE_YQ=1 MR_DEBUG=1` → debug emits `backend: python` (skip if no python3+yaml).
- [ ] `tests/test_multi_runner_manifest.sh` adds Test 9: `MR_DISABLE_YQ=1 MR_DISABLE_PYTHON=1 MR_DEBUG=1` → debug emits `backend: shell`.
- [ ] `tests/test_multi_runner_manifest.sh` adds Test 10: tab-indented manifest forced through shell backend (`MR_DISABLE_YQ=1 MR_DISABLE_PYTHON=1`) → parses correctly with field values trimmed of trailing whitespace (Issues 3+4 verified end-to-end).
- [ ] Existing 6 assertions continue to pass; +4 new tests across 7-10.
- [ ] Env-vars documented in lib function comments as "test-only — production callers should not set".

### US-003: Retrospective + IDEA_REPORT_v20 + version bump 0.7.8 → 0.7.9

**Acceptance Criteria:**
- [ ] `idea-stage/PIPELINE_REPORT_v20.md` documents v0.7.9 dogfood (3 stories, outcomes, wave plan, G30 result, test-suite delta).
- [ ] `idea-stage/IDEA_REPORT_v20.md` lists what's open after v0.7.9 (expected: N33/N35 carry-overs unchanged; v0.9.0 minor still pending).
- [ ] `quantum-loop.sh --audit` captured.
- [ ] G30 self-validation captured; `automated:true` recorded.
- [ ] CHANGELOG [0.7.9] entry covering all 6 issues.
- [ ] All 4 plugin manifest version fields bumped 0.7.8 → 0.7.9.

## Section 4: Functional Requirements

- **FR-1:** `parse_manifest` distinguishes empty/malformed YAML across all 3 backends with appropriate error messages.
- **FR-2:** Python backend stderr does not contaminate JSON stdout output.
- **FR-3:** Shell parser handles arbitrary leading-whitespace indent (tab, 2-space, 3-space, 4-space).
- **FR-4:** Shell parser produces JSON with no trailing-whitespace pollution in field values.
- **FR-5:** `validate_manifest` distinguishes missing-runners from malformed-JSON in error messages.
- **FR-6:** `MR_DISABLE_YQ`, `MR_DISABLE_PYTHON`, `MR_DEBUG` env vars enable deterministic backend testing.

## Section 5: Non-Goals

- New runner integrations (codex/copilot real-task dispatch defers to N35 / v0.9.0).
- Worktree subagent drift root-cause investigation (N33 defers to v0.9.0).
- Bumping to 0.8.0 — patch-tier per agreed framing.
- Removing the existing yq backend — graceful chain remains.

## Section 6: Design Notes

See `docs/plans/2026-04-28-v0.7.9-bundle-design.md` for full per-story design.

## Section 7: Technical Notes

Cross-platform: bash 4.3+. New env vars are opt-in (default empty/unset). No schema changes to manifests or quantum.json. No breaking changes.

## Section 8: Success Metrics

All 3 stories first-attempt PASS; CSV at ≥30 rows; 14th consecutive LOW G30 classification; multi-runner-manifest test count 6 → 10.

## Section 9: Open Questions

None.

## Lifecycle Checklist

Standard. New env vars documented as test-only. No schema changes; no breaking changes.

## Next Steps

Advisory hooks → quantum.json → execute → PR → soliton → squash-merge → tag v0.7.9.
