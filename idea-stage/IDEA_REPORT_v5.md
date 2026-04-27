# IDEA_REPORT_v5 — what's still open after v0.6.4

**Date:** 2026-04-27
**Source:** `ql/v0.7.0-bundle` dogfood retrospective (US-007). Retrospective filenames + design/PRD use the planning-time `v0.7.0` label; the release ships as `v0.6.4` per strict-semver patch-tier framing (additive instrumentation, no breaking changes, advisory mechanisms remain advisory). v5 → v0.6.4 is the actual mapping. Forward-references to v0.7.1 elsewhere in this doc should be read as v0.6.5.
**Branch:** `ql/v0.7.0-bundle` (historical name; release tag `v0.6.4`)
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
| ~~**G23: `_csv_append_locked` flock-fallback can silently lose CSV header**~~ | ~~`lib/finding-persist.sh::_csv_append_locked` else-branch (no-flock systems) does `cp "$csv" "$tmp"` without validating the precondition stated in its own doc-comment.~~ | 75 | **ADDRESSED in v0.7.0 commit `c89ba13`.** `/soliton:pr-review` independently surfaced the same root issue at confidence 90 (header-write outside flock can let writer-B truncate writer-A's appended row, not just lose the header). Fix moved header bootstrap INSIDE the flock and added `|| return 1` propagation on the fallback path. Plus a separate jq-failure abort guard (soliton finding #3, conf 85). 7 new test assertions in `tests/test_finding_persist.sh` (44/44 GREEN). G23 is closed. |
| **G24: `_audit_pre_impl_review_coverage` reads `metrics/...` as bare relative path while `persist_review_findings` writes `${root}/metrics/...`** | `quantum-loop.sh::_audit_pre_impl_review_coverage` uses `local csv="metrics/pre-impl-review-findings.csv"` (CWD-relative). `persist_review_findings` writes via an explicit `$root` parameter. If `quantum-loop.sh --audit` is invoked from a non-repo-root CWD, the CSV is silently "missing" even when it exists. | 75 | All 6 existing `_audit_*` helpers also use bare relative paths, so the new helper is consistent with established convention — but inconsistent with the `persist_review_findings` API. Either (a) make `_audit_pre_impl_review_coverage` resolve repo root via `git rev-parse --show-toplevel`, or (b) document explicitly in `quantum-loop.sh` header that `--audit` MUST be invoked from the repo root and exit 2 if not. 0.5 stories. |
| **G25: `agents/conflict-auditor.md` Step 4 sort-order doesn't enumerate `none` or `warning`** | The sort instruction reads "Sort the `fileConflicts` array by severity (high first, then medium, then low)" — written when only those 3 severities existed. Rule 0 (PR #60) added `none`; Rule 0.5 (this PR's US-006) added `warning`. Neither addition updated the sort prose. Agents following the instruction literally have indeterminate ordering for `none` and `warning` entries. | 75 | Update the sort instruction to enumerate all 5 severities: e.g., `high → medium → low → warning → none`. Tighten reproducibility. 0.25 stories. |
| **G26: `do_audit` summary line `"X/Y metrics on target"` counts WARN as on-target** | Pre-v0.7.0, every audit metric was binary OK-or-FAIL, so "X/Y on target" was accurate. PR #64's G17 (US-005) added the first WARN-capable metric (`pre-impl-review-coverage`). `do_audit`'s `ok_count` increments for any non-`FAIL` row — meaning a WARN row is counted as on-target. Test 33 asserts `'Summary: .*7 metrics on target'` for the WARN case, locking in the misleading wording. The committed `.omc/phase-N-evidence/v0.7.0-audit.log` already shows the contradiction. | 75 | Either (a) split the summary into two counts: `Summary: 6/7 metrics OK, 1 WARN, 0 FAIL.` Or (b) reframe "on target" semantics to mean "not FAIL" and add a one-line legend. (a) is more accurate; (b) is closer to existing wording. Update Test 33 in `tests/test_audit.sh` to match the new wording. 0.5 stories. |
| **G27: `agents/spec-reviewer.md` plan-review checklist still inlines the test-pattern regex** | G14/US-003's "single source of truth" intent (`SPRINT_CONTRACT_TEST_REGEX` in `lib/handoff.sh`) updated 4 enumerated consumers. But `agents/spec-reviewer.md` plan-review mode checklist (line 117) also enumerates the same regex inline (`testFirst command consistency` checklist item: `test_`, `.test.`, `pytest`, `^bash tests/`, `^npm test`, `spec`). The constant's consumer comment doesn't mention this 5th site. | 75 | Update `agents/spec-reviewer.md` plan-review checklist to reference `lib/handoff.sh::SPRINT_CONTRACT_TEST_REGEX` instead of inlining. Update `lib/handoff.sh` consumer comment to add `agents/spec-reviewer.md` to the consumer list. 0.25 stories. |

## NEW gaps surfaced by design-doc-vs-shipped audit (post-release)

After v0.6.4 shipped, a design-doc-vs-shipped audit cross-referenced the bundle's design doc + PRD + per-story acceptance criteria against the actual merged commits, post-merge review findings, and the orchestrator's execution evidence. This surfaced one process-quality gap distinct from the code findings above:

| Gap | Symptom | Where seen | Suggested fix |
|---|---|---|---|
| **G28: Risk-mitigation language was insufficient to prevent the soliton-detected flock race** | The v0.6.4 design doc §"Risk + mitigations" listed: *"US-002 CSV append race when 2 SKILLs run concurrently → Use `flock`-style atomic append via `lib/json-atomic.sh::write_quantum_json` pattern (a small shim that wraps `flock -x` around the append). Document as US-002 test fixture."* The implementer correctly added `flock -x` around the row append — but left the header bootstrap (`[[ ! -s "$csv" ]]; printf ... > "$csv"`) OUTSIDE the locked region. Soliton review caught this at confidence 90 (see G23-superseding analysis); now fixed in `c89ba13`. The design-doc language ("flock-style atomic append") was not specific enough to prevent the failure mode. | `docs/plans/2026-04-26-v0.7.0-bundle-design.md` §Risk + mitigations row 2; soliton finding #1 confirmation | Add a `references/risk-mitigation-language.md` (or extend `references/edge-cases.md`) with a checklist for risk-mitigation prose in design docs. Specifically for concurrency: "exclusive critical section MUST cover ALL observably-coupled operations, not just the obvious mutator (e.g., header bootstrap + row append, not just row append; check-then-truncate + check-then-write, not just the truncate)." The pattern is general: any "X-style" mitigation prose should enumerate the operations to be wrapped, not just the technique. 1 doc story (≤0.5 days). |

The audit also confirmed two design-vs-execution gaps that are NOT new G-items but worth surfacing for v0.6.5 planning:

- **`ql-deep-review` was skipped at the Wave-2 boundary.** The design doc explicitly listed: *"Whole-feature (after Wave 2): invoke `ql-deep-review` at HIGH or CRITICAL tier. Cross-provider critic via P5.B1 routing."* The orchestrator went straight from US-005 → US-007 without invoking it. PIPELINE_REPORT_v5 §"Module Timing" shows 0/0 invocations across all hardening modules. Post-merge `/code-review:code-review` + `/soliton:pr-review` covered some of the same ground (and surfaced the soliton race finding), so the gap was not catastrophic — but the v0.6.5 cycle should reinstate `ql-deep-review` invocation at the wave-N boundary, OR explicitly document why it's deferred per release.
- **G14's "4 call sites" enumeration in the design doc was incomplete.** The 5th call site (agents/spec-reviewer.md plan-review checklist line 117) was missed. Captured as G27 above and bumped in the v0.6.5 priority list below.

## Recommendation for v0.6.5 / next bundle

**Highest leverage v0.6.5 candidates (in order):**
1. **G26** — fix misleading `--audit` summary (the WARN-counted-as-on-target contradiction is user-facing and the test locks it in).
2. **G27** — close G14's single-source-of-truth gap with the 5th regex copy in spec-reviewer.md (bumped per design-doc audit; small fix, clean win, closes a known incomplete enumeration).
3. **G25** — extend conflict-auditor sort enumeration to cover `none` + `warning`.
4. **G28** — write `references/risk-mitigation-language.md` checklist; cite from design-doc template. Process-quality fix to prevent another soliton-driven post-merge fix loop.
5. **G18** — audit drill copy improvement (trivial; closes the "is the audit broken?" reaction; enables G26 to be wedded to a clearer drill).
6. **G20** — self-modifying caveat README note (trivial; one-time documentation debt).
7. **First end-to-end populated-CSV run** — explicitly invoke `/ql-brainstorm` → `/ql-spec` → `/ql-plan` on a v0.6.5+ planning cycle. The first run will be the first to populate `metrics/pre-impl-review-findings.csv`. This is a process step, not a story.

~~**G23**~~ (flock-fallback race) was addressed inline in v0.6.4 commit `c89ba13` after `/soliton:pr-review` surfaced it at confidence 90 plus a related jq-failure abort guard at confidence 85. Closed.

**Deferred to v0.6.x or v0.7.x:**
- **G19** (3 SKILL wrappers identical-by-design) — revisit only if a 4th pre-impl-review stage is ever added.
- **G21** (metrics rotation) — premature optimization until the CSV has accumulated >100 rows.
- **G22** (severity rubric calibration) — explicitly blocked on ≥1 release of CSV data accumulating; cannot be calibrated against zero data.
- **G24** (audit relative-path inconsistency) — consistent with all 6 existing audit helpers; not strictly a bug. Can either be fixed alongside G26 or deferred indefinitely.
- **`ql-deep-review` reinstatement** — track for v0.6.5 OR document a per-bundle decision rule (e.g., "skip when `risk-scorer` < MEDIUM").
- **P5.B2 / B3 / B5** and **P5.C\*** — same as v4 verdict.

## Promotion gate: pre-impl-review advisory → blocking

This is the central question for the v0.6.x line. The v0.6.4 bundle deliberately landed instrumentation (G13 persistence + G16 rubric + G17 audit) WITHOUT promoting any stage from advisory to blocking. **Explicit policy: blocking-promotion of any pre-impl-review stage defers until ≥1 release of CSV baseline data accumulates.**

The reason is empirical: without real finding-severity distributions, picking a blocking threshold is guesswork. Examples of decisions blocked on data:
- "How many `critical` findings per design-review run is normal?" — Need histogram.
- "What's the false-positive rate on `medium` findings?" — Need post-hoc operator-marked false-positive flags.
- "Do `prd-review` `critical` findings predict downstream story failure?" — Need correlation against `quantum.json.retries.failureLog`.

The first such retrospective should happen no earlier than v0.7.2 (i.e., after at least one populated-CSV release). v0.7.1 should ship G18+G20 + whatever else surfaces, NOT a promotion decision.
