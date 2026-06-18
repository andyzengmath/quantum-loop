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

# _ql_validate_blocking_enabled() -> 0 (blocking) | 1 (advisory)
# Track A / Q1: validators stay advisory by default and only BLOCK when
# QL_VALIDATE_BLOCKING is truthy (1|true|yes|on). Preserves the v0.9.2
# default-off contract.
_ql_validate_blocking_enabled() {
  case "${QL_VALIDATE_BLOCKING:-}" in
    1|true|TRUE|yes|on) return 0 ;;
    *) return 1 ;;
  esac
}

# validate_story_surface_budget(quantum_json_path) -> 0 | 1
# Track A / Q1+Q3: warns (stderr) for any eligible story (status pending |
# failed | in_progress) lacking a `surfaceBudget` object — the per-story
# NEW-surface cap (maxNewFiles / maxNewLines / maxNewPublicSymbols /
# maxNewAbstractions) the anti-slop gate enforces via lib/surface-budget.sh.
# Advisory (returns 0) unless QL_VALIDATE_BLOCKING is set, in which case a
# missing budget returns 1. Returns 1 on missing/unreadable file.
validate_story_surface_budget() {
  local json_path="${1:?validate_story_surface_budget: QUANTUM_JSON_PATH required}"
  if [[ ! -f "$json_path" ]]; then
    printf "ERROR: validate_story_surface_budget: file not found: %s\n" "$json_path" >&2
    return 1
  fi
  local offenders
  offenders=$(jq -r '
    .stories[]? |
    select(.status as $s | ["pending","failed","in_progress"] | index($s)) |
    select((.surfaceBudget // null) == null) |
    .id
  ' "$json_path")
  if [[ -n "$offenders" ]]; then
    while IFS= read -r sid; do
      [[ -z "$sid" ]] && continue
      printf "WARNING: Story %s has no surfaceBudget; the new-surface anti-slop cap cannot be enforced for it (Track A Q3).\n" "$sid" >&2
    done <<< "$offenders"
    if _ql_validate_blocking_enabled; then
      printf "BLOCKING: QL_VALIDATE_BLOCKING set and one or more eligible stories lack surfaceBudget.\n" >&2
      return 1
    fi
  fi
  return 0
}

# validate_quantum_blocking(quantum_json_path) -> 0 | 1
# Track A / Q1: the single blocking entry point wired into
# dag-query.sh::next_wave. ALWAYS emits the advisory warnings (filePaths +
# surfaceBudget) as a side effect. Returns non-zero ONLY when
# QL_VALIDATE_BLOCKING is enabled AND an eligible story violates the filePaths
# or surfaceBudget invariant — otherwise returns 0 (pure advisory, preserving
# the v0.9.2 default-off contract so existing plans are unaffected).
validate_quantum_blocking() {
  local json_path="${1:?validate_quantum_blocking: QUANTUM_JSON_PATH required}"
  if [[ ! -f "$json_path" ]]; then
    printf "ERROR: validate_quantum_blocking: file not found: %s\n" "$json_path" >&2
    return 1
  fi
  # Advisory warnings always emit (side effect); their rc is ignored here.
  validate_story_filepaths "$json_path" || true
  validate_story_surface_budget "$json_path" || true

  _ql_validate_blocking_enabled || return 0

  # Blocking mode: count eligible stories violating either invariant.
  local bad
  bad=$(jq -r '
    [ .stories[]?
      | select(.status as $s | ["pending","failed","in_progress"] | index($s))
      | select(
          (((.tasks // []) | map((.filePaths // []) | length) | add // 0) == 0)
          or ((.surfaceBudget // null) == null)
        )
      | .id ] | length
  ' "$json_path")
  if [[ "${bad:-0}" -gt 0 ]]; then
    printf "BLOCKING: %s eligible story/stories violate the filePaths/surfaceBudget invariants (QL_VALIDATE_BLOCKING).\n" "$bad" >&2
    return 1
  fi
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
    validate_story_surface_budget)
      validate_story_surface_budget "$@"
      ;;
    validate_quantum_blocking)
      validate_quantum_blocking "$@"
      ;;
    *)
      cat >&2 <<USAGE
Usage: bash lib/quantum-validate.sh <subcmd> [args...]
  validate_story_filepaths QUANTUM_JSON_PATH
    Advisory: warn on stderr for any eligible story (status pending | failed
    | in_progress) with empty filePaths in its tasks. Returns 0 on success
    (warnings are advisory; never block). Returns 1 only if path is
    missing/unreadable.
  validate_story_surface_budget QUANTUM_JSON_PATH
    Advisory (or blocking under QL_VALIDATE_BLOCKING): warn/fail on any eligible
    story lacking a surfaceBudget object (Track A Q3 new-surface cap).
  validate_quantum_blocking QUANTUM_JSON_PATH
    Always emits advisory warnings (filePaths + surfaceBudget). Returns non-zero
    ONLY under QL_VALIDATE_BLOCKING when an eligible story violates either
    invariant. Wired into dag-query.sh::next_wave.
USAGE
      exit 2
      ;;
  esac
fi
