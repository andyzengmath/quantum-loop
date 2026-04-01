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
