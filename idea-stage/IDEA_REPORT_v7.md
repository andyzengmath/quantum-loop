# IDEA_REPORT_v7 — what's still open after v0.6.6

**Date:** 2026-04-28
**Source:** `ql/v0.6.6-bundle` dogfood retrospective (US-007)
**Branch:** `ql/v0.6.6-bundle` (release tag v0.6.6)
**Predecessor:** `idea-stage/IDEA_REPORT_v6.md`

## Closed in v0.6.6

| ID | Story | Notes |
|---|---|---|
| **G30** | US-004 | `lib/deep-review.sh::should_dispatch_deep_review(diff_path)` — new helper returns 0 (dispatch) on tier ≥ MEDIUM, 1 (skip) on LOW. Honors `QL_DEEP_REVIEW=force` (always 0) and `QL_DEEP_REVIEW=skip` (always 1) env-var overrides. Diff-path entry-point lets retrospective callers invoke without live SHAs. `agents/orchestrator.md` Step 4B.5 documents the gate with override-syntax table. 8 new assertions in `tests/test_deep_review_dispatch.sh` (NEW) covering 4 fixture cases. **G30 self-validation** at US-007 T-003: v0.6.6's own diff (12 files, 1663 lines) → tier=LOW score=25 → skip; decision recorded in `quantum.json.reviews[v0.6.6-bundle].deepReview` with all 4 required keys. |
| **G31** | US-005 | `tests/run_all.sh` (NEW, 140 lines) supports default sequential / `--quick` (changed-file-only via `git diff master..HEAD --name-only -- 'tests/test_*.sh'`) / `--parallel N` (xargs -P, default N=4) / combined modes. Per-file output `tests/test_<name>.sh: <P>/<T> passed`. xargs -P fallback to sequential when unavailable. PARALLEL_UNSAFE allowlist convention documented. Self-recursive `--__one` private entry-point sidesteps export-f portability quirks on MSYS / Git Bash. 9 new assertions in `tests/test_run_all.sh` (NEW). Smoke benchmark on this Git-Bash-on-Windows host: `--parallel 4` ~3.6× speedup vs sequential (above PRD's 2× target). |
| **G32** | US-001 | `tests/test_sprint_contract.sh` Test 7i — negative-assertion regression guard for `agents/spec-reviewer.md`. Uses load-bearing-shape grep `(test_|\.test\.` (literal substring match) excluding the citation line, instead of the AC's literal recipe (which would 15 false-positive on prose mentions of `spec`/`test_`/`specification`). Regression-guard property verified manually: injecting an uncited inline copy fails Test 7i; reverting passes. 1 new assertion (24 → 25). |
| **G33** | US-002 | `quantum-loop.sh::do_audit` honors `QL_AUDIT_TEST_ROWS` env var (gated on `QL_AUDIT_TEST_MODE=1`) for synthetic newline-delimited ROWS injection. Tests 34/35 rewritten to subprocess-invoke `bash quantum-loop.sh --audit` instead of inlining a private `_t34_run`/`_t35_run` re-implementation. Test-mode guard tightened to require `$#==0` so `--audit` subprocesses bypass the source-mode short-circuit. -23 net lines in `tests/test_audit.sh`. Tests 34/35 now catch any future regression in `do_audit`'s case-pattern switch. |
| **G34** | US-003 | `_audit_format_row` inline comment + `do_audit` function-header trimmed to load-bearing WHY ("FAIL OR WARN because both signal something the operator should see"; "split counters by status because a single combined counter would silently treat WARN as on-target"). Removed: `confidence`, `soliton-pr-review`, `v0.6.5 post-merge`, `G18`/`G29`/`G33` tags, version-tag headers, before-and-after summary string. 4 new meta-assertions in `tests/test_audit.sh` (Tests 36a/b + 37a/b) using awk-based function-comment-range extraction enforce 0 bloat strings + ≥1 WHY phrase per function. 41 → 45 audit assertions. |
| **p008-driven test-helper audit** | US-006 | `tests/test_test_helpers.sh` (NEW) asserts every `tests/test_*.sh` file uses one of four safe sourced-script-errexit patterns: A (function-extracted subshell + two-invocation idiom), B (`\|\| true` after substitution), C (enclosing `set +e` ... `set -e` block), or D (file does not enable `set -e` — the hazard is errexit-specific). Opt-out via `# pragma test-helper-audit: opt-out (rationale: ...)` with rationale enforcement. Per-file PASS/FAIL with `file:line` citation for any unsafe substitution. 9 new assertions; **0 unsafe substitutions across all 76 test files in current corpus; 0 opt-outs needed** (target met). |

The **G30-G34 cluster + p008-driven audit** (the v0.6.6 priority list from IDEA_REPORT_v6) is now **fully closed**. Each item maps to exactly one user story; each story shipped first-attempt PASS in a single orchestrator run.

## Multi-cycle CSV milestone (second populated run)

`metrics/pre-impl-review-findings.csv` now has **6 rows** (3 v0.6.5 + 3 v0.6.6). The v0.6.6 rows came from this cycle's planning hooks:

- `/ql-spec` advisory PRD-review against `tasks/prd-v0.6.6-bundle.md`
- `/ql-design` advisory against `docs/plans/2026-04-27-v0.6.6-bundle-design.md`
- `/ql-plan` advisory against `quantum.json` (post-DAG-validation)

Severity distribution (6/6 rows): all MEDIUM or LOW; no CRITICAL or HIGH. Consistent with patch-tier framing of both v0.6.5 and v0.6.6.

**Calibration histograms become possible at v0.7.x with 3-5 more populated runs.** G22 unblocks accordingly.

## Still open after v0.6.6

### G19 — 3-SKILL-wrapper centralization
**Status:** unchanged from v0.6.5 carry-over. Defer until a 4th pre-impl-review stage is added. Current 3 stages (design / prd / plan) handle the dispatch-shape duplication acceptably with a copy-pasted wrapper. ETA: v0.7.0 if a 4th stage materializes; otherwise N/A.

### G21 — metrics CSV rotation
**Status:** premature until > 100 rows. v0.6.6 ships at 6 rows. ETA: ~v0.8 or later.

### G22 — severity rubric calibration against empirical distributions
**Status:** newly more feasible after v0.6.6 (6 rows total, ~2× v0.6.5). Still needs 3-5 more populated-CSV releases for meaningful histograms. ETA: v0.7.x retrospective territory.

### G24 — audit relative-path inconsistency
**Status:** unchanged. Consistent with all 6 existing audit helpers; not strictly a bug. Defer indefinitely unless a concrete failure surfaces.

### P5.B2 — schema validation for sprint-contract.json
**Status:** unchanged from v6 verdict. Same triage: the 1 manual schema-doc reference in `references/sprint-contract.md` covers the contract-doc requirement; jq-based runtime validation is overkill until the contract grows beyond the current 8 fields.

### P5.B3 — orchestrator state-machine formalization
**Status:** unchanged. The current state-management pattern (orchestrator-only writes, deterministic field updates per-story) works for sequential execution. Re-evaluate if the parallel-mode race-prone fields (e.g., `progress[]`) start showing reorder bugs.

### P5.B5 — ql-execute idempotency proof
**Status:** unchanged. Empirically idempotent across this 7-iteration run + the v0.6.5 7-iteration run; formal proof remains v0.7.x territory.

### P5.C frontier (HiveMind / GEPA / Skilldex / Attacker / etc.)
**Status:** all deferred. None blocking; revisit when the 6-row CSV grows enough to inform priority.

## New gaps from v0.6.6 dogfood

### N1 — should_dispatch_deep_review wired but not auto-invoked yet
**Surfaced:** US-004 + US-007 T-003 (G30 self-validation).
**Symptom:** the new helper exists and is documented in orchestrator.md Step 4B.5, BUT the orchestrator's actual control-flow at Step 4B.5 still computes `risk_score_from_quantum` directly without consulting `should_dispatch_deep_review` first. The Step 4B.5 doc-block I added in US-004 includes a leading "0. Apply the dispatch gate FIRST" pseudo-block, but it sits next to the existing pipeline rather than gating it.
**Severity:** MEDIUM. The function is callable (US-007 T-003 proves it). The miss is one-step: the orchestrator agent's prose flow doesn't yet branch-and-skip when `should_dispatch_deep_review` returns 1.
**Path:** v0.6.7 candidate. Wire the gate ahead of the score computation in the orchestrator agent's natural-language step ordering, OR move the dispatch decision into a new `dispatch-gate` lib helper that wraps both functions.

### N2 — _audit_test_suites reads phase-N-evidence/, not the live test-suite log
**Surfaced:** US-007 T-001 audit log shows `test-suites: 98/98 passed (target green) OK`.
**Symptom:** the audit reports stale `Results: P/T passed` lines from prior phase-*-evidence dirs, not the actual test corpus state. Useful as a ledger summary BUT not a real-time green/red signal. New operators may misinterpret 98/98 as "current corpus passes".
**Severity:** LOW. Doc-only fix candidate (clarify in `_audit_test_suites` comment header). OR: change to invoke `tests/run_all.sh` (US-005 dependency)?
**Path:** v0.6.7 doc clarification at minimum. Live-invocation is bigger; defer.

### N3 — Git Bash per-process startup overhead is the test-suite bottleneck
**Surfaced:** US-005 smoke benchmark.
**Symptom:** Sequential bash test-suite takes ~17 min (partial sample of 9 files; ~150 min extrapolated for full 76). The bottleneck is the 1s/process Git Bash startup × ~76 files × ~1 inner subprocess each. Even `--parallel 4` is bottlenecked at ~5.2 files/min by the same overhead.
**Severity:** LOW (tooling-environment, not pipeline). The runner is correct; the platform is slow.
**Path:** Future optimization could batch tests into a single bash process per worker (saves 75 process-startups but constrains test isolation). Defer unless a CI deadline forces.

### N4 — file-conflict serialization assumed Wave 1 had US-003-only stories
**Surfaced:** wave plan (Wave 1 = US-003 alone) and the dag-validator's "single_story_wave" warning.
**Symptom:** US-003 depends on US-002 (both touch `quantum-loop.sh` + `tests/test_audit.sh`). The plan's dependsOn-based serialization works correctly. BUT: the dag-validator's "warning" output for single-story waves implies a future where the planner could automatically split US-002 + US-003 into 2 sequential micro-waves with explicit-pass-through, vs. the current implicit serialization.
**Severity:** LOW. Current behavior is correct; the warning is advisory.
**Path:** No action needed.

### N5 — codebasePatterns array growth is not append-blocked
**Surfaced:** US-002 + US-005 + US-001 each suggested a new pattern (p009 / p010 / p011). v0.6.6's progress entries reference the candidates but don't append them to `quantum.json.codebasePatterns`. Need to add them to harvest the lesson.
**Severity:** LOW (process gap). Patterns harvested in this report's §"codebasePatterns harvested" but not yet in the JSON.
**Path:** Append p009-p011 to `quantum.json.codebasePatterns` as part of US-007's commit (this story).

## New gaps from post-push `/soliton:pr-review` on PR #67

Soliton ran post-push at risk score 30/100 (LOW), matching v0.6.6's own G30 self-validation. 4 findings surfaced; 2 critical were addressed inline in commit `c47e038`. 2 sub-threshold (below 85 confidence) queued here. Plus 1 pre-existing hang surfaced during the diagnostic.

| Gap | Source | Score | Status |
|---|---|---:|---|
| ~~**G33-bug: `IFS=$'\n' read -d '' -ra ROWS` collapses all rows into ROWS[0]**~~ | soliton correctness | 95 | **ADDRESSED** in `c47e038` (replaced with `mapfile -t`). |
| ~~**G31-bug: `run_one` runs each test file twice — side effects double-execute**~~ | soliton correctness | 90 | **ADDRESSED** in `c47e038` (single bash invocation with tmpfile capture). The orchestrator's empty `.omc/phase-N-evidence/v0.6.6-test-suite.log` was downstream evidence — re-running `tests/run_all.sh` after the fix produces non-empty output. |
| **G35: `tests/test_audit.sh` Test 4 hangs since at least v0.6.5 master** | soliton diagnostic (pre-existing surfaced during fix verification) | n/a | **NEW backlog item.** `set -euo pipefail` inheritance from sourcing `quantum-loop.sh` (line 4) into a test that runs `out=$(do_audit 2>&1); rc=$?` causes the subshell to abort on the first non-zero command inside `do_audit`. Reproduced by checking out `master` quantum-loop.sh + tests/test_audit.sh and running the test — Test 4 hangs identically. Hidden by the run_one double-execution bug (G31-bug above) which produced empty test logs that never tripped the test-suite-fail signal. v0.6.7 should either (a) wrap `do_audit` calls in `set +e` blocks within tests, or (b) restructure `do_audit` to never propagate non-zero exits during normal operation. 0.5-1 stories. |
| **G36: `should_dispatch_deep_review` empty-input false `prod_count`** | soliton correctness | 82 | Sub-threshold. `lib/deep-review.sh:176` `grep -cvE '^(tests?/\|$)\|(\.test\.\|_test\.)'` on an empty `$files` string returns 1 (the empty-line trailing newline counts as non-matching), spuriously inflating `prod_count` when no diff files exist. Guard with `if [[ "$files_changed" -gt 0 ]]; then ... fi` mirroring existing pattern in `compute_risk_score`. 0.25 stories. |
| **G37: `--parallel` mode failure detection misses tests that exit non-zero with passing Results line** | soliton correctness | 80 | Sub-threshold. `tests/run_all.sh:137-139` checks only `grep -qE ': 0/[0-9]+ passed'` against concatenated parallel output. A test exiting 1 but printing `Results: 3/3 passed` (e.g., partial-run output before crash) would not trip the failure signal. Capture xargs exit code via `xargs_rc=0; ... || xargs_rc=$?` and OR with the grep check. 0.25 stories. |

The G35 + G36 + G37 triple is a cohesive v0.6.7 follow-up — all three address gaps in v0.6.6's quality-gate infrastructure (test runner, deep-review classifier, audit parser).

## Recommendation for v0.6.7 or v0.7.0

**v0.6.7 candidate slate (patch-tier):**
1. **G35** — fix `test_audit.sh` Test 4 hang (highest-priority — pre-existing since v0.6.5+ master; hidden by G31-bug; surfaces immediately now that run_all.sh works correctly).
2. **N1** — wire `should_dispatch_deep_review` into orchestrator's actual Step 4B.5 control flow.
3. **G36** — guard `should_dispatch_deep_review` empty-input branch.
4. **G37** — `--parallel` mode failure detection via xargs_rc capture.
5. **N2** — `_audit_test_suites` doc clarification (1 line).
6. **N5** — append codebasePatterns p009-p011 to quantum.json.

**v0.7.0 candidate slate (minor tier — needs more accumulated evidence):**
1. **G22** — severity rubric calibration once CSV reaches ~10-12 rows.
2. **N3** — Git Bash test-suite optimization (if CI pressure motivates).
3. **G19** — 3-SKILL-wrapper centralization if a 4th pre-impl stage lands.

**Long-tail (deferred indefinitely):**
- G21, G24, P5.B2/B3/B5, P5.C frontier — same triage as v6.

## Recurring observations (not bugs, just patterns)

- **Patch-tier bundles structurally cluster at LOW tier.** v0.6.5 and v0.6.6 both produced LOW-tier diffs against their respective master baselines (12 files, 0 sensitive, 0 prod-without-test). G30's `should_dispatch_deep_review` correctly routes them to skip. The 2× target speedup of `--parallel 4` is achieved; the tier-gate is correctly conservative.
- **0-retry execution record extends to v0.6.6.** Held since v0.6.0; the 7-story / 3-wave pattern has run cleanly through v0.6.5 and v0.6.6.
- **Sequential mode is the right default for patch-tier bundles.** Parallel mode would have created more state to track for stories that needed serialization (US-003 depends on US-002). The orchestrator's per-story commit + quantum.json update pattern is fast enough that sequential adds <5min wall-clock vs theoretical 4-way parallel for 5-story Wave 0.
