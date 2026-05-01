# IDEA_REPORT_v33 — what's open after v0.9.6

**Date:** 2026-05-01
**Source:** v0.9.6 closes 4 mechanical-cleanup items deferred from v0.9.5 (audit MEDIUM jq migration; audit MEDIUM signal-helper extraction; audit LOW CLAUDE.md drift; 3 LOW absorbs).
**Branch:** `ql/v0.9.6-bundle` (release tag v0.9.6 — pending)
**Predecessor:** `idea-stage/IDEA_REPORT_v32.md`

## Closed in v0.9.6

| ID | Story | Notes |
|---|---|---|
| Audit MEDIUM (6 jq+tmp+mv migration) | US-001 | Required `json_atomic_update_args` variant prerequisite |
| Audit MEDIUM (3 production-path COMPLETE/BLOCKED dedup) | US-002 | `emit_terminal_signal` helper extraction |
| Audit LOW (CLAUDE.md tilde line-number drift) | US-003 | `quantum-loop.sh:~1592` → `lib/iteration-loop.sh:~212` |
| Code-reviewer LOW (`${RUNNER_EXIT:-0}` redundant default) | US-003 | Init at line 172 verified |
| Code-reviewer LOW (29-line comment-block density) | US-003 | Split into 4 subsections |
| Audit LOW (bash -c subshell scoping comment) | US-003 | 1-line clarifier added |
| US-004 architect F2 (Test 12 ambiguous label) | US-004 inline | Split 12a/12b |
| US-004 code-reviewer LOW (CLAUDE.md `~208` → `~212`) | US-004 inline | Disambiguated comment vs dispatch line |

## Persistent canon

p001-p012 carried forward. **p013 + p014 ready for canonization** (now both 7+ applications; v0.9.6 was the 8th p014 application). Operator decision pending. Strong recommendation: canonize in v0.10.0 codebasePatterns block alongside the PARALLEL_MODE extraction milestone.

## v0.10.0 candidate slate (REVISED — post-v0.9.6 closure)

The v0.9.x track is now operationally + structurally + housekeeping-CLOSED. v0.10.0 has a lean scope:

| Story | Content | Tier |
|-------|---------|------|
| US-001 | PARALLEL_MODE block extraction from `quantum-loop.sh` (~390 LOC + 8 jq+tmp+mv sites + 1 COMPLETE/BLOCKED pair migrate at the same time) | minor |
| US-002 | `2>/dev/null` symmetric hardening of `json_atomic_update` + `json_atomic_update_args` (capture jq stderr into error message; DEFER from v0.9.6 US-004 review) | patch |
| US-003 | Real-feature dogfood (first non-synthetic dispatch through decomposed + guarded outer loop). MEDIUM. | MEDIUM |
| US-004 | p013 + p014 canonization in `quantum.json.codebasePatterns` (8 each application track record) | LOW |
| US-005 | Multi-perspective post-merge review (9th application) | LOW |
| US-006 | Retrospective + IDEA_REPORT_v34 + version bump 0.9.6 → 0.10.0 | LOW |

**Honest framing for v0.10.0:** Mostly minor-tier (PARALLEL_MODE extraction is the architectural milestone; everything else is patch-or-process). Effort estimate: ~5-6 hours, similar to v0.9.5. v0.10.0 honors the architectural milestone of "decomposition complete + ADR-001 baked in" with the version bump, even though 4 of 6 stories are individually patch-tier.

**Alternative path:** v0.9.7 patch focused on US-002/003/004 (skip PARALLEL_MODE extraction). Reserves v0.10.0 for an actual architectural inflection point. But: PARALLEL_MODE extraction is the only remaining minor-tier candidate from the entire v0.9.x audit; deferring it indefinitely leaves the audit-MEDIUM list non-empty.

## Still open (carried forward)

### N46 (respawn output not re-parsed)

**Status:** unchanged. `ql_wrap_subagent_dispatch` gated OFF under coordinator mode. v0.9.3 wallclock timeout + v0.9.5 parent-side guard are the operational alternatives.
**Severity:** MEDIUM. **Path:** v0.10.0+ if wrap re-enabled (currently no compelling reason).

### N40, N43, N47, N48, N49, N50

All unchanged. LOW priority. **N47 (branch cleanup)** still operator-decision-pending — 21+ local branches now (v0.7.x..v0.9.6).

## Recurring observations

- **27 consecutive LOW G30 self-validations** (v0.6.5..v0.9.6).
- **Bundle size sequence: ...4-7-5-5-4-6-5-5.** v0.9.6 = 5 stories (matches v0.9.5).
- **Manual-takeover streak: PARTIALLY BROKEN through v0.9.6** — story execution autonomous; kickoff scope-ratification needed once. Net result of `feedback_autonomous_kickoff_caution.md` save: autonomous-kickoff gated on operator ratification when scope assumes unverified facts.
- **Pre-cycle audit-doc reading discipline strengthened** post-rollback. Lesson: `idea-stage/v*-audit*.md` files MUST be read line-by-line before scoping a cycle that touches their items.
- **p013 (operator-staged kickoff): 7th application** (v0.9.0-v0.9.6). Pattern stable; canonize in v0.10.0.
- **p014 (composite review trio): 8 review applications** post-v0.8.x. Pattern stable; canonize in v0.10.0.

## v0.9.x → v0.10.0 transition

v0.9.0 (architectural minor — wires) → v0.9.1 (validation patch — streak BROKEN) → v0.9.2 (defensive hardening — 5a CLOSED) → v0.9.3 (operational hardening — iter-3 hang CLOSED) → v0.9.4 (housekeeping — audit findings CLOSED) → v0.9.5 (post-spike patch — decomposition + parent-side guard + ADR-001 CLOSED) → **v0.9.6 (post-decomp cleanup — jq+signal+doc audit items CLOSED)** → **v0.10.0 (PARALLEL_MODE extraction + 2>/dev/null hardening + first dogfood + p013/p014 canonization).**

The v0.9.x arc is **fully closed** including all audit-flagged housekeeping. v0.10.0 has a clean architectural milestone (PARALLEL_MODE) + small patch-tier deferrals.
