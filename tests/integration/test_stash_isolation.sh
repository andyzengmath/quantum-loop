#!/usr/bin/env bash
# tests/integration/test_stash_isolation.sh
# Integration test: verifies quantum.json is never corrupted during merges.
# Tests both tracked and .gitignored quantum.json scenarios.
#
# Depends on: lib/merge-strategy.sh (with stash exclusion from US-004)

# shellcheck disable=SC1091,SC2034,SC2329

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="$SCRIPT_DIR/../../lib"
PASS=0
FAIL=0
TOTAL=0

# Source the library under test
if [[ ! -f "$LIB_DIR/merge-strategy.sh" ]]; then
  echo "SKIP: lib/merge-strategy.sh not found"
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

assert_file_not_exists() {
  local test_name="$1" file_path="$2"
  TOTAL=$((TOTAL + 1))
  if [[ ! -f "$file_path" ]]; then
    echo "  PASS: $test_name"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: $test_name (file still exists: $file_path)"
    FAIL=$((FAIL + 1))
  fi
}

assert_valid_json() {
  local test_name="$1" file_path="$2"
  TOTAL=$((TOTAL + 1))
  local py_path="$file_path"
  if command -v cygpath &>/dev/null; then
    py_path=$(cygpath -m "$file_path")
  fi
  if python -c "import json; json.load(open('${py_path}'))" 2>/dev/null; then
    echo "  PASS: $test_name"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: $test_name (invalid JSON in $file_path)"
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

# Helper: create a quantum.json with story statuses and a unique marker
create_quantum_json_with_marker() {
  local dest="$1"
  local marker="$2"
  local py_dest="$dest"
  if command -v cygpath &>/dev/null; then
    py_dest=$(cygpath -m "$dest")
  fi
  python -c "
import json
d = {
  'project': 'stash-isolation-test',
  'marker': '${marker}',
  'stories': [
    {'id': 'US-A', 'status': 'passed'},
    {'id': 'US-B', 'status': 'in_progress'},
    {'id': 'US-C', 'status': 'pending'}
  ],
  'execution': {
    'mergeStrategy': {
      'rules': [
        {'name': 'dependency_manifest', 'filePattern': 'package.json', 'strategy': 'ours'}
      ],
      'defaultAction': 'escalate'
    }
  },
  'progress': []
}
with open('${py_dest}', 'w') as f:
    json.dump(d, f, indent=2)
"
}

# Helper: read a field from quantum.json via Python
read_json_field() {
  local file_path="$1"
  local py_expr="$2"
  local py_path="$file_path"
  if command -v cygpath &>/dev/null; then
    py_path=$(cygpath -m "$file_path")
  fi
  python -c "
import json, sys
d = json.load(open('${py_path}'))
${py_expr}
"
}

# Helper: set up a temp git repo for merge testing
setup_merge_repo() {
  local repo_dir="$1"
  mkdir -p "$repo_dir"
  cd "$repo_dir" || return 1
  git init --initial-branch=main . >/dev/null 2>&1
  git config user.email "test@test.com"
  git config user.name "Test"

  # Create initial files on main
  echo "initial content" > file.txt
  echo '{"name": "test", "version": "1.0.0"}' > package.json

  # Create quantum.json with initial content (will be committed)
  create_quantum_json_with_marker "$repo_dir/quantum.json" "INITIAL_COMMITTED"

  git add -A >/dev/null 2>&1
  git commit -m "initial commit" >/dev/null 2>&1
}

echo "=== Integration Test: quantum.json Stash Isolation ==="
echo ""

# =========================================================================
# Scenario 1: Tracked quantum.json — clean merge with dirty quantum.json
# =========================================================================
echo "--- Scenario 1: Tracked quantum.json preserved through clean merge ---"

REPO1="$TMPDIR/repo1"
setup_merge_repo "$REPO1"
cd "$REPO1" || exit 1

# Create a feature branch with a non-conflicting change
git checkout -b feature-clean >/dev/null 2>&1
echo "new feature file" > feature.txt
git add feature.txt >/dev/null 2>&1
git commit -m "add feature file" >/dev/null 2>&1

# Back to main -- modify quantum.json to make it dirty (simulating orchestrator update)
git checkout main >/dev/null 2>&1
DIRTY_MARKER="DIRTY_MARKER_SCENARIO_1"
create_quantum_json_with_marker "$REPO1/quantum.json" "$DIRTY_MARKER"

# Verify quantum.json is dirty
DIRTY_STATUS=$(git -C "$REPO1" status --porcelain quantum.json)
assert_contains "quantum.json is dirty before merge" "quantum.json" "$DIRTY_STATUS"

# Run classify_and_merge
classify_and_merge "feature-clean" "$REPO1" "$REPO1/quantum.json" 2>/dev/null
EXIT_CODE=$?
assert_eq "clean merge returns 0" "0" "$EXIT_CODE"

# Verify quantum.json still contains the dirty marker
MARKER_AFTER=$(read_json_field "$REPO1/quantum.json" "print(d.get('marker', ''))")
assert_eq "quantum.json marker preserved after clean merge" "$DIRTY_MARKER" "$MARKER_AFTER"

# Verify quantum.json is valid JSON
assert_valid_json "quantum.json is valid JSON after clean merge" "$REPO1/quantum.json"

# Verify story statuses preserved
STATUS_B=$(read_json_field "$REPO1/quantum.json" "print([s['status'] for s in d['stories'] if s['id']=='US-B'][0])")
assert_eq "US-B status preserved (in_progress)" "in_progress" "$STATUS_B"

# Verify no stash artifacts
STASH_LIST=$(git -C "$REPO1" stash list 2>/dev/null)
assert_not_contains "no ql-auto-stash in stash list" "ql-auto-stash" "$STASH_LIST"

# Verify no .merge-bak file remains
assert_file_not_exists "no .merge-bak file remains" "$REPO1/quantum.json.merge-bak"

echo ""

# =========================================================================
# Scenario 2: Tracked quantum.json — conflict merge (escalation) with dirty quantum.json
# =========================================================================
echo "--- Scenario 2: Tracked quantum.json preserved through escalated merge ---"

REPO2="$TMPDIR/repo2"
setup_merge_repo "$REPO2"
cd "$REPO2" || exit 1

# Create a feature branch that modifies file.txt (will conflict)
git checkout -b feature-conflict >/dev/null 2>&1
echo "feature version" > file.txt
git add -A >/dev/null 2>&1
git commit -m "feature change to file.txt" >/dev/null 2>&1

# Back to main -- create a conflicting change AND make quantum.json dirty
git checkout main >/dev/null 2>&1
echo "main version" > file.txt
git add -A >/dev/null 2>&1
git commit -m "main change to file.txt" >/dev/null 2>&1

# Now dirty quantum.json (orchestrator update)
DIRTY_MARKER_2="DIRTY_MARKER_SCENARIO_2"
create_quantum_json_with_marker "$REPO2/quantum.json" "$DIRTY_MARKER_2"

# Run classify_and_merge (file.txt will conflict and escalate since it matches no rule)
classify_and_merge "feature-conflict" "$REPO2" "$REPO2/quantum.json" 2>/dev/null
EXIT_CODE=$?
assert_eq "escalation returns 1" "1" "$EXIT_CODE"

# Verify quantum.json preserved after aborted merge
MARKER_AFTER_2=$(read_json_field "$REPO2/quantum.json" "print(d.get('marker', ''))")
assert_eq "quantum.json marker preserved after escalated merge" "$DIRTY_MARKER_2" "$MARKER_AFTER_2"

# Verify quantum.json is valid JSON
assert_valid_json "quantum.json is valid JSON after escalated merge" "$REPO2/quantum.json"

# Verify story statuses preserved
STATUS_C=$(read_json_field "$REPO2/quantum.json" "print([s['status'] for s in d['stories'] if s['id']=='US-C'][0])")
assert_eq "US-C status preserved (pending)" "pending" "$STATUS_C"

# Verify no stash artifacts
STASH_LIST_2=$(git -C "$REPO2" stash list 2>/dev/null)
assert_not_contains "no ql-auto-stash in stash list after escalation" "ql-auto-stash" "$STASH_LIST_2"

# Verify no .merge-bak file remains
assert_file_not_exists "no .merge-bak file after escalation" "$REPO2/quantum.json.merge-bak"

echo ""

# =========================================================================
# Scenario 3: Tracked quantum.json — resolved conflict with dirty quantum.json
# =========================================================================
echo "--- Scenario 3: Tracked quantum.json preserved through resolved conflict ---"

REPO3="$TMPDIR/repo3"
setup_merge_repo "$REPO3"
cd "$REPO3" || exit 1

# Create a feature branch that modifies package.json (will conflict but auto-resolve via ours)
git checkout -b feature-resolved >/dev/null 2>&1
echo '{"name": "test", "version": "2.0.0"}' > package.json
git add -A >/dev/null 2>&1
git commit -m "feature change to package.json" >/dev/null 2>&1

# Back to main -- create a conflicting change to package.json
git checkout main >/dev/null 2>&1
echo '{"name": "test", "version": "1.1.0"}' > package.json
git add -A >/dev/null 2>&1
git commit -m "main change to package.json" >/dev/null 2>&1

# Dirty quantum.json
DIRTY_MARKER_3="DIRTY_MARKER_SCENARIO_3"
create_quantum_json_with_marker "$REPO3/quantum.json" "$DIRTY_MARKER_3"

# Run classify_and_merge (package.json -> dependency_manifest:ours, auto-resolved)
classify_and_merge "feature-resolved" "$REPO3" "$REPO3/quantum.json" 2>/dev/null
EXIT_CODE=$?
assert_eq "resolved conflict returns 0" "0" "$EXIT_CODE"

# Verify quantum.json preserved
MARKER_AFTER_3=$(read_json_field "$REPO3/quantum.json" "print(d.get('marker', ''))")
assert_eq "quantum.json marker preserved after resolved conflict" "$DIRTY_MARKER_3" "$MARKER_AFTER_3"

assert_valid_json "quantum.json is valid JSON after resolved conflict" "$REPO3/quantum.json"

# Verify no stash artifacts
STASH_LIST_3=$(git -C "$REPO3" stash list 2>/dev/null)
assert_not_contains "no ql-auto-stash in stash list after resolved conflict" "ql-auto-stash" "$STASH_LIST_3"

assert_file_not_exists "no .merge-bak file after resolved conflict" "$REPO3/quantum.json.merge-bak"

echo ""

# =========================================================================
# Scenario 4: quantum.json in .gitignore (untracked) — clean merge
# =========================================================================
echo "--- Scenario 4: Untracked quantum.json (.gitignored) preserved through clean merge ---"

REPO4="$TMPDIR/repo4"
mkdir -p "$REPO4"
cd "$REPO4" || exit 1
git init --initial-branch=main . >/dev/null 2>&1
git config user.email "test@test.com"
git config user.name "Test"

# Create .gitignore that excludes quantum.json
echo "quantum.json" > .gitignore
echo "initial content" > file.txt
git add .gitignore file.txt >/dev/null 2>&1
git commit -m "initial commit with gitignore" >/dev/null 2>&1

# Create quantum.json (untracked due to .gitignore)
DIRTY_MARKER_4="DIRTY_MARKER_GITIGNORED"
create_quantum_json_with_marker "$REPO4/quantum.json" "$DIRTY_MARKER_4"

# Verify quantum.json is untracked/ignored
TRACKED=$(git -C "$REPO4" ls-files quantum.json)
assert_eq "quantum.json is not tracked (gitignored)" "" "$TRACKED"

# Create a feature branch with a non-conflicting change
git checkout -b feature-ignored >/dev/null 2>&1
echo "feature content" > feature.txt
git add feature.txt >/dev/null 2>&1
git commit -m "add feature.txt" >/dev/null 2>&1

git checkout main >/dev/null 2>&1

# Run classify_and_merge
classify_and_merge "feature-ignored" "$REPO4" "$REPO4/quantum.json" 2>/dev/null
EXIT_CODE=$?
assert_eq "clean merge with gitignored quantum.json returns 0" "0" "$EXIT_CODE"

# Verify quantum.json preserved
MARKER_AFTER_4=$(read_json_field "$REPO4/quantum.json" "print(d.get('marker', ''))")
assert_eq "gitignored quantum.json marker preserved" "$DIRTY_MARKER_4" "$MARKER_AFTER_4"

assert_valid_json "gitignored quantum.json is valid JSON" "$REPO4/quantum.json"

# Verify no stash artifacts
STASH_LIST_4=$(git -C "$REPO4" stash list 2>/dev/null)
assert_not_contains "no ql-auto-stash with gitignored quantum.json" "ql-auto-stash" "$STASH_LIST_4"

assert_file_not_exists "no .merge-bak file with gitignored quantum.json" "$REPO4/quantum.json.merge-bak"

echo ""

# =========================================================================
# Scenario 5: quantum.json in .gitignore — escalated merge
# =========================================================================
echo "--- Scenario 5: Untracked quantum.json (.gitignored) preserved through escalated merge ---"

REPO5="$TMPDIR/repo5"
mkdir -p "$REPO5"
cd "$REPO5" || exit 1
git init --initial-branch=main . >/dev/null 2>&1
git config user.email "test@test.com"
git config user.name "Test"

echo "quantum.json" > .gitignore
echo "initial content" > file.txt
git add .gitignore file.txt >/dev/null 2>&1
git commit -m "initial commit" >/dev/null 2>&1

# Create quantum.json (untracked)
DIRTY_MARKER_5="DIRTY_MARKER_GITIGNORED_ESCALATION"
create_quantum_json_with_marker "$REPO5/quantum.json" "$DIRTY_MARKER_5"

# Feature branch: modify file.txt (will conflict)
git checkout -b feature-conflict-ignored >/dev/null 2>&1
echo "feature version" > file.txt
git add -A >/dev/null 2>&1
git commit -m "feature file change" >/dev/null 2>&1

# Back to main with conflicting change
git checkout main >/dev/null 2>&1
echo "main version" > file.txt
git add -A >/dev/null 2>&1
git commit -m "main file change" >/dev/null 2>&1

# Run classify_and_merge
classify_and_merge "feature-conflict-ignored" "$REPO5" "$REPO5/quantum.json" 2>/dev/null
EXIT_CODE=$?
assert_eq "escalation with gitignored quantum.json returns 1" "1" "$EXIT_CODE"

# Verify quantum.json preserved after abort
MARKER_AFTER_5=$(read_json_field "$REPO5/quantum.json" "print(d.get('marker', ''))")
assert_eq "gitignored quantum.json marker preserved after escalation" "$DIRTY_MARKER_5" "$MARKER_AFTER_5"

assert_valid_json "gitignored quantum.json is valid JSON after escalation" "$REPO5/quantum.json"

STASH_LIST_5=$(git -C "$REPO5" stash list 2>/dev/null)
assert_not_contains "no ql-auto-stash with gitignored escalation" "ql-auto-stash" "$STASH_LIST_5"

assert_file_not_exists "no .merge-bak after gitignored escalation" "$REPO5/quantum.json.merge-bak"

echo ""

# =========================================================================
# Scenario 6: Tracked quantum.json — clean working tree (no stash needed)
# =========================================================================
echo "--- Scenario 6: Clean working tree — no stash needed, quantum.json untouched ---"

REPO6="$TMPDIR/repo6"
setup_merge_repo "$REPO6"
cd "$REPO6" || exit 1

# Feature branch with non-conflicting change
git checkout -b feature-clean-wt >/dev/null 2>&1
echo "feature content" > feature.txt
git add feature.txt >/dev/null 2>&1
git commit -m "add feature" >/dev/null 2>&1

git checkout main >/dev/null 2>&1

# Verify working tree is clean (quantum.json is committed)
CLEAN_STATUS=$(git -C "$REPO6" status --porcelain)
assert_eq "working tree is clean before merge" "" "$CLEAN_STATUS"

# Read the committed quantum.json marker
COMMITTED_MARKER=$(read_json_field "$REPO6/quantum.json" "print(d.get('marker', ''))")

# Run classify_and_merge
classify_and_merge "feature-clean-wt" "$REPO6" "$REPO6/quantum.json" 2>/dev/null
EXIT_CODE=$?
assert_eq "clean merge with clean working tree returns 0" "0" "$EXIT_CODE"

# Verify quantum.json content matches what was committed (backup restores it)
MARKER_AFTER_6=$(read_json_field "$REPO6/quantum.json" "print(d.get('marker', ''))")
assert_eq "quantum.json marker matches committed state" "$COMMITTED_MARKER" "$MARKER_AFTER_6"

STASH_LIST_6=$(git -C "$REPO6" stash list 2>/dev/null)
assert_not_contains "no ql-auto-stash with clean working tree" "ql-auto-stash" "$STASH_LIST_6"

assert_file_not_exists "no .merge-bak with clean working tree" "$REPO6/quantum.json.merge-bak"

echo ""

# =========================================================================
# Scenario 7: Additional dirty files alongside quantum.json
# =========================================================================
echo "--- Scenario 7: Other dirty files stashed and restored alongside quantum.json ---"

REPO7="$TMPDIR/repo7"
setup_merge_repo "$REPO7"
cd "$REPO7" || exit 1

# Feature branch
git checkout -b feature-multi-dirty >/dev/null 2>&1
echo "feature content" > feature.txt
git add feature.txt >/dev/null 2>&1
git commit -m "add feature" >/dev/null 2>&1

git checkout main >/dev/null 2>&1

# Dirty both quantum.json and file.txt
DIRTY_MARKER_7="DIRTY_MARKER_MULTI_DIRTY"
create_quantum_json_with_marker "$REPO7/quantum.json" "$DIRTY_MARKER_7"
echo "dirty local change" > "$REPO7/file.txt"

# Verify both are dirty
DIRTY_FILES=$(git -C "$REPO7" status --porcelain | wc -l | tr -d ' ')
TOTAL=$((TOTAL + 1))
if [[ "$DIRTY_FILES" -ge 2 ]]; then
  echo "  PASS: multiple files dirty before merge"
  PASS=$((PASS + 1))
else
  echo "  FAIL: expected >= 2 dirty files, got $DIRTY_FILES"
  FAIL=$((FAIL + 1))
fi

classify_and_merge "feature-multi-dirty" "$REPO7" "$REPO7/quantum.json" 2>/dev/null
EXIT_CODE=$?
assert_eq "merge with multiple dirty files returns 0" "0" "$EXIT_CODE"

# Verify quantum.json preserved
MARKER_AFTER_7=$(read_json_field "$REPO7/quantum.json" "print(d.get('marker', ''))")
assert_eq "quantum.json marker preserved with other dirty files" "$DIRTY_MARKER_7" "$MARKER_AFTER_7"

# Verify no stash artifacts
STASH_LIST_7=$(git -C "$REPO7" stash list 2>/dev/null)
assert_not_contains "no ql-auto-stash with multiple dirty files" "ql-auto-stash" "$STASH_LIST_7"

assert_file_not_exists "no .merge-bak with multiple dirty files" "$REPO7/quantum.json.merge-bak"

echo ""

# =========================================================================
# Summary
# =========================================================================
cd "$ORIG_DIR" || true
echo "=========================================="
echo "=== Results: $PASS/$TOTAL passed, $FAIL failed ==="
echo "=========================================="
if [[ $FAIL -eq 0 ]]; then
  exit 0
else
  exit 1
fi
