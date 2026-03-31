#!/usr/bin/env bash
# lib/resilience.sh -- WIP commits, squash-on-merge, and crash recovery for quantum-loop
# Supersedes lib/crash-recovery.sh (merged in hardening-v2)
#
# Provides: recover_orphaned_worktrees(), wip_commit(), get_completed_tasks(),
#           squash_and_merge(), detect_resumable_work()
# Requires: lib/common.sh, lib/json-atomic.sh
# Optional: lib/merge-strategy.sh (for classify_and_merge in squash_and_merge)

# shellcheck disable=SC1091,SC2034,SC2317  # SC1091: sourced files resolved at runtime; SC2034: MERGE_STRATEGY_AVAILABLE used in squash_and_merge; SC2317: exit 1 fallback reachable at source-time

# Source shared utilities
RESILIENCE_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$RESILIENCE_LIB_DIR/common.sh" || { printf "ERROR: common.sh not found\n" >&2; return 1 2>/dev/null || exit 1; }
source "$RESILIENCE_LIB_DIR/json-atomic.sh" || { printf "ERROR: json-atomic.sh not found\n" >&2; return 1 2>/dev/null || exit 1; }

# Graceful optional module loading for merge-strategy
MERGE_STRATEGY_AVAILABLE=true
source "$RESILIENCE_LIB_DIR/merge-strategy.sh" 2>/dev/null || MERGE_STRATEGY_AVAILABLE=false

# recover_orphaned_worktrees(json_path, repo_root)
# Detects and cleans up orphaned worktrees from a previously interrupted run.
# - Reads execution.activeWorktrees from quantum.json
# - For each listed worktree that exists on disk: removes it (git worktree remove
#   with rm -rf fallback for partially-created worktrees)
# - Resets corresponding story status from 'in_progress' to 'pending'
# - Clears worktree field from recovered stories
# - Clears execution.activeWorktrees array
# - Logs a warning with the count of recovered worktrees
# Returns 0 on success, 1 on failure.
recover_orphaned_worktrees() {
  local json_path="$1"
  local repo_root="$2"

  if [[ -z "$json_path" ]]; then
    printf "ERROR: recover_orphaned_worktrees requires json_path\n" >&2
    return 1
  fi

  if [[ -z "$repo_root" ]]; then
    printf "ERROR: recover_orphaned_worktrees requires repo_root\n" >&2
    return 1
  fi

  # Check if execution field exists
  local has_execution
  has_execution=$(jq 'has("execution")' "$json_path") || {
    printf "ERROR: Failed to read %s\n" "$json_path" >&2
    return 1
  }
  if [[ "$has_execution" != "true" ]]; then
    return 0
  fi

  # Get active worktrees count
  local worktree_count
  worktree_count=$(jq '.execution.activeWorktrees | length' "$json_path") || {
    printf "ERROR: Failed to query activeWorktrees\n" >&2
    return 1
  }
  if [[ ! "$worktree_count" =~ ^[0-9]+$ ]]; then
    printf "ERROR: Failed to query activeWorktrees count\n" >&2
    return 1
  fi
  if [[ "$worktree_count" -eq 0 ]]; then
    return 0
  fi

  local recovered_count=0
  local wt_rel_path wt_abs_path

  # Remove each worktree directory listed in activeWorktrees
  local i
  for i in $(seq 0 $((worktree_count - 1))); do
    wt_rel_path=$(jq -r --argjson idx "$i" '.execution.activeWorktrees[$idx]' "$json_path") || continue
    [[ -z "$wt_rel_path" || "$wt_rel_path" == "null" ]] && continue

    wt_abs_path="$repo_root/$wt_rel_path"
    if [[ -d "$wt_abs_path" ]]; then
      # Try git worktree remove first (proper cleanup), fall back to rm -rf
      # for partially-created worktrees that git may not recognize
      git -C "$repo_root" worktree remove --force "$wt_abs_path" 2>/dev/null \
        || rm -rf "$wt_abs_path"
      recovered_count=$((recovered_count + 1))
    fi
  done

  # Update quantum.json: for each in_progress story, check if its branch
  # was already merged before the crash (#6). If merged -> mark passed. If not -> pending.
  local merged_ids=""
  local story_ids_in_progress
  story_ids_in_progress=$(jq -r '.stories[] | select(.status == "in_progress") | .id' "$json_path" 2>/dev/null)
  for sid in $story_ids_in_progress; do
    local wt_branch="ql-wt/${sid}"
    if git -C "$repo_root" rev-parse --verify "$wt_branch" >/dev/null 2>&1 \
       && git -C "$repo_root" merge-base --is-ancestor "$wt_branch" HEAD 2>/dev/null; then
      printf "INFO: %s was already merged before crash — marking passed\n" "$sid"
      merged_ids="${merged_ids}${sid},"
    fi
  done

  local updated
  updated=$(jq --arg merged "$merged_ids" '
    (.stories[] | select(.status == "in_progress")) |=
      (. as $story |
      if ($merged | split(",") | map(select(. != "")) | index($story.id) | . != null) then
        (.status = "passed" | del(.worktree) | .startedAt = null)
      else
        (.status = "pending" | del(.worktree) | .startedAt = null)
      end) |
    .execution.activeWorktrees = []
  ' "$json_path") || {
    printf "ERROR: recover_orphaned_worktrees jq transform failed\n" >&2
    return 1
  }

  if [[ -z "$updated" ]]; then
    printf "ERROR: recover_orphaned_worktrees jq transform produced empty output\n" >&2
    return 1
  fi

  write_quantum_json "$json_path" "$updated" || return 1

  if [[ "$recovered_count" -gt 0 ]]; then
    printf "WARNING: Recovered %d orphaned worktrees from interrupted parallel execution\n" "$recovered_count"
  fi

  return 0
}

# wip_commit(worktree_path, story_id, task_id, task_title, start_time, end_time)
# Creates a WIP commit in the given worktree for progress tracking.
# - If files have changed: stages all and commits with WIP message
# - If no files changed but elapsed time >= 120s: creates an empty commit
# - If no files changed and elapsed < 120s: returns 1 (nothing to commit)
# Message format: 'wip: <story_id> <task_id> - <title>'
# Returns 0 on commit, 1 if nothing to commit.
wip_commit() {
  local worktree_path="$1"
  local story_id="$2"
  local task_id="$3"
  local task_title="$4"
  local start_time="$5"
  local end_time="$6"

  if [[ -z "$worktree_path" || -z "$story_id" || -z "$task_id" ]]; then
    printf "ERROR: wip_commit requires worktree_path, story_id, task_id\n" >&2
    return 1
  fi

  local commit_msg="wip: ${story_id} ${task_id} - ${task_title}"
  local has_changes=false

  # Check for file changes
  if git -C "$worktree_path" status --porcelain 2>/dev/null | grep -q .; then
    has_changes=true
  fi

  if [[ "$has_changes" == "true" ]]; then
    git -C "$worktree_path" add -A 2>/dev/null
    git -C "$worktree_path" commit -m "$commit_msg" -q 2>/dev/null
    printf "[RESILIENCE] WIP commit: %s (files changed)\n" "$commit_msg" >&2
    return 0
  fi

  # No changes -- check elapsed time
  local elapsed=0
  if [[ -n "$start_time" && -n "$end_time" ]]; then
    elapsed=$((end_time - start_time))
  fi

  if [[ "$elapsed" -ge 120 ]]; then
    git -C "$worktree_path" commit --allow-empty -m "$commit_msg" -q 2>/dev/null
    printf "[RESILIENCE] WIP commit: %s (empty, elapsed %ds >= 120s)\n" "$commit_msg" "$elapsed" >&2
    return 0
  fi

  printf "[RESILIENCE] WIP skip: %s (no changes, elapsed %ds < 120s)\n" "$commit_msg" "$elapsed" >&2
  return 1
}

# get_completed_tasks(worktree_path, story_id)
# Extracts task IDs from WIP commit messages for a given story.
# Scans git log for commits matching 'wip: <story_id> T-NNN' pattern.
# Prints newline-separated unique task IDs on stdout.
# Returns empty output if no WIP commits found.
get_completed_tasks() {
  local worktree_path="$1"
  local story_id="$2"

  if [[ -z "$worktree_path" || -z "$story_id" ]]; then
    printf "ERROR: get_completed_tasks requires worktree_path, story_id\n" >&2
    return 1
  fi

  # Get all commit subjects, grep for WIP pattern, extract task IDs, deduplicate
  git -C "$worktree_path" log --oneline --format=%s 2>/dev/null \
    | grep "^wip: ${story_id} T-[0-9]" \
    | sed "s/^wip: ${story_id} \(T-[0-9]*\).*/\1/" \
    | awk '!seen[$0]++' \
    || true
}

# squash_and_merge(worktree_branch, repo_root, story_id, story_title, json_path)
# Merges a worktree branch into the current branch.
# - For 1 commit: uses --no-ff merge (delegates to classify_and_merge if available)
# - For 2+ commits: uses squash merge with 'feat: <story_id> - <title>' message
# Stashes quantum.json changes before merge to avoid conflicts.
# Returns 0 on success, 1 on failure.
squash_and_merge() {
  local worktree_branch="$1"
  local repo_root="$2"
  local story_id="$3"
  local story_title="$4"
  local json_path="$5"

  if [[ -z "$worktree_branch" || -z "$repo_root" || -z "$story_id" ]]; then
    printf "ERROR: squash_and_merge requires worktree_branch, repo_root, story_id\n" >&2
    return 1
  fi

  # Count commits on the branch that are not on the current branch
  local commit_count
  commit_count=$(git -C "$repo_root" rev-list --count HEAD.."$worktree_branch" 2>/dev/null) || {
    printf "ERROR: squash_and_merge failed to count commits on %s\n" "$worktree_branch" >&2
    return 1
  }

  if [[ ! "$commit_count" =~ ^[0-9]+$ ]]; then
    printf "ERROR: squash_and_merge invalid commit count: %s\n" "$commit_count" >&2
    return 1
  fi

  printf "[RESILIENCE] squash_and_merge: %s has %d commit(s)\n" "$worktree_branch" "$commit_count" >&2

  if [[ "$commit_count" -eq 0 ]]; then
    printf "[RESILIENCE] squash_and_merge: nothing to merge from %s\n" "$worktree_branch" >&2
    return 0
  fi

  local merge_exit=0

  if [[ "$commit_count" -le 1 ]]; then
    # Single commit: delegate to classify_and_merge (manages its own stash/backup)
    if [[ "$MERGE_STRATEGY_AVAILABLE" == "true" ]] && [[ -n "$json_path" ]] && type classify_and_merge &>/dev/null; then
      classify_and_merge "$worktree_branch" "$repo_root" "$json_path"
      merge_exit=$?
    else
      git -C "$repo_root" merge --no-ff "$worktree_branch" -q 2>/dev/null
      merge_exit=$?
    fi
  else
    # Multiple commits: squash merge — handle stash/backup here (no delegation)
    local stashed=false
    local qj_backup=""
    if [[ -n "$json_path" ]] && [[ -f "$json_path" ]]; then
      cp "$json_path" "${json_path}.merge-bak" 2>/dev/null && qj_backup="${json_path}.merge-bak"
    fi
    if git -C "$repo_root" status --porcelain 2>/dev/null | grep -q .; then
      git -C "$repo_root" stash push -- ":(exclude)quantum.json" -m "ql-resilience-stash-${worktree_branch}" -q 2>/dev/null && stashed=true
      git -C "$repo_root" checkout -- quantum.json 2>/dev/null || true
    fi

    local safe_title
    safe_title=$(printf '%s' "$story_title" | tr -d '\000-\037')
    local squash_msg="feat: ${story_id} - ${safe_title}"
    git -C "$repo_root" merge --squash "$worktree_branch" -q 2>/dev/null
    merge_exit=$?
    if [[ "$merge_exit" -eq 0 ]]; then
      git -C "$repo_root" commit -m "$squash_msg" -q 2>/dev/null
      merge_exit=$?
      if [[ "$merge_exit" -ne 0 ]]; then
        git -C "$repo_root" reset HEAD -q 2>/dev/null || true
      fi
    fi

    # Restore quantum.json from backup and pop stash
    if [[ -n "$qj_backup" ]] && [[ -f "$qj_backup" ]]; then
      cp "$qj_backup" "$json_path" 2>/dev/null
      rm -f "$qj_backup"
    fi
    if [[ "$stashed" == "true" ]]; then
      git -C "$repo_root" stash pop -q 2>/dev/null || true
    fi
  fi

  if [[ "$merge_exit" -ne 0 ]]; then
    printf "[RESILIENCE] squash_and_merge: merge failed for %s (exit %d)\n" "$worktree_branch" "$merge_exit" >&2
    return 1
  fi

  printf "[RESILIENCE] squash_and_merge: successfully merged %s (%d commits)\n" "$worktree_branch" "$commit_count" >&2
  return 0
}

# detect_resumable_work(json_path, repo_root, story_id)
# Checks whether a story has an existing worktree with WIP commits that can be resumed.
# Prints one of:
#   "fresh"                             -- no resumable work found
#   "resumable:<sha>:<comma-tasks>"     -- found WIP commits, can resume
# Returns 0 always.
detect_resumable_work() {
  local json_path="$1"
  local repo_root="$2"
  local story_id="$3"

  if [[ -z "$json_path" || -z "$repo_root" || -z "$story_id" ]]; then
    printf "ERROR: detect_resumable_work requires json_path, repo_root, story_id\n" >&2
    return 1
  fi

  # Look for worktree directory: .ql-wt/<story_id>
  local wt_path="$repo_root/.ql-wt/${story_id}"

  if [[ ! -d "$wt_path" ]]; then
    printf "[RESILIENCE] detect_resumable_work: no worktree found at %s\n" "$wt_path" >&2
    printf "fresh"
    return 0
  fi

  # Get completed tasks from WIP commits in the worktree
  local completed_tasks
  completed_tasks=$(get_completed_tasks "$wt_path" "$story_id")

  if [[ -z "$completed_tasks" ]]; then
    printf "[RESILIENCE] detect_resumable_work: worktree exists but no WIP commits for %s\n" "$story_id" >&2
    printf "fresh"
    return 0
  fi

  # Get the SHA of the last WIP commit
  local last_sha
  last_sha=$(git -C "$wt_path" log -1 --format=%H 2>/dev/null) || {
    printf "[RESILIENCE] detect_resumable_work: failed to get SHA from worktree\n" >&2
    printf "fresh"
    return 0
  }

  # Convert newline-separated tasks to comma-separated
  local comma_tasks
  comma_tasks=$(printf "%s" "$completed_tasks" | tr '\n' ',' | sed 's/,$//')

  printf "[RESILIENCE] detect_resumable_work: found resumable work for %s (sha=%s, tasks=%s)\n" \
    "$story_id" "$last_sha" "$comma_tasks" >&2
  printf "resumable:%s:%s" "$last_sha" "$comma_tasks"
  return 0
}
