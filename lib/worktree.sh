#!/usr/bin/env bash
# lib/worktree.sh -- Git worktree lifecycle functions for quantum-loop
# Source this file to use create_worktree(), remove_worktree(), list_worktrees()
# Requires: Git >= 2.20

# Source shared utilities
WORKTREE_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$WORKTREE_LIB_DIR/common.sh" || { printf "ERROR: common.sh not found\n" >&2; return 1 2>/dev/null || exit 1; }

# _resolve_repo_root(repo_root)
# Resolves a potentially-nested worktree path to the top-level repository root.
# Prevents worktree-inside-worktree nesting that causes exponential path growth.
# Falls back to the input path if resolution fails (e.g., not a git repo).
_resolve_repo_root() {
  local repo_root="$1"
  local real_root

  # Try --path-format=absolute first (Git >= 2.31), fall back without it (Git >= 2.20)
  real_root=$(git -C "$repo_root" rev-parse --path-format=absolute --git-common-dir 2>/dev/null \
              || git -C "$repo_root" rev-parse --git-common-dir 2>/dev/null)

  # Normalize relative path (git-common-dir may return relative like "../.git")
  if [[ -n "$real_root" && "$real_root" != /* ]]; then
    real_root="$(cd "$repo_root" && cd "$(dirname "$real_root")" && pwd)/$(basename "$real_root")"
  fi

  # Strip trailing /.git to get the repo root directory
  real_root=$(printf "%s" "$real_root" | sed 's|[/\\]\.git$||')

  if [[ -n "$real_root" && -d "$real_root" && "$real_root" != "$repo_root" ]]; then
    printf "%s" "$real_root"
  else
    printf "%s" "$repo_root"
  fi
}

# _short_path_base(repo_root)
# Returns the namespaced short-path fallback directory for this repo.
# Uses a hash of the repo root to prevent cross-repo collisions in /tmp.
_short_path_base() {
  local repo_root="$1"
  local repo_hash
  # Use md5sum if available, else cksum, else just the basename
  if command -v md5sum &>/dev/null; then
    repo_hash=$(printf "%s" "$repo_root" | md5sum | cut -c1-8)
  elif command -v cksum &>/dev/null; then
    repo_hash=$(printf "%s" "$repo_root" | cksum | cut -d' ' -f1)
  else
    repo_hash=$(basename "$repo_root")
  fi
  printf "%s/ql-wt-%s" "${TMPDIR:-/tmp}" "$repo_hash"
}

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

  # Resolve to top-level repo root to prevent worktree nesting
  repo_root=$(_resolve_repo_root "$repo_root")

  local wt_path="$repo_root/.ql-wt/$story_id"

  # Windows long-path guard: if the worktree path exceeds 200 chars, use a shorter location.
  # This prevents "fatal: '$GIT_DIR' too big" errors on Windows+OneDrive.
  local orig_len=${#wt_path}
  if [[ $orig_len -gt 200 ]]; then
    local short_base
    short_base=$(_short_path_base "$repo_root")
    mkdir -p "$short_base"
    wt_path="$short_base/$story_id"
    printf "WARN: Default worktree path too long (%d chars), using %s\n" "$orig_len" "$wt_path" >&2
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

  # Resolve to top-level repo root (same resolution as create_worktree)
  repo_root=$(_resolve_repo_root "$repo_root")

  local wt_path="$repo_root/.ql-wt/$story_id"

  # Also check the short-path fallback location (used when long paths are detected)
  local short_base
  short_base=$(_short_path_base "$repo_root")
  local short_path="$short_base/$story_id"

  for path in "$wt_path" "$short_path"; do
    if [[ -d "$path" ]]; then
      # Retry loop for Windows file locks
      local removed=false
      local attempt=0
      while [[ $attempt -lt 3 ]]; do
        git -C "$repo_root" worktree remove --force "$path" 2>/dev/null && { removed=true; break; }
        attempt=$((attempt + 1))
        if [[ $attempt -lt 3 ]]; then
          sleep 2
        fi
      done
      # Fallback: force-remove directory only if git worktree remove failed
      if [[ "$removed" != "true" && -d "$path" ]]; then
        rm -rf "$path" 2>/dev/null || true
      fi
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
# Returns newline-separated list of active worktree story IDs.
# Checks both the default location (.ql-wt/) and the repo-namespaced
# short-path fallback (/tmp/ql-wt-<hash>/).
list_worktrees() {
  local repo_root="$1"

  if [[ -z "$repo_root" ]]; then
    printf "ERROR: list_worktrees requires repo_root\n" >&2
    return 1
  fi

  # Resolve to top-level repo root (same resolution as create/remove)
  repo_root=$(_resolve_repo_root "$repo_root")

  local wt_dir="$repo_root/.ql-wt"
  local short_dir
  short_dir=$(_short_path_base "$repo_root")

  # List directories under both locations
  for search_dir in "$wt_dir" "$short_dir"; do
    if [[ -d "$search_dir" ]]; then
      for dir in "$search_dir"/*/; do
        if [[ -d "$dir" ]]; then
          basename "$dir"
        fi
      done
    fi
  done | sort -u  # Deduplicate in case a story appears in both locations
}
