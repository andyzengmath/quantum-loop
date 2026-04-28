# PRD: v0.7.5 — patch-tier reactive (N29 + N31 + retrospective)

**Status:** Approved
**Date:** 2026-04-28
**Design doc:** `docs/plans/2026-04-28-v0.7.5-bundle-design.md`
**Source:** `idea-stage/IDEA_REPORT_v15.md` v0.7.5 candidates
**Branch:** `ql/v0.7.5-bundle`
**Target version:** 0.7.5

## Section 1: Overview

3-story reactive patch closing 2 LOW process gaps surfaced in v0.7.4 dogfood (N29 CSV audit + N31 spec grep-verify) + retrospective. Tenth multi-cycle populated-CSV run (24 → 27 rows).

## Section 2: Goals

- Close N29 + N31 from IDEA_REPORT_v15.
- Bump plugin version 0.7.4 → 0.7.5.
- CSV ≥27 rows.
- G30 self-validation (10th LOW expected).

## Section 3: User Stories

### US-001: N29 — CSV-commit audit warning

**Acceptance Criteria:**
- [ ] `quantum-loop.sh --audit` adds new check `csv-uncommitted`: runs `git status --porcelain metrics/pre-impl-review-findings.csv`; if non-empty emits WARN line (NOT FAIL).
- [ ] New audit check appears in the Summary line as `csv-uncommitted: <state>`.
- [ ] `tests/test_audit.sh` adds new test: synthesize uncommitted CSV change → run `--audit` → grep WARN line + verify Summary count includes the new check.
- [ ] Existing audit checks (45) remain green.
- [ ] Typecheck/lint passes.

### US-002: N31 — spec grep-verify instruction

**Acceptance Criteria:**
- [ ] `skills/ql-spec/SKILL.md` Step 1 (Gather Context) adds bullet about grep-verifying cited file paths. Exact phrasing: "Before citing any file path in an AC, run a grep/ls verification that the path exists. If the path is being created by this PRD, annotate with `[NEW]` in parentheses to disambiguate."
- [ ] Grep verification: `skills/ql-spec/SKILL.md` contains "grep-verify" or "grep/ls verification" phrase.
- [ ] No runtime tests affected (doc-only edit).
- [ ] Typecheck/lint passes.

### US-003: Retrospective + IDEA_REPORT_v16 + version bump 0.7.4 → 0.7.5

**Acceptance Criteria:**
- [ ] `idea-stage/PIPELINE_REPORT_v16.md` documents v0.7.5 reactive cycle.
- [ ] `idea-stage/IDEA_REPORT_v16.md` lists open after v0.7.5.
- [ ] G30 self-validation captured `automated:true`.
- [ ] CHANGELOG [0.7.5] entry.
- [ ] All 4 plugin manifest fields bumped 0.7.4 → 0.7.5 (3 manifest files).

## Section 4: Functional Requirements

- **FR-1:** `quantum-loop.sh --audit` includes csv-uncommitted check; emits WARN on uncommitted CSV.
- **FR-2:** `skills/ql-spec/SKILL.md` Step 1 contains the grep-verify instruction.
- **FR-3:** CSV ≥27 rows; plugin 0.7.5; reviews `automated:true`.

## Section 5: Non-Goals

- **NG-1:** Promoting csv-uncommitted from WARN to FAIL (deliberate — operators may have legit pending work).
- **NG-2:** Auto-staging the CSV during audit (out of scope; explicit operator action only).
- **NG-3:** Backfilling v0.7.2/v0.7.3 advisory hook rows into committed CSV (history is sealed).

## Section 6-8: Design / Technical / Success Metrics

Cross-platform: bash 4.3+. Audit check uses standard `git status --porcelain`. Skill-prompt edit is doc-only.

Success: 3 stories first-attempt PASS; CSV at 27 rows; 10th LOW G30; v0.7.5 tagged.

## Section 9: Open Questions

None.

## Lifecycle Checklist

- First-run: N/A (incremental change to existing tools).
- Returning-user: WARN line surfaces only when CSV has uncommitted changes — invisible otherwise.
- Update: standard 3-manifest bump.
- Error recovery: WARN is advisory; never blocks.
- No-data: --audit always emits a Summary line.
- Uninstall/disable: revert via git; no persistent state.

## Next Steps

Advisory hooks → quantum.json → execute → soliton + copilot review → squash-merge → tag v0.7.5.
