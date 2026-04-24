#!/usr/bin/env bash
# Test suite for Phase 5 / P1.5 — claim-check integration into runner_parse_output.
# Verifies that hedge / stale-evidence / polite-stop phrases in agent output
# demote signal confidence but never flip the signal itself.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$SCRIPT_DIR/.."
PASS=0
FAIL=0
TOTAL=0

assert_eq() {
  local name="$1" expected="$2" actual="$3"
  TOTAL=$((TOTAL + 1))
  if [[ "$expected" == "$actual" ]]; then
    echo "  PASS: $name"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: $name"
    echo "    expected: [$expected]"
    echo "    actual:   [$actual]"
    FAIL=$((FAIL + 1))
  fi
}

assert_contains() {
  local name="$1" needle="$2" haystack="$3"
  TOTAL=$((TOTAL + 1))
  if echo "$haystack" | grep -qF "$needle"; then
    echo "  PASS: $name"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: $name"
    echo "    expected to contain: [$needle]"
    echo "    actual:              [${haystack:0:200}]"
    FAIL=$((FAIL + 1))
  fi
}

# Load runner.sh + claim-check.sh + signal-heuristics.sh
RUNNER_LIB_DIR="$REPO_ROOT/lib"
export RUNNER_LIB_DIR
# shellcheck disable=SC1091
source "$REPO_ROOT/lib/runner.sh"

# Stub runner name so claim-check hook logic has the global it expects
RUNNER_NAME="claude"
RUNNER_HEURISTIC_FALLBACK="true"

echo "=== Phase 5 Claim-Check Integration Tests ==="

# Test 1: Clean agent output keeps confidence=exact
echo ""
echo "Test 1: Clean output — exact signal, no hedge"
clean_output='I implemented the feature. tests passed: 14/14.
Committed.
<quantum>STORY_PASSED</quantum>'
runner_parse_output "$clean_output" 0 /tmp 2>/dev/null
assert_eq "signal result is STORY_PASSED" "STORY_PASSED" "${SIGNAL_RESULT:-}"
assert_eq "confidence stays exact" "exact" "${SIGNAL_CONFIDENCE:-}"
assert_eq "claim findings clean" "clean" "${SIGNAL_CLAIM_FINDINGS:-}"

# Test 2: Hedge phrase in output — signal stays, confidence demoted
echo ""
echo "Test 2: Hedge phrase demotes confidence but keeps signal"
hedge_output='The implementation should work for the common case.
I believe the tests pass.
<quantum>STORY_PASSED</quantum>'
runner_parse_output "$hedge_output" 0 /tmp 2>/dev/null
assert_eq "signal still STORY_PASSED" "STORY_PASSED" "${SIGNAL_RESULT:-}"
assert_eq "confidence demoted to medium" "medium" "${SIGNAL_CONFIDENCE:-}"
assert_contains "claim findings mention hedge" "hedge" "${SIGNAL_CLAIM_FINDINGS:-}"

# Test 3: Polite-stop pattern demotes confidence
echo ""
echo "Test 3: Polite-stop phrase demotes confidence"
polite_output='Work is complete. Ready for your review.
<quantum>STORY_PASSED</quantum>'
runner_parse_output "$polite_output" 0 /tmp 2>/dev/null
assert_eq "signal still STORY_PASSED" "STORY_PASSED" "${SIGNAL_RESULT:-}"
assert_eq "confidence demoted to medium" "medium" "${SIGNAL_CONFIDENCE:-}"
assert_contains "polite-stop recorded" "polite-stop" "${SIGNAL_CLAIM_FINDINGS:-}"

# Test 4: Stale-evidence phrase demotes confidence
echo ""
echo "Test 4: Stale-evidence phrase demotes confidence"
stale_output='Tests passed earlier in the previous run; committing.
<quantum>STORY_PASSED</quantum>'
runner_parse_output "$stale_output" 0 /tmp 2>/dev/null
assert_eq "signal still STORY_PASSED" "STORY_PASSED" "${SIGNAL_RESULT:-}"
assert_eq "confidence demoted to medium" "medium" "${SIGNAL_CONFIDENCE:-}"
assert_contains "stale recorded" "stale" "${SIGNAL_CLAIM_FINDINGS:-}"

# Test 5: Non-zero exit code with hedge — stays FAILED high, claim noted
echo ""
echo "Test 5: exit_code=1 + hedge keeps FAILED, but records claim"
bad_output='should pass next time.'
runner_parse_output "$bad_output" 1 /tmp 2>/dev/null
assert_eq "signal FAILED" "STORY_FAILED" "${SIGNAL_RESULT:-}"
# confidence was "high" from exit-code rule — demoted to medium by claim-check
assert_eq "confidence demoted medium" "medium" "${SIGNAL_CONFIDENCE:-}"
assert_contains "hedge recorded" "hedge" "${SIGNAL_CLAIM_FINDINGS:-}"

# Test 6: No signal + heuristics disabled + clean output — FAILED high, clean
echo ""
echo "Test 6: no signal, heuristics off, clean output"
RUNNER_HEURISTIC_FALLBACK="false"
runner_parse_output "no signal here, all good" 0 /tmp 2>/dev/null
assert_eq "signal FAILED" "STORY_FAILED" "${SIGNAL_RESULT:-}"
assert_eq "claim findings clean" "clean" "${SIGNAL_CLAIM_FINDINGS:-}"
RUNNER_HEURISTIC_FALLBACK="true"

# Summary
echo ""
echo "=== Results: $PASS/$TOTAL passed, $FAIL failed ==="
exit $((FAIL > 0 ? 1 : 0))
