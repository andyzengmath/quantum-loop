#!/usr/bin/env bash
# lib/init-guard.sh -- Environment detection and preflight checks for quantum-loop
# Source this file to use detect_environment(), warn_long_path(), prune_stale_refs(),
# cleanup_orphan_dirs(), run_preflight()

# Source shared utilities
INIT_GUARD_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091,SC2317
source "$INIT_GUARD_LIB_DIR/common.sh" || { printf "ERROR: common.sh not found\n" >&2; return 1 2>/dev/null || exit 1; }

# detect_environment(repo_root)
# Checks the environment for potential issues and returns pipe-delimited warning codes.
# Codes: long_path, onedrive_long_path, tmpdir_not_writable, windows
# Returns empty string if no issues detected.
detect_environment() {
  local repo_root="$1"
  local codes=()

  # (a) Check path length > 150 chars
  if [[ ${#repo_root} -gt 150 ]]; then
    codes+=("long_path")
  fi

  # (b) Check for OneDrive in path (case-insensitive)
  local lower_path
  lower_path=$(printf '%s' "$repo_root" | tr '[:upper:]' '[:lower:]')
  if [[ "$lower_path" == *onedrive* ]]; then
    codes+=("onedrive_long_path")
  fi

  # (c) Check tmpdir writability
  local tmpdir="${TMPDIR:-/tmp}"
  local test_file
  test_file=$(mktemp "${tmpdir}/ql-init-guard-XXXXXX" 2>/dev/null)
  if [[ -n "$test_file" && -f "$test_file" ]]; then
    rm -f "$test_file"
  else
    codes+=("tmpdir_not_writable")
  fi

  # (d) Detect Windows via uname or MSYSTEM
  local uname_s
  uname_s=$(uname -s 2>/dev/null || echo "")
  if [[ "$uname_s" == MINGW* ]] || [[ "$uname_s" == MSYS* ]] || [[ "$uname_s" == CYGWIN* ]] || [[ -n "$MSYSTEM" ]]; then
    codes+=("windows")
  fi

  # Join with pipe delimiter
  local IFS='|'
  printf '%s' "${codes[*]}"
}

# warn_long_path(repo_root)
# Logs a warning about long repo paths. Uses OneDrive-specific message when
# the path contains 'OneDrive', otherwise logs a generic long-path warning.
# Output goes to stderr for logging.
warn_long_path() {
  local repo_root="$1"
  local path_len=${#repo_root}
  local lower_path
  lower_path=$(printf '%s' "$repo_root" | tr '[:upper:]' '[:lower:]')

  if [[ "$lower_path" == *onedrive* ]]; then
    printf "[INIT-GUARD] WARN: Repo path contains OneDrive (%d chars): %s\n" "$path_len" "$repo_root" >&2
  else
    printf "[INIT-GUARD] WARN: Repo path is long (%d chars): %s\n" "$path_len" "$repo_root" >&2
  fi
}

# prune_stale_refs(repo_root)
# Runs 'git worktree prune' to clean up stale worktree references.
# Retries once after 2s on failure.
# Prints the pruned count to stdout and a log message to stderr.
# Returns 0 on success, 1 on failure.
prune_stale_refs() {
  local repo_root="$1"

  if [[ -z "$repo_root" ]]; then
    printf "ERROR: prune_stale_refs requires repo_root\n" >&2
    return 1
  fi

  # Count worktree refs before pruning
  local before_count
  before_count=$(git -C "$repo_root" worktree list --porcelain 2>/dev/null | grep -c "^worktree " || echo "0")

  # Attempt prune
  if ! git -C "$repo_root" worktree prune 2>/dev/null; then
    # Retry once after 2s
    sleep 2
    if ! git -C "$repo_root" worktree prune 2>/dev/null; then
      printf "[INIT-GUARD] ERROR: git worktree prune failed after retry\n" >&2
      printf "0"
      return 1
    fi
  fi

  # Count worktree refs after pruning
  local after_count
  after_count=$(git -C "$repo_root" worktree list --porcelain 2>/dev/null | grep -c "^worktree " || echo "0")

  local pruned=$((before_count - after_count))
  if [[ $pruned -lt 0 ]]; then
    pruned=0
  fi

  printf "[INIT-GUARD] Pruned %d stale worktree references\n" "$pruned" >&2
  printf '%d' "$pruned"
  return 0
}

# cleanup_orphan_dirs(repo_root)
# Scans .ql-wt/ for directories that are not listed in 'git worktree list'.
# Removes clean orphans (no uncommitted changes) with rm -rf.
# Preserves dirty orphans (with uncommitted changes) and logs a warning.
# Prints the cleaned count to stdout.
# Returns 0 on success, 1 on failure.
cleanup_orphan_dirs() {
  local repo_root="$1"

  if [[ -z "$repo_root" ]]; then
    printf "ERROR: cleanup_orphan_dirs requires repo_root\n" >&2
    return 1
  fi

  local wt_dir="$repo_root/.ql-wt"
  if [[ ! -d "$wt_dir" ]]; then
    printf '%d' 0
    return 0
  fi

  # Get list of registered worktree paths from git.
  # On Windows/MSYS, git returns native paths (C:/Users/...) while bash uses
  # MSYS paths (/tmp/...). We compare by basename within .ql-wt/ to avoid
  # path format mismatches.
  local registered_basenames
  registered_basenames=$(git -C "$repo_root" worktree list --porcelain 2>/dev/null \
    | grep "^worktree " | sed 's/^worktree //' \
    | while IFS= read -r rpath; do
        # Only consider paths that contain .ql-wt/
        if [[ "$rpath" == */.ql-wt/* ]] || [[ "$rpath" == *\\.ql-wt\\* ]]; then
          basename "$rpath"
        fi
      done)

  local cleaned=0

  for dir in "$wt_dir"/*/; do
    # Skip if not a directory (glob didn't match)
    [[ -d "$dir" ]] || continue

    # Normalize: remove trailing slash
    dir="${dir%/}"
    local dir_name
    dir_name=$(basename "$dir")

    # Check if this directory is a registered worktree (by basename)
    local is_registered=false
    while IFS= read -r rname; do
      [[ -z "$rname" ]] && continue
      if [[ "$rname" == "$dir_name" ]]; then
        is_registered=true
        break
      fi
    done <<< "$registered_basenames"

    if [[ "$is_registered" == "true" ]]; then
      continue
    fi

    # This is an orphan directory -- check if it has its own git state
    # (worktrees have a .git file, full repos have a .git directory).
    # Only check git status if the directory has its own git identity,
    # otherwise it is just a leftover directory and is considered clean.
    local is_dirty=false
    if [[ -e "$dir/.git" ]]; then
      local git_status
      git_status=$(git -C "$dir" status --porcelain 2>/dev/null)
      if [[ -n "$git_status" ]]; then
        is_dirty=true
      fi
    fi

    if [[ "$is_dirty" == "true" ]]; then
      printf "[INIT-GUARD] WARN: Preserving dirty orphan directory: %s\n" "$dir" >&2
    else
      # Clean orphan -- remove it
      # Windows file lock handling: retry loop (3 attempts, 2s sleep) before rm -rf fallback
      local removed=false
      local attempt=0
      while [[ $attempt -lt 3 ]]; do
        rm -rf "$dir" 2>/dev/null && { removed=true; break; }
        attempt=$((attempt + 1))
        if [[ $attempt -lt 3 ]]; then
          sleep 2
        fi
      done
      if [[ "$removed" == "true" ]]; then
        cleaned=$((cleaned + 1))
        printf "[INIT-GUARD] Removed orphan directory: %s\n" "$dir" >&2
      else
        printf "[INIT-GUARD] WARN: Failed to remove orphan directory: %s\n" "$dir" >&2
      fi
    fi
  done

  printf '%d' "$cleaned"
  return 0
}

# run_preflight(repo_root, json_path)
# Orchestrates all preflight checks and writes results to quantum.json.
# Idempotent: skips if execution.initGuard.ranAt exists and is within 1 hour.
# Steps:
#   1. Check idempotency (ranAt within 1 hour)
#   2. Call detect_environment
#   3. Call warn_long_path if path warnings detected
#   4. Call prune_stale_refs
#   5. Call cleanup_orphan_dirs
#   6. Write execution.initGuard to quantum.json via atomic Python write
#   7. Set forceSequential=true if tmpdir_not_writable
# Returns 0 on success, 1 on failure.
run_preflight() {
  local repo_root="$1"
  local json_path="$2"

  if [[ -z "$repo_root" ]]; then
    printf "ERROR: run_preflight requires repo_root\n" >&2
    return 1
  fi

  if [[ -z "$json_path" ]]; then
    printf "ERROR: run_preflight requires json_path\n" >&2
    return 1
  fi

  if [[ ! -f "$json_path" ]]; then
    printf "ERROR: run_preflight: json file not found: %s\n" "$json_path" >&2
    return 1
  fi

  local py_json_path
  py_json_path=$(_to_native_path "$json_path")

  # Step 1: Idempotency check -- skip if ranAt exists and is within 1 hour
  local should_skip
  should_skip=$(python -c "
import json, sys, datetime
jp = sys.argv[1]
d = json.load(open(jp))
ig = d.get('execution', {}).get('initGuard', {})
ran_at = ig.get('ranAt', '')
if ran_at:
    try:
        ts = datetime.datetime.fromisoformat(ran_at.replace('Z', '+00:00'))
        now = datetime.datetime.now(datetime.timezone.utc)
        if (now - ts).total_seconds() < 3600:
            print('yes')
        else:
            print('no')
    except (ValueError, TypeError):
        print('no')
else:
    print('no')
" "$py_json_path" 2>/dev/null || echo "no")

  if [[ "$should_skip" == "yes" ]]; then
    printf "[INIT-GUARD] Preflight skip: ran within the last hour\n" >&2
    return 0
  fi

  # Step 2: Detect environment
  local warnings
  warnings=$(detect_environment "$repo_root")

  # Step 3: Warn about long paths if detected
  if [[ "$warnings" == *long_path* ]] || [[ "$warnings" == *onedrive_long_path* ]]; then
    warn_long_path "$repo_root"
  fi

  # Step 4: Prune stale refs
  local pruned_count
  pruned_count=$(prune_stale_refs "$repo_root" 2>/dev/null) || pruned_count=0

  # Step 5: Cleanup orphan dirs
  local cleaned_count
  cleaned_count=$(cleanup_orphan_dirs "$repo_root" 2>/dev/null) || cleaned_count=0

  # Step 6 & 7: Write results to quantum.json
  local force_sequential="false"
  if [[ "$warnings" == *tmpdir_not_writable* ]]; then
    force_sequential="true"
  fi

  python -c "
import json, sys, datetime
jp = sys.argv[1]
warnings = sys.argv[2]
pruned = int(sys.argv[3])
cleaned = int(sys.argv[4])
force_seq = sys.argv[5] == 'true'

d = json.load(open(jp))
if 'execution' not in d:
    d['execution'] = {}

d['execution']['initGuard'] = {
    'ranAt': datetime.datetime.now(datetime.timezone.utc).isoformat(),
    'warnings': warnings.split('|') if warnings else [],
    'prunedRefs': pruned,
    'cleanedOrphans': cleaned,
    'forceSequential': force_seq
}

tmp = jp + '.tmp'
json.dump(d, open(tmp, 'w'), indent=2)
import os; os.replace(tmp, jp)
" "$py_json_path" "$warnings" "$pruned_count" "$cleaned_count" "$force_sequential" || {
    printf "[INIT-GUARD] ERROR: Failed to write initGuard to quantum.json\n" >&2
    return 1
  }

  printf "[INIT-GUARD] Preflight complete: warnings=%s pruned=%d cleaned=%d forceSequential=%s\n" \
    "${warnings:-none}" "$pruned_count" "$cleaned_count" "$force_sequential" >&2
  return 0
}
