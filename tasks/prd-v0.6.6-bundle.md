# PRD: v0.6.6 — v0.6.5 follow-through (G30, G31, G32, G33, G34, p008)

**Status:** Approved
**Date:** 2026-04-27
**Design doc:** `docs/plans/2026-04-27-v0.6.6-bundle-design.md`
**Source:** `idea-stage/IDEA_REPORT_v6.md` v0.6.6 priority list
**Branch (planned):** `ql/v0.6.6-bundle`
**Target version:** 0.6.6 (patch bump from 0.6.5)
**Total effort estimate:** ~3-4 days (single-developer; ~2-2.5 days with parallel waves)

## Section 1: Introduction / Overview

This release closes the 5 remaining G-track items from v0.6.5's post-merge review passes (`/code-review:code-review` G32/G33/G34) plus the v0.6.5 design-doc-vs-shipped audit gaps (G30 ql-deep-review tier-decision, G31 test-suite wall-clock), plus the v0.6.5 codebasePattern-harvest audit (p008 sourced-script errexit). All cleanup or small additive doc/test artifacts.

The 7-story bundle stays **patch-tier** (no breaking changes; all changes additive or in-place cleanup; no schema deltas). Per `IDEA_REPORT_v6` process commitment: this v0.6.6 cycle is the **second multi-cycle populated-CSV run** (after v0.6.5's first), bringing the ledger from 3 → 6 rows. Calibration histograms become possible at v0.7.x with 3-5 more populated runs.

## Section 2: Goals

- Close G30, G31, G32, G33, G34 from `IDEA_REPORT_v6`.
- Add p008-driven test-helper audit (`tests/test_test_helpers.sh`).
- Maintain 0-retry execution record (held since v0.6.0).
- Bump plugin version 0.6.5 → 0.6.6 across all 3 manifests.
- Backward compatibility: existing v0.6.x quantum.json files load and run unchanged.
- **Process milestone:** populate `metrics/pre-impl-review-findings.csv` with ≥3 new rows from this cycle's planning hooks (total ≥6 across releases).
- **G30 self-validation:** apply v0.6.6's own `should_dispatch_deep_review` rule against v0.6.6's own diff in US-007 retrospective.

## Section 3: User Stories

### US-001: G32 — G27 negative assertion

**Description:** As a maintainer of the SPRINT_CONTRACT_TEST_REGEX single-source-of-truth invariant, I want `tests/test_sprint_contract.sh` to assert that `agents/spec-reviewer.md` has no uncited inline regex copies (mirroring Tests 7e–7f for the other consumer files), so a future commit cannot silently re-add an inline pattern alongside the citation.

**Acceptance Criteria:**
- [ ] `tests/test_sprint_contract.sh` adds Test 7i: `grep -E '(test_|\.test\.|spec|pytest)' agents/spec-reviewer.md | grep -v 'SPRINT_CONTRACT_TEST_REGEX' | grep -v -F 'see lib/handoff.sh' | wc -l` returns 0.
- [ ] Existing 18 sprint-contract assertions remain green; 19/19 PASS post-fix.
- [ ] Test 7i FAILS if the citation line is removed (regression-guard property).
- [ ] Typecheck/lint passes.

### US-002: G33 — refactor Tests 34/35 to invoke real `do_audit`

**Description:** As a test-suite maintainer, I want Tests 34 and 35 in `tests/test_audit.sh` to exercise the real `do_audit` function instead of duplicating its `case "$row"` switch logic verbatim, so a future regression in `do_audit`'s case patterns is caught by these tests.

**Acceptance Criteria:**
- [ ] `quantum-loop.sh::do_audit` honors `QL_AUDIT_TEST_ROWS` env var: when set AND `QL_AUDIT_TEST_MODE=1`, replaces the helper-driven ROWS array with a synthetic newline-delimited string parsed via `IFS=$'\n' read -ra ROWS <<< "$QL_AUDIT_TEST_ROWS"`.
- [ ] Tests 34 and 35 rewritten to call `bash quantum-loop.sh --audit` with `QL_AUDIT_TEST_MODE=1` + `QL_AUDIT_TEST_ROWS=<synthetic>` instead of the private `_t34_run`/`_t35_run` helpers.
- [ ] The two-invocation `|| true` + `; echo $?` Platform-Notes idiom continues to wrap the subprocess captures.
- [ ] `_t34_run`/`_t35_run` helper functions REMOVED from `tests/test_audit.sh`.
- [ ] All 41 existing audit assertions remain green post-rewrite (behavior identical).
- [ ] `QL_AUDIT_TEST_ROWS` is documented in `quantum-loop.sh` near `QL_AUDIT_TEST_MODE` as test-only.
- [ ] `QL_AUDIT_TEST_ROWS` is ignored when `QL_AUDIT_TEST_MODE!=1` (production safety).
- [ ] Typecheck/lint passes.

### US-003: G34 — trim PR-metadata bloat from comments

**Description:** As a `quantum-loop.sh` maintainer, I want the `_audit_format_row` and `do_audit` function-header comments to keep their load-bearing WHY but drop the soliton-confidence / G-number / version-tag metadata (which lives in `git log` + `CHANGELOG.md` + retrospective docs anyway), so the code follows CLAUDE.md's "Default to writing no comments" guidance.

**Acceptance Criteria:**
- [ ] `_audit_format_row` function-header comment trimmed to the load-bearing WHY (drill prints on FAIL OR WARN because both signal something the operator should see). No `confidence: 97`, no `soliton-pr-review`, no `v0.6.5 post-merge`, no `G18`/`G29` tags.
- [ ] `do_audit` function-header comment trimmed similarly. Keep the WHY (counters split by status; WARN does not trip exit). No `v0.6.5 / G26 / US-001` tags, no before-and-after summary string quoting.
- [ ] New meta-assertion in `tests/test_audit.sh`: `grep -E '(confidence|G[0-9]+|v0\.[0-9]+\.[0-9]+|soliton)' quantum-loop.sh` against the lines containing `_audit_format_row` or `do_audit` function-header comments returns 0 matches (exact line-range scoped via awk or sed range).
- [ ] All existing audit assertions remain green post-trim (`bash tests/test_audit.sh` exits 0 with assertion count ≥ pre-trim baseline).
- [ ] Trimmed comment headers retain at least one explanatory phrase (`grep -E '(because|why|so that|the WHY)' quantum-loop.sh` against the function-header line ranges returns ≥1 match per function — `_audit_format_row` and `do_audit`).
- [ ] Typecheck/lint passes.

### US-004: G30 — codify `ql-deep-review` tier-decision rule

**Description:** As an orchestrator-author, I want the `ql-deep-review` dispatch decision to be a documented machine-readable rule (auto-invoke when tier>=MEDIUM; honor `QL_DEEP_REVIEW=force` and `=skip` overrides), so the decision is no longer ad-hoc per release.

**Acceptance Criteria:**
- [ ] `lib/deep-review.sh` adds `should_dispatch_deep_review(diff_path)` helper returning 0 (dispatch) or 1 (skip) based on `compute_tier` against the diff.
- [ ] `should_dispatch_deep_review` honors `QL_DEEP_REVIEW=force` (always returns 0) and `QL_DEEP_REVIEW=skip` (always returns 1) env-var overrides.
- [ ] `agents/orchestrator.md` Step 4B.5 (or a new Step 4B.5) documents the gate: dispatch on tier>=MEDIUM by default, with override-syntax docs.
- [ ] New `tests/test_deep_review_dispatch.sh` covers 4 fixture cases:
  - LOW-tier diff + no env var → exit 1 (skip)
  - MEDIUM-tier diff + no env var → exit 0 (dispatch)
  - LOW-tier diff + `QL_DEEP_REVIEW=force` → exit 0 (force-dispatch)
  - MEDIUM-tier diff + `QL_DEEP_REVIEW=skip` → exit 1 (force-skip)
- [ ] `tests/test_deep_review_dispatch.sh` has ≥8 assertions (4 fixture cases × 2 each: exit code + observable side-effect).
- [ ] Existing `lib/deep-review.sh` test coverage remains green.
- [ ] Existing `agents/orchestrator.md` test coverage remains green.
- [ ] Typecheck/lint passes.

### US-005: G31 — `tests/run_all.sh` runner

**Description:** As an operator (or retrospective T-002 step), I want a `tests/run_all.sh` script with `--quick` (changed-file-only via `git diff master..HEAD -- 'tests/test_*.sh'`) and `--parallel N` (xargs -P) modes, so retrospective test-suite captures don't bottleneck the bundle wall-clock.

**Acceptance Criteria:**
- [ ] New `tests/run_all.sh` with three modes:
  - Default (no flags): run all `tests/test_*.sh` sequentially. Output: aggregated PASS/FAIL counts + per-file summary.
  - `--quick`: run only test files changed vs `master` (via `git diff master..HEAD --name-only -- 'tests/test_*.sh'`).
  - `--parallel N`: run all files in parallel via `xargs -P N` (N defaults to 4 if not provided).
  - `--quick --parallel N`: combined.
- [ ] Exit code: 0 iff all PASS; 1 iff any FAIL.
- [ ] `--parallel` default N=4 documented in usage.
- [ ] Per-test-file output captured and aggregated; output format: one line per file `tests/test_<name>.sh: <PASS>/<TOTAL> passed`.
- [ ] PARALLEL_UNSAFE allowlist documented in `tests/run_all.sh` header (currently empty; document the convention for future additions).
- [ ] New `tests/test_run_all.sh` (or extension to existing meta-test) verifies all 4 modes via fixture (synthesize a 3-test-file fixture: 1 PASS, 1 FAIL, 1 PASS; assert sequential = 2/3 + exit 1; `--quick` runs only changed; `--parallel 2` aggregates correctly).
- [ ] Typecheck/lint passes.

### US-006: p008 — test-helper audit

**Description:** As a test-suite maintainer, I want `tests/test_test_helpers.sh` that asserts every `tests/test_*.sh` file uses one of three documented safe sourced-script-errexit patterns (function-extracted subshell + two-invocation idiom, OR `|| true` after substitution, OR explicit `set +e` block scope), so the p008 pattern from v0.6.5 is enforceable across the suite.

**Acceptance Criteria:**
- [ ] New `tests/test_test_helpers.sh` greps each `tests/test_*.sh` for `out=\$(` patterns (or equivalent capturing constructs) and asserts each is followed (within 5 lines) by one of:
  - **Pattern A**: companion two-invocation pattern with `; echo $?` (Platform Notes idiom).
  - **Pattern B**: `|| true` immediately on the same line.
  - **Pattern C**: enclosing `set +e` ... `set -e` block.
- [ ] Each test file may opt out via top-of-file marker comment `# pragma test-helper-audit: opt-out (rationale: ...)`. Audit greps for this and skips that file.
- [ ] Output: per-file PASS/FAIL summary with file:line citation for any unsafe substitution.
- [ ] Test passes against the current `tests/test_*.sh` corpus (verifying baseline cleanliness).
- [ ] ≥6 assertions in `tests/test_test_helpers.sh`.
- [ ] False-positive rate documented: any test file requiring opt-out at the time this lands gets the marker comment + rationale (target: 0 opt-outs needed).
- [ ] Typecheck/lint passes.

### US-007: Retrospective + IDEA_REPORT_v7 + version bump 0.6.5 → 0.6.6

**Description:** As a project maintainer, I want a structured retrospective after Wave 1, an IDEA_REPORT_v7, plugin version bumped 0.6.5 → 0.6.6, AND verification that v0.6.6's own `should_dispatch_deep_review` rule was applied to v0.6.6's own diff (G30 self-validation).

**Acceptance Criteria:**
- [ ] `idea-stage/PIPELINE_REPORT_v7.md` documents v0.6.6 dogfood: total wall-clock, wave timings, cross-story-contract events, test-suite delta vs v0.6.5.
- [ ] PIPELINE_REPORT_v7 explicitly notes `metrics/pre-impl-review-findings.csv` has ≥6 rows (3 from v0.6.5 + ≥3 from v0.6.6 planning hooks).
- [ ] `idea-stage/IDEA_REPORT_v7.md` lists what's still open after v0.6.6 (G19, G21, G22 — newly feasible, G24, P5.B2/B3/B5, P5.C* + any new gaps).
- [ ] `quantum-loop.sh --audit` re-run after Wave 1; output captured to `.omc/phase-N-evidence/v0.6.6-audit.log`.
- [ ] Audit log shows the split summary `<ok>/<total> OK, <warn> WARN, <fail> FAIL` AND visible WARN drill (`└─ ...` line under any WARN row) AND `pre-impl-review-coverage: 3/3 stages OK` — both v0.6.5 (3 rows from 2026-04-27) and v0.6.6 (≥3 rows from this same date) entries fall inside the 7d rolling window at v0.6.6 ship time, so OK is the deterministically expected outcome.
- [ ] G30 self-validation: invoke `bash lib/deep-review.sh should_dispatch_deep_review <diff>` against v0.6.6's own master..HEAD diff. Capture exit code + reasoning. If LOW-tier (likely — patch-tier cleanup), skip dispatch + record decision in `quantum.json.reviews[v0.6.6-bundle].deepReview` with `tier: LOW, decision: skip, rationale: ..., automated: true`.
- [ ] CHANGELOG.md updated with v0.6.6 entry covering 6 user-facing stories.
- [ ] `.claude-plugin/plugin.json` version bumped 0.6.5 → 0.6.6.
- [ ] `.claude-plugin/marketplace.json` BOTH `metadata.version` AND `plugins[0].version` bumped 0.6.5 → 0.6.6.
- [ ] `.cursor-plugin/plugin.json` bumped 0.6.5 → 0.6.6.
- [ ] Typecheck/lint passes.

## Section 4: Functional Requirements

- **FR-1:** `tests/test_sprint_contract.sh` Test 7i asserts no uncited inline regex copies in `agents/spec-reviewer.md`.
- **FR-2:** `quantum-loop.sh::do_audit` accepts `QL_AUDIT_TEST_ROWS` env var (gated by `QL_AUDIT_TEST_MODE=1`) for synthetic ROWS injection.
- **FR-3:** `tests/test_audit.sh` Tests 34 and 35 invoke real `do_audit` (not private re-implementations); `_t34_run`/`_t35_run` removed.
- **FR-4:** `_audit_format_row` and `do_audit` function-header comments contain no PR/version/confidence/G-number metadata strings.
- **FR-5:** `lib/deep-review.sh::should_dispatch_deep_review(diff_path)` returns 0 on tier>=MEDIUM; honors `QL_DEEP_REVIEW=force/skip` overrides.
- **FR-6:** `agents/orchestrator.md` documents the deep-review tier gate at Step 4B.5 (or equivalent) with override syntax.
- **FR-7:** `tests/run_all.sh` supports `--quick`, `--parallel N` (default N=4), and combined modes.
- **FR-8:** `tests/test_test_helpers.sh` audits every `tests/test_*.sh` for one of three safe sourced-script-errexit patterns; supports opt-out via `# pragma test-helper-audit: opt-out (rationale: ...)`.
- **FR-9:** `metrics/pre-impl-review-findings.csv` has ≥6 rows after v0.6.6 ships.
- **FR-10:** Plugin version bumped 0.6.5 → 0.6.6 across `.claude-plugin/plugin.json`, `.claude-plugin/marketplace.json` (both fields), `.cursor-plugin/plugin.json`.
- **FR-11:** v0.6.6's own `should_dispatch_deep_review` rule applied to v0.6.6's own diff in US-007 retrospective; decision recorded in `quantum.json.reviews[v0.6.6-bundle].deepReview`.

## Section 5: Non-Goals (Out of Scope)

- **NG-1:** G19 (3-SKILL-wrapper centralization) — only revisit if a 4th pre-impl-review stage is added.
- **NG-2:** G21 (metrics CSV rotation) — premature until >100 rows.
- **NG-3:** G22 (severity rubric calibration against empirical distributions) — newly feasible after v0.6.6's 6 rows but still needs 3-5 more populated-CSV releases for meaningful histograms. v0.7.x.
- **NG-4:** G24 (audit relative-path inconsistency) — consistent with all 6 existing audit helpers; not strictly a bug.
- **NG-5:** Promoting any pre-impl-review stage from advisory → blocking — explicit policy: defer until ≥3-5 releases of CSV baseline data accumulate.
- **NG-6:** P5.B2 / B3 / B5 — same as v4/v5/v6 verdict.
- **NG-7:** P5.C frontier (HiveMind, GEPA, Skilldex, Attacker, etc.) — all deferred.
- **NG-8:** Direction-of-diff hallucination calibration (the v0.6.5 reviewer #5 issue) — observation captured in v6 retrospective; address via prompt-engineering in v0.7.x if it recurs.
- **NG-9:** Schema migration — none needed; nothing changes in any schema.
- **NG-10:** Bumping to 0.7.0 — bundle is patch-tier per strict semver (no API/schema breaks; cleanup + small additive doc/test).

## Section 6: Design Considerations

UI: command-line only. v0.6.6 changes surface in three places:
1. Operators running `bash tests/run_all.sh` (G31 — new modes for fast/parallel test-suite captures).
2. Maintainers reading `quantum-loop.sh` source (G34 — comments trimmed to load-bearing WHY).
3. Orchestrator runs invoking `should_dispatch_deep_review` (G30 — auto-gated invocation; env-var overrides for force/skip).

Two new env vars (both opt-in test/override hooks): `QL_AUDIT_TEST_ROWS` (US-002) and `QL_DEEP_REVIEW` (US-004).

## Section 7: Technical Considerations

- **Shell compatibility:** bash 4.3+ (consistent with v0.6.x).
- **External tools:** `git`, `grep`, `find`, `wc`, `ls`, `awk`, `jq`, `xargs` (US-005 needs `xargs -P`). All already required.
- **`set -euo pipefail` safety:** new helpers wrap subprocess calls per project convention; `tests/run_all.sh` wraps `xargs -P` invocation per Platform Notes.
- **Performance:** `tests/run_all.sh --parallel 4` target speedup ≥2× vs sequential on 4-core hosts. `should_dispatch_deep_review` must complete in <500ms for typical diffs.
- **Security:** new env vars (`QL_AUDIT_TEST_ROWS`, `QL_DEEP_REVIEW`) gated/validated. `QL_AUDIT_TEST_ROWS` only honored when `QL_AUDIT_TEST_MODE=1`. `QL_DEEP_REVIEW` value validated against {`force`, `skip`} enum (other values ignored with stderr warning).
- **Cross-platform:** `tests/run_all.sh` uses `xargs -P`. POSIX `xargs -P` is widely supported but if Git Bash / MSYS lacks it, fall back to sequential (graceful degrade).
- **bash 4.3+ `local -n` namerefs:** US-005 may use them for ROWS aggregation; document in function comment per CLAUDE.md convention.

## Section 8: Success Metrics

- All 7 user stories pass with verifiable evidence.
- `bash tests/*.sh` exits 0 with ≥2,260 total assertions (was ~2,200 in v0.6.5; +60-80 from new/extended tests).
- `quantum-loop.sh --audit` after Wave 1 reports split summary + visible WARN drill + `pre-impl-review-coverage` populated.
- `metrics/pre-impl-review-findings.csv` has ≥6 rows after v0.6.6 ships (multi-cycle milestone).
- Plugin version bumped to 0.6.6 across all 3 manifests.
- IDEA_REPORT_v7 lists what's open after v0.6.6.
- 0-retry execution record maintained.
- G30 self-validation: v0.6.6's own diff classified by its own rule (likely LOW-tier → auto-skip) and recorded in `quantum.json.reviews`.
- `tests/run_all.sh --parallel 4` measured speedup ≥2× vs sequential (smoke benchmark in retrospective).
- 0 opt-outs needed in `tests/test_test_helpers.sh` against current corpus (target: baseline cleanliness).

## Section 9: Open Questions

None. Bundle composition + framing fully resolved by IDEA_REPORT_v6 priority list.

## Lifecycle Checklist

- **First-run behavior** — Operators see the trimmed comments (G34 cosmetic), the new test runner (G31), and the auto-gated deep-review (G30). The v0.6.6 dogfood itself runs on v0.6.5 master HEAD; G30's tier-gating applies to runs starting AFTER v0.6.6 ships.
- **Returning-user behavior** — Operators on v0.6.5 → v0.6.6 see the new env-var overrides documented in `quantum-loop.sh` + `agents/orchestrator.md`. No data migration required.
- **Update behavior** — Pure cleanup + additive tests/docs. No schema changes.
- **Error recovery** — `should_dispatch_deep_review` returns 1 (skip) on missing/malformed diff path with stderr warning, not crash. `tests/run_all.sh --parallel` falls back to sequential if `xargs -P` unavailable.
- **No-data / empty state** — `tests/run_all.sh --quick` with no changed test files exits 0 with "no test files changed since master" message. Empty CSV still produces clean WARN.
- **Uninstall / disable** — All v0.6.6 changes are inert if operator doesn't run `--audit`, `tests/run_all.sh`, or planning skills. New env vars are opt-in.

## Next Steps

Trigger v0.6.4 prd-review advisory hook against this PRD (CSV row 5, multi-cycle row 2). Then run `/quantum-loop:ql-plan` (or author directly) to generate `quantum.json`. Trigger plan-review hook (CSV row 6, multi-cycle row 3). Then `/quantum-loop:ql-execute` to ship.
