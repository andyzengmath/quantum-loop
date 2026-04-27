# IDEA_REPORT_v5 — what's still open after v0.7.0

**Date:** 2026-04-27
**Source:** v0.7.0-bundle dogfood retrospective (US-007)
**Branch:** `ql/v0.7.0-bundle`
**Predecessor:** `idea-stage/IDEA_REPORT_v4.md`

## Closed in v0.7.0

| ID | Story | Notes |
|---|---|---|
| **G12** | US-001 | `lib/finding-synth.sh` — pure parser library: `parse_findings(stage)` reads stdin, emits structured JSON array; `summarize_findings(stage, findings_json)` returns `{stage,count,by_severity,by_category}`; `format_summary_line(summary_json)` emits the `[REVIEW] <stage>-review complete: ...` line. CLI subcommand mode (`parse`, `summarize`, `format`). Malformed FINDING blocks warn-and-drop; remaining blocks parse. Library follows `lib/handoff.sh`'s no-flags-at-source-time + double-source guard convention. 31 new test assertions. |
| **G13** | US-002 | `lib/finding-persist.sh` + 3 SKILL wires (Phase 4d / post-prd-review / Step 9). Persistence: `.handoffs/<stage>-review-findings.json` per-run snapshots (idempotent overwrite per stage) + `metrics/pre-impl-review-findings.csv` aggregate ledger (header on first write, `flock -x` guarded append, rename-replace fallback). Read-side `read_review_findings(stage)` round-trips snapshot or emits `{}` + stderr WARN. Advisory contract preserved across all 3 stages. `.gitignore` updated. 37 new assertions. |
| **G14** | US-003 | `lib/handoff.sh::SPRINT_CONTRACT_TEST_REGEX` readonly constant — single source of truth for the test-pattern regex `(test_\|\.test\.\|spec\|pytest\|^bash tests/\|^npm test)`. 4 historical inline copies (orchestrator.md Step 2.5, ql-plan SKILL.md Step 8, test_sprint_contract.sh, test_sprint_contract_ql_plan.sh) all rewired to source the lib + pass via `jq --arg pattern`. `references/sprint-contract.md` references the constant by name. Future regex changes touch one file. 18 sprint_contract assertions GREEN (16 baseline + 2 no-inline-regex new); 13 sprint_contract_ql_plan rewired and GREEN. |
| **G15** | US-006 | CHANGELOG ownership convention codified in `agents/dag-validator.md` §5d (convention paragraph + Health Report line for >1 story touching CHANGELOG.md) and `agents/conflict-auditor.md` Rule 0.5 (severity:warning override of Rule 0:none for multi-story CHANGELOG.md conflicts). Validated by US-007 itself: this run has count=1 (only US-007 touches CHANGELOG), so no warning emitted — convention holds. 9 new assertions. |
| **G16** | US-004 | `references/finding-severity.md` rubric — 3 mode sections (`## design-review`, `## prd-review`, `## plan-review`), each with a 4-row Severity / Rubric / Example table calibrated to the mode's existing checklist categories. `agents/spec-reviewer.md` design / prd / plan sections gain 1 cross-link line each above their `### Output format` subsections (kebab-case anchor IDs). 14 new assertions. |
| **G17** | US-005 | `quantum-loop.sh --audit pre-impl-review-coverage` — 7th audit row tracking how many of the 3 advisory pre-impl-review stages have run in the last 7 days. 4 states: `missing-csv` WARN (no CSV), `no-recent-runs` WARN (CSV exists but all rows >7d old), `partial-coverage` WARN (1-2/3 stages recent), `full-coverage` OK (3/3 stages recent). WARN never trips audit exit. Cross-platform date math via 3-level fallback (GNU `date -d`, BSD `date -v`, epoch-0). PS1 parity divergence documented in quantum-loop.ps1 (no PS1 audit shim; bash-only diagnostic). 6 new assertions. |

The G12-G17 cluster is now **fully closed**. Each G item maps to exactly one story; each story shipped first-attempt PASS.

## Still open: P5.B2 / B3 / B5 (no change since v4)

| ID | What it is | Effort | v0.7.x verdict |
|---|---|---|---|
| **P5.B2** Bidirectional reviewer agent | spec-reviewer can request implementer fix specific issues; implementer can flag spec-reviewer ambiguities back. | 2-3 stories | Architectural; deferred to v0.8.x — needs ≥1 release of CSV calibration data first. |
| **P5.B3** `/ultrareview` command | Single-command "rev-the-engine" composed of spec-reviewer + quality-reviewer + ql-deep-review + far-filter + intent-graph + intent-check. | 1-2 stories | Compositional refactor; needs P5.B2 first. |
| **P5.B5** AgentGA tournament | N agent forks each implement the same story; meta-reviewer merges best-of. | 3-4 stories | Cost-quality tradeoff; needs P5.C1 measurement infra. |

## Still open: P5.C frontier (no change since v4)

| ID | What it is | When to tackle |
|---|---|---|
| **P5.C1** Cost-quality Pareto frontier measurement | Run same N-story plan at 3 model-mix points; measure $/quality. | Needs measurement infra. |
| **P5.C2** Multi-runner integration tests with REAL second provider | Today mocked. | Blocked on second-provider CLI access. |
| **P5.C3** Speculative parallel re-planning | When wave fails, plan recovery branches in parallel. | High-novelty research arc. |
| **P5.C4** Live progress UI | Web UI or rich TUI for wave/story timing. | Pure UX, deferred. |
| **P5.C5** Cross-repo skill sharing | Skills package shared across installations. | Needs registry pattern. |

## NEW gaps surfaced by v0.7.0 dogfood

| Gap | Symptom | Where seen | Suggested fix |
|---|---|---|---|
| **G18: Empty-CSV is the audit's most common state for ≥1 release** | `pre-impl-review-coverage` will WARN missing-csv until `/ql-brainstorm`, `/ql-spec`, or `/ql-plan` runs against v0.7.0+ wires. The audit row reads "WARN missing-csv" on every fresh checkout — accurate but easy to misread as a regression. | `.omc/phase-N-evidence/v0.7.0-audit.log` | Add a one-line note to the audit's WARN drill: "(expected on first run after v0.7.0 install — see CHANGELOG)". 1 trivial story. |
| **G19: 3 SKILL wrappers are intentionally identical and verified by grep** | The Phase 4d / post-prd-review / Step 9 wrappers in US-002 are textually parallel; we explicitly chose not to centralize them. The grep-needle assertions in `test_finding_persist.sh::Test10` ARE the regression guard. This works for now (3 sites) but scales poorly if a 4th stage is ever added. | `skills/ql-{brainstorm,spec,plan}/SKILL.md` | If P5.B4 ever expands beyond design/prd/plan, revisit: extract a `lib/spec-review-wrapper.sh` helper at that point. Tracked but not actionable until then. 0-1 stories. |
| **G20: Self-modifying caveat is recurring** | Every release's PIPELINE_REPORT_vX explains "the orchestrator ran on master HEAD; the new wires apply to NEXT runs." This is correct and unavoidable, but operators may be surprised. | All v0.6.x and v0.7.0 retrospectives | Add a one-paragraph note to the project README under "Self-modifying execution" explaining: any feature that instruments the planner/skills only applies to runs starting AFTER the bundle merges. 1 doc story. |
| **G21: `metrics/` directory is committed but no automation prunes old rows** | The CSV is append-only and committed. Over many releases it will grow unbounded. There's no rotation, archival, or compaction policy. | `metrics/pre-impl-review-findings.csv` (designed in v0.7.0) | Add a `lib/metrics-rotate.sh` that, on demand, archives rows older than 90 days to `metrics/archive/<year>-<quarter>.csv`. Wire into a v0.8.x quarterly `quantum-loop.sh --rotate-metrics` shortcut. 1-2 stories. |
| **G22: Severity rubric (G16) has no canonical baseline distribution** | `references/finding-severity.md` defines what severity SHOULD mean per mode, but until v0.7.1+ runs accumulate findings in the CSV, we can't sanity-check whether real reviewers calibrate to the rubric. The rubric may need adjustment after seeing actual finding distributions. | `references/finding-severity.md` | Defer: schedule a v0.7.x retrospective story to (a) read 1+ release of CSV data, (b) compute severity histograms per mode, (c) compare against the rubric's expected mix, (d) tighten the rubric language where reality diverges. 1 story, blocked on data. |

## NEW gaps surfaced by `/code-review:code-review` on PR #64 (v0.7.0 post-push)

Post-merge code review pass on PR #64 ran 5 parallel Sonnet reviewers (CLAUDE.md compliance / shallow bug scan / git-history / prior-PR-comments / code-comments-compliance) followed by per-issue Haiku confidence scoring. Six issues were surfaced; one was scored 25 (false positive — display-only USAGE heredoc) and dropped. The remaining 5 all scored 75 (real but sub-threshold for the ≥80 inline-fix gate) and are queued here for v0.7.1.

| Gap | Origin | Score | Suggested follow-up |
|---|---|:-:|---|
| **G23: `_csv_append_locked` flock-fallback can silently lose CSV header** | `lib/finding-persist.sh::_csv_append_locked` else-branch (no-flock systems) does `cp "$csv" "$tmp"` without validating the precondition stated in its own doc-comment ("The header MUST already exist in the file"). Two concurrent first-runs of different stages on a flock-less system (Git Bash, BSD without flock) can race: first writes empty CSV, second cp's the empty file, appends a data row, and `mv -f`'s a header-less CSV. Audit reads malformed CSV thereafter. | 75 | Add explicit precondition guard to `_csv_append_locked`: if `[[ ! -s "$csv" ]]`, write the header before the `cp`. Or: gate the entire two-call sequence (`! -s "$csv"` header-write + `_csv_append_locked`) under a single shared lock. 0.5 stories. |
| **G24: `_audit_pre_impl_review_coverage` reads `metrics/...` as bare relative path while `persist_review_findings` writes `${root}/metrics/...`** | `quantum-loop.sh::_audit_pre_impl_review_coverage` uses `local csv="metrics/pre-impl-review-findings.csv"` (CWD-relative). `persist_review_findings` writes via an explicit `$root` parameter. If `quantum-loop.sh --audit` is invoked from a non-repo-root CWD, the CSV is silently "missing" even when it exists. | 75 | All 6 existing `_audit_*` helpers also use bare relative paths, so the new helper is consistent with established convention — but inconsistent with the `persist_review_findings` API. Either (a) make `_audit_pre_impl_review_coverage` resolve repo root via `git rev-parse --show-toplevel`, or (b) document explicitly in `quantum-loop.sh` header that `--audit` MUST be invoked from the repo root and exit 2 if not. 0.5 stories. |
| **G25: `agents/conflict-auditor.md` Step 4 sort-order doesn't enumerate `none` or `warning`** | The sort instruction reads "Sort the `fileConflicts` array by severity (high first, then medium, then low)" — written when only those 3 severities existed. Rule 0 (PR #60) added `none`; Rule 0.5 (this PR's US-006) added `warning`. Neither addition updated the sort prose. Agents following the instruction literally have indeterminate ordering for `none` and `warning` entries. | 75 | Update the sort instruction to enumerate all 5 severities: e.g., `high → medium → low → warning → none`. Tighten reproducibility. 0.25 stories. |
| **G26: `do_audit` summary line `"X/Y metrics on target"` counts WARN as on-target** | Pre-v0.7.0, every audit metric was binary OK-or-FAIL, so "X/Y on target" was accurate. PR #64's G17 (US-005) added the first WARN-capable metric (`pre-impl-review-coverage`). `do_audit`'s `ok_count` increments for any non-`FAIL` row — meaning a WARN row is counted as on-target. Test 33 asserts `'Summary: .*7 metrics on target'` for the WARN case, locking in the misleading wording. The committed `.omc/phase-N-evidence/v0.7.0-audit.log` already shows the contradiction. | 75 | Either (a) split the summary into two counts: `Summary: 6/7 metrics OK, 1 WARN, 0 FAIL.` Or (b) reframe "on target" semantics to mean "not FAIL" and add a one-line legend. (a) is more accurate; (b) is closer to existing wording. Update Test 33 in `tests/test_audit.sh` to match the new wording. 0.5 stories. |
| **G27: `agents/spec-reviewer.md` plan-review checklist still inlines the test-pattern regex** | G14/US-003's "single source of truth" intent (`SPRINT_CONTRACT_TEST_REGEX` in `lib/handoff.sh`) updated 4 enumerated consumers. But `agents/spec-reviewer.md` plan-review mode checklist (line 117) also enumerates the same regex inline (`testFirst command consistency` checklist item: `test_`, `.test.`, `pytest`, `^bash tests/`, `^npm test`, `spec`). The constant's consumer comment doesn't mention this 5th site. | 75 | Update `agents/spec-reviewer.md` plan-review checklist to reference `lib/handoff.sh::SPRINT_CONTRACT_TEST_REGEX` instead of inlining. Update `lib/handoff.sh` consumer comment to add `agents/spec-reviewer.md` to the consumer list. 0.25 stories. |

## Recommendation for v0.7.1 / next bundle

**Highest leverage v0.7.1 candidates (in order):**
1. **G26** — fix misleading `--audit` summary (the WARN-counted-as-on-target contradiction is user-facing and the test locks it in).
2. **G23** — fix `_csv_append_locked` flock-fallback race (silent corruption is the worst failure mode; even if rare, the fix is small).
3. **G25** — extend conflict-auditor sort enumeration to cover `none` + `warning`.
4. **G27** — close G14's single-source-of-truth gap with the 5th regex copy in spec-reviewer.md.
5. **G18** — audit drill copy improvement (trivial; closes the "is the audit broken?" reaction; enables G26 to be wedded to a clearer drill).
6. **G20** — self-modifying caveat README note (trivial; one-time documentation debt).
7. **First end-to-end populated-CSV run** — explicitly invoke `/ql-brainstorm` → `/ql-spec` → `/ql-plan` on a v0.7.1+ planning cycle. The first run will be the first to populate `metrics/pre-impl-review-findings.csv`. This is a process step, not a story.

**Deferred to v0.7.x or v0.8.x:**
- **G21** (metrics rotation) — premature optimization until the CSV has accumulated >100 rows.
- **G22** (severity rubric calibration) — explicitly blocked on ≥1 release of CSV data accumulating; cannot be calibrated against zero data.
- **G24** (audit relative-path inconsistency) — consistent with all 6 existing audit helpers; not strictly a bug. Can either be fixed alongside G26 or deferred indefinitely.
- **P5.B2 / B3 / B5** and **P5.C\*** — same as v4 verdict.

## Promotion gate: pre-impl-review advisory → blocking

This is the central question for the v0.7.x line. The v0.7.0 bundle deliberately landed instrumentation (G13 persistence + G16 rubric + G17 audit) WITHOUT promoting any stage from advisory to blocking. **Explicit policy: blocking-promotion of any pre-impl-review stage defers until ≥1 release of CSV baseline data accumulates.**

The reason is empirical: without real finding-severity distributions, picking a blocking threshold is guesswork. Examples of decisions blocked on data:
- "How many `critical` findings per design-review run is normal?" — Need histogram.
- "What's the false-positive rate on `medium` findings?" — Need post-hoc operator-marked false-positive flags.
- "Do `prd-review` `critical` findings predict downstream story failure?" — Need correlation against `quantum.json.retries.failureLog`.

The first such retrospective should happen no earlier than v0.7.2 (i.e., after at least one populated-CSV release). v0.7.1 should ship G18+G20 + whatever else surfaces, NOT a promotion decision.
