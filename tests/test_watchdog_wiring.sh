#!/usr/bin/env bash
# US-001 / P5.A1 — verify lib/watchdog.sh is fully wired into the
# orchestrator monitor loop (Step 3B.3) AND that internal call sites
# reference the platform-aware reap_agent rather than the legacy
# kill_agent_process. Closes the silent-failure mode flagged by agent A:
# circuit-breaker exists in lib but never fires at runtime.
#
# Pattern follows tests/test_orchestrator_wiring.sh — grep-based
# prompt assertions that lock the reference surface.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$SCRIPT_DIR/.."
ORCH="$REPO_ROOT/agents/orchestrator.md"
WATCHDOG="$REPO_ROOT/lib/watchdog.sh"
PASS=0
FAIL=0
TOTAL=0

check() {
  local name="$1" needle="$2" file="$3"
  TOTAL=$((TOTAL + 1))
  if grep -qF -- "$needle" "$file"; then
    echo "  PASS: $name"; PASS=$((PASS + 1))
  else
    echo "  FAIL: $name — needle [$needle] not in $(basename "$file")"
    FAIL=$((FAIL + 1))
  fi
}

check_absent() {
  local name="$1" needle="$2" file="$3"
  TOTAL=$((TOTAL + 1))
  if ! grep -qF -- "$needle" "$file"; then
    echo "  PASS: $name"; PASS=$((PASS + 1))
  else
    echo "  FAIL: $name — needle [$needle] still present in $(basename "$file")"
    FAIL=$((FAIL + 1))
  fi
}

echo "=== US-001 watchdog orchestrator wiring tests ==="

# Test 1: 3 explicit watchdog calls in Step 3B.3
# (a) age-tier check, (b) circuit-breaker check, (c) circuit-breaker reset on success
echo ""
echo "Test 1: 3 explicit watchdog calls in Step 3B.3"
check "Step 3B.3 monitor-loop section header" "### 3B.3: Monitor Loop" "$ORCH"
check "age-tier check via watchdog poll" "lib/watchdog.sh\" poll" "$ORCH"
check "circuit-breaker check via watchdog circuit" "lib/watchdog.sh\" circuit" "$ORCH"
check "circuit-breaker reset on success" "lib/watchdog.sh\" reset" "$ORCH"
check "explicit reset comment refers to STORY_PASSED" "reset on STORY_PASSED" "$ORCH"

# Test 2: orchestrator watchdog block uses reap_agent (not kill_agent_process)
echo ""
echo "Test 2: watchdog block migrated kill_agent_process -> reap_agent"
# Look at the inside of the watchdog poll-loop case statement specifically.
WATCHDOG_BLOCK=$(awk '/^\*\*Watchdog tick/,/^\*\*Trajectory tick/' "$ORCH")
TOTAL=$((TOTAL + 1))
if printf '%s' "$WATCHDOG_BLOCK" | grep -qF "reap_agent"; then
  echo "  PASS: watchdog block references reap_agent"; PASS=$((PASS + 1))
else
  echo "  FAIL: watchdog block missing reap_agent reference"; FAIL=$((FAIL + 1))
fi
TOTAL=$((TOTAL + 1))
if printf '%s' "$WATCHDOG_BLOCK" | grep -qF "kill_agent_process"; then
  echo "  FAIL: watchdog block STILL references legacy kill_agent_process"; FAIL=$((FAIL + 1))
else
  echo "  PASS: watchdog block no longer references kill_agent_process"; PASS=$((PASS + 1))
fi

# Test 3: lib/watchdog.sh internal comments/calls migrated to reap_agent
# (line 4 originally said "Sits above lib/monitor.sh's kill_agent_process + check_agent_timeout")
echo ""
echo "Test 3: lib/watchdog.sh comments migrated to reap_agent"
check "lib/watchdog.sh references reap_agent" "reap_agent" "$WATCHDOG"
check_absent "lib/watchdog.sh no longer references kill_agent_process" "kill_agent_process" "$WATCHDOG"

# Final summary
echo ""
echo "=== Results: $PASS/$TOTAL passed, $FAIL failed ==="
[[ $FAIL -eq 0 ]] || exit 1
