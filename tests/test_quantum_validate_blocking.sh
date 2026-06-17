#!/usr/bin/env bash
# tests/test_quantum_validate_blocking.sh — Track A / Q1 blocking-validate tests.

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
    echo "  FAIL: $name (expected [$expected] got [$actual])"; FAIL=$((FAIL + 1))
  fi
}

# Ensure a clean baseline regardless of the caller's environment.
unset QL_VALIDATE_BLOCKING

# shellcheck disable=SC1091
source "$REPO_ROOT/lib/quantum-validate.sh"

TMP=$(mktemp -d)

# Fixture A: eligible story with filePaths but NO surfaceBudget.
cat > "$TMP/missing_budget.json" << 'JSON'
{"stories":[{"id":"US-001","status":"pending","dependsOn":[],
  "tasks":[{"id":"T-001","filePaths":["src/a.py"]}],
  "retries":{"attempts":0,"maxAttempts":3}}]}
JSON

# Fixture B: eligible story WITH surfaceBudget + filePaths (clean).
cat > "$TMP/clean.json" << 'JSON'
{"stories":[{"id":"US-001","status":"pending","dependsOn":[],
  "surfaceBudget":{"maxNewFiles":2,"maxNewLines":100,"maxNewPublicSymbols":8,"maxNewAbstractions":2},
  "tasks":[{"id":"T-001","filePaths":["src/a.py"]}],
  "retries":{"attempts":0,"maxAttempts":3}}]}
JSON

# Fixture C: eligible story with surfaceBudget but EMPTY filePaths.
cat > "$TMP/empty_filepaths.json" << 'JSON'
{"stories":[{"id":"US-001","status":"pending","dependsOn":[],
  "surfaceBudget":{"maxNewLines":100},
  "tasks":[{"id":"T-001","filePaths":[]}],
  "retries":{"attempts":0,"maxAttempts":3}}]}
JSON

echo "=== Track A Q1 blocking-validate tests ==="

# Test 1: advisory by default — missing budget does NOT block (rc 0).
echo ""
echo "Test 1: advisory default (env unset)"
validate_quantum_blocking "$TMP/missing_budget.json" >/dev/null 2>&1; rc=$?
assert "missing budget, env unset -> rc 0" "0" "$rc"

# Test 2: blocking mode — missing budget blocks (rc 1).
echo ""
echo "Test 2: blocking mode, missing surfaceBudget"
QL_VALIDATE_BLOCKING=1 validate_quantum_blocking "$TMP/missing_budget.json" >/dev/null 2>&1; rc=$?
assert "missing budget, blocking -> rc 1" "1" "$rc"

# Test 3: blocking mode — clean story passes (rc 0).
echo ""
echo "Test 3: blocking mode, clean story"
QL_VALIDATE_BLOCKING=1 validate_quantum_blocking "$TMP/clean.json" >/dev/null 2>&1; rc=$?
assert "clean story, blocking -> rc 0" "0" "$rc"

# Test 4: blocking mode — empty filePaths blocks (rc 1).
echo ""
echo "Test 4: blocking mode, empty filePaths"
QL_VALIDATE_BLOCKING=1 validate_quantum_blocking "$TMP/empty_filepaths.json" >/dev/null 2>&1; rc=$?
assert "empty filePaths, blocking -> rc 1" "1" "$rc"

# Test 5: validate_story_surface_budget standalone (env unset = advisory).
echo ""
echo "Test 5: validate_story_surface_budget advisory"
validate_story_surface_budget "$TMP/missing_budget.json" >/dev/null 2>&1; rc=$?
assert "surface-budget validator, env unset -> rc 0" "0" "$rc"

# Test 6: validate_story_surface_budget standalone (blocking).
echo ""
echo "Test 6: validate_story_surface_budget blocking"
QL_VALIDATE_BLOCKING=1 validate_story_surface_budget "$TMP/missing_budget.json" >/dev/null 2>&1; rc=$?
assert "surface-budget validator, blocking -> rc 1" "1" "$rc"

# Test 7: backward-compat — validate_story_filepaths stays advisory (rc 0).
echo ""
echo "Test 7: validate_story_filepaths unchanged (advisory)"
QL_VALIDATE_BLOCKING=1 validate_story_filepaths "$TMP/empty_filepaths.json" >/dev/null 2>&1; rc=$?
assert "filepaths validator stays advisory -> rc 0" "0" "$rc"

# Test 8: missing file -> rc 1 (defensive).
echo ""
echo "Test 8: missing file"
validate_quantum_blocking "$TMP/does_not_exist.json" >/dev/null 2>&1; rc=$?
assert "missing file -> rc 1" "1" "$rc"

rm -rf "$TMP"

echo ""
echo "=== Results: $PASS/$TOTAL passed, $FAIL failed ==="
exit $((FAIL > 0 ? 1 : 0))
