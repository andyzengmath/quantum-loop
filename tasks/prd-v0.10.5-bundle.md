# PRD: v0.10.5 — patch-tier (CLAUDE.md drift fixes + missing-arg-guard parity)

**Status:** Approved
**Date:** 2026-05-01
**Design doc:** `docs/plans/2026-05-01-v0.10.5-bundle-design.md`
**Source:** 3rd p015 doc-vs-code audit + v0.10.4 deferred MEDIUM.
**Branch:** `ql/v0.10.5-bundle`
**Target version:** 0.10.5 (patch from 0.10.4)
**Total effort:** ~1 hour

## Section 1: Introduction / Overview

3-story patch closing 3 CLAUDE.md drift findings + 1 deferred MEDIUM from v0.10.4. This is the smallest meaningful patch possible — clean closure of the v0.10.x housekeeping arc.

## Section 2: Goals

- Fix CLAUDE.md p013 count drift (9 → 12; stale 3 cycles).
- Fix CLAUDE.md p014 count drift (10 → 13; stale 3 cycles).
- Fix CLAUDE.md p013 retrospective reference (v33 → v34 for deviation+recovery footnote).
- Add missing-arg-guard parity for 4 `--max-*` flags matching `--critic`/`--planner` style.
- 14th application of multi-perspective post-merge review.
- Bump 0.10.4 → 0.10.5 (4 manifest fields).
- 33 consecutive LOW G30.

## Section 3: User Stories

### US-001: 4-sub-task fixes (CLAUDE.md drift + missing-arg-guard parity)

**Acceptance Criteria:**

T-001-1 (CLAUDE.md p013 count + enumeration):
- [ ] `CLAUDE.md` p013 entry: "9 applications (v0.9.0 → v0.9.6, v0.10.0, v0.10.1; updated v0.10.2)" → "12 applications (v0.9.0 → v0.9.6, v0.10.0 → v0.10.4; updated v0.10.5)".
- [ ] After: `grep '9 applications' CLAUDE.md` returns 0 hits in p013 entry; `grep '12 applications' CLAUDE.md` matches.

T-001-2 (CLAUDE.md p014 count + enumeration):
- [ ] `CLAUDE.md` p014 entry: "10 review applications (post-v0.8.x: v0.8.1, v0.8.2, v0.8.3, v0.8.4, v0.9.1, v0.9.3, v0.9.4, v0.9.5, v0.9.6, v0.10.1; updated v0.10.2)" → "13 review applications (post-v0.8.x: v0.8.1-v0.8.4, v0.9.1, v0.9.3-v0.9.6, v0.10.0-v0.10.4; updated v0.10.5)".
- [ ] After: `grep '10 review applications' CLAUDE.md` returns 0 hits; `grep '13 review applications' CLAUDE.md` matches.

T-001-3 (CLAUDE.md p013 retro-ref correction):
- [ ] `CLAUDE.md` p013 "Canonical retrospectives" line: replace `PIPELINE_REPORT_v33.md (v0.9.6 with the deviation + recovery footnote)` with `PIPELINE_REPORT_v34.md (v0.10.0 with the v0.9.6 first-attempt-rollback recovery footnote)`.
- [ ] After: `grep 'PIPELINE_REPORT_v34.md' CLAUDE.md` matches in p013 entry.

T-001-4 (missing-arg-guard parity):
- [ ] `quantum-loop.sh` `--max-iterations`, `--max-retries`, `--max-parallel`, `--stale-timeout` argparse branches all gain a `if [[ $# -lt 2 || "${2:-}" == --* ]]; then printf "ERROR: <flag> requires a value\n" >&2; exit 1; fi` guard BEFORE their integer-validation regex check.
- [ ] After: `bash quantum-loop.sh --max-iterations` (no value) exits 1 with "requires a value" message.
- [ ] After: `bash quantum-loop.sh --max-iterations --max-retries 5` (next arg starts with `--`) exits 1 with "requires a value".
- [ ] `bash -n quantum-loop.sh` clean.
- [ ] No regression in test_signal_parsing or test_coordinator_e2e.

### US-002: Multi-perspective post-merge review (14th application)

**Acceptance Criteria:**
- [ ] 3 reviewer agents (architect + code-reviewer + security) invoked in parallel.
- [ ] No score-≥85 finding deferred.

### US-003: Retrospective + IDEA_REPORT_v39 + version bump 0.10.4 → 0.10.5

**Acceptance Criteria:**
- [ ] `idea-stage/PIPELINE_REPORT_v39.md` documents v0.10.5 (3 stories).
- [ ] `idea-stage/IDEA_REPORT_v39.md` rolling forward state. p015 application count incremented to 3.
- [ ] `CHANGELOG.md [0.10.5]` entry.
- [ ] 4 plugin manifest version fields bumped 0.10.4 → 0.10.5.
- [ ] G30 self-validation captured (33rd consecutive LOW expected).

## Section 4: Functional Requirements

- **FR-1:** US-001 doc edits are wording corrections (no semantic change).
- **FR-2:** US-001 T-001-4 missing-arg-guard pattern matches existing `--critic`/`--planner` style for code consistency.
- **FR-3:** Plugin version 0.10.4 → 0.10.5 (4 fields).

## Section 5: Non-Goals

- No real-feature dogfood (standing backlog).
- No new architectural work.

## Section 6: Design Notes

See `docs/plans/2026-05-01-v0.10.5-bundle-design.md`.

## Section 7: Technical Notes

Bash 4.3+. Mechanical fixes.

## Section 8: Success Metrics

- All 3 stories first-attempt PASS.
- 33 consecutive LOW G30.
