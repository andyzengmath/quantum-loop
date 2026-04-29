# Dogfood findings — v0.8.1 (N39 validation of v0.8.0 N33 closure)

**Date:** 2026-04-29
**Cycle:** v0.8.1
**Mission:** Empirically validate that v0.8.0's N33 closure (`ql_wrap_subagent_dispatch` wired into `quantum-loop.sh` + `--coordinator` flag opt-in) actually fires in production.

## Final verdict (US-002 synthesis)

| Claim (from PRD US-002) | Status | Evidence anchor |
|---|---|---|
| Coordinator agent dispatched | ❌ BROKEN → ⚠️ DEGRADED post-fix | quantum-loop.sh:553/559 set var; pre-fix had 0 readers; post-fix WARN is observable but real per-wave dispatch is N42 |
| `wrap_orchestrator_dispatch` invoked in production | ❌ BROKEN → ✅ WORKED post-fix | quantum-loop.sh:1559 now calls `ql_wrap_subagent_dispatch 5 1 ""` when `SIGNAL_RESULT` is empty |
| Worktree-aware poll accurate | ✅ WORKED (test-only) | tests/test_orchestrator_liveness.sh Tests 12+13 cover; real-cycle validation deferred to N42 |
| Coordinator stayed within bounded context | ⚠️ DEGRADED / N/A | No real coordinator dispatch (defect 1); structural-only evidence (orchestrator.md 1743→1007 lines, 13 modules) |

**Quorum:** all 4 claims have explicit verdicts (no UNKNOWN entries). Two pre-fix BROKEN findings are explicit defects in v0.8.0; both received minimal viable fixes in v0.8.1. Two findings remain DEGRADED/N/A pending the larger N42 work (real per-wave dispatch). v0.8.1 is the diagnostic; v0.9.0 should be the cure.

## TL;DR

**v0.8.0 shipped two pieces of inert infrastructure** with presence-only ACs.

1. ❌ **`COORDINATOR_MODE`** — set by `--coordinator`/`--legacy-orchestrator` flags but *never consulted* by any code path in `quantum-loop.sh`. The flag has zero runtime effect.
2. ❌ **`ql_wrap_subagent_dispatch`** — defined as a wrapper (line 660) but has *zero callers* anywhere in the runner-dispatch loop. Same exact pattern as N33 root cause #1, which v0.8.0 was supposed to close.

**Both were caught by static analysis** (grep for callers / readers) rather than by a real cycle running through `--coordinator`. The defect would have shipped silently for at least another cycle without v0.8.1's dogfood.

**v0.8.1 ships fixes:** wires both into the actual dispatch loop with a regression-guard test (`tests/test_v081_wiring.sh`) that explicitly checks "function called" not just "function defined".

## Static-analysis dogfood (no LLM dispatch needed)

The validation didn't need a real LLM dispatch — pure grep against `quantum-loop.sh` exposed both defects within minutes:

```bash
# Defect 1: COORDINATOR_MODE flag is inert
$ grep -n 'COORDINATOR_MODE' quantum-loop.sh
46:COORDINATOR_MODE=false                    # init
553:      COORDINATOR_MODE=true              # --coordinator flag
559:      COORDINATOR_MODE=false             # --legacy-orchestrator flag
# (no READ sites — variable is set but never consulted)

# Defect 2: ql_wrap_subagent_dispatch has zero callers
$ grep -n 'ql_wrap_subagent_dispatch' quantum-loop.sh
657:# Usage: ql_wrap_subagent_dispatch [TIMEOUT_SEC] [INTERVAL_SEC] [WORKTREE_PATH]
660:ql_wrap_subagent_dispatch() {                  # definition
# (no call sites — function defined but never invoked)
```

Both checks took <30 seconds. v0.8.0 US-001's AC was "verifiable via grep" — and it was, but the grep checked for *the function definition*, not for a caller.

## Per-claim verdict

The v0.8.1 PRD US-002 names 4 minimum claims. Each gets an explicit verdict:

| # | Claim | Verdict | Evidence |
|---|---|---|---|
| 1 | Coordinator agent dispatched on `--coordinator` | ❌ **BROKEN** | `COORDINATOR_MODE` was never read pre-fix. The flag had zero runtime effect. **Fixed in this cycle:** added a WARN at startup when `COORDINATOR_MODE=true` so operators see the flag is unimplemented in the runner loop. |
| 2 | `wrap_orchestrator_dispatch` invoked in production | ❌ **BROKEN** | `ql_wrap_subagent_dispatch` (the v0.8.0 wrapper) had zero callers. **Fixed in this cycle:** invoked post-`runner_parse_output` when `SIGNAL_RESULT` is empty (drift suspect). |
| 3 | Worktree-aware poll accurate (US-002 v0.8.0) | ✅ **WORKED** (in tests) | `tests/test_orchestrator_liveness.sh` Tests 12+13 cover worktree-path STALE and LIVE. Real-cycle validation deferred — would need the parallel-mode dispatch with worktree spawn, which itself isn't wired through `--coordinator`. |
| 4 | Coordinator stayed within bounded context | ⚠️ **DEGRADED / N/A** | The coordinator was never actually dispatched (defect 1), so the bounded-context claim has no empirical evidence. Module count (13) and orchestrator.md size reduction (1743→1007 lines) are structural; runtime context measurement requires a real dispatch — out of scope for v0.8.1. |

## Why v0.8.0 missed this

Three failure modes, all from the v0.8.0 / N33 cycle:

1. **Presence-only ACs.** US-001 AC: "verifiable via grep" found `ql_wrap_subagent_dispatch` definition. There was no AC requiring "function is called from at least one site".

2. **Test pyramid is shallow.** `test_quantum_loop_recovery.sh` tests `wrap_orchestrator_dispatch` directly with stub repos — it never exercises the path through `quantum-loop.sh`'s actual dispatch loop.

3. **Self-referential test in `test_coordinator_dispatch.sh`.** Test 6 grep-checks that "both flags handled in quantum-loop.sh" — but "handled" was interpreted as "case branch exists", not "branch produces an effect".

This is exactly the same anti-pattern as the original N33 root cause #1 (recovery infrastructure inert: `wrap_orchestrator_dispatch` had zero production callers when v0.7.x shipped). v0.8.0 was supposed to fix this and instead reproduced it one layer deeper.

## v0.8.1 fixes

### Fix 1: COORDINATOR_MODE warns on opt-in

**File:** `quantum-loop.sh` (after `ql_wrap_subagent_dispatch` definition).

```bash
if [[ "$COORDINATOR_MODE" == "true" ]]; then
  printf "WARN: --coordinator flag set but per-wave dispatch is not yet wired into the shell-driven runner loop. spawn_coordinator() is defined but has no caller in quantum-loop.sh. Falling back to legacy single-spawn behavior. See N42 in idea-stage/IDEA_REPORT_v23.md.\n" >&2
fi
```

This is honest minimal progress: the flag's broken state is now observable to operators rather than silent.

### Fix 2: ql_wrap_subagent_dispatch wired post-dispatch

**File:** `quantum-loop.sh` (after `runner_parse_output`).

```bash
if [[ -z "${SIGNAL_RESULT:-}" ]]; then
  ql_wrap_subagent_dispatch 5 1 "" >&2 || true
fi
```

Soft-fire pattern: only invoked when no signal was parsed (drift suspect). Honors `QL_LIVENESS_ENABLE=false` for opt-out. `QL_RESPAWN_CMD` configured operators get auto-respawn via `wrap_orchestrator_dispatch`'s existing path.

This is also minimal viable progress: the wrap is now CALLED in production. The reach pattern (post-dispatch poll) is less aggressive than the design ideal (parallel-with-dispatch poll that can preempt a stale agent), but it's a real call site and proves the wire works.

### Fix 3: Anti-presence-only regression-guard test

**File:** `tests/test_v081_wiring.sh` (NEW).

Four assertions:

1. `ql_wrap_subagent_dispatch` has at least one caller in `quantum-loop.sh` (counts call sites, not the definition).
2. `$COORDINATOR_MODE` is read in at least one conditional outside flag-parsing.
3. The COORDINATOR_MODE=true branch contains a recognizable WARN.
4. **Smoke:** running `bash quantum-loop.sh --coordinator --tool claude` against a minimal stub repo emits the WARN to stderr.

The smoke test (#4) is the most important — it exercises the actual binary and asserts behavior, not source presence. This guards against the "presence-only AC" anti-pattern that bit v0.8.0.

## What v0.8.1 does NOT fix

Honestly out-of-scope for a patch-tier validation cycle:

- **Real per-wave dispatch via spawn_coordinator.** This requires substantive shell-loop restructuring (replacing single-spawn with wave-driven loop). Tracked as **N42** for v0.9.0+.
- **Parallel-with-dispatch wrap pattern.** The current wire is post-dispatch (soft-fire). Aggressive pre-emption needs background-process supervision in shell, which is fragile on Git Bash. Tracked as **N43** for v0.9.0+.
- **Real-LLM dogfood through `--coordinator`.** Would only be meaningful after N42 is shipped. Until then, there's no `--coordinator` path to dogfood.

## Patterns harvested

p012 (proposed): **Anti-presence-only AC.** When introducing a recovery wrapper or opt-in mode flag, the AC must include "function has ≥1 non-test caller in production code" or "flag has ≥1 read site outside flag-parsing assignment". Grep-based AC text alone passes for the *definition* and silently leaves the wire dead.

## Verification

- `tests/test_v081_wiring.sh`: 4/4 passed
- `tests/test_orchestrator_liveness.sh`: 34/34 passed (US-003 ceiling fix + v0.8.0 baseline preserved)
- `tests/test_quantum_loop_recovery.sh`: 5/5 passed (v0.8.0 baseline preserved)
- `tests/test_coordinator_dispatch.sh`: 7/7 passed (v0.8.0 baseline preserved)
- `tests/test_runner.sh`: 43/43 passed (US-004 copilot-hook flags landed)
- `tests/test_copilot_dispatch.sh`: 3/3 passed (US-004 ceiling bump)

## Notes for v0.9.0+ planning

The honest finding is that **v0.8.0 N33 closure was structurally complete but functionally inert** — the same root cause it claimed to close. v0.8.1 ships the minimal viable wires + a regression-guard test, but the *real* coordinator-driven dispatch (per-wave spawn, bounded context per invocation) remains future work. The architectural pattern that would actually break the manual-takeover streak is N42, which requires:

1. Replace single-spawn dispatch loop with wave-driven loop (read DAG, pick eligible wave, spawn coordinator, aggregate, loop).
2. The coordinator spawns implementer subagents per story (already partially supported in lib/spawn.sh).
3. Each wave is a fresh subagent context, breaking the "one long-running orchestrator" anti-pattern that drove drift.

This is genuinely architectural work — minor-tier scope. v0.8.1 is the diagnostic; v0.9.0 should be the cure.
