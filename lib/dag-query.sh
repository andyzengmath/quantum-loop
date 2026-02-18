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
        [.[].id] | join("\n")
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
