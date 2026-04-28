# PRD: v0.7.0 — minor-tier (G22 calibration + N14 SKILL-wrapping + carry-over cleanup)

**Status:** Approved
**Date:** 2026-04-28
**Design doc:** `docs/plans/2026-04-28-v0.7.0-bundle-design.md`
**Source:** `idea-stage/IDEA_REPORT_v10.md` v0.7.0 priority slate
**Branch (planned):** `ql/v0.7.0-bundle`
**Target version:** **0.7.0** (MINOR bump from 0.6.9 — first non-patch release in 5 cycles)
**Total effort estimate:** ~2-2.5 days

> **Path note:** This file's path (`tasks/prd-v0.7.0-bundle.md`) was previously occupied by an earlier-session draft titled "v0.7.0 — pre-impl-review maturation (G12-G17)" that retag-shipped as v0.6.4 after a strict-semver review. Overwriting that obsolete content with the actual v0.7.0 PRD here.

## Section 1: Introduction / Overview

After 5 consecutive patch-tier releases (v0.6.5..v0.6.9, all classified score=25 LOW), the patch-tier backlog is drained. v0.7.0 marks the **first minor-tier framing** in this track, justified by G22 calibration analysis (substantive rubric-language work) + N14 SKILL-level orchestrator-liveness wrapping (runtime control-flow change) + 3 LOW-priority cleanups (N15/N16/N17). 6-story bundle.

**Sixth multi-cycle populated-CSV release** (15 → 18 rows).

## Section 2: Goals

- Close G22, N14, N15, N16, N17 from `IDEA_REPORT_v10`.
- Maintain 0-retry execution record (held since v0.6.0).
- Bump plugin version 0.6.9 → **0.7.0** (MINOR — first non-patch in 5 cycles).
- Backward compatibility: existing v0.6.x quantum.json files load unchanged. `QL_LIVENESS_ENABLE=false` preserves v0.6.9 dispatch semantics exactly.
- **Process milestone:** populate `metrics/pre-impl-review-findings.csv` with ≥3 new rows (total ≥18).
- **G30 self-validation re-run.** Expected outcome may be MEDIUM tier for the first time across v0.6.5..v0.7.0 — would auto-dispatch the deep-review pipeline per v0.6.6 G30 + v0.6.7 N1 wiring.

## Section 3: User Stories

### US-001: G22 — severity rubric calibration first pass

**Description:** As a maintainer of `references/finding-severity.md`, I want a snapshot calibration doc comparing 5 cycles of empirical CSV data against the rubric's expected mix.

**Acceptance Criteria:**
- [ ] New `references/severity-rubric-calibration-v0.7.0.md` (≥150 lines) with 6 sections: Methodology / Empirical distribution / Expected distribution / Drift analysis / Rubric language updates / Future work.
- [ ] Companion script `references/severity-rubric-calibration-parse.sh` (NEW; cited by §Methodology) extracts the histograms when run against `metrics/pre-impl-review-findings.csv`. Decouples doc-cell verification from script execution.
- [ ] § Empirical distribution has 3 sub-tables (design / prd / plan) × 5 cycles × 4 severities.
- [ ] § Expected distribution quotes the relevant rubric content from `references/finding-severity.md`.
- [ ] § Drift analysis flags any severity tier where empirical % differs from expected % by >20 pp.
- [ ] § Rubric language updates either lists concrete edits if drift is significant OR documents "no updates required at this baseline; revisit at v0.7.x with minor-tier comparison data."
- [ ] § Future work documents v0.7.x tracking plan.
- [ ] New `tests/test_severity_rubric_calibration.sh`: ≥4 assertions including (a) doc exists + 6 sections present + (b) self-verifying calibration — the test runs `references/severity-rubric-calibration-parse.sh` and asserts the output matches the §Empirical distribution table.
- [ ] Cross-link from CLAUDE.md `## Process references` (under N15's new "Process-related" sub-categorization).

### US-002: N14 — SKILL-level liveness wrapping in `/ql-execute`

**Description:** As an operator running `/ql-execute` in unattended mode, I want the orchestrator dispatch to be auto-wrapped with `poll_orchestrator_commits` (default 600s timeout) so STALE signals trigger handoff to the parent.

**Acceptance Criteria (PRESENCE-ONLY — matches v0.6.8 N6 prose-guard pattern):**
- [ ] `skills/ql-execute/SKILL.md` (existence verified at design-review time) gains a new `## Orchestrator liveness gate` subsection.
- [ ] The subsection documents the wrapping flow: dispatch orchestrator → invoke `poll_orchestrator_commits` from a parent-side bash block → on STALE (rc=1) emit a structured handoff message pointing parent at `references/orchestrator-takeover.md` → exit SKILL with rc=1 (`orchestrator-stale` signal).
- [ ] `QL_LIVENESS_ENABLE` env var (default `true`) is documented; when set to `false`, the wrapping is skipped (v0.6.9 backwards compat).
- [ ] The SKILL.md contains the substring `references/orchestrator-takeover.md` (cross-link to N13's SOP).
- [ ] The SKILL.md contains the substring `QL_LIVENESS_ENABLE` (env-var documented).
- [ ] New `tests/test_ql_execute_liveness_wrapping.sh`: ≥4 PRESENCE-ONLY assertions (header + env-var + default-true + cross-link + handoff-message structure). NO runtime SKILL-execution test (matches v0.6.8 N6 — runtime enforcement deferred to v0.7.1 if needed).

### US-003: N15 — Process references CLAUDE.md re-categorization

**Description:** As a future operator skim-reading CLAUDE.md, I want `## Process references` sub-categorized into 3 sub-headers (Orchestrator-related / Test-related / Process-related).

**Acceptance Criteria:**
- [ ] `CLAUDE.md` `## Process references` refactored to use 3 `### ` sub-headers: `Orchestrator-related`, `Test-related`, `Process-related`.
- [ ] Existing entries placed in natural categories: orchestrator-takeover.md → Orchestrator-related; test-wallclock-baselines.md → Test-related; soliton-finding-triage.md → Process-related; severity-rubric-calibration-v0.7.0.md (NEW from US-001) → Process-related.
- [ ] All 3 existing tests' cross-link assertions updated (`tests/test_orchestrator_takeover_doc.sh`, `tests/test_soliton_triage_doc.sh`, `tests/test_wallclock_baselines_doc.sh`).
- [ ] Existing 14 cross-link assertions remain green post-refactor.

### US-004: N16 — interval_sec=0 guard

**Description:** As a caller of `poll_orchestrator_commits`, I want a guard that fails-fast on `interval_sec <= 0` instead of an infinite loop.

**Acceptance Criteria:**
- [ ] `lib/orchestrator-liveness.sh::poll_orchestrator_commits` adds the guard at the top: `if (( interval_sec <= 0 )); then printf "[LIVENESS] ERROR: interval_sec must be > 0 (got %s)\n" "$interval_sec" >&2; return 1; fi`.
- [ ] New Test 5 in `tests/test_orchestrator_liveness.sh`: `poll_orchestrator_commits 10 0` returns 1 within 2s wall-clock + emits ERROR log line (NOT STALE).
- [ ] Existing 8 assertions remain green.

### US-005: N17 — REPO_ROOT shell-quoting in bench

**Description:** As a developer cloning to a path containing single quotes, I want `tests/bench_wallclock_baseline_drift.sh` to remain syntactically safe.

**Acceptance Criteria:**
- [ ] `tests/bench_wallclock_baseline_drift.sh` replaces `time eval "(cd '$REPO_ROOT' && $cmd)"` with `printf %q`-quoted form: `safe_cmd=$(printf '(cd %q && %s)' "$REPO_ROOT" "$cmd"); time eval "$safe_cmd"`.
- [ ] `bash -n tests/bench_wallclock_baseline_drift.sh` passes.
- [ ] Grep verification: file contains `printf '(cd %q'` literal.

### US-006: Retrospective + IDEA_REPORT_v11 + version bump 0.6.9 → 0.7.0

**Acceptance Criteria:**
- [ ] `idea-stage/PIPELINE_REPORT_v11.md` documents v0.7.0 dogfood including the **expected-vs-actual G30 classification** (may be MEDIUM tier for the first time).
- [ ] PIPELINE_REPORT_v11 notes `metrics/pre-impl-review-findings.csv` has ≥18 rows.
- [ ] `idea-stage/IDEA_REPORT_v11.md` lists open after v0.7.0; carries forward N14-followup (broader SKILL formalization beyond ql-execute).
- [ ] `quantum-loop.sh --audit` captured to `.omc/phase-N-evidence/v0.7.0-audit.log`.
- [ ] G30 self-validation captured to `.omc/phase-N-evidence/v0.7.0-deep-review-decision.log`; decision recorded in `quantum.json.reviews[v0.7.0-bundle].deepReview` with `automated:true`.
- [ ] If MEDIUM tier, the deep-review pipeline auto-dispatches reviewers; document the verdict and operator response in PIPELINE_REPORT_v11.
- [ ] CHANGELOG.md updated with v0.7.0 entry (explicit MINOR-bump rationale).
- [ ] All 4 plugin manifest version fields bumped 0.6.9 → 0.7.0.

## Section 4: Functional Requirements

- **FR-1:** `references/severity-rubric-calibration-v0.7.0.md` exists with 6 sections + companion parse-script reference + drift analysis.
- **FR-2:** `skills/ql-execute/SKILL.md` `## Orchestrator liveness gate` documents wrapping + env-var + handoff (presence-only AC).
- **FR-3:** `CLAUDE.md` `## Process references` uses 3 `### ` sub-headers.
- **FR-4:** `poll_orchestrator_commits` guards `interval_sec <= 0`.
- **FR-5:** `bench_wallclock_baseline_drift.sh` uses `printf %q` quoting.
- **FR-6:** `metrics/pre-impl-review-findings.csv` has ≥18 rows.
- **FR-7:** Plugin version bumped 0.6.9 → 0.7.0 across 4 fields.
- **FR-8:** v0.7.0's own diff classified by its own should_dispatch_deep_review rule; recorded with `automated:true`. Possible first MEDIUM-tier outcome.

## Section 5: Non-Goals (Out of Scope)

- **NG-1:** N14 broader SKILL formalization (auto-wrapping for skills beyond `/ql-execute`) — v0.7.1+ candidate.
- **NG-2:** G19 — only revisit if a 4th pre-impl-review stage is added.
- **NG-3:** P5.B2/B3/B5 + P5.C frontier — same triage.
- **NG-4:** G21 / G24 — same triage.
- **NG-5:** Schema migration — none needed.
- **NG-6:** **Acting on BLOCKS_MERGE or REQUEST_CHANGES verdicts** from v0.7.0's first MEDIUM-tier deep-review dispatch is operator discretion. The PRD does not pre-specify the response since the verdict shape is unknown until the dispatch runs. PIPELINE_REPORT_v11 documents the actual verdict + chosen response.

## Section 6: Design Considerations

UI: command-line + agent-prose-only. v0.7.0 changes surface in operators running `/ql-execute` (auto-liveness wrapping), PRD authors (calibration snapshot), CLAUDE.md skim-readers (re-categorization), `poll_orchestrator_commits` callers (fail-fast on bad interval), bench operators on quoted paths.

1 new env var: `QL_LIVENESS_ENABLE` (default true; set false for v0.6.9 backwards compat).

## Section 7: Technical Considerations

- **Shell compatibility:** bash 4.3+.
- **External tools:** unchanged from v0.6.9.
- **Quality gates:** all stories pass typecheck/lint quality gates (orchestrator Step 5 — full `bash tests/run_all.sh` excluding bench_*).
- **MINOR bump rationale:** G22 + N14 substance + 5-cycle patch-tier-track-closure framing.

## Section 8: Success Metrics

- All 6 user stories pass with verifiable evidence.
- `bash tests/test_audit.sh` → 45/45 PASS unchanged.
- `bash tests/test_orchestrator_liveness.sh` → 9/9 PASS (8 + N16 Test 5).
- `bash tests/test_severity_rubric_calibration.sh` → ≥4/4 PASS (NEW).
- `bash tests/test_ql_execute_liveness_wrapping.sh` → ≥4/4 PASS (NEW).
- `metrics/pre-impl-review-findings.csv` has ≥18 rows.
- Plugin version bumped to 0.7.0.
- IDEA_REPORT_v11 lists open backlog.
- 0-retry execution record maintained.

## Section 9: Open Questions

None. 3 design-review findings + 3 prd-review findings addressed inline (HIGH SKILL-existence resolved; MEDIUM self-verifying calibration via separate parse-script; LOW expected-G30 quantified; MEDIUM US-002 presence-only AC re-anchored to v0.6.8 N6 pattern; LOW US-001 separate-script for parse decoupling; LOW NG-6 verdict-discretion).

## Lifecycle Checklist

- **First-run behavior** — Operators get auto-liveness wrapping unless `QL_LIVENESS_ENABLE=false`.
- **Returning-user behavior** — `QL_LIVENESS_ENABLE=false` preserves v0.6.9 semantics exactly.
- **Update behavior** — MINOR bump signals possible rubric updates; operators re-read `references/finding-severity.md` if calibration found drift.
- **Error recovery** — `poll_orchestrator_commits interval_sec=0` now fails-fast.
- **No-data / empty state** — calibration covers v0.6.5..9; future cycles re-snapshot.
- **Uninstall / disable** — `QL_LIVENESS_ENABLE=false` opts out of N14.

## Next Steps

Author quantum.json. Trigger plan-review hook (CSV row 18). Spawn dag-validator. Execute stories. Post-merge: `/soliton:pr-review`, fix score-≥85 inline, squash-merge, tag v0.7.0.
