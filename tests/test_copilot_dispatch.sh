#!/usr/bin/env bash
# US-003 (v0.7.10) — N35 copilot real-task dispatch test (skip-aware).
#
# DISPATCH-LAYER test (vs the SMOKE-LAYER version-probe in
# tests/test_copilot_runner_smoke.sh). Smoke verifies binary present +
# manifest loadable; dispatch verifies the full invocation chain end-to-end
# on a tiny real prompt. See CLAUDE.md "Multi-runner test layers".
#
# Skips silently when the copilot CLI is not installed. When installed:
# invokes copilot via runner_dispatch with a tiny prompt and asserts rc=0 +
# non-empty stdout. Wall-clock ceiling 60s.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$SCRIPT_DIR/.."
LIB="$REPO_ROOT/lib/runner.sh"
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

echo "=== US-003 v0.7.10 copilot real-task dispatch test ==="

if ! command -v copilot >/dev/null 2>&1; then
  echo "SKIP: copilot CLI not installed — dispatch test cannot run"
  echo "      (smoke tests still verify manifest schema; see CLAUDE.md Multi-runner test layers)"
  exit 0
fi

if [[ ! -f "$LIB" ]]; then
  echo "FAIL: lib/runner.sh not found"
  exit 1
fi

# Test 1: dispatch a tiny prompt to copilot
echo ""
echo "Test 1: runner_dispatch copilot 'Reply with the word OK' -> rc=0 + non-empty stdout"
PROMPT="Reply with the word OK"
t0=$(date +%s)
rc=0
out=$(bash -c "source '$LIB' && runner_dispatch copilot '$PROMPT'" 2>/dev/null) || rc=$?
t1=$(date +%s)
elapsed=$((t1 - t0))

assert "Test 1: copilot dispatch rc=0" "0" "$rc"
TOTAL=$((TOTAL + 1))
if (( elapsed <= 150 )); then  # real-network LLM dispatch + Git Bash fork overhead; see references/test-wallclock-baselines.md
  echo "  PASS: copilot dispatch completed in ${elapsed}s (<=150s ceiling — real-network + cold-start jitter tolerated)"; PASS=$((PASS + 1))
else
  echo "  FAIL: copilot dispatch took ${elapsed}s (>150s ceiling — investigate; refer to references/test-wallclock-baselines.md)"; FAIL=$((FAIL + 1))
fi
TOTAL=$((TOTAL + 1))
if [[ -n "$out" ]]; then
  echo "  PASS: copilot stdout non-empty (${#out} chars)"; PASS=$((PASS + 1))
else
  echo "  FAIL: copilot stdout empty"; FAIL=$((FAIL + 1))
fi

echo ""
echo "=== Results: $PASS/$TOTAL passed, $FAIL failed ==="
[[ $FAIL -eq 0 ]] || exit 1
