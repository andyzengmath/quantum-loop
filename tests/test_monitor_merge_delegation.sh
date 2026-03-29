#!/usr/bin/env bash
# Test suite for merge_worktree_branch() delegation to classify_and_merge() and squash_and_merge()
# Tests that merge_worktree_branch delegates to squash_and_merge when resilience available,
# falls back to classify_and_merge, and falls back to bare git merge when neither available.

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
echo "=== Test R1: RESILIENCE_AVAILABLE variable is set after sourcing monitor.sh ==="
# monitor.sh should set RESILIENCE_AVAILABLE (either true or false depending on whether
# resilience.sh exists). Since resilience.sh doesn't exist yet, it should be "false".
if [[ -n "$RESILIENCE_AVAILABLE" ]]; then
  TOTAL=$((TOTAL + 1)); echo "  PASS: RESILIENCE_AVAILABLE is set"; PASS=$((PASS + 1))
else
  TOTAL=$((TOTAL + 1)); echo "  FAIL: RESILIENCE_AVAILABLE is not set"; FAIL=$((FAIL + 1))
fi
# lib/resilience.sh exists (created by US-002), so RESILIENCE_AVAILABLE should be "true"
assert_eq "RESILIENCE_AVAILABLE is true when resilience.sh exists" "true" "$RESILIENCE_AVAILABLE"

# =========================================================================
echo "=== Test R2: squash_and_merge delegation when RESILIENCE_AVAILABLE=true ==="
# When RESILIENCE_AVAILABLE is true and squash_and_merge function exists,
# merge_worktree_branch should delegate to squash_and_merge BEFORE classify_and_merge.
# We mock squash_and_merge to write its args to a marker file (since OUTPUT=$() runs
# in a subshell, we cannot use variable tracking).

# Save original state
ORIG_RESILIENCE=$RESILIENCE_AVAILABLE
ORIG_MERGE_STRATEGY=$MERGE_STRATEGY_AVAILABLE

# Marker file for capturing squash_and_merge invocation
SQUASH_MARKER=$(mktemp)
rm -f "$SQUASH_MARKER"

# Mock squash_and_merge to write arguments to marker file and perform merge
squash_and_merge() {
  printf "%s\n" "$*" > "$SQUASH_MARKER"
  # Perform a real merge so the test repo stays consistent
  local branch="$1" repo="$2"
  git -C "$repo" merge --no-ff "$branch" --no-edit -q > /dev/null 2>&1
  return $?
}

RESILIENCE_AVAILABLE=true
MERGE_STRATEGY_AVAILABLE=true

# Create quantum.json with stories for extraction test
TEST_REPO=$(mktemp -d)
git -C "$TEST_REPO" init -q
git -C "$TEST_REPO" commit --allow-empty -m "init" -q

cat > "$TEST_REPO/quantum.json" <<'QJSON'
{
  "project": "test",
  "stories": [
    {"id": "US-R2", "title": "Resilience delegation test story"}
  ],
  "execution": {
    "mergeStrategy": { "rules": [], "defaultAction": "escalate" }
  },
  "progress": []
}
QJSON
git -C "$TEST_REPO" add quantum.json
git -C "$TEST_REPO" commit -m "add quantum.json" -q

FEATURE_BRANCH="feature-resilience-test"
git -C "$TEST_REPO" checkout -b "$FEATURE_BRANCH" -q

git -C "$TEST_REPO" checkout -b "ql-wt/US-R2" -q
printf "resilience content\n" > "$TEST_REPO/resilience-file.txt"
git -C "$TEST_REPO" add resilience-file.txt
git -C "$TEST_REPO" commit -m "worktree resilience commit" -q

git -C "$TEST_REPO" checkout "$FEATURE_BRANCH" -q

OUTPUT=$(merge_worktree_branch "$TEST_REPO" "ql-wt/US-R2" 2>&1)
EXIT_CODE=$?

# Check marker file exists (proves squash_and_merge was called)
if [[ -f "$SQUASH_MARKER" ]]; then
  SQUASH_ARGS=$(cat "$SQUASH_MARKER")
  TOTAL=$((TOTAL + 1)); echo "  PASS: squash_and_merge called when RESILIENCE_AVAILABLE=true"; PASS=$((PASS + 1))
else
  SQUASH_ARGS=""
  TOTAL=$((TOTAL + 1)); echo "  FAIL: squash_and_merge NOT called when RESILIENCE_AVAILABLE=true"; FAIL=$((FAIL + 1))
fi
assert_eq "squash_and_merge delegation returns 0" "0" "$EXIT_CODE"

# Verify arguments include story_id extracted from branch name
assert_contains "squash_and_merge receives branch" "ql-wt/US-R2" "$SQUASH_ARGS"
assert_contains "squash_and_merge receives story_id" "US-R2" "$SQUASH_ARGS"
assert_contains "squash_and_merge receives json_path" "quantum.json" "$SQUASH_ARGS"

rm -rf "$TEST_REPO"
rm -f "$SQUASH_MARKER"
unset -f squash_and_merge

# =========================================================================
echo "=== Test R3: story_title extracted from quantum.json ==="
# squash_and_merge should receive the story title extracted from quantum.json

SQUASH_MARKER=$(mktemp)
rm -f "$SQUASH_MARKER"

squash_and_merge() {
  printf "%s\n" "$*" > "$SQUASH_MARKER"
  local branch="$1" repo="$2"
  git -C "$repo" merge --no-ff "$branch" --no-edit -q > /dev/null 2>&1
  return $?
}

RESILIENCE_AVAILABLE=true
MERGE_STRATEGY_AVAILABLE=true

TEST_REPO=$(mktemp -d)
git -C "$TEST_REPO" init -q
git -C "$TEST_REPO" commit --allow-empty -m "init" -q

cat > "$TEST_REPO/quantum.json" <<'QJSON'
{
  "project": "test",
  "stories": [
    {"id": "US-R3", "title": "My special title"}
  ],
  "execution": {
    "mergeStrategy": { "rules": [], "defaultAction": "escalate" }
  },
  "progress": []
}
QJSON
git -C "$TEST_REPO" add quantum.json
git -C "$TEST_REPO" commit -m "add quantum.json" -q

FEATURE_BRANCH="feature-title-extract"
git -C "$TEST_REPO" checkout -b "$FEATURE_BRANCH" -q

git -C "$TEST_REPO" checkout -b "ql-wt/US-R3" -q
printf "title test\n" > "$TEST_REPO/titletest.txt"
git -C "$TEST_REPO" add titletest.txt
git -C "$TEST_REPO" commit -m "worktree title commit" -q

git -C "$TEST_REPO" checkout "$FEATURE_BRANCH" -q

OUTPUT=$(merge_worktree_branch "$TEST_REPO" "ql-wt/US-R3" 2>&1)
EXIT_CODE=$?

assert_eq "story title delegation returns 0" "0" "$EXIT_CODE"
if [[ -f "$SQUASH_MARKER" ]]; then
  SQUASH_ARGS=$(cat "$SQUASH_MARKER")
  assert_contains "squash_and_merge receives story title" "My special title" "$SQUASH_ARGS"
else
  TOTAL=$((TOTAL + 1)); echo "  FAIL: squash_and_merge not called for title test"; FAIL=$((FAIL + 1))
fi

rm -rf "$TEST_REPO"
rm -f "$SQUASH_MARKER"
unset -f squash_and_merge

# =========================================================================
echo "=== Test R4: Fallback to classify_and_merge when RESILIENCE_AVAILABLE=false ==="
# When RESILIENCE_AVAILABLE is false but MERGE_STRATEGY_AVAILABLE is true,
# should skip squash_and_merge and delegate to classify_and_merge instead.

RESILIENCE_AVAILABLE=false
MERGE_STRATEGY_AVAILABLE=true

TEST_REPO=$(setup_test_repo_with_quantum)
FEATURE_BRANCH="feature-no-resilience"
git -C "$TEST_REPO" checkout -b "$FEATURE_BRANCH" -q

git -C "$TEST_REPO" checkout -b "ql-wt/US-R4" -q
printf "no resilience content\n" > "$TEST_REPO/noresilience.txt"
git -C "$TEST_REPO" add noresilience.txt
git -C "$TEST_REPO" commit -m "worktree no resilience commit" -q

git -C "$TEST_REPO" checkout "$FEATURE_BRANCH" -q

OUTPUT=$(merge_worktree_branch "$TEST_REPO" "ql-wt/US-R4" 2>&1)
EXIT_CODE=$?

assert_eq "Classify_and_merge fallback returns 0" "0" "$EXIT_CODE"
if [[ -f "$TEST_REPO/noresilience.txt" ]]; then
  TOTAL=$((TOTAL + 1)); echo "  PASS: classify_and_merge fallback brought file"; PASS=$((PASS + 1))
else
  TOTAL=$((TOTAL + 1)); echo "  FAIL: classify_and_merge fallback did not bring file"; FAIL=$((FAIL + 1))
fi
rm -rf "$TEST_REPO"

# =========================================================================
echo "=== Test R5: Fallback to bare merge when both RESILIENCE and MERGE_STRATEGY false ==="
RESILIENCE_AVAILABLE=false
MERGE_STRATEGY_AVAILABLE=false

TEST_REPO=$(setup_test_repo_without_quantum)
FEATURE_BRANCH="feature-bare-fallback"
git -C "$TEST_REPO" checkout -b "$FEATURE_BRANCH" -q

git -C "$TEST_REPO" checkout -b "ql-wt/US-R5" -q
printf "bare fallback content\n" > "$TEST_REPO/barefallback.txt"
git -C "$TEST_REPO" add barefallback.txt
git -C "$TEST_REPO" commit -m "worktree bare fallback commit" -q

git -C "$TEST_REPO" checkout "$FEATURE_BRANCH" -q

OUTPUT=$(merge_worktree_branch "$TEST_REPO" "ql-wt/US-R5" 2>&1)
EXIT_CODE=$?

assert_eq "Bare git merge fallback returns 0" "0" "$EXIT_CODE"
if [[ -f "$TEST_REPO/barefallback.txt" ]]; then
  TOTAL=$((TOTAL + 1)); echo "  PASS: Bare fallback brought file"; PASS=$((PASS + 1))
else
  TOTAL=$((TOTAL + 1)); echo "  FAIL: Bare fallback did not bring file"; FAIL=$((FAIL + 1))
fi
rm -rf "$TEST_REPO"

# Restore original values
RESILIENCE_AVAILABLE=$ORIG_RESILIENCE
MERGE_STRATEGY_AVAILABLE=$ORIG_MERGE_STRATEGY

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
