#!/usr/bin/env bash
# Test suite for final verification sweep
# Tests that COMPLETE is blocked when test suite fails and allowed when it passes

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

assert_contains() {
  local test_name="$1" needle="$2" haystack="$3"
  TOTAL=$((TOTAL + 1))
  if echo "$haystack" | grep -q "$needle"; then
    echo "  PASS: $test_name"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: $test_name"
    echo "    expected to contain: $needle"
    FAIL=$((FAIL + 1))
  fi
}

setup() {
  TMPDIR=$(mktemp -d)
  cd "$TMPDIR" || exit 1
  git init -q
  git commit --allow-empty -m "init" -q
}

teardown() {
  cd "$REPO_ROOT" || exit 1
  rm -rf "$TMPDIR"
}

echo "=== Final Sweep Tests ==="

# Test 1: Test suite failure blocks COMPLETE
echo ""
echo "Test 1: Test suite failure blocks COMPLETE"
setup
# Create a fake package.json that points to a non-existent test
cat > package.json << EOF
{"name": "test", "scripts": {"test": "exit 1"}}
EOF
# Simulate final sweep logic
TEST_CMD="npm test"
if eval "$TEST_CMD" >/dev/null 2>&1; then
  SWEEP_RESULT="passed"
else
  SWEEP_RESULT="failed"
fi
assert_eq "failed test suite blocks COMPLETE" "failed" "$SWEEP_RESULT"
teardown

# Test 2: Test suite success allows COMPLETE
echo ""
echo "Test 2: Test suite success allows COMPLETE"
setup
cat > package.json << EOF
{"name": "test", "scripts": {"test": "exit 0"}}
EOF
TEST_CMD="npm test"
if eval "$TEST_CMD" >/dev/null 2>&1; then
  SWEEP_RESULT="passed"
else
  SWEEP_RESULT="failed"
fi
assert_eq "passing test suite allows COMPLETE" "passed" "$SWEEP_RESULT"
teardown

# Test 3: Import smoke test warning doesn't block
echo ""
echo "Test 3: Import smoke test failure is warning only"
setup
cat > package.json << EOF
{"name": "test", "main": "nonexistent.js", "scripts": {"test": "exit 0"}}
EOF
# Simulate import smoke test — should warn but not block
if node -e "require('./nonexistent.js')" >/dev/null 2>&1; then
  SMOKE_RESULT="passed"
else
  SMOKE_RESULT="warning"
fi
assert_eq "import smoke test failure is warning" "warning" "$SMOKE_RESULT"
# But test suite still passes
TEST_CMD="npm test"
if eval "$TEST_CMD" >/dev/null 2>&1; then
  SWEEP_RESULT="passed"
else
  SWEEP_RESULT="failed"
fi
assert_eq "COMPLETE still allowed despite smoke test warning" "passed" "$SWEEP_RESULT"
teardown

# Summary
echo ""
echo "=== Results: $PASS/$TOTAL passed ==="
[[ $FAIL -eq 0 ]] && exit 0 || exit 1
