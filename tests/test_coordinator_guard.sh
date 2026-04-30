#!/usr/bin/env bash
# tests/test_coordinator_guard.sh
#
# v0.9.2 / US-001 — regression guard for lib/coordinator-guard.sh.
#
# Closes v0.9.1 finding 5a HIGH (implementer subagent ran `git reset --hard`
# mid-wave). This library provides an engineered safety net.
#
# Per v0.9.1 US-004 security review: ordinal SHA comparison is INSUFFICIENT
# (implementer can `reset --hard && commit` to advance HEAD past snapshot
# while creating a sibling rather than a descendant). Ancestry check via
# `git merge-base --is-ancestor` is mandatory. Test 3 specifically guards
# against the ordinal-comparison anti-pattern.
#
# 4 cases (per PRD AC):
#   1. ancestor advance (SHA0 → SHA1, legit) returns 0
#   2. reset to prior commit (SHA1 → SHA0, backwards) returns 1
#   3. reset-and-recommit (SHA1 → SHA2 sibling) returns 1 — ancestry critical
#   4. missing HEAD_BEFORE arg fails fast

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$SCRIPT_DIR/.."
GUARD_LIB="$REPO_ROOT/lib/coordinator-guard.sh"

PASS=0
FAIL=0
TOTAL=0

assert_eq() {
  local name="$1" expected="$2" actual="$3"
  TOTAL=$((TOTAL + 1))
  if [[ "$expected" == "$actual" ]]; then
    echo "  PASS: $name"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: $name"
    echo "    expected: $expected"
    echo "    actual:   $actual"
    FAIL=$((FAIL + 1))
  fi
}

assert_contains() {
  local name="$1" needle="$2" haystack="$3"
  TOTAL=$((TOTAL + 1))
  if echo "$haystack" | grep -qF -- "$needle"; then
    echo "  PASS: $name"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: $name"
    echo "    expected to contain: $needle"
    echo "    actual: $haystack"
    FAIL=$((FAIL + 1))
  fi
}

echo "=== US-001 v0.9.2 coordinator-guard tests ==="

if [[ ! -f "$GUARD_LIB" ]]; then
  echo "FAIL: $GUARD_LIB does not exist (RED phase or missing implementation)"
  exit 1
fi

# Throwaway git repo
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

git -C "$TMP" init -q
git -C "$TMP" config user.email "test@test.com"
git -C "$TMP" config user.name "Test"

# SHA0 = initial commit
echo "init" > "$TMP/file.txt"
git -C "$TMP" add . && git -C "$TMP" commit -q -m "init"
SHA0=$(git -C "$TMP" rev-parse HEAD)

# SHA1 = advance from SHA0
echo "second" >> "$TMP/file.txt"
git -C "$TMP" add . && git -C "$TMP" commit -q -m "second"
SHA1=$(git -C "$TMP" rev-parse HEAD)

# shellcheck source=lib/coordinator-guard.sh
source "$GUARD_LIB"

# ─ Test 1: ancestor advance ────────────────────────────────────────────────
echo
echo "Test 1: ancestor advance (SHA0 -> SHA1) returns 0"
out=$(cd "$TMP" && guard_head_advance "$SHA0" "$SHA1" 2>&1)
rc=$?
assert_eq "Test 1: rc=0" "0" "$rc"
assert_eq "Test 1: no stderr message" "" "$out"

# ─ Test 2: reset backwards (SHA1 not ancestor of SHA0) ─────────────────────
echo
echo "Test 2: HEAD reset backwards (SHA1 -> SHA0) returns 1"
out=$(cd "$TMP" && guard_head_advance "$SHA1" "$SHA0" 2>&1)
rc=$?
assert_eq "Test 2: rc=1" "1" "$rc"
assert_contains "Test 2: stderr contains 'HEAD reset detected'" "HEAD reset detected" "$out"

# ─ Test 3: reset-and-recommit sibling (ancestry-check critical) ─────────────
echo
echo "Test 3: reset-and-recommit sibling (SHA1 not ancestor of SHA2) returns 1"
git -C "$TMP" reset --hard -q "$SHA0"
echo "different" >> "$TMP/file.txt"
git -C "$TMP" add . && git -C "$TMP" commit -q -m "different"
SHA2=$(git -C "$TMP" rev-parse HEAD)
# SHA2 is a sibling of SHA1 (both children of SHA0). Ordinal comparison
# would see SHA2 as a "different SHA" but ancestry correctly rejects.
out=$(cd "$TMP" && guard_head_advance "$SHA1" "$SHA2" 2>&1)
rc=$?
assert_eq "Test 3: rc=1" "1" "$rc"
assert_contains "Test 3: stderr contains 'HEAD reset detected'" "HEAD reset detected" "$out"

# ─ Test 4: missing HEAD_BEFORE arg fails fast ──────────────────────────────
echo
echo "Test 4: missing HEAD_BEFORE arg fails fast"
out=$(cd "$TMP" && guard_head_advance 2>&1)
rc=$?
if [[ "$rc" -ne 0 ]]; then
  TOTAL=$((TOTAL + 1)); PASS=$((PASS + 1))
  echo "  PASS: Test 4: rc != 0 (got $rc)"
else
  TOTAL=$((TOTAL + 1)); FAIL=$((FAIL + 1))
  echo "  FAIL: Test 4: rc should be non-zero (got $rc)"
fi
assert_contains "Test 4: stderr mentions HEAD_BEFORE" "HEAD_BEFORE" "$out"

echo
echo "=== Results: $PASS/$TOTAL passed, $FAIL failed ==="
[[ "$FAIL" -eq 0 ]]
