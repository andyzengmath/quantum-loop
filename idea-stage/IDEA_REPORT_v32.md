# IDEA_REPORT_v32 — what's open after v0.9.5

**Date:** 2026-05-01
**Source:** v0.9.5 closes spike-derived patch-tier work (1 architect MEDIUM decomposition + 1 architect MEDIUM parent-side guard + 1 ADR + 2 review-inline MEDIUMs). v0.9.x track FULLY CLOSED.
**Branch:** `ql/v0.9.5-bundle` (release tag v0.9.5 — pending)
**Predecessor:** `idea-stage/IDEA_REPORT_v31.md`

## Closed in v0.9.5

| ID | Story | Notes |
|---|---|---|
| Architect MEDIUM (decomposition) | US-001 | 1837 → 793 LOC; 3 sub-tasks; behavior-preserving extraction |
| Architect MEDIUM (parent-side guard) | US-002 | guard_head_advance hooked into iteration loop; Test 8 head_reset added |
| Spike 2 ("daemon-style" framing) | US-003 | ADR-001 ACCEPTED; cron `/loop` canonical; no daemon |
| US-004 code-reviewer MEDIUM (ADR letter C) | US-004 inline | Cross-ref note + restored letter C |
| US-004 security MEDIUM (guard stderr) | US-004 inline | Removed `2>/dev/null` from guard call |

## Persistent canon

p001-p012 carried forward. **p013 + p014 ready for canonization** in v0.10.0 (formalization pending operator decision; both have strong empirical track record now: p013 6x, p014 composite 7+5).

## v0.10.0 candidate slate (REVISED — post-spike + post-v0.9.5)

The architect's original "v0.10.0 = significant architectural work" framing was reframed by the design spike + ratified by ADR-001. **v0.10.0 is now materially smaller than originally projected.** Decomposition + parent-side guard + ADR have all shipped in v0.9.5. What remains:

### v0.10.0 candidate user stories (revised)

| Story | Content | Tier |
|-------|---------|------|
| US-001 | `PARALLEL_MODE` block extraction from `quantum-loop.sh` (~390 LOC; deferred from v0.9.5 US-001 due to worktree-state plumbing complexity) | minor |
| US-002 | 6 inline `jq > tmp && mv` migration to `json_atomic_update` (architect MEDIUM from v0.9.x audit) | patch |
| US-003 | 3x duplicated COMPLETE/BLOCKED exit blocks dedup (architect MEDIUM from v0.9.x audit) | patch |
| US-004 | LOW absorbs: `${RUNNER_EXIT:-0}` redundant default; comment-block density at quantum-loop.sh:1664-1692 (now shifted post-decomposition); CLAUDE.md tilde line-number drift; bash -c subshell scoping comment | LOW |
| US-005 | Real-feature dogfood (first non-synthetic dispatch through decomposed + guarded outer loop) — pattern-validating | MEDIUM |
| US-006 | p013 + p014 canonization in `quantum.json.codebasePatterns` (formalization vote) | LOW |
| US-007 | Multi-perspective post-merge review (8th application) | LOW (process) |
| US-008 | Retrospective + IDEA_REPORT_v33 + version bump 0.9.5 → 0.10.0 | LOW |

**Honest framing for v0.10.0:** PATCH-tier housekeeping if US-001 (PARALLEL_MODE extraction) defers; MINOR-tier with US-001 included. Operator-decision-pending. No architectural surface change — version bump to 0.10.0 honors the ADR + decomposition milestone, not new architecture.

**Alternative path:** continue v0.9.x with v0.9.6 patch focused on US-002/US-003/US-004 deferrals + US-005 dogfood. Reserves v0.10.0 for an actual architectural inflection point (e.g., multi-machine dispatch per ADR-001 trigger 4).

## Still open (carried forward)

### N46 (respawn output not re-parsed)

**Status:** unchanged. `ql_wrap_subagent_dispatch` gated OFF under coordinator mode. v0.9.3 US-001 wallclock timeout + v0.9.5 US-002 parent-side guard are the operational alternatives.
**Severity:** MEDIUM. **Path:** v0.10.0+ if wrap re-enabled (currently no compelling reason).

### N40, N43, N47, N48, N49, N50

All unchanged. LOW priority. **N47 (branch cleanup)** still operator-decision-pending — 20+ local branches now (v0.7.x..v0.9.5).

### Audit-deferred LOWs

All unchanged from v0.9.4 deferral list, plus:
- CLAUDE.md tilde line-number drift now WORSE post-decomposition (US-003 references `quantum-loop.sh:~1592`, but extraction shifted that ~700 lines into `lib/iteration-loop.sh`).

## Recurring observations

- **26 consecutive LOW G30 self-validations** (v0.6.5..v0.9.5).
- **Bundle size: ...4-7-5-5-4-6-5.** v0.9.5 is 5-story patch (smaller than v0.9.4's 6).
- **Manual-takeover streak: BROKEN through v0.9.5** (3rd consecutive cycle).
- **p013 + p014 still ready for canonization** — empirical evidence keeps strengthening.
- **Operator-staged kickoff** at `ccf2cd9` (6th application; pattern stable).
- **Pre-cycle design spike pattern (3-architect)** validated for the 2nd time. v0.9.5's spike caught the most consequential drift to date — it killed an entire over-engineered cycle.

## v0.9.x → v0.10.0 transition

v0.9.0 (architectural minor — wires) → v0.9.1 (validation patch — streak BROKEN) → v0.9.2 (defensive hardening — 5a CLOSED engineered) → v0.9.3 (operational hardening — iter-3 hang CLOSED) → v0.9.4 (housekeeping — audit findings CLOSED) → **v0.9.5 (post-spike patch — decomposition + parent-side guard + ADR-001 CLOSED)** → **v0.10.0 (revised scope — structural cleanup + first real-feature dogfood; daemon-style explicitly rejected via ADR-001).**

The v0.9.x arc is **fully closed**. v0.10.0 is the next cycle.
