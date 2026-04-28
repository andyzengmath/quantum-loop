#!/usr/bin/env bash
# N6 / US-001 (v0.6.8) — orchestrator Self-monitoring guard presence + regex-validity tests.
#
# v0.6.7's orchestrator subagent abandoned its cycle mid-execution due to
# LLM context-drift. v0.6.8's response is a prose-level cue (Self-monitoring
# guard subsection in agents/orchestrator.md) listing forbidden idioms the
# agent should treat as drift signals.
#
# This test file enforces the PROSE is present (presence-only) — it does NOT
# validate runtime LLM behavior. Runtime enforcement is queued as v0.6.9
# N6-followup.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$SCRIPT_DIR/.."
ORCH="$REPO_ROOT/agents/orchestrator.md"
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

echo "=== US-001 N6 orchestrator Self-monitoring guard tests ==="

# Test 1: Self-monitoring guard subsection header present
echo ""
echo "Test 1: agents/orchestrator.md contains '### Self-monitoring guard' header"
TOTAL=$((TOTAL + 1))
if grep -q '^### Self-monitoring guard' "$ORCH"; then
  echo "  PASS: Self-monitoring guard subsection header present"
  PASS=$((PASS + 1))
else
  echo "  FAIL: Self-monitoring guard subsection header missing"
  FAIL=$((FAIL + 1))
fi

# Test 2: at least 3 forbidden idioms enumerated
# Forbidden-idiom regex (also used by Test 4 negative-control). Picks up the
# distinctive multi-word phrases the orchestrator should treat as drift signals.
FORBIDDEN_RE='while that runs|let me proactively|let me prepare US-[A-Z0-9]+ in parallel'

echo ""
echo "Test 2: subsection enumerates >=3 forbidden idioms"
TOTAL=$((TOTAL + 1))
n_idioms=$(grep -cE "$FORBIDDEN_RE" "$ORCH" 2>/dev/null || true)
if (( n_idioms >= 3 )); then
  echo "  PASS: $n_idioms forbidden-idiom references found"
  PASS=$((PASS + 1))
else
  echo "  FAIL: only $n_idioms forbidden-idiom references found (expected >=3)"
  FAIL=$((FAIL + 1))
fi

# Test 3: self-recovery action documented (STALE-DETECT log marker)
echo ""
echo "Test 3: subsection documents self-recovery action (STALE-DETECT marker)"
TOTAL=$((TOTAL + 1))
if grep -q 'STALE-DETECT' "$ORCH"; then
  echo "  PASS: STALE-DETECT recovery-action log marker present"
  PASS=$((PASS + 1))
else
  echo "  FAIL: STALE-DETECT marker missing — recovery action not documented"
  FAIL=$((FAIL + 1))
fi

# Test 4: NEGATIVE-CONTROL — regex-validity test, NOT an LLM-behavior test.
# Build a string of legitimate cross-story phrases that should NOT match the
# forbidden-idiom regex. Catches an over-broad regex that would false-positive
# on normal sequential-mode logging.
echo ""
echo "Test 4: forbidden-idiom regex returns 0 matches against legitimate cross-story phrasing (negative-control)"
legitimate="dependsOn US-002 — wave-boundary edge declared.
current story passed; picking next eligible.
Wave 1 unblocked: US-004 now ready.
US-007 retrospective deps US-001..US-006 (sequential aggregator)."
TOTAL=$((TOTAL + 1))
n_falsepos=$(printf '%s' "$legitimate" | grep -cE "$FORBIDDEN_RE" || true)
if (( n_falsepos == 0 )); then
  echo "  PASS: 0 false-positives on legitimate cross-story phrasing"
  PASS=$((PASS + 1))
else
  echo "  FAIL: $n_falsepos false-positive match(es) — regex too broad"
  FAIL=$((FAIL + 1))
fi

# Test 5: regex DOES match true forbidden phrases (positive-control sanity check)
echo ""
echo "Test 5: forbidden-idiom regex matches true drift phrasing (positive-control)"
drift_sample="while that runs, let me proactively work on US-007's retrospective in parallel"
TOTAL=$((TOTAL + 1))
n_truepos=$(printf '%s' "$drift_sample" | grep -cE "$FORBIDDEN_RE" || true)
if (( n_truepos >= 1 )); then
  echo "  PASS: regex catches true drift phrase"
  PASS=$((PASS + 1))
else
  echo "  FAIL: regex did not catch a known drift phrase"
  FAIL=$((FAIL + 1))
fi

echo ""
echo "=== Results: $PASS/$TOTAL passed, $FAIL failed ==="
[[ $FAIL -eq 0 ]] || exit 1
