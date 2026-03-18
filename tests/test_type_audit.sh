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
# Tests for audit_wave_types()
# =========================================================================

echo "=== Test 13: audit_wave_types — no duplicates logs skip and returns 0 ==="
AWN_DIR="$TMPDIR/aw_nodup"
mkdir -p "$AWN_DIR"
touch "$AWN_DIR/tsconfig.json"

cat > "$AWN_DIR/a.ts" <<'EOF'
export interface Alpha {
  value: string;
}
EOF

cat > "$AWN_DIR/b.ts" <<'EOF'
export interface Beta {
  count: number;
}
EOF

# Create a minimal quantum.json for audit_wave_types
cat > "$AWN_DIR/quantum.json" <<'QEOF'
{
  "project": "test",
  "contracts": {},
  "stories": []
}
QEOF

# Initialize a git repo for git diff simulation
(cd "$AWN_DIR" && git init -q && git add -A && git commit -q -m "init")

OUTPUT=$(audit_wave_types "$AWN_DIR/quantum.json" "$AWN_DIR" 1 2>&1)
RET=$?
assert_eq "audit_wave_types returns 0 when no duplicates" "0" "$RET"

# Check that [AUDIT] skip message appears in output (stderr captured)
if echo "$OUTPUT" | grep -q "\[AUDIT\].*skip\|[Ss]kip"; then
  TOTAL=$((TOTAL + 1)); PASS=$((PASS + 1)); echo "  PASS: audit_wave_types logs skip message"
else
  TOTAL=$((TOTAL + 1)); FAIL=$((FAIL + 1)); echo "  FAIL: audit_wave_types should log skip message"
  echo "    output: $OUTPUT"
fi

# =========================================================================
echo "=== Test 14: audit_wave_types — duplicates returns count and logs ==="
AWD_DIR="$TMPDIR/aw_dup"
mkdir -p "$AWD_DIR"
touch "$AWD_DIR/tsconfig.json"

cat > "$AWD_DIR/quantum.json" <<'QEOF'
{
  "project": "test",
  "contracts": {},
  "stories": []
}
QEOF

# Initialize git repo
(cd "$AWD_DIR" && git init -q && git add -A && git commit -q -m "init")

# Add files with duplicate type after initial commit
cat > "$AWD_DIR/svc1.ts" <<'EOF'
export interface UserConfig {
  name: string;
}
EOF

cat > "$AWD_DIR/svc2.ts" <<'EOF'
export interface UserConfig {
  id: number;
}
EOF

(cd "$AWD_DIR" && git add -A && git commit -q -m "add dupes")

OUTPUT=$(audit_wave_types "$AWD_DIR/quantum.json" "$AWD_DIR" 1 2>&1)
RET=$?
assert_eq "audit_wave_types returns 1 (duplicate count) when duplicates found" "1" "$RET"

# Check that duplicate name is logged
if echo "$OUTPUT" | grep -q "UserConfig"; then
  TOTAL=$((TOTAL + 1)); PASS=$((PASS + 1)); echo "  PASS: audit_wave_types logs duplicate name UserConfig"
else
  TOTAL=$((TOTAL + 1)); FAIL=$((FAIL + 1)); echo "  FAIL: audit_wave_types should log duplicate name"
  echo "    output: $OUTPUT"
fi

# =========================================================================
echo "=== Test 15: audit_wave_types — empty repo root returns 0 ==="
EMPTY_QJ="$TMPDIR/empty_qj.json"
echo '{"project":"test","contracts":{},"stories":[]}' > "$EMPTY_QJ"
OUTPUT=$(audit_wave_types "$EMPTY_QJ" "" 1 2>&1)
RET=$?
assert_eq "audit_wave_types with empty repo_root returns 0" "0" "$RET"

# =========================================================================
echo "=== Test 16: audit_wave_types — builds type-auditor prompt on stdout ==="
# Re-use AWD_DIR from test 14 which has duplicates
PROMPT_OUTPUT=$(audit_wave_types "$AWD_DIR/quantum.json" "$AWD_DIR" 2 2>/dev/null)
# Should contain type-auditor-relevant info on stdout
if echo "$PROMPT_OUTPUT" | grep -q "UserConfig\|type-auditor\|TYPE_NAME\|WAVE"; then
  TOTAL=$((TOTAL + 1)); PASS=$((PASS + 1)); echo "  PASS: audit_wave_types outputs auditor prompt on stdout"
else
  TOTAL=$((TOTAL + 1)); FAIL=$((FAIL + 1)); echo "  FAIL: audit_wave_types should output auditor prompt on stdout"
  echo "    stdout: $PROMPT_OUTPUT"
fi

# =========================================================================
echo "=== Test 17: audit_wave_types — checks contract shapes ==="
AWC_DIR="$TMPDIR/aw_contract"
mkdir -p "$AWC_DIR"
touch "$AWC_DIR/tsconfig.json"

cat > "$AWC_DIR/quantum.json" <<'QEOF'
{
  "project": "test",
  "contracts": {
    "shared_types": {
      "UserConfig": {
        "value": "UserConfig",
        "shape": {
          "properties": [{"name": "id", "type": "string"}]
        }
      }
    }
  },
  "stories": []
}
QEOF

# Initialize git repo
(cd "$AWC_DIR" && git init -q && git add -A && git commit -q -m "init")

cat > "$AWC_DIR/svc1.ts" <<'EOF'
export interface UserConfig {
  name: string;
}
EOF

cat > "$AWC_DIR/svc2.ts" <<'EOF'
export interface UserConfig {
  id: number;
}
EOF

(cd "$AWC_DIR" && git add -A && git commit -q -m "add dupes")

PROMPT_OUTPUT=$(audit_wave_types "$AWC_DIR/quantum.json" "$AWC_DIR" 1 2>/dev/null)
# The prompt should reference contract shape info
if echo "$PROMPT_OUTPUT" | grep -q "shape\|contract\|CONTRACTS"; then
  TOTAL=$((TOTAL + 1)); PASS=$((PASS + 1)); echo "  PASS: audit_wave_types includes contract shape in prompt"
else
  TOTAL=$((TOTAL + 1)); FAIL=$((FAIL + 1)); echo "  FAIL: audit_wave_types should include contract shape in prompt"
  echo "    stdout: $PROMPT_OUTPUT"
fi

# =========================================================================
echo "=== Test 18: audit_wave_types — missing json_path returns 0 ==="
OUTPUT=$(audit_wave_types "" "$AWN_DIR" 1 2>&1)
RET=$?
assert_eq "audit_wave_types with empty json_path returns 0" "0" "$RET"

# =========================================================================
echo "=== Test 19: audit_wave_types — nonexistent repo_root returns 0 ==="
FAKE_QJ="$TMPDIR/fake_qj.json"
echo '{"project":"test","contracts":{},"stories":[]}' > "$FAKE_QJ"
OUTPUT=$(audit_wave_types "$FAKE_QJ" "/nonexistent/path/12345" 1 2>&1)
RET=$?
assert_eq "audit_wave_types with nonexistent repo_root returns 0" "0" "$RET"

# =========================================================================
echo "=== Test 20: audit_wave_types — multiple duplicates returns correct count ==="
AWM_DIR="$TMPDIR/aw_multi"
mkdir -p "$AWM_DIR"
touch "$AWM_DIR/tsconfig.json"

cat > "$AWM_DIR/quantum.json" <<'QEOF'
{
  "project": "test",
  "contracts": {},
  "stories": []
}
QEOF

(cd "$AWM_DIR" && git init -q && git add -A && git commit -q -m "init")

cat > "$AWM_DIR/a.ts" <<'EOF'
export interface Foo {
  name: string;
}
export interface Bar {
  value: number;
}
EOF

cat > "$AWM_DIR/b.ts" <<'EOF'
export interface Foo {
  id: number;
}
export interface Bar {
  count: number;
}
EOF

(cd "$AWM_DIR" && git add -A && git commit -q -m "add multi dupes")

OUTPUT=$(audit_wave_types "$AWM_DIR/quantum.json" "$AWM_DIR" 1 2>&1)
RET=$?
assert_eq "audit_wave_types returns 2 for two duplicate types" "2" "$RET"

# =========================================================================
echo "=== Test 21: audit_wave_types — wave_num defaults to 1 ==="
# Use AWD_DIR which has duplicates
PROMPT_OUTPUT=$(audit_wave_types "$AWD_DIR/quantum.json" "$AWD_DIR" 2>/dev/null)
if echo "$PROMPT_OUTPUT" | grep -q "wave 1\|WAVE: 1"; then
  TOTAL=$((TOTAL + 1)); PASS=$((PASS + 1)); echo "  PASS: audit_wave_types defaults wave_num to 1"
else
  TOTAL=$((TOTAL + 1)); FAIL=$((FAIL + 1)); echo "  FAIL: audit_wave_types should default wave_num to 1"
  echo "    stdout: $PROMPT_OUTPUT"
fi

# =========================================================================
# Tests for update_contracts_for_next_wave()
# =========================================================================

echo "=== Test 22: update_contracts_for_next_wave — adds entry to discoveredContracts ==="
UC_DIR="$TMPDIR/uc_basic"
mkdir -p "$UC_DIR"
cat > "$UC_DIR/quantum.json" <<'QEOF'
{
  "project": "test",
  "contracts": {},
  "stories": [],
  "execution": {
    "mode": "parallel",
    "currentWave": 1
  }
}
QEOF

update_contracts_for_next_wave "$UC_DIR/quantum.json" "UserConfig" "src/a.ts src/b.ts" "src/shared/types/user-config.ts" 2
RET=$?
assert_eq "update_contracts_for_next_wave returns 0" "0" "$RET"

# Verify the entry was written
DC_ENTRY=$(jq -r '.execution.discoveredContracts.UserConfig' "$UC_DIR/quantum.json")
if [[ "$DC_ENTRY" != "null" && -n "$DC_ENTRY" ]]; then
  TOTAL=$((TOTAL + 1)); PASS=$((PASS + 1)); echo "  PASS: discoveredContracts.UserConfig exists"
else
  TOTAL=$((TOTAL + 1)); FAIL=$((FAIL + 1)); echo "  FAIL: discoveredContracts.UserConfig should exist"
  echo "    actual: $DC_ENTRY"
fi

WAVE_NUM=$(jq -r '.execution.discoveredContracts.UserConfig.discoveredInWave' "$UC_DIR/quantum.json")
assert_eq "discoveredInWave is 2" "2" "$WAVE_NUM"

CONSOLIDATED=$(jq -r '.execution.discoveredContracts.UserConfig.consolidated' "$UC_DIR/quantum.json")
assert_eq "consolidated is true" "true" "$CONSOLIDATED"

CONSOL_FILE=$(jq -r '.execution.discoveredContracts.UserConfig.consolidatedFile' "$UC_DIR/quantum.json")
assert_eq "consolidatedFile is correct" "src/shared/types/user-config.ts" "$CONSOL_FILE"

SOURCE_COUNT=$(jq '.execution.discoveredContracts.UserConfig.sourceFiles | length' "$UC_DIR/quantum.json")
assert_eq "sourceFiles has 2 entries" "2" "$SOURCE_COUNT"

# =========================================================================
echo "=== Test 23: update_contracts_for_next_wave — initializes discoveredContracts if absent ==="
UC2_DIR="$TMPDIR/uc_init"
mkdir -p "$UC2_DIR"
cat > "$UC2_DIR/quantum.json" <<'QEOF'
{
  "project": "test",
  "contracts": {},
  "stories": [],
  "execution": {
    "mode": "parallel"
  }
}
QEOF

update_contracts_for_next_wave "$UC2_DIR/quantum.json" "Config" "a.py b.py" "shared/config.py" 3
RET=$?
assert_eq "update_contracts_for_next_wave returns 0 with missing discoveredContracts" "0" "$RET"

DC_EXISTS=$(jq 'has("execution") and (.execution | has("discoveredContracts"))' "$UC2_DIR/quantum.json")
assert_eq "discoveredContracts was initialized" "true" "$DC_EXISTS"

WAVE_NUM=$(jq -r '.execution.discoveredContracts.Config.discoveredInWave' "$UC2_DIR/quantum.json")
assert_eq "Config.discoveredInWave is 3" "3" "$WAVE_NUM"

# =========================================================================
echo "=== Test 24: update_contracts_for_next_wave — preserves existing entries ==="
UC3_DIR="$TMPDIR/uc_preserve"
mkdir -p "$UC3_DIR"
cat > "$UC3_DIR/quantum.json" <<'QEOF'
{
  "project": "test",
  "contracts": {},
  "stories": [],
  "execution": {
    "mode": "parallel",
    "discoveredContracts": {
      "ExistingType": {
        "discoveredInWave": 1,
        "sourceFiles": ["x.ts"],
        "consolidated": true,
        "consolidatedFile": "shared/existing.ts"
      }
    }
  }
}
QEOF

update_contracts_for_next_wave "$UC3_DIR/quantum.json" "NewType" "y.ts z.ts" "shared/new.ts" 2
RET=$?
assert_eq "update_contracts_for_next_wave returns 0 preserving existing" "0" "$RET"

EXISTING=$(jq -r '.execution.discoveredContracts.ExistingType.discoveredInWave' "$UC3_DIR/quantum.json")
assert_eq "ExistingType preserved" "1" "$EXISTING"

NEW_ENTRY=$(jq -r '.execution.discoveredContracts.NewType.discoveredInWave' "$UC3_DIR/quantum.json")
assert_eq "NewType added" "2" "$NEW_ENTRY"

# =========================================================================
echo "=== Test 25: update_contracts_for_next_wave — empty type_name returns error ==="
UC4_DIR="$TMPDIR/uc_empty"
mkdir -p "$UC4_DIR"
cat > "$UC4_DIR/quantum.json" <<'QEOF'
{"project":"test","execution":{}}
QEOF

update_contracts_for_next_wave "$UC4_DIR/quantum.json" "" "a.ts" "b.ts" 1 2>/dev/null
RET=$?
assert_eq "update_contracts_for_next_wave with empty type_name returns 1" "1" "$RET"

# =========================================================================
echo "=== Test 26: update_contracts_for_next_wave — empty json_path returns error ==="
update_contracts_for_next_wave "" "Foo" "a.ts" "b.ts" 1 2>/dev/null
RET=$?
assert_eq "update_contracts_for_next_wave with empty json_path returns 1" "1" "$RET"

# =========================================================================
echo "=== Test 27: update_contracts_for_next_wave — JSON remains valid after write ==="
# Re-read the file from test 22 and verify it's valid JSON
jq . "$UC_DIR/quantum.json" > /dev/null 2>&1
RET=$?
assert_eq "quantum.json remains valid JSON after update" "0" "$RET"

# =========================================================================
echo "=== Test 28: update_contracts_for_next_wave — no execution field initializes it ==="
UC5_DIR="$TMPDIR/uc_no_exec"
mkdir -p "$UC5_DIR"
cat > "$UC5_DIR/quantum.json" <<'QEOF'
{
  "project": "test",
  "contracts": {},
  "stories": []
}
QEOF

update_contracts_for_next_wave "$UC5_DIR/quantum.json" "Widget" "w1.ts w2.ts" "shared/widget.ts" 1
RET=$?
assert_eq "update_contracts_for_next_wave returns 0 with no execution field" "0" "$RET"

WAVE_NUM=$(jq -r '.execution.discoveredContracts.Widget.discoveredInWave' "$UC5_DIR/quantum.json")
assert_eq "Widget.discoveredInWave is 1" "1" "$WAVE_NUM"

# =========================================================================
echo ""
echo "=== Results: $PASS/$TOTAL passed, $FAIL failed ==="
if [[ $FAIL -eq 0 ]]; then
  exit 0
else
  exit 1
fi
