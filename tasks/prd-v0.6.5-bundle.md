# PRD: v0.6.5 — v0.6.4 follow-through cleanup (G18, G20, G25, G26, G27, G28)

**Status:** Approved
**Date:** 2026-04-27
**Design doc:** `docs/plans/2026-04-27-v0.6.5-bundle-design.md`
**Source:** `idea-stage/IDEA_REPORT_v5.md` v0.6.5 priority list
**Branch (planned):** `ql/v0.6.5-bundle`
**Target version:** 0.6.5 (patch bump from 0.6.4)
**Total effort estimate:** ~2-3 days (single-developer; ~1.5 days with parallel waves)

## Section 1: Introduction / Overview

This release closes 6 follow-through items from v0.6.4's two post-merge review passes (`/code-review:code-review` + `/soliton:pr-review`) plus a design-doc-vs-shipped audit: misleading audit summary, missed regex consumer, sort enumeration gap, risk-mitigation language checklist, audit drill copy, and a permanent README section on self-modifying execution. All 6 items are well-bounded cleanup or small additive doc artifacts.

The 7-story bundle stays **patch-tier**: no breaking changes, no schema deltas, no new lib modules, no new env vars. The smallest bundle by "new code shipped" since v0.5.x.

Per `IDEA_REPORT_v5`'s explicit process commitment: this v0.6.5 cycle is **the first end-to-end populated-CSV run** for `metrics/pre-impl-review-findings.csv`. The v0.6.4 advisory hooks fire against this design doc, this PRD, and the upcoming `quantum.json` so the CSV ledger is populated for the first time post-v0.6.4 install.

## Section 2: Goals

- Close G18, G20, G25, G26, G27, G28 from `IDEA_REPORT_v5`.
- Maintain the 0-retry execution record (v0.6.0 baseline; held at v0.6.3 + v0.6.4).
- Bump plugin version 0.6.4 → 0.6.5 across all 3 manifests in lockstep.
- Backward compatibility: existing v0.6.x quantum.json files load and run unchanged.
- **Process milestone:** populate `metrics/pre-impl-review-findings.csv` with at least 3 rows (design + prd + plan stages from this cycle's planning).
- Reinstate `ql-deep-review` invocation at the wave-N boundary (addressing the v0.6.4 design-doc-vs-shipped audit gap).

## Section 3: User Stories

### US-001: G26 — split `do_audit` summary into OK / WARN / FAIL

**Description:** As an operator running `quantum-loop.sh --audit`, I want the summary line to honestly report `<ok>/<total> OK, <warn> WARN, <fail> FAIL` instead of "X/Y metrics on target" (which silently counts WARN as on-target), so that a fresh-checkout WARN row from `pre-impl-review-coverage` doesn't mislead me into thinking the codebase is healthier than it is.

**Acceptance Criteria:**
- [ ] `do_audit` in `quantum-loop.sh` walks `ROWS[]` once and accumulates three counters from the `|OK|`, `|WARN|`, `|FAIL|` substrings.
- [ ] Summary line replaces the existing `printf "Summary: %d/%d metrics on target.\n"` with `printf "Summary: %d/%d OK, %d WARN, %d FAIL.\n"`.
- [ ] Exit code semantics preserved: `do_audit` returns 1 iff any row contains `|FAIL|`. WARN does NOT trip exit code.
- [ ] `tests/test_audit.sh` Test 33 expectation updated from `"7 metrics on target"` to `"6/7 OK, 1 WARN, 0 FAIL"` (matching the v0.7.0 audit log fixture).
- [ ] New assertions: 3-OK fixture → `"3/3 OK, 0 WARN, 0 FAIL."`; mixed-3-state fixture (1 OK + 1 WARN + 1 FAIL) → exit 1 + `"1/3 OK, 1 WARN, 1 FAIL."`.
- [ ] Existing 30 baseline + 6 G17 audit assertions remain green.
- [ ] CHANGELOG documents the summary-format change as v0.6.5.
- [ ] Typecheck/lint passes.

### US-002: G27 — extract 5th regex copy from `agents/spec-reviewer.md`

**Description:** As a maintainer of the Sprint-Contract test-pattern regex, I want `agents/spec-reviewer.md`'s plan-review checklist to reference `lib/handoff.sh::SPRINT_CONTRACT_TEST_REGEX` as the single source of truth, closing the 5th call site that v0.6.4's G14 / US-003 missed.

**Acceptance Criteria:**
- [ ] `agents/spec-reviewer.md` plan-review checklist's `testFirst command consistency` rule (around line 117) updated to cite `lib/handoff.sh::SPRINT_CONTRACT_TEST_REGEX` as the canonical pattern source.
- [ ] The actual regex characters remain visible inline in the checklist prose (the agent reads markdown — visibility helps), but with the explicit "see ... for the canonical pattern" framing.
- [ ] `lib/handoff.sh` `SPRINT_CONTRACT_TEST_REGEX` doc-comment updated to add `agents/spec-reviewer.md plan-review` to the consumer list (was 4 sites → now 5).
- [ ] New assertion in `tests/test_sprint_contract.sh`: `grep -q 'SPRINT_CONTRACT_TEST_REGEX' agents/spec-reviewer.md` succeeds.
- [ ] Existing G14 no-inline-regex assertion (covering orchestrator.md + ql-plan SKILL.md) remains green.
- [ ] Existing 18 sprint-contract + 13 sprint-contract-ql-plan assertions remain green.
- [ ] Typecheck/lint passes.

### US-003: G25 — extend conflict-auditor sort enumeration

**Description:** As an agent following `agents/conflict-auditor.md` Step 4 sort instruction, I want the enumeration to include all 5 severity values (`high → medium → low → warning → none`), so that conflicts with the new `none` (Rule 0) and `warning` (Rule 0.5) severities have deterministic ordering.

**Acceptance Criteria:**
- [ ] `agents/conflict-auditor.md` Step 4 sort instruction prose updated to enumerate all 5 severities in order: `high → medium → low → warning → none`.
- [ ] The chosen order is documented inline with a 1-sentence rationale: high is most-impactful; warning is informational-but-real-signal; none is "no conflict" / informational only.
- [ ] New assertion in `tests/test_changelog_ownership.sh`: `agents/conflict-auditor.md` contains the substring `"high → medium → low → warning → none"` (or equivalent literal enumeration).
- [ ] Existing 9 changelog-ownership assertions remain green.
- [ ] No code changes required (the sort happens in agent prose; the JSON `fileConflicts` array structure is unchanged).
- [ ] Typecheck/lint passes.

### US-004: G28 — `references/risk-mitigation-language.md` checklist

**Description:** As a design-doc author proposing a risk-mitigation, I want a checklist that prevents the kind of vague language that allowed the v0.6.4 flock race to slip past initial review, so that future design-doc Risk sections enumerate the operations to wrap, not just the technique.

**Acceptance Criteria:**
- [ ] New `references/risk-mitigation-language.md` contains 3 sections:
  - `## Risk-mitigation prose: enumerate operations, not just techniques` — the rule + the v0.6.4 cautionary tale (cite `c89ba13`).
  - `## Concurrency checklist for design docs` — when proposing `flock`, `mutex`, `semaphore`, `atomic-rename`, etc., the design doc MUST enumerate: shared mutable state; full set of observably-coupled operations; race window without mitigation; race window with mitigation.
  - `## Other risk-mitigation language patterns` — short-form rules for `validate input X`, `handle malformed Y`, `atomic update Z`.
- [ ] Concurrency checklist has the 4 enumerated requirements (state, operations, race-without, race-with).
- [ ] Doc cites the v0.6.4 cautionary tale: header-write outside flock, soliton finding at conf 90, fix in `c89ba13`.
- [ ] Optional: 1-line cross-link from `references/finding-severity.md` pointing here (pair docs that guide design + review craft).
- [ ] New `tests/test_risk_mitigation_language.sh` has ≥8 assertions covering doc structure: 3 section headers, 4 concurrency-checklist requirements, cautionary-tale citation substring.
- [ ] Typecheck/lint passes.

### US-005: G18 — `--audit` `pre-impl-review-coverage` WARN drill copy

**Description:** As an operator running `--audit` on a fresh checkout, I want the `pre-impl-review-coverage` `missing-csv` WARN drill text to clarify that this is the expected first-run state (not a regression), so that I know to invoke the planning skills to populate the CSV.

**Acceptance Criteria:**
- [ ] `quantum-loop.sh::_audit_pre_impl_review_coverage` `missing-csv` branch updated: drill text changes from `"no metrics CSV"` to `"no metrics CSV (expected on first run after install — invoke /ql-brainstorm/spec/plan to populate)"`.
- [ ] Other WARN states (`no recent runs`, `missing some stages`) keep their existing concise drill messages.
- [ ] `tests/test_audit.sh` Test 28 expectation updated to match the new drill text.
- [ ] New assertion: drill text contains the substring `"(expected on first run"`.
- [ ] Existing 30 baseline + 6 G17 audit assertions remain green.
- [ ] Typecheck/lint passes.

### US-006: G20 — README "Self-modifying execution" section

**Description:** As a new operator reading the project README, I want a permanent section explaining that quantum-loop is self-modifying (each release's wires apply to NEXT runs, not the current dogfood), so I don't mistake "empty CSV after fresh install" for a regression.

**Acceptance Criteria:**
- [ ] `README.md` gains a new `## Self-modifying execution` section near the existing pipeline-overview prose.
- [ ] Section content (1-2 paragraphs) explains: each release ships a bundle that often modifies the orchestrator/agent/skill prompts the orchestrator itself uses; the orchestrator runs on the PREVIOUS release's semantics; new wires apply to runs starting AFTER the bundle merges.
- [ ] Section includes at least one concrete example release (e.g., "v0.6.4 added pre-impl-review persistence; the v0.6.4 dogfood ran on v0.6.3 master HEAD, so its CSV is empty by design. v0.6.5's first run is the first to populate the CSV.").
- [ ] New `tests/test_readme.sh` (or extend if exists) has ≥5 assertions: section heading present, key phrase "self-modifying", "previous release's semantics" or equivalent, concrete example, cross-link to PIPELINE_REPORT_v5 (or equivalent).
- [ ] Typecheck/lint passes.

### US-007: Retrospective + IDEA_REPORT_v6 + version bump 0.6.4 → 0.6.5

**Description:** As a project maintainer, I want a structured retrospective after Wave 1 captures findings from running v0.6.5 through the pipeline, an IDEA_REPORT_v6 mapping what's still open after v0.6.5, plugin version bumped 0.6.4 → 0.6.5 across all 3 manifests, AND verification that the populated-CSV milestone landed (≥3 rows from this cycle's planning).

**Acceptance Criteria:**
- [ ] `idea-stage/PIPELINE_REPORT_v6.md` documents v0.6.5 dogfood: total wall-clock, wave timings, cross-story-contract events, test-suite delta vs v0.6.4.
- [ ] PIPELINE_REPORT_v6 explicitly notes `metrics/pre-impl-review-findings.csv` has ≥3 rows after this cycle's planning hooks fired (design + prd + plan).
- [ ] `idea-stage/IDEA_REPORT_v6.md` lists what's still open after v0.6.5: G19, G21, G22, G24, P5.B2/B3/B5, P5.C* + any new gaps surfaced this run.
- [ ] `quantum-loop.sh --audit` re-run after Wave 1 merges; output captured to `.omc/phase-N-evidence/v0.6.5-audit.log`.
- [ ] Audit log shows the new split summary `<ok>/<total> OK, <warn> WARN, <fail> FAIL` (G26) AND the improved missing-csv drill text (G18) — both behaviors visible in the captured audit log.
- [ ] `pre-impl-review-coverage` may now report `partial-coverage` or `full-coverage` depending on which stages ran in the last 7 days.
- [ ] `CHANGELOG.md` updated with v0.6.5 entry covering 6 user-facing stories.
- [ ] `.claude-plugin/plugin.json` version bumped 0.6.4 → 0.6.5.
- [ ] `.claude-plugin/marketplace.json` (BOTH `metadata.version` AND `plugins[0].version`) bumped 0.6.4 → 0.6.5.
- [ ] `.cursor-plugin/plugin.json` bumped 0.6.4 → 0.6.5.
- [ ] **`ql-deep-review` invoked at MEDIUM tier after Wave 1** (addressing the v0.6.4 design-doc-vs-shipped audit gap). Findings captured in `quantum.json.reviews[]`.
- [ ] Typecheck/lint passes.

## Section 4: Functional Requirements

- **FR-1:** `do_audit` summary reports `<ok>/<total> OK, <warn> WARN, <fail> FAIL` (split counters).
- **FR-2:** `do_audit` exit code: 1 iff any FAIL row; WARN does not trip exit (existing behavior preserved).
- **FR-3:** `agents/spec-reviewer.md` plan-review checklist cites `lib/handoff.sh::SPRINT_CONTRACT_TEST_REGEX` as the canonical pattern.
- **FR-4:** `lib/handoff.sh::SPRINT_CONTRACT_TEST_REGEX` doc-comment lists 5 consumers (was 4).
- **FR-5:** `agents/conflict-auditor.md` Step 4 sort prose enumerates all 5 severities in order: `high → medium → low → warning → none`.
- **FR-6:** `references/risk-mitigation-language.md` exists with 3 sections (rule, concurrency checklist, short-form patterns).
- **FR-7:** `_audit_pre_impl_review_coverage` `missing-csv` drill text contains `"(expected on first run"`.
- **FR-8:** `README.md` has a `## Self-modifying execution` section with at least one concrete example release.
- **FR-9:** `metrics/pre-impl-review-findings.csv` has ≥3 rows after v0.6.5 ships, captured in PIPELINE_REPORT_v6.
- **FR-10:** Plugin version bumped 0.6.4 → 0.6.5 across `.claude-plugin/plugin.json`, `.claude-plugin/marketplace.json` (both fields), `.cursor-plugin/plugin.json`.

## Section 5: Non-Goals (Out of Scope)

- **NG-1:** G19 (3-SKILL-wrapper centralization) — only revisit if a 4th pre-impl-review stage is added.
- **NG-2:** G21 (metrics CSV rotation) — premature until >100 rows.
- **NG-3:** G22 (severity rubric calibration against empirical distributions) — explicitly blocked on ≥1 release of CSV data; this v0.6.5 produces the FIRST data, calibration happens in v0.7.x retrospective.
- **NG-4:** G24 (audit relative-path inconsistency) — consistent with all 6 existing audit helpers; not strictly a bug.
- **NG-5:** Promoting any pre-impl-review stage from advisory → blocking — explicit policy: defer until ≥1 release of CSV baseline data accumulates. v0.6.5 produces baseline; v0.7.x retrospective evaluates.
- **NG-6:** P5.B2 / B3 / B5 — same as v4/v5 verdict.
- **NG-7:** P5.C frontier (HiveMind, GEPA, Skilldex, Attacker, etc.) — all deferred.
- **NG-8:** Schema migration — none needed; nothing changes in any schema.
- **NG-9:** Bumping to 0.7.0 — bundle is patch-tier per strict semver (no API/schema breaks; advisory mechanisms remain advisory; cleanup + small additive docs).

## Section 6: Design Considerations

UI: command-line only. The v0.6.5 changes surface in three places:
1. `bash quantum-loop.sh --audit` summary line format (G26) + missing-csv drill text (G18).
2. `agents/conflict-auditor.md` Health Report sort order (G25) — agent prose only; no JSON change.
3. `README.md` new section (G20) and new `references/risk-mitigation-language.md` file (G28) — both markdown.

No new env vars. Existing `QL_SKIP_PRE_IMPL_REVIEW` + `QL_AUDIT_TEST_MODE` unchanged.

## Section 7: Technical Considerations

- **Shell compatibility:** bash 4.3+ (consistent with v0.6.x).
- **External tools:** `git`, `grep`, `find`, `wc`, `ls`, `awk`, `jq`, `sha256sum`/`shasum` — all already required. `flock` (optional from v0.6.4) — no new requirement.
- **`set -euo pipefail` safety:** any new helpers wrap subprocess calls per project convention.
- **Performance:** all changes are documentation or in-place edits to existing helpers — no new performance budget needed.
- **Security:** no new attack surface. The new `references/risk-mitigation-language.md` is documentation only.
- **Cross-platform:** all new tests must exercise both POSIX and Git Bash / MSYS paths per CLAUDE.md Platform Notes.

## Section 8: Success Metrics

- All 7 user stories pass with verifiable evidence.
- `bash tests/*.sh` exits 0 with ≥2,220 total assertions (was 2,172 in v0.6.4; +50-70 from new/extended tests).
- `quantum-loop.sh --audit` after Wave 1 reports the new split summary AND populated-CSV state in `pre-impl-review-coverage`.
- `metrics/pre-impl-review-findings.csv` has ≥3 rows after v0.6.5 ships (first end-to-end populated-CSV milestone).
- Plugin version bumped to 0.6.5 across all 3 manifests.
- `IDEA_REPORT_v6` lists what's open after v0.6.5 (clear roadmap to v0.6.6).
- 0-retry execution record maintained.
- `ql-deep-review` invoked at MEDIUM tier after Wave 1 (closes v0.6.4 audit gap).

## Section 9: Open Questions

None. Bundle composition + framing fully resolved by `IDEA_REPORT_v5` priority list.

## Lifecycle Checklist

- **First-run behavior** — operators see the new audit summary format. The `pre-impl-review-coverage` row may show `partial-coverage` or `full-coverage` if v0.6.5 planning hooks fired (this cycle does that explicitly).
- **Returning-user behavior** — operators on v0.6.4 → v0.6.5 see the format change in `--audit` summary; CHANGELOG entry calls it out. No data migration required.
- **Update behavior** — pure cleanup + additive docs. No schema changes. No migration scripts.
- **Error recovery** — `do_audit` still returns 1 on FAIL. WARN doesn't trip exit. No new error paths.
- **No-data / empty state** — pre-impl-review-coverage WARN states get clearer drill copy (G18). Empty `metrics/` still produces a clean WARN, not a crash.
- **Uninstall / disable** — All v0.6.5 changes are inert if the operator doesn't run `--audit` or the planning skills. No new opt-out mechanisms required.

## Next Steps

Trigger v0.6.4 prd-review advisory hook against this PRD (second CSV row). Then run `/quantum-loop:ql-plan` (or author directly) to generate `quantum.json` with the wave DAG, contracts, and `fileConflicts`. Then trigger v0.6.4 plan-review hook (third CSV row, closes the populated-CSV milestone). Then `/quantum-loop:ql-execute` to ship.
