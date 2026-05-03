#!/usr/bin/env bash
# tests/test_loop_helpers.sh
#
# v0.11.4 / US-001 — `lib/loop-helpers.sh::emit_terminal_signal` direct
# test coverage. Closes the LAST MEDIUM coverage gap surfaced by the
# post-v0.11.1 comprehensive-review architect (function called from 5
# production sites in lib/iteration-loop.sh + lib/parallel-mode.sh; zero
# direct tests pre-v0.11.4; formatting regression silently breaks
# parent-agent signal parsing).
#
# Pure shell-function tests; no external CLI required.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$SCRIPT_DIR/.."
LIB="$REPO_ROOT/lib/loop-helpers.sh"
PASS=0
FAIL=0
TOTAL=0

if [[ ! -f "$LIB" ]]; then
  echo "FAIL: $LIB not found"
  exit 1
fi

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

assert_contains() {
  local name="$1" needle="$2" haystack="$3"
  TOTAL=$((TOTAL + 1))
  if printf '%s' "$haystack" | grep -qF -- "$needle"; then
    echo "  PASS: $name"; PASS=$((PASS + 1))
  else
    echo "  FAIL: $name"
    echo "    expected to contain: $needle"
    echo "    actual: $haystack"
    FAIL=$((FAIL + 1))
  fi
}

echo "=== US-001 v0.11.4 emit_terminal_signal direct tests ==="

# ─ Test 1: required signal-name arg (${1:?...} fails on empty) ────────────
echo ""
echo "Test 1: emit_terminal_signal with no args fails (parameter-required guard)"
TOTAL=$((TOTAL + 1))
rc=$(bash -c "set -uo pipefail; source '$LIB'; emit_terminal_signal >/dev/null 2>&1; echo \$?")
if [[ "$rc" != "0" ]]; then
  echo "  PASS: no-args call returned non-zero (rc=$rc; bash parameter-required guard fired)"
  PASS=$((PASS + 1))
else
  echo "  FAIL: no-args call returned 0 (expected non-zero from \${1:?...} guard)"
  FAIL=$((FAIL + 1))
fi

# ─ Test 2: signal-only call (no message) ──────────────────────────────────
echo ""
echo "Test 2: signal-only call emits <quantum>SIGNAL</quantum>"
out2=$(bash -c "source '$LIB' && emit_terminal_signal COMPLETE")
assert_contains "Test 2: output contains <quantum>COMPLETE</quantum>" "<quantum>COMPLETE</quantum>" "$out2"

# ─ Test 3: signal + message call ──────────────────────────────────────────
echo ""
echo "Test 3: signal + message call emits both"
out3=$(bash -c "source '$LIB' && emit_terminal_signal BLOCKED 'No executable stories remain.'")
assert_contains "Test 3a: output contains <quantum>BLOCKED</quantum>" "<quantum>BLOCKED</quantum>" "$out3"
assert_contains "Test 3b: output contains message text" "No executable stories remain." "$out3"

# ─ Test 4: separator wrapping ──────────────────────────────────────────────
echo ""
echo "Test 4: output wrapped in '===' separator lines"
out4=$(bash -c "source '$LIB' && emit_terminal_signal MAX_ITERATIONS")
sep="==========================================="
# Count separator lines: must be exactly 2 (one before, one after).
sep_count=$(printf '%s' "$out4" | grep -cF "$sep")
assert "Test 4: separator-line count is 2" "2" "$sep_count"

# ─ Test 5: all 4 production signals (COMPLETE, BLOCKED, MAX_ITERATIONS, +1) ─
echo ""
echo "Test 5: all production signal names emit correctly"
for sig in COMPLETE BLOCKED MAX_ITERATIONS STORY_PASSED; do
  out=$(bash -c "source '$LIB' && emit_terminal_signal $sig")
  assert_contains "Test 5/$sig: emits <quantum>$sig</quantum>" "<quantum>$sig</quantum>" "$out"
done

# ─ Test 6: no side effects (rc=0; doesn't exit; doesn't modify env) ───────
echo ""
echo "Test 6: pure formatter — rc=0, no exit, no env mutation"
# Capture exit code AND verify subsequent commands run (proves no exit() call).
out6=$(bash -c "
  set -uo pipefail
  source '$LIB'
  emit_terminal_signal COMPLETE 'test message' >/dev/null 2>&1
  rc=\$?
  echo \"after_call_rc=\$rc post_emit_marker=ok\"
")
assert_contains "Test 6a: rc=0 after emit_terminal_signal" "after_call_rc=0" "$out6"
assert_contains "Test 6b: post-emit code ran (no premature exit)" "post_emit_marker=ok" "$out6"

# Verify env unchanged: emit shouldn't modify operator-visible env vars.
TOTAL=$((TOTAL + 1))
out6c=$(bash -c "
  source '$LIB'
  TEST_MARKER=before
  emit_terminal_signal COMPLETE >/dev/null
  echo \"\$TEST_MARKER\"
")
if [[ "$out6c" == "before" ]]; then
  echo "  PASS: Test 6c: env var unchanged after emit_terminal_signal"
  PASS=$((PASS + 1))
else
  echo "  FAIL: Test 6c: env var unexpectedly changed (got: $out6c)"
  FAIL=$((FAIL + 1))
fi

echo ""
echo "=== Results: $PASS/$TOTAL passed, $FAIL failed ==="
[[ $FAIL -eq 0 ]] || exit 1
