# PRD: v0.10.14 — patch-tier (career hit-rate audit + p014 range notation cleanup)

**Status:** Auto-approved per `/loop` step 4-5; closes the 2 pre-existing notational artifacts surfaced by v0.10.12 review trio (architect LOW + code-reviewer MEDIUM, both deferred to "v0.10.13 or future p015 audit"; v0.10.13 closed different items so this is the next available cycle).
**Date:** 2026-05-02
**Predecessor:** `tasks/prd-v0.10.13-bundle.md`.
**Branch:** `ql/v0.10.14-bundle`.
**Target version:** 0.10.13 → 0.10.14 (patch).
**Total effort:** ~45 min.

## Section 1: Introduction / Overview

4-story patch closing 2 pre-existing notational artifacts:
1. **Career p014 hit-rate off-by-one** since v0.10.10 (architect LOW / code-reviewer MEDIUM at v0.10.12 review). Recount + propagate corrections through PIPELINE_REPORT_v44/v45/v46/v47, IDEA_REPORT_v44/v45/v46/v47, and CLAUDE.md.
2. **p014 range notation ambiguity** — v0.9.1 listed in the application range but not itself a p014 application (it's gap context for v0.9.2 SKIPPED). Code-reviewer flagged the enumeration mismatch (range enumerates to 21, count says 20) at v0.10.12 review.

## Section 2: Goals

- Audit catch counts cycle-by-cycle from PR_v40..PR_v47 to determine true career stat.
- Update all stale references (4 PIPELINE_REPORTs, 4 IDEA_REPORTs, CLAUDE.md) with corrected count.
- Disambiguate p014 range notation: either remove v0.9.1 from the listed range OR explicitly mark it as "(non-application; gap context for v0.9.2 SKIPPED)".
- 23rd p014 review.
- Bump 0.10.13 → 0.10.14.
- 42 consecutive LOW G30.

## Section 3: User Stories

### US-001: Career hit-rate audit + correction

**Acceptance Criteria:**

**Audit (verify counts):**
- [ ] Recount cycle-by-cycle catches v0.10.6..v0.10.13 from each PIPELINE_REPORT's review-synthesis section (count "trios with ≥1 score-≥85 inline-fixable finding"). Expected:
  - v0.10.6: 1 catch (cross-ref MEDIUM at code-reviewer 88)
  - v0.10.7: 1 catch (Retry-After MEDIUM at code-reviewer 88 + architect 88)
  - v0.10.8: 0 catches (sub-threshold MEDIUM + LOW deferred)
  - v0.10.9: 1 catch (architect 88 N44-evidence + code-reviewer 88 ×2)
  - v0.10.10: 1 catch (convergent IDEA_REPORT_v43:84-85 propagation MEDIUM)
  - v0.10.11: 1 catch (architect set-e regression + security chmod 600 + traps)
  - v0.10.12: 0 catches (pre-existing only)
  - v0.10.13: 1 catch (test 16 encoding + awk gsub + OSC-ST docs + found-flag)
- [ ] Wave segment (v0.10.6..v0.10.9) total: 3 catches.
- [ ] Post-wave (v0.10.10..v0.10.13) total: 3 catches.
- [ ] Pre-wave baseline (PR_v39 "3rd catch in 14"): 3/14.

**True career stat by ship cycle:**
- v0.10.6: 4/15 ✓ (matches PR_v40 implicit)
- v0.10.7: 5/16 ✓ (matches PR_v41 "5/16")
- v0.10.8: 5/17 ✓ (matches PR_v42 "5/17")
- v0.10.9: 6/18 ✓ (matches PR_v43 "6th in 18")
- v0.10.10: **7/19** (PR_v44 says 6/19 — OFF BY 1)
- v0.10.11: **8/20** (PR_v45 says 7/20 — OFF BY 1)
- v0.10.12: **8/21** (PR_v46 says 7/21 — OFF BY 1)
- v0.10.13: **9/22 ≈ 41%** (PR_v47 says 8/22 — OFF BY 1)

**Corrections (propagate latest stat as historical context, not retroactive rewrite):**
- [ ] `idea-stage/IDEA_REPORT_v47.md` line ~75: "8 review-gate catches in 22 applications (~36% career hit-rate)" → "9 review-gate catches in 22 applications (~41% career hit-rate; corrects off-by-one in PR_v44 onward identified at v0.10.12 review)".
- [ ] `idea-stage/PIPELINE_REPORT_v47.md` line ~88: "8th p014 catch in 22 applications career; ~36% career hit-rate" → "9th p014 catch in 22 applications career; ~41% career hit-rate (corrected from 8/22 per audit)".
- [ ] `CLAUDE.md` line 359: "Career score-≥85 inline-fix hit rate: 7/20 ≈ 35%." → "Career score-≥85 inline-fix hit rate: 9/22 ≈ 41% (audited + corrected v0.10.14)."
- [ ] Past PIPELINE_REPORTs (v44/v45/v46) and IDEA_REPORTs (v44/v45/v46): leave as-is per "snapshot in time" convention. The audit's correction lives in v48 going forward.

### US-002: p014 range notation cleanup

**Acceptance Criteria:**
- [ ] `CLAUDE.md` lines 356-358 p014 range: "v0.8.1-v0.8.4, v0.9.1, v0.9.3-v0.9.6, v0.10.0-v0.10.11" → "v0.8.1-v0.8.4, v0.9.3-v0.9.6, v0.10.0-v0.10.13; v0.9.1 + v0.9.2 SKIPPED (v0.9.1 was foundational scaffolding, no review-trio applied; v0.9.2 SKIPPED with rationale per US-004 dogfood)". Includes v0.10.12 + v0.10.13 ranging update too.
- [ ] Result: enumerated count = 4 + 4 + 14 = 22 ✓ matches stated "22 review applications".
- [ ] Application count bumps 20 → 22 (covers v0.10.12 + v0.10.13).

### US-003: Multi-perspective post-merge review (23rd application)

**Acceptance Criteria:**
- [ ] 3 reviewer agents (architect + code-reviewer + security) invoked in parallel.
- [ ] No score-≥85 finding deferred.

### US-004: Retrospective + IDEA_REPORT_v48 + version bump 0.10.13 → 0.10.14

**Acceptance Criteria:**
- [ ] `idea-stage/PIPELINE_REPORT_v48.md` documents v0.10.14 (4 stories) + audit findings.
- [ ] `idea-stage/IDEA_REPORT_v48.md` rolling forward state.
- [ ] `CHANGELOG.md [0.10.14]` entry.
- [ ] 4 plugin manifest version fields bumped 0.10.13 → 0.10.14.
- [ ] G30 self-validation (42nd consecutive LOW expected).

## Section 4: Functional Requirements

- **FR-1:** Audit identifies + corrects off-by-one error introduced at v0.10.10 PIPELINE_REPORT.
- **FR-2:** No code change; documentation-only patch.
- **FR-3:** Plugin version 0.10.13 → 0.10.14 (4 fields).

## Section 5: Non-Goals

- No `--coordinator` dispatch (still v0.11.0 reserved).
- No retroactive rewrite of historical PIPELINE_REPORT/IDEA_REPORT (snapshot-in-time convention).
- No N43 / N48 stub-coord work (operator-gated).

## Section 6: Design Notes

- **Off-by-one root cause:** PIPELINE_REPORT_v43 used phrase "6th catch in 18" referring to v0.10.9 itself being the 6th catch. PIPELINE_REPORT_v44 then said "6th catch in 19" — should have been "7th catch in 19" since v0.10.10 review trio also produced a catch (the IDEA_REPORT_v43:84-85 propagation MEDIUM caught convergently). Off-by-one propagated forward.
- **Snapshot-in-time convention:** historical PIPELINE_REPORTs are treated as immutable artifacts. The audit's correction ships in v0.10.14's IDEA_REPORT_v48 + CLAUDE.md, with explicit cross-reference to where the off-by-one originated.

## Section 7: Technical Notes

Markdown-only. No new dependencies.

## Section 8: Success Metrics

- All 4 stories first-attempt PASS.
- 6 test suites green (carried forward): 15+21+44+39+18+38 = 175.
- 42 consecutive LOW G30.
- Pre-existing notational artifacts closed; future stat references will use 9/22 baseline.
