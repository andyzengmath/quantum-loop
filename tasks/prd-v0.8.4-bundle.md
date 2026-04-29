# PRD: v0.8.4 — patch-tier (post-v0.8.3 review hotfix — final v0.8.x close)

**Status:** Approved
**Date:** 2026-04-29
**Design doc:** `docs/plans/2026-04-29-v0.8.4-bundle-design.md`
**Source:** Multi-perspective post-v0.8.3 review surfaced 1 MEDIUM + 2 LOW + 4 cosmetic doc gaps; v0.8.4 closes them atomically.
**Branch (planned):** `ql/v0.8.4-bundle`
**Target version:** 0.8.4 (patch bump from 0.8.3)
**Total effort estimate:** ~1.5-2 hours

## Section 1: Introduction / Overview

5-story patch closing all residual findings from the v0.8.3 multi-perspective review. After v0.8.4, the v0.8.x track is fully closed with zero deferred findings.

## Section 2: Goals

- Mirror bash retry-accounting semantics in PS `WAVE_FAILED` arm.
- Add `$storyId` defense-in-depth validation in PS path.
- Add idempotency source guard to `lib/spawn.sh` (matches comment claim from v0.8.3).
- Update 4 implementer-scoped docs to reference WAVE_* signals.
- Bump plugin version 0.8.3 → 0.8.4 (4 manifest fields).
- Populate `metrics/pre-impl-review-findings.csv` with 3 new rows (total ≥49).

## Section 3: User Stories

### US-001: PS `WAVE_FAILED` retry accounting

**Acceptance Criteria:**
- [ ] `quantum-loop.ps1` `"WAVE_FAILED"` switch arm replaces `startedAt = null` clear with full retry-accounting jq expression mirroring `quantum-loop.sh:1620-1625`.
- [ ] PowerShell syntax valid (verifiable via parse check).

### US-002: PS `$storyId` regex validation

**Acceptance Criteria:**
- [ ] After `$storyId` assignment in `quantum-loop.ps1`, add validation: `if ($storyId -notmatch '^[A-Za-z0-9_-]+$') { Write-Error "Invalid storyId: $storyId"; exit 1 }`
- [ ] Validation fires BEFORE any jq invocation that consumes `$storyId`.

### US-003: lib/spawn.sh idempotency source guard

**Acceptance Criteria:**
- [ ] `lib/spawn.sh` top-level adds: `if [[ -n "${_QL_SPAWN_SH:-}" ]]; then return 0; fi; readonly _QL_SPAWN_SH=1`
- [ ] Sourcing `lib/spawn.sh` twice in the same shell does NOT re-execute its body (verifiable via grep + manual test).
- [ ] Existing `lib/spawn.sh` consumers (`quantum-loop.sh`, tests) continue to work.

### US-004: Update 4 implementer-scoped docs to reference WAVE_*

**Acceptance Criteria:**
- [ ] `CLAUDE.md` Signal Reference table includes `WAVE_PASSED` and `WAVE_FAILED` rows (with note that these are wave-level signals from the coordinator pattern).
- [ ] `skills/ql-execute/SKILL.md` signal table similarly extended.
- [ ] `runners/preamble.md` signal protocol section includes WAVE_* signals.
- [ ] `templates/quantum-loop.ps1` user-template signal handling acknowledges (in comment or branch) WAVE_* signals (story-level dispatch path; informational).

### US-005: Retrospective + IDEA_REPORT_v26 + version bump 0.8.3 → 0.8.4

**Acceptance Criteria:**
- [ ] `idea-stage/PIPELINE_REPORT_v26.md` documents v0.8.4 (5 stories, outcomes, final v0.8.x close).
- [ ] `idea-stage/IDEA_REPORT_v26.md` lists open after v0.8.4. Specifically: marks v0.8.x track FULLY CLOSED with zero deferred findings; restates v0.9.0 N42 candidate slate.
- [ ] CHANGELOG [0.8.4] entry covering all 4 implementation stories.
- [ ] All 4 plugin manifest version fields bumped 0.8.3 → 0.8.4.

## Section 4: Functional Requirements

- **FR-1:** PS WAVE_FAILED arm has retry accounting parity with bash.
- **FR-2:** PS storyId validated before jq interpolation.
- **FR-3:** lib/spawn.sh source guard idempotent.
- **FR-4:** All implementer-scoped signal docs reference 6 signals.
- **FR-5:** CSV ≥49 rows; plugin version 0.8.3 → 0.8.4.

## Section 5: Non-Goals

- No v0.9.0 N42 implementation.
- No new test files (US-003 may add one inline source-guard test if low-cost).
- No removal of legacy paths.

## Section 6: Design Notes

See `docs/plans/2026-04-29-v0.8.4-bundle-design.md`.

## Section 7: Technical Notes

Cross-platform: bash 4.3+, PowerShell 5.1+. No new dependencies.

## Section 8: Success Metrics

All 5 stories first-attempt PASS; CSV at ≥49 rows; v0.8.x track FULLY CLOSED with zero deferred findings.

## Section 9: Open Questions

None.

## Lifecycle Checklist

Standard. No new dependencies, no schema changes.

## Next Steps

Advisory hooks → quantum.json → execute → PR → squash-merge → tag v0.8.4 → GitHub Release.
