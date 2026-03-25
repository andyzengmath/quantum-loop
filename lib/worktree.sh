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
    # Warn if the fallback path looks like it is inside a .ql-wt/ directory,
    # which would indicate we are inside a worktree but git resolution failed.
    if [[ "$repo_root" == */.ql-wt/* ]]; then
      printf "WARN: _resolve_repo_root: input path appears to be inside a worktree (%s). " \
          "$repo_root" >&2
      printf "Git resolution failed; cannot prevent nesting.\n" >&2
    fi
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
    local new_len=${#wt_path}
    printf "WARN: Default worktree path too long (%d chars), using %s (%d chars)\n" \
        "$orig_len" "$wt_path" "$new_len" >&2
    # Last resort: if even the short path is too long, use a bare /tmp path
    if [[ $new_len -gt 200 ]]; then
      wt_path="/tmp/ql-wt-$(printf "%s" "$story_id" | md5sum 2>/dev/null | cut -c1-6 || echo "$story_id")"
      printf "WARN: Short-path fallback still too long (%d chars), using emergency path %s\n" \
          "$new_len" "$wt_path" >&2
    fi
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

# =============================================================================
# Lifecycle tracking functions
# =============================================================================

# _to_python_path(path)
# Converts a Git Bash path to a Windows-native path when running on Windows.
# On non-Windows systems, returns the path unchanged.
# This is needed because Python on Windows cannot open Git Bash /tmp/ paths.
_to_python_path() {
  local p="$1"
  if command -v cygpath &>/dev/null; then
    cygpath -w "$p"
  else
    printf "%s" "$p"
  fi
}

# register_worktree(json_path, story_id, path, branch, wave)
# Adds an entry to execution.worktreeTracking.activeWorktrees in quantum.json.
# Creates the worktreeTracking structure if absent.
# Uses Python one-liner for atomic JSON mutation (following json-atomic.sh pattern).
# Returns 0 on success, 1 on failure.
register_worktree() {
  local json_path="$1"
  local story_id="$2"
  local wt_path="$3"
  local branch="$4"
  local wave="$5"

  if [[ -z "$json_path" || -z "$story_id" || -z "$wt_path" || -z "$branch" || -z "$wave" ]]; then
    printf "ERROR: register_worktree requires json_path, story_id, path, branch, wave\n" >&2
    return 1
  fi
  _validate_story_id "$story_id" || return 1

  if [[ ! -f "$json_path" ]]; then
    printf "ERROR: register_worktree: json file not found: %s\n" "$json_path" >&2
    return 1
  fi

  local py_json_path
  py_json_path=$(_to_python_path "$json_path")

  python -c "
import json, datetime, sys
jp = sys.argv[1]
sid = sys.argv[2]
wp = sys.argv[3]
br = sys.argv[4]
wv = int(sys.argv[5])
d = json.load(open(jp))
if 'execution' not in d:
    d['execution'] = {}
if 'worktreeTracking' not in d['execution']:
    d['execution']['worktreeTracking'] = {'activeWorktrees': [], 'cleanedThisSession': 0, 'maxWorktrees': 4}
if 'activeWorktrees' not in d['execution']['worktreeTracking']:
    d['execution']['worktreeTracking']['activeWorktrees'] = []
entry = {'path': wp, 'branch': br, 'storyId': sid, 'createdAt': datetime.datetime.now(datetime.timezone.utc).isoformat(), 'wave': wv}
d['execution']['worktreeTracking']['activeWorktrees'].append(entry)
tmp = jp + '.tmp'
json.dump(d, open(tmp, 'w'), indent=2)
import os; os.replace(tmp, jp)
" "$py_json_path" "$story_id" "$wt_path" "$branch" "$wave" || return 1

  printf "[WORKTREE] Registered %s at %s\n" "$story_id" "$wt_path"
  return 0
}

# cleanup_stale_worktrees(json_path, repo_root)
# Removes worktrees for stories that have status "passed" or "failed".
# Reads execution.worktreeTracking.activeWorktrees from quantum.json.
# Falls back to list_worktrees cross-referenced with story statuses when
# worktreeTracking is absent.
# On removal failure: retries once after 2s, then skips with warning.
# Logs '[WORKTREE] Cleaned N stale worktrees'.
# Returns 0 on success, 1 on failure.
cleanup_stale_worktrees() {
  local json_path="$1"
  local repo_root="$2"

  if [[ -z "$json_path" || -z "$repo_root" ]]; then
    printf "ERROR: cleanup_stale_worktrees requires json_path, repo_root\n" >&2
    return 1
  fi

  if [[ ! -f "$json_path" ]]; then
    printf "ERROR: cleanup_stale_worktrees: json file not found: %s\n" "$json_path" >&2
    return 1
  fi

  local py_json_path
  py_json_path=$(_to_python_path "$json_path")

  # Check if worktreeTracking exists
  local has_tracking
  has_tracking=$(python -c "
import json, sys
d = json.load(open(sys.argv[1]))
wt = d.get('execution', {}).get('worktreeTracking', {}).get('activeWorktrees')
print('yes' if wt is not None else 'no')
" "$py_json_path")

  local cleaned=0
  local consecutive_failures=0

  if [[ "$has_tracking" == "yes" ]]; then
    # Primary path: use worktreeTracking
    local stale_ids
    stale_ids=$(python -c "
import json, sys
d = json.load(open(sys.argv[1]))
statuses = {s['id']: s['status'] for s in d.get('stories', [])}
wts = d.get('execution', {}).get('worktreeTracking', {}).get('activeWorktrees', [])
for wt in wts:
    sid = wt.get('storyId', '')
    st = statuses.get(sid, '')
    if st in ('passed', 'failed'):
        print(sid)
" "$py_json_path")

    if [[ -n "$stale_ids" ]]; then
      while IFS= read -r sid; do
        if [[ -z "$sid" ]]; then
          continue
        fi
        # Attempt removal
        if remove_worktree "$sid" "$repo_root" 2>/dev/null; then
          cleaned=$((cleaned + 1))
          consecutive_failures=0
        else
          # Retry once after 2s
          sleep 2
          if remove_worktree "$sid" "$repo_root" 2>/dev/null; then
            cleaned=$((cleaned + 1))
            consecutive_failures=0
          else
            consecutive_failures=$((consecutive_failures + 1))
            printf "WARN: cleanup_stale_worktrees: failed to remove worktree for %s, skipping\n" "$sid" >&2
            if [[ $consecutive_failures -ge 3 ]]; then
              printf "WARN: cleanup_stale_worktrees: %d consecutive removal failures -- check system state\n" "$consecutive_failures" >&2
            fi
          fi
        fi
      done <<< "$stale_ids"
    fi

    # Update quantum.json: remove cleaned entries and increment cleanedThisSession
    if [[ $cleaned -gt 0 ]]; then
      python -c "
import json, sys
jp = sys.argv[1]
d = json.load(open(jp))
statuses = {s['id']: s['status'] for s in d.get('stories', [])}
wts = d.get('execution', {}).get('worktreeTracking', {}).get('activeWorktrees', [])
d['execution']['worktreeTracking']['activeWorktrees'] = [
    wt for wt in wts if statuses.get(wt.get('storyId', ''), '') not in ('passed', 'failed')
]
d['execution']['worktreeTracking']['cleanedThisSession'] = d['execution']['worktreeTracking'].get('cleanedThisSession', 0) + int(sys.argv[2])
tmp = jp + '.tmp'
json.dump(d, open(tmp, 'w'), indent=2)
import os; os.replace(tmp, jp)
" "$py_json_path" "$cleaned"
    fi
  else
    # Fallback: use list_worktrees cross-referenced with story statuses
    local all_wt_ids
    all_wt_ids=$(list_worktrees "$repo_root")

    if [[ -n "$all_wt_ids" ]]; then
      # Get in_progress story IDs from quantum.json
      local in_progress_ids
      in_progress_ids=$(python -c "
import json, sys
d = json.load(open(sys.argv[1]))
for s in d.get('stories', []):
    if s.get('status') == 'in_progress':
        print(s['id'])
" "$py_json_path")

      while IFS= read -r wt_id; do
        if [[ -z "$wt_id" ]]; then
          continue
        fi
        # Keep worktrees that match an in_progress story
        if echo "$in_progress_ids" | grep -qx "$wt_id"; then
          continue
        fi
        # Remove this stale worktree
        if remove_worktree "$wt_id" "$repo_root" 2>/dev/null; then
          cleaned=$((cleaned + 1))
          consecutive_failures=0
        else
          sleep 2
          if remove_worktree "$wt_id" "$repo_root" 2>/dev/null; then
            cleaned=$((cleaned + 1))
            consecutive_failures=0
          else
            consecutive_failures=$((consecutive_failures + 1))
            printf "WARN: cleanup_stale_worktrees: failed to remove worktree for %s, skipping\n" "$wt_id" >&2
            if [[ $consecutive_failures -ge 3 ]]; then
              printf "WARN: cleanup_stale_worktrees: %d consecutive removal failures -- check system state\n" "$consecutive_failures" >&2
            fi
          fi
        fi
      done <<< "$all_wt_ids"
    fi
  fi

  if [[ $cleaned -gt 0 ]]; then
    printf "[WORKTREE] Cleaned %d stale worktrees\n" "$cleaned"
  else
    printf "[WORKTREE] No stale worktrees found\n"
  fi

  return 0
}

# cleanup_merged_worktrees(json_path, repo_root, completed_story_ids)
# Removes worktrees for the given space-separated story IDs.
# Removes entries from activeWorktrees in quantum.json.
# Logs '[WORKTREE] Removing N merged worktrees from Wave M'.
# Returns 0 on success, 1 on failure.
cleanup_merged_worktrees() {
  local json_path="$1"
  local repo_root="$2"
  local completed_story_ids="$3"

  if [[ -z "$json_path" || -z "$repo_root" ]]; then
    printf "ERROR: cleanup_merged_worktrees requires json_path, repo_root\n" >&2
    return 1
  fi

  if [[ ! -f "$json_path" ]]; then
    printf "ERROR: cleanup_merged_worktrees: json file not found: %s\n" "$json_path" >&2
    return 1
  fi

  # Empty ID list is a no-op
  if [[ -z "$completed_story_ids" ]]; then
    printf "[WORKTREE] No merged worktrees to clean\n"
    return 0
  fi

  local py_json_path
  py_json_path=$(_to_python_path "$json_path")

  # Determine the wave for logging
  local wave
  wave=$(python -c "
import json, sys
d = json.load(open(sys.argv[1]))
ids = sys.argv[2].split()
wts = d.get('execution', {}).get('worktreeTracking', {}).get('activeWorktrees', [])
waves = [wt.get('wave', 0) for wt in wts if wt.get('storyId', '') in ids]
print(max(waves) if waves else 0)
" "$py_json_path" "$completed_story_ids" 2>/dev/null || echo "0")

  local cleaned=0
  local consecutive_failures=0

  for sid in $completed_story_ids; do
    if [[ -z "$sid" ]]; then
      continue
    fi
    if remove_worktree "$sid" "$repo_root" 2>/dev/null; then
      cleaned=$((cleaned + 1))
      consecutive_failures=0
    else
      # Retry once after 2s
      sleep 2
      if remove_worktree "$sid" "$repo_root" 2>/dev/null; then
        cleaned=$((cleaned + 1))
        consecutive_failures=0
      else
        consecutive_failures=$((consecutive_failures + 1))
        printf "WARN: cleanup_merged_worktrees: failed to remove worktree for %s, skipping\n" "$sid" >&2
        if [[ $consecutive_failures -ge 3 ]]; then
          printf "WARN: cleanup_merged_worktrees: %d consecutive removal failures -- check system state\n" "$consecutive_failures" >&2
        fi
      fi
    fi
  done

  # Update quantum.json: remove cleaned entries from activeWorktrees
  if [[ $cleaned -gt 0 ]]; then
    python -c "
import json, sys
jp = sys.argv[1]
ids = set(sys.argv[2].split())
d = json.load(open(jp))
wt_tracking = d.get('execution', {}).get('worktreeTracking', {})
if 'activeWorktrees' in wt_tracking:
    wt_tracking['activeWorktrees'] = [
        wt for wt in wt_tracking['activeWorktrees'] if wt.get('storyId', '') not in ids
    ]
tmp = jp + '.tmp'
json.dump(d, open(tmp, 'w'), indent=2)
import os; os.replace(tmp, jp)
" "$py_json_path" "$completed_story_ids"
  fi

  printf "[WORKTREE] Removing %d merged worktrees from Wave %s\n" "$cleaned" "$wave"
  return 0
}

# pre_spawn_check(json_path, max_worktrees)
# Checks if there is room to spawn a new worktree.
# If at or above the limit: calls cleanup_stale_worktrees first.
# If still at or above the limit after cleanup: returns 1 (no slot available).
# If under the limit: returns 0 (slot available).
pre_spawn_check() {
  local json_path="$1"
  local max_worktrees="$2"

  if [[ -z "$json_path" || -z "$max_worktrees" ]]; then
    printf "ERROR: pre_spawn_check requires json_path, max_worktrees\n" >&2
    return 1
  fi

  if [[ ! -f "$json_path" ]]; then
    printf "ERROR: pre_spawn_check: json file not found: %s\n" "$json_path" >&2
    return 1
  fi

  local py_json_path
  py_json_path=$(_to_python_path "$json_path")

  # Get current active worktree count
  local current_count
  current_count=$(python -c "
import json, sys
d = json.load(open(sys.argv[1]))
wts = d.get('execution', {}).get('worktreeTracking', {}).get('activeWorktrees', [])
print(len(wts))
" "$py_json_path")

  if [[ "$current_count" -ge "$max_worktrees" ]]; then
    # At limit: try cleaning stale worktrees first
    # Need repo_root for cleanup -- extract from worktree paths or use current dir
    local repo_root
    repo_root=$(python -c "
import json, sys, os
d = json.load(open(sys.argv[1]))
wts = d.get('execution', {}).get('worktreeTracking', {}).get('activeWorktrees', [])
if wts:
    p = wts[0].get('path', '')
    # Strip /.ql-wt/STORY_ID to get repo root
    idx = p.find('/.ql-wt/')
    if idx > 0:
        print(p[:idx])
    else:
        print(os.path.dirname(sys.argv[1]))
else:
    print(os.path.dirname(sys.argv[1]))
" "$py_json_path")

    cleanup_stale_worktrees "$json_path" "$repo_root" 2>/dev/null

    # Re-check count after cleanup
    current_count=$(python -c "
import json, sys
d = json.load(open(sys.argv[1]))
wts = d.get('execution', {}).get('worktreeTracking', {}).get('activeWorktrees', [])
print(len(wts))
" "$py_json_path")

    if [[ "$current_count" -ge "$max_worktrees" ]]; then
      printf "[WORKTREE] WARNING: at worktree limit (%d/%d)\n" "$current_count" "$max_worktrees" >&2
      return 1
    fi
  fi

  return 0
}
