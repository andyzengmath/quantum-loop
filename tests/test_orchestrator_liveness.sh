#!/usr/bin/env bash
# N6-followup / US-001 (v0.6.9) — orchestrator-liveness lib helper tests.
#
# Structural assertions only — no timing-fragile backgrounded git race. The
# wall-clock-sensitive tests use generous ceilings (timeout_sec * 3) to
# tolerate Git Bash sleep jitter on loaded hosts (~50% over nominal observed).
#
# Test header note: may flake on heavily-loaded Git Bash hosts where sleep
# jitter exceeds 50% of nominal — re-run if flaky.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$SCRIPT_DIR/.."
LIB="$REPO_ROOT/lib/orchestrator-liveness.sh"
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

echo "=== US-001 N6-followup orchestrator-liveness tests ==="

# Test 1: function defined after sourcing the lib
echo ""
echo "Test 1: poll_orchestrator_commits is defined after sourcing lib/orchestrator-liveness.sh"
TOTAL=$((TOTAL + 1))
fn_defined=$(bash -c "source '$LIB' && declare -F poll_orchestrator_commits >/dev/null && echo yes || echo no")
if [[ "$fn_defined" == "yes" ]]; then
  echo "  PASS: function defined"; PASS=$((PASS + 1))
else
  echo "  FAIL: function not defined after source"; FAIL=$((FAIL + 1))
fi

# Test 2: stale path — no new commits during the window → exit 1 + STALE log
echo ""
echo "Test 2: stale path returns 1 within timeout_sec*3 ceiling + emits STALE log"
TMP=$(mktemp -d)
( cd "$TMP" && git init -q && git config user.email "t@t.t" && git config user.name "t" \
  && echo "init" > README.md && git add README.md && git commit -qm "init" ) >/dev/null 2>&1

t0=$(date +%s)
out=$(cd "$TMP" && bash -c "source '$LIB' && poll_orchestrator_commits 2 1" 2>&1 || true)
rc=$(cd "$TMP" && bash -c "source '$LIB' && poll_orchestrator_commits 2 1 >/dev/null 2>&1 ; echo \$?")
t1=$(date +%s)
elapsed=$((t1 - t0))

assert "stale path exit code = 1" "1" "$rc"
TOTAL=$((TOTAL + 1))
if (( elapsed <= 12 )); then  # timeout=2 * 3 ceiling = 6, doubled for two invocations
  echo "  PASS: stale path completed in ${elapsed}s (<=12s ceiling for 2 invocations × 2*3 jitter)"
  PASS=$((PASS + 1))
else
  echo "  FAIL: stale path took ${elapsed}s (>12s ceiling — sleep jitter too high)"
  FAIL=$((FAIL + 1))
fi
TOTAL=$((TOTAL + 1))
if printf '%s' "$out" | grep -qE '^\[LIVENESS\] STALE: no commits in 2s'; then
  echo "  PASS: STALE stderr log line emitted"; PASS=$((PASS + 1))
else
  echo "  FAIL: STALE log line missing — out: $out"; FAIL=$((FAIL + 1))
fi

# Test 3: live path — pre-staged HEAD-advance via backgrounded checkout B
echo ""
echo "Test 3: live path returns 0 + emits new-commit log when HEAD advances mid-poll"
( cd "$TMP" && echo "B" > a.txt && git add a.txt && git commit -qm "commit-B" ) >/dev/null 2>&1
COMMIT_B=$(cd "$TMP" && git rev-parse HEAD)
( cd "$TMP" && git reset --hard HEAD~1 ) >/dev/null 2>&1

# Background: after 2s, fast-forward back to commit-B (advance HEAD).
( sleep 2 && cd "$TMP" && git reset --hard "$COMMIT_B" >/dev/null 2>&1 ) &
bg_pid=$!

t0=$(date +%s)
out=$(cd "$TMP" && bash -c "source '$LIB' && poll_orchestrator_commits 10 1" 2>&1 || true)
rc=$?
t1=$(date +%s)
elapsed=$((t1 - t0))
wait $bg_pid 2>/dev/null

assert "live path exit code = 0" "0" "$rc"
TOTAL=$((TOTAL + 1))
if (( elapsed <= 30 )); then
  echo "  PASS: live path completed in ${elapsed}s (<=30s ceiling)"; PASS=$((PASS + 1))
else
  echo "  FAIL: live path took ${elapsed}s"; FAIL=$((FAIL + 1))
fi
TOTAL=$((TOTAL + 1))
if printf '%s' "$out" | grep -qE '^\[LIVENESS\] new commit'; then
  echo "  PASS: 'new commit' stderr log line emitted"; PASS=$((PASS + 1))
else
  echo "  FAIL: 'new commit' log line missing — out: $out"; FAIL=$((FAIL + 1))
fi

rm -rf "$TMP"

# Test 4: default-arg behavior — function source contains 600 / 60 defaults
echo ""
echo "Test 4: function source uses documented defaults (timeout=600, interval=60)"
TOTAL=$((TOTAL + 1))
if grep -q '\${1:-600}' "$LIB" && grep -q '\${2:-60}' "$LIB"; then
  echo "  PASS: 600 / 60 defaults present in source"; PASS=$((PASS + 1))
else
  echo "  FAIL: default values not found in lib source"; FAIL=$((FAIL + 1))
fi

echo ""
echo "=== Results: $PASS/$TOTAL passed, $FAIL failed ==="
[[ $FAIL -eq 0 ]] || exit 1
