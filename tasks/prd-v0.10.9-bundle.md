# PRD: v0.10.9 — patch-tier (wave-cycle-4 final: N44 + N40-47 closeout investigation)

**Status:** Approved per `.omc/plans/2026-05-02-v0.11.0-wave-dogfood-driven-low-sweep.md` cycle-4.
**Date:** 2026-05-02
**Predecessor:** `tasks/prd-v0.10.8-bundle.md`.
**Branch:** `ql/v0.10.9-bundle`.
**Target version:** 0.10.8 → 0.10.9 (patch).
**Total effort:** ~1.5 hours.

## Section 1: Introduction / Overview

4-story patch shipping wave-plan cycle-4 (FINAL). Closes N44 (CSV/PIPELINE_REPORT count reconciliation, cosmetic) + investigates/closes-or-defers N40, N41, N38, N45, N43, N46, N47. Marks the dogfood-driven LOW-sweep wave plan complete.

## Section 2: Goals

- Audit + reconcile N44 (verify CSV row counts match PIPELINE_REPORT aggregation; document if drift exists).
- Investigate N40, N41, N38, N45, N43, N46, N47 individually; categorize each as CLOSED (obsolete post-decomposition or already implicitly closed) or DEFERRED (real work needing future cycle).
- 18th p014 review.
- Bump 0.10.8 → 0.10.9.
- 37 consecutive LOW G30.

## Section 3: User Stories

### US-001: N44 — CSV/PIPELINE_REPORT count reconciliation

**Acceptance Criteria:**
- [ ] Audit `lib/finding-persist.sh` (or equivalent CSV writer): determine whether CSV row counts match the PIPELINE_REPORT_vN aggregation language ("design=N, prd=N, plan=N").
- [ ] If reports drift from CSV: identify root cause (truncation in persistence layer? over-count in report writer?). Apply minimal fix.
- [ ] If reports match CSV (i.e., N44 was a v0.8.0-era miscount that has since been silently corrected by subsequent report writers): document closure rationale in `idea-stage/IDEA_REPORT_v43.md`.
- [ ] No new test required (verification cycle).
- [ ] No code change if audit shows reports/CSV already aligned.

### US-002: N40/N41/N38/N45/N43/N46/N47 closeout investigation

**Acceptance Criteria:**
- [ ] For each finding (N40, N41, N38, N45, N43, N46, N47): read original specification (oldest IDEA_REPORT it appears in), verify whether the underlying issue still applies in current master, and categorize:
  - **CLOSED-obsolete:** premise no longer applies (e.g., decomposition removed the surface area; a later finding subsumed it).
  - **CLOSED-implicit:** silently fixed by an unrelated cycle's work.
  - **DEFERRED-future:** real work needed; re-tier to MEDIUM/HIGH if warranted; assign tentative target version.
- [ ] Document each verdict in `idea-stage/IDEA_REPORT_v43.md` under a new "v0.10.9 N-finding closeout audit" section.
- [ ] No code change for items in CLOSED-* categories. Items in DEFERRED-future remain in the open backlog.

### US-003: Multi-perspective post-merge review (18th application)

**Acceptance Criteria:**
- [ ] 3 reviewer agents (architect + code-reviewer + security) invoked in parallel.
- [ ] No score-≥85 finding deferred.

### US-004: Wave-plan retrospective + IDEA_REPORT_v43 + version bump 0.10.8 → 0.10.9

**Acceptance Criteria:**
- [ ] `idea-stage/PIPELINE_REPORT_v43.md` documents v0.10.9 (4 stories) AND wave-plan retrospective (4 cycles: v0.10.6/v0.10.7/v0.10.8/v0.10.9).
- [ ] `idea-stage/IDEA_REPORT_v43.md` rolling forward state. Wave plan declared complete. Backlog post-sweep documented.
- [ ] `CHANGELOG.md [0.10.9]` entry.
- [ ] 4 plugin manifest version fields bumped 0.10.8 → 0.10.9.
- [ ] G30 self-validation (37th consecutive LOW expected).
- [ ] **p016 canonization decision:** if 4-cycle dogfood-driven LOW sweep proves repeatable, canonize as p016 in IDEA_REPORT_v43; otherwise document why pattern is not repeatable.

## Section 4: Functional Requirements

- **FR-1:** US-001 audit-only or minimal data fix; no architectural change.
- **FR-2:** US-002 produces verdicts (CLOSED/DEFERRED) per finding; no code change for CLOSED items.
- **FR-3:** Plugin version 0.10.8 → 0.10.9 (4 fields).

## Section 5: Non-Goals

- No `--coordinator` dispatch (still reserved for v0.11.0).
- No new architectural work for any DEFERRED-future item this cycle.
- No automated test additions (verification cycle).

## Section 6: Design Notes

- Wave plan cycle-4 closes the dogfood-driven LOW-sweep wave. Post-cycle, only DEFERRED items + the v0.11.0 operator-gated `--coordinator` dispatch remain.
- p016 canonization: if cycles v0.10.6..v0.10.9 each shipped 4 stories first-attempt PASS with no score-≥85 inline fixes deferred, the dogfood-driven LOW-sweep wave pattern qualifies for canonization.

## Section 7: Technical Notes

Bash 4.3+. No new dependencies.

## Section 8: Success Metrics

- All 4 stories first-attempt PASS.
- 5 test suites green: 15+21+44+35+18 = 133.
- 37 consecutive LOW G30.
- Wave plan COMPLETE (4 of 4 cycles shipped).
