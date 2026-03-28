#!/usr/bin/env bash
# Test suite for lib/resilience.sh
# Tests WIP commits, squash-on-merge, crash recovery, and resume detection

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="$SCRIPT_DIR/../lib"
PASS=0
FAIL=0
TOTAL=0

# Source dependencies
source "$LIB_DIR/common.sh"
source "$LIB_DIR/json-atomic.sh"

# Source the library under test
if [[ ! -f "$LIB_DIR/resilience.sh" ]]; then
  echo "SKIP: lib/resilience.sh not found (RED phase)"
  exit 1
fi
source "$LIB_DIR/resilience.sh"

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
# wip_commit tests
# =========================================================================
echo "=== wip_commit tests ==="

echo "--- Test: wip_commit with changed files creates commit ---"
TEST_REPO=$(setup_test_repo)
echo "hello" > "$TEST_REPO/file.txt"
git -C "$TEST_REPO" add -A
git -C "$TEST_REPO" commit -m "init file" -q

echo "changed" > "$TEST_REPO/file.txt"
START_TIME=$(date +%s)
END_TIME=$((START_TIME + 10))

OUTPUT=$(wip_commit "$TEST_REPO" "US-001" "T-001" "My task title" "$START_TIME" "$END_TIME" 2>&1)
EXIT_CODE=$?
assert_eq "wip_commit with changes exits 0" "0" "$EXIT_CODE"

# Verify commit was made
LAST_MSG=$(git -C "$TEST_REPO" log -1 --format=%s)
assert_eq "commit message format" "wip: US-001 T-001 - My task title" "$LAST_MSG"

# Verify working directory is clean
STATUS=$(git -C "$TEST_REPO" status --porcelain)
assert_eq "working directory is clean after commit" "" "$STATUS"

rm -rf "$TEST_REPO"

echo "--- Test: wip_commit with no changes and short duration returns 1 ---"
TEST_REPO=$(setup_test_repo)
echo "hello" > "$TEST_REPO/file.txt"
git -C "$TEST_REPO" add -A
git -C "$TEST_REPO" commit -m "init file" -q

START_TIME=$(date +%s)
END_TIME=$((START_TIME + 60))

OUTPUT=$(wip_commit "$TEST_REPO" "US-001" "T-001" "Short task" "$START_TIME" "$END_TIME" 2>&1)
EXIT_CODE=$?
assert_eq "wip_commit no changes short duration returns 1" "1" "$EXIT_CODE"

rm -rf "$TEST_REPO"

echo "--- Test: wip_commit with no changes but long duration creates empty commit ---"
TEST_REPO=$(setup_test_repo)
echo "hello" > "$TEST_REPO/file.txt"
git -C "$TEST_REPO" add -A
git -C "$TEST_REPO" commit -m "init file" -q

START_TIME=$(date +%s)
END_TIME=$((START_TIME + 130))

COMMIT_COUNT_BEFORE=$(git -C "$TEST_REPO" rev-list --count HEAD)
OUTPUT=$(wip_commit "$TEST_REPO" "US-001" "T-002" "Long task" "$START_TIME" "$END_TIME" 2>&1)
EXIT_CODE=$?
assert_eq "wip_commit no changes long duration exits 0" "0" "$EXIT_CODE"

COMMIT_COUNT_AFTER=$(git -C "$TEST_REPO" rev-list --count HEAD)
assert_eq "empty commit created" "$((COMMIT_COUNT_BEFORE + 1))" "$COMMIT_COUNT_AFTER"

LAST_MSG=$(git -C "$TEST_REPO" log -1 --format=%s)
assert_eq "empty commit message format" "wip: US-001 T-002 - Long task" "$LAST_MSG"

rm -rf "$TEST_REPO"

echo "--- Test: wip_commit logs RESILIENCE prefix ---"
TEST_REPO=$(setup_test_repo)
echo "hello" > "$TEST_REPO/file.txt"
git -C "$TEST_REPO" add -A
git -C "$TEST_REPO" commit -m "init file" -q

echo "changed" > "$TEST_REPO/file.txt"
START_TIME=$(date +%s)
END_TIME=$((START_TIME + 10))

OUTPUT=$(wip_commit "$TEST_REPO" "US-001" "T-001" "Task" "$START_TIME" "$END_TIME" 2>&1)
assert_contains "logs RESILIENCE prefix" "RESILIENCE" "$OUTPUT"

rm -rf "$TEST_REPO"

# =========================================================================
# get_completed_tasks tests
# =========================================================================
echo "=== get_completed_tasks tests ==="

echo "--- Test: returns task IDs from WIP commits ---"
TEST_REPO=$(setup_test_repo)
echo "a" > "$TEST_REPO/file1.txt"
git -C "$TEST_REPO" add -A && git -C "$TEST_REPO" commit -m "wip: US-001 T-001 - First task" -q
echo "b" > "$TEST_REPO/file2.txt"
git -C "$TEST_REPO" add -A && git -C "$TEST_REPO" commit -m "wip: US-001 T-002 - Second task" -q

RESULT=$(get_completed_tasks "$TEST_REPO" "US-001")
assert_contains "contains T-001" "T-001" "$RESULT"
assert_contains "contains T-002" "T-002" "$RESULT"

rm -rf "$TEST_REPO"

echo "--- Test: returns empty for no WIP commits ---"
TEST_REPO=$(setup_test_repo)
echo "a" > "$TEST_REPO/file1.txt"
git -C "$TEST_REPO" add -A && git -C "$TEST_REPO" commit -m "feat: unrelated commit" -q

RESULT=$(get_completed_tasks "$TEST_REPO" "US-001")
assert_eq "no tasks found returns empty" "" "$RESULT"

rm -rf "$TEST_REPO"

echo "--- Test: only returns tasks for specified story_id ---"
TEST_REPO=$(setup_test_repo)
git -C "$TEST_REPO" commit --allow-empty -m "wip: US-001 T-001 - Story 1 task" -q
git -C "$TEST_REPO" commit --allow-empty -m "wip: US-002 T-001 - Story 2 task" -q
git -C "$TEST_REPO" commit --allow-empty -m "wip: US-001 T-002 - Story 1 task 2" -q

RESULT=$(get_completed_tasks "$TEST_REPO" "US-001")
assert_contains "contains T-001" "T-001" "$RESULT"
assert_contains "contains T-002" "T-002" "$RESULT"
assert_not_contains "does not contain US-002 tasks in output" "US-002" "$RESULT"

rm -rf "$TEST_REPO"

echo "--- Test: returns unique task IDs ---"
TEST_REPO=$(setup_test_repo)
git -C "$TEST_REPO" commit --allow-empty -m "wip: US-001 T-001 - First attempt" -q
git -C "$TEST_REPO" commit --allow-empty -m "wip: US-001 T-001 - Retry" -q

RESULT=$(get_completed_tasks "$TEST_REPO" "US-001")
# Count lines containing T-001
COUNT=$(echo "$RESULT" | grep -c "T-001" || true)
assert_eq "T-001 appears only once" "1" "$COUNT"

rm -rf "$TEST_REPO"

# =========================================================================
# squash_and_merge tests
# =========================================================================
echo "=== squash_and_merge tests ==="

echo "--- Test: single commit uses --no-ff merge ---"
TEST_REPO=$(setup_test_repo)
# Create a minimal quantum.json
cat > "$TEST_REPO/quantum.json" <<'JSONEOF'
{"stories": [{"id": "US-001", "status": "in_progress"}]}
JSONEOF
git -C "$TEST_REPO" add -A && git -C "$TEST_REPO" commit -m "add quantum.json" -q

# Create a branch with one commit
git -C "$TEST_REPO" checkout -b "ql-wt/US-001" -q
echo "feature" > "$TEST_REPO/feature.txt"
git -C "$TEST_REPO" add -A && git -C "$TEST_REPO" commit -m "wip: US-001 T-001 - Task one" -q
git -C "$TEST_REPO" checkout master -q 2>/dev/null || git -C "$TEST_REPO" checkout main -q

OUTPUT=$(squash_and_merge "ql-wt/US-001" "$TEST_REPO" "US-001" "My Story" "$TEST_REPO/quantum.json" 2>&1)
EXIT_CODE=$?
assert_eq "single commit squash_and_merge exits 0" "0" "$EXIT_CODE"

# Verify the file arrived on main
if [[ -f "$TEST_REPO/feature.txt" ]]; then
  TOTAL=$((TOTAL + 1)); echo "  PASS: feature.txt exists on main"; PASS=$((PASS + 1))
else
  TOTAL=$((TOTAL + 1)); echo "  FAIL: feature.txt not found on main"; FAIL=$((FAIL + 1))
fi

rm -rf "$TEST_REPO"

echo "--- Test: multiple commits uses squash merge ---"
TEST_REPO=$(setup_test_repo)
cat > "$TEST_REPO/quantum.json" <<'JSONEOF'
{"stories": [{"id": "US-002", "status": "in_progress"}]}
JSONEOF
git -C "$TEST_REPO" add -A && git -C "$TEST_REPO" commit -m "add quantum.json" -q

# Create a branch with multiple commits
MAIN_BRANCH=$(git -C "$TEST_REPO" branch --show-current)
git -C "$TEST_REPO" checkout -b "ql-wt/US-002" -q
echo "file1" > "$TEST_REPO/f1.txt"
git -C "$TEST_REPO" add -A && git -C "$TEST_REPO" commit -m "wip: US-002 T-001 - Task one" -q
echo "file2" > "$TEST_REPO/f2.txt"
git -C "$TEST_REPO" add -A && git -C "$TEST_REPO" commit -m "wip: US-002 T-002 - Task two" -q
echo "file3" > "$TEST_REPO/f3.txt"
git -C "$TEST_REPO" add -A && git -C "$TEST_REPO" commit -m "feat: US-002 - Final" -q
git -C "$TEST_REPO" checkout "$MAIN_BRANCH" -q

OUTPUT=$(squash_and_merge "ql-wt/US-002" "$TEST_REPO" "US-002" "Multi Task Story" "$TEST_REPO/quantum.json" 2>&1)
EXIT_CODE=$?
assert_eq "multi commit squash_and_merge exits 0" "0" "$EXIT_CODE"

# Verify files arrived
if [[ -f "$TEST_REPO/f1.txt" && -f "$TEST_REPO/f2.txt" && -f "$TEST_REPO/f3.txt" ]]; then
  TOTAL=$((TOTAL + 1)); echo "  PASS: all files exist on main"; PASS=$((PASS + 1))
else
  TOTAL=$((TOTAL + 1)); echo "  FAIL: not all files on main"; FAIL=$((FAIL + 1))
fi

# Verify squash commit message
LAST_MSG=$(git -C "$TEST_REPO" log -1 --format=%s)
assert_eq "squash commit message" "feat: US-002 - Multi Task Story" "$LAST_MSG"

rm -rf "$TEST_REPO"

echo "--- Test: squash_and_merge logs RESILIENCE ---"
TEST_REPO=$(setup_test_repo)
cat > "$TEST_REPO/quantum.json" <<'JSONEOF'
{"stories": [{"id": "US-003", "status": "in_progress"}]}
JSONEOF
git -C "$TEST_REPO" add -A && git -C "$TEST_REPO" commit -m "add quantum.json" -q

git -C "$TEST_REPO" checkout -b "ql-wt/US-003" -q
echo "x" > "$TEST_REPO/x.txt"
git -C "$TEST_REPO" add -A && git -C "$TEST_REPO" commit -m "wip: US-003 T-001 - X" -q
git -C "$TEST_REPO" checkout master -q 2>/dev/null || git -C "$TEST_REPO" checkout main -q

OUTPUT=$(squash_and_merge "ql-wt/US-003" "$TEST_REPO" "US-003" "Story Three" "$TEST_REPO/quantum.json" 2>&1)
assert_contains "logs RESILIENCE prefix" "RESILIENCE" "$OUTPUT"

rm -rf "$TEST_REPO"

# =========================================================================
# recover_orphaned_worktrees tests
# =========================================================================
echo "=== recover_orphaned_worktrees tests ==="

echo "--- Test: removes orphaned worktree directories ---"
TEST_REPO=$(setup_test_repo)
WT_DIR="$TEST_REPO/.ql-wt"
mkdir -p "$WT_DIR/US-001" "$WT_DIR/US-002"

cat > "$TEST_REPO/quantum.json" <<'JSONEOF'
{
  "stories": [
    {"id": "US-001", "status": "in_progress", "worktree": ".ql-wt/US-001"},
    {"id": "US-002", "status": "in_progress", "worktree": ".ql-wt/US-002"},
    {"id": "US-003", "status": "passed"}
  ],
  "execution": {
    "mode": "parallel",
    "maxParallel": 4,
    "currentWave": 1,
    "activeWorktrees": [".ql-wt/US-001", ".ql-wt/US-002"]
  }
}
JSONEOF

OUTPUT=$(recover_orphaned_worktrees "$TEST_REPO/quantum.json" "$TEST_REPO" 2>&1)
EXIT_CODE=$?
assert_eq "recover_orphaned_worktrees exits 0" "0" "$EXIT_CODE"

if [[ ! -d "$WT_DIR/US-001" ]]; then
  TOTAL=$((TOTAL + 1)); echo "  PASS: US-001 worktree dir removed"; PASS=$((PASS + 1))
else
  TOTAL=$((TOTAL + 1)); echo "  FAIL: US-001 worktree dir still exists"; FAIL=$((FAIL + 1))
fi

if [[ ! -d "$WT_DIR/US-002" ]]; then
  TOTAL=$((TOTAL + 1)); echo "  PASS: US-002 worktree dir removed"; PASS=$((PASS + 1))
else
  TOTAL=$((TOTAL + 1)); echo "  FAIL: US-002 worktree dir still exists"; FAIL=$((FAIL + 1))
fi

rm -rf "$TEST_REPO"

echo "--- Test: resets in_progress stories to pending ---"
TEST_REPO=$(setup_test_repo)
WT_DIR="$TEST_REPO/.ql-wt"
mkdir -p "$WT_DIR/US-001"

cat > "$TEST_REPO/quantum.json" <<'JSONEOF'
{
  "stories": [
    {"id": "US-001", "status": "in_progress", "worktree": ".ql-wt/US-001"},
    {"id": "US-002", "status": "passed"},
    {"id": "US-003", "status": "pending"}
  ],
  "execution": {
    "mode": "parallel",
    "maxParallel": 4,
    "currentWave": 1,
    "activeWorktrees": [".ql-wt/US-001"]
  }
}
JSONEOF

recover_orphaned_worktrees "$TEST_REPO/quantum.json" "$TEST_REPO" >/dev/null 2>&1

US001_STATUS=$(jq -r '.stories[] | select(.id == "US-001") | .status' "$TEST_REPO/quantum.json")
US002_STATUS=$(jq -r '.stories[] | select(.id == "US-002") | .status' "$TEST_REPO/quantum.json")
US003_STATUS=$(jq -r '.stories[] | select(.id == "US-003") | .status' "$TEST_REPO/quantum.json")

assert_eq "US-001 reset to pending" "pending" "$US001_STATUS"
assert_eq "US-002 still passed" "passed" "$US002_STATUS"
assert_eq "US-003 still pending" "pending" "$US003_STATUS"

rm -rf "$TEST_REPO"

echo "--- Test: clears activeWorktrees array ---"
TEST_REPO=$(setup_test_repo)
WT_DIR="$TEST_REPO/.ql-wt"
mkdir -p "$WT_DIR/US-001"

cat > "$TEST_REPO/quantum.json" <<'JSONEOF'
{
  "stories": [
    {"id": "US-001", "status": "in_progress", "worktree": ".ql-wt/US-001"}
  ],
  "execution": {
    "mode": "parallel",
    "maxParallel": 4,
    "currentWave": 1,
    "activeWorktrees": [".ql-wt/US-001"]
  }
}
JSONEOF

recover_orphaned_worktrees "$TEST_REPO/quantum.json" "$TEST_REPO" >/dev/null 2>&1

ACTIVE_COUNT=$(jq '.execution.activeWorktrees | length' "$TEST_REPO/quantum.json")
assert_eq "activeWorktrees is empty" "0" "$ACTIVE_COUNT"

rm -rf "$TEST_REPO"

echo "--- Test: removes worktree field from recovered stories ---"
TEST_REPO=$(setup_test_repo)
WT_DIR="$TEST_REPO/.ql-wt"
mkdir -p "$WT_DIR/US-001"

cat > "$TEST_REPO/quantum.json" <<'JSONEOF'
{
  "stories": [
    {"id": "US-001", "status": "in_progress", "worktree": ".ql-wt/US-001"}
  ],
  "execution": {
    "mode": "parallel",
    "maxParallel": 4,
    "currentWave": 1,
    "activeWorktrees": [".ql-wt/US-001"]
  }
}
JSONEOF

recover_orphaned_worktrees "$TEST_REPO/quantum.json" "$TEST_REPO" >/dev/null 2>&1

HAS_WORKTREE=$(jq '.stories[] | select(.id == "US-001") | has("worktree")' "$TEST_REPO/quantum.json")
assert_eq "US-001 worktree field removed" "false" "$HAS_WORKTREE"

rm -rf "$TEST_REPO"

echo "--- Test: backward compat -- no-op when no execution field ---"
TEST_REPO=$(setup_test_repo)

cat > "$TEST_REPO/quantum.json" <<'JSONEOF'
{
  "stories": [
    {"id": "US-001", "status": "pending"}
  ]
}
JSONEOF

OUTPUT=$(recover_orphaned_worktrees "$TEST_REPO/quantum.json" "$TEST_REPO" 2>&1)
EXIT_CODE=$?
assert_eq "no execution field exits 0" "0" "$EXIT_CODE"

rm -rf "$TEST_REPO"

echo "--- Test: no-op when activeWorktrees is empty ---"
TEST_REPO=$(setup_test_repo)

cat > "$TEST_REPO/quantum.json" <<'JSONEOF'
{
  "stories": [
    {"id": "US-001", "status": "passed"}
  ],
  "execution": {
    "mode": "parallel",
    "maxParallel": 4,
    "currentWave": 1,
    "activeWorktrees": []
  }
}
JSONEOF

OUTPUT=$(recover_orphaned_worktrees "$TEST_REPO/quantum.json" "$TEST_REPO" 2>&1)
EXIT_CODE=$?
assert_eq "empty activeWorktrees exits 0" "0" "$EXIT_CODE"

rm -rf "$TEST_REPO"

echo "--- Test: input validation -- missing json_path ---"
RESULT=$(recover_orphaned_worktrees "" "/tmp" 2>&1)
EXIT_CODE=$?
assert_eq "empty json_path returns error" "1" "$EXIT_CODE"

echo "--- Test: input validation -- missing repo_root ---"
RESULT=$(recover_orphaned_worktrees "/tmp/q.json" "" 2>&1)
EXIT_CODE=$?
assert_eq "empty repo_root returns error" "1" "$EXIT_CODE"

echo "--- Test: handles worktree dirs that already disappeared ---"
TEST_REPO=$(setup_test_repo)

cat > "$TEST_REPO/quantum.json" <<'JSONEOF'
{
  "stories": [
    {"id": "US-001", "status": "in_progress", "worktree": ".ql-wt/US-001"}
  ],
  "execution": {
    "mode": "parallel",
    "maxParallel": 4,
    "currentWave": 1,
    "activeWorktrees": [".ql-wt/US-001"]
  }
}
JSONEOF

OUTPUT=$(recover_orphaned_worktrees "$TEST_REPO/quantum.json" "$TEST_REPO" 2>&1)
EXIT_CODE=$?
assert_eq "missing dir still exits 0" "0" "$EXIT_CODE"

US001_STATUS=$(jq -r '.stories[] | select(.id == "US-001") | .status' "$TEST_REPO/quantum.json")
assert_eq "US-001 reset even if dir missing" "pending" "$US001_STATUS"

rm -rf "$TEST_REPO"

echo "--- Test: warning message includes count ---"
TEST_REPO=$(setup_test_repo)
WT_DIR="$TEST_REPO/.ql-wt"
mkdir -p "$WT_DIR/US-001" "$WT_DIR/US-002"

cat > "$TEST_REPO/quantum.json" <<'JSONEOF'
{
  "stories": [
    {"id": "US-001", "status": "in_progress", "worktree": ".ql-wt/US-001"},
    {"id": "US-002", "status": "in_progress", "worktree": ".ql-wt/US-002"}
  ],
  "execution": {
    "mode": "parallel",
    "maxParallel": 4,
    "currentWave": 1,
    "activeWorktrees": [".ql-wt/US-001", ".ql-wt/US-002"]
  }
}
JSONEOF

OUTPUT=$(recover_orphaned_worktrees "$TEST_REPO/quantum.json" "$TEST_REPO" 2>&1)
assert_contains "warning includes count" "2" "$OUTPUT"
assert_contains "warning mentions orphaned" "orphaned" "$OUTPUT"

rm -rf "$TEST_REPO"

# =========================================================================
# detect_resumable_work tests
# =========================================================================
echo "=== detect_resumable_work tests ==="

echo "--- Test: returns fresh when no worktree exists ---"
TEST_REPO=$(setup_test_repo)
cat > "$TEST_REPO/quantum.json" <<'JSONEOF'
{"stories": [{"id": "US-001", "status": "in_progress"}]}
JSONEOF
git -C "$TEST_REPO" add -A && git -C "$TEST_REPO" commit -m "init" -q

RESULT=$(detect_resumable_work "$TEST_REPO/quantum.json" "$TEST_REPO" "US-001" 2>/dev/null)
assert_eq "no worktree returns fresh" "fresh" "$RESULT"

rm -rf "$TEST_REPO"

echo "--- Test: returns fresh when worktree exists but no WIP commits ---"
TEST_REPO=$(setup_test_repo)
cat > "$TEST_REPO/quantum.json" <<'JSONEOF'
{"stories": [{"id": "US-001", "status": "in_progress"}]}
JSONEOF
git -C "$TEST_REPO" add -A && git -C "$TEST_REPO" commit -m "init" -q

# Create worktree directory with a branch but no WIP commits
WT_DIR="$TEST_REPO/.ql-wt/US-001"
mkdir -p "$WT_DIR"
git -C "$TEST_REPO" worktree add "$WT_DIR" -b "ql-wt/US-001" -q 2>/dev/null

RESULT=$(detect_resumable_work "$TEST_REPO/quantum.json" "$TEST_REPO" "US-001" 2>/dev/null)
assert_eq "no WIP commits returns fresh" "fresh" "$RESULT"

git -C "$TEST_REPO" worktree remove "$WT_DIR" --force 2>/dev/null || rm -rf "$WT_DIR"
rm -rf "$TEST_REPO"

echo "--- Test: returns resumable with SHA and tasks when WIP commits exist ---"
TEST_REPO=$(setup_test_repo)
cat > "$TEST_REPO/quantum.json" <<'JSONEOF'
{"stories": [{"id": "US-001", "status": "in_progress"}]}
JSONEOF
git -C "$TEST_REPO" add -A && git -C "$TEST_REPO" commit -m "init" -q

# Create worktree with WIP commits
WT_DIR="$TEST_REPO/.ql-wt/US-001"
mkdir -p "$(dirname "$WT_DIR")"
git -C "$TEST_REPO" worktree add "$WT_DIR" -b "ql-wt/US-001" -q 2>/dev/null

echo "task1" > "$WT_DIR/t1.txt"
git -C "$WT_DIR" add -A && git -C "$WT_DIR" commit -m "wip: US-001 T-001 - First task" -q
echo "task2" > "$WT_DIR/t2.txt"
git -C "$WT_DIR" add -A && git -C "$WT_DIR" commit -m "wip: US-001 T-002 - Second task" -q

RESULT=$(detect_resumable_work "$TEST_REPO/quantum.json" "$TEST_REPO" "US-001" 2>/dev/null)
assert_contains "starts with resumable" "^resumable:" "$RESULT"
assert_contains "contains T-001" "T-001" "$RESULT"
assert_contains "contains T-002" "T-002" "$RESULT"

git -C "$TEST_REPO" worktree remove "$WT_DIR" --force 2>/dev/null || rm -rf "$WT_DIR"
rm -rf "$TEST_REPO"

echo "--- Test: detect_resumable_work logs RESILIENCE ---"
TEST_REPO=$(setup_test_repo)
cat > "$TEST_REPO/quantum.json" <<'JSONEOF'
{"stories": [{"id": "US-001", "status": "in_progress"}]}
JSONEOF
git -C "$TEST_REPO" add -A && git -C "$TEST_REPO" commit -m "init" -q

OUTPUT=$(detect_resumable_work "$TEST_REPO/quantum.json" "$TEST_REPO" "US-001" 2>&1 >/dev/null)
assert_contains "logs RESILIENCE" "RESILIENCE" "$OUTPUT"

rm -rf "$TEST_REPO"

# =========================================================================
echo ""
echo "=== Results: $PASS/$TOTAL passed, $FAIL failed ==="
if [[ $FAIL -eq 0 ]]; then
  exit 0
else
  exit 1
fi
