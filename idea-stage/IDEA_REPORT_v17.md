# IDEA_REPORT_v17 — what's still open after v0.7.6

**Date:** 2026-04-28
**Source:** `ql/v0.7.6-bundle` retrospective
**Predecessor:** `idea-stage/IDEA_REPORT_v16.md`

## Closed in v0.7.6

| ID | Story | Notes |
|---|---|---|
| **N34** | US-001 | `_audit_untracked_design_prd_docs` helper added to `quantum-loop.sh`; +2 audit tests. |

## Still open

### N30 — Multi-runner first integration (v0.8.0 anchor)
Foundation in v0.7.4. Needs ≥1 real consumer.

### N32, N33 — unchanged from v0.7.5

### G19/G21/G24/P5.* frontier — defer indefinitely

## New gaps from v0.7.6

None substantive. Patch-tier track is now genuinely drained for known process gaps.

## Recommendation for next

**Stop the patch-tier loop.** The 3-cycle reactive sequence (v0.7.4 dogfood → v0.7.5 N29+N31 → v0.7.6 N34) has closed all known process gaps surfaced in the dogfood cycle. Continued patch-tier cycles will be value-light churn.

**v0.8.0 minor-tier requires operator-defined scope:**
- N30 multi-runner first integration (which runner? what depth?)
- N33 worktree mode root-cause investigation (substantive process work)
- Or substantive new feature

## Recurring observations

- **11 consecutive LOW G30 self-validations** (v0.6.5..v0.7.6).
- **9 consecutive manual-takeover cycles** with 0-retry.
- **Bundle size: 7-7-7-7-5-6-5-3-7-3-2.** v0.7.6 is the smallest bundle yet (2 stories).
- **Patch-tier track explicitly drained** as of this report. v0.8.0 needs operator scope.
