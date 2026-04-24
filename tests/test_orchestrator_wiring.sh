#!/usr/bin/env bash
# Phase 17 — verify the orchestrator prompt wires each helper library
# we shipped in Phases 5-16. These are prompt-side assertions: the actual
# runtime invocations happen inside the orchestrator agent at run time,
# so the test locks the reference surface so future edits can't silently
# unwire a lib.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$SCRIPT_DIR/.."
ORCH="$REPO_ROOT/agents/orchestrator.md"
PASS=0
FAIL=0
TOTAL=0

check() {
  local name="$1" needle="$2"
  TOTAL=$((TOTAL + 1))
  if grep -qF -- "$needle" "$ORCH"; then
    echo "  PASS: $name"; PASS=$((PASS + 1))
  else
    echo "  FAIL: $name — needle [$needle] not in orchestrator.md"
    FAIL=$((FAIL + 1))
  fi
}

echo "=== Phase 17 orchestrator-wiring prompt tests ==="

# Test 1: Wave-boundary cross-story constant scan wired at 3C.NEG1
echo ""
echo "Test 1: lib/wave-boundary.sh wired at wave boundary"
check "3C.NEG1 section present" "3C.NEG1: Wave-boundary cross-story constant scan"
check "references wave-boundary.sh scan" "lib/wave-boundary.sh scan"
check "routes HIGH severity to fix-story" "HIGH_COUNT=\$"

# Test 2: Watchdog wired into 3B.3 monitor loop
echo ""
echo "Test 2: lib/watchdog.sh wired in monitor loop"
check "watchdog tick header" "Watchdog tick"
check "references watchdog.sh poll" "lib/watchdog.sh\" poll"
check "status-probe action branch" "status-probe"
check "kill-and-requeue action branch" "kill-and-requeue"
check "mark-failed action branch" "mark-failed"
check "circuit-breaker bump" "lib/watchdog.sh\" bump"
check "circuit-breaker check" "lib/watchdog.sh\" circuit"

# Test 3: Deep-review wired at 4B.5
echo ""
echo "Test 3: lib/deep-review.sh wired at full-feature review"
check "4B.5 deep-review section" "4B.5: Deep-review aggregation"
check "score-from-quantum call" "score-from-quantum"
check "tier lookup"      "lib/deep-review.sh\" tier"
check "dispatch-set call" "dispatch-set"
check "context preparation" "lib/deep-review.sh\" context"
check "aggregate pipe"    "lib/deep-review.sh\" aggregate"
check "BLOCKS_MERGE handled" "BLOCKS_MERGE)"
check "REQUEST_CHANGES handled" "REQUEST_CHANGES)"
check "persists into quantum.reviews" ".reviews[\$fid]"

# Test 4: Deslop wired at 3A.5B
echo ""
echo "Test 4: lib/deslop.sh wired between review-pass and commit"
check "3A.5B deslop section" "3A.5B: Post-review slop-cleanup"
check "validate_scope gate" "lib/deslop.sh\" scope"
check "baseline snapshot before" "lib/deslop.sh\" baseline"
check "compare_baseline call" "lib/deslop.sh\" compare"
check "rollback on regression" "lib/deslop.sh\" rollback"
check "DESLOP_ROLLED_BACK signal" "DESLOP_ROLLED_BACK"
check "opt-out via story.deslop.skip" "story.deslop.skip"

# Test 5: Commit-trailer validation at 3A.6
echo ""
echo "Test 5: lib/commit-trailers.sh validation gate"
check "commit-trailers reference" "lib/commit-trailers.sh\" validate"
check "non-blocking warning" "missing required trailers"

# Test 6: Handoff reads/writes — delegated to skills, but orchestrator
# should at least not trample the .handoffs/ directory. Smoke-check that
# the lib name isn't gratuitously referenced inside the orchestrator
# (which would suggest mis-wiring) — skills are the handoff producers.
echo ""
echo "Test 6: handoff.sh ownership is skill-side (orchestrator doesn't write)"
if ! grep -qE "bash .*lib/handoff\.sh write" "$ORCH"; then
  echo "  PASS: orchestrator does NOT write handoffs directly (skills do)"
  PASS=$((PASS + 1))
else
  echo "  FAIL: orchestrator is writing handoffs — should be skill-side"
  FAIL=$((FAIL + 1))
fi
TOTAL=$((TOTAL + 1))

# Test 7: Phase-17 wiring attribution present everywhere (easier to audit future edits)
echo ""
echo "Test 7: all wirings carry a Phase-17 attribution comment"
count_17=$(grep -c "Phase 17 wiring" "$ORCH")
if (( count_17 >= 4 )); then
  echo "  PASS: $count_17 Phase-17 attributions"; PASS=$((PASS + 1))
else
  echo "  FAIL: only $count_17 Phase-17 attributions (expected ≥4)"
  FAIL=$((FAIL + 1))
fi
TOTAL=$((TOTAL + 1))

echo ""
echo "=== Results: $PASS/$TOTAL passed, $FAIL failed ==="
exit $((FAIL > 0 ? 1 : 0))
