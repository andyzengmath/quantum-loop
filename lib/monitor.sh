#!/usr/bin/env bash
# lib/monitor.sh -- Agent monitoring and worktree merge functions for quantum-loop
#
# Provides: detect_signal(), check_agent_status(), merge_worktree_branch(),
#           check_agent_timeout(), kill_agent_process(), post_merge_typecheck(),
#           DEFAULT_AGENT_TIMEOUT
# Requires: lib/spawn.sh (for AGENT_OUTPUT_FILENAME), lib/materialize.sh (for detect_language),
#           lib/json-atomic.sh (for write_quantum_json)
# Optional: lib/merge-strategy.sh (for classify_and_merge), lib/resilience.sh (for squash_and_merge)

# shellcheck disable=SC1091,SC2034,SC2317  # SC1091: sourced files resolved at runtime; SC2034: vars used by callers; SC2317: exit 1 fallback reachable at source-time

# Source shared utilities
MONITOR_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$MONITOR_LIB_DIR/common.sh" || { printf "ERROR: common.sh not found\n" >&2; return 1 2>/dev/null || exit 1; }
source "$MONITOR_LIB_DIR/spawn.sh" || { printf "ERROR: spawn.sh not found\n" >&2; return 1 2>/dev/null || exit 1; }
source "$MONITOR_LIB_DIR/materialize.sh" || { printf "ERROR: materialize.sh not found\n" >&2; return 1 2>/dev/null || exit 1; }

# Graceful optional module loading: merge-strategy.sh provides classify_and_merge()
MERGE_STRATEGY_AVAILABLE=true
source "$MONITOR_LIB_DIR/merge-strategy.sh" 2>/dev/null || MERGE_STRATEGY_AVAILABLE=false

# Graceful optional module loading: resilience.sh provides squash_and_merge()
RESILIENCE_AVAILABLE=true
source "$MONITOR_LIB_DIR/resilience.sh" 2>/dev/null || RESILIENCE_AVAILABLE=false

# detect_signal(output_file [worktree_path] [exit_code])
# Scans an agent output file for quantum completion signals.
# Uses runner_parse_output() when available for heuristic fallback support.
# Returns "STORY_PASSED", "STORY_FAILED", or "" on stdout.
detect_signal() {
  local output_file="$1"
  local wt_path="${2:-.}"
  local exit_code="${3:-0}"

  if [[ -z "$output_file" || ! -f "$output_file" ]]; then
    return 0
  fi

  local output
  output=$(cat "$output_file")

  # Use runner_parse_output if available (supports heuristic fallback for non-Claude runners)
  if type runner_parse_output &>/dev/null && [[ -n "${RUNNER_NAME:-}" ]]; then
    runner_parse_output "$output" "$exit_code" "$wt_path" 2>/dev/null
    if [[ -n "${SIGNAL_RESULT:-}" ]]; then
      printf "%s" "$SIGNAL_RESULT"
      return 0
    fi
    return 0
  fi

  # Fallback: direct grep (original behavior for backward compatibility)
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
    signal=$(detect_signal "$output_file" "$worktree_path")
    if [[ -n "$signal" ]]; then
      printf "%s" "$signal"
    else
      printf "RUNNING"
    fi
    return 0
  fi

  # Process has exited -- capture exit code and check for signal
  local exit_code=0
  wait "$pid" 2>/dev/null || exit_code=$?

  local signal
  signal=$(detect_signal "$output_file" "$worktree_path" "$exit_code")
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

  # Delegate to squash_and_merge when resilience module is available
  # and quantum.json exists at the repo root.
  # squash_and_merge handles squash-merge, commit message, and cleanup internally.
  if [[ "$RESILIENCE_AVAILABLE" != "false" ]] && [[ -f "$repo_root/quantum.json" ]]; then
    local story_id story_title json_path="$repo_root/quantum.json"
    # Extract story_id from branch name (format: ql-wt/US-XXX)
    story_id="${worktree_branch##*/}"
    # Extract story_title from quantum.json
    story_title=$(python -c "import json,sys; d=json.load(open(sys.argv[1])); print(next((s['title'] for s in d.get('stories',[]) if s['id']==sys.argv[2]),''))" "$(_to_native_path "$json_path")" "$story_id" 2>/dev/null) || story_title=""
    squash_and_merge "$worktree_branch" "$repo_root" "$story_id" "${story_title:-$story_id}" "$json_path"
    return $?
  fi

  # Delegate to classify_and_merge when merge-strategy module is available
  # and quantum.json exists at the repo root (needed for merge rules context).
  # classify_and_merge handles stashing, conflict resolution, and commit internally.
  if [[ "$MERGE_STRATEGY_AVAILABLE" != "false" ]] && [[ -f "$repo_root/quantum.json" ]]; then
    classify_and_merge "$worktree_branch" "$repo_root" "$repo_root/quantum.json"
    return $?
  fi

  # Fallback: bare git merge (when merge-strategy.sh not available or no quantum.json)

  # Stash any dirty working tree state so merge can proceed
  local stashed=false
  if git -C "$repo_root" status --porcelain 2>/dev/null | grep -q .; then
    git -C "$repo_root" stash push -m "ql-auto-stash-before-merge-${worktree_branch}" -q 2>/dev/null && stashed=true
  fi

  # Attempt merge (no squash, no rebase per spec; --no-ff ensures merge commit)
  if git -C "$repo_root" merge --no-ff "$worktree_branch" --no-edit -q > /dev/null 2>&1; then
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

  # Detect language (needed for both auto-detect and error counting)
  local language
  language=$(detect_language "$repo_root")

  # If no explicit command, auto-detect from language
  if [[ -z "$typecheck_cmd" ]]; then
    case "$language" in
      typescript)
        typecheck_cmd="tsc --noEmit"
        ;;
      python)
        # Check config files first (per PRD spec), then command availability
        if [[ -f "$repo_root/pyrightconfig.json" ]] || grep -q '\[tool\.pyright\]' "$repo_root/pyproject.toml" 2>/dev/null; then
          typecheck_cmd="pyright"
        elif [[ -f "$repo_root/.mypy.ini" ]] || [[ -f "$repo_root/mypy.ini" ]] || grep -q '\[mypy\]' "$repo_root/setup.cfg" 2>/dev/null; then
          typecheck_cmd="mypy ."
        elif command -v pyright >/dev/null 2>&1; then
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
    printf "[TYPECHECK] No typecheck command configured or detected. Skipping.\n"
    return 0
  fi

  # Allowlist of known-safe typecheck command prefixes. Tests may extend
  # via TYPECHECK_EXTRA_ALLOWED_PREFIXES (colon-separated) — env-var
  # tunable, same pattern as TYPECHECK_TIMEOUT. Env var is not readable
  # by the quantum.json it guards, so this cannot be weaponized by a
  # malicious repo.
  local -a ALLOWED_TYPECHECK_PREFIXES=("tsc" "pyright" "mypy" "go vet" "go build" "npx tsc" "pnpm tsc" "yarn tsc" "pnpm exec tsc" "npx pyright")
  if [[ -n "${TYPECHECK_EXTRA_ALLOWED_PREFIXES:-}" ]]; then
    local IFS=':'
    local extra
    for extra in $TYPECHECK_EXTRA_ALLOWED_PREFIXES; do
      [[ -n "$extra" ]] && ALLOWED_TYPECHECK_PREFIXES+=("$extra")
    done
    unset IFS
  fi

  local allowed=false
  for prefix in "${ALLOWED_TYPECHECK_PREFIXES[@]}"; do
    if [[ "$typecheck_cmd" == "$prefix" || "$typecheck_cmd" == "$prefix "* ]]; then
      allowed=true
      break
    fi
  done

  # Secondary guard: reject shell metacharacters even if prefix matched
  if [[ "$typecheck_cmd" =~ [\;\|\&\$\`\(\)\>\<\!] ]] || [[ "$typecheck_cmd" == *$'\n'* ]]; then
    printf "[TYPECHECK] ERROR: typecheckCommand '%s' does not match any allowed prefix — refusing to execute\n" "$typecheck_cmd" >&2
    return 1
  fi

  if [[ "$allowed" != "true" ]]; then
    printf "[TYPECHECK] ERROR: typecheckCommand '%s' does not match any allowed prefix — refusing to execute\n" "$typecheck_cmd" >&2
    return 1
  fi

  printf "[TYPECHECK] running: %s\n" "$typecheck_cmd"

  # Execute as array to prevent shell interpretation
  local -a cmd_array
  read -ra cmd_array <<< "$typecheck_cmd"
  local tc_output
  local tc_exit=0
  tc_output=$(cd "$repo_root" && timeout "$TYPECHECK_TIMEOUT" "${cmd_array[@]}" 2>&1) || tc_exit=$?

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

  # Count errors using language-specific patterns
  local error_count=0
  if [[ -n "$tc_output" ]]; then
    case "$language" in
      typescript)
        # tsc outputs "file(line,col): error TS####: message"
        error_count=$(printf "%s\n" "$tc_output" | grep -c "error TS" 2>/dev/null) || error_count=0
        ;;
      python)
        # pyright: "N errors, N warnings" on summary line; mypy: "Found N errors"
        local summary_errors
        summary_errors=$(printf "%s\n" "$tc_output" | grep -oE '[0-9]+ error' | tail -1 | grep -oE '[0-9]+')
        error_count=${summary_errors:-0}
        ;;
      go)
        # go vet outputs one line per issue
        error_count=$(printf "%s\n" "$tc_output" | grep -cE '\.go:[0-9]+' 2>/dev/null) || error_count=0
        ;;
      *)
        # Fallback: count lines with "error" (case insensitive) but exclude "0 errors"
        error_count=$(printf "%s\n" "$tc_output" | grep -ciE 'error[^s]' 2>/dev/null) || error_count=0
        ;;
    esac
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
    local updated
    updated=$(jq --argjson count "$error_count" '.execution = (.execution // {}) | .execution.baselineTypecheckErrors = $count' "$json_path" 2>/dev/null)
    if [[ -n "$updated" ]]; then
      write_quantum_json "$json_path" "$updated" || true
    fi
    return 0
  fi

  # Compare against baseline
  if [[ "$error_count" -gt "$baseline" ]]; then
    printf "[TYPECHECK] FAIL: %d errors > baseline %d — reverting merge\n" "$error_count" "$baseline"
    # Stash any dirty tracked files before reverting (e.g., quantum.json updates)
    local stashed=false
    if git -C "$repo_root" status --porcelain 2>/dev/null | grep -q .; then
      git -C "$repo_root" stash push -m "ql-typecheck-revert" -q 2>/dev/null && stashed=true
    fi
    # Verify HEAD is a merge commit before attempting -m 1 revert
    local parent_count
    parent_count=$(git -C "$repo_root" cat-file -p HEAD 2>/dev/null | grep -c '^parent ' || echo "0")
    if [[ "$parent_count" -lt 2 ]]; then
      printf "[TYPECHECK] CRITICAL: HEAD is not a merge commit (parents: %d) — cannot revert with -m 1\n" "$parent_count" >&2
      [[ "$stashed" == "true" ]] && { git -C "$repo_root" stash pop -q 2>/dev/null || true; }
      return 1
    fi
    if ! git -C "$repo_root" revert -m 1 --no-edit HEAD 2>/dev/null; then
      printf "[TYPECHECK] CRITICAL: revert failed — manual intervention required\n" >&2
    fi
    [[ "$stashed" == "true" ]] && { git -C "$repo_root" stash pop -q 2>/dev/null || true; }
    return 1
  fi

  printf "[TYPECHECK] PASS: %d errors <= baseline %d\n" "$error_count" "$baseline"
  return 0
}
