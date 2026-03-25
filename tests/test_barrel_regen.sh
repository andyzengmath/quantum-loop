#!/usr/bin/env bash
# Test suite for lib/barrel-regen.sh
# Tests barrel detection, regeneration for all languages, and edge cases

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

# =========================================================================
# Assertion helpers
# =========================================================================

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

assert_file_contains() {
  local test_name="$1" file_path="$2" expected="$3"
  TOTAL=$((TOTAL + 1))
  if [[ ! -f "$file_path" ]]; then
    echo "  FAIL: $test_name (file not found: $file_path)"
    FAIL=$((FAIL + 1))
    return
  fi
  if grep -qF "$expected" "$file_path"; then
    echo "  PASS: $test_name"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: $test_name"
    echo "    expected file to contain: $expected"
    echo "    actual contents: $(cat "$file_path")"
    FAIL=$((FAIL + 1))
  fi
}

assert_file_not_contains() {
  local test_name="$1" file_path="$2" unexpected="$3"
  TOTAL=$((TOTAL + 1))
  if [[ ! -f "$file_path" ]]; then
    echo "  PASS: $test_name (file not found, so cannot contain string)"
    PASS=$((PASS + 1))
    return
  fi
  if grep -qF "$unexpected" "$file_path"; then
    echo "  FAIL: $test_name"
    echo "    should NOT contain: $unexpected"
    echo "    actual contents: $(cat "$file_path")"
    FAIL=$((FAIL + 1))
  else
    echo "  PASS: $test_name"
    PASS=$((PASS + 1))
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

# =========================================================================
# Setup and teardown
# =========================================================================
TMPDIR_TEST=$(mktemp -d)
ORIG_DIR=$(pwd)

cleanup_test() {
  cd "$ORIG_DIR" || true
  rm -rf "$TMPDIR_TEST"
}

trap cleanup_test EXIT

# =========================================================================
echo "=== T-025: TS/JS barrel regeneration and detect functions ==="
# =========================================================================

echo "--- Test 1: TS barrel with Foo.ts, Bar.ts, Baz.ts produces 3 sorted exports ---"
TS_DIR="$TMPDIR_TEST/ts_sorted"
mkdir -p "$TS_DIR"
echo 'export const Foo = 1' > "$TS_DIR/Foo.ts"
echo 'export const Bar = 2' > "$TS_DIR/Bar.ts"
echo 'export const Baz = 3' > "$TS_DIR/Baz.ts"
echo '' > "$TS_DIR/index.ts"
regenerate_barrel "$TS_DIR/index.ts" "typescript" >/dev/null 2>&1
EXIT_CODE=$?
assert_eq "regenerate_barrel TS exits 0" "0" "$EXIT_CODE"
TS_LINE_COUNT=$(grep -c "export \* from" "$TS_DIR/index.ts")
assert_eq "TS barrel has exactly 3 export lines" "3" "$TS_LINE_COUNT"
assert_file_contains "TS barrel has Bar export" "$TS_DIR/index.ts" "export * from './Bar'"
assert_file_contains "TS barrel has Baz export" "$TS_DIR/index.ts" "export * from './Baz'"
assert_file_contains "TS barrel has Foo export" "$TS_DIR/index.ts" "export * from './Foo'"

echo "--- Test 2: TS exports are sorted alphabetically ---"
TS_FIRST=$(grep "export \* from" "$TS_DIR/index.ts" | head -n1)
TS_LAST=$(grep "export \* from" "$TS_DIR/index.ts" | tail -n1)
assert_contains "TS first sorted export is Bar" "Bar" "$TS_FIRST"
assert_contains "TS last sorted export is Foo" "Foo" "$TS_LAST"

echo "--- Test 3: TS barrel excludes index.ts itself ---"
assert_file_not_contains "TS barrel does not export index" "$TS_DIR/index.ts" "from './index'"

echo "--- Test 4: detect_barrel_files finds nested barrel files ---"
DETECT_DIR="$TMPDIR_TEST/detect_nested"
mkdir -p "$DETECT_DIR/src/components"
mkdir -p "$DETECT_DIR/src/utils"
mkdir -p "$DETECT_DIR/python_pkg"
mkdir -p "$DETECT_DIR/rust_crate/src"
echo '' > "$DETECT_DIR/src/components/index.ts"
echo '' > "$DETECT_DIR/src/utils/index.js"
echo '' > "$DETECT_DIR/python_pkg/__init__.py"
echo '' > "$DETECT_DIR/rust_crate/src/mod.rs"
BARRELS=$(detect_barrel_files "$DETECT_DIR")
EXIT_CODE=$?
assert_eq "detect_barrel_files exits 0" "0" "$EXIT_CODE"
assert_contains "finds nested TS index.ts" "src/components/index.ts" "$BARRELS"
assert_contains "finds nested JS index.js" "src/utils/index.js" "$BARRELS"
assert_contains "finds Python __init__.py" "python_pkg/__init__.py" "$BARRELS"
assert_contains "finds Rust mod.rs" "rust_crate/src/mod.rs" "$BARRELS"
BARREL_COUNT=$(echo "$BARRELS" | grep -c '.')
TOTAL=$((TOTAL + 1))
if [[ "$BARREL_COUNT" -ge 4 ]]; then
  echo "  PASS: Found at least 4 barrel files (got $BARREL_COUNT)"
  PASS=$((PASS + 1))
else
  echo "  FAIL: Expected at least 4 barrel files, got $BARREL_COUNT"
  FAIL=$((FAIL + 1))
fi

echo "--- Test 5: detect_barrel_files on empty dir returns empty ---"
EMPTY_DIR=$(mktemp -d)
BARRELS_EMPTY=$(detect_barrel_files "$EMPTY_DIR")
assert_eq "detect_barrel_files empty returns empty" "" "$BARRELS_EMPTY"
rmdir "$EMPTY_DIR"

echo "--- Test 6: should_regenerate returns 0 when barrel in conflict list ---"
should_regenerate "src/index.ts" "src/index.ts src/utils.ts package.json"
assert_eq "should_regenerate match returns 0" "0" "$?"

echo "--- Test 7: should_regenerate returns 1 when barrel NOT in conflict list ---"
should_regenerate "src/other.ts" "src/index.ts src/utils.ts package.json"
assert_eq "should_regenerate no-match returns 1" "1" "$?"

echo "--- Test 8: should_regenerate with empty conflict list returns 1 ---"
should_regenerate "src/index.ts" ""
assert_eq "should_regenerate empty conflict list returns 1" "1" "$?"

echo "--- Test 9: should_regenerate with empty barrel_path returns 1 ---"
should_regenerate "" "src/index.ts"
assert_eq "should_regenerate empty barrel path returns 1" "1" "$?"

echo "--- Test 10: JS barrel regeneration produces exports ---"
JS_DIR="$TMPDIR_TEST/js_regen"
mkdir -p "$JS_DIR"
echo 'module.exports.api = 1' > "$JS_DIR/api.js"
echo 'module.exports.config = 2' > "$JS_DIR/config.js"
echo '' > "$JS_DIR/index.js"
regenerate_barrel "$JS_DIR/index.js" "javascript" >/dev/null 2>&1
assert_file_contains "JS barrel has api export" "$JS_DIR/index.js" "export * from './api'"
assert_file_contains "JS barrel has config export" "$JS_DIR/index.js" "export * from './config'"
assert_file_not_contains "JS barrel excludes index.js" "$JS_DIR/index.js" "from './index'"

echo "--- Test 11: regenerate_barrel logs timing and info ---"
LOG_OUTPUT=$(regenerate_barrel "$TS_DIR/index.ts" "typescript" 2>&1)
assert_contains "log has BARREL-REGEN tag" "[BARREL-REGEN]" "$LOG_OUTPUT"
assert_contains "log has Regenerated" "Regenerated" "$LOG_OUTPUT"
assert_contains "log has Completed in" "Completed in" "$LOG_OUTPUT"

# =========================================================================
echo ""
echo "=== T-026: Python/Rust barrel regeneration ==="
# =========================================================================

echo "--- Test 12: Python barrel with foo.py, bar.py produces sorted imports ---"
PY_DIR="$TMPDIR_TEST/py_regen"
mkdir -p "$PY_DIR"
echo 'def foo(): pass' > "$PY_DIR/foo.py"
echo 'def bar(): pass' > "$PY_DIR/bar.py"
echo '' > "$PY_DIR/__init__.py"
regenerate_barrel "$PY_DIR/__init__.py" "python" >/dev/null 2>&1
EXIT_CODE=$?
assert_eq "regenerate_barrel Python exits 0" "0" "$EXIT_CODE"
PY_LINE_COUNT=$(grep -c "from \." "$PY_DIR/__init__.py")
assert_eq "Python barrel has exactly 2 import lines" "2" "$PY_LINE_COUNT"
assert_file_contains "Python barrel has bar import" "$PY_DIR/__init__.py" "from .bar import *"
assert_file_contains "Python barrel has foo import" "$PY_DIR/__init__.py" "from .foo import *"

echo "--- Test 13: Python imports are sorted alphabetically ---"
PY_FIRST=$(grep "from \." "$PY_DIR/__init__.py" | head -n1)
PY_LAST=$(grep "from \." "$PY_DIR/__init__.py" | tail -n1)
assert_contains "Python first sorted import is bar" "bar" "$PY_FIRST"
assert_contains "Python last sorted import is foo" "foo" "$PY_LAST"

echo "--- Test 14: Python barrel excludes __init__.py itself ---"
assert_file_not_contains "Python barrel does not import __init__" "$PY_DIR/__init__.py" "from .__init__"

echo "--- Test 15: Python barrel skips __private.py files ---"
echo 'secret = 42' > "$PY_DIR/__private.py"
echo 'hidden = 0' > "$PY_DIR/__hidden.py"
regenerate_barrel "$PY_DIR/__init__.py" "python" >/dev/null 2>&1
assert_file_not_contains "Python barrel skips __private.py" "$PY_DIR/__init__.py" "from .__private"
assert_file_not_contains "Python barrel skips __hidden.py" "$PY_DIR/__init__.py" "from .__hidden"
# But regular files still present
assert_file_contains "Python barrel still has bar" "$PY_DIR/__init__.py" "from .bar import *"

echo "--- Test 16: Rust barrel with foo.rs, bar.rs produces sorted pub mod ---"
RS_DIR="$TMPDIR_TEST/rs_regen"
mkdir -p "$RS_DIR"
echo 'pub fn foo_fn() {}' > "$RS_DIR/foo.rs"
echo 'pub fn bar_fn() {}' > "$RS_DIR/bar.rs"
echo '' > "$RS_DIR/mod.rs"
regenerate_barrel "$RS_DIR/mod.rs" "rust" >/dev/null 2>&1
EXIT_CODE=$?
assert_eq "regenerate_barrel Rust exits 0" "0" "$EXIT_CODE"
RS_LINE_COUNT=$(grep -c "pub mod" "$RS_DIR/mod.rs")
assert_eq "Rust barrel has exactly 2 mod lines" "2" "$RS_LINE_COUNT"
assert_file_contains "Rust barrel has bar mod" "$RS_DIR/mod.rs" "pub mod bar;"
assert_file_contains "Rust barrel has foo mod" "$RS_DIR/mod.rs" "pub mod foo;"

echo "--- Test 17: Rust mods are sorted alphabetically ---"
RS_FIRST=$(grep "pub mod" "$RS_DIR/mod.rs" | head -n1)
RS_LAST=$(grep "pub mod" "$RS_DIR/mod.rs" | tail -n1)
assert_contains "Rust first sorted mod is bar" "bar" "$RS_FIRST"
assert_contains "Rust last sorted mod is foo" "foo" "$RS_LAST"

echo "--- Test 18: Rust barrel excludes mod.rs itself ---"
assert_file_not_contains "Rust barrel does not include mod" "$RS_DIR/mod.rs" "pub mod mod;"

echo "--- Test 19: Python barrel with 3 files still sorts correctly ---"
PY3_DIR="$TMPDIR_TEST/py3_regen"
mkdir -p "$PY3_DIR"
echo 'x = 1' > "$PY3_DIR/models.py"
echo 'x = 2' > "$PY3_DIR/admin.py"
echo 'x = 3' > "$PY3_DIR/views.py"
echo '' > "$PY3_DIR/__init__.py"
regenerate_barrel "$PY3_DIR/__init__.py" "python" >/dev/null 2>&1
PY3_FIRST=$(grep "from \." "$PY3_DIR/__init__.py" | head -n1)
assert_contains "Python 3-file barrel first import is admin" "admin" "$PY3_FIRST"

echo "--- Test 20: Rust barrel with 3 files still sorts correctly ---"
RS3_DIR="$TMPDIR_TEST/rs3_regen"
mkdir -p "$RS3_DIR"
echo 'pub fn z() {}' > "$RS3_DIR/utils.rs"
echo 'pub fn a() {}' > "$RS3_DIR/api.rs"
echo 'pub fn m() {}' > "$RS3_DIR/core.rs"
echo '' > "$RS3_DIR/mod.rs"
regenerate_barrel "$RS3_DIR/mod.rs" "rust" >/dev/null 2>&1
RS3_FIRST=$(grep "pub mod" "$RS3_DIR/mod.rs" | head -n1)
assert_contains "Rust 3-file barrel first mod is api" "api" "$RS3_FIRST"

# =========================================================================
echo ""
echo "=== T-027: Edge cases: manual exports, non-pure, empty, idempotency ==="
# =========================================================================

echo "--- Test 21: Manual preservation with '// manual' marker (TS) ---"
MANUAL_TS_DIR="$TMPDIR_TEST/manual_ts"
mkdir -p "$MANUAL_TS_DIR"
echo 'export const Foo = 1' > "$MANUAL_TS_DIR/Foo.ts"
printf 'export { custom } from "./special" // manual\n' > "$MANUAL_TS_DIR/index.ts"
regenerate_barrel "$MANUAL_TS_DIR/index.ts" "typescript" >/dev/null 2>&1
assert_file_contains "Manual line preserved in TS barrel" "$MANUAL_TS_DIR/index.ts" 'export { custom } from "./special" // manual'
assert_file_contains "Auto-gen export also present alongside manual" "$MANUAL_TS_DIR/index.ts" "export * from './Foo'"

echo "--- Test 22: Manual preservation with '# manual' marker (Python) ---"
MANUAL_PY_DIR="$TMPDIR_TEST/manual_py"
mkdir -p "$MANUAL_PY_DIR"
echo 'def widget(): pass' > "$MANUAL_PY_DIR/widget.py"
printf '# manual: custom import path\n' > "$MANUAL_PY_DIR/__init__.py"
regenerate_barrel "$MANUAL_PY_DIR/__init__.py" "python" >/dev/null 2>&1
assert_file_contains "Manual line preserved in Python barrel" "$MANUAL_PY_DIR/__init__.py" "# manual: custom import path"
assert_file_contains "Auto-gen import also present" "$MANUAL_PY_DIR/__init__.py" "from .widget import *"

echo "--- Test 23: Manual preservation with '// manual' marker (Rust) ---"
MANUAL_RS_DIR="$TMPDIR_TEST/manual_rs"
mkdir -p "$MANUAL_RS_DIR"
echo 'pub fn x() {}' > "$MANUAL_RS_DIR/x.rs"
printf '// manual: keep this custom module\npub mod old;\n' > "$MANUAL_RS_DIR/mod.rs"
regenerate_barrel "$MANUAL_RS_DIR/mod.rs" "rust" >/dev/null 2>&1
assert_file_contains "Manual line preserved in Rust barrel" "$MANUAL_RS_DIR/mod.rs" "// manual: keep this custom module"
assert_file_contains "Auto-gen mod also present" "$MANUAL_RS_DIR/mod.rs" "pub mod x;"

echo "--- Test 24: Fallback preservation for non-matching export patterns ---"
FALLBACK_DIR="$TMPDIR_TEST/fallback_ts"
mkdir -p "$FALLBACK_DIR"
echo 'export const A = 1' > "$FALLBACK_DIR/A.ts"
printf 'export { named } from "./lib"\n' > "$FALLBACK_DIR/index.ts"
regenerate_barrel "$FALLBACK_DIR/index.ts" "typescript" >/dev/null 2>&1
assert_file_contains "Non-matching export pattern preserved" "$FALLBACK_DIR/index.ts" 'export { named } from "./lib"'
assert_file_contains "Auto-gen export coexists with fallback" "$FALLBACK_DIR/index.ts" "export * from './A'"

echo "--- Test 25: Non-pure barrel skip with log message (TS) ---"
NONPURE_TS_DIR="$TMPDIR_TEST/nonpure_ts"
mkdir -p "$NONPURE_TS_DIR"
echo 'export const helper = 1' > "$NONPURE_TS_DIR/helper.ts"
printf "export * from './helper'\nconst config = { debug: true }\n" > "$NONPURE_TS_DIR/index.ts"
ORIGINAL_CONTENT=$(cat "$NONPURE_TS_DIR/index.ts")
NONPURE_LOG=$(regenerate_barrel "$NONPURE_TS_DIR/index.ts" "typescript" 2>&1)
AFTER_CONTENT=$(cat "$NONPURE_TS_DIR/index.ts")
assert_contains "Non-pure TS barrel SKIP logged" "SKIP" "$NONPURE_LOG"
assert_contains "Non-pure log mentions non-export logic" "non-export logic" "$NONPURE_LOG"
assert_eq "Non-pure TS barrel content unchanged" "$ORIGINAL_CONTENT" "$AFTER_CONTENT"

echo "--- Test 26: Non-pure barrel skip with log message (Python) ---"
NONPURE_PY_DIR="$TMPDIR_TEST/nonpure_py"
mkdir -p "$NONPURE_PY_DIR"
echo 'def util(): pass' > "$NONPURE_PY_DIR/util.py"
printf "from .util import *\nclass Config:\n    pass\n" > "$NONPURE_PY_DIR/__init__.py"
NONPURE_PY_LOG=$(regenerate_barrel "$NONPURE_PY_DIR/__init__.py" "python" 2>&1)
assert_contains "Non-pure Python barrel SKIP logged" "SKIP" "$NONPURE_PY_LOG"
assert_file_contains "Non-pure Python content preserved" "$NONPURE_PY_DIR/__init__.py" "class Config"

echo "--- Test 27: Non-pure barrel skip with log message (Rust) ---"
NONPURE_RS_DIR="$TMPDIR_TEST/nonpure_rs"
mkdir -p "$NONPURE_RS_DIR"
echo 'pub fn api() {}' > "$NONPURE_RS_DIR/api.rs"
printf "pub mod api;\npub fn init() {}\n" > "$NONPURE_RS_DIR/mod.rs"
NONPURE_RS_LOG=$(regenerate_barrel "$NONPURE_RS_DIR/mod.rs" "rust" 2>&1)
assert_contains "Non-pure Rust barrel SKIP logged" "SKIP" "$NONPURE_RS_LOG"
assert_file_contains "Non-pure Rust content preserved" "$NONPURE_RS_DIR/mod.rs" "pub fn init"

echo "--- Test 28: Non-pure barrel returns exit code 0 ---"
regenerate_barrel "$NONPURE_TS_DIR/index.ts" "typescript" >/dev/null 2>&1
assert_eq "Non-pure barrel returns 0 (not error)" "0" "$?"

echo "--- Test 29: Empty directory produces '// No exports' comment (TS) ---"
EMPTY_TS_DIR="$TMPDIR_TEST/empty_ts"
mkdir -p "$EMPTY_TS_DIR"
echo '' > "$EMPTY_TS_DIR/index.ts"
regenerate_barrel "$EMPTY_TS_DIR/index.ts" "typescript" >/dev/null 2>&1
assert_file_contains "TS empty barrel has no-exports comment" "$EMPTY_TS_DIR/index.ts" "// No exports"

echo "--- Test 30: Empty directory produces '# No exports' comment (Python) ---"
EMPTY_PY_DIR="$TMPDIR_TEST/empty_py"
mkdir -p "$EMPTY_PY_DIR"
echo '' > "$EMPTY_PY_DIR/__init__.py"
regenerate_barrel "$EMPTY_PY_DIR/__init__.py" "python" >/dev/null 2>&1
assert_file_contains "Python empty barrel has no-exports comment" "$EMPTY_PY_DIR/__init__.py" "# No exports"

echo "--- Test 31: Empty directory produces '// No exports' comment (Rust) ---"
EMPTY_RS_DIR="$TMPDIR_TEST/empty_rs"
mkdir -p "$EMPTY_RS_DIR"
echo '' > "$EMPTY_RS_DIR/mod.rs"
regenerate_barrel "$EMPTY_RS_DIR/mod.rs" "rust" >/dev/null 2>&1
assert_file_contains "Rust empty barrel has no-exports comment" "$EMPTY_RS_DIR/mod.rs" "// No exports"

echo "--- Test 32: Idempotency - TS two runs produce identical output ---"
IDEM_TS_DIR="$TMPDIR_TEST/idem_ts"
mkdir -p "$IDEM_TS_DIR"
echo 'export const X = 1' > "$IDEM_TS_DIR/X.ts"
echo 'export const Y = 2' > "$IDEM_TS_DIR/Y.ts"
echo '' > "$IDEM_TS_DIR/index.ts"
regenerate_barrel "$IDEM_TS_DIR/index.ts" "typescript" >/dev/null 2>&1
IDEM_TS_FIRST=$(cat "$IDEM_TS_DIR/index.ts")
regenerate_barrel "$IDEM_TS_DIR/index.ts" "typescript" >/dev/null 2>&1
IDEM_TS_SECOND=$(cat "$IDEM_TS_DIR/index.ts")
assert_eq "TS barrel idempotent: run 1 == run 2" "$IDEM_TS_FIRST" "$IDEM_TS_SECOND"

echo "--- Test 33: Idempotency - Python two runs produce identical output ---"
IDEM_PY_DIR="$TMPDIR_TEST/idem_py"
mkdir -p "$IDEM_PY_DIR"
echo 'x = 1' > "$IDEM_PY_DIR/alpha.py"
echo 'y = 2' > "$IDEM_PY_DIR/beta.py"
echo '' > "$IDEM_PY_DIR/__init__.py"
regenerate_barrel "$IDEM_PY_DIR/__init__.py" "python" >/dev/null 2>&1
IDEM_PY_FIRST=$(cat "$IDEM_PY_DIR/__init__.py")
regenerate_barrel "$IDEM_PY_DIR/__init__.py" "python" >/dev/null 2>&1
IDEM_PY_SECOND=$(cat "$IDEM_PY_DIR/__init__.py")
assert_eq "Python barrel idempotent: run 1 == run 2" "$IDEM_PY_FIRST" "$IDEM_PY_SECOND"

echo "--- Test 34: Idempotency - Rust two runs produce identical output ---"
IDEM_RS_DIR="$TMPDIR_TEST/idem_rs"
mkdir -p "$IDEM_RS_DIR"
echo 'pub fn a() {}' > "$IDEM_RS_DIR/a.rs"
echo 'pub fn b() {}' > "$IDEM_RS_DIR/b.rs"
echo '' > "$IDEM_RS_DIR/mod.rs"
regenerate_barrel "$IDEM_RS_DIR/mod.rs" "rust" >/dev/null 2>&1
IDEM_RS_FIRST=$(cat "$IDEM_RS_DIR/mod.rs")
regenerate_barrel "$IDEM_RS_DIR/mod.rs" "rust" >/dev/null 2>&1
IDEM_RS_SECOND=$(cat "$IDEM_RS_DIR/mod.rs")
assert_eq "Rust barrel idempotent: run 1 == run 2" "$IDEM_RS_FIRST" "$IDEM_RS_SECOND"

echo "--- Test 35: Idempotency - JS two runs produce identical output ---"
IDEM_JS_DIR="$TMPDIR_TEST/idem_js"
mkdir -p "$IDEM_JS_DIR"
echo 'const m = 1' > "$IDEM_JS_DIR/m.js"
echo '' > "$IDEM_JS_DIR/index.js"
regenerate_barrel "$IDEM_JS_DIR/index.js" "javascript" >/dev/null 2>&1
IDEM_JS_FIRST=$(cat "$IDEM_JS_DIR/index.js")
regenerate_barrel "$IDEM_JS_DIR/index.js" "javascript" >/dev/null 2>&1
IDEM_JS_SECOND=$(cat "$IDEM_JS_DIR/index.js")
assert_eq "JS barrel idempotent: run 1 == run 2" "$IDEM_JS_FIRST" "$IDEM_JS_SECOND"

echo "--- Test 36: Pure barrel is NOT skipped ---"
PURE_DIR="$TMPDIR_TEST/pure_ts"
mkdir -p "$PURE_DIR"
echo 'export const a = 1' > "$PURE_DIR/a.ts"
printf "// Auto-generated\nexport * from './a'\n" > "$PURE_DIR/index.ts"
PURE_LOG=$(regenerate_barrel "$PURE_DIR/index.ts" "typescript" 2>&1)
assert_contains "Pure TS barrel is regenerated" "Regenerated" "$PURE_LOG"
TOTAL=$((TOTAL + 1))
if echo "$PURE_LOG" | grep -qF "SKIP"; then
  echo "  FAIL: Pure TS barrel should NOT be skipped"
  FAIL=$((FAIL + 1))
else
  echo "  PASS: Pure TS barrel was not skipped"
  PASS=$((PASS + 1))
fi

echo "--- Test 37: BARREL_REGEN_LIB_DIR is set ---"
TOTAL=$((TOTAL + 1))
if [[ -n "$BARREL_REGEN_LIB_DIR" ]]; then
  echo "  PASS: BARREL_REGEN_LIB_DIR is set"
  PASS=$((PASS + 1))
else
  echo "  FAIL: BARREL_REGEN_LIB_DIR is not set"
  FAIL=$((FAIL + 1))
fi

echo "--- Test 38: regenerate_barrel with invalid language returns 1 ---"
INVALID_DIR="$TMPDIR_TEST/invalid_lang"
mkdir -p "$INVALID_DIR"
touch "$INVALID_DIR/index.ts"
regenerate_barrel "$INVALID_DIR/index.ts" "golang" >/dev/null 2>&1
assert_eq "Invalid language returns 1" "1" "$?"

echo "--- Test 39: regenerate_barrel with missing file returns 1 ---"
regenerate_barrel "/nonexistent/path/index.ts" "typescript" >/dev/null 2>&1
assert_eq "Missing file returns 1" "1" "$?"

echo "--- Test 40: regenerate_barrel with missing args returns 1 ---"
regenerate_barrel "" "" >/dev/null 2>&1
assert_eq "Missing args returns 1" "1" "$?"

echo "--- Test 41: detect_barrel_files with missing arg returns 1 ---"
detect_barrel_files "" >/dev/null 2>&1
assert_eq "detect_barrel_files missing arg returns 1" "1" "$?"

echo "--- Test 42: detect_barrel_files with nonexistent dir returns 1 ---"
detect_barrel_files "/nonexistent/dir" >/dev/null 2>&1
assert_eq "detect_barrel_files nonexistent dir returns 1" "1" "$?"

# =========================================================================
echo ""
echo "=== Results: $PASS/$TOTAL passed, $FAIL failed ==="
if [[ $FAIL -eq 0 ]]; then
  exit 0
else
  exit 1
fi
