# PIPELINE_REPORT_v32 — v0.9.5 retrospective (post-spike patch: decomposition + parent-side guard + ADR-001)

**Date:** 2026-05-01
**Bundle:** `ql/v0.9.5-bundle` (release tag v0.9.5 — pending push/PR/merge/tag/release)
**Predecessor report:** `idea-stage/PIPELINE_REPORT_v31.md`
**Master parent:** `63586f2` (v0.9.4 ship state)
**Source:** Operator-staged plan from `idea-stage/v0.10.0-design-spike-2026-05-01.md` (3-architect pre-cycle spike).

## Overview

v0.9.5 is a focused **post-spike patch** ratifying the design-spike outcome. The pre-cycle spike found that the originally-framed v0.10.0 "daemon-style runner" replacement was *over-engineering* — the cron `/loop` pattern already solves the motivating problem. v0.9.5 ships the spike-derived patch-tier work (decomposition + parent-side guard + ADR-001 codifying the cron canon) instead of jumping into a daemon implementation.

## Headline result

**v0.9.x post-spike patch CLOSED.** 1837 LOC monolith → 793 LOC entry-point + 3 lib files (-57%, -1044 LOC moved, behavior-preserving). Parent-side `guard_head_advance` defense-in-depth shipped. ADR-001 ACCEPTED — cron `/loop` is canonical, no daemon will be built. Operator framing call: this is a PATCH (no architectural surface change), not a minor — original v0.10.0 framing was inflated.

## The 5 stories

| # | ID | Title | Outcome |
|:-:|---|---|:-:|
| 0 | (cycle setup) | chore: v0.9.5 cycle kickoff (post-spike rebase: design + PRD + advisory hooks) | committed at `ccf2cd9` |
| 1 | US-001 | Decompose quantum-loop.sh (extract lib/audit.sh + lib/loop-helpers.sh + lib/iteration-loop.sh) | first-attempt PASS via 3 sub-tasks at `ba9ab31` + `708b0ad` + `8c51c73` |
| 2 | US-002 | Parent-side `guard_head_advance` defense-in-depth + Test 8 head_reset stub | first-attempt PASS at `473dc07` |
| 3 | US-003 | ADR-001 outer-loop architecture (cron `/loop` canonical; no daemon) | first-attempt PASS at `5ae69db` |
| 4 | US-004 | Multi-perspective post-merge review (7th application) + 2 score-≥85 inline fixes | first-attempt PASS at `b7cd3ff` |
| 5 | US-005 | Retrospective + IDEA_REPORT_v32 + version bump 0.9.4 → 0.9.5 | this report |

## Decomposition delta (US-001)

`quantum-loop.sh` 1837 → 793 LOC. Three modular extractions, each verified end-to-end before commit:

| Sub-task | New file | Source range | LOC | Commit |
|---|---|---|---:|---|
| T-001-1 | `lib/audit.sh` | quantum-loop.sh:120-501 (13 `_audit_*` fns + `do_audit`) | 408 | `ba9ab31` |
| T-001-2 | `lib/loop-helpers.sh` | quantum-loop.sh:362-655 (5 helpers) | 326 | `708b0ad` |
| T-001-3 | `lib/iteration-loop.sh` | quantum-loop.sh:786-1209 (loop body wrapped in `run_iteration_loop()`) | 468 | `8c51c73` |
| **Total moved** | | | **1202** | (3 commits) |

Each commit kept all 7 test suites green. Wrapping the iteration body in `run_iteration_loop()` confirmed `exit 0/1/2` and `continue` work correctly inside bash function bodies. Test-mode source guards (p009) applied to all 3 new libs.

**Deferred:** the `PARALLEL_MODE` block (~390 LOC) was left in `quantum-loop.sh` — extracting it requires worktree-state plumbing that doesn't fit the patch budget. Spike's ~330 LOC final-state estimate was lower than realized 793 because of this deferral. Tracked in IDEA_REPORT_v32 for v0.10.0+.

## Parent-side guard (US-002)

Coordinator-mode dispatch now performs HEAD-snapshot ancestry verification *in the parent* immediately post-`eval`, regardless of whether the coordinator subagent invoked the guard itself. Failure path: parent prints `ERROR: Parent-side HEAD guard fired. HEAD_BEFORE=… HEAD_AFTER=…`, forces `SIGNAL_RESULT=WAVE_FAILED`, and per-story review-field aggregation runs.

Rationale: removes LLM-instruction-following dependency for the safety-critical guard. If the coordinator skips/forgets the guard, parent catches it. Failure-isolation symmetric with v0.9.3's `timeout`-based wallclock gate.

`tests/test_coordinator_e2e.sh` Test 8 (`head_reset` stub mode): initializes a /tmp git repo with 2 commits, stub does `git reset --hard HEAD~1` then echoes WAVE_PASSED, asserts ERROR pattern + per-story aggregation. 20/20 → 21/21.

## ADR-001 (US-003)

`references/adr-001-outer-loop-architecture.md` ACCEPTED. The "daemon-style runner" framing from `idea-stage/IDEA_REPORT_v30.md` was a stale aspiration that outlived its motivating problem ("operator must manually re-run quantum-loop.sh after MAX_ITERATIONS"). The Claude Code `/loop` cron pattern, which drove v0.9.3 + v0.9.4 end-to-end with zero manual takeover, is the canonical outer-loop architecture. Documented alternatives: A (persistent daemon — rejected), B (cron `/loop` — chosen), C (inotify — rejected), D (hybrid `while true` — deferred). Triggers for revisit explicit.

`idea-stage/IDEA_REPORT_v31.md` updated to strikethrough Spike 2 + US-002 references and reframe v0.10.0 outlook.

## Multi-perspective review synthesis (US-004, 7th application of pattern)

| Reviewer | Verdict | Key finding |
|---|---|---|
| **Architect** | SHIP | Zero CRITICAL/HIGH. Decomposition behavior-preserving; LOC budget met; parent-side guard layered cleanly. |
| **Code-reviewer** | SHIP | **1 INLINE FIX (score ≥85; trivial text edit):** MEDIUM ADR-001 § Alternatives lettered A/B/D, skipping C without explanation. Added cross-ref note pointing at design-spike A/B/C/D + restored letter C for Inotify. Applied at `b7cd3ff`. |
| **Security** | SHIP | **1 INLINE FIX (score ≥85):** MEDIUM `lib/iteration-loop.sh` redirected `guard_head_advance ... 2>/dev/null`, suppressing operationally-useful diagnostic stderr (distinguishes reset-detected vs git-not-on-PATH vs corrupt-repo). Removed redirect; documented rationale inline. Applied at `b7cd3ff`. |

US-004 review pattern: **7th application** (post-v0.8.1, v0.8.2, v0.8.3, v0.8.4, v0.9.1, v0.9.3, v0.9.4; SKIPPED v0.9.2 because US-004 was dogfood). Pattern stable.

## v0.9.5 fixes shipped + deferrals

### Closed (from spike output)

| Finding | Severity | Story |
|---|---|---|
| Architect MEDIUM (`quantum-loop.sh` 1828 LOC decomposition) | MEDIUM | US-001 |
| Architect MEDIUM (parent-side `guard_head_advance` enforcement) | MEDIUM | US-002 |
| Spike 2 (resolve "daemon-style runner" framing) | (process) | US-003 |
| US-004 code-reviewer MEDIUM (ADR-001 letter C) | MEDIUM | US-004 inline |
| US-004 security MEDIUM (guard stderr suppression) | MEDIUM | US-004 inline |

### Deferred to v0.10.0+

| Finding | Severity | Path |
|---|---|---|
| Architect MEDIUM (~70): bash -c subshell scoping comment | LOW | absorb into v0.10.0 kickoff |
| Code-reviewer LOWs: redundant `${RUNNER_EXIT:-0}` default; comment-block density at quantum-loop.sh:1664-1692 | LOW | v0.10.0 |
| CLAUDE.md tilde line-number drift (post-decomposition) | LOW | v0.10.0 doc pass — line numbers shifted further by US-001 |
| 6 inline `jq > tmp && mv` migration to `json_atomic_update` | MEDIUM | v0.10.0 refactor |
| 3x duplicated COMPLETE/BLOCKED exit blocks | MEDIUM | v0.10.0 refactor |
| `PARALLEL_MODE` block extraction (~390 LOC) | MEDIUM | v0.10.0+ |
| **N40, N43, N46, N47, N48, N49, N50** | LOW | carried forward |

## Wave plan vs realized

US-001 sub-tasks T-001-1/2/3 are sequentially dependent (each builds on prior extraction). US-002 depends on US-001 T-001-3 (touches `lib/iteration-loop.sh`). US-003 file-disjoint. US-004 dependsOn US-001 + US-002 + US-003. US-005 dependsOn all.

Realized order under cron-driven autonomous /loop:
1. cycle kickoff at `ccf2cd9` (post-spike rebase: design + PRD + advisory hooks)
2. US-001 T-001-1 audit extraction at `ba9ab31`
3. US-001 T-001-2 helpers extraction at `708b0ad`
4. US-001 T-001-3 iteration-loop extraction at `8c51c73`
5. US-002 parent-side guard + Test 8 at `473dc07`
6. US-003 ADR-001 at `5ae69db`
7. US-004 review + 2 inline fixes at `b7cd3ff`
8. US-005 (this retrospective)

## G30 self-validation — 26th consecutive LOW

`bash lib/deep-review.sh score $BASE $HEAD` → tier=LOW (mostly-mechanical extraction; no behavioral change; small additive parent-guard + 1 ADR + 1 test). Recorded with `automated:true`. **26 consecutive LOW** (v0.6.5..v0.9.5).

> Operator framing note: 1044-LOC delta could read "minor" by line count, but every line was a *move*, not new behavior. Risk surface is the parent-guard hookpoint (~10 lines) and the function-wrapping of the iteration body. Both regression-tested.

## Test-suite delta vs v0.9.4

| Test file | v0.9.4 | v0.9.5 | delta |
|---|---:|---:|---:|
| `tests/test_coordinator_e2e.sh` (+Test 8 `head_reset`) | 20 | 21 | +1 |
| **Total v0.9.5 added:** | | | **+1** |

Cumulative: ~124 → ~125 assertions.

## Manual-takeover streak

v0.9.5 driven entirely via the autonomous /loop cron pattern (10-min cadence). No mid-cycle operator intervention beyond the initial spike-synthesis confirmation. All 5 stories first-attempt PASS. **Streak: BROKEN through v0.9.5** (3rd consecutive cycle: v0.9.3, v0.9.4, v0.9.5).

## codebasePatterns

p001-p012 carried forward. **p013 + p014 ready for canonization** (still pending — operator decision):
- **p013** — Operator-staged cycle kickoff: 6 applications (v0.9.0-v0.9.5).
- **p014** — Pre-cycle 3-architect design + post-cycle 3-reviewer trio (composite): 7 review applications + 5 architect-design applications. v0.9.5 spike caught the most consequential drift to date — *killed an entire cycle's worth of speculative architectural work* by reframing v0.10.0 from "significant architectural rewrite" to "patch-tier housekeeping plus an ADR."

Recommend formalizing p013 + p014 in v0.10.0 codebasePatterns block.

## Recommendation pointer

See `idea-stage/IDEA_REPORT_v32.md` for what's open after v0.9.5. **v0.9.x track is now fully closed.** Next significant cycle = v0.10.0 — but per ADR-001 + spike findings, the v0.10.0 scope is materially smaller than originally framed. Strong recommendation: scope v0.10.0 around remaining structural cleanup (json_atomic_update migration, COMPLETE/BLOCKED dedup, PARALLEL_MODE extraction) + first non-synthetic dogfood through new outer-loop architecture, NOT a daemon implementation.
