# IDEA_REPORT_v34 — what's open after v0.10.0

**Date:** 2026-05-01
**Source:** v0.10.0 closes the LAST v0.9.x architectural-arc item (PARALLEL_MODE extraction) + housekeeping. Architectural backlog is empty.
**Branch:** `ql/v0.10.0-bundle` (release tag v0.10.0 — pending)
**Predecessor:** `idea-stage/IDEA_REPORT_v33.md`

## Closed in v0.10.0

| ID | Story | Notes |
|---|---|---|
| Audit MEDIUM (PARALLEL_MODE block extraction; last v0.9.x item) | US-001 | quantum-loop.sh 793 → 411 LOC; lib/parallel-mode.sh 427 LOC |
| Audit MEDIUM (8 deferred PARALLEL_MODE jq+tmp+mv) | US-001 T-001-2 | All migrated to json_atomic_update_args |
| Audit MEDIUM (1 deferred PARALLEL_MODE COMPLETE/BLOCKED pair + bonus MAX_ITERATIONS) | US-001 T-001-3 | parallel-mode.sh side migrated; **iteration-loop.sh side closed in v0.10.1 US-001 T-001-1** (v0.10.0 retro claim was over-broad — see v0.10.1 retro footnote) |
| v0.9.6 US-004 deferred jq stderr swallow (parity-with-existing) | US-002 | Symmetric hardening on both helpers |
| Process pattern formalization (p013 + p014) | US-004 | Canonized in CLAUDE.md |
| Multi-perspective review (9th application; ALL SHIP) | US-005 | No score-≥85 inline fixes; both MEDIUMs are pre-existing/AC-letter |

## Closed earlier in v0.9.x track

The full v0.9.x audit-arc closure (cumulative through v0.10.0):

| Cycle | Closure |
|---|---|
| v0.9.0 | N42 wires (per-wave coordinator dispatch) |
| v0.9.1 | Validation patch (manual-takeover streak BROKEN empirically) |
| v0.9.2 | 5a HIGH closed (HEAD-snapshot guard via lib/coordinator-guard.sh) |
| v0.9.3 | iter-3 hang closed (QL_COORDINATOR_TIMEOUT_S timeout(1) wallclock) |
| v0.9.4 | Audit-housekeeping (1 HIGH + 4 MEDIUM + 2 LOW from v0.9.x audit) |
| v0.9.5 | Decomposition (1837 → 793 LOC) + parent-side guard + ADR-001 |
| v0.9.6 | jq+tmp+mv migration (6 sites + json_atomic_update_args variant) + emit_terminal_signal helper + CLAUDE.md doc sync |
| **v0.10.0** | **PARALLEL_MODE extraction (793 → 411 LOC) + jq stderr symmetric hardening + p013/p014 canonization** |

## Persistent canon

p001-p014 all carried forward. **No new patterns identified for v0.10.0 cycle** (the cycle was about CLOSING patterns, not discovering new ones).

## v0.10.1+ candidate slate (post-architectural-closure)

The v0.9.x architectural arc is COMPLETE. Remaining items are LOW-tier housekeeping or feature work.

### Optional v0.10.1 patch (if scope warrants)

| Story | Content | Tier |
|-------|---------|------|
| US-001 | Real-feature dogfood (deferred from v0.10.0 US-003). Dispatch a small (1-3 story) feature bundle through `quantum-loop.sh --coordinator`; observe end-to-end through the now-fully-decomposed + guarded outer loop. | MEDIUM |
| US-002 | Dead `--argjson wave "$WAVE"` removal at `lib/parallel-mode.sh:306` (pre-existing from master; jq silently ignores). | LOW |
| US-003 | Multi-perspective post-merge review (10th application). | LOW |
| US-004 | Retrospective + IDEA_REPORT_v35 + version bump 0.10.0 → 0.10.1. | LOW |

**Honest framing for v0.10.1:** patch-tier (LOW + 1 MEDIUM dogfood). Effort estimate: ~2 hours. Dogfood is the only meaningful work; everything else is LOW absorbs.

### Alternative: feature-work return path

The v0.9.x track was driven by the post-v0.6.x architectural arc (DAG → coordinator dispatch → decomposition → ADR-001). With that arc closed, v0.10.x+ can pivot to feature work — e.g., new runner support (Cursor, Cline), new pipeline capabilities (multi-machine via ADR-001 trigger 4), or end-user ergonomics (TUI, dashboard, real-time progress).

No specific feature scope is queued. Operator decides direction post-v0.10.0 ship.

## Still open (carried forward; LOW)

### N46 (respawn output not re-parsed)

**Status:** unchanged. `ql_wrap_subagent_dispatch` gated OFF under coordinator mode. v0.9.3 wallclock timeout + v0.9.5 parent-side guard remain the operational alternatives.
**Severity:** MEDIUM. **Path:** v0.10.x+ if wrap re-enabled (no compelling reason currently).

### N40, N43, N47, N48, N49, N50

All unchanged. LOW priority. **N47 (branch cleanup)** still operator-decision-pending — 22+ local branches now (v0.7.x..v0.10.0).

### N38, N41, N44, N45, copilot-rate-limit-observability (re-added v0.10.1)

Last carried-forward in `IDEA_REPORT_v30.md:46`; absent from v31-v34 without explicit closure or rationale. Re-added in v0.10.1 doc-cleanup cycle for honest tracking. All sub-threshold LOW; re-acknowledged in case any later cycle wants to act on them. Severity unchanged from original audit.

### STORY_ID format validation under coordinator mode

Original audit deferral at `idea-stage/v0.9.x-arc-audit-2026-04-30.md:73`. The audit itself downgraded risk: *"data is jq-injection-safe"* — STORY_ID flows through `--arg` safe-binding in all current call sites. Re-tracked here in v0.10.1 doc-cleanup as accepted-risk LOW; would warrant action only if STORY_ID ever flows into a filter-string interpolation site (none currently exist; existing inline-validated callers in `lib/iteration-loop.sh:360,364,367` are the safety floor (v0.10.2 line-ref correction)).

### Trap RETURN re-entry (theoretical, security LOW)

If a future caller wraps `json_atomic_update*` in a function that itself uses `trap ... RETURN`, the inner trap silently replaces the outer. Currently no such call sites. v0.10.x+ if introduced.

### ANSI control-char passthrough (theoretical, security LOW)

`printf "  %s\n" "$err"` passes captured jq stderr through to operator terminal. Theoretical concern only — operator owns quantum.json content. v0.10.x+ if structured logging is added.

## Recurring observations

- **28 consecutive LOW G30 self-validations** (v0.6.5..v0.10.0).
- **Bundle size sequence: ...4-7-5-5-4-6-5-5-6.** v0.10.0 = 5 shipped + 1 deferred (US-003 dogfood deferred to v0.10.1+; counted in PRD planning, not in shipped delivery).
- **Manual-takeover streak: PARTIALLY BROKEN through v0.10.0** — story execution autonomous; kickoff scope-ratification needed (v0.9.6 + v0.10.0 each took 1 operator gate). v0.9.3-v0.9.5 fully autonomous.
- **p013 (operator-staged kickoff): 8 applications.**
- **p014 (composite review trio): 9 review applications + 5 architect-design applications.**
- **Pre-cycle audit-doc reading discipline holding** post-v0.9.6 rollback: every v0.10.0 PRD reference checked against source code before commit (e.g., re-verifying PARALLEL_MODE block boundaries via `grep + awk` before extraction).

## v0.9.x → v0.10.0 → v0.10.x transition

```
v0.9.0 (architectural minor — wires)
  → v0.9.1 (validation patch — streak BROKEN)
  → v0.9.2 (defensive hardening — 5a CLOSED)
  → v0.9.3 (operational hardening — iter-3 hang CLOSED)
  → v0.9.4 (audit housekeeping)
  → v0.9.5 (post-spike patch — decomposition + parent-side guard + ADR-001)
  → v0.9.6 (post-decomp cleanup — jq + signal + doc audit items)
  → v0.10.0 (PARALLEL_MODE extraction + jq stderr hardening + p013/p014 canon)
  → v0.10.x+ (LOW housekeeping OR feature work — operator decides)
```

The v0.9.x architectural arc is **fully closed**. Future cycles do not have a forced architectural agenda.
