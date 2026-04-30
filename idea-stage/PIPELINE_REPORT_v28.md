# PIPELINE_REPORT_v28 — v0.9.1 retrospective (N42-validate dogfood)

**Date:** 2026-04-30
**Bundle:** `ql/v0.9.1-bundle` (release tag v0.9.1 — pending push/PR/merge/tag/release)
**Predecessor report:** `idea-stage/PIPELINE_REPORT_v27.md`
**Master parent:** `d66aaf8` (v0.9.0 ship state)
**Source:** Operator-staged plan + 3-architect post-merge review trio (architect + code-reviewer + security).

## Overview

v0.9.1 is the validation patch for v0.9.0 N42. Mirrors v0.8.0 → v0.8.1's pattern (architectural minor → validation patch). Empirical proof point for the 18-cycle manual-takeover streak.

## Headline result

**18-cycle manual-takeover streak BROKEN.** First cycle in 19 (v0.6.7..v0.9.0) where the autonomous loop drove a complete 2-story plan to `<quantum>COMPLETE</quantum>` exit 0 without manual takeover.

Caveats:
- Synthetic 2-story plan (one marker comment per file).
- One coordinator iteration only.
- Single platform (Git Bash on Windows).
- Internal implementer drift surfaced (5a HIGH); coordinator self-healed via emergent recovery.

## The 5 stories

| # | ID | Title | Outcome |
|:-:|---|---|:-:|
| 0 | (cycle setup) | Operator pre-staged design + PRD + advisory hooks | committed at `428c7ca` |
| 1 | US-001+US-002 | Real-LLM dogfood + findings synthesis (atomic) | first-attempt PASS at `86e4e85` |
| 2 | US-003 | Inline fix 5b (printf gate); 5a deferred | first-attempt PASS at `90c23e4` |
| 3 | US-004 | Multi-perspective post-merge review (architect + code-reviewer + security) | findings absorbed into US-005 |
| 4 | US-005 | Retrospective + IDEA_REPORT_v28 + version bump + worktree cleanup | this report |

## Multi-perspective review synthesis

| Reviewer | Verdict | Key finding |
|---|---|---|
| **Code-reviewer** | APPROVE | 1 MEDIUM latent: `STORY_PASSED`/`STORY_FAILED`/`BLOCKED` case branches still use scalar `$STORY_ID` under coordinator mode. Not reachable today (coordinator emits `WAVE_*`), but defense-in-depth would gate them. v0.9.2 candidate. |
| **Architect** | Streak-break HONEST | **Bumped 5a severity from MEDIUM-HIGH → HIGH.** Reasoning: (1) `git reset --hard` is unconditionally destructive — real data loss; (2) self-healing was emergent, not engineered; (3) only worked because synthetic plan was trivially simple. Surfaced 3 new v0.9.2 risks (worktree isolation conflicts with `--coordinator --parallel`; `filePaths` omission silent bypass; N46 deferred-debt). Recommended CHANGELOG known-issue advisory for v0.9.1. |
| **Security** | 0 active findings | (Output incomplete; no findings emitted in transcript.) |

## v0.9.1 fixes shipped + deferrals

### US-003 inline fix (5b LOW)
`quantum-loop.sh:1569-1577` legacy `Spawning %s for story %s...` printf gated under `[[ "$COORDINATOR_MODE" != "true" ]]`. Coordinator-mode branch already prints accurate `Spawning coordinator for wave-N with K story/stories: ...`.

### Deferred to v0.9.2
- **5a (HIGH)** — coordinator HEAD-snapshot guard OR per-story worktree isolation. **CHANGELOG known-issue advisory shipped in v0.9.1.**
- **Code-reviewer MEDIUM** — gate `STORY_PASSED`/`STORY_FAILED`/`BLOCKED` case branches under coordinator mode (defense-in-depth).
- **Architect risk #1** — per-story worktree isolation conflicts with `--coordinator --parallel` mutual exclusion; v0.9.2 design must choose explicitly between worktree-isolation and HEAD-snapshot guard.
- **Architect risk #2** — `filter_file_conflicts` silently bypasses on empty `filePaths` arrays. Operator PRDs under time pressure may omit. Input-validation gap.
- **Architect risk #3** — N46 (respawn output not re-parsed) remains latent. Comment-only marker; not active risk while wrap is gated off under coordinator mode.

## Wave plan vs. realized

US-001 dependsOn nothing (entry point). US-002 dependsOn US-001 (synthesis needs raw evidence). US-003 dependsOn US-002 (defects come from findings). US-004 dependsOn US-001+US-002+US-003 (review needs all cycle changes). US-005 dependsOn all.

Realized order:
1. US-001 + US-002 atomic (worktree dogfood + findings doc)
2. US-003 (5b fix; 5a deferral)
3. US-004 (3 parallel reviewers via Agent tool)
4. US-005 (this retrospective; version bump; worktree cleanup; CHANGELOG advisory)

## G30 self-validation — 22nd consecutive LOW

`bash lib/deep-review.sh score $BASE $HEAD` → tier=LOW (small diff: 1 inline fix + new findings doc + retrospective + version bump). Recorded with `automated:true`. **22 consecutive LOW-tier self-validations** (v0.6.5..v0.9.1).

## CSV milestone

`metrics/pre-impl-review-findings.csv` → 55 rows. Advisory hook findings for v0.9.1: design + prd + plan all 1 LOW each.

## Test-suite delta vs v0.9.0

| Test file | v0.9.0 | v0.9.1 | delta |
|---|---:|---:|---:|
| (no new test files) | | | 0 |

Test count carried forward at 89/89 (unchanged from v0.9.0). v0.9.2 may add a regression-guard test for finding 5a once the fix is designed.

## Manual-takeover streak

**v0.9.1 BROKE the 18-cycle streak.** v0.6.7 → v0.9.0 was the manual-takeover era; v0.9.1 dogfood is the empirical break point. The break is real but conditional (synthetic plan, single iteration, one platform). Real-feature production validation remains future work.

## codebasePatterns

p001-p012 carried forward. No new patterns this cycle. The "pre-cycle 3-architect design + post-cycle 3-reviewer trio" pattern (validated in v0.9.0 + v0.9.1) is now mature enough to reference as **p013** in v0.9.2+ retrospectives if applied a third time.

## Recommendation pointer

See `idea-stage/IDEA_REPORT_v28.md` for what's open after v0.9.1.
