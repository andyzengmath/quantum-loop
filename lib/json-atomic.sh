#!/usr/bin/env bash
# lib/json-atomic.sh -- Atomic quantum.json write functions for quantum-loop
# Source this file to use write_quantum_json(), cleanup_stale_tmp(),
# compute_prd_sha() (P5.A5 / US-005), etc.
# Requires: jq, sha256sum (or python3 sha256 fallback)

# compute_prd_sha(prd_path)
# P5.A5 / US-005 — produces a stable sha256 of the PRD file content,
# used by the orchestrator pre-flight hash-check to detect PRD drift
# (RAGShield Level-1 mitigation, arXiv:2604.00387).
#
# Excludes trailing whitespace per git hash-object convention so that
# trivial line-ending or trailing-blank-line edits don't invalidate
# every story's prdSha. Echoes the 64-char hex sha256 on stdout.
compute_prd_sha() {
  local prd_path="${1:?compute_prd_sha: PRD path required}"
  if [[ ! -f "$prd_path" ]]; then
    printf "ERROR: compute_prd_sha: file not found: %s\n" "$prd_path" >&2
    return 1
  fi
  # Normalize CRLF to LF, then strip trailing whitespace, for consistent
  # hashes across platforms (Windows Git Bash autocrlf=true vs Linux/macOS LF).
  # Without CRLF normalization, the same PRD checked out on Windows vs Linux
  # produces different sha256s — every story's prdSha would false-positive
  # as 'stale' in cross-platform setups (CLAUDE.md Platform Notes).
  # Use python3 for cross-platform consistency (Git Bash, Linux, macOS).
  python3 -c "
import sys, hashlib
with open(sys.argv[1], 'rb') as f:
    content = f.read().replace(b'\r\n', b'\n').rstrip(b' \t\n')
print(hashlib.sha256(content).hexdigest())
" "$prd_path"
}

# write_quantum_json(json_path, content)
# Writes content to json_path atomically via a .tmp intermediate file.
# Validates that content is non-empty and valid JSON before writing.
# Returns 0 on success, 1 on failure.
write_quantum_json() {
  local json_path="$1"
  local content="$2"

  if [[ -z "$json_path" ]]; then
    echo "ERROR: write_quantum_json requires json_path" >&2
    return 1
  fi

  if [[ -z "$content" ]]; then
    echo "ERROR: write_quantum_json received empty content" >&2
    return 1
  fi

  # Validate JSON before writing
  if ! printf '%s\n' "$content" | jq . >/dev/null 2>&1; then
    echo "ERROR: write_quantum_json received invalid JSON" >&2
    return 1
  fi

  local tmp_path="${json_path}.tmp"

  # Write to tmp file first
  if ! printf '%s\n' "$content" | jq . > "$tmp_path" 2>/dev/null; then
    rm -f "$tmp_path"
    return 1
  fi

  # Atomic rename
  mv "$tmp_path" "$json_path"
  return $?
}

# cleanup_stale_tmp(json_path)
# Removes a stale .tmp file if it exists (from an interrupted previous write).
# Returns 0 always.
cleanup_stale_tmp() {
  local json_path="$1"

  if [[ -z "$json_path" ]]; then
    echo "ERROR: cleanup_stale_tmp requires json_path" >&2
    return 1
  fi

  local tmp_path="${json_path}.tmp"
  if [[ -f "$tmp_path" ]]; then
    rm -f "$tmp_path"
  fi
  return 0
}

# update_execution_field(json_path, mode, max_parallel, current_wave)
# Adds or updates the execution metadata field in quantum.json.
# Initializes activeWorktrees as empty array if not present.
update_execution_field() {
  local json_path="$1"
  local mode="$2"
  local max_parallel="$3"
  local current_wave="$4"

  if [[ -z "$json_path" || -z "$mode" ]]; then
    echo "ERROR: update_execution_field requires json_path and mode" >&2
    return 1
  fi

  local updated
  updated=$(jq \
    --arg mode "$mode" \
    --argjson maxp "${max_parallel:-0}" \
    --argjson wave "${current_wave:-1}" \
    '.execution = {
      mode: $mode,
      maxParallel: $maxp,
      currentWave: $wave,
      activeWorktrees: (.execution.activeWorktrees // [])
    }' "$json_path")

  if [[ -z "$updated" ]]; then
    echo "ERROR: update_execution_field jq transform failed" >&2
    return 1
  fi

  write_quantum_json "$json_path" "$updated"
}

# set_story_worktree(json_path, story_id, worktree_path)
# Sets the worktree field on a story and adds the path to execution.activeWorktrees.
set_story_worktree() {
  local json_path="$1"
  local story_id="$2"
  local wt_path="$3"

  if [[ -z "$json_path" || -z "$story_id" || -z "$wt_path" ]]; then
    echo "ERROR: set_story_worktree requires json_path, story_id, worktree_path" >&2
    return 1
  fi

  local updated
  updated=$(jq \
    --arg sid "$story_id" \
    --arg wtp "$wt_path" \
    '(.stories[] | select(.id == $sid)).worktree = $wtp |
     .execution.activeWorktrees = ((.execution.activeWorktrees // []) + [$wtp] | unique)' \
    "$json_path")

  if [[ -z "$updated" ]]; then
    echo "ERROR: set_story_worktree jq transform failed" >&2
    return 1
  fi

  write_quantum_json "$json_path" "$updated"
}

# clear_story_worktree(json_path, story_id)
# Removes the worktree field from a story and removes its path from execution.activeWorktrees.
clear_story_worktree() {
  local json_path="$1"
  local story_id="$2"

  if [[ -z "$json_path" || -z "$story_id" ]]; then
    echo "ERROR: clear_story_worktree requires json_path, story_id" >&2
    return 1
  fi

  # Two-step approach: read worktree path first, then delete and filter
  local wt_path
  wt_path=$(jq -r --arg sid "$story_id" '.stories[] | select(.id == $sid) | .worktree // ""' "$json_path")

  local updated
  updated=$(jq \
    --arg sid "$story_id" \
    --arg wtp "$wt_path" \
    '(.stories[] | select(.id == $sid)) |= del(.worktree) |
     .execution.activeWorktrees = [.execution.activeWorktrees[] | select(. != $wtp)]' \
    "$json_path")

  if [[ -z "$updated" ]]; then
    echo "ERROR: clear_story_worktree jq transform failed" >&2
    return 1
  fi

  write_quantum_json "$json_path" "$updated"
}

# json_atomic_update(jq_filter [json_path])
# Applies a jq filter to quantum.json (or specified path) atomically.
# Uses write_quantum_json for safe tmp+mv semantics.
# Returns 0 on success, 1 on failure.
json_atomic_update() {
  local filter="$1"
  local json_path="${2:-quantum.json}"

  if [[ -z "$filter" ]]; then
    printf "ERROR: json_atomic_update requires a jq filter\n" >&2
    return 1
  fi

  if [[ ! -f "$json_path" ]]; then
    printf "ERROR: json_atomic_update: file not found: %s\n" "$json_path" >&2
    return 1
  fi

  local updated
  updated=$(jq "$filter" "$json_path" 2>/dev/null)

  if [[ -z "$updated" ]]; then
    printf "ERROR: json_atomic_update: jq filter produced empty output\n" >&2
    return 1
  fi

  write_quantum_json "$json_path" "$updated"
}
