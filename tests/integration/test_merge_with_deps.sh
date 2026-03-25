#!/usr/bin/env bash
# tests/integration/test_merge_with_deps.sh
# Integration test: dependency manifest merge via classify_and_merge
#
# Scenario:
#   main has package.json with {dependencies: {dep-a: "1.0"}}
#   worktree branch: adds dep-b to package.json
#   main: adds dep-c and commits
#   Merge worktree branch via classify_and_merge
#   Verify: package.json conflict classified as dependency_manifest:ours:install,
#           final package.json has dep-a and dep-c (ours), returns 0

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="$SCRIPT_DIR/../../lib"
PASS=0
FAIL=0
TOTAL=0

# Source the merge-strategy module (which sources barrel-regen and dep-manifest)
if [[ ! -f "$LIB_DIR/merge-strategy.sh" ]]; then
  echo "SKIP: lib/merge-strategy.sh not found"
  exit 1
fi
source "$LIB_DIR/merge-strategy.sh"

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

assert_file_contains() {
  local test_name="$1" needle="$2" file_path="$3"
  TOTAL=$((TOTAL + 1))
  if [[ -f "$file_path" ]] && grep -qF "$needle" "$file_path"; then
    echo "  PASS: $test_name"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: $test_name"
    echo "    expected file to contain: $needle"
    if [[ -f "$file_path" ]]; then
      echo "    file contents: $(cat "$file_path")"
    else
      echo "    file does not exist: $file_path"
    fi
    FAIL=$((FAIL + 1))
  fi
}

assert_file_not_contains() {
  local test_name="$1" needle="$2" file_path="$3"
  TOTAL=$((TOTAL + 1))
  if [[ -f "$file_path" ]] && ! grep -qF "$needle" "$file_path"; then
    echo "  PASS: $test_name"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: $test_name"
    echo "    expected file NOT to contain: $needle"
    if [[ -f "$file_path" ]]; then
      echo "    file contents: $(cat "$file_path")"
    fi
    FAIL=$((FAIL + 1))
  fi
}

# =========================================================================
TMPDIR=$(mktemp -d)
ORIG_DIR=$(pwd)

cleanup() {
  cd "$ORIG_DIR" || true
  rm -rf "$TMPDIR"
}
trap cleanup EXIT

# Helper: create quantum.json with dependency_manifest ours+install rule
create_deps_quantum_json() {
  local repo_dir="$1"
  local py_repo_dir="$repo_dir"
  if command -v cygpath &>/dev/null; then
    py_repo_dir=$(cygpath -m "$repo_dir")
  fi
  python -c "
import json
d = {
  'project': 'test-deps-integration',
  'execution': {
    'mergeStrategy': {
      'rules': [
        {'name': 'dependency_manifest', 'filePattern': 'package.json|package-lock.json|Cargo.toml|Cargo.lock|pyproject.toml|poetry.lock|go.mod|go.sum|requirements*.txt', 'strategy': 'ours', 'postAction': 'install'},
        {'name': 'barrel_export', 'filePattern': '**/index.ts|**/index.js|**/__init__.py|**/mod.rs', 'strategy': 'regenerate'}
      ],
      'defaultAction': 'escalate'
    }
  },
  'progress': []
}
with open('${py_repo_dir}/quantum.json', 'w') as f:
  json.dump(d, f, indent=2)
"
}

# =========================================================================
echo "=== Integration Test: Dependency Manifest Merge ==="
echo ""

# Step 1: Set up temp git repo with main branch
echo "--- Step 1: Set up repo with initial package.json ---"
REPO="$TMPDIR/deps-test"
mkdir -p "$REPO"
cd "$REPO" || exit 1
git init --initial-branch=main . >/dev/null 2>&1
git config user.email "test@test.com"
git config user.name "Test"

# Create initial package.json with dep-a
cat > package.json << 'PKGJSON'
{
  "name": "test-project",
  "version": "1.0.0",
  "dependencies": {
    "dep-a": "1.0"
  }
}
PKGJSON
git add -A >/dev/null 2>&1
git commit -m "initial: package.json with dep-a" >/dev/null 2>&1

# Step 2: Create worktree branch from main: adds dep-b to package.json
echo "--- Step 2: Create worktree branch with dep-b ---"
git checkout -b ql-wt/US-DEPS >/dev/null 2>&1
cat > package.json << 'PKGJSON'
{
  "name": "test-project",
  "version": "1.0.0",
  "dependencies": {
    "dep-a": "1.0",
    "dep-b": "2.0"
  }
}
PKGJSON
git add -A >/dev/null 2>&1
git commit -m "worktree: add dep-b" >/dev/null 2>&1

# Step 3: On main: add dep-c and commit
echo "--- Step 3: On main, add dep-c ---"
git checkout main >/dev/null 2>&1
cat > package.json << 'PKGJSON'
{
  "name": "test-project",
  "version": "1.0.0",
  "dependencies": {
    "dep-a": "1.0",
    "dep-c": "3.0"
  }
}
PKGJSON
git add -A >/dev/null 2>&1
git commit -m "main: add dep-c" >/dev/null 2>&1

# Step 4: Set up quantum.json with dependency_manifest ours+install rule
echo "--- Step 4: Set up quantum.json with mergeStrategy ---"
create_deps_quantum_json "$REPO"
git add quantum.json >/dev/null 2>&1
git commit -m "add quantum.json" >/dev/null 2>&1

# Mock npm install to avoid actually running it
# Create a mock npm script that just exits 0
MOCK_BIN="$TMPDIR/mock-bin"
mkdir -p "$MOCK_BIN"
cat > "$MOCK_BIN/npm" << 'MOCKEOF'
#!/usr/bin/env bash
# Mock npm: just exit 0 successfully
exit 0
MOCKEOF
chmod +x "$MOCK_BIN/npm"
export PATH="$MOCK_BIN:$PATH"

# Step 5: Merge worktree branch via classify_and_merge
echo "--- Step 5: Merge worktree branch via classify_and_merge ---"
OUTPUT=$(classify_and_merge "ql-wt/US-DEPS" "$REPO" "$REPO/quantum.json" 2>&1)
MERGE_EXIT=$?

echo "  classify_and_merge output:"
echo "$OUTPUT" | sed 's/^/    /'

# Verify: returns 0 (conflict resolved)
assert_eq "classify_and_merge returns 0 (deps conflict resolved)" "0" "$MERGE_EXIT"

# Verify: conflict was classified as dependency_manifest:ours:install
assert_contains "output mentions dependency_manifest classification" "dependency_manifest" "$OUTPUT"

# Step 6: Verify final package.json contents
echo "--- Step 6: Verify final package.json ---"
PKG_FILE="$REPO/package.json"
if [[ -f "$PKG_FILE" ]]; then
  echo "  Final package.json contents:"
  cat "$PKG_FILE" | sed 's/^/    /'
fi

# Ours strategy: final package.json should have dep-a and dep-c (from main)
assert_file_contains "package.json has dep-a" "dep-a" "$PKG_FILE"
assert_file_contains "package.json has dep-c (ours)" "dep-c" "$PKG_FILE"

# Theirs dep-b should NOT be in the final file (ours strategy protects main)
assert_file_not_contains "package.json does not have dep-b (theirs rejected)" "dep-b" "$PKG_FILE"

# Verify: no merge conflict markers remain
assert_file_not_contains "no conflict markers in package.json" "<<<<<<<" "$PKG_FILE"
assert_file_not_contains "no conflict separator in package.json" "=======" "$PKG_FILE"
assert_file_not_contains "no conflict end marker in package.json" ">>>>>>>" "$PKG_FILE"

# Verify: git working tree is clean
GIT_STATUS=$(git -C "$REPO" status --porcelain)
assert_eq "working tree clean after merge" "" "$GIT_STATUS"

# Verify: package.json is valid JSON
echo "--- Step 7: Verify package.json is valid JSON ---"
VALID_JSON=$(python -c "
import json, sys
py_path = '$PKG_FILE'
try:
    import subprocess
    # Handle cygpath on Windows
    try:
        py_path = subprocess.check_output(['cygpath', '-m', py_path], text=True).strip()
    except Exception:
        pass
    with open(py_path) as f:
        json.load(f)
    print('valid')
except Exception as e:
    print(f'invalid: {e}')
" 2>&1)
assert_eq "package.json is valid JSON" "valid" "$VALID_JSON"

# =========================================================================
echo ""
echo "=== Results: $PASS/$TOTAL passed, $FAIL failed ==="
if [[ $FAIL -eq 0 ]]; then
  exit 0
else
  exit 1
fi
