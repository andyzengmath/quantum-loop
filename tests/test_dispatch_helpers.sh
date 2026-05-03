#!/usr/bin/env bash
# tests/test_dispatch_helpers.sh
#
# v0.11.4 / US-002 (Path E split): dispatch-helper functions in
# lib/orchestrator-liveness.sh that go BEYOND base wrap behavior.
# Split out from tests/test_orchestrator_liveness.sh which crossed the
# architect's 600-LOC threshold at v0.11.1 ship.
#
# Coverage:
#   - N46 (v0.10.11) — wrap_orchestrator_dispatch respawn output re-parsing
#     (SIGNAL_RESULT/SIGNAL_CONFIDENCE updated; rc!=0 under set -euo pipefail;
#     graceful when runner_parse_output absent).
#   - N43 (v0.11.1) — dispatch_with_parallel_poll bg-spawn + commit-poll +
#     kill-cascade (clean completion, STALE-kill, commit-progress reset).
#
# Sister file: tests/test_orchestrator_liveness.sh covers
# poll_orchestrator_commits + wrap_orchestrator_dispatch base/respawn/
# worktree-aware (Tests 1-13 there).

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$SCRIPT_DIR/.."
LIB="$REPO_ROOT/lib/orchestrator-liveness.sh"
RUNNER_LIB="$REPO_ROOT/lib/runner.sh"
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

echo "=== v0.11.4 dispatch-helper tests (N46 respawn re-parse + N43 parallel-poll) ==="

# Test 1: v0.10.11 / US-001 (N46 closure) — respawn output is re-parsed
# and updates SIGNAL_RESULT/SIGNAL_CONFIDENCE. (Was Test 14 in original.)
echo ""
echo "Test 1: wrap_orchestrator_dispatch re-parses QL_RESPAWN_CMD output (N46 closure)"
TMP1=$(mktemp -d)
( cd "$TMP1" && git init -q && git config user.email "t@t.t" && git config user.name "t" \
  && echo "init" > README.md && git add README.md && git commit -qm "init" ) >/dev/null 2>&1

# Mock respawn: emit STORY_PASSED signal then exit 0.
RESPAWN_SCRIPT="$TMP1/mock-respawn.sh"
cat > "$RESPAWN_SCRIPT" <<'EOSH'
#!/usr/bin/env bash
echo "<quantum>STORY_PASSED</quantum>"
exit 0
EOSH
chmod +x "$RESPAWN_SCRIPT"

# Run wrap with tiny timeout (forces STALE path) + QL_RESPAWN_CMD set.
# Pre-set SIGNAL_RESULT=STORY_FAILED to simulate prior failed parse.
out1=$(cd "$TMP1" && bash -c "
  source '$RUNNER_LIB' >/dev/null 2>&1
  source '$LIB'
  SIGNAL_RESULT='STORY_FAILED'
  SIGNAL_CONFIDENCE='high'
  export QL_RESPAWN_CMD='bash $RESPAWN_SCRIPT'
  wrap_orchestrator_dispatch 1 1 >/dev/null 2>&1
  echo \"SIGNAL_RESULT=\$SIGNAL_RESULT SIGNAL_CONFIDENCE=\$SIGNAL_CONFIDENCE\"
" 2>&1)

TOTAL=$((TOTAL + 1))
if printf '%s' "$out1" | grep -q "SIGNAL_RESULT=STORY_PASSED"; then
  echo "  PASS: SIGNAL_RESULT updated to STORY_PASSED after respawn re-parse"
  PASS=$((PASS + 1))
else
  echo "  FAIL: SIGNAL_RESULT not updated — out: $out1"
  FAIL=$((FAIL + 1))
fi

TOTAL=$((TOTAL + 1))
if printf '%s' "$out1" | grep -q "SIGNAL_CONFIDENCE=exact"; then
  echo "  PASS: SIGNAL_CONFIDENCE updated to exact after respawn re-parse"
  PASS=$((PASS + 1))
else
  echo "  FAIL: SIGNAL_CONFIDENCE not updated to exact — out: $out1"
  FAIL=$((FAIL + 1))
fi
rm -rf "$TMP1"

# Test 2: v0.10.11 / US-003 review fix (architect MEDIUM regression
# coverage) — respawn rc!=0 under `set -euo pipefail` no longer aborts
# the wrap; rc propagates correctly via `|| rc=$?` pattern. (Was Test 14c.)
echo ""
echo "Test 2: respawn rc!=0 under set -euo pipefail propagates without abort"
TMP2=$(mktemp -d)
( cd "$TMP2" && git init -q && git config user.email "t@t.t" && git config user.name "t" \
  && echo "init" > README.md && git add README.md && git commit -qm "init" ) >/dev/null 2>&1
RESPAWN_FAIL_SCRIPT="$TMP2/mock-respawn-fail.sh"
cat > "$RESPAWN_FAIL_SCRIPT" <<'EOSH'
#!/usr/bin/env bash
echo "respawn-output-with-failure"
exit 42
EOSH
chmod +x "$RESPAWN_FAIL_SCRIPT"

# Source under `set -euo pipefail` (production shell flags).
out2=$(cd "$TMP2" && bash -c "
  set -euo pipefail
  source '$RUNNER_LIB' >/dev/null 2>&1
  source '$LIB'
  RUNNER_HEURISTIC_FALLBACK=false
  export QL_RESPAWN_CMD='bash $RESPAWN_FAIL_SCRIPT'
  set +e
  wrap_orchestrator_dispatch 1 1 >/dev/null 2>&1
  rc=\$?
  set -e
  echo \"wrap_rc=\$rc\"
" 2>&1)

TOTAL=$((TOTAL + 1))
if printf '%s' "$out2" | grep -q "wrap_rc=42"; then
  echo "  PASS: wrap rc=42 propagated cleanly under set -euo pipefail"
  PASS=$((PASS + 1))
else
  echo "  FAIL: wrap rc=42 not propagated — out: $out2"
  FAIL=$((FAIL + 1))
fi
rm -rf "$TMP2"

# Test 3: v0.10.11 / US-001 (N46) — graceful when runner_parse_output is
# NOT sourced (standalone usage); respawn rc still propagates. (Was Test 15.)
echo ""
echo "Test 3: wrap_orchestrator_dispatch graceful without runner_parse_output"
TMP3=$(mktemp -d)
( cd "$TMP3" && git init -q && git config user.email "t@t.t" && git config user.name "t" \
  && echo "init" > README.md && git add README.md && git commit -qm "init" ) >/dev/null 2>&1

RESPAWN_SCRIPT3="$TMP3/mock-respawn.sh"
cat > "$RESPAWN_SCRIPT3" <<'EOSH'
#!/usr/bin/env bash
echo "respawn-output-without-signal"
exit 0
EOSH
chmod +x "$RESPAWN_SCRIPT3"

# Source ONLY orchestrator-liveness.sh (not runner.sh).
rc3=$(cd "$TMP3" && bash -c "
  source '$LIB'
  export QL_RESPAWN_CMD='bash $RESPAWN_SCRIPT3'
  wrap_orchestrator_dispatch 1 1 >/dev/null 2>&1
  echo \$?
")

assert "Test 3: respawn rc=0 propagates without runner_parse_output" "0" "$rc3"
rm -rf "$TMP3"

# Test 4: v0.11.1 / US-001 (N43) — dispatch_with_parallel_poll clean
# completion path. CMD exits 0 with output; rc=0 propagates; output
# captured. (Was Test 16.)
echo ""
echo "Test 4: dispatch_with_parallel_poll clean completion (CMD exits 0)"
TMP4=$(mktemp -d)
( cd "$TMP4" && git init -q && git config user.email "t@t.t" && git config user.name "t" \
  && echo "init" > README.md && git add README.md && git commit -qm "init" ) >/dev/null 2>&1

out4=$(cd "$TMP4" && bash -c "
  source '$LIB'
  dispatch_with_parallel_poll 5 1 'echo hello-from-child; exit 0'
")
rc4=$?

TOTAL=$((TOTAL + 1))
if printf '%s' "$out4" | grep -q "hello-from-child"; then
  echo "  PASS: child output captured"
  PASS=$((PASS + 1))
else
  echo "  FAIL: child output missing — out: $out4"
  FAIL=$((FAIL + 1))
fi
assert "Test 4: rc=0 propagates from clean completion" "0" "$rc4"
rm -rf "$TMP4"

# Test 5: v0.11.1 / US-001 (N43) — STALE-kill path. CMD `sleep 30`;
# timeout=2; assert rc != 0 + STALE log emitted within ~15s wallclock.
# (Was Test 17.)
echo ""
echo "Test 5: dispatch_with_parallel_poll STALE-kill (sleep 30 with timeout=2)"
TMP5=$(mktemp -d)
( cd "$TMP5" && git init -q && git config user.email "t@t.t" && git config user.name "t" \
  && echo "init" > README.md && git add README.md && git commit -qm "init" ) >/dev/null 2>&1

t0=$(date +%s)
out5=$(cd "$TMP5" && bash -c "
  source '$LIB'
  dispatch_with_parallel_poll 2 1 'sleep 30; echo never-reached' 2>&1
")
rc5=$?
t1=$(date +%s)
elapsed5=$((t1 - t0))

TOTAL=$((TOTAL + 1))
if (( rc5 != 0 )); then
  echo "  PASS: rc=$rc5 (non-zero from kill cascade)"
  PASS=$((PASS + 1))
else
  echo "  FAIL: rc=0 (expected non-zero from kill)"
  FAIL=$((FAIL + 1))
fi

TOTAL=$((TOTAL + 1))
if printf '%s' "$out5" | grep -q "STALE: no commits in .* killing PID"; then
  echo "  PASS: STALE-kill log emitted"
  PASS=$((PASS + 1))
else
  echo "  FAIL: STALE-kill log missing — out: $out5"
  FAIL=$((FAIL + 1))
fi

TOTAL=$((TOTAL + 1))
if (( elapsed5 <= 15 )); then
  echo "  PASS: kill cascade completed in ${elapsed5}s (≤15s ceiling)"
  PASS=$((PASS + 1))
else
  echo "  FAIL: kill cascade took ${elapsed5}s (>15s — investigate Git Bash jitter)"
  FAIL=$((FAIL + 1))
fi
rm -rf "$TMP5"

# Test 6: v0.11.1 / US-001 (N43) — commit-progress reset. CMD makes a
# commit during the poll window; verify commit resets the timeout window
# and CMD completes naturally without kill (rc=0). (Was Test 18.)
echo ""
echo "Test 6: dispatch_with_parallel_poll commit-progress resets timeout window"
TMP6=$(mktemp -d)
( cd "$TMP6" && git init -q && git config user.email "t@t.t" && git config user.name "t" \
  && echo "init" > README.md && git add README.md && git commit -qm "init" ) >/dev/null 2>&1

# CMD: sleeps 3s, makes a commit (resets window), sleeps another 1s, exits 0.
PROGRESS_CMD="cd '$TMP6' && sleep 3 && echo step1 > marker.txt && git add marker.txt && git commit -qm step1 && sleep 1 && exit 0"
t0=$(date +%s)
out6=$(cd "$TMP6" && bash -c "
  source '$LIB'
  dispatch_with_parallel_poll 4 1 \"$PROGRESS_CMD\" 2>&1
")
rc6=$?
t1=$(date +%s)
elapsed6=$((t1 - t0))

assert "Test 6: rc=0 from natural completion" "0" "$rc6"
TOTAL=$((TOTAL + 1))
if printf '%s' "$out6" | grep -q "new commit"; then
  echo "  PASS: commit-progress log emitted (LIVENESS detected progress)"
  PASS=$((PASS + 1))
else
  echo "  FAIL: commit-progress log missing — out: $out6"
  FAIL=$((FAIL + 1))
fi
TOTAL=$((TOTAL + 1))
if ! printf '%s' "$out6" | grep -q "STALE: no commits .* killing"; then
  echo "  PASS: no STALE-kill log (child completed naturally)"
  PASS=$((PASS + 1))
else
  echo "  FAIL: STALE-kill log appeared — out: $out6"
  FAIL=$((FAIL + 1))
fi
rm -rf "$TMP6"

echo ""
echo "=== Results: $PASS/$TOTAL passed, $FAIL failed ==="
[[ $FAIL -eq 0 ]] || exit 1
