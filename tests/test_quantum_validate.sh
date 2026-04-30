#!/usr/bin/env bash
# tests/test_quantum_validate.sh
#
# v0.9.2 / US-003 — regression guard for lib/quantum-validate.sh.
#
# Closes v0.9.1 architect MEDIUM (US-004 review): stories with empty
# `filePaths` arrays silently bypass `filter_file_conflicts` in
# `lib/dag-query.sh`. Operator PRDs under time pressure may omit
# `filePaths`. Result: silent conflict-filter bypass.
#
# `validate_story_filepaths` is advisory-only: emits stderr warnings;
# never blocks. Wired into `next_wave`'s preamble.
#
# 5 cases (≥3 per PRD AC):
#   1. story with non-empty filePaths → no warning
#   2. story with empty filePaths → warning matching pattern
#   3. story with no tasks → warning fires
#   4. CLI entry-point works
#   5. missing file arg fails fast

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$SCRIPT_DIR/.."
VALIDATE_LIB="$REPO_ROOT/lib/quantum-validate.sh"

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

assert_not_contains() {
  local name="$1" needle="$2" haystack="$3"
  TOTAL=$((TOTAL + 1))
  if echo "$haystack" | grep -qF -- "$needle"; then
    echo "  FAIL: $name"
    echo "    expected to NOT contain: $needle"
    echo "    actual: $haystack"
    FAIL=$((FAIL + 1))
  else
    echo "  PASS: $name"
    PASS=$((PASS + 1))
  fi
}

echo "=== US-003 v0.9.2 quantum-validate tests ==="

if [[ ! -f "$VALIDATE_LIB" ]]; then
  echo "FAIL: $VALIDATE_LIB does not exist (RED phase or missing implementation)"
  exit 1
fi

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

# shellcheck source=lib/quantum-validate.sh
source "$VALIDATE_LIB"

# ─ Test 1: story with non-empty filePaths → no warning ─────────────────────
echo
echo "Test 1: story with non-empty filePaths emits no warning"
cat > "$TMP/q1.json" << 'EOF'
{"stories": [{"id":"US-A","status":"pending","tasks":[{"filePaths":["a.txt"]}]}]}
EOF
out=$(validate_story_filepaths "$TMP/q1.json" 2>&1)
rc=$?
assert_eq "Test 1: rc=0" "0" "$rc"
assert_eq "Test 1: no warning emitted" "" "$out"

# ─ Test 2: story with empty filePaths → warning ────────────────────────────
echo
echo "Test 2: story with empty filePaths emits warning"
cat > "$TMP/q2.json" << 'EOF'
{"stories": [{"id":"US-A","status":"pending","tasks":[{"filePaths":[]}]}]}
EOF
out=$(validate_story_filepaths "$TMP/q2.json" 2>&1)
rc=$?
assert_eq "Test 2: rc=0 (advisory; never blocks)" "0" "$rc"
assert_contains "Test 2: stderr WARNING about US-A" "WARNING: Story US-A has no filePaths" "$out"

# ─ Test 3: story with no tasks → warning fires ─────────────────────────────
echo
echo "Test 3: story with no tasks emits warning"
cat > "$TMP/q3.json" << 'EOF'
{"stories": [{"id":"US-B","status":"pending","tasks":[]}]}
EOF
out=$(validate_story_filepaths "$TMP/q3.json" 2>&1)
rc=$?
assert_eq "Test 3: rc=0" "0" "$rc"
assert_contains "Test 3: stderr WARNING about US-B" "WARNING: Story US-B has no filePaths" "$out"

# ─ Test 4: passed story with empty filePaths → NO warning (not eligible) ──
echo
echo "Test 4: status=passed stories not warned about (only eligible statuses)"
cat > "$TMP/q4.json" << 'EOF'
{"stories": [{"id":"US-DONE","status":"passed","tasks":[]}, {"id":"US-PEND","status":"pending","tasks":[{"filePaths":["a.txt"]}]}]}
EOF
out=$(validate_story_filepaths "$TMP/q4.json" 2>&1)
rc=$?
assert_eq "Test 4: rc=0" "0" "$rc"
assert_not_contains "Test 4: no warning for passed story US-DONE" "Story US-DONE" "$out"
assert_not_contains "Test 4: no warning for compliant pending US-PEND" "Story US-PEND" "$out"

# ─ Test 5: CLI entry-point + missing arg ───────────────────────────────────
echo
echo "Test 5: CLI entry-point + missing arg fails fast"
out=$(bash "$VALIDATE_LIB" validate_story_filepaths "$TMP/q1.json" 2>&1)
rc=$?
assert_eq "Test 5: CLI rc=0 on valid call" "0" "$rc"
out=$(bash "$VALIDATE_LIB" validate_story_filepaths 2>&1)
rc=$?
if [[ "$rc" -ne 0 ]]; then
  TOTAL=$((TOTAL + 1)); PASS=$((PASS + 1))
  echo "  PASS: Test 5: missing arg rc != 0 (got $rc)"
else
  TOTAL=$((TOTAL + 1)); FAIL=$((FAIL + 1))
  echo "  FAIL: Test 5: missing arg should fail (got rc=$rc)"
fi

echo
echo "=== Results: $PASS/$TOTAL passed, $FAIL failed ==="
[[ "$FAIL" -eq 0 ]]
