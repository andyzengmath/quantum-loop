#!/usr/bin/env bash
# Phase 44 / US-001..US-004 — --audit flag tests.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$SCRIPT_DIR/.."
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

setup_audit_repo() {
  local d; d=$(mktemp -d)
  (
    cd "$d"
    git init -q
    git config user.email "t@t.t"
    git config user.name  "t"
    echo "initial" > README.md
    git add README.md && git commit -qm init
  )
  printf '%s' "$d"
}

# Source quantum-loop.sh in test mode — skips main arg-loop, just defines helpers.
# shellcheck disable=SC1091
QL_AUDIT_TEST_MODE=1 source "$REPO_ROOT/quantum-loop.sh"

echo "=== Phase 44 audit-flag tests ==="

# --- US-001 tests -----------------------------------------------------------

# Test 1: format_row OK shape
echo ""
echo "Test 1: _audit_format_row OK shape"
out=$(_audit_format_row 'branches-local|5|≤10|OK|')
case "$out" in
  *"branches-local:"*"5"*"(target ≤10)"*"OK"*)
    echo "  PASS: format_row OK shape"; PASS=$((PASS + 1));;
  *)
    echo "  FAIL: format_row OK shape — got [$out]"; FAIL=$((FAIL + 1));;
esac
TOTAL=$((TOTAL + 1))

# Test 2: format_row FAIL shape with drill
echo ""
echo "Test 2: _audit_format_row FAIL shape"
out=$(_audit_format_row 'cpc-files|2|0|FAIL|plugin-CPC.json, README-CPC.md')
case "$out" in
  *"cpc-files:"*"FAIL"*"└─"*"plugin-CPC.json"*)
    echo "  PASS: format_row FAIL shape with drill"; PASS=$((PASS + 1));;
  *)
    echo "  FAIL: format_row FAIL shape — got [$out]"; FAIL=$((FAIL + 1));;
esac
TOTAL=$((TOTAL + 1))

# Test 3: format_row FAIL with empty drill — no drill line
echo ""
echo "Test 3: _audit_format_row FAIL empty drill omits drill line"
out=$(_audit_format_row 'x|1|0|FAIL|')
line_count=$(printf '%s' "$out" | awk 'END{print NR}')
assert "empty-drill FAIL = 1 line" "1" "$line_count"

# Test 4: do_audit stub returns 0 and prints header
echo ""
echo "Test 4: do_audit stub happy path"
out=$(do_audit 2>&1)
rc=$?
assert "do_audit exits 0" "0" "$rc"
case "$out" in
  *"=== Quantum-loop audit ==="*"placeholder:"*"Summary:"*)
    echo "  PASS: header + placeholder + summary present"; PASS=$((PASS + 1));;
  *)
    echo "  FAIL: stub output — got [$out]"; FAIL=$((FAIL + 1));;
esac
TOTAL=$((TOTAL + 1))

# Test 5: --audit clean repo exit 0
echo ""
echo "Test 5: --audit clean repo exit 0"
TMP=$(setup_audit_repo)
out=$(cd "$TMP" && bash "$REPO_ROOT/quantum-loop.sh" --audit 2>&1 || true)
rc=$(cd "$TMP" && bash "$REPO_ROOT/quantum-loop.sh" --audit >/dev/null 2>&1 ; echo $?)
TOTAL=$((TOTAL + 1))
if [[ "$rc" -eq 0 ]] && printf '%s' "$out" | grep -q '=== Quantum-loop audit ==='; then
  echo "  PASS: --audit clean repo exit 0"; PASS=$((PASS + 1))
else
  echo "  FAIL: --audit clean repo exit (rc=$rc, out=$out)"; FAIL=$((FAIL + 1))
fi
rm -rf "$TMP"

# Test 6: --audit exclusive-flag guard
echo ""
echo "Test 6: --audit exclusive"
out=$(bash "$REPO_ROOT/quantum-loop.sh" --audit --parallel 2>&1 || true)
rc=$(bash "$REPO_ROOT/quantum-loop.sh" --audit --parallel >/dev/null 2>&1 ; echo $?)
TOTAL=$((TOTAL + 1))
if [[ "$rc" -eq 2 ]] && printf '%s' "$out" | grep -q -- '--audit is exclusive'; then
  echo "  PASS: --audit exclusive exits 2 with clear error"; PASS=$((PASS + 1))
else
  echo "  FAIL: --audit exclusive guard (rc=$rc)"; FAIL=$((FAIL + 1))
fi

echo ""
echo "=== Results: $PASS/$TOTAL passed, $FAIL failed ==="
exit $((FAIL > 0 ? 1 : 0))
