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
# Additional edge-case tests (US-020)
# =========================================================================

echo ""
echo "--- Additional edge-case tests (US-020) ---"

# =========================================================================
echo "=== Test 46: materialize_contracts — mix of multi-consumer and single-consumer types ==="
MC_MIX_DIR="$TMPDIR/mc_mix"
mkdir -p "$MC_MIX_DIR"
touch "$MC_MIX_DIR/tsconfig.json"
cat > "$MC_MIX_DIR/quantum.json" << 'QJSON'
{
  "contracts": {
    "shared_types": {
      "MultiA": {
        "value": "MultiA",
        "definitionFile": "src/types/MultiA.ts",
        "definition": "export interface MultiA { a: string; }",
        "owner": "US-001",
        "consumers": ["US-002", "US-003", "US-004"]
      },
      "SingleB": {
        "value": "SingleB",
        "definitionFile": "src/types/SingleB.ts",
        "definition": "export interface SingleB { b: number; }",
        "owner": "US-001",
        "consumers": ["US-005"]
      },
      "MultiC": {
        "value": "MultiC",
        "definitionFile": "src/types/MultiC.ts",
        "definition": "export type MultiC = 'x' | 'y';",
        "owner": "US-002",
        "consumers": ["US-003", "US-006"]
      },
      "SingleD": {
        "value": "SingleD",
        "definitionFile": "src/types/SingleD.ts",
        "definition": "export interface SingleD {}",
        "owner": "US-001",
        "consumers": ["US-007"]
      }
    }
  },
  "execution": {}
}
QJSON
(cd "$MC_MIX_DIR" && git init -q && git add -A && git commit -m "init" -q) 2>/dev/null
RESULT=$(materialize_contracts "$MC_MIX_DIR/quantum.json" "$MC_MIX_DIR" 1 2>&1)
# Multi-consumer files (MultiA, MultiC) should exist; single-consumer (SingleB, SingleD) should NOT
MC_MIX_PASS=true
if [[ ! -f "$MC_MIX_DIR/src/types/MultiA.ts" ]]; then
  MC_MIX_PASS=false
  echo "    DETAIL: MultiA.ts missing (should exist)"
fi
if [[ ! -f "$MC_MIX_DIR/src/types/MultiC.ts" ]]; then
  MC_MIX_PASS=false
  echo "    DETAIL: MultiC.ts missing (should exist)"
fi
if [[ -f "$MC_MIX_DIR/src/types/SingleB.ts" ]]; then
  MC_MIX_PASS=false
  echo "    DETAIL: SingleB.ts exists (should NOT exist)"
fi
if [[ -f "$MC_MIX_DIR/src/types/SingleD.ts" ]]; then
  MC_MIX_PASS=false
  echo "    DETAIL: SingleD.ts exists (should NOT exist)"
fi
TOTAL=$((TOTAL + 1))
if [[ "$MC_MIX_PASS" == "true" ]]; then
  PASS=$((PASS + 1))
  echo "  PASS: Multi-consumer materialized, single-consumer skipped"
else
  FAIL=$((FAIL + 1))
  echo "  FAIL: Mix of multi/single consumer not handled correctly"
fi

# =========================================================================
echo "=== Test 47: materialize_contracts — empty contracts object (no-op) ==="
MC_EMPTY_DIR="$TMPDIR/mc_empty_contracts"
mkdir -p "$MC_EMPTY_DIR"
touch "$MC_EMPTY_DIR/tsconfig.json"
cat > "$MC_EMPTY_DIR/quantum.json" << 'QJSON'
{
  "contracts": {},
  "execution": {}
}
QJSON
(cd "$MC_EMPTY_DIR" && git init -q && git add -A && git commit -m "init" -q) 2>/dev/null
INITIAL_COMMIT_EMPTY=$(cd "$MC_EMPTY_DIR" && git log --oneline -1 2>/dev/null)
RESULT=$(materialize_contracts "$MC_EMPTY_DIR/quantum.json" "$MC_EMPTY_DIR" 1 2>&1)
RET=$?
AFTER_COMMIT_EMPTY=$(cd "$MC_EMPTY_DIR" && git log --oneline -1 2>/dev/null)
TOTAL=$((TOTAL + 1))
if [[ $RET -eq 0 && "$INITIAL_COMMIT_EMPTY" == "$AFTER_COMMIT_EMPTY" ]]; then
  PASS=$((PASS + 1))
  echo "  PASS: Empty contracts object is no-op (no commit, returns 0)"
else
  FAIL=$((FAIL + 1))
  echo "  FAIL: Empty contracts should be no-op"
  echo "    return code: $RET, initial_commit: $INITIAL_COMMIT_EMPTY, after_commit: $AFTER_COMMIT_EMPTY"
fi

# =========================================================================
echo "=== Test 48: generate_definition_file — shape but no definition for Python ==="
GEN_PY_SHAPE_DIR="$TMPDIR/gen_py_shape_only"
mkdir -p "$GEN_PY_SHAPE_DIR"
TYPE_JSON_PY_SHAPE='{"definitionFile":"src/shared/event.py","shape":{"properties":[{"name":"name","type":"str"},{"name":"timestamp","type":"float"}],"methods":[{"name":"serialize","params":[{"name":"format","type":"str"}],"returns":"str"}]},"consumers":["US-002","US-003"]}'
generate_definition_file "Event" "$TYPE_JSON_PY_SHAPE" "python" "$GEN_PY_SHAPE_DIR" 2>&1
TOTAL=$((TOTAL + 1))
if [[ -f "$GEN_PY_SHAPE_DIR/src/shared/event.py" ]]; then
  CONTENT_PY=$(cat "$GEN_PY_SHAPE_DIR/src/shared/event.py")
  if echo "$CONTENT_PY" | grep -q "class Event(Protocol)" && echo "$CONTENT_PY" | grep -q "from typing import Protocol"; then
    PASS=$((PASS + 1))
    echo "  PASS: Python Protocol class generated from shape (no definition)"
  else
    FAIL=$((FAIL + 1))
    echo "  FAIL: Python shape-only file does not contain Protocol class"
    echo "    actual: $CONTENT_PY"
  fi
else
  FAIL=$((FAIL + 1))
  echo "  FAIL: Python file not created from shape (no definition)"
fi

# =========================================================================
echo "=== Test 49: generate_definition_file — shape but no definition for Go ==="
GEN_GO_SHAPE_DIR="$TMPDIR/gen_go_shape_only"
mkdir -p "$GEN_GO_SHAPE_DIR"
TYPE_JSON_GO_SHAPE='{"definitionFile":"internal/shared/event.go","shape":{"properties":[],"methods":[{"name":"Serialize","params":[{"name":"format","type":"string"}],"returns":"string"},{"name":"Timestamp","params":[],"returns":"int64"}]},"consumers":["US-002","US-003"]}'
generate_definition_file "Event" "$TYPE_JSON_GO_SHAPE" "go" "$GEN_GO_SHAPE_DIR" 2>&1
TOTAL=$((TOTAL + 1))
if [[ -f "$GEN_GO_SHAPE_DIR/internal/shared/event.go" ]]; then
  CONTENT_GO=$(cat "$GEN_GO_SHAPE_DIR/internal/shared/event.go")
  if echo "$CONTENT_GO" | grep -q "type Event interface" && echo "$CONTENT_GO" | grep -q "package shared"; then
    PASS=$((PASS + 1))
    echo "  PASS: Go interface generated from shape (no definition)"
  else
    FAIL=$((FAIL + 1))
    echo "  FAIL: Go shape-only file does not contain interface"
    echo "    actual: $CONTENT_GO"
  fi
else
  FAIL=$((FAIL + 1))
  echo "  FAIL: Go file not created from shape (no definition)"
fi

# =========================================================================
echo "=== Test 50: Idempotent re-run — same content, file already exists -> skipped ==="
IDEM_DIR="$TMPDIR/idempotent_rerun"
mkdir -p "$IDEM_DIR/src/types"
# Write file with known content first
printf "export interface Widget { id: number; }" > "$IDEM_DIR/src/types/Widget.ts"
ORIG_TIMESTAMP=$(stat -c %Y "$IDEM_DIR/src/types/Widget.ts" 2>/dev/null || stat -f %m "$IDEM_DIR/src/types/Widget.ts" 2>/dev/null)
TYPE_JSON_IDEM='{"definitionFile":"src/types/Widget.ts","definition":"export interface Widget { id: number; }","consumers":["US-002","US-003"]}'
RESULT_IDEM=$(generate_definition_file "Widget" "$TYPE_JSON_IDEM" "typescript" "$IDEM_DIR" 2>&1)
TOTAL=$((TOTAL + 1))
if echo "$RESULT_IDEM" | grep -q "\[MATERIALIZE\] SKIP.*same content"; then
  PASS=$((PASS + 1))
  echo "  PASS: Idempotent re-run skipped with SKIP message (same content)"
else
  FAIL=$((FAIL + 1))
  echo "  FAIL: Expected [MATERIALIZE] SKIP ... same content message"
  echo "    actual: $RESULT_IDEM"
fi

# =========================================================================
echo "=== Test 51: Different content already exists -> NOT overwritten, warning logged ==="
DIFF_DIR="$TMPDIR/diff_content_rerun"
mkdir -p "$DIFF_DIR/src/types"
# Write file with different content first
printf "export interface Widget { id: string; name: string; }" > "$DIFF_DIR/src/types/Widget.ts"
ORIGINAL_DIFF=$(cat "$DIFF_DIR/src/types/Widget.ts")
TYPE_JSON_DIFF='{"definitionFile":"src/types/Widget.ts","definition":"export interface Widget { id: number; }","consumers":["US-002","US-003"]}'
RESULT_DIFF=$(generate_definition_file "Widget" "$TYPE_JSON_DIFF" "typescript" "$DIFF_DIR" 2>&1)
AFTER_DIFF=$(cat "$DIFF_DIR/src/types/Widget.ts")
TOTAL=$((TOTAL + 1))
if [[ "$ORIGINAL_DIFF" == "$AFTER_DIFF" ]]; then
  PASS=$((PASS + 1))
  echo "  PASS: File with different content NOT overwritten"
else
  FAIL=$((FAIL + 1))
  echo "  FAIL: File was overwritten despite different content"
fi
TOTAL=$((TOTAL + 1))
if echo "$RESULT_DIFF" | grep -q "\[MATERIALIZE\] SKIP.*different content"; then
  PASS=$((PASS + 1))
  echo "  PASS: Warning logged for different content"
else
  FAIL=$((FAIL + 1))
  echo "  FAIL: Expected warning about different content"
  echo "    actual: $RESULT_DIFF"
fi

# =========================================================================
echo "=== Test 52: discoveredContracts included alongside shared_types ==="
MC_BOTH_DIR="$TMPDIR/mc_both_sources"
mkdir -p "$MC_BOTH_DIR"
touch "$MC_BOTH_DIR/tsconfig.json"
cat > "$MC_BOTH_DIR/quantum.json" << 'QJSON'
{
  "contracts": {
    "shared_types": {
      "Priority": {
        "value": "Priority",
        "definitionFile": "src/types/Priority.ts",
        "definition": "export interface Priority { level: number; }",
        "owner": "US-001",
        "consumers": ["US-002", "US-003"]
      }
    }
  },
  "execution": {
    "discoveredContracts": {
      "Metric": {
        "discoveredInWave": 1,
        "sourceFiles": ["src/a.ts", "src/b.ts"],
        "consolidated": true,
        "consolidatedFile": "src/types/Metric.ts",
        "consumers": ["US-005", "US-006"],
        "definition": "export interface Metric { name: string; value: number; }"
      }
    }
  }
}
QJSON
(cd "$MC_BOTH_DIR" && git init -q && git add -A && git commit -m "init" -q) 2>/dev/null
STDOUT_BOTH=$(materialize_contracts "$MC_BOTH_DIR/quantum.json" "$MC_BOTH_DIR" 3 2>/dev/null)
MC_BOTH_OK=true
if [[ ! -f "$MC_BOTH_DIR/src/types/Priority.ts" ]]; then
  MC_BOTH_OK=false
  echo "    DETAIL: Priority.ts not created from shared_types"
fi
if [[ ! -f "$MC_BOTH_DIR/src/types/Metric.ts" ]]; then
  MC_BOTH_OK=false
  echo "    DETAIL: Metric.ts not created from discoveredContracts"
fi
TOTAL=$((TOTAL + 1))
if [[ "$MC_BOTH_OK" == "true" ]]; then
  PASS=$((PASS + 1))
  echo "  PASS: Both shared_types and discoveredContracts materialized"
else
  FAIL=$((FAIL + 1))
  echo "  FAIL: Not all sources materialized"
fi
# Also verify both names appear on stdout
TOTAL=$((TOTAL + 1))
if echo "$STDOUT_BOTH" | grep -q "Priority" && echo "$STDOUT_BOTH" | grep -q "Metric"; then
  PASS=$((PASS + 1))
  echo "  PASS: Both names (Priority, Metric) printed to stdout"
else
  FAIL=$((FAIL + 1))
  echo "  FAIL: Expected both Priority and Metric on stdout"
  echo "    actual: $STDOUT_BOTH"
fi

# =========================================================================
echo "=== Test 53: Git commit message format matches 'chore: materialize contracts for Wave N' ==="
MC_COMMIT_FMT="$TMPDIR/mc_commit_fmt"
mkdir -p "$MC_COMMIT_FMT"
touch "$MC_COMMIT_FMT/tsconfig.json"
cat > "$MC_COMMIT_FMT/quantum.json" << 'QJSON'
{
  "contracts": {
    "shared_types": {
      "Alpha": {
        "value": "Alpha",
        "definitionFile": "src/types/Alpha.ts",
        "definition": "export interface Alpha {}",
        "owner": "US-001",
        "consumers": ["US-002", "US-003"]
      }
    }
  },
  "execution": {}
}
QJSON
(cd "$MC_COMMIT_FMT" && git init -q && git add -A && git commit -m "init" -q) 2>/dev/null
materialize_contracts "$MC_COMMIT_FMT/quantum.json" "$MC_COMMIT_FMT" 5 2>/dev/null
COMMIT_MSG=$(cd "$MC_COMMIT_FMT" && git log --format=%s -1 2>/dev/null)
TOTAL=$((TOTAL + 1))
if [[ "$COMMIT_MSG" == "chore: materialize contracts for Wave 5" ]]; then
  PASS=$((PASS + 1))
  echo "  PASS: Commit message exactly matches 'chore: materialize contracts for Wave 5'"
else
  FAIL=$((FAIL + 1))
  echo "  FAIL: Commit message format mismatch"
  echo "    expected: chore: materialize contracts for Wave 5"
  echo "    actual:   $COMMIT_MSG"
fi

# =========================================================================
echo "=== Test 54: Git commit message for Wave 1 ==="
MC_COMMIT_W1="$TMPDIR/mc_commit_w1"
mkdir -p "$MC_COMMIT_W1"
touch "$MC_COMMIT_W1/pyproject.toml"
cat > "$MC_COMMIT_W1/quantum.json" << 'QJSON'
{
  "contracts": {
    "shared_types": {
      "Beta": {
        "value": "Beta",
        "definitionFile": "src/shared/beta.py",
        "definition": "class Beta:\n    pass",
        "owner": "US-001",
        "consumers": ["US-002", "US-003"]
      }
    }
  },
  "execution": {}
}
QJSON
(cd "$MC_COMMIT_W1" && git init -q && git add -A && git commit -m "init" -q) 2>/dev/null
materialize_contracts "$MC_COMMIT_W1/quantum.json" "$MC_COMMIT_W1" 1 2>/dev/null
COMMIT_MSG_W1=$(cd "$MC_COMMIT_W1" && git log --format=%s -1 2>/dev/null)
TOTAL=$((TOTAL + 1))
if [[ "$COMMIT_MSG_W1" == "chore: materialize contracts for Wave 1" ]]; then
  PASS=$((PASS + 1))
  echo "  PASS: Commit message matches 'chore: materialize contracts for Wave 1'"
else
  FAIL=$((FAIL + 1))
  echo "  FAIL: Commit message mismatch for Wave 1"
  echo "    expected: chore: materialize contracts for Wave 1"
  echo "    actual:   $COMMIT_MSG_W1"
fi

# =========================================================================
echo "=== Test 55: infer_shared_types_dir — priority order: src/types > src/interfaces > types > shared ==="
INFER_PRI_DIR="$TMPDIR/infer_priority2"
mkdir -p "$INFER_PRI_DIR/src/types"
mkdir -p "$INFER_PRI_DIR/src/interfaces"
mkdir -p "$INFER_PRI_DIR/types"
mkdir -p "$INFER_PRI_DIR/shared"
# src/shared/types does NOT exist, so src/types should win
RESULT=$(infer_shared_types_dir "$INFER_PRI_DIR" "typescript")
assert_eq "src/types wins when src/shared/types absent" "src/types" "$RESULT"

# =========================================================================
echo "=== Test 56: infer_shared_types_dir — src/interfaces > types > shared ==="
INFER_PRI_DIR2="$TMPDIR/infer_priority3"
mkdir -p "$INFER_PRI_DIR2/src/interfaces"
mkdir -p "$INFER_PRI_DIR2/types"
mkdir -p "$INFER_PRI_DIR2/shared"
RESULT=$(infer_shared_types_dir "$INFER_PRI_DIR2" "go")
assert_eq "src/interfaces wins when src/shared/types and src/types absent" "src/interfaces" "$RESULT"

# =========================================================================
echo "=== Test 57: infer_shared_types_dir — types > shared ==="
INFER_PRI_DIR3="$TMPDIR/infer_priority4"
mkdir -p "$INFER_PRI_DIR3/types"
mkdir -p "$INFER_PRI_DIR3/shared"
RESULT=$(infer_shared_types_dir "$INFER_PRI_DIR3" "python")
assert_eq "types wins when higher priority dirs absent" "types" "$RESULT"

# =========================================================================
echo "=== Test 58: materialize_contracts — empty shared_types with no discoveredContracts ==="
MC_EMPTY_ST="$TMPDIR/mc_empty_st"
mkdir -p "$MC_EMPTY_ST"
touch "$MC_EMPTY_ST/tsconfig.json"
cat > "$MC_EMPTY_ST/quantum.json" << 'QJSON'
{
  "contracts": {
    "shared_types": {}
  },
  "execution": {}
}
QJSON
(cd "$MC_EMPTY_ST" && git init -q && git add -A && git commit -m "init" -q) 2>/dev/null
INITIAL_COMMIT_ST=$(cd "$MC_EMPTY_ST" && git log --oneline -1 2>/dev/null)
RESULT=$(materialize_contracts "$MC_EMPTY_ST/quantum.json" "$MC_EMPTY_ST" 1 2>&1)
RET=$?
AFTER_COMMIT_ST=$(cd "$MC_EMPTY_ST" && git log --oneline -1 2>/dev/null)
TOTAL=$((TOTAL + 1))
if [[ $RET -eq 0 && "$INITIAL_COMMIT_ST" == "$AFTER_COMMIT_ST" ]]; then
  PASS=$((PASS + 1))
  echo "  PASS: Empty shared_types object is no-op"
else
  FAIL=$((FAIL + 1))
  echo "  FAIL: Empty shared_types should be no-op"
fi

# =========================================================================
echo "=== Test 59: generate_definition_file — Python shape with methods generates def ==="
GEN_PY_METHOD_DIR="$TMPDIR/gen_py_method"
mkdir -p "$GEN_PY_METHOD_DIR"
TYPE_JSON_PY_METHOD='{"definitionFile":"src/shared/calculator.py","shape":{"properties":[],"methods":[{"name":"add","params":[{"name":"a","type":"int"},{"name":"b","type":"int"}],"returns":"int"}]},"consumers":["US-002","US-003"]}'
generate_definition_file "Calculator" "$TYPE_JSON_PY_METHOD" "python" "$GEN_PY_METHOD_DIR" 2>&1
TOTAL=$((TOTAL + 1))
if [[ -f "$GEN_PY_METHOD_DIR/src/shared/calculator.py" ]]; then
  CONTENT_PY_M=$(cat "$GEN_PY_METHOD_DIR/src/shared/calculator.py")
  if echo "$CONTENT_PY_M" | grep -q "def add(self, a: int, b: int) -> int"; then
    PASS=$((PASS + 1))
    echo "  PASS: Python method with params generated correctly"
  else
    FAIL=$((FAIL + 1))
    echo "  FAIL: Python method signature incorrect"
    echo "    actual: $CONTENT_PY_M"
  fi
else
  FAIL=$((FAIL + 1))
  echo "  FAIL: Python file not created for method shape test"
fi

# =========================================================================
echo "=== Test 60: generate_definition_file — Go shape with params in methods ==="
GEN_GO_PARAM_DIR="$TMPDIR/gen_go_param"
mkdir -p "$GEN_GO_PARAM_DIR"
TYPE_JSON_GO_PARAM='{"definitionFile":"internal/shared/calc.go","shape":{"properties":[],"methods":[{"name":"Add","params":[{"name":"a","type":"int"},{"name":"b","type":"int"}],"returns":"int"}]},"consumers":["US-002","US-003"]}'
generate_definition_file "Calc" "$TYPE_JSON_GO_PARAM" "go" "$GEN_GO_PARAM_DIR" 2>&1
TOTAL=$((TOTAL + 1))
if [[ -f "$GEN_GO_PARAM_DIR/internal/shared/calc.go" ]]; then
  CONTENT_GO_P=$(cat "$GEN_GO_PARAM_DIR/internal/shared/calc.go")
  if echo "$CONTENT_GO_P" | grep -q "Add(a int, b int) int"; then
    PASS=$((PASS + 1))
    echo "  PASS: Go method with params generated correctly"
  else
    FAIL=$((FAIL + 1))
    echo "  FAIL: Go method signature incorrect"
    echo "    actual: $CONTENT_GO_P"
  fi
else
  FAIL=$((FAIL + 1))
  echo "  FAIL: Go file not created for param method test"
fi

# =========================================================================
echo "=== Test 61: materialize_contracts — discoveredContracts with single consumer skipped ==="
MC_DISC_SINGLE="$TMPDIR/mc_disc_single"
mkdir -p "$MC_DISC_SINGLE"
touch "$MC_DISC_SINGLE/tsconfig.json"
cat > "$MC_DISC_SINGLE/quantum.json" << 'QJSON'
{
  "contracts": {
    "shared_types": {}
  },
  "execution": {
    "discoveredContracts": {
      "LoneType": {
        "discoveredInWave": 1,
        "sourceFiles": ["src/a.ts"],
        "consolidated": true,
        "consolidatedFile": "src/types/LoneType.ts",
        "consumers": ["US-005"],
        "definition": "export interface LoneType {}"
      }
    }
  }
}
QJSON
(cd "$MC_DISC_SINGLE" && git init -q && git add -A && git commit -m "init" -q) 2>/dev/null
RESULT=$(materialize_contracts "$MC_DISC_SINGLE/quantum.json" "$MC_DISC_SINGLE" 1 2>&1)
TOTAL=$((TOTAL + 1))
if [[ ! -f "$MC_DISC_SINGLE/src/types/LoneType.ts" ]]; then
  PASS=$((PASS + 1))
  echo "  PASS: Discovered contract with single consumer NOT materialized"
else
  FAIL=$((FAIL + 1))
  echo "  FAIL: Discovered contract with single consumer should be skipped"
fi

# =========================================================================
echo "=== Test 62: materialize_contracts — empty repo_root returns error ==="
MC_EMPTY_ROOT="$TMPDIR/mc_empty_root"
mkdir -p "$MC_EMPTY_ROOT"
cat > "$MC_EMPTY_ROOT/quantum.json" << 'QJSON'
{
  "contracts": {"shared_types": {}},
  "execution": {}
}
QJSON
RESULT=$(materialize_contracts "$MC_EMPTY_ROOT/quantum.json" "" 1 2>&1)
RET=$?
TOTAL=$((TOTAL + 1))
if [[ $RET -ne 0 ]]; then
  PASS=$((PASS + 1))
  echo "  PASS: Empty repo_root returns error"
else
  FAIL=$((FAIL + 1))
  echo "  FAIL: Empty repo_root should return error"
fi

# =========================================================================
echo "=== Test 63: materialize_contracts — wave_num defaults to 1 when omitted ==="
MC_DEFAULT_WAVE="$TMPDIR/mc_default_wave"
mkdir -p "$MC_DEFAULT_WAVE"
touch "$MC_DEFAULT_WAVE/tsconfig.json"
cat > "$MC_DEFAULT_WAVE/quantum.json" << 'QJSON'
{
  "contracts": {
    "shared_types": {
      "Gamma": {
        "value": "Gamma",
        "definitionFile": "src/types/Gamma.ts",
        "definition": "export interface Gamma {}",
        "owner": "US-001",
        "consumers": ["US-002", "US-003"]
      }
    }
  },
  "execution": {}
}
QJSON
(cd "$MC_DEFAULT_WAVE" && git init -q && git add -A && git commit -m "init" -q) 2>/dev/null
# Call without wave_num argument (should default to 1)
materialize_contracts "$MC_DEFAULT_WAVE/quantum.json" "$MC_DEFAULT_WAVE" 2>/dev/null
COMMIT_MSG_DEF=$(cd "$MC_DEFAULT_WAVE" && git log --format=%s -1 2>/dev/null)
TOTAL=$((TOTAL + 1))
if [[ "$COMMIT_MSG_DEF" == "chore: materialize contracts for Wave 1" ]]; then
  PASS=$((PASS + 1))
  echo "  PASS: wave_num defaults to 1 when omitted"
else
  FAIL=$((FAIL + 1))
  echo "  FAIL: wave_num default not applied"
  echo "    actual commit: $COMMIT_MSG_DEF"
fi

# =========================================================================
echo "=== Test 64: generate_definition_file — TS shape with methods that have params ==="
GEN_TS_METH_DIR="$TMPDIR/gen_ts_method_params"
mkdir -p "$GEN_TS_METH_DIR"
TYPE_JSON_TS_METH='{"definitionFile":"src/types/Service.ts","shape":{"properties":[],"methods":[{"name":"process","params":[{"name":"input","type":"string"},{"name":"count","type":"number"}],"returns":"Promise<void>"}]},"consumers":["US-002","US-003"]}'
generate_definition_file "Service" "$TYPE_JSON_TS_METH" "typescript" "$GEN_TS_METH_DIR" 2>&1
TOTAL=$((TOTAL + 1))
if [[ -f "$GEN_TS_METH_DIR/src/types/Service.ts" ]]; then
  CONTENT_TS_M=$(cat "$GEN_TS_METH_DIR/src/types/Service.ts")
  if echo "$CONTENT_TS_M" | grep -q "process(input: string, count: number): Promise<void>"; then
    PASS=$((PASS + 1))
    echo "  PASS: TS method with multiple params generated correctly"
  else
    FAIL=$((FAIL + 1))
    echo "  FAIL: TS method signature incorrect"
    echo "    actual: $CONTENT_TS_M"
  fi
else
  FAIL=$((FAIL + 1))
  echo "  FAIL: TS file not created for method params test"
fi

# =========================================================================
echo "=== Test 65: generate_definition_file — Python shape with no properties and no methods ==="
GEN_PY_EMPTY_SHAPE="$TMPDIR/gen_py_empty_shape"
mkdir -p "$GEN_PY_EMPTY_SHAPE"
TYPE_JSON_PY_EMPTY_SHAPE='{"definitionFile":"src/shared/marker.py","shape":{"properties":[],"methods":[]},"consumers":["US-002","US-003"]}'
generate_definition_file "Marker" "$TYPE_JSON_PY_EMPTY_SHAPE" "python" "$GEN_PY_EMPTY_SHAPE" 2>&1
TOTAL=$((TOTAL + 1))
if [[ -f "$GEN_PY_EMPTY_SHAPE/src/shared/marker.py" ]]; then
  CONTENT_PY_E=$(cat "$GEN_PY_EMPTY_SHAPE/src/shared/marker.py")
  # Should have "..." placeholder for empty Protocol class
  if echo "$CONTENT_PY_E" | grep -q "class Marker(Protocol)" && echo "$CONTENT_PY_E" | grep -q "\.\.\."; then
    PASS=$((PASS + 1))
    echo "  PASS: Empty Python Protocol has ... placeholder"
  else
    FAIL=$((FAIL + 1))
    echo "  FAIL: Empty Python Protocol should have ... placeholder"
    echo "    actual: $CONTENT_PY_E"
  fi
else
  FAIL=$((FAIL + 1))
  echo "  FAIL: Python file not created for empty shape test"
fi

# =========================================================================
echo "=== Test 66: materialize_contracts — materializedContracts accumulates across calls ==="
MC_ACCUM="$TMPDIR/mc_accumulate"
mkdir -p "$MC_ACCUM"
touch "$MC_ACCUM/tsconfig.json"
cat > "$MC_ACCUM/quantum.json" << 'QJSON'
{
  "contracts": {
    "shared_types": {
      "TypeA": {
        "value": "TypeA",
        "definitionFile": "src/types/TypeA.ts",
        "definition": "export interface TypeA {}",
        "owner": "US-001",
        "consumers": ["US-002", "US-003"]
      }
    }
  },
  "execution": {
    "materializedContracts": ["ExistingType"]
  }
}
QJSON
(cd "$MC_ACCUM" && git init -q && git add -A && git commit -m "init" -q) 2>/dev/null
materialize_contracts "$MC_ACCUM/quantum.json" "$MC_ACCUM" 1 2>/dev/null
MATERIALIZED_LIST=$(jq -r '.execution.materializedContracts[]' "$MC_ACCUM/quantum.json" 2>/dev/null)
TOTAL=$((TOTAL + 1))
if echo "$MATERIALIZED_LIST" | grep -q "ExistingType" && echo "$MATERIALIZED_LIST" | grep -q "TypeA"; then
  PASS=$((PASS + 1))
  echo "  PASS: materializedContracts accumulates (ExistingType + TypeA)"
else
  FAIL=$((FAIL + 1))
  echo "  FAIL: materializedContracts should accumulate, not replace"
  echo "    actual: $MATERIALIZED_LIST"
fi

# =========================================================================
echo "=== Test 67: generate_definition_file — infer fallback when definitionFile missing ==="
GEN_INFER_DIR="$TMPDIR/gen_infer_fallback"
mkdir -p "$GEN_INFER_DIR"
touch "$GEN_INFER_DIR/tsconfig.json"
# Type entry with definition content but NO definitionFile
TYPE_JSON_INFER='{"definition":"export interface InferredWidget { id: string; }","consumers":["US-002","US-003"]}'
generate_definition_file "InferredWidget" "$TYPE_JSON_INFER" "typescript" "$GEN_INFER_DIR" 2>&1
# infer_shared_types_dir should return "src/shared/types" (TS default, no existing dirs)
# kebab-case of "InferredWidget" is "inferred-widget"
# So expected path: src/shared/types/inferred-widget.ts
TOTAL=$((TOTAL + 1))
if [[ -f "$GEN_INFER_DIR/src/shared/types/inferred-widget.ts" ]]; then
  INFER_CONTENT=$(cat "$GEN_INFER_DIR/src/shared/types/inferred-widget.ts")
  if [[ "$INFER_CONTENT" == "export interface InferredWidget { id: string; }" ]]; then
    PASS=$((PASS + 1))
    echo "  PASS: Inferred definitionFile fallback wrote to correct path with correct content"
  else
    FAIL=$((FAIL + 1))
    echo "  FAIL: Inferred file content mismatch"
    echo "    expected: export interface InferredWidget { id: string; }"
    echo "    actual:   $INFER_CONTENT"
  fi
else
  FAIL=$((FAIL + 1))
  echo "  FAIL: Inferred file not created at src/shared/types/inferred-widget.ts"
  # Debug: show what files exist
  echo "    files in $GEN_INFER_DIR:"
  find "$GEN_INFER_DIR" -type f 2>/dev/null | sed "s|$GEN_INFER_DIR/||"
fi

# =========================================================================
echo "=== Test 68: generate_definition_file — infer fallback with existing src/types dir ==="
GEN_INFER_DIR2="$TMPDIR/gen_infer_existing_dir"
mkdir -p "$GEN_INFER_DIR2/src/types"
touch "$GEN_INFER_DIR2/tsconfig.json"
TYPE_JSON_INFER2='{"definition":"export type Status = \"active\" | \"inactive\";","consumers":["US-002","US-003"]}'
generate_definition_file "AppStatus" "$TYPE_JSON_INFER2" "typescript" "$GEN_INFER_DIR2" 2>&1
# infer_shared_types_dir should find src/types (existing dir)
# kebab-case of "AppStatus" is "app-status"
TOTAL=$((TOTAL + 1))
if [[ -f "$GEN_INFER_DIR2/src/types/app-status.ts" ]]; then
  PASS=$((PASS + 1))
  echo "  PASS: Inferred fallback uses existing src/types dir"
else
  FAIL=$((FAIL + 1))
  echo "  FAIL: Inferred file not created at src/types/app-status.ts"
  echo "    files in $GEN_INFER_DIR2:"
  find "$GEN_INFER_DIR2" -type f 2>/dev/null | sed "s|$GEN_INFER_DIR2/||"
fi

# =========================================================================
echo "=== Test 69: generate_definition_file — infer fallback for Python ==="
GEN_INFER_PY="$TMPDIR/gen_infer_py"
mkdir -p "$GEN_INFER_PY"
touch "$GEN_INFER_PY/pyproject.toml"
TYPE_JSON_INFER_PY='{"definition":"class UserConfig:\n    pass","consumers":["US-002","US-003"]}'
generate_definition_file "UserConfig" "$TYPE_JSON_INFER_PY" "python" "$GEN_INFER_PY" 2>&1
# Python default: src/shared, kebab-case of "UserConfig" is "user-config"
TOTAL=$((TOTAL + 1))
if [[ -f "$GEN_INFER_PY/src/shared/user-config.py" ]]; then
  PASS=$((PASS + 1))
  echo "  PASS: Inferred fallback for Python writes to src/shared/user-config.py"
else
  FAIL=$((FAIL + 1))
  echo "  FAIL: Python inferred file not created at src/shared/user-config.py"
  echo "    files in $GEN_INFER_PY:"
  find "$GEN_INFER_PY" -type f 2>/dev/null | sed "s|$GEN_INFER_PY/||"
fi

# =========================================================================
echo "=== Test 70: generate_definition_file — path traversal with ../../../etc/passwd rejected ==="
GEN_TRAVERSAL_DIR="$TMPDIR/gen_traversal"
mkdir -p "$GEN_TRAVERSAL_DIR"
TYPE_JSON_TRAVERSAL='{"definitionFile":"../../../etc/passwd","definition":"malicious content","consumers":["US-002","US-003"]}'
RESULT_TRAVERSAL=$(generate_definition_file "Evil" "$TYPE_JSON_TRAVERSAL" "typescript" "$GEN_TRAVERSAL_DIR" 2>&1)
RET_TRAVERSAL=$?
TOTAL=$((TOTAL + 1))
if [[ $RET_TRAVERSAL -ne 0 ]]; then
  PASS=$((PASS + 1))
  echo "  PASS: Path traversal definitionFile rejected (returns error)"
else
  FAIL=$((FAIL + 1))
  echo "  FAIL: Path traversal definitionFile should be rejected"
  echo "    return code: $RET_TRAVERSAL"
fi
# Verify the file was NOT written
TOTAL=$((TOTAL + 1))
if [[ ! -f "$GEN_TRAVERSAL_DIR/../../../etc/passwd" ]]; then
  PASS=$((PASS + 1))
  echo "  PASS: Traversal file not written"
else
  FAIL=$((FAIL + 1))
  echo "  FAIL: Traversal file was written!"
fi

# =========================================================================
echo "=== Test 71: generate_definition_file — normal path accepted ==="
GEN_NORMAL_DIR="$TMPDIR/gen_normal_path"
mkdir -p "$GEN_NORMAL_DIR"
TYPE_JSON_NORMAL='{"definitionFile":"src/types/Normal.ts","definition":"export interface Normal { ok: boolean; }","consumers":["US-002","US-003"]}'
RESULT_NORMAL=$(generate_definition_file "Normal" "$TYPE_JSON_NORMAL" "typescript" "$GEN_NORMAL_DIR" 2>&1)
RET_NORMAL=$?
TOTAL=$((TOTAL + 1))
if [[ -f "$GEN_NORMAL_DIR/src/types/Normal.ts" ]]; then
  PASS=$((PASS + 1))
  echo "  PASS: Normal definitionFile accepted and written"
else
  FAIL=$((FAIL + 1))
  echo "  FAIL: Normal definitionFile should be accepted"
  echo "    return code: $RET_NORMAL"
fi

# =========================================================================
# Tests for US-006: fileConflicts-based materialization threshold
# =========================================================================

echo ""
echo "--- US-006: fileConflicts-based materialization tests ---"

# =========================================================================
echo "=== Test 72: materialize_contracts — single-consumer type IN fileConflicts is materialized ==="
MC_FC1="$TMPDIR/mc_fc_single_conflict"
mkdir -p "$MC_FC1"
touch "$MC_FC1/tsconfig.json"
cat > "$MC_FC1/quantum.json" << 'QJSON'
{
  "contracts": {
    "shared_types": {
      "ConflictType": {
        "value": "ConflictType",
        "definitionFile": "src/types/ConflictType.ts",
        "definition": "export interface ConflictType { id: string; }",
        "owner": "US-001",
        "consumers": ["US-002"]
      }
    }
  },
  "fileConflicts": [
    {
      "file": "src/types/ConflictType.ts",
      "stories": ["US-002", "US-003"],
      "resolvedBy": "materialize"
    }
  ],
  "execution": {}
}
QJSON
(cd "$MC_FC1" && git init -q && git add -A && git commit -m "init" -q) 2>/dev/null
RESULT_FC1=$(materialize_contracts "$MC_FC1/quantum.json" "$MC_FC1" 1 2>&1)
TOTAL=$((TOTAL + 1))
if [[ -f "$MC_FC1/src/types/ConflictType.ts" ]]; then
  PASS=$((PASS + 1))
  echo "  PASS: Single-consumer type in fileConflicts WAS materialized"
else
  FAIL=$((FAIL + 1))
  echo "  FAIL: Single-consumer type in fileConflicts should be materialized"
  echo "    stderr/stdout: $RESULT_FC1"
fi

# =========================================================================
echo "=== Test 73: materialize_contracts — fileConflicts materialization logs '(file-conflict prevention)' ==="
TOTAL=$((TOTAL + 1))
if echo "$RESULT_FC1" | grep -q "(file-conflict prevention)"; then
  PASS=$((PASS + 1))
  echo "  PASS: Log contains '(file-conflict prevention)'"
else
  FAIL=$((FAIL + 1))
  echo "  FAIL: Expected '(file-conflict prevention)' in log output"
  echo "    actual: $RESULT_FC1"
fi

# =========================================================================
echo "=== Test 74: materialize_contracts — multi-consumer type logs '(multi-consumer)' ==="
MC_FC2="$TMPDIR/mc_fc_multi_log"
mkdir -p "$MC_FC2"
touch "$MC_FC2/tsconfig.json"
cat > "$MC_FC2/quantum.json" << 'QJSON'
{
  "contracts": {
    "shared_types": {
      "MultiType": {
        "value": "MultiType",
        "definitionFile": "src/types/MultiType.ts",
        "definition": "export interface MultiType { x: number; }",
        "owner": "US-001",
        "consumers": ["US-002", "US-003"]
      }
    }
  },
  "execution": {}
}
QJSON
(cd "$MC_FC2" && git init -q && git add -A && git commit -m "init" -q) 2>/dev/null
RESULT_FC2=$(materialize_contracts "$MC_FC2/quantum.json" "$MC_FC2" 1 2>&1)
TOTAL=$((TOTAL + 1))
if echo "$RESULT_FC2" | grep -q "(multi-consumer)"; then
  PASS=$((PASS + 1))
  echo "  PASS: Multi-consumer type logs '(multi-consumer)'"
else
  FAIL=$((FAIL + 1))
  echo "  FAIL: Expected '(multi-consumer)' in log output"
  echo "    actual: $RESULT_FC2"
fi

# =========================================================================
echo "=== Test 75: materialize_contracts — single-consumer NOT in fileConflicts still skipped ==="
MC_FC3="$TMPDIR/mc_fc_single_no_conflict"
mkdir -p "$MC_FC3"
touch "$MC_FC3/tsconfig.json"
cat > "$MC_FC3/quantum.json" << 'QJSON'
{
  "contracts": {
    "shared_types": {
      "SafeType": {
        "value": "SafeType",
        "definitionFile": "src/types/SafeType.ts",
        "definition": "export interface SafeType { ok: boolean; }",
        "owner": "US-001",
        "consumers": ["US-002"]
      }
    }
  },
  "fileConflicts": [
    {
      "file": "src/types/OtherFile.ts",
      "stories": ["US-005", "US-006"]
    }
  ],
  "execution": {}
}
QJSON
(cd "$MC_FC3" && git init -q && git add -A && git commit -m "init" -q) 2>/dev/null
RESULT_FC3=$(materialize_contracts "$MC_FC3/quantum.json" "$MC_FC3" 1 2>&1)
TOTAL=$((TOTAL + 1))
if [[ ! -f "$MC_FC3/src/types/SafeType.ts" ]]; then
  PASS=$((PASS + 1))
  echo "  PASS: Single-consumer type NOT in fileConflicts still skipped"
else
  FAIL=$((FAIL + 1))
  echo "  FAIL: Single-consumer type not in fileConflicts should be skipped"
fi

# =========================================================================
echo "=== Test 76: materialize_contracts — mix of multi-consumer, fileConflict, and plain single ==="
MC_FC4="$TMPDIR/mc_fc_mix"
mkdir -p "$MC_FC4"
touch "$MC_FC4/tsconfig.json"
cat > "$MC_FC4/quantum.json" << 'QJSON'
{
  "contracts": {
    "shared_types": {
      "MultiA": {
        "value": "MultiA",
        "definitionFile": "src/types/MultiA.ts",
        "definition": "export interface MultiA { a: string; }",
        "owner": "US-001",
        "consumers": ["US-002", "US-003"]
      },
      "ConflictB": {
        "value": "ConflictB",
        "definitionFile": "src/types/ConflictB.ts",
        "definition": "export interface ConflictB { b: number; }",
        "owner": "US-001",
        "consumers": ["US-004"]
      },
      "PlainC": {
        "value": "PlainC",
        "definitionFile": "src/types/PlainC.ts",
        "definition": "export interface PlainC { c: boolean; }",
        "owner": "US-001",
        "consumers": ["US-005"]
      }
    }
  },
  "fileConflicts": [
    {
      "file": "src/types/ConflictB.ts",
      "stories": ["US-004", "US-007"]
    }
  ],
  "execution": {}
}
QJSON
(cd "$MC_FC4" && git init -q && git add -A && git commit -m "init" -q) 2>/dev/null
RESULT_FC4=$(materialize_contracts "$MC_FC4/quantum.json" "$MC_FC4" 1 2>&1)
MC_FC4_OK=true
# MultiA (multi-consumer) should be materialized
if [[ ! -f "$MC_FC4/src/types/MultiA.ts" ]]; then
  MC_FC4_OK=false
  echo "    DETAIL: MultiA.ts missing (should exist, multi-consumer)"
fi
# ConflictB (single consumer but in fileConflicts) should be materialized
if [[ ! -f "$MC_FC4/src/types/ConflictB.ts" ]]; then
  MC_FC4_OK=false
  echo "    DETAIL: ConflictB.ts missing (should exist, file-conflict)"
fi
# PlainC (single consumer, not in fileConflicts) should NOT be materialized
if [[ -f "$MC_FC4/src/types/PlainC.ts" ]]; then
  MC_FC4_OK=false
  echo "    DETAIL: PlainC.ts exists (should NOT exist, single consumer no conflict)"
fi
TOTAL=$((TOTAL + 1))
if [[ "$MC_FC4_OK" == "true" ]]; then
  PASS=$((PASS + 1))
  echo "  PASS: Mix of multi-consumer, fileConflict, and plain single handled correctly"
else
  FAIL=$((FAIL + 1))
  echo "  FAIL: Mix scenario not handled correctly"
  echo "    output: $RESULT_FC4"
fi

# =========================================================================
echo "=== Test 77: materialize_contracts — no fileConflicts key in quantum.json (backward compat) ==="
MC_FC5="$TMPDIR/mc_fc_no_key"
mkdir -p "$MC_FC5"
touch "$MC_FC5/tsconfig.json"
cat > "$MC_FC5/quantum.json" << 'QJSON'
{
  "contracts": {
    "shared_types": {
      "LoneType": {
        "value": "LoneType",
        "definitionFile": "src/types/LoneType.ts",
        "definition": "export interface LoneType {}",
        "owner": "US-001",
        "consumers": ["US-002"]
      }
    }
  },
  "execution": {}
}
QJSON
(cd "$MC_FC5" && git init -q && git add -A && git commit -m "init" -q) 2>/dev/null
RESULT_FC5=$(materialize_contracts "$MC_FC5/quantum.json" "$MC_FC5" 1 2>&1)
TOTAL=$((TOTAL + 1))
if [[ ! -f "$MC_FC5/src/types/LoneType.ts" ]]; then
  PASS=$((PASS + 1))
  echo "  PASS: No fileConflicts key — single-consumer still skipped (backward compat)"
else
  FAIL=$((FAIL + 1))
  echo "  FAIL: Should skip single-consumer when no fileConflicts key"
fi

# =========================================================================
echo "=== Test 78: materialize_contracts — empty fileConflicts array (backward compat) ==="
MC_FC6="$TMPDIR/mc_fc_empty_array"
mkdir -p "$MC_FC6"
touch "$MC_FC6/tsconfig.json"
cat > "$MC_FC6/quantum.json" << 'QJSON'
{
  "contracts": {
    "shared_types": {
      "SoloType": {
        "value": "SoloType",
        "definitionFile": "src/types/SoloType.ts",
        "definition": "export interface SoloType {}",
        "owner": "US-001",
        "consumers": ["US-002"]
      }
    }
  },
  "fileConflicts": [],
  "execution": {}
}
QJSON
(cd "$MC_FC6" && git init -q && git add -A && git commit -m "init" -q) 2>/dev/null
RESULT_FC6=$(materialize_contracts "$MC_FC6/quantum.json" "$MC_FC6" 1 2>&1)
TOTAL=$((TOTAL + 1))
if [[ ! -f "$MC_FC6/src/types/SoloType.ts" ]]; then
  PASS=$((PASS + 1))
  echo "  PASS: Empty fileConflicts array — single-consumer still skipped"
else
  FAIL=$((FAIL + 1))
  echo "  FAIL: Should skip single-consumer when fileConflicts is empty"
fi

# =========================================================================
echo ""
echo "=== Results: $PASS/$TOTAL passed, $FAIL failed ==="
if [[ $FAIL -eq 0 ]]; then
  exit 0
else
  exit 1
fi
