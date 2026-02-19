#!/usr/bin/env bash
# lib/common.sh -- Shared utility functions for quantum-loop
# Source this file from other lib/ scripts for common validation.

# _validate_story_id(story_id)
# Validates that story_id is non-empty and matches safe alphanumeric pattern.
# Returns 0 if valid, 1 otherwise (with error on stderr).
_validate_story_id() {
  local story_id="$1"
  if [[ -z "$story_id" ]]; then
    printf "ERROR: story_id is required\n" >&2
    return 1
  fi
  if [[ ! "$story_id" =~ ^[A-Za-z0-9_-]+$ ]]; then
    printf "ERROR: Invalid story_id format: %s\n" "$story_id" >&2
    return 1
  fi
  return 0
}
