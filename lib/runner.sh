#!/usr/bin/env bash
# lib/runner.sh — Runner adapter layer for quantum-loop.
# Reads JSON manifests from runners/ to configure any coding agent CLI.
#
# Usage: source lib/runner.sh; runner_load "claude"
# After loading, all RUNNER_* variables are set for command building.

RUNNER_LIB_DIR="${RUNNER_LIB_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)}"

# Source shared utilities
if [[ -f "$RUNNER_LIB_DIR/common.sh" ]]; then
  # shellcheck source=lib/common.sh
  source "$RUNNER_LIB_DIR/common.sh"
fi

# runner_load(tool_name)
# Reads runners/<tool>.json, validates required fields, checks binary, sets RUNNER_* vars.
# Returns 0 on success, 1 on error (with message on stderr).
runner_load() {
  local tool_name="${1:?runner_load requires a tool name}"

  # Validate tool name: alphanumeric, hyphens, underscores only (prevents path traversal)
  if [[ ! "$tool_name" =~ ^[A-Za-z0-9_-]+$ ]]; then
    printf "ERROR: Invalid runner name: '%s' (must be alphanumeric with hyphens/underscores)\n" "$tool_name" >&2
    return 1
  fi

  local runners_dir="$RUNNER_LIB_DIR/../runners"
  local manifest="$runners_dir/$tool_name.json"

  # Check manifest exists
  if [[ ! -f "$manifest" ]]; then
    local available=""
    if [[ -d "$runners_dir" ]]; then
      for f in "$runners_dir"/*.json; do
        [[ -f "$f" ]] || continue
        local name
        name=$(basename "$f" .json)
        available="${available:+$available, }$name"
      done
    fi
    printf "ERROR: Unknown runner '%s'. Available: %s\n" "$tool_name" "${available:-none}" >&2
    return 1
  fi

  # Verify valid JSON
  if ! jq empty "$manifest" 2>/dev/null; then
    printf "ERROR: Invalid JSON in %s\n" "$manifest" >&2
    return 1
  fi

  # Validate required fields
  local missing=""
  for field in name binary tier; do
    if [[ "$(jq -r ".$field // empty" "$manifest")" == "" ]]; then
      missing="${missing:+$missing, }$field"
    fi
  done
  for field in promptDelivery headlessFlags autoApproveFlags; do
    if [[ "$(jq -r ".invocation.$field // empty" "$manifest")" == "" ]]; then
      missing="${missing:+$missing, }invocation.$field"
    fi
  done
  if [[ "$(jq -r '.instructionFile.native // empty' "$manifest")" == "" ]]; then
    missing="${missing:+$missing, }instructionFile.native"
  fi
  for field in preambleInjection heuristicFallback; do
    if [[ "$(jq ".signals | has(\"$field\")" "$manifest")" != "true" ]]; then
      missing="${missing:+$missing, }signals.$field"
    fi
  done

  if [[ -n "$missing" ]]; then
    printf "ERROR: Runner '%s' missing required field(s): %s\n" "$tool_name" "$missing" >&2
    return 1
  fi

  # Read all values from manifest
  local binary
  binary=$(jq -r '.binary' "$manifest")

  # Validate binary name — reject shell metacharacters
  if [[ ! "$binary" =~ ^[a-zA-Z0-9_./-]+$ ]]; then
    printf "ERROR: Invalid binary name in manifest: '%s'\n" "$binary" >&2
    return 1
  fi

  # Check binary exists on PATH
  if ! command -v "$binary" &>/dev/null; then
    local hint
    hint=$(jq -r '.installHint // "check your PATH"' "$manifest")
    printf "ERROR: Binary '%s' not found. Install with: %s\n" "$binary" "$hint" >&2
    return 1
  fi

  # Set RUNNER_* shell variables (used by caller — see runner_build_cmd, runner_ensure_instructions, etc.)
  # shellcheck disable=SC2034
  RUNNER_NAME=$(jq -r '.name' "$manifest")

  # Validate RUNNER_NAME from manifest (used in hook path construction — must be safe)
  if [[ ! "$RUNNER_NAME" =~ ^[A-Za-z0-9_-]+$ ]]; then
    printf "ERROR: Invalid runner name in manifest: '%s' (must be alphanumeric with hyphens/underscores)\n" "$RUNNER_NAME" >&2
    return 1
  fi

  RUNNER_BINARY="$binary"
  # shellcheck disable=SC2034
  RUNNER_TIER=$(jq -r '.tier' "$manifest")
  # shellcheck disable=SC2034
  RUNNER_PROMPT_DELIVERY=$(jq -r '.invocation.promptDelivery' "$manifest")
  # shellcheck disable=SC2034
  RUNNER_PROMPT_FLAG=$(jq -r '.invocation.promptFlag // ""' "$manifest")
  # shellcheck disable=SC2034
  RUNNER_HEADLESS_FLAGS=$(jq -r '.invocation.headlessFlags | join(" ")' "$manifest")
  # shellcheck disable=SC2034
  RUNNER_AUTO_APPROVE_FLAGS=$(jq -r '.invocation.autoApproveFlags | join(" ")' "$manifest")
  # shellcheck disable=SC2034
  RUNNER_STDIN_PIPE=$(jq -r '.invocation.stdinPipe // false' "$manifest")
  # shellcheck disable=SC2034
  RUNNER_INSTRUCTION_NATIVE=$(jq -r '.instructionFile.native' "$manifest")
  # shellcheck disable=SC2034
  RUNNER_INSTRUCTION_FALLBACK=$(jq -r '.instructionFile.fallbackFrom // ""' "$manifest")
  # shellcheck disable=SC2034
  RUNNER_PREAMBLE_INJECTION=$(jq -r '.signals.preambleInjection // false' "$manifest")
  # shellcheck disable=SC2034
  RUNNER_HEURISTIC_FALLBACK=$(jq -r '.signals.heuristicFallback // false' "$manifest")
  # shellcheck disable=SC2034
  RUNNER_EXTRA_FLAGS=""
  # shellcheck disable=SC2034
  RUNNER_OVERRIDE_SIGNAL=""

  # Validate manifest-sourced flags — reject shell metacharacters
  local _flag_val
  for _flag_val in "$RUNNER_HEADLESS_FLAGS" "$RUNNER_AUTO_APPROVE_FLAGS" "$RUNNER_PROMPT_FLAG"; do
    if [[ "$_flag_val" =~ [\;\|\&\$\`\(\)\>\<\!\{\}] ]]; then
      printf "ERROR: Unsafe characters in runner manifest flags: '%s'\n" "$_flag_val" >&2
      return 1
    fi
  done

  printf "[RUNNER] Loaded %s (%s) — tier: %s\n" "$RUNNER_NAME" "$RUNNER_BINARY" "$RUNNER_TIER" >&2
  return 0
}

# runner_ensure_instructions([target_dir])
# Ensures the runner's native instruction file exists in target_dir (default: pwd).
# If native file is missing, copies from fallbackFrom with .ql-generated marker.
# Never overwrites user-maintained files. Idempotent.
# Returns 0 on success or no-op, 1 on error.
runner_ensure_instructions() {
  local target_dir="${1:-.}"
  local ql_marker="<!-- .ql-generated: Auto-generated from CLAUDE.md by quantum-loop. Do not edit manually. -->"

  # If native == fallback or fallback is empty, nothing to do
  if [[ "$RUNNER_INSTRUCTION_NATIVE" == "$RUNNER_INSTRUCTION_FALLBACK" ]] || [[ -z "$RUNNER_INSTRUCTION_FALLBACK" ]]; then
    return 0
  fi

  local native_path="$target_dir/$RUNNER_INSTRUCTION_NATIVE"
  local fallback_path="$target_dir/$RUNNER_INSTRUCTION_FALLBACK"

  # If native already exists, don't overwrite
  if [[ -f "$native_path" ]]; then
    return 0
  fi

  # Fallback must exist to copy from
  if [[ ! -f "$fallback_path" ]]; then
    printf "ERROR: Neither %s nor %s found in %s\n" "$RUNNER_INSTRUCTION_NATIVE" "$RUNNER_INSTRUCTION_FALLBACK" "$target_dir" >&2
    return 1
  fi

  # Generate native from fallback with marker
  {
    echo "$ql_marker"
    echo ""
    cat "$fallback_path"
  } > "$native_path"

  printf "[RUNNER] Generated %s from %s\n" "$RUNNER_INSTRUCTION_NATIVE" "$RUNNER_INSTRUCTION_FALLBACK" >&2
  return 0
}

# runner_inject_preamble(prompt)
# Prepends the quantum-loop signal protocol preamble to the prompt for non-Claude runners.
# When RUNNER_PREAMBLE_INJECTION is false, returns prompt unchanged.
runner_inject_preamble() {
  local prompt="$1"

  if [[ "$RUNNER_PREAMBLE_INJECTION" != "true" ]]; then
    printf '%s' "$prompt"
    return 0
  fi

  local preamble_path="$RUNNER_LIB_DIR/../runners/preamble.md"
  if [[ ! -f "$preamble_path" ]]; then
    printf "[RUNNER] WARNING: preamble.md not found, sending prompt without preamble\n" >&2
    printf '%s' "$prompt"
    return 0
  fi

  local preamble
  preamble=$(cat "$preamble_path")

  printf '%s\n\n---\n\n%s' "$preamble" "$prompt"
  return 0
}

# Source signal heuristics if available
if [[ -f "$RUNNER_LIB_DIR/signal-heuristics.sh" ]]; then
  # shellcheck source=lib/signal-heuristics.sh
  source "$RUNNER_LIB_DIR/signal-heuristics.sh"
fi

# Source claim-check linter if available (Phase 5 / P1.5 completion-claim gate)
if [[ -f "$RUNNER_LIB_DIR/claim-check.sh" ]]; then
  # shellcheck source=lib/claim-check.sh
  source "$RUNNER_LIB_DIR/claim-check.sh"
fi

# _runner_apply_claim_check(output_text)
# After a signal has been resolved, scan the agent output for hedge /
# stale-evidence / polite-stop patterns. Records findings in the global
# SIGNAL_CLAIM_FINDINGS and down-grades confidence from exact/high to medium
# when a hedge or polite-stop is present. Does NOT flip the signal itself —
# a PASSED signal with hedge phrases is still PASSED, just lower confidence.
_runner_apply_claim_check() {
  local output="$1"
  SIGNAL_CLAIM_FINDINGS=""
  if ! type claim_check_scan &>/dev/null; then
    return 0
  fi
  local findings verdict
  findings=$(printf '%s\n' "$output" | claim_check_scan - 2>/dev/null || true)
  verdict=$(printf '%s\n' "$findings" | claim_check_verdict 2>/dev/null || echo "clean")
  SIGNAL_CLAIM_FINDINGS="$verdict"
  if [[ "$verdict" == "clean" ]]; then
    return 0
  fi
  # Any non-clean verdict demotes exact/high to medium. Lower levels stay.
  case "$SIGNAL_CONFIDENCE" in
    exact|high)
      printf "[RUNNER] Claim-check: %s -- demoting confidence from %s to medium\n" \
        "$verdict" "$SIGNAL_CONFIDENCE" >&2
      # shellcheck disable=SC2034
      SIGNAL_CONFIDENCE="medium"
      ;;
    *)
      printf "[RUNNER] Claim-check: %s (confidence %s unchanged)\n" \
        "$verdict" "$SIGNAL_CONFIDENCE" >&2
      ;;
  esac
  return 0
}

# runner_parse_output(output, exit_code, [worktree_path])
# Parses runner output for quantum signals. Falls back to heuristics if enabled.
# After signal resolution, applies claim-check lint (Phase 5) which may demote
# SIGNAL_CONFIDENCE from exact/high to medium without changing SIGNAL_RESULT.
# Sets globals:
#   SIGNAL_RESULT          — "STORY_PASSED" | "STORY_FAILED" | "COMPLETE" | "BLOCKED"
#   SIGNAL_CONFIDENCE      — "exact" | "high" | "medium"
#   SIGNAL_CLAIM_FINDINGS  — "clean" | "hedge:N stale:M polite-stop:K"
runner_parse_output() {
  local output="$1"
  local exit_code="$2"
  local wt_path="${3:-.}"

  # shellcheck disable=SC2034
  SIGNAL_RESULT=""
  # shellcheck disable=SC2034
  SIGNAL_CONFIDENCE=""

  # Always try exact signal match first (even for Claude)
  local signals
  signals=$(echo "$output" | grep -oE '<quantum>[[:space:]]*(STORY_PASSED|STORY_FAILED|COMPLETE|BLOCKED)[[:space:]]*</quantum>' || true)

  if [[ -n "$signals" ]]; then
    local last_signal
    last_signal=$(echo "$signals" | tail -1 | sed 's/<quantum>[[:space:]]*//' | sed 's/[[:space:]]*<\/quantum>//')
    # shellcheck disable=SC2034
    SIGNAL_RESULT="$last_signal"
    # shellcheck disable=SC2034
    SIGNAL_CONFIDENCE="exact"
    printf "[RUNNER] Signal: %s (exact, confidence=exact)\n" "$last_signal" >&2
    _runner_apply_claim_check "$output"
    return 0
  fi

  # No exact signal — try heuristics if enabled
  if [[ "$RUNNER_HEURISTIC_FALLBACK" == "true" ]] && type parse_agent_output &>/dev/null; then
    parse_agent_output "$output" "$exit_code" "$wt_path"
    _runner_apply_claim_check "$output"
    return 0
  fi

  # No signal and heuristics disabled — fail
  # shellcheck disable=SC2034
  SIGNAL_RESULT="STORY_FAILED"
  # shellcheck disable=SC2034
  SIGNAL_CONFIDENCE="high"
  printf "[RUNNER] Signal: FAILED (no signal detected, heuristics disabled, confidence=high)\n" >&2
  _runner_apply_claim_check "$output"
  return 0
}

# runner_build_cmd(prompt)
# Constructs the complete shell command for the loaded runner.
# Supports flag, positional, and stdin prompt delivery methods.
# Sources hook files and calls pre_spawn() if defined.
# Echoes the command string to stdout.
runner_build_cmd() {
  local prompt="$1"

  # Inject preamble for non-Claude runners
  local final_prompt
  final_prompt=$(runner_inject_preamble "$prompt")

  # Initialize hook-extensible extra flags
  RUNNER_EXTRA_FLAGS="${RUNNER_EXTRA_FLAGS:-}"

  # Source runner-specific hooks if available (path validated to stay inside hooks dir)
  local hooks_dir="$RUNNER_LIB_DIR/../runners/hooks"
  local hook_file="$hooks_dir/${RUNNER_NAME}-hooks.sh"
  if [[ -f "$hook_file" ]]; then
    # Verify hook file is inside the expected directory (prevent symlink/traversal attacks)
    local real_hook real_hooks_dir
    real_hook=$(cd "$(dirname "$hook_file")" && pwd)/$(basename "$hook_file")
    real_hooks_dir=$(cd "$hooks_dir" 2>/dev/null && pwd)
    if [[ -n "$real_hooks_dir" && "$real_hook" != "$real_hooks_dir"/* ]]; then
      printf "ERROR: Hook file outside expected directory: %s\n" "$real_hook" >&2
      return 1
    fi
    # shellcheck disable=SC1090
    source "$hook_file"
    # Call pre_spawn if defined (hook output goes to stderr)
    if type pre_spawn &>/dev/null; then
      pre_spawn
    fi
  fi

  # Build the command based on prompt delivery method
  local cmd=""
  case "$RUNNER_PROMPT_DELIVERY" in
    flag)
      cmd="$RUNNER_BINARY"
      [[ -n "$RUNNER_HEADLESS_FLAGS" ]] && cmd="$cmd $RUNNER_HEADLESS_FLAGS"
      [[ -n "$RUNNER_AUTO_APPROVE_FLAGS" ]] && cmd="$cmd $RUNNER_AUTO_APPROVE_FLAGS"
      [[ -n "$RUNNER_EXTRA_FLAGS" ]] && cmd="$cmd $RUNNER_EXTRA_FLAGS"
      cmd="$cmd $RUNNER_PROMPT_FLAG"
      # Quote the prompt using printf %q for safe shell evaluation
      local escaped_prompt
      escaped_prompt=$(printf '%q' "$final_prompt")
      cmd="$cmd $escaped_prompt"
      ;;
    positional)
      cmd="$RUNNER_BINARY"
      [[ -n "$RUNNER_HEADLESS_FLAGS" ]] && cmd="$cmd $RUNNER_HEADLESS_FLAGS"
      [[ -n "$RUNNER_AUTO_APPROVE_FLAGS" ]] && cmd="$cmd $RUNNER_AUTO_APPROVE_FLAGS"
      [[ -n "$RUNNER_EXTRA_FLAGS" ]] && cmd="$cmd $RUNNER_EXTRA_FLAGS"
      local escaped_prompt
      escaped_prompt=$(printf '%q' "$final_prompt")
      cmd="$cmd $escaped_prompt"
      ;;
    stdin)
      local escaped_prompt
      escaped_prompt=$(printf '%q' "$final_prompt")
      cmd="printf '%s' $escaped_prompt | $RUNNER_BINARY"
      [[ -n "$RUNNER_HEADLESS_FLAGS" ]] && cmd="$cmd $RUNNER_HEADLESS_FLAGS"
      [[ -n "$RUNNER_AUTO_APPROVE_FLAGS" ]] && cmd="$cmd $RUNNER_AUTO_APPROVE_FLAGS"
      [[ -n "$RUNNER_EXTRA_FLAGS" ]] && cmd="$cmd $RUNNER_EXTRA_FLAGS"
      ;;
    *)
      printf "ERROR: Unknown promptDelivery: %s\n" "$RUNNER_PROMPT_DELIVERY" >&2
      return 1
      ;;
  esac

  # Clean up hook functions to avoid leaking between runners
  unset -f pre_spawn 2>/dev/null || true
  unset -f post_output 2>/dev/null || true

  printf '%s' "$cmd"
  return 0
}
