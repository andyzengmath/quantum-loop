#!/usr/bin/env bash
# lib/signal-heuristics.sh — Heuristic output parser for non-Claude runners.
# Infers story pass/fail when a runner fails to emit a quantum signal.
#
# Usage: source lib/signal-heuristics.sh
#        parse_agent_output "output text" exit_code [worktree_path]
#        echo "$SIGNAL_RESULT $SIGNAL_CONFIDENCE"

# parse_agent_output(output_text, exit_code, [worktree_path])
# Sets globals: SIGNAL_RESULT and SIGNAL_CONFIDENCE
parse_agent_output() {
  local output="$1"
  local exit_code="$2"
  local wt_path="${3:-.}"

  # shellcheck disable=SC2034
  SIGNAL_RESULT=""
  # shellcheck disable=SC2034
  SIGNAL_CONFIDENCE=""

  # Rule 1: Non-zero exit code always means failure
  if [[ "$exit_code" -ne 0 ]]; then
    # shellcheck disable=SC2034
    SIGNAL_RESULT="STORY_FAILED"
    # shellcheck disable=SC2034
    SIGNAL_CONFIDENCE="high"
    printf "[RUNNER] Signal: FAILED (exit_code=%s, confidence=high)\n" "$exit_code" >&2
    return 0
  fi

  # Rule 2: Check for exact quantum signals (relaxed whitespace)
  local signals
  signals=$(echo "$output" | grep -oE '<quantum>[[:space:]]*(STORY_PASSED|STORY_FAILED|COMPLETE|BLOCKED)[[:space:]]*</quantum>' || true)

  if [[ -n "$signals" ]]; then
    # Last signal wins when multiple are found
    local last_signal
    last_signal=$(echo "$signals" | tail -1 | sed 's/<quantum>[[:space:]]*//' | sed 's/[[:space:]]*<\/quantum>//')
    # shellcheck disable=SC2034
    SIGNAL_RESULT="$last_signal"
    # shellcheck disable=SC2034
    SIGNAL_CONFIDENCE="exact"
    printf "[RUNNER] Signal: %s (exact match, confidence=exact)\n" "$last_signal" >&2
    return 0
  fi

  # Rule 3: No signal found — apply heuristics
  local has_commit=false
  local has_tests_pass=false
  local has_errors=false

  # Check for feat: commit in worktree
  if git -C "$wt_path" log --oneline -1 2>/dev/null | grep -q 'feat:'; then
    has_commit=true
  fi

  # Check for test pass patterns in output
  if echo "$output" | grep -qiE '(0 failures|0 failed|all.*pass|tests? passed|PASS:|OK$)'; then
    has_tests_pass=true
  fi

  # Check for error patterns in output (excludes "0 errors", "0 failed" false positives)
  local error_lines
  error_lines=$(echo "$output" | grep -iE '(error|FAIL:|failed|exception|panic)' || true)
  if [[ -n "$error_lines" ]]; then
    # Filter out false positives: "0 errors", "0 failed", "no error"
    local real_errors
    real_errors=$(echo "$error_lines" | grep -viE '(0 errors?|0 failed|no errors?)' || true)
    if [[ -n "$real_errors" ]]; then
      has_errors=true
    fi
  fi

  # Decision matrix
  if [[ "$has_commit" == "true" ]] && [[ "$has_tests_pass" == "true" ]] && [[ "$has_errors" == "false" ]]; then
    # Commit + passing tests + no errors = PASSED high confidence
    # shellcheck disable=SC2034
    SIGNAL_RESULT="STORY_PASSED"
    # shellcheck disable=SC2034
    SIGNAL_CONFIDENCE="high"
    printf "[RUNNER] Signal: PASSED (heuristic: commit+tests, confidence=high)\n" >&2
  elif [[ "$has_commit" == "true" ]] && [[ "$has_errors" == "true" ]]; then
    # Commit but errors present = FAILED high
    # shellcheck disable=SC2034
    SIGNAL_RESULT="STORY_FAILED"
    # shellcheck disable=SC2034
    SIGNAL_CONFIDENCE="high"
    printf "[RUNNER] Signal: FAILED (heuristic: commit+errors, confidence=high)\n" >&2
  elif [[ "$has_commit" == "true" ]]; then
    # Commit only, no clear test signal = PASSED medium confidence
    # shellcheck disable=SC2034
    SIGNAL_RESULT="STORY_PASSED"
    # shellcheck disable=SC2034
    SIGNAL_CONFIDENCE="medium"
    printf "[RUNNER] Signal: PASSED (heuristic: commit-only, confidence=medium)\n" >&2
  else
    # No commit = FAILED high confidence
    # shellcheck disable=SC2034
    SIGNAL_RESULT="STORY_FAILED"
    # shellcheck disable=SC2034
    SIGNAL_CONFIDENCE="high"
    printf "[RUNNER] Signal: FAILED (heuristic: no_commit, confidence=high)\n" >&2
  fi

  return 0
}
