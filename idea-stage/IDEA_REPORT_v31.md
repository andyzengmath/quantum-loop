# IDEA_REPORT_v31 — what's open after v0.9.4

**Date:** 2026-05-01
**Source:** v0.9.4 closes audit-surfaced findings (1 HIGH + 4 MEDIUM + 1 LOW from `idea-stage/v0.9.x-arc-audit-2026-04-30.md`). v0.9.x track operationally CLOSED.
**Branch:** `ql/v0.9.4-bundle` (release tag v0.9.4 — pending)
**Predecessor:** `idea-stage/IDEA_REPORT_v30.md`

## Closed in v0.9.4

| ID | Story | Notes |
|---|---|---|
| Audit DC-001 (coordinator.md stale refs) | US-001 | 5 in-place edits + Liveness section corrected |
| Audit code-reviewer HIGH (per-story log) | US-002 | Gate behind `COORDINATOR_MODE != true` |
| Audit DC-002 (operator-facing docs) | US-003 | New "Coordinator-related" subsection in CLAUDE.md |
| Audit code-reviewer MEDIUM (next_wave coverage) | US-004 | Tests 17-20 in test_dag_query.sh; 44/44 |
| US-005 code-reviewer MEDIUM (L117 future-tense) | US-005 inline | Past-tense rewrite |
| US-005 code-reviewer LOW (CLAUDE.md enumeration) | US-005 inline | "Coordinator-related" added |

## Persistent canon

p001-p012 carried forward. **p013 + p014 ready for canonization** in a future cycle (see PIPELINE_REPORT_v31).

## v0.10.0 candidate slate (PRIMARY follow-up — architect-recommended)

The v0.9.x track is closed. v0.10.0 was originally framed as architect-recommended outer-loop replacement ("significant architectural work"), but the post-v0.9.4 design spike (`idea-stage/v0.10.0-design-spike-2026-05-01.md`) found the actual work is patch-tier in nature. **The "daemon-style runner" replacement was rejected via ADR-001** (`references/adr-001-outer-loop-architecture.md`): the existing Claude Code `/loop` cron pattern is the canonical outer-loop architecture; no persistent-daemon implementation will be built. v0.9.5 ships the spike-derived patch-tier work (decomposition + parent-side guard + this ADR).

### Pre-cycle design spike (3 architects)

| Spike | Question | Output |
|-------|----------|--------|
| 1 | Decompose `quantum-loop.sh` (1828 LOC) — extract iteration loop into `lib/iteration-loop.sh`. What's the right abstraction boundary? | Concrete decomposition plan + LOC budget. |
| 2 | ~~Define "daemon-style runner" concretely~~ — **RESOLVED via ADR-001 (2026-05-01).** Cron `/loop` pattern is canonical; no daemon implementation. | `references/adr-001-outer-loop-architecture.md` |
| 3 | Move `guard_head_advance` from coordinator-instruction-only to parent-side post-eval check. Defense-in-depth: if coordinator skips guard, parent catches it. Removes LLM-instruction-following dependency for safety-critical check. | Implementation sketch + impact on tests. |

### v0.10.0 candidate user stories (after design spike)

| Story | Content | Tier |
|-------|---------|------|
| US-001 | Decompose `quantum-loop.sh` per spike-1 output. Extract iteration loop into `lib/iteration-loop.sh`. CLI parsing + sourcing + entry-point dispatch stays in main file. | minor |
| US-002 | ~~Implement chosen daemon-style architecture~~ — **RESOLVED via ADR-001**; v0.9.5 US-003 ships the ADR; no daemon implementation. | (none) |
| US-003 | Parent-side `guard_head_advance` check per spike-3 output. | minor |
| US-004 | Pre-cycle multi-perspective review + post-cycle multi-perspective review. | LOW (process) |
| US-005 | Real-feature dogfood (first non-synthetic dispatch through new outer loop). | MEDIUM |
| US-006 | Retrospective + IDEA_REPORT_v32 + version bump 0.9.4 → 0.10.0. | LOW |

**Honest framing for v0.10.0:** This is the largest cycle since v0.9.0 (and possibly larger). Strongly recommend the operator scope it explicitly + give explicit go-ahead on each design-spike output before story implementation.

## Still open (carried forward)

### N46 (respawn output not re-parsed)

**Status:** unchanged. `ql_wrap_subagent_dispatch` gated OFF under coordinator mode (rationale documented in v0.9.3 US-002). v0.9.3 US-001 wallclock timeout is the operational alternative.
**Severity:** MEDIUM. **Path:** v0.10.0+ if wrap re-enabled (currently no compelling reason; the timeout works).

### N40, N43, N47, N48, N49, N50

All unchanged. LOW priority. **N47 (branch cleanup)** still operator-decision-pending — 19+ local branches now (v0.7.x..v0.9.4).

### Audit-deferred LOWs

- bash -c subshell scoping comment in quantum-loop.sh (architect MEDIUM ~70).
- redundant `${RUNNER_EXIT:-0}` default (code-reviewer LOW).
- 29-line comment-block density at quantum-loop.sh:1664-1692 (code-reviewer LOW).
- CLAUDE.md tilde line-number drift (architect LOW).
- 6 inline `jq > tmp && mv` migration (code-reviewer MEDIUM; v0.10.0 refactor).
- 3x duplicated COMPLETE/BLOCKED exit blocks (code-reviewer MEDIUM; v0.10.0 refactor).

All absorb naturally into v0.10.0 alongside structural refactors.

## Recurring observations

- **25 consecutive LOW G30 self-validations** (v0.6.5..v0.9.4).
- **Bundle size: ...4-7-5-5-4-6.** v0.9.4 is 6-story housekeeping (largest cycle since v0.9.0's 7-story minor).
- **Manual-takeover streak: BROKEN through v0.9.4.** Cron-driven /loop pattern handled v0.9.4 end-to-end.
- **p013 + p014 ready for canonization** as documented patterns.
- **Operator-staged kickoff** at `3edb044` (audit synthesis + design + PRD + advisory hooks) — 5th application; pattern stable.

## v0.9.x → v0.10.0 transition

v0.9.0 (architectural minor — wires) → v0.9.1 (validation patch — streak BROKEN) → v0.9.2 (defensive hardening — 5a CLOSED engineered) → v0.9.3 (operational hardening — iter-3 hang CLOSED) → v0.9.4 (housekeeping — audit findings CLOSED) → **v0.9.5 (post-spike patch — decomposition refactor + parent-side guard + ADR-001)** → v0.10.0+ (feature work or v0.9.6 housekeeping based on emerging needs; outer-loop replacement was rejected via ADR-001).

The v0.9.x arc is operationally closed. Next significant arc = v0.10.0. v0.9.5 patch-tier housekeeping NOT recommended (no remaining audit findings warrant it; deferred LOWs absorb into v0.10.0).
