#!/usr/bin/env bash
# Test suite for lib/worktree.sh
# Tests worktree creation, removal, and listing using a temporary git repo

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="$SCRIPT_DIR/../lib"
PASS=0
FAIL=0
TOTAL=0

# Source the library under test
if [[ ! -f "$LIB_DIR/worktree.sh" ]]; then
  echo "SKIP: lib/worktree.sh not found (RED phase)"
  exit 1
fi
source "$LIB_DIR/worktree.sh"

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

# =========================================================================
# Setup: create a temporary git repo for testing
# =========================================================================
TMPDIR=$(mktemp -d)
ORIG_DIR=$(pwd)

setup_test_repo() {
  cd "$TMPDIR"
  git init --initial-branch=main . >/dev/null 2>&1
  git config user.email "test@test.com"
  git config user.name "Test"
  echo "initial" > file.txt
  git add file.txt
  git commit -m "initial commit" >/dev/null 2>&1
  # Create a feature branch to simulate ql/parallel-execution
  git checkout -b ql/test-feature >/dev/null 2>&1
  echo "feature work" > feature.txt
  git add feature.txt
  git commit -m "feature commit" >/dev/null 2>&1
}

cleanup_test_repo() {
  cd "$ORIG_DIR"
  # Force remove worktrees before deleting the temp dir
  if [[ -d "$TMPDIR" ]]; then
    cd "$TMPDIR" 2>/dev/null && git worktree list --porcelain 2>/dev/null | grep "^worktree " | while read -r _ path; do
      if [[ "$path" != "$TMPDIR" ]]; then
        git worktree remove --force "$path" 2>/dev/null || true
      fi
    done
    cd "$ORIG_DIR"
    rm -rf "$TMPDIR"
  fi
}

trap cleanup_test_repo EXIT

setup_test_repo

# =========================================================================
echo "=== Test 1: Create worktree at correct path ==="
RESULT=$(create_worktree "US-001" "ql/test-feature" "$TMPDIR")
EXIT_CODE=$?
assert_eq "create_worktree exits 0" "0" "$EXIT_CODE"
assert_dir_exists "Worktree directory created" "$TMPDIR/.ql-wt/US-001"

# =========================================================================
echo "=== Test 2: Worktree has feature branch content ==="
assert_eq "Feature file exists in worktree" "0" "$(test -f "$TMPDIR/.ql-wt/US-001/feature.txt" && echo 0 || echo 1)"

# =========================================================================
echo "=== Test 3: List worktrees includes the new worktree ==="
WORKTREES=$(list_worktrees "$TMPDIR")
assert_contains "US-001 worktree listed" "US-001" "$WORKTREES"

# =========================================================================
echo "=== Test 4: Remove worktree cleans up ==="
remove_worktree "US-001" "$TMPDIR"
EXIT_CODE=$?
assert_eq "remove_worktree exits 0" "0" "$EXIT_CODE"
assert_dir_not_exists "Worktree directory removed" "$TMPDIR/.ql-wt/US-001"

# =========================================================================
echo "=== Test 5: List worktrees after removal ==="
WORKTREES=$(list_worktrees "$TMPDIR")
TOTAL=$((TOTAL + 1))
if echo "$WORKTREES" | grep -q "US-001"; then
  echo "  FAIL: US-001 should not be listed after removal"
  FAIL=$((FAIL + 1))
else
  echo "  PASS: US-001 not listed after removal"
  PASS=$((PASS + 1))
fi

# =========================================================================
echo "=== Test 6: Remove nonexistent worktree is idempotent ==="
remove_worktree "US-999" "$TMPDIR" 2>/dev/null
EXIT_CODE=$?
assert_eq "remove_worktree for nonexistent exits 0" "0" "$EXIT_CODE"

# =========================================================================
echo "=== Test 7: _resolve_repo_root from main repo returns itself ==="
RESOLVED=$(_resolve_repo_root "$TMPDIR")
assert_eq "_resolve_repo_root main repo is identity" "$TMPDIR" "$RESOLVED"

# =========================================================================
echo "=== Test 8: _resolve_repo_root from inside worktree returns main root ==="
# Create a worktree to test from
create_worktree "US-resolve" "ql/test-feature" "$TMPDIR" >/dev/null 2>&1
WT_RESOLVE="$TMPDIR/.ql-wt/US-resolve"
if [[ -d "$WT_RESOLVE" ]]; then
  RESOLVED=$(_resolve_repo_root "$WT_RESOLVE")
  assert_eq "_resolve_repo_root from worktree returns main root" "$TMPDIR" "$RESOLVED"
  remove_worktree "US-resolve" "$TMPDIR" >/dev/null 2>&1
else
  TOTAL=$((TOTAL + 1))
  echo "  FAIL: Could not create worktree for _resolve_repo_root test"
  FAIL=$((FAIL + 1))
fi

# =========================================================================
echo "=== Test 9: create_worktree from nested path roots at top level ==="
create_worktree "US-outer" "ql/test-feature" "$TMPDIR" >/dev/null 2>&1
NESTED_ROOT="$TMPDIR/.ql-wt/US-outer"
if [[ -d "$NESTED_ROOT" ]]; then
  create_worktree "US-inner" "ql/test-feature" "$NESTED_ROOT" >/dev/null 2>&1
  # Should land under main repo root, NOT double-nested
  assert_dir_exists "US-inner under main root" "$TMPDIR/.ql-wt/US-inner"
  assert_dir_not_exists "US-inner NOT nested inside US-outer" "$NESTED_ROOT/.ql-wt/US-inner"
  remove_worktree "US-inner" "$TMPDIR" >/dev/null 2>&1
  remove_worktree "US-outer" "$TMPDIR" >/dev/null 2>&1
else
  TOTAL=$((TOTAL + 1))
  echo "  FAIL: Could not create outer worktree for nesting test"
  FAIL=$((FAIL + 1))
fi

# =========================================================================
echo "=== Test 10: _short_path_base is deterministic ==="
BASE1=$(_short_path_base "$TMPDIR")
BASE2=$(_short_path_base "$TMPDIR")
assert_eq "_short_path_base deterministic" "$BASE1" "$BASE2"
assert_contains "_short_path_base has ql-wt prefix" "ql-wt-" "$BASE1"

# =========================================================================
echo "=== Test 11: _short_path_base differs per repo root ==="
BASE_A=$(_short_path_base "/tmp/repo-a")
BASE_B=$(_short_path_base "/tmp/repo-b")
TOTAL=$((TOTAL + 1))
if [[ "$BASE_A" != "$BASE_B" ]]; then
  echo "  PASS: Different repos get different short paths"
  PASS=$((PASS + 1))
else
  echo "  FAIL: Same short path for different repos: $BASE_A"
  FAIL=$((FAIL + 1))
fi

# =========================================================================
# Tests for lifecycle tracking functions (T-011, T-012, T-013)
# =========================================================================

# Helper: read a JSON value via Python (handles Windows path translation)
_read_json_py() {
  local json_file="$1"
  local py_expr="$2"
  local py_path
  py_path=$(_to_python_path "$json_file")
  python -c "
import json, sys
d = json.load(open(sys.argv[1]))
$py_expr
" "$py_path"
}

# --- T-011: register_worktree ---
echo "=== Test 12: register_worktree adds entry to quantum.json ==="
# Create a minimal quantum.json for testing
TEST_JSON="$TMPDIR/quantum.json"
cat > "$TEST_JSON" <<'ENDJSON'
{
  "stories": [
    {"id": "US-001", "status": "in_progress"}
  ]
}
ENDJSON

register_worktree "$TEST_JSON" "US-001" "$TMPDIR/.ql-wt/US-001" "ql/test-feature" 1 2>/dev/null
EXIT_CODE=$?
assert_eq "register_worktree exits 0" "0" "$EXIT_CODE"

# Verify the entry was added to worktreeTracking
REG_STORY_ID=$(_read_json_py "$TEST_JSON" "
wts = d.get('execution', {}).get('worktreeTracking', {}).get('activeWorktrees', [])
print(wts[0]['storyId'] if wts else '')
")
assert_eq "register_worktree sets storyId" "US-001" "$REG_STORY_ID"

REG_BRANCH=$(_read_json_py "$TEST_JSON" "
wts = d.get('execution', {}).get('worktreeTracking', {}).get('activeWorktrees', [])
print(wts[0]['branch'] if wts else '')
")
assert_eq "register_worktree sets branch" "ql/test-feature" "$REG_BRANCH"

REG_WAVE=$(_read_json_py "$TEST_JSON" "
wts = d.get('execution', {}).get('worktreeTracking', {}).get('activeWorktrees', [])
print(wts[0]['wave'] if wts else '')
")
assert_eq "register_worktree sets wave" "1" "$REG_WAVE"

REG_HAS_CREATED_AT=$(_read_json_py "$TEST_JSON" "
wts = d.get('execution', {}).get('worktreeTracking', {}).get('activeWorktrees', [])
print('yes' if wts and wts[0].get('createdAt') else 'no')
")
assert_eq "register_worktree sets createdAt" "yes" "$REG_HAS_CREATED_AT"

echo "=== Test 13: register_worktree validates story_id ==="
register_worktree "$TEST_JSON" "" "$TMPDIR/.ql-wt/US-002" "ql/test" 1 2>/dev/null
EXIT_CODE=$?
assert_eq "register_worktree rejects empty story_id" "1" "$EXIT_CODE"

register_worktree "$TEST_JSON" "US/../bad" "$TMPDIR/.ql-wt/bad" "ql/test" 1 2>/dev/null
EXIT_CODE=$?
assert_eq "register_worktree rejects invalid story_id" "1" "$EXIT_CODE"

echo "=== Test 14: register_worktree appends to existing entries ==="
register_worktree "$TEST_JSON" "US-002" "$TMPDIR/.ql-wt/US-002" "ql/test-feature" 1 2>/dev/null
ENTRY_COUNT=$(_read_json_py "$TEST_JSON" "
wts = d.get('execution', {}).get('worktreeTracking', {}).get('activeWorktrees', [])
print(len(wts))
")
assert_eq "register_worktree appends (count=2)" "2" "$ENTRY_COUNT"

echo "=== Test 15: register_worktree creates worktreeTracking if absent ==="
# Fresh JSON with no execution field
cat > "$TEST_JSON" <<'ENDJSON'
{
  "stories": [
    {"id": "US-010", "status": "in_progress"}
  ]
}
ENDJSON
register_worktree "$TEST_JSON" "US-010" "$TMPDIR/.ql-wt/US-010" "ql/test" 2 2>/dev/null
EXIT_CODE=$?
assert_eq "register_worktree creates tracking from scratch" "0" "$EXIT_CODE"
REG_COUNT=$(_read_json_py "$TEST_JSON" "
wts = d.get('execution', {}).get('worktreeTracking', {}).get('activeWorktrees', [])
print(len(wts))
")
assert_eq "register_worktree has 1 entry after fresh create" "1" "$REG_COUNT"

echo "=== Test 16: register_worktree requires all parameters ==="
register_worktree "$TEST_JSON" "US-001" "" "ql/test" 1 2>/dev/null
EXIT_CODE=$?
assert_eq "register_worktree rejects empty path" "1" "$EXIT_CODE"

register_worktree "" "US-001" "/some/path" "ql/test" 1 2>/dev/null
EXIT_CODE=$?
assert_eq "register_worktree rejects empty json_path" "1" "$EXIT_CODE"

# --- T-012: cleanup_stale_worktrees ---
echo "=== Test 17: cleanup_stale_worktrees removes passed story worktrees ==="
# Create worktrees for two stories, mark one as passed
create_worktree "US-STALE1" "ql/test-feature" "$TMPDIR" >/dev/null 2>&1
create_worktree "US-STALE2" "ql/test-feature" "$TMPDIR" >/dev/null 2>&1
assert_dir_exists "US-STALE1 worktree exists before cleanup" "$TMPDIR/.ql-wt/US-STALE1"
assert_dir_exists "US-STALE2 worktree exists before cleanup" "$TMPDIR/.ql-wt/US-STALE2"

# Set up quantum.json with tracking and story statuses
cat > "$TEST_JSON" <<'ENDJSON'
{
  "stories": [
    {"id": "US-STALE1", "status": "passed"},
    {"id": "US-STALE2", "status": "in_progress"}
  ],
  "execution": {
    "worktreeTracking": {
      "activeWorktrees": [
        {"path": "PLACEHOLDER_STALE1", "branch": "ql-wt/US-STALE1", "storyId": "US-STALE1", "createdAt": "2026-01-01T00:00:00Z", "wave": 1},
        {"path": "PLACEHOLDER_STALE2", "branch": "ql-wt/US-STALE2", "storyId": "US-STALE2", "createdAt": "2026-01-01T00:00:00Z", "wave": 1}
      ],
      "cleanedThisSession": 0,
      "maxWorktrees": 4
    }
  }
}
ENDJSON
# Fix placeholder paths to actual paths
_PY_TJ=$(_to_python_path "$TEST_JSON")
python -c "
import json, sys
d = json.load(open(sys.argv[1]))
for wt in d['execution']['worktreeTracking']['activeWorktrees']:
    if wt['storyId'] == 'US-STALE1':
        wt['path'] = sys.argv[2] + '/.ql-wt/US-STALE1'
    elif wt['storyId'] == 'US-STALE2':
        wt['path'] = sys.argv[2] + '/.ql-wt/US-STALE2'
json.dump(d, open(sys.argv[1], 'w'), indent=2)
" "$_PY_TJ" "$TMPDIR"

cleanup_stale_worktrees "$TEST_JSON" "$TMPDIR" 2>/dev/null
EXIT_CODE=$?
assert_eq "cleanup_stale_worktrees exits 0" "0" "$EXIT_CODE"
# US-STALE1 (passed) should be removed, US-STALE2 (in_progress) should remain
assert_dir_not_exists "US-STALE1 worktree removed (passed story)" "$TMPDIR/.ql-wt/US-STALE1"
assert_dir_exists "US-STALE2 worktree kept (in_progress story)" "$TMPDIR/.ql-wt/US-STALE2"

# Check activeWorktrees was updated
REMAINING_COUNT=$(_read_json_py "$TEST_JSON" "
wts = d.get('execution', {}).get('worktreeTracking', {}).get('activeWorktrees', [])
print(len(wts))
")
assert_eq "cleanup_stale leaves 1 active worktree" "1" "$REMAINING_COUNT"

CLEANED_COUNT=$(_read_json_py "$TEST_JSON" "
print(d.get('execution', {}).get('worktreeTracking', {}).get('cleanedThisSession', 0))
")
assert_eq "cleanup_stale increments cleanedThisSession" "1" "$CLEANED_COUNT"

# Clean up US-STALE2
remove_worktree "US-STALE2" "$TMPDIR" >/dev/null 2>&1

echo "=== Test 18: cleanup_stale_worktrees also removes failed story worktrees ==="
create_worktree "US-FAIL1" "ql/test-feature" "$TMPDIR" >/dev/null 2>&1
cat > "$TEST_JSON" <<'ENDJSON'
{
  "stories": [
    {"id": "US-FAIL1", "status": "failed"}
  ],
  "execution": {
    "worktreeTracking": {
      "activeWorktrees": [
        {"path": "PLACEHOLDER", "branch": "ql-wt/US-FAIL1", "storyId": "US-FAIL1", "createdAt": "2026-01-01T00:00:00Z", "wave": 1}
      ],
      "cleanedThisSession": 0,
      "maxWorktrees": 4
    }
  }
}
ENDJSON
python -c "
import json, sys
d = json.load(open(sys.argv[1]))
d['execution']['worktreeTracking']['activeWorktrees'][0]['path'] = sys.argv[2] + '/.ql-wt/US-FAIL1'
json.dump(d, open(sys.argv[1], 'w'), indent=2)
" "$_PY_TJ" "$TMPDIR"

cleanup_stale_worktrees "$TEST_JSON" "$TMPDIR" 2>/dev/null
assert_dir_not_exists "US-FAIL1 worktree removed (failed story)" "$TMPDIR/.ql-wt/US-FAIL1"

echo "=== Test 19: cleanup_stale_worktrees fallback when worktreeTracking absent ==="
# Create a worktree but no tracking in JSON -- fallback to list_worktrees
create_worktree "US-NOTRACK" "ql/test-feature" "$TMPDIR" >/dev/null 2>&1
assert_dir_exists "US-NOTRACK exists before fallback cleanup" "$TMPDIR/.ql-wt/US-NOTRACK"
cat > "$TEST_JSON" <<'ENDJSON'
{
  "stories": [
    {"id": "US-NOTRACK", "status": "passed"}
  ]
}
ENDJSON
cleanup_stale_worktrees "$TEST_JSON" "$TMPDIR" 2>/dev/null
EXIT_CODE=$?
assert_eq "cleanup_stale_worktrees fallback exits 0" "0" "$EXIT_CODE"
assert_dir_not_exists "US-NOTRACK removed by fallback cleanup" "$TMPDIR/.ql-wt/US-NOTRACK"

echo "=== Test 20: cleanup_stale_worktrees with no stale worktrees ==="
cat > "$TEST_JSON" <<'ENDJSON'
{
  "stories": [
    {"id": "US-CLEAN", "status": "in_progress"}
  ],
  "execution": {
    "worktreeTracking": {
      "activeWorktrees": [],
      "cleanedThisSession": 0,
      "maxWorktrees": 4
    }
  }
}
ENDJSON
cleanup_stale_worktrees "$TEST_JSON" "$TMPDIR" 2>/dev/null
EXIT_CODE=$?
assert_eq "cleanup_stale with empty list exits 0" "0" "$EXIT_CODE"

# --- T-013: cleanup_merged_worktrees and pre_spawn_check ---
echo "=== Test 21: cleanup_merged_worktrees removes specified story worktrees ==="
create_worktree "US-MERGE1" "ql/test-feature" "$TMPDIR" >/dev/null 2>&1
create_worktree "US-MERGE2" "ql/test-feature" "$TMPDIR" >/dev/null 2>&1
create_worktree "US-MERGE3" "ql/test-feature" "$TMPDIR" >/dev/null 2>&1
assert_dir_exists "US-MERGE1 exists" "$TMPDIR/.ql-wt/US-MERGE1"
assert_dir_exists "US-MERGE2 exists" "$TMPDIR/.ql-wt/US-MERGE2"
assert_dir_exists "US-MERGE3 exists" "$TMPDIR/.ql-wt/US-MERGE3"

cat > "$TEST_JSON" <<'ENDJSON'
{
  "stories": [
    {"id": "US-MERGE1", "status": "passed"},
    {"id": "US-MERGE2", "status": "passed"},
    {"id": "US-MERGE3", "status": "in_progress"}
  ],
  "execution": {
    "worktreeTracking": {
      "activeWorktrees": [
        {"path": "PLACEHOLDER1", "branch": "ql-wt/US-MERGE1", "storyId": "US-MERGE1", "createdAt": "2026-01-01T00:00:00Z", "wave": 1},
        {"path": "PLACEHOLDER2", "branch": "ql-wt/US-MERGE2", "storyId": "US-MERGE2", "createdAt": "2026-01-01T00:00:00Z", "wave": 1},
        {"path": "PLACEHOLDER3", "branch": "ql-wt/US-MERGE3", "storyId": "US-MERGE3", "createdAt": "2026-01-01T00:00:00Z", "wave": 1}
      ],
      "cleanedThisSession": 0,
      "maxWorktrees": 4
    }
  }
}
ENDJSON
python -c "
import json, sys
d = json.load(open(sys.argv[1]))
for wt in d['execution']['worktreeTracking']['activeWorktrees']:
    wt['path'] = sys.argv[2] + '/.ql-wt/' + wt['storyId']
json.dump(d, open(sys.argv[1], 'w'), indent=2)
" "$_PY_TJ" "$TMPDIR"

# Remove only US-MERGE1 and US-MERGE2 (space-separated IDs)
cleanup_merged_worktrees "$TEST_JSON" "$TMPDIR" "US-MERGE1 US-MERGE2" 2>/dev/null
EXIT_CODE=$?
assert_eq "cleanup_merged_worktrees exits 0" "0" "$EXIT_CODE"
assert_dir_not_exists "US-MERGE1 removed by cleanup_merged" "$TMPDIR/.ql-wt/US-MERGE1"
assert_dir_not_exists "US-MERGE2 removed by cleanup_merged" "$TMPDIR/.ql-wt/US-MERGE2"
assert_dir_exists "US-MERGE3 untouched by cleanup_merged" "$TMPDIR/.ql-wt/US-MERGE3"

MERGE_REMAINING=$(_read_json_py "$TEST_JSON" "
wts = d.get('execution', {}).get('worktreeTracking', {}).get('activeWorktrees', [])
print(len(wts))
")
assert_eq "cleanup_merged leaves 1 active worktree" "1" "$MERGE_REMAINING"

# Clean up US-MERGE3
remove_worktree "US-MERGE3" "$TMPDIR" >/dev/null 2>&1

echo "=== Test 22: cleanup_merged_worktrees with empty IDs ==="
cat > "$TEST_JSON" <<'ENDJSON'
{
  "stories": [],
  "execution": {
    "worktreeTracking": {
      "activeWorktrees": [],
      "cleanedThisSession": 0,
      "maxWorktrees": 4
    }
  }
}
ENDJSON
cleanup_merged_worktrees "$TEST_JSON" "$TMPDIR" "" 2>/dev/null
EXIT_CODE=$?
assert_eq "cleanup_merged_worktrees with empty IDs exits 0" "0" "$EXIT_CODE"

echo "=== Test 23: pre_spawn_check returns 0 when under limit ==="
cat > "$TEST_JSON" <<'ENDJSON'
{
  "stories": [
    {"id": "US-PSC1", "status": "in_progress"}
  ],
  "execution": {
    "worktreeTracking": {
      "activeWorktrees": [
        {"path": "/some/path", "branch": "ql-wt/US-PSC1", "storyId": "US-PSC1", "createdAt": "2026-01-01T00:00:00Z", "wave": 1}
      ],
      "cleanedThisSession": 0,
      "maxWorktrees": 4
    }
  }
}
ENDJSON
pre_spawn_check "$TEST_JSON" 4 2>/dev/null
EXIT_CODE=$?
assert_eq "pre_spawn_check under limit returns 0" "0" "$EXIT_CODE"

echo "=== Test 24: pre_spawn_check returns 1 when at limit with no stale ==="
cat > "$TEST_JSON" <<'ENDJSON'
{
  "stories": [
    {"id": "US-P1", "status": "in_progress"},
    {"id": "US-P2", "status": "in_progress"}
  ],
  "execution": {
    "worktreeTracking": {
      "activeWorktrees": [
        {"path": "/a", "branch": "b", "storyId": "US-P1", "createdAt": "2026-01-01T00:00:00Z", "wave": 1},
        {"path": "/b", "branch": "b", "storyId": "US-P2", "createdAt": "2026-01-01T00:00:00Z", "wave": 1}
      ],
      "cleanedThisSession": 0,
      "maxWorktrees": 2
    }
  }
}
ENDJSON
pre_spawn_check "$TEST_JSON" 2 2>/dev/null
EXIT_CODE=$?
assert_eq "pre_spawn_check at limit (no stale) returns 1" "1" "$EXIT_CODE"

echo "=== Test 25: pre_spawn_check cleans stale and returns 0 ==="
create_worktree "US-PSTALE" "ql/test-feature" "$TMPDIR" >/dev/null 2>&1
cat > "$TEST_JSON" <<ENDJSON
{
  "stories": [
    {"id": "US-PSTALE", "status": "passed"},
    {"id": "US-PACTIVE", "status": "in_progress"}
  ],
  "execution": {
    "worktreeTracking": {
      "activeWorktrees": [
        {"path": "$TMPDIR/.ql-wt/US-PSTALE", "branch": "ql-wt/US-PSTALE", "storyId": "US-PSTALE", "createdAt": "2026-01-01T00:00:00Z", "wave": 1},
        {"path": "/some/active", "branch": "ql-wt/US-PACTIVE", "storyId": "US-PACTIVE", "createdAt": "2026-01-01T00:00:00Z", "wave": 1}
      ],
      "cleanedThisSession": 0,
      "maxWorktrees": 2
    }
  }
}
ENDJSON
pre_spawn_check "$TEST_JSON" 2 2>/dev/null
EXIT_CODE=$?
assert_eq "pre_spawn_check cleans stale then returns 0" "0" "$EXIT_CODE"
assert_dir_not_exists "US-PSTALE cleaned by pre_spawn_check" "$TMPDIR/.ql-wt/US-PSTALE"

echo "=== Test 26: pre_spawn_check requires parameters ==="
pre_spawn_check "" 4 2>/dev/null
EXIT_CODE=$?
assert_eq "pre_spawn_check rejects empty json_path" "1" "$EXIT_CODE"

pre_spawn_check "$TEST_JSON" "" 2>/dev/null
EXIT_CODE=$?
assert_eq "pre_spawn_check rejects empty max_worktrees" "1" "$EXIT_CODE"

# =========================================================================
echo ""
echo "=== Results: $PASS/$TOTAL passed, $FAIL failed ==="
if [[ $FAIL -eq 0 ]]; then
  exit 0
else
  exit 1
fi
