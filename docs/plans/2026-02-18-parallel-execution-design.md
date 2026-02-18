# Design: Parallel Execution via DAG-Driven Worktree Agents

**Date:** 2026-02-18
**Status:** Approved
**Approach:** Worktree Wave Engine (with dual backend: Task subagents for interactive, bash processes for autonomous)

## Overview

The current quantum-loop system executes stories sequentially -- one story per iteration, even when the dependency DAG shows multiple independent stories that could run simultaneously. This wastes wall-clock time on features with wide DAGs (e.g., 4 independent UI components that all depend on a completed schema story).

This feature adds DAG-driven parallel execution: the orchestrator identifies all currently executable stories (dependencies met, retries remaining), creates an isolated git worktree for each, and spawns parallel Claude Code agents. When an agent passes both review gates, its worktree is immediately merged into the feature branch, and the DAG is re-queried to launch newly unblocked stories. Failed stories are retried in the next wave.

The parallel engine works in two modes:
- **Autonomous mode:** `quantum-loop.sh --parallel` spawns background bash processes, each running `claude --print` in its own worktree
- **Interactive mode:** `/ql-execute` uses Claude Code's `Task` tool to launch background subagents, each assigned a worktree

Both modes share the same core logic: DAG query, worktree lifecycle, merge-on-pass, atomic quantum.json updates, and cleanup.

The feature is additive -- `quantum-loop.sh` without `--parallel` and `/ql-execute` in single-story mode continue to work exactly as before.

## User Experience

**Primary interface: `/ql-execute`**

The skill detects parallelism opportunities automatically:

```
/ql-execute
```

Output:
```
Reading quantum.json... 5 stories, 2 passed.
DAG analysis: 3 stories are independently executable right now.

Launching parallel execution:
  [SPAWNED]  US-003 - Add filter endpoint → worktree .ql-wt/US-003
  [SPAWNED]  US-004 - Sort controls       → worktree .ql-wt/US-004
  [SPAWNED]  US-005 - Empty state UI       → worktree .ql-wt/US-005

  [PASSED]   US-005 - merged into ql/task-priority (2m 14s)
  [PASSED]   US-003 - merged into ql/task-priority (3m 41s)
  [FAILED]   US-004 - attempt 1/3, queued for retry

DAG updated: US-006 now unblocked.
  [SPAWNED]  US-004 - Sort controls (retry) → worktree .ql-wt/US-004
  [SPAWNED]  US-006 - Integration tests     → worktree .ql-wt/US-006
  ...
```

No flags needed -- if the DAG has multiple independent stories, the skill runs them in parallel via background Task subagents. If only one story is executable, it runs sequentially as before. The behavior is seamless.

**Autonomous mode (quantum-loop.sh):**

The shell script gains `--parallel` as a secondary interface for overnight runs, mirroring what `/ql-execute` does: query DAG, spawn parallel `claude --print` processes in worktrees, merge on pass. This is the fallback for headless CI/overnight use, not the primary UX.

**Worktree lifecycle:**
- Created at `.ql-wt/<story-id>/` (added to `.gitignore`)
- Each worktree is a full working copy branched from the current feature branch
- Cleaned up immediately after successful merge or after failure is logged
- User can `cd .ql-wt/US-003/` to inspect a running agent's work if needed

**quantum.json additions:**
- Progress entries gain `"wave": 1` and `"parallel": true` fields
- No schema-breaking changes -- sequential entries simply omit these fields

## Data Model

Three additions to quantum.json, all backward-compatible (sequential mode ignores them):

**1. Story-level: `worktree` field (runtime only)**
```json
{
  "id": "US-003",
  "status": "in_progress",
  "worktree": ".ql-wt/US-003"
}
```
Set when a parallel agent is spawned, cleared after merge or failure. Allows the orchestrator to track which stories are currently running and where.

**2. Progress entries: `wave` and `parallel` fields**
```json
{
  "timestamp": "2026-02-18T14:30:00Z",
  "iteration": 3,
  "storyId": "US-003",
  "action": "story_passed",
  "wave": 2,
  "parallel": true,
  "details": "Merged from .ql-wt/US-003",
  "filesChanged": ["api/routes/tasks.py"],
  "learnings": "..."
}
```
Sequential runs simply omit `wave` and `parallel`, or set `"parallel": false`.

**3. Top-level: `execution` metadata (optional)**
```json
{
  "project": "MyApp",
  "execution": {
    "mode": "parallel",
    "maxParallel": null,
    "currentWave": 2,
    "activeWorktrees": [".ql-wt/US-004", ".ql-wt/US-006"]
  },
  "stories": [...]
}
```
This is runtime state for the orchestrator. Null `maxParallel` means DAG-driven maximum. The `activeWorktrees` array enables crash recovery -- if the orchestrator restarts, it can detect and clean up orphaned worktrees.

**Atomic update:** Agents never modify quantum.json directly. They signal pass/fail via stdout. The orchestrator reads the signal and updates the JSON. Write via `quantum.json.tmp` then atomic `mv`.

**No changes to:** Story schema, quantum.json.example, or any existing fields.

## Architecture

```
/ql-execute (or quantum-loop.sh --parallel)
      |
      v
+-------------------+
|   Orchestrator     |  <-- Single process, owns quantum.json
|                    |
|  1. Query DAG      |  <-- Find all executable stories
|  2. Create WTs     |  <-- git worktree add .ql-wt/US-XXX
|  3. Spawn agents   |  <-- One per worktree (Task tool or bash)
|  4. Monitor        |  <-- Poll for completion signals
|  5. Merge          |  <-- git merge from worktree into feature branch
|  6. Update JSON    |  <-- Atomic write (only orchestrator writes)
|  7. Cleanup WT     |  <-- git worktree remove
|  8. Re-query DAG   |  <-- Loop back to step 1
+-------------------+
      |
      +---- Agent A (.ql-wt/US-003/)
      |     +-- Fresh claude instance
      |         +-- Reads quantum.json (read-only)
      |         +-- Implements story in worktree
      |         +-- Runs quality checks + reviews
      |         +-- Outputs <quantum>STORY_PASSED</quantum>
      |
      +---- Agent B (.ql-wt/US-004/)
      |     +-- (same as above, different story)
      |
      +---- Agent C (.ql-wt/US-005/)
            +-- (same as above, different story)
```

**Key architectural rules:**

1. **Orchestrator is the single writer.** Agents never modify quantum.json directly. They signal pass/fail via stdout. The orchestrator reads the signal and updates the JSON. This eliminates race conditions.

2. **Agents are identical to sequential agents.** The implementer agent, CLAUDE.md template, review gates -- all unchanged. An agent doesn't know or care whether it's running alone or in parallel. The only difference is its working directory is a worktree instead of the repo root.

3. **Worktrees branch from HEAD of the feature branch.** When the orchestrator creates a worktree, it branches from the current tip of `ql/<feature>`. When a story passes, its worktree is merged back into `ql/<feature>`, advancing HEAD. The next worktree created will include the merged changes.

4. **Merge-on-pass, not wave-based.** The orchestrator doesn't wait for all running agents. As soon as one signals STORY_PASSED, merge immediately, re-query DAG, and spawn any newly unblocked stories. This maximizes throughput.

5. **Two spawn backends, same orchestration logic:**
   - **Interactive (`/ql-execute`):** Uses `Task` tool with `run_in_background: true`. Monitors via `TaskOutput` with `block: false` polling.
   - **Autonomous (`quantum-loop.sh`):** Uses `claude --print` background processes. Monitors via `wait -n` or polling output files.

## Edge Cases & Error Handling

**Merge conflicts:**
Even with a correct DAG, two independent stories might touch the same file (e.g., both add an import to `index.ts`). When `git merge` fails:
1. Orchestrator logs the conflict to `retries.failureLog` with `"phase": "merge_conflict"`
2. Story status set to `"failed"`, worktree cleaned up
3. Story retries in the next cycle -- by then, the conflicting story's changes are in the branch, so the retry works against the merged codebase
4. Same retry logic and `maxAttempts` as any other failure

**Agent crashes or hangs:**
- **Timeout:** Per-story timeout (default: 15 minutes, configurable). If no signal received, kill the process, mark story `"failed"` with `"phase": "timeout"`, clean up worktree.
- **Crash (non-zero exit, no signal):** Same as timeout -- mark failed, clean up, retry.

**Orphaned worktrees (crash recovery):**
On next run, check `execution.activeWorktrees` in quantum.json. For each listed worktree that still exists on disk: `git worktree remove --force`, reset story status from `"in_progress"` to `"pending"`. Log a warning.

**quantum.json corruption:**
Write to `quantum.json.tmp` first, then atomic `mv quantum.json.tmp quantum.json`. If `quantum.json.tmp` exists on startup, delete it (incomplete write).

**All agents in a wave fail:**
Normal retry logic applies. If no stories are eligible after retries, exit with `BLOCKED`.

**Resource exhaustion:**
Optional `--max-parallel N` flag caps concurrent agents. If not set, DAG-driven maximum applies (typically 2-5 for real features).

**What we explicitly do NOT handle:**
- Deadlocks (impossible -- agents don't share locks or communicate)
- Partial merges (a story either fully merges or doesn't)
- Agent-to-agent communication (out of scope)

## Testing Strategy

**1. Unit tests for DAG query logic:**
- Verify correct executable stories returned for known dependency graphs
- Edge cases: circular dependencies, all passed, all blocked, single-story DAG
- Stories with `status: "in_progress"` excluded from executable set

**2. Worktree lifecycle tests:**
- Creation: `.ql-wt/US-XXX/` exists, correct branch, full working copy
- Merge: changes appear on feature branch
- Cleanup: worktree directory removed after merge or failure
- Crash recovery: orphaned worktrees detected and cleaned up

**3. Merge conflict simulation:**
- Two stories modifying the same file run in parallel
- One merges, other gets `"phase": "merge_conflict"` in failure log
- Failed story succeeds on retry against merged codebase

**4. Orchestrator integration test:**
- 4-story DAG: US-001 (passed) -> US-002, US-003 (independent) -> US-004 (depends on both)
- Verify US-002 and US-003 spawn in parallel
- Verify US-004 only spawns after both pass
- Verify progress entries have correct `wave` and `parallel` fields

**5. Timeout and failure test:**
- Mock agent that never signals completion
- Verify orchestrator kills after timeout, marks failed, cleans up
- Other parallel agents unaffected

**6. Backward compatibility test:**
- `quantum-loop.sh` without `--parallel` behaves identically to current sequential mode
- quantum.json without `execution` field handled gracefully

## Open Questions

- Should the per-story timeout (15 min default) scale with task count in the story?
- Should we add a `--dry-run` flag that shows which stories would run in parallel without executing?

## Next Steps

Run `/ql-spec` to generate a formal Product Requirements Document from this design.
