#!/usr/bin/env bash
# US-002 / P5.A2 — verify --critic=auto|codex|gemini|claude|none flag
# is parsed by quantum-loop.sh, validated against the enum, and routed
# through availability check + fallback. Also verifies the QL_CRITIC env
# var is consumed by lib/deep-review.sh's dispatch_critic helper.
#
# Pattern follows tests/test_audit.sh — sources quantum-loop.sh under
# QL_AUDIT_TEST_MODE so we can grep helper-function defs without
# triggering the main arg-loop.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$SCRIPT_DIR/.."
QL_SH="$REPO_ROOT/quantum-loop.sh"
QL_PS1="$REPO_ROOT/quantum-loop.ps1"
DR_SH="$REPO_ROOT/lib/deep-review.sh"
PASS=0
FAIL=0
TOTAL=0

assert_grep() {
  local name="$1" needle="$2" file="$3"
  TOTAL=$((TOTAL + 1))
  if grep -qF -- "$needle" "$file"; then
    echo "  PASS: $name"; PASS=$((PASS + 1))
  else
    echo "  FAIL: $name — needle [$needle] not in $(basename "$file")"
    FAIL=$((FAIL + 1))
  fi
}

assert_eq() {
  local name="$1" expected="$2" actual="$3"
  TOTAL=$((TOTAL + 1))
  if [[ "$expected" == "$actual" ]]; then
    echo "  PASS: $name"; PASS=$((PASS + 1))
  else
    echo "  FAIL: $name (expected [$expected] got [$actual])"
    FAIL=$((FAIL + 1))
  fi
}

echo "=== US-002 cross-provider critic CLI flag tests ==="

# Test 1: --critic flag present in quantum-loop.sh arg-parse loop
echo ""
echo "Test 1: --critic flag in quantum-loop.sh"
assert_grep "quantum-loop.sh has --critic flag case" "--critic" "$QL_SH"
assert_grep "QL_CRITIC env var assignment" "QL_CRITIC=" "$QL_SH"
assert_grep "validates against enum" "auto|codex|gemini|claude|none" "$QL_SH"

# Test 2: --critic flag present in quantum-loop.ps1
echo ""
echo "Test 2: --critic flag in quantum-loop.ps1"
assert_grep "quantum-loop.ps1 has Critic param" "Critic" "$QL_PS1"
assert_grep "ps1 validates the enum" "auto" "$QL_PS1"

# Test 3: lib/deep-review.sh consumes QL_CRITIC
echo ""
echo "Test 3: lib/deep-review.sh consumes QL_CRITIC env var"
assert_grep "deep-review.sh references QL_CRITIC" "QL_CRITIC" "$DR_SH"
assert_grep "deep-review.sh has critic-override block" "critic" "$DR_SH"

# Test 4: --critic=none short-circuit in quantum-loop.sh
echo ""
echo "Test 4: --critic=none short-circuits"
assert_grep "quantum-loop.sh handles 'none' value" "none" "$QL_SH"

# Test 5: availability check + fallback warning (US-001 unified-fallback semantics).
# After parse_critic_arg removal, the warning lives inside parse_role_arg's
# role-aware availability check. Critic role still degrades to 'none' (PS1 parity).
echo ""
echo "Test 5: availability check + degrade warning"
assert_grep "WARN message when binary missing" "WARN: per-role routing:" "$QL_SH"
assert_grep "falling back to none (critic role)" 'falling back to %s' "$QL_SH"
assert_grep "role-aware fallback comment" "critic role degrades to 'none'" "$QL_SH"

# Test 6: behavioral test — sourcing under QL_AUDIT_TEST_MODE doesn't error,
# and the unified parse_role_arg helper handles critic with role-aware fallback.
echo ""
echo "Test 6: parse_role_arg sourceable + behaves (US-001 unified-fallback)"
QL_AUDIT_TEST_MODE=1
# shellcheck disable=SC1090
source "$QL_SH" 2>/dev/null || true
unset QL_AUDIT_TEST_MODE

# US-001 / G8: parse_critic_arg has been deleted; parse_role_arg is the only entry point.
TOTAL=$((TOTAL + 1))
if ! declare -f parse_critic_arg >/dev/null 2>&1; then
  echo "  PASS: parse_critic_arg removed (dead code deleted)"
  PASS=$((PASS + 1))
else
  echo "  FAIL: parse_critic_arg still defined (G8 dead-code removal incomplete)"
  FAIL=$((FAIL + 1))
fi

if declare -f parse_role_arg >/dev/null 2>&1; then
  out=$(parse_role_arg critic auto 2>&1 | tail -1)
  assert_eq "parse_role_arg critic auto -> auto" "auto" "$out"

  out=$(parse_role_arg critic none 2>&1 | tail -1)
  assert_eq "parse_role_arg critic none -> none" "none" "$out"

  # US-001 G8: with a missing provider, critic must fall back to 'none' (not 'claude'),
  # preserving the US-002 'downgrade rather than substitute' design intent.
  ORIG_PATH="$PATH"
  PATH=/nonexistent
  out_stdout=$(parse_role_arg critic codex 2>/dev/null || true)
  out_stderr=$(parse_role_arg critic codex 2>&1 1>/dev/null || true)
  PATH="$ORIG_PATH"

  assert_eq "critic codex absent -> 'none' on stdout (role-aware fallback)" "none" "$out_stdout"

  TOTAL=$((TOTAL + 1))
  if printf '%s' "$out_stderr" | grep -qE "WARN: per-role routing: critic provider codex not available, falling back to none"; then
    echo "  PASS: critic codex absent emits role-aware WARN with 'falling back to none'"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: critic codex absent did not emit role-aware WARN (got [$out_stderr])"
    FAIL=$((FAIL + 1))
  fi

  # Same check for gemini.
  PATH=/nonexistent
  out_stdout=$(parse_role_arg critic gemini 2>/dev/null || true)
  PATH="$ORIG_PATH"
  assert_eq "critic gemini absent -> 'none' on stdout" "none" "$out_stdout"

  # Planner role: must fall back to 'claude' (NOT 'none') for missing providers.
  PATH=/nonexistent
  out_stdout=$(parse_role_arg planner codex 2>/dev/null || true)
  out_stderr=$(parse_role_arg planner codex 2>&1 1>/dev/null || true)
  PATH="$ORIG_PATH"
  assert_eq "planner codex absent -> 'claude' on stdout (role-aware: planner/executor still claude)" "claude" "$out_stdout"

  TOTAL=$((TOTAL + 1))
  if printf '%s' "$out_stderr" | grep -qE "WARN: per-role routing: planner provider codex not available, falling back to claude"; then
    echo "  PASS: planner codex absent emits 'falling back to claude'"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: planner codex absent did not emit 'falling back to claude' (got [$out_stderr])"
    FAIL=$((FAIL + 1))
  fi

  # Executor role: same as planner — falls back to 'claude'.
  PATH=/nonexistent
  out_stdout=$(parse_role_arg executor gemini 2>/dev/null || true)
  PATH="$ORIG_PATH"
  assert_eq "executor gemini absent -> 'claude' on stdout (role-aware)" "claude" "$out_stdout"
else
  TOTAL=$((TOTAL + 7))
  FAIL=$((FAIL + 7))
  for i in 1 2 3 4 5 6 7; do
    echo "  FAIL: parse_role_arg helper not defined"
  done
fi

echo ""
echo "=== Results: $PASS/$TOTAL passed, $FAIL failed ==="
[[ $FAIL -eq 0 ]] || exit 1
