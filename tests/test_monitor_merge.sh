#!/usr/bin/env bash
# Test suite for lib/monitor.sh
# Tests agent polling, signal detection, and worktree merge functions

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

assert_not_contains() {
  local test_name="$1" needle="$2" haystack="$3"
  TOTAL=$((TOTAL + 1))
  if ! echo "$haystack" | grep -q "$needle"; then
    echo "  PASS: $test_name"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: $test_name"
    echo "    expected NOT to contain: $needle"
    echo "    actual: $haystack"
    FAIL=$((FAIL + 1))
  fi
}

# Helper: create a test git repo
setup_test_repo() {
  local test_dir
  test_dir=$(mktemp -d)
  git -C "$test_dir" init -q
  git -C "$test_dir" commit --allow-empty -m "init" -q
  echo "$test_dir"
}

# =========================================================================
echo "=== Test 1: detect_signal finds STORY_PASSED ==="
TMPFILE=$(mktemp)
cat > "$TMPFILE" <<'EOF'
Some output from the agent...
Working on story US-001
<quantum>STORY_PASSED</quantum>
Done.
EOF
SIGNAL=$(detect_signal "$TMPFILE")
assert_eq "Detects STORY_PASSED" "STORY_PASSED" "$SIGNAL"
rm -f "$TMPFILE"

# =========================================================================
echo "=== Test 2: detect_signal finds STORY_FAILED ==="
TMPFILE=$(mktemp)
cat > "$TMPFILE" <<'EOF'
Some output...
<quantum>STORY_FAILED</quantum>
EOF
SIGNAL=$(detect_signal "$TMPFILE")
assert_eq "Detects STORY_FAILED" "STORY_FAILED" "$SIGNAL"
rm -f "$TMPFILE"

# =========================================================================
echo "=== Test 3: detect_signal returns empty for no signal ==="
TMPFILE=$(mktemp)
printf "Still working...\n" > "$TMPFILE"
SIGNAL=$(detect_signal "$TMPFILE")
assert_eq "No signal returns empty" "" "$SIGNAL"
rm -f "$TMPFILE"

# =========================================================================
echo "=== Test 4: detect_signal returns empty for nonexistent file ==="
SIGNAL=$(detect_signal "/tmp/nonexistent-file-$$")
assert_eq "Nonexistent file returns empty" "" "$SIGNAL"

# =========================================================================
echo "=== Test 5: check_agent_status detects completed process with PASSED ==="
# Create a mock output file with STORY_PASSED
TEST_WT=$(mktemp -d)
cat > "$TEST_WT/$AGENT_OUTPUT_FILENAME" <<'EOF'
Implementing story...
<quantum>STORY_PASSED</quantum>
EOF

# Use a finished PID (PID 1 is always running, use a known-finished one)
# Create a short-lived background process that has already finished
bash -c "exit 0" &
DONE_PID=$!
wait "$DONE_PID" 2>/dev/null

RESULT=$(check_agent_status "$DONE_PID" "$TEST_WT")
assert_contains "Completed agent returns STORY_PASSED" "STORY_PASSED" "$RESULT"
rm -rf "$TEST_WT"

# =========================================================================
echo "=== Test 6: check_agent_status returns RUNNING for active process ==="
# Start a sleep process
sleep 30 &
SLEEP_PID=$!

TEST_WT=$(mktemp -d)
printf "Still working...\n" > "$TEST_WT/$AGENT_OUTPUT_FILENAME"

RESULT=$(check_agent_status "$SLEEP_PID" "$TEST_WT")
assert_eq "Running agent returns RUNNING" "RUNNING" "$RESULT"

kill "$SLEEP_PID" 2>/dev/null
wait "$SLEEP_PID" 2>/dev/null || true
rm -rf "$TEST_WT"

# =========================================================================
echo "=== Test 7: check_agent_status detects crash (no signal, process done) ==="
TEST_WT=$(mktemp -d)
printf "Some partial output\n" > "$TEST_WT/$AGENT_OUTPUT_FILENAME"

bash -c "exit 1" &
CRASH_PID=$!
wait "$CRASH_PID" 2>/dev/null || true

RESULT=$(check_agent_status "$CRASH_PID" "$TEST_WT")
assert_eq "Crashed agent returns CRASH" "CRASH" "$RESULT"
rm -rf "$TEST_WT"

# =========================================================================
echo "=== Test 8: merge_worktree_branch merges commits into feature branch ==="
TEST_REPO=$(setup_test_repo)
FEATURE_BRANCH="feature-test"
git -C "$TEST_REPO" checkout -b "$FEATURE_BRANCH" -q

# Create a "worktree branch" with a commit
git -C "$TEST_REPO" checkout -b "ql-wt/US-001" -q
printf "new file content\n" > "$TEST_REPO/newfile.txt"
git -C "$TEST_REPO" add newfile.txt
git -C "$TEST_REPO" commit -m "worktree commit" -q

# Go back to feature branch
git -C "$TEST_REPO" checkout "$FEATURE_BRANCH" -q

# Merge
merge_worktree_branch "$TEST_REPO" "ql-wt/US-001"
EXIT_CODE=$?
assert_eq "merge_worktree_branch exits 0" "0" "$EXIT_CODE"

# Verify merge brought the file
if [[ -f "$TEST_REPO/newfile.txt" ]]; then
  TOTAL=$((TOTAL + 1)); echo "  PASS: Merged file exists on feature branch"; PASS=$((PASS + 1))
else
  TOTAL=$((TOTAL + 1)); echo "  FAIL: Merged file missing from feature branch"; FAIL=$((FAIL + 1))
fi

rm -rf "$TEST_REPO"

# =========================================================================
echo "=== Test 9: merge_worktree_branch detects merge conflict ==="
TEST_REPO=$(setup_test_repo)
FEATURE_BRANCH="feature-test"
git -C "$TEST_REPO" checkout -b "$FEATURE_BRANCH" -q

# Create conflicting content on feature branch
printf "feature content\n" > "$TEST_REPO/conflict.txt"
git -C "$TEST_REPO" add conflict.txt
git -C "$TEST_REPO" commit -m "feature commit" -q

# Create worktree branch with conflicting content
git -C "$TEST_REPO" checkout -b "ql-wt/US-002" HEAD~1 -q
printf "worktree content\n" > "$TEST_REPO/conflict.txt"
git -C "$TEST_REPO" add conflict.txt
git -C "$TEST_REPO" commit -m "worktree commit" -q

# Go back to feature branch
git -C "$TEST_REPO" checkout "$FEATURE_BRANCH" -q

# Merge should fail
merge_worktree_branch "$TEST_REPO" "ql-wt/US-002"
EXIT_CODE=$?
assert_eq "merge_worktree_branch returns 1 on conflict" "1" "$EXIT_CODE"

# Verify merge was aborted (working tree clean)
STATUS=$(git -C "$TEST_REPO" status --porcelain)
assert_eq "Working tree clean after conflict abort" "" "$STATUS"

rm -rf "$TEST_REPO"

# =========================================================================
echo "=== Test 10: Input validation ==="
RESULT=$(detect_signal "" 2>&1)
EXIT_CODE=$?
assert_eq "detect_signal empty file returns empty" "" "$RESULT"

RESULT=$(check_agent_status "" "/tmp" 2>&1)
EXIT_CODE=$?
assert_eq "check_agent_status empty PID returns error" "1" "$EXIT_CODE"

RESULT=$(merge_worktree_branch "" "branch" 2>&1)
EXIT_CODE=$?
assert_eq "merge_worktree_branch empty repo returns error" "1" "$EXIT_CODE"

RESULT=$(merge_worktree_branch "/tmp" "" 2>&1)
EXIT_CODE=$?
assert_eq "merge_worktree_branch empty branch returns error" "1" "$EXIT_CODE"

# =========================================================================
echo ""
echo "=== Results: $PASS/$TOTAL passed, $FAIL failed ==="
if [[ $FAIL -eq 0 ]]; then
  exit 0
else
  exit 1
fi
