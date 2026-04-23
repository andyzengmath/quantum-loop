#!/usr/bin/env bash
# Phase 16 / P2.6 — tests for lib/watchdog.sh task watchdog + circuit breaker.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$SCRIPT_DIR/.."
PASS=0
FAIL=0
TOTAL=0

assert() {
  local name="$1" expected="$2" actual="$3"
  TOTAL=$((TOTAL + 1))
  if [[ "$expected" == "$actual" ]]; then
    echo "  PASS: $name"; PASS=$((PASS + 1))
  else
    echo "  FAIL: $name (expected [$expected] got [$actual])"
    FAIL=$((FAIL + 1))
  fi
}

# shellcheck disable=SC1091
source "$REPO_ROOT/lib/watchdog.sh"

echo "=== Phase 16 watchdog + circuit-breaker tests ==="

# Test 1: classify_age thresholds
echo ""
echo "Test 1: classify_age thresholds"
assert "0s -> fresh"            "fresh"           "$(classify_age 0)"
assert "300s -> fresh"          "fresh"           "$(classify_age 300)"
assert "301s -> stale-check"    "stale-check"     "$(classify_age 301)"
assert "600s -> stale-check"    "stale-check"     "$(classify_age 600)"
assert "601s -> stale-reassign" "stale-reassign"  "$(classify_age 601)"
assert "1200s -> stale-reassign" "stale-reassign" "$(classify_age 1200)"
assert "1201s -> stale-reassign" "stale-reassign" "$(classify_age 1201)"
assert "1800s -> stale-reassign" "stale-reassign" "$(classify_age 1800)"
assert "1801s -> timed-out"     "timed-out"       "$(classify_age 1801)"
assert "7200s -> timed-out"     "timed-out"       "$(classify_age 7200)"

# Test 2: watchdog_poll on empty / missing quantum.json
echo ""
echo "Test 2: watchdog_poll on empty state"
out=$(watchdog_poll "/nonexistent/quantum.json")
assert "missing quantum.json -> []" "[]" "$out"

# Test 3: watchdog_poll finds fresh story -> continue
echo ""
echo "Test 3: watchdog_poll fresh in_progress story"
TEST_TMPDIR=$(mktemp -d)
# Use current UTC time for a "fresh" story
now_iso=$(date -u +%Y-%m-%dT%H:%M:%SZ)
cat > "$TEST_TMPDIR/quantum.json" << EOF
{
  "stories": [
    {"id": "US-001", "status": "in_progress", "startedAt": "$now_iso"},
    {"id": "US-002", "status": "passed", "startedAt": "$now_iso"},
    {"id": "US-003", "status": "pending"}
  ]
}
EOF
out=$(watchdog_poll "$TEST_TMPDIR/quantum.json")
count=$(printf '%s' "$out" | jq 'length')
assert "only the in_progress story returned" "1" "$count"
sid=$(printf '%s' "$out" | jq -r '.[0].story_id')
assert "story_id is US-001" "US-001" "$sid"
action=$(printf '%s' "$out" | jq -r '.[0].recommended_action')
assert "fresh -> continue"   "continue" "$action"
classification=$(printf '%s' "$out" | jq -r '.[0].classification')
assert "classification fresh" "fresh" "$classification"
rm -rf "$TEST_TMPDIR"

# Test 4: watchdog_poll finds stale-check story
echo ""
echo "Test 4: watchdog_poll stale-check (~400s old)"
TEST_TMPDIR=$(mktemp -d)
old_iso=$(python3 -c "import datetime,sys; print((datetime.datetime.now(datetime.timezone.utc) - datetime.timedelta(seconds=400)).strftime('%Y-%m-%dT%H:%M:%SZ'))")
cat > "$TEST_TMPDIR/quantum.json" << EOF
{
  "stories": [{"id": "US-010", "status": "in_progress", "startedAt": "$old_iso"}]
}
EOF
out=$(watchdog_poll "$TEST_TMPDIR/quantum.json")
cls=$(printf '%s' "$out" | jq -r '.[0].classification')
action=$(printf '%s' "$out" | jq -r '.[0].recommended_action')
assert "400s -> stale-check"      "stale-check"   "$cls"
assert "stale-check -> status-probe" "status-probe" "$action"
rm -rf "$TEST_TMPDIR"

# Test 5: watchdog_poll finds timed-out story
echo ""
echo "Test 5: watchdog_poll timed-out (>30min old)"
TEST_TMPDIR=$(mktemp -d)
ancient_iso=$(python3 -c "import datetime; print((datetime.datetime.now(datetime.timezone.utc) - datetime.timedelta(seconds=2400)).strftime('%Y-%m-%dT%H:%M:%SZ'))")
cat > "$TEST_TMPDIR/quantum.json" << EOF
{
  "stories": [{"id": "US-042", "status": "in_progress", "startedAt": "$ancient_iso"}]
}
EOF
out=$(watchdog_poll "$TEST_TMPDIR/quantum.json")
cls=$(printf '%s' "$out" | jq -r '.[0].classification')
action=$(printf '%s' "$out" | jq -r '.[0].recommended_action')
assert "2400s -> timed-out"        "timed-out"   "$cls"
assert "timed-out -> mark-failed"  "mark-failed" "$action"
rm -rf "$TEST_TMPDIR"

# Test 6: error_counter_bump increments on same signature
echo ""
echo "Test 6: error_counter_bump same signature increments"
TEST_TMPDIR=$(mktemp -d)
c1=$(error_counter_bump "$TEST_TMPDIR" "US-100" "TypeError: foo")
c2=$(error_counter_bump "$TEST_TMPDIR" "US-100" "TypeError: foo")
c3=$(error_counter_bump "$TEST_TMPDIR" "US-100" "TypeError: foo")
assert "first bump count 1" "1" "$c1"
assert "second bump count 2" "2" "$c2"
assert "third bump count 3" "3" "$c3"
rm -rf "$TEST_TMPDIR"

# Test 7: error_counter_bump resets on different signature
echo ""
echo "Test 7: different signature resets counter"
TEST_TMPDIR=$(mktemp -d)
c1=$(error_counter_bump "$TEST_TMPDIR" "US-101" "err-A")
c2=$(error_counter_bump "$TEST_TMPDIR" "US-101" "err-A")
c3=$(error_counter_bump "$TEST_TMPDIR" "US-101" "err-B")  # different sig
c4=$(error_counter_bump "$TEST_TMPDIR" "US-101" "err-B")
assert "sig-A count reaches 2"     "2" "$c2"
assert "sig-B resets to 1"          "1" "$c3"
assert "sig-B next bump is 2"       "2" "$c4"
rm -rf "$TEST_TMPDIR"

# Test 8: should_circuit_break at threshold
echo ""
echo "Test 8: should_circuit_break crosses threshold"
TEST_TMPDIR=$(mktemp -d)
error_counter_bump "$TEST_TMPDIR" "US-200" "sig" >/dev/null
should_circuit_break "$TEST_TMPDIR" "US-200"
assert "count=1, threshold=3 -> no break (exit 1)" "1" "$?"
error_counter_bump "$TEST_TMPDIR" "US-200" "sig" >/dev/null
error_counter_bump "$TEST_TMPDIR" "US-200" "sig" >/dev/null
should_circuit_break "$TEST_TMPDIR" "US-200"
assert "count=3, threshold=3 -> BREAK (exit 0)" "0" "$?"
# Custom threshold argument
should_circuit_break "$TEST_TMPDIR" "US-200" 10
assert "count=3, threshold=10 -> no break" "1" "$?"
rm -rf "$TEST_TMPDIR"

# Test 9: error_counter_reset clears
echo ""
echo "Test 9: error_counter_reset"
TEST_TMPDIR=$(mktemp -d)
error_counter_bump "$TEST_TMPDIR" "US-300" "sig" >/dev/null
error_counter_bump "$TEST_TMPDIR" "US-300" "sig" >/dev/null
error_counter_reset "$TEST_TMPDIR" "US-300"
should_circuit_break "$TEST_TMPDIR" "US-300"
assert "after reset, no break" "1" "$?"
# Fresh bump after reset is count 1
c=$(error_counter_bump "$TEST_TMPDIR" "US-300" "sig")
assert "count after reset=1" "1" "$c"
rm -rf "$TEST_TMPDIR"

# Test 10: CLI subcommands
echo ""
echo "Test 10: CLI subcommands"
cli_out=$(bash "$REPO_ROOT/lib/watchdog.sh" classify 500 | tr -d '\n')
assert "CLI classify 500 -> stale-check" "stale-check" "$cli_out"
TEST_TMPDIR=$(mktemp -d)
cli_c=$(bash "$REPO_ROOT/lib/watchdog.sh" bump "$TEST_TMPDIR" "US-500" "errsig" | tr -d '\n')
assert "CLI bump first -> 1" "1" "$cli_c"
rm -rf "$TEST_TMPDIR"

echo ""
echo "=== Results: $PASS/$TOTAL passed, $FAIL failed ==="
exit $((FAIL > 0 ? 1 : 0))
