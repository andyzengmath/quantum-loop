#!/usr/bin/env bash
# Comprehensive unit tests for lib/runner.sh functions
# Covers: runner_load, runner_build_cmd, runner_ensure_instructions

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
  echo "SKIP: lib/runner.sh not found"
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

assert_not_contains() {
  local test_name="$1" needle="$2" haystack="$3"
  TOTAL=$((TOTAL + 1))
  if echo "$haystack" | grep -F -- "$needle" >/dev/null 2>&1; then
    echo "  FAIL: $test_name"
    echo "    should NOT contain: $needle"
    echo "    actual: $haystack"
    FAIL=$((FAIL + 1))
  else
    echo "  PASS: $test_name"
    PASS=$((PASS + 1))
  fi
}

# Create mock binaries
MOCK_DIR=$(mktemp -d)
for bin in claude codex copilot agent gemini amp aider; do
  echo '#!/usr/bin/env bash' > "$MOCK_DIR/$bin"
  chmod +x "$MOCK_DIR/$bin"
done
OLD_PATH="$PATH"
export PATH="$MOCK_DIR:$PATH"

# ── runner_load tests ──

echo "Test: runner_load_valid (claude)"
runner_load "claude" 2>/dev/null
assert_eq "load claude exits 0" "0" "$?"
assert_eq "RUNNER_NAME" "claude" "$RUNNER_NAME"
assert_eq "RUNNER_TIER" "guaranteed" "$RUNNER_TIER"

echo "Test: runner_load_missing"
OUTPUT=$(runner_load "nonexistent" 2>&1)
assert_eq "missing exits 1" "1" "$?"
assert_contains "lists available" "claude" "$OUTPUT"

echo "Test: runner_load_invalid_schema"
TMPD=$(mktemp -d)
mkdir -p "$TMPD/runners"
echo '{"name":"bad"}' > "$TMPD/runners/bad.json"
SAVED="$RUNNER_LIB_DIR"
RUNNER_LIB_DIR="$TMPD/lib"
mkdir -p "$RUNNER_LIB_DIR"
OUTPUT=$(runner_load "bad" 2>&1)
assert_eq "invalid exits 1" "1" "$?"
assert_contains "missing required" "missing required" "$OUTPUT"
RUNNER_LIB_DIR="$SAVED"
rm -rf "$TMPD"

# ── runner_build_cmd tests ──

echo "Test: runner_build_cmd_claude"
runner_load "claude" 2>/dev/null
cmd=$(runner_build_cmd "test prompt" 2>/dev/null)
assert_contains "claude binary" "claude" "$cmd"
assert_contains "print flag" "--print" "$cmd"
assert_contains "auto-approve" "dangerously-skip-permissions" "$cmd"
assert_contains "prompt flag -p" "-p" "$cmd"
assert_contains "prompt text" "test prompt" "$cmd"
assert_not_contains "no preamble for Claude" "REQUIRED SIGNALS" "$cmd"

echo "Test: runner_build_cmd_codex (positional)"
runner_load "codex" 2>/dev/null
cmd=$(runner_build_cmd "implement story" 2>/dev/null)
assert_contains "codex binary" "codex" "$cmd"
assert_contains "headless -q" "-q" "$cmd"
assert_contains "approval-mode" "approval-mode" "$cmd"
assert_contains "has preamble" "REQUIRED SIGNALS" "$cmd"

echo "Test: runner_build_cmd_stdin (amp)"
runner_load "amp" 2>/dev/null
cmd=$(runner_build_cmd "do stuff" 2>/dev/null)
assert_contains "uses printf pipe" "printf" "$cmd"
assert_contains "amp binary" "amp" "$cmd"
assert_contains "auto-approve" "dangerously-allow-all" "$cmd"

# ── runner_ensure_instructions tests ──

echo "Test: runner_ensure_instructions_creates"
TMPD=$(mktemp -d)
echo "# Claude Instructions" > "$TMPD/CLAUDE.md"
RUNNER_INSTRUCTION_NATIVE="AGENTS.md"
RUNNER_INSTRUCTION_FALLBACK="CLAUDE.md"
runner_ensure_instructions "$TMPD" 2>/dev/null
TOTAL=$((TOTAL + 1))
if [[ -f "$TMPD/AGENTS.md" ]]; then
  echo "  PASS: creates AGENTS.md"
  PASS=$((PASS + 1))
else
  echo "  FAIL: AGENTS.md not created"
  FAIL=$((FAIL + 1))
fi
assert_contains "has ql-generated marker" ".ql-generated" "$(head -1 "$TMPD/AGENTS.md")"

echo "Test: runner_ensure_instructions_no_overwrite"
echo "# User content" > "$TMPD/CUSTOM.md"
RUNNER_INSTRUCTION_NATIVE="CUSTOM.md"
RUNNER_INSTRUCTION_FALLBACK="CLAUDE.md"
runner_ensure_instructions "$TMPD" 2>/dev/null
content=$(cat "$TMPD/CUSTOM.md")
assert_eq "preserves user content" "# User content" "$content"

echo "Test: runner_ensure_instructions_idempotent"
# Remove AGENTS.md so we can test fresh generation
rm -f "$TMPD/AGENTS.md"
RUNNER_INSTRUCTION_NATIVE="AGENTS.md"
RUNNER_INSTRUCTION_FALLBACK="CLAUDE.md"
runner_ensure_instructions "$TMPD" 2>/dev/null
first=$(cat "$TMPD/AGENTS.md")
runner_ensure_instructions "$TMPD" 2>/dev/null
second=$(cat "$TMPD/AGENTS.md")
assert_eq "idempotent: same output" "$first" "$second"
rm -rf "$TMPD"

# ── Cleanup ──
export PATH="$OLD_PATH"
rm -rf "$MOCK_DIR"

echo ""
echo "Results: $PASS passed, $FAIL failed out of $TOTAL tests"
if [[ $FAIL -gt 0 ]]; then
  exit 1
fi
exit 0
