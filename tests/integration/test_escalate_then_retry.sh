#!/usr/bin/env bash
# tests/integration/test_escalate_then_retry.sh
# Integration test for the escalate-then-retry merge flow:
#   1. Set up repo with main branch + src/config.ts
#   2. Create branch-a modifying config.ts line 1, merge into main
#   3. Create branch-b from pre-merge main: modify config.ts differently
#   4. Set up quantum.json with default mergeStrategy (no rule matches config.ts -> escalate)
#   5. Call classify_and_merge for branch-b: verify returns 1 (escalated), merge aborted
#   6. Simulate retry: re-create branch-b from current HEAD (post branch-a merge)
#   7. Call classify_and_merge again: verify returns 0 (no conflict)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="$SCRIPT_DIR/../../lib"
PASS=0
FAIL=0
TOTAL=0

# Source the library under test
if [[ ! -f "$LIB_DIR/merge-strategy.sh" ]]; then
  echo "SKIP: lib/merge-strategy.sh not found (RED phase)"
  exit 1
fi
source "$LIB_DIR/merge-strategy.sh"

# Disable optional module side-effects during testing
DEP_MANIFEST_AVAILABLE=false
BARREL_REGEN_AVAILABLE=false

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

assert_not_contains() {
  local test_name="$1" needle="$2" haystack="$3"
  TOTAL=$((TOTAL + 1))
  if ! echo "$haystack" | grep -qF "$needle"; then
    echo "  PASS: $test_name"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: $test_name"
    echo "    expected NOT to contain: $needle"
    echo "    actual: $haystack"
    FAIL=$((FAIL + 1))
  fi
}

# =========================================================================
# Setup
# =========================================================================
TEST_TMPDIR=$(mktemp -d)
ORIG_DIR=$(pwd)

cleanup() {
  cd "$ORIG_DIR"
  rm -rf "$TEST_TMPDIR"
}

trap cleanup EXIT

# Create quantum.json with mergeStrategy (no rule matches src/config.ts -> escalate)
create_quantum_json() {
  local repo_dir="$1"
  local py_repo_dir="$repo_dir"
  if command -v cygpath &>/dev/null; then
    py_repo_dir=$(cygpath -m "$repo_dir")
  fi
  python -c "
import json
d = {
  'project': 'test-escalation',
  'execution': {
    'mergeStrategy': {
      'rules': [
        {'name': 'dependency_manifest', 'filePattern': 'package.json|package-lock.json', 'strategy': 'ours'},
        {'name': 'barrel_export', 'filePattern': '**/index.ts|**/index.js', 'strategy': 'theirs'}
      ],
      'defaultAction': 'escalate'
    }
  },
  'progress': []
}
with open('${py_repo_dir}/quantum.json', 'w') as f:
  json.dump(d, f, indent=2)
"
}

echo "=== Integration Test: Escalate Then Retry ==="
echo ""

# =========================================================================
echo "--- Step 1: Set up repo with main branch + src/config.ts ---"
REPO="$TEST_TMPDIR/repo"
mkdir -p "$REPO/src"
cd "$REPO" || exit 1
git init --initial-branch=main . >/dev/null 2>&1
git config user.email "test@test.com"
git config user.name "Test"

printf "line1: original config\nline2: shared setting\n" > src/config.ts
git add -A >/dev/null 2>&1
git commit -m "initial commit with config.ts" >/dev/null 2>&1

# Save the pre-merge commit for branch-b later
PRE_MERGE_SHA=$(git rev-parse HEAD)

echo ""
echo "--- Step 2: Create branch-a, modify config.ts, merge into main ---"
git checkout -b branch-a >/dev/null 2>&1
printf "line1: branch-a modified config\nline2: shared setting\n" > src/config.ts
git add -A >/dev/null 2>&1
git commit -m "branch-a: modify config.ts" >/dev/null 2>&1

# Merge branch-a into main
git checkout main >/dev/null 2>&1
git merge --no-ff branch-a --no-edit -q >/dev/null 2>&1

# Verify merge
TOTAL=$((TOTAL + 1))
MERGED_CONTENT=$(cat src/config.ts)
if echo "$MERGED_CONTENT" | grep -q "branch-a modified"; then
  echo "  PASS: branch-a merged into main"
  PASS=$((PASS + 1))
else
  echo "  FAIL: branch-a content not on main"
  FAIL=$((FAIL + 1))
fi

echo ""
echo "--- Step 3: Create branch-b from pre-merge main, modify config.ts differently ---"
git checkout -b branch-b "$PRE_MERGE_SHA" >/dev/null 2>&1
printf "line1: branch-b different config\nline2: shared setting\n" > src/config.ts
git add -A >/dev/null 2>&1
git commit -m "branch-b: modify config.ts differently" >/dev/null 2>&1

# Go back to main for the merge attempt
git checkout main >/dev/null 2>&1

echo ""
echo "--- Step 4: Set up quantum.json with escalate default ---"
create_quantum_json "$REPO"

TOTAL=$((TOTAL + 1))
if [[ -f "$REPO/quantum.json" ]]; then
  echo "  PASS: quantum.json created"
  PASS=$((PASS + 1))
else
  echo "  FAIL: quantum.json not found"
  FAIL=$((FAIL + 1))
fi

# Stage and commit quantum.json so the working tree is clean for merge
git add quantum.json >/dev/null 2>&1
git commit -m "add quantum.json" >/dev/null 2>&1

echo ""
echo "--- Step 5: classify_and_merge for branch-b -- expect escalation (return 1) ---"
OUTPUT=$(classify_and_merge "branch-b" "$REPO" "$REPO/quantum.json" 2>&1)
EXIT_CODE=$?
assert_eq "escalation returns exit code 1" "1" "$EXIT_CODE"

# Verify CONFLICT line in output for src/config.ts
assert_contains "output includes CONFLICT: src/config.ts" "CONFLICT: src/config.ts" "$OUTPUT"

# Verify the merge was aborted (working tree is clean)
STATUS=$(git -C "$REPO" status --porcelain 2>/dev/null)
assert_eq "working tree clean after escalation abort" "" "$STATUS"

# Verify main still has branch-a content (merge was aborted, not committed)
MAIN_CONTENT=$(cat "$REPO/src/config.ts")
assert_contains "main still has branch-a content" "branch-a modified" "$MAIN_CONTENT"
assert_not_contains "main does NOT have branch-b content" "branch-b different" "$MAIN_CONTENT"

echo ""
echo "--- Step 6: Simulate retry -- re-create branch-b from current HEAD ---"
# Delete old branch-b
git -C "$REPO" branch -D branch-b >/dev/null 2>&1

# Create new branch-b from current main HEAD (which includes branch-a merge)
git -C "$REPO" checkout -b branch-b >/dev/null 2>&1

# Apply a non-conflicting change (different from line 1 which branch-a already changed)
printf "line1: branch-a modified config\nline2: shared setting\nline3: branch-b addition\n" > "$REPO/src/config.ts"
git -C "$REPO" add -A >/dev/null 2>&1
git -C "$REPO" commit -m "branch-b retry: add line 3 to config.ts" >/dev/null 2>&1

# Go back to main
git -C "$REPO" checkout main >/dev/null 2>&1

echo ""
echo "--- Step 7: classify_and_merge for retried branch-b -- expect success (return 0) ---"
OUTPUT2=$(classify_and_merge "branch-b" "$REPO" "$REPO/quantum.json" 2>&1)
EXIT_CODE2=$?
assert_eq "retry merge returns exit code 0" "0" "$EXIT_CODE2"

# Verify no CONFLICT lines in output
assert_not_contains "no CONFLICT in retry output" "CONFLICT:" "$OUTPUT2"

# Verify the merge was committed (branch-b content now on main)
FINAL_CONTENT=$(cat "$REPO/src/config.ts")
assert_contains "main has branch-b addition after retry" "branch-b addition" "$FINAL_CONTENT"
assert_contains "main retains branch-a content after retry" "branch-a modified" "$FINAL_CONTENT"

# Verify merge commit exists
COMMIT_MSG=$(git -C "$REPO" log -1 --format="%s" 2>/dev/null)
TOTAL=$((TOTAL + 1))
if echo "$COMMIT_MSG" | grep -qi "merge\|branch-b"; then
  echo "  PASS: merge commit created for retry"
  PASS=$((PASS + 1))
else
  echo "  FAIL: expected merge commit, got: $COMMIT_MSG"
  FAIL=$((FAIL + 1))
fi

# =========================================================================
echo ""
echo "=== Results: $PASS/$TOTAL passed, $FAIL failed ==="
if [[ $FAIL -eq 0 ]]; then
  exit 0
else
  exit 1
fi
