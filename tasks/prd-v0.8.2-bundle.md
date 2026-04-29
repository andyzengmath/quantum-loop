# PRD: v0.8.2 — patch-tier (post-v0.8.1 review fixes + v0.9.0 prerequisites)

**Status:** Approved
**Date:** 2026-04-29
**Design doc:** `docs/plans/2026-04-29-v0.8.2-bundle-design.md`
**Source:** Multi-perspective review of v0.8.1 ship state (3 parallel agents)
**Branch (planned):** `ql/v0.8.2-bundle`
**Target version:** 0.8.2 (patch bump from 0.8.1)
**Total effort estimate:** ~3-4 hours

## Section 1: Introduction / Overview

5-story patch addressing 2 CRITICAL items (CRLF hygiene + signal-protocol prerequisite) + 3 supporting follow-ups (wall-clock flake + architectural-debt docs + retrospective). Sets up v0.9.0 N42 to land cleanly.

## Section 2: Goals

- Re-encode 2 .sh files from CRLF to LF; prevent recurrence via `.gitattributes`.
- Extend `runner_parse_output` to recognize `WAVE_PASSED`/`WAVE_FAILED` signals (v0.9.0 prerequisite).
- Bump Test 5 wall-clock ceiling 6s → 10s; audit liveness test ceilings.
- Document `--coordinator --parallel` rejection policy + quantum.json field ownership in `agents/coordinator.md`.
- Bump plugin version 0.8.1 → 0.8.2 (4 manifest fields).
- Populate `metrics/pre-impl-review-findings.csv` with 3 new rows (total ≥43).
- G30 self-validation re-run (expected LOW — small reactive patch).
- Maintain 0-retry execution record under manual takeover (15th consecutive cycle).

## Section 3: User Stories

### US-001: Fix CRLF on copilot-hooks.sh + test_runner.sh; add .gitattributes

**Acceptance Criteria:**
- [ ] `file runners/hooks/copilot-hooks.sh` reports no CRLF terminators (verifiable via `file` or `grep -l $'\r' runners/hooks/copilot-hooks.sh` returning empty).
- [ ] `file tests/test_runner.sh` likewise.
- [ ] `.gitattributes` (created or extended) contains `*.sh text eol=lf` and `*.bash text eol=lf`.
- [ ] `bash tests/test_runner.sh` continues to pass (43/43 or current count).
- [ ] `bash runners/hooks/copilot-hooks.sh` (sourced) does not error.
- [ ] `git diff --stat` after the re-encode shows ≤2 file lines changed (line-ending only — content delta should be 0).

### US-002: Extend runner_parse_output to recognize WAVE_PASSED / WAVE_FAILED

**Acceptance Criteria:**
- [ ] `lib/runner.sh::runner_parse_output` regex (line ~283) extended to match `WAVE_PASSED|WAVE_FAILED` in addition to existing `STORY_PASSED|STORY_FAILED|COMPLETE|BLOCKED`.
- [ ] When `WAVE_PASSED` matched: `SIGNAL_RESULT="WAVE_PASSED"`, `SIGNAL_CONFIDENCE="exact"`.
- [ ] When `WAVE_FAILED` matched: `SIGNAL_RESULT="WAVE_FAILED"`, `SIGNAL_CONFIDENCE="exact"`.
- [ ] New unit-test assertions in either `tests/test_runner.sh` or new `tests/test_signal_parsing.sh` covering: WAVE_PASSED happy path, WAVE_FAILED happy path, and that adding wave signals does NOT regress STORY_*/COMPLETE/BLOCKED matching.
- [ ] Existing tests (98+) continue to pass.
- [ ] Comment in lib/runner.sh near the regex notes the v0.9.0 N42 prerequisite framing.

### US-003: Bump Test 5 wall-clock ceiling 6s → 10s

**Acceptance Criteria:**
- [ ] `tests/test_orchestrator_liveness.sh` Test 5 (`interval_sec=0 guard`) ceiling changed from `<= 6` to `<= 10`.
- [ ] Inline comment cites `references/test-wallclock-baselines.md` for the Git Bash rationale.
- [ ] Pre-flight audit of Tests 7, 8, 10, 11 wall-clock ceilings; bump any with observed flake (<10% jitter headroom).
- [ ] Re-running `bash tests/test_orchestrator_liveness.sh` produces 34/34 pass on Git Bash (no Test 5 flake).

### US-004: Document --coordinator --parallel rejection + quantum.json dual-writer ownership

**Acceptance Criteria:**
- [ ] `agents/coordinator.md` adds a section "Interaction with `--parallel`" stating the rejection policy: `--coordinator --parallel` is mutually exclusive (planned enforcement at CLI parse time in v0.9.0; documented now).
- [ ] `agents/coordinator.md` adds a section "quantum.json field ownership" that lists fields owned by the coordinator (`execution.completedWaves` and similar wave-tracking) vs fields owned by the parent loop (`stories[].status`, `stories[].retries.*`, `updatedAt`).
- [ ] Cross-reference link from `agents/coordinator.md` to v0.9.0 N42 future work in IDEA_REPORT_v24.
- [ ] No code change in this story.

### US-005: Retrospective + IDEA_REPORT_v24 + version bump 0.8.1 → 0.8.2

**Acceptance Criteria:**
- [ ] `idea-stage/PIPELINE_REPORT_v24.md` documents v0.8.2 (5 stories, outcomes, wave plan, G30 result, 15th consecutive manual-takeover cycle).
- [ ] `idea-stage/IDEA_REPORT_v24.md` lists open after v0.8.2. Specifically: closes the v0.8.1 review findings (CRLF + signal-protocol gap); confirms or rolls forward N40/N38/N42/N43/N44/N45/N46.
- [ ] `quantum-loop.sh --audit` captured.
- [ ] G30 self-validation captured; `automated:true` recorded.
- [ ] CHANGELOG [0.8.2] entry covering all 4 implementation stories + the architectural-debt docs.
- [ ] All 4 plugin manifest version fields bumped 0.8.1 → 0.8.2.

## Section 4: Functional Requirements

- **FR-1:** Two .sh files re-encoded from CRLF to LF; `.gitattributes` prevents recurrence.
- **FR-2:** Signal parser recognizes 6 signals (4 existing + 2 new wave signals).
- **FR-3:** Test 5 ceiling tolerant of Git Bash subprocess jitter.
- **FR-4:** `--coordinator --parallel` interaction documented + quantum.json field ownership defined.
- **FR-5:** CSV ≥43 rows; plugin version 0.8.1 → 0.8.2; reviews recorded with `automated:true`.

## Section 5: Non-Goals

- No v0.9.0 N42 implementation (real per-wave dispatch).
- No N43 (parallel-with-dispatch wrap pattern).
- No N40 (orchestrator.md ≤700 lines).
- No N38 (codex flag drift).
- No copilot rate-limit observability.
- No removal of `agents/orchestrator.md`.

## Section 6: Design Notes

See `docs/plans/2026-04-29-v0.8.2-bundle-design.md` for full per-story design.

## Section 7: Technical Notes

Cross-platform: bash 4.3+. No new dependencies. No new env vars or schema changes. Signal parser extension is additive. CRLF fix is line-ending only.

## Section 8: Success Metrics

All 5 stories first-attempt PASS; CSV at ≥43 rows; 0 CRLF on .sh files; 6 signals recognized by parser; Test 5 stable across 3 consecutive runs; agents/coordinator.md gains 2 new sections.

## Section 9: Open Questions

- Q1: Should the signal parser recognize `WAVE_PASSED`/`WAVE_FAILED` as wave-level results or map them to per-story semantics? **Decision:** keep them as wave-level distinct signals; v0.9.0 N42 will define the wave→story mapping at the dispatch-loop level, not the parser level.
- Q2: Should `.gitattributes` be created fresh or extended? **Decision:** check existence; create if missing, extend otherwise.

## Lifecycle Checklist

Standard. No new dependencies, no schema changes, no breaking CLI changes.

## Next Steps

Advisory hooks → quantum.json → execute → PR → squash-merge → tag v0.8.2 → GitHub Release.
