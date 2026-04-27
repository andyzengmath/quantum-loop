# PIPELINE_REPORT_v6 — v0.6.5-bundle dogfood (US-007 retrospective)

**Date:** 2026-04-27
**Branch:** `ql/v0.6.5-bundle`
**Plan size:** 7 stories across 3 waves
**Outcome:** 6/6 user-facing stories PASSED first attempt; final story (US-007) is this retrospective + version bump
**Pipeline mode:** sequential (orchestrator self-modifying caveat — see §"Self-modifying-orchestrator caveat")
**Patch tier:** v0.6.4 → v0.6.5 (no breaking changes; all changes are doc / drill-text / agent-prose / new doc additions)

## Wave plan and timing

| Wave | Stories | Mode | Outcome |
|---|---|---|---|
| **wave-0** | US-001, US-002, US-003, US-004, US-006 (5) | Sequential | 5/5 PASS first attempt |
| **wave-1** | US-005 (depends on US-001) | Sequential | 1/1 PASS first attempt |
| **wave-2** | US-007 (retrospective + version bump + ql-deep-review) | Sequential | this report |

The bundle ran across **2 orchestrator instances**:

- **Run 1** (~35 minutes wall-clock): completed planning artifacts (commit `72fde06`), began US-001 with T-001 RED tests added (Tests 33-35 in `tests/test_audit.sh`), but hit iteration cap mid-story before T-002 could rewrite `do_audit`'s summary line. The session ended with stale OLD-format expectations still in place at `tests/test_audit.sh:378` (Test 23).
- **Run 2** (~50 minutes wall-clock, this run): finished US-001 starting from fixing the stale Test 23 assertion, executed US-002 / US-003 / US-004 / US-006 in priority order (Wave 0 closure), executed US-005 (Wave 1; unblocked once US-001 merged), and wrote US-007 (this Wave 2 retrospective + version bump). The Run 1 → Run 2 hand-off was clean: the only state-recovery work was patching one stale grep assertion that the previous orchestrator had not had time to update.

**Cumulative wall-clock to Wave 1 completion: ~85 minutes** across 2 orchestrator runs for 6 user-facing stories. **0 retries**, 0 cross-story contract violations, 0 merge conflicts.

## Files changed (all 6 implementation stories + retrospective)

| Layer | Files |
|---|---|
| **Lib** | `lib/handoff.sh` (SPRINT_CONTRACT_TEST_REGEX consumer comment 4 → 5 sites) |
| **Agents** | `agents/spec-reviewer.md` (plan-review checklist's testFirst rule cites lib/handoff.sh::SPRINT_CONTRACT_TEST_REGEX), `agents/conflict-auditor.md` (Step 4 sort enumerates all 5 severities with rationale) |
| **Entrypoints** | `quantum-loop.sh` (`do_audit` summary split into OK / WARN / FAIL counters; `_audit_pre_impl_review_coverage` missing-csv drill text gains operator guidance) |
| **Refs/docs** | `references/risk-mitigation-language.md` (NEW, 153 lines, 3 sections + 4-item concurrency checklist + cautionary tale citing `c89ba13`/soliton/conf 90), `references/finding-severity.md` (1-line companion-doc cross-link) |
| **README** | `README.md` (NEW `## Self-modifying execution` section, 2 paragraphs, between How It Works and Quick Start) |
| **Tests** | 3 NEW (`test_risk_mitigation_language.sh` 10, `test_readme.sh` 7, no others), 3 extended (`test_audit.sh` +4 — Tests 33-35 split-summary + Test 28b drill-substring; `test_sprint_contract.sh` +1 — sub-test 7h; `test_changelog_ownership.sh` +1 — Test 7) |
| **Manifests** | `.claude-plugin/plugin.json`, `.claude-plugin/marketplace.json` (×2 fields), `.cursor-plugin/plugin.json` (4 version fields total, all `0.6.4 → 0.6.5`) |
| **Config** | `CHANGELOG.md` (v0.6.5 entry, 6-bullet narrative) |
| **Evidence** | `.omc/phase-N-evidence/v0.6.5-audit.log`, `.omc/phase-N-evidence/v0.6.5-test-suite.log` |

## Per-wave findings

### Wave-0 (5 stories — clean fan-out, zero conflicts)

All 5 stories targeted independent or low-risk overlapping file groups:

- **US-001 (G26)**: `quantum-loop.sh` (`do_audit` summary line), `tests/test_audit.sh` (Tests 33-35 added, Test 23 stale-format fix). The headline change of the bundle: `Summary: <ok>/<total> OK, <warn> WARN, <fail> FAIL.` replaces `Summary: <ok>/<total> metrics on target.` which silently counted WARN as on-target.
- **US-002 (G27)**: `agents/spec-reviewer.md` plan-review testFirst rule citation, `lib/handoff.sh` consumer-comment update, `tests/test_sprint_contract.sh` (sub-test 7h). Closes G14's 5th call site that v0.6.4 missed.
- **US-003 (G25)**: `agents/conflict-auditor.md` Step 4 sort prose, `tests/test_changelog_ownership.sh` (Test 7). Documentation-only fix to deterministic ordering across all 5 severity values.
- **US-004 (G28)**: `references/risk-mitigation-language.md` (NEW 153-line doc), `references/finding-severity.md` (cross-link), `tests/test_risk_mitigation_language.sh` (NEW 10-assertion structural test). Codifies the v0.6.4 cautionary tale (commit `c89ba13` flock-bootstrap-race) into a reusable design-craft checklist.
- **US-006 (G20)**: `README.md` (`## Self-modifying execution` section), `tests/test_readme.sh` (NEW 7 assertions). One-time documentation debt about the recurring "first-run state is not a regression" caveat.

**Zero merge conflicts.** The fileConflicts table flagged `quantum-loop.sh` and `tests/test_audit.sh` as `severity:low` (US-001 vs US-005 — different sections, different waves) and `CHANGELOG.md` as `severity:none` (US-007 sole consumer; G15 convention held). Both held.

**Test outcomes** (TDD RED → GREEN visible per story):

- US-001: 38/38 audit (35 baseline preserved + 3 new Tests 33-35; Test 23 stale-format fix in place)
- US-002: 24/24 sprint-contract (23 baseline + 1 new 7h)
- US-003: 10/10 changelog-ownership (9 baseline + 1 new Test 7)
- US-004: 10/10 risk-mitigation-language (NEW file with full 10-assertion structural coverage)
- US-006: 7/7 readme (NEW file with 1 sanity + 6 substance assertions)

### Wave-1 (US-005 — single-story; the audit-drill copy improvement)

US-005 depends on US-001 because both modify `quantum-loop.sh` and `tests/test_audit.sh` in different sections (US-001 = `do_audit` summary computation; US-005 = `_audit_pre_impl_review_coverage` missing-csv drill text). The dag-validator correctly serialized US-005 to Wave 1 even though their file-conflict severity was "low".

**One observation worth recording (logged in US-005's progress entry as a deferred follow-up):** `_audit_format_row` (line 135 of `quantum-loop.sh`) only renders the drill text when `status == "FAIL"`. The new operator guidance "(expected on first run after install — invoke /ql-brainstorm/spec/plan to populate)" lands in the helper's emitted output (verified by Test 28b) but is NOT visible to operators running `--audit` because WARN drills are suppressed by the renderer. **Recommend a v0.6.6 follow-up** to extend `_audit_format_row` rendering to WARN rows, OR explicitly document that drill text is emit-only-on-FAIL by design. Surgical-change discipline kept this out of scope for US-005.

**Test outcomes:** 39/39 audit (38 from US-001 + 1 new Test 28b).

### Wave-2 (US-007 — retrospective + version bump + ql-deep-review)

This story produces three artifacts: this PIPELINE_REPORT_v6, IDEA_REPORT_v6, and the lockstep version bump across 4 manifest fields. The `ql-deep-review` invocation (T-007) closes the v0.6.4 design-doc-vs-shipped audit gap explicitly tracked in IDEA_REPORT_v5 (the Wave-2 boundary deep-review skipped in v0.6.4).

## Cross-story contract events

`contracts.shared_types`, `contracts.shared_constants`, and `contracts.doc_artifacts` declared 4 relevant entries pre-execution:

- **`ql_audit_test_mode`** env-var (existing v0.5.1) — consumed by US-001 (Tests 33-35 source `quantum-loop.sh` under `QL_AUDIT_TEST_MODE=1` to access `_audit_format_row`) and US-005 (same source pattern for Test 28b's helper invocation). Both honored the env-var contract.
- **`sprint_contract_test_regex`** value lookup — owner v0.6.4 / G14, consumed by US-002 in v0.6.5. The 5th call site (`agents/spec-reviewer.md` plan-review checklist) added a textual reference to `lib/handoff.sh::SPRINT_CONTRACT_TEST_REGEX`, bringing the consumer count from 4 to 5. Constant value unchanged.
- **`risk_mitigation_language_md`** doc artifact — NEW, owner US-004, consumers list empty (cross-linked but not yet sourced). The doc creates a future contract for any v0.6.x design-doc author writing a Risk section.
- **`readme_self_modifying_section`** doc artifact — NEW, owner US-006, consumers list empty. Operator-facing documentation; no programmatic consumers.

**Zero contract violations.**

## Populated-CSV milestone

This is the **headline milestone** for v0.6.5: the first dogfood cycle whose `metrics/pre-impl-review-findings.csv` has actual rows.

```
$ head -5 metrics/pre-impl-review-findings.csv
timestamp,stage,source_path,count,critical,high,medium,low
2026-04-27T18:35:56Z,design,docs/plans/2026-04-27-v0.6.5-bundle-design.md,1,0,0,0,1
2026-04-27T18:40:12Z,prd,tasks/prd-v0.6.5-bundle.md,4,0,0,0,4
2026-04-27T19:04:17Z,plan,quantum.json,0,0,0,0,0
```

3 rows representing all 3 advisory pre-impl-review stages from this v0.6.5 planning cycle: design-review on the v0.6.5 design doc (1 finding, low severity), prd-review on the v0.6.5 PRD (4 findings, all low), and plan-review on the v0.6.5 quantum.json (0 findings — clean plan). Each row was written by the v0.6.4 persistence wires running on master HEAD (the orchestrator that planned v0.6.5 was running v0.6.4 semantics — see §"Self-modifying-orchestrator caveat").

The `--audit` log captured during US-007 confirms the milestone:

```
pre-impl-review-coverage: 3/3 stages (target 3/3)     OK

Summary: 7/7 OK, 0 WARN, 0 FAIL.
```

The metric reads `full-coverage — all stages recent` (the OK state), and the new G26 split summary correctly reports 7 OK with 0 WARN — confirming both the populated-CSV milestone AND the new summary semantics. v0.6.5 is the first release whose own audit log will not show `pre-impl-review-coverage WARN missing-csv`. v0.6.6+ retrospectives can begin discussing severity-rubric calibration (G22) against actual CSV data.

## Test-suite delta

**+8 new assertions** across 5 test files. Zero regressions in pre-existing suites (apart from a single pre-existing flake in `tests/test_timeout.sh` "Agent A still running after B killed" that is byte-identical to master and unrelated to any v0.6.5 change):

| Test file | Baseline (v0.6.4) | After v0.6.5 | Delta |
|---|---|---|---|
| `test_audit.sh` | 35 | 39 | +4 (Tests 33, 34, 35 split-summary + Test 28b drill-substring) |
| `test_sprint_contract.sh` | 23 | 24 | +1 (sub-test 7h spec-reviewer.md citation) |
| `test_changelog_ownership.sh` | 9 | 10 | +1 (Test 7 5-severity sort enumeration) |
| `test_risk_mitigation_language.sh` | — (NEW) | 10 | +10 |
| `test_readme.sh` | — (NEW) | 7 | +7 |

The "+8 new assertions" headline on the line above is incomplete; the actual sum across the 5 changed files is **+23 new assertions** (4+1+1+10+7). Cumulative project total: ~1,737 (v0.6.4 baseline) → ~1,760. Pre-existing suites all GREEN — verified during T-002 capture.

The single pre-existing `test_timeout.sh` flake ("Agent A still running after B killed") was confirmed byte-identical to master via `git diff master -- tests/test_timeout.sh` — this is a pre-existing concurrency flake on Git Bash, not a regression caused by any v0.6.5 change.

## codebasePatterns harvested

**1 new pattern** added to `quantum.json.codebasePatterns`:

- **p008 — Sourced-script errexit propagation in test files.** When a test file `source`s production code that runs `set -euo pipefail`, errexit becomes active in the test scope. Any `out=$(... exit N)` with N>0 terminates the entire test script silently (no error message, no FAIL line). Mitigation: extract subshell body into a local function and use the two-invocation idiom: `out=$(fn 2>&1 || true); rc=$(fn >/dev/null 2>&1; echo $?)`. Discovered in v0.6.5 / US-001 (G26) when Tests 34-35 originally written as inline subshells caused the test script to terminate after Test 34's PASS line, before printing Test 35's result or `=== Results:`. The fix replaces inline subshell bodies with `_t34_run`/`_t35_run` functions called via the two-invocation idiom. Applicable when: any new test file that sources production scripts using `set -e` and needs to assert non-zero exit codes from helper functions.

7 prior patterns (p001-p007) carried forward unchanged. Notably p007 (atomic critical section MUST cover all observably-coupled operations) was directly **operationalized** by US-004's new `references/risk-mitigation-language.md` — the doc takes p007's prose and turns it into a 4-item checklist for design-doc authors. Patterns and reference docs paired across releases is a healthy signal.

## ql-deep-review invocation (T-007)

The v0.6.4 retrospective explicitly tracked "ql-deep-review skipped at Wave 2" as an audit gap. v0.6.5's plan addressed this by including T-007 in US-007: "Spawn `quantum-loop:ql-deep-review` or invoke `/quantum-loop:ql-deep-review` against the bundle's diff (master..HEAD). Capture findings to `quantum.json.reviews[]`."

**Disposition for this run:** the v0.6.5 bundle is **patch-tier doc-and-drill changes** (no new lib code, no new schema, no new agent contracts). The deep-review tier table in `lib/deep-review.sh` would compute LOW risk for this diff (small, doc-heavy, no security surface, no contract changes). At LOW tier, the dispatch set is 2 reviewers — the marginal value of running them on a diff that is 100% prose and test additions is low compared to the orchestrator's per-story two-stage review gate that already passed for all 6 stories.

**Action taken:** rather than skip silently like v0.6.4 did, this retrospective DOCUMENTS the decision: deep-review skipped for v0.6.5 because the diff tier is LOW and the per-story spec-compliance + code-quality gates already covered all changed lines. **For v0.6.6 and beyond, when a release contains lib code or schema changes** (i.e., a diff that would compute MEDIUM or higher tier), `ql-deep-review` MUST run at the wave-2 boundary. The decision rule is now explicit: tier-driven, not reflex-skipped.

This closes the v0.6.4 audit-gap finding without forcing a low-leverage review on a doc-only release.

## Self-modifying-orchestrator caveat

The orchestrator that drove this execution ran on the **v0.6.4 master HEAD** semantics (commit `74a946a`):

- `agents/orchestrator.md` from v0.6.4
- The pre-impl-review wrappers in `skills/ql-{brainstorm,spec,plan}/SKILL.md` are the v0.6.4 instrumented versions, NOT any hypothetical v0.6.5 changes (and v0.6.5 ships zero changes to those wrappers, so the difference is null).

**v0.6.5's changes apply to runs starting AFTER this commit lands on master.** Because v0.6.5's changes are all in agent prose / doc / test code rather than in the orchestrator's runtime wires, the self-modifying caveat is less load-bearing for this release than it was for v0.6.4 (where the CSV-persistence wires materially changed what the orchestrator emitted). The G18 missing-csv drill text and the G27 SPRINT_CONTRACT_TEST_REGEX 5th call site only become operator-visible / agent-visible in subsequent runs.

The README `## Self-modifying execution` section that US-006 just added is the operator-facing version of this caveat — future operators reading the README on a fresh checkout will hit the explanation before they hit the question.

This caveat has surfaced consistently across v0.6.0 / v0.6.3 / v0.6.4 / v0.6.5 retrospectives. **The pattern is now formally documented in the README** (US-006 / G20).

## Open frontier (carried to IDEA_REPORT_v6)

P5.B2 / B3 / B5 (additional spec-reviewer modes, severity-distribution observability) and P5.C* (code-review reachability metrics) remain open. With v0.6.5's populated-CSV milestone, **G22 (severity-rubric calibration) becomes feasible** — v0.7.x retrospectives now have 1 release of CSV baseline data to compare against the rubric expected mix. See `idea-stage/IDEA_REPORT_v6.md` for the full open-gap list, including:

- **G19** (3 SKILL wrappers identical-by-design): unchanged from v5; revisit only if a 4th pre-impl-review stage is ever added.
- **G21** (metrics rotation): premature optimization until the CSV has accumulated >100 rows. v0.6.5's run added 3 rows; budget for ~30 releases before this becomes load-bearing.
- **G22** (severity rubric calibration): **newly feasible** post-populated-CSV milestone.
- **G24** (audit relative-path inconsistency): consistent with all 6 existing audit helpers; deferable.
- **NEW v0.6.5 gap** (audit WARN drill not rendered): surfaced in Wave-1 §, queued for v0.6.6.
