# IDEA_REPORT_v38 — what's open after v0.10.4

**Date:** 2026-05-01
**Source:** v0.10.4 closes 3 v0.10.3-deferred items + reclassifies dogfood as standing backlog.
**Branch:** `ql/v0.10.4-bundle` (release tag v0.10.4 — pending)
**Predecessor:** `idea-stage/IDEA_REPORT_v37.md`

## Closed in v0.10.4

| ID | Story | Notes |
|---|---|---|
| --max-parallel + --stale-timeout integer validation | US-001 | Asymmetric regex `^[1-9][0-9]*$` (positive only; 0 degenerate) |
| Subsumption-claim wording correction (4 docs) | US-002 | Annotated `[v0.10.4 honest-framing correction]` |
| Dogfood per-cycle → standing-backlog conversion | US-003 | New CLAUDE.md `### Standing backlog (v0.10.4 / US-003)` subsection |
| 13th p014 review trio | US-004 | ALL SHIP; no inline fixes |

## Persistent canon

p001-p015 carried forward. No new patterns identified.

## v0.10.5+ candidate slate

### Optional v0.10.5 patch (LOW housekeeping)

| Story | Content | Tier |
|-------|---------|------|
| US-001 | Missing-argument guard parity for --max-iterations/--max-retries/--max-parallel/--stale-timeout (add explicit `$# -lt 2` guard matching --critic/--planner pattern). | LOW (pre-existing MEDIUM-tier finding) |
| US-002 | Multi-perspective post-merge review (14th application) | LOW |
| US-003 | Retrospective + IDEA_REPORT_v39 + version bump 0.10.4 → 0.10.5 | LOW |

**Honest framing:** patch-tier; ~30 minutes. Single LOW absorb + ceremony. May not be worth a release marker; could batch with v0.11.0 if operator pivots to feature work soon.

### Alternative: v0.11.0 feature-work return

Pivot to feature work — no specific scope queued. Operator decides direction.

## Standing backlog

### Real-feature dogfood (canonized v0.10.4 / US-003)

**Status:** blocked-on-operator-feature-queue. **Resume condition:** operator queues a real feature for `quantum-loop.sh --coordinator` dispatch. **Anti-pattern:** synthesizing fake features = ceremony without value.

## Still open (carried forward)

### N46 (respawn output not re-parsed) — MEDIUM

Unchanged.

### N40, N43, N47, N48, N49, N50

LOW. **N47 (branch cleanup)** still operator-decision-pending — 24+ local branches now (v0.7.x..v0.10.4).

### N38, N41, N44, N45, copilot-rate-limit-observability

Re-added v0.10.1. LOW.

### Pre-existing LOWs

- Trap RETURN re-entry (theoretical; security LOW).
- ANSI control-char passthrough (theoretical; security LOW).

## Recurring observations

- **32 consecutive LOW G30 self-validations** (v0.6.5..v0.10.4).
- **Bundle size sequence: ...4-7-5-5-4-6-5-5-6-3-4-5-5.** v0.10.4 = 5 stories.
- **Manual-takeover streak: PARTIALLY BROKEN through v0.10.4** — 6 consecutive cycles with 1 operator gate at scope-ratification time.
- **p013 (operator-staged kickoff): 12 applications.**
- **p014 (composite review trio): 13 review applications.**
- **p015 (post-cycle 3-agent doc-vs-code audit): 2 applications, canonized.**
- **No new review-gate catches in v0.10.4.** Architect 88 lowest in this cycle but still SHIP (vs v0.10.3's 78). Pattern: review trio scores trending toward stable 88-95 range.

## v0.10.4 → v0.11.0 transition

```
v0.10.0 (minor — PARALLEL_MODE extraction; v0.9.x architectural arc CLOSED)
  → v0.10.1 (patch — 1st audit-cleanup)
  → v0.10.2 (patch — 2nd audit-cleanup + p015 canon; 1 CRITICAL caught)
  → v0.10.3 (patch — --max-retries parity + test_v081_wiring delete)
  → v0.10.4 (patch — --max-parallel/--stale-timeout parity + subsumption correction + dogfood standing-backlog)
  → v0.10.5 (optional patch — missing-arg-guard parity)
     OR
  → v0.11.0 (feature-work return)
```

**v0.10.x housekeeping arc complete.** v0.10.5 has only 1 meaningful work item (missing-arg parity); could be batched into v0.11.0 if operator pivots to feature work.
