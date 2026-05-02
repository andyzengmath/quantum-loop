# PRD: v0.10.3 — patch-tier (--max-retries parity + test_v081_wiring delete + deferred dogfood)

**Status:** Approved
**Date:** 2026-05-01
**Design doc:** `docs/plans/2026-05-01-v0.10.3-bundle-design.md`
**Source:** Operator-approved scope post-v0.10.2 ship.
**Branch:** `ql/v0.10.3-bundle`
**Target version:** 0.10.3 (patch from 0.10.2)
**Total effort:** ~1 hour

## Section 1: Introduction / Overview

5-story patch closing 2 deferred items + 1 explicit-defer + standard cycle ceremony.

## Section 2: Goals

- Close `--max-retries` argparse integer-validation parity gap (v0.10.2 review deferral).
- DELETE obsolete `tests/test_v081_wiring.sh` (4/5 stale failures; obsoleted-by-v0.9.0-rewrite; residual wiring-reachability gap accepted as low-risk per architect review). *[v0.10.4 honest-framing correction]*
- Continue deferring real-feature dogfood (4th cycle; no operator-queued feature).
- 12th application of multi-perspective post-merge review pattern.
- Bump 0.10.2 → 0.10.3 (4 manifest fields).
- 31 consecutive LOW G30 self-validation.

## Section 3: User Stories

### US-001: `--max-retries` parity validation

**Acceptance Criteria:**
- [ ] `quantum-loop.sh --max-retries` argparse case branch adds same integer-validation regex `^(0|[1-9][0-9]*)$` as `--max-iterations` (per v0.10.2 US-001 T-001-5 pattern).
- [ ] Validation runs BEFORE `MAX_RETRIES="$2"` assignment.
- [ ] Error message: `ERROR: --max-retries requires a non-negative integer, got '<value>'`.
- [ ] On rejection: exit 1.
- [ ] After: smoke tests verify (a) `--max-retries notanumber` rejected with clear error; (b) `--max-retries 0` accepted; (c) `--max-retries 5` accepted; (d) `--max-retries -1` rejected.
- [ ] `bash -n quantum-loop.sh` clean.
- [ ] No regression in test_signal_parsing or test_coordinator_e2e.

### US-002: DELETE `tests/test_v081_wiring.sh`

**Acceptance Criteria:**
- [ ] `tests/test_v081_wiring.sh` removed via `git rm`.
- [ ] Commit message documents rationale: 4 failing assertions check v0.8.1-era placeholder behaviors that v0.9.0 replaced; current coverage in test_coordinator_e2e + test_dag_query + test_next_wave + test_coordinator_dispatch + test_coordinator_guard subsumes all v0.8.1 smoke aims.
- [ ] No other tests reference `test_v081_wiring.sh` (grep confirmation).

### US-003: Real-feature dogfood — STILL DEFERRED

**Acceptance Criteria:**
- [ ] No code change. Status update only.
- [ ] US-005 retrospective documents 4th cycle of deferral (v0.10.0 → v0.10.1 → v0.10.2 → v0.10.3).
- [ ] Documents the "blocked-on-operator-feature-queue" pattern: dogfood requires a real feature; until operator queues one, the system itself's housekeeping cycles are NOT the appropriate dogfood subject (would conflict with stable-master invariant).

### US-004: Multi-perspective post-merge review (12th application)

**Acceptance Criteria:**
- [ ] 3 reviewer agents invoked in parallel: architect + code-reviewer + security.
- [ ] Findings logged in retrospective.
- [ ] No score-≥85 finding deferred.

### US-005: Retrospective + IDEA_REPORT_v37 + version bump 0.10.2 → 0.10.3

**Acceptance Criteria:**
- [ ] `idea-stage/PIPELINE_REPORT_v37.md` documents v0.10.3 (5 stories).
- [ ] `idea-stage/IDEA_REPORT_v37.md` rolling forward state.
- [ ] `CHANGELOG.md [0.10.3]` entry.
- [ ] 4 plugin manifest version fields bumped 0.10.2 → 0.10.3.
- [ ] G30 self-validation captured (31st consecutive LOW expected).

## Section 4: Functional Requirements

- **FR-1:** US-001 validation pattern matches US-001 T-001-5 from v0.10.2 (same regex, same error format with field-name swap).
- **FR-2:** US-002 deletion is irreversible from this PR forward; no need to keep the file as deprecated.
- **FR-3:** US-003 deferral is a no-op work item (documentation only).
- **FR-4:** US-004 review surfaces no blocking findings.
- **FR-5:** Plugin version 0.10.2 → 0.10.3 (4 fields).

## Section 5: Non-Goals

- No real-feature dogfood (continued deferral).
- No architectural changes.
- No N40, N43, N46, N47-N50.

## Section 6: Design Notes

See `docs/plans/2026-05-01-v0.10.3-bundle-design.md`.

## Section 7: Technical Notes

Bash 4.3+. Mechanical fixes; no new helpers.

## Section 8: Success Metrics

- All 5 stories first-attempt PASS.
- 9 → 8 test files (test_v081_wiring deleted); remaining suites green.
- 31 consecutive LOW G30 self-validation.

## Section 9: Open Questions

- **Q1:** Tier — patch (0.10.3)? **Decision:** Yes; consistent with prior patch cycles.
- **Q2:** Restore vs delete `test_v081_wiring.sh`? **Decision:** DELETE.
- **Q3:** Synthesize fake feature for dogfood? **Decision:** No.
