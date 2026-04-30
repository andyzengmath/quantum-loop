#!/usr/bin/env bash
# tests/test_next_wave.sh
#
# v0.9.0 / US-002 (N42 minor) — unit tests for lib/dag-query.sh::next_wave.
# Mirrors test_dag_query.sh harness pattern.
#
# 8 cases per architect 2 design:
#   1. happy path — single wave from independent stories
#   2. COMPLETE — all stories passed (rc=1)
#   3. BLOCKED — exhausted retries (rc=2)
#   4. file conflict reduces wave to one story
#   5. multi-dependency gate (story X waits on both A AND B)
#   6. in_progress exclusion (status excludes from candidate set)
#   7. in_progress file conflict (cross-wave file claim)
#   8. empty stories array (COMPLETE — jq all() on empty = true)

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB="$SCRIPT_DIR/../lib/dag-query.sh"
PASS=0
FAIL=0
TOTAL=0

if ! command -v jq &>/dev/null; then
  echo "SKIP: jq not found"
  exit 1
fi

if [[ ! -f "$LIB" ]]; then
  echo "SKIP: $LIB not found"
  exit 1
fi
# shellcheck source=/dev/null
source "$LIB"

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
  if echo "$haystack" | grep -qF "$needle"; then
    echo "  PASS: $name"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: $name"
    echo "    expected to contain: $needle"
    echo "    actual: $haystack"
    FAIL=$((FAIL + 1))
  fi
}

echo "=== US-002 v0.9.0 next_wave tests (N42 minor) ==="

TMPD=$(mktemp -d)
trap 'rm -rf "$TMPD"' EXIT

# Common helper: write a quantum.json fixture
write_fixture() {
  local path="$1"
  local content="$2"
  printf '%s\n' "$content" > "$path"
}

# ─ Test 1: happy path — two independent pending stories ────────────────────
echo ""
echo "Test 1: happy path — two independent pending stories returns rc=0 + wave"
write_fixture "$TMPD/q1.json" '{
  "stories": [
    {"id": "US-001", "status": "pending", "priority": 1, "dependsOn": [], "tasks": [{"filePaths": ["a.sh"]}], "retries": {"attempts": 0, "maxAttempts": 3}},
    {"id": "US-002", "status": "pending", "priority": 2, "dependsOn": [], "tasks": [{"filePaths": ["b.sh"]}], "retries": {"attempts": 0, "maxAttempts": 3}}
  ],
  "fileConflicts": []
}'
out=$(next_wave "$TMPD/q1.json"); rc=$?
assert_eq "Test 1: rc=0" "0" "$rc"
assert_contains "Test 1: wave includes US-001" "US-001" "$out"
assert_contains "Test 1: wave includes US-002" "US-002" "$out"

# ─ Test 2: COMPLETE — all stories passed → rc=1 ────────────────────────────
echo ""
echo "Test 2: COMPLETE — all stories passed returns rc=1, no stdout"
write_fixture "$TMPD/q2.json" '{
  "stories": [
    {"id": "US-001", "status": "passed", "priority": 1, "dependsOn": [], "tasks": [], "retries": {"attempts": 0, "maxAttempts": 3}}
  ],
  "fileConflicts": []
}'
out=$(next_wave "$TMPD/q2.json"); rc=$?
assert_eq "Test 2: rc=1 (COMPLETE)" "1" "$rc"
assert_eq "Test 2: no stdout output" "" "$out"

# ─ Test 3: BLOCKED — exhausted retries on dep gate → rc=2 ──────────────────
echo ""
echo "Test 3: BLOCKED — failed story (retries exhausted) blocks dependent → rc=2"
write_fixture "$TMPD/q3.json" '{
  "stories": [
    {"id": "US-001", "status": "failed", "priority": 1, "dependsOn": [], "tasks": [], "retries": {"attempts": 3, "maxAttempts": 3}},
    {"id": "US-002", "status": "pending", "priority": 2, "dependsOn": ["US-001"], "tasks": [], "retries": {"attempts": 0, "maxAttempts": 3}}
  ],
  "fileConflicts": []
}'
out=$(next_wave "$TMPD/q3.json"); rc=$?
assert_eq "Test 3: rc=2 (BLOCKED)" "2" "$rc"
assert_eq "Test 3: no stdout output" "" "$out"

# ─ Test 4: file conflict reduces wave to one story ──────────────────────────
echo ""
echo "Test 4: file conflict — three pending stories on same file → wave=1"
write_fixture "$TMPD/q4.json" '{
  "stories": [
    {"id": "US-001", "status": "pending", "priority": 1, "dependsOn": [], "tasks": [{"filePaths": ["shared.sh"]}], "retries": {"attempts": 0, "maxAttempts": 3}},
    {"id": "US-002", "status": "pending", "priority": 2, "dependsOn": [], "tasks": [{"filePaths": ["shared.sh"]}], "retries": {"attempts": 0, "maxAttempts": 3}},
    {"id": "US-003", "status": "pending", "priority": 3, "dependsOn": [], "tasks": [{"filePaths": ["shared.sh"]}], "retries": {"attempts": 0, "maxAttempts": 3}}
  ],
  "fileConflicts": []
}'
out=$(next_wave "$TMPD/q4.json"); rc=$?
assert_eq "Test 4: rc=0" "0" "$rc"
wave_len=$(echo "$out" | jq 'length')
assert_eq "Test 4: wave length=1 (highest priority only)" "1" "$wave_len"
assert_contains "Test 4: highest-priority US-001 in wave" "US-001" "$out"

# ─ Test 5: multi-dependency gate ────────────────────────────────────────────
echo ""
echo "Test 5: multi-dependency — X depends on A AND B; if B pending, X excluded"
write_fixture "$TMPD/q5.json" '{
  "stories": [
    {"id": "A", "status": "passed", "priority": 1, "dependsOn": [], "tasks": [], "retries": {"attempts": 0, "maxAttempts": 3}},
    {"id": "B", "status": "pending", "priority": 2, "dependsOn": [], "tasks": [{"filePaths": ["b.sh"]}], "retries": {"attempts": 0, "maxAttempts": 3}},
    {"id": "X", "status": "pending", "priority": 3, "dependsOn": ["A", "B"], "tasks": [{"filePaths": ["x.sh"]}], "retries": {"attempts": 0, "maxAttempts": 3}}
  ],
  "fileConflicts": []
}'
out=$(next_wave "$TMPD/q5.json"); rc=$?
assert_eq "Test 5: rc=0" "0" "$rc"
TOTAL=$((TOTAL + 1))
if echo "$out" | grep -qF '"X"'; then
  echo "  FAIL: X is in wave (should NOT be — B not yet passed)"; FAIL=$((FAIL + 1))
else
  echo "  PASS: X correctly excluded (B not yet passed)"; PASS=$((PASS + 1))
fi
assert_contains "Test 5: B in wave" "B" "$out"

# ─ Test 6: in_progress exclusion ────────────────────────────────────────────
echo ""
echo "Test 6: in_progress story A excluded; B (depends on A) excluded; C eligible"
write_fixture "$TMPD/q6.json" '{
  "stories": [
    {"id": "A", "status": "in_progress", "priority": 1, "dependsOn": [], "tasks": [{"filePaths": ["a.sh"]}], "retries": {"attempts": 0, "maxAttempts": 3}},
    {"id": "B", "status": "pending", "priority": 2, "dependsOn": ["A"], "tasks": [{"filePaths": ["b.sh"]}], "retries": {"attempts": 0, "maxAttempts": 3}},
    {"id": "C", "status": "pending", "priority": 3, "dependsOn": [], "tasks": [{"filePaths": ["c.sh"]}], "retries": {"attempts": 0, "maxAttempts": 3}}
  ],
  "fileConflicts": []
}'
out=$(next_wave "$TMPD/q6.json"); rc=$?
assert_eq "Test 6: rc=0" "0" "$rc"
assert_contains "Test 6: C in wave" "C" "$out"
TOTAL=$((TOTAL + 1))
if echo "$out" | grep -qF '"A"'; then
  echo "  FAIL: A is in wave (in_progress should be excluded)"; FAIL=$((FAIL + 1))
else
  echo "  PASS: A correctly excluded (in_progress)"; PASS=$((PASS + 1))
fi

# ─ Test 7: in_progress file conflict (cross-wave) ───────────────────────────
echo ""
echo "Test 7: in_progress A claims shared file; B blocked despite DAG-eligibility"
write_fixture "$TMPD/q7.json" '{
  "stories": [
    {"id": "A", "status": "in_progress", "priority": 1, "dependsOn": [], "tasks": [{"filePaths": ["src/x.ts"]}], "retries": {"attempts": 0, "maxAttempts": 3}},
    {"id": "B", "status": "pending", "priority": 2, "dependsOn": [], "tasks": [{"filePaths": ["src/x.ts"]}], "retries": {"attempts": 0, "maxAttempts": 3}}
  ],
  "fileConflicts": []
}'
out=$(next_wave "$TMPD/q7.json"); rc=$?
assert_eq "Test 7: rc=2 (BLOCKED — only candidate B conflicts with A in_progress)" "2" "$rc"

# ─ Test 8: empty stories array ──────────────────────────────────────────────
echo ""
echo "Test 8: empty stories array → COMPLETE (jq all() on empty = true)"
write_fixture "$TMPD/q8.json" '{"stories": [], "fileConflicts": []}'
out=$(next_wave "$TMPD/q8.json"); rc=$?
assert_eq "Test 8: rc=1 (COMPLETE on empty stories)" "1" "$rc"

echo ""
echo "=== Results: $PASS/$TOTAL passed, $FAIL failed ==="
if (( FAIL > 0 )); then
  exit 1
fi
exit 0
