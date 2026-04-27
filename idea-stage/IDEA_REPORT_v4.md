# IDEA_REPORT_v4 — what's still open after v0.6.3

**Date:** 2026-04-26
**Source:** v0.6.3-bundle dogfood retrospective (US-009)
**Branch:** `ql/v0.6.3-bundle`
**Predecessor:** `idea-stage/IDEA_REPORT_v3.md`

## Closed in v0.6.3

| ID | Story | Notes |
|---|---|---|
| **G2** | US-005 | `lib/api-rename.sh` — symbol-migration helper covers code + comments + string literals; --exclude flag for historical-path filtering. |
| **G3** | US-004 | `write_sprint_contract` wired into `/ql-plan` Step 8 exit; iterates `.stories[]` and writes `.handoffs/sprint-<id>.json` per story. Idempotent. |
| **G8** | US-001 | Critic fallback unified across bash + PS1: critic role degrades to `none` (preserving US-002's "downgrade rather than substitute" intent), planner/executor degrade to `claude`. Dead `parse_critic_arg` deleted. |
| **G9** | US-002 | Sprint-Contract `expectedTests` now filtered to test-pattern commands; non-test commands move to sibling `otherCommands`. Backward-compat preserved. |
| **G11** | US-003 | `lib/runner.sh::write_routing_snapshot` refactored to compose with `lib/json-atomic.sh::write_quantum_json` for canonical validation gate + atomic write. |
| **P5.B4-design** | US-006 | `agents/spec-reviewer.md` design-review mode + `/ql-brainstorm` Phase 4d post-exit hook. Advisory in v0.6.3. |
| **P5.B4-PRD** | US-007 | prd-review mode + `/ql-spec` post-exit hook. Advisory. |
| **P5.B4-plan** | US-008 | plan-review mode + `/ql-plan` Step 9 post-exit hook (after dag-validator + sprint-contract write). Advisory. |

P5.B4 is now FULLY closed in advisory form. Promotion to blocking gates is a future v0.7.x decision after baseline data accumulates.

## Still open: P5.B2 / B3 / B5 (no change since v3)

| ID | What it is | Effort | v0.7.x verdict |
|---|---|---|---|
| **P5.B2** Bidirectional reviewer agent | spec-reviewer can request implementer fix specific issues; implementer can flag spec-reviewer ambiguities back. | 2-3 stories | Architectural; defer to v0.7.x. |
| **P5.B3** `/ultrareview` command | Single-command "rev-the-engine" composed of spec-reviewer + quality-reviewer + ql-deep-review + far-filter + intent-graph + intent-check. | 1-2 stories | Compositional refactor; needs P5.B2 first. |
| **P5.B5** AgentGA tournament | N agent forks each implement the same story; meta-reviewer merges best-of. | 3-4 stories | Cost-quality tradeoff; needs P5.C1 measurement infra. |

## Still open: P5.C frontier (no change since v3)

| ID | What it is | When to tackle |
|---|---|---|
| **P5.C1** Cost-quality Pareto frontier measurement | Run same N-story plan at 3 model-mix points; measure $/quality. | Needs measurement infra. |
| **P5.C2** Multi-runner integration tests with REAL second provider | Today mocked. | Blocked on second-provider CLI access. |
| **P5.C3** Speculative parallel re-planning | When wave fails, plan recovery branches in parallel. | High-novelty research arc. |
| **P5.C4** Live progress UI | Web UI or rich TUI for wave/story timing. | Pure UX, deferred. |
| **P5.C5** Cross-repo skill sharing | Skills package shared across installations. | Needs registry pattern. |

## NEW gaps surfaced by v0.6.3

| Gap | Symptom | Where seen | Suggested fix |
|---|---|---|---|
| **G12: Pre-impl review subagent dispatch is theoretical** | US-006/007/008 ship the SKILL invocation as a `bash -c "claude --headless ..."` block, but no actual subagent dispatch wiring exists yet. The findings format (FINDING_START/FINDING_END) is documented; the parser/synthesizer is not. | spec-reviewer.md modes; ql-brainstorm/spec/plan SKILL hooks | Add `lib/finding-synth.sh` that parses stderr for FINDING_START..FINDING_END blocks and emits a single per-stage summary. Wire to skill exit log. 1 story. |
| **G13: P5.B4 advisory metric is uninstrumented** | We promised "baseline data accumulates" but there's no aggregation or persistence of findings. Operators see them once on stderr and they're gone. | All three new modes | Persist findings to `.handoffs/<stage>-review-findings.json` with timestamp + counts. Aggregate across runs to `metrics/pre-impl-review-findings.csv`. 1 story. |
| **G14: jq escapes documented inconsistently** | The expectedTests/otherCommands regex `(test_\|\.test\.\|spec\|pytest\|^bash tests/\|^npm test)` lives verbatim in 4 places (orchestrator.md Step 2.5, ql-plan SKILL Step 8, test_sprint_contract.sh Test 6, test_sprint_contract_ql_plan.sh). A single regex change requires touching all 4. | US-002 + US-004 wave | Extract the regex pattern into `lib/handoff.sh` as a documented constant `SPRINT_CONTRACT_TEST_REGEX`. Have all four call sites import it. 1 story. |
| **G15: CHANGELOG ownership convention is implicit** | This run consciously deferred CHANGELOG edits from US-001 + US-005 + US-002 to US-009's retrospective sweep, per the fileConflicts convention. The convention is NOT explicit anywhere — future planners may collide-edit. | dag-validator output; quantum.json.fileConflicts | Document in `agents/dag-validator.md`: stories that touch CHANGELOG.md SHOULD defer to a single retrospective story per release; flag as severity=warning if more than one story has CHANGELOG in `tasks[].filePaths`. 1 story. |
| **G16: Pre-impl review findings have no severity calibration** | The three new modes emit findings with `severity: critical|high|medium|low` but there's no rubric. Without calibration, "critical" findings on design-review will compete with "critical" findings from quality-reviewer post-impl. | spec-reviewer.md design-review/prd-review/plan-review sections | Define severity rubric in `references/finding-severity.md` with examples per category. Cross-link from each mode's Output format section. 1 story. |
| **G17: --audit doesn't measure pre-impl-review activity** | `quantum-loop.sh --audit` reports 6 metrics (branches/orphan-worktrees/conflicts/cpc-files/test-suites). v0.6.3 added 3 advisory review stages but they don't surface in --audit. | quantum-loop.sh §6 measurement plan | Extend --audit with `pre-impl-review-coverage` metric: `<actual stages run> / <stages possible>`. Read from `.handoffs/<stage>-review-findings.json` once G13 lands. Single audit-row addition. 1 story. |

## Recommendation for v0.7.0 / next bundle

**Highest leverage v0.7 candidates (in order):**
1. **G13** — persist pre-impl-review findings (unblocks G16, G17, future calibration data).
2. **G14** — extract sprint-contract regex constant (eliminates 4-way drift surface).
3. **G12** — finding-synth helper (turns advisory mode into actually-actionable stage gates).
4. **G16** — severity rubric (necessary before promoting any pre-impl-review stage to blocking).

The frontier P5.B2 / B5 and P5.C* items remain deprioritized: each is a multi-story bundle and we have higher-leverage cleanup ahead. The v0.6.3 P5.B4 trilogy demonstrated that **scaffolding-not-logic** dismissals from dag-validator are reliable signals to skip premature DRY refactors — that confidence applies to v0.7 planning too.

## Cross-track: dogfood-fed pipeline patterns

Five new patterns harvested into `quantum.json.codebasePatterns` this run:
1. Pre-impl review opt-out env var pattern (v0.6.3 P5.B4 design)
2. RED-test-first when refactoring with validation gates (v0.6.3 G11)
3. Backward-compat schema additions default to empty array (v0.6.3 G9)
4. Inline arg-parser globals (no subshell) (v0.6.3 G2)
5. Strip `\r` defensively from heredoc-fed JSON output (v0.6.3 G3)

Patterns 4 and 5 are particularly valuable: they encode Git Bash / MSYS specific gotchas that would otherwise re-bite future implementers.
