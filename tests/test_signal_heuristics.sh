#!/usr/bin/env bash
# Test suite for lib/signal-heuristics.sh and runner_parse_output()

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="$SCRIPT_DIR/../lib"
PASS=0
FAIL=0
TOTAL=0

if ! command -v jq &>/dev/null; then
  echo "SKIP: jq not found"
  exit 1
fi

if [[ ! -f "$LIB_DIR/signal-heuristics.sh" ]]; then
  echo "SKIP: lib/signal-heuristics.sh not found (RED phase)"
  exit 1
fi

source "$LIB_DIR/runner.sh"

assert_eq() {
  local test_name="$1" expected="$2" actual="$3"
  TOTAL=$((TOTAL + 1))
  if [[ "$expected" == "$actual" ]]; then
    echo "  PASS: $test_name"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: $test_name"
    echo "    expected: $expected"
    echo "    actual: $actual"
    FAIL=$((FAIL + 1))
  fi
}

# ── Test: exact_signal_passed ──
echo "Test: exact_signal_passed"
runner_parse_output "output <quantum>STORY_PASSED</quantum> done" 0 2>/dev/null
assert_eq "SIGNAL_RESULT is STORY_PASSED" "STORY_PASSED" "$SIGNAL_RESULT"
assert_eq "SIGNAL_CONFIDENCE is exact" "exact" "$SIGNAL_CONFIDENCE"

# ── Test: exact_signal_failed ──
echo "Test: exact_signal_failed"
runner_parse_output "output <quantum>STORY_FAILED</quantum> done" 0 2>/dev/null
assert_eq "SIGNAL_RESULT is STORY_FAILED" "STORY_FAILED" "$SIGNAL_RESULT"
assert_eq "SIGNAL_CONFIDENCE is exact" "exact" "$SIGNAL_CONFIDENCE"

# ── Test: relaxed_whitespace ──
echo "Test: relaxed_whitespace"
runner_parse_output "output <quantum>  STORY_PASSED  </quantum> done" 0 2>/dev/null
assert_eq "SIGNAL_RESULT is STORY_PASSED" "STORY_PASSED" "$SIGNAL_RESULT"
assert_eq "SIGNAL_CONFIDENCE is exact" "exact" "$SIGNAL_CONFIDENCE"

# ── Test: crash_exit_code (non-zero overrides even PASSED signal) ──
echo "Test: crash_exit_code"
RUNNER_HEURISTIC_FALLBACK="true"
parse_agent_output "<quantum>STORY_PASSED</quantum>" 1 2>/dev/null
assert_eq "exit_code=1 → STORY_FAILED" "STORY_FAILED" "$SIGNAL_RESULT"
assert_eq "exit_code=1 → confidence=high" "high" "$SIGNAL_CONFIDENCE"

# ── Test: both_signals_last_wins ──
echo "Test: both_signals_last_wins"
runner_parse_output "first <quantum>STORY_PASSED</quantum> then <quantum>STORY_FAILED</quantum> end" 0 2>/dev/null
assert_eq "last signal wins: STORY_FAILED" "STORY_FAILED" "$SIGNAL_RESULT"
assert_eq "confidence is exact" "exact" "$SIGNAL_CONFIDENCE"

# ── Test: heuristic_commit_and_tests ──
echo "Test: heuristic_commit_and_tests"
RUNNER_HEURISTIC_FALLBACK="true"
# Create a temp git repo with a feat: commit
TMPD=$(mktemp -d)
git -C "$TMPD" init -q 2>/dev/null
git -C "$TMPD" config user.email "test@test.com" 2>/dev/null
git -C "$TMPD" config user.name "Test" 2>/dev/null
echo "test" > "$TMPD/file.txt"
git -C "$TMPD" add . 2>/dev/null
git -C "$TMPD" commit -m "feat: US-001 - Test Story" -q 2>/dev/null
parse_agent_output "Running tests... 0 failures" 0 "$TMPD" 2>/dev/null
assert_eq "commit+tests → STORY_PASSED" "STORY_PASSED" "$SIGNAL_RESULT"
assert_eq "commit+tests → confidence=high" "high" "$SIGNAL_CONFIDENCE"
rm -rf "$TMPD"

# ── Test: heuristic_no_commit ──
echo "Test: heuristic_no_commit"
TMPD=$(mktemp -d)
git -C "$TMPD" init -q 2>/dev/null
git -C "$TMPD" config user.email "test@test.com" 2>/dev/null
git -C "$TMPD" config user.name "Test" 2>/dev/null
# Empty repo, no commits
parse_agent_output "Working on stuff" 0 "$TMPD" 2>/dev/null
assert_eq "no_commit → STORY_FAILED" "STORY_FAILED" "$SIGNAL_RESULT"
assert_eq "no_commit → confidence=high" "high" "$SIGNAL_CONFIDENCE"
rm -rf "$TMPD"

# ── Test: heuristic_commit_with_errors ──
echo "Test: heuristic_commit_with_errors"
TMPD=$(mktemp -d)
git -C "$TMPD" init -q 2>/dev/null
git -C "$TMPD" config user.email "test@test.com" 2>/dev/null
git -C "$TMPD" config user.name "Test" 2>/dev/null
echo "x" > "$TMPD/f.txt"
git -C "$TMPD" add . 2>/dev/null
git -C "$TMPD" commit -m "feat: US-001 - Story" -q 2>/dev/null
parse_agent_output "FAIL: 3 tests failed with error" 0 "$TMPD" 2>/dev/null
assert_eq "commit+errors → STORY_FAILED" "STORY_FAILED" "$SIGNAL_RESULT"
assert_eq "commit+errors → confidence=high" "high" "$SIGNAL_CONFIDENCE"
rm -rf "$TMPD"

# ── Test: heuristic_commit_no_tests ──
echo "Test: heuristic_commit_no_tests"
TMPD=$(mktemp -d)
git -C "$TMPD" init -q 2>/dev/null
git -C "$TMPD" config user.email "test@test.com" 2>/dev/null
git -C "$TMPD" config user.name "Test" 2>/dev/null
echo "x" > "$TMPD/f.txt"
git -C "$TMPD" add . 2>/dev/null
git -C "$TMPD" commit -m "feat: US-002 - Story" -q 2>/dev/null
parse_agent_output "Done implementing the feature" 0 "$TMPD" 2>/dev/null
assert_eq "commit-only → STORY_PASSED" "STORY_PASSED" "$SIGNAL_RESULT"
assert_eq "commit-only → confidence=medium" "medium" "$SIGNAL_CONFIDENCE"
rm -rf "$TMPD"

# ── Test: heuristic_skipped_for_claude ──
echo "Test: heuristic_skipped_for_claude"
RUNNER_HEURISTIC_FALLBACK="false"
runner_parse_output "some output with no signal" 0 2>/dev/null
assert_eq "heuristics disabled → STORY_FAILED" "STORY_FAILED" "$SIGNAL_RESULT"
assert_eq "heuristics disabled → confidence=high" "high" "$SIGNAL_CONFIDENCE"

# ── Test: runner_parse_output exact signal wins over nonzero exit ──
echo "Test: runner_parse_output_exact_signal_over_exit_code"
# When exit_code != 0 but an exact signal is present, runner_parse_output trusts the signal
# (heuristics are only consulted when there is NO exact signal)
runner_parse_output "<quantum>STORY_PASSED</quantum>" 1 2>/dev/null
assert_eq "exact signal wins over nonzero exit" "STORY_PASSED" "$SIGNAL_RESULT"
assert_eq "confidence is exact (not high)" "exact" "$SIGNAL_CONFIDENCE"

# ── Summary ──
echo ""
echo "=== Results: $PASS/$TOTAL passed, $FAIL failed ==="
if [[ $FAIL -gt 0 ]]; then
  exit 1
fi
exit 0
