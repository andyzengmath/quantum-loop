#!/usr/bin/env bash
# Test suite for lib/barrel-regen.sh
# Tests barrel detection, regeneration, and non-pure barrel handling

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="$SCRIPT_DIR/../lib"
PASS=0
FAIL=0
TOTAL=0

# Source the library under test
if [[ ! -f "$LIB_DIR/barrel-regen.sh" ]]; then
  echo "SKIP: lib/barrel-regen.sh not found (RED phase)"
  exit 1
fi
source "$LIB_DIR/barrel-regen.sh"

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
  if echo "$haystack" | grep -qF "$needle"; then
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
# Setup: create a temporary directory structure with barrel files
# =========================================================================
TMPDIR_TEST=$(mktemp -d)
ORIG_DIR=$(pwd)

setup_barrel_fixtures() {
  # Create nested directories with barrel files
  mkdir -p "$TMPDIR_TEST/src/components"
  mkdir -p "$TMPDIR_TEST/src/utils"
  mkdir -p "$TMPDIR_TEST/lib/core"
  mkdir -p "$TMPDIR_TEST/python_pkg/subpkg"
  mkdir -p "$TMPDIR_TEST/rust_crate/src"

  # TypeScript barrels
  echo 'export * from "./Button"' > "$TMPDIR_TEST/src/components/index.ts"
  echo 'export * from "./helpers"' > "$TMPDIR_TEST/src/utils/index.ts"

  # JavaScript barrel
  echo 'module.exports = {}' > "$TMPDIR_TEST/lib/core/index.js"

  # Python barrel
  echo 'from .module import *' > "$TMPDIR_TEST/python_pkg/__init__.py"
  echo 'from .sub import *' > "$TMPDIR_TEST/python_pkg/subpkg/__init__.py"

  # Rust barrel
  echo 'pub mod core;' > "$TMPDIR_TEST/rust_crate/src/mod.rs"
}

cleanup_barrel_fixtures() {
  cd "$ORIG_DIR"
  rm -rf "$TMPDIR_TEST"
}

trap cleanup_barrel_fixtures EXIT

setup_barrel_fixtures

# =========================================================================
echo "=== T-004: detect_barrel_files and should_regenerate ==="
# =========================================================================

echo "--- Test 1: detect_barrel_files finds all barrel files ---"
BARRELS=$(detect_barrel_files "$TMPDIR_TEST")
EXIT_CODE=$?
assert_eq "detect_barrel_files exits 0" "0" "$EXIT_CODE"
assert_contains "finds TS index.ts in components" "src/components/index.ts" "$BARRELS"
assert_contains "finds TS index.ts in utils" "src/utils/index.ts" "$BARRELS"
assert_contains "finds JS index.js" "lib/core/index.js" "$BARRELS"
assert_contains "finds Python __init__.py" "python_pkg/__init__.py" "$BARRELS"
assert_contains "finds Python __init__.py in subpkg" "python_pkg/subpkg/__init__.py" "$BARRELS"
assert_contains "finds Rust mod.rs" "rust_crate/src/mod.rs" "$BARRELS"

echo "--- Test 2: detect_barrel_files returns newline-separated paths ---"
BARREL_COUNT=$(echo "$BARRELS" | grep -c '.')
TOTAL=$((TOTAL + 1))
if [[ "$BARREL_COUNT" -ge 6 ]]; then
  echo "  PASS: Found at least 6 barrel files (got $BARREL_COUNT)"
  PASS=$((PASS + 1))
else
  echo "  FAIL: Expected at least 6 barrel files, got $BARREL_COUNT"
  echo "    barrels: $BARRELS"
  FAIL=$((FAIL + 1))
fi

echo "--- Test 3: detect_barrel_files on empty dir returns empty ---"
EMPTY_DIR=$(mktemp -d)
BARRELS_EMPTY=$(detect_barrel_files "$EMPTY_DIR")
assert_eq "detect_barrel_files on empty dir returns empty" "" "$BARRELS_EMPTY"
rmdir "$EMPTY_DIR"

echo "--- Test 4: should_regenerate returns 0 when file is in conflict list ---"
should_regenerate "src/index.ts" "src/index.ts src/utils.ts package.json"
assert_eq "should_regenerate match returns 0" "0" "$?"

echo "--- Test 5: should_regenerate returns 1 when file not in conflict list ---"
should_regenerate "src/other.ts" "src/index.ts src/utils.ts package.json"
assert_eq "should_regenerate no-match returns 1" "1" "$?"

echo "--- Test 6: should_regenerate with empty conflict list returns 1 ---"
should_regenerate "src/index.ts" ""
assert_eq "should_regenerate empty list returns 1" "1" "$?"

echo "--- Test 7: should_regenerate with empty barrel_path returns 1 ---"
should_regenerate "" "src/index.ts"
assert_eq "should_regenerate empty path returns 1" "1" "$?"

echo "--- Test 8: BARREL_REGEN_LIB_DIR is set ---"
TOTAL=$((TOTAL + 1))
if [[ -n "$BARREL_REGEN_LIB_DIR" ]]; then
  echo "  PASS: BARREL_REGEN_LIB_DIR is set ($BARREL_REGEN_LIB_DIR)"
  PASS=$((PASS + 1))
else
  echo "  FAIL: BARREL_REGEN_LIB_DIR is not set"
  FAIL=$((FAIL + 1))
fi

# =========================================================================
echo "=== T-005: regenerate_barrel for TypeScript and JavaScript ==="
# =========================================================================

# Setup: TS directory with source files
TS_DIR="$TMPDIR_TEST/ts_regen"
mkdir -p "$TS_DIR"
echo 'export const Button = () => {}' > "$TS_DIR/Button.ts"
echo 'export const Modal = () => {}' > "$TS_DIR/Modal.ts"
echo 'export function helper() {}' > "$TS_DIR/utils.ts"
echo '' > "$TS_DIR/index.ts"

echo "--- Test 9: regenerate_barrel TS produces sorted exports ---"
regenerate_barrel "$TS_DIR/index.ts" "typescript" 2>/dev/null
EXIT_CODE=$?
assert_eq "regenerate_barrel TS exits 0" "0" "$EXIT_CODE"
TS_CONTENT=$(cat "$TS_DIR/index.ts")
assert_contains "TS barrel has Button export" "export * from './Button'" "$TS_CONTENT"
assert_contains "TS barrel has Modal export" "export * from './Modal'" "$TS_CONTENT"
assert_contains "TS barrel has utils export" "export * from './utils'" "$TS_CONTENT"
# Verify sorted order: Button < Modal < utils
FIRST_LINE=$(head -n1 "$TS_DIR/index.ts")
assert_contains "TS barrel first line is Button (sorted)" "Button" "$FIRST_LINE"

echo "--- Test 10: regenerate_barrel TS excludes index.ts itself ---"
assert_not_contains "TS barrel does not export index" "from './index'" "$TS_CONTENT"

echo "--- Test 11: regenerate_barrel TS preserves // manual lines ---"
# Add a manual line and a regular export, then regenerate
printf "// manual: keep this custom export\nexport * from './Button'\n" > "$TS_DIR/index.ts"
regenerate_barrel "$TS_DIR/index.ts" "typescript" 2>/dev/null
TS_CONTENT2=$(cat "$TS_DIR/index.ts")
assert_contains "TS barrel preserves // manual line" "// manual: keep this custom export" "$TS_CONTENT2"
assert_contains "TS barrel still has auto exports" "export * from './Modal'" "$TS_CONTENT2"

echo "--- Test 12: regenerate_barrel TS empty dir produces comment ---"
EMPTY_TS_DIR="$TMPDIR_TEST/empty_ts"
mkdir -p "$EMPTY_TS_DIR"
echo '' > "$EMPTY_TS_DIR/index.ts"
regenerate_barrel "$EMPTY_TS_DIR/index.ts" "typescript" 2>/dev/null
EMPTY_CONTENT=$(cat "$EMPTY_TS_DIR/index.ts")
assert_contains "TS empty barrel has no-exports comment" "// No exports" "$EMPTY_CONTENT"

echo "--- Test 13: regenerate_barrel JS produces exports ---"
JS_DIR="$TMPDIR_TEST/js_regen"
mkdir -p "$JS_DIR"
echo 'module.exports.foo = 1' > "$JS_DIR/api.js"
echo 'module.exports.bar = 2' > "$JS_DIR/config.js"
echo '' > "$JS_DIR/index.js"
regenerate_barrel "$JS_DIR/index.js" "javascript" 2>/dev/null
JS_CONTENT=$(cat "$JS_DIR/index.js")
assert_contains "JS barrel has api export" "export * from './api'" "$JS_CONTENT"
assert_contains "JS barrel has config export" "export * from './config'" "$JS_CONTENT"

echo "--- Test 14: regenerate_barrel logs output ---"
LOG_OUTPUT=$(regenerate_barrel "$TS_DIR/index.ts" "typescript" 2>&1)
assert_contains "regenerate_barrel logs BARREL-REGEN" "[BARREL-REGEN]" "$LOG_OUTPUT"
assert_contains "regenerate_barrel logs Regenerated" "Regenerated" "$LOG_OUTPUT"

echo "--- Test 15: regenerate_barrel TS preserves non-matching lines ---"
# Lines that are not auto-gen pattern should be preserved
printf "export * from './Button'\nexport { specific } from './Modal'\n" > "$TS_DIR/index.ts"
regenerate_barrel "$TS_DIR/index.ts" "typescript" 2>/dev/null
TS_CONTENT3=$(cat "$TS_DIR/index.ts")
assert_contains "TS barrel preserves non-matching export line" "export { specific } from './Modal'" "$TS_CONTENT3"

echo "--- Test 16: regenerate_barrel is idempotent ---"
# Run twice, output should be the same
regenerate_barrel "$JS_DIR/index.js" "javascript" 2>/dev/null
JS_FIRST=$(cat "$JS_DIR/index.js")
regenerate_barrel "$JS_DIR/index.js" "javascript" 2>/dev/null
JS_SECOND=$(cat "$JS_DIR/index.js")
assert_eq "JS barrel is idempotent" "$JS_FIRST" "$JS_SECOND"

# =========================================================================
echo "=== T-006: regenerate_barrel for Python and Rust ==="
# =========================================================================

echo "--- Test 17: regenerate_barrel Python produces sorted imports ---"
PY_DIR="$TMPDIR_TEST/py_regen"
mkdir -p "$PY_DIR"
echo 'def foo(): pass' > "$PY_DIR/models.py"
echo 'def bar(): pass' > "$PY_DIR/views.py"
echo 'def baz(): pass' > "$PY_DIR/admin.py"
echo '' > "$PY_DIR/__init__.py"
regenerate_barrel "$PY_DIR/__init__.py" "python" 2>/dev/null
PY_CONTENT=$(cat "$PY_DIR/__init__.py")
EXIT_CODE=$?
assert_eq "regenerate_barrel Python exits 0" "0" "$EXIT_CODE"
assert_contains "Python barrel has admin import" "from .admin import *" "$PY_CONTENT"
assert_contains "Python barrel has models import" "from .models import *" "$PY_CONTENT"
assert_contains "Python barrel has views import" "from .views import *" "$PY_CONTENT"
# Verify sorted order: admin < models < views
PY_FIRST_LINE=$(head -n1 "$PY_DIR/__init__.py")
assert_contains "Python barrel first line is admin (sorted)" "admin" "$PY_FIRST_LINE"

echo "--- Test 18: regenerate_barrel Python excludes __init__.py ---"
assert_not_contains "Python barrel does not import __init__" "from .__init__" "$PY_CONTENT"

echo "--- Test 19: regenerate_barrel Python skips __private.py ---"
echo 'secret = 42' > "$PY_DIR/__private.py"
echo 'more_secret = 0' > "$PY_DIR/__hidden.py"
regenerate_barrel "$PY_DIR/__init__.py" "python" 2>/dev/null
PY_CONTENT2=$(cat "$PY_DIR/__init__.py")
assert_not_contains "Python barrel skips __private.py" "from .__private" "$PY_CONTENT2"
assert_not_contains "Python barrel skips __hidden.py" "from .__hidden" "$PY_CONTENT2"
# But regular files still present
assert_contains "Python barrel still has admin" "from .admin import *" "$PY_CONTENT2"

echo "--- Test 20: regenerate_barrel Python preserves # manual lines ---"
printf "# manual: custom import path\nfrom .models import *\n" > "$PY_DIR/__init__.py"
regenerate_barrel "$PY_DIR/__init__.py" "python" 2>/dev/null
PY_CONTENT3=$(cat "$PY_DIR/__init__.py")
assert_contains "Python barrel preserves # manual line" "# manual: custom import path" "$PY_CONTENT3"
assert_contains "Python barrel still has auto imports" "from .views import *" "$PY_CONTENT3"

echo "--- Test 21: regenerate_barrel Python empty dir produces comment ---"
EMPTY_PY_DIR="$TMPDIR_TEST/empty_py"
mkdir -p "$EMPTY_PY_DIR"
echo '' > "$EMPTY_PY_DIR/__init__.py"
regenerate_barrel "$EMPTY_PY_DIR/__init__.py" "python" 2>/dev/null
EMPTY_PY_CONTENT=$(cat "$EMPTY_PY_DIR/__init__.py")
assert_contains "Python empty barrel has no-exports comment" "# No exports" "$EMPTY_PY_CONTENT"

echo "--- Test 22: regenerate_barrel Rust produces sorted pub mod ---"
RS_DIR="$TMPDIR_TEST/rs_regen"
mkdir -p "$RS_DIR"
echo 'pub fn core_fn() {}' > "$RS_DIR/core.rs"
echo 'pub fn utils_fn() {}' > "$RS_DIR/utils.rs"
echo 'pub fn api_fn() {}' > "$RS_DIR/api.rs"
echo '' > "$RS_DIR/mod.rs"
regenerate_barrel "$RS_DIR/mod.rs" "rust" 2>/dev/null
RS_CONTENT=$(cat "$RS_DIR/mod.rs")
EXIT_CODE=$?
assert_eq "regenerate_barrel Rust exits 0" "0" "$EXIT_CODE"
assert_contains "Rust barrel has api mod" "pub mod api;" "$RS_CONTENT"
assert_contains "Rust barrel has core mod" "pub mod core;" "$RS_CONTENT"
assert_contains "Rust barrel has utils mod" "pub mod utils;" "$RS_CONTENT"
# Verify sorted order: api < core < utils
RS_FIRST_LINE=$(head -n1 "$RS_DIR/mod.rs")
assert_contains "Rust barrel first line is api (sorted)" "api" "$RS_FIRST_LINE"

echo "--- Test 23: regenerate_barrel Rust excludes mod.rs ---"
assert_not_contains "Rust barrel does not include mod" "pub mod mod;" "$RS_CONTENT"

echo "--- Test 24: regenerate_barrel Rust preserves // manual lines ---"
printf "// manual: keep this custom module\npub mod core;\n" > "$RS_DIR/mod.rs"
regenerate_barrel "$RS_DIR/mod.rs" "rust" 2>/dev/null
RS_CONTENT2=$(cat "$RS_DIR/mod.rs")
assert_contains "Rust barrel preserves // manual line" "// manual: keep this custom module" "$RS_CONTENT2"
assert_contains "Rust barrel still has auto mods" "pub mod utils;" "$RS_CONTENT2"

echo "--- Test 25: regenerate_barrel Rust empty dir produces comment ---"
EMPTY_RS_DIR="$TMPDIR_TEST/empty_rs"
mkdir -p "$EMPTY_RS_DIR"
echo '' > "$EMPTY_RS_DIR/mod.rs"
regenerate_barrel "$EMPTY_RS_DIR/mod.rs" "rust" 2>/dev/null
EMPTY_RS_CONTENT=$(cat "$EMPTY_RS_DIR/mod.rs")
assert_contains "Rust empty barrel has no-exports comment" "// No exports" "$EMPTY_RS_CONTENT"

echo "--- Test 26: regenerate_barrel Python is idempotent ---"
regenerate_barrel "$PY_DIR/__init__.py" "python" 2>/dev/null
PY_IDEM1=$(cat "$PY_DIR/__init__.py")
regenerate_barrel "$PY_DIR/__init__.py" "python" 2>/dev/null
PY_IDEM2=$(cat "$PY_DIR/__init__.py")
assert_eq "Python barrel is idempotent" "$PY_IDEM1" "$PY_IDEM2"

echo "--- Test 27: regenerate_barrel Rust is idempotent ---"
regenerate_barrel "$RS_DIR/mod.rs" "rust" 2>/dev/null
RS_IDEM1=$(cat "$RS_DIR/mod.rs")
regenerate_barrel "$RS_DIR/mod.rs" "rust" 2>/dev/null
RS_IDEM2=$(cat "$RS_DIR/mod.rs")
assert_eq "Rust barrel is idempotent" "$RS_IDEM1" "$RS_IDEM2"

# =========================================================================
echo "=== T-007: Non-pure barrel detection and timing ==="
# =========================================================================

echo "--- Test 28: Non-pure TS barrel is skipped ---"
NONPURE_TS_DIR="$TMPDIR_TEST/nonpure_ts"
mkdir -p "$NONPURE_TS_DIR"
echo 'const x = 1' > "$NONPURE_TS_DIR/helper.ts"
# Create a non-pure barrel: contains a const declaration (not just exports)
printf "export * from './helper'\nconst config = { debug: true }\n" > "$NONPURE_TS_DIR/index.ts"
NONPURE_LOG=$(regenerate_barrel "$NONPURE_TS_DIR/index.ts" "typescript" 2>&1)
NONPURE_TS_CONTENT=$(cat "$NONPURE_TS_DIR/index.ts")
assert_contains "Non-pure TS barrel SKIP logged" "SKIP" "$NONPURE_LOG"
assert_contains "Non-pure TS barrel log has path" "nonpure_ts/index.ts" "$NONPURE_LOG"
assert_contains "Non-pure TS barrel log mentions non-export logic" "non-export logic" "$NONPURE_LOG"
# Content should be unchanged (not modified)
assert_contains "Non-pure TS barrel content preserved" "const config" "$NONPURE_TS_CONTENT"

echo "--- Test 29: Non-pure Python barrel is skipped ---"
NONPURE_PY_DIR="$TMPDIR_TEST/nonpure_py"
mkdir -p "$NONPURE_PY_DIR"
echo 'def foo(): pass' > "$NONPURE_PY_DIR/utils.py"
# Non-pure: contains a class definition
printf "from .utils import *\nclass Config:\n    pass\n" > "$NONPURE_PY_DIR/__init__.py"
NONPURE_PY_LOG=$(regenerate_barrel "$NONPURE_PY_DIR/__init__.py" "python" 2>&1)
NONPURE_PY_CONTENT=$(cat "$NONPURE_PY_DIR/__init__.py")
assert_contains "Non-pure Python barrel SKIP logged" "SKIP" "$NONPURE_PY_LOG"
assert_contains "Non-pure Python barrel content preserved" "class Config" "$NONPURE_PY_CONTENT"

echo "--- Test 30: Non-pure Rust barrel is skipped ---"
NONPURE_RS_DIR="$TMPDIR_TEST/nonpure_rs"
mkdir -p "$NONPURE_RS_DIR"
echo 'pub fn api() {}' > "$NONPURE_RS_DIR/api.rs"
# Non-pure: contains a function definition
printf "pub mod api;\npub fn init() {}\n" > "$NONPURE_RS_DIR/mod.rs"
NONPURE_RS_LOG=$(regenerate_barrel "$NONPURE_RS_DIR/mod.rs" "rust" 2>&1)
NONPURE_RS_CONTENT=$(cat "$NONPURE_RS_DIR/mod.rs")
assert_contains "Non-pure Rust barrel SKIP logged" "SKIP" "$NONPURE_RS_LOG"
assert_contains "Non-pure Rust barrel content preserved" "pub fn init" "$NONPURE_RS_CONTENT"

echo "--- Test 31: Pure barrel with only exports/comments/blanks is NOT skipped ---"
PURE_TS_DIR="$TMPDIR_TEST/pure_ts"
mkdir -p "$PURE_TS_DIR"
echo 'export const a = 1' > "$PURE_TS_DIR/a.ts"
echo 'export const b = 2' > "$PURE_TS_DIR/b.ts"
printf "// Auto-generated barrel\nexport * from './a'\n\nexport * from './b'\n" > "$PURE_TS_DIR/index.ts"
PURE_LOG=$(regenerate_barrel "$PURE_TS_DIR/index.ts" "typescript" 2>&1)
assert_contains "Pure TS barrel is regenerated" "Regenerated" "$PURE_LOG"
assert_not_contains "Pure TS barrel is NOT skipped" "SKIP" "$PURE_LOG"

echo "--- Test 32: Non-pure barrel returns 0 (no error) ---"
regenerate_barrel "$NONPURE_TS_DIR/index.ts" "typescript" 2>/dev/null
assert_eq "Non-pure barrel returns 0" "0" "$?"

echo "--- Test 33: Timing log is present ---"
TIMING_LOG=$(regenerate_barrel "$PURE_TS_DIR/index.ts" "typescript" 2>&1)
assert_contains "Timing log has Completed" "Completed in" "$TIMING_LOG"
assert_contains "Timing log has ms" "ms" "$TIMING_LOG"
assert_contains "Timing log has BARREL-REGEN tag" "[BARREL-REGEN]" "$TIMING_LOG"

echo "--- Test 34: Pure barrel with import lines is not skipped (JS) ---"
PURE_JS_DIR="$TMPDIR_TEST/pure_js"
mkdir -p "$PURE_JS_DIR"
echo 'export const c = 3' > "$PURE_JS_DIR/c.js"
printf "import { something } from 'other'\nexport * from './c'\n" > "$PURE_JS_DIR/index.js"
PURE_JS_LOG=$(regenerate_barrel "$PURE_JS_DIR/index.js" "javascript" 2>&1)
assert_not_contains "Pure JS with import is NOT skipped" "SKIP" "$PURE_JS_LOG"

echo "--- Test 35: Pure Python barrel with comments and imports not skipped ---"
PURE_PY_DIR="$TMPDIR_TEST/pure_py"
mkdir -p "$PURE_PY_DIR"
echo 'x = 1' > "$PURE_PY_DIR/m.py"
printf "# Auto-generated\nimport os\nfrom .m import *\n" > "$PURE_PY_DIR/__init__.py"
PURE_PY_LOG=$(regenerate_barrel "$PURE_PY_DIR/__init__.py" "python" 2>&1)
assert_not_contains "Pure Python with import/comment not skipped" "SKIP" "$PURE_PY_LOG"

echo "--- Test 36: Pure Rust barrel with use/pub use not skipped ---"
PURE_RS_DIR="$TMPDIR_TEST/pure_rs"
mkdir -p "$PURE_RS_DIR"
echo 'pub fn x() {}' > "$PURE_RS_DIR/x.rs"
printf "pub mod x;\npub use x::*;\nuse std::io;\n// comment\n" > "$PURE_RS_DIR/mod.rs"
PURE_RS_LOG=$(regenerate_barrel "$PURE_RS_DIR/mod.rs" "rust" 2>&1)
assert_not_contains "Pure Rust with use/pub use not skipped" "SKIP" "$PURE_RS_LOG"

# =========================================================================
echo ""
echo "=== Results: $PASS/$TOTAL passed, $FAIL failed ==="
if [[ $FAIL -eq 0 ]]; then
  exit 0
else
  exit 1
fi
