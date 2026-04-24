#!/usr/bin/env bash
set -euo pipefail

# =============================================================================
# quantum-loop.sh -- PLUGIN-LEVEL autonomous development loop.
#
# THIS SCRIPT IS FOR THE QUANTUM-LOOP PLUGIN REPO ITSELF.
# It requires lib/*.sh modules and jq. It operates at the STORY level
# (one story per agent invocation) and uses CLAUDE.md as the agent prompt.
#
# FOR USER PROJECTS: Use templates/quantum-loop.sh instead.
# That script is self-contained (no lib/ dependency), uses node for JSON,
# and operates at the TASK level. Download it via:
#   curl -sO https://raw.githubusercontent.com/andyzengmath/quantum-loop/main/templates/quantum-loop.sh
#
# Features: DAG-based story selection, two-stage review gates,
# structured error recovery, parallel execution via worktree agents.
#
# Usage:
#   ./quantum-loop.sh [OPTIONS]
#
# Options:
#   --max-iterations N   Maximum iterations before stopping (default: 20)
#   --max-retries N      Max retry attempts per story (default: 3)
#   --tool TOOL          AI tool to use (default: "claude"). Any runner in runners/*.json.
#   --parallel           Enable parallel execution of independent stories
#   --max-parallel N     Maximum concurrent agents in parallel mode (default: 4)
#   --help               Show this help message
#
# Prerequisites:
#   - quantum.json must exist in the current directory (run /quantum-loop:plan first)
#   - jq must be installed
#   - The selected runner CLI must be installed (see runners/*.json)
# =============================================================================

# Defaults
MAX_ITERATIONS=20
MAX_RETRIES=3
TOOL="claude"
PARALLEL_MODE=false
MAX_PARALLEL=4
STALE_TIMEOUT=20
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# =============================================================================
# --audit flag support (Phase 44 / US-001 -- US-004). Read-only repo-hygiene
# check per idea-stage/IDEA_REPORT.md §6 measurement plan.
# Helpers live near the top so the pre-arg-loop audit shortcut can call them.
# =============================================================================

# _audit_format_row PIPE_ROW
# Takes one pipe-delimited string "name|value|target|status|drill" and emits
# formatted output on stdout. Single line for OK, two lines for FAIL (main
# line + indented drill-down with └─ prefix). Column widths locked so CI
# scripts can grep reliably.
_audit_format_row() {
  local row="${1:-}"
  local name value target status drill
  IFS='|' read -r name value target status drill <<< "$row"
  # Main line: "<name>: <value> (target <target>) <status>"
  # Column widths: name: padded to 18, value+target padded to 30, status right.
  printf "%-18s %s (target %s) %6s\n" "${name}:" "$value" "$target" "$status"
  # Drill only when FAIL and non-empty drill
  if [[ "$status" == "FAIL" && -n "$drill" ]]; then
    printf "                   └─ %s\n" "$drill"
  fi
}

# do_audit
# Driver for --audit. US-001 ships a stub that emits header + one placeholder
# row + Summary. US-002 and US-003 extend it with real metric helpers.
do_audit() {
  printf "=== Quantum-loop audit ===\n"
  local -a ROWS=()
  # US-001 placeholder row (removed in US-002 T-004 once real helpers land):
  ROWS+=("placeholder|0|0|OK|")
  local any_fail=0 ok_count=0 total=0
  local row
  for row in "${ROWS[@]}"; do
    _audit_format_row "$row"
    total=$((total + 1))
    if [[ "$row" == *"|FAIL|"* ]]; then
      any_fail=1
    else
      ok_count=$((ok_count + 1))
    fi
  done
  printf "\nSummary: %d/%d metrics on target.\n" "$ok_count" "$total"
  return "$any_fail"
}

# Test-mode guard (Phase 44 / US-001): when QL_AUDIT_TEST_MODE=1 is set,
# sourcing this file returns here so unit tests can reach the audit
# helpers defined above without triggering the main arg-loop or any
# state-mutating code below.
[[ "${QL_AUDIT_TEST_MODE:-0}" == "1" ]] && return 0 2>/dev/null

# Pre-arg-loop audit shortcut: --audit is exclusive and takes no other args.
# Must run BEFORE the normal arg-parsing loop so any stray sibling flag
# (--audit --parallel) is rejected with exit 2.
if [[ " $* " == *" --audit "* ]]; then
  if [[ "$#" -ne 1 ]]; then
    printf "Error: --audit is exclusive and takes no other arguments\n" >&2
    exit 2
  fi
  do_audit
  exit $?
fi

# Parse arguments
while [[ $# -gt 0 ]]; do
  case $1 in
    --max-iterations)
      MAX_ITERATIONS="$2"
      shift 2
      ;;
    --max-retries)
      MAX_RETRIES="$2"
      shift 2
      ;;
    --tool)
      TOOL="$2"
      shift 2
      ;;
    --parallel)
      PARALLEL_MODE=true
      shift
      ;;
    --max-parallel)
      MAX_PARALLEL="$2"
      shift 2
      ;;
    --stale-timeout)
      STALE_TIMEOUT="$2"
      shift 2
      ;;
    --non-interactive)
      NON_INTERACTIVE=true
      shift
      ;;
    --help)
      head -24 "$0" | tail -19
      exit 0
      ;;
    *)
      printf "Unknown option: %s\n" "$1"
      exit 1
      ;;
  esac
done

# Validate dependencies
if ! command -v jq &>/dev/null; then
  printf "ERROR: jq is required. Install it: https://jqlang.github.io/jq/download/\n"
  exit 1
fi

# Validate quantum.json
if [[ ! -f quantum.json ]]; then
  printf "ERROR: quantum.json not found. Run /quantum-loop:plan first to create it.\n"
  exit 1
fi

# Source library functions
source "$SCRIPT_DIR/lib/common.sh" || { printf "ERROR: lib/common.sh not found\n"; exit 1; }
source "$SCRIPT_DIR/lib/json-atomic.sh" || { printf "ERROR: lib/json-atomic.sh not found\n"; exit 1; }
source "$SCRIPT_DIR/lib/runner.sh" || { printf "ERROR: lib/runner.sh not found\n"; exit 1; }

# Load runner manifest (validates tool name, binary existence, sets RUNNER_* vars)
runner_load "$TOOL" || exit 1
runner_ensure_instructions || true

# Experimental tier warning
if [[ "$RUNNER_TIER" == "experimental" && "${NON_INTERACTIVE:-}" != "true" ]]; then
  printf "\nWARNING: Runner '%s' is experimental (tier: %s).\n" "$RUNNER_NAME" "$RUNNER_TIER"
  printf "Experimental runners may not reliably emit quantum signals.\n"
  printf "Press Enter to continue or Ctrl-C to abort...\n"
  read -r
fi
if [[ "$PARALLEL_MODE" == "true" ]]; then
  source "$SCRIPT_DIR/lib/dag-query.sh" || { printf "ERROR: lib/dag-query.sh not found\n"; exit 1; }
  source "$SCRIPT_DIR/lib/worktree.sh" || { printf "ERROR: lib/worktree.sh not found\n"; exit 1; }
  source "$SCRIPT_DIR/lib/spawn.sh" || { printf "ERROR: lib/spawn.sh not found\n"; exit 1; }
  source "$SCRIPT_DIR/lib/monitor.sh" || { printf "ERROR: lib/monitor.sh not found\n"; exit 1; }
  source "$SCRIPT_DIR/lib/resilience.sh" || { printf "ERROR: lib/resilience.sh not found\n"; exit 1; }
fi

# =============================================================================
# Archive previous run if branch changed
# =============================================================================

BRANCH=$(jq -r '.branchName' quantum.json)
LAST_BRANCH_FILE=".last-ql-branch"

if [[ -f "$LAST_BRANCH_FILE" ]]; then
  LAST_BRANCH=$(cat "$LAST_BRANCH_FILE")
  if [[ "$LAST_BRANCH" != "$BRANCH" ]]; then
    ARCHIVE_DIR="archive/$(date +%Y-%m-%d)-${BRANCH//\//-}"
    printf "Branch changed from %s to %s\n" "$LAST_BRANCH" "$BRANCH"
    printf "Archiving previous run to %s\n" "$ARCHIVE_DIR"
    mkdir -p "$ARCHIVE_DIR"
    cp quantum.json "$ARCHIVE_DIR/quantum.json" 2>/dev/null || true
    printf "Archive complete.\n"
  fi
fi

printf "%s" "$BRANCH" > "$LAST_BRANCH_FILE"

# Update maxAttempts in quantum.json if different from default
jq --argjson max "$MAX_RETRIES" '
  .stories |= map(.retries.maxAttempts = $max)
' quantum.json > quantum.json.tmp && mv quantum.json.tmp quantum.json

# =============================================================================
# Summary table function
# =============================================================================

print_summary_table() {
  printf "\n"
  printf "Summary\n"
  printf "%-10s %-40s %-8s %-6s %-8s\n" "Story" "Title" "Status" "Wave" "Retries"
  printf "%-10s %-40s %-8s %-6s %-8s\n" "----------" "----------------------------------------" "--------" "------" "--------"
  jq -r '.stories[] | "\(.id)|\(.title)|\(.status)|\(.retries.attempts)/\(.retries.maxAttempts)"' quantum.json | \
  while IFS='|' read -r sid title status retries; do
    printf "%-10s %-40s %-8s %-6s %-8s\n" "$sid" "${title:0:40}" "$status" "-" "$retries"
  done
  printf "\n"

  local total passed failed
  total=$(jq '.stories | length' quantum.json)
  passed=$(jq '[.stories[] | select(.status == "passed")] | length' quantum.json)
  failed=$((total - passed))
  printf "Result: %d/%d stories passed\n" "$passed" "$total"
}

# =============================================================================
# Stale story detection
# =============================================================================

detect_stale_stories() {
  local threshold="${STALE_TIMEOUT:-20}"
  local now_epoch
  now_epoch=$(date +%s)

  # Find all in_progress stories with startedAt set
  local stale_ids
  stale_ids=$(jq -r --argjson threshold "$threshold" '
    .stories[] |
    select(.status == "in_progress" and .startedAt != null) |
    select(
      ((now | floor) - (.startedAt | fromdateiso8601)) > ($threshold * 60)
    ) |
    .id
  ' quantum.json 2>/dev/null) || return 0

  if [[ -z "$stale_ids" ]]; then
    return 0
  fi

  while IFS= read -r sid; do
    [[ -z "$sid" ]] && continue
    printf "[STALE] %s - resetting to failed (exceeded %d minute threshold)\n" "$sid" "$threshold"
    jq --arg id "$sid" --argjson threshold "$threshold" '
      .stories |= map(if .id == $id then
        .status = (if .retries.attempts + 1 >= .retries.maxAttempts then "blocked" else "failed" end) |
        .startedAt = null |
        .retries.attempts += 1 |
        .retries.failureLog += [{"phase": "stale_detection", "timestamp": (now | todate), "error": ("Story exceeded " + ($threshold | tostring) + " minute stale threshold")}]
      else . end)
    ' quantum.json > quantum.json.tmp && mv quantum.json.tmp quantum.json
  done <<< "$stale_ids"
}

# =============================================================================
# Safe test command execution (allowlist + metacharacter rejection)
# =============================================================================

# Allowlist of known-safe test command prefixes
ALLOWED_TEST_PREFIXES=("npm test" "npx jest" "npx vitest" "yarn test" "pnpm test" "python -m pytest" "pytest" "cargo test" "go test" "make test" "bash tests/" "shellcheck")

# validate_and_run_test_cmd(cmd, [work_dir])
# Validates a test command against the allowlist and rejects shell metacharacters.
# Executes via array splitting (no eval). Returns the command's exit code.
validate_and_run_test_cmd() {
  local cmd="$1"
  local work_dir="${2:-.}"

  if [[ -z "$cmd" ]]; then
    return 1
  fi

  # Reject shell metacharacters
  if [[ "$cmd" =~ [\;\|\&\$\`\(\)\>\<\!] ]] || [[ "$cmd" == *$'\n'* ]]; then
    printf "ERROR: Test command contains unsafe characters: %s\n" "$cmd" >&2
    return 1
  fi

  # Check allowlist
  local allowed=false
  for prefix in "${ALLOWED_TEST_PREFIXES[@]}"; do
    if [[ "$cmd" == "$prefix" || "$cmd" == "$prefix "* ]]; then
      allowed=true
      break
    fi
  done

  if [[ "$allowed" != "true" ]]; then
    printf "ERROR: Test command '%s' does not match any allowed prefix — refusing to execute\n" "$cmd" >&2
    return 1
  fi

  # Execute as array to prevent shell interpretation
  local -a cmd_array
  read -ra cmd_array <<< "$cmd"
  (cd "$work_dir" && "${cmd_array[@]}" >/dev/null 2>&1)
}

# =============================================================================
# Final verification sweep before declaring COMPLETE
# =============================================================================

final_verification_sweep() {
  printf "\n[FINAL SWEEP] Running test suite before declaring COMPLETE...\n"

  # Detect test command
  local TEST_CMD=""
  if [[ -f "package.json" ]]; then TEST_CMD="npm test"
  elif [[ -f "pyproject.toml" ]] || [[ -f "setup.py" ]]; then TEST_CMD="python -m pytest -x -q"
  elif [[ -f "Cargo.toml" ]]; then TEST_CMD="cargo test"
  elif [[ -f "go.mod" ]]; then TEST_CMD="go test ./..."
  fi

  if [[ -n "$TEST_CMD" ]]; then
    if validate_and_run_test_cmd "$TEST_CMD"; then
      printf "[FINAL SWEEP] Test suite passed.\n"
    else
      printf "[FINAL SWEEP] FAILED: test suite. Cannot declare COMPLETE.\n"
      print_summary_table
      exit 1
    fi
  else
    printf "[FINAL SWEEP] No test suite detected, skipping.\n"
  fi

  # Import smoke test (warning only)
  if [[ -f "package.json" ]]; then
    local entry
    entry=$(jq -r '.main // empty' package.json 2>/dev/null)
    if [[ -n "$entry" ]]; then
      if node -e "require('./$entry')" >/dev/null 2>&1; then
        printf "[FINAL SWEEP] Import smoke test passed.\n"
      else
        printf "[FINAL SWEEP] WARNING: Import smoke test failed for %s (non-blocking).\n" "$entry"
      fi
    fi
  elif [[ -f "go.mod" ]]; then
    if go build ./... >/dev/null 2>&1; then
      printf "[FINAL SWEEP] Go build passed.\n"
    else
      printf "[FINAL SWEEP] WARNING: go build failed (non-blocking).\n"
    fi
  fi
}

# =============================================================================
# Generate execution observations document
# =============================================================================

generate_observations() {
  local branch
  branch=$(jq -r '.branchName' quantum.json)
  local date_str
  date_str=$(date +%Y-%m-%d)
  local obs_file="docs/post-mortems/${date_str}-${branch//\//-}-observations.md"

  mkdir -p docs/post-mortems

  local total passed failed blocked
  total=$(jq '.stories | length' quantum.json)
  passed=$(jq '[.stories[] | select(.status == "passed")] | length' quantum.json)
  failed=$(jq '[.stories[] | select(.status == "failed")] | length' quantum.json)
  blocked=$(jq '[.stories[] | select(.status == "blocked")] | length' quantum.json)

  {
    printf "# Execution Observations: %s\n\n" "$branch"
    printf "**Date:** %s\n" "$date_str"
    printf "**Stories:** %d passed, %d failed, %d blocked (of %d total)\n" "$passed" "$failed" "$blocked" "$total"
    printf "**Mode:** %s\n\n" "$(if $PARALLEL_MODE; then echo 'parallel'; else echo 'sequential'; fi)"

    printf "## Failure Summary\n\n"
    local failures
    # Sanitize pipe characters in title so the markdown table stays aligned
    failures=$(jq -r '.stories[] | select(.status == "failed" or .status == "blocked") | "\(.id)|\(.title | gsub("\\|"; "/"))|\(.status)|\(.retries.attempts)/\(.retries.maxAttempts)"' quantum.json 2>/dev/null)
    if [[ -n "$failures" ]]; then
      printf "| Story | Title | Status | Retries |\n"
      printf "|-------|-------|--------|--------|\n"
      while IFS='|' read -r sid title status retries; do
        printf "| %s | %s | %s | %s |\n" "$sid" "${title:0:40}" "$status" "$retries"
      done <<< "$failures"
    else
      printf "No failures.\n"
    fi

    # Phase 6 / P1.7 — Progress Log table: one row per failed-story phase
    # so the learning loop has structured data (previously this block was
    # just an empty <details> block when .progress was []).
    printf "\n## Progress Log\n\n"
    local progress_rows
    progress_rows=$(jq -r '
      [
        (.stories[] | select(.retries.failureLog // [] | length > 0)
          | .id as $sid
          | (.retries.failureLog // [])[]
          | [ $sid,
              (.phase // "unknown"),
              ((.error // "") | gsub("\\|"; "/") | .[0:80]),
              "",
              "",
              "" ]
          | @tsv),
        (.progress // []
          | .[]
          | [ (.storyId // "(pipeline)"),
              (.action // "unknown"),
              ((.details // "") | gsub("\\|"; "/") | .[0:80]),
              "",
              "",
              (.learnings // "") ]
          | @tsv)
      ] | .[]
    ' quantum.json 2>/dev/null)
    if [[ -n "$progress_rows" ]]; then
      printf "| Story | Phase / Action | Error / Detail | Root cause | Fix applied | Lesson |\n"
      printf "|-------|----------------|----------------|-----------|-------------|--------|\n"
      while IFS=$'\t' read -r sid phase detail rc fix lesson; do
        [[ -z "$sid" && -z "$phase" ]] && continue
        printf "| %s | %s | %s | %s | %s | %s |\n" \
          "${sid:-(pipeline)}" "${phase:-unknown}" "${detail:-}" "${rc:-}" "${fix:-}" "${lesson:-}"
      done <<< "$progress_rows"
    else
      printf "_No failed / retried stories. Progress log is empty._\n"
    fi

    printf "\n## Raw Data\n\n"
    printf "<details>\n<summary>Progress JSON</summary>\n\n"
    printf '```json\n'
    jq '.progress' quantum.json
    printf '```\n\n'
    printf "</details>\n\n"

    printf "<details>\n<summary>Failure Logs</summary>\n\n"
    printf '```json\n'
    jq '[.stories[] | select(.retries.failureLog | length > 0) | {id, failureLog: .retries.failureLog}]' quantum.json
    printf '```\n\n'
    printf "</details>\n"
  } > "$obs_file"

  # Phase 6 / P1.7 — promote generalizable lessons from progress entries into
  # codebasePatterns so the next iteration inherits them.
  local new_patterns
  new_patterns=$(jq '[.progress // [] | .[] | select(.learnings? and (.learnings | length > 0)) | .learnings]' quantum.json 2>/dev/null)
  if [[ "$new_patterns" != "[]" && -n "$new_patterns" ]]; then
    local tmpfile
    tmpfile=$(mktemp 2>/dev/null || mktemp -t qlobs)
    jq --argjson newlessons "$new_patterns" '
      .codebasePatterns = ((.codebasePatterns // []) + $newlessons | unique)
    ' quantum.json > "$tmpfile" 2>/dev/null
    if [[ -s "$tmpfile" ]]; then
      mv "$tmpfile" quantum.json
      printf "[OBSERVATIONS] Promoted %s lessons into codebasePatterns.\n" \
        "$(echo "$new_patterns" | jq 'length')"
    else
      rm -f "$tmpfile"
    fi
  fi

  git add "$obs_file" && git commit -m "docs: execution observations for $branch" >/dev/null 2>&1 || true
  printf "[OBSERVATIONS] Generated %s\n" "$obs_file"

  # Check if observations contain issues worth reporting
  local has_blocked has_recurring
  has_blocked=$(jq '[.stories[] | select(.status == "blocked" or .status == "failed")] | length' quantum.json)
  has_recurring=$(jq '[.stories[] | (.retries.failureLog // [])[] | .phase] | group_by(.) | map(select(length > 1)) | length' quantum.json 2>/dev/null || echo "0")

  if [[ "$has_blocked" -gt 0 || "$has_recurring" -gt 0 ]]; then
    # Skip prompt if non-interactive
    if [[ ! -t 0 ]] || [[ "${NON_INTERACTIVE:-false}" == "true" ]]; then
      printf "[OBSERVATIONS] Skipping GitHub issue prompt (non-interactive mode).\n"
      return
    fi

    printf "\n[OBSERVATIONS] Found issues worth reporting (%d blocked/failed, %d recurring patterns).\n" "$has_blocked" "$has_recurring"
    read -rp "File observations as GitHub issue on quantum-loop? [y/N] " response
    if [[ "$response" =~ ^[Yy]$ ]]; then
      if command -v gh >/dev/null 2>&1; then
        gh issue create --repo andyzengmath/quantum-loop \
          --title "Execution observations: $branch ($date_str)" \
          --body "$(cat "$obs_file")" \
          --label "execution-feedback" 2>/dev/null && \
          printf "[OBSERVATIONS] GitHub issue filed.\n" || \
          printf "[OBSERVATIONS] Failed to file GitHub issue (gh error). Local doc is available.\n"
      else
        printf "[OBSERVATIONS] gh CLI not found. Local doc is available at %s\n" "$obs_file"
      fi
    fi
  fi
}

# =============================================================================
# Main header
# =============================================================================

printf "===========================================\n"
printf "  Quantum-Loop Autonomous Development\n"
printf "===========================================\n"
printf "  Branch:      %s\n" "$BRANCH"
printf "  Runner:      %s (%s)\n" "$RUNNER_NAME" "$RUNNER_BINARY"
printf "  Tier:        %s\n" "$RUNNER_TIER"
printf "  Instruction: %s\n" "$RUNNER_INSTRUCTION_NATIVE"
printf "  Max Iter:    %s\n" "$MAX_ITERATIONS"
printf "  Max Retries: %s\n" "$MAX_RETRIES"
if [[ "$PARALLEL_MODE" == "true" ]]; then
  printf "  Mode:        Parallel (max %s concurrent)\n" "$MAX_PARALLEL"
else
  printf "  Mode:        Sequential\n"
fi
printf "===========================================\n\n"

# =============================================================================
# Parallel execution mode
# =============================================================================

if [[ "$PARALLEL_MODE" == "true" ]]; then
  # Phase 20 / P2.11 — platform-aware reaper. Load lib/reaper.sh so the trap
  # cascades through `taskkill //T //F` on Git Bash (where `kill` on a subshell
  # pid does NOT reach the native claude.exe child) and via `kill -TERM -pgid`
  # on POSIX where available. Durable pidfiles live in REAPER_PID_DIR so a
  # separate `ql-housekeep --reap-orphans` can clean up anything this trap
  # misses (terminal close, crash, Agent-tool grandchildren).
  REAPER_PID_DIR="${REAPER_PID_DIR:-.ql-agent-pids}"
  export REAPER_PID_DIR
  if [[ -f "$REPO_ROOT/lib/reaper.sh" ]]; then
    # shellcheck source=lib/reaper.sh
    source "$REPO_ROOT/lib/reaper.sh"
  fi

  declare -a AGENT_PIDS=()
  declare -a AGENT_STORIES=()
  cleanup_on_exit() {
    printf "\n[INTERRUPT] Cleaning up agents...\n"
    if type reap_agent &>/dev/null; then
      # Phase 21 fix: background each reap so the SIGTERM → grace → SIGKILL
      # escalation happens IN PARALLEL across all agents. Without this,
      # Ctrl+C blocks for N × REAPER_GRACE_SECS (20+ seconds with
      # MAX_PARALLEL=4). Waits ≤ 1 × REAPER_GRACE_SECS regardless of
      # agent count.
      local -a REAP_PIDS=()
      for sid in "${AGENT_STORIES[@]+"${AGENT_STORIES[@]}"}"; do
        reap_agent "$REAPER_PID_DIR" "$sid" &
        REAP_PIDS+=("$!")
      done
      for rp in "${REAP_PIDS[@]+"${REAP_PIDS[@]}"}"; do
        wait "$rp" 2>/dev/null || true
      done
    else
      # Fallback: legacy best-effort kill if reaper missing
      for pid in "${AGENT_PIDS[@]+"${AGENT_PIDS[@]}"}"; do
        kill "$pid" 2>/dev/null || true
      done
      for pid in "${AGENT_PIDS[@]+"${AGENT_PIDS[@]}"}"; do
        wait "$pid" 2>/dev/null || true
      done
    fi
    exit 130
  }
  trap cleanup_on_exit INT TERM

  # Crash recovery on startup
  REPO_ROOT="$(pwd)"
  recover_orphaned_worktrees "$REPO_ROOT/quantum.json" "$REPO_ROOT" || true
  cleanup_stale_tmp "$REPO_ROOT/quantum.json" || true
  # Phase 20 / P2.11 — reap any claude processes left by a prior crashed run
  # (their pidfiles will be in REAPER_PID_DIR with start_epoch older than
  # REAPER_STALE_SECS, default 1h). No-op if reaper not loaded.
  if type reap_orphans &>/dev/null; then
    REAPED=$(reap_orphans "$REPO_ROOT/$REAPER_PID_DIR" 2>/dev/null || echo 0)
    if [[ -n "$REAPED" && "$REAPED" != "0" ]]; then
      printf "[REAPER] reaped %s orphan agent(s) from prior run\n" "$REAPED"
    fi
  fi

  WAVE=0

  for ITERATION in $(seq 1 "$MAX_ITERATIONS"); do
    printf "\n=== Iteration %d / %d ===\n\n" "$ITERATION" "$MAX_ITERATIONS"

    # Detect stale stories before DAG query
    detect_stale_stories

    # Get executable stories from DAG
    EXECUTABLE=$(get_executable_stories "$REPO_ROOT/quantum.json")

    if [[ "$EXECUTABLE" == "COMPLETE" ]]; then
      final_verification_sweep
      printf "\n===========================================\n"
      printf "  <quantum>COMPLETE</quantum>\n"
      printf "  All stories passed! Feature is done.\n"
      printf "===========================================\n"
      print_summary_table
      exit 0
    fi

    if [[ "$EXECUTABLE" == "BLOCKED" ]]; then
      printf "\n===========================================\n"
      printf "  <quantum>BLOCKED</quantum>\n"
      printf "  No executable stories remain.\n"
      printf "===========================================\n"
      print_summary_table
      exit 1
    fi

    if [[ -z "$EXECUTABLE" ]]; then
      printf "WARNING: No executable stories found\n"
      print_summary_table
      exit 1
    fi

    # Filter out stories that share files with higher-priority stories in this wave
    EXECUTABLE=$(filter_file_conflicts "$REPO_ROOT/quantum.json" "$EXECUTABLE")

    # Count executable stories
    EXEC_COUNT=$(echo "$EXECUTABLE" | jq '. | length')
    WAVE=$((WAVE + 1))

    # Setup execution metadata
    update_execution_field "$REPO_ROOT/quantum.json" "parallel" "$MAX_PARALLEL" "$WAVE" || true

    # Arrays to track spawned agents
    declare -a AGENT_PIDS=()
    declare -a AGENT_STORIES=()
    declare -a AGENT_WORKTREES=()
    declare -a AGENT_START_TIMES=()

    # Spawn agents for each executable story (up to MAX_PARALLEL)
    SPAWN_COUNT=0
    for i in $(seq 0 $((EXEC_COUNT - 1))); do
      if [[ "$SPAWN_COUNT" -ge "$MAX_PARALLEL" ]]; then
        break
      fi

      SID=$(echo "$EXECUTABLE" | jq -r ".[$i]")
      STITLE=$(jq -r --arg id "$SID" '.stories[] | select(.id == $id) | .title' "$REPO_ROOT/quantum.json")

      # Create worktree
      WT_PATH="$REPO_ROOT/.ql-wt/$SID"
      if ! create_worktree "$SID" "$BRANCH" "$REPO_ROOT"; then
        printf "[ERROR] Failed to create worktree for %s\n" "$SID"
        continue
      fi

      # Update quantum.json
      set_story_worktree "$REPO_ROOT/quantum.json" "$SID" ".ql-wt/$SID" || true
      jq --arg id "$SID" --arg now "$(date -u +'%Y-%m-%dT%H:%M:%SZ')" '
        .stories |= map(if .id == $id then .status = "in_progress" | .startedAt = $now else . end)
      ' "$REPO_ROOT/quantum.json" > "$REPO_ROOT/quantum.json.tmp" \
        && mv "$REPO_ROOT/quantum.json.tmp" "$REPO_ROOT/quantum.json"

      # Spawn agent
      PID_FILE=$(mktemp)
      spawn_autonomous "$SID" "$WT_PATH" > "$PID_FILE"
      AGENT_PID=$(cat "$PID_FILE")
      rm -f "$PID_FILE"

      AGENT_PIDS+=("$AGENT_PID")
      AGENT_STORIES+=("$SID")
      AGENT_WORKTREES+=("$WT_PATH")
      AGENT_START_TIMES+=("$(date +%s)")
      SPAWN_COUNT=$((SPAWN_COUNT + 1))

      printf "[SPAWNED] %s - %s (wave %d, PID %s)\n" "$SID" "$STITLE" "$WAVE" "$AGENT_PID"
    done

    if [[ "$SPAWN_COUNT" -eq 0 ]]; then
      printf "WARNING: No agents spawned this iteration\n"
      continue
    fi

    # Monitoring loop
    while [[ ${#AGENT_PIDS[@]} -gt 0 ]]; do
      sleep 5

      local_completed=()
      for idx in "${!AGENT_PIDS[@]}"; do
        PID="${AGENT_PIDS[$idx]}"
        SID="${AGENT_STORIES[$idx]}"
        WT="${AGENT_WORKTREES[$idx]}"
        START="${AGENT_START_TIMES[$idx]}"

        # Check timeout
        TIMED_OUT=$(check_agent_timeout "$START" "$DEFAULT_AGENT_TIMEOUT")
        if [[ "$TIMED_OUT" == "true" ]]; then
          # Phase 21 fix: on Git Bash, kill_agent_process sends SIGTERM
          # only to the MSYS wrapper PID — claude.exe survives. Prefer
          # reap_agent which does MSYS→winpid translation + taskkill //T
          # //F. This was the exact orphan bug PR #29 was filed for, but
          # the watchdog path wasn't migrated in the original commit.
          if type reap_agent &>/dev/null && [[ -n "${REAPER_PID_DIR:-}" ]]; then
            reap_agent "$REAPER_PID_DIR" "$SID" || true
          else
            kill_agent_process "$PID"
          fi
          printf "[TIMEOUT] %s\n" "$SID"
          # Mark failed with phase timeout
          jq --arg id "$SID" '
            .stories |= map(if .id == $id then
              .status = "failed" |
              .startedAt = null |
              .retries.attempts += 1 |
              .retries.failureLog += [{"phase": "timeout", "timestamp": (now | todate)}]
            else . end)
          ' "$REPO_ROOT/quantum.json" > "$REPO_ROOT/quantum.json.tmp" \
            && mv "$REPO_ROOT/quantum.json.tmp" "$REPO_ROOT/quantum.json"
          remove_worktree "$SID" "$REPO_ROOT" || true
          clear_story_worktree "$REPO_ROOT/quantum.json" "$SID" || true
          local_completed+=("$idx")
          continue
        fi

        # Check status
        STATUS=$(check_agent_status "$PID" "$WT")

        case "$STATUS" in
          RUNNING)
            ;;
          STORY_PASSED)
            # Give agent a few seconds to finish after signaling (#9: post-signal timeout)
            local wait_start
            wait_start=$(date +%s)
            while kill -0 "$PID" 2>/dev/null; do
              local wait_elapsed=$(( $(date +%s) - wait_start ))
              if [[ $wait_elapsed -ge 30 ]]; then
                kill "$PID" 2>/dev/null || true
                break
              fi
              sleep 1
            done
            wait "$PID" 2>/dev/null || true
            WT_BRANCH="ql-wt/${SID}"
            # Safety commit: ensure agent changes are committed before merge
            # Exclude junk files (#4) and quantum.json (#5)
            if git -C "$WT" status --porcelain 2>/dev/null | grep -q .; then
              git -C "$WT" add -A >/dev/null 2>&1 || true
              git -C "$WT" reset HEAD -- quantum.json .ql-agent-output.txt quantum.json.tmp >/dev/null 2>&1 || true
              git -C "$WT" checkout -- quantum.json >/dev/null 2>&1 || true
              if ! git -C "$WT" diff --cached --quiet 2>/dev/null; then
                git -C "$WT" commit -m "feat: ${SID} - auto-commit by orchestrator" >/dev/null 2>&1 || true
              fi
            fi
            local STATUS_MERGE=0
            # merge_worktree_branch outputs conflict file list on failure (before aborting)
            local MERGE_OUTPUT
            MERGE_OUTPUT=$(merge_worktree_branch "$REPO_ROOT" "$WT_BRANCH" 2>&1)
            if [[ $? -eq 0 ]]; then
              # Post-merge regression test: verify the merge didn't break anything
              # Detect test command from quantum.json or common patterns
              local TEST_CMD
              TEST_CMD=$(jq -r '.testCommand // empty' "$REPO_ROOT/quantum.json" 2>/dev/null)
              if [[ -z "$TEST_CMD" ]]; then
                # Auto-detect: try common test runners
                if [[ -f "$REPO_ROOT/package.json" ]]; then TEST_CMD="npm test"
                elif [[ -f "$REPO_ROOT/pyproject.toml" ]] || [[ -f "$REPO_ROOT/setup.py" ]]; then TEST_CMD="python -m pytest -x -q"
                elif [[ -f "$REPO_ROOT/Cargo.toml" ]]; then TEST_CMD="cargo test"
                fi
              fi
              if [[ -n "$TEST_CMD" ]]; then
                if ! validate_and_run_test_cmd "$TEST_CMD" "$REPO_ROOT"; then
                  printf "[REGRESSION] %s - tests fail after merge, reverting\n" "$SID"
                  git -C "$REPO_ROOT" revert -m 1 HEAD --no-edit >/dev/null 2>&1 || true
                  jq --arg id "$SID" '
                    .stories |= map(if .id == $id then
                      .status = "failed" |
                      .startedAt = null |
                      .retries.attempts += 1 |
                      .retries.failureLog += [{"phase": "merge_regression", "timestamp": (now | todate)}]
                    else . end)
                  ' "$REPO_ROOT/quantum.json" > "$REPO_ROOT/quantum.json.tmp" \
                    && mv "$REPO_ROOT/quantum.json.tmp" "$REPO_ROOT/quantum.json"
                  STATUS_MERGE=1
                fi
              fi
              if [[ "$STATUS_MERGE" -eq 0 ]]; then
                printf "[PASSED] %s\n" "$SID"
                jq --arg id "$SID" --argjson wave "$WAVE" '
                  .stories |= map(if .id == $id then .status = "passed" | .startedAt = null else . end)
                ' "$REPO_ROOT/quantum.json" > "$REPO_ROOT/quantum.json.tmp" \
                  && mv "$REPO_ROOT/quantum.json.tmp" "$REPO_ROOT/quantum.json"
              fi
            else
              CONFLICT_FILES="${MERGE_OUTPUT:-unknown}"
              STATUS_MERGE=1
              printf "[CONFLICT] %s - merge conflict in: %s\n" "$SID" "$CONFLICT_FILES"
              printf "[INFO] Branch %s preserved for manual resolution\n" "$WT_BRANCH"
              jq --arg id "$SID" --arg files "$CONFLICT_FILES" '
                .stories |= map(if .id == $id then
                  .status = "failed" |
                  .startedAt = null |
                  .retries.attempts += 1 |
                  .retries.failureLog += [{"phase": "merge_conflict", "files": $files, "timestamp": (now | todate)}]
                else . end)
              ' "$REPO_ROOT/quantum.json" > "$REPO_ROOT/quantum.json.tmp" \
                && mv "$REPO_ROOT/quantum.json.tmp" "$REPO_ROOT/quantum.json"
            fi
            # Only remove worktree dir, preserve branch on conflict for manual resolution (#3)
            if [[ "$STATUS_MERGE" == "0" ]]; then
              remove_worktree "$SID" "$REPO_ROOT" || true
            else
              # Remove worktree dir but keep the branch
              git -C "$REPO_ROOT" worktree remove --force ".ql-wt/$SID" 2>/dev/null || true
            fi
            clear_story_worktree "$REPO_ROOT/quantum.json" "$SID" || true
            local_completed+=("$idx")
            ;;
          STORY_FAILED)
            wait "$PID" 2>/dev/null || true
            printf "[FAILED] %s\n" "$SID"
            jq --arg id "$SID" '
              .stories |= map(if .id == $id then
                .status = "failed" |
                .startedAt = null |
                .retries.attempts += 1 |
                .retries.failureLog += [{"phase": "agent_failed", "timestamp": (now | todate)}]
              else . end)
            ' "$REPO_ROOT/quantum.json" > "$REPO_ROOT/quantum.json.tmp" \
              && mv "$REPO_ROOT/quantum.json.tmp" "$REPO_ROOT/quantum.json"
            remove_worktree "$SID" "$REPO_ROOT" || true
            clear_story_worktree "$REPO_ROOT/quantum.json" "$SID" || true
            local_completed+=("$idx")
            ;;
          CRASH)
            printf "[CRASH] %s\n" "$SID"
            jq --arg id "$SID" '
              .stories |= map(if .id == $id then
                .status = "failed" |
                .startedAt = null |
                .retries.attempts += 1 |
                .retries.failureLog += [{"phase": "crash", "timestamp": (now | todate)}]
              else . end)
            ' "$REPO_ROOT/quantum.json" > "$REPO_ROOT/quantum.json.tmp" \
              && mv "$REPO_ROOT/quantum.json.tmp" "$REPO_ROOT/quantum.json"
            remove_worktree "$SID" "$REPO_ROOT" || true
            clear_story_worktree "$REPO_ROOT/quantum.json" "$SID" || true
            local_completed+=("$idx")
            ;;
        esac
      done

      # Remove completed agents from tracking arrays (reverse order to preserve indices)
      for ((ci=${#local_completed[@]}-1; ci>=0; ci--)); do
        ridx="${local_completed[$ci]}"
        unset 'AGENT_PIDS[ridx]'
        unset 'AGENT_STORIES[ridx]'
        unset 'AGENT_WORKTREES[ridx]'
        unset 'AGENT_START_TIMES[ridx]'
      done
      # Re-index arrays
      AGENT_PIDS=("${AGENT_PIDS[@]+"${AGENT_PIDS[@]}"}")
      AGENT_STORIES=("${AGENT_STORIES[@]+"${AGENT_STORIES[@]}"}")
      AGENT_WORKTREES=("${AGENT_WORKTREES[@]+"${AGENT_WORKTREES[@]}"}")
      AGENT_START_TIMES=("${AGENT_START_TIMES[@]+"${AGENT_START_TIMES[@]}"}")

      # After completions, check if new stories are unblocked
      if [[ ${#local_completed[@]} -gt 0 && ${#AGENT_PIDS[@]} -lt $MAX_PARALLEL ]]; then
        NEW_EXEC=$(get_executable_stories "$REPO_ROOT/quantum.json")
        if [[ "$NEW_EXEC" != "COMPLETE" && "$NEW_EXEC" != "BLOCKED" && -n "$NEW_EXEC" ]]; then
          NEW_EXEC=$(filter_file_conflicts "$REPO_ROOT/quantum.json" "$NEW_EXEC")
          NEW_COUNT=$(echo "$NEW_EXEC" | jq '. | length')
          WAVE=$((WAVE + 1))
          for ni in $(seq 0 $((NEW_COUNT - 1))); do
            if [[ ${#AGENT_PIDS[@]} -ge $MAX_PARALLEL ]]; then
              break
            fi
            NSID=$(echo "$NEW_EXEC" | jq -r ".[$ni]")
            NSTITLE=$(jq -r --arg id "$NSID" '.stories[] | select(.id == $id) | .title' "$REPO_ROOT/quantum.json")

            NWT="$REPO_ROOT/.ql-wt/$NSID"
            if ! create_worktree "$NSID" "$BRANCH" "$REPO_ROOT"; then
              printf "[ERROR] Failed to create worktree for %s\n" "$NSID"
              continue
            fi

            set_story_worktree "$REPO_ROOT/quantum.json" "$NSID" ".ql-wt/$NSID" || true
            jq --arg id "$NSID" --arg now "$(date -u +'%Y-%m-%dT%H:%M:%SZ')" '
              .stories |= map(if .id == $id then .status = "in_progress" | .startedAt = $now else . end)
            ' "$REPO_ROOT/quantum.json" > "$REPO_ROOT/quantum.json.tmp" \
              && mv "$REPO_ROOT/quantum.json.tmp" "$REPO_ROOT/quantum.json"

            NPID_FILE=$(mktemp)
            spawn_autonomous "$NSID" "$NWT" > "$NPID_FILE"
            NAGENT_PID=$(cat "$NPID_FILE")
            rm -f "$NPID_FILE"

            AGENT_PIDS+=("$NAGENT_PID")
            AGENT_STORIES+=("$NSID")
            AGENT_WORKTREES+=("$NWT")
            AGENT_START_TIMES+=("$(date +%s)")

            printf "[SPAWNED] %s - %s (wave %d, PID %s)\n" "$NSID" "$NSTITLE" "$WAVE" "$NAGENT_PID"
          done
        fi
      fi
    done

    # Brief pause between iterations
    sleep 2
  done

  printf "\n===========================================\n"
  printf "  <quantum>MAX_ITERATIONS</quantum>\n"
  printf "  Reached maximum of %d iterations.\n" "$MAX_ITERATIONS"
  printf "===========================================\n"
  print_summary_table
  exit 2
fi

# =============================================================================
# Sequential execution mode (original behavior)
# =============================================================================

for ITERATION in $(seq 1 "$MAX_ITERATIONS"); do
  printf "\n=== Iteration %d / %d ===\n\n" "$ITERATION" "$MAX_ITERATIONS"

  # Detect stale stories before DAG query
  detect_stale_stories

  # -------------------------------------------------------------------------
  # Select next executable story from the dependency DAG
  # -------------------------------------------------------------------------

  STORY_ID=$(jq -r '
    .stories as $all |
    [.stories[] |
      select(
        (.status == "pending" or (.status == "failed" and .retries.attempts < .retries.maxAttempts)) and
        (if (.dependsOn | length) == 0 then true
         else [.dependsOn[] | . as $dep | $all | map(select(.id == $dep)) | .[0].status] | all(. == "passed")
         end)
      )
    ] |
    sort_by(.priority) |
    .[0].id // empty
  ' quantum.json)

  # Validate story ID format to prevent jq injection in downstream json_atomic_update calls
  if [[ -n "$STORY_ID" && "$STORY_ID" != "null" && ! "$STORY_ID" =~ ^[A-Za-z0-9_-]+$ ]]; then
    printf "ERROR: invalid story ID format: %s\n" "$STORY_ID" >&2
    exit 1
  fi

  if [[ -z "$STORY_ID" || "$STORY_ID" == "null" ]]; then
    # Check if all stories are passed
    ALL_PASSED=$(jq '[.stories[].status] | all(. == "passed")' quantum.json)
    if [[ "$ALL_PASSED" == "true" ]]; then
      final_verification_sweep
      printf "\n===========================================\n"
      printf "  <quantum>COMPLETE</quantum>\n"
      printf "  All stories passed! Feature is done.\n"
      printf "===========================================\n"
      print_summary_table
      exit 0
    else
      printf "\n===========================================\n"
      printf "  <quantum>BLOCKED</quantum>\n"
      printf "  No executable stories remain.\n"
      printf "===========================================\n"
      print_summary_table
      exit 1
    fi
  fi

  STORY_TITLE=$(jq -r --arg id "$STORY_ID" '.stories[] | select(.id == $id) | .title' quantum.json)
  STORY_ATTEMPT=$(jq -r --arg id "$STORY_ID" '.stories[] | select(.id == $id) | .retries.attempts' quantum.json)

  printf "Story:   %s - %s\n" "$STORY_ID" "$STORY_TITLE"
  printf "Attempt: %d\n" "$((STORY_ATTEMPT + 1))"
  printf "\n"

  # Mark story as in_progress and set startedAt atomically
  now=$(date -u +'%Y-%m-%dT%H:%M:%SZ')
  jq --arg id "$STORY_ID" --arg now "$now" '
    .stories |= map(if .id == $id then .status = "in_progress" | .startedAt = $now else . end) |
    .updatedAt = (now | todate)
  ' quantum.json > quantum.json.tmp && mv quantum.json.tmp quantum.json

  # -------------------------------------------------------------------------
  # Spawn fresh AI instance
  # -------------------------------------------------------------------------

  printf "Spawning %s for story %s...\n" "$RUNNER_NAME" "$STORY_ID"

  RUNNER_EXIT=0
  if [[ "$RUNNER_NAME" == "claude" ]]; then
    # Claude Code: preserve original command structure — CLAUDE.md via -p, story instruction via --
    PROMPT_FILE="$SCRIPT_DIR/CLAUDE.md"
    OUTPUT=$(claude --dangerously-skip-permissions --print \
      -p "$(cat "$PROMPT_FILE")" \
      -- "Implement story $STORY_ID from quantum.json. This is iteration $ITERATION." 2>&1) || RUNNER_EXIT=$?
  else
    # Non-Claude runners: use runner adapter with preamble injection
    AGENT_PROMPT="Implement story $STORY_ID from quantum.json. This is iteration $ITERATION."
    RUNNER_CMD=$(runner_build_cmd "$AGENT_PROMPT") || {
      printf "ERROR: runner_build_cmd failed for %s\n" "$RUNNER_NAME" >&2
      continue
    }
    OUTPUT=$(eval "$RUNNER_CMD" 2>&1) || RUNNER_EXIT=$?
  fi

  # -------------------------------------------------------------------------
  # Process output
  # -------------------------------------------------------------------------

  # Invoke post_output() hook if defined (for non-Claude runners with hooks)
  if [[ "$RUNNER_NAME" != "claude" ]]; then
    local hooks_dir="${SCRIPT_DIR}/runners/hooks"
    local hook_file="${hooks_dir}/${RUNNER_NAME}-hooks.sh"
    if [[ -f "$hook_file" ]]; then
      # shellcheck source=/dev/null
      source "$hook_file"
      if type post_output &>/dev/null; then
        post_output "$OUTPUT"
      fi
      unset -f post_output pre_spawn 2>/dev/null
    fi
    # Check if hook forced a signal override
    if [[ -n "${RUNNER_OVERRIDE_SIGNAL:-}" ]]; then
      SIGNAL_RESULT="$RUNNER_OVERRIDE_SIGNAL"
      SIGNAL_CONFIDENCE="hook"
      RUNNER_OVERRIDE_SIGNAL=""
    fi
  fi

  # Parse runner output for signals (uses heuristics if enabled for non-Claude runners)
  runner_parse_output "$OUTPUT" "$RUNNER_EXIT"

  case "$SIGNAL_RESULT" in
    COMPLETE)
      final_verification_sweep
      printf "\n===========================================\n"
      printf "  <quantum>COMPLETE</quantum>\n"
      printf "  All stories passed! Feature is done.\n"
      printf "===========================================\n"
      print_summary_table
      exit 0
      ;;
    STORY_PASSED)
      printf "Story %s PASSED. Continuing to next story...\n" "$STORY_ID"
      json_atomic_update ".stories |= map(if .id == \"$STORY_ID\" then .status = \"passed\" | .startedAt = null else . end)"
      ;;
    STORY_FAILED)
      printf "Story %s FAILED (attempt %d). Will retry if attempts remain.\n" "$STORY_ID" "$((STORY_ATTEMPT + 1))"
      json_atomic_update ".stories |= map(if .id == \"$STORY_ID\" then .status = \"failed\" | .startedAt = null | .retries.attempts += 1 | .retries.failureLog += [{\"phase\": \"agent_failed\", \"timestamp\": (now | todate)}] else . end)"
      ;;
    BLOCKED)
      json_atomic_update ".stories |= map(if .id == \"$STORY_ID\" then .startedAt = null else . end)"
      printf "\n===========================================\n"
      printf "  <quantum>BLOCKED</quantum>\n"
      printf "  Agent reports no executable stories.\n"
      printf "===========================================\n"
      print_summary_table
      exit 1
      ;;
    *)
      printf "WARNING: No recognized signal in output. Story may not have completed cleanly.\n"
      printf "Last 10 lines of output:\n"
      echo "$OUTPUT" | tail -10
      json_atomic_update ".stories |= map(if .id == \"$STORY_ID\" then .startedAt = null | .status = \"failed\" else . end)"
      ;;
  esac

  # Brief pause between iterations
  sleep 2
done

printf "\n===========================================\n"
printf "  <quantum>MAX_ITERATIONS</quantum>\n"
printf "  Reached maximum of %d iterations.\n" "$MAX_ITERATIONS"
printf "===========================================\n"
print_summary_table
generate_observations
exit 2
