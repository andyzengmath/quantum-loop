# PRD: v0.10.15 — patch-tier (6th p015 audit closure: CLAUDE.md staleness)

**Status:** Auto-approved per `/loop` step 4-5; closes 2 MEDIUM doc-staleness items from 6th p015 application audit.
**Date:** 2026-05-02
**Predecessor:** `tasks/prd-v0.10.14-bundle.md`.
**Branch:** `ql/v0.10.15-bundle`.
**Target version:** 0.10.14 → 0.10.15 (patch).
**Total effort:** ~30 min.

## Section 1: Introduction / Overview

3-story patch closing 2 MEDIUM doc-staleness items surfaced by 6th p015 application:
1. CLAUDE.md p015 application count stale (3 → 5).
2. CLAUDE.md p014 career stats lag (9/23 ≈ 39% → 10/23 ≈ 43%) + range end v0.10.13 → v0.10.14.

Convergent finding: architect surfaced p015 count, critic surfaced career stats lag + range end. Both stale because they were written mid-v0.10.14 before that cycle's own catch (v0.9.1 misattribution caught by architect) was tallied.

## Section 2: Goals

- Close 2 MEDIUM doc-staleness items.
- 24th p014 review.
- Bump 0.10.14 → 0.10.15.
- 43 consecutive LOW G30.

## Section 3: User Stories

### US-001: CLAUDE.md p015 + p014 count synchronization

**Acceptance Criteria:**
- [ ] `CLAUDE.md` line 379 (p015 entry): "**3 applications**" → "**5 applications**"; update parenthetical to list all 5 (post-v0.10.0 6 gaps; post-v0.10.1 3 gaps + canonization; post-v0.10.4 4 gaps; post-v0.10.9 5 gaps; post-v0.10.11 4 gaps).
- [ ] `CLAUDE.md` line 357: range end "v0.10.0-v0.10.13" → "v0.10.0-v0.10.14"; arithmetic 4+1+4+15=24 ✓ (covers v0.10.14's own review trio).
- [ ] `CLAUDE.md` line 360: career hit rate "9/23 ≈ 39%" → "10/24 ≈ 42%" (1 catch added at v0.10.14 for v0.9.1 misattribution; 1 application added for v0.10.14's own trio).
- [ ] Cross-reference: IDEA_REPORT_v48:59 says "10 review-gate catches in 23 applications (~43%)" — note that 23 was the count AT v0.10.14 ship state; CLAUDE.md now correctly shows 24 (post-v0.10.14). IDEA_REPORT_v49 will reflect 24.

### US-002: Multi-perspective post-merge review (24th application)

**Acceptance Criteria:**
- [ ] 3 reviewer agents (architect + code-reviewer + security) invoked in parallel.
- [ ] No score-≥85 finding deferred.

### US-003: Retrospective + IDEA_REPORT_v49 + version bump 0.10.14 → 0.10.15

**Acceptance Criteria:**
- [ ] `idea-stage/PIPELINE_REPORT_v49.md` documents v0.10.15 (3 stories) + 6th p015 application outcome.
- [ ] `idea-stage/IDEA_REPORT_v49.md` rolling forward state (24 p014 applications, 10 catches at this ship; tally at v0.10.16 ship would be 11/25 if v0.10.15's review catches anything).
- [ ] `CHANGELOG.md [0.10.15]` entry.
- [ ] 4 plugin manifest version fields bumped 0.10.14 → 0.10.15.
- [ ] G30 self-validation (43rd consecutive LOW expected).

**Note:** This is a 3-story cycle (not 4) — there's no separate US-001+US-002 split since the work is purely doc updates done together. Established cycle-pattern is flexible on this when scope is contained.

## Section 4: Functional Requirements

- **FR-1:** All 2 doc-staleness items closed with explicit before/after evidence.
- **FR-2:** No code change; documentation-only patch.
- **FR-3:** Plugin version 0.10.14 → 0.10.15 (4 fields).

## Section 5: Non-Goals

- No `--coordinator` dispatch (still v0.11.0 reserved).
- No new architectural work.
- No retroactive rewrite of IDEA_REPORT_v48 (snapshot-in-time convention).
- No test coverage for "respawn rc!=0 + runner_parse_output unavailable" (architect LOW finding; defer per defer-future tier).

## Section 6: Design Notes

The 6th p015 audit demonstrated continued review-gate value: 2 MEDIUM items surfaced even after the v0.10.14 audit had already addressed similar staleness. Pattern p015 stable.

## Section 7: Technical Notes

Markdown-only.

## Section 8: Success Metrics

- All 3 stories first-attempt PASS.
- 6 test suites green (carried forward): 175.
- 43 consecutive LOW G30.
