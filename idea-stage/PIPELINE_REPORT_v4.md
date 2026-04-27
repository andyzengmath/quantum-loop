# PIPELINE_REPORT_v4 — v0.6.3-bundle dogfood (P5.Z1 / US-009)

**Date:** 2026-04-26
**Branch:** `ql/v0.6.3-bundle`
**Plan size:** 9 stories across 4 waves
**Outcome:** 8/8 user-facing stories PASSED first attempt; 1 retrospective story (US-009) IN_PROGRESS at write time
**Pipeline mode:** sequential (orchestrator self-modifying caveat — see §3)
**Patch tier:** v0.6.2 → 0.6.3 (no breaking changes)

## Wave plan and timing

| Wave | Stories | Mode | Start | End | Duration | Outcome |
|---|---|---|---|---|---|---|
| **wave-0** | US-001, US-002, US-005, US-006, US-004 (5) | Sequential | 22:35 | 22:58 | ~23 min | 5/5 PASS first attempt |
| **wave-1** | US-003, US-007 (2) | Sequential | 22:59 | 23:06 | ~7 min | 2/2 PASS first attempt |
| **wave-2** | US-008 (1) | Sequential | 23:07 | 23:09 | ~2 min | 1/1 PASS first attempt |
| **wave-3** | US-009 (retrospective) | Sequential | 23:10 | — | ongoing | this report |

**Total wall-clock to wave-2 completion: ~34 minutes** for 8 user-facing stories.

## Files changed (Wave-0 through Wave-2)

| Layer | Files |
|---|---|
| **Agents** | `agents/orchestrator.md` (Step 2.5 jq split), `agents/spec-reviewer.md` (3 new modes: design-review, prd-review, plan-review) |
| **Lib** | `lib/runner.sh` (parse_role_arg + _availability_check role-aware; write_routing_snapshot composes with write_quantum_json), `lib/api-rename.sh` (NEW) |
| **Entrypoints** | `quantum-loop.sh` (deleted dead parse_critic_arg) |
| **Skills** | `skills/ql-brainstorm/SKILL.md` (Phase 4d design-review hook), `skills/ql-spec/SKILL.md` (post-exit prd-review hook), `skills/ql-plan/SKILL.md` (Step 8 sprint-contract write + Step 9 plan-review hook) |
| **Schema doc** | `references/sprint-contract.md` (added otherCommands optional field) |
| **Tests** | 4 new (`test_api_rename.sh`, `test_spec_review_design.sh`, `test_spec_review_prd.sh`, `test_spec_review_plan.sh`, `test_sprint_contract_ql_plan.sh`) + extended `test_cross_provider_critic_flag.sh`, `test_sprint_contract.sh`, `test_per_role_routing.sh` |

## Per-wave findings

### Wave-0 (5 stories — biggest fan-out)

The largest fan-out of the bundle. All five stories targeted distinct file groups:
- **US-001**: `quantum-loop.sh`, `lib/runner.sh`, `tests/test_cross_provider_critic_flag.sh` (G8 critic-fallback unification)
- **US-002**: `agents/orchestrator.md`, `references/sprint-contract.md`, `tests/test_sprint_contract.sh` (G9 expectedTests filter)
- **US-005**: `lib/api-rename.sh` (NEW), `tests/test_api_rename.sh` (NEW) (G2 symbol-migration helper)
- **US-006**: `agents/spec-reviewer.md`, `skills/ql-brainstorm/SKILL.md`, `tests/test_spec_review_design.sh` (P5.B4-design)
- **US-004**: `skills/ql-plan/SKILL.md`, `tests/test_sprint_contract_ql_plan.sh` (G3 wire write_sprint_contract)

**Zero merge conflicts** — Rule 0 fileConflicts severity=none classification held perfectly. The single `agents/spec-reviewer.md` collision (US-006/US-007/US-008 across waves 0/1/2) was naturally serialized by `dependsOn`, so no parallel-mode contention occurred.

**Test outcomes** (all first-attempt GREEN, with TDD RED→GREEN visible per story):
- US-001: 13 baseline + 7 new = 20/20 cross-provider critic
- US-002: 11 baseline + 5 new = 16/16 sprint-contract; handoff 38/38 unaffected
- US-005: 14/14 api-rename (pure new module)
- US-006: 14/14 design-review (12 doc + 2 behavioral)
- US-004: 13/13 sprint-contract-ql-plan (round-trip + 3 schema asserts + idempotency)

### Wave-1 (2 stories — clean dependency unblocking)

US-003 + US-007 are independent: US-003 builds on US-001 (lib/runner.sh canonicalization); US-007 builds on US-006 (prd-review mode after design-review template). No interaction.

**One harness wrinkle worth recording:**
- US-003 added a "composition" assertion (`declare -f write_routing_snapshot | grep -qF write_quantum_json`) on top of the behavioral validation-gate test. The behavioral test passed even on the un-refactored function (because the original ALSO used jq + tmp + mv); only the composition assertion proved the refactor genuinely happened. **Pattern logged**: composition tests should assert function-body content (not just behavior) to guard against future copy-paste regressions.

### Wave-2 (US-008 — three-stage P5.B4 closure)

Last of the three pre-impl-review modes. The P5.B4 trilogy (US-006/007/008) crystallized a deliberate **scaffolding-not-logic** design:
- Each mode is its own `## Mode: <name>-review` section in `agents/spec-reviewer.md`.
- Each is invoked by exactly one skill (`ql-brainstorm` / `ql-spec` / `ql-plan`) with the same env-var gate idiom.
- All three honor a single comma-separated `QL_SKIP_PRE_IMPL_REVIEW` env var with values `design,prd,plan`.

dag-validator dismissed the 0.44-0.50 Jaccard overlaps in `duplicationDismissed` ahead of time as deliberate. Confirmed: the modes share scaffolding by design but have distinct checklist semantics. No premature DRY refactor needed.

## Cross-story contract events

`contracts.shared_types` declared three relevant types pre-execution:
- `spec_reviewer_modes`: `design-review | prd-review | plan-review` — consumed by US-006/007/008. Each story honored the exact mode token.
- `sprint_contract_schema_v2`: serialized field list — consumed by US-002/004. US-002 added `otherCommands` to the schema doc; US-004's iteration logic emitted contracts with the new field. Backward-compat preserved (existing readers ignore unknown fields).
- `ql_skip_pre_impl_review` env var pattern `^([a-z]+(,[a-z]+)*)?$` — consumed by US-006/007/008. All three implementations accepted both single (`prd`) and comma-separated (`design,prd,plan`) forms.

**Zero contract violations.** The materialize-then-implement flow held throughout.

## Pre-impl review baseline

US-006/007/008 added three advisory review stages (design / PRD / plan exits). v0.6.3 ships them in **advisory-only** mode — findings emit to stderr, skills do not abort. This baseline run did NOT execute the new stages on its own design/PRD/plan because the orchestrator (running on master HEAD `33e569e` v0.6.2 baseline) doesn't yet trigger them; v0.6.3-bundle's design + PRD were authored by hand prior to this run.

**Future baseline target** for first run with the new stages active:
- `<X>` design-doc findings (TBD/hedge/non-goals) per /ql-brainstorm
- `<Y>` PRD findings (vague AC / FR-no-measurement) per /ql-spec
- `<Z>` plan findings (AC-coverage-gap / testFirst-no-test-cmd) per /ql-plan

These numbers will land in `PIPELINE_REPORT_v5.md`.

## Test-suite delta vs v0.6.2

Wave-0 through Wave-2 introduced 5 new test files:
1. `tests/test_api_rename.sh` (14 assertions)
2. `tests/test_spec_review_design.sh` (14 assertions)
3. `tests/test_spec_review_prd.sh` (13 assertions)
4. `tests/test_spec_review_plan.sh` (13 assertions)
5. `tests/test_sprint_contract_ql_plan.sh` (13 assertions)

Plus extensions:
- `tests/test_cross_provider_critic_flag.sh` 13 → 20 (+7 unified-fallback assertions)
- `tests/test_sprint_contract.sh` 11 → 16 (+5 expectedTests filter assertions)
- `tests/test_per_role_routing.sh` 26 → 29 (+3 G11 composition + validation-gate assertions)

**Net delta**: 67 new assertions across 8 test files. Baseline test suite: 63 files → 68 files.

Full test-suite log: `.omc/phase-N-evidence/v0.6.3-test-suite.log`.
Audit log: `.omc/phase-N-evidence/v0.6.3-audit.log` (6/6 metrics on target).

## Cross-story contract events (none)

No retries, no merges, no cross-wave conflicts. Sequential execution mode kept the harness simple. Zero retry events recorded in `quantum.json.retries.failureLog` across all 8 user-facing stories.

## codebasePatterns harvested this run

Five new patterns recorded in `quantum.json.codebasePatterns` during execution:

1. **Pre-impl review opt-out env var pattern** (`QL_SKIP_PRE_IMPL_REVIEW=design,prd,plan` csv-form). Discovered during US-006/007/008 design — promoted upfront because dag-validator pre-recorded it.
2. **RED-test-first when refactoring with validation gates**. From US-003: write the new gate's failing assertion before the refactor.
3. **Backward-compat schema additions default to empty array**. From US-002: `otherCommands: string[]` (optional, default `[]`) lets existing readers ignore the new field.
4. **Inline arg-parser globals (no subshell)**. From US-005: process substitution `< <(parser)` runs in a subshell where global assignments are silently lost. Inline the parser when shared state is needed.
5. **Strip `\r` defensively from heredoc-fed JSON output**. From US-004: jq -r piped through `for X in $(...)` on Git Bash retains CRLF; prefer `while IFS= read -r LINE; do LINE=${LINE%$'\r'}; ...; done < <(jq -r ...)`.

## Self-modifying-orchestrator caveat

Stories US-002, US-004, US-006, US-007, US-008 modified the orchestrator and skill prompts that the orchestrator itself uses. **The current run executed on the v0.6.2 orchestrator semantics** (master HEAD `33e569e`); the v0.6.3 changes apply to NEXT runs. This is the safest pattern for self-modifying pipelines: never apply your own diff to your in-flight execution.

## What's next

US-009 (this story) wraps with:
- IDEA_REPORT_v4.md (what's still open after v0.6.3)
- CHANGELOG.md v0.6.3 entry covering 8 user-facing stories
- 3-manifest version bump 0.6.2 → 0.6.3 in lockstep
