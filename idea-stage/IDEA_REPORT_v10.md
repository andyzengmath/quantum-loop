# IDEA_REPORT_v10 — what's still open after v0.6.9

**Date:** 2026-04-28
**Source:** `ql/v0.6.9-bundle` dogfood retrospective (US-005)
**Branch:** `ql/v0.6.9-bundle` (release tag v0.6.9)
**Predecessor:** `idea-stage/IDEA_REPORT_v9.md`

## Closed in v0.6.9

| ID | Story | Notes |
|---|---|---|
| **N6-followup** | US-001 | `lib/orchestrator-liveness.sh::poll_orchestrator_commits` — parent-side commit-poll helper. Defaults timeout=600s, interval=60s, base=git rev-parse HEAD. Returns 0 (live) or 1 (stale). Library contract (no shell flags at source). agents/orchestrator.md Step 1.0.4 prose pointer. 8 assertions in tests/test_orchestrator_liveness.sh. |
| **N13** | US-002 | `references/orchestrator-takeover.md` (NEW) — manual-takeover SOP for parent agents. 4 sections: When/What/How/Recovery. Verification-failure-driven amendment rule documented with v0.6.7 Pattern C → Pattern A worked example. CLAUDE.md Process references cross-link. 5 assertions in tests/test_orchestrator_takeover_doc.sh. |
| **N9-followup** | US-003 | `tests/bench_wallclock_baseline_drift.sh` (NEW) — opt-in benchmark; `bench_*` prefix deliberately skips run_all.sh's `tests/test_*.sh` glob. Hardcoded BASELINES with 7 commands. Always exits 0 (informational). |
| **N12** | US-004 | tests/test_audit.sh: `extract_function_comments` → `extract_function_header_comments`; `extract_function_full_comments` → `extract_function_all_comments`. 9-occurrence mechanical rename across function defs + 4 call sites + 3 doc-comment refs. 45/45 audit assertions unchanged. |

The **N6-followup / N13 / N9-followup / N12 cluster** (the v0.6.9 priority list from IDEA_REPORT_v9) is now **fully closed**. 4 of 5 stories shipped first-attempt PASS; US-005 retrospective is this report.

## Persistent canon

**Codebase patterns p009/p010/p011** verbatim definitions remain at `idea-stage/PIPELINE_REPORT_v7.md` § "codebasePatterns harvested" — durable single source-of-truth across cycles. v0.6.9 carried over p001-p011 unchanged.

## Multi-cycle CSV milestone (15 rows, 41 findings, 5 cycles)

| Cycle | design | prd | plan | total |
|---|---|---|---|---:|
| v0.6.5 | 0/0/0/1 | 0/0/0/4 | 0/0/0/0 | 5 |
| v0.6.6 | 0/0/0/0 | 0/2/4/3 | 0/0/0/1 | 10 |
| v0.6.7 | 0/0/1/2 | 0/0/2/3 | 0/0/0/2 | 10 |
| v0.6.8 | 0/0/1/2 | 0/0/1/2 | 0/0/0/2 | 8 |
| v0.6.9 | 0/0/1/2 | 0/0/1/2 | 0/0/0/2 | 8 |
| **Total** | **0/0/3/7** | **0/2/8/14** | **0/0/0/7** | **41** |

Severity distribution: **0 crit / 2 high / 11 med / 28 low**. LOW remains 68 %. HIGH stable at 2 total (v0.6.6 prd-only). The patch-tier baseline at 5 cycles / 15 rows is now stable enough for G22 calibration.

## Still open after v0.6.9

### G19 — 3-SKILL-wrapper centralization
**Status:** unchanged. Defer indefinitely.

### G21 — metrics CSV rotation
**Status:** premature. v0.6.9 ships at 15 rows. ETA: ~v1.0+.

### G22 — severity rubric calibration
**Status:** **first calibration pass becomes meaningful at v0.7.x.** 5-cycle baseline solidly established. Need 1-3 minor-tier bundles for the comparison axis.

### G24 — audit relative-path inconsistency
**Status:** unchanged.

### P5.B2 / B3 / B5
**Status:** unchanged.

### P5.C frontier
**Status:** all deferred.

## New gaps from v0.6.9 dogfood

### N14 — SKILL-level wrapping of the v0.6.9 liveness helper
**Surfaced:** v0.6.9 N6-followup ships the helper but `/ql-execute` SKILL does NOT yet wrap the orchestrator with it. The helper is operator-side opt-in only.
**Severity:** MEDIUM. Manual operators won't get auto-detect; only callers of the helper do.
**Path:** v0.7.0 candidate. Update `/ql-execute` SKILL.md to invoke `poll_orchestrator_commits` after spawning the orchestrator subagent; on STALE, hand off via `references/orchestrator-takeover.md`. Or wrap as a parent-side bash script that operates on the orchestrator process. 0.5-1 stories. Couples with the broader v0.7.0 SKILL formalization track.

### N15 — Process references CLAUDE.md section growth
**Surfaced:** v0.6.9 added the 3rd entry (orchestrator-takeover) joining v0.6.8's N7 (soliton-finding-triage) and N9 (test-wallclock-baselines). At 4+ entries the section may benefit from sub-categorization (orchestrator-related vs test-related vs process-related).
**Severity:** LOW (organizational taste).
**Path:** v0.7.0 doc-only candidate. Re-categorize when the section reaches 5+ entries. 0.1 stories.

## Recommendation for v0.6.10 or v0.7.0

**v0.6.10 candidate slate (patch-tier):**
None compelling. The v0.6.x backlog is now exhausted of patch-tier-appropriate items. The remaining open items (G19/G21/G22/G24, P5.* frontier, N14 SKILL wrapping, N15 section re-cat) all benefit more from v0.7.0 minor-tier framing where infrastructure changes are appropriate.

**v0.7.0 candidate slate (minor tier):**
1. **G22** — severity rubric calibration first pass against the 5-cycle 15-row patch-tier baseline.
2. **N14** — SKILL-level wrapping of `lib/orchestrator-liveness.sh` (auto-invocation of liveness check + automatic handoff to takeover SOP).
3. **N15** — Process references CLAUDE.md sub-categorization at 5+ entries.
4. **G19** — 3-SKILL-wrapper centralization if a 4th pre-impl stage is added.
5. **P5.B2 / B3 / B5** — formalization candidates per their long-standing status.

**Long-tail (deferred indefinitely):**
- G21, G24, P5.C frontier.

## Recurring observations

- **5 consecutive cycles, 5 consecutive LOW-tier self-validations.** v0.6.5/6/7/8/9 all classified score=25 → skip via `should_dispatch_deep_review`. The G30 dispatch gate routes patch-tier bundles correctly with 100% accuracy across the established baseline.
- **Manual takeover is the established recovery pattern.** v0.6.7 + v0.6.8 + v0.6.9 all shipped under parent-agent execution. v0.6.9 finally formalizes the recovery via N13 SOP doc + N6-followup runtime helper. v0.7.0 N14 closes the loop with SKILL-level auto-invocation.
- **0-retry execution record extends to v0.6.9** under manual takeover. Held since v0.6.0 across 5 patch-tier cycles.
- **Sequential mode is the right default for patch-tier.** All small-bundle cycles work cleanly in priority order with 1-2 dependsOn edges.
- **Bundle size is shrinking.** v0.6.5/6/7/8 all had 7 stories; v0.6.9 had 5. The natural endpoint of a patch-tier track — backlog drains as fixes ship. v0.6.10 would be the smallest yet (likely 0-3 stories), so v0.7.0 minor-tier is the right next move.
