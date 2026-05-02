# PRD: v0.10.10 — patch-tier (post-wave doc-cleanup; 4th p015 application)

**Status:** Auto-approved per `/loop` step 4-5; recommended path after v0.10.9 wave-plan completion + 4th p015 application surfaced gaps.
**Date:** 2026-05-02
**Predecessor:** `tasks/prd-v0.10.9-bundle.md`.
**Branch:** `ql/v0.10.10-bundle`.
**Target version:** 0.10.9 → 0.10.10 (patch).
**Total effort:** ~1 hour.

## Section 1: Introduction / Overview

4-story patch closing 5 gaps surfaced by the 4th p015 application (post-v0.10.9 doc-vs-code audit by architect + document-specialist + critic agent trio). Not part of the dogfood-driven LOW-sweep wave (which closed at v0.10.9); this is the established follow-up doc-cleanup cycle that p015 was canonized to produce.

## Section 2: Goals

- Close HIGH-tier gap: add p016 to CLAUDE.md `### Process patterns` section (precedent from p015 canonization at v0.10.2 / PIPELINE_REPORT_v36).
- Close MEDIUM-tier gaps: bump CLAUDE.md p013/p014/p015 application counts (12→17, 13→18, 2→3); reconcile PIPELINE_REPORT_v43 wave-scope review count (2→5) + IDEA_REPORT_v43 career-count (5→6).
- Close LOW-tier gaps: stale PRD line-refs in prd-v0.10.7-bundle.md US-002 (382/406/438 → 412/436/468) + prd-v0.10.8-bundle.md US-002 (296/341 → 302/349).
- 19th p014 review.
- Bump 0.10.9 → 0.10.10.
- 38 consecutive LOW G30.

## Section 3: User Stories

### US-001: CLAUDE.md process-patterns refresh + p016 canonization

**Acceptance Criteria:**
- [ ] `CLAUDE.md` line 341: p013 count "12 applications" → "17 applications (v0.9.0 → v0.9.6, v0.10.0 → v0.10.9; updated v0.10.10)".
- [ ] `CLAUDE.md` line 357: p014 count "13 review applications" → "18 review applications (post-v0.8.x: v0.8.1-v0.8.4, v0.9.1, v0.9.3-v0.9.6, v0.10.0-v0.10.9; v0.9.2 SKIPPED with rationale; updated v0.10.10)".
- [ ] `CLAUDE.md` line 371: p015 count "2 applications" → "3 applications (post-v0.10.0 closed 6 gaps in v0.10.1; post-v0.10.1 closed 3 gaps + p015 canonization in v0.10.2; post-v0.10.9 wave closure surfaced 5 gaps for v0.10.10)".
- [ ] **Add p016 entry** after p015 block. Definition: "Dogfood-driven LOW-sweep wave — when LOW backlog accumulates, batch-decompose it into a 3-5 cycle wave plan; each cycle becomes a small feature shipping 3-5 stories of related LOW closures. Every cycle is its own complete patch (PRD → code → review → ship), preserving p013/p014/p015 invariants." Empirical track record: 1 application (v0.10.6..v0.10.9; 4 cycles, 16 stories all first-attempt PASS; 5 score-≥85 inline-fixable findings caught). Canonized v0.10.9 / US-004. Canonical retrospective: `idea-stage/PIPELINE_REPORT_v43.md`.

### US-002: PIPELINE_REPORT_v43 + IDEA_REPORT_v43 quantitative reconciliation

**Acceptance Criteria:**
- [ ] `idea-stage/PIPELINE_REPORT_v43.md:88` (or wave-scope summary line): "2 inline-fixable score-≥85 findings caught" → "5 inline-fixable score-≥85 findings caught (v0.10.6: 1; v0.10.7: 1; v0.10.8: 0; v0.10.9: 3)". Recompute trio-level hit rate (3/4 = 75%) and per-reviewer rate (5/12 ≈ 42%).
- [ ] `idea-stage/PIPELINE_REPORT_v43.md` retro-table cycle-4 row: replace "TBD (this cycle's review)" with "3 MEDIUM inline-fixed (architect 88, code-reviewer 88×2)".
- [ ] `idea-stage/IDEA_REPORT_v43.md:74`: "5 review-gate catches in 18 applications (~28%)" → "6 review-gate catches in 18 applications (~33%)". Cross-reference matches PIPELINE_REPORT_v43:51 ("6th review-gate catch in 18 applications") which is correct per critic audit.
- [ ] `idea-stage/IDEA_REPORT_v43.md:85` p016 evidence stat: matches the corrected wave-scope total.

### US-003: PRD line-ref drift fixes

**Acceptance Criteria:**
- [ ] `tasks/prd-v0.10.7-bundle.md` US-002 AC line refs `lib/iteration-loop.sh:382, 406, 438` → `lib/iteration-loop.sh:412, 436, 468` (post-v0.10.8 N48 snapshot-diff insertion shifted 3 sites by +30).
- [ ] `tasks/prd-v0.10.8-bundle.md` US-002 AC line refs `lib/json-atomic.sh:296, 341` → `lib/json-atomic.sh:302, 349` (printf-with-`$err` actual line numbers).
- [ ] Implementation verdicts (N49 closed; ANSI sanitization shipped) unaffected — these are documentation-only line-ref drift fixes.
- [ ] `parallel-mode.sh:153` → `:154` minor off-by-1 in prd-v0.10.6-bundle US-001 — fold into same edit.

### US-004: Multi-perspective post-merge review (19th application) + retrospective + IDEA_REPORT_v44 + version bump 0.10.9 → 0.10.10

**Acceptance Criteria:**
- [ ] 3 reviewer agents (architect + code-reviewer + security) invoked in parallel.
- [ ] No score-≥85 finding deferred.
- [ ] `idea-stage/PIPELINE_REPORT_v44.md` documents v0.10.10 (4 stories) + 4th p015 application + 5 gaps closed.
- [ ] `idea-stage/IDEA_REPORT_v44.md` rolling forward state.
- [ ] `CHANGELOG.md [0.10.10]` entry.
- [ ] 4 plugin manifest version fields bumped 0.10.9 → 0.10.10.
- [ ] G30 self-validation (38th consecutive LOW expected).

## Section 4: Functional Requirements

- **FR-1:** All 5 gaps closed with explicit before/after evidence in IDEA_REPORT_v44.
- **FR-2:** No code change; documentation-only patch.
- **FR-3:** Plugin version 0.10.9 → 0.10.10 (4 fields).

## Section 5: Non-Goals

- No `--coordinator` dispatch (still v0.11.0 reserved).
- No N46 implementation (deferred to v0.10.11; architect's audit confirms autonomously achievable).
- No N43 work (v0.11.x architectural).

## Section 6: Design Notes

- p015 canonical pattern: spawn 3 agents (architect + document-specialist + critic) in parallel, synthesize findings, ship doc-cleanup patch with false-positive filter. This cycle is the 4th application, post-wave.
- Combining US-001 + US-002 + US-003 in a single commit is acceptable since all 3 are documentation-only edits with no inter-dependencies.

## Section 7: Technical Notes

Bash 4.3+. No new dependencies. Documentation-only patch.

## Section 8: Success Metrics

- All 4 stories first-attempt PASS.
- 5 test suites green: 15+21+44+35+18 = 133 (no test impact; docs-only).
- 38 consecutive LOW G30.
- Career p014 hit-rate: 6/19 ≈ 32% post-cycle.
