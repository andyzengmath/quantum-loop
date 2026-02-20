#!/usr/bin/env bash
# Test suite for lib/worktree.sh
# Tests worktree creation, removal, and listing using a temporary git repo

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="$SCRIPT_DIR/../lib"
PASS=0
FAIL=0
TOTAL=0

# Source the library under test
if [[ ! -f "$LIB_DIR/worktree.sh" ]]; then
  echo "SKIP: lib/worktree.sh not found (RED phase)"
  exit 1
fi
source "$LIB_DIR/worktree.sh"

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

assert_dir_exists() {
  local test_name="$1" dir="$2"
  TOTAL=$((TOTAL + 1))
  if [[ -d "$dir" ]]; then
    echo "  PASS: $test_name"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: $test_name (directory not found: $dir)"
    FAIL=$((FAIL + 1))
  fi
}

assert_dir_not_exists() {
  local test_name="$1" dir="$2"
  TOTAL=$((TOTAL + 1))
  if [[ ! -d "$dir" ]]; then
    echo "  PASS: $test_name"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: $test_name (directory still exists: $dir)"
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
# Setup: create a temporary git repo for testing
# =========================================================================
TMPDIR=$(mktemp -d)
ORIG_DIR=$(pwd)

setup_test_repo() {
  cd "$TMPDIR"
  git init --initial-branch=main . >/dev/null 2>&1
  git config user.email "test@test.com"
  git config user.name "Test"
  echo "initial" > file.txt
  git add file.txt
  git commit -m "initial commit" >/dev/null 2>&1
  # Create a feature branch to simulate ql/parallel-execution
  git checkout -b ql/test-feature >/dev/null 2>&1
  echo "feature work" > feature.txt
  git add feature.txt
  git commit -m "feature commit" >/dev/null 2>&1
}

cleanup_test_repo() {
  cd "$ORIG_DIR"
  # Force remove worktrees before deleting the temp dir
  if [[ -d "$TMPDIR" ]]; then
    cd "$TMPDIR" 2>/dev/null && git worktree list --porcelain 2>/dev/null | grep "^worktree " | while read -r _ path; do
      if [[ "$path" != "$TMPDIR" ]]; then
        git worktree remove --force "$path" 2>/dev/null || true
      fi
    done
    cd "$ORIG_DIR"
    rm -rf "$TMPDIR"
  fi
}

trap cleanup_test_repo EXIT

setup_test_repo

# =========================================================================
echo "=== Test 1: Create worktree at correct path ==="
RESULT=$(create_worktree "US-001" "ql/test-feature" "$TMPDIR")
EXIT_CODE=$?
assert_eq "create_worktree exits 0" "0" "$EXIT_CODE"
assert_dir_exists "Worktree directory created" "$TMPDIR/.ql-wt/US-001"

# =========================================================================
echo "=== Test 2: Worktree has feature branch content ==="
assert_eq "Feature file exists in worktree" "0" "$(test -f "$TMPDIR/.ql-wt/US-001/feature.txt" && echo 0 || echo 1)"

# =========================================================================
echo "=== Test 3: List worktrees includes the new worktree ==="
WORKTREES=$(list_worktrees "$TMPDIR")
assert_contains "US-001 worktree listed" "US-001" "$WORKTREES"

# =========================================================================
echo "=== Test 4: Remove worktree cleans up ==="
remove_worktree "US-001" "$TMPDIR"
EXIT_CODE=$?
assert_eq "remove_worktree exits 0" "0" "$EXIT_CODE"
assert_dir_not_exists "Worktree directory removed" "$TMPDIR/.ql-wt/US-001"

# =========================================================================
echo "=== Test 5: List worktrees after removal ==="
WORKTREES=$(list_worktrees "$TMPDIR")
TOTAL=$((TOTAL + 1))
if echo "$WORKTREES" | grep -q "US-001"; then
  echo "  FAIL: US-001 should not be listed after removal"
  FAIL=$((FAIL + 1))
else
  echo "  PASS: US-001 not listed after removal"
  PASS=$((PASS + 1))
fi

# =========================================================================
echo "=== Test 6: Remove nonexistent worktree is idempotent ==="
remove_worktree "US-999" "$TMPDIR" 2>/dev/null
EXIT_CODE=$?
assert_eq "remove_worktree for nonexistent exits 0" "0" "$EXIT_CODE"

# =========================================================================
echo ""
echo "=== Results: $PASS/$TOTAL passed, $FAIL failed ==="
if [[ $FAIL -eq 0 ]]; then
  exit 0
else
  exit 1
fi
