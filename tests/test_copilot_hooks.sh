#!/usr/bin/env bash
# tests/test_copilot_hooks.sh
#
# v0.11.3 / US-001 — `runners/hooks/copilot-hooks.sh::post_output` test
# coverage. Closes the MEDIUM coverage gap surfaced by the post-v0.11.1
# comprehensive-review critic.
#
# Pure string-parsing tests; no copilot CLI required (cf.
# tests/test_copilot_dispatch.sh which IS skip-aware on real CLI).
# Tests source the hooks file directly and invoke post_output() with
# hand-crafted output strings, capturing the [RATE-LIMIT] stderr
# emissions for assertion.
#
# Coverage scope:
#   - 5 rate-limit detection patterns (rate-limit, 429, Retry-After,
#     quota-exceeded, too many requests)
#   - 4 Retry-After extraction cases (single-line, HTTP/1.1 prefix,
#     folded-header form, digit-mix continuation)
#   - 2 negative cases (no rate-limit; idempotency)

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$SCRIPT_DIR/.."
HOOKS="$REPO_ROOT/runners/hooks/copilot-hooks.sh"
PASS=0
FAIL=0
TOTAL=0

if [[ ! -f "$HOOKS" ]]; then
  echo "FAIL: $HOOKS not found"
  exit 1
fi

assert_emits_ratelimit() {
  local name="$1" input="$2"
  TOTAL=$((TOTAL + 1))
  local out
  out=$(bash -c "source '$HOOKS' && post_output \"\$1\"" -- "$input" 2>&1)
  if printf '%s' "$out" | grep -qF "[RATE-LIMIT] copilot rate-limit detected:"; then
    echo "  PASS: $name"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: $name"
    echo "    expected stderr to contain '[RATE-LIMIT] copilot rate-limit detected:'"
    echo "    actual: $out"
    FAIL=$((FAIL + 1))
  fi
}

assert_no_ratelimit() {
  local name="$1" input="$2"
  TOTAL=$((TOTAL + 1))
  local out
  out=$(bash -c "source '$HOOKS' && post_output \"\$1\"" -- "$input" 2>&1)
  if ! printf '%s' "$out" | grep -qF "[RATE-LIMIT]"; then
    echo "  PASS: $name"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: $name (false positive — should NOT emit)"
    echo "    actual: $out"
    FAIL=$((FAIL + 1))
  fi
}

assert_retry_after() {
  local name="$1" input="$2" expected="$3"
  TOTAL=$((TOTAL + 1))
  local out
  out=$(bash -c "source '$HOOKS' && post_output \"\$1\"" -- "$input" 2>&1)
  local actual
  actual=$(printf '%s' "$out" | sed -n 's/.*\[RATE-LIMIT\] copilot suggests Retry-After: \([0-9][0-9]*\)s.*/\1/p' | head -1)
  if [[ "$actual" == "$expected" ]]; then
    echo "  PASS: $name (extracted $expected)"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: $name"
    echo "    expected Retry-After: ${expected}s; actual extraction: '$actual'"
    echo "    full output: $out"
    FAIL=$((FAIL + 1))
  fi
}

echo "=== US-001 v0.11.3 copilot-hooks::post_output tests ==="

# ─ Rate-limit pattern detection (5 patterns) ──────────────────────────────
echo ""
echo "Rate-limit pattern detection:"
assert_emits_ratelimit "Test 1: 'rate-limit' substring" "Error: rate-limit hit on this request"
assert_emits_ratelimit "Test 2: HTTP 429 word-boundary" "Error response: 429 Too Many Requests"
assert_emits_ratelimit "Test 3: 'Retry-After' header keyword" "HTTP/1.1 429
Retry-After: 30"
assert_emits_ratelimit "Test 4: 'quota-exceeded' kebab-case" "Error: quota-exceeded for this user"
assert_emits_ratelimit "Test 5: 'too many requests' (case-insensitive)" "TOO MANY REQUESTS — please retry"

# ─ Retry-After extraction (4 cases) ───────────────────────────────────────
echo ""
echo "Retry-After extraction:"
assert_retry_after "Test 6: single-line 'Retry-After: 30'" "rate-limit error
Retry-After: 30" "30"
assert_retry_after "Test 7: HTTP/1.1 prefix anchor (v0.10.7 fix)" "HTTP/1.1 429 Retry-After: 60
quota exceeded" "60"
assert_retry_after "Test 8: folded-header form (v0.10.13 fallback)" "rate-limit
Retry-After:
   45" "45"
assert_retry_after "Test 9: digit-mix continuation (v0.10.13 match/substr fix)" "rate-limit
Retry-After:
   30 something 99" "30"

# ─ Negative + idempotency cases ───────────────────────────────────────────
echo ""
echo "Negative + idempotency:"
assert_no_ratelimit "Test 10: benign output (no rate-limit keywords)" "All systems operational. Reply with the word OK."

# Test 11: idempotency — multiple rate-limit lines should emit ONCE
echo ""
TOTAL=$((TOTAL + 1))
out11=$(bash -c "source '$HOOKS' && post_output \"\$1\"" -- "rate-limit hit on request 1
rate-limit hit on request 2
rate-limit hit on request 3" 2>&1)
emit_count=$(printf '%s' "$out11" | grep -cF "[RATE-LIMIT] copilot rate-limit detected:")
if [[ "$emit_count" == "1" ]]; then
  echo "  PASS: Test 11: idempotency — emits once for multiple matches (count=$emit_count)"
  PASS=$((PASS + 1))
else
  echo "  FAIL: Test 11: idempotency — expected 1 emission, got $emit_count"
  echo "    output: $out11"
  FAIL=$((FAIL + 1))
fi

echo ""
echo "=== Results: $PASS/$TOTAL passed, $FAIL failed ==="
[[ $FAIL -eq 0 ]] || exit 1
