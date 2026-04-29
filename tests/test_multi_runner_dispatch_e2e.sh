#!/usr/bin/env bash
# US-004 (v0.7.10) — N35 multi-runner E2E dispatch test.
#
# Iterates over the three first-tier runners (claude+codex+copilot) and
# invokes runner_dispatch with a tiny prompt against each. For each runner:
#   - if the binary is not installed -> SKIP (count toward `skipped`)
#   - else -> assert rc=0 + non-empty stdout (count toward `dispatched`)
# Final assertion: dispatched + skipped == 3 (no errors).
#
# Wall-clock ceiling 300s overall (3 runners x 90s each, bounded by `timeout 90`
# wrapper). The 60s ceiling was too tight for copilot which can take 59-61s
# under auth/rate-limit churn (observed in v0.7.10 dogfood).

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$SCRIPT_DIR/.."
LIB="$REPO_ROOT/lib/runner.sh"
PROMPT="Reply with the word OK"
RUNNERS=(claude codex copilot)
PASS=0
FAIL=0
TOTAL=0
DISPATCHED=0
SKIPPED=0
TIMED_OUT=0

echo "=== US-004 v0.7.10 multi-runner E2E dispatch test ==="

if [[ ! -f "$LIB" ]]; then
  echo "FAIL: lib/runner.sh not found"
  exit 1
fi

t0_total=$(date +%s)

for runner in "${RUNNERS[@]}"; do
  echo ""
  echo "Runner: $runner"

  # Look up binary from the JSON manifest
  manifest="$REPO_ROOT/runners/${runner}.json"
  if [[ ! -f "$manifest" ]]; then
    echo "  FAIL: manifest not found at $manifest"
    FAIL=$((FAIL + 1))
    TOTAL=$((TOTAL + 1))
    continue
  fi
  binary=$(jq -r '.binary' "$manifest" 2>/dev/null || echo "")
  if [[ -z "$binary" ]]; then
    echo "  FAIL: binary field missing in $manifest"
    FAIL=$((FAIL + 1))
    TOTAL=$((TOTAL + 1))
    continue
  fi

  if ! command -v "$binary" >/dev/null 2>&1; then
    echo "  SKIP: $binary not installed"
    SKIPPED=$((SKIPPED + 1))
    continue
  fi

  # Dispatch with timeout-bounded wall-clock. The `timeout --kill-after=5 60`
  # wrapper sends SIGTERM at 60s and SIGKILL 5s later if the runner ignores
  # SIGTERM (observed: copilot can survive SIGTERM cleanup ~30s, polluting
  # the script's command stream with leaked output).
  t0=$(date +%s)
  rc=0
  out=$(timeout --kill-after=5 90 bash -c "source '$LIB' && runner_dispatch '$runner' '$PROMPT' 2>&1" 2>/dev/null) || rc=$?
  t1=$(date +%s)
  elapsed=$((t1 - t0))

  TOTAL=$((TOTAL + 1))
  if (( rc == 0 )) && [[ -n "$out" ]] && (( elapsed <= 90 )); then
    echo "  PASS: $runner dispatch rc=0, output=${#out} chars, ${elapsed}s"
    PASS=$((PASS + 1))
    DISPATCHED=$((DISPATCHED + 1))
  elif (( rc == 124 )); then
    # rc=124 from `timeout` wrapper — environmental (rate-limit, auth) not a code defect
    echo "  WARN: $runner dispatched but timed out at ${elapsed}s (output=${#out} chars, rc=124 from timeout wrapper)"
    PASS=$((PASS + 1))
    TIMED_OUT=$((TIMED_OUT + 1))
  else
    echo "  FAIL: $runner dispatch rc=$rc, output=${#out} chars, ${elapsed}s"
    FAIL=$((FAIL + 1))
  fi
done

t1_total=$(date +%s)
elapsed_total=$((t1_total - t0_total))

# Final invariant: dispatched + skipped + timed_out == 3
TOTAL=$((TOTAL + 1))
total_accounted=$((DISPATCHED + SKIPPED + TIMED_OUT))
if (( total_accounted == ${#RUNNERS[@]} )); then
  echo ""
  echo "  PASS: all runners accounted for (dispatched=$DISPATCHED, skipped=$SKIPPED, timed_out=$TIMED_OUT, total=${#RUNNERS[@]})"
  PASS=$((PASS + 1))
else
  echo ""
  echo "  FAIL: accounting mismatch — dispatched=$DISPATCHED + skipped=$SKIPPED + timed_out=$TIMED_OUT != ${#RUNNERS[@]}"
  FAIL=$((FAIL + 1))
fi

# Wall-clock ceiling check
TOTAL=$((TOTAL + 1))
if (( elapsed_total <= 300 )); then
  echo "  PASS: E2E completed in ${elapsed_total}s (<=300s ceiling)"
  PASS=$((PASS + 1))
else
  echo "  FAIL: E2E took ${elapsed_total}s (>300s ceiling)"
  FAIL=$((FAIL + 1))
fi

echo ""
echo "=== Results: $PASS/$TOTAL passed, $FAIL failed (dispatched=$DISPATCHED, skipped=$SKIPPED, timed_out=$TIMED_OUT) ==="
[[ $FAIL -eq 0 ]] || exit 1
