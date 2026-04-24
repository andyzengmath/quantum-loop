#!/usr/bin/env bash
# lib/phase-skip.sh — phase-skip via artifact detection (P2.4, OMC Autopilot).
#
# Each pipeline stage re-runs from scratch by default. For long autonomous
# sessions, re-running brainstorm on an unchanged design or re-running spec
# on an unchanged PRD is wasted budget. This library lets a skill fingerprint
# its inputs once, then skip on subsequent invocations if the fingerprint
# matches.
#
# Storage: .handoffs/<stage>.fingerprint.json alongside the Phase 15
# stage-handoff files. Separate file (not embedded in handoff frontmatter)
# so the Phase 15 parser stays untouched.
#
# Fingerprint file shape:
#   {
#     "stage": "brainstorm",
#     "recorded_at": "2026-04-23T10:00:00Z",
#     "artifacts": [
#       {"path": "docs/plans/2026-04-23-x-design.md", "sha256": "abc...",  "size": 1234},
#       {"path": "inline://userIntent.text",          "sha256": "def...",  "size": null}
#     ]
#   }
#
# The "inline://" prefix is an escape hatch so a skill can fingerprint a
# logical value (like quantum.json.userIntent.text) that isn't its own file.
#
# Functions:
#   artifact_hash PATH               — sha256 of file content, "" if missing.
#   artifact_hash_inline CONTENT     — sha256 of a literal string (for the
#                                      inline:// fingerprint class).
#   record_fingerprint STAGE JSON    — write .handoffs/<stage>.fingerprint.json.
#   read_fingerprint STAGE           — load the JSON, or "{}" if absent.
#   should_skip_stage STAGE LIST...  — exit 0 if every listed path's current
#                                      hash matches the recorded fingerprint;
#                                      exit 1 if any differs or no record.
#
# Library contract (same as Phase 5/8/9/11/12/14/15/16): no shell flags at
# source time. CLI block enables strict mode locally.

PHASE_SKIP_LIB_DIR="${PHASE_SKIP_LIB_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)}"

# _fingerprint_file(repo_root, stage)
_fingerprint_file() {
  local root="${1:-.}"
  local stage="${2:?stage required}"
  printf "%s/.handoffs/%s.fingerprint.json" "${root%/}" "$stage"
}

# artifact_hash(path)
# Prints sha256 of file content, or "" if the file doesn't exist.
artifact_hash() {
  local path="${1:?artifact_hash: path required}"
  [[ -f "$path" ]] || { printf ""; return 0; }
  sha256sum "$path" 2>/dev/null | awk '{print $1}'
}

# artifact_hash_inline(content)
# Prints sha256 of a literal string (for values not backed by a file).
artifact_hash_inline() {
  local content="${1:-}"
  printf '%s' "$content" | sha256sum | awk '{print $1}'
}

# record_fingerprint(stage, fingerprint_json, [repo_root])
# Writes .handoffs/<stage>.fingerprint.json. fingerprint_json MUST already
# be a complete JSON object (caller builds it via jq with artifact entries).
record_fingerprint() {
  local stage="${1:?record_fingerprint: stage required}"
  local body="${2:?record_fingerprint: json required}"
  local root="${3:-.}"
  mkdir -p "$root/.handoffs"
  local ts
  ts=$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date -u)
  # Normalize: ensure stage + recorded_at + artifacts exist.
  jq -c --arg s "$stage" --arg ts "$ts" '
    {
      stage: $s,
      recorded_at: $ts,
      artifacts: (.artifacts // [])
    }
  ' <<< "$body" > "$(_fingerprint_file "$root" "$stage")"
  printf "%s" "$(_fingerprint_file "$root" "$stage")"
}

# read_fingerprint(stage, [repo_root])
# Emits the recorded fingerprint JSON, or "{}" if not present.
read_fingerprint() {
  local stage="${1:?read_fingerprint: stage required}"
  local root="${2:-.}"
  local file
  file=$(_fingerprint_file "$root" "$stage")
  [[ -f "$file" ]] || { printf "{}"; return 0; }
  cat "$file"
}

# should_skip_stage(stage, repo_root, artifact_path [artifact_path...])
# For each current artifact path, computes its sha256 (or inline hash if the
# path begins with "inline:<content>") and compares to the stored fingerprint.
# Exit 0 (skip) iff every artifact's current hash exactly equals the
# recorded hash for that path. Exit 1 (don't skip) on any mismatch, missing
# record, or missing file.
#
# Example:
#   should_skip_stage brainstorm . docs/plans/x.md "inline:$USER_INTENT_TEXT"
should_skip_stage() {
  local stage="${1:?should_skip_stage: stage required}"
  local root="${2:?should_skip_stage: repo_root required}"
  shift 2
  local fp
  fp=$(read_fingerprint "$stage" "$root")
  [[ "$fp" == "{}" ]] && return 1  # no record => can't skip
  local recorded_count
  recorded_count=$(printf '%s' "$fp" | jq '.artifacts | length')
  [[ "$recorded_count" -eq 0 ]] && return 1
  local current_count=$#
  [[ "$current_count" -ne "$recorded_count" ]] && return 1
  local path cur_hash recorded_hash
  for path in "$@"; do
    if [[ "$path" == inline:* ]]; then
      cur_hash=$(artifact_hash_inline "${path#inline:}")
      local key="inline://${path#inline:}"
      # Special case: we stored with logical key form.
    else
      cur_hash=$(artifact_hash "$path")
      local key="$path"
    fi
    [[ -z "$cur_hash" ]] && return 1  # missing file means not fresh
    recorded_hash=$(printf '%s' "$fp" | \
      jq -r --arg p "$key" '.artifacts[]? | select(.path == $p) | .sha256')
    [[ -z "$recorded_hash" ]] && return 1
    [[ "$cur_hash" != "$recorded_hash" ]] && return 1
  done
  return 0  # every artifact fresh
}

# ------------------------------------------------------------------------------
# CLI entry
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  set -euo pipefail
  subcmd="${1:-}"
  shift || true
  case "$subcmd" in
    hash)    artifact_hash "$@"; printf "\n" ;;
    inline)  artifact_hash_inline "$@"; printf "\n" ;;
    record)  record_fingerprint "$@" ;;
    read)    read_fingerprint "$@" ;;
    skip)    should_skip_stage "$@" ;;
    *)
      cat >&2 <<USAGE
Usage: bash lib/phase-skip.sh <subcmd> [args...]
  hash PATH                              — sha256 of file
  inline CONTENT                         — sha256 of literal
  record STAGE JSON [REPO_ROOT]          — write fingerprint
  read   STAGE [REPO_ROOT]               — read fingerprint JSON
  skip   STAGE REPO_ROOT PATH [PATH...]  — exit 0 if all fresh
USAGE
      exit 2
      ;;
  esac
fi
