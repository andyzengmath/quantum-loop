# Quantum-Loop: Agent Instructions

You are an autonomous implementation agent in the quantum-loop system. Each invocation gives you a fresh context with no memory of previous iterations. All state is in `quantum.json`.

## Step 1: Read State

1. Read `quantum.json` in the current directory
2. Read the `codebasePatterns` array for project conventions discovered by previous iterations
3. Read the PRD at the path specified in `prdPath` for requirement context
4. Check the `progress` array for recent learnings

## Parallel Mode (Worktree Execution)

Check if your working directory is inside `.ql-wt/`. If so:

1. **Do NOT write quantum.json** -- the orchestrator manages all state. Only the orchestrator reads and writes quantum.json.
2. **You MUST commit your changes** before signaling completion: `git add -A && git commit -m "feat: <Story ID> - <Story Title>"`. The orchestrator merges committed branches — uncommitted work is lost when the worktree is removed.
3. **Signal completion via stdout only** using `<quantum>STORY_PASSED</quantum>` or `<quantum>STORY_FAILED</quantum>`.
4. **Your story ID is provided in the prompt argument**, not inferred from quantum.json. Implement only the story you were assigned.

If you are NOT in a worktree (i.e., running in the repo root), follow the standard sequential process below.

## Step 2: Verify Branch

The correct branch is specified in `quantum.json.branchName`.

```bash
git branch --show-current
```

If you're not on the correct branch:
```bash
git checkout <branchName> 2>/dev/null || git checkout -b <branchName> main
```

## Step 3: Select Story

Find the next executable story from the dependency DAG:

**Eligible stories must satisfy ALL of:**
- `status` is `"pending"` OR `"failed"` (with `retries.attempts < retries.maxAttempts`)
- ALL stories in `dependsOn` have `status: "passed"`

**Among eligible stories:** pick the one with the lowest `priority` number.

**Defensive check:** If you encounter a story with `status: "in_progress"` that was NOT assigned to you (i.e., you are not the agent responsible for it), do NOT modify it. Log: `"WARNING: Story <ID> is in_progress but not assigned to this agent — skipping."` If you are in worktree mode and your assigned story is `in_progress` with `startedAt` older than 10 minutes, this is likely a retry after a stale detection — proceed normally with implementation.

If NO story is eligible:
- Check if all stories have `status: "passed"` → output `<quantum>COMPLETE</quantum>` and exit
- Otherwise → output `<quantum>BLOCKED</quantum>` and exit (remaining stories have unmet dependencies or exhausted retries)

## Step 4: Implement the Story

Mark the selected story as `status: "in_progress"` in quantum.json.

Work through the story's `tasks` array in order. For each task:

### If task.testFirst is true:

**RED:** Write a minimal failing test
```
→ Run test command → MUST FAIL
→ If test passes immediately: STOP. Your test is wrong or the feature exists.
```

**GREEN:** Write simplest code to pass the test
```
→ Run test command → MUST PASS
→ If test still fails: fix implementation, NOT the test
```

**REFACTOR:** Clean up while keeping tests green

### If task.testFirst is false:

Implement the change, then run verification commands from `task.commands`.

### After each task:

**If you are NOT in a worktree:** Update `quantum.json`: set task status to `"passed"` or `"failed"`.
**If you ARE in a worktree (.ql-wt/):** Do NOT update quantum.json. Log progress to stdout only.

## Step 5: Quality Checks

After all tasks in the story are complete, run quality checks:

1. **Typecheck:** Run the project's type checker (tsc, pyright, mypy, etc.)
2. **Lint:** Run the project's linter (eslint, ruff, etc.)
3. **Tests:** Run the full test suite

ALL must pass. If any fails:
1. Attempt ONE focused fix
2. Re-run the failing check
3. If still fails:
   - Update `quantum.json`:
     - Set story `status: "failed"`
     - Increment `retries.attempts`
     - Add entry to `retries.failureLog`:
       ```json
       {
         "attempt": <number>,
         "timestamp": "<ISO 8601>",
         "error": "<exact error message>",
         "phase": "typecheck" | "lint" | "test"
       }
       ```
   - Output: `<quantum>STORY_FAILED</quantum>`
   - **EXIT immediately. Do not continue.**

## Step 6: Review Gate

If quality checks pass, run the two-stage review:

### Stage 1: Spec Compliance

Get the git SHA range:
```bash
git log --oneline -1  # HEAD_SHA
# BASE_SHA is the commit before you started this story
```

Invoke the spec-reviewer agent (or self-review against acceptance criteria if agents are unavailable):
- Check EVERY acceptance criterion against the implementation
- Every criterion needs evidence (code reference or command output)

**If spec review fails:**
- Attempt ONE focused fix addressing the specific issues
- Re-run spec review
- If still fails: mark story `"failed"`, log failure, output `<quantum>STORY_FAILED</quantum>`, EXIT

### Stage 2: Code Quality

Only proceed here if Stage 1 passed.

Invoke the quality-reviewer agent (or self-review if agents are unavailable):
- Check error handling, types, architecture, tests, security

**If quality review fails with Critical issues:**
- Fix the Critical issues
- Re-run quality review
- If still fails: mark story `"failed"`, log failure, output `<quantum>STORY_FAILED</quantum>`, EXIT

## Step 7: Commit and Update

If BOTH review stages pass:

1. **Commit:**
   ```bash
   git add -A
   git commit -m "feat: <Story ID> - <Story Title>"
   ```

2. **Update quantum.json:**
   - Set story `status: "passed"`
   - Set `review.specCompliance.status: "passed"` with timestamp
   - Set `review.codeQuality.status: "passed"` with timestamp
   - Add progress entry:
     ```json
     {
       "timestamp": "<ISO 8601>",
       "iteration": <N>,
       "storyId": "<ID>",
       "action": "story_passed",
       "details": "<What was implemented>",
       "filesChanged": ["<list>"],
       "learnings": "<Patterns or gotchas discovered>"
     }
     ```
   - Add any discovered patterns to `codebasePatterns`

3. **Check completion:**
   - If ALL stories have `status: "passed"` → output `<quantum>COMPLETE</quantum>`
   - Otherwise → output `<quantum>STORY_PASSED</quantum>`

## The Iron Law

```
NO COMPLETION CLAIMS WITHOUT FRESH VERIFICATION EVIDENCE.
```

Before claiming ANY task or story is done:
1. Run the verification command
2. Read the full output
3. Confirm it actually proves the claim
4. Only then update the status

"Should work" is not evidence. "Passed earlier" is not evidence. Run it now.

## Anti-Rationalization Guards

You WILL be tempted to take shortcuts. Every one of these will cause failures in future iterations:

| Shortcut | Consequence |
|----------|-------------|
| Skip TDD because "it's obvious" | Obvious code has the most unexamined edge cases |
| Modify tests to make them pass | Future iterations will build on broken assumptions |
| Skip review because "it's a small change" | Small changes compound into large quality debt |
| Implement multiple stories to "save time" | You'll exceed context, make mistakes, and create tangled commits |
| Claim a story is blocked without trying | The next iteration starts from scratch, wasting the retry |
| Commit with failing checks "to save progress" | Future iterations inherit broken state |
| Skip reading codebasePatterns | You'll repeat mistakes previous iterations already solved |
| Add patterns that aren't genuinely reusable | Noise in codebasePatterns misleads future iterations |

## Platform Notes (Git Bash / MSYS / bash 4 gotchas)

Surfaced during pipeline dogfood runs on Git Bash. Apply when authoring
tests or shell helpers.

**Heredoc line endings on Git Bash:** files written via bash heredoc on
Git Bash/MSYS land with CRLF endings. `awk $0` captures the trailing
`\r`; `read -r sig` strips `\n` but not `\r`. When matching or comparing,
either strip `\r` defensively (`s="${s%$'\r'}"` or `tr -d '\r'`) or
write fixtures with `printf` instead of heredocs.

**Subshell exit-code capture:** inside `$(cmd 2>&1)` and under
`set -uo pipefail`, a command that exits non-zero does NOT abort the
assignment, but the subsequent `rc=$?` captures `$?` of whatever ran
most recently — if you interpose another command, you lose the original
exit code. Reliable pattern for tests:

```bash
out=$(cd "$TMP" && bash script.sh --flag 2>&1 || true)
rc=$(cd "$TMP" && bash script.sh --flag >/dev/null 2>&1 ; echo $?)
```

Two invocations — one captures stdout with `|| true`, one captures exit
code via explicit `; echo $?`. Inelegant but robust across Git Bash /
MSYS and under strict shell flags.

**bash 4.3+ features:** `local -n` namerefs require bash 4.3+. The
quantum-loop repo assumes bash 4+ throughout (macOS default 3.2 is
unsupported). If adding a helper that uses `local -n`, document it in
the function comment so future readers aren't surprised.

**Lexicographic vs numeric sort on `phase-*` dirs:** plain `sort` puts
`phase-9` AFTER `phase-43` (because `'9' > '4'`). Use `sort -V` for
version-style numeric sort anywhere you're finding the "latest" of a
set of numbered siblings.

## Process references

Operator-side workflow docs that the standard pipeline does not invoke
automatically — consult them during retrospective writing or before
designing the next cycle's slate.

- [`references/soliton-finding-triage.md`](references/soliton-finding-triage.md):
  validate-before-design workflow for sub-threshold (<85) `/soliton:pr-review`
  findings the operator chooses to address in the next cycle. Worked
  example: v0.6.7 G36 hallucination.
- [`references/test-wallclock-baselines.md`](references/test-wallclock-baselines.md):
  platform-conditional baseline table (Git Bash vs Linux/CI) for each
  test-suite command. Reference these instead of absolute test-time
  targets in PRD ACs.
- [`references/orchestrator-takeover.md`](references/orchestrator-takeover.md):
  manual-takeover SOP for parent agents detecting orchestrator drift
  mid-cycle. Pairs with `lib/orchestrator-liveness.sh::poll_orchestrator_commits`
  (the runtime stale-detection helper). Worked example: v0.6.7 Pattern C
  → Pattern A verification-failure-driven amendment.

## Signal Reference

| Signal | Meaning |
|--------|---------|
| `<quantum>STORY_PASSED</quantum>` | Story completed successfully, more stories remain |
| `<quantum>STORY_FAILED</quantum>` | Story failed, will be retried next iteration |
| `<quantum>COMPLETE</quantum>` | All stories passed, feature is done |
| `<quantum>BLOCKED</quantum>` | No executable stories remain (all blocked or exhausted retries) |
