# Module: quantum.json Fields — Init-Guard and Resilience

**Activation:** reference documentation; consulted when reading/writing the relevant `execution.*` substructures.

The init-guard and resilience modules introduce the following fields in quantum.json under `execution`:

## execution.initGuard

Populated by `run_preflight()` from `lib/init-guard.sh`. Records the results of environment pre-flight checks:

```json
{
  "execution": {
    "initGuard": {
      "ranAt": "<ISO 8601>",
      "warnings": ["<warning message 1>", "<warning message 2>"],
      "shortPathBase": "<short path base for worktrees on Windows>",
      "prunedWorktrees": 0,
      "cleanedOrphans": 0,
      "forceSequential": false
    }
  }
}
```

| Field | Type | Description |
|-------|------|-------------|
| `ranAt` | string (ISO 8601) | Timestamp of the last successful pre-flight run. Used for idempotency: if within 1 hour, `run_preflight` skips re-running. |
| `warnings` | string[] | Non-fatal warnings from pre-flight checks (e.g., low disk space, old git version). Empty array if no warnings. |
| `shortPathBase` | string | On Windows, the 8.3 short path base used for worktree creation to avoid MAX_PATH issues. Null on non-Windows systems. |
| `prunedWorktrees` | number | Count of stale git worktrees pruned during pre-flight cleanup. |
| `cleanedOrphans` | number | Count of orphaned worktree directories cleaned up during pre-flight. |
| `forceSequential` | boolean | When `true`, forces the orchestrator to use sequential execution even when 2+ stories are eligible. Set by `run_preflight` when the environment cannot support parallel worktrees, or manually by the user. |

## execution.resilience

Populated by `detect_resumable_work()` and `squash_and_merge()` from `lib/resilience.sh`. Tracks WIP commit recovery and merge operations:

```json
{
  "execution": {
    "resilience": {
      "wipCommits": {
        "<story_id>": {
          "detectedAt": "<ISO 8601>",
          "completedTasks": ["T-001", "T-002"],
          "branchRef": "<branch name>",
          "resumedAt": "<ISO 8601 or null>"
        }
      },
      "squashMerges": {
        "<story_id>": {
          "mergedAt": "<ISO 8601>",
          "commitsSquashed": 3,
          "quantumJsonExcluded": true
        }
      }
    }
  }
}
```

| Field | Type | Description |
|-------|------|-------------|
| `wipCommits.<story_id>.detectedAt` | string (ISO 8601) | When WIP commits were detected for a stale story. |
| `wipCommits.<story_id>.completedTasks` | string[] | Task IDs that were completed before the story went stale, as determined from WIP commit analysis. |
| `wipCommits.<story_id>.branchRef` | string | The worktree branch containing the WIP commits. |
| `wipCommits.<story_id>.resumedAt` | string or null | When the story was re-spawned with resumed task context. Null if not yet resumed. |
| `squashMerges.<story_id>.mergedAt` | string (ISO 8601) | When the squash merge was performed. |
| `squashMerges.<story_id>.commitsSquashed` | number | Number of individual commits squashed into the merge commit. |
| `squashMerges.<story_id>.quantumJsonExcluded` | boolean | Whether quantum.json was automatically excluded from the merge (should always be `true` when using `squash_and_merge`). |
