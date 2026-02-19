#!/usr/bin/env bash
# Test suite for lib/spawn.sh
# Tests agent spawn functions for both interactive and autonomous modes

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="$SCRIPT_DIR/../lib"
PASS=0
FAIL=0
TOTAL=0

# Source the library under test
if [[ ! -f "$LIB_DIR/spawn.sh" ]]; then
  echo "SKIP: lib/spawn.sh not found (RED phase)"
  exit 1
fi
source "$LIB_DIR/spawn.sh"

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
  if echo "$haystack" | grep -q "$needle"; then
    echo "  PASS: $test_name"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: $test_name"
    echo "    expected to contain: $needle"
    echo "    actual: $haystack"
    FAIL=$((FAIL + 1))
  fi
}

assert_not_empty() {
  local test_name="$1" value="$2"
  TOTAL=$((TOTAL + 1))
  if [[ -n "$value" ]]; then
    echo "  PASS: $test_name"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: $test_name (value is empty)"
    FAIL=$((FAIL + 1))
  fi
}

# =========================================================================
echo "=== Test 1: build_agent_prompt includes story ID ==="
PROMPT=$(build_agent_prompt "US-003")
assert_contains "Prompt contains story ID" "US-003" "$PROMPT"
assert_contains "Prompt contains implement instruction" "Implement story" "$PROMPT"

# =========================================================================
echo "=== Test 2: build_agent_prompt includes worktree warning ==="
PROMPT=$(build_agent_prompt "US-003")
assert_contains "Prompt warns about quantum.json" "quantum.json" "$PROMPT"

# =========================================================================
echo "=== Test 3: build_autonomous_command generates correct command ==="
CMD=$(build_autonomous_command "US-003" "/tmp/test-wt")
assert_contains "Command includes worktree path" "/tmp/test-wt" "$CMD"
assert_contains "Command includes story ID" "US-003" "$CMD"
assert_contains "Command uses claude" "claude" "$CMD"

# =========================================================================
echo "=== Test 4: Input validation - empty story_id ==="
RESULT=$(build_agent_prompt "" 2>&1)
EXIT_CODE=$?
assert_eq "Empty story_id returns error" "1" "$EXIT_CODE"

# =========================================================================
echo "=== Test 5: Input validation - invalid story_id format ==="
RESULT=$(build_agent_prompt "../hack" 2>&1)
EXIT_CODE=$?
assert_eq "Invalid story_id returns error" "1" "$EXIT_CODE"

# =========================================================================
echo "=== Test 6: build_autonomous_command validates inputs ==="
RESULT=$(build_autonomous_command "" "/tmp/wt" 2>&1)
EXIT_CODE=$?
assert_eq "Empty story_id in command returns error" "1" "$EXIT_CODE"

RESULT=$(build_autonomous_command "US-001" "" 2>&1)
EXIT_CODE=$?
assert_eq "Empty worktree_path in command returns error" "1" "$EXIT_CODE"

# =========================================================================
echo "=== Test 7: spawn_autonomous rejects empty story_id ==="
RESULT=$(spawn_autonomous "" "/tmp/wt" 2>&1)
EXIT_CODE=$?
assert_eq "spawn_autonomous empty story_id returns error" "1" "$EXIT_CODE"
assert_contains "spawn_autonomous empty story_id error message" "story_id is required" "$RESULT"

# =========================================================================
echo "=== Test 8: spawn_autonomous rejects empty worktree_path ==="
RESULT=$(spawn_autonomous "US-001" "" 2>&1)
EXIT_CODE=$?
assert_eq "spawn_autonomous empty worktree_path returns error" "1" "$EXIT_CODE"
assert_contains "spawn_autonomous empty worktree_path error message" "worktree_path is required" "$RESULT"

# =========================================================================
echo "=== Test 9: spawn_autonomous rejects nonexistent worktree_path ==="
RESULT=$(spawn_autonomous "US-001" "/tmp/nonexistent-path-$$" 2>&1)
EXIT_CODE=$?
assert_eq "spawn_autonomous nonexistent worktree_path returns error" "1" "$EXIT_CODE"
assert_contains "spawn_autonomous nonexistent path error message" "does not exist" "$RESULT"

# =========================================================================
echo "=== Test 10: spawn_autonomous returns PID with mock claude ==="
# Create a temp directory to act as worktree
TEST_WT=$(mktemp -d)
# Create a mock 'claude' that just echoes and exits
MOCK_BIN=$(mktemp -d)
cat > "$MOCK_BIN/claude" <<'MOCKEOF'
#!/usr/bin/env bash
echo "mock agent output"
exit 0
MOCKEOF
chmod +x "$MOCK_BIN/claude"

# Prepend mock to PATH so spawn_autonomous finds it
PATH="$MOCK_BIN:$PATH" PID_RESULT=$(spawn_autonomous "US-010" "$TEST_WT")
EXIT_CODE=$?
assert_eq "spawn_autonomous with mock returns 0" "0" "$EXIT_CODE"
assert_not_empty "spawn_autonomous returns a PID" "$PID_RESULT"

# Wait for the background process to finish
if [[ -n "$PID_RESULT" ]]; then
  wait "$PID_RESULT" 2>/dev/null || true
fi

# Verify output file was created with expected content
OUTPUT_FILE="${TEST_WT}/${AGENT_OUTPUT_FILENAME}"
if [[ -f "$OUTPUT_FILE" ]]; then
  TOTAL=$((TOTAL + 1))
  echo "  PASS: Output file created at expected path"
  PASS=$((PASS + 1))
  CONTENT=$(cat "$OUTPUT_FILE")
  assert_contains "Output file contains mock output" "mock agent output" "$CONTENT"
else
  TOTAL=$((TOTAL + 1))
  echo "  FAIL: Output file not found at $OUTPUT_FILE"
  FAIL=$((FAIL + 1))
fi

# Cleanup
rm -rf "$TEST_WT" "$MOCK_BIN"

# =========================================================================
echo "=== Test 11: AGENT_OUTPUT_FILENAME constant is defined ==="
assert_eq "AGENT_OUTPUT_FILENAME value" ".ql-agent-output.txt" "$AGENT_OUTPUT_FILENAME"

# =========================================================================
echo "=== Test 12: Multiple agents run concurrently ==="
# Create 3 temp directories to act as worktrees
WT1=$(mktemp -d)
WT2=$(mktemp -d)
WT3=$(mktemp -d)
# Create a mock 'claude' that sleeps so processes overlap
MOCK_BIN2=$(mktemp -d)
cat > "$MOCK_BIN2/claude" <<'MOCKEOF'
#!/usr/bin/env bash
sleep 3
echo "agent done"
exit 0
MOCKEOF
chmod +x "$MOCK_BIN2/claude"

# Use file-based PID capture (not command substitution) so background
# processes remain children of this shell and stay alive
PID_DIR=$(mktemp -d)
export PATH="$MOCK_BIN2:$PATH"

spawn_autonomous "US-001" "$WT1" > "$PID_DIR/pid1"
spawn_autonomous "US-002" "$WT2" > "$PID_DIR/pid2"
spawn_autonomous "US-003" "$WT3" > "$PID_DIR/pid3"

PID1=$(cat "$PID_DIR/pid1")
PID2=$(cat "$PID_DIR/pid2")
PID3=$(cat "$PID_DIR/pid3")

assert_not_empty "Agent 1 got a PID" "$PID1"
assert_not_empty "Agent 2 got a PID" "$PID2"
assert_not_empty "Agent 3 got a PID" "$PID3"

# Verify all 3 are running simultaneously
ALIVE_COUNT=0
for pid in $PID1 $PID2 $PID3; do
  if kill -0 "$pid" 2>/dev/null; then
    ALIVE_COUNT=$((ALIVE_COUNT + 1))
  fi
done
assert_eq "All 3 agents running concurrently" "3" "$ALIVE_COUNT"

# Wait for all to finish
for pid in $PID1 $PID2 $PID3; do
  wait "$pid" 2>/dev/null || true
done

# Cleanup
rm -rf "$WT1" "$WT2" "$WT3" "$MOCK_BIN2" "$PID_DIR"

# =========================================================================
echo ""
echo "=== Results: $PASS/$TOTAL passed, $FAIL failed ==="
if [[ $FAIL -eq 0 ]]; then
  exit 0
else
  exit 1
fi
