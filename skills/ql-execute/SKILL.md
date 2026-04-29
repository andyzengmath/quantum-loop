---
name: ql-execute
description: "Part of the quantum-loop autonomous development pipeline (brainstorm \u2192 spec \u2192 plan \u2192 execute \u2192 review \u2192 verify). Run the autonomous execution loop. Reads quantum.json, queries the dependency DAG, implements stories with TDD and two-stage review gates. Supports parallel execution via native worktree isolation. Use after /quantum-loop:plan has created quantum.json. Triggers on: execute, run loop, start building, ql-execute."
---

# Quantum-Loop: Execute

Run the autonomous execution loop to implement all stories in quantum.json.

## Prerequisites

Before starting:
1. `quantum.json` must exist (created by `/quantum-loop:plan`)
2. The project must be a git repository
3. Project build tools must be available (npm, pip, cargo, etc.)

If prerequisites are not met, inform the user and stop.

## Execution

Read and follow the orchestrator agent instructions in `agents/orchestrator.md`.

The orchestrator will:
1. Read quantum.json state and validate the dependency DAG
2. Query for eligible stories (pending/retriable with all dependencies passed)
3. **If 1 story eligible:** execute it sequentially (implement, quality checks, review, commit)
4. **If 2+ stories eligible:** spawn parallel implementer subagents in isolated worktrees
5. Handle retries, cascade blocking, and error recovery
6. Loop until all stories pass (COMPLETE) or no stories are executable (BLOCKED)

## Orchestrator liveness gate (N14 / US-002 — v0.7.0)

**Default-on for unattended `/ql-execute` runs.** v0.6.7 + v0.6.8 + v0.6.9 all saw the orchestrator subagent abandon its cycle mid-execution (LLM context-drift). v0.6.8 N6 shipped a prose-only Self-monitoring guard. v0.6.9 N6-followup shipped `lib/orchestrator-liveness.sh::poll_orchestrator_commits` as a callable runtime helper. This v0.7.0 N14 SKILL-level wrapping is the third and final layer — auto-invoke the helper after dispatching the orchestrator, hand off to the parent on STALE.

```bash
# After dispatching the orchestrator subagent (Step 3 of Execution above):
source lib/orchestrator-liveness.sh
wrap_orchestrator_dispatch 600 60 || exit 1
```

The `wrap_orchestrator_dispatch` function (v0.7.1 N20 extraction; see
`lib/orchestrator-liveness.sh`) handles the `QL_LIVENESS_ENABLE` env-var
check, the `poll_orchestrator_commits` invocation, and the structured
handoff message internally. The SKILL just calls it and exits 1 on
STALE so CI / wrapper scripts can distinguish stale-signal exits from
clean COMPLETE / BLOCKED exits.

**Env var contract:**

| `QL_LIVENESS_ENABLE=` | Effect |
|---|---|
| (unset) or `true` | default — wrap orchestrator dispatch with `poll_orchestrator_commits` (timeout 600s, interval 60s) |
| `false` | skip the wrapping; preserve v0.6.9 dispatch semantics exactly (backwards compat for operators with their own wrappers) |
| any other value | treated as `true` (default-true semantics; warn to stderr) |

**Handoff message structure** (printed to stdout when STALE fires):
- One-line `[QL-EXECUTE] orchestrator-stale signal.` header.
- Pointer to `references/orchestrator-takeover.md` (the v0.6.9 N13 SOP).
- Numbered recovery steps the parent agent runs (drift verification + manual takeover).

The parent agent reads the handoff and either re-spawns `/ql-execute` (after confirming whether drift was a transient LLM hiccup) or takes over manually per the SOP. SKILL exits with rc=1 (`orchestrator-stale`) so CI / wrapper scripts can distinguish stale-signal exits from clean COMPLETE / BLOCKED exits.

**Testability note (presence-only AC):** the wrapping prose above is consumed by an LLM that runs `/ql-execute`. There is no runtime test that EXERCISES the env-var conditional or the handoff message structure inside the SKILL itself — those would require running the SKILL in a controlled fixture. Instead, `tests/test_ql_execute_liveness_wrapping.sh` verifies the prose contains the expected idioms (header, env var, default-true, cross-link, handoff structure). Matches v0.6.8 N6 prose-guard pattern.

## Autonomous CLI Alternative

For unattended execution outside Claude Code (Linux/Mac):
```bash
./quantum-loop.sh --max-iterations 20
./quantum-loop.sh --parallel --max-parallel 4
```

On Windows, use `/ql-execute` instead of the shell script for reliable execution.

## Signals

| Signal | Meaning |
|--------|---------|
| `<quantum>COMPLETE</quantum>` | All stories passed |
| `<quantum>BLOCKED</quantum>` | No executable stories remain |
| `<quantum>STORY_PASSED</quantum>` | One story completed (more remain) |
| `<quantum>STORY_FAILED</quantum>` | One story failed (will retry if attempts remain) |
| `<quantum>WAVE_PASSED</quantum>` | All stories in a coordinator wave passed (v0.8.0+ coordinator pattern; see `agents/coordinator.md`) |
| `<quantum>WAVE_FAILED</quantum>` | One or more wave stories failed (parent decides retry/abort) |

## Post-review slop-cleanup hook (Phase 9 / P1.6)

After each story's two-stage review gate PASSES but BEFORE the merge to the feature branch, the orchestrator SHOULD invoke `/quantum-loop:ql-deslop` on the story's changed files. Opt-out via `--no-deslop` (record the reason in commit trailer `Deslop: skipped | <reason>`).

Mandatory safety rails, enforced by `lib/deslop.sh`:

1. `validate_scope <file> BASE HEAD` — rejects any edit to a file outside the story's diff. Prevents "adjacent cleanup" scope creep.
2. `take_baseline <before.json>` — snapshots test / lint / typecheck exit codes.
3. Run ONE deslop pass at a time from the 4-pass taxonomy in `skills/ql-deslop/SKILL.md` (dead-code → duplication → consistency → test-reinforcement).
4. `take_baseline <after.json>` + `compare_baseline before.json after.json`. Any regression triggers:
5. `rollback_pass BASE <files>` and emits `<quantum>DESLOP_ROLLED_BACK</quantum>`. The next pass does NOT start until the user inspects.
6. Persist per-pass report into `quantum.deslop[<story-id>].pass_<n>`.

Language detection: `bash lib/deslop.sh detect-language` dispatches to the appropriate dead-code detector (knip / ts-prune / vulture / staticcheck / cargo-udeps). When tooling is missing, the step is skipped cleanly rather than failing the pipeline.

## Post-pipeline review hook (Phase 8 / P1.1 + P1.2)

After `COMPLETE` fires, the orchestrator SHOULD invoke `/quantum-loop:ql-deep-review` before handing the merged branch back to the user. Opt-in via `--deep-review` (or mandatory when the feature's risk tier is HIGH / CRITICAL per `lib/deep-review.sh compute_risk_score`).

Gate steps:

1. Run the wave-boundary checks on the final commit range (`BASE_SHA..HEAD_SHA`):
   - **Cross-story constant scan** — `bash lib/wave-boundary.sh scan BASE HEAD` emits JSON findings for literals that canonicalize to the same key across ≥2 stories (e.g. `'google'` vs `'google-api-key'`; the Math-Research regression class). Gate via `bash lib/wave-boundary.sh gate BASE HEAD` — exit 0 = divergence found, exit 1 = clean. Non-empty findings are treated as a `medium` (2 variants) or `high` (3+ variants) severity input to the reviewer-set dispatch.
   - **Wave-wide typecheck** (`lib/resilience.sh` `run_typecheck`).
   - **Full test suite**.
   - **Barrel + dep-manifest regeneration** (`lib/barrel-regen.sh`, `lib/dep-manifest.sh`).
2. Compute risk tier: `bash lib/deep-review.sh score BASE HEAD` → then `bash lib/deep-review.sh tier <score>`.
3. Dispatch the reviewer-set specified in `skills/ql-deep-review/SKILL.md §"Risk scoring"`.
4. Apply `lib/deep-review.sh actionability / dedup / hallucination / verdict` in sequence to aggregate findings.
5. Persist the final review object into `quantum.reviews[<feature-id>].deepReview`.
6. Verdicts:
   - `BLOCKS_MERGE` → refuse handoff; emit `STORY_FAILED` with blockers in the failureLog.
   - `REQUEST_CHANGES` → route to a targeted fix-story in the next wave.
   - `APPROVE_WITH_COMMENTS` → proceed but log comments into `codebasePatterns`.
   - `APPROVE` → proceed cleanly.

For legacy pipelines that predate this hook, `/quantum-loop:ql-deep-review` can be invoked manually post-merge.
