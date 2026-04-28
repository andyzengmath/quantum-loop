# PRD: v0.6.7 — v0.6.6 follow-through (G35, G36, G37, N1, N2, N5)

**Status:** Approved
**Date:** 2026-04-28
**Design doc:** `docs/plans/2026-04-28-v0.6.7-bundle-design.md`
**Source:** `idea-stage/IDEA_REPORT_v7.md` v0.6.7 priority list
**Branch (planned):** `ql/v0.6.7-bundle`
**Target version:** 0.6.7 (patch bump from 0.6.6)
**Total effort estimate:** ~2 days (single-developer; ~1-1.5 days with parallel waves)

## Section 1: Introduction / Overview

This release closes the 4 remaining items from v0.6.6's post-merge review passes (`/soliton:pr-review` G36 score 82, G37 score 80; pre-existing G35 hang surfaced during diagnostic; v0.6.6-dogfood-gap N1 documented-but-not-wired) plus 1 doc clarification (N2: `_audit_test_suites` ledger-vs-live signal) plus 1 process-additive (N5: persist v0.6.6-harvested codebasePatterns p009/p010/p011 into v0.6.7 quantum.json).

The 7-story bundle stays **patch-tier** (no breaking changes; all changes additive or in-place cleanup; no schema deltas; 0 new files). Per `IDEA_REPORT_v7` process commitment: this v0.6.7 cycle is the **third multi-cycle populated-CSV run** (after v0.6.5's first and v0.6.6's second), bringing the ledger from 6 → 9 rows.

## Section 2: Goals

- Close G35, G36, G37, N1, N2, N5 from `IDEA_REPORT_v7`.
- Maintain 0-retry execution record (held since v0.6.0).
- Bump plugin version 0.6.6 → 0.6.7 across all 3 manifests.
- Backward compatibility: existing v0.6.x quantum.json files load and run unchanged.
- **Process milestone:** populate `metrics/pre-impl-review-findings.csv` with ≥3 new rows from this cycle's planning hooks (total ≥9 across releases).
- **G30 self-validation re-run:** apply v0.6.6's `should_dispatch_deep_review` rule (now correctly gating the live pipeline via N1) against v0.6.7's own diff in US-007 retrospective.
- **Persistent patterns canon:** v0.6.7's IDEA_REPORT_v8 cross-links to the committed authority at `idea-stage/PIPELINE_REPORT_v7.md` § "codebasePatterns harvested" so future cycles' quantum.json authors have a single durable pointer for p009/p010/p011 re-seeding.

## Section 3: User Stories

### US-001: G35 — fix `tests/test_audit.sh` Test 4 hang

**Description:** As a test-suite maintainer, I want `tests/test_audit.sh` Test 4 to complete without hanging under the inherited `set -euo pipefail` from sourcing `quantum-loop.sh`, so the full test suite (`tests/run_all.sh`) no longer hangs since v0.6.6's run_one fix exposes the previously-swallowed Test 4 abort.

**Acceptance Criteria:**
- [ ] `tests/test_audit.sh` Test 4 (`do_audit stub happy path`) wraps the captured `do_audit` invocation in an explicit `set +e ... set -e` block so inherited errexit does NOT propagate into the subshell capture.
- [ ] `bash tests/test_audit.sh` completes in <60s wall-clock and exits 0 (was: hang at >30s with no progress past Test 4).
- [ ] All 45 existing audit assertions remain green; assertion count unchanged.
- [ ] Test 4 PASSes (do_audit's exit code == 0, output contains `=== Quantum-loop audit ===` and `Summary:` substrings — verifying do_audit's behavior, not just the new wrapper).
- [ ] `bash tests/run_all.sh` (sequential mode) completes the full suite without timeout.
- [ ] `bash tests/run_all.sh --parallel 4` completes the full suite without timeout.

### US-002: G36 — guard `should_dispatch_deep_review` empty-input prod_count

**Description:** As an orchestrator-author, I want `lib/deep-review.sh::should_dispatch_deep_review` to correctly handle 0-files diffs (empty `diff --git` patch or no-op patch), so an empty-input case no longer spuriously inflates `prod_count` and routes a no-change diff into a higher-than-LOW tier.

**Acceptance Criteria:**
- [ ] `lib/deep-review.sh::should_dispatch_deep_review` adds a `files_changed > 0` guard around the `prod_count = $(printf '%s\n' "$files" | grep -cvE ...)` block.
- [ ] When invoked against a patch file containing 0 `diff --git` headers, `prod_count == 0`, `score == 0`, `tier == LOW`, return value == 1 (skip).
- [ ] The fix mirrors the existing pattern in `compute_risk_score` line 78 (`if [[ -n "$base_sha" && -n "$head_sha" ]]; then ... fi`).
- [ ] `tests/test_deep_review_dispatch.sh` adds a 0-files-diff fixture: synthesize an empty patch file → assert `should_dispatch_deep_review` returns 1 AND stderr log shows `files=0 sensitive=0`.
- [ ] Existing 8 fixture cases (LOW-tier, MEDIUM-tier, force-LOW, skip-MEDIUM) remain green.
- [ ] `tests/test_deep_review_dispatch.sh` assertion count grows by ≥1.

### US-003: G37 — `tests/run_all.sh --parallel` failure detection via xargs_rc

**Description:** As an operator running `tests/run_all.sh --parallel N`, I want a test that exits non-zero with a passing `Results: <P>/<T> passed` line (e.g., partial-run output before crash) to be detected as a failure, so a green run_all status correctly reflects underlying test exit codes.

**Acceptance Criteria:**
- [ ] `tests/run_all.sh` `--parallel` branch (around line 141) captures `xargs`'s exit code into a local variable `xargs_rc` using the `out=$(... ) || xargs_rc=$?` pattern (per CLAUDE.md Platform Notes).
- [ ] The OVERALL_RC computation ORs `(( xargs_rc != 0 ))` with the existing `grep -qE ': 0/[0-9]+ passed'` check.
- [ ] When any parallel test exits non-zero, `tests/run_all.sh --parallel N` exits 1 (regardless of whether the test's output line shows `: 0/N passed` or `: P/N passed` for P>0).
- [ ] Sequential mode (no `--parallel`) exit-code semantics remain unchanged (sequential branch is not touched).
- [ ] `tests/test_run_all.sh` adds a fixture: synthetic test file that prints `=== Results: 1/1 passed, 0 failed ===` then `exit 1` → `--parallel 2` mode catches the non-zero exit.
- [ ] Existing 9 assertions remain green.
- [ ] `tests/test_run_all.sh` assertion count grows by ≥1.

### US-004: N1 — wire `should_dispatch_deep_review` into orchestrator Step 4B.5 control flow

**Description:** As an orchestrator-author, I want `agents/orchestrator.md` Step 4B.5 to actually short-circuit the deep-review pipeline when `should_dispatch_deep_review` returns skip, so the documented gate (added in v0.6.6 / G30) is load-bearing rather than informational.

**Acceptance Criteria:**
- [ ] `agents/orchestrator.md` Step 4B.5 pseudocode block restructured with explicit `if/else` containment: the dispatch pipeline (steps 1-7) lives INSIDE the `else` branch.
- [ ] The skip branch (when `should_dispatch_deep_review` returns 1) records the `deepReview: {decision: skip, automated: true}` entry to quantum.json AND removes the temporary diff patch file AND falls through to Step 4C (no execution of steps 1-7).
- [ ] The else branch (dispatch path) preserves all 7 existing steps, verifiable via grep on the post-edit `agents/orchestrator.md` Step 4B.5 block: each of `score-from-quantum`, `dispatch-set`, `prepare_review_context` (or `context` subcmd invocation), `aggregate`, `synthesize_verdict`, `.reviews[$fid].deepReview` jq-write, and the `case "$VERDICT"` block covering BLOCKS_MERGE / REQUEST_CHANGES / APPROVE_WITH_COMMENTS / APPROVE — each appearing AFTER the `else` line and BEFORE the closing `fi` line.
- [ ] The cleanup `rm -f "$REPO_ROOT/.quantum-feature-diff.patch"` is symmetric across branches (called once per branch, not duplicated outside the if/else).
- [ ] `tests/test_deep_review_dispatch.sh` adds a structural assertion: grep that orchestrator.md Step 4B.5 contains both `if ! ` (for the gate invocation) AND `else` (for the dispatch containment), AND that `score-from-quantum` lives between the `else` and the closing `fi`.
- [ ] Existing orchestrator.md test coverage remains green.

### US-005: N2 — `_audit_test_suites` doc clarification

**Description:** As an operator running `quantum-loop.sh --audit`, I want the `_audit_test_suites` row's behavior to be documented as a phase-evidence ledger query (not a live test corpus run), so I don't misinterpret a green ledger row as proof that tests pass right now.

**Acceptance Criteria:**
- [ ] `quantum-loop.sh::_audit_test_suites` function-header comment block (lines ~290-296) appends a 2-3 line clarification: the helper reads the most-recent `.omc/phase-*-evidence/` LEDGER, not the live test corpus, and points operators at `bash tests/run_all.sh` for live state.
- [ ] The new comment lines contain the substring `tests/run_all.sh`, scoped to the `_audit_test_suites` function-header comment range — verifiable via the same awk-based `extract_function_comments` pattern that `tests/test_audit.sh` Tests 36-37 use, asserting ≥1 match for `tests/run_all.sh` within that range.
- [ ] Existing comment WHY (FR-10 fail-when-no-evidence rationale) is preserved unchanged.
- [ ] No code-line edits; comment-only change.
- [ ] All 45 audit assertions remain green (`bash tests/test_audit.sh` exits 0).

### US-006: N5 — persist v0.6.6-harvested codebasePatterns p009/p010/p011

**Description:** As a quantum-loop maintainer, I want the 3 codebasePatterns harvested during v0.6.6's user stories (p009 test-mode source guards; p010 self-recursive --__one xargs dispatch; p011 AC grep shape filter) to be appended to `quantum.json.codebasePatterns`, transcribed verbatim from the committed canonical record at `idea-stage/PIPELINE_REPORT_v7.md` § "codebasePatterns harvested", so future iterations of orchestrator runs honor them.

**Acceptance Criteria:**
- [ ] Initial v0.6.7 quantum.json (authored at cycle generation time) includes the 8 existing patterns (p001-p008) verbatim from v0.6.6 ship state. (Setup invariant — verified transitively via the `jq '.codebasePatterns | length'` AC below; the orchestrator implementer running US-006 does NOT re-check this.)
- [ ] US-006 task appends p009/p010/p011 to `.codebasePatterns` via jq, with the exact id/pattern/description/discoveredIn/applicableWhen JSON shape specified in the design doc § US-006 (which transcribes from `idea-stage/PIPELINE_REPORT_v7.md` § "codebasePatterns harvested").
- [ ] `jq '.codebasePatterns | length' quantum.json` returns 11.
- [ ] `jq '.codebasePatterns | map(.id) | sort' quantum.json` returns `["p001","p002","p003","p004","p005","p006","p007","p008","p009","p010","p011"]`.
- [ ] `jq -r '.codebasePatterns[] | select(.id=="p009") | .pattern' quantum.json` returns `Test-mode source guards must require zero positional args`.
- [ ] `jq -r '.codebasePatterns[] | select(.id=="p010") | .pattern' quantum.json` returns `Self-recursive --__one entry-point pattern for parallel xargs dispatch`.
- [ ] `jq -r '.codebasePatterns[] | select(.id=="p011") | .pattern' quantum.json` returns `AC literal grep recipes need shape filters for prose-rich source files`.
- [ ] Each appended pattern's `description` field is non-empty and matches PIPELINE_REPORT_v7's verbatim row text.
- [ ] Each appended pattern's `discoveredIn` field equals `"v0.6.6"`.
- [ ] Each appended pattern's `applicableWhen` field is non-empty.

### US-007: Retrospective + IDEA_REPORT_v8 + version bump 0.6.6 → 0.6.7

**Description:** As a project maintainer, I want a structured retrospective after Wave 1, an IDEA_REPORT_v8, plugin version bumped 0.6.6 → 0.6.7, AND verification that v0.6.6's `should_dispatch_deep_review` rule was correctly applied (now via the freshly-wired N1 gate) to v0.6.7's own diff.

**Acceptance Criteria:**
- [ ] `idea-stage/PIPELINE_REPORT_v8.md` documents v0.6.7 dogfood: total wall-clock, wave timings, cross-story-contract events, test-suite delta vs v0.6.6.
- [ ] PIPELINE_REPORT_v8 explicitly notes `metrics/pre-impl-review-findings.csv` has ≥9 rows (3 from v0.6.5 + 3 from v0.6.6 + ≥3 from v0.6.7 planning hooks).
- [ ] `idea-stage/IDEA_REPORT_v8.md` lists what's still open after v0.6.7 (G19, G21, G22 — newly more feasible at 9 rows, G24, P5.B2/B3/B5/C* unchanged + any new gaps from v0.6.7 dogfood).
- [ ] `idea-stage/IDEA_REPORT_v8.md` § "Persistent canon" cross-links to `idea-stage/PIPELINE_REPORT_v7.md` § "codebasePatterns harvested" as the committed authority for p009/p010/p011 — no JSON re-mirror needed since PIPELINE_REPORT_v7 already holds the verbatim record.
- [ ] `quantum-loop.sh --audit` re-run after Wave 1; output captured to `.omc/phase-N-evidence/v0.6.7-audit.log`.
- [ ] Audit log shows the split summary `<ok>/<total> OK, <warn> WARN, <fail> FAIL` AND a `pre-impl-review-coverage: <N>/3 stages` row with N≥1 — at v0.6.7 ship time, v0.6.7's just-fired rows are within the 7d window, so N≥1 is guaranteed; status is OK iff N==3, otherwise WARN (per FR-10 in v0.5.1, WARN does not fail the audit, so both states pass).
- [ ] G30 self-validation re-run: invoke `bash lib/deep-review.sh should_dispatch_deep_review <diff>` against v0.6.7's own master..HEAD diff. Capture exit code + reasoning. If LOW-tier (likely — patch-tier cleanup), skip dispatch + record decision in `quantum.json.reviews[v0.6.7-bundle].deepReview` with `tier: LOW, decision: skip, rationale: ..., automated: true`.
- [ ] Self-validation evidence captured to `.omc/phase-N-evidence/v0.6.7-deep-review-decision.log`.
- [ ] CHANGELOG.md updated with v0.6.7 entry covering 6 user-facing stories.
- [ ] `.claude-plugin/plugin.json` version bumped 0.6.6 → 0.6.7.
- [ ] `.claude-plugin/marketplace.json` BOTH `metadata.version` AND `plugins[0].version` bumped 0.6.6 → 0.6.7.
- [ ] `.cursor-plugin/plugin.json` bumped 0.6.6 → 0.6.7.

## Section 4: Functional Requirements

- **FR-1:** `tests/test_audit.sh` Test 4 wraps the `out=$(do_audit 2>&1); rc=$?` capture in an explicit `set +e ... set -e` block.
- **FR-2:** `lib/deep-review.sh::should_dispatch_deep_review` guards `prod_count` computation behind `if (( files_changed > 0 ))` to prevent empty-input inflation.
- **FR-3:** `tests/run_all.sh --parallel` mode captures xargs exit code via `|| xargs_rc=$?` and ORs into OVERALL_RC.
- **FR-4:** `agents/orchestrator.md` Step 4B.5 pseudocode uses explicit `if !` ... `else` ... `fi` containment so the live deep-review pipeline runs only on the dispatch path.
- **FR-5:** `quantum-loop.sh::_audit_test_suites` comment header includes a clarification that the helper reads the phase-evidence ledger, not the live test corpus.
- **FR-6:** `quantum.json.codebasePatterns` array contains 11 patterns total (p001-p011) after US-006 lands.
- **FR-7:** `metrics/pre-impl-review-findings.csv` has ≥9 rows after v0.6.7 ships.
- **FR-8:** Plugin version bumped 0.6.6 → 0.6.7 across `.claude-plugin/plugin.json`, `.claude-plugin/marketplace.json` (both fields), `.cursor-plugin/plugin.json`.
- **FR-9:** v0.6.7's own `should_dispatch_deep_review` rule applied to v0.6.7's own diff in US-007 retrospective; decision recorded in `quantum.json.reviews[v0.6.7-bundle].deepReview` with `automated:true`.
- **FR-10:** `idea-stage/IDEA_REPORT_v8.md` includes a § "Persistent canon" section that cross-links to `idea-stage/PIPELINE_REPORT_v7.md` § "codebasePatterns harvested" (the existing committed authority for p009/p010/p011 from v0.6.6 dogfood).

## Section 5: Non-Goals (Out of Scope)

- **NG-1:** G19 (3-SKILL-wrapper centralization) — only revisit if a 4th pre-impl-review stage is added.
- **NG-2:** G21 (metrics CSV rotation) — premature until >100 rows. v0.6.7 ships at 9 rows.
- **NG-3:** G22 (severity rubric calibration against empirical distributions) — newly more feasible at 9 rows but still needs 1-3 more populated-CSV releases for stable histograms. v0.7.x.
- **NG-4:** G24 (audit relative-path inconsistency) — consistent with all 6 existing audit helpers; not strictly a bug.
- **NG-5:** Promoting any pre-impl-review stage from advisory → blocking — explicit policy: defer until ≥3-5 releases of CSV baseline data accumulate.
- **NG-6:** N3 (Git Bash test-suite per-process startup overhead) — tooling-environment limitation; defer unless CI deadline forces.
- **NG-7:** N4 (single-story wave warning) — current behavior is correct; the dag-validator warning is advisory.
- **NG-8:** P5.B2 / B3 / B5 — same as v4/v5/v6/v7 verdict.
- **NG-9:** P5.C frontier (HiveMind, GEPA, Skilldex, Attacker, etc.) — all deferred.
- **NG-10:** Restructuring `do_audit` to never propagate non-zero exits (option (b) from IDEA_REPORT_v7 §G35) — invasive; the chosen mitigation (US-001's `set +e` wrapper) is less invasive and preserves the 41 existing audit assertions.
- **NG-11:** Schema migration — none needed; nothing changes in any schema.
- **NG-12:** Bumping to 0.7.0 — bundle is patch-tier per strict semver (no API/schema breaks; cleanup + bug fixes + small additive doc).

## Section 6: Design Considerations

UI: command-line only. v0.6.7 changes surface in five places:
1. Operators running `bash tests/test_audit.sh` (G35 — no longer hangs).
2. Operators running `bash tests/run_all.sh --parallel N` (G37 — failure detection now correctly catches non-zero-exit-with-passing-output tests).
3. Maintainers reading `quantum-loop.sh` source (N2 — clarified comment).
4. Orchestrator runs invoking `should_dispatch_deep_review` (N1 — gate now actually short-circuits the live pipeline; G36 — empty-input no longer mis-classifies).
5. Future quantum.json authors (N5 — codebasePatterns array seeded with p009/p010/p011 from v0.6.6 dogfood).

No new env vars. No new files. All env-var infrastructure (QL_AUDIT_TEST_MODE / QL_AUDIT_TEST_ROWS / QL_DEEP_REVIEW) ships unchanged from v0.6.6.

## Section 7: Technical Considerations

- **Shell compatibility:** bash 4.3+ (consistent with v0.6.x).
- **External tools:** `git`, `grep`, `find`, `wc`, `ls`, `awk`, `jq`, `xargs`. All already required by v0.6.6.
- **`set -euo pipefail` safety:** US-001's `set +e ... set -e` block is the project's documented escape-hatch for inherited-errexit hazards in subshell-capture contexts (pattern p008-adjacent). US-003's `|| xargs_rc=$?` follows the Platform Notes' two-invocation-idiom spirit (capture exit code without aborting).
- **Quality gates:** All stories' implementations must pass the project's typecheck/lint quality gates (enforced by orchestrator Step 5 — typecheck via project's chosen checker, lint via shellcheck where applicable, full `bash tests/run_all.sh` test suite). This is a global precondition for any story to ship; per-story ACs do not repeat it.
- **Performance:** US-001 fix removes a >30s hang; full test suite wall-clock returns to v0.6.5-baseline (~17min sequential / ~5min `--parallel 4`). US-002/G36 + US-004/N1 are sub-millisecond logic adjustments.
- **Security:** No new attack surface. US-001's `set +e` block scope is narrowly contained to a single subshell capture. US-003's xargs_rc capture preserves existing exit-code propagation guarantees.
- **Cross-platform:** All edits respect Git Bash / MSYS portability. US-003's `|| var=$?` works identically on GNU bash + Git Bash + MSYS. US-001's `set +e ... set -e` block is POSIX-spec'd shell behavior.
- **bash 4.3+ `local -n` namerefs:** none of v0.6.7's edits introduce new uses; existing usage in `tests/run_all.sh` (US-005 v0.6.6) preserved.

## Section 8: Success Metrics

- All 7 user stories pass with verifiable evidence.
- `bash tests/run_all.sh` (sequential) completes in <20min wall-clock and exits 0 with ≥2,266 total assertions (was ~2,260 in v0.6.6; +6-10 from extended fixtures).
- `bash tests/run_all.sh --parallel 4` completes in <8min wall-clock and exits 0.
- `bash tests/test_audit.sh` completes in <60s (was: hang at >30s).
- `quantum-loop.sh --audit` after Wave 1 reports split summary + `pre-impl-review-coverage: 3/3 stages OK`.
- `metrics/pre-impl-review-findings.csv` has ≥9 rows after v0.6.7 ships (third multi-cycle data point).
- Plugin version bumped to 0.6.7 across all 3 manifests.
- IDEA_REPORT_v8 lists what's open after v0.6.7 + persists p009/p010/p011 as canonical record.
- 0-retry execution record maintained.
- G30 self-validation re-run: v0.6.7's own diff classified by its own (now-actually-gating) rule and recorded with `automated:true` in `quantum.json.reviews`.

## Section 9: Open Questions

None. Bundle composition + framing fully resolved by IDEA_REPORT_v7 priority list and design-doc design-review hook (3 advisory findings — 0/0/1/2 — addressed inline before this PRD).

## Lifecycle Checklist

- **First-run behavior** — Operators see the test-runner no-longer-hangs (G35) and the freshly-gating Step 4B.5 (N1). The v0.6.7 dogfood itself runs on v0.6.6 master HEAD; G35's wrapper applies during this very run; N1's gate applies to runs starting AFTER v0.6.7 ships.
- **Returning-user behavior** — Operators on v0.6.6 → v0.6.7 see no behavior change in normal operation (no new env vars, no new flags). The orchestrator's Step 4B.5 gate behavior is now correct (was: would record skip decision but run pipeline anyway).
- **Update behavior** — Pure cleanup + bug fixes + additive doc. No schema changes. No data migration.
- **Error recovery** — `should_dispatch_deep_review` empty-input case (G36) now correctly returns skip without crash. `tests/run_all.sh --parallel` failure detection (G37) now correctly trips on non-zero xargs exits. `tests/test_audit.sh` Test 4 (G35) now completes without hanging.
- **No-data / empty state** — `should_dispatch_deep_review` empty patch → returns 1 (skip). `tests/run_all.sh --quick` with no changed test files → exits 0 (unchanged).
- **Uninstall / disable** — All v0.6.7 changes are inert if operator doesn't run `--audit`, `tests/run_all.sh`, or quantum-loop.sh orchestration. No new opt-in features.

## Next Steps

Trigger v0.6.4 prd-review advisory hook against this PRD (CSV row 8, multi-cycle row 2). Then author `quantum.json` directly. Trigger plan-review hook (CSV row 9, multi-cycle row 3). Spawn dag-validator. Then orchestrator.
