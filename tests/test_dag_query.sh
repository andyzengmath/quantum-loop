#!/usr/bin/env bash
# Test suite for lib/dag-query.sh
# Requires: jq, bash 4+

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="$SCRIPT_DIR/../lib"
PASS=0
FAIL=0
TOTAL=0

# Ensure jq is available
if ! command -v jq &>/dev/null; then
  echo "SKIP: jq not found"
  exit 1
fi

# Source the library under test
if [[ ! -f "$LIB_DIR/dag-query.sh" ]]; then
  echo "SKIP: lib/dag-query.sh not found (RED phase)"
  exit 1
fi
source "$LIB_DIR/dag-query.sh"

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

# =========================================================================
echo "=== Test 1: Basic eligible stories ==="
TMPJSON=$(mktemp)
cat > "$TMPJSON" << 'EOF'
{
  "stories": [
    {"id": "US-001", "status": "passed", "dependsOn": [], "retries": {"attempts": 0, "maxAttempts": 3}},
    {"id": "US-002", "status": "pending", "dependsOn": ["US-001"], "retries": {"attempts": 0, "maxAttempts": 3}},
    {"id": "US-003", "status": "pending", "dependsOn": ["US-001"], "retries": {"attempts": 0, "maxAttempts": 3}},
    {"id": "US-004", "status": "pending", "dependsOn": ["US-002", "US-003"], "retries": {"attempts": 0, "maxAttempts": 3}}
  ]
}
EOF
RESULT=$(get_executable_stories "$TMPJSON")
assert_contains "US-002 is eligible" "US-002" "$RESULT"
assert_contains "US-003 is eligible" "US-003" "$RESULT"
assert_not_contains "US-004 is NOT eligible" "US-004" "$RESULT"
rm -f "$TMPJSON"

# =========================================================================
echo "=== Test 2: in_progress exclusion ==="
TMPJSON=$(mktemp)
cat > "$TMPJSON" << 'EOF'
{
  "stories": [
    {"id": "US-001", "status": "passed", "dependsOn": [], "retries": {"attempts": 0, "maxAttempts": 3}},
    {"id": "US-002", "status": "in_progress", "dependsOn": ["US-001"], "retries": {"attempts": 0, "maxAttempts": 3}},
    {"id": "US-003", "status": "pending", "dependsOn": ["US-001"], "retries": {"attempts": 0, "maxAttempts": 3}}
  ]
}
EOF
RESULT=$(get_executable_stories "$TMPJSON")
assert_contains "US-003 is eligible" "US-003" "$RESULT"
assert_not_contains "US-002 (in_progress) is excluded" "US-002" "$RESULT"
rm -f "$TMPJSON"

# =========================================================================
echo "=== Test 3: maxAttempts exclusion ==="
TMPJSON=$(mktemp)
cat > "$TMPJSON" << 'EOF'
{
  "stories": [
    {"id": "US-001", "status": "passed", "dependsOn": [], "retries": {"attempts": 0, "maxAttempts": 3}},
    {"id": "US-002", "status": "failed", "dependsOn": ["US-001"], "retries": {"attempts": 3, "maxAttempts": 3}},
    {"id": "US-003", "status": "failed", "dependsOn": ["US-001"], "retries": {"attempts": 1, "maxAttempts": 3}}
  ]
}
EOF
RESULT=$(get_executable_stories "$TMPJSON")
assert_contains "US-003 (failed, retries remaining) is eligible" "US-003" "$RESULT"
assert_not_contains "US-002 (maxAttempts reached) is excluded" "US-002" "$RESULT"
rm -f "$TMPJSON"

# =========================================================================
echo "=== Test 4: COMPLETE detection ==="
TMPJSON=$(mktemp)
cat > "$TMPJSON" << 'EOF'
{
  "stories": [
    {"id": "US-001", "status": "passed", "dependsOn": [], "retries": {"attempts": 0, "maxAttempts": 3}},
    {"id": "US-002", "status": "passed", "dependsOn": ["US-001"], "retries": {"attempts": 0, "maxAttempts": 3}}
  ]
}
EOF
RESULT=$(get_executable_stories "$TMPJSON")
assert_eq "Returns COMPLETE when all passed" "COMPLETE" "$RESULT"
rm -f "$TMPJSON"

# =========================================================================
echo "=== Test 5: BLOCKED detection ==="
TMPJSON=$(mktemp)
cat > "$TMPJSON" << 'EOF'
{
  "stories": [
    {"id": "US-001", "status": "passed", "dependsOn": [], "retries": {"attempts": 0, "maxAttempts": 3}},
    {"id": "US-002", "status": "failed", "dependsOn": ["US-001"], "retries": {"attempts": 3, "maxAttempts": 3}},
    {"id": "US-003", "status": "pending", "dependsOn": ["US-002"], "retries": {"attempts": 0, "maxAttempts": 3}}
  ]
}
EOF
RESULT=$(get_executable_stories "$TMPJSON")
assert_eq "Returns BLOCKED when stuck" "BLOCKED" "$RESULT"
rm -f "$TMPJSON"

# =========================================================================
echo "=== Test 6: Cycle detection ==="
TMPJSON=$(mktemp)
cat > "$TMPJSON" << 'EOF'
{
  "stories": [
    {"id": "US-001", "status": "pending", "dependsOn": ["US-002"], "retries": {"attempts": 0, "maxAttempts": 3}},
    {"id": "US-002", "status": "pending", "dependsOn": ["US-001"], "retries": {"attempts": 0, "maxAttempts": 3}}
  ]
}
EOF
RESULT=$(detect_cycles "$TMPJSON" 2>&1 || true)
assert_contains "Cycle detected" "CYCLE" "$RESULT"
rm -f "$TMPJSON"

# =========================================================================
echo "=== Test 7: No cycles ==="
TMPJSON=$(mktemp)
cat > "$TMPJSON" << 'EOF'
{
  "stories": [
    {"id": "US-001", "status": "pending", "dependsOn": [], "retries": {"attempts": 0, "maxAttempts": 3}},
    {"id": "US-002", "status": "pending", "dependsOn": ["US-001"], "retries": {"attempts": 0, "maxAttempts": 3}}
  ]
}
EOF
RESULT=$(detect_cycles "$TMPJSON" 2>&1 || true)
assert_contains "No cycles" "NO_CYCLES" "$RESULT"
rm -f "$TMPJSON"

# =========================================================================
echo "=== Test 8: All independent stories ==="
TMPJSON=$(mktemp)
cat > "$TMPJSON" << 'EOF'
{
  "stories": [
    {"id": "US-001", "status": "pending", "dependsOn": [], "retries": {"attempts": 0, "maxAttempts": 3}},
    {"id": "US-002", "status": "pending", "dependsOn": [], "retries": {"attempts": 0, "maxAttempts": 3}},
    {"id": "US-003", "status": "pending", "dependsOn": [], "retries": {"attempts": 0, "maxAttempts": 3}}
  ]
}
EOF
RESULT=$(get_executable_stories "$TMPJSON")
assert_contains "US-001 eligible" "US-001" "$RESULT"
assert_contains "US-002 eligible" "US-002" "$RESULT"
assert_contains "US-003 eligible" "US-003" "$RESULT"
rm -f "$TMPJSON"

# =========================================================================
# =========================================================================
echo "=== Test 9: filter_file_conflicts — filePaths overlap ==="
TMPJSON=$(mktemp)
cat > "$TMPJSON" << 'EOF'
{
  "stories": [
    {"id": "US-001", "priority": 1, "status": "pending", "dependsOn": [], "tasks": [{"filePaths": ["src/a.ts", "src/b.ts"]}], "retries": {"attempts": 0, "maxAttempts": 3}},
    {"id": "US-002", "priority": 2, "status": "pending", "dependsOn": [], "tasks": [{"filePaths": ["src/b.ts", "src/c.ts"]}], "retries": {"attempts": 0, "maxAttempts": 3}},
    {"id": "US-003", "priority": 3, "status": "pending", "dependsOn": [], "tasks": [{"filePaths": ["src/d.ts"]}], "retries": {"attempts": 0, "maxAttempts": 3}}
  ],
  "fileConflicts": []
}
EOF
RESULT=$(filter_file_conflicts "$TMPJSON" '["US-001","US-002","US-003"]')
assert_contains "US-001 included (highest priority)" "US-001" "$RESULT"
assert_not_contains "US-002 excluded (shares src/b.ts with US-001)" "US-002" "$RESULT"
assert_contains "US-003 included (no conflict)" "US-003" "$RESULT"
rm -f "$TMPJSON"

# =========================================================================
echo "=== Test 10: filter_file_conflicts — fileConflicts entry ==="
TMPJSON=$(mktemp)
cat > "$TMPJSON" << 'EOF'
{
  "stories": [
    {"id": "US-001", "priority": 1, "status": "pending", "dependsOn": [], "tasks": [{"filePaths": ["src/x.ts"]}], "retries": {"attempts": 0, "maxAttempts": 3}},
    {"id": "US-002", "priority": 2, "status": "pending", "dependsOn": [], "tasks": [{"filePaths": ["src/y.ts"]}], "retries": {"attempts": 0, "maxAttempts": 3}},
    {"id": "US-003", "priority": 3, "status": "pending", "dependsOn": [], "tasks": [{"filePaths": ["src/z.ts"]}], "retries": {"attempts": 0, "maxAttempts": 3}}
  ],
  "fileConflicts": [{"file": "src/shared.ts", "stories": ["US-001", "US-003"]}]
}
EOF
RESULT=$(filter_file_conflicts "$TMPJSON" '["US-001","US-002","US-003"]')
assert_contains "US-001 included" "US-001" "$RESULT"
assert_contains "US-002 included (no conflict)" "US-002" "$RESULT"
assert_not_contains "US-003 excluded (fileConflict with US-001)" "US-003" "$RESULT"
rm -f "$TMPJSON"

# =========================================================================
echo "=== Test 11: filter_file_conflicts — empty filePaths ==="
TMPJSON=$(mktemp)
cat > "$TMPJSON" << 'EOF'
{
  "stories": [
    {"id": "US-001", "priority": 1, "status": "pending", "dependsOn": [], "tasks": [{"filePaths": []}], "retries": {"attempts": 0, "maxAttempts": 3}},
    {"id": "US-002", "priority": 2, "status": "pending", "dependsOn": [], "tasks": [], "retries": {"attempts": 0, "maxAttempts": 3}}
  ],
  "fileConflicts": []
}
EOF
RESULT=$(filter_file_conflicts "$TMPJSON" '["US-001","US-002"]')
assert_contains "US-001 included (empty filePaths)" "US-001" "$RESULT"
assert_contains "US-002 included (no tasks)" "US-002" "$RESULT"
rm -f "$TMPJSON"

# =========================================================================
echo "=== Test 12: filter_file_conflicts — no conflicts ==="
TMPJSON=$(mktemp)
cat > "$TMPJSON" << 'EOF'
{
  "stories": [
    {"id": "US-001", "priority": 1, "status": "pending", "dependsOn": [], "tasks": [{"filePaths": ["src/a.ts"]}], "retries": {"attempts": 0, "maxAttempts": 3}},
    {"id": "US-002", "priority": 2, "status": "pending", "dependsOn": [], "tasks": [{"filePaths": ["src/b.ts"]}], "retries": {"attempts": 0, "maxAttempts": 3}},
    {"id": "US-003", "priority": 3, "status": "pending", "dependsOn": [], "tasks": [{"filePaths": ["src/c.ts"]}], "retries": {"attempts": 0, "maxAttempts": 3}}
  ],
  "fileConflicts": []
}
EOF
RESULT=$(filter_file_conflicts "$TMPJSON" '["US-001","US-002","US-003"]')
assert_contains "US-001 included" "US-001" "$RESULT"
assert_contains "US-002 included" "US-002" "$RESULT"
assert_contains "US-003 included" "US-003" "$RESULT"
rm -f "$TMPJSON"

# =========================================================================
echo "=== Test 13: filter_file_conflicts — three-way conflict ==="
TMPJSON=$(mktemp)
cat > "$TMPJSON" << 'EOF'
{
  "stories": [
    {"id": "US-001", "priority": 1, "status": "pending", "dependsOn": [], "tasks": [{"filePaths": ["src/shared.ts"]}], "retries": {"attempts": 0, "maxAttempts": 3}},
    {"id": "US-002", "priority": 2, "status": "pending", "dependsOn": [], "tasks": [{"filePaths": ["src/shared.ts"]}], "retries": {"attempts": 0, "maxAttempts": 3}},
    {"id": "US-003", "priority": 3, "status": "pending", "dependsOn": [], "tasks": [{"filePaths": ["src/shared.ts"]}], "retries": {"attempts": 0, "maxAttempts": 3}}
  ],
  "fileConflicts": []
}
EOF
RESULT=$(filter_file_conflicts "$TMPJSON" '["US-001","US-002","US-003"]')
assert_contains "US-001 included (highest priority)" "US-001" "$RESULT"
assert_not_contains "US-002 excluded (conflict)" "US-002" "$RESULT"
assert_not_contains "US-003 excluded (conflict)" "US-003" "$RESULT"
rm -f "$TMPJSON"

# =========================================================================
echo "=== Test 14: filter_file_conflicts — null fileConflicts ==="
TMPJSON=$(mktemp)
cat > "$TMPJSON" << 'EOF'
{
  "stories": [
    {"id": "US-001", "priority": 1, "status": "pending", "dependsOn": [], "tasks": [{"filePaths": ["src/a.ts"]}], "retries": {"attempts": 0, "maxAttempts": 3}},
    {"id": "US-002", "priority": 2, "status": "pending", "dependsOn": [], "tasks": [{"filePaths": ["src/b.ts"]}], "retries": {"attempts": 0, "maxAttempts": 3}}
  ],
  "fileConflicts": null
}
EOF
RESULT=$(filter_file_conflicts "$TMPJSON" '["US-001","US-002"]')
assert_contains "US-001 with null fileConflicts" "US-001" "$RESULT"
assert_contains "US-002 with null fileConflicts" "US-002" "$RESULT"
rm -f "$TMPJSON"

# =========================================================================
echo "=== Test 15: filter_file_conflicts — transitive conflict chain ==="
TMPJSON=$(mktemp)
cat > "$TMPJSON" << 'EOF'
{
  "stories": [
    {"id": "US-001", "priority": 1, "status": "pending", "dependsOn": [], "tasks": [{"filePaths": ["src/a.ts"]}], "retries": {"attempts": 0, "maxAttempts": 3}},
    {"id": "US-002", "priority": 2, "status": "pending", "dependsOn": [], "tasks": [{"filePaths": ["src/a.ts", "src/b.ts"]}], "retries": {"attempts": 0, "maxAttempts": 3}},
    {"id": "US-003", "priority": 3, "status": "pending", "dependsOn": [], "tasks": [{"filePaths": ["src/b.ts"]}], "retries": {"attempts": 0, "maxAttempts": 3}}
  ],
  "fileConflicts": []
}
EOF
RESULT=$(filter_file_conflicts "$TMPJSON" '["US-001","US-002","US-003"]')
assert_contains "US-001 included (claims src/a.ts)" "US-001" "$RESULT"
assert_not_contains "US-002 excluded (src/a.ts conflict with US-001)" "US-002" "$RESULT"
assert_contains "US-003 included (src/b.ts unclaimed — US-002 was excluded)" "US-003" "$RESULT"
rm -f "$TMPJSON"

# =========================================================================
echo "=== Test 16: filter_file_conflicts — similar-but-different paths ==="
TMPJSON=$(mktemp)
cat > "$TMPJSON" << 'EOF'
{
  "stories": [
    {"id": "US-001", "priority": 1, "status": "pending", "dependsOn": [], "tasks": [{"filePaths": ["src/a.ts"]}], "retries": {"attempts": 0, "maxAttempts": 3}},
    {"id": "US-002", "priority": 2, "status": "pending", "dependsOn": [], "tasks": [{"filePaths": ["src/a.tsx"]}], "retries": {"attempts": 0, "maxAttempts": 3}}
  ],
  "fileConflicts": []
}
EOF
RESULT=$(filter_file_conflicts "$TMPJSON" '["US-001","US-002"]')
assert_contains "US-001 included" "US-001" "$RESULT"
assert_contains "US-002 included (a.tsx != a.ts, exact match)" "US-002" "$RESULT"
rm -f "$TMPJSON"

# =========================================================================
echo ""
echo "=== Results: $PASS/$TOTAL passed, $FAIL failed ==="
if [[ $FAIL -eq 0 ]]; then
  exit 0
else
  exit 1
fi
