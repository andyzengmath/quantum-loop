#!/usr/bin/env bash
# US-001 (v0.8.0) — codex CLI real smoke test.
#
# First end-to-end validation that the multi-runner infrastructure
# (runners/codex.json + runners/hooks/codex-hooks.sh + lib/runner.sh)
# integrates with the actual codex CLI binary. Skip-pass if codex is
# not on PATH (CI may not install it).

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$SCRIPT_DIR/.."
RUNNER="$REPO_ROOT/lib/runner.sh"
RUNNER_TOOL="codex"
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

echo "=== US-001 v0.8.0 codex CLI smoke test ==="

if ! command -v codex >/dev/null 2>&1; then
  printf "[CODEX-SMOKE] WARN: codex CLI not available in PATH — skip-pass\n" >&2
  TOTAL=$((TOTAL + 1))
  echo "  PASS: codex absent — skip-pass"; PASS=$((PASS + 1))
  echo ""
  echo "=== Results: $PASS/$TOTAL passed, $FAIL failed (skipped) ==="
  exit 0
fi

# Codex present — exercise the load + version chain.
t0=$(date +%s)
out=$(bash -c "source '$RUNNER' && runner_load '$RUNNER_TOOL' >/dev/null 2>&1 && printf '%s|%s|%s\n' \"\$RUNNER_NAME\" \"\$RUNNER_BINARY\" \"\$RUNNER_TIER\"")
t1=$(date +%s)
elapsed=$((t1 - t0))

IFS='|' read -r rn rb rt <<< "$out"
assert "RUNNER_NAME=codex" "codex" "$rn"
assert "RUNNER_BINARY=codex" "codex" "$rb"
assert "RUNNER_TIER=tested" "tested" "$rt"

ver=$(bash -c "source '$RUNNER' && _provider_version codex" 2>/dev/null)
TOTAL=$((TOTAL + 1))
if [[ -n "$ver" && "$ver" != "unknown" && "$ver" != "n/a" ]]; then
  echo "  PASS: _provider_version codex emits non-empty version: $ver"; PASS=$((PASS + 1))
else
  echo "  FAIL: _provider_version codex returned: '$ver'"; FAIL=$((FAIL + 1))
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
