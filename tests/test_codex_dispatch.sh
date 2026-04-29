#!/usr/bin/env bash
# US-002 (v0.7.10) — N35 codex real-task dispatch test (skip-aware).
#
# DISPATCH-LAYER test (vs the SMOKE-LAYER version-probe in
# tests/test_codex_runner_smoke.sh). Smoke verifies binary present + manifest
# loadable; dispatch verifies the full invocation chain end-to-end on a tiny
# real prompt. See CLAUDE.md "Multi-runner test layers".
#
# Skips silently when the codex CLI is not installed (mirrors v0.7.7 smoke
# pattern). When installed: invokes codex via runner_dispatch with a tiny
# prompt and asserts rc=0 + non-empty stdout. Wall-clock ceiling 60s.

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

echo "=== US-002 v0.7.10 codex real-task dispatch test ==="

if ! command -v codex >/dev/null 2>&1; then
  echo "SKIP: codex CLI not installed — dispatch test cannot run"
  echo "      (smoke tests still verify manifest schema; see CLAUDE.md Multi-runner test layers)"
  exit 0
fi

if [[ ! -f "$LIB" ]]; then
  echo "FAIL: lib/runner.sh not found"
  exit 1
fi

# Test 1: dispatch a tiny prompt to codex
echo ""
echo "Test 1: runner_dispatch codex 'Reply with the word OK' -> rc=0 + non-empty stdout"
PROMPT="Reply with the word OK"
t0=$(date +%s)
rc=0
out=$(bash -c "source '$LIB' && runner_dispatch codex '$PROMPT'" 2>/dev/null) || rc=$?
t1=$(date +%s)
elapsed=$((t1 - t0))

assert "Test 1: codex dispatch rc=0" "0" "$rc"
TOTAL=$((TOTAL + 1))
if (( elapsed <= 60 )); then
  echo "  PASS: codex dispatch completed in ${elapsed}s (<=60s ceiling)"; PASS=$((PASS + 1))
else
  echo "  FAIL: codex dispatch took ${elapsed}s (>60s ceiling)"; FAIL=$((FAIL + 1))
fi
TOTAL=$((TOTAL + 1))
if [[ -n "$out" ]]; then
  echo "  PASS: codex stdout non-empty (${#out} chars)"; PASS=$((PASS + 1))
else
  echo "  FAIL: codex stdout empty"; FAIL=$((FAIL + 1))
fi

echo ""
echo "=== Results: $PASS/$TOTAL passed, $FAIL failed ==="
[[ $FAIL -eq 0 ]] || exit 1
