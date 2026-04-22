#!/usr/bin/env bash
# tests/integration/test_init_to_merge.sh
# Integration test for the full init-to-merge flow:
#   1. Create a temp git repo with quantum.json
#   2. Source lib/init-guard.sh and lib/resilience.sh
#   3. Run run_preflight() -- verify execution.initGuard populated (ranAt, warnings)
#   4. Create a worktree branch (ql-wt/US-INTEG)
#   5. In the worktree, create 3 files with 3 WIP commits + 1 feat commit
#   6. Back on main, call squash_and_merge() -- verify 1 squashed commit, all 3 files present
#   7. Clean up

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="$SCRIPT_DIR/../../lib"
PASS=0
FAIL=0
TOTAL=0

# Source common.sh and json-atomic.sh first (required by init-guard.sh, resilience.sh)
if [[ ! -f "$LIB_DIR/common.sh" ]]; then
  echo "SKIP: lib/common.sh not found"
  exit 1
fi

if [[ ! -f "$LIB_DIR/json-atomic.sh" ]]; then
  echo "SKIP: lib/json-atomic.sh not found"
  exit 1
fi

# Source init-guard.sh (provides run_preflight)
if [[ ! -f "$LIB_DIR/init-guard.sh" ]]; then
  echo "SKIP: lib/init-guard.sh not found (dependency not yet merged)"
  exit 1
fi
source "$LIB_DIR/init-guard.sh"

# Source resilience.sh (provides squash_and_merge, wip_commit)
if [[ ! -f "$LIB_DIR/resilience.sh" ]]; then
  echo "SKIP: lib/resilience.sh not found (dependency not yet merged)"
  exit 1
fi
source "$LIB_DIR/resilience.sh"

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

assert_file_exists() {
  local test_name="$1" file_path="$2"
  TOTAL=$((TOTAL + 1))
  if [[ -f "$file_path" ]]; then
    echo "  PASS: $test_name"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: $test_name (file not found: $file_path)"
    FAIL=$((FAIL + 1))
  fi
}

# Helper: read a JSON value via Python (handles Windows path translation)
_read_json_py() {
  local json_file="$1"
  local py_expr="$2"
  local py_path
  py_path=$(_to_native_path "$json_file")
  python -c "
import json, sys
d = json.load(open(sys.argv[1]))
$py_expr
" "$py_path"
}

# =========================================================================
# Setup: create a temporary git repo
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

echo "=== Integration Test: Init to Merge Flow ==="
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

# Create quantum.json with a story
JSON_PATH="$TEST_TMPDIR/quantum.json"
PY_JSON_PATH=$(_to_native_path "$JSON_PATH")

python -c "
import json, sys
d = {
  'project': 'test-init-to-merge',
  'stories': [
    {
      'id': 'US-INTEG',
      'title': 'Integration test story',
      'status': 'in_progress',
      'tasks': [
        {'id': 'T-001', 'title': 'First task', 'status': 'pending'},
        {'id': 'T-002', 'title': 'Second task', 'status': 'pending'},
        {'id': 'T-003', 'title': 'Third task', 'status': 'pending'}
      ],
      'retries': {'attempts': 0, 'maxAttempts': 3, 'failureLog': []}
    }
  ],
  'execution': {}
}
with open(sys.argv[1], 'w') as f:
  json.dump(d, f, indent=2)
" "$PY_JSON_PATH"

git add quantum.json
git commit -m "add quantum.json" >/dev/null 2>&1

assert_file_exists "quantum.json created" "$JSON_PATH"

# =========================================================================
echo ""
echo "--- Step 2: Run run_preflight and verify initGuard populated ---"

run_preflight "$TEST_TMPDIR" "$JSON_PATH" 2>/dev/null
PREFLIGHT_EXIT=$?
assert_eq "run_preflight exits 0" "0" "$PREFLIGHT_EXIT"

# Verify execution.initGuard.ranAt exists
RAN_AT=$(_read_json_py "$JSON_PATH" "
ig = d.get('execution', {}).get('initGuard', {})
print(ig.get('ranAt', ''))
")

TOTAL=$((TOTAL + 1))
if [[ -n "$RAN_AT" ]]; then
  echo "  PASS: initGuard.ranAt is populated ($RAN_AT)"
  PASS=$((PASS + 1))
else
  echo "  FAIL: initGuard.ranAt is empty"
  FAIL=$((FAIL + 1))
fi

# Verify execution.initGuard.warnings array exists (may be empty or contain entries)
WARNINGS_TYPE=$(_read_json_py "$JSON_PATH" "
ig = d.get('execution', {}).get('initGuard', {})
w = ig.get('warnings')
print(type(w).__name__)
")

assert_eq "initGuard.warnings is a list" "list" "$WARNINGS_TYPE"

# =========================================================================
echo ""
echo "--- Step 3: Create worktree branch ql-wt/US-INTEG ---"

# Commit any quantum.json changes from preflight before creating worktree
git -C "$TEST_TMPDIR" add -A >/dev/null 2>&1
git -C "$TEST_TMPDIR" commit -m "post-preflight quantum.json update" -q >/dev/null 2>&1 || true

WT_PATH="$TEST_TMPDIR/.ql-wt/US-INTEG"
mkdir -p "$TEST_TMPDIR/.ql-wt"
git -C "$TEST_TMPDIR" worktree add "$WT_PATH" -b ql-wt/US-INTEG HEAD >/dev/null 2>&1
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

# Configure git user in worktree
git -C "$WT_PATH" config user.email "test@test.com"
git -C "$WT_PATH" config user.name "Test"

# =========================================================================
echo ""
echo "--- Step 4: Create 3 WIP commits in the worktree ---"

# WIP commit 1: T-001
echo "first task output" > "$WT_PATH/task1.txt"
git -C "$WT_PATH" add -A >/dev/null 2>&1
git -C "$WT_PATH" commit -m "wip: US-INTEG T-001 - First task" -q >/dev/null 2>&1

# WIP commit 2: T-002
echo "second task output" > "$WT_PATH/task2.txt"
git -C "$WT_PATH" add -A >/dev/null 2>&1
git -C "$WT_PATH" commit -m "wip: US-INTEG T-002 - Second task" -q >/dev/null 2>&1

# WIP commit 3: T-003
echo "third task output" > "$WT_PATH/task3.txt"
git -C "$WT_PATH" add -A >/dev/null 2>&1
git -C "$WT_PATH" commit -m "wip: US-INTEG T-003 - Third task" -q >/dev/null 2>&1

# Verify WIP commit count
WIP_COUNT=$(git -C "$WT_PATH" log --oneline --format=%s | grep "^wip: US-INTEG T-" | wc -l | tr -d ' ')
assert_eq "3 WIP commits created" "3" "$WIP_COUNT"

# =========================================================================
echo ""
echo "--- Step 5: Add feat commit on top ---"

git -C "$WT_PATH" commit --allow-empty -m "feat: US-INTEG - Integration test story" -q >/dev/null 2>&1

# Verify total commit count on the worktree branch (relative to main)
BRANCH_COMMIT_COUNT=$(git -C "$TEST_TMPDIR" rev-list --count main..ql-wt/US-INTEG 2>/dev/null)
assert_eq "worktree branch has 4 commits ahead of main" "4" "$BRANCH_COMMIT_COUNT"

# =========================================================================
echo ""
echo "--- Step 6: squash_and_merge on main ---"

# Ensure we are on main in the main repo
cd "$TEST_TMPDIR"
git checkout main >/dev/null 2>&1

# Count commits on main before merge
COMMITS_BEFORE=$(git -C "$TEST_TMPDIR" rev-list --count HEAD)

# Call squash_and_merge
squash_and_merge "ql-wt/US-INTEG" "$TEST_TMPDIR" "US-INTEG" "Integration test story" "$JSON_PATH" 2>/dev/null
MERGE_EXIT=$?

assert_eq "squash_and_merge exits 0" "0" "$MERGE_EXIT"

# Count commits on main after merge
COMMITS_AFTER=$(git -C "$TEST_TMPDIR" rev-list --count HEAD)

# Should have exactly 1 new commit (the squash commit)
NEW_COMMITS=$((COMMITS_AFTER - COMMITS_BEFORE))
assert_eq "exactly 1 new commit on main after squash merge" "1" "$NEW_COMMITS"

# =========================================================================
echo ""
echo "--- Step 7: Verify squashed commit message ---"

SQUASH_MSG=$(git -C "$TEST_TMPDIR" log -1 --format=%s)
assert_eq "squash commit message is correct" "feat: US-INTEG - Integration test story" "$SQUASH_MSG"

# =========================================================================
echo ""
echo "--- Step 8: Verify all 3 task files present on main ---"

assert_file_exists "task1.txt present on main" "$TEST_TMPDIR/task1.txt"
assert_file_exists "task2.txt present on main" "$TEST_TMPDIR/task2.txt"
assert_file_exists "task3.txt present on main" "$TEST_TMPDIR/task3.txt"

# Verify file contents are correct
TASK1_CONTENT=$(cat "$TEST_TMPDIR/task1.txt")
assert_eq "task1.txt has correct content" "first task output" "$TASK1_CONTENT"

TASK2_CONTENT=$(cat "$TEST_TMPDIR/task2.txt")
assert_eq "task2.txt has correct content" "second task output" "$TASK2_CONTENT"

TASK3_CONTENT=$(cat "$TEST_TMPDIR/task3.txt")
assert_eq "task3.txt has correct content" "third task output" "$TASK3_CONTENT"

# =========================================================================
echo ""
echo "--- Step 9: Verify no WIP commits leaked onto main ---"

WIP_ON_MAIN=$(git -C "$TEST_TMPDIR" log --oneline --format=%s | grep "^wip:" | wc -l | tr -d ' ')
assert_eq "no WIP commits on main history" "0" "$WIP_ON_MAIN"

# =========================================================================
echo ""
echo "--- Step 10: Remove worktree and verify working tree is clean ---"

# Remove the worktree (simulating normal orchestrator cleanup after merge)
git -C "$TEST_TMPDIR" worktree remove --force "$WT_PATH" 2>/dev/null || rm -rf "$WT_PATH"
rmdir "$TEST_TMPDIR/.ql-wt" 2>/dev/null || true

GIT_STATUS=$(git -C "$TEST_TMPDIR" status --porcelain)
assert_eq "working tree clean after merge and cleanup" "" "$GIT_STATUS"

# =========================================================================
echo ""
echo "--- Cleanup ---"
# Cleanup is handled by the EXIT trap

# =========================================================================
echo ""
echo "=== Results: $PASS/$TOTAL passed, $FAIL failed ==="
if [[ $FAIL -eq 0 ]]; then
  exit 0
else
  exit 1
fi
