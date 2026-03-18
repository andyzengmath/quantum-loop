#!/usr/bin/env bash
# tests/test_typecheck_gate.sh -- Tests for post_merge_typecheck() in lib/monitor.sh
#
# Test cases for T-001 (typecheck command detection):
#   1. No typecheckCommand in JSON, no language files -> skip, return 0
#   2. Explicit typecheckCommand in JSON -> uses it
#   3. Auto-detect TypeScript (tsconfig.json) -> tsc --noEmit
#   4. Command not found (exit 127) -> logs warning, returns 0
#
# Test cases for T-002 (baseline comparison):
#   5. Baseline not set -> initialize baseline, return 0
#   6. Error count <= baseline -> return 0
#   7. Error count > baseline -> revert merge, return 1

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="$SCRIPT_DIR/../lib"
PASS=0
FAIL=0
TOTAL=0

# Source dependencies
source "$LIB_DIR/common.sh"
source "$LIB_DIR/json-atomic.sh"
source "$LIB_DIR/spawn.sh"

# Source the library under test
if [[ ! -f "$LIB_DIR/monitor.sh" ]]; then
  echo "SKIP: lib/monitor.sh not found (RED phase)"
  exit 1
fi
source "$LIB_DIR/monitor.sh"

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

# Helper: create a test git repo with quantum.json
setup_typecheck_repo() {
  local test_dir
  test_dir=$(mktemp -d)
  git -C "$test_dir" init -q
  git -C "$test_dir" config user.email "test@test.com"
  git -C "$test_dir" config user.name "Test"
  # Create initial commit
  printf "init\n" > "$test_dir/README.md"
  git -C "$test_dir" add README.md
  git -C "$test_dir" commit -m "init" -q
  echo "$test_dir"
}

# =========================================================================
echo "=== Test 1: No typecheckCommand, no language files -> skip, return 0 ==="
TEST_REPO=$(setup_typecheck_repo)
# Create minimal quantum.json with no typecheckCommand
cat > "$TEST_REPO/quantum.json" <<'EOF'
{
  "project": "test",
  "stories": []
}
EOF

OUTPUT=$(post_merge_typecheck "$TEST_REPO" "$TEST_REPO/quantum.json" 2>&1)
EXIT_CODE=$?
assert_eq "No config skip returns 0" "0" "$EXIT_CODE"
assert_contains "Logs skip message" "[TYPECHECK] skip" "$OUTPUT"
rm -rf "$TEST_REPO"

# =========================================================================
echo "=== Test 2: Explicit typecheckCommand in JSON -> uses it ==="
TEST_REPO=$(setup_typecheck_repo)
# Create a fake typecheck script that always succeeds with 0 errors
cat > "$TEST_REPO/fake_typecheck.sh" <<'SCRIPT'
#!/usr/bin/env bash
exit 0
SCRIPT
chmod +x "$TEST_REPO/fake_typecheck.sh"

cat > "$TEST_REPO/quantum.json" <<EOF
{
  "project": "test",
  "typecheckCommand": "bash $TEST_REPO/fake_typecheck.sh",
  "stories": [],
  "execution": {
    "baselineTypecheckErrors": 0
  }
}
EOF

OUTPUT=$(post_merge_typecheck "$TEST_REPO" "$TEST_REPO/quantum.json" 2>&1)
EXIT_CODE=$?
assert_eq "Explicit command returns 0" "0" "$EXIT_CODE"
rm -rf "$TEST_REPO"

# =========================================================================
echo "=== Test 3: Auto-detect TypeScript (tsconfig.json) -> tsc --noEmit ==="
TEST_REPO=$(setup_typecheck_repo)
# Create tsconfig.json to trigger TypeScript detection
printf '{"compilerOptions":{}}' > "$TEST_REPO/tsconfig.json"

# Create a fake tsc that outputs known error count
mkdir -p "$TEST_REPO/.bin"
cat > "$TEST_REPO/.bin/tsc" <<'SCRIPT'
#!/usr/bin/env bash
# Simulate tsc with 0 errors (just exit 0)
exit 0
SCRIPT
chmod +x "$TEST_REPO/.bin/tsc"

cat > "$TEST_REPO/quantum.json" <<'EOF'
{
  "project": "test",
  "stories": [],
  "execution": {
    "baselineTypecheckErrors": 0
  }
}
EOF

# Run with PATH including our fake tsc
OUTPUT=$(PATH="$TEST_REPO/.bin:$PATH" post_merge_typecheck "$TEST_REPO" "$TEST_REPO/quantum.json" 2>&1)
EXIT_CODE=$?
assert_eq "Auto-detect TS returns 0" "0" "$EXIT_CODE"
assert_contains "Logs auto-detect" "[TYPECHECK]" "$OUTPUT"
rm -rf "$TEST_REPO"

# =========================================================================
echo "=== Test 4: Command not found (exit 127) -> logs warning, returns 0 ==="
TEST_REPO=$(setup_typecheck_repo)
cat > "$TEST_REPO/quantum.json" <<'EOF'
{
  "project": "test",
  "typecheckCommand": "nonexistent_typecheck_tool_xyz_123",
  "stories": []
}
EOF

OUTPUT=$(post_merge_typecheck "$TEST_REPO" "$TEST_REPO/quantum.json" 2>&1)
EXIT_CODE=$?
assert_eq "Command not found returns 0" "0" "$EXIT_CODE"
assert_contains "Logs not found warning" "[TYPECHECK]" "$OUTPUT"
rm -rf "$TEST_REPO"

# =========================================================================
echo "=== Test 5: Baseline not set -> initialize baseline, return 0 ==="
TEST_REPO=$(setup_typecheck_repo)
# Create a fake typecheck that outputs 3 error lines
cat > "$TEST_REPO/fake_typecheck.sh" <<'SCRIPT'
#!/usr/bin/env bash
echo "src/foo.ts:1:1 - error TS2322: Type mismatch"
echo "src/bar.ts:5:3 - error TS2339: Property missing"
echo "src/baz.ts:10:1 - error TS7006: Implicit any"
exit 1
SCRIPT
chmod +x "$TEST_REPO/fake_typecheck.sh"

# JSON with no execution.baselineTypecheckErrors
cat > "$TEST_REPO/quantum.json" <<EOF
{
  "project": "test",
  "typecheckCommand": "bash $TEST_REPO/fake_typecheck.sh",
  "stories": []
}
EOF

OUTPUT=$(post_merge_typecheck "$TEST_REPO" "$TEST_REPO/quantum.json" 2>&1)
EXIT_CODE=$?
assert_eq "Baseline init returns 0" "0" "$EXIT_CODE"
assert_contains "Logs baseline initialized" "[TYPECHECK] baseline initialized" "$OUTPUT"

# Verify baseline was written to JSON
BASELINE_VAL=$(jq -r '.execution.baselineTypecheckErrors' "$TEST_REPO/quantum.json" 2>/dev/null)
assert_eq "Baseline value written to JSON" "3" "$BASELINE_VAL"
rm -rf "$TEST_REPO"

# =========================================================================
echo "=== Test 6: Error count <= baseline -> return 0 ==="
TEST_REPO=$(setup_typecheck_repo)
# Create a fake typecheck that outputs 2 error lines (below baseline of 3)
cat > "$TEST_REPO/fake_typecheck.sh" <<'SCRIPT'
#!/usr/bin/env bash
echo "src/foo.ts:1:1 - error TS2322: Type mismatch"
echo "src/bar.ts:5:3 - error TS2339: Property missing"
exit 1
SCRIPT
chmod +x "$TEST_REPO/fake_typecheck.sh"

cat > "$TEST_REPO/quantum.json" <<EOF
{
  "project": "test",
  "typecheckCommand": "bash $TEST_REPO/fake_typecheck.sh",
  "stories": [],
  "execution": {
    "baselineTypecheckErrors": 3
  }
}
EOF

OUTPUT=$(post_merge_typecheck "$TEST_REPO" "$TEST_REPO/quantum.json" 2>&1)
EXIT_CODE=$?
assert_eq "Errors <= baseline returns 0" "0" "$EXIT_CODE"
assert_contains "Logs PASS" "[TYPECHECK] PASS" "$OUTPUT"
rm -rf "$TEST_REPO"

# =========================================================================
echo "=== Test 7: Error count > baseline -> revert merge, return 1 ==="
TEST_REPO=$(setup_typecheck_repo)

# Create a merge commit to revert (need at least 2 parent commits for -m 1)
# Create a branch, add a file, merge it
git -C "$TEST_REPO" checkout -b "side-branch" -q
printf "side content\n" > "$TEST_REPO/side.txt"
git -C "$TEST_REPO" add side.txt
git -C "$TEST_REPO" commit -m "side commit" -q
git -C "$TEST_REPO" checkout master -q 2>/dev/null || git -C "$TEST_REPO" checkout main -q 2>/dev/null
# Add something on main to ensure merge commit (not fast-forward)
printf "main content\n" > "$TEST_REPO/main_extra.txt"
git -C "$TEST_REPO" add main_extra.txt
git -C "$TEST_REPO" commit -m "main extra" -q
git -C "$TEST_REPO" merge side-branch --no-edit -q

# Now create fake typecheck with 5 errors (above baseline of 2)
cat > "$TEST_REPO/fake_typecheck.sh" <<'SCRIPT'
#!/usr/bin/env bash
echo "error: type mismatch 1"
echo "error: type mismatch 2"
echo "error: type mismatch 3"
echo "error: type mismatch 4"
echo "error: type mismatch 5"
exit 1
SCRIPT
chmod +x "$TEST_REPO/fake_typecheck.sh"

cat > "$TEST_REPO/quantum.json" <<EOF
{
  "project": "test",
  "typecheckCommand": "bash $TEST_REPO/fake_typecheck.sh",
  "stories": [],
  "execution": {
    "baselineTypecheckErrors": 2
  }
}
EOF

# Capture HEAD before the revert to verify the revert happened
HEAD_BEFORE=$(git -C "$TEST_REPO" rev-parse HEAD)

OUTPUT=$(post_merge_typecheck "$TEST_REPO" "$TEST_REPO/quantum.json" 2>&1)
EXIT_CODE=$?
assert_eq "Errors > baseline returns 1" "1" "$EXIT_CODE"
assert_contains "Logs FAIL and revert" "[TYPECHECK] FAIL" "$OUTPUT"

# Verify a revert commit was created (HEAD should have moved)
HEAD_AFTER=$(git -C "$TEST_REPO" rev-parse HEAD)
if [[ "$HEAD_BEFORE" != "$HEAD_AFTER" ]]; then
  TOTAL=$((TOTAL + 1)); echo "  PASS: Revert commit created (HEAD changed)"; PASS=$((PASS + 1))
else
  TOTAL=$((TOTAL + 1)); echo "  FAIL: No revert commit (HEAD unchanged)"; FAIL=$((FAIL + 1))
fi
rm -rf "$TEST_REPO"

# =========================================================================
echo ""
echo "=== Results: $PASS/$TOTAL passed, $FAIL failed ==="
if [[ $FAIL -eq 0 ]]; then
  exit 0
else
  exit 1
fi
