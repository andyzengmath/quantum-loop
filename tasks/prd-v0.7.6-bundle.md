# PRD: v0.7.6 — patch-tier reactive (N34)

**Status:** Approved
**Date:** 2026-04-28
**Design doc:** `docs/plans/2026-04-28-v0.7.6-bundle-design.md`
**Branch:** `ql/v0.7.6-bundle`
**Target version:** 0.7.6

## Section 1: Overview

2-story compact reactive closing N34 (untracked design+PRD docs audit check) + retrospective.

## Section 2: Goals

- Close N34 from IDEA_REPORT_v16.
- Bump 0.7.5 → 0.7.6.
- 11th LOW G30 expected.

## Section 3: User Stories

### US-001: N34 — untracked-design-prd audit

**Acceptance Criteria:**
- [ ] `quantum-loop.sh` adds `_audit_untracked_design_prd_docs` helper using `git ls-files --others --exclude-standard docs/plans/ tasks/`. WARN if any matches; OK otherwise.
- [ ] Helper invoked from `do_audit` ROWS array (after `_audit_csv_uncommitted`).
- [ ] `tests/test_audit.sh` adds Test 39 + 39b verifying helper definition + invocation (mirrors Test 38/38b pattern from N29).
- [ ] Existing 47+ audit tests remain green.

### US-002: Retrospective + IDEA_REPORT_v17 + version bump 0.7.5 → 0.7.6

**Acceptance Criteria:**
- [ ] `idea-stage/PIPELINE_REPORT_v17.md` documents v0.7.6.
- [ ] `idea-stage/IDEA_REPORT_v17.md` lists open after v0.7.6.
- [ ] CHANGELOG [0.7.6] entry.
- [ ] All 4 manifest version fields → 0.7.6.

## Section 4-9

Cross-platform: bash 4.3+. WARN-level only. No env var changes.

Non-Goals: auto-staging the docs (out of scope), gating the warn (operators may legitimately have draft docs untracked), promoting to FAIL.

## Next Steps

Advisory hooks → execute → review → squash → tag v0.7.6.
