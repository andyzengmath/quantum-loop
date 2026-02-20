#!/usr/bin/env bash
# Test suite for timeout and crash handling extensions in lib/monitor.sh
# Tests check_agent_timeout() and related functions

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="$SCRIPT_DIR/../lib"
PASS=0
FAIL=0
TOTAL=0

# Source dependencies
source "$LIB_DIR/common.sh"
source "$LIB_DIR/json-atomic.sh"
source "$LIB_DIR/spawn.sh"
source "$LIB_DIR/monitor.sh"

assert_eq() {
  local test_name="$1" expected="$2" actual="$3"
  TOTAL=$((TOTAL + 1))
  if [[ "$expected" == "$actual" ]]; then
    echo "  PASS: $test_name"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: $test_name"
    echo "    expected: $expected"
    echo "    actual:   $actual"
    FAIL=$((FAIL + 1))
  fi
}

assert_contains() {
  local test_name="$1" needle="$2" haystack="$3"
  TOTAL=$((TOTAL + 1))
  if echo "$haystack" | grep -q "$needle"; then
    echo "  PASS: $test_name"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: $test_name"
    echo "    expected to contain: $needle"
    echo "    actual: $haystack"
    FAIL=$((FAIL + 1))
  fi
}

# =========================================================================
echo "=== Test 1: DEFAULT_AGENT_TIMEOUT is defined ==="
assert_eq "DEFAULT_AGENT_TIMEOUT is 900" "900" "$DEFAULT_AGENT_TIMEOUT"

# =========================================================================
echo "=== Test 2: check_agent_timeout returns false for recent start ==="
NOW=$(date +%s)
RESULT=$(check_agent_timeout "$NOW" "$DEFAULT_AGENT_TIMEOUT")
assert_eq "Recent start is not timed out" "false" "$RESULT"

# =========================================================================
echo "=== Test 3: check_agent_timeout returns true for old start ==="
NOW=$(date +%s)
OLD_START=$((NOW - 1000))
RESULT=$(check_agent_timeout "$OLD_START" "$DEFAULT_AGENT_TIMEOUT")
assert_eq "Old start is timed out" "true" "$RESULT"

# =========================================================================
echo "=== Test 4: check_agent_timeout with custom timeout ==="
NOW=$(date +%s)
RECENT=$((NOW - 5))
RESULT=$(check_agent_timeout "$RECENT" "3")
assert_eq "5 seconds ago with 3s timeout is timed out" "true" "$RESULT"

RESULT=$(check_agent_timeout "$RECENT" "10")
assert_eq "5 seconds ago with 10s timeout is not timed out" "false" "$RESULT"

# =========================================================================
echo "=== Test 5: kill_agent_process kills a running process ==="
sleep 30 &
SLEEP_PID=$!

# Verify it's running first
if kill -0 "$SLEEP_PID" 2>/dev/null; then
  TOTAL=$((TOTAL + 1)); echo "  PASS: Process running before kill"; PASS=$((PASS + 1))
else
  TOTAL=$((TOTAL + 1)); echo "  FAIL: Process not running before kill"; FAIL=$((FAIL + 1))
fi

kill_agent_process "$SLEEP_PID"
EXIT_CODE=$?
assert_eq "kill_agent_process exits 0" "0" "$EXIT_CODE"

# Brief wait for process to die
sleep 0.2

# Verify it's dead
if ! kill -0 "$SLEEP_PID" 2>/dev/null; then
  TOTAL=$((TOTAL + 1)); echo "  PASS: Process dead after kill"; PASS=$((PASS + 1))
else
  TOTAL=$((TOTAL + 1)); echo "  FAIL: Process still running after kill"; FAIL=$((FAIL + 1))
  kill -9 "$SLEEP_PID" 2>/dev/null || true
fi
wait "$SLEEP_PID" 2>/dev/null || true

# =========================================================================
echo "=== Test 6: kill_agent_process is no-op for dead process ==="
bash -c "exit 0" &
DONE_PID=$!
wait "$DONE_PID" 2>/dev/null

kill_agent_process "$DONE_PID"
EXIT_CODE=$?
assert_eq "kill_agent_process on dead process exits 0" "0" "$EXIT_CODE"

# =========================================================================
echo "=== Test 7: check_agent_timeout input validation ==="
RESULT=$(check_agent_timeout "" "900" 2>&1)
EXIT_CODE=$?
assert_eq "Empty start_time returns error" "1" "$EXIT_CODE"

RESULT=$(check_agent_timeout "123" "" 2>&1)
EXIT_CODE=$?
assert_eq "Empty timeout returns error" "1" "$EXIT_CODE"

# =========================================================================
echo "=== Test 8: Other agents unaffected by one kill ==="
# Start 3 sleep processes
sleep 30 &
PID_A=$!
sleep 30 &
PID_B=$!
sleep 30 &
PID_C=$!

# Kill only PID_B
kill_agent_process "$PID_B"
sleep 0.2
wait "$PID_B" 2>/dev/null || true

# Verify A and C are still running
ALIVE_A=0
ALIVE_C=0
if kill -0 "$PID_A" 2>/dev/null; then ALIVE_A=1; fi
if kill -0 "$PID_C" 2>/dev/null; then ALIVE_C=1; fi

assert_eq "Agent A still running after B killed" "1" "$ALIVE_A"
assert_eq "Agent C still running after B killed" "1" "$ALIVE_C"

# Cleanup
kill "$PID_A" "$PID_C" 2>/dev/null || true
wait "$PID_A" "$PID_C" 2>/dev/null || true

# =========================================================================
echo ""
echo "=== Results: $PASS/$TOTAL passed, $FAIL failed ==="
if [[ $FAIL -eq 0 ]]; then
  exit 0
else
  exit 1
fi
