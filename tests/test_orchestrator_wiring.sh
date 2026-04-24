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

# Phase 21 fixes
# ----------------------------------------------------------------------

# Test 8: deslop wiring has graceful fallback + uses BASE_SHA
# (Phase 21 fix for PR #28 correctness finding)
echo ""
echo "Test 8: deslop wiring uses DESLOP_AVAILABLE + BASE_SHA"
check "DESLOP_AVAILABLE guard present"  "DESLOP_AVAILABLE=true"
check "DESLOP_AVAILABLE file check"      "[[ -f \"\$REPO_ROOT/lib/deslop.sh\" ]] || DESLOP_AVAILABLE=false"
check "Fallback skip branch"             "DESLOP_AVAILABLE\" == \"false\""
# Scope loop uses BASE_SHA (from 3A.1), not undefined STORY_BASE_SHA
check "scope loop uses BASE_SHA"         "scope \"\$f\" \"\$BASE_SHA\" \"HEAD\""
check "rollback uses BASE_SHA"           "rollback \"\$BASE_SHA\" \$STORY_FILES"
# Negative check: no active STORY_BASE_SHA references in 3A.5B (comments
# mentioning "not STORY_BASE_SHA" to document the fix are fine and expected)
if grep -A 40 '3A.5B' "$ORCH" \
   | grep -vE '^\s*#' \
   | grep -q 'STORY_BASE_SHA'; then
  echo "  FAIL: STORY_BASE_SHA still referenced (non-comment) in 3A.5B"
  FAIL=$((FAIL + 1))
else
  echo "  PASS: no active STORY_BASE_SHA refs in 3A.5B"; PASS=$((PASS + 1))
fi
TOTAL=$((TOTAL + 1))

# Test 9: RUNNER_EXTRA_FLAGS metacharacter guard in lib/runner.sh
# (Phase 21 fix for PR #27 security finding)
echo ""
echo "Test 9: RUNNER_EXTRA_FLAGS validated after pre_spawn()"
RUNNER="$REPO_ROOT/lib/runner.sh"
TOTAL=$((TOTAL + 1))
if grep -qF 'Unsafe characters in RUNNER_EXTRA_FLAGS' "$RUNNER"; then
  echo "  PASS: RUNNER_EXTRA_FLAGS validation present"
  PASS=$((PASS + 1))
else
  echo "  FAIL: RUNNER_EXTRA_FLAGS not validated after hook pre_spawn()"
  FAIL=$((FAIL + 1))
fi
# Verify the metacharacter blocklist matches the existing RUNNER_HEADLESS_FLAGS pattern
TOTAL=$((TOTAL + 1))
if grep -E 'RUNNER_EXTRA_FLAGS.*=~.*\[\\;\\\|\\&\\\$\\\`' "$RUNNER" >/dev/null 2>&1; then
  echo "  PASS: metacharacter blocklist consistent with existing guards"
  PASS=$((PASS + 1))
else
  # Accept any regex with at least ; and $
  if grep -qE 'RUNNER_EXTRA_FLAGS.*=~.*[\\;]' "$RUNNER"; then
    echo "  PASS: blocklist present (regex form varies)"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: blocklist regex missing"
    FAIL=$((FAIL + 1))
  fi
fi

# Test 10: integration — runner_build_cmd rejects injection payload
echo ""
echo "Test 10: runner_build_cmd rejects injection via RUNNER_EXTRA_FLAGS"
# Source the runner then set RUNNER_EXTRA_FLAGS with an injection payload and call runner_build_cmd.
TEST_TMPDIR=$(mktemp -d)
HOOKS_DIR="$REPO_ROOT/runners/hooks"
(
  # Minimal runner state so runner_build_cmd's path validation etc. is satisfied
  export RUNNER_NAME="claude"
  export RUNNER_BINARY="true"
  export RUNNER_PROMPT_DELIVERY="flag"
  export RUNNER_PROMPT_FLAG="-p"
  export RUNNER_HEADLESS_FLAGS=""
  export RUNNER_AUTO_APPROVE_FLAGS=""
  export RUNNER_EXTRA_FLAGS='--flag; rm -rf $HOME'
  source "$RUNNER" 2>/dev/null
  runner_build_cmd "safe prompt" 2>/tmp/rbc-stderr
) >/dev/null
rc=$?
TOTAL=$((TOTAL + 1))
if [[ "$rc" -ne 0 ]] && grep -qF 'Unsafe characters in RUNNER_EXTRA_FLAGS' /tmp/rbc-stderr 2>/dev/null; then
  echo "  PASS: injection payload rejected with clear error"
  PASS=$((PASS + 1))
else
  echo "  FAIL: injection payload NOT rejected (rc=$rc)"
  cat /tmp/rbc-stderr 2>/dev/null | sed 's/^/    /' | head -3
  FAIL=$((FAIL + 1))
fi
rm -rf "$TEST_TMPDIR" /tmp/rbc-stderr

# Test 10b: Re-grounding wired at Step 1C (Phase 28 / P3.9 wiring)
echo ""
echo "Test 10b: lib/reground.sh wired at Step 1C"
check "reground source line present" 'source "$REPO_ROOT/lib/reground.sh"'
check "REGROUND_AVAILABLE fallback flag" "REGROUND_AVAILABLE=true"
check "Step 1C header present" "Step 1C: Periodic Re-grounding"
check "should_reground invoked" "| should_reground"
check "build_reground_context invoked" "| build_reground_context"
check "mark_grounded invoked" 'mark_grounded "$JSON_PATH"'
check "reground block path stable" ".quantum-reground.md"

# Test 10c: TraceCoder wired at Step 3A.3 quality-gate failure path (Phase 27 / P3.8)
echo ""
echo "Test 10c: lib/tracecoder.sh wired at Step 3A.3"
check "tracecoder source line present" 'source "$REPO_ROOT/lib/tracecoder.sh"'
check "TRACECODER_AVAILABLE fallback flag" "TRACECODER_AVAILABLE=true"
check "observe primitive invoked" 'OBS=$(observe "$GATE_CMD"'
check "should_repair gate check" "| should_repair"
check "build_analysis_context call" "| build_analysis_context"
check "opaque-failure bypass documented" "opaque failure"

# Test 10d: Dead-code wired at Step 3A.5C post-review advisory (Phase 33 / P3.10)
echo ""
echo "Test 10d: lib/dead-code.sh wired at Step 3A.5C"
check "dead-code source line present" 'source "$REPO_ROOT/lib/dead-code.sh"'
check "DEAD_CODE_AVAILABLE fallback flag" "DEAD_CODE_AVAILABLE=true"
check "3A.5C header present" "3A.5C: Post-generation dead-code check"
check "find_post_commit_dead invoked" 'find_post_commit_dead "$BASE_SHA" "HEAD"'
check "advisory trailer generated" "Dead-Code: advisory"
check "clean-case trailer" "Dead-Code: clean"
check "side-file path for progress attach" ".quantum-dead-code.\$STORY_ID.json"
check "non-blocking by design documented" "non-blocking by design"

# Test 10e: Intent-graph wired at Step 3A.5D advisory (Phase 32 / P3.6)
echo ""
echo "Test 10e: lib/intent-graph.sh wired at Step 3A.5D"
check "intent-graph source line present" 'source "$REPO_ROOT/lib/intent-graph.sh"'
check "INTENT_GRAPH_AVAILABLE fallback flag" "INTENT_GRAPH_AVAILABLE=true"
check "3A.5D header present" "3A.5D: Intent-graph drift check"
check "extract_story_intents invoked" "| extract_story_intents"
check "extract_code_intents invoked" 'extract_code_intents "$f"'
check "match_intents invoked" 'match_intents "$STORY_INTENTS"'
check "intent trailer form" "Intent-Graph: jaccard="
check "bidirectional drift documented" "bidirectional"
check "side-file path" ".quantum-intent-graph.\$STORY_ID.json"

# Test 10f: Skeleton wired at Step 3A.1 preview + Step 3A.5E drift (Phase 31 / P3.1)
echo ""
echo "Test 10f: lib/skeleton.sh wired at 3A.1 + 3A.5E"
check "skeleton source line present" 'source "$REPO_ROOT/lib/skeleton.sh"'
check "SKELETON_AVAILABLE fallback flag" "SKELETON_AVAILABLE=true"
check "3A.1 pre-skeleton preview step" "Skeleton preview"
check "pre-skeleton side-file" ".quantum-skeleton-pre.\$STORY_ID.md"
check "skeleton_text invoked in pre" "skeleton_text \"\$f\""
check "3A.5E header present" "3A.5E: Skeleton drift check"
check "skeleton_diff invoked" 'skeleton_diff "$PRE_TMP" "$POST_TMP"'
check "trailer form has added/removed/changed" "Skeleton: added="
check "post-task side-file" ".quantum-skeleton-diff.\$STORY_ID.json"

# Test 10g: Trajectory wired into monitor loop (Phase 24 / P3.5)
echo ""
echo "Test 10g: lib/trajectory.sh wired in Step 3B.3"
check "trajectory source line present" 'source "$REPO_ROOT/lib/trajectory.sh"'
check "TRAJECTORY_AVAILABLE fallback flag" "TRAJECTORY_AVAILABLE=true"
check "Trajectory tick header" "Trajectory tick"
check "parse_trajectory invoked" 'parse_trajectory "$LOG"'
check "should_early_kill gate" "| should_early_kill"
check "classify_trajectory for log category" "| classify_trajectory"
check "agent log uses spawn.sh convention" ".ql-wt/\$sid/.ql-agent-output.txt"
check "reap_agent integration (Phase 20)" "reap_agent"
check "failureLog phase=trajectory-\$cls" '"trajectory-" + $cls'

# Test 10h: Conflict-grade wired into merge-strategy (Phase 38 / P3.2)
echo ""
echo "Test 10h: lib/conflict-grade.sh wired in merge-strategy.sh"
MERGE_STRATEGY="$REPO_ROOT/lib/merge-strategy.sh"
check_ms() {
  local name="$1" needle="$2"
  TOTAL=$((TOTAL + 1))
  if grep -qF -- "$needle" "$MERGE_STRATEGY"; then
    echo "  PASS: $name"; PASS=$((PASS + 1))
  else
    echo "  FAIL: $name — needle [$needle] not in merge-strategy.sh"
    FAIL=$((FAIL + 1))
  fi
}
check_ms "conflict-grade source line" 'source "$MERGE_STRATEGY_LIB_DIR/conflict-grade.sh"'
check_ms "CONFLICT_GRADE_AVAILABLE fallback" "CONFLICT_GRADE_AVAILABLE=true"
check_ms "grade_file invoked per conflict" "grade_file \"\$file\""
check_ms "routing_recommendation logged" "routing_recommendation \"\$cg_max\""
check_ms "grade 5 short-circuit to escalate" "grade 5 (structural)"

# Test 10i: HyClone wired at wave-boundary 3C.NEG0 (Phase 25 / P3.7)
echo ""
echo "Test 10i: lib/hyclone.sh wired at Step 3C.NEG0"
check "hyclone source line present" 'source "$REPO_ROOT/lib/hyclone.sh"'
check "HYCLONE_AVAILABLE fallback flag" "HYCLONE_AVAILABLE=true"
check "3C.NEG0 header present" "3C.NEG0: Wave-boundary semantic clone scan"
check "find_clones invoked" "| find_clones"
check "uses WAVE_BASE_SHA diff"  'git diff --name-only "$WAVE_BASE_SHA" HEAD'
check "persists for deep-review"  ".quantum-hyclone-wave.json"
check "advisory not blocking documented" "advisory"

# Test 11: classify_age doc comment fixed (Phase 21 consistency fix)
echo ""
echo "Test 11: lib/watchdog.sh doc comment corrected"
WATCHDOG="$REPO_ROOT/lib/watchdog.sh"
TOTAL=$((TOTAL + 1))
if grep -qF '>30 min = timed-out' "$WATCHDOG"; then
  echo "  PASS: watchdog threshold comment matches code (>30 min = timed-out)"
  PASS=$((PASS + 1))
else
  echo "  FAIL: watchdog comment still says '>20 min = timeout'"
  FAIL=$((FAIL + 1))
fi

echo ""
echo "=== Results: $PASS/$TOTAL passed, $FAIL failed ==="
exit $((FAIL > 0 ? 1 : 0))
