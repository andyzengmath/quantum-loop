# IDEA_REPORT_v35 — what's open after v0.10.1

**Date:** 2026-05-01
**Source:** v0.10.1 closes 6 audit-finding gaps (1 code + 5 doc) from operator-initiated 3-agent audit post-v0.10.0 ship.
**Branch:** `ql/v0.10.1-bundle` (release tag v0.10.1 — pending)
**Predecessor:** `idea-stage/IDEA_REPORT_v34.md`

## Closed in v0.10.1

| ID | Story | Notes |
|---|---|---|
| Architect Gap 1 (`lib/iteration-loop.sh:455-458` raw MAX_ITERATIONS) | US-001 T-001-1 | Migrated to emit_terminal_signal |
| Doc-specialist HIGH (ADR-001 stale `quantum-loop.sh:~1447-1838` refs) | US-001 T-001-2 | Annotated with post-decomposition location |
| Architect Gap 3 (IDEA_REPORT_v30 daemon-style without ADR cross-ref) | US-001 T-001-3 | Supersession blockquote added |
| Architect Gap 2 (silent-dropped N38/N41/N44/N45/copilot-rate-limit) | US-001 T-001-4 | Re-added to v34 carried-forward |
| Architect Gap 4 (lost STORY_ID validation deferral) | US-001 T-001-4 | Re-tracked as accepted-risk LOW |
| Architect Gap 5 (v34 bundle-count framing) | US-001 T-001-4 | Clarified |
| Multi-perspective review (10th application; ALL SHIP) | US-002 | No score-≥85 inline fixes |

## Persistent canon

p001-p014 carried forward. No new patterns. Both p013 (operator-staged kickoff) and p014 (composite review trio) canonized in CLAUDE.md per v0.10.0 US-004.

## v0.11.0+ candidate slate (post-architectural-arc + post-audit-cleanup)

The v0.9.x architectural arc + v0.10.0 PARALLEL_MODE extraction + v0.10.1 audit-cleanup are all CLOSED. There is no remaining architectural backlog. Future work falls into:

### Optional v0.10.2 patch (LOW-tier housekeeping; if scope warrants)

| Story | Content | Tier |
|-------|---------|------|
| US-001 | Real-feature dogfood (deferred from v0.10.0 US-003). | MEDIUM |
| US-002 | Dead `--argjson wave "$WAVE"` removal at `lib/parallel-mode.sh:306`. | LOW |
| US-003 | MAX_ITERATIONS argparse integer validation (security pre-existing LOW). | LOW |
| US-004 | Multi-perspective post-merge review (11th application). | LOW |
| US-005 | Retrospective + IDEA_REPORT_v36 + version bump 0.10.1 → 0.10.2. | LOW |

**Honest framing:** patch-tier; ~1.5 hours. Real-feature dogfood is the only meaningful work; everything else is LOW absorbs.

### Alternative: v0.11.0 feature-work return

Pivot to feature work — no specific scope queued. Operator decides direction.

## Still open (carried forward; LOW)

### N46 (respawn output not re-parsed) — MEDIUM

Unchanged. v0.9.3 wallclock timeout + v0.9.5 parent-side guard remain operational alternatives. v0.11.0+ if wrap re-enabled.

### N40, N43, N47, N48, N49, N50

LOW. **N47 (branch cleanup)** still operator-decision-pending — 22+ local branches now (v0.7.x..v0.10.1).

### N38, N41, N44, N45, copilot-rate-limit-observability

Re-added in v0.10.1 from silent-drop. LOW. No active path.

### STORY_ID format validation

Audit-deferred at `idea-stage/v0.9.x-arc-audit-2026-04-30.md:73`. Audit itself downgraded risk: "data is jq-injection-safe." Accepted-risk LOW; would warrant action only if STORY_ID flows into a filter-string interpolation site (none currently).

### Pre-existing LOWs from v0.10.0 review

- Trap RETURN re-entry (theoretical, security LOW).
- ANSI control-char passthrough in jq stderr (theoretical, security LOW).
- Dead `--argjson wave "$WAVE"` at `lib/parallel-mode.sh:306` (pre-existing).
- MAX_ITERATIONS argparse integer validation (pre-existing, security LOW).

## Recurring observations

- **29 consecutive LOW G30 self-validations** (v0.6.5..v0.10.1).
- **Bundle size sequence: ...4-7-5-5-4-6-5-5-6-3.** v0.10.1 = 3 stories (smallest patch since v0.6.x era).
- **Manual-takeover streak: PARTIALLY BROKEN through v0.10.1** — story execution autonomous; kickoff scope-ratification needed once per cycle (audit-finding closure also counts; same posture as v0.9.6 + v0.10.0).
- **p013 (operator-staged kickoff): 9 applications.**
- **p014 (composite review trio): 10 review applications + 5 architect-design applications + 1 doc-vs-code audit (3-agent) application.**
- **Pre-cycle audit-doc reading discipline holding** (no scope-error rollback in v0.10.0 or v0.10.1).
- **NEW pattern candidate:** "post-cycle 3-agent doc-vs-code audit" — applied once after v0.10.0 (this cycle's source). If applied a second time, consider canonizing as p015.

## v0.10.0 → v0.10.1 → v0.11.0 transition

```
v0.10.0 (minor — PARALLEL_MODE extraction; v0.9.x architectural arc CLOSED)
  → v0.10.1 (patch — audit-driven doc-cleanup + 1 code fix)
  → v0.10.2 (optional patch — real-feature dogfood + LOW absorbs)
     OR
  → v0.11.0 (feature-work return; no architectural backlog forced)
```

The v0.9.x → v0.10.0 architectural arc is fully closed AND fully documented (after v0.10.1). Future cycles do not have a forced architectural agenda.
