#!/usr/bin/env bash
# lib/dag-query.sh -- DAG query functions for quantum-loop
# Source this file to use get_executable_stories() and detect_cycles()
# Requires: jq

# v0.9.2 / US-003: optional source of quantum-validate.sh for advisory hooks
# in next_wave's preamble. If the file is missing (older checkout / partial
# install), validate_story_filepaths is simply not defined and the call in
# next_wave is gated behind a `type` check.
_DAG_QUERY_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd)"
if [[ -f "$_DAG_QUERY_DIR/quantum-validate.sh" ]]; then
  # shellcheck source=lib/quantum-validate.sh
  source "$_DAG_QUERY_DIR/quantum-validate.sh"
fi

# get_executable_stories(quantum_json_path)
# Returns newline-separated list of executable story IDs, sorted by priority.
# Returns "COMPLETE" if all stories are passed.
# Returns "BLOCKED" if no stories are executable but some are not passed.
get_executable_stories() {
  local json_path="$1"

  jq -r '
    .stories as $all |

    # Check if all stories are passed
    if ($all | all(.status == "passed")) then
      "COMPLETE"
    else
      # Find eligible stories
      [
        $all[] |
        select(
          .status != "in_progress" and
          (
            .status == "pending" or
            (.status == "failed" and .retries.attempts < .retries.maxAttempts)
          )
          and
          (
            if (.dependsOn | length) == 0 then true
            else
              [.dependsOn[] | . as $dep | $all[] | select(.id == $dep) | .status] | all(. == "passed")
            end
          )
        )
      ] |
      sort_by(.priority // 999) |
      if length == 0 then
        "BLOCKED"
      else
        [.[].id]
      end
    end
  ' "$json_path"
}

# detect_cycles(quantum_json_path)
# Checks for cycles by attempting DFS-based topological sort.
# Prints "CYCLE_DETECTED" and returns 1 if a cycle is found.
# Prints "NO_CYCLES" and returns 0 if acyclic.
detect_cycles() {
  local json_path="$1"

  local result
  result=$(jq -r '
    .stories as $stories |
    ($stories | length) as $n |

    # Simple cycle detection: for each story, follow dependsOn chain.
    # If we visit more nodes than exist, there is a cycle.
    # We use iterative deepening: for each story, walk ancestors up to $n steps.
    [
      $stories[] |
      .id as $start |
      {current: [.dependsOn[]], visited: [.id], depth: 0, has_cycle: false} |
      until(
        .has_cycle or (.current | length) == 0 or .depth >= $n;
        .current[0] as $node |
        if ([.visited[] | select(. == $node)] | length) > 0 then
          .has_cycle = true
        else
          # Get dependencies of $node
          ([$stories[] | select(.id == $node) | .dependsOn[]] // []) as $next_deps |
          .visited += [$node] |
          .current = (.current[1:] + $next_deps) |
          .depth += 1
        end
      ) |
      .has_cycle
    ] |
    if any then "CYCLE_DETECTED" else "NO_CYCLES" end
  ' "$json_path")

  printf "%s\n" "$result"
  if [[ "$result" == *"CYCLE"* ]]; then
    return 1
  fi
  return 0
}

# filter_file_conflicts(quantum_json_path, eligible_ids_json_array)
# Given a JSON array of eligible story IDs, filters out stories that share
# file paths (via tasks[].filePaths or fileConflicts) with higher-priority
# stories in the same wave. Returns a filtered JSON array.
#
# Example: filter_file_conflicts quantum.json '["US-001","US-002","US-003"]'
filter_file_conflicts() {
  local json_path="$1"
  local eligible="$2"

  if [[ -z "$json_path" || ! -f "$json_path" ]]; then
    printf "ERROR: filter_file_conflicts requires a valid JSON file path\n" >&2
    return 1
  fi
  if [[ -z "$eligible" ]]; then
    printf "ERROR: filter_file_conflicts requires eligible IDs JSON array\n" >&2
    return 1
  fi

  jq -r --argjson eligible "$eligible" '
    .stories as $all |
    .fileConflicts as $fc |

    # Collect files already claimed by in_progress stories (from prior waves).
    # This prevents cross-wave file conflicts when a new wave spawns while
    # a previous wave is still running.
    (
      [ $all[] | select(.status == "in_progress") |
        .tasks[]? | .filePaths[]?
      ]
    ) as $in_progress_files |

    # Build a map of story_id -> set of file paths (from tasks)
    (
      [ $all[] | select(.id as $id | $eligible | index($id)) |
        {id: .id, priority: (.priority // 999),
         files: [.tasks[]? | .filePaths[]?]}
      ] | sort_by(.priority)
    ) as $eligible_stories |

    # Also include fileConflicts entries
    (
      [$fc[]? | {file: .file, stories: .stories}]
    ) as $conflict_entries |

    # Greedily select stories: for each story in priority order,
    # include it only if none of its files overlap with already-selected stories
    # OR with in_progress stories from prior waves.
    # Note: we bind the accumulator to named variables ($claimed, $sel) inside
    # the reduce body because jq `env` refers to shell $ENV, not the accumulator.
    reduce $eligible_stories[] as $story (
      {selected: [], claimed_files: $in_progress_files};
      .claimed_files as $claimed |
      .selected as $sel |
      if (
            # Check filePaths overlap: every file in this story must NOT already
            # be claimed. Use index() for exact-match (not inside/substring).
            ([$story.files[] | select(. as $f | $claimed | index($f) | not)]
             | length) == ($story.files | length)
         )
         and
         (
           # Check fileConflicts: no conflict entry includes both this story
           # and an already-selected story
           [ $conflict_entries[] |
             select(
               (.stories | index($story.id)) and
               ([.stories[] | . as $s | select(
                 [$sel[].id] | index($s)
               )] | length > 0)
             )
           ] | length == 0
         )
      then
        .selected += [$story] |
        .claimed_files += $story.files
      else
        .
      end
    ) |
    [.selected[].id]
  ' "$json_path"
}

# next_wave(quantum_json_path)
# v0.9.0 / US-002 (N42 minor) — thin composer over get_executable_stories
# + filter_file_conflicts. Returns the next wave of parallel-safe story IDs
# for coordinator-driven dispatch.
#
# Architectural rationale: coordinators (agents/coordinator.md) consume a
# WAVE of stories per invocation. v0.9.0 N42 wires the parent loop
# (quantum-loop.sh) to call next_wave under COORDINATOR_MODE=true and pass
# the wave's story_ids to spawn_coordinator. Per-iteration semantics: ONE
# wave = ONE coordinator spawn = ONE parent iteration.
#
# Output: JSON array of story IDs on stdout (e.g., ["US-001","US-003"]).
# Empty array is NEVER printed — the function returns a non-zero exit code
# instead, allowing callers to use plain rc-based dispatch (no
# string-sentinel parsing).
#
# Exit codes:
#   0 — wave found; JSON array printed to stdout (≥1 story ID)
#   1 — all stories passed (COMPLETE); nothing printed
#   2 — no eligible stories remain but not all passed (BLOCKED); nothing printed
#
# Usage:
#   wave=$(next_wave quantum.json)
#   case $? in
#     0) dispatch_wave "$wave" ;;
#     1) printf "<quantum>COMPLETE</quantum>\n"; exit 0 ;;
#     2) printf "<quantum>BLOCKED</quantum>\n"; exit 1 ;;
#   esac
next_wave() {
  local json_path="${1:?next_wave requires a quantum.json path}"

  if [[ ! -f "$json_path" ]]; then
    printf "ERROR: next_wave: quantum.json not found at %s\n" "$json_path" >&2
    return 2
  fi

  # v0.9.2 / US-003: advisory preamble. Warn (stderr) on stories with empty
  # filePaths in their tasks (would silently bypass filter_file_conflicts).
  # Gated behind `type` check so this is a no-op if quantum-validate.sh is
  # missing (older checkout). Never blocks — return code ignored.
  if type validate_story_filepaths >/dev/null 2>&1; then
    validate_story_filepaths "$json_path" || true
  fi

  local raw
  raw=$(get_executable_stories "$json_path")

  # Map COMPLETE/BLOCKED string sentinels to exit codes (no stdout output).
  case "$raw" in
    COMPLETE) return 1 ;;
    BLOCKED|"") return 2 ;;
  esac

  # Defensive: confirm $raw is a JSON array (guards against silent
  # contract drift in get_executable_stories' output format).
  local raw_type
  raw_type=$(echo "$raw" | jq -r 'type' 2>/dev/null)
  if [[ "$raw_type" != "array" ]]; then
    printf "ERROR: next_wave: get_executable_stories returned unexpected type '%s' (expected array)\n" "$raw_type" >&2
    return 2
  fi

  # Apply file-conflict filter (also excludes files claimed by in_progress
  # stories from prior waves, per dag-query.sh:115-122).
  local wave
  wave=$(filter_file_conflicts "$json_path" "$raw")

  # Empty filtered wave → BLOCKED (transient if in_progress stories release
  # files; permanent if eligible set is empty for other reasons). v0.9.0
  # treats both uniformly as rc=2; v0.9.1+ may distinguish if needed.
  local wave_len
  wave_len=$(echo "$wave" | jq 'length' 2>/dev/null)
  if [[ -z "$wave_len" || "$wave_len" -eq 0 ]]; then
    return 2
  fi

  printf '%s\n' "$wave"
  return 0
}
