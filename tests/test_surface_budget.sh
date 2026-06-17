#!/usr/bin/env bash
# tests/test_surface_budget.sh — Track A / Q3 surface-budget gate tests.

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
    echo "  FAIL: $name (expected [$expected] got [$actual])"; FAIL=$((FAIL + 1))
  fi
}

# shellcheck disable=SC1091
source "$REPO_ROOT/lib/surface-budget.sh"

echo "=== Track A Q3 surface-budget tests ==="

# Test 1: compute_surface counts new file, added lines, and new symbols.
echo ""
echo "Test 1: compute_surface (python new file)"
TEST_TMPDIR=$(mktemp -d)
(
  cd "$TEST_TMPDIR"
  git init -q; git config user.email t@t.t; git config user.name t
  echo "x = 1" > base.py
  git add -A; git commit -qm init
  BASE=$(git rev-parse HEAD)
  cat > new.py << 'PY'
import os


def alpha(x):
    return x + 1


def beta(y):
    return y * 2


class Gamma:
    def method(self):
        return 0
PY
  git add -A; git commit -qm add
  HEAD=$(git rev-parse HEAD)
  compute_surface "$BASE" "$HEAD"
) > "$TEST_TMPDIR/out.json" 2>/dev/null
surface=$(cat "$TEST_TMPDIR/out.json")
assert "newFiles=1"        "1"  "$(jq -r '.newFiles' <<< "$surface")"
assert "newSymbols=4"      "4"  "$(jq -r '.newSymbols' <<< "$surface")"
assert "newAbstractions=0" "0"  "$(jq -r '.newAbstractions' <<< "$surface")"
assert "addedLines=14"     "14" "$(jq -r '.addedLines' <<< "$surface")"
rm -rf "$TEST_TMPDIR"

S='{"newFiles":1,"addedLines":14,"newSymbols":4,"newAbstractions":0}'

# Test 2: check_budget within budget -> rc 0, no breaches.
echo ""
echo "Test 2: check_budget within budget"
out=$(check_budget "$S" '{"maxNewLines":100,"maxNewPublicSymbols":10}'); rc=$?
assert "within: rc=0"        "0"  "$rc"
assert "within: breaches=[]" "[]" "$out"

# Test 3: check_budget over addedLines -> rc 1.
echo ""
echo "Test 3: check_budget over addedLines"
out=$(check_budget "$S" '{"maxNewLines":10}'); rc=$?
assert "over-lines: rc=1"   "1"          "$rc"
assert "over-lines: axis"   "addedLines" "$(jq -r '.[0].axis' <<< "$out")"

# Test 4: check_budget over newPublicSymbols -> rc 1.
echo ""
echo "Test 4: check_budget over newPublicSymbols"
out=$(check_budget "$S" '{"maxNewPublicSymbols":2}'); rc=$?
assert "over-symbols: rc=1"  "1"          "$rc"
assert "over-symbols: axis"  "newSymbols" "$(jq -r '.[0].axis' <<< "$out")"

# Test 5: empty budget = no caps -> rc 0.
echo ""
echo "Test 5: empty budget never breaches"
out=$(check_budget "$S" '{}'); rc=$?
assert "empty-budget: rc=0"        "0"  "$rc"
assert "empty-budget: breaches=[]" "[]" "$out"

# Test 6: gate_budget end-to-end -> breach rc 1.
echo ""
echo "Test 6: gate_budget end-to-end (over budget)"
TEST_TMPDIR=$(mktemp -d)
(
  cd "$TEST_TMPDIR"
  git init -q; git config user.email t@t.t; git config user.name t
  echo "x=1" > base.py; git add -A; git commit -qm init
  BASE=$(git rev-parse HEAD)
  printf 'def f():\n    return 1\n' > big.py
  git add -A; git commit -qm add
  HEAD=$(git rev-parse HEAD)
  gate_budget "$BASE" "$HEAD" '{"maxNewLines":1}' >/dev/null 2>&1
)
gate_rc=$?
assert "gate over-budget rc=1" "1" "$gate_rc"
rm -rf "$TEST_TMPDIR"

# Test 7: abstractions counted (exported TS interface + type alias).
echo ""
echo "Test 7: compute_surface counts abstractions"
TEST_TMPDIR=$(mktemp -d)
(
  cd "$TEST_TMPDIR"
  git init -q; git config user.email t@t.t; git config user.name t
  echo "// base" > base.ts; git add -A; git commit -qm init
  BASE=$(git rev-parse HEAD)
  cat > shape.ts << 'TS'
export interface Foo {
  id: string;
}

export type Bar = { n: number };

export function go(): void {}
TS
  git add -A; git commit -qm add
  HEAD=$(git rev-parse HEAD)
  compute_surface "$BASE" "$HEAD"
) > "$TEST_TMPDIR/o.json" 2>/dev/null
surface=$(cat "$TEST_TMPDIR/o.json")
assert "abstractions=2 (interface + type)" "2" "$(jq -r '.newAbstractions' <<< "$surface")"
rm -rf "$TEST_TMPDIR"

echo ""
echo "=== Results: $PASS/$TOTAL passed, $FAIL failed ==="
exit $((FAIL > 0 ? 1 : 0))
