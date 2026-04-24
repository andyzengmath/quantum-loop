#!/usr/bin/env bash
# lib/reground.sh — periodic re-grounding of agent context (Phase 28 / P3.9).
#
# Sources:
#   arXiv:2603.00492 — "Context drift in long-horizon agents"
#   arXiv:2602.18822 — "Refresh-prompting mitigates goal drift in multi-
#                       step task agents by +23% success"
#
# Problem: after many stories, agents lose fidelity to the original PRD.
# Each iteration starts with a fresh context window, but the fresh context
# is populated only with `quantum.json` state + the story at hand — NOT
# with a reminder of the overall goal.
#
# Solution: every N stories, inject a re-grounding block into the
# implementer prompt that summarizes (a) the PRD goal, (b) progress so
# far, (c) the iron law of fresh-evidence verification. Cheap, and the
# cited paper shows measurable drift mitigation.
#
# Orthogonal to:
#   lib/watchdog.sh        — wall-clock staleness of a single agent
#   lib/trajectory.sh      — tool-shape thrashing within a single story
#   lib/constitution.sh    — regex-checkable invariants about generated code
#   This lib                — SESSION-level drift from the PRD
#
# Functions:
#   should_reground STATE_JSON
#     Exit 0 if iteration is at or past the next re-ground threshold.
#     Exit 1 otherwise. Threshold is REGROUND_INTERVAL stories since
#     lastGroundedIteration (tracked in state).
#
#   build_reground_context QUANTUM_JSON
#     Emits a markdown block summarizing goal + progress + reminders.
#     Designed to be prepended to the next implementer prompt.
#
#   mark_grounded QUANTUM_JSON_PATH
#     Sets .state.lastGroundedIteration = .iteration in the file. Uses
#     a temp file + atomic rename.
#
# Library contract: no shell flags at source time; CLI block enables
# strict mode locally.

REGROUND_LIB_DIR="${REGROUND_LIB_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)}"

: "${REGROUND_INTERVAL:=5}"     # re-ground every N stories by default
: "${REGROUND_PRD_HEAD_LINES:=20}"  # how many lines of PRD to include
: "${REGROUND_NEXT_STORIES:=3}"     # how many upcoming stories to preview

# should_reground(state_json)
# Returns exit 0 iff (iteration - lastGroundedIteration) >= REGROUND_INTERVAL.
# Rationale: we re-ground at fixed intervals regardless of story outcome,
# so a long streak of passes doesn't cause drift silently.
should_reground() {
  local state="${1:-}"
  [[ -z "$state" ]] && state=$(cat)
  local iter last
  iter=$(jq -r '.iteration // 0' <<< "$state")
  last=$(jq -r '.state.lastGroundedIteration // 0' <<< "$state")
  local delta=$(( iter - last ))
  if (( delta >= REGROUND_INTERVAL )); then
    return 0
  fi
  return 1
}

# build_reground_context(quantum_json)
# Emits a markdown-ish block on stdout. Safe on missing fields (uses //).
# Reads PRD file if .prdPath exists and is readable.
build_reground_context() {
  local q="${1:-}"
  [[ -z "$q" ]] && q=$(cat)
  local prd_path branch iter total passed failed pending
  prd_path=$(jq -r '.prdPath // ""' <<< "$q")
  branch=$(jq -r '.branchName // "(unknown)"' <<< "$q")
  iter=$(jq -r '.iteration // 0' <<< "$q")
  total=$(jq '.stories | length // 0' <<< "$q")
  passed=$(jq '[.stories[]? | select(.status == "passed")] | length' <<< "$q")
  failed=$(jq '[.stories[]? | select(.status == "failed")] | length' <<< "$q")
  pending=$(jq '[.stories[]? | select(.status == "pending")] | length' <<< "$q")

  {
    printf "## Re-grounding (iteration %s)\n\n" "$iter"
    printf "**Branch**: \`%s\`\n" "$branch"
    printf "**PRD**: \`%s\`\n" "${prd_path:-(not set)}"
    printf "**Progress**: %s/%s passed, %s failed, %s pending\n\n" \
      "$passed" "$total" "$failed" "$pending"
    printf "### Goal reminder\n\n"
    printf "Stay faithful to the PRD. Verify EACH claim with fresh evidence.\n"
    printf "Make small surgical changes — no speculative refactors.\n\n"
    if [[ -n "$prd_path" && -f "$prd_path" ]]; then
      printf "### PRD head (first %s lines)\n\n" "$REGROUND_PRD_HEAD_LINES"
      printf '```\n'
      head -n "$REGROUND_PRD_HEAD_LINES" "$prd_path"
      printf '\n```\n\n'
    fi
    printf "### Next %s pending stories\n\n" "$REGROUND_NEXT_STORIES"
    jq -r --argjson k "$REGROUND_NEXT_STORIES" \
      '[.stories[]? | select(.status == "pending")]
       | sort_by(.priority // 999)
       | .[0:$k]
       | .[]
       | "- **\(.id // "(no-id)")** (prio \(.priority // "?")): \(.title // "(no title)")"' \
      <<< "$q"
  }
}

# mark_grounded(quantum_json_path)
# Updates .state.lastGroundedIteration to .iteration in the file. Atomic
# via temp file + mv.
mark_grounded() {
  local path="${1:?path required}"
  [[ -f "$path" ]] || return 1
  local q iter
  q=$(cat "$path")
  iter=$(jq -r '.iteration // 0' <<< "$q")
  local tmp="${path}.reground.tmp"
  jq --argjson i "$iter" \
    '.state = (.state // {}) | .state.lastGroundedIteration = $i' \
    <<< "$q" > "$tmp"
  mv "$tmp" "$path"
}

# ------------------------------------------------------------------------------
# CLI entry
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  set -euo pipefail
  subcmd="${1:-}"
  shift || true
  case "$subcmd" in
    should)   should_reground "$@" ;;
    context)  build_reground_context "$@" ;;
    mark)     mark_grounded "$@" ;;
    *)
      cat >&2 <<USAGE
Usage: bash lib/reground.sh <subcmd> [args...]
  should  < state      — exit 0 if re-grounding is due
  context < quantum    — emit re-grounding markdown block
  mark    QUANTUM_PATH — update lastGroundedIteration in-place
USAGE
      exit 2
      ;;
  esac
fi
