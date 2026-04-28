# PRD: v0.6.8 — v0.6.7 follow-through (N6, N7, N8, N9, N10, N11)

**Status:** Approved
**Date:** 2026-04-28
**Design doc:** `docs/plans/2026-04-28-v0.6.8-bundle-design.md`
**Source:** `idea-stage/IDEA_REPORT_v8.md` v0.6.8 priority list
**Branch (planned):** `ql/v0.6.8-bundle`
**Target version:** 0.6.8 (patch bump from 0.6.7)
**Total effort estimate:** ~1.5-2 days (single-developer; ~1-1.5 days with parallel waves)

## Section 1: Introduction / Overview

This release closes 6 v0.6.8 candidate items from `IDEA_REPORT_v8`: N6 (orchestrator stale-detection prose guard), N7 (soliton-finding-triage process doc), N8 (Test 37a awk scope narrowing), N9 (wall-clock baselines doc), N10 (compute_risk_score comment correction), N11 (orchestrator Step 4B.5 cleanup ordering). Plus 1 retrospective.

The 7-story bundle is **patch-tier** (no breaking changes; cleanup + doc-additive; no schema deltas; 2 new committed reference files). Per process commitment: this v0.6.8 cycle is the **fourth multi-cycle populated-CSV run**, bringing the ledger from 9 → 12 rows.

## Section 2: Goals

- Close N6, N7, N8, N9, N10, N11 from `IDEA_REPORT_v8`.
- Maintain 0-retry execution record (held since v0.6.0).
- Bump plugin version 0.6.7 → 0.6.8 across all 3 manifests.
- Backward compatibility: existing v0.6.x quantum.json files load unchanged.
- **Process milestone:** populate `metrics/pre-impl-review-findings.csv` with ≥3 new rows (total ≥12).
- **G30 self-validation re-run** against v0.6.8 diff.

## Section 3: User Stories

### US-001: N6 — orchestrator stale-detection prose guard

**Description:** As a quantum-loop maintainer, I want `agents/orchestrator.md` to contain a documented "Self-monitoring guard" subsection that names forbidden-idiom phrases the LLM agent should treat as drift signals, so the agent has a prose-level cue to reset to the current `in_progress` story when context-drifting.

**Acceptance Criteria:**
- [ ] `agents/orchestrator.md` adds a new `### Self-monitoring guard` subsection between Step 4 and Step 4B.
- [ ] The subsection enumerates ≥3 forbidden idioms ("while that runs", "let me proactively work on later", "let me prepare US-XXX in parallel" — when current story isn't `passed`).
- [ ] The subsection documents the self-recovery action: re-read quantum.json, identify current `in_progress` story, reset to its task list.
- [ ] **Enforcement model is presence-only**: AC validates the guard EXISTS (grep), not that the LLM honors it at runtime. Runtime enforcement is out of scope (queued as v0.6.9 N6-followup for parent-side liveness check).
- [ ] New `tests/test_orchestrator_wiring.sh` extension OR new `tests/test_orchestrator_self_monitor.sh`: grep that orchestrator.md contains both `Self-monitoring guard` header AND the forbidden-idiom regex `while that runs|let me proactively`. ≥3 new assertions.
- [ ] Negative-control assertion (regex-validity test, NOT an LLM-behavior test): the new test file constructs a string containing legitimate cross-story phrasing (e.g. `"dependsOn US-002"` and `"current story passed; picking next eligible"`) and asserts that running the forbidden-idiom regex against that string returns 0 matches. Validates the regex doesn't false-positive on legitimate prose.
- [ ] Existing orchestrator.md test coverage remains green.

### US-002: N7 — soliton-finding-triage doc

**Description:** As an operator triaging post-merge soliton sub-threshold findings (score < 85) for the next cycle's design slate, I want a committed reference documenting the "validate-before-design" workflow, so I don't ship fixes for hallucinated bugs.

**Acceptance Criteria:**
- [ ] New `references/soliton-finding-triage.md` (≥40 lines) with 3 sections: Workflow / Repro template / Examples.
- [ ] Workflow section documents the rule: write a 1-line empirical reproduction or counter-example BEFORE adding a sub-threshold finding to the next-cycle design slate.
- [ ] Examples section includes the v0.6.7 G36 case as a worked false-positive example (regex `|$` already handled empty-input; the design-time fix shipped as defense-in-depth + regression-guard test).
- [ ] Cross-link from `CLAUDE.md` (or equivalent dispatch-doc) so future operators discover it during retrospective writing.
- [ ] New test `tests/test_soliton_triage_doc.sh` (or extension to existing reference-doc audit): asserts file exists, has 3 sections, and ≥1 worked example.
- [ ] ≥3 new assertions.

### US-003: N8 — narrow Test 37a awk to function-header range

**Description:** As a `tests/test_audit.sh` maintainer, I want `extract_function_comments` to return ONLY the function-header comment range (matching G34's design intent), so a future post-merge fix that legitimately needs a soliton-style comment in a function BODY does not trip the G34 audit.

**Acceptance Criteria:**
- [ ] `tests/test_audit.sh::extract_function_comments` awk simplified: emits accumulated header buffer ONLY, then exits at the function-definition line. No `in_body` state machine.
- [ ] Tests 36a/36b (for `_audit_format_row`) remain green: header has ≥1 WHY phrase + 0 PR-metadata bloat.
- [ ] Tests 37a/37b (for `do_audit`) remain green for the same reasons, scoped to header.
- [ ] All 45 audit assertions remain green (`bash tests/test_audit.sh` exits 0).
- [ ] Inline meta-comment in `tests/test_audit.sh` notes N8 / v0.6.8 scope clarification: "Header range only — body comments are out of scope per G34's stated intent (which trims function-header PR-metadata bloat, not body comments)."
- [ ] Regression-guard demonstration **(manual verification step during US-003 implementation; not a permanent automated test — mirrors v0.6.6 US-001 T-002's framing)**: temporarily inject a body comment containing `confidence 99` into `do_audit` body → Test 37a still PASSes (was: would FAIL pre-N8). Revert injection. The orchestrator implementer performs this once during US-003 to verify the awk-narrowing intent; the synthetic injection is not committed.

### US-004: N9 — wall-clock baselines reference

**Description:** As a future PRD-author, I want a committed reference table of platform-conditional test wall-clock baselines, so test-time ACs reference these baselines instead of unmeetable absolute targets (the v0.6.7 "<60s" miss).

**Acceptance Criteria:**
- [ ] New `references/test-wallclock-baselines.md` documenting baselines for at least 4 commands: `bash tests/test_audit.sh`, `bash tests/run_all.sh`, `bash tests/run_all.sh --parallel 4`, `bash tests/test_run_all.sh`. Each row has Git Bash and Linux/CI columns.
- [ ] Reference notes that the dominant cost on Git Bash is per-process subprocess startup (~1s × N invocations).
- [ ] Reference is cross-linked from `CLAUDE.md` Platform Notes (or section that future PRD authors are expected to consult).
- [ ] New test `tests/test_wallclock_baselines_doc.sh` (or extension): asserts the reference exists + has ≥4 baseline rows + cross-link present in CLAUDE.md.
- [ ] ≥2 new assertions.
- [ ] Baseline-drift detection (running `time` against each baseline command, WARN-ing on >50% drift) is **out of scope for v0.6.8**; queued as v0.6.9 N9-followup.

### US-005: N10 — compute_risk_score comment correction

**Description:** As a `lib/deep-review.sh` maintainer, I want the comment in `should_dispatch_deep_review` that claims "Mirrors the structure used in compute_risk_score above" to be corrected, so a future maintainer following the comment is not misled.

**Acceptance Criteria:**
- [ ] The comment block above the `if (( files_changed > 0 ))` guard in `should_dispatch_deep_review` (lines ~167-172 of post-v0.6.7 state) rewritten to clarify: `compute_risk_score` does NOT have an inner files_changed-count guard; it relies on the outer `if [[ -n base && -n head ]]` SHA-presence check at line 51. The two functions handle the empty-input case via different mechanisms (outer SHA-presence vs inner files_changed-count), both correct.
- [ ] No code-line edits in `lib/deep-review.sh`; comment-only change.
- [ ] `bash tests/test_deep_review_dispatch.sh` → 14/14 PASS (no behavior change).
- [ ] The new comment contains the substring `compute_risk_score` AND `outer` AND mentions both mechanisms differ.

### US-006: N11 — orchestrator Step 4B.5 cleanup-line move

**Description:** As an operator triaging a failed deep-review pipeline (e.g., jq error in step 6), I want `.quantum-feature-diff.patch` to remain inspectable for debugging, so I move the cleanup `rm -f` line to the END of the else-branch instead of the start.

**Acceptance Criteria:**
- [ ] `agents/orchestrator.md` Step 4B.5 else-branch's `rm -f "$REPO_ROOT/.quantum-feature-diff.patch"` line moved from immediately after `else` to immediately before the closing `fi` (after the verdict-case block).
- [ ] If-branch's cleanup REMAINS at end-of-branch (already in correct position from v0.6.7's restructure — the existing line at orchestrator.md ~1382 sits between the jq-write and the `# proceed to Step 4C` comment, which IS the if-branch's last action). Only the else-branch line moves; if-branch is verified in-place via grep.
- [ ] BLOCKS_MERGE edge handled: when verdict=BLOCKS_MERGE the case statement `exit 1`s; the cleanup-at-end is intentionally NOT reached on that path. Patch file remains for forensic inspection. Documented in the orchestrator.md comment near the cleanup.
- [ ] New Test 7 in `tests/test_deep_review_dispatch.sh`: asserts `rm -f` line index appears AFTER the `case "$VERDICT"` line index in the awk-extracted Step 4B.5 region (still within `else` and `fi`).
- [ ] Existing 14 dispatch tests remain green.
- [ ] ≥1 new assertion.

### US-007: Retrospective + IDEA_REPORT_v9 + version bump 0.6.7 → 0.6.8

**Description:** As a project maintainer, I want a structured retrospective + IDEA_REPORT_v9 + plugin version bumped 0.6.7 → 0.6.8 + G30 self-validation re-run.

**Acceptance Criteria:**
- [ ] `idea-stage/PIPELINE_REPORT_v9.md` documents v0.6.8 dogfood: total wall-clock, wave timings, cross-story-contract events, test-suite delta vs v0.6.7.
- [ ] PIPELINE_REPORT_v9 explicitly notes `metrics/pre-impl-review-findings.csv` has ≥12 rows (3 v0.6.5 + 3 v0.6.6 + 3 v0.6.7 + ≥3 v0.6.8).
- [ ] `idea-stage/IDEA_REPORT_v9.md` lists what's still open after v0.6.8 (G19, G21, G22 — newly more feasible at 12 rows, G24, P5.B2/B3/B5/C* unchanged, plus N6-followup parent-side liveness check, N9-followup baseline-drift detection, plus any new gaps from v0.6.8 dogfood).
- [ ] `quantum-loop.sh --audit` re-run after Wave 2; output captured to `.omc/phase-N-evidence/v0.6.8-audit.log`.
- [ ] Audit log shows split summary AND `pre-impl-review-coverage: <N>/3 stages` row with N≥1 (per the v0.6.7-defensive-widen pattern; given typical same-day cycle, N==3).
- [ ] G30 self-validation re-run: `bash lib/deep-review.sh should_dispatch_deep_review <diff>` against v0.6.8's master..HEAD diff. Captured to `.omc/phase-N-evidence/v0.6.8-deep-review-decision.log`. Decision recorded in `quantum.json.reviews[v0.6.8-bundle].deepReview` with automated:true.
- [ ] CHANGELOG.md updated with v0.6.8 entry covering 6 user-facing stories.
- [ ] All 4 plugin manifest version fields bumped 0.6.7 → 0.6.8.

## Section 4: Functional Requirements

- **FR-1:** `agents/orchestrator.md` contains `Self-monitoring guard` subsection with ≥3 forbidden idioms + recovery action.
- **FR-2:** `references/soliton-finding-triage.md` exists with Workflow + Repro template + Examples sections.
- **FR-3:** `tests/test_audit.sh::extract_function_comments` scope is function-header-only (no body-comment processing).
- **FR-4:** `references/test-wallclock-baselines.md` exists with ≥4 platform-conditional baseline rows + CLAUDE.md cross-link.
- **FR-5:** `lib/deep-review.sh::should_dispatch_deep_review` comment correctly documents the structural difference between its empty-input handling and `compute_risk_score`'s.
- **FR-6:** `agents/orchestrator.md` Step 4B.5 cleanup-rm lives at the END of each branch (not start).
- **FR-7:** `metrics/pre-impl-review-findings.csv` has ≥12 rows after v0.6.8 ships.
- **FR-8:** Plugin version bumped 0.6.7 → 0.6.8 across `.claude-plugin/plugin.json`, `.claude-plugin/marketplace.json` (both fields), `.cursor-plugin/plugin.json`.
- **FR-9:** v0.6.8's own diff classified by its own should_dispatch_deep_review rule; decision recorded in `quantum.json.reviews[v0.6.8-bundle].deepReview` with automated:true.

## Section 5: Non-Goals (Out of Scope)

- **NG-1:** N6-followup parent-side liveness check — runtime enforcement of orchestrator stale-detection. Queued as v0.6.9.
- **NG-2:** N9-followup baseline-drift WARN-test. Queued as v0.6.9.
- **NG-3:** G19 / G21 / G22 / G24 — same as prior cycles' verdicts.
- **NG-4:** P5.B2/B3/B5 + P5.C frontier — same as prior cycles.
- **NG-5:** Schema migration. None needed.
- **NG-6:** Bumping to 0.7.0 — patch-tier per strict semver.

## Section 6: Design Considerations

UI: command-line + agent-prose-only. v0.6.8 changes surface in:
1. Orchestrator runs (after merge — N6 prose guard, N11 cleanup ordering).
2. Future PRD authors (N9 baselines reference; N7 soliton-triage workflow).
3. Maintainers reading `lib/deep-review.sh` (N10 corrected comment) or `tests/test_audit.sh` (N8 narrowed awk).

No new env vars, no new CLI flags, 2 new committed reference files.

## Section 7: Technical Considerations

- **Shell compatibility:** bash 4.3+ (consistent with v0.6.x).
- **External tools:** unchanged from v0.6.7.
- **`set -euo pipefail` safety:** N8's awk simplification preserves the existing test-script flag setup. No changes to subshell-capture patterns.
- **Quality gates:** All stories' implementations must pass typecheck/lint quality gates (orchestrator Step 5 — full `bash tests/run_all.sh` test suite). Per-story ACs do not repeat this.
- **Cross-platform:** All edits respect Git Bash / MSYS portability.

## Section 8: Success Metrics

- All 7 user stories pass with verifiable evidence.
- `bash tests/test_audit.sh` → 45/45 PASS (assertion count unchanged after N8 awk simplification).
- `bash tests/test_deep_review_dispatch.sh` → 15+/15+ PASS (existing 14 + N11 Test 7).
- New tests pass: orchestrator-self-monitor (≥3), soliton-triage-doc (≥3), wallclock-baselines-doc (≥2).
- `metrics/pre-impl-review-findings.csv` has ≥12 rows.
- Plugin version bumped to 0.6.8.
- IDEA_REPORT_v9 lists what's open + N6-followup + N9-followup queued.
- 0-retry execution record maintained.
- G30 self-validation re-run records automated:true.

## Section 9: Open Questions

None. Bundle composition fully resolved; all 3 advisory-design findings addressed inline.

## Lifecycle Checklist

- **First-run behavior** — Orchestrator runs (after v0.6.8 merge) consume the new self-monitoring prose guard. Manual operators reading `lib/deep-review.sh` see the corrected comment. Future PRD-authors see the new references.
- **Returning-user behavior** — No env-var or CLI changes. v0.6.7 → v0.6.8 transparent.
- **Update behavior** — Pure cleanup + doc-additive. No schema, no migration.
- **Error recovery** — N11's cleanup-at-end means BLOCKS_MERGE leaves the patch file for forensics; operator manually cleans up after triage. Documented.
- **No-data / empty state** — All pre-existing edge-case behaviors preserved.
- **Uninstall / disable** — All v0.6.8 changes are inert if operator doesn't run --audit, run_all.sh, or quantum-loop.sh orchestration.

## Next Steps

Trigger v0.6.4 prd-review advisory hook against this PRD (CSV row 11, multi-cycle row 2). Then author `quantum.json` directly. Trigger plan-review hook (CSV row 12, multi-cycle row 3). Spawn dag-validator. Then orchestrator.
