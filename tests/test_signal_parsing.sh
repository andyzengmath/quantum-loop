#!/usr/bin/env bash
# tests/test_signal_parsing.sh
#
# v0.8.2 / US-002 (v0.9.0 N42 prerequisite) — unit tests for the exact-match
# path in lib/runner.sh::runner_parse_output. Confirms all 6 signals match
# correctly and that adding WAVE_PASSED/WAVE_FAILED does NOT regress the
# original 4-signal recognition.
#
# Why this exists: v0.8.1 dogfood found that v0.8.0 shipped two pieces of
# inert infrastructure with presence-only ACs. The architect post-v0.8.1
# review identified one more layer: runner_parse_output's regex was missing
# WAVE_PASSED/WAVE_FAILED, which agents/coordinator.md emits. Without these
# unit tests, the parser regression would have shipped with v0.9.0 N42 and
# routed every coordinator dispatch to the unknown-signal failure branch.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB="$SCRIPT_DIR/../lib/runner.sh"
PASS=0
FAIL=0
TOTAL=0

if [[ ! -f "$LIB" ]]; then
  echo "SKIP: $LIB not found"
  exit 1
fi
# shellcheck source=/dev/null
source "$LIB"

assert_eq() {
  local name="$1" expected="$2" actual="$3"
  TOTAL=$((TOTAL + 1))
  if [[ "$expected" == "$actual" ]]; then
    echo "  PASS: $name"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: $name"
    echo "    expected: $expected"
    echo "    actual:   $actual"
    FAIL=$((FAIL + 1))
  fi
}

echo "=== US-002 v0.8.2 signal parsing tests (6-signal recognition) ==="

# Disable heuristic fallback so we test only the exact-match path.
RUNNER_HEURISTIC_FALLBACK=false

# ─ Existing 4 signals (regression guard) ────────────────────────────────────

echo ""
echo "Test 1: STORY_PASSED exact match (regression guard)"
runner_parse_output "Some output\n<quantum>STORY_PASSED</quantum>\nMore output" 0 "." 2>/dev/null
assert_eq "STORY_PASSED matched"      "STORY_PASSED" "$SIGNAL_RESULT"
assert_eq "confidence is exact"       "exact"        "$SIGNAL_CONFIDENCE"

echo ""
echo "Test 2: STORY_FAILED exact match (regression guard)"
runner_parse_output "Output\n<quantum>STORY_FAILED</quantum>" 1 "." 2>/dev/null
assert_eq "STORY_FAILED matched"      "STORY_FAILED" "$SIGNAL_RESULT"

echo ""
echo "Test 3: COMPLETE exact match (regression guard)"
runner_parse_output "Output\n<quantum>COMPLETE</quantum>" 0 "." 2>/dev/null
assert_eq "COMPLETE matched"          "COMPLETE"     "$SIGNAL_RESULT"

echo ""
echo "Test 4: BLOCKED exact match (regression guard)"
runner_parse_output "Output\n<quantum>BLOCKED</quantum>" 0 "." 2>/dev/null
assert_eq "BLOCKED matched"           "BLOCKED"      "$SIGNAL_RESULT"

# ─ NEW v0.8.2 / US-002 signals ──────────────────────────────────────────────

echo ""
echo "Test 5: WAVE_PASSED exact match (NEW — v0.9.0 N42 prerequisite)"
runner_parse_output "Wave 0 done\n<quantum>WAVE_PASSED</quantum>" 0 "." 2>/dev/null
assert_eq "WAVE_PASSED matched"       "WAVE_PASSED"  "$SIGNAL_RESULT"
assert_eq "confidence is exact"       "exact"        "$SIGNAL_CONFIDENCE"

echo ""
echo "Test 6: WAVE_FAILED exact match (NEW — v0.9.0 N42 prerequisite)"
runner_parse_output "Wave 1 broke\n<quantum>WAVE_FAILED</quantum>" 1 "." 2>/dev/null
assert_eq "WAVE_FAILED matched"       "WAVE_FAILED"  "$SIGNAL_RESULT"

# ─ Whitespace-tolerance regression guard (existing behavior preserved) ──────

echo ""
echo "Test 7: tolerates internal whitespace (regression guard)"
runner_parse_output "<quantum> STORY_PASSED </quantum>" 0 "." 2>/dev/null
assert_eq "whitespace tolerated"      "STORY_PASSED" "$SIGNAL_RESULT"

# ─ Last-signal-wins (existing behavior preserved) ───────────────────────────

echo ""
echo "Test 8: last-signal-wins regression guard"
runner_parse_output "<quantum>STORY_FAILED</quantum>... retry... <quantum>STORY_PASSED</quantum>" 0 "." 2>/dev/null
assert_eq "last signal wins"          "STORY_PASSED" "$SIGNAL_RESULT"

# ─ Negative tests: substrings of WAVE_* don't match ─────────────────────────

echo ""
echo "Test 9: WAVE_PASSING (substring) does NOT match"
runner_parse_output "<quantum>WAVE_PASSING</quantum>" 0 "." 2>/dev/null
# Should fall through to the no-signal default (STORY_FAILED, high confidence).
assert_eq "non-canonical not matched" "STORY_FAILED" "$SIGNAL_RESULT"
assert_eq "fallback confidence high"  "high"         "$SIGNAL_CONFIDENCE"

echo ""
echo "Test 10: bare 'WAVE_PASSED' without quantum tags does NOT match"
runner_parse_output "Output mentions WAVE_PASSED but no quantum tags" 0 "." 2>/dev/null
assert_eq "untagged not matched"      "STORY_FAILED" "$SIGNAL_RESULT"

echo ""
echo "=== Results: $PASS/$TOTAL passed, $FAIL failed ==="
if (( FAIL > 0 )); then
  exit 1
fi
exit 0
