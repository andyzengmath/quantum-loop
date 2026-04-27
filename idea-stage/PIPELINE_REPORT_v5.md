# PIPELINE_REPORT_v5 — v0.7.0-bundle dogfood (US-007 retrospective)

**Date:** 2026-04-27
**Branch:** `ql/v0.7.0-bundle`
**Plan size:** 7 stories across 4 waves
**Outcome:** 7/7 user-facing stories PASSED first attempt; final story (US-007) is this retrospective + version bump
**Pipeline mode:** sequential (orchestrator self-modifying caveat — see §3)
**Minor tier:** v0.6.3 → 0.7.0 (no breaking changes; all mechanisms additive/opt-in)

## Wave plan and timing

| Wave | Stories | Mode | Outcome |
|---|---|---|---|
| **wave-0** | US-001, US-003, US-004, US-006 (4) | Sequential | 4/4 PASS first attempt |
| **wave-1** | US-002 (depends on US-001 + US-003) | Sequential | 1/1 PASS first attempt |
| **wave-2** | US-005 (depends on US-002) | Sequential | 1/1 PASS first attempt |
| **wave-3** | US-007 (retrospective + version bump) | Sequential | this report |

The bundle ran across **3 orchestrator instances** (each iteration cap-bound):
- **Run 1** completed Wave 0 stories US-001 + US-003 (commits `ba9b7cb`, `a09925f`).
- **Run 2** completed Wave 0 stories US-004 + US-006 (commits `05d28e5`, `77bef42`); started US-002 with partial implementation (lib/finding-persist.sh + tests/test_finding_persist.sh written, 8/10 assertions passing — the 2 RED ones being the SKILL-wire grep needles that T-003-T-005 were designed to flip GREEN).
- **Run 3** (this run) finished US-002 from T-003 onward (3 SKILL wires + .gitignore), executed US-005 (Wave 2), and wrote US-007 (Wave 3 retrospective + version bump).

**Cumulative wall-clock to wave-2 completion: ~70 minutes** across 3 orchestrator runs for 6 user-facing stories. 0 retries, 0 cross-story contract violations, 0 merge conflicts.

## Files changed (all 7 stories)

| Layer | Files |
|---|---|
| **Lib** | `lib/finding-synth.sh` (NEW, 224 lines), `lib/finding-persist.sh` (NEW, 218 lines), `lib/handoff.sh` (SPRINT_CONTRACT_TEST_REGEX constant added) |
| **Agents** | `agents/orchestrator.md` (Step 2.5 sources lib/handoff.sh + jq --arg pattern), `agents/spec-reviewer.md` (3 cross-link lines), `agents/dag-validator.md` (§5d CHANGELOG ownership convention), `agents/conflict-auditor.md` (Rule 0.5 severity override) |
| **Skills** | `skills/ql-brainstorm/SKILL.md` (Phase 4d wrapper), `skills/ql-spec/SKILL.md` (post-prd-review wrapper), `skills/ql-plan/SKILL.md` (Step 8 regex source + Step 9 plan-review wrapper) |
| **Entrypoints** | `quantum-loop.sh` (_audit_pre_impl_review_coverage helper + 7th ROW), `quantum-loop.ps1` (PS1/SH parity divergence comment) |
| **Refs/docs** | `references/finding-severity.md` (NEW, 3-mode rubric), `references/sprint-contract.md` (constant ref) |
| **Tests** | 4 NEW (`test_finding_synth.sh` 31, `test_finding_persist.sh` 37, `test_finding_severity.sh` 14, `test_changelog_ownership.sh` 9), 3 extended (`test_sprint_contract.sh` +2, `test_sprint_contract_ql_plan.sh` rewired, `test_audit.sh` +6) |
| **Manifests** | `.claude-plugin/plugin.json`, `.claude-plugin/marketplace.json` (×2 fields), `.cursor-plugin/plugin.json` (4 version fields total, all `0.6.3 → 0.7.0`) |
| **Config** | `.gitignore` (`.handoffs/*-review-findings.json` rule); CHANGELOG.md (v0.7.0 entry) |
| **Evidence** | `.omc/phase-N-evidence/v0.7.0-audit.log`, `.omc/phase-N-evidence/v0.7.0-test-suite.log` |

## Per-wave findings

### Wave-0 (4 stories — clean fan-out, zero conflicts)

All 4 stories targeted disjoint file groups:
- **US-001 (G12)**: `lib/finding-synth.sh` (NEW), `tests/test_finding_synth.sh` (NEW). Pure parser library.
- **US-003 (G14)**: `lib/handoff.sh`, `agents/orchestrator.md`, `skills/ql-plan/SKILL.md` Step 8, `tests/test_sprint_contract.sh`, `tests/test_sprint_contract_ql_plan.sh`, `references/sprint-contract.md`. DRY refactor consolidating an inline regex into a single readonly constant.
- **US-004 (G16)**: `references/finding-severity.md` (NEW), `agents/spec-reviewer.md` (3 cross-links), `tests/test_finding_severity.sh` (NEW). Doc-heavy story with structural tests.
- **US-006 (G15)**: `agents/dag-validator.md`, `agents/conflict-auditor.md`, `tests/test_changelog_ownership.sh` (NEW). LLM-prompt rule documentation; rule text IS the testable artifact.

**Zero merge conflicts.** The fileConflicts table flagged `skills/ql-plan/SKILL.md` as severity:low (US-002 vs US-003 different sections, different waves) and `agents/spec-reviewer.md` as severity:none (US-004 sole consumer); both held.

**Test outcomes** (TDD RED→GREEN visible per story):
- US-001: 31/31 finding-synth (10 happy-path + 8 mixed-severity counts + 7 malformed-block + 6 CLI-mode)
- US-003: 18/18 sprint-contract (16 baseline + 2 no-inline-regex new) + 13/13 sprint-contract-ql-plan (rewired)
- US-004: 14/14 finding-severity (3 mode sections + 4 severity rows × 3 + cross-link anchors)
- US-006: 9/9 changelog-ownership (3 fixture plans × 2 + 2 doc-grep + 1 conflict-auditor rule grep)

### Wave-1 (US-002 — single-story; biggest story of the bundle by complexity)

US-002 is the bundle's keystone: it consumes US-001's parser (`source lib/finding-synth.sh`) and edits the same file US-003 already modified — but a different region (US-003 = Step 8 sprint-contract regex; US-002 = Step 9 plan-review wrapper). The dag-validator's `dependsOn` correctly serialized US-002 after US-003 even though file-conflict severity was "low".

**The story's 7 tasks form a 3-layer build:**
1. T-001/T-002: lib + RED tests (pure file artifacts).
2. T-003/T-004/T-005: 3 SKILL wires (Phase 4d / post-prd-review / Step 9), all using the same wrapper shape: `mktemp` → `claude --headless 2> $LOG` → source libs → `parse_findings` → `summarize_findings` → `persist_review_findings` → `format_summary_line` → `cat $LOG` → `rm $LOG`.
3. T-006/T-007: `.gitignore` + final verification.

**One harness wrinkle worth recording:** the 3 SKILL wires are intentionally identical wrappers. Centralizing into a helper lib was tempting but rejected — the 9 grep-needle assertions in `test_finding_persist.sh::Test10` are precisely the regression guard against drift. If a future change reworded any of the three wrappers asymmetrically, the test fails before the inconsistency reaches a release. **Pattern logged**: when N parallel sites share a contract, prefer N copies guarded by N grep assertions over 1 helper that obscures the contract.

**Test outcomes:** 37/37 finding-persist (10 test groups including snapshot schema, CSV header-once + flock append, idempotent overwrite, 3-stage E2E, missing-dir auto-create, missing-file→{}, stage validation, .gitignore wires, 9 SKILL grep needles).

### Wave-2 (US-005 — audit metric)

The G17 helper `_audit_pre_impl_review_coverage` introduced a third audit-row state: **WARN**, alongside OK and FAIL. The choice was deliberate — the metric measures **operator pipeline-engagement** (did they run reviews?), not **codebase health** (does the codebase compile?). FAILing the audit on a fresh checkout would punish operators for running `quantum-loop.sh` on a clean repo. **Pattern logged**: any new --audit metric measuring operator engagement (vs. codebase health) should use WARN states; FAIL is reserved for measurable codebase regressions.

The summary line auto-updated from 6/6 to 7/7 because `do_audit`'s loop tracks `total++` per row dynamically — no hardcoded count needed updating beyond the test 23 expectation.

**Test outcomes:** 36/36 audit (24 baseline + 3 PR #56 review-followup + 6 G17 4-state coverage + 3 ones whose expectations flipped from 6/6 → 7/7).

## Cross-story contract events

`contracts.shared_types` and `contracts.shared_constants` declared 4 relevant entries pre-execution:
- `review_finding_stage` enum `^(design|prd|plan)$` — consumed by US-002 (filename suffix + CSV column) and US-005 (state-counting). Both honored the closed enum exactly.
- `sprint_contract_test_regex` value lookup → `lib/handoff.sh::SPRINT_CONTRACT_TEST_REGEX` — consumed by US-002 (which inherited the clean ql-plan SKILL.md Step 8 from US-003's refactor) and US-003 (the producer). All 4 historical inline copies replaced.
- `ql_skip_pre_impl_review` env-var pattern `^([a-z]+(,[a-z]+)*)?$` — consumed by US-002 (kept the v0.6.3 advisory-stage gate intact in all 3 wrappers).
- `pre_impl_review_findings_csv` schema — consumed by US-002 (writer) and US-005 (reader). Header row `timestamp,stage,source_path,count,critical,high,medium,low` written once on first append; never duplicated.

**Zero contract violations.**

## Pre-impl review baseline

This is the headline self-modifying-orchestrator caveat for v0.7.0:

**`metrics/pre-impl-review-findings.csv` is empty after this run.** The file does not exist in the repo at the end of Wave-2 because:
1. The orchestrator runs on **v0.6.3 master HEAD semantics** (the v0.7.0 wires apply to NEXT runs only).
2. Even if v0.7.0's wires were active, the bundle didn't run `/ql-brainstorm`, `/ql-spec`, or `/ql-plan` during execution — those skills produce findings only when invoked. Quantum-loop's planning happened pre-execution by hand.

The audit log at `.omc/phase-N-evidence/v0.7.0-audit.log` confirms this: `pre-impl-review-coverage: 0/3 stages WARN missing-csv`. **This is correct behavior, not a regression.** v0.7.1's first end-to-end run (planning + execution under the v0.7.0-installed wires) will be the first to populate the CSV.

**Promotion of any pre-impl-review stage from advisory → blocking should wait until ≥1 release of CSV baseline data accumulates.** Without empirical severity-distribution data, picking a blocking threshold is guesswork.

## Test-suite delta

**+97 new assertions** across 7 test files. Zero regressions in pre-existing suites:

| Test file | Baseline | After v0.7.0 | Delta |
|---|---|---|---|
| `test_finding_synth.sh` | — (NEW) | 31 | +31 |
| `test_finding_persist.sh` | — (NEW) | 37 | +37 |
| `test_finding_severity.sh` | — (NEW) | 14 | +14 |
| `test_changelog_ownership.sh` | — (NEW) | 9 | +9 |
| `test_sprint_contract.sh` | 16 | 18 | +2 (no-inline-regex assertions) |
| `test_sprint_contract_ql_plan.sh` | 13 | 13 | 0 (rewired internally; count unchanged) |
| `test_audit.sh` | 30 | 36 | +6 (G17 4-state coverage) |

Approximate cumulative project total: ~1,640 → ~1,737. Pre-existing suites (`test_handoff.sh` 38, `test_spec_review_design.sh` 14, `test_spec_review_prd.sh` 13, `test_spec_review_plan.sh` 13) all GREEN — verified during US-002 T-007 verification gate.

## codebasePatterns harvested

**1 new pattern** added to `quantum.json.codebasePatterns`:

- **p006 — Single source of truth for shell constants.** When a regex or pattern is duplicated in N>1 places, extract to a readonly constant in the most-imported lib (e.g., `lib/handoff.sh`) and have all call sites source + reference. Use `jq --arg pattern` injection rather than inlining the regex. Discovered in v0.7.0 / US-003 (G14). Applicable when: any regex/pattern duplicated in 2+ files.

5 prior patterns (p001-p005) carried forward unchanged.

## Self-modifying-orchestrator caveat

The orchestrator that drove this execution ran on the v0.6.3 codebase semantics — specifically:
- `agents/orchestrator.md` from commit `33e569e` (master HEAD).
- The pre-impl-review wrappers in `skills/ql-brainstorm/SKILL.md`, `skills/ql-spec/SKILL.md`, `skills/ql-plan/SKILL.md` are the v0.6.3 advisory-only versions during planning, NOT the v0.7.0 instrumented versions that this bundle just installed.

**v0.7.0's persistence and audit instrumentation apply to runs starting AFTER this commit lands on master.** That is the source of the empty CSV. It is also why "missing-csv WARN" is the correct exit state for the audit — the audit metric reflects empirically what's been logged, not aspirationally what the new code can log.

This caveat has surfaced consistently across v0.6.0/v0.6.3/v0.7.0 retrospectives: the orchestrator implementing a feature cannot, within the same run, exercise the feature it just installed. Future planners should continue to expect the first-run CSV / metrics / audit-trail signals from each release to land in v_<x.y.z>+1's first execution.

## Open frontier (carried to IDEA_REPORT_v5)

P5.B2/B3/B5 (additional spec-reviewer modes, severity-distribution observability) and P5.C* (code-review reachability metrics) remain open. The v0.7.0 finding-persist + audit instrumentation IS the foundation for converting any pre-impl-review stage from advisory to blocking; the prerequisite is real CSV data from ≥1 v0.7.1+ run. See `idea-stage/IDEA_REPORT_v5.md` for the full open-gap list.
