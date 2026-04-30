# IDEA_REPORT_v29 — what's open after v0.9.2

**Date:** 2026-04-30
**Source:** v0.9.2 ships defensive hardening; 5a HIGH advisory closed empirically; iter-3 hang surfaced as v0.9.3 candidate.
**Branch:** `ql/v0.9.2-bundle` (release tag v0.9.2 — pending)
**Predecessor:** `idea-stage/IDEA_REPORT_v28.md`

## Closed in v0.9.2

| ID | Story | Notes |
|---|---|---|
| **5a HIGH** | US-001 + US-004 | Coordinator HEAD-snapshot guard engineered + empirically validated. Guard fired across 2 dogfood iterations. |
| **Code-reviewer MEDIUM** | US-002 | Legacy STORY_* case branches gated under coordinator mode (defense-in-depth). |
| **Architect MEDIUM** (filePaths) | US-003 | Advisory hook in next_wave preamble. |

## Persistent canon

p001-p012 carried forward. No new patterns this cycle. p013 (pre-cycle 3-architect + post-cycle 3-reviewer trio) candidate awaits 3rd application.

## v0.9.3 candidate slate (PRIMARY follow-up)

### Primary: 5a iter-3 hang (MEDIUM)

**Status:** new. v0.9.2 dogfood iteration 3 hung mid-`eval "$COORD_CMD"` for 3+ hours (operator killed parent shell). Iterations 1+2 worked correctly. The coordinator subagent (claude --print) appears to have stuck on a tool call OR hit a token-budget exhaustion in its own context after 2 prior iterations of complex tool work.
**Severity:** MEDIUM. Operational, not architectural — guard correctness is intact.
**Path:** Re-evaluate `ql_wrap_subagent_dispatch` STALE detection. v0.9.0 US-001 gated it OFF under coordinator mode (rationale: respawn would re-spawn entire wave with stale single-story args; full N46 fix deferred). v0.9.3 should:
1. Add a parent-side wallclock timeout on `eval "$COORD_CMD"` (e.g., 30 min ceiling).
2. Surface timeout as STORY_FAILED for all wave members; let parent retry-loop handle.
3. Optional: add LOC-budget alarm in coordinator instructions (heuristic: if coordinator's own context approaches token limit, emit WAVE_FAILED early rather than hang).

### Secondary candidates

- **N46 (respawn output not re-parsed)** — still unresolved. Currently gated OFF under coordinator mode at quantum-loop.sh:1657.
  **Severity:** MEDIUM. **Path:** v0.9.3+ if respawn semantics under coordinator mode are revisited alongside 5a iter-3 hang.

- **Real-feature dispatch validation** — synthetic plans don't exercise multi-file diffs or non-trivial work. v0.9.3 could fire a small REAL feature (e.g., a v0.9.x housekeeping task — N47 bundle cleanup?) through `--coordinator` to validate.
  **Severity:** MEDIUM. **Path:** v0.9.3 US-X (TBD which feature).

- **Coordinator bookkeeping commits formalization** — v0.9.2 dogfood observed coordinator voluntarily adding `chore: wave-N coordinator results` commits documenting decisions. Could be formalized in `agents/coordinator.md` for cleaner audit trail.
  **Severity:** LOW (cosmetic / docs). **Path:** v0.9.3+ housekeeping.

## Still open (carried forward)

### N43, N47, N48, N49, N50

All unchanged. LOW priority. **N47 (branch cleanup)** still operator-decision-pending — 18+ local branches now (v0.7.x..v0.9.2).

### N40, N38, copilot rate-limit observability, N41, N44, N45

All unchanged. LOW priority.

## Recommendation for next

**v0.9.3 candidate slate (patch-tier — closes iter-3 hang):**

| Story | Content |
|-------|---------|
| US-001 | Parent-side wallclock timeout on `eval "$COORD_CMD"` in `quantum-loop.sh`. Default 30 min ceiling; configurable via env var (e.g. `QL_COORDINATOR_TIMEOUT_S`). On timeout: kill subprocess; mark all wave members STORY_FAILED; let parent retry-loop handle. |
| US-002 | Re-evaluate gating `ql_wrap_subagent_dispatch` under coordinator mode. Either re-enable with adapted semantics (respawn entire wave, not single story) OR keep OFF with explicit comment. |
| US-003 | (Optional) Real-feature dogfood: pick a small housekeeping task (e.g., N47 bundle cleanup automation) and dispatch through `--coordinator`. Validates non-synthetic dispatch. |
| US-004 | Multi-perspective post-merge review (architect + code-reviewer + security via Agent tool). 5th cycle of this pattern (post-v0.8.1, v0.8.2, v0.8.3, v0.8.4, v0.9.1; SKIPPED in v0.9.2 because US-004 was dogfood). |
| US-005 | Retrospective + IDEA_REPORT_v30 + version bump 0.9.2 → 0.9.3. |

**Honest framing for v0.9.3:** patch-tier (closes operational gap surfaced by v0.9.2 iter-3 hang). Sets up potential v0.9.4 with full-autonomous real-feature dispatch.

## Recurring observations

- **23 consecutive LOW G30 self-validations** (v0.6.5..v0.9.2).
- **Bundle size: ...4-7-5-5.** v0.9.2 is 5-story defensive hardening (matches v0.9.1 N42-validate pattern at 5).
- **Manual-takeover streak: BROKEN at cycle 19 (v0.9.1).** Cycle 20 (v0.9.2) had partial manual takeover at iter-3 cleanup. Architectural success (guard works) but operational hand-off needed at iter-3.
- **Pre-cycle 3-architect + post-cycle 3-reviewer pattern validated 2nd time** (v0.9.0 + v0.9.1). v0.9.2 used US-004 for dogfood; review trio skipped this cycle.
- **Operator-staged kickoff** (design + PRD + advisory hooks committed at `cd7d764` before US-001) — same pattern as v0.9.1's `428c7ca`. Validates IDEA_REPORT pipeline as source-of-truth for follow-up scope.

## v0.9.x track outlook

v0.9.0 (architectural minor) → v0.9.1 (validation patch — streak BROKEN; 5a HIGH surfaced) → **v0.9.2 (defensive hardening — 5a CLOSED engineered + empirically validated; iter-3 hang surfaced)** → v0.9.3 (operational hardening — closes iter-3 hang; possibly real-feature dogfood) → v0.10.0+ (outer-loop replacement; architect-recommended deferred from v0.9.0).
