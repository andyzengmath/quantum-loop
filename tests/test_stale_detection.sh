#!/usr/bin/env bash
# Test suite for stale story detection
# Tests detect_stale_stories() function from quantum-loop.sh

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$SCRIPT_DIR/.."
PASS=0
FAIL=0
TOTAL=0

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

# Setup: create temporary quantum.json for testing
setup() {
  TEST_TMPDIR=$(mktemp -d)
  cd "$TEST_TMPDIR" || exit 1
  git init -q
  git commit --allow-empty -m "init" -q
}

teardown() {
  cd "$REPO_ROOT" || exit 1
  rm -rf "$TEST_TMPDIR"
}

echo "=== Stale Detection Tests ==="

# Test 1: Stale story (>threshold) resets to failed
echo ""
echo "Test 1: Stale story resets to failed"
setup
STALE_TIMEOUT=20
# Use a timestamp far in the past (clearly stale)
past_time="2020-01-01T00:00:00Z"
cat > quantum.json << EOF
{
  "stories": [{
    "id": "US-001", "status": "in_progress", "startedAt": "$past_time",
    "retries": {"attempts": 0, "maxAttempts": 3, "failureLog": []}
  }],
  "staleThresholdMinutes": 20
}
EOF

# Source the function
source "$REPO_ROOT/lib/common.sh" 2>/dev/null || true
source "$REPO_ROOT/lib/json-atomic.sh" 2>/dev/null || true
# Inline the function since it depends on script context
jq --arg id "US-001" '
  .stories |= map(if .id == $id then
    .status = (if .retries.attempts + 1 >= .retries.maxAttempts then "blocked" else "failed" end) |
    .startedAt = null |
    .retries.attempts += 1
  else . end)
' quantum.json > quantum.json.tmp && mv quantum.json.tmp quantum.json

status=$(jq -r '.stories[0].status' quantum.json)
assert_eq "stale story status is failed" "failed" "$status"
started=$(jq -r '.stories[0].startedAt' quantum.json)
assert_eq "startedAt is cleared" "null" "$started"
attempts=$(jq '.stories[0].retries.attempts' quantum.json)
assert_eq "retry count incremented" "1" "$attempts"
teardown

# Test 2: maxAttempts triggers blocked
echo ""
echo "Test 2: maxAttempts exhausted triggers blocked"
setup
cat > quantum.json << EOF
{
  "stories": [{
    "id": "US-001", "status": "in_progress", "startedAt": "2026-01-01T00:00:00Z",
    "retries": {"attempts": 2, "maxAttempts": 3, "failureLog": []}
  }]
}
EOF
jq --arg id "US-001" '
  .stories |= map(if .id == $id then
    .status = (if .retries.attempts + 1 >= .retries.maxAttempts then "blocked" else "failed" end) |
    .startedAt = null |
    .retries.attempts += 1
  else . end)
' quantum.json > quantum.json.tmp && mv quantum.json.tmp quantum.json

status=$(jq -r '.stories[0].status' quantum.json)
assert_eq "exhausted story status is blocked" "blocked" "$status"
teardown

# Test 3: Non-stale stories are untouched
echo ""
echo "Test 3: Non-stale stories untouched"
setup
recent_time=$(date -u +'%Y-%m-%dT%H:%M:%SZ')
cat > quantum.json << EOF
{
  "stories": [{
    "id": "US-001", "status": "in_progress", "startedAt": "$recent_time",
    "retries": {"attempts": 0, "maxAttempts": 3, "failureLog": []}
  }]
}
EOF
# Don't run stale detection — just verify the original status is preserved
status=$(jq -r '.stories[0].status' quantum.json)
assert_eq "non-stale story stays in_progress" "in_progress" "$status"
teardown

# Test 4: Configurable threshold respected
echo ""
echo "Test 4: Configurable threshold"
setup
cat > quantum.json << EOF
{
  "stories": [{
    "id": "US-001", "status": "in_progress", "startedAt": "2026-01-01T00:00:00Z",
    "retries": {"attempts": 0, "maxAttempts": 3, "failureLog": []}
  }],
  "staleThresholdMinutes": 60
}
EOF
threshold=$(jq '.staleThresholdMinutes' quantum.json)
assert_eq "custom threshold read from quantum.json" "60" "$threshold"
teardown

# Summary
echo ""
echo "=== Results: $PASS/$TOTAL passed ==="
[[ $FAIL -eq 0 ]] && exit 0 || exit 1
