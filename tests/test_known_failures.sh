#!/usr/bin/env bash
# Test suite for lib/known-failures.sh
# Tests detect_test_runner, capture_baseline, capture_wave_snapshot, delta_check, format_agent_context

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="$SCRIPT_DIR/../lib"
PASS=0
FAIL=0
TOTAL=0

# Source the library under test
if [[ ! -f "$LIB_DIR/known-failures.sh" ]]; then
  echo "SKIP: lib/known-failures.sh not found (RED phase)"
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

assert_not_empty() {
  local test_name="$1" actual="$2"
  TOTAL=$((TOTAL + 1))
  if [[ -n "$actual" ]]; then
    echo "  PASS: $test_name"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: $test_name (expected non-empty)"
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
# Usage: read_json_field "/path/to/file.json" "python expression using d"
read_json_field() {
  local json_file="$1"
  local expr="$2"
  local native_path
  native_path=$(_to_native "$json_file")
  python -c "import json; d=json.load(open('$native_path')); print($expr)" 2>/dev/null
}

# =========================================================================
# Setup: create temporary directories for testing
# =========================================================================
TMPDIR_BASE=$(mktemp -d)
trap 'rm -rf "$TMPDIR_BASE"' EXIT

# =========================================================================
echo "=== Test T-014: detect_test_runner ==="
# =========================================================================

echo "--- T-014a: detect jest from package.json ---"
JEST_REPO="$TMPDIR_BASE/jest-repo"
mkdir -p "$JEST_REPO"
cat > "$JEST_REPO/package.json" << 'EJSON'
{
  "name": "test-app",
  "devDependencies": {
    "jest": "^29.0.0",
    "typescript": "^5.0.0"
  }
}
EJSON
RESULT=$(detect_test_runner "$JEST_REPO")
assert_contains "jest detected" "jest:" "$RESULT"
assert_contains "jest command includes npx jest" "npx jest" "$RESULT"

echo "--- T-014b: detect vitest from package.json ---"
VITEST_REPO="$TMPDIR_BASE/vitest-repo"
mkdir -p "$VITEST_REPO"
cat > "$VITEST_REPO/package.json" << 'EJSON'
{
  "name": "test-app",
  "devDependencies": {
    "vitest": "^1.0.0"
  }
}
EJSON
RESULT=$(detect_test_runner "$VITEST_REPO")
assert_contains "vitest detected" "vitest:" "$RESULT"
assert_contains "vitest command includes npx vitest" "npx vitest" "$RESULT"

echo "--- T-014c: detect pytest from pyproject.toml ---"
PYTEST_REPO="$TMPDIR_BASE/pytest-repo"
mkdir -p "$PYTEST_REPO"
cat > "$PYTEST_REPO/pyproject.toml" << 'ETOML'
[tool.pytest.ini_options]
testpaths = ["tests"]
ETOML
RESULT=$(detect_test_runner "$PYTEST_REPO")
assert_contains "pytest detected from pyproject.toml" "pytest:" "$RESULT"
assert_contains "pytest command" "pytest" "$RESULT"

echo "--- T-014d: detect pytest from pytest.ini ---"
PYTESTINI_REPO="$TMPDIR_BASE/pytestini-repo"
mkdir -p "$PYTESTINI_REPO"
cat > "$PYTESTINI_REPO/pytest.ini" << 'EINI'
[pytest]
testpaths = tests
EINI
RESULT=$(detect_test_runner "$PYTESTINI_REPO")
assert_contains "pytest detected from pytest.ini" "pytest:" "$RESULT"

echo "--- T-014e: detect pytest from setup.cfg ---"
SETUPCFG_REPO="$TMPDIR_BASE/setupcfg-repo"
mkdir -p "$SETUPCFG_REPO"
cat > "$SETUPCFG_REPO/setup.cfg" << 'ECFG'
[tool:pytest]
testpaths = tests
ECFG
RESULT=$(detect_test_runner "$SETUPCFG_REPO")
assert_contains "pytest detected from setup.cfg" "pytest:" "$RESULT"

echo "--- T-014f: detect go test from go.mod ---"
GO_REPO="$TMPDIR_BASE/go-repo"
mkdir -p "$GO_REPO"
cat > "$GO_REPO/go.mod" << 'EMOD'
module example.com/myapp
go 1.21
EMOD
RESULT=$(detect_test_runner "$GO_REPO")
assert_contains "go detected" "go:" "$RESULT"
assert_contains "go test command" "go test" "$RESULT"

echo "--- T-014g: empty repo returns empty ---"
EMPTY_REPO="$TMPDIR_BASE/empty-repo"
mkdir -p "$EMPTY_REPO"
RESULT=$(detect_test_runner "$EMPTY_REPO")
assert_empty "empty repo returns empty" "$RESULT"

echo "--- T-014h: nonexistent directory returns empty ---"
RESULT=$(detect_test_runner "$TMPDIR_BASE/does-not-exist")
assert_empty "nonexistent dir returns empty" "$RESULT"

echo "--- T-014i: jest takes priority over vitest when both present ---"
BOTH_REPO="$TMPDIR_BASE/both-repo"
mkdir -p "$BOTH_REPO"
cat > "$BOTH_REPO/package.json" << 'EJSON'
{
  "devDependencies": {
    "jest": "^29.0.0",
    "vitest": "^1.0.0"
  }
}
EJSON
RESULT=$(detect_test_runner "$BOTH_REPO")
assert_contains "jest takes priority" "jest:" "$RESULT"

echo "--- T-014j: package.json without test deps returns empty ---"
NOTEST_REPO="$TMPDIR_BASE/notest-repo"
mkdir -p "$NOTEST_REPO"
cat > "$NOTEST_REPO/package.json" << 'EJSON'
{
  "name": "my-app",
  "dependencies": {
    "express": "^4.0.0"
  }
}
EJSON
RESULT=$(detect_test_runner "$NOTEST_REPO")
assert_empty "package.json without test deps returns empty" "$RESULT"

# =========================================================================
echo "=== Test T-015: capture_baseline ==="
# =========================================================================

echo "--- T-015a: capture_baseline with jest JSON output ---"
JEST_BL_REPO="$TMPDIR_BASE/jest-bl-repo"
mkdir -p "$JEST_BL_REPO"
cat > "$JEST_BL_REPO/package.json" << 'EJSON'
{
  "devDependencies": { "jest": "^29.0.0" }
}
EJSON
# Create a mock npx that outputs jest JSON
mkdir -p "$JEST_BL_REPO/.bin"
cat > "$JEST_BL_REPO/.bin/npx" << 'ESCRIPT'
#!/usr/bin/env bash
cat << 'EJESTJSON'
{
  "numPassedTests": 10,
  "numFailedTests": 2,
  "numPendingTests": 1,
  "testResults": [
    {"name": "test_a.test.js", "status": "passed"},
    {"name": "test_b.test.js", "status": "failed", "message": "Expected true to be false"},
    {"name": "test_c.test.js", "status": "passed"},
    {"name": "test_d.test.js", "status": "failed", "message": "Timeout after 5000ms"},
    {"name": "test_e.test.js", "status": "pending"}
  ]
}
EJESTJSON
ESCRIPT
chmod +x "$JEST_BL_REPO/.bin/npx"
# Create quantum.json
cat > "$JEST_BL_REPO/quantum.json" << 'EQJSON'
{"stories": []}
EQJSON
# Run capture_baseline with mock PATH
OLD_PATH="$PATH"
export PATH="$JEST_BL_REPO/.bin:$PATH"
OUTPUT=$(capture_baseline "$JEST_BL_REPO" "$JEST_BL_REPO/quantum.json" 2>&1)
export PATH="$OLD_PATH"
# Verify baseline was written
BL_PASS=$(read_json_field "$JEST_BL_REPO/quantum.json" "d.get('knownFailures',{}).get('baseline',{}).get('passCount','MISSING')")
BL_FAIL=$(read_json_field "$JEST_BL_REPO/quantum.json" "d.get('knownFailures',{}).get('baseline',{}).get('failCount','MISSING')")
BL_SKIP=$(read_json_field "$JEST_BL_REPO/quantum.json" "d.get('knownFailures',{}).get('baseline',{}).get('skipCount','MISSING')")
assert_eq "jest baseline passCount" "10" "$BL_PASS"
assert_eq "jest baseline failCount" "2" "$BL_FAIL"
assert_eq "jest baseline skipCount" "1" "$BL_SKIP"
# Verify current is also set
CUR_PASS=$(read_json_field "$JEST_BL_REPO/quantum.json" "d.get('knownFailures',{}).get('current',{}).get('passCount','MISSING')")
assert_eq "jest current initialized from baseline" "10" "$CUR_PASS"
# Verify failing test names
FAIL_NAMES=$(read_json_field "$JEST_BL_REPO/quantum.json" "','.join(t['name'] for t in d.get('knownFailures',{}).get('baseline',{}).get('failingTests',[]))")
assert_contains "jest failing tests include test_b" "test_b" "$FAIL_NAMES"
assert_contains "jest failing tests include test_d" "test_d" "$FAIL_NAMES"
# Verify log output
assert_contains "capture_baseline logs baseline" "KNOWN-FAILURES" "$OUTPUT"

echo "--- T-015b: capture_baseline with pytest output ---"
PYTEST_BL_REPO="$TMPDIR_BASE/pytest-bl-repo"
mkdir -p "$PYTEST_BL_REPO"
cat > "$PYTEST_BL_REPO/pyproject.toml" << 'ETOML'
[tool.pytest.ini_options]
testpaths = ["tests"]
ETOML
mkdir -p "$PYTEST_BL_REPO/.bin"
cat > "$PYTEST_BL_REPO/.bin/pytest" << 'ESCRIPT'
#!/usr/bin/env bash
cat << 'EPYTEST'
tests/test_auth.py::test_login PASSED
tests/test_auth.py::test_logout PASSED
tests/test_auth.py::test_refresh FAILED
tests/test_api.py::test_create PASSED
tests/test_api.py::test_delete FAILED
tests/test_api.py::test_skip SKIPPED
3 passed, 2 failed, 1 skipped
EPYTEST
exit 1
ESCRIPT
chmod +x "$PYTEST_BL_REPO/.bin/pytest"
cat > "$PYTEST_BL_REPO/quantum.json" << 'EQJSON'
{"stories": []}
EQJSON
export PATH="$PYTEST_BL_REPO/.bin:$PATH"
OUTPUT=$(capture_baseline "$PYTEST_BL_REPO" "$PYTEST_BL_REPO/quantum.json" 2>&1)
export PATH="$OLD_PATH"
BL_PASS=$(read_json_field "$PYTEST_BL_REPO/quantum.json" "d.get('knownFailures',{}).get('baseline',{}).get('passCount','MISSING')")
BL_FAIL=$(read_json_field "$PYTEST_BL_REPO/quantum.json" "d.get('knownFailures',{}).get('baseline',{}).get('failCount','MISSING')")
BL_SKIP=$(read_json_field "$PYTEST_BL_REPO/quantum.json" "d.get('knownFailures',{}).get('baseline',{}).get('skipCount','MISSING')")
assert_eq "pytest baseline passCount" "3" "$BL_PASS"
assert_eq "pytest baseline failCount" "2" "$BL_FAIL"
assert_eq "pytest baseline skipCount" "1" "$BL_SKIP"

echo "--- T-015c: capture_baseline with go test output ---"
GO_BL_REPO="$TMPDIR_BASE/go-bl-repo"
mkdir -p "$GO_BL_REPO"
cat > "$GO_BL_REPO/go.mod" << 'EMOD'
module example.com/myapp
go 1.21
EMOD
mkdir -p "$GO_BL_REPO/.bin"
cat > "$GO_BL_REPO/.bin/go" << 'ESCRIPT'
#!/usr/bin/env bash
cat << 'EGOTEST'
=== RUN   TestAdd
--- PASS: TestAdd (0.00s)
=== RUN   TestSub
--- PASS: TestSub (0.00s)
=== RUN   TestMul
--- FAIL: TestMul (0.00s)
    mul_test.go:15: expected 6, got 5
=== RUN   TestDiv
--- PASS: TestDiv (0.00s)
=== RUN   TestDivZero
--- SKIP: TestDivZero (0.00s)
FAIL
EGOTEST
exit 1
ESCRIPT
chmod +x "$GO_BL_REPO/.bin/go"
cat > "$GO_BL_REPO/quantum.json" << 'EQJSON'
{"stories": []}
EQJSON
export PATH="$GO_BL_REPO/.bin:$PATH"
OUTPUT=$(capture_baseline "$GO_BL_REPO" "$GO_BL_REPO/quantum.json" 2>&1)
export PATH="$OLD_PATH"
BL_PASS=$(read_json_field "$GO_BL_REPO/quantum.json" "d.get('knownFailures',{}).get('baseline',{}).get('passCount','MISSING')")
BL_FAIL=$(read_json_field "$GO_BL_REPO/quantum.json" "d.get('knownFailures',{}).get('baseline',{}).get('failCount','MISSING')")
BL_SKIP=$(read_json_field "$GO_BL_REPO/quantum.json" "d.get('knownFailures',{}).get('baseline',{}).get('skipCount','MISSING')")
assert_eq "go baseline passCount" "3" "$BL_PASS"
assert_eq "go baseline failCount" "1" "$BL_FAIL"
assert_eq "go baseline skipCount" "1" "$BL_SKIP"

echo "--- T-015d: capture_baseline with unparseable output falls back to regex ---"
REGEX_BL_REPO="$TMPDIR_BASE/regex-bl-repo"
mkdir -p "$REGEX_BL_REPO"
cat > "$REGEX_BL_REPO/pyproject.toml" << 'ETOML'
[tool.pytest.ini_options]
testpaths = ["tests"]
ETOML
mkdir -p "$REGEX_BL_REPO/.bin"
cat > "$REGEX_BL_REPO/.bin/pytest" << 'ESCRIPT'
#!/usr/bin/env bash
# Garbled output that fails structured parse but has PASS/FAIL keywords
echo "Running tests..."
echo "PASS: test_one"
echo "PASS: test_two"
echo "FAIL: test_three"
echo "FAIL: test_four"
echo "ERROR: test_five"
echo "Done."
exit 1
ESCRIPT
chmod +x "$REGEX_BL_REPO/.bin/pytest"
cat > "$REGEX_BL_REPO/quantum.json" << 'EQJSON'
{"stories": []}
EQJSON
export PATH="$REGEX_BL_REPO/.bin:$PATH"
OUTPUT=$(capture_baseline "$REGEX_BL_REPO" "$REGEX_BL_REPO/quantum.json" 2>&1)
export PATH="$OLD_PATH"
BL_PASS=$(read_json_field "$REGEX_BL_REPO/quantum.json" "d.get('knownFailures',{}).get('baseline',{}).get('passCount','MISSING')")
BL_FAIL=$(read_json_field "$REGEX_BL_REPO/quantum.json" "d.get('knownFailures',{}).get('baseline',{}).get('failCount','MISSING')")
# Regex should count PASS/FAIL/ERROR lines (ERROR counts as failure)
assert_eq "regex fallback passCount" "2" "$BL_PASS"
assert_eq "regex fallback failCount" "3" "$BL_FAIL"

echo "--- T-015e: capture_baseline with no test runner returns gracefully ---"
NORT_REPO="$TMPDIR_BASE/nort-repo"
mkdir -p "$NORT_REPO"
cat > "$NORT_REPO/quantum.json" << 'EQJSON'
{"stories": []}
EQJSON
OUTPUT=$(capture_baseline "$NORT_REPO" "$NORT_REPO/quantum.json" 2>&1)
EXIT_CODE=$?
BL_VAL=$(read_json_field "$NORT_REPO/quantum.json" "d.get('knownFailures',{}).get('baseline', 'NOT_SET')")
assert_eq "no runner: baseline is null" "None" "$BL_VAL"

# =========================================================================
echo "=== Test T-016: capture_wave_snapshot ==="
# =========================================================================

echo "--- T-016a: capture_wave_snapshot detects new failures ---"
WAVE_REPO="$TMPDIR_BASE/wave-repo"
mkdir -p "$WAVE_REPO/.bin"
cat > "$WAVE_REPO/pyproject.toml" << 'ETOML'
[tool.pytest.ini_options]
testpaths = ["tests"]
ETOML
# Mock pytest that has a NEW failure compared to baseline
cat > "$WAVE_REPO/.bin/pytest" << 'ESCRIPT'
#!/usr/bin/env bash
cat << 'EPYTEST'
tests/test_auth.py::test_login PASSED
tests/test_auth.py::test_logout PASSED
tests/test_auth.py::test_refresh FAILED
tests/test_api.py::test_create PASSED
tests/test_api.py::test_delete PASSED
tests/test_api.py::test_new_feature FAILED
3 passed, 2 failed, 0 skipped
EPYTEST
exit 1
ESCRIPT
chmod +x "$WAVE_REPO/.bin/pytest"
# Set up quantum.json with existing baseline (1 known failure)
WAVE_NATIVE=$(_to_native "$WAVE_REPO/quantum.json")
python -c "
import json
d = {
    'stories': [{'id': 'US-001', 'status': 'passed', 'fixes': []}],
    'knownFailures': {
        'baseline': {
            'capturedAt': '2026-03-20T00:00:00Z', 'wave': 0,
            'passCount': 4, 'failCount': 1, 'skipCount': 0,
            'failingTests': [
                {'name': 'tests/test_auth.py::test_refresh', 'failingSince': 1, 'introducedBy': None, 'expectedFix': None, 'error': ''}
            ]
        },
        'current': {
            'updatedAt': '2026-03-20T00:00:00Z', 'capturedAt': '2026-03-20T00:00:00Z', 'wave': 0,
            'passCount': 4, 'failCount': 1, 'skipCount': 0,
            'failingTests': [
                {'name': 'tests/test_auth.py::test_refresh', 'failingSince': 1, 'introducedBy': None, 'expectedFix': None, 'error': ''}
            ]
        },
        'flakyThreshold': 1,
        'fullSuiteTimeout': 60
    }
}
with open('$WAVE_NATIVE', 'w') as f:
    json.dump(d, f, indent=2)
"
export PATH="$WAVE_REPO/.bin:$PATH"
OUTPUT=$(capture_wave_snapshot "$WAVE_REPO" "$WAVE_REPO/quantum.json" 2 2>&1)
export PATH="$OLD_PATH"
# Verify new failure added
CUR_FAIL_COUNT=$(read_json_field "$WAVE_REPO/quantum.json" "d.get('knownFailures',{}).get('current',{}).get('failCount','MISSING')")
assert_eq "wave snapshot failCount" "2" "$CUR_FAIL_COUNT"
CUR_WAVE=$(read_json_field "$WAVE_REPO/quantum.json" "d.get('knownFailures',{}).get('current',{}).get('wave','MISSING')")
assert_eq "wave snapshot wave num" "2" "$CUR_WAVE"
# Verify new failure is in failingTests
NEW_FAIL=$(read_json_field "$WAVE_REPO/quantum.json" "','.join(t['name'] for t in d.get('knownFailures',{}).get('current',{}).get('failingTests',[]))")
assert_contains "wave snapshot has new failure" "test_new_feature" "$NEW_FAIL"
assert_contains "wave snapshot keeps known failure" "test_refresh" "$NEW_FAIL"
# Verify log
assert_contains "wave snapshot logs delta" "KNOWN-FAILURES" "$OUTPUT"

echo "--- T-016b: capture_wave_snapshot detects resolved failures ---"
RESOLVE_REPO="$TMPDIR_BASE/resolve-repo"
mkdir -p "$RESOLVE_REPO/.bin"
cat > "$RESOLVE_REPO/pyproject.toml" << 'ETOML'
[tool.pytest.ini_options]
testpaths = ["tests"]
ETOML
# All tests pass now -- the known failure is resolved
cat > "$RESOLVE_REPO/.bin/pytest" << 'ESCRIPT'
#!/usr/bin/env bash
cat << 'EPYTEST'
tests/test_auth.py::test_login PASSED
tests/test_auth.py::test_refresh PASSED
tests/test_api.py::test_create PASSED
3 passed, 0 failed, 0 skipped
EPYTEST
exit 0
ESCRIPT
chmod +x "$RESOLVE_REPO/.bin/pytest"
RESOLVE_NATIVE=$(_to_native "$RESOLVE_REPO/quantum.json")
python -c "
import json
d = {
    'stories': [],
    'knownFailures': {
        'baseline': {
            'capturedAt': '2026-03-20T00:00:00Z', 'wave': 0,
            'passCount': 2, 'failCount': 1, 'skipCount': 0,
            'failingTests': [
                {'name': 'tests/test_auth.py::test_refresh', 'failingSince': 0, 'introducedBy': None, 'expectedFix': None, 'error': 'err'}
            ]
        },
        'current': {
            'updatedAt': '2026-03-20T00:00:00Z', 'capturedAt': '2026-03-20T00:00:00Z', 'wave': 1,
            'passCount': 2, 'failCount': 1, 'skipCount': 0,
            'failingTests': [
                {'name': 'tests/test_auth.py::test_refresh', 'failingSince': 0, 'introducedBy': None, 'expectedFix': None, 'error': 'err'}
            ]
        },
        'flakyThreshold': 1,
        'fullSuiteTimeout': 60
    }
}
with open('$RESOLVE_NATIVE', 'w') as f:
    json.dump(d, f, indent=2)
"
export PATH="$RESOLVE_REPO/.bin:$PATH"
OUTPUT=$(capture_wave_snapshot "$RESOLVE_REPO" "$RESOLVE_REPO/quantum.json" 3 2>&1)
export PATH="$OLD_PATH"
CUR_FAIL_COUNT=$(read_json_field "$RESOLVE_REPO/quantum.json" "d.get('knownFailures',{}).get('current',{}).get('failCount','MISSING')")
assert_eq "resolved failure: failCount is 0" "0" "$CUR_FAIL_COUNT"
CUR_FAIL_TESTS=$(read_json_field "$RESOLVE_REPO/quantum.json" "len(d.get('knownFailures',{}).get('current',{}).get('failingTests',[]))")
assert_eq "resolved failure: failingTests empty" "0" "$CUR_FAIL_TESTS"

# =========================================================================
echo "=== Test T-017: delta_check ==="
# =========================================================================

echo "--- T-017a: delta_check with only known failures returns 0 ---"
DC_REPO="$TMPDIR_BASE/dc-repo"
mkdir -p "$DC_REPO/.bin"
cat > "$DC_REPO/pyproject.toml" << 'ETOML'
[tool.pytest.ini_options]
testpaths = ["tests"]
ETOML
cat > "$DC_REPO/.bin/pytest" << 'ESCRIPT'
#!/usr/bin/env bash
cat << 'EPYTEST'
tests/test_a.py::test_one PASSED
tests/test_a.py::test_two FAILED
2 passed, 1 failed, 0 skipped
EPYTEST
exit 1
ESCRIPT
chmod +x "$DC_REPO/.bin/pytest"
DC_NATIVE=$(_to_native "$DC_REPO/quantum.json")
python -c "
import json
d = {
    'stories': [],
    'knownFailures': {
        'current': {
            'updatedAt': '2026-03-20T00:00:00Z', 'wave': 1,
            'passCount': 2, 'failCount': 1, 'skipCount': 0,
            'failingTests': [
                {'name': 'tests/test_a.py::test_two', 'failingSince': 0, 'introducedBy': None, 'expectedFix': None, 'error': ''}
            ]
        },
        'flakyThreshold': 1,
        'fullSuiteTimeout': 60
    }
}
with open('$DC_NATIVE', 'w') as f:
    json.dump(d, f, indent=2)
"
export PATH="$DC_REPO/.bin:$PATH"
OUTPUT=$(delta_check "$DC_REPO" "$DC_REPO/quantum.json" "US-001" 2>&1)
DC_EXIT=$?
export PATH="$OLD_PATH"
assert_eq "delta_check known failures returns 0" "0" "$DC_EXIT"
assert_contains "delta_check logs known failures" "known failures present" "$OUTPUT"

echo "--- T-017b: delta_check with new failure above threshold returns 1 ---"
DC2_REPO="$TMPDIR_BASE/dc2-repo"
mkdir -p "$DC2_REPO/.bin"
cat > "$DC2_REPO/pyproject.toml" << 'ETOML'
[tool.pytest.ini_options]
testpaths = ["tests"]
ETOML
# Two new failures -- above flakyThreshold of 1
cat > "$DC2_REPO/.bin/pytest" << 'ESCRIPT'
#!/usr/bin/env bash
cat << 'EPYTEST'
tests/test_a.py::test_one PASSED
tests/test_a.py::test_two FAILED
tests/test_a.py::test_three FAILED
tests/test_a.py::test_four FAILED
1 passed, 3 failed, 0 skipped
EPYTEST
exit 1
ESCRIPT
chmod +x "$DC2_REPO/.bin/pytest"
DC2_NATIVE=$(_to_native "$DC2_REPO/quantum.json")
python -c "
import json
d = {
    'stories': [],
    'knownFailures': {
        'current': {
            'updatedAt': '2026-03-20T00:00:00Z', 'wave': 1,
            'passCount': 3, 'failCount': 1, 'skipCount': 0,
            'failingTests': [
                {'name': 'tests/test_a.py::test_two', 'failingSince': 0, 'introducedBy': None, 'expectedFix': None, 'error': ''}
            ]
        },
        'flakyThreshold': 1,
        'fullSuiteTimeout': 60
    }
}
with open('$DC2_NATIVE', 'w') as f:
    json.dump(d, f, indent=2)
"
export PATH="$DC2_REPO/.bin:$PATH"
OUTPUT=$(delta_check "$DC2_REPO" "$DC2_REPO/quantum.json" "US-002" 2>&1)
DC_EXIT=$?
export PATH="$OLD_PATH"
assert_eq "delta_check new failures returns 1" "1" "$DC_EXIT"
assert_contains "delta_check output includes new failure name" "test_three" "$OUTPUT"

echo "--- T-017c: delta_check with new failure at threshold returns 0 ---"
DC3_REPO="$TMPDIR_BASE/dc3-repo"
mkdir -p "$DC3_REPO/.bin"
cat > "$DC3_REPO/pyproject.toml" << 'ETOML'
[tool.pytest.ini_options]
testpaths = ["tests"]
ETOML
# One new failure (test_three) -- exactly at flakyThreshold of 1
cat > "$DC3_REPO/.bin/pytest" << 'ESCRIPT'
#!/usr/bin/env bash
cat << 'EPYTEST'
tests/test_a.py::test_one PASSED
tests/test_a.py::test_two FAILED
tests/test_a.py::test_three FAILED
1 passed, 2 failed, 0 skipped
EPYTEST
exit 1
ESCRIPT
chmod +x "$DC3_REPO/.bin/pytest"
DC3_NATIVE=$(_to_native "$DC3_REPO/quantum.json")
python -c "
import json
d = {
    'stories': [],
    'knownFailures': {
        'current': {
            'updatedAt': '2026-03-20T00:00:00Z', 'wave': 1,
            'passCount': 2, 'failCount': 1, 'skipCount': 0,
            'failingTests': [
                {'name': 'tests/test_a.py::test_two', 'failingSince': 0, 'introducedBy': None, 'expectedFix': None, 'error': ''}
            ]
        },
        'flakyThreshold': 1,
        'fullSuiteTimeout': 60
    }
}
with open('$DC3_NATIVE', 'w') as f:
    json.dump(d, f, indent=2)
"
export PATH="$DC3_REPO/.bin:$PATH"
OUTPUT=$(delta_check "$DC3_REPO" "$DC3_REPO/quantum.json" "US-003" 2>&1)
DC_EXIT=$?
export PATH="$OLD_PATH"
assert_eq "delta_check at flaky threshold returns 0" "0" "$DC_EXIT"
assert_contains "delta_check logs flaky threshold" "flaky threshold" "$OUTPUT"

echo "--- T-017d: delta_check logs timing ---"
assert_contains "delta_check logs timing" "completed in" "$OUTPUT"

# =========================================================================
echo "=== Test T-018: format_agent_context ==="
# =========================================================================

echo "--- T-018a: format_agent_context with failing tests ---"
FMT_REPO="$TMPDIR_BASE/fmt-repo"
mkdir -p "$FMT_REPO"
FMT_NATIVE=$(_to_native "$FMT_REPO/quantum.json")
python -c "
import json
d = {
    'knownFailures': {
        'current': {
            'failingTests': [
                {'name': 'test_auth::test_refresh', 'failingSince': 1, 'introducedBy': 'US-010', 'expectedFix': 'US-015', 'error': 'timeout'},
                {'name': 'test_api::test_delete', 'failingSince': 2, 'introducedBy': None, 'expectedFix': None, 'error': 'not found'}
            ]
        }
    }
}
with open('$FMT_NATIVE', 'w') as f:
    json.dump(d, f, indent=2)
"
OUTPUT=$(format_agent_context "$FMT_REPO/quantum.json")
assert_contains "format includes header" "Known failing tests" "$OUTPUT"
assert_contains "format includes test name" "test_auth::test_refresh" "$OUTPUT"
assert_contains "format includes wave info" "Wave 1" "$OUTPUT"
assert_contains "format includes expected fix" "US-015" "$OUTPUT"
assert_contains "format includes unknown fix" "unknown" "$OUTPUT"
assert_contains "format includes not-your-fault" "not your fault" "$OUTPUT"
assert_contains "format includes new-failure warning" "NEW failures" "$OUTPUT"

echo "--- T-018b: format_agent_context with no failing tests ---"
FMT2_REPO="$TMPDIR_BASE/fmt2-repo"
mkdir -p "$FMT2_REPO"
FMT2_NATIVE=$(_to_native "$FMT2_REPO/quantum.json")
python -c "
import json
d = {
    'knownFailures': {
        'current': {
            'failingTests': []
        }
    }
}
with open('$FMT2_NATIVE', 'w') as f:
    json.dump(d, f, indent=2)
"
OUTPUT=$(format_agent_context "$FMT2_REPO/quantum.json")
assert_empty "format with no failures returns empty" "$OUTPUT"

echo "--- T-018c: format_agent_context with null knownFailures ---"
FMT3_REPO="$TMPDIR_BASE/fmt3-repo"
mkdir -p "$FMT3_REPO"
FMT3_NATIVE=$(_to_native "$FMT3_REPO/quantum.json")
python -c "
import json
d = {'knownFailures': None}
with open('$FMT3_NATIVE', 'w') as f:
    json.dump(d, f, indent=2)
"
OUTPUT=$(format_agent_context "$FMT3_REPO/quantum.json")
assert_empty "format with null knownFailures returns empty" "$OUTPUT"

echo "--- T-018d: format_agent_context with missing knownFailures ---"
FMT4_REPO="$TMPDIR_BASE/fmt4-repo"
mkdir -p "$FMT4_REPO"
FMT4_NATIVE=$(_to_native "$FMT4_REPO/quantum.json")
python -c "
import json
d = {'stories': []}
with open('$FMT4_NATIVE', 'w') as f:
    json.dump(d, f, indent=2)
"
OUTPUT=$(format_agent_context "$FMT4_REPO/quantum.json")
assert_empty "format with missing knownFailures returns empty" "$OUTPUT"

# =========================================================================
echo "=== Test T-033: Additional detect_test_runner and capture_baseline ==="
# =========================================================================

echo "--- T-033a: capture_baseline with clean suite (10 pass, 0 fail) ---"
CLEAN_REPO="$TMPDIR_BASE/clean-repo"
mkdir -p "$CLEAN_REPO/.bin"
cat > "$CLEAN_REPO/package.json" << 'EJSON'
{
  "devDependencies": { "jest": "^29.0.0" }
}
EJSON
cat > "$CLEAN_REPO/.bin/npx" << 'ESCRIPT'
#!/usr/bin/env bash
cat << 'EJESTJSON'
{
  "numPassedTests": 10,
  "numFailedTests": 0,
  "numPendingTests": 0,
  "testResults": [
    {"name": "test_a.test.js", "status": "passed"},
    {"name": "test_b.test.js", "status": "passed"},
    {"name": "test_c.test.js", "status": "passed"},
    {"name": "test_d.test.js", "status": "passed"},
    {"name": "test_e.test.js", "status": "passed"},
    {"name": "test_f.test.js", "status": "passed"},
    {"name": "test_g.test.js", "status": "passed"},
    {"name": "test_h.test.js", "status": "passed"},
    {"name": "test_i.test.js", "status": "passed"},
    {"name": "test_j.test.js", "status": "passed"}
  ]
}
EJESTJSON
ESCRIPT
chmod +x "$CLEAN_REPO/.bin/npx"
cat > "$CLEAN_REPO/quantum.json" << 'EQJSON'
{"stories": []}
EQJSON
OLD_PATH="$PATH"
export PATH="$CLEAN_REPO/.bin:$PATH"
OUTPUT=$(capture_baseline "$CLEAN_REPO" "$CLEAN_REPO/quantum.json" 2>&1)
export PATH="$OLD_PATH"
BL_PASS=$(read_json_field "$CLEAN_REPO/quantum.json" "d.get('knownFailures',{}).get('baseline',{}).get('passCount','MISSING')")
BL_FAIL=$(read_json_field "$CLEAN_REPO/quantum.json" "d.get('knownFailures',{}).get('baseline',{}).get('failCount','MISSING')")
BL_SKIP=$(read_json_field "$CLEAN_REPO/quantum.json" "d.get('knownFailures',{}).get('baseline',{}).get('skipCount','MISSING')")
BL_TESTS_LEN=$(read_json_field "$CLEAN_REPO/quantum.json" "len(d.get('knownFailures',{}).get('baseline',{}).get('failingTests',[]))")
assert_eq "clean suite passCount" "10" "$BL_PASS"
assert_eq "clean suite failCount" "0" "$BL_FAIL"
assert_eq "clean suite skipCount" "0" "$BL_SKIP"
assert_eq "clean suite failingTests empty" "0" "$BL_TESTS_LEN"
# Verify current is also initialized
CUR_PASS=$(read_json_field "$CLEAN_REPO/quantum.json" "d.get('knownFailures',{}).get('current',{}).get('passCount','MISSING')")
assert_eq "clean suite current passCount" "10" "$CUR_PASS"

echo "--- T-033b: capture_baseline with exactly 5 failures ---"
FIVE_REPO="$TMPDIR_BASE/five-fail-repo"
mkdir -p "$FIVE_REPO/.bin"
cat > "$FIVE_REPO/package.json" << 'EJSON'
{
  "devDependencies": { "jest": "^29.0.0" }
}
EJSON
cat > "$FIVE_REPO/.bin/npx" << 'ESCRIPT'
#!/usr/bin/env bash
cat << 'EJESTJSON'
{
  "numPassedTests": 5,
  "numFailedTests": 5,
  "numPendingTests": 0,
  "testResults": [
    {"name": "test_a.test.js", "status": "passed"},
    {"name": "test_b.test.js", "status": "failed", "message": "Error in test_b"},
    {"name": "test_c.test.js", "status": "passed"},
    {"name": "test_d.test.js", "status": "failed", "message": "Error in test_d"},
    {"name": "test_e.test.js", "status": "passed"},
    {"name": "test_f.test.js", "status": "failed", "message": "Error in test_f"},
    {"name": "test_g.test.js", "status": "passed"},
    {"name": "test_h.test.js", "status": "failed", "message": "Error in test_h"},
    {"name": "test_i.test.js", "status": "passed"},
    {"name": "test_j.test.js", "status": "failed", "message": "Error in test_j"}
  ]
}
EJESTJSON
ESCRIPT
chmod +x "$FIVE_REPO/.bin/npx"
cat > "$FIVE_REPO/quantum.json" << 'EQJSON'
{"stories": []}
EQJSON
export PATH="$FIVE_REPO/.bin:$PATH"
OUTPUT=$(capture_baseline "$FIVE_REPO" "$FIVE_REPO/quantum.json" 2>&1)
export PATH="$OLD_PATH"
BL_FAIL=$(read_json_field "$FIVE_REPO/quantum.json" "d.get('knownFailures',{}).get('baseline',{}).get('failCount','MISSING')")
BL_TESTS_LEN=$(read_json_field "$FIVE_REPO/quantum.json" "len(d.get('knownFailures',{}).get('baseline',{}).get('failingTests',[]))")
assert_eq "5 failures failCount" "5" "$BL_FAIL"
assert_eq "5 failures failingTests has 5 entries" "5" "$BL_TESTS_LEN"
# Verify each failure is present
FAIL_NAMES=$(read_json_field "$FIVE_REPO/quantum.json" "','.join(t['name'] for t in d.get('knownFailures',{}).get('baseline',{}).get('failingTests',[]))")
assert_contains "5 fail includes test_b" "test_b" "$FAIL_NAMES"
assert_contains "5 fail includes test_d" "test_d" "$FAIL_NAMES"
assert_contains "5 fail includes test_f" "test_f" "$FAIL_NAMES"
assert_contains "5 fail includes test_h" "test_h" "$FAIL_NAMES"
assert_contains "5 fail includes test_j" "test_j" "$FAIL_NAMES"

echo "--- T-033c: capture_baseline with garbled output (both parses fail) ---"
GARBLED_REPO="$TMPDIR_BASE/garbled-repo"
mkdir -p "$GARBLED_REPO/.bin"
cat > "$GARBLED_REPO/pyproject.toml" << 'ETOML'
[tool.pytest.ini_options]
testpaths = ["tests"]
ETOML
cat > "$GARBLED_REPO/.bin/pytest" << 'ESCRIPT'
#!/usr/bin/env bash
# Completely garbled output -- no PASS/FAIL/ERROR keywords, no structured format
echo "Segmentation fault (core dumped)"
echo "Process exited with code 139"
echo ">>>>>>>>>>>>>>>>>>>>>>><<"
echo "binary garbage: \x00\x01\x02"
exit 139
ESCRIPT
chmod +x "$GARBLED_REPO/.bin/pytest"
cat > "$GARBLED_REPO/quantum.json" << 'EQJSON'
{"stories": []}
EQJSON
export PATH="$GARBLED_REPO/.bin:$PATH"
OUTPUT=$(capture_baseline "$GARBLED_REPO" "$GARBLED_REPO/quantum.json" 2>&1)
export PATH="$OLD_PATH"
BL_VAL=$(read_json_field "$GARBLED_REPO/quantum.json" "d.get('knownFailures',{}).get('baseline', 'NOT_SET')")
assert_eq "garbled output: baseline is null" "None" "$BL_VAL"
assert_contains "garbled output logs tracking disabled or fallback" "KNOWN-FAILURES" "$OUTPUT"

# =========================================================================
echo "=== Test T-034: Additional capture_wave_snapshot and delta_check ==="
# =========================================================================

echo "--- T-034a: capture_wave_snapshot from 0 failures to 3 new failures ---"
WAVE3_REPO="$TMPDIR_BASE/wave3-repo"
mkdir -p "$WAVE3_REPO/.bin"
cat > "$WAVE3_REPO/pyproject.toml" << 'ETOML'
[tool.pytest.ini_options]
testpaths = ["tests"]
ETOML
cat > "$WAVE3_REPO/.bin/pytest" << 'ESCRIPT'
#!/usr/bin/env bash
cat << 'EPYTEST'
tests/test_a.py::test_one PASSED
tests/test_a.py::test_two FAILED
tests/test_a.py::test_three FAILED
tests/test_a.py::test_four FAILED
tests/test_a.py::test_five PASSED
2 passed, 3 failed, 0 skipped
EPYTEST
exit 1
ESCRIPT
chmod +x "$WAVE3_REPO/.bin/pytest"
WAVE3_NATIVE=$(_to_native "$WAVE3_REPO/quantum.json")
python -c "
import json
d = {
    'stories': [],
    'knownFailures': {
        'baseline': {
            'capturedAt': '2026-03-20T00:00:00Z', 'wave': 0,
            'passCount': 5, 'failCount': 0, 'skipCount': 0,
            'failingTests': []
        },
        'current': {
            'updatedAt': '2026-03-20T00:00:00Z', 'capturedAt': '2026-03-20T00:00:00Z', 'wave': 0,
            'passCount': 5, 'failCount': 0, 'skipCount': 0,
            'failingTests': []
        },
        'flakyThreshold': 1,
        'fullSuiteTimeout': 60
    }
}
with open('$WAVE3_NATIVE', 'w') as f:
    json.dump(d, f, indent=2)
"
export PATH="$WAVE3_REPO/.bin:$PATH"
OUTPUT=$(capture_wave_snapshot "$WAVE3_REPO" "$WAVE3_REPO/quantum.json" 2 2>&1)
export PATH="$OLD_PATH"
CUR_FAIL_COUNT=$(read_json_field "$WAVE3_REPO/quantum.json" "d.get('knownFailures',{}).get('current',{}).get('failCount','MISSING')")
CUR_FAIL_LEN=$(read_json_field "$WAVE3_REPO/quantum.json" "len(d.get('knownFailures',{}).get('current',{}).get('failingTests',[]))")
assert_eq "wave3 failCount is 3" "3" "$CUR_FAIL_COUNT"
assert_eq "wave3 failingTests has 3 entries" "3" "$CUR_FAIL_LEN"
# Verify failingSince is wave 2
SINCE_VALS=$(read_json_field "$WAVE3_REPO/quantum.json" "','.join(str(t['failingSince']) for t in d.get('knownFailures',{}).get('current',{}).get('failingTests',[]))")
assert_contains "wave3 entries have failingSince=2" "2" "$SINCE_VALS"

echo "--- T-034b: capture_wave_snapshot resolves 3 previous failures ---"
RESOLVE3_REPO="$TMPDIR_BASE/resolve3-repo"
mkdir -p "$RESOLVE3_REPO/.bin"
cat > "$RESOLVE3_REPO/pyproject.toml" << 'ETOML'
[tool.pytest.ini_options]
testpaths = ["tests"]
ETOML
# All tests pass -- 3 previous failures resolved
cat > "$RESOLVE3_REPO/.bin/pytest" << 'ESCRIPT'
#!/usr/bin/env bash
cat << 'EPYTEST'
tests/test_a.py::test_one PASSED
tests/test_a.py::test_two PASSED
tests/test_a.py::test_three PASSED
tests/test_a.py::test_four PASSED
tests/test_a.py::test_five PASSED
5 passed, 0 failed, 0 skipped
EPYTEST
exit 0
ESCRIPT
chmod +x "$RESOLVE3_REPO/.bin/pytest"
RESOLVE3_NATIVE=$(_to_native "$RESOLVE3_REPO/quantum.json")
python -c "
import json
d = {
    'stories': [],
    'knownFailures': {
        'baseline': {
            'capturedAt': '2026-03-20T00:00:00Z', 'wave': 0,
            'passCount': 5, 'failCount': 0, 'skipCount': 0,
            'failingTests': []
        },
        'current': {
            'updatedAt': '2026-03-21T00:00:00Z', 'capturedAt': '2026-03-20T00:00:00Z', 'wave': 2,
            'passCount': 2, 'failCount': 3, 'skipCount': 0,
            'failingTests': [
                {'name': 'tests/test_a.py::test_two', 'failingSince': 2, 'introducedBy': None, 'expectedFix': None, 'error': ''},
                {'name': 'tests/test_a.py::test_three', 'failingSince': 2, 'introducedBy': None, 'expectedFix': None, 'error': ''},
                {'name': 'tests/test_a.py::test_four', 'failingSince': 2, 'introducedBy': None, 'expectedFix': None, 'error': ''}
            ]
        },
        'flakyThreshold': 1,
        'fullSuiteTimeout': 60
    }
}
with open('$RESOLVE3_NATIVE', 'w') as f:
    json.dump(d, f, indent=2)
"
export PATH="$RESOLVE3_REPO/.bin:$PATH"
OUTPUT=$(capture_wave_snapshot "$RESOLVE3_REPO" "$RESOLVE3_REPO/quantum.json" 3 2>&1)
export PATH="$OLD_PATH"
CUR_FAIL_COUNT=$(read_json_field "$RESOLVE3_REPO/quantum.json" "d.get('knownFailures',{}).get('current',{}).get('failCount','MISSING')")
CUR_FAIL_LEN=$(read_json_field "$RESOLVE3_REPO/quantum.json" "len(d.get('knownFailures',{}).get('current',{}).get('failingTests',[]))")
CUR_PASS_COUNT=$(read_json_field "$RESOLVE3_REPO/quantum.json" "d.get('knownFailures',{}).get('current',{}).get('passCount','MISSING')")
assert_eq "resolve3 failCount is 0" "0" "$CUR_FAIL_COUNT"
assert_eq "resolve3 failingTests empty" "0" "$CUR_FAIL_LEN"
assert_eq "resolve3 passCount is 5" "5" "$CUR_PASS_COUNT"

echo "--- T-034c: capture_wave_snapshot with no change ---"
NOCHANGE_REPO="$TMPDIR_BASE/nochange-repo"
mkdir -p "$NOCHANGE_REPO/.bin"
cat > "$NOCHANGE_REPO/pyproject.toml" << 'ETOML'
[tool.pytest.ini_options]
testpaths = ["tests"]
ETOML
# Same 2 failures as before
cat > "$NOCHANGE_REPO/.bin/pytest" << 'ESCRIPT'
#!/usr/bin/env bash
cat << 'EPYTEST'
tests/test_a.py::test_one PASSED
tests/test_a.py::test_two PASSED
tests/test_a.py::test_three FAILED
tests/test_a.py::test_four FAILED
2 passed, 2 failed, 0 skipped
EPYTEST
exit 1
ESCRIPT
chmod +x "$NOCHANGE_REPO/.bin/pytest"
NOCHANGE_NATIVE=$(_to_native "$NOCHANGE_REPO/quantum.json")
python -c "
import json
d = {
    'stories': [],
    'knownFailures': {
        'baseline': {
            'capturedAt': '2026-03-20T00:00:00Z', 'wave': 0,
            'passCount': 2, 'failCount': 2, 'skipCount': 0,
            'failingTests': [
                {'name': 'tests/test_a.py::test_three', 'failingSince': 1, 'introducedBy': None, 'expectedFix': None, 'error': ''},
                {'name': 'tests/test_a.py::test_four', 'failingSince': 1, 'introducedBy': None, 'expectedFix': None, 'error': ''}
            ]
        },
        'current': {
            'updatedAt': '2026-03-20T00:00:00Z', 'capturedAt': '2026-03-20T00:00:00Z', 'wave': 1,
            'passCount': 2, 'failCount': 2, 'skipCount': 0,
            'failingTests': [
                {'name': 'tests/test_a.py::test_three', 'failingSince': 1, 'introducedBy': None, 'expectedFix': None, 'error': ''},
                {'name': 'tests/test_a.py::test_four', 'failingSince': 1, 'introducedBy': None, 'expectedFix': None, 'error': ''}
            ]
        },
        'flakyThreshold': 1,
        'fullSuiteTimeout': 60
    }
}
with open('$NOCHANGE_NATIVE', 'w') as f:
    json.dump(d, f, indent=2)
"
export PATH="$NOCHANGE_REPO/.bin:$PATH"
OUTPUT=$(capture_wave_snapshot "$NOCHANGE_REPO" "$NOCHANGE_REPO/quantum.json" 3 2>&1)
export PATH="$OLD_PATH"
CUR_FAIL_COUNT=$(read_json_field "$NOCHANGE_REPO/quantum.json" "d.get('knownFailures',{}).get('current',{}).get('failCount','MISSING')")
CUR_FAIL_LEN=$(read_json_field "$NOCHANGE_REPO/quantum.json" "len(d.get('knownFailures',{}).get('current',{}).get('failingTests',[]))")
CUR_WAVE=$(read_json_field "$NOCHANGE_REPO/quantum.json" "d.get('knownFailures',{}).get('current',{}).get('wave','MISSING')")
assert_eq "nochange failCount stays 2" "2" "$CUR_FAIL_COUNT"
assert_eq "nochange failingTests still 2" "2" "$CUR_FAIL_LEN"
assert_eq "nochange wave updated to 3" "3" "$CUR_WAVE"

echo "--- T-034d: delta_check no regressions (baseline 5 failures, same 5) ---"
DC5_REPO="$TMPDIR_BASE/dc5-repo"
mkdir -p "$DC5_REPO/.bin"
cat > "$DC5_REPO/pyproject.toml" << 'ETOML'
[tool.pytest.ini_options]
testpaths = ["tests"]
ETOML
# 5 known failures, all the same as current
cat > "$DC5_REPO/.bin/pytest" << 'ESCRIPT'
#!/usr/bin/env bash
cat << 'EPYTEST'
tests/test_a.py::test_one PASSED
tests/test_a.py::test_two FAILED
tests/test_a.py::test_three FAILED
tests/test_a.py::test_four FAILED
tests/test_a.py::test_five FAILED
tests/test_a.py::test_six FAILED
tests/test_a.py::test_seven PASSED
2 passed, 5 failed, 0 skipped
EPYTEST
exit 1
ESCRIPT
chmod +x "$DC5_REPO/.bin/pytest"
DC5_NATIVE=$(_to_native "$DC5_REPO/quantum.json")
python -c "
import json
d = {
    'stories': [],
    'knownFailures': {
        'current': {
            'updatedAt': '2026-03-20T00:00:00Z', 'wave': 1,
            'passCount': 2, 'failCount': 5, 'skipCount': 0,
            'failingTests': [
                {'name': 'tests/test_a.py::test_two', 'failingSince': 0, 'introducedBy': None, 'expectedFix': None, 'error': ''},
                {'name': 'tests/test_a.py::test_three', 'failingSince': 0, 'introducedBy': None, 'expectedFix': None, 'error': ''},
                {'name': 'tests/test_a.py::test_four', 'failingSince': 0, 'introducedBy': None, 'expectedFix': None, 'error': ''},
                {'name': 'tests/test_a.py::test_five', 'failingSince': 0, 'introducedBy': None, 'expectedFix': None, 'error': ''},
                {'name': 'tests/test_a.py::test_six', 'failingSince': 0, 'introducedBy': None, 'expectedFix': None, 'error': ''}
            ]
        },
        'flakyThreshold': 1,
        'fullSuiteTimeout': 60
    }
}
with open('$DC5_NATIVE', 'w') as f:
    json.dump(d, f, indent=2)
"
export PATH="$DC5_REPO/.bin:$PATH"
OUTPUT=$(delta_check "$DC5_REPO" "$DC5_REPO/quantum.json" "US-010" 2>&1)
DC_EXIT=$?
export PATH="$OLD_PATH"
assert_eq "delta_check 5 known failures returns 0" "0" "$DC_EXIT"
assert_contains "delta_check 5 known failures logged" "known failures present" "$OUTPUT"

echo "--- T-034e: delta_check with 0 failures (no regressions, clean run) ---"
DC_CLEAN_REPO="$TMPDIR_BASE/dc-clean-repo"
mkdir -p "$DC_CLEAN_REPO/.bin"
cat > "$DC_CLEAN_REPO/pyproject.toml" << 'ETOML'
[tool.pytest.ini_options]
testpaths = ["tests"]
ETOML
# All tests pass
cat > "$DC_CLEAN_REPO/.bin/pytest" << 'ESCRIPT'
#!/usr/bin/env bash
cat << 'EPYTEST'
tests/test_a.py::test_one PASSED
tests/test_a.py::test_two PASSED
tests/test_a.py::test_three PASSED
3 passed, 0 failed, 0 skipped
EPYTEST
exit 0
ESCRIPT
chmod +x "$DC_CLEAN_REPO/.bin/pytest"
DC_CLEAN_NATIVE=$(_to_native "$DC_CLEAN_REPO/quantum.json")
python -c "
import json
d = {
    'stories': [],
    'knownFailures': {
        'current': {
            'updatedAt': '2026-03-20T00:00:00Z', 'wave': 1,
            'passCount': 3, 'failCount': 0, 'skipCount': 0,
            'failingTests': []
        },
        'flakyThreshold': 1,
        'fullSuiteTimeout': 60
    }
}
with open('$DC_CLEAN_NATIVE', 'w') as f:
    json.dump(d, f, indent=2)
"
export PATH="$DC_CLEAN_REPO/.bin:$PATH"
OUTPUT=$(delta_check "$DC_CLEAN_REPO" "$DC_CLEAN_REPO/quantum.json" "US-011" 2>&1)
DC_EXIT=$?
export PATH="$OLD_PATH"
assert_eq "delta_check clean run returns 0" "0" "$DC_EXIT"
assert_contains "delta_check logs timing on clean" "completed in" "$OUTPUT"

# =========================================================================
echo "=== Test T-035: Additional format_agent_context ==="
# =========================================================================

echo "--- T-035a: format_agent_context with exactly 3 failures ---"
FMT5_REPO="$TMPDIR_BASE/fmt5-repo"
mkdir -p "$FMT5_REPO"
FMT5_NATIVE=$(_to_native "$FMT5_REPO/quantum.json")
python -c "
import json
d = {
    'knownFailures': {
        'current': {
            'failingTests': [
                {'name': 'tests/test_auth::test_login', 'failingSince': 1, 'introducedBy': 'US-003', 'expectedFix': 'US-007', 'error': 'timeout'},
                {'name': 'tests/test_api::test_create', 'failingSince': 2, 'introducedBy': 'US-005', 'expectedFix': 'US-009', 'error': 'not found'},
                {'name': 'tests/test_db::test_migrate', 'failingSince': 3, 'introducedBy': None, 'expectedFix': None, 'error': 'schema mismatch'}
            ]
        }
    }
}
with open('$FMT5_NATIVE', 'w') as f:
    json.dump(d, f, indent=2)
"
OUTPUT=$(format_agent_context "$FMT5_REPO/quantum.json")
assert_contains "fmt3 includes test_login" "test_auth::test_login" "$OUTPUT"
assert_contains "fmt3 includes test_create" "test_api::test_create" "$OUTPUT"
assert_contains "fmt3 includes test_migrate" "test_db::test_migrate" "$OUTPUT"
assert_contains "fmt3 includes US-007 fix" "US-007" "$OUTPUT"
assert_contains "fmt3 includes US-009 fix" "US-009" "$OUTPUT"
assert_contains "fmt3 includes Wave 1" "Wave 1" "$OUTPUT"
assert_contains "fmt3 includes Wave 2" "Wave 2" "$OUTPUT"
assert_contains "fmt3 includes Wave 3" "Wave 3" "$OUTPUT"
assert_contains "fmt3 includes unknown for null fix" "unknown" "$OUTPUT"

echo "--- T-035b: format_agent_context summary ---"
echo "  (Summary included in final results below)"

# =========================================================================
echo ""
echo "=== Results: $PASS/$TOTAL passed, $FAIL failed ==="
if [[ $FAIL -eq 0 ]]; then
  exit 0
else
  exit 1
fi
