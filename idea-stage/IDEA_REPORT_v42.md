# IDEA_REPORT_v42 — what's open after v0.10.8

**Date:** 2026-05-02
**Source:** v0.10.8 ships wave-plan cycle-3 (N48 field-ownership runtime enforcement + ANSI passthrough sanitization).
**Branch:** `ql/v0.10.8-bundle` (release tag v0.10.8 — pending)
**Predecessor:** `idea-stage/IDEA_REPORT_v41.md`

## Closed in v0.10.8

| ID | Story | Notes |
|---|---|---|
| N48 (field-ownership runtime enforcement) | US-001 | Snapshot-diff WARN at coordinator-mode dispatch boundary; observability-only |
| ANSI control-char passthrough | US-002 | sed CSI strip + tr non-printable strip in json_atomic_update* error paths |
| 17th p014 review trio | US-003 | All SHIP (91/88/92); no score-≥85 inline fixes |

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

- **N50, N49, N48:** CLOSED.
- **N44:** v0.10.9 candidate.
- **N40, N41, N38, N45, N43, N47:** v0.10.9 investigation (some likely obsolete post-decomposition).

### Pre-existing security LOWs

- (ANSI control-char passthrough — CLOSED in v0.10.8.)
- (Trap RETURN re-entry — CLOSED in v0.10.6.)

### New from v0.10.8 review

- **N48 stub-coordinator test coverage** — MEDIUM (sub-threshold); deferred to v0.11.0 dogfood (need real-coordinator violation case).
- **OSC sequence body residue** — LOW; cosmetic, non-exploitable, future hardening.

## Recurring observations

- **36 consecutive LOW G30 self-validations** (v0.6.5..v0.10.8).
- **Bundle size sequence: ...3-4-4-4.** v0.10.8 = 4 stories.
- **Manual-takeover streak: PARTIALLY BROKEN through v0.10.8** — 10 consecutive cycles with 1 operator gate (at v0.10.6 wave plan approval; v0.10.7 + v0.10.8 ran fully autonomous on cron).
- **p013 (operator-staged kickoff): 16 applications.**
- **p014 (composite review trio): 17 review applications.** 5 review-gate catches in 17 applications (~29% hit-rate).
- **p015 (post-cycle 3-agent doc-vs-code audit): 3 applications, canonized at 2.**
- **p016 candidate (dogfood-driven LOW sweep wave): 3/4 cycles complete.** Canonization possible after v0.10.9.

## v0.10.8 → v0.11.0 transition

```
v0.10.6 (wave-cycle-1: N50 + Trap RETURN) ✓
v0.10.7 (wave-cycle-2: copilot-rate-limit + N49 closure) ✓
v0.10.8 (wave-cycle-3: N48 + ANSI sanitization) ✓ ← THIS CYCLE
v0.10.9 (wave-cycle-4: N44 + N40-47 closeout) ← NEXT
v0.11.0 (operator-gated --coordinator dispatch)
```
