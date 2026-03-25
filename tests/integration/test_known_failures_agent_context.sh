#!/usr/bin/env bash
# Integration test: Known failures agent context
# Tests that format_agent_context correctly outputs pre-existing failure info for agent prompts.
#
# Sets up quantum.json with knownFailures.current containing 2 failing tests
# and verifies the formatted output contains expected text.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="$SCRIPT_DIR/../../lib"
PASS=0
FAIL=0
TOTAL=0

# Source the library under test
if [[ ! -f "$LIB_DIR/known-failures.sh" ]]; then
  echo "SKIP: lib/known-failures.sh not found"
  exit 1
fi
source "$LIB_DIR/known-failures.sh"

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

assert_empty() {
  local test_name="$1" actual="$2"
  TOTAL=$((TOTAL + 1))
  if [[ -z "$actual" ]]; then
    echo "  PASS: $test_name"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: $test_name"
    echo "    expected empty, got: $actual"
    FAIL=$((FAIL + 1))
  fi
}

# Helper: convert path to native (Windows) format for Python
_to_native() {
  if command -v cygpath &>/dev/null; then
    cygpath -m "$1"
  else
    printf '%s' "$1"
  fi
}

# =========================================================================
# Setup
# =========================================================================
TMPDIR_BASE=$(mktemp -d)
trap 'rm -rf "$TMPDIR_BASE"' EXIT

echo "=== Known Failures Agent Context Integration Test ==="
echo ""

# =========================================================================
echo "--- Test 1: format_agent_context with 2 known failures ---"
# =========================================================================
JSON_FILE="$TMPDIR_BASE/test1.json"
cat > "$JSON_FILE" <<'EOF'
{
  "stories": [],
  "knownFailures": {
    "baseline": {
      "capturedAt": "2026-03-25T10:00:00Z",
      "wave": 0,
      "passCount": 10,
      "failCount": 0,
      "skipCount": 0,
      "failingTests": []
    },
    "current": {
      "capturedAt": "2026-03-25T10:00:00Z",
      "updatedAt": "2026-03-25T11:00:00Z",
      "wave": 2,
      "passCount": 8,
      "failCount": 2,
      "skipCount": 0,
      "failingTests": [
        {
          "name": "tests/api/test_auth.py::test_expired_token",
          "failingSince": 1,
          "introducedBy": "US-003",
          "expectedFix": "US-007",
          "error": "AssertionError: expected 401 got 500"
        },
        {
          "name": "tests/core/test_cache.py::test_eviction_policy",
          "failingSince": 2,
          "introducedBy": "US-004",
          "expectedFix": "US-009",
          "error": "TimeoutError: cache eviction exceeded 5s"
        }
      ]
    },
    "flakyThreshold": 1,
    "fullSuiteTimeout": 60
  }
}
EOF

OUTPUT=$(format_agent_context "$JSON_FILE")

# Verify output contains both test names
assert_contains "Contains test_expired_token name" "tests/api/test_auth.py::test_expired_token" "$OUTPUT"
assert_contains "Contains test_eviction_policy name" "tests/core/test_cache.py::test_eviction_policy" "$OUTPUT"

# Verify output contains 'failing since Wave N' text
assert_contains "Contains 'failing since Wave 1'" "failing since Wave 1" "$OUTPUT"
assert_contains "Contains 'failing since Wave 2'" "failing since Wave 2" "$OUTPUT"

# Verify expected fix story IDs are included
assert_contains "Contains expected fix US-007" "expected fix: US-007" "$OUTPUT"
assert_contains "Contains expected fix US-009" "expected fix: US-009" "$OUTPUT"

# Verify instruction lines
assert_contains "Contains header line" "Known failing tests (pre-existing, not caused by your story):" "$OUTPUT"
assert_contains "Contains proceed instruction" "If you see ONLY these failures, they are not your fault -- proceed normally." "$OUTPUT"
assert_contains "Contains new failure instruction" "If you see NEW failures not on this list, they ARE your responsibility -- fix them." "$OUTPUT"

echo ""

# =========================================================================
echo "--- Test 2: format_agent_context with no failures (empty output) ---"
# =========================================================================
JSON_FILE2="$TMPDIR_BASE/test2.json"
cat > "$JSON_FILE2" <<'EOF'
{
  "stories": [],
  "knownFailures": {
    "current": {
      "passCount": 10,
      "failCount": 0,
      "skipCount": 0,
      "failingTests": []
    }
  }
}
EOF

OUTPUT2=$(format_agent_context "$JSON_FILE2")
assert_empty "No failures: output is empty" "$OUTPUT2"

echo ""

# =========================================================================
echo "--- Test 3: format_agent_context with no knownFailures field ---"
# =========================================================================
JSON_FILE3="$TMPDIR_BASE/test3.json"
cat > "$JSON_FILE3" <<'EOF'
{
  "stories": [{"id": "US-001", "status": "pending"}]
}
EOF

OUTPUT3=$(format_agent_context "$JSON_FILE3")
assert_empty "No knownFailures: output is empty" "$OUTPUT3"

echo ""

# =========================================================================
echo "--- Test 4: format_agent_context with null current ---"
# =========================================================================
JSON_FILE4="$TMPDIR_BASE/test4.json"
cat > "$JSON_FILE4" <<'EOF'
{
  "stories": [],
  "knownFailures": {
    "baseline": null,
    "current": null
  }
}
EOF

OUTPUT4=$(format_agent_context "$JSON_FILE4")
assert_empty "Null current: output is empty" "$OUTPUT4"

echo ""

# =========================================================================
echo "--- Test 5: format_agent_context with expectedFix null shows 'unknown' ---"
# =========================================================================
JSON_FILE5="$TMPDIR_BASE/test5.json"
cat > "$JSON_FILE5" <<'EOF'
{
  "stories": [],
  "knownFailures": {
    "current": {
      "passCount": 5,
      "failCount": 1,
      "skipCount": 0,
      "failingTests": [
        {
          "name": "tests/unit/test_util.py::test_edge_case",
          "failingSince": 3,
          "introducedBy": null,
          "expectedFix": null,
          "error": "ValueError: unexpected None"
        }
      ]
    }
  }
}
EOF

OUTPUT5=$(format_agent_context "$JSON_FILE5")
assert_contains "Null fix shows 'unknown'" "expected fix: unknown" "$OUTPUT5"
assert_contains "Contains test name" "test_edge_case" "$OUTPUT5"
assert_contains "Contains wave number" "failing since Wave 3" "$OUTPUT5"

echo ""

# =========================================================================
echo "--- Test 6: format_agent_context with empty json_path ---"
# =========================================================================
OUTPUT6=$(format_agent_context "")
assert_empty "Empty path: output is empty" "$OUTPUT6"

echo ""

# =========================================================================
echo "--- Test 7: format_agent_context with single failure ---"
# =========================================================================
JSON_FILE7="$TMPDIR_BASE/test7.json"
cat > "$JSON_FILE7" <<'EOF'
{
  "stories": [],
  "knownFailures": {
    "current": {
      "passCount": 20,
      "failCount": 1,
      "skipCount": 2,
      "failingTests": [
        {
          "name": "src/components/__tests__/Button.test.tsx::renders disabled state",
          "failingSince": 1,
          "introducedBy": "US-012",
          "expectedFix": "US-015",
          "error": "Expected aria-disabled to be true"
        }
      ]
    }
  }
}
EOF

OUTPUT7=$(format_agent_context "$JSON_FILE7")
assert_contains "Single failure: has test name" "Button.test.tsx" "$OUTPUT7"
assert_contains "Single failure: has wave" "failing since Wave 1" "$OUTPUT7"
assert_contains "Single failure: has fix ID" "expected fix: US-015" "$OUTPUT7"
# Verify both instruction lines still present with single failure
assert_contains "Single failure: proceed instruction" "proceed normally" "$OUTPUT7"
assert_contains "Single failure: new failure instruction" "your responsibility" "$OUTPUT7"

echo ""

# =========================================================================
echo "--- Test 8: format_agent_context output line count is correct ---"
# =========================================================================
# With 2 failing tests, we expect:
# Line 1: header
# Line 2: test 1 detail
# Line 3: test 2 detail
# Line 4: proceed instruction
# Line 5: new failure instruction
# = 5 lines total
OUTPUT_LINES=$(format_agent_context "$JSON_FILE" | wc -l | tr -d ' ')
assert_eq "Line count with 2 failures" "5" "$OUTPUT_LINES"

echo ""

# =========================================================================
# Summary
# =========================================================================
echo "=== Results: $PASS/$TOTAL passed, $FAIL failed ==="
if [[ $FAIL -eq 0 ]]; then
  exit 0
else
  exit 1
fi
