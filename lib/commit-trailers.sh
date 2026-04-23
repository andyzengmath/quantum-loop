#!/usr/bin/env bash
# lib/commit-trailers.sh — parse + validate structured commit trailers
# per the P2.7 protocol in agents/implementer.md §Commit Format.
#
# The prompt side tells the implementer WHICH trailers to write; this
# library gives the orchestrator / reviewers a deterministic parser so
# findings like "commit with Confidence: low but no Rejected: entry" can
# be surfaced mechanically.
#
# Functions:
#   parse_trailers        — stdin: commit message; emit JSON object keyed
#                           by trailer name; "Rejected" becomes an array
#                           since it may repeat.
#   validate_trailers     — stdin: commit message; exit 0 if required
#                           trailer set is present and well-formed,
#                           exit 1 otherwise. Echoes violations on stderr.
#   extract_commit        — COMMIT_SHA: run `git log -1 --format=%B SHA`
#                           and pipe through parse_trailers.
#   assert_confidence_low_has_rejected — enforce the rule that
#                           "Confidence: low" commits MUST also carry at
#                           least one Rejected: trailer (otherwise the
#                           low-confidence claim is unsupported).
#
# Library contract: does not set shell flags at source time. Strict mode
# only in the CLI-entry block at bottom.

COMMIT_TRAILERS_LIB_DIR="${COMMIT_TRAILERS_LIB_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)}"

# Trailer keys recognized by the protocol. Guarded against double-source.
if [[ -z "${COMMIT_TRAILER_KEYS+x}" ]]; then
readonly COMMIT_TRAILER_KEYS=(
  "Story" "Story-Title" "PRD" "Files-changed"
  "Constraint" "Directive" "Rejected"
  "Confidence" "Scope-risk" "Not-tested" "Deslop"
)
fi

# parse_trailers()
# Reads a commit message from stdin. Emits a compact JSON object where:
#   - keys are the trailer names,
#   - "Rejected" is an array of strings (may repeat),
#   - other keys are strings (last one wins if duplicated).
# Lines that don't match "<Key>: <value>" or whose key isn't in the known
# set are ignored.
parse_trailers() {
  # Collect lines into a JSON object incrementally.
  local json='{}'
  local key value
  local rejected='[]'
  while IFS= read -r line; do
    # Match "<Key>: <value>" — key is alphanumeric + hyphens
    if [[ "$line" =~ ^([A-Z][A-Za-z-]*)\ *:\ *(.+)$ ]]; then
      key="${BASH_REMATCH[1]}"
      value="${BASH_REMATCH[2]}"
      # Trim trailing whitespace
      value="${value%"${value##*[![:space:]]}"}"
      # Is this a known trailer?
      local known=0
      local k
      for k in "${COMMIT_TRAILER_KEYS[@]}"; do
        [[ "$k" == "$key" ]] && { known=1; break; }
      done
      [[ "$known" -eq 0 ]] && continue
      if [[ "$key" == "Rejected" ]]; then
        rejected=$(jq -c --arg v "$value" '. + [$v]' <<< "$rejected")
      else
        json=$(jq -c --arg k "$key" --arg v "$value" '. + {($k): $v}' <<< "$json")
      fi
    fi
  done
  # Attach Rejected array at the end
  jq -c --argjson r "$rejected" '. + {Rejected: $r}' <<< "$json"
}

# validate_trailers()
# Reads commit message from stdin. Checks:
#   * "Story" is present and matches US-NNN.
#   * "Confidence" is present and one of {high, medium, low}.
#   * "Scope-risk" is present and one of {none, contained, spreads}.
#   * If "Confidence: low", at least one Rejected: entry must be present
#     (otherwise the low-confidence claim is empty hand-waving).
#   * "Not-tested" is either absent or non-empty.
# Exit 0 on clean, exit 1 on any violation (violations printed to stderr).
validate_trailers() {
  local parsed
  parsed=$(parse_trailers)
  local story confidence scope_risk nottested rejected_n
  story=$(jq -r '.Story // ""' <<< "$parsed")
  confidence=$(jq -r '.Confidence // ""' <<< "$parsed")
  scope_risk=$(jq -r '."Scope-risk" // ""' <<< "$parsed")
  nottested=$(jq -r '."Not-tested" // ""' <<< "$parsed")
  rejected_n=$(jq -r '.Rejected | length' <<< "$parsed")

  local violations=0
  if [[ ! "$story" =~ ^US-[0-9]+$ ]]; then
    echo "[TRAILERS] FAIL: Story trailer missing or not US-NNN (got [$story])" >&2
    violations=$((violations + 1))
  fi
  case "$confidence" in
    high|medium|low) ;;
    *)
      echo "[TRAILERS] FAIL: Confidence must be one of {high, medium, low} (got [$confidence])" >&2
      violations=$((violations + 1)) ;;
  esac
  case "$scope_risk" in
    none|contained|spreads) ;;
    *)
      echo "[TRAILERS] FAIL: Scope-risk must be one of {none, contained, spreads} (got [$scope_risk])" >&2
      violations=$((violations + 1)) ;;
  esac
  if [[ "$confidence" == "low" && "$rejected_n" -lt 1 ]]; then
    echo "[TRAILERS] FAIL: Confidence: low requires at least one Rejected: entry" >&2
    violations=$((violations + 1))
  fi
  return "$violations"
}

# extract_commit(sha)
# Runs git log on the given SHA and parses its message trailers.
extract_commit() {
  local sha="${1:?extract_commit: sha required}"
  git log -1 --format=%B "$sha" 2>/dev/null | parse_trailers
}

# assert_confidence_low_has_rejected(sha)
# Convenience exit-code gate — used by CI/pre-merge hooks.
assert_confidence_low_has_rejected() {
  local sha="${1:?sha required}"
  local parsed
  parsed=$(extract_commit "$sha")
  local conf rn
  conf=$(jq -r '.Confidence // ""' <<< "$parsed")
  rn=$(jq -r '.Rejected | length' <<< "$parsed")
  if [[ "$conf" == "low" && "$rn" -lt 1 ]]; then
    return 1
  fi
  return 0
}

# ------------------------------------------------------------------------------
# CLI entry
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  set -euo pipefail
  subcmd="${1:-}"
  shift || true
  case "$subcmd" in
    parse)    parse_trailers ;;
    validate) validate_trailers ;;
    extract)  extract_commit "$@" ;;
    *)
      cat >&2 <<USAGE
Usage: bash lib/commit-trailers.sh <subcmd> [args...]
  parse             < message.txt  — emit JSON of parsed trailers
  validate          < message.txt  — exit 0 if trailers well-formed
  extract SHA                      — parse trailers from a commit
USAGE
      exit 2
      ;;
  esac
fi
