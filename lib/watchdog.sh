#!/usr/bin/env bash
# lib/watchdog.sh — task watchdog + circuit breaker (P2.6, OMC pattern).
#
# Sits above lib/monitor.sh's kill_agent_process + check_agent_timeout
# primitives. Provides:
#
#   classify_age        — map "seconds since startedAt" to
#                         fresh | stale-check | stale-reassign | timed-out.
#   watchdog_poll       — walk quantum.json.stories[] in_progress entries,
#                         emit actionable JSON per stale story.
#   error_counter_bump  — increment a consecutive-same-error counter for
#                         a story, stored under $state_dir/<story>.errcount.
#   error_counter_reset — reset counter (call on any not-same-error outcome).
#   should_circuit_break— returns 0 (yes) when consecutive-same-error count
#                         for a story reaches the threshold (default 3).
#
# Thresholds (all env-overrideable):
#   WATCHDOG_FRESH_SECS=300          # ≤5 min = fresh, no action
#   WATCHDOG_STALE_CHECK_SECS=600    # 5-10 min = status check
#   WATCHDOG_STALE_REASSIGN_SECS=1200# 10-20 min = reassign
#   WATCHDOG_TIMEOUT_SECS=1800       # >20 min = timeout (kill + mark failed)
#   WATCHDOG_CIRCUIT_THRESHOLD=3     # N consecutive same-error failures
#
# Library contract: no shell flags at source time. CLI block enables
# strict mode locally (same pattern as Phase 5/8/9/11/12/14/15 libs).

WATCHDOG_LIB_DIR="${WATCHDOG_LIB_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)}"

: "${WATCHDOG_FRESH_SECS:=300}"
: "${WATCHDOG_STALE_CHECK_SECS:=600}"
: "${WATCHDOG_STALE_REASSIGN_SECS:=1200}"
: "${WATCHDOG_TIMEOUT_SECS:=1800}"
: "${WATCHDOG_CIRCUIT_THRESHOLD:=3}"

# classify_age(age_seconds)
# Echoes one of: fresh | stale-check | stale-reassign | timed-out.
classify_age() {
  local age="${1:?classify_age: age_seconds required}"
  if   (( age <= WATCHDOG_FRESH_SECS ));          then printf "fresh"
  elif (( age <= WATCHDOG_STALE_CHECK_SECS ));    then printf "stale-check"
  elif (( age <= WATCHDOG_STALE_REASSIGN_SECS )); then printf "stale-reassign"
  elif (( age <= WATCHDOG_TIMEOUT_SECS ));        then printf "stale-reassign"
  else printf "timed-out"
  fi
}

# _now_epoch()
# Echoes current Unix epoch seconds.
_now_epoch() {
  date -u +%s
}

# _iso_to_epoch(iso8601)
# Converts ISO 8601 timestamp (e.g., "2026-04-23T10:00:00Z") to epoch seconds.
# Uses python3 (cross-platform) rather than GNU date -d (unavailable on BSD).
_iso_to_epoch() {
  local iso="${1:?_iso_to_epoch: iso8601 required}"
  python3 -c "
import sys, datetime
s = sys.argv[1].replace('Z', '+00:00')
print(int(datetime.datetime.fromisoformat(s).timestamp()))
" "$iso" 2>/dev/null
}

# watchdog_poll(quantum_json_path)
# Walk stories[] in_progress entries; emit JSON array of actionable items:
#   [ {story_id, started_at, age_seconds, classification, recommended_action},
#     ... ]
# classification uses classify_age; recommended_action:
#   fresh          -> "continue"
#   stale-check    -> "status-probe"
#   stale-reassign -> "kill-and-requeue"
#   timed-out      -> "mark-failed"
watchdog_poll() {
  local qj="${1:?watchdog_poll: quantum.json path required}"
  [[ -f "$qj" ]] || { printf "[]"; return 0; }
  local now
  now=$(_now_epoch)
  local entries
  entries=$(jq -c '.stories[]? | select(.status == "in_progress" and .startedAt)' "$qj")
  local out='[]'
  local line
  while IFS= read -r line; do
    [[ -z "$line" ]] && continue
    local sid started_at
    sid=$(jq -r '.id' <<< "$line")
    started_at=$(jq -r '.startedAt' <<< "$line")
    local ep age classification action
    ep=$(_iso_to_epoch "$started_at")
    [[ -z "$ep" ]] && continue
    age=$(( now - ep ))
    classification=$(classify_age "$age")
    case "$classification" in
      fresh)          action="continue" ;;
      stale-check)    action="status-probe" ;;
      stale-reassign) action="kill-and-requeue" ;;
      timed-out)      action="mark-failed" ;;
    esac
    out=$(jq -c \
      --arg sid "$sid" --arg sa "$started_at" \
      --argjson age "$age" --arg cls "$classification" --arg act "$action" \
      '. + [{story_id: $sid, started_at: $sa, age_seconds: $age,
             classification: $cls, recommended_action: $act}]' \
      <<< "$out")
  done <<< "$entries"
  printf "%s" "$out"
}

# _counter_file(state_dir, story_id)
_counter_file() {
  printf "%s/%s.errcount" "${1%/}" "$2"
}

# error_counter_bump(state_dir, story_id, error_signature)
# Increments the consecutive-same-error counter for a story if the new
# error_signature matches the last recorded one; otherwise RESETS the
# counter to 1 with the new signature. Emits the new count on stdout.
#
# File format (two lines):
#   <count>
#   <sha256-of-error-signature>
error_counter_bump() {
  local state_dir="${1:?error_counter_bump: state_dir required}"
  local sid="${2:?error_counter_bump: story_id required}"
  local sig="${3:?error_counter_bump: error_signature required}"
  mkdir -p "$state_dir"
  local file
  file=$(_counter_file "$state_dir" "$sid")
  local hash
  hash=$(printf '%s' "$sig" | sha256sum | awk '{print $1}')
  local count=1
  if [[ -f "$file" ]]; then
    local prev_count prev_hash
    prev_count=$(sed -n '1p' "$file" 2>/dev/null || echo 0)
    prev_hash=$(sed -n '2p' "$file" 2>/dev/null || echo "")
    if [[ "$prev_hash" == "$hash" ]]; then
      count=$(( prev_count + 1 ))
    fi
  fi
  {
    printf "%s\n" "$count"
    printf "%s\n" "$hash"
  } > "$file"
  printf "%s" "$count"
}

# error_counter_reset(state_dir, story_id)
# Removes the counter file for the story. Call on any pass or any
# different-error outcome to prevent spurious circuit breaks.
error_counter_reset() {
  local state_dir="${1:?error_counter_reset: state_dir required}"
  local sid="${2:?error_counter_reset: story_id required}"
  rm -f "$(_counter_file "$state_dir" "$sid")"
}

# should_circuit_break(state_dir, story_id, [threshold])
# Exit 0 (yes, break the circuit) if the stored count ≥ threshold.
# Exit 1 otherwise. Default threshold: $WATCHDOG_CIRCUIT_THRESHOLD.
should_circuit_break() {
  local state_dir="${1:?should_circuit_break: state_dir required}"
  local sid="${2:?should_circuit_break: story_id required}"
  local threshold="${3:-$WATCHDOG_CIRCUIT_THRESHOLD}"
  local file
  file=$(_counter_file "$state_dir" "$sid")
  [[ -f "$file" ]] || return 1
  local count
  count=$(sed -n '1p' "$file" 2>/dev/null || echo 0)
  if (( count >= threshold )); then
    return 0
  fi
  return 1
}

# ------------------------------------------------------------------------------
# CLI entry
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  set -euo pipefail
  subcmd="${1:-}"
  shift || true
  case "$subcmd" in
    classify)     classify_age "$@"; printf "\n" ;;
    poll)         watchdog_poll "$@" ;;
    bump)         error_counter_bump "$@"; printf "\n" ;;
    reset)        error_counter_reset "$@" ;;
    circuit)      should_circuit_break "$@" ;;
    *)
      cat >&2 <<USAGE
Usage: bash lib/watchdog.sh <subcmd> [args...]
  classify AGE_SECONDS                        — fresh | stale-check | stale-reassign | timed-out
  poll QUANTUM_JSON                           — emit actionable JSON per in-progress story
  bump STATE_DIR STORY_ID SIGNATURE           — increment (or reset) counter, echo count
  reset STATE_DIR STORY_ID                    — clear counter
  circuit STATE_DIR STORY_ID [THRESHOLD]      — exit 0 if should break circuit
USAGE
      exit 2
      ;;
  esac
fi
