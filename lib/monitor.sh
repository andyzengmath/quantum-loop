#!/usr/bin/env bash
# lib/monitor.sh -- Agent monitoring and worktree merge functions for quantum-loop
#
# Provides: detect_signal(), check_agent_status(), merge_worktree_branch(),
#           check_agent_timeout(), kill_agent_process(), DEFAULT_AGENT_TIMEOUT
# Requires: lib/spawn.sh (for AGENT_OUTPUT_FILENAME)

# Source shared utilities
MONITOR_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$MONITOR_LIB_DIR/common.sh" || { printf "ERROR: common.sh not found\n" >&2; return 1 2>/dev/null || exit 1; }
source "$MONITOR_LIB_DIR/spawn.sh" || { printf "ERROR: spawn.sh not found\n" >&2; return 1 2>/dev/null || exit 1; }

# detect_signal(output_file)
# Scans an agent output file for quantum completion signals.
# Returns "STORY_PASSED", "STORY_FAILED", or "" on stdout.
detect_signal() {
  local output_file="$1"

  if [[ -z "$output_file" || ! -f "$output_file" ]]; then
    return 0
  fi

  if grep -q '<quantum>STORY_PASSED</quantum>' "$output_file" 2>/dev/null; then
    printf "STORY_PASSED"
    return 0
  fi

  if grep -q '<quantum>STORY_FAILED</quantum>' "$output_file" 2>/dev/null; then
    printf "STORY_FAILED"
    return 0
  fi

  return 0
}

# check_agent_status(pid, worktree_path)
# Checks whether a background agent process is still running and what its signal is.
# Returns one of: "RUNNING", "STORY_PASSED", "STORY_FAILED", "CRASH"
check_agent_status() {
  local pid="$1"
  local worktree_path="$2"

  if [[ -z "$pid" ]]; then
    printf "ERROR: check_agent_status requires pid\n" >&2
    return 1
  fi

  if [[ -z "$worktree_path" ]]; then
    printf "ERROR: check_agent_status requires worktree_path\n" >&2
    return 1
  fi

  local output_file="${worktree_path}/${AGENT_OUTPUT_FILENAME}"

  # Check if process is still running
  if kill -0 "$pid" 2>/dev/null; then
    # Process alive -- check if it already emitted a signal
    local signal
    signal=$(detect_signal "$output_file")
    if [[ -n "$signal" ]]; then
      printf "%s" "$signal"
    else
      printf "RUNNING"
    fi
    return 0
  fi

  # Process has exited -- check for signal in output
  local signal
  signal=$(detect_signal "$output_file")
  if [[ -n "$signal" ]]; then
    printf "%s" "$signal"
    return 0
  fi

  # Process exited with no signal -- crash
  printf "CRASH"
  return 0
}

# merge_worktree_branch(repo_root, worktree_branch)
# Merges a worktree branch into the current branch (feature branch).
# On success: returns 0.
# On conflict: aborts the merge and returns 1.
merge_worktree_branch() {
  local repo_root="$1"
  local worktree_branch="$2"

  if [[ -z "$repo_root" ]]; then
    printf "ERROR: merge_worktree_branch requires repo_root\n" >&2
    return 1
  fi

  if [[ -z "$worktree_branch" ]]; then
    printf "ERROR: merge_worktree_branch requires worktree_branch\n" >&2
    return 1
  fi

  # Stash any dirty working tree state so merge can proceed
  local stashed=false
  if git -C "$repo_root" status --porcelain 2>/dev/null | grep -q .; then
    git -C "$repo_root" stash push -m "ql-auto-stash-before-merge-${worktree_branch}" -q 2>/dev/null && stashed=true
  fi

  # Attempt merge (no squash, no rebase per spec)
  if git -C "$repo_root" merge "$worktree_branch" --no-edit -q 2>/dev/null; then
    [[ "$stashed" == "true" ]] && { git -C "$repo_root" stash pop -q 2>/dev/null || true; }
    return 0
  fi

  # Merge failed -- capture conflict details before aborting
  # Write conflict file list to stdout so caller can capture it
  git -C "$repo_root" diff --name-only --diff-filter=U 2>/dev/null || true
  git -C "$repo_root" merge --abort 2>/dev/null || true
  [[ "$stashed" == "true" ]] && { git -C "$repo_root" stash pop -q 2>/dev/null || true; }
  return 1
}

# Default per-story timeout in seconds (15 minutes)
DEFAULT_AGENT_TIMEOUT=900

# check_agent_timeout(start_time, timeout_seconds)
# Checks whether an agent has exceeded its timeout.
# start_time: epoch seconds when the agent was spawned.
# timeout_seconds: max allowed runtime in seconds.
# Returns "true" or "false" on stdout.
check_agent_timeout() {
  local start_time="$1"
  local timeout="$2"

  if [[ -z "$start_time" ]]; then
    printf "ERROR: check_agent_timeout requires start_time\n" >&2
    return 1
  fi

  if [[ -z "$timeout" ]]; then
    printf "ERROR: check_agent_timeout requires timeout_seconds\n" >&2
    return 1
  fi

  local now
  now=$(date +%s)
  local elapsed=$((now - start_time))

  if [[ "$elapsed" -ge "$timeout" ]]; then
    printf "true"
  else
    printf "false"
  fi
  return 0
}

# kill_agent_process(pid)
# Sends SIGTERM to an agent process. Idempotent (no error if already dead).
# Returns 0 always.
kill_agent_process() {
  local pid="$1"

  if [[ -z "$pid" ]]; then
    printf "ERROR: kill_agent_process requires pid\n" >&2
    return 1
  fi

  if kill -0 "$pid" 2>/dev/null; then
    kill "$pid" 2>/dev/null || true
  fi

  return 0
}
