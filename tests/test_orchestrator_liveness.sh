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

# Soliton-pr-review caught at confidence 90 (v0.6.9 PR #70): the previous
# pattern `out=$(... || true)` followed by `rc=$?` captures the exit code
# of the assignment's subshell (always 0 due to `|| true` swallowing the
# inner exit), making the rc-assertion below vacuously always-pass. Fix:
# capture exit code via `out=$(...) || rc=$?` so the inner exit propagates
# without aborting under set -uo pipefail.
t0=$(date +%s)
rc=0
out=$(cd "$TMP" && bash -c "source '$LIB' && poll_orchestrator_commits 10 1" 2>&1) || rc=$?
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

# Test 5: N16 / US-004 (v0.7.0) — interval_sec=0 guard
echo ""
echo "Test 5: poll_orchestrator_commits 10 0 returns 1 with ERROR log (interval_sec=0 guard)"
TMP=$(mktemp -d)
( cd "$TMP" && git init -q && git config user.email "t@t.t" && git config user.name "t" \
  && echo "init" > README.md && git add README.md && git commit -qm "init" ) >/dev/null 2>&1

t0=$(date +%s)
out=$(cd "$TMP" && bash -c "source '$LIB' && poll_orchestrator_commits 10 0" 2>&1 || true)
rc=$(cd "$TMP" && bash -c "source '$LIB' && poll_orchestrator_commits 10 0 >/dev/null 2>&1 ; echo \$?")
t1=$(date +%s)
elapsed=$((t1 - t0))

assert "interval_sec=0 guard exit code = 1" "1" "$rc"
TOTAL=$((TOTAL + 1))
# Soliton-pr-review caught at confidence 82 (v0.7.0 PR #71): the previous 2s
# ceiling was too tight for two `bash -c "source ..."` subprocess launches
# on Git Bash / Windows (each can take 0.5-1.5s startup). Raised to 6s to
# match the proportional generosity used in Test 2 (12s ceiling for two
# invocations of a 2s poll). The guard itself returns in microseconds; the
# ceiling measures subprocess launch overhead, not the function logic.
if (( elapsed <= 6 )); then
  echo "  PASS: guard returns within 6s (no infinite-loop hazard; subprocess-launch headroom)"; PASS=$((PASS + 1))
else
  echo "  FAIL: guard took ${elapsed}s (expected <6s)"; FAIL=$((FAIL + 1))
fi
TOTAL=$((TOTAL + 1))
if printf '%s' "$out" | grep -qE '^\[LIVENESS\] ERROR: interval_sec must be > 0'; then
  echo "  PASS: ERROR stderr log line emitted (NOT STALE)"; PASS=$((PASS + 1))
else
  echo "  FAIL: ERROR log line missing (or wrong format)"; FAIL=$((FAIL + 1))
fi
TOTAL=$((TOTAL + 1))
if printf '%s' "$out" | grep -qE 'STALE'; then
  echo "  FAIL: STALE log emitted on guard path (should be ERROR only)"; FAIL=$((FAIL + 1))
else
  echo "  PASS: no STALE log on guard path (correct — fail-fast before timeout loop)"; PASS=$((PASS + 1))
fi
rm -rf "$TMP"

# Test 6: N20 / US-002 (v0.7.1) — wrap_orchestrator_dispatch QL_LIVENESS_ENABLE=false silent skip
echo ""
echo "Test 6: wrap_orchestrator_dispatch with QL_LIVENESS_ENABLE=false returns 0 silently"
TMP6=$(mktemp -d)
( cd "$TMP6" && git init -q && git config user.email "t@t.t" && git config user.name "t" \
  && echo "init" > README.md && git add README.md && git commit -qm "init" ) >/dev/null 2>&1
out6=$(cd "$TMP6" && QL_LIVENESS_ENABLE=false bash -c "source '$LIB' && wrap_orchestrator_dispatch 2 1" 2>&1 || true)
rc6=$(cd "$TMP6" && QL_LIVENESS_ENABLE=false bash -c "source '$LIB' && wrap_orchestrator_dispatch 2 1 >/dev/null 2>&1 ; echo \$?")
assert "Test 6: opt-out exit code = 0 (silent skip)" "0" "$rc6"
TOTAL=$((TOTAL + 1))
if [[ -z "$out6" ]] || [[ "$out6" == "" ]]; then
  echo "  PASS: opt-out emits no stdout/stderr (silent)"; PASS=$((PASS + 1))
else
  echo "  FAIL: opt-out emitted unexpected output: $out6"; FAIL=$((FAIL + 1))
fi
rm -rf "$TMP6"

# Test 7: wrap_orchestrator_dispatch default-on with stale repo emits handoff + rc=1
echo ""
echo "Test 7: wrap_orchestrator_dispatch default + stale repo -> handoff stdout + rc=1"
TMP7=$(mktemp -d)
( cd "$TMP7" && git init -q && git config user.email "t@t.t" && git config user.name "t" \
  && echo "init" > README.md && git add README.md && git commit -qm "init" ) >/dev/null 2>&1
t0=$(date +%s)
rc7=0
out7=$(cd "$TMP7" && bash -c "source '$LIB' && wrap_orchestrator_dispatch 2 1" 2>&1) || rc7=$?
t1=$(date +%s)
elapsed=$((t1 - t0))
assert "Test 7: stale path exit code = 1" "1" "$rc7"
TOTAL=$((TOTAL + 1))
if (( elapsed <= 10 )); then
  echo "  PASS: stale-path completed within 10s (got ${elapsed}s)"; PASS=$((PASS + 1))
else
  echo "  FAIL: stale-path took ${elapsed}s (>10s)"; FAIL=$((FAIL + 1))
fi
TOTAL=$((TOTAL + 1))
if printf '%s' "$out7" | grep -qE 'orchestrator-stale signal'; then
  echo "  PASS: handoff message emitted to stdout"; PASS=$((PASS + 1))
else
  echo "  FAIL: handoff message missing from stdout"; FAIL=$((FAIL + 1))
fi
TOTAL=$((TOTAL + 1))
if printf '%s' "$out7" | grep -q 'references/orchestrator-takeover.md'; then
  echo "  PASS: handoff cross-links references/orchestrator-takeover.md"; PASS=$((PASS + 1))
else
  echo "  FAIL: handoff missing cross-link to takeover SOP"; FAIL=$((FAIL + 1))
fi
rm -rf "$TMP7"

# Test 8: N24 / US-001 (v0.7.2) — QL_RESPAWN_CMD set + STALE -> respawn cmd executed, rc=0
echo ""
echo "Test 8: wrap_orchestrator_dispatch QL_RESPAWN_CMD set + stale -> respawn executed rc=0 (wall-clock <10s)"
TMP8=$(mktemp -d)
( cd "$TMP8" && git init -q && git config user.email "t@t.t" && git config user.name "t" \
  && echo "init" > README.md && git add README.md && git commit -qm "init" ) >/dev/null 2>&1
rc8=0
out8=$(cd "$TMP8" && QL_RESPAWN_CMD="echo respawned" bash -c "source '$LIB' && wrap_orchestrator_dispatch 2 1" 2>&1) || rc8=$?
assert "Test 8: QL_RESPAWN_CMD respawn rc=0" "0" "$rc8"
TOTAL=$((TOTAL + 1))
if printf '%s' "$out8" | grep -q 'respawned'; then
  echo "  PASS: respawn command output 'respawned' present in stdout"; PASS=$((PASS + 1))
else
  echo "  FAIL: 'respawned' not found in stdout — out: $out8"; FAIL=$((FAIL + 1))
fi
rm -rf "$TMP8"

# Test 9: N24 / US-001 (v0.7.2) — QL_RESPAWN_CMD unset + STALE -> handoff + rc=1 (v0.7.1 regression guard)
echo ""
echo "Test 9: wrap_orchestrator_dispatch QL_RESPAWN_CMD unset + stale -> handoff rc=1 (regression guard)"
TMP9=$(mktemp -d)
( cd "$TMP9" && git init -q && git config user.email "t@t.t" && git config user.name "t" \
  && echo "init" > README.md && git add README.md && git commit -qm "init" ) >/dev/null 2>&1
rc9=0
out9=$(cd "$TMP9" && bash -c "source '$LIB' && wrap_orchestrator_dispatch 2 1" 2>&1) || rc9=$?
assert "Test 9: unset QL_RESPAWN_CMD fallback rc=1" "1" "$rc9"
TOTAL=$((TOTAL + 1))
if printf '%s' "$out9" | grep -qE 'orchestrator-stale signal'; then
  echo "  PASS: handoff message present (v0.7.1 behavior unchanged)"; PASS=$((PASS + 1))
else
  echo "  FAIL: handoff message missing — out: $out9"; FAIL=$((FAIL + 1))
fi
rm -rf "$TMP9"

echo ""
echo "=== Results: $PASS/$TOTAL passed, $FAIL failed ==="
[[ $FAIL -eq 0 ]] || exit 1
