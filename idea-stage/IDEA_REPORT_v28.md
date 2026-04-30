# IDEA_REPORT_v28 — what's open after v0.9.1

**Date:** 2026-04-30
**Source:** v0.9.1 N42-validate dogfood succeeded (streak broken); 3-reviewer trio surfaced HIGH finding (5a) + 4 v0.9.2 candidates.
**Branch:** `ql/v0.9.1-bundle` (release tag v0.9.1 — pending)
**Predecessor:** `idea-stage/IDEA_REPORT_v27.md`

## Closed in v0.9.1

| ID | Story | Notes |
|---|---|---|
| **N42-validate** | US-001 + US-002 | Real-LLM dogfood through `--coordinator` succeeded end-to-end. Streak BROKEN. |
| **5b cosmetic printf** | US-003 | Legacy `Spawning %s for story %s` gated under non-coordinator mode |
| **Multi-perspective review pattern** | US-004 | Validated 5th cycle (post-v0.8.1/v0.8.2/v0.8.3/v0.8.4/v0.9.1) |

## Persistent canon

p001-p012 carried forward. p013 candidate ("pre-cycle 3-architect design + post-cycle 3-reviewer trio") not yet formalized — wait until 3rd consecutive cycle uses it (v0.9.2 candidate).

## v0.9.2 candidate slate (PRIMARY follow-up — all surfaced by v0.9.1 review trio)

### Primary: finding 5a (HIGH)

**Status:** new. Coordinator dispatched US-B implementer ran `git reset --hard d66aaf8` before its commit, wiping US-A's prior commit. Coordinator self-healed via emergent recovery (`fix: US-A recovery - restore marker after US-B implementer reset HEAD`). Self-healing only worked because the synthetic plan was trivially simple.
**Severity:** HIGH (post-architect-review bump from MEDIUM-HIGH).
**Path options for v0.9.2:**
1. **Coordinator HEAD-snapshot guard** — coordinator captures `HEAD_BEFORE` before each implementer dispatch; refuses to advance if `HEAD_AFTER < HEAD_BEFORE` (i.e., commits were lost). Engineered safety net replaces emergent recovery.
2. **Per-story isolated worktrees** — each implementer in a wave gets its own `.ql-wt/<story>/` worktree (mirrors `--parallel` pattern). Eliminates shared-worktree drift class entirely.
3. **Hybrid** — option 1 by default; option 2 opt-in via `--coordinator-isolated`.

**Architect's caveat on option 2:** functionally equivalent to `--parallel`'s worktree dispatch. Adopting it inside the coordinator would violate the v0.8.2 US-004 mutual exclusion. Either policy must be re-negotiated, OR option 1 is preferred (architecturally cheaper).

### Secondary: code-reviewer MEDIUM

**Status:** new. `quantum-loop.sh:1673-1682` `STORY_PASSED`/`STORY_FAILED`/`BLOCKED` case branches still use scalar `$STORY_ID` and `$STORY_ATTEMPT`. Under coordinator mode the contract requires `WAVE_*` signals, so these branches are not expected to fire — but a coordinator bug emitting `STORY_PASSED` instead would orphan wave members.
**Severity:** MEDIUM (latent; defense-in-depth).
**Path:** gate the legacy case branches under `[[ "$COORDINATOR_MODE" == "true" ]]` to redirect through the wave-aware jq, OR log a warning on unexpected signal under coordinator mode.

### Architect risks

- **Architect #1** — `filePaths` omission silent bypass at `lib/dag-query.sh:142-172`. Stories with empty `filePaths` arrays bypass `filter_file_conflicts` despite modifying the same file. Operator PRDs under time pressure may omit. Input-validation gap.
  **Severity:** MEDIUM. **Path:** v0.9.2 add an explicit input check (warn on empty `filePaths` for any story whose `tasks` modify files); OR add a `fileConflicts` synthesis from `git diff --name-only` post-task.
- **Architect #2** — N46 (respawn output not re-parsed) remains latent. Currently gated off under coordinator mode (`quantum-loop.sh:1657`). v0.9.2+ if wrap is re-enabled.
  **Severity:** LOW (deferred-debt; no active risk).
- **Architect #3** — per-story worktree isolation conflicts with `--coordinator --parallel` mutual exclusion. Captured in 5a path option 2.

## Still open (carried forward)

### N43, N46, N47, N48, N49, N50

All unchanged. LOW priority. **N47 (branch cleanup)** still operator-decision-pending — 17+ local branches now (v0.7.x..v0.9.1).

### N40, N38, copilot rate-limit observability, N41, N44, N45

All unchanged. LOW priority.

## Recommendation for next

**v0.9.2 candidate slate (patch-tier — closes the 5a HIGH known-issue advisory):**

| Story | Content |
|-------|---------|
| US-001 | Coordinator HEAD-snapshot guard: `HEAD_BEFORE` captured pre-dispatch; reject implementer commit chains that move HEAD backward. New regression-guard test in `tests/test_coordinator_e2e.sh`. (Architect-recommended over option 2.) |
| US-002 | Gate legacy `STORY_PASSED`/`STORY_FAILED`/`BLOCKED` case branches under coordinator mode (code-reviewer MEDIUM). Defense-in-depth. |
| US-003 | `filePaths` validation: warn on empty `filePaths` for any story whose `tasks` modify files (architect MEDIUM). Add to `lib/dag-query.sh` or new `lib/quantum-validate.sh`. |
| US-004 | Real-LLM dogfood under v0.9.2 wires (mirrors v0.9.1 dogfood; verify HEAD-snapshot guard fires + 5a no longer reproducible). |
| US-005 | Retrospective + IDEA_REPORT_v29 + version bump 0.9.1 → 0.9.2. |

**Honest framing for v0.9.2:** patch-tier (no new architecture; defensive hardening). Closes the v0.9.1 known-issue advisory. Sets up potential v0.9.3 dogfood (real feature, not synthetic) once HEAD-snapshot guard validated.

## Recurring observations

- **22 consecutive LOW G30 self-validations** (v0.6.5..v0.9.1).
- **Bundle size: ...4-4-7-5.** v0.9.1 is 5-story validation patch (matches v0.8.1 N39 dogfood pattern).
- **Manual-takeover streak BROKEN at 18 cycles.** First break since v0.6.7. Conditional (synthetic plan; single iteration; one platform); real-feature production validation = v0.9.3+.
- **Pre-cycle 3-architect + post-cycle 3-reviewer pattern validated 2nd time.** Once more (v0.9.2) and p013 formalization candidate.
- **Operator pre-staged the v0.9.1 cycle artifacts** (design + PRD + quantum.json + advisory hooks committed at `428c7ca` before US-001 kickoff). New pattern: operator-staged kickoff for follow-up cycles where the candidate slate is well-defined. Validates the IDEA_REPORT pipeline as the source-of-truth for follow-up scope.

## v0.9.x track outlook

v0.9.0 (architectural minor — wires) → **v0.9.1 (validation patch — streak BROKEN; 5a HIGH surfaced)** → v0.9.2 (defensive hardening — closes 5a + 3 secondary findings) → v0.9.3+ (real-feature dogfood; production confidence).
