#!/usr/bin/env bash
# lib/quantum-validate.sh — quantum.json validation hooks (v0.9.2 / US-003)
#
# Closes v0.9.1 architect MEDIUM (US-004 review): stories with empty
# `filePaths` arrays in their `tasks[]` silently bypass
# `filter_file_conflicts` in `lib/dag-query.sh`. Operator PRDs under time
# pressure may omit `filePaths`, and the conflict filter computes
# `[.tasks[]?.filePaths[]?]` which evaluates to `[]` — the conflict check
# then trivially passes for any pair.
#
# This library provides advisory hooks that warn (stderr) without blocking.
# Wired into `lib/dag-query.sh::next_wave`'s preamble.
#
# Functions:
#   validate_story_filepaths QUANTUM_JSON_PATH
#     Emit stderr WARNING for any eligible story (status pending | failed |
#     in_progress) whose tasks have empty `filePaths` arrays in aggregate.
#     Returns 0 unconditionally on success (advisory). Returns 1 only on
#     missing/unreadable file.
#
# Library contract: no shell flags at source time; strict mode only in the
# CLI-entry block at bottom (mirrors lib/coordinator-guard.sh, lib/handoff.sh).

# Source-guard
if [[ -n "${_QL_QUANTUM_VALIDATE_LIB:-}" ]]; then
  return 0 2>/dev/null || true
fi
readonly _QL_QUANTUM_VALIDATE_LIB=1

# validate_story_filepaths(quantum_json_path) -> 0 | 1
# Returns 1 only if path is missing/unreadable (defensive). Empty-filePaths
# warnings do NOT block — they go to stderr and the function returns 0.
validate_story_filepaths() {
  local json_path="${1:?validate_story_filepaths: QUANTUM_JSON_PATH required}"
  if [[ ! -f "$json_path" ]]; then
    printf "ERROR: validate_story_filepaths: file not found: %s\n" "$json_path" >&2
    return 1
  fi
  jq -r '
    .stories[]? |
    select(.status as $s | ["pending","failed","in_progress"] | index($s)) |
    select(((.tasks // []) | map((.filePaths // []) | length) | add // 0) == 0) |
    "WARNING: Story \(.id) has no filePaths in any task; filter_file_conflicts will bypass it (architect MEDIUM finding from v0.9.1 US-004 review)."
  ' "$json_path" >&2
  return 0
}

# ------------------------------------------------------------------------------
# CLI entry. Strict mode only here.
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  set -euo pipefail
  subcmd="${1:-}"
  shift || true
  case "$subcmd" in
    validate_story_filepaths)
      validate_story_filepaths "$@"
      ;;
    *)
      cat >&2 <<USAGE
Usage: bash lib/quantum-validate.sh <subcmd> [args...]
  validate_story_filepaths QUANTUM_JSON_PATH
    Advisory: warn on stderr for any eligible story (status pending | failed
    | in_progress) with empty filePaths in its tasks. Returns 0 on success
    (warnings are advisory; never block). Returns 1 only if path is
    missing/unreadable.
USAGE
      exit 2
      ;;
  esac
fi
