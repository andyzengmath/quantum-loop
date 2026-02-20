#!/usr/bin/env bash
# Test suite for lib/crash-recovery.sh
# Tests orphaned worktree detection and cleanup

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="$SCRIPT_DIR/../lib"
PASS=0
FAIL=0
TOTAL=0

# Source dependencies
source "$LIB_DIR/common.sh"
source "$LIB_DIR/json-atomic.sh"

# Source the library under test
if [[ ! -f "$LIB_DIR/crash-recovery.sh" ]]; then
  echo "SKIP: lib/crash-recovery.sh not found (RED phase)"
  exit 1
fi
source "$LIB_DIR/crash-recovery.sh"

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

# Helper: create a test git repo with quantum.json that has orphaned worktrees
setup_test_repo() {
  local test_dir
  test_dir=$(mktemp -d)

  # Initialize a git repo
  git -C "$test_dir" init -q
  git -C "$test_dir" commit --allow-empty -m "init" -q

  echo "$test_dir"
}

# =========================================================================
echo "=== Test 1: Recover orphaned worktrees removes directories ==="
TEST_REPO=$(setup_test_repo)
WT_DIR="$TEST_REPO/.ql-wt"
mkdir -p "$WT_DIR/US-001" "$WT_DIR/US-002"

# Create quantum.json with in_progress stories and activeWorktrees
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

# Verify worktree directories removed
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

# =========================================================================
echo "=== Test 2: Story statuses reset from in_progress to pending ==="
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

# Check story status was reset
US001_STATUS=$(jq -r '.stories[] | select(.id == "US-001") | .status' "$TEST_REPO/quantum.json")
US002_STATUS=$(jq -r '.stories[] | select(.id == "US-002") | .status' "$TEST_REPO/quantum.json")
US003_STATUS=$(jq -r '.stories[] | select(.id == "US-003") | .status' "$TEST_REPO/quantum.json")

assert_eq "US-001 reset to pending" "pending" "$US001_STATUS"
assert_eq "US-002 still passed" "passed" "$US002_STATUS"
assert_eq "US-003 still pending" "pending" "$US003_STATUS"

rm -rf "$TEST_REPO"

# =========================================================================
echo "=== Test 3: activeWorktrees array is cleared ==="
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

# =========================================================================
echo "=== Test 4: Worktree field cleared from recovered stories ==="
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

# =========================================================================
echo "=== Test 5: Warning message includes count ==="
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
assert_contains "Warning includes count" "2" "$OUTPUT"
assert_contains "Warning mentions orphaned" "orphaned" "$OUTPUT"

rm -rf "$TEST_REPO"

# =========================================================================
echo "=== Test 6: No-op when no activeWorktrees ==="
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
assert_eq "No-op exits 0" "0" "$EXIT_CODE"

rm -rf "$TEST_REPO"

# =========================================================================
echo "=== Test 7: No-op when no execution field (backward compat) ==="
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
assert_eq "No execution field exits 0" "0" "$EXIT_CODE"

rm -rf "$TEST_REPO"

# =========================================================================
echo "=== Test 8: Input validation ==="
RESULT=$(recover_orphaned_worktrees "" "/tmp" 2>&1)
EXIT_CODE=$?
assert_eq "Empty json_path returns error" "1" "$EXIT_CODE"

RESULT=$(recover_orphaned_worktrees "/tmp/q.json" "" 2>&1)
EXIT_CODE=$?
assert_eq "Empty repo_root returns error" "1" "$EXIT_CODE"

# =========================================================================
echo "=== Test 9: Handles worktree dirs that already disappeared ==="
TEST_REPO=$(setup_test_repo)
# Don't create the actual directories -- they "already disappeared"

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
assert_eq "Missing dir still exits 0" "0" "$EXIT_CODE"

# Story should still be reset to pending
US001_STATUS=$(jq -r '.stories[] | select(.id == "US-001") | .status' "$TEST_REPO/quantum.json")
assert_eq "US-001 reset even if dir missing" "pending" "$US001_STATUS"

rm -rf "$TEST_REPO"

# =========================================================================
echo ""
echo "=== Results: $PASS/$TOTAL passed, $FAIL failed ==="
if [[ $FAIL -eq 0 ]]; then
  exit 0
else
  exit 1
fi
