#!/usr/bin/env bash
# lib/loop-helpers.sh -- quantum-loop iteration helpers (v0.9.5 / US-001 decomposition).
#
# Extracted from quantum-loop.sh in v0.9.5 / US-001 (decomposition refactor;
# spike 1 from idea-stage/v0.10.0-design-spike-2026-05-01.md). Source from
# quantum-loop.sh AFTER lib/runner.sh (uses RUNNER_NAME) and BEFORE the
# main iteration loop.
#
# Functions exported to caller's scope:
#   print_summary_table         -- prints Summary header + per-story status table
#   detect_stale_stories        -- detects in_progress stories with stale startedAt
#   validate_and_run_test_cmd   -- validates test cmd from stories[].test_cmd + runs
#   final_verification_sweep    -- post-COMPLETE sweep over all stories' test cmds
#   generate_observations       -- emits docs/post-mortems/<date>-<branch>-observations.md
#   emit_terminal_signal        -- v0.9.6 / US-002: prints separator-wrapped <quantum>SIGNAL</quantum>
#                                  with optional human message (COMPLETE / BLOCKED dedup helper)
#
# Required globals (set in quantum-loop.sh before sourcing):
#   - $BRANCH (string; current branch name)
#   - $RUNNER_NAME, $RUNNER_BINARY, $RUNNER_TIER, $RUNNER_INSTRUCTION_NATIVE
#   - $MAX_ITERATIONS, $MAX_RETRIES
#   - $PARALLEL_MODE, $MAX_PARALLEL
#   - $STALE_TIMEOUT
#   - $NON_INTERACTIVE (optional; default unset → treated as false)
#
# Library contract: no shell flags at source time; parent's set -euo pipefail
# carries through naturally.

# Source-guard
if [[ -n "${_QL_LOOP_HELPERS_LIB:-}" ]]; then
  return 0 2>/dev/null || true
fi
readonly _QL_LOOP_HELPERS_LIB=1

# =============================================================================
# Summary table function
# =============================================================================

print_summary_table() {
  printf "\n"
  printf "Summary\n"
  printf "%-10s %-40s %-8s %-6s %-8s\n" "Story" "Title" "Status" "Wave" "Retries"
  printf "%-10s %-40s %-8s %-6s %-8s\n" "----------" "----------------------------------------" "--------" "------" "--------"
  jq -r '.stories[] | "\(.id)|\(.title)|\(.status)|\(.retries.attempts)/\(.retries.maxAttempts)"' quantum.json | \
  while IFS='|' read -r sid title status retries; do
    printf "%-10s %-40s %-8s %-6s %-8s\n" "$sid" "${title:0:40}" "$status" "-" "$retries"
  done
  printf "\n"

  local total passed failed
  total=$(jq '.stories | length' quantum.json)
  passed=$(jq '[.stories[] | select(.status == "passed")] | length' quantum.json)
  failed=$((total - passed))
  printf "Result: %d/%d stories passed\n" "$passed" "$total"
}

# =============================================================================
# Stale story detection
# =============================================================================

detect_stale_stories() {
  local threshold="${STALE_TIMEOUT:-20}"
  local now_epoch
  now_epoch=$(date +%s)

  # Find all in_progress stories with startedAt set
  local stale_ids
  stale_ids=$(jq -r --argjson threshold "$threshold" '
    .stories[] |
    select(.status == "in_progress" and .startedAt != null) |
    select(
      ((now | floor) - (.startedAt | fromdateiso8601)) > ($threshold * 60)
    ) |
    .id
  ' quantum.json 2>/dev/null) || return 0

  if [[ -z "$stale_ids" ]]; then
    return 0
  fi

  while IFS= read -r sid; do
    [[ -z "$sid" ]] && continue
    printf "[STALE] %s - resetting to failed (exceeded %d minute threshold)\n" "$sid" "$threshold"
    json_atomic_update_args '
      .stories |= map(if .id == $id then
        .status = (if .retries.attempts + 1 >= .retries.maxAttempts then "blocked" else "failed" end) |
        .startedAt = null |
        .retries.attempts += 1 |
        .retries.failureLog += [{"phase": "stale_detection", "timestamp": (now | todate), "error": ("Story exceeded " + ($threshold | tostring) + " minute stale threshold")}]
      else . end)
    ' quantum.json --arg id "$sid" --argjson threshold "$threshold"
  done <<< "$stale_ids"
}

# =============================================================================
# Safe test command execution (allowlist + metacharacter rejection)
# =============================================================================

# Allowlist of known-safe test command prefixes
ALLOWED_TEST_PREFIXES=("npm test" "npx jest" "npx vitest" "yarn test" "pnpm test" "python -m pytest" "pytest" "cargo test" "go test" "make test" "bash tests/" "shellcheck")

# validate_and_run_test_cmd(cmd, [work_dir])
# Validates a test command against the allowlist and rejects shell metacharacters.
# Executes via array splitting (no eval). Returns the command's exit code.
validate_and_run_test_cmd() {
  local cmd="$1"
  local work_dir="${2:-.}"

  if [[ -z "$cmd" ]]; then
    return 1
  fi

  # Reject shell metacharacters
  if [[ "$cmd" =~ [\;\|\&\$\`\(\)\>\<\!] ]] || [[ "$cmd" == *$'\n'* ]]; then
    printf "ERROR: Test command contains unsafe characters: %s\n" "$cmd" >&2
    return 1
  fi

  # Check allowlist
  local allowed=false
  for prefix in "${ALLOWED_TEST_PREFIXES[@]}"; do
    if [[ "$cmd" == "$prefix" || "$cmd" == "$prefix "* ]]; then
      allowed=true
      break
    fi
  done

  if [[ "$allowed" != "true" ]]; then
    printf "ERROR: Test command '%s' does not match any allowed prefix — refusing to execute\n" "$cmd" >&2
    return 1
  fi

  # Execute as array to prevent shell interpretation
  local -a cmd_array
  read -ra cmd_array <<< "$cmd"
  (cd "$work_dir" && "${cmd_array[@]}" >/dev/null 2>&1)
}

# =============================================================================
# Final verification sweep before declaring COMPLETE
# =============================================================================

final_verification_sweep() {
  printf "\n[FINAL SWEEP] Running test suite before declaring COMPLETE...\n"

  # Detect test command
  local TEST_CMD=""
  if [[ -f "package.json" ]]; then TEST_CMD="npm test"
  elif [[ -f "pyproject.toml" ]] || [[ -f "setup.py" ]]; then TEST_CMD="python -m pytest -x -q"
  elif [[ -f "Cargo.toml" ]]; then TEST_CMD="cargo test"
  elif [[ -f "go.mod" ]]; then TEST_CMD="go test ./..."
  fi

  if [[ -n "$TEST_CMD" ]]; then
    if validate_and_run_test_cmd "$TEST_CMD"; then
      printf "[FINAL SWEEP] Test suite passed.\n"
    else
      printf "[FINAL SWEEP] FAILED: test suite. Cannot declare COMPLETE.\n"
      print_summary_table
      exit 1
    fi
  else
    printf "[FINAL SWEEP] No test suite detected, skipping.\n"
  fi

  # Import smoke test (warning only)
  if [[ -f "package.json" ]]; then
    local entry
    entry=$(jq -r '.main // empty' package.json 2>/dev/null)
    if [[ -n "$entry" ]]; then
      if node -e "require('./$entry')" >/dev/null 2>&1; then
        printf "[FINAL SWEEP] Import smoke test passed.\n"
      else
        printf "[FINAL SWEEP] WARNING: Import smoke test failed for %s (non-blocking).\n" "$entry"
      fi
    fi
  elif [[ -f "go.mod" ]]; then
    if go build ./... >/dev/null 2>&1; then
      printf "[FINAL SWEEP] Go build passed.\n"
    else
      printf "[FINAL SWEEP] WARNING: go build failed (non-blocking).\n"
    fi
  fi
}

# =============================================================================
# Generate execution observations document
# =============================================================================

generate_observations() {
  local branch
  branch=$(jq -r '.branchName' quantum.json)
  local date_str
  date_str=$(date +%Y-%m-%d)
  local obs_file="docs/post-mortems/${date_str}-${branch//\//-}-observations.md"

  mkdir -p docs/post-mortems

  local total passed failed blocked
  total=$(jq '.stories | length' quantum.json)
  passed=$(jq '[.stories[] | select(.status == "passed")] | length' quantum.json)
  failed=$(jq '[.stories[] | select(.status == "failed")] | length' quantum.json)
  blocked=$(jq '[.stories[] | select(.status == "blocked")] | length' quantum.json)

  {
    printf "# Execution Observations: %s\n\n" "$branch"
    printf "**Date:** %s\n" "$date_str"
    printf "**Stories:** %d passed, %d failed, %d blocked (of %d total)\n" "$passed" "$failed" "$blocked" "$total"
    printf "**Mode:** %s\n\n" "$(if $PARALLEL_MODE; then echo 'parallel'; else echo 'sequential'; fi)"

    printf "## Failure Summary\n\n"
    local failures
    # Sanitize pipe characters in title so the markdown table stays aligned
    failures=$(jq -r '.stories[] | select(.status == "failed" or .status == "blocked") | "\(.id)|\(.title | gsub("\\|"; "/"))|\(.status)|\(.retries.attempts)/\(.retries.maxAttempts)"' quantum.json 2>/dev/null)
    if [[ -n "$failures" ]]; then
      printf "| Story | Title | Status | Retries |\n"
      printf "|-------|-------|--------|--------|\n"
      while IFS='|' read -r sid title status retries; do
        printf "| %s | %s | %s | %s |\n" "$sid" "${title:0:40}" "$status" "$retries"
      done <<< "$failures"
    else
      printf "No failures.\n"
    fi

    # Phase 6 / P1.7 — Progress Log table: one row per failed-story phase
    # so the learning loop has structured data (previously this block was
    # just an empty <details> block when .progress was []).
    printf "\n## Progress Log\n\n"
    local progress_rows
    progress_rows=$(jq -r '
      [
        (.stories[] | select(.retries.failureLog // [] | length > 0)
          | .id as $sid
          | (.retries.failureLog // [])[]
          | [ $sid,
              (.phase // "unknown"),
              ((.error // "") | gsub("\\|"; "/") | .[0:80]),
              "",
              "",
              "" ]
          | @tsv),
        (.progress // []
          | .[]
          | [ (.storyId // "(pipeline)"),
              (.action // "unknown"),
              ((.details // "") | gsub("\\|"; "/") | .[0:80]),
              "",
              "",
              (.learnings // "") ]
          | @tsv)
      ] | .[]
    ' quantum.json 2>/dev/null)
    if [[ -n "$progress_rows" ]]; then
      printf "| Story | Phase / Action | Error / Detail | Root cause | Fix applied | Lesson |\n"
      printf "|-------|----------------|----------------|-----------|-------------|--------|\n"
      while IFS=$'\t' read -r sid phase detail rc fix lesson; do
        [[ -z "$sid" && -z "$phase" ]] && continue
        printf "| %s | %s | %s | %s | %s | %s |\n" \
          "${sid:-(pipeline)}" "${phase:-unknown}" "${detail:-}" "${rc:-}" "${fix:-}" "${lesson:-}"
      done <<< "$progress_rows"
    else
      printf "_No failed / retried stories. Progress log is empty._\n"
    fi

    printf "\n## Raw Data\n\n"
    printf "<details>\n<summary>Progress JSON</summary>\n\n"
    printf '```json\n'
    jq '.progress' quantum.json
    printf '```\n\n'
    printf "</details>\n\n"

    printf "<details>\n<summary>Failure Logs</summary>\n\n"
    printf '```json\n'
    jq '[.stories[] | select(.retries.failureLog | length > 0) | {id, failureLog: .retries.failureLog}]' quantum.json
    printf '```\n\n'
    printf "</details>\n"
  } > "$obs_file"

  # Phase 6 / P1.7 — promote generalizable lessons from progress entries into
  # codebasePatterns so the next iteration inherits them.
  local new_patterns
  new_patterns=$(jq '[.progress // [] | .[] | select(.learnings? and (.learnings | length > 0)) | .learnings]' quantum.json 2>/dev/null)
  if [[ "$new_patterns" != "[]" && -n "$new_patterns" ]]; then
    local tmpfile
    tmpfile=$(mktemp 2>/dev/null || mktemp -t qlobs)
    jq --argjson newlessons "$new_patterns" '
      .codebasePatterns = ((.codebasePatterns // []) + $newlessons | unique)
    ' quantum.json > "$tmpfile" 2>/dev/null
    if [[ -s "$tmpfile" ]]; then
      mv "$tmpfile" quantum.json
      printf "[OBSERVATIONS] Promoted %s lessons into codebasePatterns.\n" \
        "$(echo "$new_patterns" | jq 'length')"
    else
      rm -f "$tmpfile"
    fi
  fi

  git add "$obs_file" && git commit -m "docs: execution observations for $branch" >/dev/null 2>&1 || true
  printf "[OBSERVATIONS] Generated %s\n" "$obs_file"

  # Check if observations contain issues worth reporting
  local has_blocked has_recurring
  has_blocked=$(jq '[.stories[] | select(.status == "blocked" or .status == "failed")] | length' quantum.json)
  has_recurring=$(jq '[.stories[] | (.retries.failureLog // [])[] | .phase] | group_by(.) | map(select(length > 1)) | length' quantum.json 2>/dev/null || echo "0")

  if [[ "$has_blocked" -gt 0 || "$has_recurring" -gt 0 ]]; then
    # Skip prompt if non-interactive
    if [[ ! -t 0 ]] || [[ "${NON_INTERACTIVE:-false}" == "true" ]]; then
      printf "[OBSERVATIONS] Skipping GitHub issue prompt (non-interactive mode).\n"
      return
    fi

    printf "\n[OBSERVATIONS] Found issues worth reporting (%d blocked/failed, %d recurring patterns).\n" "$has_blocked" "$has_recurring"
    read -rp "File observations as GitHub issue on quantum-loop? [y/N] " response
    if [[ "$response" =~ ^[Yy]$ ]]; then
      if command -v gh >/dev/null 2>&1; then
        gh issue create --repo andyzengmath/quantum-loop \
          --title "Execution observations: $branch ($date_str)" \
          --body "$(cat "$obs_file")" \
          --label "execution-feedback" 2>/dev/null && \
          printf "[OBSERVATIONS] GitHub issue filed.\n" || \
          printf "[OBSERVATIONS] Failed to file GitHub issue (gh error). Local doc is available.\n"
      else
        printf "[OBSERVATIONS] gh CLI not found. Local doc is available at %s\n" "$obs_file"
      fi
    fi
  fi
}

# =============================================================================
# Terminal signal emission helper (v0.9.6 / US-002 dedup)
# =============================================================================

# emit_terminal_signal(signal_name, [human_message])
# Pure formatter: prints separator + '<quantum>$signal</quantum>' + optional
# message + separator. No exit; no control-flow side effects. Caller decides
# exit code. Used at all production-path terminal-signal call sites:
#   - lib/iteration-loop.sh — sequential/coordinator COMPLETE/BLOCKED + MAX_ITERATIONS
#   - lib/parallel-mode.sh  — parallel-mode COMPLETE/BLOCKED + MAX_ITERATIONS
# (PARALLEL_MODE was extracted from quantum-loop.sh in v0.10.0; iteration-loop
# MAX_ITERATIONS migrated in v0.10.1; comment refreshed in v0.10.2.)
emit_terminal_signal() {
  local signal="${1:?emit_terminal_signal: signal name required}"
  local message="${2:-}"
  printf "\n===========================================\n"
  printf "  <quantum>%s</quantum>\n" "$signal"
  [[ -n "$message" ]] && printf "  %s\n" "$message"
  printf "===========================================\n"
}
