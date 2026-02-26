#!/usr/bin/env bash
# lib/spawn.sh -- Agent spawn functions for quantum-loop parallel execution
#
# Provides: build_agent_prompt(), build_autonomous_command(), spawn_autonomous()
# Requires: lib/common.sh (for _validate_story_id)
# Interactive spawning uses the Task tool directly (not a shell function).

# Source shared utilities
SPAWN_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SPAWN_LIB_DIR/common.sh" || { printf "ERROR: common.sh not found\n" >&2; return 1 2>/dev/null || exit 1; }

# Output filename used by spawn_autonomous and read by the monitor
AGENT_OUTPUT_FILENAME=".ql-agent-output.txt"

# build_agent_prompt(story_id)
# Builds the prompt string that tells an agent which story to implement.
# The agent runs in a worktree and must NOT write quantum.json.
# Returns the prompt string on stdout.
build_agent_prompt() {
  local story_id="$1"

  _validate_story_id "$story_id" || return 1

  cat <<PROMPT
Implement story ${story_id} following the instructions in CLAUDE.md.

IMPORTANT: You are running in a worktree (.ql-wt/). Do NOT write quantum.json.
The orchestrator manages all state.

Your workflow:
1. Read quantum.json for story details, PRD path, and codebasePatterns
2. Implement all tasks in order (TDD if testFirst is true)
3. Verify new code is wired into callers (not just created in isolation)
4. Run quality checks (typecheck, lint, tests)
5. Self-review against acceptance criteria in the PRD
6. Commit: git add -A && git commit -m "feat: ${story_id} - <Story Title>"
7. Signal: <quantum>STORY_PASSED</quantum> or <quantum>STORY_FAILED</quantum>

Uncommitted work is LOST when the worktree is removed.
Your story ID is ${story_id}. Implement ONLY this story.
PROMPT
}

# build_autonomous_command(story_id, worktree_path)
# Builds the shell command to spawn a claude --print agent in autonomous mode.
# Returns the command string on stdout.
build_autonomous_command() {
  local story_id="$1"
  local worktree_path="$2"

  _validate_story_id "$story_id" || return 1

  if [[ -z "$worktree_path" ]]; then
    printf "ERROR: worktree_path is required\n" >&2
    return 1
  fi

  local prompt
  prompt=$(build_agent_prompt "$story_id") || return 1

  # Build the command that will be run in the background
  printf 'cd %q && claude --print -p %q' "$worktree_path" "$prompt"
}

# spawn_autonomous(story_id, worktree_path)
# Spawns a claude --print agent as a background process.
# Returns the PID on stdout. The caller is responsible for monitoring.
spawn_autonomous() {
  local story_id="$1"
  local worktree_path="$2"

  _validate_story_id "$story_id" || return 1

  if [[ -z "$worktree_path" ]]; then
    printf "ERROR: worktree_path is required\n" >&2
    return 1
  fi

  if [[ ! -d "$worktree_path" ]]; then
    printf "ERROR: worktree_path does not exist: %s\n" "$worktree_path" >&2
    return 1
  fi

  local prompt
  prompt=$(build_agent_prompt "$story_id") || return 1
  local output_file="${worktree_path}/${AGENT_OUTPUT_FILENAME}"

  # Spawn in background, capture output to file
  # --dangerously-skip-permissions required: background agents have no TTY for permission prompts
  (cd "$worktree_path" && claude --dangerously-skip-permissions --print -p "$prompt" > "$output_file" 2>&1) &
  local pid=$!

  printf "%s" "$pid"
}
