#!/usr/bin/env bash
# lib/parallel-mode.sh -- quantum-loop parallel-mode dispatch (v0.10.0 / US-001 decomposition).
#
# Extracted from quantum-loop.sh:394-784 in v0.10.0 / US-001 (the last block-
# extraction completing the v0.9.5 decomposition arc). Source from
# quantum-loop.sh AFTER lib/json-atomic.sh (uses json_atomic_update_args) and
# AFTER lib/loop-helpers.sh (uses emit_terminal_signal, print_summary_table,
# detect_stale_stories, validate_and_run_test_cmd, final_verification_sweep).
#
# Functions exported to caller's scope:
#   run_parallel_mode  -- main parallel-mode dispatch loop. Calls exit 0/1/2.
#                         No return-to-caller path; caller invokes guarded by
#                         `if [[ "$PARALLEL_MODE" == "true" ]]`.
#
# Required globals (set in quantum-loop.sh before sourcing):
#   - $REPO_ROOT (string; absolute path to repo root)
#   - $BRANCH (string; current cycle branch)
#   - $MAX_PARALLEL (int; concurrent agent ceiling)
#   - $MAX_ITERATIONS (int; outer loop ceiling)
#   - $MAX_RETRIES (int; per-story retry ceiling -- consumed by helpers)
#   - $RUNNER_NAME, $RUNNER_BINARY, $RUNNER_TIER, $RUNNER_INSTRUCTION_NATIVE
#   - $DEFAULT_AGENT_TIMEOUT (seconds; consumed by check_agent_timeout)
#   - $STALE_TIMEOUT (consumed by detect_stale_stories)
#   - $LAST_BRANCH_FILE (path; previously set; not directly used here)
#   - $PARALLEL_MODE (must be "true" to enter -- caller-guarded)
#
# Required helpers (sourced before this lib):
#   - lib/dag-query.sh:  get_executable_stories, filter_file_conflicts
#   - lib/worktree.sh:   create_worktree, remove_worktree
#   - lib/spawn.sh:      spawn_autonomous, merge_worktree_branch
#   - lib/monitor.sh:    check_agent_status, check_agent_timeout, kill_agent_process
#   - lib/resilience.sh: recover_orphaned_worktrees
#   - lib/json-atomic.sh: json_atomic_update_args, set_story_worktree,
#                         clear_story_worktree, update_execution_field,
#                         cleanup_stale_tmp
#   - lib/loop-helpers.sh: emit_terminal_signal, print_summary_table,
#                          detect_stale_stories, validate_and_run_test_cmd,
#                          final_verification_sweep
#   - lib/reaper.sh (optional, Git Bash): reap_agent, reap_orphans
#
# Library contract: no shell flags at source time; parent's set -euo pipefail
# carries through naturally.

# Source-guard
if [[ -n "${_QL_PARALLEL_MODE_LIB:-}" ]]; then
  return 0 2>/dev/null || true
fi
_QL_PARALLEL_MODE_LIB=1

# =============================================================================
# Parallel execution mode
# =============================================================================
run_parallel_mode() {
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
      emit_terminal_signal "COMPLETE" "All stories passed! Feature is done."
      print_summary_table
      exit 0
    fi

    if [[ "$EXECUTABLE" == "BLOCKED" ]]; then
      emit_terminal_signal "BLOCKED" "No executable stories remain."
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
      json_atomic_update_args '
        .stories |= map(if .id == $id then .status = "in_progress" | .startedAt = $now else . end)
      ' "$REPO_ROOT/quantum.json" --arg id "$SID" --arg now "$(date -u +'%Y-%m-%dT%H:%M:%SZ')"

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
          json_atomic_update_args '
            .stories |= map(if .id == $id then
              .status = "failed" |
              .startedAt = null |
              .retries.attempts += 1 |
              .retries.failureLog += [{"phase": "timeout", "timestamp": (now | todate)}]
            else . end)
          ' "$REPO_ROOT/quantum.json" --arg id "$SID"
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
                  json_atomic_update_args '
                    .stories |= map(if .id == $id then
                      .status = "failed" |
                      .startedAt = null |
                      .retries.attempts += 1 |
                      .retries.failureLog += [{"phase": "merge_regression", "timestamp": (now | todate)}]
                    else . end)
                  ' "$REPO_ROOT/quantum.json" --arg id "$SID"
                  STATUS_MERGE=1
                fi
              fi
              if [[ "$STATUS_MERGE" -eq 0 ]]; then
                printf "[PASSED] %s\n" "$SID"
                json_atomic_update_args '
                  .stories |= map(if .id == $id then .status = "passed" | .startedAt = null else . end)
                ' "$REPO_ROOT/quantum.json" --arg id "$SID"
              fi
            else
              CONFLICT_FILES="${MERGE_OUTPUT:-unknown}"
              STATUS_MERGE=1
              printf "[CONFLICT] %s - merge conflict in: %s\n" "$SID" "$CONFLICT_FILES"
              printf "[INFO] Branch %s preserved for manual resolution\n" "$WT_BRANCH"
              json_atomic_update_args '
                .stories |= map(if .id == $id then
                  .status = "failed" |
                  .startedAt = null |
                  .retries.attempts += 1 |
                  .retries.failureLog += [{"phase": "merge_conflict", "files": $files, "timestamp": (now | todate)}]
                else . end)
              ' "$REPO_ROOT/quantum.json" --arg id "$SID" --arg files "$CONFLICT_FILES"
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
            json_atomic_update_args '
              .stories |= map(if .id == $id then
                .status = "failed" |
                .startedAt = null |
                .retries.attempts += 1 |
                .retries.failureLog += [{"phase": "agent_failed", "timestamp": (now | todate)}]
              else . end)
            ' "$REPO_ROOT/quantum.json" --arg id "$SID"
            remove_worktree "$SID" "$REPO_ROOT" || true
            clear_story_worktree "$REPO_ROOT/quantum.json" "$SID" || true
            local_completed+=("$idx")
            ;;
          CRASH)
            printf "[CRASH] %s\n" "$SID"
            json_atomic_update_args '
              .stories |= map(if .id == $id then
                .status = "failed" |
                .startedAt = null |
                .retries.attempts += 1 |
                .retries.failureLog += [{"phase": "crash", "timestamp": (now | todate)}]
              else . end)
            ' "$REPO_ROOT/quantum.json" --arg id "$SID"
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
            json_atomic_update_args '
              .stories |= map(if .id == $id then .status = "in_progress" | .startedAt = $now else . end)
            ' "$REPO_ROOT/quantum.json" --arg id "$NSID" --arg now "$(date -u +'%Y-%m-%dT%H:%M:%SZ')"

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

  emit_terminal_signal "MAX_ITERATIONS" \
    "$(printf 'Reached maximum of %d iterations.' "$MAX_ITERATIONS")"
  print_summary_table
  exit 2
}
