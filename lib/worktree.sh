#!/usr/bin/env bash
# lib/worktree.sh -- Git worktree lifecycle functions for quantum-loop
# Source this file to use create_worktree(), remove_worktree(), list_worktrees()

# Source shared utilities
WORKTREE_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$WORKTREE_LIB_DIR/common.sh" || { printf "ERROR: common.sh not found\n" >&2; return 1 2>/dev/null || exit 1; }

# create_worktree(story_id, branch_name, repo_root)
# Creates a worktree at <repo_root>/.ql-wt/<story_id>/ branched from branch_name HEAD.
# On Windows with long paths (OneDrive, deep directories), falls back to a shorter
# temp-directory location if the default path exceeds 200 characters.
# Returns 0 on success, 1 on failure.
create_worktree() {
  local story_id="$1"
  local branch_name="$2"
  local repo_root="$3"

  if [[ -z "$story_id" || -z "$branch_name" || -z "$repo_root" ]]; then
    printf "ERROR: create_worktree requires story_id, branch_name, repo_root\n" >&2
    return 1
  fi
  _validate_story_id "$story_id" || return 1

  local wt_path="$repo_root/.ql-wt/$story_id"

  # Windows long-path guard: if the worktree path exceeds 200 chars, use a shorter location.
  # This prevents "fatal: '$GIT_DIR' too big" errors on Windows+OneDrive.
  if [[ ${#wt_path} -gt 200 ]]; then
    local short_base="${TMPDIR:-/tmp}/ql-wt"
    mkdir -p "$short_base"
    wt_path="$short_base/$story_id"
    printf "WARN: Default worktree path too long (%d chars), using %s\n" "${#wt_path}" "$wt_path" >&2
  fi

  # Ensure parent directory exists
  mkdir -p "$(dirname "$wt_path")"

  # Create worktree with a new branch for this story, based on the feature branch
  local wt_branch="ql-wt/${story_id}"
  git -C "$repo_root" worktree add -b "$wt_branch" "$wt_path" "$branch_name"
  return $?
}

# remove_worktree(story_id, repo_root)
# Removes the worktree at <repo_root>/.ql-wt/<story_id>/.
# Idempotent: returns 0 even if the worktree doesn't exist.
# On Windows, retries up to 3 times with a short delay to handle file locks
# (OneDrive sync, Python __pycache__, etc.).
remove_worktree() {
  local story_id="$1"
  local repo_root="$2"

  if [[ -z "$story_id" || -z "$repo_root" ]]; then
    printf "ERROR: remove_worktree requires story_id, repo_root\n" >&2
    return 1
  fi
  _validate_story_id "$story_id" || return 1

  local wt_path="$repo_root/.ql-wt/$story_id"

  # Also check the short-path fallback location (used when long paths are detected)
  local short_path="${TMPDIR:-/tmp}/ql-wt/$story_id"

  for path in "$wt_path" "$short_path"; do
    if [[ -d "$path" ]]; then
      # Retry loop for Windows file locks
      local attempt=0
      while [[ $attempt -lt 3 ]]; do
        git -C "$repo_root" worktree remove --force "$path" 2>/dev/null && break
        attempt=$((attempt + 1))
        if [[ $attempt -lt 3 ]]; then
          sleep 2
        fi
      done
      # Fallback: force-remove directory if git worktree remove failed
      rm -rf "$path" 2>/dev/null || true
    fi
  done

  # Clean up the worktree branch
  local wt_branch="ql-wt/${story_id}"
  git -C "$repo_root" branch -D "$wt_branch" 2>/dev/null || true

  # Prune stale worktree references
  git -C "$repo_root" worktree prune 2>/dev/null || true

  return 0
}

# list_worktrees(repo_root)
# Returns newline-separated list of active worktree story IDs (those under .ql-wt/).
list_worktrees() {
  local repo_root="$1"

  if [[ -z "$repo_root" ]]; then
    printf "ERROR: list_worktrees requires repo_root\n" >&2
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
