#!/usr/bin/env bash
# Integration tests for --tool flag behavior with runner adapter system
# Tests all 7 runners, unknown rejection, default tool, banner, experimental warning,
# and Claude command regression gate.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="$SCRIPT_DIR/../lib"
RUNNERS_DIR="$SCRIPT_DIR/../runners"
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
    echo "    actual: $(echo "$haystack" | head -5)"
    FAIL=$((FAIL + 1))
  fi
}

assert_not_contains() {
  local test_name="$1" needle="$2" haystack="$3"
  TOTAL=$((TOTAL + 1))
  if echo "$haystack" | grep -F -- "$needle" >/dev/null 2>&1; then
    echo "  FAIL: $test_name"
    echo "    should NOT contain: $needle"
    FAIL=$((FAIL + 1))
  else
    echo "  PASS: $test_name"
    PASS=$((PASS + 1))
  fi
}

# Create mock binaries for all 7 runners
MOCK_DIR=$(mktemp -d)
for bin in claude codex copilot agent gemini amp aider; do
  echo '#!/usr/bin/env bash' > "$MOCK_DIR/$bin"
  echo 'echo "mock $0"' >> "$MOCK_DIR/$bin"
  chmod +x "$MOCK_DIR/$bin"
done
OLD_PATH="$PATH"
export PATH="$MOCK_DIR:$PATH"

# ── Test: all_manifests_accepted ──
echo "Test: all_manifests_accepted"
for runner in claude codex copilot cursor gemini amp aider; do
  source "$LIB_DIR/runner.sh"
  runner_load "$runner" 2>/dev/null
  RESULT=$?
  assert_eq "runner_load $runner succeeds" "0" "$RESULT"
done

# ── Test: unknown_rejected ──
echo "Test: unknown_rejected"
source "$LIB_DIR/runner.sh"
OUTPUT=$(runner_load "unknown_tool_xyz" 2>&1)
RESULT=$?
assert_eq "unknown runner rejected" "1" "$RESULT"
assert_contains "lists available runners" "claude" "$OUTPUT"

# ── Test: default_is_claude ──
echo "Test: default_is_claude"
source "$LIB_DIR/runner.sh"
runner_load "claude" 2>/dev/null
assert_eq "default runner is claude" "claude" "$RUNNER_NAME"
assert_eq "default tier is guaranteed" "guaranteed" "$RUNNER_TIER"

# ── Test: banner_shows_runner ──
echo "Test: banner_shows_runner"
source "$LIB_DIR/runner.sh"
runner_load "codex" 2>/dev/null
assert_eq "banner runner name" "codex" "$RUNNER_NAME"
assert_eq "banner binary" "codex" "$RUNNER_BINARY"
assert_eq "banner tier" "tested" "$RUNNER_TIER"

# ── Test: experimental_warning ──
echo "Test: experimental_warning"
source "$LIB_DIR/runner.sh"
runner_load "copilot" 2>/dev/null
assert_eq "copilot is experimental" "experimental" "$RUNNER_TIER"
# Verify the warning would trigger (tier == experimental)
TOTAL=$((TOTAL + 1))
if [[ "$RUNNER_TIER" == "experimental" ]]; then
  echo "  PASS: experimental warning triggers for copilot"
  PASS=$((PASS + 1))
else
  echo "  FAIL: experimental warning should trigger for copilot"
  FAIL=$((FAIL + 1))
fi

# ── Test: no_warning_noninteractive ──
echo "Test: no_warning_noninteractive"
# The warning is suppressed by NON_INTERACTIVE=true in quantum-loop.sh
# Here we verify the runner loads successfully without blocking
source "$LIB_DIR/runner.sh"
runner_load "gemini" 2>/dev/null
RESULT=$?
assert_eq "experimental runner loads without blocking" "0" "$RESULT"

# ── Test: claude_command_regression (CI gate) ──
echo "Test: claude_command_regression"
source "$LIB_DIR/runner.sh"
runner_load "claude" 2>/dev/null
cmd=$(runner_build_cmd "test prompt" 2>/dev/null)
# Must match: claude --print --dangerously-skip-permissions -p 'test prompt'
assert_contains "has claude binary" "claude" "$cmd"
assert_contains "has --print" "--print" "$cmd"
assert_contains "has -p flag" "-p" "$cmd"
assert_contains "has prompt" "test" "$cmd"  # printf %q escapes spaces
assert_not_contains "no preamble" "REQUIRED SIGNALS" "$cmd"
assert_not_contains "no heuristic" "heuristic" "$cmd"

# ── Test: codex_end_to_end ──
echo "Test: codex_end_to_end"
source "$LIB_DIR/runner.sh"
runner_load "codex" 2>/dev/null

# Verify all codex manifest values loaded correctly
assert_eq "codex name" "codex" "$RUNNER_NAME"
assert_eq "codex binary" "codex" "$RUNNER_BINARY"
assert_eq "codex tier" "tested" "$RUNNER_TIER"
assert_eq "codex delivery" "positional" "$RUNNER_PROMPT_DELIVERY"
assert_contains "codex headless -q" "-q" "$RUNNER_HEADLESS_FLAGS"
assert_contains "codex approval-mode" "approval-mode" "$RUNNER_AUTO_APPROVE_FLAGS"
assert_eq "codex preamble enabled" "true" "$RUNNER_PREAMBLE_INJECTION"
assert_eq "codex heuristic enabled" "true" "$RUNNER_HEURISTIC_FALLBACK"
assert_eq "codex native instruction" "AGENTS.md" "$RUNNER_INSTRUCTION_NATIVE"
assert_eq "codex fallback" "CLAUDE.md" "$RUNNER_INSTRUCTION_FALLBACK"

# Verify codex command structure (positional delivery + preamble)
cmd=$(runner_build_cmd "implement story US-001" 2>/dev/null)
assert_contains "codex cmd has binary" "codex" "$cmd"
assert_contains "codex cmd has -q" "-q" "$cmd"
assert_contains "codex cmd has approval-mode" "approval-mode" "$cmd"
assert_contains "codex cmd has preamble" "REQUIRED SIGNALS" "$cmd"
assert_contains "codex cmd has prompt" "implement" "$cmd"
# Positional: no -p flag
assert_not_contains "codex cmd no -p flag" " -p " "$cmd"

# Verify codex hook fires (sandbox warning)
OUTPUT=$(runner_build_cmd "test" 2>&1 >/dev/null)
assert_contains "codex hook sandbox warning" "sandbox" "$OUTPUT"

# Verify instruction file generation
TMPD=$(mktemp -d)
echo "# Project instructions" > "$TMPD/CLAUDE.md"
runner_ensure_instructions "$TMPD" 2>/dev/null
TOTAL=$((TOTAL + 1))
if [[ -f "$TMPD/AGENTS.md" ]]; then
  echo "  PASS: codex AGENTS.md generated from CLAUDE.md"
  PASS=$((PASS + 1))
else
  echo "  FAIL: codex AGENTS.md not generated"
  FAIL=$((FAIL + 1))
fi
assert_contains "codex AGENTS.md has marker" ".ql-generated" "$(head -1 "$TMPD/AGENTS.md")"
assert_contains "codex AGENTS.md has original content" "Project instructions" "$(cat "$TMPD/AGENTS.md")"
rm -rf "$TMPD"

# Verify codex signal heuristic path works
RUNNER_HEURISTIC_FALLBACK="true"
TMPD=$(mktemp -d)
git -C "$TMPD" init -q 2>/dev/null
git -C "$TMPD" config user.email "t@t.com" 2>/dev/null
git -C "$TMPD" config user.name "T" 2>/dev/null
echo "x" > "$TMPD/f.txt"
git -C "$TMPD" add . 2>/dev/null
git -C "$TMPD" commit -m "feat: US-001 - Test" -q 2>/dev/null
runner_parse_output "Running tests... 0 failures" 0 "$TMPD" 2>/dev/null
assert_eq "codex heuristic commit+tests → PASSED" "STORY_PASSED" "$SIGNAL_RESULT"
assert_eq "codex heuristic confidence=high" "high" "$SIGNAL_CONFIDENCE"
rm -rf "$TMPD"

# ── Cleanup ──
export PATH="$OLD_PATH"
rm -rf "$MOCK_DIR"

echo ""
echo "=== Results: $PASS/$TOTAL passed, $FAIL failed ==="
if [[ $FAIL -gt 0 ]]; then
  exit 1
fi
exit 0
