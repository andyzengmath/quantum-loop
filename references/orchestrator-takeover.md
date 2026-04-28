# Orchestrator manual-takeover SOP

**Audience:** parent agents (or human operators) detecting that the `quantum-loop:orchestrator` subagent has stalled mid-cycle.

**Why this exists:** v0.6.7 + v0.6.8 both saw the orchestrator subagent abandon its execution mid-cycle (LLM context-drift — agent edits a file, sets the story to `in_progress`, then stops committing). The recovery in both cycles was manual — a parent agent detecting drift via `git log` + `jq status` checks and continuing the cycle's stories from the orchestrator's working state. v0.6.9 introduces a runtime liveness helper (`lib/orchestrator-liveness.sh::poll_orchestrator_commits`) that emits a `[LIVENESS] STALE` signal — but the helper itself does NOT take over. This SOP is the parent-side recovery procedure that pairs with the STALE signal.

## When to detect drift

Symptoms (any one is sufficient to trigger this SOP):

1. **Liveness helper STALE signal** — `lib/orchestrator-liveness.sh::poll_orchestrator_commits` returns 1 with a `[LIVENESS] STALE: no commits in Ns` log line.
2. **Orchestrator output references "later stories" or "background work"** while the current `in_progress` story has no commit. Example phrasing seen in v0.6.7 dogfood: *"While that runs, let me proactively work on later stories that don't depend on US-001's verification..."* — exactly the forbidden idiom v0.6.8 N6 tried to advise against.
3. **Story status field stuck** at `in_progress` for >10 min with no `feat: <Story ID>` commit landing.
4. **Working tree has uncommitted edits** that match the in-progress story's task list, but the orchestrator has stopped reasoning.

These signals are independent — observe ANY ONE, run the verification step before assuming the orchestrator has stalled.

## What to verify before taking over

Run these three commands in order. The output establishes ground truth before any parent-side mutation:

1. **`git log <BASE_SHA>..HEAD --oneline`** where `BASE_SHA` is the parent commit before this bundle. The output should show one `feat: <Story ID> - <Title>` commit per passed story. If the most recent commit's Story ID is older than the `in_progress` story in `quantum.json`, the orchestrator stopped before committing.

2. **`jq -r '.stories[] | select(.status=="in_progress") | "\(.id) \(.title)"' quantum.json`** — identifies the current in-progress story. If multiple stories are in_progress (should not happen in sequential mode), that's a state-corruption signal — investigate before continuing.

3. **`git status --short` and `git diff --stat`** — what has the orchestrator changed but not committed? The diff should show exactly the file paths from the in-progress story's `tasks[].filePaths` arrays. If extra files appear, the orchestrator may have started multiple stories — investigate before committing.

## How to take over without corrupting state

The general rule: **preserve the orchestrator's existing in-progress edits unless a verification check (test failure, lint failure, audit assertion) proves them broken.**

The v0.6.7 manual takeover amended the Test 4 wrapper from Pattern C (`set +e` block) to Pattern A (two-invocation idiom with `|| true`) because Pattern C tripped `tests/test_test_helpers.sh`'s corpus baseline cleanliness check — that's a **verification-failure-driven amendment**, which IS allowed. Other in-progress edits (e.g., partial test additions, comment changes the orchestrator started) should be preserved as-is and continued.

Pattern: **amend only when an existing assertion or quality gate proves the orchestrator's edit broke something.** Continue from the working state otherwise.

Concrete recovery steps:

1. **Verify the orchestrator's existing edits run cleanly**: run the test commands listed in the in-progress story's `tasks[].commands` arrays. If they pass, the orchestrator's edits are correct — proceed to step 2.
2. **Complete remaining tasks**: read the in-progress story's `tasks[]` array; identify the first task that is still `pending` (status field). Implement it as the orchestrator would have.
3. **Commit normally**: `git add <files> && git commit -m "feat: <Story ID> - <Title>"`. The commit message must match the orchestrator's expected format so any downstream consumer (changelog generator, retrospective tooling) sees a uniform history.
4. **Update quantum.json AT THE END of the story** (not mid-flight): set the story's `status` to `"passed"`, set each task's `status` to `"passed"`, set `review.specCompliance.status` and `review.codeQuality.status` to `"passed"` with timestamps, append a `progress[]` entry. Use `jq` for atomic edits.
5. **Continue to the next story** by re-running the DAG eligibility query (`jq` on `dependsOn` and `status`). Repeat steps 1-4 until all stories pass.
6. **Do not re-spawn the orchestrator** mid-cycle — the existing quantum.json state may not be cleanly resumable from a fresh agent context. Continue manually until US-007 (or the cycle's retrospective story) ships.

## Recovery from N6-followup STALE signal

When the v0.6.9 `lib/orchestrator-liveness.sh::poll_orchestrator_commits` helper returns 1 (stale) — the parent AGENT (LLM) reads this doc to drive recovery. The helper itself emits stderr only and has no awareness of this SOP.

Concrete flow when liveness is wrapped around the orchestrator:

```bash
source lib/orchestrator-liveness.sh
if poll_orchestrator_commits 600 60; then
  echo "Orchestrator alive — continuing"
else
  # STALE signal — parent agent reads this doc and follows §"How to take over"
  cat references/orchestrator-takeover.md
  # ... parent then runs §"What to verify" + §"How to take over" steps
fi
```

The 0-retry first-attempt-PASS record across v0.6.5..v0.6.8 was preserved under manual takeover for v0.6.7 + v0.6.8 — this SOP makes that pattern reproducible for future cycles.
