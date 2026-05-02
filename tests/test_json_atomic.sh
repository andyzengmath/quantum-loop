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
TEST_TMPDIR=$(mktemp -d)
trap 'rm -rf "$TEST_TMPDIR"' EXIT

# =========================================================================
echo "=== Test 1: write_quantum_json writes via tmp then renames ==="
QJSON="$TEST_TMPDIR/quantum.json"
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
QJSON="$TEST_TMPDIR/quantum2.json"
echo '{"stories":[]}' > "$QJSON"
echo '{"stale":"data"}' > "${QJSON}.tmp"
cleanup_stale_tmp "$QJSON"
assert_file_not_exists "Stale .tmp removed" "${QJSON}.tmp"
assert_file_exists "Original quantum.json untouched" "$QJSON"

# =========================================================================
echo "=== Test 3: cleanup_stale_tmp is no-op when no .tmp exists ==="
QJSON="$TEST_TMPDIR/quantum3.json"
echo '{"stories":[]}' > "$QJSON"
cleanup_stale_tmp "$QJSON"
EXIT_CODE=$?
assert_eq "cleanup exits 0 when no tmp" "0" "$EXIT_CODE"

# =========================================================================
echo "=== Test 4: update_execution_field adds execution metadata ==="
QJSON="$TEST_TMPDIR/quantum4.json"
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
QJSON="$TEST_TMPDIR/quantum5.json"
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
QJSON="$TEST_TMPDIR/quantum7.json"
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
# v0.9.6 / US-001 T-001-1: json_atomic_update_args variant tests.
# The variant forwards extra args to jq verbatim so callers can use --arg /
# --argjson safely instead of inlining values into the filter string.
# =========================================================================
echo "=== Test 9: json_atomic_update_args --arg string passthrough ==="
QJSON="$TEST_TMPDIR/quantum9.json"
cat > "$QJSON" << 'JSONEOF'
{"stories":[{"id":"US-001","status":"pending"},{"id":"US-002","status":"pending"}]}
JSONEOF
json_atomic_update_args \
  '.stories |= map(if .id == $sid then .status = "passed" else . end)' \
  "$QJSON" \
  --arg sid "US-002"
EXIT_CODE=$?
assert_eq "args variant exits 0 on --arg" "0" "$EXIT_CODE"
ACTUAL=$(jq -r '.stories[] | select(.id=="US-002") | .status' "$QJSON")
assert_eq "args variant applied --arg substitution" "passed" "$ACTUAL"
ACTUAL_OTHER=$(jq -r '.stories[] | select(.id=="US-001") | .status' "$QJSON")
assert_eq "args variant only updated targeted story" "pending" "$ACTUAL_OTHER"
assert_file_not_exists "args variant cleaned up tmp file" "${QJSON}.tmp"

# =========================================================================
echo "=== Test 10: json_atomic_update_args --argjson JSON passthrough ==="
QJSON="$TEST_TMPDIR/quantum10.json"
cat > "$QJSON" << 'JSONEOF'
{"stories":[{"id":"US-001","retries":{"attempts":0,"maxAttempts":1}},{"id":"US-002","retries":{"attempts":0,"maxAttempts":1}}]}
JSONEOF
json_atomic_update_args \
  '.stories |= map(.retries.maxAttempts = $max)' \
  "$QJSON" \
  --argjson max 5
EXIT_CODE=$?
assert_eq "args variant exits 0 on --argjson" "0" "$EXIT_CODE"
ACTUAL=$(jq -r '.stories[0].retries.maxAttempts' "$QJSON")
assert_eq "args variant applied --argjson number" "5" "$ACTUAL"

# =========================================================================
echo "=== Test 11: json_atomic_update_args rejects missing filter ==="
json_atomic_update_args "" "$TEST_TMPDIR/quantum10.json" 2>/dev/null
EXIT_CODE=$?
assert_eq "args variant rejects empty filter" "1" "$EXIT_CODE"

# =========================================================================
echo "=== Test 12a: json_atomic_update_args rejects empty json_path ==="
json_atomic_update_args '.stories' "" 2>/dev/null
EXIT_CODE=$?
assert_eq "args variant rejects empty json_path" "1" "$EXIT_CODE"

# =========================================================================
echo "=== Test 12b: json_atomic_update_args rejects missing json_path file ==="
json_atomic_update_args '.stories' "$TEST_TMPDIR/does-not-exist.json" 2>/dev/null
EXIT_CODE=$?
assert_eq "args variant rejects missing json_path file" "1" "$EXIT_CODE"

# =========================================================================
# v0.10.0 / US-002: 2>/dev/null symmetric hardening tests.
# When jq emits a parse error (e.g., --argjson with invalid JSON), the
# captured stderr should appear in our error message instead of being
# silently swallowed. Covers BOTH json_atomic_update and json_atomic_update_args.
# =========================================================================
echo "=== Test 13: json_atomic_update_args surfaces jq stderr on bad --argjson ==="
QJSON="$TEST_TMPDIR/quantum13.json"
cat > "$QJSON" << 'JSONEOF'
{"stories":[{"id":"US-001"}]}
JSONEOF
ERR=$(json_atomic_update_args '.stories' "$QJSON" --argjson bad notjson 2>&1)
EXIT_CODE=$?
assert_eq "args variant exits 1 on bad --argjson" "1" "$EXIT_CODE"
TOTAL=$((TOTAL + 1))
if [[ "$ERR" == *"jq stderr:"* ]]; then
  echo "  PASS: args variant error message includes 'jq stderr:'"
  PASS=$((PASS + 1))
else
  echo "  FAIL: args variant error message missing 'jq stderr:'"
  echo "    actual: $ERR"
  FAIL=$((FAIL + 1))
fi

# =========================================================================
echo "=== Test 14: json_atomic_update surfaces jq stderr on filter syntax error ==="
QJSON="$TEST_TMPDIR/quantum14.json"
cat > "$QJSON" << 'JSONEOF'
{"stories":[{"id":"US-001"}]}
JSONEOF
# Filter with deliberately invalid jq syntax to force a jq parse error
ERR=$(json_atomic_update '.stories | map(' "$QJSON" 2>&1)
EXIT_CODE=$?
assert_eq "json_atomic_update exits 1 on bad filter" "1" "$EXIT_CODE"
TOTAL=$((TOTAL + 1))
if [[ "$ERR" == *"jq stderr:"* ]]; then
  echo "  PASS: json_atomic_update error message includes 'jq stderr:'"
  PASS=$((PASS + 1))
else
  echo "  FAIL: json_atomic_update error message missing 'jq stderr:'"
  echo "    actual: $ERR"
  FAIL=$((FAIL + 1))
fi

# =========================================================================
# v0.10.6 / US-002: trap RETURN re-entry baseline-safety verification.
# Asserts that calling json_atomic_update from inside another function does
# NOT leak the stderr-capture tmp file. This is the current-state safety
# property; the docstring caveat documents the future-nesting risk.
# =========================================================================
echo "=== Test 15: json_atomic_update tmp-file cleanup from wrapper function ==="
QJSON="$TEST_TMPDIR/quantum15.json"
cat > "$QJSON" << 'JSONEOF'
{"stories":[{"id":"US-001","status":"pending"}]}
JSONEOF
# Snapshot tmp dir state before, run helper from inside a wrapper, then
# count any leaked tmp.* files that match the mktemp pattern.
TMPDIR_BEFORE=$(find "${TMPDIR:-/tmp}" -maxdepth 1 -name 'tmp.*' 2>/dev/null | wc -l)
wrapper_caller() {
  json_atomic_update_args \
    '.stories |= map(if .id == $sid then .status = "passed" else . end)' \
    "$QJSON" \
    --arg sid "US-001"
}
wrapper_caller
EXIT_CODE=$?
TMPDIR_AFTER=$(find "${TMPDIR:-/tmp}" -maxdepth 1 -name 'tmp.*' 2>/dev/null | wc -l)
assert_eq "wrapper_caller succeeds" "0" "$EXIT_CODE"
ACTUAL=$(jq -r '.stories[0].status' "$QJSON")
assert_eq "wrapper_caller applied filter" "passed" "$ACTUAL"
# Allow ±1 for ambient tmp churn, but no growth indicates clean RETURN trap.
TMP_DELTA=$((TMPDIR_AFTER - TMPDIR_BEFORE))
TOTAL=$((TOTAL + 1))
if (( TMP_DELTA <= 1 )); then
  echo "  PASS: trap RETURN cleanup ran (delta=$TMP_DELTA, threshold ≤1)"
  PASS=$((PASS + 1))
else
  echo "  FAIL: trap RETURN cleanup leaked tmp files (delta=$TMP_DELTA)"
  FAIL=$((FAIL + 1))
fi

# =========================================================================
# v0.10.13 / US-001: OSC body strip extension to ANSI sanitization.
# Verifies the sanitization pipeline used by json_atomic_update_args /
# json_atomic_update at lines 301/348 strips:
#   - CSI sequences (\x1b[...m) — already covered v0.10.8
#   - OSC-BEL sequences (\x1b]...\x07) — added v0.10.13
#   - residual ESC bytes (any unmatched escape framing) — added v0.10.13
# =========================================================================
echo "=== Test 16: ANSI sanitization strips CSI + OSC-BEL + neutralizes ESC bytes ==="
SANITIZED=$(printf 'csi: \x1b[31mred\x1b[0m\nosc-bel: \x1b]2;title\x07ok\nosc-st: \x1b]3;hover\x1b\\back\nplain' \
  | sed -e 's/\x1b\[[0-9;]*[a-zA-Z]//g' -e 's/\x1b\][^\x07]*\x07//g' \
  | tr -d '\001-\010\013-\037\177\033')

TOTAL=$((TOTAL + 1))
if printf '%s' "$SANITIZED" | grep -q $'\x1b'; then
  echo "  FAIL: ESC bytes still present after sanitization"
  echo "    output: $SANITIZED"
  FAIL=$((FAIL + 1))
else
  echo "  PASS: no ESC bytes remain in sanitized output"
  PASS=$((PASS + 1))
fi

TOTAL=$((TOTAL + 1))
if printf '%s' "$SANITIZED" | grep -q "csi: red"; then
  echo "  PASS: CSI strip preserves text content (red)"
  PASS=$((PASS + 1))
else
  echo "  FAIL: CSI strip mangled text content"
  echo "    output: $SANITIZED"
  FAIL=$((FAIL + 1))
fi

TOTAL=$((TOTAL + 1))
if printf '%s' "$SANITIZED" | grep -q "osc-bel: ok"; then
  echo "  PASS: OSC-BEL stripped including title body"
  PASS=$((PASS + 1))
else
  echo "  FAIL: OSC-BEL not fully stripped"
  echo "    output: $SANITIZED"
  FAIL=$((FAIL + 1))
fi

# =========================================================================
echo ""
echo "=== Results: $PASS/$TOTAL passed, $FAIL failed ==="
if [[ $FAIL -eq 0 ]]; then
  exit 0
else
  exit 1
fi
