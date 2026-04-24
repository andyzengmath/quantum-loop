# PR-ready summary: `ql/orchestrator-wire-2026-04` → master (follow-up to PR #27)

**Date**: 2026-04-23
**Branch**: `ql/orchestrator-wire-2026-04` (2 commits ahead of PR #27 tip)
**Base**: Depends on PR #27 landing first (shares `ql/bug-gap-fix-2026-04` as base)
**Source**: PR #27's `.omc/PR_READY.md` listed these two items as natural follow-ups.

---

## One-line description

Wire the 7 helper libraries shipped in PR #27 into the runtime orchestrator, and add phase-skip-via-artifact-detection so identical re-invocations of upstream skills short-circuit.

---

## Commits (2)

| # | Commit | Phase | Description |
|---|--------|-------|-------------|
| 2 | `30b7631` | 18 | Phase-skip via artifact detection (P2.4, OMC Autopilot) |
| 1 | `ee0efc9` | 17 | Wire new helper libs into orchestrator (P0-P2 productionization) |

Diffstat: 18 files changed, ~1400 lines added.

---

## What was wired (Phase 17)

PR #27 shipped 7 testable helper libraries but never invoked them at runtime. Phase 17 adds explicit insertion points in `agents/orchestrator.md`:

| Insertion | Lib | Action |
|---|---|---|
| 3A.5B per-story | `lib/deslop.sh` | scope-fence + baseline/compare + rollback on regression |
| 3A.6 per-commit | `lib/commit-trailers.sh` | non-blocking validation of each commit message |
| 3B.3 monitor loop | `lib/watchdog.sh` | age poll (5/10/30-min tiers) + circuit-breaker on same-error |
| 3C.NEG1 wave boundary | `lib/wave-boundary.sh` | divergent-constants scan, HIGH → fix-story |
| 4B.5 full-feature review | `lib/deep-review.sh` | score → tier → dispatch → aggregate → verdict |

**Intentionally NOT wired** in orchestrator:
- `lib/handoff.sh` — skill-side ownership; orchestrator just leaves `.handoffs/` alone.
- `lib/claim-check.sh` — already transitive via `lib/runner.sh` since Phase 5.

---

## What was added (Phase 18)

`lib/phase-skip.sh` — fingerprint-based idempotent re-invocation for upstream skills. Each skill records a sha256 of its inputs; identical re-calls short-circuit.

| Skill | Fingerprints |
|---|---|
| `/ql-brainstorm` | `userIntent.text` (inline hash) + most recent `docs/plans/*-design.md` |
| `/ql-spec` | design doc + `.handoffs/brainstorm.md` |
| `/ql-plan` | most recent PRD + `.handoffs/spec.md` |

Stored at `.handoffs/<stage>.fingerprint.json` — separate from `.handoffs/<stage>.md` so Phase 15's parser stays untouched. Composes with the handoff protocol: skip reuses the handoff as its summary output.

---

## Tests (58 new assertions)

| Suite | Assertions |
|---|---:|
| `test_orchestrator_wiring.sh` | 30 (Phase 17 prompt-side wiring) |
| `test_phase_skip.sh` | 28 (Phase 18 fingerprint + skip semantics + skill wiring) |

Regression: **12/12 suites green, 316/316 individual assertions** (captured in `.omc/phase-17-evidence/` and `.omc/phase-18-evidence/`). No overlap with PR #27's 39/40 baseline.

---

## Rollout

This PR **depends on PR #27 merging first**. Two rollout paths:

**Path A: Sequential** (recommended). Wait for PR #27 → rebase this branch onto master → open this PR.

**Path B: Stacked** (faster but coupled). Open this PR now targeting PR #27's branch. GitHub's "merge queue" or Graphite-style stacking handles the sequencing.

Either way, all of the new orchestrator insertion points reference helpers that ONLY exist on PR #27's tip — so this PR cannot merge independently.

---

## Deferred backlog

After PR #27 and this follow-up land, the remaining P2 items are:

- **P2.8 Ambiguity-gated brainstorm** (OMC deep-interview pattern) — scores ambiguity across goal/constraints/criteria dimensions before allowing PRD generation. Medium effort.
- **P2.10 Tournament selection + re-benchmark** — opt-in per-story; high cost for the common case. Defer.
- **P3 academic wedges** (SSAT, KBI-FAR, SCF, HyClone) — next research cycle.
- **P4 AI-native integration** — blocked on upstream deps.

---

## Pending user action

- [ ] **Push `ql/orchestrator-wire-2026-04` to origin** — first remote push of this branch.
- [ ] **Open PR targeting either master (after PR #27 merges) or `ql/bug-gap-fix-2026-04` (stacked)**.

Both are shared-state actions. Awaiting OK.
