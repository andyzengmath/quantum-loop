#!/usr/bin/env bash
# tests/integration/test_merge_with_barrel.sh
# Integration test: barrel export merge via classify_and_merge
#
# Scenario:
#   main has src/parsers/index.ts with 'export * from "./OldParser"'
#   branch-a: adds NewParser.ts, adds export to index.ts
#   branch-b (from main): adds AnotherParser.ts, adds export to index.ts
#   Merge branch-a into main (clean)
#   Merge branch-b via classify_and_merge -- index.ts conflicts
#   Verify: conflict classified as barrel_export:regenerate,
#           final index.ts has all 3 exports sorted, returns 0

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="$SCRIPT_DIR/../../lib"
PASS=0
FAIL=0
TOTAL=0

# Source the merge-strategy module (which sources barrel-regen and dep-manifest)
if [[ ! -f "$LIB_DIR/merge-strategy.sh" ]]; then
  echo "SKIP: lib/merge-strategy.sh not found"
  exit 1
fi
source "$LIB_DIR/merge-strategy.sh"

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

assert_file_contains() {
  local test_name="$1" needle="$2" file_path="$3"
  TOTAL=$((TOTAL + 1))
  if [[ -f "$file_path" ]] && grep -qF "$needle" "$file_path"; then
    echo "  PASS: $test_name"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: $test_name"
    echo "    expected file to contain: $needle"
    if [[ -f "$file_path" ]]; then
      echo "    file contents: $(cat "$file_path")"
    else
      echo "    file does not exist: $file_path"
    fi
    FAIL=$((FAIL + 1))
  fi
}

assert_file_not_contains() {
  local test_name="$1" needle="$2" file_path="$3"
  TOTAL=$((TOTAL + 1))
  if [[ -f "$file_path" ]] && ! grep -qF "$needle" "$file_path"; then
    echo "  PASS: $test_name"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: $test_name"
    echo "    expected file NOT to contain: $needle"
    if [[ -f "$file_path" ]]; then
      echo "    file contents: $(cat "$file_path")"
    fi
    FAIL=$((FAIL + 1))
  fi
}

# =========================================================================
TMPDIR=$(mktemp -d)
ORIG_DIR=$(pwd)

cleanup() {
  cd "$ORIG_DIR" || true
  rm -rf "$TMPDIR"
}
trap cleanup EXIT

# Helper: create quantum.json with barrel_export regenerate rule
create_barrel_quantum_json() {
  local repo_dir="$1"
  local py_repo_dir="$repo_dir"
  if command -v cygpath &>/dev/null; then
    py_repo_dir=$(cygpath -m "$repo_dir")
  fi
  python -c "
import json
d = {
  'project': 'test-barrel-integration',
  'execution': {
    'mergeStrategy': {
      'rules': [
        {'name': 'barrel_export', 'filePattern': '**/index.ts|**/index.js|**/__init__.py|**/mod.rs', 'strategy': 'regenerate'},
        {'name': 'dependency_manifest', 'filePattern': 'package.json|package-lock.json', 'strategy': 'ours', 'postAction': 'install'}
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

# =========================================================================
echo "=== Integration Test: Barrel Export Merge ==="
echo ""

# Step 1: Set up temp git repo with main branch
echo "--- Step 1: Set up repo with initial barrel file ---"
REPO="$TMPDIR/barrel-test"
mkdir -p "$REPO/src/parsers"
cd "$REPO" || exit 1
git init --initial-branch=main . >/dev/null 2>&1
git config user.email "test@test.com"
git config user.name "Test"

# Create OldParser.ts and initial barrel
printf "export class OldParser {}\n" > src/parsers/OldParser.ts
printf "export * from './OldParser'\n" > src/parsers/index.ts
git add -A >/dev/null 2>&1
git commit -m "initial: OldParser with barrel" >/dev/null 2>&1

# Step 2: Create branch-a from main
echo "--- Step 2: Create branch-a with NewParser ---"
git checkout -b branch-a >/dev/null 2>&1
printf "export class NewParser {}\n" > src/parsers/NewParser.ts
printf "export * from './NewParser'\nexport * from './OldParser'\n" > src/parsers/index.ts
git add -A >/dev/null 2>&1
git commit -m "branch-a: add NewParser" >/dev/null 2>&1

# Step 3: Create branch-b from main (diverging)
echo "--- Step 3: Create branch-b with AnotherParser ---"
git checkout main >/dev/null 2>&1
git checkout -b branch-b >/dev/null 2>&1
printf "export class AnotherParser {}\n" > src/parsers/AnotherParser.ts
printf "export * from './AnotherParser'\nexport * from './OldParser'\n" > src/parsers/index.ts
git add -A >/dev/null 2>&1
git commit -m "branch-b: add AnotherParser" >/dev/null 2>&1

# Step 4: Merge branch-a into main (clean merge)
echo "--- Step 4: Merge branch-a into main (clean) ---"
git checkout main >/dev/null 2>&1
git merge --no-ff branch-a --no-edit -q >/dev/null 2>&1
MERGE_A_EXIT=$?
assert_eq "branch-a merges cleanly into main" "0" "$MERGE_A_EXIT"

# Verify main now has NewParser
assert_file_contains "main has NewParser.ts after branch-a merge" "NewParser" "$REPO/src/parsers/NewParser.ts"
assert_file_contains "main barrel has NewParser export" "NewParser" "$REPO/src/parsers/index.ts"

# Step 5: Set up quantum.json with barrel_export regenerate rule and commit it
echo "--- Step 5: Set up quantum.json with mergeStrategy ---"
create_barrel_quantum_json "$REPO"
git -C "$REPO" add quantum.json >/dev/null 2>&1
git -C "$REPO" commit -m "add quantum.json" >/dev/null 2>&1

# Step 6: Merge branch-b via classify_and_merge (will conflict on index.ts)
echo "--- Step 6: Merge branch-b via classify_and_merge ---"
OUTPUT=$(classify_and_merge "branch-b" "$REPO" "$REPO/quantum.json" 2>&1)
MERGE_EXIT=$?

echo "  classify_and_merge output:"
echo "$OUTPUT" | sed 's/^/    /'

# Verify: returns 0 (conflict resolved)
assert_eq "classify_and_merge returns 0 (barrel conflict resolved)" "0" "$MERGE_EXIT"

# Verify: conflict was classified as barrel_export:regenerate
assert_contains "output mentions barrel_export classification" "barrel_export" "$OUTPUT"

# Verify: final index.ts has all 3 exports
BARREL_FILE="$REPO/src/parsers/index.ts"
echo "--- Step 7: Verify final barrel contents ---"
if [[ -f "$BARREL_FILE" ]]; then
  echo "  Final barrel contents:"
  cat "$BARREL_FILE" | sed 's/^/    /'
fi

assert_file_contains "barrel has AnotherParser export" "AnotherParser" "$BARREL_FILE"
assert_file_contains "barrel has NewParser export" "NewParser" "$BARREL_FILE"
assert_file_contains "barrel has OldParser export" "OldParser" "$BARREL_FILE"

# Verify: no merge conflict markers remain
assert_file_not_contains "no conflict markers in barrel" "<<<<<<<" "$BARREL_FILE"
assert_file_not_contains "no conflict separator in barrel" "=======" "$BARREL_FILE"
assert_file_not_contains "no conflict end marker in barrel" ">>>>>>>" "$BARREL_FILE"

# Verify: exports are sorted (AnotherParser before NewParser before OldParser)
echo "--- Step 8: Verify export ordering ---"
if [[ -f "$BARREL_FILE" ]]; then
  SORTED_CHECK=$(grep "export \* from" "$BARREL_FILE" | sort -c 2>&1)
  SORT_EXIT=$?
  assert_eq "exports are sorted" "0" "$SORT_EXIT"
fi

# Verify: AnotherParser.ts file exists on main after merge
assert_file_contains "AnotherParser.ts exists after merge" "AnotherParser" "$REPO/src/parsers/AnotherParser.ts"

# Verify: git working tree is clean
GIT_STATUS=$(git -C "$REPO" status --porcelain)
assert_eq "working tree clean after merge" "" "$GIT_STATUS"

# =========================================================================
echo ""
echo "=== Results: $PASS/$TOTAL passed, $FAIL failed ==="
if [[ $FAIL -eq 0 ]]; then
  exit 0
else
  exit 1
fi
