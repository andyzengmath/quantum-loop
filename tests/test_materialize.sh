#!/usr/bin/env bash
# Test suite for lib/materialize.sh
# Tests detect_language() function across language config file detection

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="$SCRIPT_DIR/../lib"
PASS=0
FAIL=0
TOTAL=0

# Source the library under test
if [[ ! -f "$LIB_DIR/materialize.sh" ]]; then
  echo "SKIP: lib/materialize.sh not found (RED phase)"
  exit 1
fi
source "$LIB_DIR/materialize.sh"

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
# Setup: create temporary directories for testing
# =========================================================================
TMPDIR=$(mktemp -d)

cleanup() {
  rm -rf "$TMPDIR"
}

trap cleanup EXIT

# =========================================================================
echo "=== Test 1: detect_language — TypeScript (tsconfig.json) ==="
TS_DIR="$TMPDIR/ts_project"
mkdir -p "$TS_DIR"
touch "$TS_DIR/tsconfig.json"
RESULT=$(detect_language "$TS_DIR")
assert_eq "TypeScript detected via tsconfig.json" "typescript" "$RESULT"

# =========================================================================
echo "=== Test 2: detect_language — Python (pyproject.toml) ==="
PY_DIR="$TMPDIR/py_project"
mkdir -p "$PY_DIR"
touch "$PY_DIR/pyproject.toml"
RESULT=$(detect_language "$PY_DIR")
assert_eq "Python detected via pyproject.toml" "python" "$RESULT"

# =========================================================================
echo "=== Test 3: detect_language — Python (setup.py) ==="
PY2_DIR="$TMPDIR/py2_project"
mkdir -p "$PY2_DIR"
touch "$PY2_DIR/setup.py"
RESULT=$(detect_language "$PY2_DIR")
assert_eq "Python detected via setup.py" "python" "$RESULT"

# =========================================================================
echo "=== Test 4: detect_language — Go (go.mod) ==="
GO_DIR="$TMPDIR/go_project"
mkdir -p "$GO_DIR"
touch "$GO_DIR/go.mod"
RESULT=$(detect_language "$GO_DIR")
assert_eq "Go detected via go.mod" "go" "$RESULT"

# =========================================================================
echo "=== Test 5: detect_language — Unknown (no config files) ==="
EMPTY_DIR="$TMPDIR/empty_project"
mkdir -p "$EMPTY_DIR"
RESULT=$(detect_language "$EMPTY_DIR")
assert_eq "Unknown when no config files" "unknown" "$RESULT"

# =========================================================================
echo "=== Test 6: detect_language — Multiple config files (first match wins: typescript) ==="
MULTI_DIR="$TMPDIR/multi_project"
mkdir -p "$MULTI_DIR"
touch "$MULTI_DIR/tsconfig.json"
touch "$MULTI_DIR/pyproject.toml"
touch "$MULTI_DIR/go.mod"
RESULT=$(detect_language "$MULTI_DIR")
assert_eq "TypeScript wins when multiple config files present" "typescript" "$RESULT"

# =========================================================================
echo "=== Test 7: detect_language — Python + Go (python wins over go) ==="
PY_GO_DIR="$TMPDIR/py_go_project"
mkdir -p "$PY_GO_DIR"
touch "$PY_GO_DIR/pyproject.toml"
touch "$PY_GO_DIR/go.mod"
RESULT=$(detect_language "$PY_GO_DIR")
assert_eq "Python wins over Go in priority" "python" "$RESULT"

# =========================================================================
echo "=== Test 8: detect_language — Both pyproject.toml and setup.py ==="
PY_BOTH_DIR="$TMPDIR/py_both_project"
mkdir -p "$PY_BOTH_DIR"
touch "$PY_BOTH_DIR/pyproject.toml"
touch "$PY_BOTH_DIR/setup.py"
RESULT=$(detect_language "$PY_BOTH_DIR")
assert_eq "Python detected when both pyproject.toml and setup.py" "python" "$RESULT"

# =========================================================================
echo "=== Test 9: detect_language — Empty string repo_root ==="
RESULT=$(detect_language "" 2>/dev/null)
assert_eq "Unknown for empty repo_root" "unknown" "$RESULT"

# =========================================================================
echo "=== Test 10: detect_language — Nonexistent directory ==="
RESULT=$(detect_language "$TMPDIR/nonexistent_dir" 2>/dev/null)
assert_eq "Unknown for nonexistent directory" "unknown" "$RESULT"

# =========================================================================
echo ""
echo "=== Results: $PASS/$TOTAL passed, $FAIL failed ==="
if [[ $FAIL -eq 0 ]]; then
  exit 0
else
  exit 1
fi
