# IDEA_REPORT_v18 — what's open after v0.7.7

**Date:** 2026-04-28
**Source:** `ql/v0.7.7-bundle` retrospective
**Predecessor:** `idea-stage/IDEA_REPORT_v17.md`

## Closed in v0.7.7

| ID | Story | Notes |
|---|---|---|
| **N30** | US-001+US-002+US-003 | First end-to-end smoke validation of codex (tier=tested) + copilot (tier=experimental) CLI runners. 13 new assertions across 2 new test files + 1 extended. |

The **N30 v0.7.7 anchor** is now **fully closed**.

## Persistent canon

p001-p011 unchanged.

## Multi-cycle CSV milestone (10 cycles, ~30 rows, ~64 findings)

Approximate (post-v0.7.7 hooks).

## Still open

### N33 — Worktree mode root-cause investigation
**Status:** unchanged. 10 consecutive manual-takeover cycles; subagent drift baseline holds at 100%. Recommend formal investigation in next minor.

### G19/G21/G24/P5.* frontier — defer indefinitely

## New gaps from v0.7.7

### N35 — Real-task dispatch (vs version probe) for codex/copilot
**Surfaced:** v0.7.7 validated `runner_load` + `_provider_version` end-to-end. The next step would be a real prompt-dispatch smoke test: `runner_build_cmd` + spawn subprocess + parse output for an actual minimal task (e.g., "echo hello"). Deferred to v0.9.0+ as the natural next milestone.
**Severity:** LOW (gap, not bug).
**Path:** Track for v0.9.0 anchor — promote codex from version-tested to task-tested.

### N36 — runner_load name-vs-path API ambiguity
**Surfaced:** US-001/US-002 smoke tests initially passed manifest paths instead of names. The function rejects paths via regex (good defense), but the error message doesn't suggest the correct form.
**Severity:** LOW (UX nit).
**Path:** Skill-prompt edit: when v0.7.7+ documentation references `runner_load`, include explicit "takes a name (not a path)" annotation.

### N37 — runners/manifest.example.yaml (v0.7.4) is redundant with runners/*.json
**Surfaced:** v0.7.4 added a yaml-based aggregate manifest schema. v0.7.7 confirmed the per-runner JSON manifests in `runners/*.json` are the authoritative source. The yaml example is harmless but redundant.
**Severity:** LOW (cleanup opportunity).
**Path:** v0.8.1 or v0.9.0 — either deprecate `runners/manifest.example.yaml` or convert it to a dispatcher-level config (different concern from per-runner manifests).

## Recommendation for next

**v0.8.1 candidates (small reactive):**
- N36 doc-annotation (skill prompt edit, ~5 min)
- N37 cleanup (deprecate yaml example, ~10 min)

**v0.9.0 candidates (next minor):**
- **N35** — codex/copilot real-task dispatch validation (substantive minor anchor)
- **N33** — worktree subagent drift root-cause investigation
- G22 fourth calibration pass once 2+ patch-tier cycles ship

## Recurring observations

- **12 consecutive LOW G30 self-validations** (v0.6.5..v0.7.7).
- **10 consecutive manual-takeover cycles** with 0-retry.
- **Bundle size: 7-7-7-7-5-6-5-3-7-3-2-4.** v0.7.7 is 4 stories — patch-tier framing earned by integration substance, not story count.
- **Multi-runner is now real.** codex (tested) + copilot (experimental) integrated end-to-end at the version-probe level.
