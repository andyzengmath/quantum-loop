# IDEA_REPORT_v6 — what's still open after v0.6.5

**Date:** 2026-04-27
**Source:** `ql/v0.6.5-bundle` dogfood retrospective (US-007)
**Branch:** `ql/v0.6.5-bundle` (release tag v0.6.5)
**Predecessor:** `idea-stage/IDEA_REPORT_v5.md`

## Closed in v0.6.5

| ID | Story | Notes |
|---|---|---|
| **G18** | US-005 | `quantum-loop.sh _audit_pre_impl_review_coverage` missing-csv branch drill text now includes operator guidance: "(expected on first run after install — invoke /ql-brainstorm/spec/plan to populate)". Closes the operator-confusion gap from v0.6.4 dogfood. **One follow-up surfaced**: `_audit_format_row` only renders drills for FAIL rows, so the new guidance is captured in tests but not yet visible at `--audit` runtime. Queued as a v0.6.6 candidate (see "New gaps from v0.6.5 dogfood" below). 1 new test assertion (Test 28b in `test_audit.sh`). |
| **G20** | US-006 | `README.md` gains `## Self-modifying execution` section between How It Works and Quick Start. Two paragraphs explain the rule (each release ships wires that apply to NEXT runs) and a concrete v0.6.4 example (the CSV-persistence wires that the v0.6.4 dogfood couldn't exercise). Cross-link to `idea-stage/PIPELINE_REPORT_v5.md`. Closes the recurring "is the audit broken?" reaction for new operators. 7 new test assertions in `tests/test_readme.sh` (NEW). |
| **G25** | US-003 | `agents/conflict-auditor.md` Step 4 sort instruction now enumerates all 5 severities in priority order: `high → medium → low → warning → none` with a 1-sentence rationale (high most-impactful; warning informational-but-real-signal; none informational-only). Closes the gap opened by v0.7.0 G15 (`warning`) and Rule 0 (`none`) which had no deterministic ordering before. 1 new test assertion (Test 7 in `test_changelog_ownership.sh`). |
| **G26** | US-001 | `quantum-loop.sh do_audit` summary line splits from `Summary: <ok>/<total> metrics on target.` to `Summary: <ok>/<total> OK, <warn> WARN, <fail> FAIL.`. Walks `ROWS[]` once accumulating 3 counters from the `\|OK\|` / `\|WARN\|` / `\|FAIL\|` substrings. Exit-code semantics preserved: returns 1 iff any row contains `\|FAIL\|`. Closes the misleading-on-target wording the v0.6.4 retrospective flagged. 4 new test assertions (Tests 33-35 + updated Test 23 in `test_audit.sh`). |
| **G27** | US-002 | `agents/spec-reviewer.md` plan-review checklist's "testFirst command consistency" rule now cites `lib/handoff.sh::SPRINT_CONTRACT_TEST_REGEX` as canonical (the 5th call site that v0.6.4 G14 missed). Inline regex characters preserved with explicit "see ..." framing for self-documentation. `lib/handoff.sh` consumer comment updated 4 → 5 sites. 1 new test assertion (sub-test 7h in `test_sprint_contract.sh`). |
| **G28** | US-004 | `references/risk-mitigation-language.md` (NEW, 153 lines): design-craft checklist for Risk-section authors. 3 sections — the rule + cautionary tale (v0.6.4 c89ba13 flock-bootstrap-race + soliton finding at confidence 90), 4-item concurrency checklist (shared state / observably-coupled ops / race window without / race window with), short-form patterns for non-concurrency mitigations. Bidirectional cross-link with `references/finding-severity.md` (review-craft pair). Operationalizes codebasePattern p007 from v0.6.4. 10 new test assertions in `tests/test_risk_mitigation_language.sh` (NEW). |

The **G18-G28 cluster** (the v0.6.5 priority list from IDEA_REPORT_v5) is now **fully closed**. Each G item maps to exactly one user story; each story shipped first-attempt PASS across the 2 orchestrator runs.

## First populated-CSV milestone

v0.6.5 is the **first release whose dogfood produced real CSV data**. `metrics/pre-impl-review-findings.csv` now contains 3 rows representing the design / prd / plan reviews on this v0.6.5 cycle's planning artifacts:

```
2026-04-27T18:35:56Z,design,docs/plans/2026-04-27-v0.6.5-bundle-design.md,1,0,0,0,1
2026-04-27T18:40:12Z,prd,tasks/prd-v0.6.5-bundle.md,4,0,0,0,4
2026-04-27T19:04:17Z,plan,quantum.json,0,0,0,0,0
```

This unblocks **G22 (severity-rubric calibration)** for v0.7.x retrospectives. It also closes the v0.6.4 PIPELINE_REPORT_v5 line *"v0.7.1's first end-to-end run will be the first to populate the CSV"* — fulfilled, with 3 rows of provenance attached. The audit log captured at `.omc/phase-N-evidence/v0.6.5-audit.log` shows `pre-impl-review-coverage: 3/3 stages OK` (was `0/3 stages WARN` in v0.6.4 retrospectives).

## Still open: P5.B2 / B3 / B5 (no change since v5)

| ID | What it is | Effort | v0.6.x verdict |
|---|---|---|---|
| **P5.B2** Bidirectional reviewer agent | spec-reviewer can request implementer fix specific issues; implementer can flag spec-reviewer ambiguities back. | 2-3 stories | Architectural; deferred to v0.8.x — needs ≥1 release of CSV calibration data first. **v0.6.5's populated-CSV milestone is the first calibration data point.** |
| **P5.B3** `/ultrareview` command | Single-command "rev-the-engine" composed of spec-reviewer + quality-reviewer + ql-deep-review + far-filter + intent-graph + intent-check. | 1-2 stories | Compositional refactor; needs P5.B2 first. |
| **P5.B5** AgentGA tournament | N agent forks each implement the same story; meta-reviewer merges best-of. | 3-4 stories | Cost-quality tradeoff; needs P5.C1 measurement infra. |

## Still open: P5.C frontier (no change since v5)

| ID | What it is | When to tackle |
|---|---|---|
| **P5.C1** Cost-quality Pareto frontier measurement | Run same N-story plan at 3 model-mix points; measure $/quality. | Needs measurement infra. |
| **P5.C2** Multi-runner integration tests with REAL second provider | Today mocked. | Blocked on second-provider CLI access. |
| **P5.C3** Speculative parallel re-planning | When wave fails, plan recovery branches in parallel. | High-novelty research arc. |
| **P5.C4** Live progress UI | Web UI or rich TUI for wave/story timing. | Pure UX, deferred. |
| **P5.C5** Cross-repo skill sharing | Skills package shared across installations. | Needs registry pattern. |

## Carried forward from v5 (still open)

| ID | What it is | v0.6.5 disposition |
|---|---|---|
| **G19** | 3 SKILL wrappers identical-by-design (Phase 4d / post-prd-review / Step 9 in ql-{brainstorm,spec,plan}/SKILL.md) verified by grep. Works for 3 sites; scales poorly if a 4th stage is added. | Unchanged. Revisit only if a 4th pre-impl-review stage is ever added. The v0.6.5 G27 closure of the SPRINT_CONTRACT_TEST_REGEX 5th call site validates that grep-needle assertions DO catch missed-enumeration bugs at scale, so the pattern is healthier than v5 suggested. |
| **G21** | `metrics/` directory is committed but no automation prunes old rows. Append-only over many releases. | v0.6.5 added 3 rows. Total CSV is now 4 lines including header. Premature optimization; revisit at >100 rows (~30 releases). |
| **G22** | Severity rubric (G16) has no canonical baseline distribution. | **NEWLY FEASIBLE** after v0.6.5's populated-CSV milestone. v0.7.x retrospective should: (a) read 1+ release of CSV data, (b) compute severity histograms per mode (design/prd/plan), (c) compare against rubric's expected mix in `references/finding-severity.md`, (d) tighten the rubric language where reality diverges. v0.6.5's 3 rows are too few for distribution analysis (only 5 findings total, all low-severity); need 3-5 more populated-CSV releases before histogramming becomes meaningful. |
| **G24** | `_audit_pre_impl_review_coverage` reads `metrics/...` as bare relative path while `persist_review_findings` writes `${root}/metrics/...`. CWD inconsistency. | Unchanged from v5. Consistent with all 6 existing audit helpers; not strictly a bug. Deferable. |

## NEW gaps surfaced by v0.6.5 dogfood

| Gap | Symptom | Where seen | Suggested fix |
|---|---|---|---|
| ~~**G29: Audit WARN drills not rendered to operators**~~ | ~~`_audit_format_row` line 135 only renders drill text when status==FAIL — G18's first-run guidance is invisible.~~ | — | **ADDRESSED in v0.6.5 commit `f6cd1e0`.** `/soliton:pr-review` on PR #66 independently surfaced the same root issue at confidence 97. Fix extended `_audit_format_row` to render drill on FAIL OR WARN. Tests 3b + 3c added (regression guard + symmetric empty-drill test). 41/41 audit tests GREEN. G29 is closed. |
| **G30: ql-deep-review tier-decision rule needs explicit doc** | v0.6.4 retrospective tracked "ql-deep-review skipped at Wave 2" as an audit gap. v0.6.5 addressed this by documenting (in `idea-stage/PIPELINE_REPORT_v6.md`) that the v0.6.5 diff is LOW-tier and the per-story two-stage review gate covers all changes, so deep-review was skipped intentionally. **But the decision rule itself is not yet codified anywhere outside this retrospective.** A future release with a new lib + new schema + new agent contracts (i.e., MEDIUM-or-higher tier) needs the decision rule machine-readable so the orchestrator can auto-invoke deep-review at the wave-N boundary. | `lib/deep-review.sh::tier` is computed; the decision-to-invoke based on tier is not codified in `agents/orchestrator.md` Step 4B.5. | Update `agents/orchestrator.md` Step 4B.5 to gate ql-deep-review dispatch on `tier >= MEDIUM`, AND document explicit override syntax (e.g., `QL_DEEP_REVIEW=force` env var). Add a fixture-driven test: a low-tier diff exits Step 4B.5 without spawning reviewers; a medium-tier diff spawns them. 1 story. |
| **G31: Test-suite runtime growing past comfortable wall-clock** | The full test suite (73 files) ran in T-002 capture during this retrospective and was still mid-flight after several minutes of background execution before the report-writing finished. As the project accumulates assertions (now ~1,760), the dogfood test-suite capture becomes a noticeable bottleneck for retrospective writing. | `.omc/phase-N-evidence/v0.6.5-test-suite.log` (mid-flight at retrospective-write time) | Two paths: (a) parallelize the for-loop with `xargs -P` or GNU `parallel` (test files appear independent — verify); (b) add `--quick` mode to retrospective T-002 that runs only the most-recently-changed test files via `git diff master..HEAD --name-only -- 'tests/test_*.sh'`. (a) is the structural fix; (b) is the conservative mitigation. 1 story for either. |

## NEW gaps surfaced by codebasePattern harvest

A new pattern p008 (sourced-script errexit propagation in test files) was harvested during US-001's RED-test phase. **The pattern itself is the surfaced gap**: any new test file that sources production code with `set -e` is at risk of silent termination on subshell exits. Existing test files in `tests/` may have latent versions of this issue that haven't manifested yet (because the production code happens to never `exit N≠0` from inside a captured subshell).

**Suggested follow-up:** a `tests/test_test_helpers.sh` that asserts every `tests/test_*.sh` file uses one of the safe patterns (function-extracted subshell + two-invocation idiom, OR `|| true` immediately after the substitution, OR an explicit `set +e` block scope). 0.5 stories.

## NEW gaps surfaced by post-push review passes on PR #66

This v0.6.5 cycle ran BOTH `/soliton:pr-review` AND `/code-review:code-review` post-push, matching the v0.6.4 convention. Soliton found 1 critical (G29 above, now closed inline). The 5-Sonnet code-review pass surfaced 4 candidate findings — 1 dismissed as false-positive (claimed `warning` severity was undeclared in `agents/conflict-auditor.md`; verified false — Rule 0.5 explicitly defines it). The remaining 3 all scored below the ≥80 inline-fix threshold and are queued here for v0.6.6.

| Gap | Origin | Score | Suggested follow-up |
|---|---|:-:|---|
| **G32: G27 negative assertion missing in `tests/test_sprint_contract.sh`** | `/code-review:code-review` reviewer #4 (prior-PR feedback). The PR's design doc + PRD §US-002 Verification specify both a positive assertion (`grep -q 'SPRINT_CONTRACT_TEST_REGEX' agents/spec-reviewer.md`, present as Test 7h) AND a negative assertion (no uncited inline regex copies remain — pattern roughly `grep -E '(test_\|\.test\.\|spec\|pytest)' agents/spec-reviewer.md \| grep -v 'SPRINT_CONTRACT_TEST_REGEX' \| grep -v -F 'see lib/handoff.sh' \| wc -l == 0`). Only the positive assertion shipped. Without the negative guard, a future commit could re-add an inline regex copy alongside the citation and the test would still pass — defeating G27's "single source of truth" purpose. The other 4 SPRINT_CONTRACT_TEST_REGEX consumer sites have equivalent negative assertions (Tests 7e–7f cover orchestrator.md and ql-plan/SKILL.md). | 75 | Add the negative grep assertion as a new Test 7i in `tests/test_sprint_contract.sh` mirroring 7e–7f. 0.25 stories. |
| **G33: Tests 34/35 in `tests/test_audit.sh` duplicate `do_audit` counting logic verbatim** | `/code-review:code-review` reviewers #1 + #3 corroborated. Tests 34/35 define `_t34_run`/`_t35_run` private helpers that copy-paste the `case "$row" in *"\|FAIL\|"*` switch from `do_audit` rather than calling the real function. Test 33 already exercises real `do_audit` integration-style, so the gap is partial — but a future regression in `do_audit`'s case patterns (e.g., changing `*"\|WARN\|"*` to `*"WARN"*`) would not be caught by 34/35. The duplication exists for a real reason (subshell exit-code capture per CLAUDE.md Platform Notes), but a more invasive test using `bash quantum-loop.sh --audit` against synthetic ROWS via env-var override would track the real function. | ~55 | Refactor Tests 34/35 to invoke `bash quantum-loop.sh --audit` with a `QL_AUDIT_TEST_ROWS` env-var override that lets `do_audit` consume a synthetic ROWS array. Or accept the duplication and add a comment explaining why. 0.5 stories. |
| **G34: Verbose explanatory comments in `quantum-loop.sh` embed PR-metadata** | `/code-review:code-review` reviewer #1 (CLAUDE.md compliance). The `_audit_format_row` and `do_audit` function-headers added in this PR cite soliton confidence scores, G-numbers, and version tags inline (e.g., `(v0.6.5 post-merge fix: G18 added a WARN drill ... soliton-pr-review caught at conf 97.)`). CLAUDE.md says "Don't reference the current task, fix, or callers ... since those belong in the PR description." The underlying WHY (why both FAIL and WARN drill) is non-obvious and merits a short comment, but the PR/release/confidence metadata bloats it. | 62 | Trim the comments to keep the WHY (why FAIL+WARN, not just FAIL) and remove the PR-metadata (G-numbers, version tags, soliton confidence). 0.25 stories. Or accept as a minor style drift if the citations help future readers find the historical context faster than git log. |

## False positives surfaced this cycle (for protocol calibration)

| Source | Claim | Resolution |
|---|---|---|
| `/code-review:code-review` reviewer #2 | `agents/conflict-auditor.md` Step 4 sort prose names `warning` but enum doesn't define it. | **FALSE.** Rule 0.5 explicitly defines `severity: warning` for the CHANGELOG-ownership convention violation. Confirmed by Haiku scorer at 0/100. No action needed. |
| `/code-review:code-review` reviewer #5 | Multiple "violations" claiming the PR "reverts" the WARN-drill behavior, removes the conflict-auditor sort prose, removes the risk-mitigation-language doc, etc. | **HALLUCINATED.** Reviewer #5 read the diff in the wrong direction — described the PR as removing changes that the PR actually adds. All 5 of its findings are wrong-direction reads. None scored. |

The hallucinated reviewer suggests adding a calibration step in v0.7.x to detect direction-of-diff confusion: a reviewer claiming "the PR reverts X" should be cross-checked against the actual diff direction. Tracked here as an observation for v0.6.6 retrospective rather than a backlog item.

## Recommendation for v0.6.6 / next bundle

**Highest leverage v0.6.6 candidates (in order):**

1. **G32** — add the missing G27 negative assertion to `tests/test_sprint_contract.sh` (closes a real coverage gap; quarter-story; defends G27's single-source-of-truth invariant).
2. **G30** — codify ql-deep-review tier-decision rule in orchestrator prose + add fixture test (closes the v0.6.4-traced audit gap structurally rather than retrospectively).
3. **G31** — test-suite parallelization or `--quick` mode (operator-facing wall-clock improvement; gating future retrospective velocity).
4. **G33** — refactor Tests 34/35 to invoke real `do_audit` via env-var ROWS override (or document the duplication rationale). Closes the duplicate-logic test-coverage maintenance liability.
5. **G34** — trim PR-metadata bloat from `quantum-loop.sh` function-header comments while keeping the load-bearing WHY (CLAUDE.md "Default to writing no comments" compliance).
6. **p008-driven test-helper audit** — defensive pattern enforcement across all `tests/test_*.sh` (small but high-prevention-value).
7. **First multi-cycle severity-rubric data point** — explicitly invoke /ql-brainstorm + /ql-spec + /ql-plan on the v0.6.6 planning cycle so the CSV grows from 3 to 6+ rows. **Process step, not a story.**

~~**G29**~~ (audit WARN drill rendering) was addressed inline in v0.6.5 commit `f6cd1e0` after `/soliton:pr-review` independently surfaced it at confidence 97. Closed.

**Deferred to v0.6.x or v0.7.x:**

- **G19** (3 SKILL wrappers identical-by-design) — unchanged.
- **G21** (metrics rotation) — unchanged; revisit at >100 rows.
- **G22** (severity rubric calibration) — newly feasible but needs 3-5 more populated-CSV releases before histograms are meaningful. v0.7.x.
- **G24** (audit relative-path inconsistency) — unchanged; consistent with existing helpers, not a bug.
- **P5.B2 / B3 / B5** and **P5.C\*** — same as v5 verdict.

## Promotion gate: pre-impl-review advisory → blocking

Same policy as v5: blocking-promotion of any pre-impl-review stage defers until the CSV accumulates baseline distribution data. v0.6.5 contributed the **first 3 rows** — a meaningful unblock signal but still too few for distribution analysis. The first such retrospective should happen no earlier than v0.7.2 (after at least 3-5 populated-CSV releases). v0.6.6 should ship G29 + G30 + whatever else surfaces, NOT a promotion decision.

The 3 rows from this cycle's planning are also a **provenance baseline**: future calibration retrospectives can compare against the v0.6.5 row distribution as the earliest known datum.

## Recurring caveat: self-modifying execution

The v0.6.5 dogfood ran on v0.6.4 master HEAD (commit `74a946a`). v0.6.5's changes apply to runs starting AFTER the bundle merges. **For v0.6.5 specifically, this caveat is less load-bearing** than for v0.6.4 (where CSV-persistence wires materially changed orchestrator output) — v0.6.5 is doc-and-drill changes that only become operator-/agent-visible in subsequent runs.

The README `## Self-modifying execution` section that US-006 added is the operator-facing version of this recurring note. **Future first-run operators reading --audit WARN output find the answer in the README, not by hunting through PIPELINE_REPORT_vN.** This was the entire point of G20.
