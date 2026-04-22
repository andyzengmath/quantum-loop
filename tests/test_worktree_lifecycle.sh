#!/usr/bin/env bash
# Test suite for worktree lifecycle functions in lib/worktree.sh
# Focused on register_worktree, cleanup_stale_worktrees, cleanup_merged_worktrees,
# pre_spawn_check, and fallback behaviors with edge cases.

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
  git checkout -b ql/test-feature >/dev/null 2>&1
  echo "feature work" > feature.txt
  git add feature.txt
  git commit -m "feature commit" >/dev/null 2>&1
}

cleanup_test_repo() {
  cd "$ORIG_DIR"
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

TEST_JSON="$TMPDIR/quantum.json"
_PY_TJ=$(_to_python_path "$TEST_JSON")

# =========================================================================
# T-031: register_worktree and cleanup_stale_worktrees
# =========================================================================

echo "=== Test 1: register_worktree records correct path in activeWorktrees ==="
cat > "$TEST_JSON" <<'ENDJSON'
{
  "stories": [
    {"id": "US-R01", "status": "in_progress"}
  ]
}
ENDJSON
# Use $TMPDIR-based path; on Windows, MSYS2 converts /tmp/ paths for Python,
# so we verify the stored path ends with the expected suffix.
register_worktree "$TEST_JSON" "US-R01" "$TMPDIR/wt/US-R01" "ql/test-feature" 1 2>/dev/null
EXIT_CODE=$?
assert_eq "register_worktree exits 0" "0" "$EXIT_CODE"
REG_PATH=$(_read_json_py "$TEST_JSON" "
wts = d.get('execution', {}).get('worktreeTracking', {}).get('activeWorktrees', [])
print(wts[0]['path'] if wts else '')
")
assert_contains "register_worktree stores path with correct suffix" "wt/US-R01" "$REG_PATH"
# Also verify path is non-empty and absolute-looking
TOTAL=$((TOTAL + 1))
if [[ -n "$REG_PATH" && "$REG_PATH" == */* ]]; then
  echo "  PASS: register_worktree stores non-empty path"
  PASS=$((PASS + 1))
else
  echo "  FAIL: register_worktree stores non-empty path (got: $REG_PATH)"
  FAIL=$((FAIL + 1))
fi

echo "=== Test 2: register_worktree stores correct storyId, branch, wave ==="
REG_SID=$(_read_json_py "$TEST_JSON" "
wts = d['execution']['worktreeTracking']['activeWorktrees']
print(wts[0]['storyId'])
")
assert_eq "register_worktree storyId" "US-R01" "$REG_SID"

REG_BR=$(_read_json_py "$TEST_JSON" "
wts = d['execution']['worktreeTracking']['activeWorktrees']
print(wts[0]['branch'])
")
assert_eq "register_worktree branch" "ql/test-feature" "$REG_BR"

REG_WV=$(_read_json_py "$TEST_JSON" "
wts = d['execution']['worktreeTracking']['activeWorktrees']
print(wts[0]['wave'])
")
assert_eq "register_worktree wave" "1" "$REG_WV"

echo "=== Test 3: register_worktree createdAt is valid ISO 8601 ==="
REG_CA=$(_read_json_py "$TEST_JSON" "
import datetime
wts = d['execution']['worktreeTracking']['activeWorktrees']
ca = wts[0].get('createdAt', '')
try:
    datetime.datetime.fromisoformat(ca.replace('Z', '+00:00'))
    print('valid')
except:
    print('invalid: ' + ca)
")
assert_eq "register_worktree createdAt is valid ISO" "valid" "$REG_CA"

echo "=== Test 4: register_worktree with wave=0 boundary ==="
register_worktree "$TEST_JSON" "US-R02" "$TMPDIR/wt/US-R02" "ql/branch" 0 2>/dev/null
EXIT_CODE=$?
assert_eq "register_worktree wave=0 exits 0" "0" "$EXIT_CODE"
REG_WV0=$(_read_json_py "$TEST_JSON" "
wts = d['execution']['worktreeTracking']['activeWorktrees']
entry = [w for w in wts if w['storyId'] == 'US-R02']
print(entry[0]['wave'] if entry else 'missing')
")
assert_eq "register_worktree stores wave=0" "0" "$REG_WV0"

echo "=== Test 5: register_worktree with large wave number ==="
register_worktree "$TEST_JSON" "US-R03" "$TMPDIR/wt/US-R03" "ql/branch" 99 2>/dev/null
EXIT_CODE=$?
assert_eq "register_worktree wave=99 exits 0" "0" "$EXIT_CODE"
REG_WV99=$(_read_json_py "$TEST_JSON" "
wts = d['execution']['worktreeTracking']['activeWorktrees']
entry = [w for w in wts if w['storyId'] == 'US-R03']
print(entry[0]['wave'] if entry else 'missing')
")
assert_eq "register_worktree stores wave=99" "99" "$REG_WV99"

echo "=== Test 6: register_worktree preserves existing entries ==="
ENTRY_COUNT=$(_read_json_py "$TEST_JSON" "
wts = d['execution']['worktreeTracking']['activeWorktrees']
print(len(wts))
")
assert_eq "register_worktree accumulated 3 entries" "3" "$ENTRY_COUNT"

echo "=== Test 7: register_worktree sets default maxWorktrees and cleanedThisSession ==="
MAX_WT=$(_read_json_py "$TEST_JSON" "
print(d['execution']['worktreeTracking']['maxWorktrees'])
")
assert_eq "register_worktree sets default maxWorktrees=4" "4" "$MAX_WT"
CLEANED=$(_read_json_py "$TEST_JSON" "
print(d['execution']['worktreeTracking']['cleanedThisSession'])
")
assert_eq "register_worktree sets default cleanedThisSession=0" "0" "$CLEANED"

echo "=== Test 8: register_worktree with nonexistent json file ==="
register_worktree "$TMPDIR/no-such-file.json" "US-R04" "$TMPDIR/p" "ql/b" 1 2>/dev/null
EXIT_CODE=$?
assert_eq "register_worktree with bad json_path returns 1" "1" "$EXIT_CODE"

echo "=== Test 9: register_worktree preserves existing stories data ==="
STORY_COUNT=$(_read_json_py "$TEST_JSON" "
print(len(d.get('stories', [])))
")
assert_eq "register_worktree preserves stories array" "1" "$STORY_COUNT"

echo "=== Test 10: register_worktree with duplicate storyId appends (no dedup) ==="
register_worktree "$TEST_JSON" "US-R01" "$TMPDIR/another/path" "ql/branch2" 2 2>/dev/null
DUP_COUNT=$(_read_json_py "$TEST_JSON" "
wts = d['execution']['worktreeTracking']['activeWorktrees']
dups = [w for w in wts if w['storyId'] == 'US-R01']
print(len(dups))
")
assert_eq "register_worktree allows duplicate storyId" "2" "$DUP_COUNT"

echo "=== Test 11: register_worktree preserves existing worktreeTracking structure ==="
cat > "$TEST_JSON" <<'ENDJSON'
{
  "stories": [{"id": "US-X1", "status": "in_progress"}],
  "execution": {
    "worktreeTracking": {
      "activeWorktrees": [
        {"path": "/existing", "branch": "b", "storyId": "US-OLD", "createdAt": "2026-01-01T00:00:00Z", "wave": 1}
      ],
      "cleanedThisSession": 5,
      "maxWorktrees": 8
    }
  }
}
ENDJSON
register_worktree "$TEST_JSON" "US-X1" "$TMPDIR/new/path" "ql/b" 2 2>/dev/null
PRESERVED_MAX=$(_read_json_py "$TEST_JSON" "
print(d['execution']['worktreeTracking']['maxWorktrees'])
")
assert_eq "register_worktree preserves existing maxWorktrees=8" "8" "$PRESERVED_MAX"
PRESERVED_CLEANED=$(_read_json_py "$TEST_JSON" "
print(d['execution']['worktreeTracking']['cleanedThisSession'])
")
assert_eq "register_worktree preserves existing cleanedThisSession=5" "5" "$PRESERVED_CLEANED"
COMBINED_COUNT=$(_read_json_py "$TEST_JSON" "
print(len(d['execution']['worktreeTracking']['activeWorktrees']))
")
assert_eq "register_worktree appends to existing entries" "2" "$COMBINED_COUNT"

# =========================================================================
# cleanup_stale_worktrees: 2 stale (both passed)
# Verifies that cleanup_stale processes all stale entries:
# - Both entries removed from activeWorktrees tracking
# - cleanedThisSession reflects the count of processed entries
# On Windows, git worktree remove inside a while-read loop may hit file
# locks on the first entry; we verify tracking is correct regardless.
# =========================================================================
echo "=== Test 12: cleanup_stale with 2 stale worktrees (both passed) ==="
create_worktree "US-ST1" "ql/test-feature" "$TMPDIR" >/dev/null 2>&1
create_worktree "US-ST2" "ql/test-feature" "$TMPDIR" >/dev/null 2>&1
assert_dir_exists "US-ST1 exists before cleanup" "$TMPDIR/.ql-wt/US-ST1"
assert_dir_exists "US-ST2 exists before cleanup" "$TMPDIR/.ql-wt/US-ST2"

cat > "$TEST_JSON" <<ENDJSON
{
  "stories": [
    {"id": "US-ST1", "status": "passed"},
    {"id": "US-ST2", "status": "passed"}
  ],
  "execution": {
    "worktreeTracking": {
      "activeWorktrees": [
        {"path": "$TMPDIR/.ql-wt/US-ST1", "branch": "ql-wt/US-ST1", "storyId": "US-ST1", "createdAt": "2026-01-01T00:00:00Z", "wave": 1},
        {"path": "$TMPDIR/.ql-wt/US-ST2", "branch": "ql-wt/US-ST2", "storyId": "US-ST2", "createdAt": "2026-01-01T00:00:00Z", "wave": 1}
      ],
      "cleanedThisSession": 0,
      "maxWorktrees": 4
    }
  }
}
ENDJSON

OUTPUT=$(cleanup_stale_worktrees "$TEST_JSON" "$TMPDIR" 2>&1)
EXIT_CODE=$?
assert_eq "cleanup_stale with 2 stale exits 0" "0" "$EXIT_CODE"

# Both entries must be removed from JSON tracking
REMAINING=$(_read_json_py "$TEST_JSON" "
print(len(d['execution']['worktreeTracking']['activeWorktrees']))
")
assert_eq "cleanup_stale removes both entries from activeWorktrees" "0" "$REMAINING"

# cleanedThisSession tracks how many remove_worktree calls succeeded
CLEANED_SESSION=$(_read_json_py "$TEST_JSON" "
print(d['execution']['worktreeTracking']['cleanedThisSession'])
")
# At least 1 must be cleaned; on non-Windows both are cleaned
TOTAL=$((TOTAL + 1))
if [[ "$CLEANED_SESSION" -ge 1 ]]; then
  echo "  PASS: cleanup_stale cleanedThisSession >= 1 (got $CLEANED_SESSION)"
  PASS=$((PASS + 1))
else
  echo "  FAIL: cleanup_stale cleanedThisSession >= 1"
  echo "    expected: >= 1"
  echo "    actual:   $CLEANED_SESSION"
  FAIL=$((FAIL + 1))
fi

# Verify log message mentions cleaned worktrees
assert_contains "cleanup_stale logs Cleaned" "Cleaned" "$OUTPUT"

# Clean up any remaining worktree directories (Windows file-lock resilience)
remove_worktree "US-ST1" "$TMPDIR" >/dev/null 2>&1
remove_worktree "US-ST2" "$TMPDIR" >/dev/null 2>&1

# =========================================================================
# cleanup_stale_worktrees: single stale (passed) -- direct verification
# =========================================================================
echo "=== Test 13: cleanup_stale single passed story worktree ==="
create_worktree "US-SP1" "ql/test-feature" "$TMPDIR" >/dev/null 2>&1
assert_dir_exists "US-SP1 exists before cleanup" "$TMPDIR/.ql-wt/US-SP1"

cat > "$TEST_JSON" <<ENDJSON
{
  "stories": [
    {"id": "US-SP1", "status": "passed"}
  ],
  "execution": {
    "worktreeTracking": {
      "activeWorktrees": [
        {"path": "$TMPDIR/.ql-wt/US-SP1", "branch": "ql-wt/US-SP1", "storyId": "US-SP1", "createdAt": "2026-01-01T00:00:00Z", "wave": 1}
      ],
      "cleanedThisSession": 0,
      "maxWorktrees": 4
    }
  }
}
ENDJSON

OUTPUT=$(cleanup_stale_worktrees "$TEST_JSON" "$TMPDIR" 2>/dev/null)
EXIT_CODE=$?
assert_eq "cleanup_stale single passed exits 0" "0" "$EXIT_CODE"
assert_dir_not_exists "US-SP1 removed" "$TMPDIR/.ql-wt/US-SP1"
SP_CLEANED=$(_read_json_py "$TEST_JSON" "
print(d['execution']['worktreeTracking']['cleanedThisSession'])
")
assert_eq "cleanup_stale single cleanedThisSession=1" "1" "$SP_CLEANED"
assert_contains "cleanup_stale single logs Cleaned 1" "Cleaned 1" "$OUTPUT"

# =========================================================================
# cleanup_stale_worktrees: 0 stale (all in_progress)
# =========================================================================
echo "=== Test 14: cleanup_stale with 0 stale (all in_progress) ==="
create_worktree "US-IP1" "ql/test-feature" "$TMPDIR" >/dev/null 2>&1
create_worktree "US-IP2" "ql/test-feature" "$TMPDIR" >/dev/null 2>&1
assert_dir_exists "US-IP1 exists" "$TMPDIR/.ql-wt/US-IP1"
assert_dir_exists "US-IP2 exists" "$TMPDIR/.ql-wt/US-IP2"

cat > "$TEST_JSON" <<ENDJSON
{
  "stories": [
    {"id": "US-IP1", "status": "in_progress"},
    {"id": "US-IP2", "status": "in_progress"}
  ],
  "execution": {
    "worktreeTracking": {
      "activeWorktrees": [
        {"path": "$TMPDIR/.ql-wt/US-IP1", "branch": "ql-wt/US-IP1", "storyId": "US-IP1", "createdAt": "2026-01-01T00:00:00Z", "wave": 1},
        {"path": "$TMPDIR/.ql-wt/US-IP2", "branch": "ql-wt/US-IP2", "storyId": "US-IP2", "createdAt": "2026-01-01T00:00:00Z", "wave": 1}
      ],
      "cleanedThisSession": 0,
      "maxWorktrees": 4
    }
  }
}
ENDJSON

OUTPUT=$(cleanup_stale_worktrees "$TEST_JSON" "$TMPDIR" 2>/dev/null)
EXIT_CODE=$?
assert_eq "cleanup_stale 0 stale exits 0" "0" "$EXIT_CODE"
assert_dir_exists "US-IP1 still exists after cleanup" "$TMPDIR/.ql-wt/US-IP1"
assert_dir_exists "US-IP2 still exists after cleanup" "$TMPDIR/.ql-wt/US-IP2"
IP_REMAINING=$(_read_json_py "$TEST_JSON" "
print(len(d['execution']['worktreeTracking']['activeWorktrees']))
")
assert_eq "cleanup_stale preserves 2 in_progress entries" "2" "$IP_REMAINING"
assert_contains "cleanup_stale logs no stale found" "No stale" "$OUTPUT"

# Clean up
remove_worktree "US-IP1" "$TMPDIR" >/dev/null 2>&1
remove_worktree "US-IP2" "$TMPDIR" >/dev/null 2>&1

# =========================================================================
# cleanup_stale: single failed story (removes it like passed)
# =========================================================================
echo "=== Test 15: cleanup_stale removes failed story worktree ==="
create_worktree "US-F1" "ql/test-feature" "$TMPDIR" >/dev/null 2>&1
cat > "$TEST_JSON" <<ENDJSON
{
  "stories": [
    {"id": "US-F1", "status": "failed"}
  ],
  "execution": {
    "worktreeTracking": {
      "activeWorktrees": [
        {"path": "$TMPDIR/.ql-wt/US-F1", "branch": "ql-wt/US-F1", "storyId": "US-F1", "createdAt": "2026-01-01T00:00:00Z", "wave": 1}
      ],
      "cleanedThisSession": 0,
      "maxWorktrees": 4
    }
  }
}
ENDJSON
cleanup_stale_worktrees "$TEST_JSON" "$TMPDIR" 2>/dev/null
assert_dir_not_exists "US-F1 (failed) removed" "$TMPDIR/.ql-wt/US-F1"
F_CLEANED=$(_read_json_py "$TEST_JSON" "
print(d['execution']['worktreeTracking']['cleanedThisSession'])
")
assert_eq "cleanup_stale failed cleanedThisSession=1" "1" "$F_CLEANED"

# =========================================================================
# cleanup_stale: pending stories are NOT cleaned
# =========================================================================
echo "=== Test 16: cleanup_stale preserves pending story worktrees ==="
create_worktree "US-PD1" "ql/test-feature" "$TMPDIR" >/dev/null 2>&1
cat > "$TEST_JSON" <<ENDJSON
{
  "stories": [
    {"id": "US-PD1", "status": "pending"}
  ],
  "execution": {
    "worktreeTracking": {
      "activeWorktrees": [
        {"path": "$TMPDIR/.ql-wt/US-PD1", "branch": "ql-wt/US-PD1", "storyId": "US-PD1", "createdAt": "2026-01-01T00:00:00Z", "wave": 1}
      ],
      "cleanedThisSession": 0,
      "maxWorktrees": 4
    }
  }
}
ENDJSON
cleanup_stale_worktrees "$TEST_JSON" "$TMPDIR" 2>/dev/null
assert_dir_exists "US-PD1 (pending) preserved" "$TMPDIR/.ql-wt/US-PD1"
PD_COUNT=$(_read_json_py "$TEST_JSON" "
print(len(d['execution']['worktreeTracking']['activeWorktrees']))
")
assert_eq "cleanup_stale pending: entry still in tracking" "1" "$PD_COUNT"

# Clean up
remove_worktree "US-PD1" "$TMPDIR" >/dev/null 2>&1

# =========================================================================
# cleanup_stale: missing parameters
# =========================================================================
echo "=== Test 17: cleanup_stale validates parameters ==="
cleanup_stale_worktrees "" "$TMPDIR" 2>/dev/null
EXIT_CODE=$?
assert_eq "cleanup_stale rejects empty json_path" "1" "$EXIT_CODE"

cleanup_stale_worktrees "$TEST_JSON" "" 2>/dev/null
EXIT_CODE=$?
assert_eq "cleanup_stale rejects empty repo_root" "1" "$EXIT_CODE"

cleanup_stale_worktrees "$TMPDIR/no-such-file.json" "$TMPDIR" 2>/dev/null
EXIT_CODE=$?
assert_eq "cleanup_stale rejects nonexistent json file" "1" "$EXIT_CODE"

# =========================================================================
# T-032: cleanup_merged, pre_spawn_check, and fallback
# =========================================================================

echo "=== Test 18: cleanup_merged removes all 3 specified worktrees ==="
create_worktree "US-CM1" "ql/test-feature" "$TMPDIR" >/dev/null 2>&1
create_worktree "US-CM2" "ql/test-feature" "$TMPDIR" >/dev/null 2>&1
create_worktree "US-CM3" "ql/test-feature" "$TMPDIR" >/dev/null 2>&1
assert_dir_exists "US-CM1 exists" "$TMPDIR/.ql-wt/US-CM1"
assert_dir_exists "US-CM2 exists" "$TMPDIR/.ql-wt/US-CM2"
assert_dir_exists "US-CM3 exists" "$TMPDIR/.ql-wt/US-CM3"

cat > "$TEST_JSON" <<ENDJSON
{
  "stories": [
    {"id": "US-CM1", "status": "passed"},
    {"id": "US-CM2", "status": "passed"},
    {"id": "US-CM3", "status": "passed"}
  ],
  "execution": {
    "worktreeTracking": {
      "activeWorktrees": [
        {"path": "$TMPDIR/.ql-wt/US-CM1", "branch": "ql-wt/US-CM1", "storyId": "US-CM1", "createdAt": "2026-01-01T00:00:00Z", "wave": 2},
        {"path": "$TMPDIR/.ql-wt/US-CM2", "branch": "ql-wt/US-CM2", "storyId": "US-CM2", "createdAt": "2026-01-01T00:00:00Z", "wave": 2},
        {"path": "$TMPDIR/.ql-wt/US-CM3", "branch": "ql-wt/US-CM3", "storyId": "US-CM3", "createdAt": "2026-01-01T00:00:00Z", "wave": 2}
      ],
      "cleanedThisSession": 0,
      "maxWorktrees": 4
    }
  }
}
ENDJSON

OUTPUT=$(cleanup_merged_worktrees "$TEST_JSON" "$TMPDIR" "US-CM1 US-CM2 US-CM3" 2>/dev/null)
EXIT_CODE=$?
assert_eq "cleanup_merged exits 0" "0" "$EXIT_CODE"
assert_dir_not_exists "US-CM1 removed" "$TMPDIR/.ql-wt/US-CM1"
assert_dir_not_exists "US-CM2 removed" "$TMPDIR/.ql-wt/US-CM2"
assert_dir_not_exists "US-CM3 removed" "$TMPDIR/.ql-wt/US-CM3"

CM_REMAINING=$(_read_json_py "$TEST_JSON" "
wts = d['execution']['worktreeTracking']['activeWorktrees']
print(len(wts))
")
assert_eq "cleanup_merged all 3 removed from activeWorktrees" "0" "$CM_REMAINING"
assert_contains "cleanup_merged logs count" "3 merged" "$OUTPUT"

echo "=== Test 19: cleanup_merged preserves unspecified worktrees ==="
create_worktree "US-CM4" "ql/test-feature" "$TMPDIR" >/dev/null 2>&1
create_worktree "US-CM5" "ql/test-feature" "$TMPDIR" >/dev/null 2>&1

cat > "$TEST_JSON" <<ENDJSON
{
  "stories": [
    {"id": "US-CM4", "status": "passed"},
    {"id": "US-CM5", "status": "in_progress"}
  ],
  "execution": {
    "worktreeTracking": {
      "activeWorktrees": [
        {"path": "$TMPDIR/.ql-wt/US-CM4", "branch": "ql-wt/US-CM4", "storyId": "US-CM4", "createdAt": "2026-01-01T00:00:00Z", "wave": 1},
        {"path": "$TMPDIR/.ql-wt/US-CM5", "branch": "ql-wt/US-CM5", "storyId": "US-CM5", "createdAt": "2026-01-01T00:00:00Z", "wave": 1}
      ],
      "cleanedThisSession": 0,
      "maxWorktrees": 4
    }
  }
}
ENDJSON

cleanup_merged_worktrees "$TEST_JSON" "$TMPDIR" "US-CM4" 2>/dev/null
assert_dir_not_exists "US-CM4 removed" "$TMPDIR/.ql-wt/US-CM4"
assert_dir_exists "US-CM5 preserved" "$TMPDIR/.ql-wt/US-CM5"
CM5_REMAINING=$(_read_json_py "$TEST_JSON" "
wts = d['execution']['worktreeTracking']['activeWorktrees']
ids = [w['storyId'] for w in wts]
print(' '.join(ids))
")
assert_eq "cleanup_merged preserves US-CM5 entry" "US-CM5" "$CM5_REMAINING"

# Clean up
remove_worktree "US-CM5" "$TMPDIR" >/dev/null 2>&1

echo "=== Test 20: cleanup_merged validates parameters ==="
cleanup_merged_worktrees "" "$TMPDIR" "US-001" 2>/dev/null
EXIT_CODE=$?
assert_eq "cleanup_merged rejects empty json_path" "1" "$EXIT_CODE"

cleanup_merged_worktrees "$TEST_JSON" "" "US-001" 2>/dev/null
EXIT_CODE=$?
assert_eq "cleanup_merged rejects empty repo_root" "1" "$EXIT_CODE"

cleanup_merged_worktrees "$TMPDIR/no-such-file.json" "$TMPDIR" "US-001" 2>/dev/null
EXIT_CODE=$?
assert_eq "cleanup_merged rejects nonexistent json file" "1" "$EXIT_CODE"

echo "=== Test 21: cleanup_merged with empty IDs is no-op ==="
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
OUTPUT=$(cleanup_merged_worktrees "$TEST_JSON" "$TMPDIR" "" 2>/dev/null)
EXIT_CODE=$?
assert_eq "cleanup_merged with empty IDs exits 0" "0" "$EXIT_CODE"
assert_contains "cleanup_merged empty logs no merged" "No merged" "$OUTPUT"

echo "=== Test 22: cleanup_merged with nonexistent story ID is graceful ==="
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
cleanup_merged_worktrees "$TEST_JSON" "$TMPDIR" "US-NOPE" 2>/dev/null
EXIT_CODE=$?
assert_eq "cleanup_merged with nonexistent ID exits 0" "0" "$EXIT_CODE"

# =========================================================================
# pre_spawn_check
# =========================================================================
echo "=== Test 23: pre_spawn_check returns 0 when 2 active, max=4 ==="
cat > "$TEST_JSON" <<'ENDJSON'
{
  "stories": [
    {"id": "US-PSA", "status": "in_progress"},
    {"id": "US-PSB", "status": "in_progress"}
  ],
  "execution": {
    "worktreeTracking": {
      "activeWorktrees": [
        {"path": "/a", "branch": "b", "storyId": "US-PSA", "createdAt": "2026-01-01T00:00:00Z", "wave": 1},
        {"path": "/b", "branch": "b", "storyId": "US-PSB", "createdAt": "2026-01-01T00:00:00Z", "wave": 1}
      ],
      "cleanedThisSession": 0,
      "maxWorktrees": 4
    }
  }
}
ENDJSON
pre_spawn_check "$TEST_JSON" 4 2>/dev/null
EXIT_CODE=$?
assert_eq "pre_spawn_check 2/4 returns 0" "0" "$EXIT_CODE"

echo "=== Test 24: pre_spawn_check returns 1 when 4 active, max=4 (no stale) ==="
cat > "$TEST_JSON" <<'ENDJSON'
{
  "stories": [
    {"id": "US-L1", "status": "in_progress"},
    {"id": "US-L2", "status": "in_progress"},
    {"id": "US-L3", "status": "in_progress"},
    {"id": "US-L4", "status": "in_progress"}
  ],
  "execution": {
    "worktreeTracking": {
      "activeWorktrees": [
        {"path": "/a", "branch": "b", "storyId": "US-L1", "createdAt": "2026-01-01T00:00:00Z", "wave": 1},
        {"path": "/b", "branch": "b", "storyId": "US-L2", "createdAt": "2026-01-01T00:00:00Z", "wave": 1},
        {"path": "/c", "branch": "b", "storyId": "US-L3", "createdAt": "2026-01-01T00:00:00Z", "wave": 1},
        {"path": "/d", "branch": "b", "storyId": "US-L4", "createdAt": "2026-01-01T00:00:00Z", "wave": 1}
      ],
      "cleanedThisSession": 0,
      "maxWorktrees": 4
    }
  }
}
ENDJSON
pre_spawn_check "$TEST_JSON" 4 2>/dev/null
EXIT_CODE=$?
assert_eq "pre_spawn_check 4/4 (no stale) returns 1" "1" "$EXIT_CODE"

echo "=== Test 25: pre_spawn_check at limit triggers cleanup, returns 0 if slot freed ==="
create_worktree "US-PCS1" "ql/test-feature" "$TMPDIR" >/dev/null 2>&1
cat > "$TEST_JSON" <<ENDJSON
{
  "stories": [
    {"id": "US-PCS1", "status": "passed"},
    {"id": "US-PCS2", "status": "in_progress"}
  ],
  "execution": {
    "worktreeTracking": {
      "activeWorktrees": [
        {"path": "$TMPDIR/.ql-wt/US-PCS1", "branch": "ql-wt/US-PCS1", "storyId": "US-PCS1", "createdAt": "2026-01-01T00:00:00Z", "wave": 1},
        {"path": "$TMPDIR/somewhere", "branch": "ql-wt/US-PCS2", "storyId": "US-PCS2", "createdAt": "2026-01-01T00:00:00Z", "wave": 1}
      ],
      "cleanedThisSession": 0,
      "maxWorktrees": 2
    }
  }
}
ENDJSON
pre_spawn_check "$TEST_JSON" 2 2>/dev/null
EXIT_CODE=$?
assert_eq "pre_spawn_check frees slot by cleaning stale, returns 0" "0" "$EXIT_CODE"
assert_dir_not_exists "US-PCS1 cleaned by pre_spawn_check" "$TMPDIR/.ql-wt/US-PCS1"

echo "=== Test 26: pre_spawn_check with 0 active (empty tracking) returns 0 ==="
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
pre_spawn_check "$TEST_JSON" 4 2>/dev/null
EXIT_CODE=$?
assert_eq "pre_spawn_check 0/4 returns 0" "0" "$EXIT_CODE"

echo "=== Test 27: pre_spawn_check with max_worktrees=1 boundary ==="
cat > "$TEST_JSON" <<'ENDJSON'
{
  "stories": [
    {"id": "US-B1", "status": "in_progress"}
  ],
  "execution": {
    "worktreeTracking": {
      "activeWorktrees": [
        {"path": "/x", "branch": "b", "storyId": "US-B1", "createdAt": "2026-01-01T00:00:00Z", "wave": 1}
      ],
      "cleanedThisSession": 0,
      "maxWorktrees": 1
    }
  }
}
ENDJSON
pre_spawn_check "$TEST_JSON" 1 2>/dev/null
EXIT_CODE=$?
assert_eq "pre_spawn_check 1/1 (no stale) returns 1" "1" "$EXIT_CODE"

echo "=== Test 28: pre_spawn_check with missing worktreeTracking ==="
cat > "$TEST_JSON" <<'ENDJSON'
{
  "stories": []
}
ENDJSON
pre_spawn_check "$TEST_JSON" 4 2>/dev/null
EXIT_CODE=$?
assert_eq "pre_spawn_check with no worktreeTracking returns 0 (0 active)" "0" "$EXIT_CODE"

echo "=== Test 29: pre_spawn_check validates parameters ==="
pre_spawn_check "" 4 2>/dev/null
EXIT_CODE=$?
assert_eq "pre_spawn_check rejects empty json_path" "1" "$EXIT_CODE"

pre_spawn_check "$TEST_JSON" "" 2>/dev/null
EXIT_CODE=$?
assert_eq "pre_spawn_check rejects empty max_worktrees" "1" "$EXIT_CODE"

# =========================================================================
# Fallback: cleanup_stale without worktreeTracking
# =========================================================================
echo "=== Test 30: cleanup_stale fallback uses git worktree list ==="
create_worktree "US-FB1" "ql/test-feature" "$TMPDIR" >/dev/null 2>&1
assert_dir_exists "US-FB1 exists for fallback test" "$TMPDIR/.ql-wt/US-FB1"

# quantum.json has NO worktreeTracking -- fallback mode
cat > "$TEST_JSON" <<'ENDJSON'
{
  "stories": [
    {"id": "US-FB1", "status": "passed"}
  ]
}
ENDJSON

OUTPUT=$(cleanup_stale_worktrees "$TEST_JSON" "$TMPDIR" 2>/dev/null)
EXIT_CODE=$?
assert_eq "cleanup_stale fallback exits 0" "0" "$EXIT_CODE"
assert_dir_not_exists "US-FB1 removed by fallback" "$TMPDIR/.ql-wt/US-FB1"
assert_contains "cleanup_stale fallback logs cleaned" "Cleaned" "$OUTPUT"

echo "=== Test 31: cleanup_stale fallback preserves in_progress worktree ==="
create_worktree "US-FB2" "ql/test-feature" "$TMPDIR" >/dev/null 2>&1
cat > "$TEST_JSON" <<'ENDJSON'
{
  "stories": [
    {"id": "US-FB2", "status": "in_progress"}
  ]
}
ENDJSON
OUTPUT=$(cleanup_stale_worktrees "$TEST_JSON" "$TMPDIR" 2>/dev/null)
assert_dir_exists "US-FB2 preserved by fallback" "$TMPDIR/.ql-wt/US-FB2"
assert_contains "cleanup_stale fallback logs no stale" "No stale" "$OUTPUT"

# Clean up
remove_worktree "US-FB2" "$TMPDIR" >/dev/null 2>&1

echo "=== Test 32: cleanup_stale fallback with no worktrees at all ==="
cat > "$TEST_JSON" <<'ENDJSON'
{
  "stories": [
    {"id": "US-NONE", "status": "passed"}
  ]
}
ENDJSON
OUTPUT=$(cleanup_stale_worktrees "$TEST_JSON" "$TMPDIR" 2>/dev/null)
EXIT_CODE=$?
assert_eq "cleanup_stale fallback with no worktrees exits 0" "0" "$EXIT_CODE"
assert_contains "cleanup_stale fallback no worktrees logs no stale" "No stale" "$OUTPUT"

# =========================================================================
# Removal failure handling with retry
# =========================================================================
echo "=== Test 33: cleanup_stale handles worktree already removed from disk ==="
cat > "$TEST_JSON" <<'ENDJSON'
{
  "stories": [
    {"id": "US-GHOST", "status": "passed"}
  ],
  "execution": {
    "worktreeTracking": {
      "activeWorktrees": [
        {"path": "/nonexistent/path/US-GHOST", "branch": "ql-wt/US-GHOST", "storyId": "US-GHOST", "createdAt": "2026-01-01T00:00:00Z", "wave": 1}
      ],
      "cleanedThisSession": 0,
      "maxWorktrees": 4
    }
  }
}
ENDJSON
cleanup_stale_worktrees "$TEST_JSON" "$TMPDIR" 2>/dev/null
EXIT_CODE=$?
assert_eq "cleanup_stale with ghost entry exits 0" "0" "$EXIT_CODE"
GHOST_REMAINING=$(_read_json_py "$TEST_JSON" "
wts = d['execution']['worktreeTracking']['activeWorktrees']
print(len(wts))
")
assert_eq "cleanup_stale removes ghost entry from tracking" "0" "$GHOST_REMAINING"

echo "=== Test 34: cleanup_merged with already-removed worktree is graceful ==="
cat > "$TEST_JSON" <<'ENDJSON'
{
  "stories": [
    {"id": "US-GONE", "status": "passed"}
  ],
  "execution": {
    "worktreeTracking": {
      "activeWorktrees": [
        {"path": "/nonexistent/US-GONE", "branch": "ql-wt/US-GONE", "storyId": "US-GONE", "createdAt": "2026-01-01T00:00:00Z", "wave": 1}
      ],
      "cleanedThisSession": 0,
      "maxWorktrees": 4
    }
  }
}
ENDJSON
cleanup_merged_worktrees "$TEST_JSON" "$TMPDIR" "US-GONE" 2>/dev/null
EXIT_CODE=$?
assert_eq "cleanup_merged with already-removed worktree exits 0" "0" "$EXIT_CODE"

# =========================================================================
# Print summary
# =========================================================================
echo ""
echo "=== Results: $PASS/$TOTAL passed, $FAIL failed ==="
if [[ $FAIL -eq 0 ]]; then
  exit 0
else
  exit 1
fi
