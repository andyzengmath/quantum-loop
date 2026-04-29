# PRD: v0.8.3 — patch-tier (post-v0.8.2 review hotfix — close the WAVE_* anti-pattern across all sites)

**Status:** Approved
**Date:** 2026-04-29
**Design doc:** `docs/plans/2026-04-29-v0.8.3-bundle-design.md`
**Source:** Multi-perspective post-v0.8.2 review found 4-6 parallel WAVE_* wire sites that v0.8.2 missed
**Branch (planned):** `ql/v0.8.3-bundle`
**Target version:** 0.8.3 (patch bump from 0.8.2)
**Total effort estimate:** ~2-3 hours

## Section 1: Introduction / Overview

4-story patch closing the FOURTH layer of the N33 root-cause #1 anti-pattern (presence-only AC at parallel signal-wire sites). v0.8.2 fixed one regex; v0.8.3 closes the heuristic regex + case switch + source gate + PowerShell parity. After v0.8.3, all 4 layers of the anti-pattern are closed.

## Section 2: Goals

- Extend `lib/signal-heuristics.sh:33` regex to recognize all 6 signals.
- Add `WAVE_PASSED` and `WAVE_FAILED` case branches in `quantum-loop.sh:1570` switch.
- Extend `lib/spawn.sh` source gate at `quantum-loop.sh:688-691` to fire under `COORDINATOR_MODE=true`.
- Mirror regex + switch in `quantum-loop.ps1:364` for PowerShell parity.
- Tighten `tests/test_signal_parsing.sh` Tests 9/10 with `SIGNAL_CONFIDENCE != "exact"` assertion.
- Bump plugin version 0.8.2 → 0.8.3 (4 manifest fields).
- Populate `metrics/pre-impl-review-findings.csv` with 3 new rows (total ≥46).
- G30 self-validation re-run (expected LOW — small reactive hotfix).

## Section 3: User Stories

### US-001: Atomic close of 3 WAVE_* wire sites in bash code

**Acceptance Criteria:**
- [ ] `lib/signal-heuristics.sh` line ~33 regex includes `WAVE_PASSED` and `WAVE_FAILED` in the alternation, mirroring `lib/runner.sh::runner_parse_output` (verifiable via grep).
- [ ] `quantum-loop.sh` `case "$SIGNAL_RESULT"` switch (around line 1570) has explicit `WAVE_PASSED)` and `WAVE_FAILED)` branches BEFORE the `*)` wildcard. `WAVE_PASSED)` maps to story-progressing semantics (continue); `WAVE_FAILED)` maps to retry semantics (increment retries). v0.8.3 wires the branches; v0.9.0 N42 can refine wave-to-story mapping further.
- [ ] `quantum-loop.sh` source gate at line ~688-691 fires `source lib/spawn.sh` under `COORDINATOR_MODE=true` in addition to `PARALLEL_MODE=true`.
- [ ] `bash -n quantum-loop.sh` confirms no syntax errors.
- [ ] `bash tests/test_signal_parsing.sh` continues to pass (13/13 or extended count).
- [ ] `bash tests/test_runner.sh` continues to pass (43/43 or extended count).

### US-002: PowerShell parity — quantum-loop.ps1 regex + switch arms

**Acceptance Criteria:**
- [ ] `quantum-loop.ps1` line ~364 regex includes `WAVE_PASSED|WAVE_FAILED` (mirrors bash regex).
- [ ] `quantum-loop.ps1` switch block (around line ~379) has explicit `"WAVE_PASSED"` and `"WAVE_FAILED"` case arms.
- [ ] PowerShell syntax validation: `pwsh -NoProfile -Command "Get-Content quantum-loop.ps1 | Out-Null"` runs without parse errors (or skip if pwsh not on PATH).
- [ ] No regression in any existing tests.

### US-003: Tighten test_signal_parsing.sh Tests 9/10 negative assertions

**Acceptance Criteria:**
- [ ] `tests/test_signal_parsing.sh` Tests 9 and 10 each gain an assertion that `SIGNAL_CONFIDENCE` is NOT `"exact"` (verifies the negative tests aren't trivially passing).
- [ ] Test count rises from 13 to 15 (or similar; document actual count in commit message).
- [ ] All assertions pass.

### US-004: Retrospective + IDEA_REPORT_v25 + version bump 0.8.2 → 0.8.3

**Acceptance Criteria:**
- [ ] `idea-stage/PIPELINE_REPORT_v25.md` documents v0.8.3 (4 stories, outcomes, 4-layer N33 closure summary).
- [ ] `idea-stage/IDEA_REPORT_v25.md` lists open after v0.8.3. Specifically: marks N33 anti-pattern fully closed (4 layers); confirms v0.9.0 N42 prerequisites genuinely complete.
- [ ] `quantum-loop.sh --audit` captured.
- [ ] G30 self-validation captured; `automated:true` recorded.
- [ ] CHANGELOG [0.8.3] entry covering the 3 implementation stories + the multi-layer retrospective insight.
- [ ] All 4 plugin manifest version fields bumped 0.8.2 → 0.8.3.

## Section 4: Functional Requirements

- **FR-1:** All 4 signal-protocol consumer sites recognize 6 signals (parser regex + heuristic regex + case switch + PowerShell mirror).
- **FR-2:** `lib/spawn.sh` is loadable under both PARALLEL_MODE and COORDINATOR_MODE.
- **FR-3:** Negative tests in test_signal_parsing.sh exercise the regex non-trivially.
- **FR-4:** CSV ≥46 rows; plugin version 0.8.2 → 0.8.3; reviews recorded with `automated:true`.

## Section 5: Non-Goals

- No v0.9.0 N42 implementation.
- No new test files.
- No removal of legacy paths.
- No N40, N38, copilot rate-limit observability.

## Section 6: Design Notes

See `docs/plans/2026-04-29-v0.8.3-bundle-design.md`.

## Section 7: Technical Notes

Cross-platform: bash 4.3+, PowerShell 5.1+. No new dependencies. No new env vars or schema changes.

## Section 8: Success Metrics

All 4 stories first-attempt PASS; CSV at ≥46 rows; 0 unexposed WAVE_* wire sites remaining; 4-layer N33 anti-pattern fully closed.

## Section 9: Open Questions

- Q1: Should `WAVE_FAILED` case branch increment retries on the wave's stories (multi-story update) or treat the wave as a single retry unit? **Decision:** v0.8.3 ships single-retry-unit semantics; v0.9.0 N42 may refine to multi-story update once the wave-to-story mapping is implemented.

## Lifecycle Checklist

Standard. No new dependencies, no schema changes, no breaking CLI changes.

## Next Steps

Advisory hooks → quantum.json → execute → PR → squash-merge → tag v0.8.3 → GitHub Release.
