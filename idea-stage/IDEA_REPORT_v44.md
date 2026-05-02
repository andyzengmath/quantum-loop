# IDEA_REPORT_v44 — what's open after v0.10.10

**Date:** 2026-05-02
**Source:** v0.10.10 ships post-wave doc-cleanup patch (4th p015 application; 5 of 5 gaps closed; p016 added to CLAUDE.md).
**Branch:** `ql/v0.10.10-bundle` (release tag v0.10.10 — pending)
**Predecessor:** `idea-stage/IDEA_REPORT_v43.md`

## Closed in v0.10.10

| ID | Story | Notes |
|---|---|---|
| p016 missing from CLAUDE.md | US-001 | added; 17 patterns canonized total |
| CLAUDE.md p013/p014/p015 stale counts | US-001 | 12→17, 13→18, 2→3; career hit rate 6/18 |
| PIPELINE_REPORT_v43 wave-scope review count + IDEA_REPORT_v43 career contradiction | US-002 | reconciled to 5 findings / 75% trio-hit / 6/18 career |
| PRD line-ref drift (prd-v0.10.7 + prd-v0.10.8 US-002) | US-003 | post-N48 +30 shift; post-ANSI +6 shift |
| IDEA_REPORT_v43:84-85 propagation gap | US-004 review | architect + code-reviewer convergent MEDIUM; inline-fixed |

## v0.10.11 (next, recommended autonomous path)

| Story | Content | Tier |
|-------|---------|------|
| US-001 | **N46** — QL_RESPAWN_CMD respawn-output re-parse fix in `lib/orchestrator-liveness.sh:125`. Capture stdout/stderr from `bash -c "${QL_RESPAWN_CMD}"`, call `runner_parse_output` (already available via lib/runner.sh:280), update `SIGNAL_RESULT`/`SIGNAL_CONFIDENCE` before falling into post-wrap case-statement. ~30 LOC code change. | LOW (mechanical) |
| US-002 | Test coverage for N46 (mock QL_RESPAWN_CMD; assert SIGNAL_RESULT updates after successful respawn rc=0). | LOW |
| US-003 | 20th p014 review trio. | LOW |
| US-004 | Retrospective + IDEA_REPORT_v45 + version bump 0.10.10 → 0.10.11. | LOW |

## v0.11.0 (OPERATOR-GATED)

**Reserved for the FIRST actual `--coordinator` dispatch on the live repo.**

## Standing backlog

### Real-feature dogfood (canonized v0.10.4 / US-003)

**Status:** UNCHANGED — blocked-on-operator-feature-queue.

## v0.11.x backlog (post-N46 close)

| Item | Severity | Path |
|------|----------|------|
| N43 — Parallel-with-dispatch wrap | MEDIUM | v0.11.x (operator-gated; bg-process supervision needs stuck-agent observation) |
| N48 stub-coordinator test coverage | MEDIUM (sub-threshold) | v0.11.0 dogfood |
| OSC sequence body residue | LOW | future hardening |
| Retry-After multi-line edge cases | LOW | future hardening |
| N47 — branch cleanup | operator | operator-decision-pending |

## Recurring observations

- **38 consecutive LOW G30 self-validations** (v0.6.5..v0.10.10).
- **Bundle size sequence: ...3-4-4-4-4-4.** v0.10.10 = 4 stories.
- **Manual-takeover streak: PARTIALLY BROKEN through v0.10.10** — 12 consecutive cycles with 1 operator gate (v0.10.6).
- **p013 (operator-staged kickoff): 17 applications.** (Note: v0.10.10 did NOT use p013 — auto-approved per /loop step 4-5 from p015 audit findings; this is the 2nd deviation after v0.9.6's first-attempt rollback.)
- **p014 (composite review trio): 19 review applications.** 6 review-gate catches in 19 applications (~32% career hit-rate).
- **p015 (post-cycle 3-agent doc-vs-code audit): 3 applications**, canonized at 2; 14 gaps closed total (6+3+5).
- **p016 (dogfood-driven LOW sweep wave): 1 application** (canonized at 1; v0.10.6..v0.10.9; 4 cycles, 16 stories).

## v0.10.10 → v0.10.11 → v0.11.0 transition

```
v0.10.6..v0.10.9 (wave plan: N50/N49/N48/N44/N40-47 + LOWs) ✓
v0.10.10 (post-wave doc-cleanup; 4th p015 application; p016 to CLAUDE.md) ✓ ← THIS CYCLE
v0.10.11 (N46 implementation; ~30 LOC + test) ← NEXT (autonomous)
v0.11.0 (operator-gated --coordinator dispatch) ← OPERATOR-STAGED
```

**Operator decision NOT required for v0.10.11 entry.** Architect's p015 audit confirmed N46 is autonomously achievable (mock QL_RESPAWN_CMD + standard test infra).
