# IDEA_REPORT_v30 — what's open after v0.9.3

**Date:** 2026-04-30
**Source:** v0.9.3 ships parent-side wallclock timeout closing v0.9.2's iter-3 hang. 18/18 tests green. Multi-perspective review surfaced 1 HIGH + 1 MEDIUM (both inline-fixed).
**Branch:** `ql/v0.9.3-bundle` (release tag v0.9.3 — pending)
**Predecessor:** `idea-stage/IDEA_REPORT_v29.md`

## Closed in v0.9.3

| ID | Story | Notes |
|---|---|---|
| **5a iter-3 hang** | US-001 | Parent-side `timeout` wrap; default 1800s; configurable. |
| **ql_wrap re-evaluation** | US-002 | KEEP OFF documented; rationale + cross-ref to US-001. |
| **Code-reviewer HIGH (FR-1)** | US-003 | `command -v timeout` guard with WARN fallback. |
| **Code-reviewer MEDIUM (numeric validation)** | US-003 | Regex check + WARN + default on bad input. |

## Persistent canon

p001-p012 carried forward. No new patterns. Multi-perspective review pattern at 5 applications (post-v0.8.1, v0.8.2, v0.8.3, v0.8.4, v0.9.1, v0.9.3).

## v0.9.4 candidate slate (low-priority housekeeping)

The substantive v0.9.x work is largely complete. v0.9.4 would be a smaller housekeeping cycle if pursued.

| Story | Content | Severity |
|-------|---------|----------|
| US-001 | (Optional) Real-feature dogfood — pick small task (e.g., one of the LOW backlog items) and dispatch through `--coordinator` end-to-end. Validates non-synthetic behavior. | MEDIUM |
| US-002 | Architect MEDIUM (~70): one-line `bash -c "$COORD_CMD"` comment in quantum-loop.sh noting subshell-scoping constraint for future runner authors. | LOW |
| US-003 | Code-reviewer LOW: simplify `${RUNNER_EXIT:-0}` to `$RUNNER_EXIT` (RUNNER_EXIT initialized at line ~1578; default redundant). | LOW |
| US-004 | Multi-perspective post-merge review (architect + code-reviewer + security). 6th application. | LOW |
| US-005 | Retrospective + IDEA_REPORT_v31 + version bump 0.9.3 → 0.9.4. | LOW |

**Honest framing:** v0.9.4 candidate slate is mostly cosmetic + 1 optional dogfood. The v0.9.x track has reached structural maturity. The next significant cycle would be **v0.10.0** (architect-recommended outer-loop replacement; deferred from v0.9.0).

## Still open (carried forward)

### N46 (respawn output not re-parsed)

**Status:** unchanged. `ql_wrap_subagent_dispatch` gated OFF under coordinator mode (rationale documented in v0.9.3 US-002 comment). The v0.9.3 US-001 wallclock timeout is the operational alternative.
**Severity:** MEDIUM. **Path:** v0.9.4+ if wrap re-enabled (currently no compelling reason).

### N43, N47, N48, N49, N50

All unchanged. LOW priority.

### N40, N38, copilot rate-limit observability, N41, N44, N45

All unchanged. LOW priority.

## v0.10.0 candidate slate (next major arc)

Architect-recommended in v0.9.0 retrospective: **outer-loop replacement**. Replace `quantum-loop.sh`'s for-loop iteration mechanism with a daemon-style runner. Out of scope for v0.9.x. Significant architectural work.

**Why deferred:** v0.9.x focused on per-wave coordinator dispatch + closing operational gaps. v0.10.0 would tackle the outer iteration loop itself.

## Recurring observations

- **24 consecutive LOW G30 self-validations** (v0.6.5..v0.9.3).
- **Bundle size: 7-7-7-7-5-6-5-3-7-3-2-4-3-3-7-7-5-5-4-4-7-5-5-4.** v0.9.3 is 4-story (smallest in 25 cycles).
- **Manual-takeover streak: BROKEN through v0.9.3.** Cron-driven /loop pattern handled v0.9.3 end-to-end.
- **Multi-perspective review pattern validated 5th time** (architectural-tier + post-merge-review combined). p013 candidate (after 1 more application).
- **Operator-staged kickoff** at `11a033e` (design + PRD + advisory hooks) — 4th application of pattern (after v0.9.0/v0.9.1/v0.9.2 kickoffs). Should be formalized as p013.

## v0.9.x track outlook

v0.9.0 (architectural minor — wires) → v0.9.1 (validation patch — streak BROKEN) → v0.9.2 (defensive hardening — 5a CLOSED engineered) → **v0.9.3 (operational hardening — iter-3 hang CLOSED engineered)** → v0.9.4 (optional housekeeping; minor cleanup) → **v0.10.0** (architect-recommended outer-loop replacement; significant architectural work; not yet scoped).

The v0.9.x track has reached operational + structural maturity. Time to consider whether v0.9.4 housekeeping is worth a cycle, OR pivot directly to v0.10.0 design phase.
