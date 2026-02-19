#!/usr/bin/env bash
# Test suite for lib/json-atomic.sh
# Tests atomic write, stale tmp cleanup, and execution field management

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="$SCRIPT_DIR/../lib"
PASS=0
FAIL=0
TOTAL=0

# Ensure jq is available
if ! command -v jq &>/dev/null; then
  echo "SKIP: jq not found"
  exit 1
fi

# Source the library under test
if [[ ! -f "$LIB_DIR/json-atomic.sh" ]]; then
  echo "SKIP: lib/json-atomic.sh not found (RED phase)"
  exit 1
fi
source "$LIB_DIR/json-atomic.sh"

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

assert_file_exists() {
  local test_name="$1" file="$2"
  TOTAL=$((TOTAL + 1))
  if [[ -f "$file" ]]; then
    echo "  PASS: $test_name"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: $test_name (file not found: $file)"
    FAIL=$((FAIL + 1))
  fi
}

assert_file_not_exists() {
  local test_name="$1" file="$2"
  TOTAL=$((TOTAL + 1))
  if [[ ! -f "$file" ]]; then
    echo "  PASS: $test_name"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: $test_name (file still exists: $file)"
    FAIL=$((FAIL + 1))
  fi
}

# Setup temp directory
TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

# =========================================================================
echo "=== Test 1: write_quantum_json writes via tmp then renames ==="
QJSON="$TMPDIR/quantum.json"
echo '{"stories":[]}' > "$QJSON"
CONTENT='{"stories":[{"id":"US-001"}]}'
write_quantum_json "$QJSON" "$CONTENT"
EXIT_CODE=$?
assert_eq "write exits 0" "0" "$EXIT_CODE"
assert_file_exists "quantum.json exists after write" "$QJSON"
assert_file_not_exists "quantum.json.tmp removed after write" "${QJSON}.tmp"
ACTUAL=$(jq -r '.stories[0].id' "$QJSON")
assert_eq "Content written correctly" "US-001" "$ACTUAL"

# =========================================================================
echo "=== Test 2: cleanup_stale_tmp removes leftover .tmp ==="
QJSON="$TMPDIR/quantum2.json"
echo '{"stories":[]}' > "$QJSON"
echo '{"stale":"data"}' > "${QJSON}.tmp"
cleanup_stale_tmp "$QJSON"
assert_file_not_exists "Stale .tmp removed" "${QJSON}.tmp"
assert_file_exists "Original quantum.json untouched" "$QJSON"

# =========================================================================
echo "=== Test 3: cleanup_stale_tmp is no-op when no .tmp exists ==="
QJSON="$TMPDIR/quantum3.json"
echo '{"stories":[]}' > "$QJSON"
cleanup_stale_tmp "$QJSON"
EXIT_CODE=$?
assert_eq "cleanup exits 0 when no tmp" "0" "$EXIT_CODE"

# =========================================================================
echo "=== Test 4: update_execution_field adds execution metadata ==="
QJSON="$TMPDIR/quantum4.json"
echo '{"stories":[],"progress":[]}' > "$QJSON"
update_execution_field "$QJSON" "parallel" "4" "1"
ACTUAL_MODE=$(jq -r '.execution.mode' "$QJSON")
ACTUAL_MAX=$(jq -r '.execution.maxParallel' "$QJSON")
ACTUAL_WAVE=$(jq -r '.execution.currentWave' "$QJSON")
ACTUAL_WT=$(jq -r '.execution.activeWorktrees | length' "$QJSON")
assert_eq "mode is parallel" "parallel" "$ACTUAL_MODE"
assert_eq "maxParallel is 4" "4" "$ACTUAL_MAX"
assert_eq "currentWave is 1" "1" "$ACTUAL_WAVE"
assert_eq "activeWorktrees starts empty" "0" "$ACTUAL_WT"

# =========================================================================
echo "=== Test 5: set_story_worktree sets worktree path on story ==="
QJSON="$TMPDIR/quantum5.json"
cat > "$QJSON" << 'JSONEOF'
{"stories":[{"id":"US-001","status":"pending"},{"id":"US-002","status":"pending"}],"execution":{"activeWorktrees":[]}}
JSONEOF
set_story_worktree "$QJSON" "US-001" ".ql-wt/US-001"
ACTUAL_WT=$(jq -r '.stories[] | select(.id=="US-001") | .worktree' "$QJSON")
ACTUAL_ACTIVE=$(jq -r '.execution.activeWorktrees | length' "$QJSON")
assert_eq "Story US-001 has worktree set" ".ql-wt/US-001" "$ACTUAL_WT"
assert_eq "activeWorktrees has 1 entry" "1" "$ACTUAL_ACTIVE"

# =========================================================================
echo "=== Test 6: clear_story_worktree removes worktree from story ==="
clear_story_worktree "$QJSON" "US-001"
ACTUAL_WT=$(jq -r '.stories[] | select(.id=="US-001") | .worktree // "null"' "$QJSON")
ACTUAL_ACTIVE=$(jq -r '.execution.activeWorktrees | length' "$QJSON")
assert_eq "Story US-001 worktree cleared" "null" "$ACTUAL_WT"
assert_eq "activeWorktrees is empty" "0" "$ACTUAL_ACTIVE"

# =========================================================================
echo "=== Test 7: write_quantum_json validates JSON ==="
QJSON="$TMPDIR/quantum7.json"
echo '{"stories":[]}' > "$QJSON"
write_quantum_json "$QJSON" "not valid json" 2>/dev/null
EXIT_CODE=$?
assert_eq "write rejects invalid JSON" "1" "$EXIT_CODE"
# Original file should be unchanged
ACTUAL=$(jq -r '.stories | length' "$QJSON")
assert_eq "Original file unchanged after invalid write" "0" "$ACTUAL"

# =========================================================================
echo "=== Test 8: Input validation ==="
write_quantum_json "" '{}' 2>/dev/null
EXIT_CODE=$?
assert_eq "write_quantum_json rejects empty path" "1" "$EXIT_CODE"
cleanup_stale_tmp "" 2>/dev/null
EXIT_CODE=$?
assert_eq "cleanup_stale_tmp rejects empty path" "1" "$EXIT_CODE"

# =========================================================================
echo ""
echo "=== Results: $PASS/$TOTAL passed, $FAIL failed ==="
if [[ $FAIL -eq 0 ]]; then
  exit 0
else
  exit 1
fi
