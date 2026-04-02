#!/usr/bin/env bash
# Test suite for lib/runner.sh runner_load() function

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="$SCRIPT_DIR/../lib"
PASS=0
FAIL=0
TOTAL=0

if ! command -v jq &>/dev/null; then
  echo "SKIP: jq not found"
  exit 1
fi

if [[ ! -f "$LIB_DIR/runner.sh" ]]; then
  echo "SKIP: lib/runner.sh not found (RED phase)"
  exit 1
fi
source "$LIB_DIR/runner.sh"

assert_eq() {
  local test_name="$1" expected="$2" actual="$3"
  TOTAL=$((TOTAL + 1))
  if [[ "$expected" == "$actual" ]]; then
    echo "  PASS: $test_name"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: $test_name"
    echo "    expected: $expected"
    echo "    actual: $actual"
    FAIL=$((FAIL + 1))
  fi
}

assert_contains() {
  local test_name="$1" needle="$2" haystack="$3"
  TOTAL=$((TOTAL + 1))
  if echo "$haystack" | grep -F -- "$needle" >/dev/null 2>&1; then
    echo "  PASS: $test_name"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: $test_name"
    echo "    expected to contain: $needle"
    echo "    actual: $haystack"
    FAIL=$((FAIL + 1))
  fi
}

# ── Test: runner_load with valid claude manifest ──
echo "Test: runner_load_valid_claude"

# Create a mock binary so command -v succeeds
MOCK_DIR=$(mktemp -d)
cat > "$MOCK_DIR/claude" << 'MOCKEOF'
#!/usr/bin/env bash
echo "mock claude"
MOCKEOF
chmod +x "$MOCK_DIR/claude"
OLD_PATH="$PATH"
export PATH="$MOCK_DIR:$PATH"

# Call runner_load directly (NOT in a subshell) so RUNNER_* vars persist
runner_load "claude" 2>/dev/null
RESULT=$?
assert_eq "runner_load claude exits 0" "0" "$RESULT"
assert_eq "RUNNER_NAME is claude" "claude" "$RUNNER_NAME"
assert_eq "RUNNER_BINARY is claude" "claude" "$RUNNER_BINARY"
assert_eq "RUNNER_TIER is guaranteed" "guaranteed" "$RUNNER_TIER"
assert_eq "RUNNER_PROMPT_DELIVERY is flag" "flag" "$RUNNER_PROMPT_DELIVERY"
assert_eq "RUNNER_PROMPT_FLAG is -p" "-p" "$RUNNER_PROMPT_FLAG"
assert_contains "RUNNER_HEADLESS_FLAGS contains --print" "--print" "$RUNNER_HEADLESS_FLAGS"
assert_contains "RUNNER_AUTO_APPROVE_FLAGS contains skip-permissions" "dangerously-skip-permissions" "$RUNNER_AUTO_APPROVE_FLAGS"
assert_eq "RUNNER_STDIN_PIPE is false" "false" "$RUNNER_STDIN_PIPE"
assert_eq "RUNNER_INSTRUCTION_NATIVE is CLAUDE.md" "CLAUDE.md" "$RUNNER_INSTRUCTION_NATIVE"
assert_eq "RUNNER_PREAMBLE_INJECTION is false" "false" "$RUNNER_PREAMBLE_INJECTION"
assert_eq "RUNNER_HEURISTIC_FALLBACK is false" "false" "$RUNNER_HEURISTIC_FALLBACK"
assert_eq "RUNNER_EXTRA_FLAGS is empty" "" "$RUNNER_EXTRA_FLAGS"
assert_eq "RUNNER_OVERRIDE_SIGNAL is empty" "" "$RUNNER_OVERRIDE_SIGNAL"

export PATH="$OLD_PATH"
rm -rf "$MOCK_DIR"

# ── Test: runner_load with missing manifest ──
echo "Test: runner_load_missing_manifest"
OUTPUT=$(runner_load "nonexistent" 2>&1)
RESULT=$?
assert_eq "runner_load nonexistent exits 1" "1" "$RESULT"
assert_contains "error mentions unknown runner" "Unknown runner" "$OUTPUT"
assert_contains "error lists available runners" "claude" "$OUTPUT"

# ── Test: runner_load with missing binary ──
echo "Test: runner_load_missing_binary"
# Create a temp manifest for a runner whose binary doesn't exist
TMPDIR_MANIFEST=$(mktemp -d)
mkdir -p "$TMPDIR_MANIFEST/runners"
cat > "$TMPDIR_MANIFEST/runners/fakecli.json" << 'EOF'
{
  "name": "fakecli",
  "displayName": "Fake CLI",
  "binary": "nonexistent-binary-xyz",
  "tier": "experimental",
  "installHint": "pip install fakecli",
  "version": ">=0.1.0",
  "invocation": {
    "promptDelivery": "flag",
    "promptFlag": "-p",
    "headlessFlags": [],
    "autoApproveFlags": [],
    "outputFlags": [],
    "extraFlags": [],
    "stdinPipe": false
  },
  "instructionFile": { "native": "AGENTS.md", "fallbackFrom": "CLAUDE.md", "autoGenerate": true },
  "signals": { "preambleInjection": true, "heuristicFallback": true },
  "quirks": {}
}
EOF
SAVED_LIB_DIR="$RUNNER_LIB_DIR"
RUNNER_LIB_DIR="$TMPDIR_MANIFEST/lib"
mkdir -p "$RUNNER_LIB_DIR"
OUTPUT=$(runner_load "fakecli" 2>&1)
RESULT=$?
assert_eq "runner_load missing binary exits 1" "1" "$RESULT"
assert_contains "error mentions binary not found" "not found" "$OUTPUT"
assert_contains "error shows install hint" "pip install fakecli" "$OUTPUT"
RUNNER_LIB_DIR="$SAVED_LIB_DIR"
rm -rf "$TMPDIR_MANIFEST"

# ── Summary ──
echo ""
echo "=== Results: $PASS/$TOTAL passed, $FAIL failed ==="
if [[ $FAIL -gt 0 ]]; then
  exit 1
fi
exit 0
