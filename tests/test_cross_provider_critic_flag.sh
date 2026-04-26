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

# Test 5: availability check + fallback warning
echo ""
echo "Test 5: availability check + degrade warning"
assert_grep "WARN message when binary missing" "WARN: critic provider" "$QL_SH"
assert_grep "falling back to none" "falling back to none" "$QL_SH"

# Test 6: behavioral test — sourcing under QL_AUDIT_TEST_MODE doesn't error,
# and the parse_critic helper exists.
echo ""
echo "Test 6: parse_critic helper sourceable + behaves"
QL_AUDIT_TEST_MODE=1
# shellcheck disable=SC1090
source "$QL_SH" 2>/dev/null || true
unset QL_AUDIT_TEST_MODE

if declare -f parse_critic_arg >/dev/null 2>&1; then
  out=$(parse_critic_arg auto 2>&1 | tail -1)
  assert_eq "auto resolves to auto" "auto" "$out"

  out=$(parse_critic_arg none 2>&1 | tail -1)
  assert_eq "none resolves to none" "none" "$out"

  # Codex without binary on a fake PATH — must degrade to none and
  # emit warning to stderr. Save PATH (we need grep below) and restore.
  ORIG_PATH="$PATH"
  PATH=/nonexistent
  out_stderr=$(parse_critic_arg codex 2>&1 1>/dev/null || true)
  PATH="$ORIG_PATH"
  TOTAL=$((TOTAL + 1))
  if printf '%s' "$out_stderr" | grep -qF "WARN: critic provider codex not available"; then
    echo "  PASS: codex absent emits WARN"; PASS=$((PASS + 1))
  else
    echo "  FAIL: codex absent did not emit WARN (got [$out_stderr])"
    FAIL=$((FAIL + 1))
  fi
else
  TOTAL=$((TOTAL + 3))
  FAIL=$((FAIL + 3))
  echo "  FAIL: parse_critic_arg helper not defined"
  echo "  FAIL: parse_critic_arg helper not defined"
  echo "  FAIL: parse_critic_arg helper not defined"
fi

echo ""
echo "=== Results: $PASS/$TOTAL passed, $FAIL failed ==="
[[ $FAIL -eq 0 ]] || exit 1
