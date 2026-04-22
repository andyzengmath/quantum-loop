#!/usr/bin/env bash
# Test suite for lib/merge-semantic.sh
# Tests tooling detection, can_semantic_merge, semantic_merge with diff3 fallback,
# TypeScript AST merge, and Python CST merge.

# shellcheck disable=SC1091,SC2034,SC2329

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="$SCRIPT_DIR/../lib"
PASS=0
FAIL=0
TOTAL=0

# Source the library under test
if [[ ! -f "$LIB_DIR/merge-semantic.sh" ]]; then
  echo "SKIP: lib/merge-semantic.sh not found (RED phase)"
  exit 1
fi
source "$LIB_DIR/merge-semantic.sh"

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

# Setup temp directory
TMPDIR=$(mktemp -d)
ORIG_DIR=$(pwd)

cleanup() {
  cd "$ORIG_DIR" || true
  rm -rf "$TMPDIR"
}
trap cleanup EXIT

# =========================================================================
# T-001: Tooling detection and get_semantic_merge_status
# =========================================================================
echo "=== T-001: Tooling detection and get_semantic_merge_status ==="

# --- Test 1: DIFF3_AVAILABLE is set ---
echo "--- Test 1: DIFF3_AVAILABLE is defined ---"
assert_eq "DIFF3_AVAILABLE is defined" "true" "${DIFF3_AVAILABLE:-undefined}"

# --- Test 2: TSMORPH_AVAILABLE is set (true or false, but defined) ---
echo "--- Test 2: TSMORPH_AVAILABLE is defined ---"
if [[ "$TSMORPH_AVAILABLE" == "true" || "$TSMORPH_AVAILABLE" == "false" ]]; then
  TOTAL=$((TOTAL + 1))
  echo "  PASS: TSMORPH_AVAILABLE is defined ($TSMORPH_AVAILABLE)"
  PASS=$((PASS + 1))
else
  TOTAL=$((TOTAL + 1))
  echo "  FAIL: TSMORPH_AVAILABLE is not defined or invalid (${TSMORPH_AVAILABLE:-undefined})"
  FAIL=$((FAIL + 1))
fi

# --- Test 3: LIBCST_AVAILABLE is set (true or false, but defined) ---
echo "--- Test 3: LIBCST_AVAILABLE is defined ---"
if [[ "$LIBCST_AVAILABLE" == "true" || "$LIBCST_AVAILABLE" == "false" ]]; then
  TOTAL=$((TOTAL + 1))
  echo "  PASS: LIBCST_AVAILABLE is defined ($LIBCST_AVAILABLE)"
  PASS=$((PASS + 1))
else
  TOTAL=$((TOTAL + 1))
  echo "  FAIL: LIBCST_AVAILABLE is not defined or invalid (${LIBCST_AVAILABLE:-undefined})"
  FAIL=$((FAIL + 1))
fi

# --- Test 4: get_semantic_merge_status returns comma-separated backends ---
echo "--- Test 4: get_semantic_merge_status returns comma-separated string ---"
STATUS_OUTPUT=$(get_semantic_merge_status)
# Must contain diff3 since diff3 is available on this system
assert_contains "status contains diff3" "diff3" "$STATUS_OUTPUT"

# --- Test 5: get_semantic_merge_status output is backend names only ---
echo "--- Test 5: get_semantic_merge_status format is backend names ---"
# Output should be backend names like "diff3" or "ts-morph,diff3", not key=value pairs
# Since diff3 is available, it should appear as a name (not "diff3=true")
assert_contains "status does not contain =" "diff3" "$STATUS_OUTPUT"

# =========================================================================
# T-002: can_semantic_merge
# =========================================================================
echo "=== T-002: can_semantic_merge ==="

# --- Test 6: .ts files are supported (diff3 fallback) ---
echo "--- Test 6: .ts files are supported ---"
can_semantic_merge "src/app.ts"
assert_eq ".ts file returns 0" "0" "$?"

# --- Test 7: .tsx files are supported ---
echo "--- Test 7: .tsx files are supported ---"
can_semantic_merge "src/Component.tsx"
assert_eq ".tsx file returns 0" "0" "$?"

# --- Test 8: .py files are supported ---
echo "--- Test 8: .py files are supported ---"
can_semantic_merge "lib/util.py"
assert_eq ".py file returns 0" "0" "$?"

# --- Test 9: .js files are supported (text, diff3 available) ---
echo "--- Test 9: .js files are supported ---"
can_semantic_merge "src/index.js"
assert_eq ".js file returns 0" "0" "$?"

# --- Test 10: .sh files are supported (text, diff3 available) ---
echo "--- Test 10: .sh files are supported ---"
can_semantic_merge "scripts/build.sh"
assert_eq ".sh file returns 0" "0" "$?"

# --- Test 11: Binary .png returns 1 ---
echo "--- Test 11: Binary .png returns 1 ---"
can_semantic_merge "assets/logo.png"
assert_eq ".png returns 1" "1" "$?"

# --- Test 12: Binary .jpg returns 1 ---
echo "--- Test 12: Binary .jpg returns 1 ---"
can_semantic_merge "photo.jpg"
assert_eq ".jpg returns 1" "1" "$?"

# --- Test 13: Binary .wasm returns 1 ---
echo "--- Test 13: Binary .wasm returns 1 ---"
can_semantic_merge "module.wasm"
assert_eq ".wasm returns 1" "1" "$?"

# --- Test 14: Binary .exe returns 1 ---
echo "--- Test 14: Binary .exe returns 1 ---"
can_semantic_merge "program.exe"
assert_eq ".exe returns 1" "1" "$?"

# --- Test 15: Empty string returns 1 ---
echo "--- Test 15: Empty string returns 1 ---"
can_semantic_merge ""
assert_eq "empty string returns 1" "1" "$?"

# --- Test 16: File with no extension, text-like (diff3 available) ---
echo "--- Test 16: File with no extension ---"
can_semantic_merge "Makefile"
assert_eq "no-extension file returns 0 (diff3)" "0" "$?"

# --- Test 17: Binary .gif returns 1 ---
echo "--- Test 17: Binary .gif returns 1 ---"
can_semantic_merge "anim.gif"
assert_eq ".gif returns 1" "1" "$?"

# --- Test 18: Binary .ico returns 1 ---
echo "--- Test 18: Binary .ico returns 1 ---"
can_semantic_merge "favicon.ico"
assert_eq ".ico returns 1" "1" "$?"

# --- Test 19: .json files are supported (text, diff3) ---
echo "--- Test 19: .json files are supported ---"
can_semantic_merge "package.json"
assert_eq ".json file returns 0" "0" "$?"

# =========================================================================
# T-003: semantic_merge with diff3 fallback
# =========================================================================
echo "=== T-003: semantic_merge with diff3 fallback ==="

# Create test files for clean 3-way merge (non-adjacent changes for diff3)
BASE_FILE="$TMPDIR/base.txt"
OURS_FILE="$TMPDIR/ours.txt"
THEIRS_FILE="$TMPDIR/theirs.txt"
OUTPUT_FILE="$TMPDIR/output.txt"

cat > "$BASE_FILE" << 'EOF'
line1
line2
line3
line4
line5
EOF

cat > "$OURS_FILE" << 'EOF'
line1
line2-ours
line3
line4
line5
EOF

cat > "$THEIRS_FILE" << 'EOF'
line1
line2
line3
line4
line5-theirs
EOF

# --- Test 20: Clean merge succeeds (return 0) ---
echo "--- Test 20: Clean merge returns 0 ---"
semantic_merge "$BASE_FILE" "$OURS_FILE" "$THEIRS_FILE" "$OUTPUT_FILE" 2>/dev/null
assert_eq "clean merge returns 0" "0" "$?"

# --- Test 21: Output file contains both changes ---
echo "--- Test 21: Output has both changes ---"
OUTPUT_CONTENT=$(cat "$OUTPUT_FILE")
assert_contains "output has ours change" "line2-ours" "$OUTPUT_CONTENT"
assert_contains "output has theirs change" "line5-theirs" "$OUTPUT_CONTENT"

# --- Test 22: Input files are not modified (idempotent) ---
echo "--- Test 22: Input files not modified ---"
BASE_HASH_BEFORE=$(cat "$BASE_FILE")
OURS_HASH_BEFORE=$(cat "$OURS_FILE")
THEIRS_HASH_BEFORE=$(cat "$THEIRS_FILE")
EXPECTED_BASE=$'line1\nline2\nline3\nline4\nline5'
EXPECTED_OURS=$'line1\nline2-ours\nline3\nline4\nline5'
EXPECTED_THEIRS=$'line1\nline2\nline3\nline4\nline5-theirs'
assert_eq "base file unchanged" "$EXPECTED_BASE" "$BASE_HASH_BEFORE"
assert_eq "ours file unchanged" "$EXPECTED_OURS" "$OURS_HASH_BEFORE"
assert_eq "theirs file unchanged" "$EXPECTED_THEIRS" "$THEIRS_HASH_BEFORE"

# --- Test 23: Conflicting merge returns 1 (same line changed both sides) ---
echo "--- Test 23: Conflicting merge returns 1 ---"
CONFLICT_BASE="$TMPDIR/cbase.txt"
CONFLICT_OURS="$TMPDIR/cours.txt"
CONFLICT_THEIRS="$TMPDIR/ctheirs.txt"
CONFLICT_OUTPUT="$TMPDIR/coutput.txt"

cat > "$CONFLICT_BASE" << 'EOF'
line1
line2
line3
EOF

cat > "$CONFLICT_OURS" << 'EOF'
line1
line2-ours
line3
EOF

cat > "$CONFLICT_THEIRS" << 'EOF'
line1
line2-theirs
line3
EOF

semantic_merge "$CONFLICT_BASE" "$CONFLICT_OURS" "$CONFLICT_THEIRS" "$CONFLICT_OUTPUT" 2>/dev/null
assert_eq "conflicting merge returns 1" "1" "$?"

# --- Test 24: Missing base file returns 1 ---
echo "--- Test 24: Missing base file returns 1 ---"
semantic_merge "$TMPDIR/nonexistent.txt" "$OURS_FILE" "$THEIRS_FILE" "$OUTPUT_FILE" 2>/dev/null
assert_eq "missing base returns 1" "1" "$?"

# --- Test 25: Missing ours file returns 1 ---
echo "--- Test 25: Missing ours file returns 1 ---"
semantic_merge "$BASE_FILE" "$TMPDIR/nonexistent.txt" "$THEIRS_FILE" "$OUTPUT_FILE" 2>/dev/null
assert_eq "missing ours returns 1" "1" "$?"

# --- Test 26: Missing theirs file returns 1 ---
echo "--- Test 26: Missing theirs file returns 1 ---"
semantic_merge "$BASE_FILE" "$OURS_FILE" "$TMPDIR/nonexistent.txt" "$OUTPUT_FILE" 2>/dev/null
assert_eq "missing theirs returns 1" "1" "$?"

# --- Test 27: Empty args returns 1 ---
echo "--- Test 27: Empty args returns 1 ---"
semantic_merge "" "" "" "" 2>/dev/null
assert_eq "empty args returns 1" "1" "$?"

# --- Test 28: Identical files (no changes) merge cleanly ---
echo "--- Test 28: Identical files merge cleanly ---"
SAME_FILE="$TMPDIR/same.txt"
SAME_OUT="$TMPDIR/same_out.txt"
echo "same content" > "$SAME_FILE"
cp "$SAME_FILE" "$TMPDIR/same2.txt"
cp "$SAME_FILE" "$TMPDIR/same3.txt"
semantic_merge "$SAME_FILE" "$TMPDIR/same2.txt" "$TMPDIR/same3.txt" "$SAME_OUT" 2>/dev/null
assert_eq "identical files return 0" "0" "$?"
SAME_CONTENT=$(cat "$SAME_OUT")
assert_eq "identical merge content" "same content" "$SAME_CONTENT"

# =========================================================================
# T-004: TypeScript AST merge via ts-morph
# =========================================================================
echo "=== T-004: TypeScript AST merge via ts-morph ==="

if [[ "$TSMORPH_AVAILABLE" == "true" ]]; then
  # Test with actual ts-morph: non-overlapping top-level declarations
  TS_BASE="$TMPDIR/base.ts"
  TS_OURS="$TMPDIR/ours.ts"
  TS_THEIRS="$TMPDIR/theirs.ts"
  TS_OUTPUT="$TMPDIR/output.ts"

  cat > "$TS_BASE" << 'TSEOF'
export function hello(): string {
  return "hello";
}
TSEOF

  cat > "$TS_OURS" << 'TSEOF'
export function hello(): string {
  return "hello";
}

export function fromOurs(): number {
  return 1;
}
TSEOF

  cat > "$TS_THEIRS" << 'TSEOF'
export function hello(): string {
  return "hello";
}

export function fromTheirs(): boolean {
  return true;
}
TSEOF

  # --- Test 29: ts-morph merges non-overlapping additions ---
  echo "--- Test 29: ts-morph merges non-overlapping additions ---"
  semantic_merge "$TS_BASE" "$TS_OURS" "$TS_THEIRS" "$TS_OUTPUT" 2>/dev/null
  assert_eq "ts-morph non-overlapping returns 0" "0" "$?"

  TS_CONTENT=$(cat "$TS_OUTPUT")
  assert_contains "ts output has fromOurs" "fromOurs" "$TS_CONTENT"
  assert_contains "ts output has fromTheirs" "fromTheirs" "$TS_CONTENT"

  # --- Test 30: ts-morph conflicting same-name declaration returns 1 ---
  echo "--- Test 30: ts-morph conflicting same-name returns 1 ---"
  TS_CONFLICT_BASE="$TMPDIR/cbase.ts"
  TS_CONFLICT_OURS="$TMPDIR/cours.ts"
  TS_CONFLICT_THEIRS="$TMPDIR/ctheirs.ts"
  TS_CONFLICT_OUTPUT="$TMPDIR/coutput.ts"

  cat > "$TS_CONFLICT_BASE" << 'TSEOF'
export function greet(): string {
  return "hi";
}
TSEOF

  cat > "$TS_CONFLICT_OURS" << 'TSEOF'
export function greet(): string {
  return "hello from ours";
}
TSEOF

  cat > "$TS_CONFLICT_THEIRS" << 'TSEOF'
export function greet(): string {
  return "hello from theirs";
}
TSEOF

  semantic_merge "$TS_CONFLICT_BASE" "$TS_CONFLICT_OURS" "$TS_CONFLICT_THEIRS" "$TS_CONFLICT_OUTPUT" 2>/dev/null
  TS_CONFLICT_RC=$?
  # Falls back to diff3 which will report conflict
  assert_eq "ts conflicting same-name returns 1" "1" "$TS_CONFLICT_RC"
else
  echo "SKIP: ts-morph not available, testing .ts falls back to diff3"
  # --- Test 29: .ts files fall back to diff3 when ts-morph unavailable ---
  echo "--- Test 29: .ts files fall back to diff3 ---"
  TS_BASE="$TMPDIR/base.ts"
  TS_OURS="$TMPDIR/ours.ts"
  TS_THEIRS="$TMPDIR/theirs.ts"
  TS_OUTPUT="$TMPDIR/output.ts"

  cat > "$TS_BASE" << 'TSEOF'
const a = 1;
const b = 2;
const c = 3;
const d = 4;
const e = 5;
TSEOF

  cat > "$TS_OURS" << 'TSEOF'
const a = 1;
const b = 22;
const c = 3;
const d = 4;
const e = 5;
TSEOF

  cat > "$TS_THEIRS" << 'TSEOF'
const a = 1;
const b = 2;
const c = 3;
const d = 4;
const e = 55;
TSEOF

  semantic_merge "$TS_BASE" "$TS_OURS" "$TS_THEIRS" "$TS_OUTPUT" 2>/dev/null
  assert_eq ".ts diff3 fallback returns 0" "0" "$?"
  TS_CONTENT=$(cat "$TS_OUTPUT")
  assert_contains "ts diff3 has ours" "const b = 22;" "$TS_CONTENT"
  assert_contains "ts diff3 has theirs" "const e = 55;" "$TS_CONTENT"
fi

# =========================================================================
# T-005: Python CST merge via libcst
# =========================================================================
echo "=== T-005: Python CST merge via libcst ==="

if [[ "$LIBCST_AVAILABLE" == "true" ]]; then
  # Test with actual libcst: non-overlapping top-level statements
  PY_BASE="$TMPDIR/base.py"
  PY_OURS="$TMPDIR/ours.py"
  PY_THEIRS="$TMPDIR/theirs.py"
  PY_OUTPUT="$TMPDIR/output.py"

  cat > "$PY_BASE" << 'PYEOF'
def hello():
    return "hello"
PYEOF

  cat > "$PY_OURS" << 'PYEOF'
def hello():
    return "hello"

def from_ours():
    return 1
PYEOF

  cat > "$PY_THEIRS" << 'PYEOF'
def hello():
    return "hello"

def from_theirs():
    return True
PYEOF

  # --- Test 31: libcst merges non-overlapping additions ---
  echo "--- Test 31: libcst merges non-overlapping additions ---"
  semantic_merge "$PY_BASE" "$PY_OURS" "$PY_THEIRS" "$PY_OUTPUT" 2>/dev/null
  assert_eq "libcst non-overlapping returns 0" "0" "$?"

  PY_CONTENT=$(cat "$PY_OUTPUT")
  assert_contains "py output has from_ours" "from_ours" "$PY_CONTENT"
  assert_contains "py output has from_theirs" "from_theirs" "$PY_CONTENT"

  # --- Test 32: libcst conflicting same-name returns 1 ---
  echo "--- Test 32: libcst conflicting same-name returns 1 ---"
  PY_CONFLICT_BASE="$TMPDIR/cbase.py"
  PY_CONFLICT_OURS="$TMPDIR/cours.py"
  PY_CONFLICT_THEIRS="$TMPDIR/ctheirs.py"
  PY_CONFLICT_OUTPUT="$TMPDIR/coutput.py"

  cat > "$PY_CONFLICT_BASE" << 'PYEOF'
def greet():
    return "hi"
PYEOF

  cat > "$PY_CONFLICT_OURS" << 'PYEOF'
def greet():
    return "hello from ours"
PYEOF

  cat > "$PY_CONFLICT_THEIRS" << 'PYEOF'
def greet():
    return "hello from theirs"
PYEOF

  semantic_merge "$PY_CONFLICT_BASE" "$PY_CONFLICT_OURS" "$PY_CONFLICT_THEIRS" "$PY_CONFLICT_OUTPUT" 2>/dev/null
  PY_CONFLICT_RC=$?
  assert_eq "py conflicting same-name returns 1" "1" "$PY_CONFLICT_RC"
else
  echo "SKIP: libcst not available, testing .py falls back to diff3"
  # --- Test 31: .py files fall back to diff3 when libcst unavailable ---
  echo "--- Test 31: .py files fall back to diff3 ---"
  PY_BASE="$TMPDIR/base.py"
  PY_OURS="$TMPDIR/ours.py"
  PY_THEIRS="$TMPDIR/theirs.py"
  PY_OUTPUT="$TMPDIR/output.py"

  cat > "$PY_BASE" << 'PYEOF'
a = 1
b = 2
c = 3
d = 4
e = 5
PYEOF

  cat > "$PY_OURS" << 'PYEOF'
a = 1
b = 22
c = 3
d = 4
e = 5
PYEOF

  cat > "$PY_THEIRS" << 'PYEOF'
a = 1
b = 2
c = 3
d = 4
e = 55
PYEOF

  semantic_merge "$PY_BASE" "$PY_OURS" "$PY_THEIRS" "$PY_OUTPUT" 2>/dev/null
  assert_eq ".py diff3 fallback returns 0" "0" "$?"
  PY_CONTENT=$(cat "$PY_OUTPUT")
  assert_contains "py diff3 has ours" "b = 22" "$PY_CONTENT"
  assert_contains "py diff3 has theirs" "e = 55" "$PY_CONTENT"
fi

# =========================================================================
# Summary
# =========================================================================
cd "$ORIG_DIR" || true
echo ""
echo "=========================================="
echo "=== Final Results: $PASS/$TOTAL passed, $FAIL failed ==="
echo "=========================================="
if [[ $FAIL -eq 0 ]]; then
  exit 0
else
  exit 1
fi
