#!/usr/bin/env bash
# lib/monitor.sh -- Agent monitoring and worktree merge functions for quantum-loop
#
# Provides: detect_signal(), check_agent_status(), merge_worktree_branch(),
#           check_agent_timeout(), kill_agent_process(), post_merge_typecheck(),
#           DEFAULT_AGENT_TIMEOUT
# Requires: lib/spawn.sh (for AGENT_OUTPUT_FILENAME), lib/materialize.sh (for detect_language)

# Source shared utilities
MONITOR_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$MONITOR_LIB_DIR/common.sh" || { printf "ERROR: common.sh not found\n" >&2; return 1 2>/dev/null || exit 1; }
source "$MONITOR_LIB_DIR/spawn.sh" || { printf "ERROR: spawn.sh not found\n" >&2; return 1 2>/dev/null || exit 1; }
source "$MONITOR_LIB_DIR/materialize.sh" || { printf "ERROR: materialize.sh not found\n" >&2; return 1 2>/dev/null || exit 1; }

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
# On conflict: prints "CONFLICT: <filename>" lines to stdout, aborts the merge,
#   and returns 1. Caller can capture stdout for retries.failureLog[].error.
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
  if git -C "$repo_root" merge "$worktree_branch" --no-edit -q > /dev/null 2>&1; then
    [[ "$stashed" == "true" ]] && { git -C "$repo_root" stash pop -q 2>/dev/null || true; }
    return 0
  fi

  # Merge failed -- capture conflict file list before aborting
  # Prefix each file with CONFLICT: for structured failureLog inclusion
  local conflict_files
  conflict_files=$(git -C "$repo_root" diff --name-only --diff-filter=U 2>/dev/null) || true
  if [[ -n "$conflict_files" ]]; then
    while IFS= read -r file; do
      printf "CONFLICT: %s\n" "$file"
    done <<< "$conflict_files"
  fi
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

# Typecheck timeout in seconds
TYPECHECK_TIMEOUT=120

# post_merge_typecheck(repo_root, json_path)
# Runs a typecheck command after merging a worktree branch.
# Uses typecheckCommand from quantum.json if set, else auto-detects from language.
# If no command can be determined: logs skip warning and returns 0.
# If command not found in PATH (exit 127): logs warning and returns 0.
# Compares error count against execution.baselineTypecheckErrors:
#   - If baseline not set: initializes baseline with current count, returns 0.
#   - If current errors > baseline: reverts merge (git revert -m 1 HEAD --no-edit), returns 1.
#   - If current errors <= baseline: returns 0.
# Runs with 120s timeout.
post_merge_typecheck() {
  local repo_root="$1"
  local json_path="$2"

  if [[ -z "$repo_root" ]]; then
    printf "[TYPECHECK] ERROR: repo_root is required\n" >&2
    return 1
  fi

  if [[ -z "$json_path" ]]; then
    printf "[TYPECHECK] ERROR: json_path is required\n" >&2
    return 1
  fi

  # Read typecheckCommand from JSON
  local typecheck_cmd=""
  if [[ -f "$json_path" ]]; then
    typecheck_cmd=$(jq -r '.typecheckCommand // empty' "$json_path" 2>/dev/null) || true
  fi

  # If no explicit command, auto-detect from language
  if [[ -z "$typecheck_cmd" ]]; then
    local language
    language=$(detect_language "$repo_root")

    case "$language" in
      typescript)
        typecheck_cmd="tsc --noEmit"
        ;;
      python)
        if command -v pyright >/dev/null 2>&1; then
          typecheck_cmd="pyright"
        elif command -v mypy >/dev/null 2>&1; then
          typecheck_cmd="mypy ."
        fi
        ;;
      go)
        typecheck_cmd="go vet ./..."
        ;;
    esac
  fi

  # If still no command, skip
  if [[ -z "$typecheck_cmd" ]]; then
    printf "[TYPECHECK] skip: no typecheck command configured or detected\n"
    return 0
  fi

  printf "[TYPECHECK] running: %s\n" "$typecheck_cmd"

  # Run the typecheck command with timeout, capture output and exit code
  local tc_output
  local tc_exit
  tc_output=$(cd "$repo_root" && timeout "$TYPECHECK_TIMEOUT" bash -c "$typecheck_cmd" 2>&1) || tc_exit=$?
  tc_exit=${tc_exit:-0}

  # Handle command not found (exit 127)
  if [[ "$tc_exit" -eq 127 ]]; then
    printf "[TYPECHECK] warning: command not found: %s\n" "$typecheck_cmd"
    return 0
  fi

  # Handle timeout (exit 124 from GNU timeout)
  if [[ "$tc_exit" -eq 124 ]]; then
    printf "[TYPECHECK] warning: command timed out after %ds\n" "$TYPECHECK_TIMEOUT"
    return 0
  fi

  # Count error lines in the output
  local error_count=0
  if [[ -n "$tc_output" ]]; then
    error_count=$(printf "%s\n" "$tc_output" | grep -c "error" 2>/dev/null) || error_count=0
  fi

  # If command exited non-zero, use exit code as minimum error count (at least 1)
  if [[ "$tc_exit" -ne 0 && "$error_count" -eq 0 ]]; then
    error_count=1
  fi

  printf "[TYPECHECK] completed: %d errors (exit code %d)\n" "$error_count" "$tc_exit"

  # Read baseline from JSON
  local baseline
  baseline=$(jq -r '.execution.baselineTypecheckErrors // empty' "$json_path" 2>/dev/null) || true

  # If no baseline, initialize it
  if [[ -z "$baseline" ]]; then
    printf "[TYPECHECK] baseline initialized: %d errors\n" "$error_count"
    # Write baseline to JSON using atomic jq pattern
    local tmp_json="${json_path}.tmp.$$"
    if jq --argjson count "$error_count" '
      .execution = (.execution // {}) | .execution.baselineTypecheckErrors = $count
    ' "$json_path" > "$tmp_json" 2>/dev/null; then
      mv "$tmp_json" "$json_path"
    else
      rm -f "$tmp_json"
    fi
    return 0
  fi

  # Compare against baseline
  if [[ "$error_count" -gt "$baseline" ]]; then
    printf "[TYPECHECK] FAIL: %d errors > baseline %d — reverting merge\n" "$error_count" "$baseline"
    # Stash any dirty tracked files before reverting (e.g., quantum.json updates)
    git -C "$repo_root" stash push -q 2>/dev/null || true
    git -C "$repo_root" revert --no-edit -m 1 HEAD 2>/dev/null || true
    git -C "$repo_root" stash pop -q 2>/dev/null || true
    return 1
  fi

  printf "[TYPECHECK] PASS: %d errors <= baseline %d\n" "$error_count" "$baseline"
  return 0
}
