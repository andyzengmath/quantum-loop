# IDEA_REPORT_v45 — what's open after v0.10.11

**Date:** 2026-05-02
**Source:** v0.10.11 closes N46 (respawn output re-parsing); 38 → 39 consecutive LOW G30.
**Branch:** `ql/v0.10.11-bundle` (release tag v0.10.11 — pending)
**Predecessor:** `idea-stage/IDEA_REPORT_v44.md`

## Closed in v0.10.11

| ID | Story | Notes |
|---|---|---|
| N46 (QL_RESPAWN_CMD respawn re-parsing) | US-001 | subshell-isolated tee + runner_parse_output; 3 new tests |
| `set -e` + pipefail abort regression | US-003 architect | inline-fixed (subshell isolation) |
| Git Bash mktemp mode 644 | US-003 security | inline-fixed (chmod 600) |
| trap-based tmpfile cleanup | US-003 architect+CR+security | inline-fixed (trap RETURN) |
| Test coverage for rc!=0 under set -e | US-003 architect | inline-fixed (Test 14c) |

## Autonomously-achievable backlog: largely exhausted

The v0.10.6..v0.10.11 sweep closed nearly all LOW + sub-threshold MEDIUM items that don't require operator-gated `--coordinator` dispatch:

- **CLOSED in waves/follow-ups:** N50, N49, N48, N44, N40, N41, N38, N45, N46, copilot-rate-limit, ANSI passthrough, trap RETURN, p016 canonization, count-reconciliation gaps.
- **Remaining DEFERRED-future MEDIUMs:** N43 (operator-gated; needs stuck-agent observation), N48 stub-coordinator test (needs real-coordinator violation case → v0.11.0 dogfood).
- **Remaining LOW backlog:** OSC body residue (cosmetic; non-exploitable); Retry-After multi-line edge cases (rare; current single-line extraction sufficient).
- **Operator-decision-pending:** N47 branch cleanup.

## v0.10.12+ candidates (low priority; idle-tick fillers)

| Story | Content | Tier | Effort |
|-------|---------|------|--------|
| Possible | OSC body strip in ANSI sanitization (`lib/json-atomic.sh:302,349`) | LOW | ~5 LOC |
| Possible | Retry-After multi-line extraction | LOW | ~10 LOC |
| Possible | Branch cleanup operator chore (operator decision required first) | operator | N/A |

These are eligible for batch-as-one cycle but provide marginal value. Recommendation: hold v0.10.12 until either (a) operator stages a real feature for v0.11.0, or (b) sufficient new findings accumulate to justify another wave.

## v0.11.0 (OPERATOR-GATED — UNCHANGED)

**Reserved for the FIRST actual `--coordinator` dispatch on the live repo.** All wave-plan dogfood subjects are now closed; the system is ready for real-feature dispatch when operator queues scope.

## Standing backlog

### Real-feature dogfood (canonized v0.10.4 / US-003)

**Status:** UNCHANGED — blocked-on-operator-feature-queue. Wave plan + post-wave hardening (v0.10.6..v0.10.11) have prepared 11 cycles of contained patches; v0.11.0 entry is purely operator-decision.

## v0.11.x backlog (post-N46 close)

| Item | Severity | Path |
|------|----------|------|
| N43 — Parallel-with-dispatch wrap | MEDIUM | v0.11.x (operator-gated; bg-process supervision needs stuck-agent observation; review confirmed NOT autonomously achievable) |
| N48 stub-coordinator test coverage | MEDIUM (sub-threshold) | v0.11.0 dogfood |
| OSC sequence body residue | LOW | future hardening (or v0.10.12 if batched) |
| Retry-After multi-line edge cases | LOW | future hardening (or v0.10.12 if batched) |
| N47 — branch cleanup | operator | operator-decision-pending |

## Recurring observations

- **39 consecutive LOW G30 self-validations** (v0.6.5..v0.10.11).
- **Bundle size sequence: ...3-4-4-4-4-4-4.** v0.10.11 = 4 stories.
- **Manual-takeover streak: PARTIALLY BROKEN through v0.10.11** — 13 consecutive cycles with 1 operator gate (at v0.10.6 wave plan approval).
- **p013 (operator-staged kickoff): 17 applications.** (v0.10.10 + v0.10.11 are 2nd + 3rd autonomous-kickoff deviations after v0.9.6's first-attempt rollback; both validated by p015 audits + multi-perspective reviews → no rollback.)
- **p014 (composite review trio): 20 review applications.** 7 review-gate catches in 20 applications (~35% career hit-rate; trended slightly up from 33% at v0.10.10).
- **p015 (post-cycle 3-agent doc-vs-code audit): 3 applications**, canonized at 2; 14 gaps closed total.
- **p016 (dogfood-driven LOW sweep wave): 1 application**, canonized at 1; 16 stories shipped first-attempt PASS.

## v0.10.11 → v0.11.0 transition

```
v0.10.6..v0.10.9 (p016 wave plan: N50/N49/N48/N44/N40-47 + LOWs) ✓
v0.10.10 (post-wave doc-cleanup; 4th p015 application; p016 to CLAUDE.md) ✓
v0.10.11 (N46 closure; respawn output re-parsing) ✓ ← THIS CYCLE
v0.10.12 (idle-tick filler IF accumulated; else hold) — eligible but low-value
v0.11.0 (operator-gated --coordinator dispatch) ← OPERATOR-STAGED
```

**Operator decision still required for v0.11.0 entry.** Autonomous backlog is now functionally exhausted of high-value items.
