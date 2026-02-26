#!/usr/bin/env bash
# quantum-loop.sh — Executes quantum.json tasks via Claude Code CLI
# Respects dependency DAG, runs independent tasks in parallel via git worktrees.
#
# Usage:
#   ./quantum-loop.sh [OPTIONS]
#
# Options:
#   --parallel           Enable parallel execution of independent tasks (default: sequential)
#   --max-parallel N     Max concurrent tasks (default: 4)
#   --max-iterations N   Max total tasks to execute (default: all)
#   --story STORY_ID     Only execute tasks from a specific story (e.g., A1)
#   --dry-run            Show execution plan without running anything
#   --skip-permissions   Add --dangerously-skip-permissions to Claude CLI calls
#   --model MODEL        Override model (default: uses Claude CLI default)
#   --verbose            Show full Claude output (default: summary only)
#   --plan FILE          Path to quantum.json (default: ./quantum.json)
#   --timeout SECS       Per-task timeout in seconds (default: 900 = 15 min)
#
# Requirements:
#   - claude CLI (Claude Code) installed and authenticated
#   - node/npm (for JSON processing)
#   - git (for worktree support in parallel mode)

# ─── Windows PATH fix (Git Bash doesn't inherit full Windows PATH) ───
export PATH="/c/Program Files/nodejs:/c/ProgramData/global-npm:$PATH"
set -euo pipefail

# ─── Defaults ───
PARALLEL=false
MAX_PARALLEL=4
MAX_ITERATIONS=999
STORY_FILTER=""
DRY_RUN=false
SKIP_PERMISSIONS=false
MODEL=""
VERBOSE=false
PLAN_FILE="./quantum.json"
LOG_DIR=".quantum-logs"
WORKTREE_DIR=".ql-wt"
TASK_TIMEOUT=900

# ─── Parse Args ───
while [[ $# -gt 0 ]]; do
  case "$1" in
    --parallel)       PARALLEL=true; shift ;;
    --max-parallel)   MAX_PARALLEL="$2"; shift 2 ;;
    --max-iterations) MAX_ITERATIONS="$2"; shift 2 ;;
    --story)          STORY_FILTER="$2"; shift 2 ;;
    --dry-run)        DRY_RUN=true; shift ;;
    --skip-permissions) SKIP_PERMISSIONS=true; shift ;;
    --model)          MODEL="$2"; shift 2 ;;
    --verbose)        VERBOSE=true; shift ;;
    --plan)           PLAN_FILE="$2"; shift 2 ;;
    --timeout)        TASK_TIMEOUT="$2"; shift 2 ;;
    -h|--help)
      head -24 "$0" | grep "^#" | sed 's/^# \?//'
      exit 0
      ;;
    *) echo "Unknown option: $1"; exit 1 ;;
  esac
done

# ─── Dependency Check ───
if ! command -v claude &>/dev/null; then
  echo "ERROR: 'claude' CLI not found. Install Claude Code first."
  exit 1
fi

if ! command -v node &>/dev/null; then
  echo "ERROR: 'node' not found. Required for JSON processing."
  exit 1
fi

if [[ ! -f "$PLAN_FILE" ]]; then
  echo "ERROR: Plan file not found: $PLAN_FILE"
  exit 1
fi

REPO_ROOT="$(pwd)"
mkdir -p "$LOG_DIR"

# ─── Helpers ───
timestamp() { date '+%Y-%m-%d %H:%M:%S'; }
log() { echo "[$(timestamp)] $*"; }

# ─── Atomic JSON update (write to tmp, then rename) ───
# Usage: atomic_json_update 'javascript code that modifies q and returns it'
atomic_json_update() {
  local js_code="$1"
  node -e "
    const fs = require('fs');
    const q = JSON.parse(fs.readFileSync('$PLAN_FILE', 'utf8'));
    const updated = (function(q) { $js_code; return q; })(q);
    const tmp = '$PLAN_FILE' + '.tmp';
    fs.writeFileSync(tmp, JSON.stringify(updated, null, 2) + '\n');
    fs.renameSync(tmp, '$PLAN_FILE');
  "
}

# Update task status atomically
update_task_status() {
  local task_id="$1"
  local new_status="$2"
  atomic_json_update "
    for (const story of q.stories) {
      for (const task of story.tasks) {
        if (task.id === '$task_id') task.status = '$new_status';
      }
    }
  "
}

# Update story status atomically
update_story_status() {
  local story_id="$1"
  local new_status="$2"
  atomic_json_update "
    for (const story of q.stories) {
      if (story.id === '$story_id') story.status = '$new_status';
    }
  "
}

# Check if all tasks in a story are completed
is_story_complete() {
  local story_id="$1"
  node -e "
    const q = JSON.parse(require('fs').readFileSync('$PLAN_FILE', 'utf8'));
    const story = q.stories.find(s => s.id === '$story_id');
    process.exit(story.tasks.every(t => t.status === 'completed') ? 0 : 1);
  "
}

# Get next executable tasks (respects DAG + story filter)
get_next_tasks() {
  node -e "
    const q = JSON.parse(require('fs').readFileSync('$PLAN_FILE', 'utf8'));
    const completedStories = new Set(
      q.stories
        .filter(s => s.tasks.every(t => t.status === 'completed'))
        .map(s => s.id)
    );
    const readyStories = q.stories.filter(s => {
      if (s.tasks.every(t => t.status === 'completed')) return false;
      if (s.tasks.some(t => t.status === 'in_progress')) return false;
      return s.dependsOn.every(dep => completedStories.has(dep));
    });
    const filtered = '$STORY_FILTER'
      ? readyStories.filter(s => s.id === '$STORY_FILTER')
      : readyStories;
    const tasks = [];
    for (const story of filtered) {
      const nextTask = story.tasks.find(t => t.status === 'pending');
      if (nextTask) tasks.push({ storyId: story.id, ...nextTask });
    }
    console.log(JSON.stringify(tasks));
  "
}

# ─── Build Claude Prompt for a Task ───
build_prompt() {
  local task_json="$1"
  node -e "
    const task = JSON.parse(process.argv[1]);
    const q = JSON.parse(require('fs').readFileSync('$PLAN_FILE', 'utf8'));
    const story = q.stories.find(s => s.id === task.storyId);
    let prompt = 'You are executing a task from an automated plan. Follow instructions precisely.\n\n';
    prompt += '## Story: ' + story.title + '\n';
    prompt += story.description + '\n\n';
    prompt += '## Task: ' + task.id + ' — ' + task.title + '\n\n';
    prompt += '### Description\n' + task.description + '\n\n';
    prompt += '### Files to modify\n';
    task.filePaths.forEach(f => prompt += '- ' + f + '\n');
    prompt += '\n';
    if (task.commands && task.commands.length > 0) {
      prompt += '### Verification commands (MUST pass)\n';
      task.commands.forEach(c => prompt += '- \`' + c + '\`\n');
      prompt += '\n';
    }
    if (task.testFirst) {
      prompt += '### TEST-FIRST: Write tests BEFORE implementation. Tests should initially fail, then pass after implementation.\n\n';
    }
    prompt += '### Rules\n';
    prompt += '- Follow existing code conventions\n';
    prompt += '- Run verification commands and ensure they pass\n';
    prompt += '- Do NOT commit changes — the orchestrator handles commits\n';
    process.stdout.write(prompt);
  " "$task_json"
}

# ─── Execute a Single Task (sequential mode) ───
execute_task() {
  local task_json="$1"
  local task_id story_id log_file prompt exit_code=0
  task_id=$(node -e "console.log(JSON.parse(process.argv[1]).id)" "$task_json")
  story_id=$(node -e "console.log(JSON.parse(process.argv[1]).storyId)" "$task_json")
  log_file="$LOG_DIR/${task_id}.log"

  log "▶ Starting task $task_id (story $story_id)"
  update_task_status "$task_id" "in_progress"

  prompt=$(build_prompt "$task_json")

  local claude_cmd=(claude --print)
  [[ "$SKIP_PERMISSIONS" == "true" ]] && claude_cmd=(claude --dangerously-skip-permissions --print)
  [[ -n "$MODEL" ]] && claude_cmd+=(--model "$MODEL")

  if [[ "$DRY_RUN" == "true" ]]; then
    log "  [DRY RUN] Would execute: ${claude_cmd[*]} -p '...'"
    echo "$prompt" > "$log_file"
    update_task_status "$task_id" "pending"
    return 0
  fi

  # Write prompt to temp file, pass via -p flag (not piped stdin)
  local prompt_file
  prompt_file=$(mktemp)
  printf '%s' "$prompt" > "$prompt_file"
  "${claude_cmd[@]}" -p "You are an autonomous coding agent. Read the task below and implement it by writing actual code files. Use your tools (Write, Edit, Bash) to create and modify files. Do NOT just describe what to do — actually do it. After implementation, run any verification commands." -- "$(cat "$prompt_file")" > "$log_file" 2>&1 || exit_code=$?
  rm -f "$prompt_file"

  if [[ $exit_code -eq 0 ]]; then
    log "✅ Task $task_id completed"
    update_task_status "$task_id" "completed"
    if is_story_complete "$story_id"; then
      log "🎉 Story $story_id fully completed"
      update_story_status "$story_id" "completed"
    fi
  else
    log "❌ Task $task_id failed (exit code $exit_code)"
    update_task_status "$task_id" "failed"
    [[ "$VERBOSE" != "true" ]] && echo "  See log: $log_file"
    [[ "$VERBOSE" == "true" ]] && cat "$log_file"
    return 1
  fi
  [[ "$VERBOSE" == "true" ]] && cat "$log_file"
}

# ═══════════════════════════════════════════════════════════════════════
# Parallel Mode — Worktree-based isolation
# ═══════════════════════════════════════════════════════════════════════

# Create a worktree for a task
create_task_worktree() {
  local task_id="$1"
  local branch_name="$2"
  local wt_path="$REPO_ROOT/$WORKTREE_DIR/$task_id"

  if [[ -d "$wt_path" ]]; then
    git -C "$REPO_ROOT" worktree remove --force "$wt_path" >/dev/null 2>&1 || rm -rf "$wt_path"
  fi

  local wt_branch="ql-wt/${task_id}"
  # Clean stale refs and branches from previous failed runs
  git -C "$REPO_ROOT" worktree prune >/dev/null 2>&1 || true
  git -C "$REPO_ROOT" branch -D "$wt_branch" >/dev/null 2>&1 || true
  git -C "$REPO_ROOT" worktree add -b "$wt_branch" "$wt_path" HEAD >/dev/null 2>&1
  if [[ ! -d "$wt_path" ]]; then
    printf "ERROR: worktree not created at %s\n" "$wt_path" >&2
    return 1
  fi
  printf '%s' "$wt_path"
}

# Remove a worktree
remove_task_worktree() {
  local task_id="$1"
  local wt_path="$REPO_ROOT/$WORKTREE_DIR/$task_id"
  local wt_branch="ql-wt/${task_id}"

  git -C "$REPO_ROOT" worktree remove --force "$wt_path" 2>/dev/null || true
  [[ -d "$wt_path" ]] && rm -rf "$wt_path"
  git -C "$REPO_ROOT" branch -D "$wt_branch" 2>/dev/null || true
}

# Merge worktree branch into current branch
merge_task_worktree() {
  local task_id="$1"
  local wt_branch="ql-wt/${task_id}"

  # Stash any dirty working tree state so merge can proceed
  local stashed=false
  if git -C "$REPO_ROOT" status --porcelain 2>/dev/null | grep -q .; then
    git -C "$REPO_ROOT" stash push -m "ql-auto-stash-before-merge-${task_id}" >/dev/null 2>&1 && stashed=true
  fi

  if git -C "$REPO_ROOT" merge --no-edit "$wt_branch" 2>/dev/null; then
    [[ "$stashed" == "true" ]] && git -C "$REPO_ROOT" stash pop >/dev/null 2>&1 || true
    return 0
  else
    git -C "$REPO_ROOT" merge --abort 2>/dev/null || true
    [[ "$stashed" == "true" ]] && git -C "$REPO_ROOT" stash pop >/dev/null 2>&1 || true
    return 1
  fi
}

# Spawn a Claude agent in a worktree (background process)
spawn_worktree_agent() {
  local task_id="$1"
  local wt_path="$2"
  local task_json="$3"

  # Use absolute paths so they work after cd into worktree
  local abs_log_dir="$REPO_ROOT/$LOG_DIR"
  local log_file="$abs_log_dir/${task_id}.log"
  local prompt_file="$abs_log_dir/${task_id}.prompt"
  local exit_file="$abs_log_dir/${task_id}.exit"
  local pid_file="$abs_log_dir/${task_id}.pid"
  local runner_script="$abs_log_dir/${task_id}.runner.sh"

  local prompt
  prompt=$(build_prompt "$task_json")

  # Write prompt to file (avoids stdin piping issues in background)
  printf '%s' "$prompt" > "$prompt_file"

  local claude_cmd="claude --print"
  [[ "$SKIP_PERMISSIONS" == "true" ]] && claude_cmd="claude --dangerously-skip-permissions --print"
  [[ -n "$MODEL" ]] && claude_cmd="$claude_cmd --model $MODEL"

  # Write a self-contained runner script (survives parent exit on Windows)
  cat > "$runner_script" <<RUNNER_EOF
#!/usr/bin/env bash
cd "$wt_path" || exit 1
$claude_cmd -p "You are an autonomous coding agent. Read the task below and implement it by writing actual code files. Use your tools (Write, Edit, Bash) to create and modify files. Do NOT just describe what to do — actually do it. After implementation, run any verification commands." -- "\$(cat '$prompt_file')" > "$log_file" 2>&1
echo \$? > "$exit_file"
RUNNER_EOF
  chmod +x "$runner_script"

  # Launch runner script in background
  bash "$runner_script" &
  local pid=$!
  echo "$pid" > "$pid_file"
  printf '%s' "$pid"
}

# Clean up orphaned worktrees from a previous interrupted run
cleanup_orphaned_worktrees() {
  if [[ ! -d "$REPO_ROOT/$WORKTREE_DIR" ]]; then
    return 0
  fi

  local count=0
  for wt_dir in "$REPO_ROOT/$WORKTREE_DIR"/*/; do
    [[ -d "$wt_dir" ]] || continue
    local tid
    tid=$(basename "$wt_dir")
    log "  Cleaning up orphaned worktree: $tid"
    # Kill any process using this worktree (read PID file if exists)
    local pid_file="$REPO_ROOT/$LOG_DIR/${tid}.pid"
    if [[ -f "$pid_file" ]]; then
      local old_pid
      old_pid=$(cat "$pid_file" 2>/dev/null)
      kill -9 "$old_pid" 2>/dev/null || true
      sleep 1
    fi
    remove_task_worktree "$tid" || log "  Warning: could not remove worktree $tid (may be locked)"
    # Reset any in_progress tasks back to pending
    atomic_json_update "
      for (const s of q.stories) {
        for (const t of s.tasks) {
          if (t.id === '$tid' && t.status === 'in_progress') t.status = 'pending';
        }
      }
    " 2>/dev/null || true
    count=$((count + 1))
  done

  if [[ $count -gt 0 ]]; then
    log "  Recovered $count orphaned worktree(s) from previous run"
  fi
}

# ─── Main Loop ───
main() {
  log "═══════════════════════════════════════════"
  log "  quantum-loop.sh"
  log "  Plan: $PLAN_FILE"
  log "  Mode: $(if $PARALLEL; then echo "parallel (max $MAX_PARALLEL)"; else echo "sequential"; fi)"
  log "  Max iterations: $MAX_ITERATIONS"
  [[ -n "$STORY_FILTER" ]] && log "  Story filter: $STORY_FILTER"
  [[ "$DRY_RUN" == "true" ]] && log "  *** DRY RUN ***"
  [[ "$PARALLEL" == "true" ]] && log "  Timeout: ${TASK_TIMEOUT}s per task"
  log "═══════════════════════════════════════════"

  # ─── Parallel mode ───
  if [[ "$PARALLEL" == "true" ]]; then
    local current_branch
    current_branch=$(git -C "$REPO_ROOT" branch --show-current)

    # Cleanup from any previous crashed run
    cleanup_orphaned_worktrees

    local iteration=0
    local wave=0

    while [[ $iteration -lt $MAX_ITERATIONS ]]; do
      local tasks_json
      tasks_json=$(get_next_tasks)
      local task_count
      task_count=$(node -e "console.log(JSON.parse(process.argv[1]).length)" "$tasks_json")

      if [[ "$task_count" == "0" ]]; then
        log "No more executable tasks."
        break
      fi

      wave=$((wave + 1))
      log ""
      log "━━━ Wave $wave: $task_count executable task(s) ━━━"

      # Track active agents
      declare -a PIDS=()
      declare -a TASK_IDS=()
      declare -a STORY_IDS=()
      declare -a WT_KEYS=()
      declare -a START_TIMES=()
      local spawned=0

      # Spawn agents in worktrees (up to MAX_PARALLEL)
      local i=0
      while [[ $i -lt $task_count && $spawned -lt $MAX_PARALLEL ]]; do
        local task
        task=$(node -e "console.log(JSON.stringify(JSON.parse(process.argv[1])[$i]))" "$tasks_json" "$i")
        local tid sid
        tid=$(node -e "console.log(JSON.parse(process.argv[1]).id)" "$task")
        sid=$(node -e "console.log(JSON.parse(process.argv[1]).storyId)" "$task")

        # Use storyId-taskId as unique key (task IDs can repeat across stories)
        local wt_key="${sid}-${tid}"

        if [[ "$DRY_RUN" == "true" ]]; then
          log "  [DRY RUN] Would spawn: $tid (story $sid)"
          i=$((i + 1))
          spawned=$((spawned + 1))
          continue
        fi

        # Create worktree
        local wt_path
        wt_path=$(create_task_worktree "$wt_key" "$current_branch") || {
          log "  [ERROR] Failed to create worktree for $wt_key"
          i=$((i + 1))
          continue
        }

        # Mark task in_progress
        update_task_status "$tid" "in_progress"

        # Spawn agent
        local pid
        pid=$(spawn_worktree_agent "$wt_key" "$wt_path" "$task")

        PIDS+=("$pid")
        TASK_IDS+=("$tid")
        STORY_IDS+=("$sid")
        WT_KEYS+=("$wt_key")
        START_TIMES+=("$(date +%s)")
        spawned=$((spawned + 1))

        log "  [SPAWNED] $tid (story $sid) — PID $pid"
        i=$((i + 1))
        iteration=$((iteration + 1))
      done

      if [[ "$DRY_RUN" == "true" ]]; then
        log "No more executable tasks."
        break
      fi
      [[ $spawned -eq 0 ]] && { log "  No agents spawned"; continue; }

      # ─── Monitor loop: poll until all agents finish ───
      while [[ ${#PIDS[@]} -gt 0 ]]; do
        sleep 5
        local completed_indices=()

        for idx in "${!PIDS[@]}"; do
          local pid="${PIDS[$idx]}"
          local tid="${TASK_IDS[$idx]}"
          local sid="${STORY_IDS[$idx]}"
          local wk="${WT_KEYS[$idx]}"
          local start="${START_TIMES[$idx]}"
          local now
          now=$(date +%s)
          local elapsed=$((now - start))

          # Check timeout
          if [[ $elapsed -ge $TASK_TIMEOUT ]]; then
            kill "$pid" 2>/dev/null || true
            wait "$pid" 2>/dev/null || true
            log "  [TIMEOUT] $tid (story $sid) after ${elapsed}s"
            update_task_status "$tid" "failed"
            remove_task_worktree "$wk" || true
            completed_indices+=("$idx")
            continue
          fi

          # Check if process is still running
          if kill -0 "$pid" 2>/dev/null; then
            continue  # Still running
          fi

          # Process finished — check exit code (|| true: wait returns process exit code)
          wait "$pid" 2>/dev/null || true
          local exit_file="$LOG_DIR/${wk}.exit"
          local exit_code=1
          [[ -f "$exit_file" ]] && exit_code=$(cat "$exit_file")

          if [[ "$exit_code" == "0" ]]; then
            local wt_path="$REPO_ROOT/$WORKTREE_DIR/$wk"

            # Commit all changes in the worktree BEFORE merging
            # (agents are told not to commit — the orchestrator does it here)
            local has_changes=false
            if git -C "$wt_path" status --porcelain 2>/dev/null | grep -q .; then
              has_changes=true
              git -C "$wt_path" add -A >/dev/null 2>&1 || true
              git -C "$wt_path" commit -m "feat: $tid ($sid) - task completion" >/dev/null 2>&1 || true
            fi

            if [[ "$has_changes" == "true" ]]; then
              # Merge worktree branch into main branch
              if merge_task_worktree "$wk"; then
                log "  [PASSED] $tid (story $sid) — ${elapsed}s"
                update_task_status "$tid" "completed"
                if is_story_complete "$sid"; then
                  log "  [STORY DONE] $sid"
                  update_story_status "$sid" "completed"
                fi
              else
                log "  [CONFLICT] $tid (story $sid) — merge failed"
                update_task_status "$tid" "failed"
              fi
            else
              # Agent exited 0 but made no changes — suspicious but mark completed
              log "  [PASSED] $tid (story $sid) — ${elapsed}s (no file changes)"
              update_task_status "$tid" "completed"
              if is_story_complete "$sid"; then
                log "  [STORY DONE] $sid"
                update_story_status "$sid" "completed"
              fi
            fi
          else
            log "  [FAILED] $tid (story $sid) — exit code $exit_code"
            update_task_status "$tid" "failed"
          fi

          remove_task_worktree "$wk" || true
          rm -f "$LOG_DIR/${wk}.exit" "$LOG_DIR/${wk}.pid" "$LOG_DIR/${wk}.prompt" "$LOG_DIR/${wk}.runner.sh"
          completed_indices+=("$idx")
        done

        # Remove completed entries (reverse order to preserve indices)
        for ((ci=${#completed_indices[@]}-1; ci>=0; ci--)); do
          local ridx="${completed_indices[$ci]}"
          unset 'PIDS[ridx]'
          unset 'TASK_IDS[ridx]'
          unset 'STORY_IDS[ridx]'
          unset 'WT_KEYS[ridx]'
          unset 'START_TIMES[ridx]'
        done
        # Re-index arrays
        PIDS=("${PIDS[@]+"${PIDS[@]}"}")
        TASK_IDS=("${TASK_IDS[@]+"${TASK_IDS[@]}"}")
        STORY_IDS=("${STORY_IDS[@]+"${STORY_IDS[@]}"}")
        WT_KEYS=("${WT_KEYS[@]+"${WT_KEYS[@]}"}")
        START_TIMES=("${START_TIMES[@]+"${START_TIMES[@]}"}")

        # If any completed, check if new tasks are unblocked
        if [[ ${#completed_indices[@]} -gt 0 && ${#PIDS[@]} -lt $MAX_PARALLEL ]]; then
          local new_tasks
          new_tasks=$(get_next_tasks)
          local new_count
          new_count=$(node -e "console.log(JSON.parse(process.argv[1]).length)" "$new_tasks")

          if [[ "$new_count" -gt 0 ]]; then
            local ni=0
            while [[ $ni -lt $new_count && ${#PIDS[@]} -lt $MAX_PARALLEL && $iteration -lt $MAX_ITERATIONS ]]; do
              local ntask
              ntask=$(node -e "console.log(JSON.stringify(JSON.parse(process.argv[1])[$ni]))" "$new_tasks" "$ni")
              local ntid nsid
              ntid=$(node -e "console.log(JSON.parse(process.argv[1]).id)" "$ntask")
              nsid=$(node -e "console.log(JSON.parse(process.argv[1]).storyId)" "$ntask")
              local nwt_key="${nsid}-${ntid}"

              local nwt
              nwt=$(create_task_worktree "$nwt_key" "$current_branch") || {
                log "  [ERROR] Failed to create worktree for $nwt_key"
                ni=$((ni + 1))
                continue
              }
              update_task_status "$ntid" "in_progress"

              local npid
              npid=$(spawn_worktree_agent "$nwt_key" "$nwt" "$ntask")

              PIDS+=("$npid")
              TASK_IDS+=("$ntid")
              STORY_IDS+=("$nsid")
              WT_KEYS+=("$nwt_key")
              START_TIMES+=("$(date +%s)")

              log "  [SPAWNED] $ntid (story $nsid) — PID $npid (newly unblocked)"
              ni=$((ni + 1))
              iteration=$((iteration + 1))
            done
          fi
        fi
      done

      sleep 1
    done

  # ─── Sequential mode (unchanged) ───
  else
    local iteration=0
    local failed_tasks=()

    while [[ $iteration -lt $MAX_ITERATIONS ]]; do
      local tasks_json
      tasks_json=$(get_next_tasks)
      local task_count
      task_count=$(node -e "console.log(JSON.parse(process.argv[1]).length)" "$tasks_json")

      if [[ "$task_count" == "0" ]]; then
        log "No more executable tasks. Checking completion..."
        break
      fi

      log "Found $task_count executable task(s)"

      local task
      task=$(node -e "console.log(JSON.stringify(JSON.parse(process.argv[1])[0]))" "$tasks_json")
      if ! execute_task "$task"; then
        local failed_id
        failed_id=$(node -e "console.log(JSON.parse(process.argv[1]).id)" "$task")
        failed_tasks+=("$failed_id")
        log "⚠️  Task $failed_id failed. Continuing..."
      fi
      iteration=$((iteration + 1))
    done
  fi

  # ─── Summary ───
  log ""
  log "═══════════════════════════════════════════"
  log "  Execution Complete"
  log "═══════════════════════════════════════════"

  node -e "
    const q = JSON.parse(require('fs').readFileSync('$PLAN_FILE', 'utf8'));
    let completed = 0, pending = 0, failed = 0, inProgress = 0;
    for (const s of q.stories) {
      for (const t of s.tasks) {
        if (t.status === 'completed') completed++;
        else if (t.status === 'failed') failed++;
        else if (t.status === 'in_progress') inProgress++;
        else pending++;
      }
    }
    const total = completed + pending + failed + inProgress;
    console.log('  Completed: ' + completed + '/' + total);
    console.log('  Failed:    ' + failed);
    console.log('  Pending:   ' + pending);
    if (inProgress > 0) console.log('  Stuck:     ' + inProgress + ' (were in_progress when loop ended)');
    console.log('');
    console.log('  Stories:');
    for (const s of q.stories) {
      const done = s.tasks.filter(t => t.status === 'completed').length;
      const icon = done === s.tasks.length ? '✅' : s.tasks.some(t => t.status === 'failed') ? '❌' : '⏳';
      console.log('    ' + icon + ' ' + s.id + ': ' + done + '/' + s.tasks.length + ' — ' + s.title);
    }
  "

  log "═══════════════════════════════════════════"
  log "  Logs: $LOG_DIR/"
  log "═══════════════════════════════════════════"
}

main
