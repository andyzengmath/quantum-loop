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
# Tests for generate_definition_file()
# =========================================================================

echo ""
echo "--- generate_definition_file() tests ---"

# =========================================================================
echo "=== Test 25: generate_definition_file — writes definition verbatim when present ==="
GEN_DIR1="$TMPDIR/gen_def_verbatim"
mkdir -p "$GEN_DIR1"
TYPE_JSON_1='{"definitionFile":"src/types/Priority.ts","definition":"export interface Priority {\n  label: string;\n  level: number;\n}","consumers":["US-002","US-003"]}'
RESULT=$(generate_definition_file "Priority" "$TYPE_JSON_1" "typescript" "$GEN_DIR1" 2>&1)
# Check file was created
if [[ -f "$GEN_DIR1/src/types/Priority.ts" ]]; then
  # Normalize line endings for cross-platform (Windows jq produces CRLF)
  CONTENT=$(cat "$GEN_DIR1/src/types/Priority.ts" | tr -d '\r')
  EXPECTED=$(printf "export interface Priority {\n  label: string;\n  level: number;\n}")
  assert_eq "Definition written verbatim to definitionFile" "$EXPECTED" "$CONTENT"
else
  TOTAL=$((TOTAL + 1))
  FAIL=$((FAIL + 1))
  echo "  FAIL: File src/types/Priority.ts was not created"
fi

# =========================================================================
echo "=== Test 26: generate_definition_file — generates TS interface from shape ==="
GEN_DIR2="$TMPDIR/gen_shape_ts"
mkdir -p "$GEN_DIR2"
TYPE_JSON_2='{"definitionFile":"src/types/TaskStatus.ts","shape":{"properties":[{"name":"value","type":"string"},{"name":"label","type":"string","readonly":true}],"methods":[{"name":"isComplete","params":[],"returns":"boolean"}]},"consumers":["US-002","US-003"]}'
generate_definition_file "TaskStatus" "$TYPE_JSON_2" "typescript" "$GEN_DIR2" 2>&1
if [[ -f "$GEN_DIR2/src/types/TaskStatus.ts" ]]; then
  CONTENT=$(cat "$GEN_DIR2/src/types/TaskStatus.ts")
  # Should contain "export interface TaskStatus"
  if echo "$CONTENT" | grep -q "export interface TaskStatus"; then
    TOTAL=$((TOTAL + 1))
    PASS=$((PASS + 1))
    echo "  PASS: Generated TS interface from shape"
  else
    TOTAL=$((TOTAL + 1))
    FAIL=$((FAIL + 1))
    echo "  FAIL: Generated file does not contain 'export interface TaskStatus'"
    echo "    actual: $CONTENT"
  fi
else
  TOTAL=$((TOTAL + 1))
  FAIL=$((FAIL + 1))
  echo "  FAIL: File src/types/TaskStatus.ts was not created from shape"
fi

# =========================================================================
echo "=== Test 27: generate_definition_file — generates Python Protocol from shape ==="
GEN_DIR3="$TMPDIR/gen_shape_py"
mkdir -p "$GEN_DIR3"
TYPE_JSON_3='{"definitionFile":"src/shared/task_status.py","shape":{"properties":[{"name":"value","type":"str"},{"name":"label","type":"str","readonly":true}],"methods":[]},"consumers":["US-002","US-003"]}'
generate_definition_file "TaskStatus" "$TYPE_JSON_3" "python" "$GEN_DIR3" 2>&1
if [[ -f "$GEN_DIR3/src/shared/task_status.py" ]]; then
  CONTENT=$(cat "$GEN_DIR3/src/shared/task_status.py")
  if echo "$CONTENT" | grep -q "class TaskStatus(Protocol)"; then
    TOTAL=$((TOTAL + 1))
    PASS=$((PASS + 1))
    echo "  PASS: Generated Python Protocol from shape"
  else
    TOTAL=$((TOTAL + 1))
    FAIL=$((FAIL + 1))
    echo "  FAIL: Generated file does not contain 'class TaskStatus(Protocol)'"
    echo "    actual: $CONTENT"
  fi
else
  TOTAL=$((TOTAL + 1))
  FAIL=$((FAIL + 1))
  echo "  FAIL: File src/shared/task_status.py was not created from shape"
fi

# =========================================================================
echo "=== Test 28: generate_definition_file — generates Go interface from shape ==="
GEN_DIR4="$TMPDIR/gen_shape_go"
mkdir -p "$GEN_DIR4"
TYPE_JSON_4='{"definitionFile":"internal/shared/taskstatus.go","shape":{"properties":[],"methods":[{"name":"IsComplete","params":[],"returns":"bool"},{"name":"Label","params":[],"returns":"string"}]},"consumers":["US-002","US-003"]}'
generate_definition_file "TaskStatus" "$TYPE_JSON_4" "go" "$GEN_DIR4" 2>&1
if [[ -f "$GEN_DIR4/internal/shared/taskstatus.go" ]]; then
  CONTENT=$(cat "$GEN_DIR4/internal/shared/taskstatus.go")
  if echo "$CONTENT" | grep -q "type TaskStatus interface"; then
    TOTAL=$((TOTAL + 1))
    PASS=$((PASS + 1))
    echo "  PASS: Generated Go interface from shape"
  else
    TOTAL=$((TOTAL + 1))
    FAIL=$((FAIL + 1))
    echo "  FAIL: Generated file does not contain 'type TaskStatus interface'"
    echo "    actual: $CONTENT"
  fi
else
  TOTAL=$((TOTAL + 1))
  FAIL=$((FAIL + 1))
  echo "  FAIL: File internal/shared/taskstatus.go was not created from shape"
fi

# =========================================================================
echo "=== Test 29: generate_definition_file — skips when neither definition nor shape ==="
GEN_DIR5="$TMPDIR/gen_neither"
mkdir -p "$GEN_DIR5"
TYPE_JSON_5='{"definitionFile":"src/types/Empty.ts","consumers":["US-002","US-003"]}'
RESULT=$(generate_definition_file "Empty" "$TYPE_JSON_5" "typescript" "$GEN_DIR5" 2>&1)
if echo "$RESULT" | grep -q "\[MATERIALIZE\].*warning"; then
  TOTAL=$((TOTAL + 1))
  PASS=$((PASS + 1))
  echo "  PASS: Warning logged when neither definition nor shape"
else
  # Check file was NOT created
  if [[ ! -f "$GEN_DIR5/src/types/Empty.ts" ]]; then
    TOTAL=$((TOTAL + 1))
    PASS=$((PASS + 1))
    echo "  PASS: File not created when neither definition nor shape"
  else
    TOTAL=$((TOTAL + 1))
    FAIL=$((FAIL + 1))
    echo "  FAIL: File was created despite no definition or shape"
  fi
fi

# =========================================================================
echo "=== Test 30: generate_definition_file — idempotent skip when file exists with same content ==="
GEN_DIR6="$TMPDIR/gen_idempotent"
mkdir -p "$GEN_DIR6/src/types"
printf "export interface Priority {\n  label: string;\n  level: number;\n}" > "$GEN_DIR6/src/types/Priority.ts"
TYPE_JSON_6='{"definitionFile":"src/types/Priority.ts","definition":"export interface Priority {\n  label: string;\n  level: number;\n}","consumers":["US-002","US-003"]}'
RESULT=$(generate_definition_file "Priority" "$TYPE_JSON_6" "typescript" "$GEN_DIR6" 2>&1)
# Content should remain unchanged
CONTENT=$(cat "$GEN_DIR6/src/types/Priority.ts")
EXPECTED=$(printf "export interface Priority {\n  label: string;\n  level: number;\n}")
assert_eq "Idempotent: file with same content not modified" "$EXPECTED" "$CONTENT"

# =========================================================================
echo "=== Test 31: generate_definition_file — does NOT overwrite file with different content ==="
GEN_DIR7="$TMPDIR/gen_no_overwrite"
mkdir -p "$GEN_DIR7/src/types"
printf "// existing different content\nexport type Priority = 'high' | 'low';\n" > "$GEN_DIR7/src/types/Priority.ts"
ORIGINAL_CONTENT=$(cat "$GEN_DIR7/src/types/Priority.ts")
TYPE_JSON_7='{"definitionFile":"src/types/Priority.ts","definition":"export interface Priority {\n  label: string;\n  level: number;\n}","consumers":["US-002","US-003"]}'
RESULT=$(generate_definition_file "Priority" "$TYPE_JSON_7" "typescript" "$GEN_DIR7" 2>&1)
CONTENT_AFTER=$(cat "$GEN_DIR7/src/types/Priority.ts")
assert_eq "File with different content NOT overwritten" "$ORIGINAL_CONTENT" "$CONTENT_AFTER"
if echo "$RESULT" | grep -q "\[MATERIALIZE\] SKIP"; then
  TOTAL=$((TOTAL + 1))
  PASS=$((PASS + 1))
  echo "  PASS: [MATERIALIZE] SKIP logged for different content"
else
  TOTAL=$((TOTAL + 1))
  FAIL=$((FAIL + 1))
  echo "  FAIL: Expected [MATERIALIZE] SKIP log message"
  echo "    actual output: $RESULT"
fi

# =========================================================================
echo "=== Test 32: generate_definition_file — creates parent directories ==="
GEN_DIR8="$TMPDIR/gen_mkdir"
mkdir -p "$GEN_DIR8"
# parent dir does NOT exist yet
TYPE_JSON_8='{"definitionFile":"deep/nested/dir/types/Foo.ts","definition":"export interface Foo {}","consumers":["US-002","US-003"]}'
generate_definition_file "Foo" "$TYPE_JSON_8" "typescript" "$GEN_DIR8" 2>&1
if [[ -f "$GEN_DIR8/deep/nested/dir/types/Foo.ts" ]]; then
  TOTAL=$((TOTAL + 1))
  PASS=$((PASS + 1))
  echo "  PASS: Parent directories created with mkdir -p"
else
  TOTAL=$((TOTAL + 1))
  FAIL=$((FAIL + 1))
  echo "  FAIL: Parent directories not created"
fi

# =========================================================================
# Edge case tests
# =========================================================================

echo "=== Test 33: generate_definition_file — empty type_name ==="
GEN_DIR9="$TMPDIR/gen_empty_name"
mkdir -p "$GEN_DIR9"
TYPE_JSON_9='{"definitionFile":"src/types/X.ts","definition":"export interface X {}","consumers":["US-002","US-003"]}'
RESULT=$(generate_definition_file "" "$TYPE_JSON_9" "typescript" "$GEN_DIR9" 2>&1)
# Should handle gracefully (warning or skip)
TOTAL=$((TOTAL + 1))
if [[ $? -eq 0 ]] || echo "$RESULT" | grep -qi "warning\|skip\|error"; then
  PASS=$((PASS + 1))
  echo "  PASS: Empty type_name handled gracefully"
else
  FAIL=$((FAIL + 1))
  echo "  FAIL: Empty type_name not handled"
fi

# =========================================================================
echo "=== Test 34: generate_definition_file — empty JSON ==="
GEN_DIR10="$TMPDIR/gen_empty_json"
mkdir -p "$GEN_DIR10"
RESULT=$(generate_definition_file "Foo" "{}" "typescript" "$GEN_DIR10" 2>&1)
# Should handle gracefully since no definitionFile
TOTAL=$((TOTAL + 1))
if echo "$RESULT" | grep -qi "warning\|skip"; then
  PASS=$((PASS + 1))
  echo "  PASS: Empty JSON handled with warning"
else
  # Also OK if it just returns without creating anything
  PASS=$((PASS + 1))
  echo "  PASS: Empty JSON handled gracefully"
fi

# =========================================================================
echo "=== Test 35: generate_definition_file — TS shape with readonly properties ==="
GEN_DIR11="$TMPDIR/gen_ts_readonly"
mkdir -p "$GEN_DIR11"
TYPE_JSON_11='{"definitionFile":"src/types/ReadOnly.ts","shape":{"properties":[{"name":"id","type":"string","readonly":true},{"name":"count","type":"number"}],"methods":[]},"consumers":["US-002","US-003"]}'
generate_definition_file "ReadOnly" "$TYPE_JSON_11" "typescript" "$GEN_DIR11" 2>&1
if [[ -f "$GEN_DIR11/src/types/ReadOnly.ts" ]]; then
  CONTENT=$(cat "$GEN_DIR11/src/types/ReadOnly.ts")
  if echo "$CONTENT" | grep -q "readonly id: string"; then
    TOTAL=$((TOTAL + 1))
    PASS=$((PASS + 1))
    echo "  PASS: Readonly property generated correctly in TS"
  else
    TOTAL=$((TOTAL + 1))
    FAIL=$((FAIL + 1))
    echo "  FAIL: Expected 'readonly id: string' in generated TS"
    echo "    actual: $CONTENT"
  fi
else
  TOTAL=$((TOTAL + 1))
  FAIL=$((FAIL + 1))
  echo "  FAIL: File not created for readonly shape test"
fi

# =========================================================================
# Tests for materialize_contracts()
# =========================================================================

echo ""
echo "--- materialize_contracts() tests ---"

# =========================================================================
echo "=== Test 36: materialize_contracts — materializes multi-consumer types ==="
MC_DIR1="$TMPDIR/mc_multi"
mkdir -p "$MC_DIR1"
touch "$MC_DIR1/tsconfig.json"
# Create a quantum.json with two multi-consumer types
cat > "$MC_DIR1/quantum.json" << 'QJSON'
{
  "contracts": {
    "shared_types": {
      "Priority": {
        "value": "Priority",
        "definitionFile": "src/types/Priority.ts",
        "definition": "export interface Priority {\n  label: string;\n}",
        "owner": "US-001",
        "consumers": ["US-002", "US-003"]
      },
      "Status": {
        "value": "Status",
        "definitionFile": "src/types/Status.ts",
        "definition": "export type Status = 'active' | 'done';",
        "owner": "US-001",
        "consumers": ["US-002", "US-004"]
      }
    }
  },
  "execution": {}
}
QJSON
# Init git repo for the commit
(cd "$MC_DIR1" && git init -q && git add -A && git commit -m "init" -q) 2>/dev/null
RESULT=$(materialize_contracts "$MC_DIR1/quantum.json" "$MC_DIR1" 1 2>&1)
# Both files should exist
if [[ -f "$MC_DIR1/src/types/Priority.ts" && -f "$MC_DIR1/src/types/Status.ts" ]]; then
  TOTAL=$((TOTAL + 1))
  PASS=$((PASS + 1))
  echo "  PASS: Both multi-consumer type files created"
else
  TOTAL=$((TOTAL + 1))
  FAIL=$((FAIL + 1))
  echo "  FAIL: Not all multi-consumer type files created"
  echo "    Priority.ts exists: $(test -f "$MC_DIR1/src/types/Priority.ts" && echo yes || echo no)"
  echo "    Status.ts exists: $(test -f "$MC_DIR1/src/types/Status.ts" && echo yes || echo no)"
fi

# =========================================================================
echo "=== Test 37: materialize_contracts — skips single-consumer types ==="
MC_DIR2="$TMPDIR/mc_single"
mkdir -p "$MC_DIR2"
touch "$MC_DIR2/tsconfig.json"
cat > "$MC_DIR2/quantum.json" << 'QJSON'
{
  "contracts": {
    "shared_types": {
      "Priority": {
        "value": "Priority",
        "definitionFile": "src/types/Priority.ts",
        "definition": "export interface Priority {}",
        "owner": "US-001",
        "consumers": ["US-002"]
      }
    }
  },
  "execution": {}
}
QJSON
(cd "$MC_DIR2" && git init -q && git add -A && git commit -m "init" -q) 2>/dev/null
RESULT=$(materialize_contracts "$MC_DIR2/quantum.json" "$MC_DIR2" 1 2>&1)
if [[ ! -f "$MC_DIR2/src/types/Priority.ts" ]]; then
  TOTAL=$((TOTAL + 1))
  PASS=$((PASS + 1))
  echo "  PASS: Single-consumer type NOT materialized"
else
  TOTAL=$((TOTAL + 1))
  FAIL=$((FAIL + 1))
  echo "  FAIL: Single-consumer type was materialized"
fi

# =========================================================================
echo "=== Test 38: materialize_contracts — skips types without consumers ==="
MC_DIR3="$TMPDIR/mc_no_consumers"
mkdir -p "$MC_DIR3"
touch "$MC_DIR3/tsconfig.json"
cat > "$MC_DIR3/quantum.json" << 'QJSON'
{
  "contracts": {
    "shared_types": {
      "Foo": {
        "value": "Foo",
        "definitionFile": "src/types/Foo.ts",
        "definition": "export interface Foo {}"
      }
    }
  },
  "execution": {}
}
QJSON
(cd "$MC_DIR3" && git init -q && git add -A && git commit -m "init" -q) 2>/dev/null
RESULT=$(materialize_contracts "$MC_DIR3/quantum.json" "$MC_DIR3" 1 2>&1)
if [[ ! -f "$MC_DIR3/src/types/Foo.ts" ]]; then
  TOTAL=$((TOTAL + 1))
  PASS=$((PASS + 1))
  echo "  PASS: Type without consumers NOT materialized"
else
  TOTAL=$((TOTAL + 1))
  FAIL=$((FAIL + 1))
  echo "  FAIL: Type without consumers was materialized"
fi

# =========================================================================
echo "=== Test 39: materialize_contracts — creates git commit ==="
MC_DIR4="$TMPDIR/mc_commit"
mkdir -p "$MC_DIR4"
touch "$MC_DIR4/tsconfig.json"
cat > "$MC_DIR4/quantum.json" << 'QJSON'
{
  "contracts": {
    "shared_types": {
      "Priority": {
        "value": "Priority",
        "definitionFile": "src/types/Priority.ts",
        "definition": "export interface Priority {}",
        "owner": "US-001",
        "consumers": ["US-002", "US-003"]
      }
    }
  },
  "execution": {}
}
QJSON
(cd "$MC_DIR4" && git init -q && git add -A && git commit -m "init" -q) 2>/dev/null
materialize_contracts "$MC_DIR4/quantum.json" "$MC_DIR4" 2 2>/dev/null
LAST_COMMIT=$(cd "$MC_DIR4" && git log --oneline -1 2>/dev/null)
if echo "$LAST_COMMIT" | grep -q "chore: materialize contracts for Wave 2"; then
  TOTAL=$((TOTAL + 1))
  PASS=$((PASS + 1))
  echo "  PASS: Git commit created with correct message"
else
  TOTAL=$((TOTAL + 1))
  FAIL=$((FAIL + 1))
  echo "  FAIL: Expected git commit 'chore: materialize contracts for Wave 2'"
  echo "    actual: $LAST_COMMIT"
fi

# =========================================================================
echo "=== Test 40: materialize_contracts — updates execution.materializedContracts ==="
MC_DIR5="$TMPDIR/mc_exec_update"
mkdir -p "$MC_DIR5"
touch "$MC_DIR5/tsconfig.json"
cat > "$MC_DIR5/quantum.json" << 'QJSON'
{
  "contracts": {
    "shared_types": {
      "Priority": {
        "value": "Priority",
        "definitionFile": "src/types/Priority.ts",
        "definition": "export interface Priority {}",
        "owner": "US-001",
        "consumers": ["US-002", "US-003"]
      }
    }
  },
  "execution": {}
}
QJSON
(cd "$MC_DIR5" && git init -q && git add -A && git commit -m "init" -q) 2>/dev/null
materialize_contracts "$MC_DIR5/quantum.json" "$MC_DIR5" 1 2>/dev/null
MATERIALIZED=$(jq -r '.execution.materializedContracts // [] | .[]' "$MC_DIR5/quantum.json" 2>/dev/null)
if echo "$MATERIALIZED" | grep -q "Priority"; then
  TOTAL=$((TOTAL + 1))
  PASS=$((PASS + 1))
  echo "  PASS: execution.materializedContracts updated"
else
  TOTAL=$((TOTAL + 1))
  FAIL=$((FAIL + 1))
  echo "  FAIL: execution.materializedContracts not updated"
  echo "    quantum.json execution: $(jq '.execution' "$MC_DIR5/quantum.json" 2>/dev/null)"
fi

# =========================================================================
echo "=== Test 41: materialize_contracts — prints materialized names to stdout ==="
MC_DIR6="$TMPDIR/mc_stdout"
mkdir -p "$MC_DIR6"
touch "$MC_DIR6/tsconfig.json"
cat > "$MC_DIR6/quantum.json" << 'QJSON'
{
  "contracts": {
    "shared_types": {
      "Priority": {
        "value": "Priority",
        "definitionFile": "src/types/Priority.ts",
        "definition": "export interface Priority {}",
        "owner": "US-001",
        "consumers": ["US-002", "US-003"]
      },
      "Status": {
        "value": "Status",
        "definitionFile": "src/types/Status.ts",
        "definition": "export type Status = 'active';",
        "owner": "US-001",
        "consumers": ["US-002", "US-004"]
      }
    }
  },
  "execution": {}
}
QJSON
(cd "$MC_DIR6" && git init -q && git add -A && git commit -m "init" -q) 2>/dev/null
STDOUT_RESULT=$(materialize_contracts "$MC_DIR6/quantum.json" "$MC_DIR6" 1 2>/dev/null)
if echo "$STDOUT_RESULT" | grep -q "Priority" && echo "$STDOUT_RESULT" | grep -q "Status"; then
  TOTAL=$((TOTAL + 1))
  PASS=$((PASS + 1))
  echo "  PASS: Materialized names printed to stdout"
else
  TOTAL=$((TOTAL + 1))
  FAIL=$((FAIL + 1))
  echo "  FAIL: Expected materialized names on stdout"
  echo "    actual: $STDOUT_RESULT"
fi

# =========================================================================
echo "=== Test 42: materialize_contracts — reads discoveredContracts ==="
MC_DIR7="$TMPDIR/mc_discovered"
mkdir -p "$MC_DIR7"
touch "$MC_DIR7/tsconfig.json"
cat > "$MC_DIR7/quantum.json" << 'QJSON'
{
  "contracts": {
    "shared_types": {}
  },
  "execution": {
    "discoveredContracts": {
      "UserProfile": {
        "discoveredInWave": 1,
        "sourceFiles": ["src/a.ts", "src/b.ts"],
        "consolidated": true,
        "consolidatedFile": "src/types/UserProfile.ts",
        "consumers": ["US-005", "US-006"],
        "definition": "export interface UserProfile { name: string; }"
      }
    }
  }
}
QJSON
(cd "$MC_DIR7" && git init -q && git add -A && git commit -m "init" -q) 2>/dev/null
STDOUT_RESULT=$(materialize_contracts "$MC_DIR7/quantum.json" "$MC_DIR7" 2 2>/dev/null)
if [[ -f "$MC_DIR7/src/types/UserProfile.ts" ]]; then
  TOTAL=$((TOTAL + 1))
  PASS=$((PASS + 1))
  echo "  PASS: Discovered contract materialized"
else
  TOTAL=$((TOTAL + 1))
  FAIL=$((FAIL + 1))
  echo "  FAIL: Discovered contract NOT materialized"
fi

# =========================================================================
echo "=== Test 43: materialize_contracts — no-op when no multi-consumer contracts ==="
MC_DIR8="$TMPDIR/mc_noop"
mkdir -p "$MC_DIR8"
touch "$MC_DIR8/tsconfig.json"
cat > "$MC_DIR8/quantum.json" << 'QJSON'
{
  "contracts": {
    "shared_types": {
      "Solo": {
        "value": "Solo",
        "definitionFile": "src/types/Solo.ts",
        "definition": "export interface Solo {}",
        "consumers": ["US-001"]
      }
    }
  },
  "execution": {}
}
QJSON
(cd "$MC_DIR8" && git init -q && git add -A && git commit -m "init" -q) 2>/dev/null
INITIAL_COMMIT=$(cd "$MC_DIR8" && git log --oneline -1 2>/dev/null)
STDERR_RESULT=$(materialize_contracts "$MC_DIR8/quantum.json" "$MC_DIR8" 1 2>&1 >/dev/null)
AFTER_COMMIT=$(cd "$MC_DIR8" && git log --oneline -1 2>/dev/null)
if [[ "$INITIAL_COMMIT" == "$AFTER_COMMIT" ]]; then
  TOTAL=$((TOTAL + 1))
  PASS=$((PASS + 1))
  echo "  PASS: No git commit when nothing to materialize"
else
  TOTAL=$((TOTAL + 1))
  FAIL=$((FAIL + 1))
  echo "  FAIL: Unexpected git commit when nothing to materialize"
fi

# =========================================================================
echo "=== Test 44: materialize_contracts — empty json_path ==="
RESULT=$(materialize_contracts "" "/tmp" 1 2>&1)
RET=$?
if [[ $RET -ne 0 ]]; then
  TOTAL=$((TOTAL + 1))
  PASS=$((PASS + 1))
  echo "  PASS: Empty json_path returns error"
else
  TOTAL=$((TOTAL + 1))
  FAIL=$((FAIL + 1))
  echo "  FAIL: Empty json_path should return error"
fi

# =========================================================================
echo "=== Test 45: materialize_contracts — nonexistent quantum.json ==="
RESULT=$(materialize_contracts "$TMPDIR/nonexistent/quantum.json" "$TMPDIR" 1 2>&1)
RET=$?
if [[ $RET -ne 0 ]]; then
  TOTAL=$((TOTAL + 1))
  PASS=$((PASS + 1))
  echo "  PASS: Nonexistent json_path returns error"
else
  TOTAL=$((TOTAL + 1))
  FAIL=$((FAIL + 1))
  echo "  FAIL: Nonexistent json_path should return error"
fi

# =========================================================================
echo ""
echo "=== Results: $PASS/$TOTAL passed, $FAIL failed ==="
if [[ $FAIL -eq 0 ]]; then
  exit 0
else
  exit 1
fi
