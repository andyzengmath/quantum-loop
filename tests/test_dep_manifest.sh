#!/usr/bin/env bash
# Test suite for lib/dep-manifest.sh
# Tests dependency manifest detection, protection, lockfile verification, and install

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="$SCRIPT_DIR/../lib"
PASS=0
FAIL=0
TOTAL=0

# Source dependencies
source "$LIB_DIR/common.sh"

# Source the library under test
if [[ ! -f "$LIB_DIR/dep-manifest.sh" ]]; then
  echo "SKIP: lib/dep-manifest.sh not found (RED phase)"
  exit 1
fi
source "$LIB_DIR/dep-manifest.sh"

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
echo "=== Test 1: detect_package_manager returns npm for package.json ==="
TEST_DIR=$(mktemp -d)
touch "$TEST_DIR/package.json"
RESULT=$(detect_package_manager "$TEST_DIR")
assert_contains "detects npm" "npm" "$RESULT"
rm -rf "$TEST_DIR"

# =========================================================================
echo "=== Test 2: detect_package_manager returns yarn for yarn.lock ==="
TEST_DIR=$(mktemp -d)
touch "$TEST_DIR/yarn.lock"
RESULT=$(detect_package_manager "$TEST_DIR")
assert_contains "detects yarn" "yarn" "$RESULT"
rm -rf "$TEST_DIR"

# =========================================================================
echo "=== Test 3: detect_package_manager returns pnpm for pnpm-lock.yaml ==="
TEST_DIR=$(mktemp -d)
touch "$TEST_DIR/pnpm-lock.yaml"
RESULT=$(detect_package_manager "$TEST_DIR")
assert_contains "detects pnpm" "pnpm" "$RESULT"
rm -rf "$TEST_DIR"

# =========================================================================
echo "=== Test 4: detect_package_manager returns cargo for Cargo.toml ==="
TEST_DIR=$(mktemp -d)
touch "$TEST_DIR/Cargo.toml"
RESULT=$(detect_package_manager "$TEST_DIR")
assert_contains "detects cargo" "cargo" "$RESULT"
rm -rf "$TEST_DIR"

# =========================================================================
echo "=== Test 5: detect_package_manager returns pip for requirements.txt ==="
TEST_DIR=$(mktemp -d)
touch "$TEST_DIR/requirements.txt"
RESULT=$(detect_package_manager "$TEST_DIR")
assert_contains "detects pip" "pip" "$RESULT"
rm -rf "$TEST_DIR"

# =========================================================================
echo "=== Test 6: detect_package_manager returns poetry for poetry.lock+pyproject.toml ==="
TEST_DIR=$(mktemp -d)
touch "$TEST_DIR/poetry.lock"
touch "$TEST_DIR/pyproject.toml"
RESULT=$(detect_package_manager "$TEST_DIR")
assert_contains "detects poetry" "poetry" "$RESULT"
rm -rf "$TEST_DIR"

# =========================================================================
echo "=== Test 7: detect_package_manager returns go for go.mod ==="
TEST_DIR=$(mktemp -d)
touch "$TEST_DIR/go.mod"
RESULT=$(detect_package_manager "$TEST_DIR")
assert_contains "detects go" "go" "$RESULT"
rm -rf "$TEST_DIR"

# =========================================================================
echo "=== Test 8: detect_package_manager returns empty for no manifests ==="
TEST_DIR=$(mktemp -d)
RESULT=$(detect_package_manager "$TEST_DIR")
assert_eq "empty for no manifests" "" "$RESULT"
rm -rf "$TEST_DIR"

# =========================================================================
echo "=== Test 9: detect_package_manager returns multiple managers ==="
TEST_DIR=$(mktemp -d)
touch "$TEST_DIR/package.json"
touch "$TEST_DIR/Cargo.toml"
touch "$TEST_DIR/go.mod"
RESULT=$(detect_package_manager "$TEST_DIR")
assert_contains "detects npm in multi" "npm" "$RESULT"
assert_contains "detects cargo in multi" "cargo" "$RESULT"
assert_contains "detects go in multi" "go" "$RESULT"
rm -rf "$TEST_DIR"

# =========================================================================
echo "=== Test 10: detect_package_manager with empty repo_root ==="
RESULT=$(detect_package_manager "" 2>&1)
EXIT_CODE=$?
assert_eq "empty repo_root returns error" "1" "$EXIT_CODE"
assert_contains "error message for empty repo_root" "ERROR" "$RESULT"

# =========================================================================
echo "=== Test 11: detect_package_manager with nonexistent directory ==="
RESULT=$(detect_package_manager "/nonexistent/path/xxx" 2>&1)
EXIT_CODE=$?
assert_eq "nonexistent dir returns error" "1" "$EXIT_CODE"

# =========================================================================
echo "=== Test 12: poetry requires BOTH poetry.lock and pyproject.toml ==="
TEST_DIR=$(mktemp -d)
touch "$TEST_DIR/poetry.lock"
# No pyproject.toml -- should NOT detect poetry
RESULT=$(detect_package_manager "$TEST_DIR")
assert_not_contains "no poetry without pyproject.toml" "poetry" "$RESULT"
rm -rf "$TEST_DIR"

# =========================================================================
echo "=== Test 13: pyproject.toml alone does not trigger poetry ==="
TEST_DIR=$(mktemp -d)
touch "$TEST_DIR/pyproject.toml"
# No poetry.lock -- should NOT detect poetry
RESULT=$(detect_package_manager "$TEST_DIR")
assert_not_contains "no poetry without poetry.lock" "poetry" "$RESULT"
rm -rf "$TEST_DIR"

# =========================================================================
# Tests for protect_manifest
# =========================================================================

setup_git_repo() {
  local test_dir
  test_dir=$(mktemp -d)
  git -C "$test_dir" init -q
  git -C "$test_dir" config user.email "test@test.com"
  git -C "$test_dir" config user.name "Test"
  git -C "$test_dir" commit --allow-empty -m "init" -q
  echo "$test_dir"
}

echo "=== Test 14: protect_manifest protects known manifests ==="
TEST_REPO=$(setup_git_repo)
# Create a package.json and commit it
echo '{"name":"test"}' > "$TEST_REPO/package.json"
git -C "$TEST_REPO" add package.json
git -C "$TEST_REPO" commit -m "add package.json" -q
# Modify to simulate conflict scenario
echo '{"name":"modified"}' > "$TEST_REPO/package.json"
git -C "$TEST_REPO" add package.json
RESULT=$(protect_manifest "$TEST_REPO" "package.json")
assert_eq "protect_manifest returns 1 for one manifest" "1" "$RESULT"
rm -rf "$TEST_REPO"

echo "=== Test 15: protect_manifest with multiple manifests ==="
TEST_REPO=$(setup_git_repo)
echo '{"name":"test"}' > "$TEST_REPO/package.json"
echo '[dependencies]' > "$TEST_REPO/Cargo.toml"
git -C "$TEST_REPO" add package.json Cargo.toml
git -C "$TEST_REPO" commit -m "add manifests" -q
echo '{"name":"conflict"}' > "$TEST_REPO/package.json"
echo '[devdeps]' > "$TEST_REPO/Cargo.toml"
git -C "$TEST_REPO" add package.json Cargo.toml
RESULT=$(protect_manifest "$TEST_REPO" "package.json Cargo.toml")
assert_eq "protect_manifest returns 2 for two manifests" "2" "$RESULT"
rm -rf "$TEST_REPO"

echo "=== Test 16: protect_manifest skips non-manifest files ==="
TEST_REPO=$(setup_git_repo)
echo 'hello' > "$TEST_REPO/README.md"
git -C "$TEST_REPO" add README.md
git -C "$TEST_REPO" commit -m "add readme" -q
echo 'changed' > "$TEST_REPO/README.md"
git -C "$TEST_REPO" add README.md
RESULT=$(protect_manifest "$TEST_REPO" "README.md")
assert_eq "protect_manifest returns 0 for non-manifest" "0" "$RESULT"
rm -rf "$TEST_REPO"

echo "=== Test 17: protect_manifest with empty conflict_files ==="
TEST_REPO=$(setup_git_repo)
RESULT=$(protect_manifest "$TEST_REPO" "")
assert_eq "protect_manifest returns 0 for empty conflict list" "0" "$RESULT"
rm -rf "$TEST_REPO"

echo "=== Test 18: protect_manifest with empty repo_root ==="
RESULT=$(protect_manifest "" "package.json" 2>&1)
EXIT_CODE=$?
assert_eq "protect_manifest empty repo_root returns error" "1" "$EXIT_CODE"

echo "=== Test 19: protect_manifest with mixed manifest and non-manifest ==="
TEST_REPO=$(setup_git_repo)
echo '{}' > "$TEST_REPO/package.json"
mkdir -p "$TEST_REPO/src"
echo 'hi' > "$TEST_REPO/src/app.js"
git -C "$TEST_REPO" add -A
git -C "$TEST_REPO" commit -m "add files" -q
echo '{"v":2}' > "$TEST_REPO/package.json"
echo 'bye' > "$TEST_REPO/src/app.js"
git -C "$TEST_REPO" add -A
RESULT=$(protect_manifest "$TEST_REPO" "package.json src/app.js")
assert_eq "protect_manifest counts only manifests" "1" "$RESULT"
rm -rf "$TEST_REPO"

# =========================================================================
# Tests for verify_lockfile
# =========================================================================

echo "=== Test 20: verify_lockfile finds non-empty package-lock.json ==="
TEST_DIR=$(mktemp -d)
echo '{"lockfileVersion":1}' > "$TEST_DIR/package-lock.json"
verify_lockfile "$TEST_DIR" "npm"
EXIT_CODE=$?
assert_eq "verify_lockfile npm returns 0" "0" "$EXIT_CODE"
rm -rf "$TEST_DIR"

echo "=== Test 21: verify_lockfile fails for missing lockfile ==="
TEST_DIR=$(mktemp -d)
verify_lockfile "$TEST_DIR" "npm" 2>/dev/null
EXIT_CODE=$?
assert_eq "verify_lockfile npm missing returns 1" "1" "$EXIT_CODE"
rm -rf "$TEST_DIR"

echo "=== Test 22: verify_lockfile fails for empty lockfile ==="
TEST_DIR=$(mktemp -d)
touch "$TEST_DIR/package-lock.json"
verify_lockfile "$TEST_DIR" "npm" 2>/dev/null
EXIT_CODE=$?
assert_eq "verify_lockfile npm empty returns 1" "1" "$EXIT_CODE"
rm -rf "$TEST_DIR"

echo "=== Test 23: verify_lockfile for yarn ==="
TEST_DIR=$(mktemp -d)
echo 'lockfile-content' > "$TEST_DIR/yarn.lock"
verify_lockfile "$TEST_DIR" "yarn"
EXIT_CODE=$?
assert_eq "verify_lockfile yarn returns 0" "0" "$EXIT_CODE"
rm -rf "$TEST_DIR"

echo "=== Test 24: verify_lockfile for pnpm ==="
TEST_DIR=$(mktemp -d)
echo 'lockfile-content' > "$TEST_DIR/pnpm-lock.yaml"
verify_lockfile "$TEST_DIR" "pnpm"
EXIT_CODE=$?
assert_eq "verify_lockfile pnpm returns 0" "0" "$EXIT_CODE"
rm -rf "$TEST_DIR"

echo "=== Test 25: verify_lockfile for cargo ==="
TEST_DIR=$(mktemp -d)
echo 'lockfile-content' > "$TEST_DIR/Cargo.lock"
verify_lockfile "$TEST_DIR" "cargo"
EXIT_CODE=$?
assert_eq "verify_lockfile cargo returns 0" "0" "$EXIT_CODE"
rm -rf "$TEST_DIR"

echo "=== Test 26: verify_lockfile for pip (no lockfile concept) ==="
TEST_DIR=$(mktemp -d)
echo 'flask==2.0' > "$TEST_DIR/requirements.txt"
verify_lockfile "$TEST_DIR" "pip"
EXIT_CODE=$?
assert_eq "verify_lockfile pip returns 0 with requirements.txt" "0" "$EXIT_CODE"
rm -rf "$TEST_DIR"

echo "=== Test 27: verify_lockfile for poetry ==="
TEST_DIR=$(mktemp -d)
echo 'lockfile-content' > "$TEST_DIR/poetry.lock"
verify_lockfile "$TEST_DIR" "poetry"
EXIT_CODE=$?
assert_eq "verify_lockfile poetry returns 0" "0" "$EXIT_CODE"
rm -rf "$TEST_DIR"

echo "=== Test 28: verify_lockfile for go ==="
TEST_DIR=$(mktemp -d)
echo 'lockfile-content' > "$TEST_DIR/go.sum"
verify_lockfile "$TEST_DIR" "go"
EXIT_CODE=$?
assert_eq "verify_lockfile go returns 0" "0" "$EXIT_CODE"
rm -rf "$TEST_DIR"

echo "=== Test 29: verify_lockfile with empty repo_root ==="
verify_lockfile "" "npm" 2>/dev/null
EXIT_CODE=$?
assert_eq "verify_lockfile empty repo_root returns 1" "1" "$EXIT_CODE"

echo "=== Test 30: verify_lockfile with empty package_manager ==="
TEST_DIR=$(mktemp -d)
verify_lockfile "$TEST_DIR" "" 2>/dev/null
EXIT_CODE=$?
assert_eq "verify_lockfile empty manager returns 1" "1" "$EXIT_CODE"
rm -rf "$TEST_DIR"

echo "=== Test 31: verify_lockfile for unknown manager ==="
TEST_DIR=$(mktemp -d)
verify_lockfile "$TEST_DIR" "unknown_manager" 2>/dev/null
EXIT_CODE=$?
assert_eq "verify_lockfile unknown manager returns 1" "1" "$EXIT_CODE"
rm -rf "$TEST_DIR"

# =========================================================================
# Tests for run_install
# =========================================================================

echo "=== Test 32: run_install with empty repo_root ==="
OUTPUT=$(run_install "" "npm" 2>&1)
EXIT_CODE=$?
assert_eq "run_install empty repo_root returns 1" "1" "$EXIT_CODE"
assert_contains "run_install error for empty repo_root" "ERROR" "$OUTPUT"

echo "=== Test 33: run_install with empty package_manager ==="
TEST_DIR=$(mktemp -d)
OUTPUT=$(run_install "$TEST_DIR" "" 2>&1)
EXIT_CODE=$?
assert_eq "run_install empty manager returns 1" "1" "$EXIT_CODE"
rm -rf "$TEST_DIR"

echo "=== Test 34: run_install with unknown manager ==="
TEST_DIR=$(mktemp -d)
OUTPUT=$(run_install "$TEST_DIR" "unknown_mgr" 2>&1)
EXIT_CODE=$?
assert_eq "run_install unknown manager returns 1" "1" "$EXIT_CODE"
rm -rf "$TEST_DIR"

echo "=== Test 35: run_install with npm runs npm install ==="
# We create a fake npm that succeeds to test the mapping
TEST_DIR=$(mktemp -d)
mkdir -p "$TEST_DIR/bin"
cat > "$TEST_DIR/bin/npm" <<'FAKEEOF'
#!/usr/bin/env bash
echo "npm-install-ran"
exit 0
FAKEEOF
chmod +x "$TEST_DIR/bin/npm"
echo '{"name":"test"}' > "$TEST_DIR/package.json"
OUTPUT=$(PATH="$TEST_DIR/bin:$PATH" run_install "$TEST_DIR" "npm" 2>&1)
EXIT_CODE=$?
assert_eq "run_install npm exits 0" "0" "$EXIT_CODE"
assert_contains "run_install npm timing log" "[DEP-MANIFEST]" "$OUTPUT"
assert_contains "run_install npm completed message" "completed in" "$OUTPUT"
rm -rf "$TEST_DIR"

echo "=== Test 36: run_install with cargo ==="
TEST_DIR=$(mktemp -d)
mkdir -p "$TEST_DIR/bin"
cat > "$TEST_DIR/bin/cargo" <<'FAKEEOF'
#!/usr/bin/env bash
echo "cargo-build-ran"
exit 0
FAKEEOF
chmod +x "$TEST_DIR/bin/cargo"
echo '[package]' > "$TEST_DIR/Cargo.toml"
OUTPUT=$(PATH="$TEST_DIR/bin:$PATH" run_install "$TEST_DIR" "cargo" 2>&1)
EXIT_CODE=$?
assert_eq "run_install cargo exits 0" "0" "$EXIT_CODE"
assert_contains "run_install cargo timing log" "[DEP-MANIFEST]" "$OUTPUT"
rm -rf "$TEST_DIR"

echo "=== Test 37: run_install with pip ==="
TEST_DIR=$(mktemp -d)
mkdir -p "$TEST_DIR/bin"
cat > "$TEST_DIR/bin/pip" <<'FAKEEOF'
#!/usr/bin/env bash
echo "pip-install-ran"
exit 0
FAKEEOF
chmod +x "$TEST_DIR/bin/pip"
echo 'flask==2.0' > "$TEST_DIR/requirements.txt"
OUTPUT=$(PATH="$TEST_DIR/bin:$PATH" run_install "$TEST_DIR" "pip" 2>&1)
EXIT_CODE=$?
assert_eq "run_install pip exits 0" "0" "$EXIT_CODE"
rm -rf "$TEST_DIR"

echo "=== Test 38: run_install with poetry ==="
TEST_DIR=$(mktemp -d)
mkdir -p "$TEST_DIR/bin"
cat > "$TEST_DIR/bin/poetry" <<'FAKEEOF'
#!/usr/bin/env bash
echo "poetry-install-ran"
exit 0
FAKEEOF
chmod +x "$TEST_DIR/bin/poetry"
OUTPUT=$(PATH="$TEST_DIR/bin:$PATH" run_install "$TEST_DIR" "poetry" 2>&1)
EXIT_CODE=$?
assert_eq "run_install poetry exits 0" "0" "$EXIT_CODE"
rm -rf "$TEST_DIR"

echo "=== Test 39: run_install with go ==="
TEST_DIR=$(mktemp -d)
mkdir -p "$TEST_DIR/bin"
cat > "$TEST_DIR/bin/go" <<'FAKEEOF'
#!/usr/bin/env bash
echo "go-mod-tidy-ran"
exit 0
FAKEEOF
chmod +x "$TEST_DIR/bin/go"
OUTPUT=$(PATH="$TEST_DIR/bin:$PATH" run_install "$TEST_DIR" "go" 2>&1)
EXIT_CODE=$?
assert_eq "run_install go exits 0" "0" "$EXIT_CODE"
rm -rf "$TEST_DIR"

echo "=== Test 40: run_install failure returns 1 but does not propagate ==="
TEST_DIR=$(mktemp -d)
mkdir -p "$TEST_DIR/bin"
# Fake npm that always fails, and fake git checkout --theirs also fails
cat > "$TEST_DIR/bin/npm" <<'FAKEEOF'
#!/usr/bin/env bash
echo "npm-install-failed" >&2
exit 1
FAKEEOF
chmod +x "$TEST_DIR/bin/npm"
echo '{"name":"test"}' > "$TEST_DIR/package.json"
# Also mock git to avoid real git operations during recovery
cat > "$TEST_DIR/bin/git" <<'FAKEEOF'
#!/usr/bin/env bash
exit 1
FAKEEOF
chmod +x "$TEST_DIR/bin/git"
OUTPUT=$(PATH="$TEST_DIR/bin:$PATH" run_install "$TEST_DIR" "npm" 2>&1)
EXIT_CODE=$?
assert_eq "run_install failure returns 1" "1" "$EXIT_CODE"
rm -rf "$TEST_DIR"

echo "=== Test 41: run_install timing log format ==="
TEST_DIR=$(mktemp -d)
mkdir -p "$TEST_DIR/bin"
cat > "$TEST_DIR/bin/yarn" <<'FAKEEOF'
#!/usr/bin/env bash
echo "yarn-install-ran"
exit 0
FAKEEOF
chmod +x "$TEST_DIR/bin/yarn"
OUTPUT=$(PATH="$TEST_DIR/bin:$PATH" run_install "$TEST_DIR" "yarn" 2>&1)
EXIT_CODE=$?
assert_eq "run_install yarn exits 0" "0" "$EXIT_CODE"
# Check timing format: [DEP-MANIFEST] Install completed in Nms
assert_contains "timing format has ms" "ms" "$OUTPUT"
rm -rf "$TEST_DIR"

echo "=== Test 42: run_install with pnpm ==="
TEST_DIR=$(mktemp -d)
mkdir -p "$TEST_DIR/bin"
cat > "$TEST_DIR/bin/pnpm" <<'FAKEEOF'
#!/usr/bin/env bash
echo "pnpm-install-ran"
exit 0
FAKEEOF
chmod +x "$TEST_DIR/bin/pnpm"
OUTPUT=$(PATH="$TEST_DIR/bin:$PATH" run_install "$TEST_DIR" "pnpm" 2>&1)
EXIT_CODE=$?
assert_eq "run_install pnpm exits 0" "0" "$EXIT_CODE"
rm -rf "$TEST_DIR"

# =========================================================================
echo ""
echo "=== Results: $PASS/$TOTAL passed, $FAIL failed ==="
if [[ $FAIL -eq 0 ]]; then
  exit 0
else
  exit 1
fi
