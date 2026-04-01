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
  local runners_dir="$RUNNER_LIB_DIR/../runners"
  local manifest="$runners_dir/$tool_name.json"

  # Check manifest exists
  if [[ ! -f "$manifest" ]]; then
    local available=""
    if [[ -d "$runners_dir" ]]; then
      available=$(find "$runners_dir" -maxdepth 1 -name '*.json' -print0 2>/dev/null \
        | xargs -0 -I{} basename {} .json | tr '\n' ', ' | sed 's/,$//')
    fi
    echo "ERROR: Unknown runner '$tool_name'. Available: ${available:-none}" >&2
    return 1
  fi

  # Verify valid JSON
  if ! jq empty "$manifest" 2>/dev/null; then
    echo "ERROR: Invalid JSON in $manifest" >&2
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

  if [[ -n "$missing" ]]; then
    echo "ERROR: Runner '$tool_name' missing required field(s): $missing" >&2
    return 1
  fi

  # Read all values from manifest
  local binary
  binary=$(jq -r '.binary' "$manifest")

  # Check binary exists on PATH
  if ! command -v "$binary" &>/dev/null; then
    local hint
    hint=$(jq -r '.installHint // "check your PATH"' "$manifest")
    echo "ERROR: Binary '$binary' not found. Install with: $hint" >&2
    return 1
  fi

  # Set RUNNER_* shell variables (used by caller — see runner_build_cmd, runner_ensure_instructions, etc.)
  # shellcheck disable=SC2034
  RUNNER_NAME=$(jq -r '.name' "$manifest")
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

  echo "[RUNNER] Loaded $RUNNER_NAME ($RUNNER_BINARY) — tier: $RUNNER_TIER" >&2
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
    echo "ERROR: Neither $RUNNER_INSTRUCTION_NATIVE nor $RUNNER_INSTRUCTION_FALLBACK found in $target_dir" >&2
    return 1
  fi

  # Generate native from fallback with marker
  {
    echo "$ql_marker"
    echo ""
    cat "$fallback_path"
  } > "$native_path"

  echo "[RUNNER] Generated $RUNNER_INSTRUCTION_NATIVE from $RUNNER_INSTRUCTION_FALLBACK" >&2
  return 0
}
