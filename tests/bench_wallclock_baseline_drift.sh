#!/usr/bin/env bash
# N9-followup / US-003 (v0.6.9) — wall-clock baseline drift bench.
#
# OPT-IN: this is a benchmark, not a test. The `bench_*` filename prefix
# deliberately does NOT match `tests/run_all.sh`'s `test_*.sh` glob, so the
# standard runner skips it. Operators must invoke this script directly:
#   bash tests/bench_wallclock_baseline_drift.sh
#
# WHAT IT DOES: runs each documented baseline command from
# `references/test-wallclock-baselines.md` with `time`, parses the `real`
# wall-clock seconds, compares against the hardcoded baseline. Emits a
# WARN line if measured wall-clock exceeds 1.5× baseline (>50% drift).
#
# ALWAYS EXITS 0 — informational only. Never FAILs CI. Operators read the
# WARN lines (if any) during retrospective writing to decide whether to
# refresh the reference baselines.
#
# UPDATE PROCEDURE: when refreshing baselines, update BOTH the BASELINES
# associative array below AND the table rows in
# references/test-wallclock-baselines.md. The bench does NOT auto-extract
# from the doc — the operator is the parser.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$SCRIPT_DIR/.."

# Hardcoded baselines — Git Bash on Windows wall-clock seconds (curated subset).
# Last refreshed: 2026-04-28 (v0.6.9 ship). Source:
# references/test-wallclock-baselines.md.
declare -A BASELINES=(
  ["bash tests/test_audit.sh"]=240
  ["bash tests/test_run_all.sh"]=30
  ["bash tests/test_deep_review_dispatch.sh"]=20
  ["bash tests/test_orchestrator_self_monitor.sh"]=5
  ["bash tests/test_soliton_triage_doc.sh"]=5
  ["bash tests/test_orchestrator_takeover_doc.sh"]=5
  ["bash tests/test_orchestrator_liveness.sh"]=15
)

echo "=== bench_wallclock_baseline_drift (v0.6.9 / N9-followup) ==="
echo ""
echo "Running ${#BASELINES[@]} baseline commands; WARN-ing on >50% drift."
echo ""

n_warn=0
for cmd in "${!BASELINES[@]}"; do
  baseline=${BASELINES[$cmd]}
  threshold=$(( baseline * 150 / 100 ))
  # Run with `time` and parse the real wall-clock from stderr.
  # `time` output format on bash: 3 lines (real / user / sys). On Git Bash,
  # `real` is in `0m1.234s` form. Convert to integer seconds.
  # N17 / US-005 (v0.7.0) — printf %q safely quotes REPO_ROOT against single
  # quotes. v0.6.9 PR #70 soliton conf-65 carry-over: pre-N17 the literal
  # `cd '$REPO_ROOT'` form would syntax-error if REPO_ROOT contained a single
  # quote (e.g. /home/user/andy's-repos/). Current paths are quote-free; this
  # change is defensive against future relocations.
  safe_cmd=$(printf '(cd %q && %s)' "$REPO_ROOT" "$cmd")
  measured_raw=$( { time eval "$safe_cmd" >/dev/null 2>&1 ; } 2>&1 | grep '^real' | awk '{print $2}')
  # Parse 0m12.345s → 12 (integer seconds; round down).
  if [[ "$measured_raw" =~ ^([0-9]+)m([0-9]+)\.([0-9]+)s ]]; then
    minutes="${BASH_REMATCH[1]}"
    seconds="${BASH_REMATCH[2]}"
    measured=$((minutes * 60 + seconds))
  else
    measured=0
  fi

  if (( measured > threshold )); then
    echo "WARN: $cmd took ${measured}s (baseline ${baseline}s, threshold ${threshold}s — drift > 50%)"
    n_warn=$((n_warn + 1))
  else
    echo "OK:   $cmd took ${measured}s (baseline ${baseline}s)"
  fi
done

echo ""
if (( n_warn == 0 )); then
  echo "Bench result: 0 WARN — all baselines within 50% drift threshold."
else
  echo "Bench result: $n_warn WARN line(s) — refresh baselines in"
  echo "  references/test-wallclock-baselines.md AND the BASELINES array"
  echo "  in this file."
fi

# Always exit 0 — informational bench, never FAILs CI.
exit 0
