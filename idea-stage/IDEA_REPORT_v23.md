# IDEA_REPORT_v23 — what's open after v0.8.1

**Date:** 2026-04-29
**Source:** Operator-scoped v0.8.1 N39 validation; dogfood found v0.8.0 N33 closure was inert
**Branch:** `ql/v0.8.1-bundle` (release tag v0.8.1)
**Predecessor:** `idea-stage/IDEA_REPORT_v22.md`

## Closed in v0.8.1

| ID | Story | Notes |
|---|---|---|
| **N39** | Dogfood validation | The cycle's primary mission. Found the defect (v0.8.0 shipped inert infrastructure), shipped minimal viable wires (US-001) + regression-guard test. **Closes the validation question, opens N42 for the real cure.** |
| **N41** | Coordinator → orchestrator handoff for legacy paths | Documentation gap from v0.8.0; v0.8.1's WARN message + N42 backlog entry covers it. Close. |

## Persistent canon

p001-p011 unchanged. v0.8.1 proposes new pattern p012 (anti-presence-only AC); see `idea-stage/PIPELINE_REPORT_v23.md` § codebasePatterns.

## Still open (carried forward)

### N40 — orchestrator.md further reduction (≤700 lines target)

**Status:** unchanged from IDEA_REPORT_v22. v0.8.0 US-003 reduced 1743 → 1007 lines (42%). Further reduction requires extracting Step 3B (Parallel Execution) which is core logic.
**Severity:** LOW (cosmetic AC compliance; substantive value already delivered).
**Path:** defer indefinitely unless context-window pressure resurfaces.

### N38 — codex CLI flag drift detection automation

**Status:** unchanged from IDEA_REPORT_v21. LOW.

### Copilot rate-limit observability

**Status:** unchanged. LOW (environmental).

## New gaps from v0.8.1 dogfood

### N42 — Real per-wave coordinator dispatch (PRIMARY follow-up; v0.9.0 candidate)

**Status:** NEW. v0.8.1 dogfood found that `COORDINATOR_MODE` is set/unset by flags but never consulted. The `agents/coordinator.md` agent definition and `lib/spawn.sh::spawn_coordinator` helper exist but no caller wires them into the dispatch loop in `quantum-loop.sh`.
**Severity:** HIGH for the architectural goal (breaking the manual-takeover streak); LOW for current production stability (the legacy single-spawn path still works).
**Path:** v0.9.0 minor-tier — replace the single-spawn dispatch loop with a wave-driven loop:
1. Read DAG, pick eligible wave from quantum.json
2. `spawn_coordinator wave_id story_ids` to invoke a fresh coordinator subagent per wave (bounded context per invocation)
3. Coordinator implements stories within the wave (sequential or via implementer subagents)
4. Aggregate result, update quantum.json, loop to next wave

This is genuinely architectural work: introduces a new control-flow pattern. **Per `feedback_version_tier_calibration.md`: this is minor-tier.** First architectural-tier work since v0.8.0's N33 closure.

### N43 — Parallel-with-dispatch wrap pattern (vs current post-dispatch)

**Status:** NEW. v0.8.1's `ql_wrap_subagent_dispatch` wire is post-dispatch (called after the runner returns). The design ideal is parallel-with-dispatch: spawn the runner in background, poll commits in foreground, kill the runner if STALE before respawn.
**Severity:** MEDIUM (current wire is reachable but reactive — can't pre-empt a stuck agent).
**Path:** v0.9.0+ once N42 lands. Background-process supervision in shell is fragile on Git Bash; needs careful design with `wait`, signal handling, and `pkill`-style cleanup. Likely deferred to a dedicated cycle after N42 is stable.

### N44 — CSV/PIPELINE_REPORT count reconciliation

**Status:** NEW. v0.8.0's PIPELINE_REPORT_v22 reported "design=2, prd=2, plan=2 (3 MEDIUM and 3 LOW total)" but the underlying CSV rows show count=1 for each (1 LOW per stage). The discrepancy is documented but not investigated. Possibly the persistence layer truncates or the report aggregation drifted.
**Severity:** LOW (cosmetic — CSV is canonical; report drift doesn't affect production).
**Path:** ad-hoc audit during a future housekeeping cycle. Run `lib/finding-persist.sh` directly with multiple findings per stage and verify CSV row counts match. If the layer truncates, fix; if the report writer over-counts, fix the report writer.

### N46 — QL_RESPAWN_CMD respawn-output not re-parsed

**Status:** NEW (acknowledged limitation in v0.8.1 US-006 fix). When `wrap_orchestrator_dispatch` fires on STALE with `QL_RESPAWN_CMD` set, the respawn command runs but its stdout/stderr is NOT captured back into `OUTPUT`, and `runner_parse_output` is NOT re-invoked. Result: even a successful respawn (rc=0) leaves `SIGNAL_RESULT` at the original failed value, so the post-wrap case-statement still marks the story failed.
**Severity:** MEDIUM (operators with `QL_RESPAWN_CMD` configured may be confused that their respawn ran but the story still appears failed).
**Path:** v0.9.0+ alongside N42 (real per-wave dispatch). Proper fix: capture respawn output, re-feed through `runner_parse_output`, update SIGNAL_RESULT/SIGNAL_CONFIDENCE before falling into the case statement.

### N45 — External-helper working-tree noise

**Status:** NEW (recurring). External-process modifications to test files appeared between v0.7.10 and v0.8.0 (stashed as `wip-pre-v0.8.0-external-edits`) and again between v0.8.0 and v0.8.1 (stashed as `v0.8.1-pre: external-helper edits 2026-04-29`). Pattern: CRLF normalization + minor content additions to dispatch tests + cleanup traps in test_timeout.sh.
**Severity:** LOW (operational hygiene; the modifications are usually beneficial).
**Path:** Document the helper's identity. If it's an MCP server or autonomic loop, isolate it to a working tree separate from master. If it's value-add, fold into a dedicated automation cycle.

## Recommendation for next

**v0.9.0 candidate slate (minor-tier — first architectural work since v0.8.0):**

| Story | Content |
|-------|---------|
| US-001 | N42 — replace single-spawn dispatch loop with wave-driven loop using spawn_coordinator |
| US-002 | DAG + wave-eligibility logic in shell (`lib/dag-query.sh::next_wave` if not already defined) |
| US-003 | Per-wave runner instrumentation: capture wall-clock, context-tokens estimate, post-wave quantum.json snapshot |
| US-004 | Real-fire integration tests for the wave-driven loop (not presence-only — actually invoke `quantum-loop.sh --coordinator` against a 2-story stub plan and assert per-wave behavior) |
| US-005 | Backward-compat: `--legacy-orchestrator` continues to use the single-spawn loop for at least 3 cycles after v0.9.0 ships |
| US-006 | Retrospective + IDEA_REPORT_v24 + version bump 0.8.1 → 0.9.0 |

**Honest risk for v0.9.0:** Background-process supervision (N43) intersects N42's design. If we don't ship N43 alongside N42, the per-wave dispatch will still be sequential blocking — the gain is bounded context per wave, not parallel agent execution. That's still a meaningful improvement (was the v0.8.0 thesis), but operators may expect more.

## Recurring observations

- **17 consecutive LOW G30 self-validations** (v0.6.5..v0.8.1). The rubric continues to correctly identify cosmetic vs sensitive changes.
- **Bundle size: 7-7-7-7-5-6-5-3-7-3-2-4-3-3-7-7-5.** v0.8.1 is 5-story patch (validation + 2 inline fixes + retro). Smaller than v0.8.0's 7-story architectural minor.
- **First minor-tier in ~9 cycles.** v0.8.0 (N33 closure) was minor; v0.8.1 is patch. v0.9.0 (N42) is the next minor candidate.
- **Manual-takeover continues to be the de-facto execution mode.** 14 consecutive cycles. v0.8.1 ships the wires that *could* break the streak; v0.9.0's N42 is the architectural cure that *should* break it.
- **First cycle to surface a defect via static-analysis dogfood.** No LLM dispatch needed — pure grep against `quantum-loop.sh` exposed both defects in <30s. Lesson: ACs that include "function has ≥1 caller" (not just "function is defined") would have caught this in v0.8.0.

## v0.8.x track close

v0.8.x is now structurally complete (v0.8.0 architectural minor + v0.8.1 validation patch). v0.9.0 should pick up N42 as the next minor-tier cycle.

If the operator pivots to non-cycle work, the v0.8.x track is in a stable shippable state. If continuing the autonomous-iteration cadence, **v0.9.0 N42 is the natural next move.**
