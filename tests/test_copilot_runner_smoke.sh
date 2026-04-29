#!/usr/bin/env bash
# US-002 (v0.8.0) — copilot CLI smoke test (HEALTH-CHECK LAYER).
#
# v0.7.10 N35 reframe: this is the SMOKE layer — version-probe health check
# that verifies binary present + manifest loadable. The complementary
# DISPATCH layer (`tests/test_copilot_dispatch.sh`) verifies real-task
# end-to-end (prompt -> output). Both layers skip-pass when copilot is not
# installed. See CLAUDE.md "Multi-runner test layers".

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$SCRIPT_DIR/.."
RUNNER="$REPO_ROOT/lib/runner.sh"
RUNNER_TOOL="copilot"
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

echo "=== US-002 v0.8.0 copilot CLI smoke test ==="

if ! command -v copilot >/dev/null 2>&1; then
  printf "[COPILOT-SMOKE] WARN: copilot CLI not available in PATH — skip-pass\n" >&2
  TOTAL=$((TOTAL + 1))
  echo "  PASS: copilot absent — skip-pass"; PASS=$((PASS + 1))
  echo ""
  echo "=== Results: $PASS/$TOTAL passed, $FAIL failed (skipped) ==="
  exit 0
fi

t0=$(date +%s)
out=$(bash -c "source '$RUNNER' && runner_load '$RUNNER_TOOL' >/dev/null 2>&1 && printf '%s|%s|%s\n' \"\$RUNNER_NAME\" \"\$RUNNER_BINARY\" \"\$RUNNER_TIER\"")
t1=$(date +%s)
elapsed=$((t1 - t0))

IFS='|' read -r rn rb rt <<< "$out"
assert "RUNNER_NAME=copilot" "copilot" "$rn"
assert "RUNNER_BINARY=copilot" "copilot" "$rb"
assert "RUNNER_TIER=experimental" "experimental" "$rt"

ver=$(bash -c "source '$RUNNER' && _provider_version copilot" 2>/dev/null)
TOTAL=$((TOTAL + 1))
if [[ -n "$ver" && "$ver" != "unknown" && "$ver" != "n/a" ]]; then
  echo "  PASS: _provider_version copilot emits non-empty version: $ver"; PASS=$((PASS + 1))
else
  echo "  FAIL: _provider_version copilot returned: '$ver'"; FAIL=$((FAIL + 1))
fi

TOTAL=$((TOTAL + 1))
if (( elapsed <= 15 )); then
  echo "  PASS: smoke completed within 15s (got ${elapsed}s)"; PASS=$((PASS + 1))
else
  echo "  FAIL: smoke took ${elapsed}s (>15s)"; FAIL=$((FAIL + 1))
fi

echo ""
echo "=== Results: $PASS/$TOTAL passed, $FAIL failed ==="
[[ $FAIL -eq 0 ]] || exit 1
