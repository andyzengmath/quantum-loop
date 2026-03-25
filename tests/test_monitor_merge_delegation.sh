#!/usr/bin/env bash
# Test suite for US-007: merge_worktree_branch() delegation to classify_and_merge()
# Tests that merge_worktree_branch delegates to classify_and_merge when available,
# and falls back to bare git merge when not available.

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
  echo "SKIP: lib/monitor.sh not found"
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

# Helper: create a test git repo with quantum.json
setup_test_repo_with_quantum() {
  local test_dir
  test_dir=$(mktemp -d)
  git -C "$test_dir" init -q
  git -C "$test_dir" commit --allow-empty -m "init" -q

  # Create a minimal quantum.json with mergeStrategy
  cat > "$test_dir/quantum.json" <<'QJSON'
{
  "project": "test",
  "execution": {
    "mergeStrategy": {
      "rules": [],
      "defaultAction": "escalate"
    }
  },
  "progress": []
}
QJSON
  git -C "$test_dir" add quantum.json
  git -C "$test_dir" commit -m "add quantum.json" -q

  echo "$test_dir"
}

# Helper: create a test git repo without quantum.json
setup_test_repo_without_quantum() {
  local test_dir
  test_dir=$(mktemp -d)
  git -C "$test_dir" init -q
  git -C "$test_dir" commit --allow-empty -m "init" -q
  echo "$test_dir"
}

# =========================================================================
echo "=== Test D1: Delegation on clean merge (merge-strategy available + quantum.json exists) ==="
# When merge-strategy is available and quantum.json exists, merge_worktree_branch
# should delegate to classify_and_merge and return 0 on clean merge.
MERGE_STRATEGY_AVAILABLE=true
TEST_REPO=$(setup_test_repo_with_quantum)
FEATURE_BRANCH="feature-delegation-test"
git -C "$TEST_REPO" checkout -b "$FEATURE_BRANCH" -q

# Create a worktree branch with a non-conflicting commit
git -C "$TEST_REPO" checkout -b "ql-wt/US-D1" -q
printf "delegation test content\n" > "$TEST_REPO/delegation.txt"
git -C "$TEST_REPO" add delegation.txt
git -C "$TEST_REPO" commit -m "worktree delegation commit" -q

git -C "$TEST_REPO" checkout "$FEATURE_BRANCH" -q

OUTPUT=$(merge_worktree_branch "$TEST_REPO" "ql-wt/US-D1" 2>&1)
EXIT_CODE=$?
assert_eq "Delegation clean merge returns 0" "0" "$EXIT_CODE"

# Verify the file was merged
if [[ -f "$TEST_REPO/delegation.txt" ]]; then
  TOTAL=$((TOTAL + 1)); echo "  PASS: Delegated merge brought file"; PASS=$((PASS + 1))
else
  TOTAL=$((TOTAL + 1)); echo "  FAIL: Delegated merge did not bring file"; FAIL=$((FAIL + 1))
fi
rm -rf "$TEST_REPO"

# =========================================================================
echo "=== Test D2: Fallback when MERGE_STRATEGY_AVAILABLE=false ==="
# When merge-strategy is not available, should fall back to bare git merge.
MERGE_STRATEGY_AVAILABLE=false
TEST_REPO=$(setup_test_repo_without_quantum)
FEATURE_BRANCH="feature-fallback-test"
git -C "$TEST_REPO" checkout -b "$FEATURE_BRANCH" -q

git -C "$TEST_REPO" checkout -b "ql-wt/US-D2" -q
printf "fallback content\n" > "$TEST_REPO/fallback.txt"
git -C "$TEST_REPO" add fallback.txt
git -C "$TEST_REPO" commit -m "worktree fallback commit" -q

git -C "$TEST_REPO" checkout "$FEATURE_BRANCH" -q

OUTPUT=$(merge_worktree_branch "$TEST_REPO" "ql-wt/US-D2" 2>&1)
EXIT_CODE=$?
assert_eq "Fallback merge returns 0" "0" "$EXIT_CODE"

if [[ -f "$TEST_REPO/fallback.txt" ]]; then
  TOTAL=$((TOTAL + 1)); echo "  PASS: Fallback merge brought file"; PASS=$((PASS + 1))
else
  TOTAL=$((TOTAL + 1)); echo "  FAIL: Fallback merge did not bring file"; FAIL=$((FAIL + 1))
fi
rm -rf "$TEST_REPO"

# =========================================================================
echo "=== Test D3: Fallback when quantum.json does not exist ==="
# Even if MERGE_STRATEGY_AVAILABLE=true, if quantum.json doesn't exist at repo_root,
# should fall back to bare git merge.
MERGE_STRATEGY_AVAILABLE=true
TEST_REPO=$(setup_test_repo_without_quantum)
FEATURE_BRANCH="feature-no-qjson"
git -C "$TEST_REPO" checkout -b "$FEATURE_BRANCH" -q

git -C "$TEST_REPO" checkout -b "ql-wt/US-D3" -q
printf "no quantum content\n" > "$TEST_REPO/noqjson.txt"
git -C "$TEST_REPO" add noqjson.txt
git -C "$TEST_REPO" commit -m "worktree no quantum commit" -q

git -C "$TEST_REPO" checkout "$FEATURE_BRANCH" -q

OUTPUT=$(merge_worktree_branch "$TEST_REPO" "ql-wt/US-D3" 2>&1)
EXIT_CODE=$?
assert_eq "No quantum.json fallback returns 0" "0" "$EXIT_CODE"

if [[ -f "$TEST_REPO/noqjson.txt" ]]; then
  TOTAL=$((TOTAL + 1)); echo "  PASS: No quantum.json fallback brought file"; PASS=$((PASS + 1))
else
  TOTAL=$((TOTAL + 1)); echo "  FAIL: No quantum.json fallback did not bring file"; FAIL=$((FAIL + 1))
fi
rm -rf "$TEST_REPO"

# =========================================================================
echo "=== Test D3b: Resolvable conflict returns 0 when delegated (key behavioral difference) ==="
# THIS is the test that can ONLY pass if delegation is working.
# classify_and_merge resolves "theirs" conflicts automatically (returns 0),
# but bare git merge would return 1 on any conflict.
MERGE_STRATEGY_AVAILABLE=true
TEST_REPO=$(mktemp -d)
git -C "$TEST_REPO" init -q
git -C "$TEST_REPO" commit --allow-empty -m "init" -q

# Create quantum.json with a rule that resolves *.txt conflicts via "theirs"
cat > "$TEST_REPO/quantum.json" <<'QJSON'
{
  "project": "test",
  "execution": {
    "mergeStrategy": {
      "rules": [
        {
          "name": "text_files",
          "filePattern": "*.txt",
          "strategy": "theirs",
          "postAction": ""
        }
      ],
      "defaultAction": "escalate"
    }
  },
  "progress": []
}
QJSON
git -C "$TEST_REPO" add quantum.json
git -C "$TEST_REPO" commit -m "add quantum.json" -q

FEATURE_BRANCH="feature-resolvable"
git -C "$TEST_REPO" checkout -b "$FEATURE_BRANCH" -q

# Create conflicting content on feature branch
printf "feature version\n" > "$TEST_REPO/resolvable.txt"
git -C "$TEST_REPO" add resolvable.txt
git -C "$TEST_REPO" commit -m "feature resolvable" -q

# Create worktree branch with conflicting content
git -C "$TEST_REPO" checkout -b "ql-wt/US-D3b" HEAD~1 -q
printf "worktree version\n" > "$TEST_REPO/resolvable.txt"
git -C "$TEST_REPO" add resolvable.txt
git -C "$TEST_REPO" commit -m "worktree resolvable" -q

git -C "$TEST_REPO" checkout "$FEATURE_BRANCH" -q

OUTPUT=$(merge_worktree_branch "$TEST_REPO" "ql-wt/US-D3b" 2>/dev/null)
EXIT_CODE=$?
# If delegation works: classify_and_merge resolves via "theirs" rule, returns 0
# If delegation does NOT work: bare git merge hits conflict, returns 1
assert_eq "Resolvable conflict via delegation returns 0" "0" "$EXIT_CODE"
assert_not_contains "No CONFLICT lines on resolved merge" "CONFLICT:" "$OUTPUT"

# Verify the worktree version won (theirs strategy)
if [[ -f "$TEST_REPO/resolvable.txt" ]]; then
  CONTENT=$(cat "$TEST_REPO/resolvable.txt")
  assert_eq "Theirs strategy applied (worktree content wins)" "worktree version" "$CONTENT"
fi
rm -rf "$TEST_REPO"

# =========================================================================
echo "=== Test D4: Delegation on conflict with escalation returns 1 with CONFLICT lines ==="
# When merge-strategy is available but conflict is escalated (defaultAction=escalate),
# should return 1 with CONFLICT: lines.
MERGE_STRATEGY_AVAILABLE=true
TEST_REPO=$(setup_test_repo_with_quantum)
FEATURE_BRANCH="feature-conflict-test"
git -C "$TEST_REPO" checkout -b "$FEATURE_BRANCH" -q

# Create conflicting content on feature branch
printf "feature conflicting content\n" > "$TEST_REPO/conflicted.txt"
git -C "$TEST_REPO" add conflicted.txt
git -C "$TEST_REPO" commit -m "feature conflict commit" -q

# Create worktree branch with conflicting content
git -C "$TEST_REPO" checkout -b "ql-wt/US-D4" HEAD~1 -q
printf "worktree conflicting content\n" > "$TEST_REPO/conflicted.txt"
git -C "$TEST_REPO" add conflicted.txt
git -C "$TEST_REPO" commit -m "worktree conflict commit" -q

git -C "$TEST_REPO" checkout "$FEATURE_BRANCH" -q

OUTPUT=$(merge_worktree_branch "$TEST_REPO" "ql-wt/US-D4" 2>/dev/null)
EXIT_CODE=$?
assert_eq "Delegated escalation returns 1" "1" "$EXIT_CODE"
assert_contains "Escalation has CONFLICT line" "CONFLICT:" "$OUTPUT"

# Verify merge was aborted (clean working tree)
STATUS=$(git -C "$TEST_REPO" status --porcelain)
assert_eq "Working tree clean after delegated conflict abort" "" "$STATUS"
rm -rf "$TEST_REPO"

# =========================================================================
echo "=== Test D5: Fallback conflict also returns 1 with CONFLICT lines ==="
# When merge-strategy NOT available, conflict should fall through to bare git merge
# which returns 1 with CONFLICT: lines.
MERGE_STRATEGY_AVAILABLE=false
TEST_REPO=$(setup_test_repo_without_quantum)
FEATURE_BRANCH="feature-fallback-conflict"
git -C "$TEST_REPO" checkout -b "$FEATURE_BRANCH" -q

printf "feature content fb\n" > "$TEST_REPO/fbconflict.txt"
git -C "$TEST_REPO" add fbconflict.txt
git -C "$TEST_REPO" commit -m "feature conflict fb" -q

git -C "$TEST_REPO" checkout -b "ql-wt/US-D5" HEAD~1 -q
printf "worktree content fb\n" > "$TEST_REPO/fbconflict.txt"
git -C "$TEST_REPO" add fbconflict.txt
git -C "$TEST_REPO" commit -m "worktree conflict fb" -q

git -C "$TEST_REPO" checkout "$FEATURE_BRANCH" -q

OUTPUT=$(merge_worktree_branch "$TEST_REPO" "ql-wt/US-D5" 2>/dev/null)
EXIT_CODE=$?
assert_eq "Fallback conflict returns 1" "1" "$EXIT_CODE"
assert_contains "Fallback conflict has CONFLICT line" "CONFLICT:" "$OUTPUT"

STATUS=$(git -C "$TEST_REPO" status --porcelain)
assert_eq "Working tree clean after fallback conflict abort" "" "$STATUS"
rm -rf "$TEST_REPO"

# =========================================================================
echo "=== Test D6: Function signature unchanged (still repo_root, worktree_branch) ==="
# Verify parameter validation still works as before
MERGE_STRATEGY_AVAILABLE=true
RESULT=$(merge_worktree_branch "" "branch" 2>&1)
EXIT_CODE=$?
assert_eq "Empty repo_root still returns 1" "1" "$EXIT_CODE"
assert_contains "Empty repo_root error message" "requires repo_root" "$RESULT"

RESULT=$(merge_worktree_branch "/tmp" "" 2>&1)
EXIT_CODE=$?
assert_eq "Empty branch still returns 1" "1" "$EXIT_CODE"
assert_contains "Empty branch error message" "requires worktree_branch" "$RESULT"

# =========================================================================
echo ""
echo "=== Results: $PASS/$TOTAL passed, $FAIL failed ==="
if [[ $FAIL -eq 0 ]]; then
  exit 0
else
  exit 1
fi
