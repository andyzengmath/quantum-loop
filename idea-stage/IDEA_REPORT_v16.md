# IDEA_REPORT_v16 — what's still open after v0.7.5

**Date:** 2026-04-28
**Source:** `ql/v0.7.5-bundle` retrospective (US-003)
**Predecessor:** `idea-stage/IDEA_REPORT_v15.md`

## Closed in v0.7.5

| ID | Story | Notes |
|---|---|---|
| **N29** | US-001 | `quantum-loop.sh --audit` adds `csv-uncommitted` check (WARN-level). +2 audit tests in `tests/test_audit.sh`. |
| **N31** | US-002 | `/ql-spec` SKILL Step 1 grep-verify instruction. Doc-only edit (1 line). |

The **N29+N31 cluster** (v0.7.5 reactive slate from IDEA_REPORT_v15) is **fully closed**.

## Persistent canon

p001-p011 unchanged.

## Multi-cycle CSV milestone (9 committed cycles, 27 rows, ~61 findings)

v0.7.5 advisory hooks added 3 rows. Total committed: 27 rows.

## Still open after v0.7.5

### N30 — Multi-runner first integration (v0.8.0 anchor)
**Status:** unchanged. Foundation in v0.7.4; needs ≥1 real consumer (codex or copilot CLI).
**Severity:** MEDIUM (architecturally substantive — would justify minor-tier).

### N32 — Per-story dual-review pattern
**Status:** v0.7.4 + v0.7.5 used PR-time consolidated review. Still the pragmatic default; no rubric action.

### N33 — Worktree mode framed but unused
**Status:** unchanged. Recommend formal disable in `/ql-execute` until subagent drift root-cause investigated.

### G19/G21/G24/P5.* frontier
**Status:** defer indefinitely.

## New gaps from v0.7.5

### N34 — Housekeeping: v0.7.4 + v0.7.5 design+PRD docs untracked
**Surfaced:** v0.7.4 PR (and now v0.7.5) repeats the "design doc + PRD authored locally but never committed" pattern that v0.7.3 housekeeping caught. v0.7.5 working tree has both v0.7.4 and v0.7.5 design+PRD untracked.
**Severity:** LOW (process gap).
**Path:** Add to next cycle's housekeeping commit OR add a hook that auto-stages `docs/plans/` + `tasks/prd-*.md` after writes. Track for v0.7.6 or v0.8.0.

## Recommendation for v0.7.6 or v0.8.0

**v0.7.6 candidates (small reactive):**
- N34 housekeeping — auto-stage hook for design+PRD files (small).

**v0.8.0 candidates (minor tier):**
- **N30** multi-runner first real integration — primary minor-tier anchor.
- **N33** worktree mode root-cause investigation — substantive process work.
- G22 fourth calibration pass once v0.8.0 minor-tier ships.

## Recurring observations

- **10 consecutive LOW G30 self-validations** (v0.6.5..v0.7.5).
- **8 consecutive manual-takeover cycles** with 0-retry.
- **Bundle size: 7-7-7-7-5-6-5-3-7-3.** v0.7.5 returns to compact 3-story shape.
