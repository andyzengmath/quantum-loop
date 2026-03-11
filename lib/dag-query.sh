#!/usr/bin/env bash
# lib/dag-query.sh -- DAG query functions for quantum-loop
# Source this file to use get_executable_stories() and detect_cycles()
# Requires: jq

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

  echo "$result"
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
    # include it only if none of its files overlap with already-selected stories.
    # Note: we bind the accumulator to named variables ($claimed, $sel) inside
    # the reduce body because jq `env` refers to shell $ENV, not the accumulator.
    reduce $eligible_stories[] as $story (
      {selected: [], claimed_files: []};
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
