#!/usr/bin/env bash
# Test suite for lib/type-audit.sh
# Tests grep_duplicate_definitions() function across TS, Python, Go patterns

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="$SCRIPT_DIR/../lib"
PASS=0
FAIL=0
TOTAL=0

# Source the library under test
if [[ ! -f "$LIB_DIR/type-audit.sh" ]]; then
  echo "SKIP: lib/type-audit.sh not found (RED phase)"
  exit 1
fi
source "$LIB_DIR/type-audit.sh"

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

# Helper to check JSON array length
json_array_len() {
  echo "$1" | jq 'length'
}

# Helper to get first duplicate name from result
json_first_name() {
  echo "$1" | jq -r '.[0].name'
}

# Helper to get file count for first duplicate
json_first_files_len() {
  echo "$1" | jq '.[0].files | length'
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
echo "=== Test 1: TypeScript duplicate — two files define same interface ==="
TS_DIR="$TMPDIR/ts_project"
mkdir -p "$TS_DIR"
touch "$TS_DIR/tsconfig.json"

cat > "$TS_DIR/a.ts" <<'EOF'
export interface Foo {
  name: string;
}
EOF

cat > "$TS_DIR/b.ts" <<'EOF'
export interface Foo {
  id: number;
}
EOF

RESULT=$(grep_duplicate_definitions "$TS_DIR" "$TS_DIR/a.ts $TS_DIR/b.ts")
LEN=$(json_array_len "$RESULT")
assert_eq "TS duplicate detected (array length 1)" "1" "$LEN"

FIRST_NAME=$(json_first_name "$RESULT")
assert_eq "TS duplicate name is Foo" "Foo" "$FIRST_NAME"

FIRST_FILES_LEN=$(json_first_files_len "$RESULT")
assert_eq "TS duplicate has 2 files" "2" "$FIRST_FILES_LEN"

# =========================================================================
echo "=== Test 2: Python Protocol duplicate ==="
PY_DIR="$TMPDIR/py_project"
mkdir -p "$PY_DIR"
touch "$PY_DIR/pyproject.toml"

cat > "$PY_DIR/x.py" <<'EOF'
class Bar(Protocol):
    def greet(self) -> str: ...
EOF

cat > "$PY_DIR/y.py" <<'EOF'
class Bar(Protocol):
    def greet(self) -> str: ...
EOF

RESULT=$(grep_duplicate_definitions "$PY_DIR" "$PY_DIR/x.py $PY_DIR/y.py")
LEN=$(json_array_len "$RESULT")
assert_eq "Python Protocol duplicate detected (array length 1)" "1" "$LEN"

FIRST_NAME=$(json_first_name "$RESULT")
assert_eq "Python Protocol duplicate name is Bar" "Bar" "$FIRST_NAME"

# =========================================================================
echo "=== Test 3: Go interface duplicate ==="
GO_DIR="$TMPDIR/go_project"
mkdir -p "$GO_DIR"
touch "$GO_DIR/go.mod"

cat > "$GO_DIR/svc.go" <<'EOF'
type Handler interface {
    ServeHTTP(w http.ResponseWriter, r *http.Request)
}
EOF

cat > "$GO_DIR/svc2.go" <<'EOF'
type Handler interface {
    ServeHTTP(w http.ResponseWriter, r *http.Request)
}
EOF

RESULT=$(grep_duplicate_definitions "$GO_DIR" "$GO_DIR/svc.go $GO_DIR/svc2.go")
LEN=$(json_array_len "$RESULT")
assert_eq "Go interface duplicate detected (array length 1)" "1" "$LEN"

FIRST_NAME=$(json_first_name "$RESULT")
assert_eq "Go interface duplicate name is Handler" "Handler" "$FIRST_NAME"

# =========================================================================
echo "=== Test 4: No duplicates — each type defined once ==="
NODUP_DIR="$TMPDIR/nodup_project"
mkdir -p "$NODUP_DIR"
touch "$NODUP_DIR/tsconfig.json"

cat > "$NODUP_DIR/c.ts" <<'EOF'
export interface Alpha {
  value: string;
}
EOF

cat > "$NODUP_DIR/d.ts" <<'EOF'
export interface Beta {
  count: number;
}
EOF

RESULT=$(grep_duplicate_definitions "$NODUP_DIR" "$NODUP_DIR/c.ts $NODUP_DIR/d.ts")
LEN=$(json_array_len "$RESULT")
assert_eq "No duplicates returns empty array" "0" "$LEN"

# =========================================================================
echo "=== Test 5: Scoped to file list only — ignores files not in list ==="
SCOPE_DIR="$TMPDIR/scope_project"
mkdir -p "$SCOPE_DIR"
touch "$SCOPE_DIR/tsconfig.json"

cat > "$SCOPE_DIR/in1.ts" <<'EOF'
export interface Gamma {
  x: number;
}
EOF

cat > "$SCOPE_DIR/in2.ts" <<'EOF'
export type Delta = { y: string };
EOF

# This file defines Gamma too but is NOT in the file list
cat > "$SCOPE_DIR/outside.ts" <<'EOF'
export interface Gamma {
  x: number;
}
EOF

# Only scan in1.ts and in2.ts — Gamma appears once, no duplicate
RESULT=$(grep_duplicate_definitions "$SCOPE_DIR" "$SCOPE_DIR/in1.ts $SCOPE_DIR/in2.ts")
LEN=$(json_array_len "$RESULT")
assert_eq "Scoped scan ignores files not in list" "0" "$LEN"

# =========================================================================
echo "=== Test 6: Cross-file only — same name in same file not flagged ==="
CROSS_DIR="$TMPDIR/cross_project"
mkdir -p "$CROSS_DIR"
touch "$CROSS_DIR/tsconfig.json"

# Two definitions of Epsilon in the SAME file should not be flagged as cross-file duplicate
cat > "$CROSS_DIR/single.ts" <<'EOF'
export interface Epsilon {
  a: string;
}

export type Epsilon = { b: number };
EOF

RESULT=$(grep_duplicate_definitions "$CROSS_DIR" "$CROSS_DIR/single.ts")
LEN=$(json_array_len "$RESULT")
assert_eq "Same-file duplicate not flagged (cross-file only)" "0" "$LEN"

# =========================================================================
echo "=== Test 7: Edge case — empty file list ==="
EMPTY_DIR="$TMPDIR/empty_project"
mkdir -p "$EMPTY_DIR"
touch "$EMPTY_DIR/tsconfig.json"
RESULT=$(grep_duplicate_definitions "$EMPTY_DIR" "")
LEN=$(json_array_len "$RESULT")
assert_eq "Empty file list returns empty array" "0" "$LEN"

# =========================================================================
echo "=== Test 8: Edge case — empty repo root ==="
RESULT=$(grep_duplicate_definitions "" "somefile.ts")
LEN=$(json_array_len "$RESULT")
assert_eq "Empty repo root returns empty array" "0" "$LEN"

# =========================================================================
echo "=== Test 9: Edge case — Python BaseModel duplicate ==="
BM_DIR="$TMPDIR/bm_project"
mkdir -p "$BM_DIR"
touch "$BM_DIR/pyproject.toml"

cat > "$BM_DIR/m1.py" <<'EOF'
class Config(BaseModel):
    name: str
EOF

cat > "$BM_DIR/m2.py" <<'EOF'
class Config(BaseModel):
    value: int
EOF

RESULT=$(grep_duplicate_definitions "$BM_DIR" "$BM_DIR/m1.py $BM_DIR/m2.py")
LEN=$(json_array_len "$RESULT")
assert_eq "Python BaseModel duplicate detected" "1" "$LEN"

FIRST_NAME=$(json_first_name "$RESULT")
assert_eq "Python BaseModel duplicate name is Config" "Config" "$FIRST_NAME"

# =========================================================================
echo "=== Test 10: Edge case — nonexistent files in list ==="
GHOST_DIR="$TMPDIR/ghost_project"
mkdir -p "$GHOST_DIR"
touch "$GHOST_DIR/tsconfig.json"
RESULT=$(grep_duplicate_definitions "$GHOST_DIR" "$GHOST_DIR/missing1.ts $GHOST_DIR/missing2.ts")
LEN=$(json_array_len "$RESULT")
assert_eq "Nonexistent files return empty array" "0" "$LEN"

# =========================================================================
echo "=== Test 11: Edge case — Go struct duplicate ==="
GO2_DIR="$TMPDIR/go2_project"
mkdir -p "$GO2_DIR"
touch "$GO2_DIR/go.mod"

cat > "$GO2_DIR/a.go" <<'EOF'
type Config struct {
    Name string
}
EOF

cat > "$GO2_DIR/b.go" <<'EOF'
type Config struct {
    Value int
}
EOF

RESULT=$(grep_duplicate_definitions "$GO2_DIR" "$GO2_DIR/a.go $GO2_DIR/b.go")
LEN=$(json_array_len "$RESULT")
assert_eq "Go struct duplicate detected" "1" "$LEN"

FIRST_NAME=$(json_first_name "$RESULT")
assert_eq "Go struct duplicate name is Config" "Config" "$FIRST_NAME"

# =========================================================================
echo "=== Test 12: Edge case — TS export type duplicate ==="
TT_DIR="$TMPDIR/tt_project"
mkdir -p "$TT_DIR"
touch "$TT_DIR/tsconfig.json"

cat > "$TT_DIR/t1.ts" <<'EOF'
export type Result = { ok: boolean };
EOF

cat > "$TT_DIR/t2.ts" <<'EOF'
export type Result = { success: boolean };
EOF

RESULT=$(grep_duplicate_definitions "$TT_DIR" "$TT_DIR/t1.ts $TT_DIR/t2.ts")
LEN=$(json_array_len "$RESULT")
assert_eq "TS export type duplicate detected" "1" "$LEN"

FIRST_NAME=$(json_first_name "$RESULT")
assert_eq "TS export type duplicate name is Result" "Result" "$FIRST_NAME"

# =========================================================================
echo ""
echo "=== Results: $PASS/$TOTAL passed, $FAIL failed ==="
if [[ $FAIL -eq 0 ]]; then
  exit 0
else
  exit 1
fi
