---
name: ql-execute
description: Run the autonomous execution loop. Processes stories from the dependency DAG with TDD enforcement, two-stage review gates, and structured error recovery. Supports parallel execution via DAG-driven worktree agents. Use after /quantum-loop:plan has created quantum.json. Triggers on: execute, run loop, start building, ql-execute.
---

# Quantum-Loop: Execute

You are orchestrating the autonomous execution loop. This skill drives the end-to-end implementation of all stories in quantum.json, enforcing verification, TDD, and review at every step. When multiple independent stories are executable, they run in parallel via isolated worktrees.

## Prerequisites

Before starting:
1. `quantum.json` must exist (created by `/quantum-loop:plan`)
2. The project must be a git repository
3. Project build tools must be available (npm, pip, cargo, etc.)

If prerequisites are not met, inform the user and stop.

## Execution Modes

### Mode 1: Sequential (1 story executable)
Run stories one at a time within the current Claude Code session.
Best for: debugging, small features (1-3 stories), learning the system.

### Mode 2: Parallel (2+ stories executable)
Spawn background Task subagents, one per story, each in an isolated worktree.
Best for: large features with independent stories, maximizing throughput.

### Mode 3: Autonomous CLI (via quantum-loop.sh)
Run the bash loop that spawns fresh Claude Code instances per story.
Best for: overnight runs, maximum autonomy.

To launch autonomous mode:
```bash
./quantum-loop.sh --max-iterations 20 --max-retries 3
# Add --parallel for parallel execution:
./quantum-loop.sh --parallel --max-parallel 4
```

## Step 1: Read State and Recover

```
1. Read quantum.json
2. Read codebasePatterns for conventions from previous iterations
3. Read PRD at prdPath for requirement context
4. Check progress array for recent learnings
5. If execution.activeWorktrees is non-empty:
   → Run crash recovery (source lib/crash-recovery.sh, call recover_orphaned_worktrees)
   → Log recovered count
6. Clean up stale quantum.json.tmp if present
7. Verify dependency DAG has no cycles (source lib/dag-query.sh, call detect_cycles)
8. Count: pending, failed (retriable), passed, blocked
9. Report summary to user
```

## Step 2: Query DAG for Executable Stories

Apply the DAG selection algorithm:

```
EXECUTABLE = stories WHERE:
  (status == "pending" OR (status == "failed" AND retries.attempts < retries.maxAttempts))
  AND all(dependsOn[*].status == "passed")
  AND status != "in_progress"

IF no EXECUTABLE:
  IF all stories passed → output COMPLETE, print summary table, stop
  ELSE → output BLOCKED (report which stories are stuck and why), stop
```

If **1 story** is executable → proceed to Sequential Workflow (Step 3A)
If **2+ stories** are executable → proceed to Parallel Workflow (Step 3B)

## Step 3A: Sequential Workflow (Single Story)

This is the existing workflow, used when only one story is eligible.

### Present the selected story:
```
Next story: US-002 - Display priority indicator on task cards
Dependencies: US-001 (passed)
Tasks: 3 (T-004, T-005, T-006)
Attempt: 1 of 3
Mode: Sequential
```

### Implement Story Tasks

For each task in order:

**Pre-task:**
- Mark task `in_progress` in quantum.json
- Show task details to user

**Implementation (follows implementer agent protocol):**
- If `testFirst: true`: RED → GREEN → REFACTOR
- If `testFirst: false`: implement → verify

**Post-task:**
- Run verification commands from `task.commands`
- Apply Iron Law: fresh evidence required
- Mark task `passed` or `failed`
- If `failed`: stop implementation, proceed to error handling

### Quality Checks → Review Gate → Commit

Same as Steps 4-6 below. After commit, return to Step 2.

## Step 3B: Parallel Workflow (Multiple Stories)

When 2+ independent stories are executable, run them simultaneously.

### Wave Setup

```
1. Determine the executable stories (sorted by priority)
2. Set up execution metadata:
   - source lib/json-atomic.sh
   - call update_execution_field(quantum.json, "parallel", maxParallel, waveNumber)
3. For each executable story (up to maxParallel):
   a. Create worktree:
      source lib/worktree.sh
      create_worktree(story_id, branch_name, repo_root)
   b. Track worktree in quantum.json:
      set_story_worktree(quantum.json, story_id, worktree_path)
   c. Mark story status "in_progress"
   d. Spawn background Task subagent:
      Use Task tool with run_in_background: true
      Prompt: build_agent_prompt(story_id) from lib/spawn.sh
      subagent_type: "quantum-loop:implementer"
   e. Print: [SPAWNED] US-XXX - Story Title (wave N)
   f. Record agent handle (task_id) and start time
```

### Monitoring Loop

```
WHILE any agents are running:
  1. Poll each agent:
     - Use TaskOutput with block: false, timeout: 5000
     - Check for <quantum>STORY_PASSED</quantum> or <quantum>STORY_FAILED</quantum>
  2. Check timeouts:
     - If elapsed > DEFAULT_AGENT_TIMEOUT (900s): kill agent
     - Print: [TIMEOUT] US-XXX - Story Title
  3. For each completed agent:
     a. IF STORY_PASSED:
        - Merge worktree branch into feature branch (no squash, no rebase)
        - IF merge succeeds:
          → Mark story "passed" in quantum.json
          → Print: [PASSED] US-XXX - Story Title
        - IF merge conflict:
          → Mark story "failed" with phase "merge_conflict"
          → Print: [CONFLICT] US-XXX - Story Title
        - Remove worktree, clear_story_worktree()
     b. IF STORY_FAILED:
        - Mark story "failed", increment retries
        - Print: [FAILED] US-XXX - Story Title
        - Remove worktree, clear_story_worktree()
     c. IF CRASH (process exited, no signal):
        - Mark story "failed" with phase "crash"
        - Print: [CRASH] US-XXX - Story Title
        - Remove worktree, clear_story_worktree()
  4. After any completion: re-query DAG
     - If new stories are executable: spawn them immediately (new wave)
     - Print: [SPAWNED] US-YYY - New Story (wave N+1)
  5. Sleep 5 seconds between poll cycles
```

### After all agents complete:
Return to Step 2 (which will query the DAG again).

## Step 4: Quality Checks

After all tasks pass (sequential mode), run project quality checks:

1. **Typecheck** (tsc --noEmit, pyright, etc.)
2. **Lint** (eslint, ruff, etc.)
3. **Test suite** (npm test, pytest, etc.)

**If any check fails:**
- Attempt ONE focused fix
- Re-run the failing check
- If still fails:
  - Mark story `"failed"`
  - Log to `retries.failureLog`
  - Increment `retries.attempts`
  - Report failure to user
  - Return to Step 2 (select next story)

## Step 5: Two-Stage Review Gate

**Stage 1: Spec Compliance**
- Compare implementation against PRD acceptance criteria
- Every criterion must have evidence (code reference or test output)
- If ANY criterion unsatisfied → story fails review

**Stage 2: Code Quality** (only if Stage 1 passes)
- Check error handling, types, architecture, tests, security
- Categorize issues: Critical / Important / Minor
- Critical issues or 3+ Important issues → story fails review

**On review failure:**
- ONE attempt to fix the identified issues
- Re-run both review stages from scratch
- If second attempt fails → mark story `"failed"`, log, increment retries

## Step 6: Commit and Record

On success (all checks and reviews pass):

```bash
git add -A
git commit -m "feat: <Story ID> - <Story Title>"
```

Update quantum.json:
- Story `status: "passed"`
- Review statuses updated with timestamps
- Progress entry added (include `"parallel": true, "wave": N` for parallel stories)
- Codebase patterns updated (if new patterns discovered)

## Step 7: Continue or Complete

- If more eligible stories exist → return to Step 2
- If all stories `"passed"` → report COMPLETE with summary table
- If no eligible stories but some remain → report BLOCKED with details

## DAG Selection Algorithm (Reference)

```
Given stories S1..Sn with statuses and dependency edges:

1. Build adjacency list from dependsOn relationships
2. For each story:
   a. Skip if status is "passed" or "blocked"
   b. Skip if status is "failed" and attempts >= maxAttempts
   c. Skip if status is "in_progress"
   d. Skip if any dependency has status != "passed"
   e. Otherwise: add to eligible set
3. Sort eligible set by priority (ascending)
4. Return all eligible stories (not just first) for parallel spawning
```

**Cycle detection:** Before starting, verify the dependency graph is a DAG:
- Perform topological sort
- If sort fails (cycle detected): report the cycle and stop

## Error Recovery Protocol

### Task-level failure:
- Mark task as `"failed"` with detailed error
- Stop processing remaining tasks in the story
- Proceed to story-level error handling

### Story-level failure:
1. Increment `retries.attempts`
2. Log failure details to `retries.failureLog`
3. If `retries.attempts < retries.maxAttempts`:
   - Story remains eligible for future iterations
   - Next attempt starts fresh (re-read all tasks)
4. If `retries.attempts >= retries.maxAttempts`:
   - Set story `status: "blocked"`
   - Story will not be retried
   - Other stories that depend on this one become blocked

### Cascade blocking:
When a story is blocked, all stories that (directly or transitively) depend on it become ineligible. The system reports these as blocked with the root cause.

## Anti-Rationalization Guards

| Excuse | Reality |
|--------|---------|
| "Skip review for this story, it's simple" | Simple stories have the most unexamined assumptions. Review everything. |
| "Skip TDD for this task, it's just config" | Config errors are among the hardest to debug. Test what you can. |
| "The tests passed, so the feature works" | Tests might not cover the acceptance criteria. Verify each criterion. |
| "This review issue isn't worth fixing" | If it's Critical, fix it. If it's Important and there are 3+, fix them. No negotiation. |
| "Retry won't help, let me just skip this story" | Try the retry. A fresh context often succeeds where the previous one failed. |
| "Let me implement two stories at once to save time" | One story per agent. Always. Context contamination causes subtle bugs. |
| "The quality check warning isn't important" | Warnings become errors. Fix them now. |
| "I'll commit now and fix the review issues later" | "Later" means "never" in autonomous execution. Fix before committing. |
| "Sequential is fine, no need for parallel" | If 2+ stories are independent, parallel saves time. Use it. |

## Summary Table

At the end of execution (COMPLETE or BLOCKED), print a summary:

```
╔═══════════╤════════════════════════════════════════╤═════════╤══════╤══════════╗
║ Story     │ Title                                  │ Status  │ Wave │ Retries  ║
╠═══════════╪════════════════════════════════════════╪═════════╪══════╪══════════╣
║ US-001    │ DAG query returns executable stories   │ PASSED  │  1   │  0/3     ║
║ US-002    │ Create and clean up git worktrees      │ PASSED  │  1   │  0/3     ║
║ US-003    │ Spawn parallel agents                  │ PASSED  │  1   │  0/3     ║
║ US-004    │ Monitor agents and merge on pass       │ PASSED  │  2   │  0/3     ║
║ US-005    │ Atomic quantum.json updates            │ PASSED  │  1   │  0/3     ║
║ US-006    │ Handle agent timeout and crash         │ FAILED  │  2   │  2/3     ║
╚═══════════╧════════════════════════════════════════╧═════════╧══════╧══════════╝

Result: 5/6 stories passed (BLOCKED - US-006 exhausted retries)
```

## Progress Reporting

After each story (pass or fail), report:

```
=== Story US-002: Display priority indicator ===
Status:      PASSED
Attempt:     1 of 3
Tasks:       3/3 passed
Mode:        Parallel (wave 1)
Typecheck:   PASSED
Lint:        PASSED
Tests:       PASSED (47 total, 0 failed)
Spec Review: PASSED (5/5 criteria satisfied)
Quality:     PASSED (0 critical, 1 minor)
Commit:      feat: US-002 - Display priority indicator

Overall: 2/4 stories passed, 2 remaining
Next:    US-003 - Filter tasks by priority
```
