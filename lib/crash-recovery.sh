#!/usr/bin/env bash
# lib/crash-recovery.sh -- Orphaned worktree recovery for quantum-loop
#
# Provides: recover_orphaned_worktrees()
# Requires: lib/json-atomic.sh (for write_quantum_json)

# Source shared utilities
CRASH_RECOVERY_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$CRASH_RECOVERY_LIB_DIR/common.sh" || { printf "ERROR: common.sh not found\n" >&2; return 1 2>/dev/null || exit 1; }
source "$CRASH_RECOVERY_LIB_DIR/json-atomic.sh" || { printf "ERROR: json-atomic.sh not found\n" >&2; return 1 2>/dev/null || exit 1; }

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
  # was already merged before the crash (#6). If merged → mark passed. If not → pending.
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
      if ($merged | split(",") | map(select(. != "")) | index(.id) | . != null) then
        (.status = "passed" | del(.worktree))
      else
        (.status = "pending" | del(.worktree))
      end |
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
