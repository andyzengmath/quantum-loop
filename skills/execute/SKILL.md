---
name: ql-execute
description: "Run the autonomous execution loop. Processes stories from the dependency DAG with TDD enforcement, two-stage review gates, and structured error recovery. Use after /ql-plan has created quantum.json. Triggers on: execute, run loop, start building, ql-execute."
user-invocable: true
---

# Quantum-Loop: Execute

You are orchestrating the autonomous execution loop. This skill drives the end-to-end implementation of all stories in quantum.json, enforcing verification, TDD, and review at every step.

## Prerequisites

Before starting:
1. `quantum.json` must exist (created by `/ql-plan`)
2. The project must be a git repository
3. Project build tools must be available (npm, pip, cargo, etc.)

If prerequisites are not met, inform the user and stop.

## Execution Modes

### Mode 1: Interactive (within current session)
Run stories one at a time within the current Claude Code session.
Best for: debugging, small features (1-3 stories), learning the system.

### Mode 2: Autonomous (via quantum-loop.sh)
Run the bash loop that spawns fresh Claude Code instances per story.
Best for: large features (4+ stories), overnight runs, maximum autonomy.

To launch autonomous mode:
```bash
./quantum-loop.sh --max-iterations 20 --max-retries 3
```

## Interactive Mode Workflow

### Step 1: Read and Validate State

```
1. Read quantum.json
2. Verify all stories have valid status values
3. Verify dependency DAG has no cycles
4. Count: pending stories, failed (retriable), passed, blocked
5. Report summary to user
```

### Step 2: Select Next Story

Apply the DAG selection algorithm:

```
ELIGIBLE = stories WHERE:
  (status == "pending" OR (status == "failed" AND retries.attempts < retries.maxAttempts))
  AND all(dependsOn[*].status == "passed")

NEXT = ELIGIBLE sorted by priority ASC, take first

IF no ELIGIBLE:
  IF all stories passed → COMPLETE
  ELSE → BLOCKED (report which stories are stuck and why)
```

Present the selected story to the user:
```
Next story: US-002 - Display priority indicator on task cards
Dependencies: US-001 (passed)
Tasks: 3 (T-004, T-005, T-006)
Attempt: 1 of 3
```

### Step 3: Implement Story Tasks

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

### Step 4: Quality Checks

After all tasks pass, run project quality checks:

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

### Step 5: Two-Stage Review Gate

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

### Step 6: Commit and Record

On success (all checks and reviews pass):

```bash
git add -A
git commit -m "feat: <Story ID> - <Story Title>"
```

Update quantum.json:
- Story `status: "passed"`
- Review statuses updated with timestamps
- Progress entry added
- Codebase patterns updated (if new patterns discovered)

### Step 7: Continue or Complete

- If more eligible stories exist → return to Step 2
- If all stories `"passed"` → report COMPLETE
- If no eligible stories but some remain → report BLOCKED with details

## DAG Selection Algorithm (Reference)

```
Given stories S1..Sn with statuses and dependency edges:

1. Build adjacency list from dependsOn relationships
2. For each story:
   a. Skip if status is "passed" or "blocked"
   b. Skip if status is "failed" and attempts >= maxAttempts
   c. Skip if any dependency has status != "passed"
   d. Otherwise: add to eligible set
3. Sort eligible set by priority (ascending)
4. Return first element (or empty if no eligible stories)
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
| "Let me implement two stories at once to save time" | One story per pass. Always. Context contamination causes subtle bugs. |
| "The quality check warning isn't important" | Warnings become errors. Fix them now. |
| "I'll commit now and fix the review issues later" | "Later" means "never" in autonomous execution. Fix before committing. |

## Progress Reporting

After each story (pass or fail), report:

```
=== Story US-002: Display priority indicator ===
Status:      PASSED
Attempt:     1 of 3
Tasks:       3/3 passed
Typecheck:   PASSED
Lint:        PASSED
Tests:       PASSED (47 total, 0 failed)
Spec Review: PASSED (5/5 criteria satisfied)
Quality:     PASSED (0 critical, 1 minor)
Commit:      feat: US-002 - Display priority indicator

Overall: 2/4 stories passed, 2 remaining
Next:    US-003 - Filter tasks by priority
```
