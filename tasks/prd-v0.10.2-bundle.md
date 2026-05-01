# PRD: v0.10.2 — patch-tier (2nd audit-cleanup + LOW absorbs + p015 canonization)

**Status:** Approved
**Date:** 2026-05-01
**Design doc:** `docs/plans/2026-05-01-v0.10.2-bundle-design.md`
**Source:** Operator-initiated 2nd post-cycle 3-agent doc-vs-code audit + carried-forward LOWs.
**Branch:** `ql/v0.10.2-bundle`
**Target version:** 0.10.2 (patch from 0.10.1)
**Total effort:** ~1.5 hours

## Section 1: Introduction / Overview

4-story patch closing 1 MEDIUM + 2 LOW from 2nd audit pass + 2 LOW absorbs from v0.10.0 review carry-forward + p015 canonization.

## Section 2: Goals

- Close `CLAUDE.md:341,355` stale p013/p014 application counts (MEDIUM).
- Close `lib/loop-helpers.sh:338-340` stale `quantum-loop.sh:467+476` reference (LOW; extraction happened in v0.10.0).
- Close `IDEA_REPORT_v34.md:76` wrong STORY_ID line refs (LOW; off by ~3).
- Close dead `--argjson wave "$WAVE"` at `lib/parallel-mode.sh:306` (LOW; pre-existing from master).
- Close MAX_ITERATIONS argparse integer validation gap at `quantum-loop.sh:164` (security LOW; pre-existing).
- Canonize p015 (post-cycle 3-agent doc-vs-code audit pattern) in CLAUDE.md.
- 11th application of multi-perspective post-merge review pattern.
- Bump 0.10.1 → 0.10.2 (4 manifest fields).
- 30 consecutive LOW G30 self-validation.

## Section 3: User Stories

### US-001: Audit fixes + LOW absorbs (5 sub-tasks)

**Acceptance Criteria:**

T-001-1 (CLAUDE.md p013/p014 counts):
- [ ] `CLAUDE.md` p013 entry updated from "8 applications (v0.9.0 → v0.9.6, plus v0.10.0)" to "9 applications (v0.9.0 → v0.9.6, v0.10.0, v0.10.1)".
- [ ] `CLAUDE.md` p014 entry updated from "9 review applications" to "10 review applications" with v0.10.1 added to the cycle list.
- [ ] After: `grep -E '\*\*p013\*\* — Operator-staged.*9 applications' CLAUDE.md` matches; `grep -E '\*\*p014\*\* — Composite review trio.*10 review applications' CLAUDE.md` matches.

T-001-2 (loop-helpers.sh stale comment):
- [ ] `lib/loop-helpers.sh:338-340` docstring for `emit_terminal_signal` no longer references `quantum-loop.sh:467+476` as "PARALLEL_MODE pair stays inline pending v0.10.0+ block extraction" (extraction already happened).
- [ ] Updated comment references current call sites: `lib/iteration-loop.sh:458` (sequential/coordinator MAX_ITERATIONS) and `lib/parallel-mode.sh:423` (parallel-mode MAX_ITERATIONS).
- [ ] After: `! grep -q 'quantum-loop.sh:467' lib/loop-helpers.sh`.

T-001-3 (IDEA_REPORT_v34 line refs):
- [ ] `idea-stage/IDEA_REPORT_v34.md:76` STORY_ID line refs corrected from `363,367,370` to `360,364,367` (line 370 is `exit 1`, not a STORY_ID interpolation site).
- [ ] After: re-grep verifies the correction.

T-001-4 (dead --argjson wave):
- [ ] `lib/parallel-mode.sh:306` (or wherever the `--argjson wave "$WAVE"` is) — dead jq binding removed (filter never references `$wave`).
- [ ] After: `! grep -q -- '--argjson wave' lib/parallel-mode.sh`.
- [ ] `bash -n lib/parallel-mode.sh` clean.
- [ ] `tests/test_dag_query.sh`, `tests/test_coordinator_e2e.sh` pass (regression-clean).

T-001-5 (MAX_ITERATIONS argparse validation):
- [ ] `quantum-loop.sh:164` (or wherever MAX_ITERATIONS is set from CLI) — add integer validation guard. On non-integer input: print ERROR + exit 1.
- [ ] After: `bash quantum-loop.sh --max-iterations notanumber` exits non-zero with clear error.
- [ ] `bash -n quantum-loop.sh` clean.
- [ ] No regression in test_signal_parsing or test_coordinator_e2e.

### US-002: p015 canonization in CLAUDE.md

**Acceptance Criteria:**
- [ ] CLAUDE.md `## Process patterns (canonized v0.10.0 / US-004)` section gains a new entry for **p015 — Post-cycle 3-agent doc-vs-code audit (architect + document-specialist + critic).**
- [ ] Entry references the 2 canonical applications: post-v0.10.0 (closed 6 gaps in v0.10.1) and post-v0.10.1 (closed 3 gaps in v0.10.2).
- [ ] No removal of existing p013/p014 entries (additive only).

### US-003: Multi-perspective post-merge review (11th application)

**Acceptance Criteria:**
- [ ] 3 reviewer agents invoked in parallel: architect + code-reviewer + security.
- [ ] Findings logged in retrospective.
- [ ] No score-≥85 finding deferred.

### US-004: Retrospective + IDEA_REPORT_v36 + version bump 0.10.1 → 0.10.2

**Acceptance Criteria:**
- [ ] `idea-stage/PIPELINE_REPORT_v36.md` documents v0.10.2 (4 stories).
- [ ] `idea-stage/IDEA_REPORT_v36.md` rolling forward state. Updates p015 to "canonized" (was "candidate" in v35).
- [ ] `CHANGELOG.md [0.10.2]` entry.
- [ ] 4 plugin manifest version fields bumped 0.10.1 → 0.10.2.
- [ ] G30 self-validation captured (30th consecutive LOW expected).

## Section 4: Functional Requirements

- **FR-1:** Doc edits are accuracy-improving (line refs, application counts).
- **FR-2:** Code edits (T-001-4, T-001-5) are behavior-preserving in happy paths; T-001-5 adds defensive rejection on bad input.
- **FR-3:** US-003 review surfaces no blocking findings.
- **FR-4:** Plugin version 0.10.1 → 0.10.2 (4 fields).

## Section 5: Non-Goals

- No real-feature dogfood (deferred to v0.11.0+).
- No architectural changes.
- No N40, N43, N46, N47-N50.

## Section 6: Design Notes

See `docs/plans/2026-05-01-v0.10.2-bundle-design.md`.

## Section 7: Technical Notes

Bash 4.3+. Mechanical fixes; no new helpers, no schema changes.

## Section 8: Success Metrics

- All 4 stories first-attempt PASS.
- 9 test suites green.
- 30 consecutive LOW G30 self-validation.

## Section 9: Open Questions

- **Q1:** Tier — patch (0.10.2)? **Decision:** Yes; consistent with prior patch cycles.
- **Q2:** Bundle real-feature dogfood? **Decision:** No (no scope queued).
- **Q3:** Skip cycle ceremony for 5 LOW edits? **Decision:** No; p015 canonization warrants release marker.
