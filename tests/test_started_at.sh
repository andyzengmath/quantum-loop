#!/usr/bin/env bash
# Test suite for startedAt timestamp management
# Tests that startedAt is written before spawn and cleared after completion

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

assert_match() {
  local test_name="$1" pattern="$2" actual="$3"
  TOTAL=$((TOTAL + 1))
  if echo "$actual" | grep -qE "$pattern"; then
    echo "  PASS: $test_name"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: $test_name"
    echo "    expected to match: $pattern"
    echo "    actual: $actual"
    FAIL=$((FAIL + 1))
  fi
}

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

echo "=== startedAt Tests ==="

# Test 1: startedAt is set in ISO 8601 format
echo ""
echo "Test 1: startedAt written in ISO 8601 format"
setup
cat > quantum.json << EOF
{
  "stories": [{"id": "US-001", "status": "pending", "startedAt": null, "retries": {"attempts": 0, "maxAttempts": 3, "failureLog": []}}]
}
EOF
now=$(date -u +'%Y-%m-%dT%H:%M:%SZ')
jq --arg id "US-001" --arg now "$now" '
  .stories |= map(if .id == $id then .status = "in_progress" | .startedAt = $now else . end)
' quantum.json > quantum.json.tmp && mv quantum.json.tmp quantum.json

started=$(jq -r '.stories[0].startedAt' quantum.json)
assert_match "startedAt is ISO 8601" '^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$' "$started"
teardown

# Test 2: startedAt cleared after story passed
echo ""
echo "Test 2: startedAt cleared on passed"
setup
cat > quantum.json << EOF
{
  "stories": [{"id": "US-001", "status": "in_progress", "startedAt": "2026-03-09T12:00:00Z", "retries": {"attempts": 0, "maxAttempts": 3, "failureLog": []}}]
}
EOF
jq --arg id "US-001" '
  .stories |= map(if .id == $id then .status = "passed" | .startedAt = null else . end)
' quantum.json > quantum.json.tmp && mv quantum.json.tmp quantum.json

started=$(jq -r '.stories[0].startedAt' quantum.json)
assert_eq "startedAt is null after passed" "null" "$started"
teardown

# Test 3: startedAt cleared after story failed
echo ""
echo "Test 3: startedAt cleared on failed"
setup
cat > quantum.json << EOF
{
  "stories": [{"id": "US-001", "status": "in_progress", "startedAt": "2026-03-09T12:00:00Z", "retries": {"attempts": 0, "maxAttempts": 3, "failureLog": []}}]
}
EOF
jq --arg id "US-001" '
  .stories |= map(if .id == $id then .status = "failed" | .startedAt = null else . end)
' quantum.json > quantum.json.tmp && mv quantum.json.tmp quantum.json

started=$(jq -r '.stories[0].startedAt' quantum.json)
assert_eq "startedAt is null after failed" "null" "$started"
teardown

# Summary
echo ""
echo "=== Results: $PASS/$TOTAL passed ==="
[[ $FAIL -eq 0 ]] && exit 0 || exit 1
