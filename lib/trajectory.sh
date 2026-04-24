#!/usr/bin/env bash
# lib/trajectory.sh — trajectory-length early kill (Phase 24 / P3.5).
#
# Sources:
#   arXiv:2511.00197 — trajectory features (step count, read/edit ratio)
#                      predict story success/failure early
#   TRAJEVAL 2603.24631 — benchmark showing thrashing agents (high read-
#                         to-edit ratio) rarely recover without intervention
#
# Complements lib/watchdog.sh which tracks wall-clock staleness. This
# library tracks the SHAPE of the agent's work: how many tool calls did it
# make, how many were reads/greps vs edits/writes, is it making progress?
#
# An agent stuck in a read/grep loop without making edits is usually lost.
# Better to kill it early, log the trajectory, and let the retry path do
# something different (different agent, clearer prompt, smaller scope).
#
# Functions:
#   parse_trajectory OUTPUT_FILE
#     Scans an agent's stdout file for tool-call patterns. Emits JSON
#     with counts per category plus derived ratios.
#   classify_trajectory JSON
#     Returns one of: productive | searching | thrashing | stuck.
#   should_early_kill JSON
#     Exit 0 if trajectory suggests kill (thrashing or stuck). Exit 1
#     otherwise. Caller threads this into the monitor loop alongside
#     the time-based watchdog.
#
# Library contract: no shell flags at source time; CLI block enables
# strict mode locally.

TRAJECTORY_LIB_DIR="${TRAJECTORY_LIB_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)}"

# Tuning knobs, all env-overrideable.
: "${TRAJECTORY_THRASH_MIN_CALLS:=20}"   # need at least this many calls to call it thrashing
: "${TRAJECTORY_STUCK_MIN_CALLS:=30}"    # after this many calls with 0 edits, we're stuck
: "${TRAJECTORY_THRASH_READ_RATIO:=70}"  # % of calls that are reads/greps to flag thrashing
: "${TRAJECTORY_THRASH_EDIT_RATIO:=5}"   # edits/writes must stay below this % to be thrashing

# parse_trajectory(output_file)
# Parses a Claude Code agent's stdout dump for tool-call markers. We look
# for the common patterns Claude emits when it invokes a tool:
#   "Tool use: Read"  /  "Tool: Grep"  /  "⏺ Edit(..."  /  "Calling Bash"
# Emits a compact JSON object with counts and derived ratios.
#
# Since Claude's output format varies across CLI versions, we use a
# deliberately broad set of patterns per tool and dedup by line number.
parse_trajectory() {
  local out="${1:?output_file required}"
  [[ -f "$out" ]] || {
    jq -cn '{total_calls: 0, reads: 0, greps: 0, edits: 0, writes: 0, bashes: 0, other: 0, read_edit_ratio: 0, exists: false}'
    return 0
  }

  # Per-tool regex patterns (case-insensitive, broad)
  local reads greps edits writes bashes other_calls
  reads=$(grep -cE "(⏺|•|\*) (Read|Tool: Read|Tool use: Read)|tool.?use.*\"?name\"?:.?\"?Read\"?" "$out" 2>/dev/null || echo 0)
  greps=$(grep -cE "(⏺|•|\*) (Grep|Glob|Search|Tool: Grep)|tool.?use.*\"?name\"?:.?\"?Grep\"?" "$out" 2>/dev/null || echo 0)
  edits=$(grep -cE "(⏺|•|\*) (Edit|MultiEdit|Tool: Edit)|tool.?use.*\"?name\"?:.?\"?(Edit|MultiEdit)\"?" "$out" 2>/dev/null || echo 0)
  writes=$(grep -cE "(⏺|•|\*) (Write|Tool: Write)|tool.?use.*\"?name\"?:.?\"?Write\"?" "$out" 2>/dev/null || echo 0)
  bashes=$(grep -cE "(⏺|•|\*) (Bash|Tool: Bash)|tool.?use.*\"?name\"?:.?\"?Bash\"?" "$out" 2>/dev/null || echo 0)
  # "other" = generic tool-use marker not matching specific names
  other_calls=$(grep -cE "(⏺|•|\*) (Agent|Task|Glob|TodoWrite|WebFetch|Git|NotebookEdit)" "$out" 2>/dev/null || echo 0)
  # Trim whitespace
  reads=$(echo "$reads" | tr -d ' \n')
  greps=$(echo "$greps" | tr -d ' \n')
  edits=$(echo "$edits" | tr -d ' \n')
  writes=$(echo "$writes" | tr -d ' \n')
  bashes=$(echo "$bashes" | tr -d ' \n')
  other_calls=$(echo "$other_calls" | tr -d ' \n')

  local total=$(( reads + greps + edits + writes + bashes + other_calls ))
  local prod=$(( edits + writes ))
  # ratio as integer %, avoid div-by-zero
  local read_pct=0 edit_pct=0
  if (( total > 0 )); then
    read_pct=$(( (reads + greps) * 100 / total ))
    edit_pct=$(( prod * 100 / total ))
  fi
  jq -cn \
    --argjson r "$reads" --argjson g "$greps" --argjson e "$edits" \
    --argjson w "$writes" --argjson b "$bashes" --argjson o "$other_calls" \
    --argjson total "$total" --argjson rp "$read_pct" --argjson ep "$edit_pct" \
    '{total_calls: $total, reads: $r, greps: $g, edits: $e, writes: $w,
      bashes: $b, other: $o, read_pct: $rp, edit_pct: $ep, exists: true}'
}

# classify_trajectory(json)
# Echoes one of: productive | searching | thrashing | stuck.
# Rules:
#   stuck       — total_calls >= STUCK_MIN and edits+writes == 0
#   thrashing   — total_calls >= THRASH_MIN AND read_pct >= THRASH_READ_RATIO
#                 AND edit_pct <= THRASH_EDIT_RATIO
#   searching   — read_pct > 50 (early exploration, OK so far)
#   productive  — otherwise
classify_trajectory() {
  local json="${1:-}"
  [[ -z "$json" ]] && json=$(cat)
  local total rp ep prod
  total=$(jq -r '.total_calls // 0' <<< "$json")
  rp=$(jq -r '.read_pct // 0' <<< "$json")
  ep=$(jq -r '.edit_pct // 0' <<< "$json")
  prod=$(jq -r '(.edits // 0) + (.writes // 0)' <<< "$json")

  if (( total >= TRAJECTORY_STUCK_MIN_CALLS && prod == 0 )); then
    printf "stuck"; return 0
  fi
  if (( total >= TRAJECTORY_THRASH_MIN_CALLS \
       && rp >= TRAJECTORY_THRASH_READ_RATIO \
       && ep <= TRAJECTORY_THRASH_EDIT_RATIO )); then
    printf "thrashing"; return 0
  fi
  if (( rp > 50 )); then
    printf "searching"; return 0
  fi
  printf "productive"
}

# should_early_kill(json)
# Exit 0 if classification is "thrashing" or "stuck" (caller should kill
# the agent). Exit 1 otherwise.
should_early_kill() {
  local cls
  cls=$(classify_trajectory "$@")
  case "$cls" in
    thrashing|stuck) return 0 ;;
    *)               return 1 ;;
  esac
}

# ------------------------------------------------------------------------------
# CLI entry
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  set -euo pipefail
  subcmd="${1:-}"
  shift || true
  case "$subcmd" in
    parse)    parse_trajectory "$@" ;;
    classify) classify_trajectory "$@"; printf "\n" ;;
    kill)     should_early_kill "$@" ;;
    *)
      cat >&2 <<USAGE
Usage: bash lib/trajectory.sh <subcmd> [args...]
  parse OUTPUT_FILE               — emit JSON with tool-call counts and ratios
  classify [JSON]                 — one of productive|searching|thrashing|stuck
  kill [JSON]                     — exit 0 if thrashing or stuck
USAGE
      exit 2
      ;;
  esac
fi
