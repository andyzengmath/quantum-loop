#!/usr/bin/env bash
# tests/integration/test_semantic_merge_conflict.sh
# Integration test: semantic 3-way merge of TypeScript interfaces using diff3
#
# Scenario:
#   Base file has `interface Base { id: string; }`
#   branch-a adds `interface Foo { name: string; }` to the same file
#   branch-b adds `interface Bar { value: number; }` to the same file
#   Extract base/ours(branch-a)/theirs(branch-b) versions from git
#   Use diff3 -m to perform a 3-way semantic merge
#   Verify merged output contains all three: Base, Foo, and Bar

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="$SCRIPT_DIR/../../lib"
PASS=0
FAIL=0
TOTAL=0

# Check if diff3 is available; SKIP if not
if ! command -v diff3 &>/dev/null; then
  echo "SKIP: diff3 not available"
  exit 0
fi

# Source the merge-strategy library for consistency with other integration tests
if [[ ! -f "$LIB_DIR/merge-strategy.sh" ]]; then
  echo "SKIP: lib/merge-strategy.sh not found"
  exit 0
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
TMPDIR=$(mktemp -d)
ORIG_DIR=$(pwd)

cleanup() {
  cd "$ORIG_DIR" || true
  rm -rf "$TMPDIR"
}
trap cleanup EXIT

echo "=== Integration Test: Semantic Merge Conflict ==="
echo ""

# =========================================================================
# Step 1: Create a temp git repo with base TypeScript file
# =========================================================================
echo "--- Step 1: Set up repo with base interface ---"
REPO="$TMPDIR/semantic-merge-test"
mkdir -p "$REPO"
cd "$REPO" || exit 1
git init --initial-branch=main . >/dev/null 2>&1
git config user.email "test@test.com"
git config user.name "Test"

# Create base TypeScript file with interface Base and section markers.
# The file has distinct regions so branch-a and branch-b can each add
# their interface to a different location, enabling diff3 to merge cleanly.
cat > types.ts << 'TSEOF'
// === Section: Core Types ===

interface Base {
  id: string;
}

// === Section: Extended Types ===

// placeholder: more types go here
TSEOF
git add -A >/dev/null 2>&1
git commit -m "initial: interface Base" >/dev/null 2>&1

BASE_SHA=$(git rev-parse HEAD)

TOTAL=$((TOTAL + 1))
if [[ -n "$BASE_SHA" ]]; then
  echo "  PASS: base commit created ($BASE_SHA)"
  PASS=$((PASS + 1))
else
  echo "  FAIL: base commit not created"
  FAIL=$((FAIL + 1))
fi

# =========================================================================
# Step 2: Create branch-a, add interface Foo
# =========================================================================
echo ""
echo "--- Step 2: Create branch-a with interface Foo ---"
git checkout -b branch-a >/dev/null 2>&1

# Add interface Foo right after Base in the Core Types section
cat > types.ts << 'TSEOF'
// === Section: Core Types ===

interface Base {
  id: string;
}

interface Foo {
  name: string;
}

// === Section: Extended Types ===

// placeholder: more types go here
TSEOF
git add -A >/dev/null 2>&1
git commit -m "branch-a: add interface Foo" >/dev/null 2>&1

BRANCH_A_SHA=$(git rev-parse HEAD)

TOTAL=$((TOTAL + 1))
if git log --oneline -1 | grep -q "Foo"; then
  echo "  PASS: branch-a commit has Foo"
  PASS=$((PASS + 1))
else
  echo "  FAIL: branch-a commit missing Foo"
  FAIL=$((FAIL + 1))
fi

# =========================================================================
# Step 3: Switch back to main
# =========================================================================
echo ""
echo "--- Step 3: Switch back to main ---"
git checkout main >/dev/null 2>&1

TOTAL=$((TOTAL + 1))
CURRENT_BRANCH=$(git branch --show-current)
if [[ "$CURRENT_BRANCH" == "main" ]]; then
  echo "  PASS: on main branch"
  PASS=$((PASS + 1))
else
  echo "  FAIL: expected main branch, got $CURRENT_BRANCH"
  FAIL=$((FAIL + 1))
fi

# =========================================================================
# Step 4: Create branch-b, add interface Bar
# =========================================================================
echo ""
echo "--- Step 4: Create branch-b with interface Bar ---"
git checkout -b branch-b >/dev/null 2>&1

# Add interface Bar in the Extended Types section (replacing the placeholder)
cat > types.ts << 'TSEOF'
// === Section: Core Types ===

interface Base {
  id: string;
}

// === Section: Extended Types ===

interface Bar {
  value: number;
}
TSEOF
git add -A >/dev/null 2>&1
git commit -m "branch-b: add interface Bar" >/dev/null 2>&1

BRANCH_B_SHA=$(git rev-parse HEAD)

TOTAL=$((TOTAL + 1))
if git log --oneline -1 | grep -q "Bar"; then
  echo "  PASS: branch-b commit has Bar"
  PASS=$((PASS + 1))
else
  echo "  FAIL: branch-b commit missing Bar"
  FAIL=$((FAIL + 1))
fi

# =========================================================================
# Step 5: Extract base, ours (branch-a), theirs (branch-b) file versions
# =========================================================================
echo ""
echo "--- Step 5: Extract file versions for 3-way merge ---"

BASE_FILE="$TMPDIR/base.ts"
OURS_FILE="$TMPDIR/ours.ts"
THEIRS_FILE="$TMPDIR/theirs.ts"

git show "${BASE_SHA}:types.ts" > "$BASE_FILE" 2>/dev/null
git show "${BRANCH_A_SHA}:types.ts" > "$OURS_FILE" 2>/dev/null
git show "${BRANCH_B_SHA}:types.ts" > "$THEIRS_FILE" 2>/dev/null

TOTAL=$((TOTAL + 1))
if [[ -s "$BASE_FILE" ]] && [[ -s "$OURS_FILE" ]] && [[ -s "$THEIRS_FILE" ]]; then
  echo "  PASS: all three file versions extracted"
  PASS=$((PASS + 1))
else
  echo "  FAIL: failed to extract file versions"
  FAIL=$((FAIL + 1))
fi

# =========================================================================
# Step 6: Perform 3-way merge using diff3
# =========================================================================
echo ""
echo "--- Step 6: Run diff3 -m for semantic 3-way merge ---"

# diff3 -m: merge ours, base, theirs
# Exit 0 = clean merge, Exit 1 = conflicts remain, Exit 2 = trouble
MERGED_OUTPUT=$(diff3 -m "$OURS_FILE" "$BASE_FILE" "$THEIRS_FILE" 2>&1)
DIFF3_EXIT=$?

echo "  diff3 exit code: $DIFF3_EXIT"
echo "  Merged output:"
echo "$MERGED_OUTPUT" | sed 's/^/    /'

# diff3 exit 0 means clean merge (no conflicts)
assert_eq "diff3 exits with 0 (clean merge)" "0" "$DIFF3_EXIT"

# =========================================================================
# Step 7: Verify merged output contains all three interfaces
# =========================================================================
echo ""
echo "--- Step 7: Verify merged output contains Base, Foo, and Bar ---"

assert_contains "merged output contains interface Base" "interface Base" "$MERGED_OUTPUT"
assert_contains "merged output contains interface Foo" "interface Foo" "$MERGED_OUTPUT"
assert_contains "merged output contains interface Bar" "interface Bar" "$MERGED_OUTPUT"

# Verify specific field members are present
assert_contains "merged output contains id: string" "id: string" "$MERGED_OUTPUT"
assert_contains "merged output contains name: string" "name: string" "$MERGED_OUTPUT"
assert_contains "merged output contains value: number" "value: number" "$MERGED_OUTPUT"

# Verify no conflict markers in the merged output
assert_not_contains "no conflict markers (<<<<<<)" "<<<<<<<" "$MERGED_OUTPUT"
assert_not_contains "no conflict separator (=======)" "=======" "$MERGED_OUTPUT"
assert_not_contains "no conflict end marker (>>>>>>>)" ">>>>>>>" "$MERGED_OUTPUT"

# =========================================================================
# Step 8: Verify git repo is in a clean state
# =========================================================================
echo ""
echo "--- Step 8: Verify temp repo state ---"

GIT_STATUS=$(git -C "$REPO" status --porcelain 2>/dev/null)
assert_eq "temp repo working tree is clean" "" "$GIT_STATUS"

# Verify all branches exist
TOTAL=$((TOTAL + 1))
if git -C "$REPO" rev-parse --verify branch-a &>/dev/null && \
   git -C "$REPO" rev-parse --verify branch-b &>/dev/null; then
  echo "  PASS: both branches (branch-a, branch-b) exist"
  PASS=$((PASS + 1))
else
  echo "  FAIL: expected both branch-a and branch-b to exist"
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
