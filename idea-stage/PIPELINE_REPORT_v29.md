# PIPELINE_REPORT_v29 — v0.9.2 retrospective (defensive hardening; 5a HIGH closed)

**Date:** 2026-04-30
**Bundle:** `ql/v0.9.2-bundle` (release tag v0.9.2 — pending push/PR/merge/tag/release)
**Predecessor report:** `idea-stage/PIPELINE_REPORT_v28.md`
**Master parent:** `ed27f2c` (v0.9.1 ship state)
**Source:** Operator-staged plan from `idea-stage/IDEA_REPORT_v28.md` § "v0.9.2 candidate slate" (HIGH 5a + 2 reviewer MEDIUMs).

## Overview

v0.9.2 is the defensive-hardening patch closing v0.9.1's known-issue advisory (5a HIGH — implementer subagents may run destructive `git reset --hard` in shared coordinator worktrees). Mirrors v0.8.x's pattern (validation cycles followed by post-review hardening). 5-story patch; engineered safety net replaces v0.9.1's emergent recovery.

## Headline result

**v0.9.1 finding 5a HIGH — EMPIRICALLY CLOSED.** The v0.9.2 dogfood (US-004) fired the synthetic plan with US-B explicitly instructed to perform `git reset --hard HEAD~1`. Across 2 iterations, the new HEAD-snapshot guard (`lib/coordinator-guard.sh::guard_head_advance`) fired correctly — every time the implementer ran the destructive op, the coordinator detected the reset, marked US-B failed in review fields, and emitted WAVE_FAILED. Per-story aggregation correctly routed US-A → passed and US-B → failed.

Caveats:
- Synthetic plan; not a real feature.
- Iteration 3 hung mid-`eval` (operator killed; documented as v0.9.3 candidate — re-evaluate `ql_wrap_subagent_dispatch` STALE detection under coordinator mode).
- Manual-takeover streak: BROKEN at v0.9.1 (cycle 19); v0.9.2 had partial manual takeover at iter-3 cleanup. Honest framing: GUARD architecture works; subagent-stability hardening still needed.

## The 5 stories

| # | ID | Title | Outcome |
|:-:|---|---|:-:|
| 0 | (cycle setup) | chore: v0.9.2 cycle kickoff (design + PRD + advisory hooks) | committed at `cd7d764` |
| 1 | US-001 | Coordinator HEAD-snapshot guard (lib/coordinator-guard.sh + agents/coordinator.md amend) | first-attempt PASS at `5c536de` |
| 2 | US-002 | Gate legacy STORY_* case branches under coordinator mode | first-attempt PASS at `9d734b6` |
| 3 | US-003 | filePaths validation gap (lib/quantum-validate.sh + next_wave preamble hook) | first-attempt PASS at `110b9a5` |
| 4 | US-004 | Real-LLM dogfood validating HEAD-snapshot guard | first-attempt PASS at `f7e4950` (guard fired 2/2 iterations; iter-3 hung) |
| 5 | US-005 | Retrospective + IDEA_REPORT_v29 + version bump + worktree cleanup | this report |

## Architectural newness justifying patch-tier

- New helper library `lib/coordinator-guard.sh` (~50 LOC; defensive only).
- New helper library `lib/quantum-validate.sh` (~40 LOC; advisory only).
- `agents/coordinator.md` step 2 amended (instruction-only).
- 9-line gate in `quantum-loop.sh` (defense-in-depth case-branch redirect).
- 8-line preamble hook in `lib/dag-query.sh::next_wave`.

Per `feedback_version_tier_calibration.md`: defensive hardening with small new helper libraries; default patch-tier unless genuinely architectural. v0.9.2 falls cleanly under patch-tier.

## v0.9.2 fixes shipped + deferrals

### Closed

| Finding | Severity | Closure |
|---|---|---|
| **5a (v0.9.1 HIGH advisory)** | HIGH | CLOSED (engineered). `lib/coordinator-guard.sh::guard_head_advance` uses `git merge-base --is-ancestor`. Empirically validated across 2 dogfood iterations. |
| **Code-reviewer MEDIUM** (legacy STORY_* case branches under coord mode) | MEDIUM | CLOSED. Defense-in-depth gate redirects to WAVE_FAILED branch for per-story aggregation. New Test 5 in `tests/test_coordinator_e2e.sh`. |
| **Architect MEDIUM** (filePaths silent bypass) | MEDIUM | CLOSED. `lib/quantum-validate.sh::validate_story_filepaths` advisory hook called once per `next_wave` invocation. Warnings to stderr; never blocks. |

### Deferred to v0.9.3+

| Finding | Severity | Path |
|---|---|---|
| **5a iter-3 hang** (coordinator subagent stuck > 3 hours mid-eval during dogfood iter 3) | MEDIUM | Re-evaluate `ql_wrap_subagent_dispatch` STALE detection under coordinator mode (currently gated OFF per v0.9.0 US-001). |
| **N46** (respawn output not re-parsed) | MEDIUM | Unchanged from v0.9.0. |
| **Architect risk #3** (per-story worktree isolation conflicts with `--coordinator --parallel`) | MEDIUM | Architect option 1 (HEAD-snapshot guard) shipped. Option 2 (worktree isolation) deferred. |
| **N40, N43, N47, N49, N50, N48** | LOW | Carried forward. |

## Multi-perspective review

This cycle's US-004 was the dogfood — NOT the multi-perspective post-merge review. Operator's loop directive (item 1) instructs running `/pr-review` or `/code-review` AFTER the cycle's stories complete; that runs post-merge as part of cycle close. Findings from that review (if any) become v0.9.3 candidates.

## Wave plan vs realized

US-001/2/3 file-disjoint (parallel-safe in wave-1 if --coordinator used). US-004 dependsOn US-001+US-002+US-003 (validates the hardening they ship). US-005 dependsOn all.

Realized order under manual takeover (sequential):
1. cycle kickoff at `cd7d764`
2. US-001 → coordinator-guard lib + amendment
3. US-002 → STORY_* case-branch gate
4. US-003 → filePaths validation gap
5. US-004 → dogfood (3 iterations attempted; iters 1+2 conclusive, iter 3 hung)
6. US-005 → this retrospective

## G30 self-validation — 23rd consecutive LOW

`bash lib/deep-review.sh score $BASE $HEAD` → tier=LOW (small diff: 2 new helper libs, 2 new test files, 1 doc amendment, 1 case-branch gate, 1 preamble hook + retrospective + version bump). Recorded with `automated:true`. **23 consecutive LOW-tier self-validations** (v0.6.5..v0.9.2).

## CSV milestone

`metrics/pre-impl-review-findings.csv` → 58 rows. Advisory hook findings for v0.9.2: design + prd + plan all 1 LOW each.

## Test-suite delta vs v0.9.1

| Test file | v0.9.1 | v0.9.2 | delta |
|---|---:|---:|---:|
| `tests/test_coordinator_guard.sh` (NEW) | — | 8 | +8 |
| `tests/test_quantum_validate.sh` (NEW) | — | 11 | +11 |
| `tests/test_coordinator_e2e.sh` (existing; +1 case for US-002) | 10 | 13 | +3 |
| **Total v0.9.2 added:** | | | **+22** |

Cumulative test-assert count: ~89 (v0.9.1) → ~111 (v0.9.2).

## Manual-takeover streak

**v0.9.1 broke the streak at cycle 19.** v0.9.2 cycle had partial manual takeover at the dogfood iter-3 hang (operator killed parent shell + curated findings). Honest framing: cycle 20 was NOT fully autonomous due to iter-3 hang, but the GUARD ARCHITECTURE worked correctly. Cycle 20 streak status: PARTIAL (architectural success; operational hand-off at cleanup).

v0.9.3 should aim for full-autonomous run (closes 5a iter-3 hang).

## codebasePatterns

p001-p012 carried forward. No new patterns this cycle. The "pre-cycle 3-architect design + post-cycle 3-reviewer trio" pattern (validated in v0.9.0 + v0.9.1) was NOT applied this cycle (US-004 was dogfood instead of review trio); applied 2x so far. p013 formalization candidate — wait for 3rd application.

## Recommendation pointer

See `idea-stage/IDEA_REPORT_v29.md` for what's open after v0.9.2.
