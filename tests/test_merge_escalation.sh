#!/usr/bin/env bash
# tests/test_merge_escalation.sh -- Tests for merge_worktree_branch() conflict classification
#
# 6 test cases:
#   1. No conflict merge -> returns 0
#   2. Conflicting branches -> returns 1 with conflict files on stdout
#   3. After failed merge, working tree is clean
#   4. Output format includes file names prefixed with CONFLICT:
#   5. Multiple files conflicting simultaneously -> all listed
#   6. Merge with unrelated changes (different files) -> succeeds

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="$SCRIPT_DIR/../lib"
PASS=0
FAIL=0
TOTAL=0

# Source dependencies
source "$LIB_DIR/common.sh"
source "$LIB_DIR/json-atomic.sh"
source "$LIB_DIR/spawn.sh"

# Source the library under test
if [[ ! -f "$LIB_DIR/monitor.sh" ]]; then
  echo "SKIP: lib/monitor.sh not found (RED phase)"
  exit 1
fi
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
  if echo "$haystack" | grep -qF "$needle"; then
    echo "  PASS: $test_name"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: $test_name"
    echo "    expected to contain: $needle"
    echo "    actual: $haystack"
    FAIL=$((FAIL + 1))
  fi
}

# Helper: create a test git repo with an initial commit
setup_test_repo() {
  local test_dir
  test_dir=$(mktemp -d)
  git -C "$test_dir" init -q
  git -C "$test_dir" config user.email "test@test.com"
  git -C "$test_dir" config user.name "Test"
  git -C "$test_dir" commit --allow-empty -m "init" -q
  echo "$test_dir"
}

# =========================================================================
echo "=== Test 1: No conflict merge returns 0 ==="
TEST_REPO=$(setup_test_repo)
FEATURE_BRANCH="feature-merge-test"
git -C "$TEST_REPO" checkout -b "$FEATURE_BRANCH" -q

# Create a worktree branch with a non-conflicting commit
git -C "$TEST_REPO" checkout -b "ql-wt/US-CLEAN" -q
printf "clean file content\n" > "$TEST_REPO/clean.txt"
git -C "$TEST_REPO" add clean.txt
git -C "$TEST_REPO" commit -m "clean worktree commit" -q

# Switch back to feature branch
git -C "$TEST_REPO" checkout "$FEATURE_BRANCH" -q

# Merge -- should succeed
OUTPUT=$(merge_worktree_branch "$TEST_REPO" "ql-wt/US-CLEAN" 2>&1)
EXIT_CODE=$?
assert_eq "No conflict merge returns 0" "0" "$EXIT_CODE"

# Verify the file was merged
if [[ -f "$TEST_REPO/clean.txt" ]]; then
  TOTAL=$((TOTAL + 1)); echo "  PASS: Merged file exists on feature branch"; PASS=$((PASS + 1))
else
  TOTAL=$((TOTAL + 1)); echo "  FAIL: Merged file missing from feature branch"; FAIL=$((FAIL + 1))
fi

rm -rf "$TEST_REPO"

# =========================================================================
echo "=== Test 2: Conflicting branches returns 1 with conflict files on stdout ==="
TEST_REPO=$(setup_test_repo)
FEATURE_BRANCH="feature-conflict-test"
git -C "$TEST_REPO" checkout -b "$FEATURE_BRANCH" -q

# Create conflicting content on feature branch
printf "feature version of file\n" > "$TEST_REPO/shared.txt"
git -C "$TEST_REPO" add shared.txt
git -C "$TEST_REPO" commit -m "feature commit" -q

# Create worktree branch diverging from before the feature commit
git -C "$TEST_REPO" checkout -b "ql-wt/US-CONFLICT" HEAD~1 -q
printf "worktree version of file\n" > "$TEST_REPO/shared.txt"
git -C "$TEST_REPO" add shared.txt
git -C "$TEST_REPO" commit -m "worktree commit" -q

# Switch back to feature branch
git -C "$TEST_REPO" checkout "$FEATURE_BRANCH" -q

# Merge -- should fail with conflict info on stdout
OUTPUT=$(merge_worktree_branch "$TEST_REPO" "ql-wt/US-CONFLICT")
EXIT_CODE=$?
assert_eq "Conflicting merge returns 1" "1" "$EXIT_CODE"
assert_contains "Output includes conflict file name" "shared.txt" "$OUTPUT"

rm -rf "$TEST_REPO"

# =========================================================================
echo "=== Test 3: After failed merge, working tree is clean ==="
TEST_REPO=$(setup_test_repo)
FEATURE_BRANCH="feature-clean-test"
git -C "$TEST_REPO" checkout -b "$FEATURE_BRANCH" -q

# Create conflicting content on feature branch
printf "feature content\n" > "$TEST_REPO/dirty.txt"
git -C "$TEST_REPO" add dirty.txt
git -C "$TEST_REPO" commit -m "feature commit" -q

# Create worktree branch with conflicting content
git -C "$TEST_REPO" checkout -b "ql-wt/US-DIRTY" HEAD~1 -q
printf "worktree content\n" > "$TEST_REPO/dirty.txt"
git -C "$TEST_REPO" add dirty.txt
git -C "$TEST_REPO" commit -m "worktree commit" -q

# Switch back to feature branch
git -C "$TEST_REPO" checkout "$FEATURE_BRANCH" -q

# Trigger conflict
merge_worktree_branch "$TEST_REPO" "ql-wt/US-DIRTY" > /dev/null 2>&1

# Verify working tree is clean after abort
STATUS=$(git -C "$TEST_REPO" status --porcelain)
assert_eq "Working tree clean after conflict abort" "" "$STATUS"

rm -rf "$TEST_REPO"

# =========================================================================
echo "=== Test 4: Output format includes CONFLICT: prefix on file names ==="
TEST_REPO=$(setup_test_repo)
FEATURE_BRANCH="feature-format-test"
git -C "$TEST_REPO" checkout -b "$FEATURE_BRANCH" -q

# Create conflicting content on feature branch
printf "feature line\n" > "$TEST_REPO/format_test.txt"
git -C "$TEST_REPO" add format_test.txt
git -C "$TEST_REPO" commit -m "feature commit" -q

# Create worktree branch with conflicting content
git -C "$TEST_REPO" checkout -b "ql-wt/US-FORMAT" HEAD~1 -q
printf "worktree line\n" > "$TEST_REPO/format_test.txt"
git -C "$TEST_REPO" add format_test.txt
git -C "$TEST_REPO" commit -m "worktree commit" -q

# Switch back to feature branch
git -C "$TEST_REPO" checkout "$FEATURE_BRANCH" -q

# Merge and capture output
OUTPUT=$(merge_worktree_branch "$TEST_REPO" "ql-wt/US-FORMAT")
EXIT_CODE=$?
assert_eq "Returns 1 on conflict" "1" "$EXIT_CODE"
assert_contains "Output has CONFLICT: prefix" "CONFLICT: format_test.txt" "$OUTPUT"

rm -rf "$TEST_REPO"

# =========================================================================
echo "=== Test 5: Multiple files conflicting simultaneously ==="
TEST_REPO=$(setup_test_repo)
FEATURE_BRANCH="feature-multi-conflict"
git -C "$TEST_REPO" checkout -b "$FEATURE_BRANCH" -q

# Create multiple files on feature branch
printf "feature alpha\n" > "$TEST_REPO/alpha.txt"
printf "feature beta\n" > "$TEST_REPO/beta.txt"
printf "feature gamma\n" > "$TEST_REPO/gamma.txt"
git -C "$TEST_REPO" add alpha.txt beta.txt gamma.txt
git -C "$TEST_REPO" commit -m "feature multi commit" -q

# Create worktree branch diverging from before, with conflicting content in all 3 files
git -C "$TEST_REPO" checkout -b "ql-wt/US-MULTI" HEAD~1 -q
printf "worktree alpha\n" > "$TEST_REPO/alpha.txt"
printf "worktree beta\n" > "$TEST_REPO/beta.txt"
printf "worktree gamma\n" > "$TEST_REPO/gamma.txt"
git -C "$TEST_REPO" add alpha.txt beta.txt gamma.txt
git -C "$TEST_REPO" commit -m "worktree multi commit" -q

# Switch back to feature branch
git -C "$TEST_REPO" checkout "$FEATURE_BRANCH" -q

# Merge -- should fail with all 3 files listed
OUTPUT=$(merge_worktree_branch "$TEST_REPO" "ql-wt/US-MULTI")
EXIT_CODE=$?
assert_eq "Multiple conflict merge returns 1" "1" "$EXIT_CODE"
assert_contains "Output lists alpha.txt" "CONFLICT: alpha.txt" "$OUTPUT"
assert_contains "Output lists beta.txt" "CONFLICT: beta.txt" "$OUTPUT"
assert_contains "Output lists gamma.txt" "CONFLICT: gamma.txt" "$OUTPUT"

# Verify working tree is clean after abort
STATUS=$(git -C "$TEST_REPO" status --porcelain)
assert_eq "Working tree clean after multi-conflict abort" "" "$STATUS"

rm -rf "$TEST_REPO"

# =========================================================================
echo "=== Test 6: Merge with unrelated changes (different files) succeeds ==="
TEST_REPO=$(setup_test_repo)
FEATURE_BRANCH="feature-unrelated"
git -C "$TEST_REPO" checkout -b "$FEATURE_BRANCH" -q

# Create a file on the feature branch
printf "feature only file\n" > "$TEST_REPO/feature_only.txt"
git -C "$TEST_REPO" add feature_only.txt
git -C "$TEST_REPO" commit -m "feature only commit" -q

# Create worktree branch from the same divergence point, with a DIFFERENT file
git -C "$TEST_REPO" checkout -b "ql-wt/US-UNRELATED" HEAD~1 -q
printf "worktree only file\n" > "$TEST_REPO/worktree_only.txt"
git -C "$TEST_REPO" add worktree_only.txt
git -C "$TEST_REPO" commit -m "worktree only commit" -q

# Switch back to feature branch
git -C "$TEST_REPO" checkout "$FEATURE_BRANCH" -q

# Merge -- should succeed because files don't overlap
OUTPUT=$(merge_worktree_branch "$TEST_REPO" "ql-wt/US-UNRELATED" 2>&1)
EXIT_CODE=$?
assert_eq "Unrelated changes merge returns 0" "0" "$EXIT_CODE"

# Verify both files exist after merge
if [[ -f "$TEST_REPO/feature_only.txt" && -f "$TEST_REPO/worktree_only.txt" ]]; then
  TOTAL=$((TOTAL + 1)); echo "  PASS: Both files present after merge"; PASS=$((PASS + 1))
else
  TOTAL=$((TOTAL + 1)); echo "  FAIL: Missing files after unrelated merge"; FAIL=$((FAIL + 1))
fi

rm -rf "$TEST_REPO"

# =========================================================================
echo ""
echo "=== Results: $PASS/$TOTAL passed, $FAIL failed ==="
if [[ $FAIL -eq 0 ]]; then
  exit 0
else
  exit 1
fi
