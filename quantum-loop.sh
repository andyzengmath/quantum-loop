#!/usr/bin/env bash
set -euo pipefail

# =============================================================================
# quantum-loop.sh -- Autonomous development loop with DAG-based story selection,
# two-stage review gates, and structured error recovery.
# Supports parallel execution via DAG-driven worktree agents.
#
# Usage:
#   ./quantum-loop.sh [OPTIONS]
#
# Options:
#   --max-iterations N   Maximum iterations before stopping (default: 20)
#   --max-retries N      Max retry attempts per story (default: 3)
#   --tool TOOL          AI tool to use: "claude" (default) or "amp"
#   --parallel           Enable parallel execution of independent stories
#   --max-parallel N     Maximum concurrent agents in parallel mode (default: 4)
#   --help               Show this help message
#
# Prerequisites:
#   - quantum.json must exist in the current directory (run /quantum-loop:plan first)
#   - jq must be installed
#   - claude or amp CLI must be installed
# =============================================================================

# Defaults
MAX_ITERATIONS=20
MAX_RETRIES=3
TOOL="claude"
PARALLEL_MODE=false
MAX_PARALLEL=4
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

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

# Validate tool
if [[ "$TOOL" != "claude" && "$TOOL" != "amp" ]]; then
  printf "ERROR: --tool must be 'claude' or 'amp'. Got: %s\n" "$TOOL"
  exit 1
fi

# Validate dependencies
if ! command -v jq &>/dev/null; then
  printf "ERROR: jq is required. Install it: https://jqlang.github.io/jq/download/\n"
  exit 1
fi

if ! command -v "$TOOL" &>/dev/null; then
  printf "ERROR: %s CLI not found. Please install it first.\n" "$TOOL"
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
if [[ "$PARALLEL_MODE" == "true" ]]; then
  source "$SCRIPT_DIR/lib/dag-query.sh" || { printf "ERROR: lib/dag-query.sh not found\n"; exit 1; }
  source "$SCRIPT_DIR/lib/worktree.sh" || { printf "ERROR: lib/worktree.sh not found\n"; exit 1; }
  source "$SCRIPT_DIR/lib/spawn.sh" || { printf "ERROR: lib/spawn.sh not found\n"; exit 1; }
  source "$SCRIPT_DIR/lib/monitor.sh" || { printf "ERROR: lib/monitor.sh not found\n"; exit 1; }
  source "$SCRIPT_DIR/lib/crash-recovery.sh" || { printf "ERROR: lib/crash-recovery.sh not found\n"; exit 1; }
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
# Main header
# =============================================================================

printf "===========================================\n"
printf "  Quantum-Loop Autonomous Development\n"
printf "===========================================\n"
printf "  Branch:      %s\n" "$BRANCH"
printf "  Tool:        %s\n" "$TOOL"
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
  # Crash recovery on startup
  REPO_ROOT="$SCRIPT_DIR"
  recover_orphaned_worktrees "$REPO_ROOT/quantum.json" "$REPO_ROOT" || true
  cleanup_stale_tmp "$REPO_ROOT/quantum.json" || true

  WAVE=0

  for ITERATION in $(seq 1 "$MAX_ITERATIONS"); do
    printf "\n=== Iteration %d / %d ===\n\n" "$ITERATION" "$MAX_ITERATIONS"

    # Get executable stories from DAG
    EXECUTABLE=$(get_executable_stories "$REPO_ROOT/quantum.json")

    if [[ "$EXECUTABLE" == "COMPLETE" ]]; then
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
      jq --arg id "$SID" '
        .stories |= map(if .id == $id then .status = "in_progress" else . end)
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
          kill_agent_process "$PID"
          printf "[TIMEOUT] %s\n" "$SID"
          # Mark failed with phase timeout
          jq --arg id "$SID" '
            .stories |= map(if .id == $id then
              .status = "failed" |
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
            wait "$PID" 2>/dev/null || true
            WT_BRANCH="ql-wt/${SID}"
            if merge_worktree_branch "$REPO_ROOT" "$WT_BRANCH"; then
              printf "[PASSED] %s\n" "$SID"
              jq --arg id "$SID" --argjson wave "$WAVE" '
                .stories |= map(if .id == $id then .status = "passed" else . end)
              ' "$REPO_ROOT/quantum.json" > "$REPO_ROOT/quantum.json.tmp" \
                && mv "$REPO_ROOT/quantum.json.tmp" "$REPO_ROOT/quantum.json"
            else
              printf "[CONFLICT] %s - merge conflict\n" "$SID"
              jq --arg id "$SID" '
                .stories |= map(if .id == $id then
                  .status = "failed" |
                  .retries.attempts += 1 |
                  .retries.failureLog += [{"phase": "merge_conflict", "timestamp": (now | todate)}]
                else . end)
              ' "$REPO_ROOT/quantum.json" > "$REPO_ROOT/quantum.json.tmp" \
                && mv "$REPO_ROOT/quantum.json.tmp" "$REPO_ROOT/quantum.json"
            fi
            remove_worktree "$SID" "$REPO_ROOT" || true
            clear_story_worktree "$REPO_ROOT/quantum.json" "$SID" || true
            local_completed+=("$idx")
            ;;
          STORY_FAILED)
            wait "$PID" 2>/dev/null || true
            printf "[FAILED] %s\n" "$SID"
            jq --arg id "$SID" '
              .stories |= map(if .id == $id then
                .status = "failed" |
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
            jq --arg id "$NSID" '
              .stories |= map(if .id == $id then .status = "in_progress" else . end)
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

  if [[ -z "$STORY_ID" || "$STORY_ID" == "null" ]]; then
    # Check if all stories are passed
    ALL_PASSED=$(jq '[.stories[].status] | all(. == "passed")' quantum.json)
    if [[ "$ALL_PASSED" == "true" ]]; then
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

  # Mark story as in_progress
  jq --arg id "$STORY_ID" '
    .stories |= map(if .id == $id then .status = "in_progress" else . end) |
    .updatedAt = (now | todate)
  ' quantum.json > quantum.json.tmp && mv quantum.json.tmp quantum.json

  # -------------------------------------------------------------------------
  # Spawn fresh AI instance
  # -------------------------------------------------------------------------

  PROMPT_FILE="$SCRIPT_DIR/CLAUDE.md"
  if [[ "$TOOL" == "amp" && -f "$SCRIPT_DIR/prompt.md" ]]; then
    PROMPT_FILE="$SCRIPT_DIR/prompt.md"
  fi

  printf "Spawning %s for story %s...\n" "$TOOL" "$STORY_ID"

  if [[ "$TOOL" == "claude" ]]; then
    OUTPUT=$(claude --dangerously-skip-permissions --print \
      -p "$(cat "$PROMPT_FILE")" \
      -- "Implement story $STORY_ID from quantum.json. This is iteration $ITERATION." 2>&1) || true
  else
    OUTPUT=$(printf "%s\n\nImplement story %s from quantum.json. This is iteration %d." \
      "$(cat "$PROMPT_FILE")" "$STORY_ID" "$ITERATION" | amp 2>&1) || true
  fi

  # -------------------------------------------------------------------------
  # Process output
  # -------------------------------------------------------------------------

  if echo "$OUTPUT" | grep -q "<quantum>COMPLETE</quantum>"; then
    printf "\n===========================================\n"
    printf "  <quantum>COMPLETE</quantum>\n"
    printf "  All stories passed! Feature is done.\n"
    printf "===========================================\n"
    print_summary_table
    exit 0

  elif echo "$OUTPUT" | grep -q "<quantum>STORY_PASSED</quantum>"; then
    printf "Story %s PASSED. Continuing to next story...\n" "$STORY_ID"

  elif echo "$OUTPUT" | grep -q "<quantum>STORY_FAILED</quantum>"; then
    printf "Story %s FAILED (attempt %d). Will retry if attempts remain.\n" "$STORY_ID" "$((STORY_ATTEMPT + 1))"

  elif echo "$OUTPUT" | grep -q "<quantum>BLOCKED</quantum>"; then
    printf "\n===========================================\n"
    printf "  <quantum>BLOCKED</quantum>\n"
    printf "  Agent reports no executable stories.\n"
    printf "===========================================\n"
    print_summary_table
    exit 1

  else
    printf "WARNING: No recognized signal in output. Story may not have completed cleanly.\n"
    printf "Last 10 lines of output:\n"
    echo "$OUTPUT" | tail -10
  fi

  # Brief pause between iterations
  sleep 2
done

printf "\n===========================================\n"
printf "  <quantum>MAX_ITERATIONS</quantum>\n"
printf "  Reached maximum of %d iterations.\n" "$MAX_ITERATIONS"
printf "===========================================\n"
print_summary_table
exit 2
