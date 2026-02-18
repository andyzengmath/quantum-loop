# PRD: Parallel Execution via DAG-Driven Worktree Agents

## 1. Introduction/Overview

The quantum-loop plugin currently executes user stories sequentially -- one per iteration -- even when the dependency DAG shows multiple independent stories that could run simultaneously. This feature adds DAG-driven parallel execution: the orchestrator identifies all independently executable stories, creates an isolated git worktree for each, spawns parallel Claude Code agents, and merges results immediately on pass. This reduces wall-clock time proportionally to the width of the dependency graph.

## 2. Goals

- Reduce wall-clock execution time for features with 2+ independent stories by running them in parallel
- Maintain full backward compatibility -- sequential mode is unchanged when no `--parallel` flag is used or only one story is executable
- Keep agents identical to sequential agents -- parallel execution is purely an orchestration concern
- Provide crash recovery for interrupted parallel runs (orphaned worktrees, stale in_progress states)
- Support both interactive mode (`/ql-execute` via Task subagents) and autonomous mode (`quantum-loop.sh --parallel` via bash processes)

## 3. User Stories

### US-001: DAG query returns all independently executable stories
**Description:** As the orchestrator, I want to query the DAG for all stories whose dependencies are met and that are not currently in_progress, so that I can spawn agents for all of them simultaneously.

**Acceptance Criteria:**
- [ ] Given stories where all `dependsOn` stories have `status: "passed"`, and their own status is `"pending"` or `"failed"` with retries remaining, they are returned as executable
- [ ] Stories with `status: "in_progress"` are excluded from the executable set
- [ ] Stories with `retries.attempts >= retries.maxAttempts` are excluded
- [ ] If no stories are executable and all are passed, return COMPLETE signal
- [ ] If no stories are executable and some are not passed, return BLOCKED signal
- [ ] Circular dependencies are detected and reported as an error before execution begins

### US-002: Create and clean up git worktrees
**Description:** As the orchestrator, I want to create an isolated git worktree for each parallel agent and clean it up after merge or failure, so that agents don't interfere with each other's file changes.

**Acceptance Criteria:**
- [ ] `git worktree add .ql-wt/US-XXX ql/<feature-branch>` creates a worktree at the correct path
- [ ] The worktree is branched from the current HEAD of the feature branch
- [ ] After successful merge, `git worktree remove .ql-wt/US-XXX` removes the worktree
- [ ] After failure, worktree is removed and story status updated
- [ ] `.ql-wt/` directory is added to `.gitignore`
- [ ] `quantum.json.tmp` and `quantum.json.lock` are added to `.gitignore`

### US-003: Spawn parallel agents with story assignment via CLI argument
**Description:** As the orchestrator, I want to spawn one Claude Code agent per executable story, passing the story ID as a CLI argument, so that each agent knows which story to implement.

**Acceptance Criteria:**
- [ ] In interactive mode: agent spawned via `Task` tool with `run_in_background: true`, prompt includes story ID
- [ ] In autonomous mode: agent spawned via `claude --print` background process in the worktree directory, prompt includes story ID
- [ ] Each agent receives the story ID explicitly (not inferred from quantum.json in_progress scan)
- [ ] Agent works entirely within its assigned worktree directory
- [ ] Multiple agents run concurrently (verified by checking process/task count)

### US-004: Monitor agents and merge on pass
**Description:** As the orchestrator, I want to detect when any agent signals completion and immediately merge its worktree into the feature branch, so that fast stories don't wait for slow ones.

**Acceptance Criteria:**
- [ ] Orchestrator polls for `<quantum>STORY_PASSED</quantum>` signal from each running agent
- [ ] On STORY_PASSED: `git merge` brings the worktree branch commits into the feature branch (no squash, no rebase)
- [ ] On successful merge: story status set to `"passed"`, worktree cleaned up, progress entry added with `"parallel": true` and `"wave": N`
- [ ] On merge conflict: story status set to `"failed"`, `retries.failureLog` entry with `"phase": "merge_conflict"`, worktree cleaned up
- [ ] On STORY_FAILED: story status set to `"failed"`, retries incremented, worktree cleaned up
- [ ] After any agent completes (pass or fail): re-query DAG and spawn newly unblocked stories immediately
- [ ] Only the orchestrator writes quantum.json -- agents signal via stdout only

### US-005: Atomic quantum.json updates
**Description:** As the orchestrator, I want to update quantum.json atomically so that concurrent agent completions don't corrupt the file.

**Acceptance Criteria:**
- [ ] All writes go to `quantum.json.tmp` first, then `mv quantum.json.tmp quantum.json`
- [ ] If `quantum.json.tmp` exists on startup, it is deleted (incomplete previous write)
- [ ] The `execution` field is added to quantum.json with `mode`, `maxParallel`, `currentWave`, and `activeWorktrees`
- [ ] `activeWorktrees` array is updated as worktrees are created and removed
- [ ] Story-level `worktree` field is set on spawn and cleared on merge/failure

### US-006: Handle agent timeout and crash
**Description:** As the orchestrator, I want to kill agents that hang or crash and retry their stories, so that one stuck agent doesn't block the entire execution.

**Acceptance Criteria:**
- [ ] Default per-story timeout is 15 minutes
- [ ] If no signal received within timeout: kill process/task, mark story `"failed"` with `"phase": "timeout"`, clean up worktree
- [ ] If agent exits with non-zero code and no signal: mark story `"failed"` with `"phase": "crash"`, clean up worktree
- [ ] Failed stories with remaining retries are eligible for the next DAG query cycle
- [ ] Other running agents are unaffected by one agent's timeout or crash

### US-007: Crash recovery for orphaned worktrees
**Description:** As the orchestrator, I want to detect and clean up orphaned worktrees from a previously interrupted run, so that a crashed session doesn't leave the repo in a broken state.

**Acceptance Criteria:**
- [ ] On startup, read `execution.activeWorktrees` from quantum.json
- [ ] For each listed worktree that exists on disk: run `git worktree remove --force`
- [ ] Reset corresponding story status from `"in_progress"` to `"pending"`
- [ ] Clear `execution.activeWorktrees` array
- [ ] Log a warning: "Recovered N orphaned worktrees from interrupted parallel execution"

### US-008: Update CLAUDE.md for parallel-aware agents
**Description:** As a developer, I want the CLAUDE.md template to instruct agents not to write quantum.json when running in a worktree, so that only the orchestrator manages state.

**Acceptance Criteria:**
- [ ] CLAUDE.md contains a section: "If your working directory is a worktree (.ql-wt/), do NOT write quantum.json. Signal completion via stdout only."
- [ ] Agent behavior is unchanged when running in the repo root (sequential mode)
- [ ] The addition is a minor paragraph, not a separate template file

### US-009: Update /ql-execute skill for parallel orchestration
**Description:** As a user, I want `/ql-execute` to automatically detect independent stories and run them in parallel via background Task subagents, showing status lines as each completes.

**Acceptance Criteria:**
- [ ] Skill reads quantum.json and runs DAG query for executable stories
- [ ] If 2+ stories are executable: creates worktrees, spawns background Task subagents, monitors via TaskOutput polling
- [ ] If 1 story is executable: runs sequentially as before (no worktree)
- [ ] Status lines printed as events happen: `[SPAWNED]`, `[PASSED]`, `[FAILED]`
- [ ] After each completion: re-queries DAG and spawns newly unblocked stories
- [ ] Loop continues until COMPLETE or BLOCKED
- [ ] Backward compatible: quantum.json without `execution` field is handled gracefully

### US-010: Update quantum-loop.sh for parallel mode
**Description:** As a user, I want `quantum-loop.sh --parallel` to run stories in parallel via background bash processes, so that I can use parallel execution in autonomous overnight runs.

**Acceptance Criteria:**
- [ ] `--parallel` flag enables parallel mode
- [ ] Optional `--max-parallel N` flag caps concurrent agents
- [ ] Without `--parallel`, behavior is identical to current sequential mode
- [ ] Parallel mode: creates worktrees, spawns `claude --print` background processes, monitors via output polling
- [ ] Merge-on-pass with immediate DAG re-query
- [ ] Exit codes unchanged: 0 (COMPLETE), 1 (BLOCKED), 2 (MAX_ITERATIONS)
- [ ] Terminal output shows `[SPAWNED]`, `[PASSED]`, `[FAILED]` status lines with wave numbers

## 4. Functional Requirements

FR-1: The system shall query the dependency DAG to find all stories where all `dependsOn` stories have `status: "passed"`, the story's own status is `"pending"` or `"failed"` with `retries.attempts < retries.maxAttempts`, and status is not `"in_progress"`.

FR-2: The system shall create one git worktree per executable story at `.ql-wt/<story-id>/`, branched from the current HEAD of the feature branch.

FR-3: The system shall spawn one Claude Code agent per worktree, passing the story ID in the agent's prompt as a CLI argument.

FR-4: The system shall monitor all running agents and, upon receiving `<quantum>STORY_PASSED</quantum>`, immediately merge the worktree branch into the feature branch using `git merge` (bringing commits as-is).

FR-5: The system shall update quantum.json atomically by writing to `quantum.json.tmp` then renaming to `quantum.json`.

FR-6: Only the orchestrator shall write to quantum.json. Agents shall signal completion via stdout signals only.

FR-7: The system shall re-query the DAG after every agent completion (pass or fail) and spawn agents for any newly executable stories.

FR-8: The system shall kill agents that exceed the per-story timeout (default 15 minutes) and mark their stories as `"failed"` with `"phase": "timeout"`.

FR-9: The system shall detect orphaned worktrees on startup by checking `execution.activeWorktrees` and clean them up with `git worktree remove --force`.

FR-10: The system shall add `.ql-wt/`, `quantum.json.tmp`, and `quantum.json.lock` to `.gitignore`.

FR-11: The system shall support parallel execution in both interactive mode (via Task subagents) and autonomous mode (via bash background processes).

FR-12: The system shall maintain full backward compatibility -- without `--parallel` flag or with only one executable story, behavior is identical to current sequential mode.

## 5. Non-Goals (Out of Scope)

- **Cross-agent communication:** Agents cannot message each other during execution. They communicate only through merged code and quantum.json state.
- **Dynamic re-planning:** If a parallel agent discovers the task decomposition is wrong, it does NOT modify other stories. It fails its own story only.
- **Shared resource management:** No shared database connections, test servers, or port allocation between agents. Each worktree is fully independent.
- **Adaptive throttling:** No automatic adjustment of parallelism based on API rate limits or system resources in v1.
- **Agent output streaming:** Individual agent output is not streamed in real-time. Only summary status lines are shown.
- **Performance benchmarking:** No built-in measurement of parallel vs sequential wall-clock improvement.

## 6. Design Considerations

- Worktrees are lightweight git constructs (shared .git objects, separate working trees). Overhead is ~2-3 seconds per worktree creation/removal.
- The `.ql-wt/` directory should be at the project root, not nested inside `.git/`.
- Merge-on-pass means the feature branch advances incrementally. Later worktrees don't automatically get earlier merges -- they were branched from an earlier HEAD. This is by design: merge conflicts are caught at merge time and handled via retry.
- The orchestrator should print a summary table at the end showing per-story timing, wave assignment, and pass/fail status.

## 7. Technical Considerations

- **Git version:** `git worktree` requires git 2.5+. Most modern systems have this.
- **Bash version:** `wait -n` (for autonomous mode) requires bash 4.3+. Fallback to polling if unavailable.
- **Windows compatibility:** Git worktrees work on Windows via Git Bash. Path separators need testing.
- **Claude Code Task tool:** Background tasks via `run_in_background: true` return an output file path. Orchestrator polls this file for completion signals.
- **Atomic file operations:** `mv` is atomic on POSIX. On Windows, a rename operation serves the same purpose but has edge cases with open file handles.

## 8. Success Metrics

- Features with 3+ independent stories complete in less than 60% of sequential wall-clock time
- Zero data corruption in quantum.json across 50+ parallel execution runs
- Crash recovery successfully cleans up orphaned worktrees in 100% of interrupted runs
- Merge conflict retry succeeds on second attempt in 90%+ of cases
- Backward compatibility: sequential mode produces identical results with and without parallel code present

## 9. Open Questions

- Should the per-story timeout (15 min default) scale with the number of tasks in the story?
- Should we add a `--dry-run` flag that shows which stories would run in parallel without executing?
- Should the orchestrator log per-agent API token usage for cost visibility?
