#!/usr/bin/env bash
# Test suite for lib/merge-strategy.sh
# Tests classify_conflict for all rule categories, rule ordering,
# classify_and_merge for clean merge, all-resolved, escalation, and fallback.

# shellcheck disable=SC1091,SC2034,SC2329  # SC1091: source paths at runtime; SC2034: vars used by sourced lib; SC2329: functions called via trap

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="$SCRIPT_DIR/../lib"
PASS=0
FAIL=0
TOTAL=0

# Source the library under test
if [[ ! -f "$LIB_DIR/merge-strategy.sh" ]]; then
  echo "SKIP: lib/merge-strategy.sh not found (RED phase)"
  exit 1
fi
source "$LIB_DIR/merge-strategy.sh"

# Disable optional module side-effects during testing
DEP_MANIFEST_AVAILABLE=false
BARREL_REGEN_AVAILABLE=false

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

# =========================================================================
# Setup: create temporary directories and mock context files
# =========================================================================
TMPDIR=$(mktemp -d)
ORIG_DIR=$(pwd)

cleanup() {
  cd "$ORIG_DIR" || true
  rm -rf "$TMPDIR"
}
trap cleanup EXIT

# Helper: create a mock context file with the default 5 rules
# Rules use actual glob patterns from the PRD:
#   dependency_manifest: package.json|package-lock.json|Cargo.toml|...
#   barrel_export: **/index.ts|**/index.js|**/__init__.py|**/mod.rs
#   new_story_file: condition file_not_on_ours
#   shared_infrastructure: condition file_merged_in_earlier_wave
#   contract_stub: condition file_in_materializedContracts
create_default_context() {
  local ctx_file="$1"
  local files_changed="${2:-}"
  local materialized="${3:-}"
  cat > "$ctx_file" << CTXEOF
defaultAction=escalate
materializedContracts=${materialized}
filesChanged=${files_changed}
rules=[{"name":"dependency_manifest","filePattern":"package.json|package-lock.json|Cargo.toml|Cargo.lock|pyproject.toml|poetry.lock|go.mod|go.sum|requirements*.txt","strategy":"ours","postAction":"install"},{"name":"barrel_export","filePattern":"**/index.ts|**/index.js|**/__init__.py|**/mod.rs","strategy":"regenerate"},{"name":"new_story_file","condition":"file_not_on_ours","strategy":"theirs"},{"name":"shared_infrastructure","condition":"file_merged_in_earlier_wave","strategy":"ours"},{"name":"contract_stub","condition":"file_in_materializedContracts","strategy":"theirs"}]
CTXEOF
}

# =========================================================================
# T-036: Test classify_conflict for all rule categories
# =========================================================================

echo "=== T-036: Test classify_conflict for all rule categories ==="

# --- Test 1: dependency_manifest pattern match (package.json) ---
echo "--- Test 1: dependency_manifest pattern match ---"
CTX1="$TMPDIR/ctx1.txt"
create_default_context "$CTX1"
RESULT=$(classify_conflict "package.json" "$CTX1" 2>/dev/null)
assert_eq "package.json -> dependency_manifest:ours:install" "dependency_manifest:ours:install" "$RESULT"

# --- Test 2: dependency_manifest with other manifest files ---
echo "--- Test 2: dependency_manifest pattern (package-lock.json) ---"
RESULT=$(classify_conflict "package-lock.json" "$CTX1" 2>/dev/null)
assert_eq "package-lock.json -> dependency_manifest:ours:install" "dependency_manifest:ours:install" "$RESULT"

# --- Test 3: dependency_manifest (Cargo.toml) ---
echo "--- Test 3: dependency_manifest pattern (Cargo.toml) ---"
RESULT=$(classify_conflict "Cargo.toml" "$CTX1" 2>/dev/null)
assert_eq "Cargo.toml -> dependency_manifest:ours:install" "dependency_manifest:ours:install" "$RESULT"

# --- Test 4: dependency_manifest (pyproject.toml) ---
echo "--- Test 4: dependency_manifest pattern (pyproject.toml) ---"
RESULT=$(classify_conflict "pyproject.toml" "$CTX1" 2>/dev/null)
assert_eq "pyproject.toml -> dependency_manifest:ours:install" "dependency_manifest:ours:install" "$RESULT"

# --- Test 5: dependency_manifest (go.mod) ---
echo "--- Test 5: dependency_manifest pattern (go.mod) ---"
RESULT=$(classify_conflict "go.mod" "$CTX1" 2>/dev/null)
assert_eq "go.mod -> dependency_manifest:ours:install" "dependency_manifest:ours:install" "$RESULT"

# --- Test 6: barrel_export pattern match (index.ts in subdir) ---
echo "--- Test 6: barrel_export pattern match ---"
RESULT=$(classify_conflict "src/parsers/index.ts" "$CTX1" 2>/dev/null)
assert_eq "src/parsers/index.ts -> barrel_export:regenerate:" "barrel_export:regenerate:" "$RESULT"

# --- Test 7: barrel_export (__init__.py) ---
echo "--- Test 7: barrel_export pattern (__init__.py) ---"
RESULT=$(classify_conflict "src/models/__init__.py" "$CTX1" 2>/dev/null)
assert_eq "src/models/__init__.py -> barrel_export:regenerate:" "barrel_export:regenerate:" "$RESULT"

# --- Test 8: barrel_export (mod.rs) ---
echo "--- Test 8: barrel_export pattern (mod.rs) ---"
RESULT=$(classify_conflict "src/handlers/mod.rs" "$CTX1" 2>/dev/null)
assert_eq "src/handlers/mod.rs -> barrel_export:regenerate:" "barrel_export:regenerate:" "$RESULT"

# --- Test 9: barrel_export (index.js) ---
echo "--- Test 9: barrel_export pattern (index.js) ---"
RESULT=$(classify_conflict "lib/utils/index.js" "$CTX1" 2>/dev/null)
assert_eq "lib/utils/index.js -> barrel_export:regenerate:" "barrel_export:regenerate:" "$RESULT"

# --- Test 10: new_story_file (file_not_on_ours condition) ---
echo "--- Test 10: new_story_file (file not on HEAD) ---"
RESULT=$(classify_conflict "src/brand-new-feature/handler.ts" "$CTX1" 2>/dev/null)
assert_eq "new file not on HEAD -> new_story_file:theirs:" "new_story_file:theirs:" "$RESULT"

# --- Test 11: shared_infrastructure (file_merged_in_earlier_wave) ---
echo "--- Test 11: shared_infrastructure (file in filesChanged) ---"
CTX11="$TMPDIR/ctx11.txt"
create_default_context "$CTX11" "lib/common.sh"
RESULT=$(classify_conflict "lib/common.sh" "$CTX11" 2>/dev/null)
assert_eq "file in filesChanged (on HEAD) -> shared_infrastructure:ours:" "shared_infrastructure:ours:" "$RESULT"

# --- Test 12: contract_stub (file_in_materializedContracts) ---
echo "--- Test 12: contract_stub (file in materializedContracts) ---"
CTX12="$TMPDIR/ctx12.txt"
create_default_context "$CTX12" "" "lib/common.sh"
RESULT=$(classify_conflict "lib/common.sh" "$CTX12" 2>/dev/null)
assert_eq "file in materializedContracts -> contract_stub:theirs:" "contract_stub:theirs:" "$RESULT"

# --- Test 13: no match -> unknown:escalate: ---
echo "--- Test 13: no match -> escalate ---"
CTX13="$TMPDIR/ctx13.txt"
create_default_context "$CTX13"
RESULT=$(classify_conflict "lib/common.sh" "$CTX13" 2>/dev/null)
assert_eq "no match -> unknown:escalate:" "unknown:escalate:" "$RESULT"

# --- Test 14: rule ordering - first match wins ---
echo "--- Test 14: rule ordering - first match wins ---"
CTX14="$TMPDIR/ctx14.txt"
create_default_context "$CTX14"
RESULT=$(classify_conflict "package.json" "$CTX14" 2>/dev/null)
assert_eq "first match wins: package.json -> dependency_manifest (not new_story_file)" "dependency_manifest:ours:install" "$RESULT"

# --- Test 15: rule ordering with reordered rules ---
echo "--- Test 15: rule ordering with reordered rules ---"
CTX15="$TMPDIR/ctx15.txt"
cat > "$CTX15" << 'EOF'
defaultAction=escalate
materializedContracts=
filesChanged=
rules=[{"name":"barrel_export","filePattern":"**/index.ts","strategy":"regenerate"},{"name":"dependency_manifest","filePattern":"**/index.ts","strategy":"ours","postAction":"install"}]
EOF
RESULT=$(classify_conflict "src/index.ts" "$CTX15" 2>/dev/null)
assert_eq "first rule wins when both match" "barrel_export:regenerate:" "$RESULT"

# --- Test 16: empty rules -> falls back to defaultAction ---
echo "--- Test 16: empty rules -> defaultAction ---"
CTX16="$TMPDIR/ctx16.txt"
cat > "$CTX16" << 'EOF'
defaultAction=escalate
materializedContracts=
filesChanged=
rules=[]
EOF
RESULT=$(classify_conflict "anything.txt" "$CTX16" 2>/dev/null)
assert_eq "empty rules -> unknown:escalate:" "unknown:escalate:" "$RESULT"

# --- Test 17: custom defaultAction ---
echo "--- Test 17: custom defaultAction ---"
CTX17="$TMPDIR/ctx17.txt"
cat > "$CTX17" << 'EOF'
defaultAction=ours
materializedContracts=
filesChanged=
rules=[]
EOF
RESULT=$(classify_conflict "anything.txt" "$CTX17" 2>/dev/null)
assert_eq "custom defaultAction -> unknown:ours:" "unknown:ours:" "$RESULT"

# --- Test 18: basename matching for package.json ---
echo "--- Test 18: basename matching for package.json ---"
RESULT=$(classify_conflict "package.json" "$CTX1" 2>/dev/null)
assert_eq "basename package.json matches" "dependency_manifest:ours:install" "$RESULT"

# --- Test 19: condition with pattern both set - pattern takes priority ---
echo "--- Test 19: pattern + condition - pattern checked first ---"
CTX19="$TMPDIR/ctx19.txt"
cat > "$CTX19" << 'EOF'
defaultAction=escalate
materializedContracts=
filesChanged=
rules=[{"name":"mixed_rule","filePattern":"*.json","condition":"file_not_on_ours","strategy":"ours"}]
EOF
RESULT=$(classify_conflict "package.json" "$CTX19" 2>/dev/null)
assert_eq "pattern matches before condition checked" "mixed_rule:ours:" "$RESULT"

# --- Test 20: multiple files in filesChanged (pipe-delimited) ---
echo "--- Test 20: multiple files in filesChanged ---"
CTX20="$TMPDIR/ctx20.txt"
create_default_context "$CTX20" "lib/common.sh|README.md|quantum-loop.sh"
RESULT=$(classify_conflict "README.md" "$CTX20" 2>/dev/null)
assert_eq "README.md in multi-file filesChanged -> shared_infrastructure:ours:" "shared_infrastructure:ours:" "$RESULT"

# --- Test 21: multiple files in materializedContracts ---
echo "--- Test 21: multiple files in materializedContracts ---"
CTX21="$TMPDIR/ctx21.txt"
create_default_context "$CTX21" "" "types/shared.ts|README.md|lib/common.sh"
RESULT=$(classify_conflict "README.md" "$CTX21" 2>/dev/null)
assert_eq "README.md in materializedContracts -> contract_stub:theirs:" "contract_stub:theirs:" "$RESULT"

# --- Test 22: classify_conflict with missing file_path ---
echo "--- Test 22: classify_conflict error on empty file_path ---"
classify_conflict "" "$CTX1" >/dev/null 2>&1
EXIT_CODE=$?
assert_eq "empty file_path returns error" "1" "$EXIT_CODE"

# --- Test 23: classify_conflict with missing context_file ---
echo "--- Test 23: classify_conflict error on empty context_file ---"
classify_conflict "somefile.txt" "" >/dev/null 2>&1
EXIT_CODE=$?
assert_eq "empty context_file returns error" "1" "$EXIT_CODE"

# --- Test 24: classify_conflict with nonexistent context_file ---
echo "--- Test 24: classify_conflict error on nonexistent context_file ---"
classify_conflict "somefile.txt" "/tmp/nonexistent_ctx_12345.txt" >/dev/null 2>&1
EXIT_CODE=$?
assert_eq "nonexistent context_file returns error" "1" "$EXIT_CODE"

echo ""
echo "=== T-036 Results: $PASS/$TOTAL passed, $FAIL failed ==="
echo ""

# =========================================================================
# T-037: Test classify_and_merge with git scenarios
# =========================================================================

echo "=== T-037: Test classify_and_merge with git scenarios ==="

# Helper: set up a temp git repo for merge testing
setup_merge_repo() {
  local repo_dir="$1"
  mkdir -p "$repo_dir"
  cd "$repo_dir" || return 1
  git init --initial-branch=main . >/dev/null 2>&1
  git config user.email "test@test.com"
  git config user.name "Test"

  # Create initial files on main
  echo "initial content" > file.txt
  echo '{"name": "test", "version": "1.0.0"}' > package.json
  echo "shared infra content" > config.json
  git add -A >/dev/null 2>&1
  git commit -m "initial commit" >/dev/null 2>&1
}

# Helper: create quantum.json with mergeStrategy in a repo dir
# Uses only ours/theirs strategies (no regenerate) to avoid barrel-regen dependency
create_test_quantum_json() {
  local repo_dir="$1"
  local extra_files_changed="${2:-}"
  local extra_materialized="${3:-}"
  local py_repo_dir="$repo_dir"
  if command -v cygpath &>/dev/null; then
    py_repo_dir=$(cygpath -m "$repo_dir")
  fi
  python -c "
import json
d = {
  'project': 'test',
  'execution': {
    'mergeStrategy': {
      'rules': [
        {'name': 'dependency_manifest', 'filePattern': 'package.json|package-lock.json', 'strategy': 'ours'},
        {'name': 'new_story_file', 'condition': 'file_not_on_ours', 'strategy': 'theirs'},
        {'name': 'shared_infrastructure', 'condition': 'file_merged_in_earlier_wave', 'strategy': 'ours'},
        {'name': 'contract_stub', 'condition': 'file_in_materializedContracts', 'strategy': 'theirs'}
      ],
      'defaultAction': 'escalate'
    },
    'materializedContracts': [c for c in '${extra_materialized}'.split('|') if c]
  },
  'progress': [
    {'filesChanged': [c for c in '${extra_files_changed}'.split('|') if c]}
  ] if '${extra_files_changed}' else []
}
with open('${py_repo_dir}/quantum.json', 'w') as f:
  json.dump(d, f, indent=2)
"
}

# Helper: create quantum.json WITHOUT mergeStrategy (fallback test)
create_test_quantum_json_no_strategy() {
  local repo_dir="$1"
  local py_repo_dir="$repo_dir"
  if command -v cygpath &>/dev/null; then
    py_repo_dir=$(cygpath -m "$repo_dir")
  fi
  python -c "
import json
d = {
  'project': 'test',
  'execution': {},
  'progress': []
}
with open('${py_repo_dir}/quantum.json', 'w') as f:
  json.dump(d, f, indent=2)
"
}

# --- Test 25: Clean merge (no conflicts) ---
echo "--- Test 25: Clean merge - no conflicts ---"
REPO25="$TMPDIR/repo25"
setup_merge_repo "$REPO25"
cd "$REPO25" || exit 1

git checkout -b feature-clean >/dev/null 2>&1
echo "new feature file" > feature.txt
git add feature.txt >/dev/null 2>&1
git commit -m "add feature file" >/dev/null 2>&1

git checkout main >/dev/null 2>&1
create_test_quantum_json "$REPO25"

OUTPUT=$(classify_and_merge "feature-clean" "$REPO25" "$REPO25/quantum.json" 2>&1)
EXIT_CODE=$?
assert_eq "clean merge returns 0" "0" "$EXIT_CODE"

COMMIT_COUNT=$(git log --oneline | wc -l | tr -d ' ')
TOTAL=$((TOTAL + 1))
if [[ "$COMMIT_COUNT" -ge 3 ]]; then
  echo "  PASS: merge commit created (commit count: $COMMIT_COUNT)"
  PASS=$((PASS + 1))
else
  echo "  FAIL: merge commit not created (commit count: $COMMIT_COUNT)"
  FAIL=$((FAIL + 1))
fi

assert_contains "clean merge logs timing" "Merge completed in" "$OUTPUT"

# --- Test 26: All-resolved merge (ours for package.json and config.json) ---
echo "--- Test 26: All-resolved merge with ours strategy ---"
REPO26="$TMPDIR/repo26"
setup_merge_repo "$REPO26"
cd "$REPO26" || exit 1

# Feature branch: modify package.json and config.json
git checkout -b feature-resolved >/dev/null 2>&1
echo '{"name": "test", "version": "2.0.0"}' > package.json
echo "feature config" > config.json
git add -A >/dev/null 2>&1
git commit -m "feature changes" >/dev/null 2>&1

# Main: make conflicting changes to same files
git checkout main >/dev/null 2>&1
echo '{"name": "test", "version": "1.1.0"}' > package.json
echo "main config" > config.json
git add -A >/dev/null 2>&1
git commit -m "main changes" >/dev/null 2>&1

# Create quantum.json with config.json in filesChanged (shared_infrastructure -> ours)
create_test_quantum_json "$REPO26" "config.json"

OUTPUT=$(classify_and_merge "feature-resolved" "$REPO26" "$REPO26/quantum.json" 2>&1)
EXIT_CODE=$?
assert_eq "all-resolved merge returns 0" "0" "$EXIT_CODE"
assert_contains "merge log mentions MERGE-STRATEGY" "MERGE-STRATEGY" "$OUTPUT"

# Verify package.json has main's version (ours strategy)
if [[ -f "$REPO26/package.json" ]]; then
  PKG_CONTENT=$(cat "$REPO26/package.json")
  assert_contains "package.json kept ours version" "1.1.0" "$PKG_CONTENT"
fi

# Verify config.json has main's version (shared_infrastructure -> ours)
if [[ -f "$REPO26/config.json" ]]; then
  CFG_CONTENT=$(cat "$REPO26/config.json")
  assert_contains "config.json kept ours version" "main config" "$CFG_CONTENT"
fi

# --- Test 27: Escalation - unknown file conflict aborts merge ---
echo "--- Test 27: Escalation on unknown file conflict ---"
REPO27="$TMPDIR/repo27"
setup_merge_repo "$REPO27"
cd "$REPO27" || exit 1

# Feature branch: modify file.txt (not matching any rule)
git checkout -b feature-unknown >/dev/null 2>&1
echo "feature version of file" > file.txt
git add -A >/dev/null 2>&1
git commit -m "feature file change" >/dev/null 2>&1

# Main: conflicting change to file.txt
git checkout main >/dev/null 2>&1
echo "main version of file" > file.txt
git add -A >/dev/null 2>&1
git commit -m "main file change" >/dev/null 2>&1

# Create quantum.json (file.txt matches no pattern, no condition)
create_test_quantum_json "$REPO27"

OUTPUT=$(classify_and_merge "feature-unknown" "$REPO27" "$REPO27/quantum.json" 2>&1)
EXIT_CODE=$?
assert_eq "escalation returns 1" "1" "$EXIT_CODE"
assert_contains "CONFLICT line in output" "CONFLICT:" "$OUTPUT"
assert_contains "CONFLICT mentions file.txt" "file.txt" "$OUTPUT"

# Verify merge was aborted (main's content preserved)
CURRENT_CONTENT=$(cat "$REPO27/file.txt")
assert_eq "merge aborted - main content preserved" "main version of file" "$CURRENT_CONTENT"

# --- Test 28: Fallback when mergeStrategy absent from quantum.json ---
echo "--- Test 28: Fallback - no mergeStrategy -> all escalate ---"
REPO28="$TMPDIR/repo28"
setup_merge_repo "$REPO28"
cd "$REPO28" || exit 1

# Feature branch: modify package.json (would normally match dependency_manifest)
git checkout -b feature-fallback >/dev/null 2>&1
echo '{"name": "test", "version": "3.0.0"}' > package.json
git add -A >/dev/null 2>&1
git commit -m "feature package change" >/dev/null 2>&1

# Main: conflicting change
git checkout main >/dev/null 2>&1
echo '{"name": "test", "version": "1.2.0"}' > package.json
git add -A >/dev/null 2>&1
git commit -m "main package change" >/dev/null 2>&1

# Create quantum.json WITHOUT mergeStrategy
create_test_quantum_json_no_strategy "$REPO28"

OUTPUT=$(classify_and_merge "feature-fallback" "$REPO28" "$REPO28/quantum.json" 2>&1)
EXIT_CODE=$?
assert_eq "no mergeStrategy -> escalation returns 1" "1" "$EXIT_CODE"
assert_contains "fallback escalates with CONFLICT" "CONFLICT:" "$OUTPUT"

# --- Test 29: classify_and_merge error handling for missing arguments ---
echo "--- Test 29: Error handling for missing arguments ---"
classify_and_merge "" "$REPO28" "$REPO28/quantum.json" >/dev/null 2>&1
assert_eq "missing branch returns 1" "1" "$?"

classify_and_merge "some-branch" "" "$REPO28/quantum.json" >/dev/null 2>&1
assert_eq "missing repo_root returns 1" "1" "$?"

classify_and_merge "some-branch" "$REPO28" "" >/dev/null 2>&1
assert_eq "missing json_path returns 1" "1" "$?"

# --- Test 30: Mixed conflicts - some resolved, one escalates ---
echo "--- Test 30: Mixed - some resolved, one escalates ---"
REPO30="$TMPDIR/repo30"
setup_merge_repo "$REPO30"
cd "$REPO30" || exit 1

# Feature branch: modify package.json and file.txt
git checkout -b feature-mixed >/dev/null 2>&1
echo '{"name": "test", "version": "4.0.0"}' > package.json
echo "feature txt" > file.txt
git add -A >/dev/null 2>&1
git commit -m "feature mixed changes" >/dev/null 2>&1

# Main: conflicting changes to both
git checkout main >/dev/null 2>&1
echo '{"name": "test", "version": "1.3.0"}' > package.json
echo "main txt" > file.txt
git add -A >/dev/null 2>&1
git commit -m "main mixed changes" >/dev/null 2>&1

# package.json -> dependency_manifest:ours (resolved)
# file.txt -> unknown:escalate (escalation!)
create_test_quantum_json "$REPO30"

OUTPUT=$(classify_and_merge "feature-mixed" "$REPO30" "$REPO30/quantum.json" 2>&1)
EXIT_CODE=$?
assert_eq "mixed conflicts with escalation returns 1" "1" "$EXIT_CODE"
assert_contains "file.txt in CONFLICT output" "file.txt" "$OUTPUT"

# Verify merge aborted - no partial state
MAIN_TXT=$(cat "$REPO30/file.txt")
assert_eq "merge aborted, main content preserved" "main txt" "$MAIN_TXT"

# --- Test 31: get_merge_context with valid quantum.json ---
echo "--- Test 31: get_merge_context reads correctly ---"
REPO31="$TMPDIR/repo31"
mkdir -p "$REPO31"
create_test_quantum_json "$REPO31" "a.ts|b.ts" "types/shared.ts"
CTX_FILE=$(get_merge_context "$REPO31/quantum.json" 2>/dev/null)
EXIT_CODE=$?
assert_eq "get_merge_context returns 0" "0" "$EXIT_CODE"
if [[ -f "$CTX_FILE" ]]; then
  CTX_CONTENT=$(cat "$CTX_FILE")
  assert_contains "context has defaultAction" "defaultAction=escalate" "$CTX_CONTENT"
  assert_contains "context has filesChanged" "a.ts" "$CTX_CONTENT"
  assert_contains "context has materializedContracts" "types/shared.ts" "$CTX_CONTENT"
  assert_contains "context has rules" "dependency_manifest" "$CTX_CONTENT"
  rm -f "$CTX_FILE"
else
  TOTAL=$((TOTAL + 1))
  echo "  FAIL: get_merge_context did not create context file"
  FAIL=$((FAIL + 1))
fi

# --- Test 32: get_merge_context with missing file ---
echo "--- Test 32: get_merge_context error on missing file ---"
get_merge_context "/tmp/nonexistent_quantum_12345.json" >/dev/null 2>&1
assert_eq "get_merge_context on missing file returns 1" "1" "$?"

# --- Test 33: get_merge_context with empty path ---
echo "--- Test 33: get_merge_context error on empty path ---"
get_merge_context "" >/dev/null 2>&1
assert_eq "get_merge_context on empty path returns 1" "1" "$?"

# --- Test 34: get_merge_context fallback (no mergeStrategy) ---
echo "--- Test 34: get_merge_context with no mergeStrategy ---"
REPO34="$TMPDIR/repo34"
mkdir -p "$REPO34"
create_test_quantum_json_no_strategy "$REPO34"
CTX34=$(get_merge_context "$REPO34/quantum.json" 2>/dev/null)
EXIT_CODE=$?
assert_eq "get_merge_context returns 0 even without mergeStrategy" "0" "$EXIT_CODE"
if [[ -f "$CTX34" ]]; then
  CTX34_CONTENT=$(cat "$CTX34")
  assert_contains "defaultAction is escalate" "defaultAction=escalate" "$CTX34_CONTENT"
  assert_contains "rules is empty array" "rules=[]" "$CTX34_CONTENT"
  rm -f "$CTX34"
else
  TOTAL=$((TOTAL + 1))
  echo "  FAIL: context file not created for no-mergeStrategy case"
  FAIL=$((FAIL + 1))
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
