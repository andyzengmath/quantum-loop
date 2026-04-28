# Changelog

All notable changes to this project will be documented in this file.

Format: [Semantic Versioning](https://semver.org/). Bump per PR:
- **Patch** (0.0.x): bug fixes, doc updates
- **Minor** (0.x.0): new features, backward-compatible
- **Major** (x.0.0): breaking changes

## [0.7.1] - 2026-04-28

### Added

4 user-facing changes addressing v0.7.0's IDEA_REPORT_v11 v0.7.1 slate (N18, N19, N20, N21) + 1 retrospective. **Seventh multi-cycle populated-CSV run** — ledger 18 → 21 rows. Patch-tier; 5-story compact bundle. v0.7.1's own diff was self-validated: tier=LOW score=25 files=10 sensitive=0 → skip recorded with `automated:true`. **7 consecutive LOW-tier self-validations** (v0.6.5..v0.7.1).

- **N19 — G30 dispatch gate end-to-end MEDIUM-tier fixture** (US-001) — `tests/test_deep_review_dispatch.sh` Test 8 (4 new assertions): synthesizes patch with sensitive_hits=2 (auth/login.js + .env) → should_dispatch_deep_review returns 0 (dispatch); dispatch_set MEDIUM returns 4 canonical reviewers (oh-my-claudecode:code-reviewer, soliton:synthesizer, oh-my-claudecode:security-reviewer, oh-my-claudecode:test-engineer). Closes the v0.7.0 PIPELINE_REPORT_v11 calibration-insight gap (MEDIUM/HIGH/CRITICAL branches now exercised end-to-end). 15 → 19 dispatch tests.
- **N20 — `wrap_orchestrator_dispatch` runtime extraction** (US-002) — `lib/orchestrator-liveness.sh` adds NEW `wrap_orchestrator_dispatch [timeout_sec] [interval_sec]` function. Honors `QL_LIVENESS_ENABLE` env var (default true; false silent skip). Invokes `poll_orchestrator_commits`; on STALE emits canonical handoff message (cross-link to `references/orchestrator-takeover.md` + numbered recovery steps) and returns 1. `skills/ql-execute/SKILL.md` replaces inline `if [[ ${QL_LIVENESS_ENABLE:-true} == "true" ]]; then ...` example with single-line `wrap_orchestrator_dispatch || exit 1`. Tests 6 + 7 (6 new assertions): opt-out silent rc=0; default + stale tmp repo → handoff stdout + rc=1 + cross-link. 12 → 18 liveness tests. `tests/test_ql_execute_liveness_wrapping.sh` Test 6 grep updated to verify the function reference (replacing the v0.7.0 poll_orchestrator_commits inline grep).
- **N18 — plan-review MEDIUM second example** (US-003) — `references/finding-severity.md` plan-review MEDIUM row gains a second worked example joined by `**OR**`: `single-story-wave-bottleneck-masked` (dag-validator single-story-wave warning that's structurally correct but informational, masking a real serialization risk). Closes v0.7.0 G22 calibration insight that plan-review emitted ONLY LOW findings (9/9 across 6 cycles).
- **N21 — parse-script aggregate suppress zero-row** (US-004) — `references/severity-rubric-calibration-parse.sh` per-stage aggregate awk adds `rows++` counter and `if (rows == 0) exit` before printing `**Aggregate**:` line. v0.7.0 PR #71 soliton conf-75 sub-threshold carry-over closed.

### Test-suite delta

**+10 new assertions** across 2 extended test files + 0 new files:

- 2 extended: `test_deep_review_dispatch.sh` 15 → 19 (+4 N19 Test 8); `test_orchestrator_liveness.sh` 12 → 18 (+6 N20 Tests 6 + 7)
- 1 modified (count unchanged): `test_ql_execute_liveness_wrapping.sh` 6 → 6 (Test 6 grep target updated)

### Dogfood milestone (v0.7.1)

**4/4 user-facing stories shipped first-attempt PASS** under manual takeover (5th consecutive cycle). 0 retries. **Multi-cycle CSV milestone**: 18 → 21 rows. Aggregate across 7 cycles: 53 findings (0 critical / 3 high / 12 medium / 38 low; LOW share 71.7%). **G30 self-validation** (7th consecutive correct LOW classification): tier=LOW score=25 files=10 sensitive=0 → skip; recorded with `automated:true`. **3-layer + extraction recovery infrastructure complete**: v0.6.8 prose / v0.6.9 lib helper / v0.7.0 SKILL prose / v0.7.1 SKILL → callable function. **Bundle size pattern**: 7-7-7-7-5-6-5; patch-tier track increasingly drained. v0.8.0 minor-tier framing recommended for next substantive cycle (G22 second calibration pass + bundle-tier comparison data). Full retrospective: `idea-stage/PIPELINE_REPORT_v12.md`. v0.8.0+ backlog: `idea-stage/IDEA_REPORT_v12.md`.

## [0.7.0] - 2026-04-28

**MINOR bump rationale:** First non-patch release in 5 cycles. Patch-tier backlog drained over v0.6.5..v0.6.9 (5 consecutive LOW-tier patch releases). v0.7.0 ships substantive G22 calibration analysis + N14 SKILL-level runtime control-flow change + 3 LOW-priority cleanups. The version bump deliberately skips 0.6.10 to signal v0.6.x patch-track closure.

### Added

5 user-facing changes addressing v0.6.9's IDEA_REPORT_v10 v0.7.0 slate (G22, N14, N15, N16, N17) + 1 retrospective. **Sixth multi-cycle populated-CSV run** — ledger 15 → 18 rows. v0.7.0's own diff was self-validated: tier=LOW score=25 files=12 sensitive=0 → skip recorded with `automated:true`. **6 consecutive LOW-tier self-validations** across v0.6.5..v0.7.0 — calibration insight: G30 score formula caps blast-radius at 25 for files_changed ≥ 10 + 0 sensitive + 0 cg = 25 = LOW; conservative threshold means patch-tier and small-minor-tier bundles correctly skip the deep-review pipeline.

- **G22 — severity rubric calibration first pass** (US-001) — new `references/severity-rubric-calibration-v0.7.0.md` (~150 lines, 6 sections: Methodology / Empirical distribution / Expected distribution / Drift analysis / Rubric language updates / Future work). Companion `references/severity-rubric-calibration-parse.sh` (NEW awk parser cited by Methodology). 6-cycle aggregate: 49 findings → 0/3/13/33 (critical/high/medium/low). Drift: HIGH mild under-classification (-4 to -9pp); LOW mild over-classification (+7 to +17pp); plan-review emits ONLY LOW (9/9 = 100%). Verdict: no urgent rubric edits at this baseline; plan-review MEDIUM-example tweak queued for v0.7.1 N18. Re-snapshot at v0.7.x retrospectives via the parse-script. Cross-linked from CLAUDE.md `## Process references` (under N15's new Process-related sub-categorization). 6 assertions in `tests/test_severity_rubric_calibration.sh`.

- **N14 — `/ql-execute` SKILL-level liveness wrapping** (US-002) — `skills/ql-execute/SKILL.md` `## Orchestrator liveness gate` subsection wraps orchestrator dispatch with `poll_orchestrator_commits` (timeout 600s, interval 60s). Honors `QL_LIVENESS_ENABLE` env var (default `true`; set `false` preserves v0.6.9 dispatch semantics for backwards compat). On STALE signal (rc=1), the SKILL emits a structured handoff message (header + pointer to `references/orchestrator-takeover.md` + numbered recovery steps) and exits with rc=1 (`orchestrator-stale` signal). Closes the v0.6.7+v0.6.8+v0.6.9 manual-takeover recovery loop: v0.6.8 N6 prose advisory → v0.6.9 N6-followup lib helper → v0.7.0 N14 SKILL wrapping (3-layer recovery infrastructure complete). 6 PRESENCE-ONLY assertions in `tests/test_ql_execute_liveness_wrapping.sh` (matches v0.6.8 N6 pattern).

- **N15 — CLAUDE.md `## Process references` re-categorization** (US-003) — refactored into 3 `### ` sub-headers (Orchestrator-related / Test-related / Process-related). 4 entries placed in natural categories (orchestrator-takeover.md → Orchestrator; test-wallclock-baselines.md → Test; soliton-finding-triage.md + severity-rubric-calibration-v0.7.0.md → Process). Existing 14 cross-link assertions remain green post-refactor.

- **N16 — `poll_orchestrator_commits` interval_sec=0 guard** (US-004) — adds `if (( interval_sec <= 0 ))` fail-fast guard at top of function. Emits `[LIVENESS] ERROR: interval_sec must be > 0 (got %s)` log + returns 1, preventing the infinite-loop hazard (sleep 0 + elapsed never increases). v0.6.9 PR #70 soliton conf-82 carry-over closed. Test 5 in `tests/test_orchestrator_liveness.sh` (4 new assertions: exit 1 + ERROR log within 2s + no STALE log on guard path). 8 → 12 dispatch tests.

- **N17 — `tests/bench_wallclock_baseline_drift.sh` REPO_ROOT printf %q quoting** (US-005) — replaces `eval "(cd '$REPO_ROOT' && $cmd)"` with `safe_cmd=$(printf '(cd %q && %s)' "$REPO_ROOT" "$cmd"); time eval "$safe_cmd"`. Defensive against future relocations to single-quote-containing paths (e.g. `/home/user/andy's-repos/`). v0.6.9 PR #70 soliton conf-65 carry-over closed.

### Test-suite delta

**+16 new assertions** across 2 new test files + 1 extended:

- 2 new files: `test_severity_rubric_calibration.sh` (6), `test_ql_execute_liveness_wrapping.sh` (6)
- 1 extended: `test_orchestrator_liveness.sh` 8 → 12 (+4: Test 5 N16 guard)
- 1 implicit (cross-link assertions remain green post-refactor): 14 unchanged across 3 existing test files

### Dogfood milestone (v0.7.0)

**5/5 user-facing stories shipped first-attempt PASS** under manual takeover (4th consecutive cycle; orchestrator subagent's 3-layer recovery infrastructure now complete but applies only to runs starting AFTER v0.7.0 merges — the v0.7.0 dogfood ran on v0.6.9 master HEAD which has the lib helper but no SKILL wrapping). 0 retries. **Multi-cycle CSV milestone**: 15 → 18 rows. Aggregate across 6 cycles: 49 findings (0 critical / 3 high / 13 medium / 33 low). **G30 self-validation** (6th consecutive correct LOW classification): tier=LOW score=25 files=12 sensitive=0 → skip; recorded with `automated:true`. **G30 score-formula calibration insight**: blast-radius caps at 25 for files_changed ≥ 10; the dispatch gate's threshold (score>30) is conservative — only sensitive-path or coverage-gap diffs trigger MEDIUM+. v0.7.x candidates: N18 (plan-review MEDIUM example), N19 (G30 dispatch gate end-to-end test fixture), N20 (N14 SKILL wrapping runtime extraction). Full retrospective: `idea-stage/PIPELINE_REPORT_v11.md`. v0.7.1+ backlog: `idea-stage/IDEA_REPORT_v11.md`.

## [0.6.9] - 2026-04-28

### Added

4 user-facing changes addressing v0.6.8's IDEA_REPORT_v9 priority list (N6-followup orchestrator-liveness lib helper, N13 orchestrator-takeover SOP doc, N9-followup wall-clock baseline-drift bench, N12 helper rename) + 1 retrospective. Patch-tier; 5-story bundle (smaller than the typical 7 — clean LOW-tier slate, patch-track backlog drained). **Fifth multi-cycle populated-CSV run** — ledger 12 → 15 rows. v0.6.9's own diff was self-validated: tier=LOW score=25 files=11 sensitive=0 → skip recorded in `quantum.json.reviews[v0.6.9-bundle].deepReview` with `automated:true`. **5 consecutive LOW-tier self-validations** across v0.6.5..v0.6.9 — G30 dispatch gate routes patch-tier bundles with 100% accuracy across the established baseline.

- **N6-followup — `lib/orchestrator-liveness.sh::poll_orchestrator_commits`** (US-001) — new parent-side commit-poll helper. Defaults: timeout=600s, interval=60s, base=git rev-parse HEAD at call time. Returns 0 (live) on new-commit observation; 1 (stale) on timeout. Stderr log: `[LIVENESS] new commit XXXXXXXX observed at +Ns` (live) / `[LIVENESS] STALE: no commits in Ns (base=XXXXXXXX)` (stale). Library contract: no shell flags at source time. `agents/orchestrator.md` Step 1.0.4 prose subsection points operators at the helper for unattended `/ql-execute` mode (helper invocation is operator-side; SKILL-level wrapping queued as v0.7.0 N14). 8 assertions in `tests/test_orchestrator_liveness.sh` (function defined, stale-path within timeout-jitter ceiling, live-path with pre-staged HEAD-advance, default-arg behavior).
- **N13 — `references/orchestrator-takeover.md`** (US-002) — new manual-takeover SOP for parent agents detecting orchestrator drift mid-cycle. 4 sections: When to detect drift / What to verify / How to take over without corrupting state / Recovery from N6-followup STALE signal. Documents the verification-failure-driven amendment rule (preserve orchestrator edits unless a check proves them broken; v0.6.7 Pattern C → Pattern A worked example). Cross-linked from `CLAUDE.md` `## Process references` section (joining N7 soliton-finding-triage + N9 wallclock-baselines). 5 assertions in `tests/test_orchestrator_takeover_doc.sh`.
- **N9-followup — `tests/bench_wallclock_baseline_drift.sh`** (US-003) — new opt-in benchmark. Runs 7 documented baseline commands with `time`, parses real wall-clock seconds, compares against hardcoded BASELINES (curated subset of `references/test-wallclock-baselines.md`). Emits `WARN: <cmd> took Ns (baseline Xs, threshold Ys — drift > 50%)` if measured > 1.5× baseline. Always exits 0 (informational). File-naming uses `bench_*` prefix (NOT `test_*`) so `tests/run_all.sh`'s `tests/test_*.sh` glob deliberately skips it; operators must invoke directly: `bash tests/bench_wallclock_baseline_drift.sh`.
- **N12 — helper rename in `tests/test_audit.sh`** (US-004) — `extract_function_comments` → `extract_function_header_comments` (clarifies: returns ONLY the function-header comment block); `extract_function_full_comments` → `extract_function_all_comments` (clarifies: returns header AND body comments). Mechanical rename across 9 occurrences (2 function defs + 4 call sites + 3 doc-comment refs). Replacement order: longer name substituted first to avoid sub-string overlap. 45/45 audit assertions unchanged.

### Test-suite delta

**+13 new assertions** across 2 new test files (the bench file is opt-in and not counted toward run_all):

- 2 new files: `test_orchestrator_liveness.sh` (8), `test_orchestrator_takeover_doc.sh` (5)
- 1 new opt-in bench: `bench_wallclock_baseline_drift.sh` (informational; not run by `tests/run_all.sh` due to glob mismatch)
- 1 modified (assertion count unchanged): `test_audit.sh` 45 → 45 (mechanical rename)

### Dogfood milestone (v0.6.9)

**5/5 user-facing stories shipped first-attempt PASS** under manual takeover (3rd consecutive cycle; orchestrator-liveness helper SHIPS in this bundle and applies only to runs starting AFTER v0.6.9 merges — the v0.6.9 dogfood itself ran on v0.6.8 master HEAD which had no runtime liveness). 0 retries. **Multi-cycle CSV milestone**: 12 → 15 rows. Aggregate across 5 cycles: 41 findings (0 critical / 2 high / 11 medium / 28 low) — patch-tier baseline solidly stable; G22 first calibration pass becomes meaningful at v0.7.x. **G30 self-validation**: v0.6.9's own master..HEAD diff (11 files) classified by its own `should_dispatch_deep_review` rule as tier=LOW score=25 → skip; decision recorded with `automated:true`. **Bundle size shrinking**: v0.6.5/6/7/8 all had 7 stories; v0.6.9 had 5 — the natural endpoint of a patch-tier track. v0.7.0 minor-tier is the right next move. v0.7.0 candidates: G22 calibration first pass, N14 SKILL-level wrapping of the liveness helper, N15 CLAUDE.md Process references re-categorization. Full retrospective: `idea-stage/PIPELINE_REPORT_v10.md`. v0.7.0 backlog: `idea-stage/IDEA_REPORT_v10.md`.

## [0.6.8] - 2026-04-28

### Added

6 user-facing changes addressing v0.6.7's IDEA_REPORT_v8 priority list (N6 orchestrator stale-detection prose guard, N7 soliton-finding-triage doc, N8 narrow Test 37a awk to function-header range, N9 wall-clock baselines reference, N10 compute_risk_score comment correction, N11 orchestrator Step 4B.5 cleanup-line move). Patch-tier; all changes are doc/cleanup-additive (no schema deltas, no breaking changes, 2 new committed reference files). **Fourth multi-cycle populated-CSV run** — ledger 9 → 12 rows. v0.6.8's own diff was self-validated: tier=LOW score=25 files=13 sensitive=0 → skip recorded in `quantum.json.reviews[v0.6.8-bundle].deepReview` with `automated:true`.

- **N6 — orchestrator Self-monitoring guard prose** (US-001) — `agents/orchestrator.md` adds a new `### Self-monitoring guard` subsection between Step 4 and Step 4B. Documents the rule (verify in_progress story commit landed before reasoning about other stories), 3 forbidden idioms ("while that runs", "let me proactively", "let me prepare US-XXX in parallel"), self-recovery action ([ORCH] STALE-DETECT log + reset to current in_progress story's task list), and explicit prose-only enforcement model. Runtime enforcement (parent-side liveness check) queued as v0.6.9 N6-followup. New `tests/test_orchestrator_self_monitor.sh` (5 assertions: presence header, >=3 idioms, STALE-DETECT marker, negative-control regex against legitimate cross-story phrasing, positive-control regex match against true drift phrase).
- **N7 — soliton-finding-triage doc** (US-002) — new `references/soliton-finding-triage.md` (Workflow / Repro template / Examples) documenting the validate-before-design workflow for sub-threshold (<85) `/soliton:pr-review` findings between cycles. v0.6.7 G36 documented as worked HALLUCINATION example. Cross-linked from new `## Process references` section in CLAUDE.md. New `tests/test_soliton_triage_doc.sh` (5 assertions).
- **N8 — narrow `extract_function_comments` awk to header range** (US-003) — `tests/test_audit.sh::extract_function_comments` simplified to emit accumulated header buffer ONLY (no `in_body` state machine). Matches G34 stated scope ("trim PR-metadata bloat from function-HEADER comments"). DISCOVERED: Tests 36b/37b WHY-phrase checks were relying on body comments; SPLIT INTO 2 HELPERS — `extract_function_comments` (header-only) for Tests 36a/37a (bloat); new `extract_function_full_comments` (header+body) for Tests 36b/37b (WHY). 45/45 audit assertions preserved.
- **N9 — wall-clock baselines reference** (US-004) — new `references/test-wallclock-baselines.md` (6-row platform-conditional table: Git Bash vs Linux/CI for the major test commands). Cross-linked from CLAUDE.md `## Process references`. New `tests/test_wallclock_baselines_doc.sh` (4 assertions). Baseline-drift WARN-test deferred to v0.6.9 N9-followup per design-review.
- **N10 — compute_risk_score comment correction** (US-005) — `lib/deep-review.sh` comment block above v0.6.7's G36 defense-in-depth guard rewritten. Removed misleading "Mirrors the structure used in compute_risk_score above" claim (compute_risk_score uses outer SHA-presence gate; should_dispatch_deep_review uses inner files_changed-count gate — different mechanisms, same intent). Comment-only edit. 14/14 dispatch tests preserved.
- **N11 — orchestrator Step 4B.5 cleanup-line move** (US-006) — `agents/orchestrator.md` Step 4B.5 else-branch: `rm -f .quantum-feature-diff.patch` moved from start-of-branch to end-of-branch (after the verdict-case block, before closing fi). BLOCKS_MERGE intentional skip-via-exit-1 documented in comment near new location — patch file remains for forensic inspection by the operator triaging the blocked merge. New Test 7 in `tests/test_deep_review_dispatch.sh` (awk-line-numbering assertion: rm-f line index AFTER case-VERDICT line index).

### Test-suite delta

**+15 new assertions** across 3 new test files + 1 extended:

- 3 new files: `test_orchestrator_self_monitor.sh` (5), `test_soliton_triage_doc.sh` (5), `test_wallclock_baselines_doc.sh` (4)
- 1 extended: `test_deep_review_dispatch.sh` 14 → 15 (+1: Test 7 N11 cleanup ordering)
- 1 modified (assertion count unchanged): `test_audit.sh` 45 → 45 (awk simplification + helper split)

### Dogfood milestone (v0.6.8)

**6/6 user-facing stories shipped first-attempt PASS** under manual takeover (parent agent executed all stories — orchestrator subagent's N6 prose guard does not yet apply since the dogfood ran on v0.6.7 master HEAD). 0 retries. **Multi-cycle CSV milestone**: `metrics/pre-impl-review-findings.csv` now has 12 rows (3 v0.6.5 + 3 v0.6.6 + 3 v0.6.7 + 3 v0.6.8) — first calibration pass becomes meaningful at v0.7.x with bundle-tier comparison data (33 findings total: 0 critical / 2 high / 9 medium / 22 low). **G30 self-validation**: v0.6.8's own master..HEAD diff (13 files) classified by its own `should_dispatch_deep_review` rule as tier=LOW score=25 → skip; decision recorded in `quantum.json.reviews[v0.6.8-bundle].deepReview` with all 4 required keys. Audit log shows split summary AND `pre-impl-review-coverage: 3/3 stages OK` (deterministic given v0.6.7 + v0.6.8 rows fall inside the 7d rolling window). **2 mid-cycle design-improvements**: US-001 regex form needed `[A-Z0-9]+` (not `[0-9]+`) for placeholder match; US-003 needed a split into 2 helpers (`extract_function_comments` header-only vs `extract_function_full_comments` for WHY-checks) to match G34's actual semantics. v0.6.9+ candidates: N6-followup (parent-side liveness check), N13 (`references/orchestrator-takeover.md`), N9-followup (baseline-drift WARN-test), N12 (helper rename). Full retrospective: `idea-stage/PIPELINE_REPORT_v9.md`. v0.6.9+ backlog: `idea-stage/IDEA_REPORT_v9.md`.

## [0.6.7] - 2026-04-28

### Added

6 user-facing changes addressing v0.6.6's IDEA_REPORT_v7 priority list (G35, G36, G37, N1, N2, N5) plus 1 discovered v0.6.6 commit-hygiene fix (c47e038's body comment trimmed). Patch-tier; all changes are bug fixes, doc clarifications, or process-additive (no schema deltas, no breaking changes, no new files). **Third multi-cycle populated-CSV run** — the v0.6.6 ledger of 6 rows extended to 9 rows from this cycle's planning hooks. **First N1-gated dispatch wiring** — `should_dispatch_deep_review` now load-bearing in `agents/orchestrator.md` Step 4B.5 via explicit `if/else` containment (pre-N1 the gate was informational; post-N1 the live pipeline runs only on dispatch path). v0.6.7's own diff was self-validated: tier=LOW score=25 files=10 sensitive=0 → skip recorded in `quantum.json.reviews[v0.6.7-bundle].deepReview` with `automated:true`.

- **G35 — `tests/test_audit.sh` Test 4 hang fix** (US-001) — wraps the `out=$(do_audit 2>&1); rc=$?` capture in an explicit `set +e ... set -e` block so inherited `set -euo pipefail` (from sourcing quantum-loop.sh) doesn't propagate into the subshell capture. Runs do_audit against a clean tmp repo (matching Test 5's pattern) for determinism — prevents the test from depending on the developer's working repo state. **Bundled inline:** v0.6.6 c47e038 regression fix — do_audit body comment had "confidence 95" + "Soliton-pr-review caught at" tripping Test 37a (whose awk `extract_function_comments` includes body comments). Rephrased to load-bearing-WHY only ("mapfile is the right tool because it treats newlines as record separators by default"). 0 assertion delta (45 → 45); was: hang past 30s indefinitely → now: completes in ~3-4min wall-clock (Git Bash subprocess overhead is the new bottleneck, not the test logic).
- **G36 — `should_dispatch_deep_review` empty-input guard** (US-002) — adds `if (( files_changed > 0 ))` short-circuit around the `prod_count` grep computation in `lib/deep-review.sh`. Defense-in-depth: the existing regex `^(tests?/|$)|...` already excludes empty input via the `|$` alternative (verified empirically — soliton's confidence-82 finding was a false positive). The new `tests/test_deep_review_dispatch.sh` Test 5 fixture (3 assertions: empty-diff exit 1, files=0, score=0) is the durable regression-guard locking in current correct behavior. 8 → 11 dispatch tests.
- **G37 — `tests/run_all.sh --parallel` xargs_rc capture** (US-003) — replaces `|| true` with `|| xargs_rc=$?` in the `--parallel` xargs invocation; ORs `(( xargs_rc != 0 ))` into OVERALL_RC alongside the existing `: 0/N passed` grep check. Catches the missed surface: a worker that exits non-zero AFTER printing a passing "P/N passed" Results line (partial-run-then-crash; post-assertion cleanup-failure). `tests/test_run_all.sh` Test 4 (RED-tested before fix → GREEN after). 9 → 10 run_all tests.
- **N1 — wire `should_dispatch_deep_review` into orchestrator Step 4B.5 control flow** (US-004) — `agents/orchestrator.md` Step 4B.5 pseudocode block restructured with explicit `if/else` containment. Skip branch records the deepReview decision via jq AND removes the diff patch file AND falls through to Step 4C. Else branch holds the 7-step dispatch pipeline (score-from-quantum, dispatch-set, prepare-context, agent dispatch, aggregate, persist, verdict-case). Cleanup symmetric across branches. Pre-N1 the dispatch pipeline ran unconditionally; post-N1 it runs only on the dispatch path. `tests/test_deep_review_dispatch.sh` Test 6 (3 structural assertions via awk-bounded code-fence extraction) verifies gate-then-else containment + `score-from-quantum` lives between `else` and `fi`. 11 → 14 dispatch tests.
- **N2 — `_audit_test_suites` doc clarification** (US-005) — `quantum-loop.sh` function-header comment gains a 4-line clarification: helper reads the `.omc/phase-*-evidence/` LEDGER, not the live test corpus; row answers "did the most recent recorded test run pass?" not "do tests pass right now?"; for live state, run `bash tests/run_all.sh`. Existing FR-10 fail-when-no-evidence WHY preserved. Comment-only change. Closes the operator-confusion gap from IDEA_REPORT_v7 §N2.
- **N5 — `quantum.json.codebasePatterns` re-seed** (US-006) — appended p009/p010/p011 verbatim from `idea-stage/PIPELINE_REPORT_v7.md` § "codebasePatterns harvested" (the committed canonical record from v0.6.6 dogfood). Final state: 8 → 11 patterns. quantum.json is gitignored — committed as audit-trail marker only. IDEA_REPORT_v8 § "Persistent canon" cross-links to PIPELINE_REPORT_v7 as the durable single source-of-truth across cycles.

### Test-suite delta

**+7 new assertions** across 3 extended test files. Zero new test files; zero regressions:

- 3 extended: `test_audit.sh` 45 → 45 (Test 4 wrapper change; no count delta), `test_deep_review_dispatch.sh` 8 → 14 (+6: Test 5 + Test 6 add 3 each), `test_run_all.sh` 9 → 10 (+1: Test 4)

### Dogfood milestone (v0.6.7)

**7/7 user-facing stories shipped first-attempt PASS** (5 stories Wave 0 + 1 story Wave 1 [US-004 deps US-002] + 1 story Wave 2 [US-007 deps all]). 0 retries. **Multi-cycle CSV milestone**: `metrics/pre-impl-review-findings.csv` now has 9 rows (3 v0.6.5 + 3 v0.6.6 + 3 v0.6.7) — calibration histograms become meaningful at v0.7.x with 1-3 more populated releases (current 9-row baseline shows 0 critical / 2 high / 7 medium / 16 low across 25 findings; LOW dominates at 64%). **G30 self-validation**: v0.6.7's own master..HEAD diff (10 files) classified by its own `should_dispatch_deep_review` rule as tier=LOW score=25 → skip; decision recorded in `quantum.json.reviews[v0.6.7-bundle].deepReview` with all 4 required keys. Audit log shows split summary AND `pre-impl-review-coverage: <N>/3 stages` row. **3 mid-cycle discoveries**: (a) v0.6.6 c47e038 regression in do_audit body comment (fixed inline in US-001), (b) soliton G36 finding was a false positive (defensive guard + regression-guard test still shipped), (c) orchestrator subagent context-drift mid-task (parent agent took over manually for stories US-001 through US-007 — first-attempt-PASS pattern preserved despite agent failure). v0.6.8+ candidates: N6 (orchestrator stale-detection heuristic), N7 (soliton-validate-before-design process), N8 (Test 37a scope decision), N9 (wall-clock target calibration). Full retrospective: `idea-stage/PIPELINE_REPORT_v8.md`. v0.6.8+ backlog: `idea-stage/IDEA_REPORT_v8.md`.

## [0.6.6] - 2026-04-28

### Added

6 user-facing changes addressing v0.6.5's IDEA_REPORT_v6 priority list (G30, G31, G32, G33, G34, p008-driven test-helper audit). Patch-tier; all changes are cleanup or additive (no schema deltas, no breaking changes). **Second multi-cycle populated-CSV run** — the v0.6.5 ledger of 3 rows extended to 6 rows from this cycle's planning hooks. Calibration histograms become possible at v0.7.x with 3-5 more populated runs. **First release with auto-gated `ql-deep-review` dispatch** — `should_dispatch_deep_review` is the canonical decision rule going forward; v0.6.6's own diff was self-validated against the new rule (tier=LOW score=25 → skip recorded in `quantum.json.reviews`).

- **G32 — `agents/spec-reviewer.md` negative-assertion regression guard** (US-001) — `tests/test_sprint_contract.sh` Test 7i asserts 0 uncited inline regex enumerations in `agents/spec-reviewer.md` (the inline regex shape `(test_|\.test\.` excluding the citation line). Regression-guard property verified manually: injecting an inline copy fails the test; reverting passes. 1 new assertion (24 → 25).
- **G33 — `tests/test_audit.sh` Tests 34/35 invoke real `do_audit` via `QL_AUDIT_TEST_ROWS`** (US-002) — `quantum-loop.sh::do_audit` now honors `QL_AUDIT_TEST_ROWS` env var (gated on `QL_AUDIT_TEST_MODE=1`) for synthetic newline-delimited ROWS injection. Tests 34/35 rewritten to subprocess-invoke `bash quantum-loop.sh --audit` instead of inlining a private `_t34_run`/`_t35_run` re-implementation. Test-mode guard tightened to require `$#==0` so `--audit` subprocesses bypass the source-mode short-circuit. -23 net lines in `tests/test_audit.sh`. Tests 34/35 now catch any future regression in `do_audit`'s case-pattern switch.
- **G34 — trim PR-metadata bloat from `quantum-loop.sh` function comments** (US-003) — `_audit_format_row` inline comment + `do_audit` function-header trimmed to load-bearing WHY ("FAIL OR WARN because both signal something the operator should see"; "split counters by status because a single combined counter would silently treat WARN as on-target"). Removed: `confidence`, `soliton-pr-review`, `v0.6.5 post-merge`, `G18`/`G29`/`G33` tags, version-tag headers, before-and-after summary string. 4 new meta-assertions in `tests/test_audit.sh` (Tests 36a/b + 37a/b) using awk-based function-comment-range extraction enforce 0 bloat strings + ≥1 WHY phrase per function. 41 → 45 audit assertions.
- **G30 — `lib/deep-review.sh::should_dispatch_deep_review` + `agents/orchestrator.md` Step 4B.5 documentation** (US-004) — new `should_dispatch_deep_review(diff_path)` helper returns 0 (dispatch) on tier ≥ MEDIUM, 1 (skip) on LOW. Honors `QL_DEEP_REVIEW=force` (always dispatch) and `QL_DEEP_REVIEW=skip` (always skip) env-var overrides. Diff-path entry-point lets retrospective callers invoke without live SHAs (US-007 self-validation depends on this). Orchestrator Step 4B.5 documents the gate with override-syntax table. 8 new assertions in `tests/test_deep_review_dispatch.sh` (NEW) covering 4 fixture cases × 2 assertions each.
- **G31 — `tests/run_all.sh` runner with `--quick` and `--parallel N` modes** (US-005) — new test-suite runner. Default: sequential; `--quick`: filter to `git diff master..HEAD --name-only -- 'tests/test_*.sh'`; `--parallel N` (default N=4): xargs -P dispatch via private `--__one` self-recursive entry-point (sidesteps export-f portability quirks on MSYS/Git Bash); combined `--quick --parallel N`. Per-file output format `tests/test_<name>.sh: <P>/<T> passed`. Exit 0 iff all PASS; 1 iff any FAIL. xargs -P fallback to sequential when unavailable. PARALLEL_UNSAFE allowlist convention documented (currently empty). 9 new assertions in `tests/test_run_all.sh` (NEW) covering all 4 modes via 3-test fixture.
- **p008 — `tests/test_test_helpers.sh` test-helper audit** (US-006) — new audit asserts every `tests/test_*.sh` file uses one of four safe sourced-script-errexit patterns: A (function-extracted subshell + two-invocation idiom), B (`|| true` after substitution), C (enclosing `set +e` ... `set -e` block), or D (file does not enable `set -e` — the hazard is errexit-specific). Opt-out via `# pragma test-helper-audit: opt-out (rationale: ...)` with rationale enforcement. Per-file PASS/FAIL with `file:line` citation for any unsafe substitution. 9 new assertions; 0 unsafe substitutions across all 76 test files in current corpus; 0 opt-outs needed (target met).

### Test-suite delta

**+30 new assertions** across 6 test files (1 modified + 5 NEW, including the runner from G31 and the audit from p008). Zero regressions:

- 4 new files: `test_deep_review_dispatch.sh` (8), `test_run_all.sh` (9), `test_test_helpers.sh` (9), `tests/run_all.sh` (runner; not a test file)
- 2 extended: `test_sprint_contract.sh` 24 → 25 (+1: Test 7i G32 negative assertion), `test_audit.sh` 41 → 45 (+4: Tests 36a/b + 37a/b G34 meta-assertions)

### Dogfood milestone (v0.6.6)

**7/7 user-facing stories shipped first-attempt PASS across 3 waves** (Wave 0: 5 sequential — US-001/US-002/US-004/US-005/US-006; Wave 1: 1 sequential — US-003 depends on US-002; Wave 2: 1 sequential — US-007 retrospective). 0 retries, 0 cross-story contract violations, 0 merge conflicts. **Multi-cycle CSV milestone**: `metrics/pre-impl-review-findings.csv` now has 6 rows (3 v0.6.5 + 3 v0.6.6) — calibration histograms feasible at v0.7.x. **G30 self-validation**: v0.6.6's own master..HEAD diff (12 files, 1663 lines) classified by its own `should_dispatch_deep_review` rule as tier=LOW score=25 → skip; decision recorded in `quantum.json.reviews[v0.6.6-bundle].deepReview` with all 4 required keys (tier/decision/rationale/automated). Audit log shows split summary `7/7 OK, 0 WARN, 0 FAIL` AND `pre-impl-review-coverage: 3/3 stages OK` (deterministic given v0.6.5 + v0.6.6 rows fall inside the 7d rolling window). Full retrospective: `idea-stage/PIPELINE_REPORT_v7.md`. v0.6.7+ backlog: `idea-stage/IDEA_REPORT_v7.md`.

## [0.6.5] - 2026-04-27

### Added

6 user-facing changes addressing v0.6.4's IDEA_REPORT_v5 priority list (G18, G20, G25, G26, G27, G28). Patch-tier; all changes are doc / drill-text / agent-prose / new-doc additions. No breaking changes; no schema changes; no new lib code. **First release whose dogfood produced real `metrics/pre-impl-review-findings.csv` data** — 3 rows representing all 3 advisory pre-impl-review stages on this v0.6.5 planning cycle. Closes IDEA_REPORT_v5 §G18/G20/G25/G26/G27/G28; unblocks G22 (severity-rubric calibration) for v0.7.x retrospectives. The orchestrator that drove this dogfood ran on v0.6.4 master HEAD semantics — see `README.md ## Self-modifying execution` (NEW in this release) for the recurring caveat.

- **`do_audit` summary split into OK / WARN / FAIL counters** (US-001, G26) — `quantum-loop.sh::do_audit` summary line now reads `Summary: <ok>/<total> OK, <warn> WARN, <fail> FAIL.` instead of `Summary: <ok>/<total> metrics on target.` which silently counted WARN rows as on-target. The `case`-style row scan accumulates 3 counters in a single pass; exit-code semantics preserved (returns 1 iff any row contains `|FAIL|`; WARN rows do not trip exit). Fixes the misleading wording exposed by v0.6.4's introduction of the first WARN-capable metric (`pre-impl-review-coverage`). 4 new test assertions in `tests/test_audit.sh` (Tests 33-35 split-summary fixtures + Test 23 fixed-format update); existing 35 audit assertions preserved.
- **`agents/spec-reviewer.md` plan-review checklist cites SPRINT_CONTRACT_TEST_REGEX** (US-002, G27) — closes G14's 5th call site that v0.6.4 missed. The plan-review checklist's "testFirst command consistency" rule now references `lib/handoff.sh::SPRINT_CONTRACT_TEST_REGEX` as the canonical pattern source. Inline regex characters preserved with explicit "see ..." framing for self-documentation. `lib/handoff.sh` consumer comment updated 4 → 5 sites. 1 new test assertion (sub-test 7h in `tests/test_sprint_contract.sh`).
- **`agents/conflict-auditor.md` Step 4 sort enumerates all 5 severities** (US-003, G25) — sort instruction now reads "high → medium → low → warning → none" with a 1-sentence rationale (high most-impactful; warning informational-but-real-signal; none informational-only). Closes the gap opened by v0.7.0 G15 (warning) and Rule 0 (none) which had no deterministic ordering before. Pure documentation-only fix. 1 new test assertion (Test 7 in `tests/test_changelog_ownership.sh`).
- **`references/risk-mitigation-language.md`** (US-004, G28) — NEW 153-line design-craft checklist for Risk-section authors. 3 sections: (1) the rule (enumerate operations, not just techniques) + cautionary tale citing v0.6.4 commit `c89ba13` and the soliton finding at confidence 90 that surfaced the flock-bootstrap-race; (2) 4-item concurrency checklist (shared mutable state / observably-coupled operations / race window without mitigation / race window with mitigation, each with concrete interleaving examples); (3) short-form patterns for non-concurrency mitigations (validate input X / handle malformed Y / atomic update Z). Bidirectional cross-link with `references/finding-severity.md` (review-craft pair). Operationalizes codebasePattern p007 from v0.6.4. 10 new test assertions in `tests/test_risk_mitigation_language.sh` (NEW).
- **`_audit_pre_impl_review_coverage` missing-csv drill text gains operator guidance** (US-005, G18) — drill text now reads "missing-csv — no metrics/pre-impl-review-findings.csv yet (expected on first run after install — invoke /ql-brainstorm/spec/plan to populate)". Other WARN states (`no-recent-runs`, `partial-coverage`) keep their existing drill messages. Closes the v0.6.4-flagged operator-confusion gap. **One follow-up surfaced**: `_audit_format_row` only renders drills for FAIL rows, so the new guidance is captured in tests but not yet visible at runtime; queued as v0.6.6 G29. 1 new test assertion (Test 28b in `tests/test_audit.sh`).
- **`README.md ## Self-modifying execution` section** (US-006, G20) — NEW 2-paragraph section between How It Works and Quick Start. Explains: each release ships a bundle that modifies the very orchestrator/agent/skill prompts the orchestrator itself uses, so each dogfood runs on the PREVIOUS release's prompt semantics, and this release's wires only apply to runs starting AFTER the bundle merges to master. Concrete v0.6.4 example (CSV-persistence wires applied to v0.6.5+ runs, not the v0.6.4 dogfood that introduced them). Cross-link to `idea-stage/PIPELINE_REPORT_v5.md`. Closes the recurring "is the audit broken?" reaction for new operators surfaced in PIPELINE_REPORT_v5 and the v0.6.5 PRD-review missing-measurement finding. 7 new test assertions in `tests/test_readme.sh` (NEW).

### Test-suite delta

**+23 new assertions** across 5 test files. Zero regressions in pre-existing suites (apart from a single pre-existing flake in `tests/test_timeout.sh` "Agent A still running after B killed" that is byte-identical to master and unrelated to any v0.6.5 change):

- 2 new files: `test_risk_mitigation_language.sh` (10), `test_readme.sh` (7)
- 3 extended: `test_audit.sh` 35 → 39 (+4: Tests 33-35 split-summary + Test 28b drill-substring), `test_sprint_contract.sh` 23 → 24 (+1: sub-test 7h), `test_changelog_ownership.sh` 9 → 10 (+1: Test 7)

### Dogfood milestone (v0.6.5)

**6/6 user-facing stories shipped first-attempt PASS across 2 waves** (5 sequential + 1 sequential). 0 retries, 0 cross-story contract violations, 0 merge conflicts. Total wall-clock to Wave 1 completion: ~85 minutes across 2 orchestrator instances (Run 1 hit iteration cap mid-US-001 with T-001 RED tests in place; Run 2 resumed by fixing one stale grep assertion and proceeded through US-001..US-006 + US-007 retrospective without further interruption). **First populated-CSV milestone**: 3 rows in `metrics/pre-impl-review-findings.csv` (design + prd + plan from this cycle's planning) — the first release whose dogfood produced real CSV data via manual hook invocation pre-execution. Audit log shows the new G26 split summary AND `pre-impl-review-coverage: 3/3 stages OK` (was `0/3 stages WARN missing-csv` in v0.6.4 retrospectives). **1 new codebasePattern** harvested (p008: sourced-script errexit propagation in test files; mitigation via function-extraction + two-invocation idiom). The G18-G28 cluster from IDEA_REPORT_v5 is now fully closed. Full retrospective: `idea-stage/PIPELINE_REPORT_v6.md`. v0.6.6+ backlog: `idea-stage/IDEA_REPORT_v6.md`.

## [0.6.4] - 2026-04-27

### Added

6 user-facing changes maturing v0.6.3's advisory pre-impl-reviewers via instrumentation (G12-G17). All mechanisms additive/opt-in; no breaking changes — patch-tier per strict semver (no API/schema breaks; advisory mechanisms remain advisory; retrospective artifacts use the planning-time `v0.7.0` label but the release ships as `v0.6.4`). Closes IDEA_REPORT_v4 §G12/G13/G14/G15/G16/G17. **v0.6.5's first run will be the first end-to-end populated `metrics/pre-impl-review-findings.csv`** — this v0.6.4 dogfood ran on v0.6.3 master HEAD (self-modifying caveat) so the new persistence wires apply only to NEXT runs. Promotion of any pre-impl-review stage from advisory → blocking should wait until ≥1 release of CSV baseline data accumulates.

- **`lib/finding-synth.sh`** (US-001, G12) — pre-impl-review FINDING-block parser. `parse_findings(stage)` reads stdin, accumulates lines between `FINDING_START` / `FINDING_END` markers, parses key:value pairs (category/severity/file/line/evidence/suggestion), emits a structured JSON array. `summarize_findings(stage, findings_json)` returns `{stage,count,by_severity,by_category}`. `format_summary_line(summary_json)` emits the `[REVIEW] <stage>-review complete: <N> findings (<crit>/<high>/<med>/<low>)` line. CLI subcommand mode supported. Malformed blocks warn-and-drop; remaining well-formed blocks parse. Library follows lib/handoff.sh's no-flags-at-source-time + double-source-guard convention. 31 new test assertions.
- **`lib/finding-persist.sh`** + **3 SKILL wires** (US-002, G13) — persistence layer for parsed findings. `persist_review_findings(stage, source_path, summary_json, findings_json)` writes (a) `.handoffs/<stage>-review-findings.json` per-run snapshot (idempotent overwrite per stage) and (b) appends a row to the aggregate `metrics/pre-impl-review-findings.csv` ledger (header on first write, then `flock -x` guarded append; rename-replace fallback on systems without `flock`). `read_review_findings(stage)` round-trips snapshot or emits `{}` + stderr WARN on missing-file. `skills/ql-brainstorm/SKILL.md` Phase 4d, `skills/ql-spec/SKILL.md` post-prd-review, and `skills/ql-plan/SKILL.md` Step 9 each gain a wrapper that captures reviewer stderr → parses → summarizes → persists. Advisory contract preserved across all 3 stages — wrappers never abort. `.gitignore` adds `.handoffs/*-review-findings.json` (per-run snapshots are runtime state); `metrics/` remains tracked (CSV ledger is committed baseline data). 37 new test assertions.
- **`lib/handoff.sh::SPRINT_CONTRACT_TEST_REGEX` constant** (US-003, G14) — DRY refactor: the test-pattern regex `'(test_|\.test\.|spec|pytest|^bash tests/|^npm test)'` previously inlined in 4 places (orchestrator.md Step 2.5, ql-plan SKILL.md Step 8, test_sprint_contract.sh, test_sprint_contract_ql_plan.sh) is now a single readonly shell constant near the top of `lib/handoff.sh`. All 4 consumers source the lib + pass via `jq --arg pattern`. `references/sprint-contract.md` references the constant by name. Future regex changes touch one file. Pure refactor — same behavior, single source of truth. **+2 no-inline-regex assertions** in test_sprint_contract.sh; existing 16 + 13 baseline assertions preserved.
- **CHANGELOG ownership convention** (US-006, G15) — `agents/dag-validator.md` §5d documents: stories that touch `CHANGELOG.md` SHOULD defer to a single retrospective story per release. If >1 story has `CHANGELOG.md` in `tasks[].filePaths`, the conflict-auditor MUST classify the conflict as `severity: warning` (not `severity: none`) and emit a Health Report line: `WARNING: <N> stories touch CHANGELOG.md — consolidate to a single retrospective story per the v0.6.3 convention`. `agents/conflict-auditor.md` Rule 0.5 codifies the per-file override (positioned between universal-pre-empt Rule 0 and category Rule 1). 9 new assertions in `tests/test_changelog_ownership.sh`.
- **`references/finding-severity.md` rubric** (US-004, G16) — new severity-calibration document with 3 mode sections (`## design-review`, `## prd-review`, `## plan-review`), each with a 4-row Severity / Rubric / Example table calibrated to the mode's existing checklist categories. `agents/spec-reviewer.md` design-review / prd-review / plan-review sections each gain a single cross-link line above their `### Output format` subsection (kebab-case anchor IDs). Helps operators distinguish "critical for design-review" from "critical for quality-reviewer downstream" — different bars. 14 new assertions in `tests/test_finding_severity.sh`.
- **`quantum-loop.sh --audit pre-impl-review-coverage` metric** (US-005, G17) — 7th audit row tracks how many of the 3 advisory pre-impl-review stages have run in the last 7 days. 4 states: `missing-csv` WARN (no CSV), `no-recent-runs` WARN (CSV exists but all rows >7d old), `partial-coverage` WARN (1-2/3 stages recent), `full-coverage` OK (3/3 stages recent). **WARN never trips audit exit code** — the metric measures operator pipeline-engagement, not codebase health. Cross-platform date math: GNU `date -d '7 days ago'` first, BSD `date -v-7d` fallback, epoch-0 fallback otherwise (degrades to "all rows count as recent" rather than crash). `quantum-loop.ps1` documents the PS1/SH parity divergence in its `.DESCRIPTION` block — `--audit` remains bash-only per AC. 6 new assertions in `tests/test_audit.sh` (Tests 28-33); existing 30 baseline assertions preserved.

### Test-suite delta

**+97 new assertions** across 7 test files. Zero regressions:

- 4 new files: `test_finding_synth.sh` (31), `test_finding_persist.sh` (37), `test_finding_severity.sh` (14), `test_changelog_ownership.sh` (9)
- 3 extended: `test_sprint_contract.sh` 16 → 18 (+2 no-inline-regex), `test_sprint_contract_ql_plan.sh` 13 → 13 (rewired, count unchanged), `test_audit.sh` 30 → 36 (+6 G17 4-state coverage)

### Dogfood milestone (v0.6.4)

7/7 user-facing stories shipped first-attempt PASS across 4 waves (4 parallel + 1 + 1 + retrospective). 0 retries, 0 cross-story contract violations, 0 merge conflicts. The new G15 CHANGELOG-ownership convention validated itself: only US-007 touches CHANGELOG.md (count=1, no warning emitted). G14's SPRINT_CONTRACT_TEST_REGEX constant exercised by both `test_sprint_contract.sh` and `test_sprint_contract_ql_plan.sh` — both green via the shared lib source. **1 new codebasePattern** harvested (p006: single source of truth for shell constants). The execution itself ran on v0.6.3 master HEAD semantics — v0.6.4's persistence wires apply to v0.6.5+ runs only (self-modifying-orchestrator caveat). Plus 3 post-merge fixes (commit `c89ba13`, `/soliton:pr-review`-driven) addressing race conditions in `lib/finding-persist.sh`: atomic header bootstrap inside flock, fallback path guards, jq-failure abort. 44/44 tests GREEN (37 baseline + 7 new). Full retrospective: `idea-stage/PIPELINE_REPORT_v5.md`. v0.6.5+ backlog: `idea-stage/IDEA_REPORT_v5.md`.

## [0.6.3] - 2026-04-26

### Added

8 user-facing changes covering G-track cleanup (G2/G3/G8/G9/G11) + 3-stage pre-impl spec-review (P5.B4 design / PRD / plan exits, advisory-only). Patch-tier; new mechanisms are opt-out via `QL_SKIP_PRE_IMPL_REVIEW` env var. No breaking changes. Closes IDEA_REPORT_v3 §G2/G3/G8/G9/G11 + §P5.B4 (expanded to 3 stages).

- **`lib/api-rename.sh`** (US-005, G2) — symbol-migration helper. `find_rename_targets <old> <new> [--exclude <glob>]` emits `<file>:<line>:<context>` for every occurrence (code AND doc-comments); `validate_rename_complete <old> [--exclude <glob>]` exits 0 iff no occurrences remain. Addresses the v0.6.0 US-001 dogfood where the `kill_agent_process → reap_agent` rename initially missed line-4 module-header doc-comments.
- **Sprint-Contract `expectedTests` filter + `otherCommands` schema split** (US-002, G9) — orchestrator Step 2.5 jq splits `.commands` by test-pattern regex (`test_|\.test\.|spec|pytest|^bash tests/|^npm test`); test-pattern matches → `expectedTests`, rest → new sibling `otherCommands`. Backward-compat: existing readers ignore the new optional field.
- **`/ql-plan` exit writes Sprint-Contract per story** (US-004, G3) — `skills/ql-plan/SKILL.md` Step 8 iterates stories and calls `write_sprint_contract`, materializing `.handoffs/sprint-<storyId>.json` files at plan time instead of lazily during orchestrator's first run. Idempotent on re-run.
- **`write_routing_snapshot` canonicalization** (US-003, G11) — `lib/runner.sh::write_routing_snapshot` now composes with `lib/json-atomic.sh::write_quantum_json` for atomic write + JSON-validation gate, replacing its inline `jq > tmp && mv` pattern. Inherits `cleanup_stale_tmp` coordination consistently with all other quantum.json writers.
- **Critic fallback unification** (US-001, G8) — deleted dead `quantum-loop.sh::parse_critic_arg` shim; `lib/runner.sh::_availability_check` now role-aware: `critic` falls back to `none` (preserving US-002's "downgrade-not-substitute" intent), `planner`/`executor` fall back to `claude`. PowerShell already at `none` for critic. **Operator-visible behavior change:** `--critic=codex` with codex absent now produces critic disabled (was `claude` since v0.6.0).
- **`spec-reviewer` design-review mode** (US-006, P5.B4-design) — new `## Mode: design-review` section in `agents/spec-reviewer.md` + Phase 4d hook in `skills/ql-brainstorm/SKILL.md`. Reads the just-saved design doc and reports structural gaps (missing sections, TBD/FIXME markers, hedge phrases, missing non-goals). Advisory: emits to stderr; does not abort the skill. Opt out via `QL_SKIP_PRE_IMPL_REVIEW=design`.
- **`spec-reviewer` prd-review mode** (US-007, P5.B4-PRD) — new `## Mode: prd-review` section + post-exit hook in `skills/ql-spec/SKILL.md`. Reads the just-saved PRD and reports non-testable ACs, vague FRs, missing measurement methods. Advisory. Opt out via `QL_SKIP_PRE_IMPL_REVIEW=prd` (or comma-combined, e.g. `design,prd`).
- **`spec-reviewer` plan-review mode** (US-008, P5.B4-plan) — new `## Mode: plan-review` section + Step 9 hook in `skills/ql-plan/SKILL.md` (after dag-validator + US-004 sprint-contract write). Cross-references quantum.json against the PRD; reports AC coverage gaps, command-test mismatches, missing wiring tasks. Advisory. Opt out via `QL_SKIP_PRE_IMPL_REVIEW=plan`.

### Test-suite delta

**+67 new assertions** across 8 test files. Zero regressions:

- 5 new files: `test_api_rename.sh` (14), `test_spec_review_design.sh` (14), `test_spec_review_prd.sh` (13), `test_spec_review_plan.sh` (13), `test_sprint_contract_ql_plan.sh` (13)
- 3 extended: `test_cross_provider_critic_flag.sh` 13 → 20 (+7), `test_sprint_contract.sh` 11 → 16 (+5), `test_per_role_routing.sh` 26 → 29 (+3 G11 composition + validation-gate)

### Dogfood milestone (v0.6.3)

**8/8 user-facing stories shipped first-attempt PASS across 4 waves** (5 + 2 + 1 + retrospective). Total wall-clock to wave-2 completion: ~34 minutes. Zero retries, zero cross-story contract violations, zero merge conflicts. Rule 0 `fileConflicts severity=none` classification held perfectly across all 4 conflicts. Per-story two-stage review gate applied; cross-story constant scan + typecheck + full test suite + barrel/dep-manifest regen ran at each wave boundary. **5 new codebasePatterns** harvested (opt-out env-var pattern; RED-test-first when refactoring with validation gates; backward-compat schema additions default to empty array; inline-vs-subshell arg-parser globals; defensive `\r` stripping for heredoc-fed JSON on Git Bash). Full retrospective: `idea-stage/PIPELINE_REPORT_v4.md`. v0.7.0 backlog: `idea-stage/IDEA_REPORT_v4.md`.

## [0.6.2] - 2026-04-26

### Fixed

Two follow-up items from the v0.6.x cycle's `/soliton:pr-review` post-merge findings (IDEA_REPORT_v3 §G10 + score-100 .cursor-plugin gap):

- **G10 — `lib/json-atomic.sh` PRD-sha migration shim** (`compute_prd_sha_legacy` + `verify_prd_sha`). Before v0.6.1, `compute_prd_sha` did not normalize CRLF; Windows users with `autocrlf=true` who ran `/ql-plan` under v0.6.0 stored CRLF-era hashes. After upgrading to v0.6.1, the same PRD now hashes differently — every story's `prdSha` would be marked `stale` and force a full `/ql-plan` re-run. v0.6.2 adds a transparent migration: `verify_prd_sha` tries the new (LF-normalized) hash first; on mismatch, falls back to the legacy (v0.6.0) hash; if THAT matches, the orchestrator's Step 1.1 updates the stored value in-place with a single one-line "MIGRATE" log message and no re-plan. Real drift still marks the story stale as before. 3 new tests added (match / migrate / drift paths) + 1 orchestrator-wiring test.
- **`.cursor-plugin/plugin.json` version catch-up bump 0.5.1 → 0.6.2** — the v0.6.0 + v0.6.1 cycle bumped `.claude-plugin/plugin.json` and `.claude-plugin/marketplace.json` but the Cursor manifest was missed. PR #58 established the convention of moving all three plugin manifests in lockstep on every release; `/soliton:pr-review` flagged this at score 100 on PR #61 but the fix landed here. Cursor marketplace consumers will now see v0.6.2 in sync with the Claude side.

### Backward compatibility

The migration path is transparent: existing v0.6.0/v0.6.1 `quantum.json` files load and run without operator action. The first orchestrator pass after upgrade silently rewrites legacy `prdSha` values to the new format. Stories without a `prdSha` field continue to behave exactly as before (back-compat warning logged once).

## [0.6.1] - 2026-04-26

### Fixed

Three correctness bugs surfaced by `soliton:pr-review` on the v0.6.0 bundle (1 at-threshold + 2 below-threshold; all confirmed as real cross-environment hazards rather than nits):

- **`lib/runner.sh:write_routing_snapshot` orphan `.tmp` cleanup** — the inline `jq ... > "$qj.tmp" && mv ...` pattern left a 0-byte `$qj.tmp` on jq failure, inconsistent with `lib/json-atomic.sh:write_quantum_json`'s canonical `rm -f "$tmp_path"` failure-branch cleanup. Now the function captures the jq exit code and removes the tmp file before propagating, mirroring the canonical pattern.
- **`lib/json-atomic.sh:compute_prd_sha` CRLF cross-platform sha mismatch** — the `rstrip(b' \t\n\r')` only stripped trailing whitespace; on Windows with `autocrlf=true`, internal `\r\n` bytes throughout a CRLF-checked-out PRD were retained, producing a different sha256 than the same file on Linux/LF. Every story's `prdSha` would false-positive as `status: "stale"` in cross-platform setups. Now normalizes `\r\n` → `\n` before hashing.
- **`quantum-loop.sh` `--critic` / `--planner` / `--executor` space-form `$2` guards** — under `set -euo pipefail`, a trailing flag (e.g. `--critic` at end-of-args) crashed with bash's `unbound variable` error; a flag-following pattern (e.g. `--critic --parallel`) consumed the next flag as a value and emitted a generic enum error. Each space-form now guards `[[ $# -lt 2 || "${2:-}" == --* ]]` and emits a user-friendly `Error: --<flag> requires a value (...)` exit-2 message.

No new tests required — these fixes are tightening existing code paths exercised by `tests/test_per_role_routing.sh` (26), `tests/test_prd_hash_pinning.sh` (12), and `tests/test_runner_integration.sh` baseline. Test count and assertion totals unchanged from v0.6.0.

## [0.6.0] - 2026-04-26

### Added

P5.A cleanup bundle (8 items) + P5.B1 per-role provider routing + P5.Z1 dogfood retrospective. Bigger dogfood than v0.5.1's --audit (10 stories, 5 waves, multi-runner dispatch). Closes P2.9 fully via OMC v4.12 mechanism port.

- **`agents/orchestrator.md` Step 3B.3 watchdog wiring** (US-001) — 3 explicit calls (poll, circuit, reset on STORY_PASSED) with reap_agent migration for platform-aware kills via taskkill on Windows.
- **`--critic=auto|codex|gemini|claude|none`** (US-002) — operator-facing critic provider flag with availability detection and fallback (subsumed by --planner/--critic/--executor in US-009).
- **`lib/deslop.sh` regex fallback** (US-003) — when knip/ts-prune/vulture/cargo-udeps/staticcheck are absent, dispatches to `lib/dead-code.sh` with normalized `{file, line, kind, severity}` schema.
- **5 new runner manifests** (US-004) — `runners/{opencode,devin,kiro,goose,cline}.json`, all `experimental: true`. `opencode.json` includes skill_discovery_paths quirk for Superpowers v5 plugin pattern compatibility.
- **`prdSha` field per story** (US-005) — RAGShield Level-1 drift detection (arXiv:2604.00387). `lib/json-atomic.sh:compute_prd_sha` produces a stable sha256; orchestrator Step 1.1 hash-check marks mismatched stories `status: "stale"` for re-plan.
- **Sprint-Contract handoff** (US-006) — per-story `.handoffs/sprint-<storyId>.json` written by `/ql-plan` and consumed by `/ql-execute` + `/ql-review`. Mirrors Anthropic's 2026-03-24 Generator-Evaluator contract pattern. Schema documented in `references/sprint-contract.md`.
- **Inline self-review checklists** (US-007) — `[INLINE-REVIEW] typecheck OK / lint OK / all assigned tests pass / file-org follows project conventions` tokens in implementer prompt before STORY_PASSED. Subagent dispatch reserved for adversarial review (cross-story conflict, intent drift, security). 25min -> 30s on routine path per Superpowers v5.0.6.
- **`complexity` field per story + `runner_select_model`** (US-008) — formula `min(100, task_count*10 + dependsOn_depth*15 + (security_tag ? 30 : 0) + filePaths_count*2)`. Routes <=30 -> haiku, 31-60 -> sonnet, 61+ -> opus. Story-level `model:'<override>'` wins.
- **`--planner / --critic / --executor` per-role routing** (US-009) — ports OMC v4.12 mechanism. `lib/runner.sh:resolve_routing` resolves each role with availability check + fallback to claude. Snapshot persisted to `quantum.json.routing` for replay determinism. Closes P2.9 fully.
- **`idea-stage/PIPELINE_REPORT_v3.md` + `idea-stage/IDEA_REPORT_v3.md`** (US-010) — v0.6.0 dogfood findings: 9/9 user-facing stories first-attempt PASS across 5 waves (5 parallel + 2 parallel + 3 sequential). 5 NEW codebasePatterns logged. P5.B2-B5 + P5.C frontier remain open for v0.7+. Test-suite delta: ~+110 new assertions, zero regressions.

### Test-suite delta

110+ new assertions across 8 new test files. Zero regressions in pre-existing suites:
- `tests/test_watchdog_wiring.sh` (9), `tests/test_cross_provider_critic_flag.sh` (13), `tests/test_deslop_regex_fallback.sh` (7)
- `tests/test_runner_manifests.sh` extended +28 assertions, `tests/test_complexity_routing.sh` (19)
- `tests/test_prd_hash_pinning.sh` (12), `tests/test_sprint_contract.sh` (11)
- `tests/test_per_role_routing.sh` (26), `tests/test_per_role_routing_integration.sh` (6)
- `tests/test_orchestrator_wiring.sh` extended +7 assertions for inline-checklist tokens

### Dogfood milestone (v0.6.0)

The pipeline executed its largest fan-out yet: **5-story parallel wave-0** with worktree isolation, zero file-conflict resolution failures. The DAG validator's Rule 0 fileConflicts severity=none classification held perfectly across all 10 conflicts. 5 NEW codebasePatterns surfaced (cross-module rename doc-comment scanning, jq validator gaps, PATH manipulation in tests, test-guard carve-outs, set -uo pipefail return-1 termination). All retrospective material captured in `idea-stage/PIPELINE_REPORT_v3.md` + `idea-stage/IDEA_REPORT_v3.md`.

## [0.5.1] - 2026-04-24

### Added

- **`quantum-loop.sh --audit`** (#56) — read-only repo-hygiene check that prints the six IDEA_REPORT §6 measurement metrics with drill-down on failures. Exit 0 all-OK, exit 1 any off-target, exit 2 misuse. Env-tunable thresholds via `QL_AUDIT_BRANCH_MAX` / `QL_AUDIT_ORPHAN_MAX` / `QL_AUDIT_CONFLICT_MAX` / `QL_AUDIT_CPC_MAX`.
- **`docs/plans/2026-04-24-audit-flag-design.md`** + **`tasks/prd-audit-flag.md`** (#57) — pipeline artifacts from dogfooding `/ql-brainstorm` + `/ql-spec` on the audit feature. Preserves the IDEA_REPORT §6 → design → PRD → shipped-feature traceback.

### Dogfood milestone

First real pipeline self-use. The `/ql-brainstorm` → `/ql-spec` → `/ql-plan` → `/ql-execute` cycle drove a complete 4-story feature end-to-end. Findings captured in #56 PR body for follow-up skill refinements (question-count rigidity in ql-spec, placeholder-drift across stories, file-conflict serialization heuristics).

## [0.5.0] - 2026-04-24

### Added — P3 academic-wedge libraries (10 libs)

All ten wedges from `idea-stage/IDEA_REPORT.md` §P3 landed with a consistent contract pattern (no shell flags at source time, CLI block enables strict mode, env-var tunables, readonly arrays guarded against re-source).

- **`lib/constitution.sh`** (P3.11, arXiv:2602.02584) — regex-based invariants on generated code: hardcoded-secret scan, SQL-injection pattern, input-validation presence, immutable-schema rule.
- **`lib/deep-review.sh` `far_filter`** (P3.3/P3.4, arXiv:2505.17928 + arXiv:2604.03196) — KBI→FAR reviewer split with agreement boost, confidence cutoff, known-false-positive regex suppression.
- **`lib/trajectory.sh`** (P3.5, arXiv:2511.00197) — tool-shape thrashing detection: `parse_trajectory` / `classify_trajectory` (productive | searching | thrashing | stuck) / `should_early_kill`.
- **`lib/hyclone.sh`** (P3.7, arXiv:2508.01357) — Stage-1 semantic-clone fingerprint: alpha-normalize + sha256 + `find_clones` grouping.
- **`lib/conflict-grade.sh`** (P3.2, ConGra arXiv:2409.14121) — per-hunk conflict severity grading 1-5 + routing to `auto-git | diff3 | llm-merge | escalate`.
- **`lib/tracecoder.sh`** (P3.8, arXiv:2602.06875) — Observe-Analyze-Repair primitives: `observe` / `extract_error_markers` / `build_analysis_context` / `should_repair`.
- **`lib/reground.sh`** (P3.9, arXiv:2603.00492) — session-level drift mitigation: re-inject PRD + progress + iron-law reminder every N stories.
- **`lib/skeleton.sh`** (P3.1 SSAT, arXiv:2303.06689) — signature-level API surface: `extract_skeleton` / `skeleton_text` / `skeleton_diff` across TS/JS/Python/Go/Rust.
- **`lib/intent-graph.sh`** (P3.6, arXiv:2604.11209) — formal semantic-intent extraction: `(verb, object)` triples from stories + code with bidirectional drift reporting.
- **`lib/dead-code.sh`** (P3.10, arXiv:2604.07291) — regex-based unused-import + unused-private-helper detection across TS/JS/Python/Go/Rust.

### Added — Orchestrator wirings (8 integration points)

Every new lib wired into the orchestrator via grep-assertion-covered integration points. `test_orchestrator_wiring.sh` grew from 40 → 106 assertions, none can silently unwire a lib.

- **Step 1C** (reground) — periodic re-grounding, gate on `REGROUND_INTERVAL` stories.
- **Step 3A.1 sub-5** (skeleton) — pre-task API-surface preview.
- **Step 3A.3** (tracecoder) — Observe-Analyze-Repair wrapper on typecheck/lint/test gates.
- **Step 3A.5C** (dead-code) — post-generation advisory unused-import/private scan.
- **Step 3A.5D** (intent-graph) — post-generation advisory verb-object drift check.
- **Step 3A.5E** (skeleton) — post-task skeleton-diff drift report.
- **Step 3A.6** (trailers) — advisory trailers appended to commit message for durability in `git log`.
- **Step 3B.3** (trajectory) — monitor-loop tick alongside watchdog; kill path via `reap_agent`.
- **Step 3C.NEG0** (hyclone) — wave-boundary cross-story clone detection.
- **`lib/merge-strategy.sh`** (conflict-grade) — grade 5 short-circuits to escalation; grades 1-4 logged alongside category routing.

### Fixed

- **String-unsafe comment stripper** in `lib/hyclone.sh` and `lib/conflict-grade.sh` — awk passes now track string state so `//`, `/*`, `#` inside a string literal are preserved verbatim (e.g., `"http://x"`, `"/regex/"`, `"/* not a comment */"`).
- **Trajectory wiring log-path mismatch** — orchestrator now reads `.ql-wt/$sid/.ql-agent-output.txt` (spawn.sh convention) instead of the non-existent `.ql-wt/$sid/agent.log`.
- **TraceCoder wiring pseudocode** — removed undefined `GATE_CMD[$gate]` / `mark_story_failed` / `apply_focused_fix` identifiers; replaced with prose agent-action comments matching the pattern used elsewhere (watchdog mark-failed, etc.).
- **test_typecheck_gate 12 failures** — added `TYPECHECK_EXTRA_ALLOWED_PREFIXES` env var to extend the security allowlist for test fixtures without weakening the runtime gate.
- **Advisory trailers dead code** — Steps 3A.5B/C/D/E each set a trailer variable but none were appended to the 3A.6 commit. `git log` grep workflow was unusable. Now each trailer is guarded-appended to `COMMIT_MSG` before commit.

### Measurement targets (per IDEA_REPORT §6)

| Target | Goal | Achieved |
|--------|------|----------|
| CPC variant files | 0 | ✓ 0 |
| README conflict markers | 0 | ✓ 0 |
| Orphan `.claude/worktrees/agent-*` | 0 | ✓ 0 |
| Remote branch count | ≤10 | ✓ 1 (master) |
| Local branch count | ≤10 | ✓ 1 (master) |
| Archive tags preserved | — | 49 |
| Master test suites green | 100% | ✓ 54/54 (~1,400 tests) |

## [0.4.1] - 2026-04-01

### Added
- **Multi-runner support** — universal runner adapter lets quantum-loop drive Claude, Codex, Copilot, Cursor, Gemini, Aider, Cline, Amp, Devin, Kiro, Goose, and OpenCode through a shared manifest contract. Design doc: `docs/plans/2026-04-01-multi-runner-support-design.md`.
- **Runner JSON schema** (`schemas/runner.schema.json`) + validator (`schemas/validate.sh`) for manifest linting.
- **Runner library** (`lib/runner.sh`) with load / ensure_instructions / command_builder / hook helpers. Manifests under `runners/*.json`.
- **Signal protocol preamble** injected into non-Claude runners so they emit `<quantum>STORY_PASSED/FAILED/COMPLETE/BLOCKED</quantum>` markers in a shared format.
- **Signal heuristic fallback** (`lib/signal-heuristics.sh`) — if no explicit `<quantum>` signal is present, infer from commit evidence, test results, and hedge-phrase filters.
- **Instruction-file auto-copy** — replicates `CLAUDE.md` to each runner's convention (`AGENTS.md`, `GEMINI.md`, etc.).
- **Runner manifests**: `claude.json` (guaranteed), `codex.json` (tested end-to-end), plus experimental manifests for `amp`, `aider`, `copilot`, `cursor`, `gemini`.
- Sequential mode, PowerShell mode, and `templates/quantum-loop.sh` all wired to the runner framework.
- 22-test signal-heuristic suite and an integration test-suite for Codex CLI dispatch.

### Fixed
- Sequential-mode status updates no longer lose state on runner switch.
- Heuristic false-positive filter for ambiguous runner output.
- Runner name + template argument validation hardened against injection.

## [0.3.7] - 2026-03-30

### Added
- **Hardening-v2: init-guard + AST-aware merge + resilience** — design doc `docs/plans/2026-03-28-hardening-v2-design.md`.
- **`lib/init-guard.sh`** — environment pre-flight: OneDrive / long-path detection, tmpdir writability check, orphan worktree prune.
- **`lib/merge-semantic.sh`** — AST-aware 3-way merge (ts-morph for TypeScript, libcst for Python, diff3 fallback) routed via `lib/merge-strategy.sh`.
- **`lib/resilience.sh`** — WIP commits per task, squash-on-merge at story boundary, crash recovery via `lastWipCommit` + `completedTasks` fields. Supersedes `lib/crash-recovery.sh` (to be removed).
- **Stash exclusion for `quantum.json`** during merges to prevent schema corruption.
- Integration tests covering init → merge flow, crash recovery with WIP commits, semantic merge conflict, quantum.json stash isolation.

### Fixed
- Stash-ordering race in `merge-strategy.sh`.
- Trap cleanup on early abort paths in `resilience.sh`.
- stderr redirect typo on ts-morph merge fallback path.

## [0.3.6] - 2026-03-25

### Added
- **Modular Hardening (7 independent modules)** — design doc `docs/plans/2026-03-25-modular-hardening-design.md`.
- **`lib/barrel-regen.sh`** — auto-regenerate barrel exports (`_barrel.ts` / `__init__.py` / etc.) post-merge so new story files become consumer-importable.
- **`lib/dep-manifest.sh`** — detect dependency-manifest changes (npm / pip / go / cargo) and run appropriate install post-merge.
- **`lib/known-failures.sh`** — baseline + delta tracking of test failures per wave. Alerts on **new** regressions, not pre-existing red.
- **Worktree lifecycle** — `worktree.sh` extended with lifecycle-tracking functions; `execution.worktreeTracking` fields `{activeWorktrees, cleanedThisSession, maxWorktrees}`.
- **Category-based merge strategy** (`lib/merge-strategy.sh`) — routes conflicts by file kind: `dependency_manifest → ours+install`, `barrel_export → regenerate`, `new_story_file → theirs`, `shared_infrastructure → ours`, `contract_stub → theirs`, default escalate.
- **Interface cascade guard** extending the L5 type audit.
- **`contractBreaking` flag + `fixes` field** in ql-plan for intentional breaking changes.
- Unit tests for barrel-regen, dep-manifest, known-failures, worktree lifecycle, merge-strategy, plus integration tests for known-failures lifecycle and escalation retry.

## [0.3.5] - 2026-03-24

### Added
- **DAG Intelligence — parallel specialist validators** — design doc `docs/plans/2026-03-24-dag-intelligence-design.md`.
- **`dag-validator` coordinator agent** that spawns three specialists in parallel:
  - **`bottleneck-analyzer`** — Kahn's-algorithm wave assignment; detects sequential bottlenecks.
  - **`duplication-detector`** — Jaccard keyword pre-filter + LLM semantic check for overlapping stories.
  - **`conflict-auditor`** — computes complete `fileConflicts` from `filePaths` intersections with severity classification.
- **`storyType` field** on stories (feature / refactor / fix / test / docs / skeleton / integration).
- **`dagValidation` block** + `severity` field in `quantum.json` schema.
- `dag-validation.md` reference doc.
- `ql-plan` integrates `dag-validator` invocation before plan confirmation; shows DAG Health Report.

### Fixed
- PR-review findings from soliton review (prompt hardening, context-window optimization).

## [0.3.4] - 2026-03-18

### Added
- **Progressive Materialization (5-layer type-divergence defense)** — design doc `docs/plans/2026-03-18-worktree-isolation-fix-design.md`.
- **`lib/materialize.sh`** — detects language; materializes real interface files for contracts consumed by ≥2 stories (threshold configurable). Smart-materialization threshold logic added in this release.
- **`lib/type-audit.sh`** — grep-based duplicate-definition detection at wave boundary; spawns `type-auditor` agent on hits and feeds findings back into contracts.
- **Post-merge typecheck gate** — auto-detects project typechecker (tsc, pyright, mypy, etc.) and reverts on failure.
- **Auto-promotion of discovered contracts** — orchestrator promotes wave-end audited types into `materializedContracts`.
- **`typecheckCommand` field** in `quantum.json` schema; new execution-metadata fields for materialization and audit tracking.
- **Shared-types directory inference** + `contract-shapes` reference doc for `ql-plan`.
- **Contract Effectiveness section** in orchestrator post-mortem output.
- Extended `merge_worktree_branch()` with conflict classification.
- Unit tests for `materialize.sh`, `type-audit.sh`, merge escalation, typecheck gate.

### Fixed
- Command-injection hardening in merged scripts.
- Path-traversal checks in materialization paths.
- Merge revert safety when a post-merge gate fails.
- L5 audit feedback loop, error counting, Python pattern recognition.

## [0.3.3] - 2026-03-11

### Fixed
- **File-conflict-aware DAG scheduling** — new `filter_file_conflicts()` in `dag-query.sh` prevents spawning parallel agents that share file paths. Uses greedy priority-ordered selection with exact-match comparison. Wired into both dispatch sites in `quantum-loop.sh` (initial wave + mid-wave top-up). Also detects cross-wave conflicts by seeding with in_progress stories' files.
- **Worktree nesting prevention** — new `_resolve_repo_root()` helper in `worktree.sh` resolves nested worktree paths to the top-level repo root via `git rev-parse --git-common-dir`. Used by all three public functions (create, remove, list). Falls back gracefully on Git < 2.31 and warns when resolution fails inside `.ql-wt/` paths.
- **Windows long-path fallback** — `create_worktree` detects paths > 200 chars and falls back to a repo-namespaced temp directory (`/tmp/ql-wt-<hash>/`). Re-checks fallback length with emergency `/tmp` last resort. `remove_worktree` and `list_worktrees` check both locations.
- **Editable install race condition** — PYTHONPATH injection guidance added to `implementer.md`, `orchestrator.md`, and `spawn.sh` (both src-layout and flat-layout variants). Agents no longer run `pip install -e .` in parallel worktrees.
- **Worktree cleanup on Windows** — retry loop (3 attempts, 2s delay) for file locks from OneDrive sync / `__pycache__`. `rm -rf` fallback only runs when `git worktree remove` actually fails. `git worktree prune` runs after cleanup.
- **Unescaped shell expansions** — `orchestrator.md` prompt template now uses `\$(pwd)` and `\$PYTHONPATH` (matching `spawn.sh` pattern) to prevent premature expansion.
- **echo → printf** — `detect_cycles` in `dag-query.sh` now uses `printf` matching project convention.

### Added
- **Inline review gate for parallel mode** (Step 3B.4) — orchestrator runs spec compliance + code quality checks after each worktree merge, matching sequential mode's quality bar. Defers to wave-end when accumulated diff exceeds 2000 lines.
- **Full-feature code review** (Step 4B) — holistic review of entire branch diff after all stories pass. Checks cross-story consistency (naming, duplicates, type mismatches), architecture coherence (PRD goals, data flow, backward compatibility), and security (secrets, TODOs, error handling).
- **quantum.json merge guidance** — documented stash/merge/restore pattern and recommended `.gitignore` best practice.
- **Input validation** — `filter_file_conflicts()` validates file path and eligible array before processing.
- **Cross-repo collision prevention** — `_short_path_base()` uses repo-root hash to namespace `/tmp` worktrees per repository.
- 14 new tests: `filter_file_conflicts` (8 tests covering filePaths overlap, fileConflicts entries, empty/null, three-way conflict, transitive chains, similar paths), `_resolve_repo_root` (3 tests: identity, from-worktree, nested-create), `_short_path_base` (2 tests: determinism, cross-repo uniqueness), PYTHONPATH in spawn prompt (4 assertions). **79 total tests, all passing.**

## [0.3.2] - 2026-03-10

### Fixed
- **Mandatory worktree isolation** — `isolation: "worktree"` is now documented as MANDATORY for parallel execution, with specific failure modes listed (bash contention, file conflicts, quantum.json races)
- **Correct tool naming** — orchestrator now references "Agent tool" (not "Task tool") with exact parameter names (`subagent_type`, `isolation`, `mode`, `run_in_background`)
- **Atomic quantum.json updates** — new Step 3B.1 batches all `in_progress` status writes into a single atomic update before spawning agents
- **Monitor loop** — changed from polling to waiting for Claude Code completion notifications
- **State management discipline** — only the orchestrator writes quantum.json; Edit tool banned (use Python/jq); multi-story updates batched into one write
- **Implementer parallel mode** — implementer agents in worktrees no longer edit quantum.json (stale copy); report via output message instead
- **Anti-rationalization guards** — 2 new entries blocking "skip worktree" and "worktrees won't work on this OS" excuses

## [0.3.1] - 2026-03-09

### Added
- **Cross-story contracts** — `contracts` field in quantum.json for shared values (secret keys, env vars, types) across parallel stories. ql-plan generates them; implementer reads and enforces them with propose-and-wait on disagreements.
- **Wiring verification** — `wiring_verification` field on tasks with grep-based mechanical check in spec-reviewer. No agent judgment: missing string = fail, present = pass.
- **`consumedBy` field** — declares cross-story consumption so implementers import existing components instead of inlining duplicates.
- **Coverage gate** — configurable `coverageThreshold` in quantum.json; quality-reviewer runs coverage tool and fails stories below threshold (tool detection: c8 → nyc → pytest-cov → go test → JaCoCo).
- **Coding standards enforcement** — quality-reviewer reads CLAUDE.md, `.claude/rules/`, and `codebasePatterns`; violations of documented rules are CRITICAL severity.
- **Stale story detection** — `startedAt` timestamp + `staleThresholdMinutes` (default 20, CLI-overridable). Implemented in orchestrator, quantum-loop.sh, quantum-loop.ps1, and templates/quantum-loop.sh.
- **Final verification sweep** — scripts run full test suite + import smoke test before declaring COMPLETE. Test failure blocks COMPLETE.
- **Execution observations** — auto-generated post-mortem doc after every run with failure summary, patterns, and raw data. Optional GitHub issue filing with user confirmation.
- **CLAUDE.md defensive check** — Step 3 warns and skips stories that are in_progress but not assigned to the current agent.
- **Lifecycle awareness** — ql-brainstorm question #7 (LIFECYCLE) and ql-spec Pre-Save lifecycle checklist (first-run, returning-user, update, error recovery, empty state, uninstall).
- **`testFirst` mandate** — ql-plan defaults `testFirst: true` for all tasks; exempt tasks require `notes` justification.
- Shell tests for stale detection, startedAt, final sweep, and observations (4 new test files, 14 tests)

### Fixed
- **Atomic in_progress + startedAt write** — single jq operation prevents crash window where story is in_progress without startedAt
- **startedAt cleared on all exit paths** — BLOCKED, unrecognized signal, timeout, merge conflict, non-zero exit, and crash recovery
- **Null-guard failureLog** — observations jq uses `(.retries.failureLog // [])[]` to handle null vs empty array

## [0.3.0] - 2026-02-27

### Added
- **Cross-story integration review** — Stage 3 in ql-review traces call chains across story boundaries using LSP (grep fallback). Runs after dependency chains complete and as a final gate before COMPLETE.
- **Final integration gate** — orchestrator runs import smoke test, full test suite, and dead code scan before declaring COMPLETE
- **File-touch conflict detection** — ql-plan Step 5 flags parallel stories modifying the same file, adds reconciliation tasks, stores conflicts in `quantum.json` metadata (`fileConflicts`)
- **Consumer verification pattern** — wiring acceptance criteria belong on the consumer story, not the creator
- **Edge case test requirements** — boundary values, type variations, collision scenarios, scale tests required for all testFirst tasks
- **Edge case reference doc** — `references/edge-cases.md` with Python, JS, Go, Rust testing gotchas. Implementer reads it at the start of every testFirst task.
- **Import chain verification** — ql-verify requires integration evidence for multi-story features
- **Cursor marketplace manifest** — `.cursor-plugin/plugin.json` for cross-platform publishing

### Changed
- Orchestrator Step 4 split into Step 4 (Final Integration Gate) and Step 5 (Completion)
- Implementer always reads `references/edge-cases.md` for testFirst tasks (not on-demand)

## [0.2.0] - 2026-02-25

### Added
- **Orchestrator agent** (`agents/orchestrator.md`) — manages full execution lifecycle inside Claude Code with DAG query, sequential/parallel dispatch, two-stage review, retry logic
- **Native PowerShell script** (`quantum-loop.ps1`) — Windows overnight runs without bash/WSL
- **SkillsMP compatibility** — `name` field in all SKILL.md frontmatter
- **ql-plan runner copy** — copies quantum-loop.sh/ps1 into project after planning

### Fixed
- **Lost work in parallel mode** — agents must commit before signaling; orchestrator adds safety commit before merge
- **Merge failure on dirty tree** — stash working tree before merge, pop after
- **Stale worktree branches** — delete existing branch before `git worktree add -b`

### Changed
- Simplified `skills/ql-execute/SKILL.md` from ~300 lines to ~50 line dispatcher
- `CLAUDE.md` parallel mode: agents explicitly told to commit before signaling
- `lib/spawn.sh` prompt includes commit instruction

## [0.1.0] - 2026-02-19

### Added
- Parallel execution via DAG-driven worktree agents
- 7 shell library modules (`lib/`) for DAG query, worktree lifecycle, agent spawning, monitoring, atomic JSON writes, crash recovery
- 7 test suites with 110 tests
- `--parallel` and `--max-parallel` flags for `quantum-loop.sh`
- `/ql-execute` parallel orchestration via Task subagents
- Crash recovery for orphaned worktrees
- `CLAUDE.md` parallel mode instructions

## [0.0.1] - 2026-02-18

### Added
- Initial release
- 6 skills: brainstorm, spec, plan, execute, verify, review
- 3 agents: implementer, spec-reviewer, quality-reviewer
- `quantum-loop.sh` sequential autonomous loop
- `CLAUDE.md` agent template
- Dependency DAG execution
- Two-stage review gates (spec compliance + code quality)
- Iron Law verification
- Anti-rationalization guards
