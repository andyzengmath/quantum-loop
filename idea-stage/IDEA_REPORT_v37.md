# IDEA_REPORT_v37 — what's open after v0.10.3

**Date:** 2026-05-01
**Source:** v0.10.3 closes 2 deferred items (--max-retries parity + test_v081_wiring delete) + 4th-cycle dogfood deferral.
**Branch:** `ql/v0.10.3-bundle` (release tag v0.10.3 — pending)
**Predecessor:** `idea-stage/IDEA_REPORT_v36.md`

## Closed in v0.10.3

| ID | Story | Notes |
|---|---|---|
| --max-retries argparse integer validation | US-001 | Parity with v0.10.2 --max-iterations regex |
| test_v081_wiring.sh restore-or-delete decision | US-002 | DELETED; v0.8.1 placeholders v0.9.0 superseded |
| Real-feature dogfood (4th cycle deferral) | US-003 | Status update only; no code; new framing as "blocked-on-operator-feature-queue" |
| 12th p014 review trio (SHIP; 1 inline fix) | US-004 | Architect 78 (lowest in 12-cycle history due to honesty gap) |

## Persistent canon

p001-p015 carried forward. No new patterns identified.

## v0.10.4+ candidate slate

### Optional v0.10.4 patch (LOW housekeeping; if scope warrants)

| Story | Content | Tier |
|-------|---------|------|
| US-001 | --max-parallel + --stale-timeout integer validation (architect + security flagged in v0.10.3 review as LOW parity gap) | LOW |
| US-002 | Subsumption-claim wording correction in v0.10.3 retro/CHANGELOG (architect MEDIUM; honesty improvement) | LOW |
| US-003 | Convert real-feature dogfood from per-cycle story to standing-backlog item (architect process recommendation) | LOW (process) |
| US-004 | Multi-perspective post-merge review (13th application) | LOW |
| US-005 | Retrospective + IDEA_REPORT_v38 + version bump 0.10.3 → 0.10.4 | LOW |

**Honest framing:** patch-tier; ~1 hour. All LOW; no new architectural work.

### Alternative: v0.11.0 feature-work return

Pivot to feature work — no specific scope queued. Operator decides direction.

## Standing backlog (re-classified per architect recommendation)

The following items now live as standing backlog rather than per-cycle deferred stories:

### Real-feature dogfood (was v0.10.0 US-003 → v0.10.3 US-003)

**Status:** standing backlog. Blocked-on-operator-feature-queue.
**Resume condition:** operator queues a real feature for dispatch through `quantum-loop.sh --coordinator`.
**Why not synthetic dogfood:** the system's housekeeping work is by-design low-risk and direct-commit-friendly; routing it through coordinator dispatch tests the dispatch path, not the housekeeping work. Manufactured features add ceremony without value.

## Still open (carried forward; LOW)

### N46 (respawn output not re-parsed) — MEDIUM

Unchanged. v0.9.3 timeout + v0.9.5 parent-side guard remain operational alternatives.

### N40, N43, N47, N48, N49, N50

LOW. **N47 (branch cleanup)** still operator-decision-pending — 23+ local branches now (v0.7.x..v0.10.3).

### N38, N41, N44, N45, copilot-rate-limit-observability

Re-added v0.10.1 from silent-drop. LOW. No active path.

### Pre-existing LOWs from prior reviews

- Trap RETURN re-entry (theoretical, security LOW).
- ANSI control-char passthrough in jq stderr (theoretical, security LOW).
- --max-parallel + --stale-timeout integer validation parity (newly flagged in v0.10.3 review).
- Subsumption-claim wording in v0.10.3 retro (architect honesty MEDIUM).
- v0.10.3 wiring-reachability coverage gap: `ql_wrap_subagent_dispatch` caller + `COORDINATOR_MODE` consultation + dead-`-z` guard form not asserted in any test suite post-test_v081_wiring deletion. Functional coverage exists via `test_coordinator_e2e` but not symbol-grep coverage.

## Recurring observations

- **31 consecutive LOW G30 self-validations** (v0.6.5..v0.10.3).
- **Bundle size sequence: ...4-7-5-5-4-6-5-5-6-3-4-5.** v0.10.3 = 5 stories.
- **Manual-takeover streak: PARTIALLY BROKEN through v0.10.3** — 5 consecutive cycles with 1 operator gate at scope-ratification time.
- **p013 (operator-staged kickoff): 11 applications.**
- **p014 (composite review trio): 12 review applications.**
- **p015 (post-cycle 3-agent doc-vs-code audit): 2 applications, canonized.**
- **2nd p014 review-gate catch:** v0.10.3 architect caught a doc-honesty MEDIUM (overstated subsumption claim). 1st was v0.10.2 code-reviewer's CRITICAL regex catch. Both validate the review-gate's spec-compliance value beyond local implementer testing.
- **Lowest architect score in p014 history: 78/100** (v0.10.3). Prior range: 91-95.

## v0.10.3 → v0.11.0 transition

```
v0.10.0 (minor — PARALLEL_MODE extraction; v0.9.x architectural arc CLOSED)
  → v0.10.1 (patch — 1st audit-cleanup; 6 gaps)
  → v0.10.2 (patch — 2nd audit-cleanup + p015 canon; 1 CRITICAL caught)
  → v0.10.3 (patch — --max-retries parity + test_v081_wiring delete; 1 doc-honesty MEDIUM caught)
  → v0.10.4 (optional patch — --max-parallel/--stale-timeout parity + LOW housekeeping)
     OR
  → v0.11.0 (feature-work return; no architectural backlog forced)
```

The v0.10.x audit-cleanup arc (v0.10.1 → v0.10.3) has reached LOW-tier-only territory. Future v0.10.x cycles are pure housekeeping; v0.11.0 is the natural next significant release.
