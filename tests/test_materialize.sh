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
# Tests for infer_shared_types_dir()
# =========================================================================

echo ""
echo "--- infer_shared_types_dir() tests ---"

# =========================================================================
echo "=== Test 11: infer_shared_types_dir — finds src/shared/types/ (highest priority) ==="
INFER_DIR1="$TMPDIR/infer_project1"
mkdir -p "$INFER_DIR1/src/shared/types"
mkdir -p "$INFER_DIR1/src/types"
mkdir -p "$INFER_DIR1/types"
RESULT=$(infer_shared_types_dir "$INFER_DIR1" "typescript")
assert_eq "src/shared/types/ found first (highest priority)" "src/shared/types" "$RESULT"

# =========================================================================
echo "=== Test 12: infer_shared_types_dir — finds src/types/ when src/shared/types/ missing ==="
INFER_DIR2="$TMPDIR/infer_project2"
mkdir -p "$INFER_DIR2/src/types"
mkdir -p "$INFER_DIR2/types"
RESULT=$(infer_shared_types_dir "$INFER_DIR2" "typescript")
assert_eq "src/types/ found when src/shared/types/ absent" "src/types" "$RESULT"

# =========================================================================
echo "=== Test 13: infer_shared_types_dir — finds src/interfaces/ ==="
INFER_DIR3="$TMPDIR/infer_project3"
mkdir -p "$INFER_DIR3/src/interfaces"
RESULT=$(infer_shared_types_dir "$INFER_DIR3" "typescript")
assert_eq "src/interfaces/ found" "src/interfaces" "$RESULT"

# =========================================================================
echo "=== Test 14: infer_shared_types_dir — finds types/ (project root) ==="
INFER_DIR4="$TMPDIR/infer_project4"
mkdir -p "$INFER_DIR4/types"
RESULT=$(infer_shared_types_dir "$INFER_DIR4" "typescript")
assert_eq "types/ found at project root" "types" "$RESULT"

# =========================================================================
echo "=== Test 15: infer_shared_types_dir — finds shared/ ==="
INFER_DIR5="$TMPDIR/infer_project5"
mkdir -p "$INFER_DIR5/shared"
RESULT=$(infer_shared_types_dir "$INFER_DIR5" "python")
assert_eq "shared/ found" "shared" "$RESULT"

# =========================================================================
echo "=== Test 16: infer_shared_types_dir — TypeScript fallback default ==="
INFER_DIR6="$TMPDIR/infer_project6"
mkdir -p "$INFER_DIR6"
RESULT=$(infer_shared_types_dir "$INFER_DIR6" "typescript")
assert_eq "TypeScript default: src/shared/types" "src/shared/types" "$RESULT"

# =========================================================================
echo "=== Test 17: infer_shared_types_dir — Python fallback default ==="
INFER_DIR7="$TMPDIR/infer_project7"
mkdir -p "$INFER_DIR7"
RESULT=$(infer_shared_types_dir "$INFER_DIR7" "python")
assert_eq "Python default: src/shared" "src/shared" "$RESULT"

# =========================================================================
echo "=== Test 18: infer_shared_types_dir — Go fallback default ==="
INFER_DIR8="$TMPDIR/infer_project8"
mkdir -p "$INFER_DIR8"
RESULT=$(infer_shared_types_dir "$INFER_DIR8" "go")
assert_eq "Go default: internal/shared" "internal/shared" "$RESULT"

# =========================================================================
echo "=== Test 19: infer_shared_types_dir — Unknown language fallback default ==="
INFER_DIR9="$TMPDIR/infer_project9"
mkdir -p "$INFER_DIR9"
RESULT=$(infer_shared_types_dir "$INFER_DIR9" "unknown")
assert_eq "Unknown language default: src/shared/types" "src/shared/types" "$RESULT"

# =========================================================================
echo "=== Test 20: infer_shared_types_dir — does NOT create directories ==="
INFER_DIR10="$TMPDIR/infer_no_create"
mkdir -p "$INFER_DIR10"
RESULT=$(infer_shared_types_dir "$INFER_DIR10" "typescript")
# Verify the default path was returned
assert_eq "Returns default path for TypeScript" "src/shared/types" "$RESULT"
# Verify the directory was NOT created on disk
if [[ -d "$INFER_DIR10/src/shared/types" ]]; then
  TOTAL=$((TOTAL + 1))
  FAIL=$((FAIL + 1))
  echo "  FAIL: Directory was created (should NOT create directories)"
else
  TOTAL=$((TOTAL + 1))
  PASS=$((PASS + 1))
  echo "  PASS: Directory was NOT created (idempotent)"
fi

# =========================================================================
echo "=== Test 21: infer_shared_types_dir — empty repo_root ==="
RESULT=$(infer_shared_types_dir "" "typescript" 2>/dev/null)
assert_eq "Empty repo_root defaults to src/shared/types" "src/shared/types" "$RESULT"

# =========================================================================
echo "=== Test 22: infer_shared_types_dir — nonexistent repo_root ==="
RESULT=$(infer_shared_types_dir "$TMPDIR/nonexistent_infer" "python" 2>/dev/null)
assert_eq "Nonexistent repo_root defaults to Python default" "src/shared" "$RESULT"

# =========================================================================
echo "=== Test 23: infer_shared_types_dir — empty language string ==="
INFER_DIR11="$TMPDIR/infer_empty_lang"
mkdir -p "$INFER_DIR11"
RESULT=$(infer_shared_types_dir "$INFER_DIR11" "")
assert_eq "Empty language defaults to src/shared/types" "src/shared/types" "$RESULT"

# =========================================================================
echo "=== Test 24: infer_shared_types_dir — priority order: src/shared/types > types > shared ==="
INFER_DIR12="$TMPDIR/infer_priority"
mkdir -p "$INFER_DIR12/src/shared/types"
mkdir -p "$INFER_DIR12/types"
mkdir -p "$INFER_DIR12/shared"
RESULT=$(infer_shared_types_dir "$INFER_DIR12" "go")
assert_eq "src/shared/types/ wins regardless of language" "src/shared/types" "$RESULT"

# =========================================================================
echo ""
echo "=== Results: $PASS/$TOTAL passed, $FAIL failed ==="
if [[ $FAIL -eq 0 ]]; then
  exit 0
else
  exit 1
fi
