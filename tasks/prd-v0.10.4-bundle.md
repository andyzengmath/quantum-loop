# PRD: v0.10.4 — patch-tier (--max-parallel/--stale-timeout parity + subsumption correction + US-003 standing-backlog)

**Status:** Approved
**Date:** 2026-05-01
**Design doc:** `docs/plans/2026-05-01-v0.10.4-bundle-design.md`
**Source:** Operator-approved per `idea-stage/IDEA_REPORT_v37.md` v0.10.4+ slate.
**Branch:** `ql/v0.10.4-bundle`
**Target version:** 0.10.4 (patch from 0.10.3)
**Total effort:** ~1 hour

## Section 1: Introduction / Overview

5-story patch closing 3 explicit v0.10.3 deferrals. v0.10.x audit-cleanup arc finishes here (architectural + housekeeping fully closed).

## Section 2: Goals

- Add integer validation to `--max-parallel` + `--stale-timeout` (parity with v0.10.2/v0.10.3).
- Correct overstated "subsumed by current coverage" wording in v0.10.3 retro docs.
- Reclassify dogfood: per-cycle US-003 → standing-backlog item documented in CLAUDE.md.
- 13th p014 review trio.
- Bump 0.10.3 → 0.10.4 (4 manifest fields).
- 32 consecutive LOW G30.

## Section 3: User Stories

### US-001: `--max-parallel` + `--stale-timeout` integer validation

**Acceptance Criteria:**
- [ ] `quantum-loop.sh:208-211` `--max-parallel` argparse adds regex `^[1-9][0-9]*$` (positive integer only; 0 rejected as degenerate). Error: `--max-parallel requires a positive integer, got '<value>'`. Exit 1 on rejection. Validation BEFORE assignment.
- [ ] `quantum-loop.sh:212-215` `--stale-timeout` argparse adds regex `^[1-9][0-9]*$` (positive integer only). Error: `--stale-timeout requires a positive integer, got '<value>'`. Exit 1 on rejection. Validation BEFORE assignment.
- [ ] After: smoke tests verify (a) `--max-parallel notanumber` rejected; (b) `--max-parallel 0` rejected (degenerate); (c) `--max-parallel 4` accepted; (d) `--stale-timeout 0` rejected; (e) `--stale-timeout 30` accepted.
- [ ] `bash -n quantum-loop.sh` clean.
- [ ] No regression in test suites.

### US-002: Honest framing correction in v0.10.3 retro docs

**Acceptance Criteria:**
- [ ] `idea-stage/PIPELINE_REPORT_v37.md` "Honest scope drift" section already documents this; add cross-reference annotation noting v0.10.4 US-002 closure.
- [ ] `CHANGELOG.md [0.10.3]` entry "Honest scope drift" subsection: replace `subsumed by current coverage` references with `obsoleted-by-v0.9.0-rewrite; residual wiring-reachability gap accepted as low-risk`. Add annotation `[v0.10.4 honest-framing correction]`.
- [ ] `docs/plans/2026-05-01-v0.10.3-bundle-design.md` "DELETE rationale" section: same wording replacement + annotation.
- [ ] `tasks/prd-v0.10.3-bundle.md` US-002 AC commit message references: same wording replacement + annotation.

### US-003: Standing-backlog conversion of dogfood story

**Acceptance Criteria:**
- [ ] `CLAUDE.md` `## Process references` gains a new `### Standing backlog` subsection documenting the real-feature dogfood as blocked-on-operator-feature-queue (not per-cycle US-003 anymore).
- [ ] Documents resume condition: operator queues a real feature for `quantum-loop.sh --coordinator` dispatch.
- [ ] Documents anti-pattern: synthesizing fake features for dogfood adds ceremony without value.
- [ ] No removal of existing `Process patterns` content (additive only).

### US-004: Multi-perspective post-merge review (13th application)

**Acceptance Criteria:**
- [ ] 3 reviewer agents invoked in parallel: architect + code-reviewer + security.
- [ ] No score-≥85 finding deferred.

### US-005: Retrospective + IDEA_REPORT_v38 + version bump 0.10.3 → 0.10.4

**Acceptance Criteria:**
- [ ] `idea-stage/PIPELINE_REPORT_v38.md` documents v0.10.4 (5 stories).
- [ ] `idea-stage/IDEA_REPORT_v38.md` rolling forward state.
- [ ] `CHANGELOG.md [0.10.4]` entry.
- [ ] 4 plugin manifest version fields bumped 0.10.3 → 0.10.4.
- [ ] G30 self-validation captured (32nd consecutive LOW expected).

## Section 4: Functional Requirements

- **FR-1:** US-001 regex `^[1-9][0-9]*$` (positive only) differs from --max-iterations/--max-retries `^(0|[1-9][0-9]*)$` (non-negative). Justified per design Q1+Q2: 0 parallel agents and 0 stale timeout are degenerate configs.
- **FR-2:** US-002 doc edits are annotation-style (preserve original + note correction).
- **FR-3:** US-003 is additive CLAUDE.md edit (no content removal).
- **FR-4:** Plugin version 0.10.3 → 0.10.4 (4 fields).

## Section 5: Non-Goals

- No new architectural work.
- No real-feature dogfood (standing-backlog item).

## Section 6: Design Notes

See `docs/plans/2026-05-01-v0.10.4-bundle-design.md`.

## Section 7: Technical Notes

Bash 4.3+. Mechanical fixes.

## Section 8: Success Metrics

- All 5 stories first-attempt PASS.
- 32 consecutive LOW G30.
