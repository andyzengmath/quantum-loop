# IDEA_REPORT_v3 — what's still open after v0.6.0

**Date:** 2026-04-26
**Predecessor:** `idea-stage/IDEA_REPORT_v2.md` (March 2026, after v0.5.1 --audit dogfood)
**Successor:** `idea-stage/IDEA_REPORT_v4.md` (TBD, after next dogfood)

## Closed in v0.6.0

| Item | Story | Notes |
|---|---|---|
| **P5.A1** Watchdog orchestrator wiring | US-001 | 3 explicit calls in Step 3B.3 (poll, circuit, reset on STORY_PASSED). Migrated to reap_agent. |
| **P5.A2** Cross-provider critic CLI flag | US-002 | --critic=auto\|codex\|gemini\|claude\|none with availability fallback. **Subsumed by P5.B1 / US-009 unified per-role helper.** |
| **P5.A3** Deslop regex fallback | US-003 | When tooling absent, dispatches to lib/dead-code.sh with normalized {file,line,kind,severity} schema. |
| **P5.A4** 5 new runner manifests | US-004 | opencode, devin, kiro, goose, cline. All experimental:true. opencode has skill auto-discovery quirk. |
| **P5.A5** PRD hash-pinning (RAGShield L-1) | US-005 | compute_prd_sha + Step 1.1 hash-check + dag-validator emission. |
| **P5.A6** Sprint-Contract handoff | US-006 | write/read_sprint_contract + .handoffs/sprint-<storyId>.json + references/sprint-contract.md. |
| **P5.A7** Inline self-review checklists | US-007 | Routine review (typecheck/lint/test/file-org) inline-only; subagents reserved for adversarial. |
| **P5.A8** Cheapest-capable-model routing | US-008 | compute_complexity formula + runner_select_model + per-story complexity field. |
| **P5.B1** Per-role provider routing | US-009 | --planner / --critic / --executor + resolve_routing + quantum.json.routing snapshot. **Closes P2.9 fully.** |

## Still open: P5.B2-B5

| Item | Brief | Effort estimate | Why not in v0.6.0 |
|---|---|---|---|
| **P5.B2** Bidirectional reviewer agent | spec-reviewer can request implementer fix specific issues; implementer can flag spec-reviewer ambiguities back. Beyond current one-way review-then-fix flow. | 2-3 stories | Bigger architectural change; out of scope for cleanup bundle. |
| **P5.B3** /ultrareview command | Single-command "rev-the-engine" that runs spec-reviewer + quality-reviewer + ql-deep-review + far-filter + intent-graph + intent-check in one canonical sequence with merged output. | 1-2 stories | Compositional refactor; needs P5.B2 first to be maximally useful. |
| **P5.B4** Spec-review-before-impl | Spec-reviewer sanity-checks the PRD's acceptance criteria for testability + measurability **before** any implementation begins, not after. Catches PRD smells (e.g. "should work well") at the lowest cost. | 1 story | Pipeline-stage reordering; needs ql-plan to invoke spec-reviewer in dry-run mode. |
| **P5.B5** AgentGA tournament | Tournament-style diff-merging where N agent forks each implement the same story and a meta-reviewer picks the winner (or merges best-of). Higher quality at proportional cost. | 3-4 stories | Cost-quality tradeoff needs measurement before commitment. |

## Still open: P5.C frontier

| Item | Brief | Notes |
|---|---|---|
| **P5.C1** Cost-quality Pareto frontier measurement | Run the same N-story plan at 3 different model-mix points (all-Haiku / Sonnet-default / all-Opus) and measure $/quality. | Needs measurement infra; defer until cost matters. |
| **P5.C2** Multi-runner integration tests with REAL second provider | The US-009 multi-runner integration test mocks codex absence. We need an actual claude+codex round-trip on a small toy plan. | Blocked on test-environment access to a second provider's CLI. |
| **P5.C3** Speculative parallel re-planning | When an early wave fails, speculatively plan two recovery branches in parallel; pick the one that lands first. | High novelty, low confidence; fits a research arc. |
| **P5.C4** Live progress UI | Replace the terminal-tail-watching UX with a live progress indicator (web UI or rich TUI) showing wave status + per-story timing. | Pure UX; deferred. |
| **P5.C5** Cross-repo skill sharing | Today skills live per-project. Allow skills/ to be a shared package across multiple quantum-loop installations. | Needs a registry or git-submodule pattern. |

## NEW gaps surfaced by v0.6.0

| Gap | Origin | Suggested follow-up |
|---|---|---|
| **G1: jq field-presence validators don't enforce additionalProperties** | US-004 dogfood: my schema-noncompliant `experimental` field passed `bash schemas/validate.sh` because validate.sh is field-presence-only, not full JSON Schema. | Either replace validate.sh with `ajv-cli` (1 story, brings npm dep) or document the gap in `runners/preamble.md` (5 minutes). |
| **G2: cross-module API renames need doc-comment scanning** | US-001 dogfood: my migration of `kill_agent_process -> reap_agent` initially missed the line-4 module-header comment. Test caught it; pattern is generally applicable. | Add a `lib/api-rename.sh` helper that scans both call sites AND doc comments for an old symbol when validating an API rename. |
| **G3: Sprint-Contract not yet wired into /ql-plan exit** | US-006 ships the helpers and the orchestrator emission step, but the actual `/ql-plan` skill doesn't yet write sprint-contracts at exit. | 1 story to wire skills/ql-plan/SKILL.md to call write_sprint_contract per story when the planner exits. |
| **G4: Test scripts under set -uo pipefail terminate on first non-zero return** | US-009 dogfood: feeding `parse_role_arg planner none` (which correctly returns 1) killed the test. Discovered repeatedly across this dogfood. | Add a "test patterns" reference doc that mandates `\|\| true` on calls that legitimately return non-zero. |
| **G5: Routing snapshot is missing from /ql-plan stub** | US-009 ships `resolve_routing` + `write_routing_snapshot`, but a brand-new `quantum.json` from `/ql-plan` doesn't get a routing snapshot until the orchestrator runs the first time. | Either have `/ql-plan` call resolve_routing at plan-creation time, or document that the snapshot is lazily populated. |
| **G6: Inline-review token grep is brittle** | US-007's checklist tokens (`typecheck OK`, `lint OK`, etc.) are pure prompt-text — they're verifiable only by grep, not by any executable check. An implementer that types the token without actually running the command would falsely pass. | Add a paired runtime check: orchestrator regreps the implementer's stdout AND verifies the underlying command actually ran (e.g. by intercepting bash calls). Defer to P5.B2 bidirectional reviewer. |
| **G7: Sprint-Contract prdSha validation duplicates US-005 Step 1.1** | US-006 implementer reads the sprint-contract and validates prdSha matches; US-005 orchestrator Step 1.1 does the same. Two checks for one drift event. | Fold the implementer-side check into a noop when Step 1.1 has already validated; or make Step 1.1 skip stories that have a sprint-contract (defer to implementer). |

## NEW gaps surfaced by `/soliton:pr-review` on PR #61 (v0.6.x post-merge)

Five sub-threshold (score 75/100) and one at-threshold (score 100/100) findings emerged when `/soliton:pr-review` ran on the v0.6.0+v0.6.1 bundle. The 100-score finding (`.cursor-plugin/plugin.json` not bumped) was fixed inline; the 75-score findings are queued here for v0.7.x:

| Gap | Origin | Score | Suggested follow-up |
|---|---|:-:|---|
| **G8: Critic fallback 3-way divergence** | `quantum-loop.sh::parse_critic_arg` (dead code, falls back to `none`) vs `parse_role_arg` via `_availability_check` (falls back to `claude`) vs `quantum-loop.ps1` (falls back to `none` for critic role). The active bash `--critic` arg-handler now calls `parse_role_arg`, so cross-platform parity is broken: same `--critic=codex` with codex absent → bash gets `claude` (review gate runs), PowerShell gets `none` (review gate downgraded). | 75 | Either delete `parse_critic_arg` (genuinely dead code created by this same PR — no external US-002 callers since US-002 and US-009 land together) AND align PowerShell's critic fallback to `claude`, OR make `parse_role_arg`'s critic-role branch fall back to `none` to match the original US-002 design intent. The latter is more conservative (preserves the deliberate "downgrade rather than substitute" behavior US-002 was designed for). 1 story. |
| **G9: orchestrator.md Step 2.5 `expectedTests` populated from ALL `.commands`** | The Sprint-Contract jq writes `expectedTests: [($story.tasks // [])[].commands // []] \| flatten` — but `.commands` mixes typecheck/lint/test commands. Per `references/sprint-contract.md`, `expectedTests` should be "test names or patterns the implementer must produce or extend," not arbitrary verification commands. | 75 | Filter the jq to test-pattern-only commands (e.g., `[($story.tasks // [])[].commands // [] \| .[] \| select(test("test_") or test("\\.test\\.") or test("spec"))] \| flatten`). Or split `commands` into `testCommands` and `otherCommands` at the schema level. 1 story. |
| **G10: `compute_prd_sha` v0.6.1 CRLF fix is a sha-migration hazard for Windows v0.6.0 users** | v0.6.0 hashed CRLF bytes verbatim; v0.6.1 normalizes `\r\n` → `\n` first. Same PRD on Windows produces different shas on the two versions. Windows users with in-flight v0.6.0 `quantum.json` (containing stored `prdSha`) will see ALL stories marked `status: "stale"` on first orchestrator run after upgrade — forced full `/ql-plan` re-run mid-sprint. | 75 | Add migration shim: on first run, if `prdSha` mismatch detected AND a one-shot CRLF-preserved hash matches, log a one-line "migrating prdSha to LF-normalized form" notice + re-write the field. Or document the migration in CHANGELOG with explicit instructions to re-run `/ql-plan` after upgrade. ≤1 story. |
| **G11: `write_routing_snapshot` rolls own atomic-write instead of calling `write_quantum_json`** | `lib/runner.sh::write_routing_snapshot` does `tmp+mv` inline; bypasses `write_quantum_json`'s pre-write `jq .` validation gate AND `cleanup_stale_tmp` coordination. Both functions target the same `${qj}.tmp` path → potential race if both ever fire concurrently. | 75 | Refactor `write_routing_snapshot` to compose: build the new content via `jq --argjson r "$routing" '.routing = $r' "$qj"`, then pass result to `write_quantum_json "$qj" "$content"`. Single canonical writer; validation gate inherited. ½ story. |

These all scored 75 (Haiku confidence). The threshold for surfacing in the soliton review comment was ≥80, so they were filtered out of the public PR comment but are real findings worth addressing.

## Recommendation for v0.7.0 / next bundle

**Highest-leverage next bundle (revised after PR #61 review)**: G8 (critic fallback unification) + G9 (expectedTests filter) + G11 (write_routing_snapshot canonicalization) + G3 (wire sprint-contract into /ql-plan) + G2 (api-rename helper). Total ~5 stories, all cleanup of v0.6.x follow-throughs. **G10 (CRLF migration) can be a v0.6.2 patch** since it's an upgrade-path concern affecting current users on Windows — ship it standalone before any v0.7 work.

P5.B4 (spec-review-before-impl) is still strong but de-prioritized by the v0.6.x post-merge findings; defer to v0.7.1 unless one of the new gaps proves blocking. P5.B2 and P5.B5 still defer until P5.C1 measurement infra exists.

The dogfood signal from this run is **strongly positive** — even after a fresh `/soliton:pr-review` round, no critical bugs surfaced; everything found is at-or-below confidence threshold and points to refactoring / canonicalization rather than functional defects. The remaining gaps are mostly "wire feature X end-to-end" or "dedupe parallel implementations" rather than architectural rethinks.
