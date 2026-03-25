#!/usr/bin/env bash
# Integration test: Known failures lifecycle
# Tests the full lifecycle: baseline -> introduce failures -> detect as new -> mark as known -> resolve
#
# Uses a mock pytest runner (a shell script on PATH) to produce controlled output.

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

# Helper: convert path to native (Windows) format for Python
_to_native() {
  if command -v cygpath &>/dev/null; then
    cygpath -m "$1"
  else
    printf '%s' "$1"
  fi
}

# Helper: read a field from a JSON file using Python (handles Windows paths)
read_json_field() {
  local json_file="$1"
  local expr="$2"
  local native_path
  native_path=$(_to_native "$json_file")
  python -c "import json; d=json.load(open('$native_path')); print($expr)" 2>/dev/null
}

# =========================================================================
# Setup: Create a temp project with mock test runner
# =========================================================================
TMPDIR_BASE=$(mktemp -d)
trap 'rm -rf "$TMPDIR_BASE"' EXIT

PROJECT_DIR="$TMPDIR_BASE/project"
mkdir -p "$PROJECT_DIR"

# Create pyproject.toml so detect_test_runner finds pytest
cat > "$PROJECT_DIR/pyproject.toml" <<'EOF'
[tool.pytest]
testpaths = ["tests"]
EOF

# Create a directory for the mock pytest binary
MOCK_BIN="$TMPDIR_BASE/mock_bin"
mkdir -p "$MOCK_BIN"

# Create a control file that tells the mock what to output
MOCK_CONTROL="$TMPDIR_BASE/mock_control.txt"
echo "all_pass" > "$MOCK_CONTROL"

# Create mock pytest script
# On Windows (MSYS/Git Bash), the script must be executable and on PATH
cat > "$MOCK_BIN/pytest" <<MOCKEOF
#!/usr/bin/env bash
CONTROL_FILE="$MOCK_CONTROL"
MODE=\$(cat "\$CONTROL_FILE" 2>/dev/null || echo "all_pass")
case "\$MODE" in
  all_pass)
    echo "test_alpha.py::test_one PASSED"
    echo "test_alpha.py::test_two PASSED"
    echo "test_alpha.py::test_three PASSED"
    echo "3 passed"
    ;;
  three_failures)
    echo "test_alpha.py::test_one PASSED"
    echo "test_alpha.py::test_two PASSED"
    echo "test_beta.py::test_fail_a FAILED"
    echo "test_beta.py::test_fail_b FAILED"
    echo "test_beta.py::test_fail_c FAILED"
    echo "2 passed, 3 failed"
    exit 1
    ;;
  resolved)
    echo "test_alpha.py::test_one PASSED"
    echo "test_alpha.py::test_two PASSED"
    echo "test_alpha.py::test_three PASSED"
    echo "test_beta.py::test_fix_a PASSED"
    echo "test_beta.py::test_fix_b PASSED"
    echo "5 passed"
    ;;
esac
exit 0
MOCKEOF
chmod +x "$MOCK_BIN/pytest"

# Prepend mock bin to PATH so our mock pytest is found first
export PATH="$MOCK_BIN:$PATH"

# Create minimal quantum.json for the project
cat > "$PROJECT_DIR/quantum.json" <<'EOF'
{
  "stories": [
    {"id": "US-TEST", "status": "in_progress"}
  ]
}
EOF

JSON_PATH="$PROJECT_DIR/quantum.json"

echo "=== Known Failures Lifecycle Integration Test ==="
echo ""

# =========================================================================
echo "--- Phase 1: capture_baseline with 0 failures ---"
# =========================================================================
echo "all_pass" > "$MOCK_CONTROL"

capture_baseline "$PROJECT_DIR" "$JSON_PATH" 2>/dev/null

# Verify baseline was set
BL_PASS=$(read_json_field "$JSON_PATH" "d['knownFailures']['baseline']['passCount']")
BL_FAIL=$(read_json_field "$JSON_PATH" "d['knownFailures']['baseline']['failCount']")
BL_TESTS=$(read_json_field "$JSON_PATH" "len(d['knownFailures']['baseline']['failingTests'])")
CUR_PASS=$(read_json_field "$JSON_PATH" "d['knownFailures']['current']['passCount']")
CUR_FAIL=$(read_json_field "$JSON_PATH" "d['knownFailures']['current']['failCount']")
CUR_TESTS=$(read_json_field "$JSON_PATH" "len(d['knownFailures']['current']['failingTests'])")

assert_eq "Phase 1: baseline passCount" "3" "$BL_PASS"
assert_eq "Phase 1: baseline failCount" "0" "$BL_FAIL"
assert_eq "Phase 1: baseline failingTests empty" "0" "$BL_TESTS"
assert_eq "Phase 1: current passCount" "3" "$CUR_PASS"
assert_eq "Phase 1: current failCount" "0" "$CUR_FAIL"
assert_eq "Phase 1: current failingTests empty" "0" "$CUR_TESTS"

# Verify flakyThreshold and fullSuiteTimeout defaults
FLAKY=$(read_json_field "$JSON_PATH" "d['knownFailures']['flakyThreshold']")
TIMEOUT=$(read_json_field "$JSON_PATH" "d['knownFailures']['fullSuiteTimeout']")
assert_eq "Phase 1: flakyThreshold default" "1" "$FLAKY"
assert_eq "Phase 1: fullSuiteTimeout default" "60" "$TIMEOUT"

echo ""

# =========================================================================
echo "--- Phase 2: delta_check detects 3 NEW regressions ---"
# =========================================================================
echo "three_failures" > "$MOCK_CONTROL"

# Set flakyThreshold to 0 so even 1 new failure is flagged
native_json=$(_to_native "$JSON_PATH")
python -c "
import json
with open('$native_json') as f:
    d = json.load(f)
d['knownFailures']['flakyThreshold'] = 0
with open('$native_json', 'w') as f:
    json.dump(d, f, indent=2)
" 2>/dev/null

DELTA_OUTPUT=$(delta_check "$PROJECT_DIR" "$JSON_PATH" "US-TEST" 2>/dev/null)
DELTA_EXIT=$?

assert_eq "Phase 2: delta_check returns non-zero" "1" "$DELTA_EXIT"
assert_contains "Phase 2: delta_check outputs test_fail_a" "test_fail_a" "$DELTA_OUTPUT"
assert_contains "Phase 2: delta_check outputs test_fail_b" "test_fail_b" "$DELTA_OUTPUT"
assert_contains "Phase 2: delta_check outputs test_fail_c" "test_fail_c" "$DELTA_OUTPUT"

echo ""

# =========================================================================
echo "--- Phase 3: capture_wave_snapshot adds failures to current ---"
# =========================================================================
capture_wave_snapshot "$PROJECT_DIR" "$JSON_PATH" 1 2>/dev/null

CUR_PASS=$(read_json_field "$JSON_PATH" "d['knownFailures']['current']['passCount']")
CUR_FAIL=$(read_json_field "$JSON_PATH" "d['knownFailures']['current']['failCount']")
CUR_TESTS=$(read_json_field "$JSON_PATH" "len(d['knownFailures']['current']['failingTests'])")
CUR_WAVE=$(read_json_field "$JSON_PATH" "d['knownFailures']['current']['wave']")

assert_eq "Phase 3: current passCount updated" "2" "$CUR_PASS"
assert_eq "Phase 3: current failCount updated" "3" "$CUR_FAIL"
assert_eq "Phase 3: current has 3 failingTests" "3" "$CUR_TESTS"
assert_eq "Phase 3: current wave is 1" "1" "$CUR_WAVE"

# Verify failing test names are recorded
TEST_NAMES=$(read_json_field "$JSON_PATH" "','.join(sorted(t['name'] for t in d['knownFailures']['current']['failingTests']))")
assert_contains "Phase 3: test_fail_a recorded" "test_fail_a" "$TEST_NAMES"
assert_contains "Phase 3: test_fail_b recorded" "test_fail_b" "$TEST_NAMES"
assert_contains "Phase 3: test_fail_c recorded" "test_fail_c" "$TEST_NAMES"

# Verify baseline is unchanged
BL_PASS=$(read_json_field "$JSON_PATH" "d['knownFailures']['baseline']['passCount']")
BL_FAIL=$(read_json_field "$JSON_PATH" "d['knownFailures']['baseline']['failCount']")
assert_eq "Phase 3: baseline passCount unchanged" "3" "$BL_PASS"
assert_eq "Phase 3: baseline failCount unchanged" "0" "$BL_FAIL"

echo ""

# =========================================================================
echo "--- Phase 4: delta_check with same failures returns 0 (all known) ---"
# =========================================================================
# Mock still produces the same 3 failures
DELTA_OUTPUT=$(delta_check "$PROJECT_DIR" "$JSON_PATH" "US-TEST" 2>/dev/null)
DELTA_EXIT=$?

assert_eq "Phase 4: delta_check returns 0 (all known)" "0" "$DELTA_EXIT"

echo ""

# =========================================================================
echo "--- Phase 5: resolve all failures, capture_wave_snapshot clears them ---"
# =========================================================================
echo "resolved" > "$MOCK_CONTROL"

capture_wave_snapshot "$PROJECT_DIR" "$JSON_PATH" 2 2>/dev/null

CUR_PASS=$(read_json_field "$JSON_PATH" "d['knownFailures']['current']['passCount']")
CUR_FAIL=$(read_json_field "$JSON_PATH" "d['knownFailures']['current']['failCount']")
CUR_TESTS=$(read_json_field "$JSON_PATH" "len(d['knownFailures']['current']['failingTests'])")
CUR_WAVE=$(read_json_field "$JSON_PATH" "d['knownFailures']['current']['wave']")

assert_eq "Phase 5: current passCount after resolve" "5" "$CUR_PASS"
assert_eq "Phase 5: current failCount after resolve" "0" "$CUR_FAIL"
assert_eq "Phase 5: failingTests emptied" "0" "$CUR_TESTS"
assert_eq "Phase 5: current wave is 2" "2" "$CUR_WAVE"

# Verify baseline is still the original
BL_PASS=$(read_json_field "$JSON_PATH" "d['knownFailures']['baseline']['passCount']")
assert_eq "Phase 5: baseline still original" "3" "$BL_PASS"

echo ""

# =========================================================================
echo "--- Edge case: delta_check after resolution sees 0 failures ---"
# =========================================================================
DELTA_OUTPUT=$(delta_check "$PROJECT_DIR" "$JSON_PATH" "US-TEST" 2>/dev/null)
DELTA_EXIT=$?
assert_eq "Edge: delta_check after resolve returns 0" "0" "$DELTA_EXIT"

echo ""

# =========================================================================
echo "--- Edge case: partial resolution (1 of 3 tests fixed) ---"
# =========================================================================
# Reset: re-introduce 3 failures, snapshot them as known
echo "three_failures" > "$MOCK_CONTROL"
capture_wave_snapshot "$PROJECT_DIR" "$JSON_PATH" 3 2>/dev/null

# Create a partial fix mock (1 of 3 failures fixed, 2 remain)
cat > "$MOCK_BIN/pytest" <<MOCKEOF2
#!/usr/bin/env bash
CONTROL_FILE="$MOCK_CONTROL"
MODE=\$(cat "\$CONTROL_FILE" 2>/dev/null || echo "all_pass")
case "\$MODE" in
  all_pass)
    echo "test_alpha.py::test_one PASSED"
    echo "test_alpha.py::test_two PASSED"
    echo "test_alpha.py::test_three PASSED"
    echo "3 passed"
    ;;
  three_failures)
    echo "test_alpha.py::test_one PASSED"
    echo "test_alpha.py::test_two PASSED"
    echo "test_beta.py::test_fail_a FAILED"
    echo "test_beta.py::test_fail_b FAILED"
    echo "test_beta.py::test_fail_c FAILED"
    echo "2 passed, 3 failed"
    exit 1
    ;;
  partial_fix)
    echo "test_alpha.py::test_one PASSED"
    echo "test_alpha.py::test_two PASSED"
    echo "test_beta.py::test_fail_a PASSED"
    echo "test_beta.py::test_fail_b FAILED"
    echo "test_beta.py::test_fail_c FAILED"
    echo "3 passed, 2 failed"
    exit 1
    ;;
  resolved)
    echo "test_alpha.py::test_one PASSED"
    echo "test_alpha.py::test_two PASSED"
    echo "test_alpha.py::test_three PASSED"
    echo "test_beta.py::test_fix_a PASSED"
    echo "test_beta.py::test_fix_b PASSED"
    echo "5 passed"
    ;;
esac
exit 0
MOCKEOF2
chmod +x "$MOCK_BIN/pytest"

echo "partial_fix" > "$MOCK_CONTROL"
capture_wave_snapshot "$PROJECT_DIR" "$JSON_PATH" 4 2>/dev/null

CUR_TESTS=$(read_json_field "$JSON_PATH" "len(d['knownFailures']['current']['failingTests'])")
CUR_FAIL=$(read_json_field "$JSON_PATH" "d['knownFailures']['current']['failCount']")
assert_eq "Partial: 2 failingTests remain" "2" "$CUR_TESTS"
assert_eq "Partial: failCount is 2" "2" "$CUR_FAIL"

# delta_check should see 0 new failures (the remaining 2 are known)
DELTA_OUTPUT=$(delta_check "$PROJECT_DIR" "$JSON_PATH" "US-TEST" 2>/dev/null)
DELTA_EXIT=$?
assert_eq "Partial: delta_check returns 0 (remaining are known)" "0" "$DELTA_EXIT"

echo ""

# =========================================================================
echo "--- Edge case: re-introduction of failures after full resolve ---"
# =========================================================================
echo "resolved" > "$MOCK_CONTROL"
capture_wave_snapshot "$PROJECT_DIR" "$JSON_PATH" 5 2>/dev/null

CUR_TESTS=$(read_json_field "$JSON_PATH" "len(d['knownFailures']['current']['failingTests'])")
assert_eq "Re-intro: failingTests fully resolved" "0" "$CUR_TESTS"

# Now re-introduce failures
echo "three_failures" > "$MOCK_CONTROL"
DELTA_OUTPUT=$(delta_check "$PROJECT_DIR" "$JSON_PATH" "US-TEST" 2>/dev/null)
DELTA_EXIT=$?
assert_eq "Re-intro: delta_check returns 1 (new regressions)" "1" "$DELTA_EXIT"
assert_contains "Re-intro: delta_check outputs test_fail_a" "test_fail_a" "$DELTA_OUTPUT"

echo ""

# =========================================================================
echo "--- Edge case: updatedAt timestamp changes each wave ---"
# =========================================================================
UPDATED_1=$(read_json_field "$JSON_PATH" "d['knownFailures']['current']['updatedAt']")
echo "resolved" > "$MOCK_CONTROL"
# Small delay to ensure timestamps differ (Windows might have low resolution)
sleep 1
capture_wave_snapshot "$PROJECT_DIR" "$JSON_PATH" 6 2>/dev/null
UPDATED_2=$(read_json_field "$JSON_PATH" "d['knownFailures']['current']['updatedAt']")

TOTAL=$((TOTAL + 1))
if [[ "$UPDATED_1" != "$UPDATED_2" ]]; then
  echo "  PASS: updatedAt changes between waves"
  PASS=$((PASS + 1))
else
  echo "  FAIL: updatedAt did not change between waves"
  echo "    both: $UPDATED_1"
  FAIL=$((FAIL + 1))
fi

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
