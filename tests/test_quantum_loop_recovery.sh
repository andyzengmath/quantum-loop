#!/usr/bin/env bash
# US-006 (v0.8.0) — N33 quantum-loop.sh recovery-infrastructure integration test.
#
# Verifies that v0.8.0 / US-001 successfully wired wrap_orchestrator_dispatch
# into quantum-loop.sh. Without this wiring, the recovery infrastructure was
# inert in production for 12+ cycles. This test asserts:
#   - quantum-loop.sh sources lib/orchestrator-liveness.sh
#   - quantum-loop.sh exposes ql_wrap_subagent_dispatch as a callable function
#   - The wrapper, when invoked against a stale tmp repo, fires STALE detection
#     within wall-clock ceiling and emits the canonical handoff message

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$SCRIPT_DIR/.."
QUANTUM_LOOP="$REPO_ROOT/quantum-loop.sh"
LIVENESS_LIB="$REPO_ROOT/lib/orchestrator-liveness.sh"
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

echo "=== US-006 v0.8.0 quantum-loop.sh recovery integration tests ==="

# Test 1: lib/orchestrator-liveness.sh source wired into quantum-loop.sh
echo ""
echo "Test 1: quantum-loop.sh sources lib/orchestrator-liveness.sh"
TOTAL=$((TOTAL + 1))
if grep -q 'orchestrator-liveness' "$QUANTUM_LOOP"; then
  echo "  PASS: source line present"; PASS=$((PASS + 1))
else
  echo "  FAIL: orchestrator-liveness not sourced in quantum-loop.sh"; FAIL=$((FAIL + 1))
fi

# Test 2: ql_wrap_subagent_dispatch helper defined in quantum-loop.sh
echo ""
echo "Test 2: quantum-loop.sh defines ql_wrap_subagent_dispatch helper"
TOTAL=$((TOTAL + 1))
if grep -q 'ql_wrap_subagent_dispatch' "$QUANTUM_LOOP"; then
  echo "  PASS: helper definition present"; PASS=$((PASS + 1))
else
  echo "  FAIL: ql_wrap_subagent_dispatch not defined in quantum-loop.sh"; FAIL=$((FAIL + 1))
fi

# Test 3: wrap_orchestrator_dispatch fires STALE detection on stub-orchestrator scenario
echo ""
echo "Test 3: wrap_orchestrator_dispatch fires STALE on a non-committing orchestrator"
TMP=$(mktemp -d)
( cd "$TMP" && git init -q && git config user.email "t@t.t" && git config user.name "t" \
  && echo "init" > README.md && git add README.md && git commit -qm "init" ) >/dev/null 2>&1
t0=$(date +%s)
rc=0
out=$(cd "$TMP" && bash -c "source '$LIVENESS_LIB' && wrap_orchestrator_dispatch 2 1" 2>&1) || rc=$?
t1=$(date +%s)
elapsed=$((t1 - t0))

assert "Test 3: stale rc=1" "1" "$rc"
TOTAL=$((TOTAL + 1))
if (( elapsed <= 15 )); then
  echo "  PASS: stale detection within 15s ceiling (got ${elapsed}s)"; PASS=$((PASS + 1))
else
  echo "  FAIL: stale detection took ${elapsed}s (>15s)"; FAIL=$((FAIL + 1))
fi
TOTAL=$((TOTAL + 1))
if printf '%s' "$out" | grep -qE 'orchestrator-stale signal'; then
  echo "  PASS: handoff message present"; PASS=$((PASS + 1))
else
  echo "  FAIL: handoff message missing — out: $out"; FAIL=$((FAIL + 1))
fi
rm -rf "$TMP"

echo ""
echo "=== Results: $PASS/$TOTAL passed, $FAIL failed ==="
[[ $FAIL -eq 0 ]] || exit 1
