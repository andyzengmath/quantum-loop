# PRD: v0.10.12 — patch-tier (5th p015 application closure; CLAUDE.md count refresh + 38→39 G30 fix)

**Status:** Auto-approved per `/loop` step 4-5; recommended path after 5th p015 application surfaced 4 documentation gaps.
**Date:** 2026-05-02
**Predecessor:** `tasks/prd-v0.10.11-bundle.md`.
**Branch:** `ql/v0.10.12-bundle`.
**Target version:** 0.10.11 → 0.10.12 (patch).
**Total effort:** ~30 min.

## Section 1: Introduction / Overview

4-story patch closing 4 of 4 actionable gaps surfaced by the 5th p015 application (post-v0.10.11 architect + document-specialist + critic agent trio audit). 0 LOC code change; documentation-only. Architect confirmed autonomous backlog exhaustion at 90%+ confidence; this cycle closes the post-v0.10.11 doc drift, then the autonomous cycle goes idle until operator stages real-feature dispatch (v0.11.0) or new findings accumulate.

## Section 2: Goals

- Close 4 doc gaps from p015 5th audit (3 CLAUDE.md count staleness + 1 PIPELINE_REPORT_v45 G30 typo).
- 21st p014 review.
- Bump 0.10.11 → 0.10.12.
- 40 consecutive LOW G30.

## Section 3: User Stories

### US-001: CLAUDE.md p013/p014 count refresh post-v0.10.11

**Acceptance Criteria:**
- [ ] `CLAUDE.md` line 341 (p013): "**17 applications** (v0.9.0 → v0.9.6, v0.10.0 → v0.10.9; updated v0.10.10)" — note p013 count remains 17 (v0.10.10 + v0.10.11 are autonomous-kickoff deviations per IDEA_REPORT_v44:73 / IDEA_REPORT_v45:62; do NOT count toward p013) — but the "updated v0.10.10" marker should bump to "updated v0.10.12" to reflect the latest validation.
- [ ] `CLAUDE.md` lines 356-358 (p014): "**18 review applications** (post-v0.8.x: ... v0.10.0-v0.10.9; ... updated v0.10.10)" → "**20 review applications** (post-v0.8.x: v0.8.1-v0.8.4, v0.9.1, v0.9.3-v0.9.6, v0.10.0-v0.10.11; v0.9.2 SKIPPED with rationale; updated v0.10.12)".
- [ ] `CLAUDE.md` line 359 (p014 career hit rate): "Career score-≥85 inline-fix hit rate: 6/18 ≈ 33%." → "Career score-≥85 inline-fix hit rate: 7/20 ≈ 35%."
- [ ] No bash syntax check needed (markdown only).

### US-002: PIPELINE_REPORT_v45 G30 streak typo fix

**Acceptance Criteria:**
- [ ] `idea-stage/PIPELINE_REPORT_v45.md` line ~11 (Overview): "**38th consecutive LOW G30 self-validation**" → "**39th consecutive LOW G30 self-validation**". (PIPELINE_REPORT_v45:86-88 already correctly says 39th; the overview blurb was stale copy-forward from PIPELINE_REPORT_v44.)
- [ ] Cross-check: `IDEA_REPORT_v45.md:55` correctly says "39 consecutive" — no change needed there.

### US-003: Multi-perspective post-merge review (21st application)

**Acceptance Criteria:**
- [ ] 3 reviewer agents (architect + code-reviewer + security) invoked in parallel.
- [ ] No score-≥85 finding deferred.

### US-004: Retrospective + IDEA_REPORT_v46 + version bump 0.10.11 → 0.10.12

**Acceptance Criteria:**
- [ ] `idea-stage/PIPELINE_REPORT_v46.md` documents v0.10.12 (4 stories) + 5th p015 application outcome.
- [ ] `idea-stage/IDEA_REPORT_v46.md` rolling forward state. **Mark autonomous backlog as fully exhausted** (5th p015 audit confirms; only operator-gated items + sub-priority idle-tickers remain).
- [ ] `CHANGELOG.md [0.10.12]` entry.
- [ ] 4 plugin manifest version fields bumped 0.10.11 → 0.10.12.
- [ ] G30 self-validation (40th consecutive LOW expected).

## Section 4: Functional Requirements

- **FR-1:** All 4 doc gaps closed with explicit before/after evidence.
- **FR-2:** No code change; documentation-only patch.
- **FR-3:** Plugin version 0.10.11 → 0.10.12 (4 fields).

## Section 5: Non-Goals

- No `--coordinator` dispatch (still v0.11.0 reserved).
- No OSC body strip / Retry-After multi-line work (LOW + sub-priority per architect; defer indefinitely).
- No N48 stub-coordinator test or N43 work (operator-gated).
- No test-file split (test_orchestrator_liveness.sh at ~495 LOC; architect threshold ~600 LOC; defer).

## Section 6: Design Notes

- 5th p015 application; per architect, autonomous backlog is exhausted at HIGH confidence (90%+). Post-v0.10.12, the autonomous /loop cron will likely produce idle-tick monitoring without new cycles until operator stages real-feature dispatch.

## Section 7: Technical Notes

Markdown-only. No new dependencies.

## Section 8: Success Metrics

- All 4 stories first-attempt PASS.
- 5 baseline test suites + liveness suite green: 15+21+44+35+18+38 = 171.
- 40 consecutive LOW G30.
- Autonomous backlog confirmed exhausted.
