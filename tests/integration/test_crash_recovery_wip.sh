#!/usr/bin/env bash
# tests/integration/test_crash_recovery_wip.sh
# Integration test for crash recovery with WIP commits:
#   1. Create a temp git repo with quantum.json containing story US-TEST
#   2. Create a worktree at .ql-wt/US-TEST
#   3. In the worktree, make 3 WIP commits (T-001, T-002, T-003)
#   4. Call detect_resumable_work -- verify it returns resumable:<sha>:T-001,T-002,T-003
#   5. Call build_agent_prompt with completed_tasks -- verify "Previously completed tasks"
#   6. Verify worktree WIP commits are intact
#   7. Clean up

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="$SCRIPT_DIR/../../lib"
PASS=0
FAIL=0
TOTAL=0

# Source the libraries under test
if [[ ! -f "$LIB_DIR/resilience.sh" ]]; then
  echo "SKIP: lib/resilience.sh not found (dependency not yet merged)"
  exit 1
fi
source "$LIB_DIR/resilience.sh"

if [[ ! -f "$LIB_DIR/spawn.sh" ]]; then
  echo "SKIP: lib/spawn.sh not found (dependency not yet merged)"
  exit 1
fi
source "$LIB_DIR/spawn.sh"

# === Helpers ===

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

assert_starts_with() {
  local test_name="$1" prefix="$2" actual="$3"
  TOTAL=$((TOTAL + 1))
  if [[ "$actual" == "$prefix"* ]]; then
    echo "  PASS: $test_name"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: $test_name"
    echo "    expected to start with: $prefix"
    echo "    actual: $actual"
    FAIL=$((FAIL + 1))
  fi
}

# =========================================================================
# Setup: create a temporary git repo with quantum.json
# =========================================================================
TEST_TMPDIR=$(mktemp -d)
ORIG_DIR=$(pwd)

cleanup_test_repo() {
  cd "$ORIG_DIR" 2>/dev/null || true
  if [[ -d "$TEST_TMPDIR" ]]; then
    # Remove any git worktrees first to avoid lock issues
    cd "$TEST_TMPDIR" 2>/dev/null && git worktree list --porcelain 2>/dev/null | grep "^worktree " | while read -r _ path; do
      if [[ "$path" != "$TEST_TMPDIR" ]]; then
        git worktree remove --force "$path" 2>/dev/null || true
      fi
    done
    cd "$ORIG_DIR" 2>/dev/null || true
    rm -rf "$TEST_TMPDIR"
  fi
}

trap cleanup_test_repo EXIT

echo "=== Integration Test: Crash Recovery with WIP Commits ==="
echo ""

# =========================================================================
echo "--- Step 1: Create temp git repo with quantum.json ---"

cd "$TEST_TMPDIR"
git init --initial-branch=main . >/dev/null 2>&1
git config user.email "test@test.com"
git config user.name "Test"

# Create initial commit
echo "initial content" > file.txt
git add file.txt
git commit -m "initial commit" >/dev/null 2>&1

# Create quantum.json with a story US-TEST having tasks T-001, T-002, T-003
cat > "$TEST_TMPDIR/quantum.json" <<'JSONEOF'
{
  "project": "test-crash-recovery-wip",
  "stories": [
    {
      "id": "US-TEST",
      "title": "Test story for WIP crash recovery",
      "status": "in_progress",
      "tasks": [
        {"id": "T-001", "title": "Task one", "status": "pending"},
        {"id": "T-002", "title": "Task two", "status": "pending"},
        {"id": "T-003", "title": "Task three", "status": "pending"}
      ],
      "retries": {"attempts": 0, "maxAttempts": 3, "failureLog": []}
    }
  ],
  "execution": {
    "mode": "parallel",
    "maxParallel": 4,
    "currentWave": 1,
    "activeWorktrees": [".ql-wt/US-TEST"]
  }
}
JSONEOF

git add quantum.json
git commit -m "add quantum.json" >/dev/null 2>&1

TOTAL=$((TOTAL + 1))
if [[ -f "$TEST_TMPDIR/quantum.json" ]]; then
  echo "  PASS: quantum.json created"
  PASS=$((PASS + 1))
else
  echo "  FAIL: quantum.json not created"
  FAIL=$((FAIL + 1))
fi

# =========================================================================
echo ""
echo "--- Step 2: Create worktree at .ql-wt/US-TEST ---"

WT_PATH="$TEST_TMPDIR/.ql-wt/US-TEST"
git worktree add "$WT_PATH" -b ql-wt/US-TEST HEAD >/dev/null 2>&1
WT_EXIT=$?

assert_eq "worktree created successfully" "0" "$WT_EXIT"

TOTAL=$((TOTAL + 1))
if [[ -d "$WT_PATH" ]]; then
  echo "  PASS: worktree directory exists"
  PASS=$((PASS + 1))
else
  echo "  FAIL: worktree directory not found"
  FAIL=$((FAIL + 1))
fi

# =========================================================================
echo ""
echo "--- Step 3: Create 3 WIP commits in the worktree ---"

# Configure git user in worktree
git -C "$WT_PATH" config user.email "test@test.com"
git -C "$WT_PATH" config user.name "Test"

# WIP commit 1: T-001
echo "task one work" > "$WT_PATH/task1.txt"
git -C "$WT_PATH" add -A >/dev/null 2>&1
git -C "$WT_PATH" commit -m "wip: US-TEST T-001 - Task one" -q >/dev/null 2>&1

# WIP commit 2: T-002
echo "task two work" > "$WT_PATH/task2.txt"
git -C "$WT_PATH" add -A >/dev/null 2>&1
git -C "$WT_PATH" commit -m "wip: US-TEST T-002 - Task two" -q >/dev/null 2>&1

# WIP commit 3: T-003
echo "task three work" > "$WT_PATH/task3.txt"
git -C "$WT_PATH" add -A >/dev/null 2>&1
git -C "$WT_PATH" commit -m "wip: US-TEST T-003 - Task three" -q >/dev/null 2>&1

# Verify commit count in worktree
WIP_COUNT=$(git -C "$WT_PATH" log --oneline --format=%s | grep "^wip: US-TEST T-" | wc -l | tr -d ' ')
assert_eq "3 WIP commits created" "3" "$WIP_COUNT"

# =========================================================================
echo ""
echo "--- Step 4: detect_resumable_work returns resumable with correct tasks ---"

DETECT_OUTPUT=$(detect_resumable_work "$TEST_TMPDIR/quantum.json" "$TEST_TMPDIR" "US-TEST" 2>/dev/null)
DETECT_EXIT=$?

assert_eq "detect_resumable_work exits 0" "0" "$DETECT_EXIT"
assert_starts_with "output starts with resumable:" "resumable:" "$DETECT_OUTPUT"

# Parse the output: resumable:<sha>:<comma-tasks>
# Extract the tasks portion (everything after the second colon)
# Note: get_completed_tasks returns tasks in git log order (most recent first),
# so the order may be T-003,T-002,T-001. We sort both sides for comparison.
DETECT_TASKS=$(echo "$DETECT_OUTPUT" | sed 's/^resumable:[^:]*://')
SORTED_ACTUAL=$(echo "$DETECT_TASKS" | tr ',' '\n' | sort | tr '\n' ',' | sed 's/,$//')
SORTED_EXPECTED="T-001,T-002,T-003"
assert_eq "detected tasks contain T-001,T-002,T-003" "$SORTED_EXPECTED" "$SORTED_ACTUAL"

# Extract the SHA portion (between first and second colon)
DETECT_SHA=$(echo "$DETECT_OUTPUT" | sed 's/^resumable:\([^:]*\):.*/\1/')
TOTAL=$((TOTAL + 1))
if [[ ${#DETECT_SHA} -ge 40 ]]; then
  echo "  PASS: SHA is a valid full hash (${#DETECT_SHA} chars)"
  PASS=$((PASS + 1))
else
  echo "  FAIL: SHA is too short (${#DETECT_SHA} chars): $DETECT_SHA"
  FAIL=$((FAIL + 1))
fi

# =========================================================================
echo ""
echo "--- Step 5: build_agent_prompt includes 'Previously completed tasks' ---"

PROMPT_OUTPUT=$(build_agent_prompt "US-TEST" "T-001,T-002,T-003")
PROMPT_EXIT=$?

assert_eq "build_agent_prompt exits 0" "0" "$PROMPT_EXIT"
assert_contains "prompt includes 'Previously completed tasks'" "Previously completed tasks" "$PROMPT_OUTPUT"
assert_contains "prompt includes task list" "T-001,T-002,T-003" "$PROMPT_OUTPUT"
assert_contains "prompt includes story ID" "US-TEST" "$PROMPT_OUTPUT"

# =========================================================================
echo ""
echo "--- Step 6: Verify worktree WIP commits are intact ---"

# The WIP commits should still be in the worktree log
INTACT_COUNT=$(git -C "$WT_PATH" log --oneline --format=%s | grep "^wip: US-TEST T-" | wc -l | tr -d ' ')
assert_eq "WIP commits still intact after detect" "3" "$INTACT_COUNT"

# Verify the files from WIP commits are present
TOTAL=$((TOTAL + 1))
if [[ -f "$WT_PATH/task1.txt" && -f "$WT_PATH/task2.txt" && -f "$WT_PATH/task3.txt" ]]; then
  echo "  PASS: all task files present in worktree"
  PASS=$((PASS + 1))
else
  echo "  FAIL: some task files missing from worktree"
  FAIL=$((FAIL + 1))
fi

# Verify git log order (T-003 should be most recent, T-001 earliest)
FIRST_WIP=$(git -C "$WT_PATH" log --oneline --format=%s | grep "^wip: US-TEST T-" | head -1)
assert_eq "most recent WIP is T-003" "wip: US-TEST T-003 - Task three" "$FIRST_WIP"

LAST_WIP=$(git -C "$WT_PATH" log --oneline --format=%s | grep "^wip: US-TEST T-" | tail -1)
assert_eq "oldest WIP is T-001" "wip: US-TEST T-001 - Task one" "$LAST_WIP"

# =========================================================================
echo ""
echo "--- Step 7: Clean up ---"
# Cleanup is handled by the EXIT trap

# =========================================================================
echo ""
echo "=== Results: $PASS/$TOTAL passed, $FAIL failed ==="
if [[ $FAIL -eq 0 ]]; then
  exit 0
else
  exit 1
fi
