# IDEA_REPORT_v40 — what's open after v0.10.6

**Date:** 2026-05-02
**Source:** v0.10.6 ships wave-plan cycle-1 work content (N50 + Trap RETURN). v0.11.0 minor reserved for first operator-run `--coordinator` dispatch session.
**Branch:** `ql/v0.10.6-bundle` (release tag v0.10.6 — pending)
**Predecessor:** `idea-stage/IDEA_REPORT_v39.md`

## Closed in v0.10.6

| ID | Story | Notes |
|---|---|---|
| N50 (Iter/Wave counter naming) | US-001 | `WAVE` → `WAVE_COUNTER` in lib/parallel-mode.sh |
| Trap RETURN re-entry hardening | US-002 | Docstring caveat on both helpers + Test 15 (3 asserts) |
| Cross-reference gap on json_atomic_update | US-003 inline | Inline-fixed at bb4e745 |
| 15th p014 review trio | US-003 | All SHIP (88/88/92); 1 MEDIUM inline-fixed |

## Persistent canon

p001-p015 carried forward. Wave plan candidate **p016 (dogfood-driven LOW sweep)** in progress; needs 2 applications + retros to canonize.

## v0.10.7+ candidate slate (per wave plan)

Wave plan: `.omc/plans/2026-05-02-v0.11.0-wave-dogfood-driven-low-sweep.md`. Re-numbered after v0.10.6:

### v0.10.7 (next patch)

| Story | Content | Tier |
|-------|---------|------|
| US-001 | **N49** — bulk-update single-jq optimization for WAVE_* branches | LOW |
| US-002 | **copilot-rate-limit-observability** — visibility feature for rate-limit hits | LOW |
| US-003 | Multi-perspective post-merge review (16th application) | LOW |
| US-004 | Retrospective + IDEA_REPORT_v41 + version bump 0.10.6 → 0.10.7 | LOW |

### v0.10.8 (planned)

| Story | Content | Tier |
|-------|---------|------|
| US-001 | **N48** — field-ownership runtime enforcement (snapshot-diff guard) | LOW (defense-in-depth) |
| US-002 | **ANSI control-char passthrough sanitization** | LOW (security) |
| US-003 | 17th p014 review | LOW |
| US-004 | Retro + IDEA_REPORT_v42 + version bump 0.10.7 → 0.10.8 | LOW |

### v0.10.9 (planned, closeout)

| Story | Content | Tier |
|-------|---------|------|
| US-001 | **N44** — CSV/PIPELINE_REPORT count reconciliation | LOW |
| US-002 | Investigate + close-or-defer N40, N41, N38, N45, N43, N46, N47 | LOW (process) |
| US-003 | 18th p014 review | LOW |
| US-004 | Wave-plan retrospective + IDEA_REPORT_v43 + version bump 0.10.8 → 0.10.9 | LOW |

### v0.11.0 (OPERATOR-GATED)

**Reserved for the FIRST actual `--coordinator` dispatch on the live repo.**

When operator runs `bash quantum-loop.sh --coordinator --tool claude` on a cycle branch and dispatches real implementer subagents end-to-end, that cycle becomes v0.11.0 minor — the architectural milestone of "first real-feature dogfood unblocks the 6+-cycle deferral".

The dispatch subject can be any small story (need not be from the wave plan); the milestone is the empirical pipeline validation, not the specific feature.

## Standing backlog

### Real-feature dogfood (canonized v0.10.4 / US-003)

**Status:** UNCHANGED — blocked-on-operator-feature-queue. v0.10.6 documented the alternative path: the wave plan converts LOW backlog INTO the dogfood subjects (any LOW becomes the "feature"). v0.11.0 reservation makes this concrete.

## Still open (carried forward; LOW)

### N46 (respawn output not re-parsed) — MEDIUM

Unchanged. Will be evaluated in v0.10.9 closeout investigation.

### Other N-numbers

All to be addressed in wave plan cycles. Status:
- **N50:** CLOSED (this cycle)
- **N49:** v0.10.7 candidate
- **N48:** v0.10.8 candidate
- **N44:** v0.10.9 candidate
- **N40, N41, N38, N45, N43, N47:** v0.10.9 investigation (some likely obsolete post-decomposition)

### Deferred from v0.10.6 review

- **Test 15 private-TMPDIR isolation** — LOW; deferred to future hardening
- **Trap RETURN explicit `rm -f` switch** — gated on nested-trap caller appearing

### Pre-existing security LOWs

- ANSI control-char passthrough — v0.10.8 candidate
- (Trap RETURN re-entry — CLOSED in v0.10.6 via docstring + Test 15)

## Recurring observations

- **34 consecutive LOW G30 self-validations** (v0.6.5..v0.10.6).
- **Bundle size sequence: ...4-5-5-3-4-5-5-3-4.** v0.10.6 = 4 stories.
- **Manual-takeover streak: PARTIALLY BROKEN through v0.10.6** — 8 consecutive cycles with 1 operator gate at scope-ratification time.
- **p013 (operator-staged kickoff): 14 applications.**
- **p014 (composite review trio): 15 review applications.** 1 MEDIUM inline-fixed in v0.10.6 (4th review-gate catch in 15 applications: v0.10.2 CRITICAL, v0.10.3 doc-honesty MEDIUM, v0.10.5 parity HIGH, v0.10.6 cross-reference MEDIUM).
- **p015 (post-cycle 3-agent doc-vs-code audit): 3 applications** (canonized at 2; 3rd at v0.10.4).
- **p016 candidate (dogfood-driven LOW sweep): 1 application in progress** (v0.10.6 is cycle-1 of 4).

## v0.10.6 → v0.11.0 transition

```
v0.10.5 (patch — CLAUDE.md drift + missing-arg-guard parity)
  → v0.10.6 (patch — wave-cycle-1 housekeeping; N50 + Trap RETURN; v0.11.0 reserved)
  → v0.10.7 (patch — wave-cycle-2; N49 + copilot-rate-limit)
  → v0.10.8 (patch — wave-cycle-3; N48 + ANSI passthrough)
  → v0.10.9 (patch — wave-cycle-4; N44 + N40/N41/N38/N45/N43/N46/N47 investigation)
  → v0.11.0 (minor — OPERATOR-GATED; first --coordinator dispatch on live repo)
```

The wave plan covers v0.10.6 → v0.10.9 as direct-commit housekeeping (LOW backlog clearance). v0.11.0 minor is the architectural milestone reserved for the operator's interactive dispatch session.
