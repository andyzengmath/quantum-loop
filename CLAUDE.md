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
designing the next cycle's slate. Sub-categorized into Orchestrator-related,
Coordinator-related, Test-related, and Process-related.

### Orchestrator-related

- [`references/orchestrator-takeover.md`](references/orchestrator-takeover.md):
  manual-takeover SOP for parent agents detecting orchestrator drift
  mid-cycle. Pairs with `lib/orchestrator-liveness.sh::poll_orchestrator_commits`
  (the runtime stale-detection helper) and v0.7.0 N14's `/ql-execute`
  SKILL-level wrapping. Worked example: v0.6.7 Pattern C → Pattern A
  verification-failure-driven amendment.

### Coordinator-related

Operator-facing surface for the v0.9.x per-wave coordinator dispatch
(`quantum-loop.sh --coordinator`):

- **`QL_COORDINATOR_TIMEOUT_S`** (env var; default `1800` seconds = 30 min;
  v0.9.3 / US-001). Wallclock ceiling on the coordinator subagent's
  `bash -c "$COORD_CMD"` invocation in `lib/iteration-loop.sh:~212`
  (post-v0.9.5 decomposition; line 212 is the timeout-guarded dispatch,
  line 215 is the no-timeout fallback). On `timeout`
  rc=124 (SIGTERM kill from `timeout(1)` + 10s `--kill-after` grace), the
  parent prints `ERROR: Coordinator subagent exceeded ${N}s timeout` and
  forces `<quantum>WAVE_FAILED</quantum>` so per-story review-field
  aggregation runs. Override for long real-feature dispatches:
  `QL_COORDINATOR_TIMEOUT_S=3600 bash quantum-loop.sh --coordinator`.
  Closes v0.9.2 dogfood iter-3 hang.
- [`lib/coordinator-guard.sh`](lib/coordinator-guard.sh) (v0.9.2 / US-001).
  HEAD-snapshot guard: `guard_head_advance HEAD_BEFORE [HEAD_AFTER=HEAD]`
  uses `git merge-base --is-ancestor` to detect destructive `git reset
  --hard` by implementer subagents. Returns 1 with stderr `HEAD reset
  detected` on failure. The coordinator (per `agents/coordinator.md`
  step 2) MUST capture `HEAD_BEFORE=$(git rev-parse HEAD)` pre-dispatch
  and invoke `bash lib/coordinator-guard.sh guard_head_advance "$HEAD_BEFORE"`
  post-dispatch. Closes v0.9.1 finding 5a HIGH.
- [`lib/quantum-validate.sh`](lib/quantum-validate.sh) (v0.9.2 / US-003).
  Advisory hook: `validate_story_filepaths QUANTUM_JSON_PATH` warns to
  stderr for any eligible story (status pending|failed|in_progress)
  whose `tasks[].filePaths` is empty in aggregate. Wired into
  `lib/dag-query.sh::next_wave` preamble. Never blocks. Closes v0.9.1
  architect MEDIUM (silent `filter_file_conflicts` bypass).
- Coordinator-specific tests: `tests/test_coordinator_guard.sh`,
  `tests/test_quantum_validate.sh`, `tests/test_coordinator_e2e.sh`,
  `tests/test_coordinator_dispatch.sh`, `tests/test_next_wave.sh`.

### Test-related

- [`references/test-wallclock-baselines.md`](references/test-wallclock-baselines.md):
  platform-conditional baseline table (Git Bash vs Linux/CI) for each
  test-suite command. Reference these instead of absolute test-time
  targets in PRD ACs.

### Multi-runner test layers

Multi-runner tests are split into two complementary layers (v0.7.10 N35):

- **Smoke** (`tests/test_<runner>_runner_smoke.sh`) — version-probe health
  check. Verifies the binary is on PATH and the manifest schema loads.
  Cheap (<5s). Always green when the binary is installed correctly.
- **Dispatch** (`tests/test_<runner>_dispatch.sh`,
  `tests/test_runner_dispatch.sh`, `tests/test_multi_runner_dispatch_e2e.sh`) —
  real-task end-to-end. Loads the manifest, builds the invocation chain,
  evaluates a tiny prompt, asserts rc=0 + non-empty stdout. Catches manifest
  drift when the underlying CLI changes flags (worked example: v0.7.10
  caught the codex `-q` → `exec` subcommand migration). Skip-aware on
  missing binaries; ≤60s per runner.

The dispatch layer entry-point is `lib/runner.sh::runner_dispatch <name>
<prompt>` — composes `runner_load` + `runner_build_cmd` + `eval`.

### Process-related

- [`references/soliton-finding-triage.md`](references/soliton-finding-triage.md):
  validate-before-design workflow for sub-threshold (<85) `/soliton:pr-review`
  findings the operator chooses to address in the next cycle. Worked
  example: v0.6.7 G36 hallucination.
- [`references/severity-rubric-calibration-v0.7.4.md`](references/severity-rubric-calibration-v0.7.4.md):
  v0.7.4 third calibration pass of `references/finding-severity.md`
  against the 8-committed-cycle / 24-row CSV baseline. Empirical
  aggregate: 58 findings, 0/3/13/42 (critical/high/medium/low).
  Bundle-tier comparison: patch-tier HIGH 4.0% vs minor-tier HIGH
  12.5% (n=1, ratio worsens from v0.7.2). Documents the v0.7.2/v0.7.3
  CSV-commit gap. Plan-review MEDIUM still 0/12 across all cycles.
  Re-snapshot at v0.8.0+ via the companion parse-script.

### Process patterns (canonized v0.10.0 / US-004)

Two cycle-level process patterns with sustained empirical track records.
Promoted from `quantum.json.codebasePatterns` (per-cycle gitignored copy)
into permanent project documentation here so future cycles inherit them
without depending on quantum.json carryover.

- **p013 — Operator-staged cycle kickoff.** Operator pre-commits design
  doc + PRD + advisory hooks (pre-impl review CSV) on the cycle branch
  BEFORE the autonomous /loop fires. The autonomous loop then drives
  US-001 through US-N to first-attempt PASS. Empirical track record:
  **9 applications** (v0.9.0 → v0.9.6, v0.10.0, v0.10.1; updated v0.10.2).
  The 1 deviation
  (v0.9.6 first-attempt autonomous-kickoff at `5de3bbc`) was rolled
  back the same /loop tick once source-doc reading revealed scope
  errors — see `feedback_autonomous_kickoff_caution.md`. Pattern
  remains stable. Canonical retrospectives:
  `idea-stage/PIPELINE_REPORT_v28.md` (v0.9.1, first articulation),
  `idea-stage/PIPELINE_REPORT_v33.md` (v0.9.6 with the deviation
  + recovery footnote).
- **p014 — Composite review trio (pre-cycle architect-design + post-cycle
  3-reviewer trio).** Pre-cycle: 3 parallel architect spike agents on
  decomposable sub-problems (worked example: v0.10.0 design spike's 3
  architects scoping decomposition vs daemon-style vs parent-side
  guard). Post-cycle: 3 parallel reviewers (architect + code-reviewer +
  security) on the cycle diff with score-≥85 inline-fix gate.
  Empirical track record: **10 review applications** (post-v0.8.x:
  v0.8.1, v0.8.2, v0.8.3, v0.8.4, v0.9.1, v0.9.3, v0.9.4, v0.9.5,
  v0.9.6, v0.10.1; v0.9.2 SKIPPED with rationale because US-004 was
  the dogfood; updated v0.10.2). Pre-cycle architect-design count: 5 applications
  (v0.9.0 minor, v0.10.0 design spike, plus 3 mid-arc applications).
  Canonical retrospectives:
  `idea-stage/PIPELINE_REPORT_v28.md` (first formal application),
  `idea-stage/PIPELINE_REPORT_v33.md` (8th application + score-≥85
  inline-fix gate explicit).

- **p015 — Post-cycle 3-agent doc-vs-code audit.** Operator-initiated
  3-agent audit (architect + document-specialist + critic) of planning
  docs vs current code state, run after a cycle ships. Each agent has
  a focused scope (rolling-forward backlog claims; design/PRD line
  refs; PIPELINE_REPORT chain consistency). Findings synthesized into
  a doc-cleanup patch cycle. Empirical track record: **2 applications**
  (post-v0.10.0 closed 6 gaps in v0.10.1; post-v0.10.1 closed 3 gaps
  + p015 canonization in v0.10.2). Canonized v0.10.2 / US-002 after
  meeting the "applied a 2nd time" trigger condition flagged at
  `idea-stage/IDEA_REPORT_v35.md:78`. Canonical retrospectives:
  `idea-stage/PIPELINE_REPORT_v35.md` (1st application; 6 gaps),
  `idea-stage/PIPELINE_REPORT_v36.md` (2nd application; 3 gaps).
  False-positive filter is part of the pattern: each application has
  also produced 3-4 false-positive findings that the synthesizing
  step verifies-against-code and explicitly filters with rationale.

### Standing backlog (v0.10.4 / US-003)

Items that don't fit into per-cycle stories but should remain visible
to operators planning future cycles. Promoted from per-cycle deferred
stories when the deferral reason is structural rather than schedule-
based.

- **Real-feature dogfood (was v0.10.0 US-003 → v0.10.3 US-003).**
  Status: **blocked-on-operator-feature-queue.** Resume condition:
  operator queues a real feature for dispatch through `quantum-loop.sh
  --coordinator`. Anti-pattern: synthesizing fake features for dogfood
  adds ceremony without value — the system's housekeeping work is
  by-design low-risk and direct-commit-friendly; routing it through
  coordinator dispatch tests the dispatch path, not the housekeeping
  work. Architect recommendation post-v0.10.3 review (12th p014
  application). Tracked in `idea-stage/IDEA_REPORT_v37.md` § "Standing
  backlog (re-classified per architect recommendation)".

## Signal Reference

| Signal | Meaning |
|--------|---------|
| `<quantum>STORY_PASSED</quantum>` | Story completed successfully, more stories remain |
| `<quantum>STORY_FAILED</quantum>` | Story failed, will be retried next iteration |
| `<quantum>COMPLETE</quantum>` | All stories passed, feature is done |
| `<quantum>BLOCKED</quantum>` | No executable stories remain (all blocked or exhausted retries) |
| `<quantum>WAVE_PASSED</quantum>` | All stories in this wave passed (coordinator pattern, v0.8.0+; see `agents/coordinator.md`) |
| `<quantum>WAVE_FAILED</quantum>` | One or more stories in this wave failed (coordinator pattern, v0.8.0+; parent decides retry/abort) |
