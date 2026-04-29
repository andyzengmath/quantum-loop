#!/usr/bin/env bash
# tests/test_v081_wiring.sh
#
# v0.8.1 / US-001 (N39 dogfood) — verifies the v0.8.0 recovery infrastructure
# is actually CALLED in production (not just defined). v0.8.0 shipped
# ql_wrap_subagent_dispatch and COORDINATOR_MODE with presence-only ACs;
# v0.8.1 dogfood found both were inert. These tests protect against the
# regression repeating.
#
# Anti-pattern guarded against: "function defined" != "function called".
#
# Tests:
#   1. quantum-loop.sh has a non-trivial caller of ql_wrap_subagent_dispatch
#      (i.e. the function is invoked from within the dispatch loop, not
#      merely defined as a wrapper).
#   2. quantum-loop.sh consults $COORDINATOR_MODE at least once outside of
#      flag-parsing assignment (i.e. the flag has a runtime effect).
#   3. The COORDINATOR_MODE=true path emits a recognizable WARN to stderr.
#   4. quantum-loop.sh --coordinator parses without error and triggers the
#      WARN (smoke check on the actual binary).

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
QUANTUM_LOOP="$SCRIPT_DIR/../quantum-loop.sh"
PASS=0
FAIL=0

if [[ ! -f "$QUANTUM_LOOP" ]]; then
  echo "SKIP: quantum-loop.sh not found at $QUANTUM_LOOP"
  exit 1
fi

assert() {
  local name="$1" expected="$2" actual="$3"
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

echo "=== US-001 v0.8.1 wiring tests (N39 dogfood) ==="

# Test 1: ql_wrap_subagent_dispatch is invoked (not just defined) within
# quantum-loop.sh. Specifically, look for a call site outside the function
# definition itself.
echo ""
echo "Test 1: ql_wrap_subagent_dispatch has a non-trivial caller in quantum-loop.sh"
# Count call sites: grep for the function name followed by a numeric arg or
# whitespace+arg (caller pattern), excluding the function-definition line.
caller_count=$(grep -cE 'ql_wrap_subagent_dispatch [0-9"]' "$QUANTUM_LOOP" || true)
if (( caller_count >= 1 )); then
  echo "  PASS: at least 1 caller of ql_wrap_subagent_dispatch found ($caller_count)"
  PASS=$((PASS + 1))
else
  echo "  FAIL: ql_wrap_subagent_dispatch has zero callers — regression to N33 root cause #1"
  FAIL=$((FAIL + 1))
fi

# Test 1b: the caller's guard must be REACHABLE. v0.8.1 PR-review caught a
# regression: original guard was `[[ -z "$SIGNAL_RESULT" ]]` which is always
# false (runner_parse_output always sets SIGNAL_RESULT). The corrected guard
# fires on STORY_FAILED with non-exact confidence. This test asserts the
# guard is NOT the dead `-z SIGNAL_RESULT` form.
echo ""
echo "Test 1b: ql_wrap_subagent_dispatch guard is reachable (not the dead -z SIGNAL_RESULT form)"
# Find the guard line preceding the caller. If it's the dead `-z` form, fail.
dead_guard=$(grep -B 1 'ql_wrap_subagent_dispatch [0-9"]' "$QUANTUM_LOOP" 2>/dev/null | grep -cE '\[\[ -z "?\$\{?SIGNAL_RESULT' || true)
reachable_guard=$(grep -B 1 'ql_wrap_subagent_dispatch [0-9"]' "$QUANTUM_LOOP" 2>/dev/null | grep -cE 'SIGNAL_RESULT.*==.*STORY_FAILED|SIGNAL_RESULT.*!=.*STORY_PASSED' || true)
if (( dead_guard == 0 && reachable_guard >= 1 )); then
  echo "  PASS: guard fires on a runtime-reachable condition (no dead -z guard)"
  PASS=$((PASS + 1))
else
  echo "  FAIL: guard appears to be the dead -z SIGNAL_RESULT form (dead=$dead_guard, reachable=$reachable_guard)"
  FAIL=$((FAIL + 1))
fi

# Test 2: $COORDINATOR_MODE is consulted (not just assigned).
echo ""
echo "Test 2: COORDINATOR_MODE is consulted (read) outside of flag-parsing assignment"
# Look for $COORDINATOR_MODE usage in a conditional (== / != / -z / -n).
read_count=$(grep -cE '\$COORDINATOR_MODE.*==|\$COORDINATOR_MODE.*!=|\[\[ "?\$\{?COORDINATOR_MODE' "$QUANTUM_LOOP" || true)
if (( read_count >= 1 )); then
  echo "  PASS: COORDINATOR_MODE consulted in conditional ($read_count site)"
  PASS=$((PASS + 1))
else
  echo "  FAIL: COORDINATOR_MODE is set but never read — flag is inert"
  FAIL=$((FAIL + 1))
fi

# Test 3: The COORDINATOR_MODE=true path emits a recognizable WARN.
echo ""
echo "Test 3: COORDINATOR_MODE=true branch emits WARN"
warn_present=$(grep -cE 'WARN:.*--coordinator|coordinator.*not.*wired|coordinator.*not yet' "$QUANTUM_LOOP" || true)
if (( warn_present >= 1 )); then
  echo "  PASS: WARN message present in source ($warn_present occurrence)"
  PASS=$((PASS + 1))
else
  echo "  FAIL: COORDINATOR_MODE=true branch silently falls through — operators won't notice the flag is inert"
  FAIL=$((FAIL + 1))
fi

# Test 4: Smoke — running with --coordinator (and a minimal quantum.json
# stub in a tmp dir) actually emits the WARN to stderr. This proves the
# wire is reachable from the CLI, not just present in the source.
echo ""
echo "Test 4: quantum-loop.sh --coordinator emits WARN to stderr (smoke)"
TMPD=$(mktemp -d)
cat > "$TMPD/quantum.json" << 'JSON_EOF'
{"prdPath": "p.md", "branchName": "test-branch", "progress": [], "stories": []}
JSON_EOF
echo "stub" > "$TMPD/p.md"
( cd "$TMPD" && git init -q && git add . && git config user.email "t@t.t" && git config user.name "t" && git commit -qm "init" ) >/dev/null 2>&1
# Run with --coordinator + -t claude. Even if the dispatch fails downstream,
# the WARN should fire BEFORE any dispatch.
out=$(cd "$TMPD" && bash "$QUANTUM_LOOP" --coordinator --tool claude --max-iterations 0 2>&1 || true)
if printf '%s' "$out" | grep -q 'WARN.*coordinator.*not.*wired\|WARN.*--coordinator.*not yet'; then
  echo "  PASS: WARN fired on actual --coordinator invocation"
  PASS=$((PASS + 1))
else
  echo "  FAIL: WARN did not fire — last 5 lines of output:"
  printf '%s\n' "$out" | tail -5 | sed 's/^/    /'
  FAIL=$((FAIL + 1))
fi
rm -rf "$TMPD"

echo ""
TOTAL=$((PASS + FAIL))
echo "=== Results: $PASS/$TOTAL passed, $FAIL failed ==="
if (( FAIL > 0 )); then
  exit 1
fi
exit 0
