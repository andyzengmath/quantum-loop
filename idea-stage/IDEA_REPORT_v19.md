# IDEA_REPORT_v19 — what's open after v0.7.8

**Date:** 2026-04-28
**Predecessor:** `idea-stage/IDEA_REPORT_v18.md`

## Closed in v0.7.8

| ID | Story | Notes |
|---|---|---|
| **N36** | US-001 | `runner_load` invalid-name error gains a hint sentence pointing at the correct form. |
| **N37** | US-002 | `runners/manifest.example.yaml` header notes the file is documentation-only; per-runner JSON manifests are authoritative. |

## Still open

### N33 — Worktree mode root-cause investigation
**Status:** unchanged. 11 consecutive manual-takeover cycles.

### N35 — Real-task dispatch (codex/copilot beyond version probe)
**Status:** unchanged. v0.9.0 anchor.

## New gaps from v0.7.8

None substantive — patch-tier track once again drained.

## Recommendation for next

**Stop the patch-tier loop.** v0.7.4-v0.7.8 has now closed every reactive item surfaced by the dogfood + N30 cycles. Further patch cycles will be value-light churn unless a new finding surfaces from operator usage or external review.

**v0.9.0 candidates (next minor — needs operator scope):**
- **N35** — codex/copilot real-task dispatch (substantive minor anchor)
- **N33** — worktree subagent drift root-cause investigation
- New feature TBD

## Recurring observations

- **13 consecutive LOW G30 self-validations** (v0.6.5..v0.7.8).
- **11 consecutive manual-takeover cycles** with 0-retry.
- **Bundle size: 7-7-7-7-5-6-5-3-7-3-2-4-3.** v0.7.8 is 3-story.
