# IDEA_REPORT_v39 — what's open after v0.10.5

**Date:** 2026-05-01
**Source:** v0.10.5 closes 3 CLAUDE.md drift + 1 deferred MEDIUM + 1 inline-fixed HIGH from US-002 review.
**Branch:** `ql/v0.10.5-bundle` (release tag v0.10.5 — pending)
**Predecessor:** `idea-stage/IDEA_REPORT_v38.md`

## Closed in v0.10.5

| ID | Story | Notes |
|---|---|---|
| CLAUDE.md p013 count drift (9→12) | US-001 T-001-1 | Stale 3 cycles; updated v0.10.5 |
| CLAUDE.md p014 count drift (10→13) | US-001 T-001-2 | Stale 3 cycles; updated v0.10.5 |
| CLAUDE.md p013 retro-ref correction | US-001 T-001-3 | v33 → v34 (recovery narrative location) |
| --max-* missing-arg-guard parity | US-001 T-001-4 | 4 flags get $# -lt 2 guard |
| **--tool missing-arg-guard parity (HIGH)** | US-002 inline | Caught by review; 5th flag missed by initial PRD |
| 14th p014 review trio | US-002 | 1 HIGH inline-fixed; arch 91, code 82→92, sec 95 |

## Persistent canon

p001-p015 carried forward. p015 (post-cycle 3-agent doc-vs-code audit) now has 3 applications post-v0.10.0/v0.10.1/v0.10.4. CLAUDE.md p015 entry says "2 applications" (canonized at v0.10.2); next cycle may want to update to "3 applications" if the pattern is applied a 4th time.

## v0.11.0+ candidate slate

The v0.10.x housekeeping arc (v0.10.1 → v0.10.5) is genuinely complete. There is NO LOW-or-higher backlog from internal review/audit findings. Only standing-backlog items remain.

### v0.11.0 feature-work return (recommended)

Pivot to feature work. No specific scope queued. Operator decides direction.

### Speculative options for v0.11.0+ (none queued)

Per ADR-001 trigger conditions and project history, plausible next-arc candidates:
- Multi-machine / distributed dispatch (ADR-001 trigger 4)
- New runner support (Cursor, Cline, etc.)
- TUI / dashboard / real-time progress UI
- Live introspection (ADR-001 trigger 3)
- New pipeline capabilities (e.g., dependency-injection refactoring for tests)

None of these have a concrete ask from the operator. v0.11.0 stays paused until one is queued.

## Standing backlog

### Real-feature dogfood (canonized v0.10.4 / US-003)

**Status:** blocked-on-operator-feature-queue. Same condition as v0.10.4. **Resume condition:** operator queues a real feature for `quantum-loop.sh --coordinator` dispatch.

## Still open (carried forward; LOW)

### N46 (respawn output not re-parsed) — MEDIUM

Unchanged. v0.9.3 timeout + v0.9.5 parent-side guard remain operational alternatives.

### N40, N43, N47, N48, N49, N50, N38, N41, N44, N45, copilot-rate-limit

LOW. **N47 (branch cleanup)** still operator-decision-pending — 25+ local branches now (v0.7.x..v0.10.5).

### Pre-existing security LOWs

- Trap RETURN re-entry (theoretical).
- ANSI control-char passthrough (theoretical).

## Recurring observations

- **33 consecutive LOW G30 self-validations** (v0.6.5..v0.10.5).
- **Bundle size sequence: ...4-7-5-5-4-6-5-5-6-3-4-5-5-3.** v0.10.5 = 3 stories (smallest patch since v0.7.x).
- **Manual-takeover streak: PARTIALLY BROKEN through v0.10.5** — 7 consecutive cycles with 1 operator gate at scope-ratification time.
- **p013 (operator-staged kickoff): 13 applications.**
- **p014 (composite review trio): 14 review applications.**
- **p015 (post-cycle 3-agent doc-vs-code audit): 3 applications** (canonized at 2; 3rd happened post-v0.10.4 via operator request).
- **3rd p014 review-gate catch in 14 applications.** v0.10.2 CRITICAL + v0.10.3 MEDIUM + v0.10.5 HIGH. Hit-rate ~21%.

## v0.10.x → v0.11.0 transition

```
v0.10.0 (minor — PARALLEL_MODE extraction; v0.9.x architectural arc CLOSED)
  → v0.10.1 (patch — 1st audit-cleanup)
  → v0.10.2 (patch — 2nd audit-cleanup + p015 canon; 1 CRITICAL caught)
  → v0.10.3 (patch — --max-retries parity + test_v081_wiring delete)
  → v0.10.4 (patch — --max-parallel/--stale-timeout parity + subsumption correction + dogfood standing-backlog)
  → v0.10.5 (patch — CLAUDE.md drift + missing-arg-guard parity; 3rd p015 audit; 1 HIGH inline-fixed)
  → v0.11.0 (feature-work return; no architectural backlog forced)
```

**v0.10.x housekeeping arc genuinely complete.** 5 patches closed all internal-review/audit findings. v0.11.0 awaits operator scope.
