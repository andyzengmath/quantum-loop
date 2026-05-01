# IDEA_REPORT_v36 — what's open after v0.10.2

**Date:** 2026-05-01
**Source:** v0.10.2 closes 1 MEDIUM + 4 LOW from 2nd audit + 2 LOW absorbs + p015 canonization. 1 CRITICAL caught + fixed inline by US-003 review.
**Branch:** `ql/v0.10.2-bundle` (release tag v0.10.2 — pending)
**Predecessor:** `idea-stage/IDEA_REPORT_v35.md`

## Closed in v0.10.2

| ID | Story | Notes |
|---|---|---|
| Doc-specialist Finding 3 (CLAUDE.md p013/p014 counts stale) | US-001 T-001-1 | 8→9 + 9→10 |
| Architect Finding 1 (lib/loop-helpers.sh stale comment) | US-001 T-001-2 | Now references current call sites |
| Architect Finding 2 (IDEA_REPORT_v34 line refs off by 3) | US-001 T-001-3 | 363,367,370 → 360,364,367 |
| Dead `--argjson wave "$WAVE"` (carry-forward) | US-001 T-001-4 | Removed |
| MAX_ITERATIONS argparse validation (carry-forward) | US-001 T-001-5 | Validates non-negative integer |
| p015 canonization | US-002 | "Post-cycle 3-agent doc-vs-code audit" pattern |
| 11th p014 review trio (CRITICAL caught + inline-fixed) | US-003 | Validates review-gate's spec-compliance value |

## Persistent canon

p001-p015 carried forward. v0.10.2 canonized p015 ("post-cycle 3-agent doc-vs-code audit"). Total 15 patterns: 3 process (p013/p014/p015) + 12 coding-idiom (p001-p012).

## v0.11.0+ candidate slate (post-architectural-arc + post-audit-cleanup × 2)

The v0.9.x architectural arc + v0.10.0 PARALLEL_MODE extraction + v0.10.1 + v0.10.2 audit-cleanups are all CLOSED. There is NO remaining architectural backlog.

### Optional v0.10.3 patch (LOW-tier housekeeping; if scope warrants)

| Story | Content | Tier |
|-------|---------|------|
| US-001 | `--max-retries` argparse integer validation (parity with `--max-iterations`; deferred from v0.10.2 review). | LOW |
| US-002 | `tests/test_v081_wiring.sh` — either restore (rewrite assertions for v0.9.0+ wires) or delete (mark obsolete). 4/5 currently failing on pre-v0.9.0 assertions. | LOW |
| US-003 | Real-feature dogfood (deferred from v0.10.0 US-003). | MEDIUM (only meaningful work) |
| US-004 | Multi-perspective post-merge review (12th application). | LOW |
| US-005 | Retrospective + IDEA_REPORT_v37 + version bump 0.10.2 → 0.10.3. | LOW |

**Honest framing:** patch-tier; ~1.5 hours. Real-feature dogfood (if operator queues a feature) is the only meaningful work; everything else is LOW absorbs.

### Alternative: v0.11.0 feature-work return

Pivot to feature work — no specific scope queued. Operator decides direction.

### 3rd post-cycle audit application — diminishing returns watch

p015 has been applied twice (post-v0.10.0 found 6 gaps; post-v0.10.1 found 3 gaps + 1 already-acknowledged). The 2nd application found materially fewer gaps. A 3rd application post-v0.10.2 may find 0-1 gaps (diminishing returns). Recommend gating: only run p015 after a cycle that meaningfully changed code or docs (not after a tiny patch like v0.10.2 itself).

## Still open (carried forward)

### N46 (respawn output not re-parsed) — MEDIUM

Unchanged. v0.9.3 timeout + v0.9.5 parent-side guard remain operational alternatives. v0.11.0+ if wrap re-enabled.

### test_v081_wiring.sh (NEW deferral, pre-existing)

4/5 failures on pre-v0.9.0 assertions (the `WARN coordinator not wired` placeholder check + `ql_wrap_subagent_dispatch zero callers` + `dead -z SIGNAL_RESULT form` + `COORDINATOR_MODE silently falls through`). All assertions check v0.8.1-era behavior that v0.9.0 superseded with real coordinator dispatch. Test was last touched in v0.8.1 (b1ac946); 9 cycles of stale.

**Resolution paths:**
- Delete the suite (mark obsolete; v0.9.0+ behavior tested by test_coordinator_e2e + test_dag_query + test_next_wave).
- Rewrite assertions for v0.9.0+ wires (re-derive each test's intent in current architecture).
- Leave as-is (operator may have informational reason for keeping the v0.8.1 record).

Recommend: ask operator preference in v0.10.3.

### `--max-retries` argparse parity gap

Code-reviewer + security flagged in v0.10.2 review. jq's `--argjson` provides implicit downstream safety net (parse error on non-integer); but operator-facing error would be less clear than `--max-iterations`. Defer to v0.10.3.

### Other LOWs (unchanged)

- N40, N43, N47, N48, N49, N50.
- N38, N41, N44, N45, copilot-rate-limit-observability (re-added v0.10.1).
- Trap RETURN re-entry (theoretical; security LOW).
- ANSI control-char passthrough (theoretical; security LOW).

## Recurring observations

- **30 consecutive LOW G30 self-validations** (v0.6.5..v0.10.2). Round number.
- **Bundle size sequence: ...4-7-5-5-4-6-5-5-6-3-4.** v0.10.2 = 4 stories.
- **Manual-takeover streak: PARTIALLY BROKEN through v0.10.2** — same posture as v0.9.6 + v0.10.0 + v0.10.1.
- **p013 (operator-staged kickoff): 10 applications.**
- **p014 (composite review trio): 11 review applications + 5 architect-design + 2 doc-vs-code audits.**
- **p015 (post-cycle 3-agent doc-vs-code audit): 2 applications, NOW CANONIZED.**
- **First p014 CRITICAL catch:** v0.10.2 US-003 caught a regex regression (T-001-5) before it shipped. Validates the review-gate's spec-compliance value over 11 applications.

## Pre-cycle audit-doc reading discipline

Per `feedback_autonomous_kickoff_caution.md`. Holding strong: v0.10.2 audit + cycle scope + execution all matched real code state via verified greps. The CRITICAL caught at review was an implementer-error (regex semantic), not a source-doc-reading failure.

## v0.10.0 → v0.10.1 → v0.10.2 → v0.11.0 transition

```
v0.10.0 (minor — PARALLEL_MODE extraction; v0.9.x architectural arc CLOSED)
  → v0.10.1 (patch — 1st audit-cleanup)
  → v0.10.2 (patch — 2nd audit-cleanup + p015 canon + LOW absorbs)
  → v0.10.3 (optional patch — --max-retries parity + test_v081_wiring + maybe dogfood)
     OR
  → v0.11.0 (feature-work return; no architectural backlog forced)
```

The v0.9.x → v0.10.0 architectural arc + 2 audit-cleanup follow-ups are fully closed. Future cycles do not have a forced agenda.
