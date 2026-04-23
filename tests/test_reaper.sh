#!/usr/bin/env bash
# Phase 20 / P2.11 — tests for lib/reaper.sh + lib/spawn.sh exec-capture fix.
#
# Covers the testable surface of the reaper library. Can't portably test the
# actual taskkill path (would require spawning claude.exe on a live machine),
# so we test pidfile semantics, platform detection, alive/dead detection,
# and the orphan-scan machinery against sleep-based fixtures.

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

# shellcheck disable=SC1091
source "$REPO_ROOT/lib/reaper.sh"

echo "=== Phase 20 reaper + spawn exec-capture tests ==="

# Test 1: detect_platform returns a known value
echo ""
echo "Test 1: detect_platform recognizes current environment"
plat=$(detect_platform)
case "$plat" in
  posix-setsid|posix-plain|msys|cygwin|unknown) valid=1 ;;
  *) valid=0 ;;
esac
assert "platform is valid enum" "1" "$valid"
printf "  (detected: %s)\n" "$plat"

# Test 2: _msys_to_winpid returns either a numeric winpid (Git Bash) or empty
echo ""
echo "Test 2: _msys_to_winpid handles current PID"
out=$(_msys_to_winpid "$$")
if [[ -z "$out" ]]; then
  echo "  PASS: no winpid (non-MSYS platform)"; PASS=$((PASS + 1))
elif [[ "$out" =~ ^[0-9]+$ ]]; then
  echo "  PASS: numeric winpid ($out)"; PASS=$((PASS + 1))
else
  echo "  FAIL: unexpected winpid output [$out]"; FAIL=$((FAIL + 1))
fi
TOTAL=$((TOTAL + 1))

# Test 3: write + read pidfile round-trip
echo ""
echo "Test 3: write + read pidfile round-trip"
TEST_TMPDIR=$(mktemp -d)
# Start a sleep and record it
sleep 30 &
SLEEP_PID=$!
WINPID=$(_msys_to_winpid "$SLEEP_PID")
write_agent_pidfile "$TEST_TMPDIR" "US-001" "$SLEEP_PID" "$WINPID" "sleep 30" >/dev/null
assert "pidfile exists" "yes" "$([[ -f "$TEST_TMPDIR/US-001.pid" ]] && echo yes || echo no)"
read_out=$(read_agent_pidfile "$TEST_TMPDIR" "US-001")
msys=$(jq -r '.msys_pid' <<< "$read_out")
cmd=$(jq -r '.cmd' <<< "$read_out")
assert "msys_pid round-trips" "$SLEEP_PID" "$msys"
assert "cmd round-trips" "sleep 30" "$cmd"
# Read non-existent entry
empty=$(read_agent_pidfile "$TEST_TMPDIR" "US-nope")
assert "missing pidfile -> {}" "{}" "$empty"
kill "$SLEEP_PID" 2>/dev/null
wait "$SLEEP_PID" 2>/dev/null || true
rm -rf "$TEST_TMPDIR"

# Test 4: is_agent_alive returns true while process runs, false after
echo ""
echo "Test 4: is_agent_alive tracks liveness"
TEST_TMPDIR=$(mktemp -d)
sleep 30 &
SLEEP_PID=$!
WINPID=$(_msys_to_winpid "$SLEEP_PID")
write_agent_pidfile "$TEST_TMPDIR" "US-002" "$SLEEP_PID" "$WINPID" "sleep 30" >/dev/null
is_agent_alive "$TEST_TMPDIR" "US-002"
assert "alive while running" "0" "$?"
kill -9 "$SLEEP_PID" 2>/dev/null
wait "$SLEEP_PID" 2>/dev/null || true
# Small settle for OS process-table cleanup
sleep 1
is_agent_alive "$TEST_TMPDIR" "US-002"
assert "dead after kill" "1" "$?"
rm -rf "$TEST_TMPDIR"

# Test 5: is_agent_alive returns false when pidfile missing
echo ""
echo "Test 5: is_agent_alive on missing pidfile"
TEST_TMPDIR=$(mktemp -d)
is_agent_alive "$TEST_TMPDIR" "US-nope"
assert "missing pidfile -> not alive" "1" "$?"
rm -rf "$TEST_TMPDIR"

# Test 6: reap_agent on already-dead process is a clean no-op
echo ""
echo "Test 6: reap_agent on already-dead process cleans pidfile"
TEST_TMPDIR=$(mktemp -d)
sleep 1 &
SLEEP_PID=$!
write_agent_pidfile "$TEST_TMPDIR" "US-003" "$SLEEP_PID" "" "short sleep" >/dev/null
wait "$SLEEP_PID" 2>/dev/null || true
sleep 1  # ensure process-table cleared
reap_agent "$TEST_TMPDIR" "US-003" 2>/dev/null
assert "reap exits 0" "0" "$?"
assert "pidfile removed" "no" "$([[ -f "$TEST_TMPDIR/US-003.pid" ]] && echo yes || echo no)"
rm -rf "$TEST_TMPDIR"

# Test 7: reap_agent kills a live process
echo ""
echo "Test 7: reap_agent terminates a live process"
TEST_TMPDIR=$(mktemp -d)
# Use a long sleep we can kill
sleep 300 &
SLEEP_PID=$!
WINPID=$(_msys_to_winpid "$SLEEP_PID")
write_agent_pidfile "$TEST_TMPDIR" "US-004" "$SLEEP_PID" "$WINPID" "sleep 300" >/dev/null
# Speed up the test — 1s grace instead of 5s
REAPER_GRACE_SECS=1 reap_agent "$TEST_TMPDIR" "US-004" 2>/dev/null
reap_rc=$?
# wait to reap zombie
wait "$SLEEP_PID" 2>/dev/null || true
sleep 1
# Process should be gone
kill -0 "$SLEEP_PID" 2>/dev/null
alive_rc=$?
assert "reap_agent exits 0"   "0"  "$reap_rc"
assert "process not alive"    "1"  "$alive_rc"
assert "pidfile removed"      "no" "$([[ -f "$TEST_TMPDIR/US-004.pid" ]] && echo yes || echo no)"
rm -rf "$TEST_TMPDIR"

# Test 8: reap_orphans — dead pidfile cleaned, fresh pidfile kept
echo ""
echo "Test 8: reap_orphans cleans stale pidfiles only"
TEST_TMPDIR=$(mktemp -d)
# Write one pidfile pointing at a dead pid
write_agent_pidfile "$TEST_TMPDIR" "US-dead" "99999" "" "already dead" >/dev/null
# Write one pidfile for a live, NOT-stale process
sleep 30 &
LIVE_PID=$!
WINPID=$(_msys_to_winpid "$LIVE_PID")
write_agent_pidfile "$TEST_TMPDIR" "US-live" "$LIVE_PID" "$WINPID" "live sleep" >/dev/null
# REAPER_STALE_SECS default is 3600, so this fresh process is NOT reaped
count=$(reap_orphans "$TEST_TMPDIR" 2>/dev/null)
# dead-pidfile cleanup shouldn't count (it was already dead, not reaped).
# count should be 0 (no LIVE + stale processes).
assert "no stale-orphans reaped" "0" "$count"
assert "dead pidfile removed"  "no"  "$([[ -f "$TEST_TMPDIR/US-dead.pid" ]] && echo yes || echo no)"
assert "live pidfile kept"     "yes" "$([[ -f "$TEST_TMPDIR/US-live.pid" ]] && echo yes || echo no)"
kill "$LIVE_PID" 2>/dev/null
wait "$LIVE_PID" 2>/dev/null || true
rm -rf "$TEST_TMPDIR"

# Test 9: reap_orphans on empty dir is a safe no-op
echo ""
echo "Test 9: reap_orphans safe on missing/empty dir"
count=$(reap_orphans "/nonexistent/dir" 2>/dev/null)
assert "missing dir -> 0" "" "$count"  # (function prints nothing + returns early)
TEST_TMPDIR=$(mktemp -d)
count=$(reap_orphans "$TEST_TMPDIR" 2>/dev/null)
assert "empty dir -> 0" "0" "$count"
rm -rf "$TEST_TMPDIR"

# Test 10: lib/spawn.sh uses `exec` for inner-PID capture (Phase 20 fix)
echo ""
echo "Test 10: lib/spawn.sh contains the exec-replacement fix"
if grep -q 'exec claude --dangerously-skip-permissions' "$REPO_ROOT/lib/spawn.sh"; then
  echo "  PASS: exec prepended to claude invocation"; PASS=$((PASS + 1))
else
  echo "  FAIL: lib/spawn.sh does NOT exec claude — subshell PID would be captured"
  FAIL=$((FAIL + 1))
fi
TOTAL=$((TOTAL + 1))
if grep -q 'eval "exec $cmd"' "$REPO_ROOT/lib/spawn.sh"; then
  echo "  PASS: runner-path uses eval \"exec \$cmd\""; PASS=$((PASS + 1))
else
  echo "  FAIL: runner-path missing exec"; FAIL=$((FAIL + 1))
fi
TOTAL=$((TOTAL + 1))
if grep -q 'write_agent_pidfile' "$REPO_ROOT/lib/spawn.sh"; then
  echo "  PASS: spawn writes pidfile"; PASS=$((PASS + 1))
else
  echo "  FAIL: spawn does not record pidfile"; FAIL=$((FAIL + 1))
fi
TOTAL=$((TOTAL + 1))

# Test 11: quantum-loop.sh wires the reaper
echo ""
echo "Test 11: quantum-loop.sh trap uses reaper"
if grep -q 'reap_agent "$REAPER_PID_DIR"' "$REPO_ROOT/quantum-loop.sh"; then
  echo "  PASS: cleanup_on_exit calls reap_agent"; PASS=$((PASS + 1))
else
  echo "  FAIL: trap not wired to reap_agent"; FAIL=$((FAIL + 1))
fi
TOTAL=$((TOTAL + 1))
if grep -q 'reap_orphans "$REPO_ROOT/$REAPER_PID_DIR"' "$REPO_ROOT/quantum-loop.sh"; then
  echo "  PASS: startup calls reap_orphans"; PASS=$((PASS + 1))
else
  echo "  FAIL: startup does not reap prior-run orphans"; FAIL=$((FAIL + 1))
fi
TOTAL=$((TOTAL + 1))

# Test 12: CLI subcommands
echo ""
echo "Test 12: CLI subcommands work"
cli_plat=$(bash "$REPO_ROOT/lib/reaper.sh" platform | tr -d '\n')
[[ -n "$cli_plat" ]] && { echo "  PASS: CLI platform output: $cli_plat"; PASS=$((PASS + 1)); } \
                     || { echo "  FAIL: CLI platform empty"; FAIL=$((FAIL + 1)); }
TOTAL=$((TOTAL + 1))

echo ""
echo "=== Results: $PASS/$TOTAL passed, $FAIL failed ==="
exit $((FAIL > 0 ? 1 : 0))
