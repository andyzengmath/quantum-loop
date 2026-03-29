#!/usr/bin/env bash
# Test suite for lib/init-guard.sh
# Tests environment detection, warnings, cleanup, and preflight functions

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="$SCRIPT_DIR/../lib"
PASS=0
FAIL=0
TOTAL=0

# Source the library under test
if [[ ! -f "$LIB_DIR/init-guard.sh" ]]; then
  echo "SKIP: lib/init-guard.sh not found (RED phase)"
  exit 1
fi
source "$LIB_DIR/init-guard.sh"

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
  if echo "$haystack" | grep -q "$needle"; then
    echo "  FAIL: $test_name"
    echo "    should NOT contain: $needle"
    echo "    actual: $haystack"
    FAIL=$((FAIL + 1))
  else
    echo "  PASS: $test_name"
    PASS=$((PASS + 1))
  fi
}

# =========================================================================
# T-001 Tests: detect_environment()
# =========================================================================

echo "=== Test 1: detect_environment returns no long_path/onedrive for short normal path ==="
RESULT=$(detect_environment "/tmp/repo")
assert_not_contains "short normal path no long_path" "long_path" "$RESULT"
assert_not_contains "short normal path no onedrive" "onedrive_long_path" "$RESULT"
assert_not_contains "short normal path no tmpdir issue" "tmpdir_not_writable" "$RESULT"

echo "=== Test 2: detect_environment detects long path (>150 chars) ==="
LONG_PATH="/tmp/$(printf 'a%.0s' {1..160})"
RESULT=$(detect_environment "$LONG_PATH")
assert_contains "long path detected" "long_path" "$RESULT"

echo "=== Test 3: detect_environment detects OneDrive path (case insensitive) ==="
RESULT=$(detect_environment "/c/Users/test/OneDrive/repo")
assert_contains "OneDrive detected" "onedrive_long_path" "$RESULT"

echo "=== Test 4: detect_environment detects onedrive lowercase ==="
RESULT=$(detect_environment "/c/Users/test/onedrive/repo")
assert_contains "onedrive lowercase detected" "onedrive_long_path" "$RESULT"

echo "=== Test 5: detect_environment detects ONEDRIVE uppercase ==="
RESULT=$(detect_environment "/c/Users/test/ONEDRIVE/repo")
assert_contains "ONEDRIVE uppercase detected" "onedrive_long_path" "$RESULT"

echo "=== Test 6: detect_environment pipe-delimited with multiple codes ==="
# A path that is both long AND has OneDrive
LONG_OD_PATH="/c/Users/test/OneDrive/$(printf 'a%.0s' {1..160})"
RESULT=$(detect_environment "$LONG_OD_PATH")
assert_contains "long_path in combined" "long_path" "$RESULT"
assert_contains "onedrive in combined" "onedrive_long_path" "$RESULT"
# Verify pipe delimiter
TOTAL=$((TOTAL + 1))
if echo "$RESULT" | grep -q "|"; then
  echo "  PASS: pipe delimiter present in combined result"
  PASS=$((PASS + 1))
else
  echo "  FAIL: pipe delimiter missing in combined result: $RESULT"
  FAIL=$((FAIL + 1))
fi

echo "=== Test 7: detect_environment detects Windows via uname/MSYSTEM ==="
# On this Windows machine, we should get 'windows'
if [[ "$(uname -s 2>/dev/null)" == MINGW* ]] || [[ "$(uname -s 2>/dev/null)" == MSYS* ]] || [[ -n "$MSYSTEM" ]]; then
  RESULT=$(detect_environment "/tmp/repo")
  assert_contains "windows detected on Windows" "windows" "$RESULT"
else
  echo "  SKIP: Not on Windows, skipping Windows detection test"
  TOTAL=$((TOTAL + 1))
  PASS=$((PASS + 1))
fi

echo "=== Test 8: detect_environment tmpdir writability check ==="
# With a writable tmpdir, should NOT get tmpdir_not_writable
RESULT=$(detect_environment "/tmp/repo")
assert_not_contains "writable tmpdir not flagged" "tmpdir_not_writable" "$RESULT"

echo "=== Test 9: detect_environment with empty path ==="
RESULT=$(detect_environment "")
# Empty path is short, so no long_path
assert_not_contains "empty path no long_path" "long_path" "$RESULT"

echo "=== Test 10: detect_environment with exactly 150 chars ==="
# 150 chars should NOT trigger long_path (only >150)
PATH_150="/tmp/$(printf 'x%.0s' {1..145})"
RESULT=$(detect_environment "$PATH_150")
assert_not_contains "exactly 150 chars not flagged" "long_path" "$RESULT"

echo "=== Test 11: detect_environment with 151 chars triggers long_path ==="
PATH_151="/tmp/$(printf 'x%.0s' {1..146})"
RESULT=$(detect_environment "$PATH_151")
assert_contains "151 chars triggers long_path" "long_path" "$RESULT"

# =========================================================================
# T-002 Tests: warn_long_path() and prune_stale_refs()
# =========================================================================

echo "=== Test 12: warn_long_path with OneDrive path logs OneDrive warning ==="
OUTPUT=$(warn_long_path "/c/Users/test/OneDrive/my-repo" 2>&1)
assert_contains "OneDrive warning logged" "INIT-GUARD" "$OUTPUT"
assert_contains "OneDrive warning mentions OneDrive" "OneDrive" "$OUTPUT"
assert_contains "OneDrive warning has WARN" "WARN" "$OUTPUT"

echo "=== Test 13: warn_long_path with non-OneDrive path logs generic warning ==="
LONG_NOD="/tmp/$(printf 'a%.0s' {1..160})"
OUTPUT=$(warn_long_path "$LONG_NOD" 2>&1)
assert_contains "generic warning logged" "INIT-GUARD" "$OUTPUT"
assert_contains "generic warning has WARN" "WARN" "$OUTPUT"
# Should contain path length
assert_contains "generic warning has char count" "chars" "$OUTPUT"

echo "=== Test 14: warn_long_path includes path length in message ==="
OUTPUT=$(warn_long_path "/c/Users/test/OneDrive/my-repo" 2>&1)
assert_contains "path length in message" "chars" "$OUTPUT"

echo "=== Test 15: prune_stale_refs on a clean repo ==="
# Set up temp repo for prune tests
PRUNE_TMPDIR=$(mktemp -d)
PRUNE_ORIG_DIR=$(pwd)
cd "$PRUNE_TMPDIR" || exit 1
git init --initial-branch=main . >/dev/null 2>&1
git config user.email "test@test.com"
git config user.name "Test"
echo "init" > file.txt
git add file.txt
git commit -m "initial" >/dev/null 2>&1
cd "$PRUNE_ORIG_DIR" || exit 1

OUTPUT=$(prune_stale_refs "$PRUNE_TMPDIR" 2>&1)
EXIT_CODE=$?
assert_eq "prune_stale_refs exits 0 on clean repo" "0" "$EXIT_CODE"
# Should log with INIT-GUARD prefix
assert_contains "prune log has prefix" "INIT-GUARD" "$OUTPUT"

echo "=== Test 16: prune_stale_refs returns count on stdout ==="
# Capture just stdout (the count)
COUNT=$(prune_stale_refs "$PRUNE_TMPDIR" 2>/dev/null)
# Count should be a number (0 for clean repo)
TOTAL=$((TOTAL + 1))
if [[ "$COUNT" =~ ^[0-9]+$ ]]; then
  echo "  PASS: prune_stale_refs returns numeric count: $COUNT"
  PASS=$((PASS + 1))
else
  echo "  FAIL: prune_stale_refs did not return numeric count: $COUNT"
  FAIL=$((FAIL + 1))
fi

echo "=== Test 17: prune_stale_refs with stale worktree reference ==="
# Create a worktree then manually remove its directory to create stale ref
cd "$PRUNE_TMPDIR" || exit 1
git checkout -b test-branch >/dev/null 2>&1
echo "branch" > branch.txt
git add branch.txt
git commit -m "branch commit" >/dev/null 2>&1
git checkout main >/dev/null 2>&1
mkdir -p "$PRUNE_TMPDIR/.ql-wt"
git worktree add "$PRUNE_TMPDIR/.ql-wt/stale-wt" test-branch >/dev/null 2>&1
# Remove the directory without git worktree remove (creates stale ref)
rm -rf "$PRUNE_TMPDIR/.ql-wt/stale-wt"
cd "$PRUNE_ORIG_DIR" || exit 1

COUNT=$(prune_stale_refs "$PRUNE_TMPDIR" 2>/dev/null)
EXIT_CODE=$?
assert_eq "prune with stale exits 0" "0" "$EXIT_CODE"

echo "=== Test 18: prune_stale_refs with empty repo_root ==="
OUTPUT=$(prune_stale_refs "" 2>&1)
EXIT_CODE=$?
assert_eq "prune with empty repo_root fails" "1" "$EXIT_CODE"

# Clean up prune test repo
rm -rf "$PRUNE_TMPDIR"

# =========================================================================
# T-003 Tests: cleanup_orphan_dirs()
# =========================================================================

assert_dir_exists() {
  local test_name="$1" dir="$2"
  TOTAL=$((TOTAL + 1))
  if [[ -d "$dir" ]]; then
    echo "  PASS: $test_name"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: $test_name (directory not found: $dir)"
    FAIL=$((FAIL + 1))
  fi
}

assert_dir_not_exists() {
  local test_name="$1" dir="$2"
  TOTAL=$((TOTAL + 1))
  if [[ ! -d "$dir" ]]; then
    echo "  PASS: $test_name"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: $test_name (directory still exists: $dir)"
    FAIL=$((FAIL + 1))
  fi
}

echo "=== Test 19: cleanup_orphan_dirs removes clean orphan directory ==="
# Set up a test repo with a worktree dir that is NOT in git worktree list
ORPHAN_TMPDIR=$(mktemp -d)
ORPHAN_ORIG_DIR=$(pwd)
cd "$ORPHAN_TMPDIR" || exit 1
git init --initial-branch=main . >/dev/null 2>&1
git config user.email "test@test.com"
git config user.name "Test"
echo "init" > file.txt
git add file.txt
git commit -m "initial" >/dev/null 2>&1
cd "$ORPHAN_ORIG_DIR" || exit 1

# Create an orphan directory under .ql-wt (not a real git worktree)
mkdir -p "$ORPHAN_TMPDIR/.ql-wt/orphan-clean"
echo "leftover" > "$ORPHAN_TMPDIR/.ql-wt/orphan-clean/file.txt"

COUNT=$(cleanup_orphan_dirs "$ORPHAN_TMPDIR" 2>/dev/null)
EXIT_CODE=$?
assert_eq "cleanup_orphan_dirs exits 0" "0" "$EXIT_CODE"
assert_dir_not_exists "clean orphan removed" "$ORPHAN_TMPDIR/.ql-wt/orphan-clean"

echo "=== Test 20: cleanup_orphan_dirs preserves dirty orphan (uncommitted changes) ==="
# Create a new orphan directory with a git repo that has uncommitted changes
mkdir -p "$ORPHAN_TMPDIR/.ql-wt/orphan-dirty"
cd "$ORPHAN_TMPDIR/.ql-wt/orphan-dirty" || exit 1
git init --initial-branch=main . >/dev/null 2>&1
git config user.email "test@test.com"
git config user.name "Test"
echo "initial" > committed.txt
git add committed.txt
git commit -m "committed" >/dev/null 2>&1
echo "uncommitted changes" > dirty.txt
git add dirty.txt
cd "$ORPHAN_ORIG_DIR" || exit 1

COUNT=$(cleanup_orphan_dirs "$ORPHAN_TMPDIR" 2>/dev/null)
EXIT_CODE=$?
assert_eq "cleanup_orphan_dirs with dirty exits 0" "0" "$EXIT_CODE"
assert_dir_exists "dirty orphan preserved" "$ORPHAN_TMPDIR/.ql-wt/orphan-dirty"

echo "=== Test 21: cleanup_orphan_dirs returns cleaned count ==="
# Create two clean orphan dirs
rm -rf "$ORPHAN_TMPDIR/.ql-wt/orphan-dirty"
mkdir -p "$ORPHAN_TMPDIR/.ql-wt/clean1"
echo "x" > "$ORPHAN_TMPDIR/.ql-wt/clean1/file.txt"
mkdir -p "$ORPHAN_TMPDIR/.ql-wt/clean2"
echo "y" > "$ORPHAN_TMPDIR/.ql-wt/clean2/file.txt"

COUNT=$(cleanup_orphan_dirs "$ORPHAN_TMPDIR" 2>/dev/null)
assert_eq "cleanup returns count of 2" "2" "$COUNT"
assert_dir_not_exists "clean1 removed" "$ORPHAN_TMPDIR/.ql-wt/clean1"
assert_dir_not_exists "clean2 removed" "$ORPHAN_TMPDIR/.ql-wt/clean2"

echo "=== Test 22: cleanup_orphan_dirs with no .ql-wt dir ==="
rm -rf "$ORPHAN_TMPDIR/.ql-wt"
COUNT=$(cleanup_orphan_dirs "$ORPHAN_TMPDIR" 2>/dev/null)
EXIT_CODE=$?
assert_eq "cleanup with no .ql-wt exits 0" "0" "$EXIT_CODE"
assert_eq "cleanup with no .ql-wt returns 0" "0" "$COUNT"

echo "=== Test 23: cleanup_orphan_dirs with empty repo_root ==="
OUTPUT=$(cleanup_orphan_dirs "" 2>&1)
EXIT_CODE=$?
assert_eq "cleanup with empty repo_root fails" "1" "$EXIT_CODE"

echo "=== Test 24: cleanup_orphan_dirs preserves real worktree ==="
# Create a real worktree and verify it is NOT removed
cd "$ORPHAN_TMPDIR" || exit 1
git checkout -b real-wt-branch >/dev/null 2>&1
echo "branch" > branch.txt
git add branch.txt
git commit -m "branch" >/dev/null 2>&1
git checkout main >/dev/null 2>&1
mkdir -p "$ORPHAN_TMPDIR/.ql-wt"
git worktree add "$ORPHAN_TMPDIR/.ql-wt/real-wt" real-wt-branch >/dev/null 2>&1
cd "$ORPHAN_ORIG_DIR" || exit 1

# Also add a clean orphan to verify it gets removed while real one stays
mkdir -p "$ORPHAN_TMPDIR/.ql-wt/orphan-clean"
echo "leftover" > "$ORPHAN_TMPDIR/.ql-wt/orphan-clean/file.txt"

COUNT=$(cleanup_orphan_dirs "$ORPHAN_TMPDIR" 2>/dev/null)
assert_eq "cleanup returns 1 (only orphan)" "1" "$COUNT"
assert_dir_exists "real worktree preserved" "$ORPHAN_TMPDIR/.ql-wt/real-wt"
assert_dir_not_exists "clean orphan removed" "$ORPHAN_TMPDIR/.ql-wt/orphan-clean"

# Clean up
cd "$ORPHAN_TMPDIR" || exit 1
git worktree remove --force "$ORPHAN_TMPDIR/.ql-wt/real-wt" 2>/dev/null
cd "$ORPHAN_ORIG_DIR" || exit 1
rm -rf "$ORPHAN_TMPDIR"

# =========================================================================
# T-004 Tests: run_preflight()
# =========================================================================

# Helper to read JSON fields via Python
_read_json_field() {
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

echo "=== Test 25: run_preflight writes execution.initGuard to quantum.json ==="
PF_TMPDIR=$(mktemp -d)
PF_ORIG_DIR=$(pwd)
cd "$PF_TMPDIR" || exit 1
git init --initial-branch=main . >/dev/null 2>&1
git config user.email "test@test.com"
git config user.name "Test"
echo "init" > file.txt
git add file.txt
git commit -m "initial" >/dev/null 2>&1
cd "$PF_ORIG_DIR" || exit 1

# Create a minimal quantum.json
PF_JSON="$PF_TMPDIR/quantum.json"
cat > "$PF_JSON" <<'ENDJSON'
{
  "stories": [],
  "execution": {}
}
ENDJSON

run_preflight "$PF_TMPDIR" "$PF_JSON" 2>/dev/null
EXIT_CODE=$?
assert_eq "run_preflight exits 0" "0" "$EXIT_CODE"

# Verify execution.initGuard was written
HAS_INIT_GUARD=$(_read_json_field "$PF_JSON" "
ig = d.get('execution', {}).get('initGuard')
print('yes' if ig is not None else 'no')
")
assert_eq "initGuard field exists" "yes" "$HAS_INIT_GUARD"

# Verify ranAt timestamp exists
HAS_RAN_AT=$(_read_json_field "$PF_JSON" "
ig = d.get('execution', {}).get('initGuard', {})
print('yes' if ig.get('ranAt') else 'no')
")
assert_eq "ranAt exists in initGuard" "yes" "$HAS_RAN_AT"

# Verify warnings field exists
HAS_WARNINGS=$(_read_json_field "$PF_JSON" "
ig = d.get('execution', {}).get('initGuard', {})
print('yes' if 'warnings' in ig else 'no')
")
assert_eq "warnings field exists" "yes" "$HAS_WARNINGS"

# Verify prunedWorktrees field exists
HAS_PRUNED=$(_read_json_field "$PF_JSON" "
ig = d.get('execution', {}).get('initGuard', {})
print('yes' if 'prunedWorktrees' in ig else 'no')
")
assert_eq "prunedWorktrees field exists" "yes" "$HAS_PRUNED"

# Verify cleanedOrphans field exists
HAS_CLEANED=$(_read_json_field "$PF_JSON" "
ig = d.get('execution', {}).get('initGuard', {})
print('yes' if 'cleanedOrphans' in ig else 'no')
")
assert_eq "cleanedOrphans field exists" "yes" "$HAS_CLEANED"

echo "=== Test 26: run_preflight is idempotent within 1 hour ==="
# Run again immediately -- should skip (ranAt is recent)
OUTPUT=$(run_preflight "$PF_TMPDIR" "$PF_JSON" 2>&1)
EXIT_CODE=$?
assert_eq "run_preflight idempotent exits 0" "0" "$EXIT_CODE"
assert_contains "idempotent run mentions skip" "skip" "$OUTPUT"

echo "=== Test 27: run_preflight runs again if ranAt is old ==="
# Set ranAt to 2 hours ago
PF_PY_JSON=$(_to_native_path "$PF_JSON")
python -c "
import json, sys, datetime
jp = sys.argv[1]
d = json.load(open(jp))
old_time = (datetime.datetime.now(datetime.timezone.utc) - datetime.timedelta(hours=2)).isoformat()
d['execution']['initGuard']['ranAt'] = old_time
tmp = jp + '.tmp'
json.dump(d, open(tmp, 'w'), indent=2)
import os; os.replace(tmp, jp)
" "$PF_PY_JSON"

OUTPUT=$(run_preflight "$PF_TMPDIR" "$PF_JSON" 2>&1)
EXIT_CODE=$?
assert_eq "run_preflight re-runs after old ranAt" "0" "$EXIT_CODE"
assert_not_contains "re-run does not skip" "skip" "$OUTPUT"

echo "=== Test 28: run_preflight sets forceSequential when tmpdir not writable ==="
# Force tmpdir_not_writable by setting TMPDIR to a non-existent path
SAVED_TMPDIR="${TMPDIR:-}"
export TMPDIR="/nonexistent_path_ql_test_$$"

# Clear existing initGuard so it runs fresh
python -c "
import json, sys
jp = sys.argv[1]
d = json.load(open(jp))
if 'initGuard' in d.get('execution', {}):
    del d['execution']['initGuard']
tmp = jp + '.tmp'
json.dump(d, open(tmp, 'w'), indent=2)
import os; os.replace(tmp, jp)
" "$PF_PY_JSON"

run_preflight "$PF_TMPDIR" "$PF_JSON" 2>/dev/null
FORCE_SEQ=$(_read_json_field "$PF_JSON" "
ig = d.get('execution', {}).get('initGuard', {})
print(ig.get('forceSequential', False))
")
assert_eq "forceSequential is True when tmpdir not writable" "True" "$FORCE_SEQ"

# Restore TMPDIR
if [[ -n "$SAVED_TMPDIR" ]]; then
  export TMPDIR="$SAVED_TMPDIR"
else
  unset TMPDIR
fi

echo "=== Test 29: run_preflight does NOT set forceSequential when tmpdir writable ==="
# Clear initGuard and run with writable tmpdir
python -c "
import json, sys
jp = sys.argv[1]
d = json.load(open(jp))
if 'initGuard' in d.get('execution', {}):
    del d['execution']['initGuard']
tmp = jp + '.tmp'
json.dump(d, open(tmp, 'w'), indent=2)
import os; os.replace(tmp, jp)
" "$PF_PY_JSON"

run_preflight "$PF_TMPDIR" "$PF_JSON" 2>/dev/null
FORCE_SEQ=$(_read_json_field "$PF_JSON" "
ig = d.get('execution', {}).get('initGuard', {})
print(ig.get('forceSequential', False))
")
assert_eq "forceSequential is False when tmpdir writable" "False" "$FORCE_SEQ"

echo "=== Test 30: run_preflight with empty repo_root ==="
OUTPUT=$(run_preflight "" "$PF_JSON" 2>&1)
EXIT_CODE=$?
assert_eq "run_preflight with empty repo_root fails" "1" "$EXIT_CODE"

echo "=== Test 31: run_preflight with empty json_path ==="
OUTPUT=$(run_preflight "$PF_TMPDIR" "" 2>&1)
EXIT_CODE=$?
assert_eq "run_preflight with empty json_path fails" "1" "$EXIT_CODE"

echo "=== Test 32: run_preflight preserves existing execution fields ==="
# Write a quantum.json with existing execution data
cat > "$PF_JSON" <<'ENDJSON'
{
  "stories": [],
  "execution": {
    "mode": "parallel",
    "maxParallel": 4
  }
}
ENDJSON

run_preflight "$PF_TMPDIR" "$PF_JSON" 2>/dev/null
# Verify existing fields are preserved
MODE=$(_read_json_field "$PF_JSON" "
print(d.get('execution', {}).get('mode', ''))
")
assert_eq "existing execution.mode preserved" "parallel" "$MODE"
MAX_P=$(_read_json_field "$PF_JSON" "
print(d.get('execution', {}).get('maxParallel', ''))
")
assert_eq "existing execution.maxParallel preserved" "4" "$MAX_P"

# Clean up
rm -rf "$PF_TMPDIR"

# =========================================================================
echo ""
echo "=== Results: $PASS/$TOTAL passed, $FAIL failed ==="
if [[ $FAIL -eq 0 ]]; then
  exit 0
else
  exit 1
fi
