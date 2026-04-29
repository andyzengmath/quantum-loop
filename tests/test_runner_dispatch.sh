#!/usr/bin/env bash
# US-001 (v0.7.10) — N35 runner_dispatch wrapper unit tests.
#
# Verifies the runner_dispatch function in lib/runner.sh:
#   - Composes runner_load + runner_build_cmd + eval
#   - Returns the dispatched runner's exit code
#   - Forwards stdout from the runner

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$SCRIPT_DIR/.."
LIB="$REPO_ROOT/lib/runner.sh"
RUNNERS_DIR="$REPO_ROOT/runners"
MOCK_NAME="_test_mock_dispatch"
MOCK_MANIFEST="$RUNNERS_DIR/${MOCK_NAME}.json"
PASS=0
FAIL=0
TOTAL=0

assert() {
  local name="$1" expected="$2" actual="$3"
  TOTAL=$((TOTAL + 1))
  if [[ "$expected" == "$actual" ]]; then
    echo "  PASS: $name"; PASS=$((PASS + 1))
  else
    echo "  FAIL: $name (expected [$expected] got [$actual])"
    FAIL=$((FAIL + 1))
  fi
}

# Cleanup mock manifest on exit
cleanup() {
  rm -f "$MOCK_MANIFEST"
}
trap cleanup EXIT

echo "=== US-001 v0.7.10 runner_dispatch tests ==="

# Skip suite cleanly if lib missing
if [[ ! -f "$LIB" ]]; then
  echo "SKIP: lib/runner.sh not found"
  exit 1
fi

# Create mock manifest pointing at the echo binary (always available on Linux/Git Bash).
# Schema-conformant: all required fields populated.
cat > "$MOCK_MANIFEST" <<'EOF'
{
  "$schema": "../schemas/runner.schema.json",
  "name": "_test_mock_dispatch",
  "displayName": "Mock Echo Runner (test fixture)",
  "binary": "echo",
  "tier": "experimental",
  "installHint": "no install required (uses system echo)",
  "version": ">=0.0.0",
  "invocation": {
    "promptDelivery": "positional",
    "promptFlag": null,
    "headlessFlags": [],
    "autoApproveFlags": [],
    "outputFlags": [],
    "extraFlags": [],
    "stdinPipe": false
  },
  "instructionFile": {
    "native": "MOCK_INSTRUCTIONS.md",
    "fallbackFrom": null,
    "autoGenerate": false
  },
  "signals": {
    "preambleInjection": false,
    "heuristicFallback": false
  }
}
EOF

# Test 1: function exists after sourcing
echo ""
echo "Test 1: runner_dispatch is defined after sourcing lib/runner.sh"
TOTAL=$((TOTAL + 1))
fn_defined=$(bash -c "source '$LIB' && declare -F runner_dispatch >/dev/null && echo yes || echo no")
if [[ "$fn_defined" == "yes" ]]; then
  echo "  PASS: function defined"; PASS=$((PASS + 1))
else
  echo "  FAIL: function not defined after source"; FAIL=$((FAIL + 1))
fi

# Test 2: dispatch a prompt to the mock-echo runner -> stdout contains the prompt
echo ""
echo "Test 2: runner_dispatch _test_mock_dispatch -> echoes prompt + rc=0"
PROMPT="hello-from-runner-dispatch-test"
out2=$(bash -c "source '$LIB' && runner_dispatch '$MOCK_NAME' '$PROMPT'" 2>/dev/null)
rc2=$?
assert "Test 2: dispatch rc=0" "0" "$rc2"
TOTAL=$((TOTAL + 1))
if printf '%s' "$out2" | grep -q "$PROMPT"; then
  echo "  PASS: dispatched prompt present in stdout"; PASS=$((PASS + 1))
else
  echo "  FAIL: prompt not echoed back — got: $out2"; FAIL=$((FAIL + 1))
fi

# Test 3: dispatch with missing runner name -> rc != 0
echo ""
echo "Test 3: runner_dispatch unknown_runner -> rc != 0"
rc3=$(bash -c "source '$LIB' && runner_dispatch '_unknown_runner_xyz' 'prompt' >/dev/null 2>&1; echo \$?")
TOTAL=$((TOTAL + 1))
if [[ "$rc3" != "0" ]]; then
  echo "  PASS: unknown runner returns non-zero rc=$rc3"; PASS=$((PASS + 1))
else
  echo "  FAIL: unknown runner returned rc=0 (expected non-zero)"; FAIL=$((FAIL + 1))
fi

# Test 4: missing arguments -> rc != 0
echo ""
echo "Test 4: runner_dispatch with no args -> rc != 0"
rc4=$(bash -c "source '$LIB' && runner_dispatch >/dev/null 2>&1; echo \$?")
TOTAL=$((TOTAL + 1))
if [[ "$rc4" != "0" ]]; then
  echo "  PASS: missing args returns non-zero rc=$rc4"; PASS=$((PASS + 1))
else
  echo "  FAIL: missing args returned rc=0 (expected non-zero)"; FAIL=$((FAIL + 1))
fi

echo ""
echo "=== Results: $PASS/$TOTAL passed, $FAIL failed ==="
[[ $FAIL -eq 0 ]] || exit 1
