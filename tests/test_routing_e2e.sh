#!/usr/bin/env bash
# US-002 (v0.7.4) — provider-routing E2E lifecycle test.
#
# Exercises resolve_routing -> write_routing_snapshot -> read_routing_snapshot
# round-trip end-to-end. Complements the unit-level tests in
# test_per_role_routing.sh (function presence + JSON shape) and the
# integration tests in test_per_role_routing_integration.sh.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$SCRIPT_DIR/.."
RUNNER="$REPO_ROOT/lib/runner.sh"
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

echo "=== US-002 v0.7.4 provider-routing E2E tests ==="

# Test 1: resolve_routing with claude/auto/auto returns well-shaped snapshot
echo ""
echo "Test 1: resolve_routing claude auto auto -> JSON with planner/critic/executor + resolvedAt"
TMP1=$(mktemp -d)
out1=$(bash -c "source '$RUNNER' && resolve_routing claude auto auto" 2>/dev/null)
TOTAL=$((TOTAL + 1))
if printf '%s' "$out1" | jq -e '.planner and .critic and .executor and .resolvedAt' >/dev/null 2>&1; then
  echo "  PASS: resolve_routing emits planner/critic/executor/resolvedAt JSON"; PASS=$((PASS + 1))
else
  echo "  FAIL: resolve_routing JSON malformed — out: $out1"; FAIL=$((FAIL + 1))
fi
TOTAL=$((TOTAL + 1))
planner1=$(printf '%s' "$out1" | jq -r '.planner')
if [[ "$planner1" == "claude" ]]; then
  echo "  PASS: planner=claude resolved as claude"; PASS=$((PASS + 1))
else
  echo "  FAIL: planner expected claude got $planner1"; FAIL=$((FAIL + 1))
fi
rm -rf "$TMP1"

# Test 2: round-trip write -> read snapshot
echo ""
echo "Test 2: write_routing_snapshot then read_routing_snapshot round-trip"
TMP2=$(mktemp -d)
echo '{"stories":[]}' > "$TMP2/quantum.json"
out2_resolve=$(bash -c "source '$RUNNER' && resolve_routing claude auto auto" 2>/dev/null)
bash -c "source '$RUNNER' && write_routing_snapshot '$TMP2/quantum.json' '$out2_resolve'" 2>&1 >/dev/null
out2_read=$(bash -c "source '$RUNNER' && read_routing_snapshot '$TMP2/quantum.json'" 2>/dev/null)
TOTAL=$((TOTAL + 1))
if printf '%s' "$out2_read" | jq -e '.planner == "claude"' >/dev/null 2>&1; then
  echo "  PASS: round-trip preserved .planner=claude"; PASS=$((PASS + 1))
else
  echo "  FAIL: round-trip lost or mutated planner — read: $out2_read"; FAIL=$((FAIL + 1))
fi
TOTAL=$((TOTAL + 1))
if printf '%s' "$out2_read" | jq -e '.resolvedAt' >/dev/null 2>&1; then
  echo "  PASS: round-trip preserved .resolvedAt"; PASS=$((PASS + 1))
else
  echo "  FAIL: round-trip lost .resolvedAt"; FAIL=$((FAIL + 1))
fi
rm -rf "$TMP2"

# Test 3: read_routing_snapshot on quantum.json without .routing returns {}
echo ""
echo "Test 3: read_routing_snapshot on quantum.json without .routing returns {}"
TMP3=$(mktemp -d)
echo '{"stories":[]}' > "$TMP3/quantum.json"
out3=$(bash -c "source '$RUNNER' && read_routing_snapshot '$TMP3/quantum.json'" 2>/dev/null)
assert "Test 3: empty .routing returns {}" "{}" "$out3"
rm -rf "$TMP3"

# Test 4: read_routing_snapshot on missing file returns {}
echo ""
echo "Test 4: read_routing_snapshot on missing quantum.json returns {}"
out4=$(bash -c "source '$RUNNER' && read_routing_snapshot '/tmp/nonexistent-quantum-$(date +%s).json'" 2>/dev/null)
assert "Test 4: missing file returns {}" "{}" "$out4"

echo ""
echo "=== Results: $PASS/$TOTAL passed, $FAIL failed ==="
[[ $FAIL -eq 0 ]] || exit 1
