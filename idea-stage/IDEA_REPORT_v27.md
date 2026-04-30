# IDEA_REPORT_v27 — what's open after v0.9.0

**Date:** 2026-04-29
**Source:** v0.9.0 N42 ships the per-wave coordinator dispatch wires. v0.9.1 dogfood is the empirical proof point.
**Branch:** `ql/v0.9.0-bundle` (release tag v0.9.0 — pending)
**Predecessor:** `idea-stage/IDEA_REPORT_v26.md`

## Closed in v0.9.0

| ID | Story | Notes |
|---|---|---|
| **N42** | US-001+US-002+US-003+US-004 | Real per-wave coordinator dispatch wired; integration tests pass (stub-driven). Empirical proof = v0.9.1 dogfood. |
| **agents/coordinator.md contradiction** | US-000 | Step 1 + step 4 amended to align with field-ownership contract |
| **WAVE_FAILED per-story attribution** | US-003 | Option A: derive from coordinator-written review.* fields (no signal-protocol change) |
| **--coordinator --parallel mutual exclusion** | US-004 | Hard exit at parse time replacing v0.8.1 warn-only |
| **Coordinator-crash retry orphan risk** | US-001 (architect 1's HIGH) | `*)` branch now applies retry accounting to ALL `WAVE_STORY_IDS`, not undefined `$STORY_ID` |
| **Real-fire integration coverage** | US-005 | 10 assertions exercising actual quantum-loop.sh --coordinator binary; not presence-only |

## Persistent canon

p001-p012 unchanged. v0.9.0 introduces no new patterns; leverages existing ones (atomic critical sections, jq json mutations, runner adapter abstraction).

## Still open

### N42-validate — Real-LLM dogfood through `--coordinator` (PRIMARY follow-up; v0.9.1 candidate)

**Status:** new. v0.9.0 ships infrastructure with stub-driven integration tests (10/10 pass). The empirical question — does the per-wave coordinator pattern actually break the manual-takeover streak? — requires a real cycle through `--coordinator` with a real LLM.
**Severity:** HIGH for the architectural goal (18-cycle manual-takeover streak; v0.9.1 is the empirical break point).
**Path:** v0.9.1 dogfood validation cycle. Mirrors v0.8.0 → v0.8.1's pattern (architectural minor → validation patch).

### N43 — Parallel-with-dispatch wrap pattern

**Status:** unchanged. Defer to v0.9.1+ after N42 validation. Background-process supervision in shell is fragile on Git Bash; intersects v0.9.0's synchronous coordinator design.
**Severity:** MEDIUM.

### N46 — QL_RESPAWN_CMD respawn-output not re-parsed

**Status:** unchanged from IDEA_REPORT_v26. v0.9.0 explicitly gates `ql_wrap_subagent_dispatch` soft-fire OFF under coordinator mode. The full N46 fix (capture respawn output, re-feed through runner_parse_output) remains v0.9.1+ scope.
**Severity:** MEDIUM.

### N40, N38, copilot rate-limit observability, N41, N44, N45, N47

All unchanged from IDEA_REPORT_v26. LOW priority.

## New v0.9.0 follow-ups

### N48 — Field-ownership runtime enforcement (snapshot-diff guard)

**Status:** new. Architect 3 recommended a lightweight snapshot-diff guard: parent records `stories[].status` + `stories[].retries` BEFORE coordinator runs, compares AFTER, warns/restores on coordinator-written drift. v0.9.0 deferred this in favor of trust-the-contract (now that US-000 amended coordinator.md).
**Severity:** LOW (the contract is documented + the coordinator instructions are amended; runtime enforcement is defense-in-depth).
**Path:** v0.9.x housekeeping if any drift observed in v0.9.1 dogfood.

### N49 — Bulk-update single-jq optimization for WAVE_* branches

**Status:** new. v0.9.0's WAVE_PASSED/WAVE_FAILED branches use one jq invocation each (good). The pre-mark step also uses one jq. Performance is fine for waves of 1-5 stories. Larger waves (10+) might benefit from streaming or batch optimization, but this is purely a performance follow-up — not a correctness gap.
**Severity:** LOW.
**Path:** v0.10.0+ if observed slow.

### N50 — Iteration vs Wave counter naming clarity

**Status:** new (cosmetic). v0.9.0 reuses `ITERATION` as the wave counter (`WAVE_ID="wave-${ITERATION}"`). Per architect 1's design, this is correct (one iteration = one spawn = one wave) but the variable name `ITERATION` is now overloaded. A future refactor could rename to `WAVE_COUNTER` or split conceptually.
**Severity:** LOW (naming clarity only).

## Recommendation for next

**v0.9.1 candidate slate (patch-tier — N42 validation):**

| Story | Content |
|-------|---------|
| US-001 | Real-LLM dogfood — small 1-2 story test bundle dispatched via `quantum-loop.sh --coordinator` end-to-end |
| US-002 | Capture findings: did wave dispatch fire? did per-story aggregation work? did WAVE_FAILED/PASSED route correctly? |
| US-003 | Soliton-driven inline fixes for any v0.9.0 issues surfaced |
| US-004 | Multi-perspective post-merge review (architect + code-reviewer + security) |
| US-005 | Retrospective + IDEA_REPORT_v28 + version bump 0.9.0 → 0.9.1 |

This mirrors v0.8.0 → v0.8.1's pattern.

**Honest risk:** v0.9.1 may surface that `--coordinator` doesn't break the manual-takeover streak in production. Possible failure modes:
- Real coordinator subagent drifts mid-wave (same drift class as legacy orchestrator)
- spawn_coordinator command construction has bugs not caught by stubs
- review.* field writes don't actually populate per the contract
- Wave-eligibility logic edge cases under realistic quantum.json complexity

If v0.9.1 finds defects, ship inline fixes. If v0.9.0 holds up: 19th-cycle streak break is the milestone.

## Recurring observations

- **21 consecutive LOW G30 self-validations** (v0.6.5..v0.9.0). Score actually dropped from 25 (v0.8.4) to 20 (v0.9.0) despite minor-tier scope — the rubric discounts additive changes (new files outweigh modifications).
- **Bundle size: 7-7-7-7-5-6-5-3-7-3-2-4-3-3-7-7-5-5-4-4-7.** v0.9.0 is 7-story (matches v0.8.0 minor — both architectural cycles).
- **Architect-design pattern is now standardized** alongside the post-merge multi-perspective review pattern. Pre-cycle 3-agent design + post-cycle 3-agent review = full coverage of architectural changes.
- **Manual-takeover streak: 18 consecutive cycles.** v0.9.1 dogfood = empirical break point.
- **First v0.9.x cycle.** v0.8.x closed cleanly with zero deferred findings.

## v0.9.x track outlook

v0.9.0 (architectural minor — N42 wires) → v0.9.1 (validation patch — dogfood) → potentially v0.9.2 (post-validation review fix) → eventual v0.10.0 (outer-loop replacement; architect-recommended deferred from v0.9.0).
