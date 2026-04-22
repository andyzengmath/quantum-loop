# Design: Hardening Layer v2 — Post-Mortem Fixes

**Date:** 2026-03-28
**Status:** Approved
**Approach:** Hardening Layer v2
**Source:** `docs/post-mortems/2026-03-28-cross-repo-research-execution.md` (from Logical_inference repo)

## Overview

**What we're building:** A comprehensive hardening pass for the quantum-loop orchestrator that addresses all 7 issues observed in the cross-repo research execution (2026-03-28 post-mortem). The changes span three categories:

1. **Targeted patches** to existing modules — fixing `git add -A` usage, quantum.json stash exclusion, materialization threshold, and worktree pruning at init
2. **New modules** for capabilities that don't exist today — `init-guard.sh` for environment pre-flight checks, `merge-semantic.sh` for AST-aware 3-way conflict resolution, and `resilience.sh` for WIP commit/squash-on-merge crash recovery
3. **Agent prompt updates** to `orchestrator.md`, `implementer.md`, `CLAUDE.md`, and `spawn.sh` to align agent behavior with the new capabilities

**Why:** The post-mortem showed that while all 19 stories eventually passed, the system wasted ~3 hours on npm path issues, corrupted quantum.json state during merges, silently dropped code via `ours`/`theirs` resolution, and lost agent progress on session restart. These are systemic issues that will recur on every future run unless addressed.

**Scope:** All changes are within the quantum-loop plugin — `lib/`, `agents/`, `CLAUDE.md`, and `tests/`. No changes to external repos or the Claude Code platform itself.

## User Experience

The user interacts with quantum-loop through the same commands as today (`/ql-execute`, `/ql-plan`, etc.). The fixes are mostly invisible — the system just works better. Here's what changes from the user's perspective:

**At orchestrator init (new pre-flight output):**
```
[INIT-GUARD] Environment pre-flight check...
[INIT-GUARD] WARN: Repo path contains 'OneDrive' (79 chars). Worktrees will use short paths under /tmp/ql-wt-*.
[INIT-GUARD] Pruned 3 stale worktree references from previous sessions.
[INIT-GUARD] Cleaned 2 orphaned .ql-wt/ directories.
[INIT-GUARD] Pre-flight complete. 0 blockers, 1 warning.
```

The warning is informational — execution continues. No new flags or config needed unless the user wants to override the short-path behavior.

**During agent execution (WIP commits — mostly invisible):**
Agents now commit after each completed task in worktree mode:
```
[IMPLEMENTER] Task T-001 passed — WIP commit: "wip: US-005 T-001 - Create provider interface"
[IMPLEMENTER] Task T-002 passed — WIP commit: "wip: US-005 T-002 - Implement OpenAI adapter"
```
On session restart, the orchestrator detects these WIP commits and can re-spawn the agent with a "resume from last WIP" hint instead of starting from scratch.

**During merge (semantic merge — visible only on conflict):**
```
[MERGE-STRATEGY] Conflict on src/types/cross-repo.ts
[MERGE-SEMANTIC] Attempting AST-aware 3-way merge...
[MERGE-SEMANTIC] Merged: kept 3 types from ours + 2 types from theirs (0 true conflicts)
[MERGE-STRATEGY] Resolved 1/1 conflicts (semantic). Merge completed in 1240ms
```
Falls back to the existing `ours`/`theirs` classification if semantic merge fails or the file type isn't supported.

**On `git add` (invisible change):**
Agents commit specific files instead of `git add -A`. No user-visible difference except fewer index.lock issues.

## Data Model

No new files or schemas are introduced. Changes are additions to existing quantum.json fields and module interfaces.

**quantum.json additions:**

```json
{
  "execution": {
    "initGuard": {
      "ranAt": "2026-03-28T10:00:00Z",
      "warnings": ["onedrive_long_path"],
      "shortPathBase": "/tmp/ql-wt-a1b2c3d4",
      "prunedWorktrees": 3,
      "cleanedOrphans": 2
    },
    "mergeStrategy": {
      "rules": ["...existing..."],
      "defaultAction": "escalate",
      "semanticMergeEnabled": true,
      "semanticMergeLanguages": ["typescript", "python"]
    },
    "resilience": {
      "wipCommitsEnabled": true,
      "squashOnMerge": true
    }
  }
}
```

- `initGuard` — records pre-flight results so subsequent waves skip redundant checks
- `semanticMergeEnabled` / `semanticMergeLanguages` — opt-in per project. Defaults to `true` for TypeScript and Python where AST tooling is mature.
- `resilience.wipCommitsEnabled` — controls whether agents make per-task WIP commits. Default `true`.
- `resilience.squashOnMerge` — controls whether the orchestrator squashes WIP commits into a single merge commit. Default `true`.

**Story-level additions:**

```json
{
  "id": "US-005",
  "status": "in_progress",
  "lastWipCommit": "abc1234",
  "completedTasks": ["T-001", "T-002"]
}
```

- `lastWipCommit` — SHA of the most recent WIP commit in the worktree. Used by resilience module to detect resumable progress on stale detection.
- `completedTasks` — list of task IDs that have been WIP-committed. On re-spawn, the agent skips these tasks.

**No changes to:** story schema structure, contracts, fileConflicts, DAG dependencies, or progress entries. All additions are backward-compatible — missing fields fall back to defaults.

## Architecture

The system adds 3 new modules to `lib/` and modifies 4 existing components. Here's how they connect:

**New modules:**

```
lib/
├── init-guard.sh          (NEW - environment pre-flight)
├── merge-semantic.sh      (NEW - AST-aware 3-way merge)
├── resilience.sh          (NEW - WIP commits + crash recovery)
├── merge-strategy.sh      (MODIFIED - stash exclusion, semantic merge delegation)
├── worktree.sh            (MODIFIED - prune at cleanup)
├── monitor.sh             (MODIFIED - squash-on-merge)
├── materialize.sh         (MODIFIED - threshold change)
└── ...existing modules unchanged...
```

**Module responsibilities and call flow:**

```
orchestrator init
  └─> init-guard.sh
        ├─ detect_environment()     — checks OneDrive, path length, OS
        ├─ warn_long_path()         — logs warning, sets shortPathBase
        ├─ prune_stale_refs()       — git worktree prune
        └─ cleanup_orphan_dirs()    — removes .ql-wt/* from previous sessions

orchestrator spawn agent
  └─> implementer (in worktree)
        └─> resilience.sh
              ├─ wip_commit()       — commits after each task: "wip: US-XXX T-YYY - title"
              └─ record_wip()       — writes lastWipCommit + completedTasks to stdout signal

orchestrator merge
  └─> merge-strategy.sh (existing)
        ├─ classify_and_merge()     — MODIFIED: excludes quantum.json from stash
        ├─ on conflict:
        │    └─> merge-semantic.sh  (NEW - called when action would be "ours" or "theirs")
        │          ├─ can_semantic_merge(file)  — checks language support + AST parsability
        │          ├─ semantic_merge(base, ours, theirs, output)
        │          │    ├─ TypeScript: ts-morph to parse, diff AST nodes, merge non-overlapping
        │          │    ├─ Python: libcst to parse, diff nodes, merge non-overlapping
        │          │    └─ Fallback: diff3 line-level 3-way merge
        │          └─ returns 0 (merged) or 1 (true conflict, fall back to ours/theirs)
        └─> monitor.sh
              └─ squash_and_merge()  — NEW: replaces direct merge for WIP-commit branches
                    ├─ git merge --squash <worktree-branch>
                    ├─ git commit -m "feat: US-XXX - Title"
                    └─ falls back to regular merge if no WIP commits detected
```

**Key design decisions:**

1. **Semantic merge is a fallback enhancer, not a replacement.** `classify_and_merge()` still runs first. Only when it would use `ours`/`theirs` does it delegate to `merge-semantic.sh`. If semantic merge fails, the original `ours`/`theirs` action proceeds.

2. **WIP commits are in the worktree branch only.** The feature branch never sees them — `squash_and_merge()` collapses them into one commit. This means the orchestrator's post-merge typecheck and test suite see a clean single-commit diff.

3. **init-guard runs once per session.** Results are written to `execution.initGuard` so subsequent waves don't re-run environment detection.

4. **AST tooling is optional.** If `ts-morph` or `libcst` aren't installed, `can_semantic_merge()` returns false and the system falls back to `diff3`. If `diff3` isn't available either, it falls back to the existing `ours`/`theirs` behavior.

## Edge Cases & Error Handling

**init-guard.sh:**

| Edge Case | Handling |
|-----------|----------|
| Repo path is long but NOT OneDrive (e.g., deep WSL mount) | Warning triggers on path length alone (>150 chars), not just OneDrive detection. OneDrive is called out specifically in the message but the guard is path-length-generic. |
| `/tmp` is not writable (rare container environments) | `detect_environment()` tests write access to `$TMPDIR` fallback. If unwritable, logs a CRITICAL warning and forces sequential mode (no worktrees). |
| Previous session's `.ql-wt/` has uncommitted changes | `cleanup_orphan_dirs()` checks for uncommitted changes before deleting. If found, logs `[INIT-GUARD] WARN: .ql-wt/US-XXX has uncommitted work — preserving for manual inspection` and skips that directory. |
| `git worktree prune` fails (permission issues on Windows) | Retry once after 2s. If still fails, log warning and continue — this is non-blocking. |

**merge-semantic.sh:**

| Edge Case | Handling |
|-----------|----------|
| AST parse failure (syntax error in merged file) | `can_semantic_merge()` returns false. Falls back to existing `ours`/`theirs`. Logs `[MERGE-SEMANTIC] Parse failed for <file> — falling back to rule-based resolution`. |
| Both sides add the same symbol name with different implementations | True conflict — semantic merge returns 1. `classify_and_merge()` uses the original rule-based action. |
| Both sides add different symbols (no overlap) | Clean merge — both additions are kept. This is the primary value-add over `ours`/`theirs`. |
| File type not supported (e.g., `.go`, `.rs`, `.json`) | `can_semantic_merge()` returns false for unsupported languages. `diff3` fallback attempted for text files. Binary files always fall back to rule-based. |
| `ts-morph` / `libcst` not installed | Detected at module load time. `SEMANTIC_MERGE_AVAILABLE` flag set to false. `diff3` used as intermediate fallback. |
| Semantic merge produces file that fails typecheck | Caught by existing `post_merge_typecheck()` gate. Merge is reverted, story marked failed, retried next wave with rule-based merge. |

**resilience.sh:**

| Edge Case | Handling |
|-----------|----------|
| Agent dies between task completion and WIP commit | Task work is in the working directory but uncommitted. On stale detection, orchestrator checks `git status` in the worktree. If dirty + has prior WIP commits, the last WIP commit is still valid — agent resumes from that point. |
| Agent's WIP commit has a failing test | WIP commits don't require passing tests — only the final story commit does. On re-spawn, the agent picks up from `completedTasks` and continues. Quality gates run at the end. |
| `squash_and_merge()` encounters conflicts | Same flow as regular merge — delegates to `classify_and_merge()` which delegates to semantic merge. The squash just changes `git merge` to `git merge --squash`. |
| Story has 0 WIP commits (all tasks completed in one shot) | `squash_and_merge()` detects single commit on worktree branch, falls back to regular `--no-ff` merge. No behavioral difference. |
| `completedTasks` list is stale (code was modified after WIP commit) | On re-spawn, agent verifies each "completed" task by running its test command. If a previously-passed task now fails, it's removed from `completedTasks` and re-implemented. |

**quantum.json stash exclusion (merge-strategy.sh):**

| Edge Case | Handling |
|-----------|----------|
| quantum.json is tracked (not in .gitignore) | `classify_and_merge()` explicitly backs up quantum.json with `cp`, removes it from stash scope using `git stash push --keep-index -- ':!quantum.json'`, restores after merge. |
| Other untracked dirty files besides quantum.json | Still stashed normally. Only quantum.json gets special treatment. |
| Stash pop fails on non-quantum.json files | Existing behavior: `git stash pop -q 2>/dev/null || true` — silently drops failed pop. This is acceptable since the merge already committed. |

## Testing Strategy

Testing spans three tiers: unit tests for each module, integration tests for orchestrator flows, and a live validation run.

**Tier 1: Unit Tests (shell-based, extend existing `tests/` suite)**

| Module | Test File | Key Test Cases |
|--------|-----------|---------------|
| `init-guard.sh` | `tests/test_init_guard.sh` | OneDrive path detection, path length thresholds, `/tmp` write check, orphan cleanup with uncommitted work preservation, `git worktree prune` retry on failure, idempotent re-runs |
| `merge-semantic.sh` | `tests/test_merge_semantic.sh` | Both-sides-add-different-symbols merge, same-symbol true conflict fallback, parse failure fallback, unsupported language fallback, `diff3` intermediate fallback, missing `ts-morph`/`libcst` graceful degradation |
| `resilience.sh` | `tests/test_resilience.sh` | WIP commit creation with correct message format, `completedTasks` tracking, squash-on-merge producing single commit, single-commit branch fallback to `--no-ff`, stale task re-verification |
| `merge-strategy.sh` | `tests/test_merge_strategy.sh` (extend) | quantum.json excluded from stash, quantum.json backup/restore cycle, semantic merge delegation on `ours`/`theirs` classified files |
| `worktree.sh` | `tests/test_worktree.sh` (extend) | Orphan `.ql-wt/` cleanup, prune at init, uncommitted work detection |
| `materialize.sh` | `tests/test_materialize.sh` (extend) | Single-consumer types now materialized (threshold change), existing multi-consumer tests still pass |

Each test file follows the existing pattern: create temp git repos, simulate scenarios, assert outcomes. Target: all new logic paths covered.

**Tier 2: Integration Tests (end-to-end module interaction)**

| Test File | Scenario |
|-----------|----------|
| `tests/integration/test_init_to_merge.sh` | Full flow: init-guard -> create worktree -> implement with WIP commits -> squash merge -> typecheck gate. Validates the modules work together. |
| `tests/integration/test_semantic_merge_conflict.sh` | Two worktree branches both add exports to the same TypeScript file. Semantic merge resolves without dropping code. Verify both additions present in merged output. |
| `tests/integration/test_crash_recovery.sh` | Simulate session restart: create worktree with 3 WIP commits, kill agent, run stale detection, re-spawn, verify agent skips completed tasks and finishes from WIP state. |
| `tests/integration/test_stash_isolation.sh` | Merge a worktree branch while quantum.json is dirty. Verify quantum.json is not corrupted, not included in stash, and retains orchestrator's in-memory state after merge. |

**Tier 3: Live Validation**

After all unit and integration tests pass, run a real quantum-loop execution on a small test feature (3-5 stories) that deliberately triggers the fixed scenarios:
- At least 2 stories editing the same TypeScript file (tests semantic merge)
- Repo path on the current OneDrive location (tests init-guard warning + short-path worktrees)
- Manually interrupt one agent mid-execution (tests WIP recovery)
- At least one wave with 2+ parallel agents (tests squash-on-merge, `git add` specific files)

**Success criteria for live validation:**
- All stories pass without manual intervention
- No quantum.json corruption
- Semantic merge preserves code from both sides on the shared file
- Interrupted agent recovers from WIP commits on re-spawn
- No `index.lock` contention errors in logs

## Open Questions

- **Semantic merge granularity:** Should `merge-semantic.sh` merge at the statement level (fine-grained, higher risk of subtle bugs) or the top-level declaration level (coarser, safer)? Starting with top-level declarations and iterating.
- **WIP commit frequency:** Should agents commit after every task, or only after tasks that create/modify files? Leaning toward every task for consistency.
- **`diff3` availability on Windows Git Bash:** Need to verify `diff3` ships with Git for Windows. If not, the intermediate fallback layer may not be available on the primary target platform.
- **Materialization threshold change impact:** Lowering from `consumers >= 2` to `consumers >= 1` means ALL contract types get materialized. This increases the pre-wave commit size. Need to validate this doesn't slow down worktree creation on large plans.

## Next Steps

Run `/quantum-loop:spec` to generate a formal Product Requirements Document from this design.
