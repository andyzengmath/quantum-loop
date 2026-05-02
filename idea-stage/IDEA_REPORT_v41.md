# IDEA_REPORT_v41 — what's open after v0.10.7

**Date:** 2026-05-02
**Source:** v0.10.7 ships wave-plan cycle-2 (copilot-rate-limit observability + N49 implicit-closure verification).
**Branch:** `ql/v0.10.7-bundle` (release tag v0.10.7 — pending)
**Predecessor:** `idea-stage/IDEA_REPORT_v40.md`

## Closed in v0.10.7

| ID | Story | Notes |
|---|---|---|
| Copilot rate-limit observability | US-001 | post_output hook in runners/hooks/copilot-hooks.sh |
| N49 (single-jq bulk-update for WAVE_* branches) | US-002 | Implicitly closed by v0.9.0 N42 wires; tracking lapse, not unfinished work |
| Retry-After extraction MEDIUM (US-003 review) | inline | sed capture-group anchored on 'retry-after' |
| 16th p014 review trio | US-003 | All SHIP (88/88/95); 1 MEDIUM inline-fixed |

## v0.10.8 (next, per wave plan)

| Story | Content | Tier |
|-------|---------|------|
| US-001 | **N48** — field-ownership runtime enforcement (snapshot-diff guard) | LOW |
| US-002 | **ANSI control-char passthrough sanitization** (security LOW) | LOW |
| US-003 | 17th p014 review | LOW |
| US-004 | Retrospective + IDEA_REPORT_v42 + version bump 0.10.7 → 0.10.8 | LOW |

## v0.10.9 (final wave cycle, per plan)

| Story | Content | Tier |
|-------|---------|------|
| US-001 | **N44** — CSV/PIPELINE_REPORT count reconciliation | LOW |
| US-002 | Investigate + close-or-defer **N40, N41, N38, N45, N43, N46, N47** | LOW (process) |
| US-003 | 18th p014 review | LOW |
| US-004 | Wave-plan retrospective + IDEA_REPORT_v43 + version bump 0.10.8 → 0.10.9 | LOW |

## v0.11.0 (OPERATOR-GATED)

**Reserved for the FIRST actual `--coordinator` dispatch on the live repo.**

## Standing backlog

### Real-feature dogfood (canonized v0.10.4 / US-003)

**Status:** UNCHANGED — blocked-on-operator-feature-queue. Wave plan converts LOW backlog INTO dogfood subjects for a future operator-run dispatch session.

## Still open

### N46 (respawn output not re-parsed) — MEDIUM

Will be evaluated in v0.10.9 closeout investigation.

### Other N-numbers (in wave plan)

- **N50, N49:** CLOSED.
- **N48:** v0.10.8 candidate.
- **N44:** v0.10.9 candidate.
- **N40, N41, N38, N45, N43, N47:** v0.10.9 investigation (some likely obsolete post-decomposition).

### Pre-existing security LOWs

- ANSI control-char passthrough — v0.10.8 (this cycle's deferral).
- (Trap RETURN re-entry — CLOSED in v0.10.6.)

### New from v0.10.7 review

- Retry-After multi-line edge cases — LOW; current extraction handles common single-line forms.

## Recurring observations

- **35 consecutive LOW G30 self-validations** (v0.6.5..v0.10.7).
- **Bundle size sequence: ...3-4-4.** v0.10.7 = 4 stories.
- **Manual-takeover streak: PARTIALLY BROKEN through v0.10.7** — 9 consecutive cycles with 1 operator gate (at v0.10.6 wave plan approval; v0.10.7 ran fully autonomous on cron).
- **p013 (operator-staged kickoff): 15 applications.**
- **p014 (composite review trio): 16 review applications.** 5 review-gate catches in 16 applications (~31% hit-rate).
- **p015 (post-cycle 3-agent doc-vs-code audit): 3 applications, canonized at 2.**
- **p016 candidate (dogfood-driven LOW sweep wave): 2/4 cycles complete.**

## v0.10.7 → v0.11.0 transition

```
v0.10.6 (wave-cycle-1: N50 + Trap RETURN)
  → v0.10.7 (wave-cycle-2: copilot-rate-limit + N49 closure)
  → v0.10.8 (wave-cycle-3: N48 + ANSI passthrough)
  → v0.10.9 (wave-cycle-4: N44 + N40-47 investigation)
  → v0.11.0 (OPERATOR-GATED; first --coordinator dispatch on live repo)
```
