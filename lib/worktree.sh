#!/usr/bin/env bash
# lib/worktree.sh -- Git worktree lifecycle functions for quantum-loop
# Source this file to use create_worktree(), remove_worktree(), list_worktrees()

# _validate_story_id(story_id)
# Returns 0 if story_id matches safe pattern, 1 otherwise.
_validate_story_id() {
  local story_id="$1"
  if [[ ! "$story_id" =~ ^[A-Za-z0-9_-]+$ ]]; then
    echo "ERROR: Invalid story_id format: $story_id" >&2
    return 1
  fi
  return 0
}

# create_worktree(story_id, branch_name, repo_root)
# Creates a worktree at <repo_root>/.ql-wt/<story_id>/ branched from branch_name HEAD.
# Returns 0 on success, 1 on failure.
create_worktree() {
  local story_id="$1"
  local branch_name="$2"
  local repo_root="$3"

  if [[ -z "$story_id" || -z "$branch_name" || -z "$repo_root" ]]; then
    echo "ERROR: create_worktree requires story_id, branch_name, repo_root" >&2
    return 1
  fi
  _validate_story_id "$story_id" || return 1

  local wt_path="$repo_root/.ql-wt/$story_id"

  # Ensure .ql-wt directory exists
  mkdir -p "$repo_root/.ql-wt"

  # Create worktree with a new branch for this story, based on the feature branch
  local wt_branch="ql-wt/${story_id}"
  git -C "$repo_root" worktree add -b "$wt_branch" "$wt_path" "$branch_name"
  return $?
}

# remove_worktree(story_id, repo_root)
# Removes the worktree at <repo_root>/.ql-wt/<story_id>/.
# Idempotent: returns 0 even if the worktree doesn't exist.
remove_worktree() {
  local story_id="$1"
  local repo_root="$2"

  if [[ -z "$story_id" || -z "$repo_root" ]]; then
    echo "ERROR: remove_worktree requires story_id, repo_root" >&2
    return 1
  fi
  _validate_story_id "$story_id" || return 1

  local wt_path="$repo_root/.ql-wt/$story_id"

  if [[ -d "$wt_path" ]]; then
    git -C "$repo_root" worktree remove --force "$wt_path" 2>/dev/null || true
  fi

  # Clean up the worktree branch
  local wt_branch="ql-wt/${story_id}"
  git -C "$repo_root" branch -D "$wt_branch" 2>/dev/null || true

  # Remove directory if still present (edge case)
  rm -rf "$wt_path" 2>/dev/null || true

  return 0
}

# list_worktrees(repo_root)
# Returns newline-separated list of active worktree story IDs (those under .ql-wt/).
list_worktrees() {
  local repo_root="$1"

  if [[ -z "$repo_root" ]]; then
    echo "ERROR: list_worktrees requires repo_root" >&2
    return 1
  fi

  local wt_dir="$repo_root/.ql-wt"
  if [[ ! -d "$wt_dir" ]]; then
    return 0
  fi

  # List directories under .ql-wt/ that are actual git worktrees
  for dir in "$wt_dir"/*/; do
    if [[ -d "$dir" ]]; then
      basename "$dir"
    fi
  done
}
