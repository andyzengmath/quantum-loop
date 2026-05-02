#!/usr/bin/env bash
# N6-followup / US-001 (v0.6.9) — orchestrator-liveness lib helper tests.
#
# Structural assertions only — no timing-fragile backgrounded git race. The
# wall-clock-sensitive tests use generous ceilings (timeout_sec * 3) to
# tolerate Git Bash sleep jitter on loaded hosts (~50% over nominal observed).
#
# Test header note: may flake on heavily-loaded Git Bash hosts where sleep
# jitter exceeds 50% of nominal — re-run if flaky.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$SCRIPT_DIR/.."
LIB="$REPO_ROOT/lib/orchestrator-liveness.sh"
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

echo "=== US-001 N6-followup orchestrator-liveness tests ==="

# Test 1: function defined after sourcing the lib
echo ""
echo "Test 1: poll_orchestrator_commits is defined after sourcing lib/orchestrator-liveness.sh"
TOTAL=$((TOTAL + 1))
fn_defined=$(bash -c "source '$LIB' && declare -F poll_orchestrator_commits >/dev/null && echo yes || echo no")
if [[ "$fn_defined" == "yes" ]]; then
  echo "  PASS: function defined"; PASS=$((PASS + 1))
else
  echo "  FAIL: function not defined after source"; FAIL=$((FAIL + 1))
fi

# Test 2: stale path — no new commits during the window → exit 1 + STALE log
echo ""
echo "Test 2: stale path returns 1 within timeout_sec*3 ceiling + emits STALE log"
TMP=$(mktemp -d)
( cd "$TMP" && git init -q && git config user.email "t@t.t" && git config user.name "t" \
  && echo "init" > README.md && git add README.md && git commit -qm "init" ) >/dev/null 2>&1

t0=$(date +%s)
out=$(cd "$TMP" && bash -c "source '$LIB' && poll_orchestrator_commits 2 1" 2>&1 || true)
rc=$(cd "$TMP" && bash -c "source '$LIB' && poll_orchestrator_commits 2 1 >/dev/null 2>&1 ; echo \$?")
t1=$(date +%s)
elapsed=$((t1 - t0))

assert "stale path exit code = 1" "1" "$rc"
TOTAL=$((TOTAL + 1))
if (( elapsed <= 30 )); then  # v0.8.2 / US-003 audit-followup: bumped 20 -> 30s for Git Bash worst-case jitter (observed 21s post-v0.8.1; aligned with other liveness wall-clock ceilings); see references/test-wallclock-baselines.md
  echo "  PASS: stale path completed in ${elapsed}s (<=30s ceiling — Git Bash subprocess jitter tolerated)"
  PASS=$((PASS + 1))
else
  echo "  FAIL: stale path took ${elapsed}s (>30s ceiling — investigate; refer to references/test-wallclock-baselines.md)"
  FAIL=$((FAIL + 1))
fi
TOTAL=$((TOTAL + 1))
if printf '%s' "$out" | grep -qE '^\[LIVENESS\] STALE: no commits in 2s'; then
  echo "  PASS: STALE stderr log line emitted"; PASS=$((PASS + 1))
else
  echo "  FAIL: STALE log line missing — out: $out"; FAIL=$((FAIL + 1))
fi

# Test 3: live path — pre-staged HEAD-advance via backgrounded checkout B
echo ""
echo "Test 3: live path returns 0 + emits new-commit log when HEAD advances mid-poll"
( cd "$TMP" && echo "B" > a.txt && git add a.txt && git commit -qm "commit-B" ) >/dev/null 2>&1
COMMIT_B=$(cd "$TMP" && git rev-parse HEAD)
( cd "$TMP" && git reset --hard HEAD~1 ) >/dev/null 2>&1

# Background: after 2s, fast-forward back to commit-B (advance HEAD).
( sleep 2 && cd "$TMP" && git reset --hard "$COMMIT_B" >/dev/null 2>&1 ) &
bg_pid=$!

# Soliton-pr-review caught at confidence 90 (v0.6.9 PR #70): the previous
# pattern `out=$(... || true)` followed by `rc=$?` captures the exit code
# of the assignment's subshell (always 0 due to `|| true` swallowing the
# inner exit), making the rc-assertion below vacuously always-pass. Fix:
# capture exit code via `out=$(...) || rc=$?` so the inner exit propagates
# without aborting under set -uo pipefail.
t0=$(date +%s)
rc=0
out=$(cd "$TMP" && bash -c "source '$LIB' && poll_orchestrator_commits 10 1" 2>&1) || rc=$?
t1=$(date +%s)
elapsed=$((t1 - t0))
wait $bg_pid 2>/dev/null

assert "live path exit code = 0" "0" "$rc"
TOTAL=$((TOTAL + 1))
if (( elapsed <= 30 )); then
  echo "  PASS: live path completed in ${elapsed}s (<=30s ceiling)"; PASS=$((PASS + 1))
else
  echo "  FAIL: live path took ${elapsed}s"; FAIL=$((FAIL + 1))
fi
TOTAL=$((TOTAL + 1))
if printf '%s' "$out" | grep -qE '^\[LIVENESS\] new commit'; then
  echo "  PASS: 'new commit' stderr log line emitted"; PASS=$((PASS + 1))
else
  echo "  FAIL: 'new commit' log line missing — out: $out"; FAIL=$((FAIL + 1))
fi

rm -rf "$TMP"

# Test 4: default-arg behavior — function source contains 600 / 60 defaults
echo ""
echo "Test 4: function source uses documented defaults (timeout=600, interval=60)"
TOTAL=$((TOTAL + 1))
if grep -q '\${1:-600}' "$LIB" && grep -q '\${2:-60}' "$LIB"; then
  echo "  PASS: 600 / 60 defaults present in source"; PASS=$((PASS + 1))
else
  echo "  FAIL: default values not found in lib source"; FAIL=$((FAIL + 1))
fi

# Test 5: N16 / US-004 (v0.7.0) — interval_sec=0 guard
echo ""
echo "Test 5: poll_orchestrator_commits 10 0 returns 1 with ERROR log (interval_sec=0 guard)"
TMP=$(mktemp -d)
( cd "$TMP" && git init -q && git config user.email "t@t.t" && git config user.name "t" \
  && echo "init" > README.md && git add README.md && git commit -qm "init" ) >/dev/null 2>&1

t0=$(date +%s)
out=$(cd "$TMP" && bash -c "source '$LIB' && poll_orchestrator_commits 10 0" 2>&1 || true)
rc=$(cd "$TMP" && bash -c "source '$LIB' && poll_orchestrator_commits 10 0 >/dev/null 2>&1 ; echo \$?")
t1=$(date +%s)
elapsed=$((t1 - t0))

assert "interval_sec=0 guard exit code = 1" "1" "$rc"
TOTAL=$((TOTAL + 1))
# Soliton-pr-review caught at confidence 82 (v0.7.0 PR #71): the previous 2s
# ceiling was too tight for two `bash -c "source ..."` subprocess launches
# on Git Bash / Windows (each can take 0.5-1.5s startup). Raised to 6s to
# match the proportional generosity used in Test 2 (12s ceiling for two
# invocations of a 2s poll). The guard itself returns in microseconds; the
# ceiling measures subprocess launch overhead, not the function logic.
if (( elapsed <= 10 )); then  # v0.8.2 / US-003: bumped 6 -> 10s for Git Bash subprocess jitter (see references/test-wallclock-baselines.md). Same class as v0.8.1 Test 2 fix.
  echo "  PASS: guard returns within 10s (no infinite-loop hazard; subprocess-launch headroom + Git Bash jitter tolerated)"; PASS=$((PASS + 1))
else
  echo "  FAIL: guard took ${elapsed}s (>10s ceiling — investigate; refer to references/test-wallclock-baselines.md)"; FAIL=$((FAIL + 1))
fi
TOTAL=$((TOTAL + 1))
if printf '%s' "$out" | grep -qE '^\[LIVENESS\] ERROR: interval_sec must be > 0'; then
  echo "  PASS: ERROR stderr log line emitted (NOT STALE)"; PASS=$((PASS + 1))
else
  echo "  FAIL: ERROR log line missing (or wrong format)"; FAIL=$((FAIL + 1))
fi
TOTAL=$((TOTAL + 1))
if printf '%s' "$out" | grep -qE 'STALE'; then
  echo "  FAIL: STALE log emitted on guard path (should be ERROR only)"; FAIL=$((FAIL + 1))
else
  echo "  PASS: no STALE log on guard path (correct — fail-fast before timeout loop)"; PASS=$((PASS + 1))
fi
rm -rf "$TMP"

# Test 6: N20 / US-002 (v0.7.1) — wrap_orchestrator_dispatch QL_LIVENESS_ENABLE=false silent skip
echo ""
echo "Test 6: wrap_orchestrator_dispatch with QL_LIVENESS_ENABLE=false returns 0 silently"
TMP6=$(mktemp -d)
( cd "$TMP6" && git init -q && git config user.email "t@t.t" && git config user.name "t" \
  && echo "init" > README.md && git add README.md && git commit -qm "init" ) >/dev/null 2>&1
out6=$(cd "$TMP6" && QL_LIVENESS_ENABLE=false bash -c "source '$LIB' && wrap_orchestrator_dispatch 2 1" 2>&1 || true)
rc6=$(cd "$TMP6" && QL_LIVENESS_ENABLE=false bash -c "source '$LIB' && wrap_orchestrator_dispatch 2 1 >/dev/null 2>&1 ; echo \$?")
assert "Test 6: opt-out exit code = 0 (silent skip)" "0" "$rc6"
TOTAL=$((TOTAL + 1))
if [[ -z "$out6" ]] || [[ "$out6" == "" ]]; then
  echo "  PASS: opt-out emits no stdout/stderr (silent)"; PASS=$((PASS + 1))
else
  echo "  FAIL: opt-out emitted unexpected output: $out6"; FAIL=$((FAIL + 1))
fi
rm -rf "$TMP6"

# Test 7: wrap_orchestrator_dispatch default-on with stale repo emits handoff + rc=1
echo ""
echo "Test 7: wrap_orchestrator_dispatch default + stale repo -> handoff stdout + rc=1"
TMP7=$(mktemp -d)
( cd "$TMP7" && git init -q && git config user.email "t@t.t" && git config user.name "t" \
  && echo "init" > README.md && git add README.md && git commit -qm "init" ) >/dev/null 2>&1
t0=$(date +%s)
rc7=0
out7=$(cd "$TMP7" && bash -c "source '$LIB' && wrap_orchestrator_dispatch 2 1" 2>&1) || rc7=$?
t1=$(date +%s)
elapsed=$((t1 - t0))
assert "Test 7: stale path exit code = 1" "1" "$rc7"
TOTAL=$((TOTAL + 1))
if (( elapsed <= 25 )); then  # v0.8.2 / US-003 audit-followup: bumped 10 -> 25s for Git Bash worst-case fork-overhead jitter (observed 15s)
  echo "  PASS: stale-path completed within 25s (got ${elapsed}s)"; PASS=$((PASS + 1))
else
  echo "  FAIL: stale-path took ${elapsed}s (>25s — investigate; refer to references/test-wallclock-baselines.md)"; FAIL=$((FAIL + 1))
fi
TOTAL=$((TOTAL + 1))
if printf '%s' "$out7" | grep -qE 'orchestrator-stale signal'; then
  echo "  PASS: handoff message emitted to stdout"; PASS=$((PASS + 1))
else
  echo "  FAIL: handoff message missing from stdout"; FAIL=$((FAIL + 1))
fi
TOTAL=$((TOTAL + 1))
if printf '%s' "$out7" | grep -q 'references/orchestrator-takeover.md'; then
  echo "  PASS: handoff cross-links references/orchestrator-takeover.md"; PASS=$((PASS + 1))
else
  echo "  FAIL: handoff missing cross-link to takeover SOP"; FAIL=$((FAIL + 1))
fi
rm -rf "$TMP7"

# Test 8: N24 / US-001 (v0.7.2) — QL_RESPAWN_CMD set + STALE -> respawn cmd executed, rc=0
echo ""
echo "Test 8: wrap_orchestrator_dispatch QL_RESPAWN_CMD set + stale -> respawn executed rc=0 (wall-clock <10s)"
TMP8=$(mktemp -d)
( cd "$TMP8" && git init -q && git config user.email "t@t.t" && git config user.name "t" \
  && echo "init" > README.md && git add README.md && git commit -qm "init" ) >/dev/null 2>&1
t0=$(date +%s)
rc8=0
out8=$(cd "$TMP8" && QL_RESPAWN_CMD="echo respawned" bash -c "source '$LIB' && wrap_orchestrator_dispatch 2 1" 2>&1) || rc8=$?
t1=$(date +%s)
elapsed=$((t1 - t0))
assert "Test 8: QL_RESPAWN_CMD respawn rc=0" "0" "$rc8"
TOTAL=$((TOTAL + 1))
if (( elapsed <= 25 )); then  # v0.8.2 / US-003 audit-followup: bumped 10 -> 25s for Git Bash jitter (observed 11s)
  echo "  PASS: stale+respawn completed within 25s (got ${elapsed}s)"; PASS=$((PASS + 1))
else
  echo "  FAIL: stale+respawn took ${elapsed}s (>25s — investigate; refer to references/test-wallclock-baselines.md)"; FAIL=$((FAIL + 1))
fi
TOTAL=$((TOTAL + 1))
if printf '%s' "$out8" | grep -q 'respawned'; then
  echo "  PASS: respawn command output 'respawned' present in stdout"; PASS=$((PASS + 1))
else
  echo "  FAIL: 'respawned' not found in stdout — out: $out8"; FAIL=$((FAIL + 1))
fi
TOTAL=$((TOTAL + 1))
if printf '%s' "$out8" | grep -qE 'orchestrator-stale .* respawning via QL_RESPAWN_CMD'; then
  echo "  PASS: respawn-trigger diagnostic emitted to stderr"; PASS=$((PASS + 1))
else
  echo "  FAIL: respawn-trigger diagnostic missing — out: $out8"; FAIL=$((FAIL + 1))
fi
rm -rf "$TMP8"

# Test 9: N24 / US-001 (v0.7.2) — QL_RESPAWN_CMD unset + STALE -> handoff + rc=1 (v0.7.1 regression guard)
echo ""
echo "Test 9: wrap_orchestrator_dispatch QL_RESPAWN_CMD unset + stale -> handoff rc=1 (regression guard)"
TMP9=$(mktemp -d)
( cd "$TMP9" && git init -q && git config user.email "t@t.t" && git config user.name "t" \
  && echo "init" > README.md && git add README.md && git commit -qm "init" ) >/dev/null 2>&1
rc9=0
out9=$(cd "$TMP9" && bash -c "source '$LIB' && wrap_orchestrator_dispatch 2 1" 2>&1) || rc9=$?
assert "Test 9: unset QL_RESPAWN_CMD fallback rc=1" "1" "$rc9"
TOTAL=$((TOTAL + 1))
if printf '%s' "$out9" | grep -qE 'orchestrator-stale signal'; then
  echo "  PASS: handoff message present (v0.7.1 behavior unchanged)"; PASS=$((PASS + 1))
else
  echo "  FAIL: handoff message missing — out: $out9"; FAIL=$((FAIL + 1))
fi
rm -rf "$TMP9"

# Test 10: N24 soliton-fix — failing QL_RESPAWN_CMD propagates non-zero exit code
echo ""
echo "Test 10: wrap_orchestrator_dispatch failing QL_RESPAWN_CMD propagates rc=42 (wall-clock <10s)"
TMP10=$(mktemp -d)
( cd "$TMP10" && git init -q && git config user.email "t@t.t" && git config user.name "t" \
  && echo "init" > README.md && git add README.md && git commit -qm "init" ) >/dev/null 2>&1
t0=$(date +%s)
rc10=0
out10=$(cd "$TMP10" && QL_RESPAWN_CMD="exit 42" bash -c "source '$LIB' && wrap_orchestrator_dispatch 2 1" 2>&1) || rc10=$?
t1=$(date +%s)
elapsed=$((t1 - t0))
assert "Test 10: failing QL_RESPAWN_CMD propagates rc=42" "42" "$rc10"
TOTAL=$((TOTAL + 1))
if (( elapsed <= 25 )); then  # v0.8.2 / US-003 audit-followup: bumped 10 -> 25s for Git Bash jitter (observed 14s)
  echo "  PASS: stale+failing-respawn completed within 25s (got ${elapsed}s)"; PASS=$((PASS + 1))
else
  echo "  FAIL: stale+failing-respawn took ${elapsed}s (>25s — investigate; refer to references/test-wallclock-baselines.md)"; FAIL=$((FAIL + 1))
fi
TOTAL=$((TOTAL + 1))
if printf '%s' "$out10" | grep -qE 'QL_RESPAWN_CMD exited 42 .* respawn may have failed'; then
  echo "  PASS: failing-respawn diagnostic emitted to stderr"; PASS=$((PASS + 1))
else
  echo "  FAIL: failing-respawn diagnostic missing — out: $out10"; FAIL=$((FAIL + 1))
fi
rm -rf "$TMP10"

# Test 11: N25 / US-001 (v0.7.4) — QL_RESPAWN_CMD real-CLI smoke test
echo ""
echo "Test 11: wrap_orchestrator_dispatch QL_RESPAWN_CMD=claude --version + stale -> respawn rc=0 (skip-pass if claude absent)"
if ! command -v claude >/dev/null 2>&1; then
  printf "[N25] WARN: claude CLI not available in PATH — skip-pass\n" >&2
  # Soliton-fix: write deferred-finding to a tmp path (not the repo working tree)
  # to avoid leaking test artifacts. The handoff serves as a one-time signal —
  # if the operator wants persistent capture, they wire the path explicitly.
  N25_DEFER=$(mktemp -t n25-deferred.XXXXXX)
  printf '{"finding":"n25-deferred","reason":"claude CLI absent","timestamp":"%s","host":"%s"}\n' \
    "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "${HOSTNAME:-unknown}" \
    > "$N25_DEFER"
  TOTAL=$((TOTAL + 1))
  echo "  PASS: Test 11 skipped (claude unavailable; deferred-finding emitted to $N25_DEFER)"; PASS=$((PASS + 1))
  rm -f "$N25_DEFER"
else
  TMP11=$(mktemp -d)
  ( cd "$TMP11" && git init -q && git config user.email "t@t.t" && git config user.name "t" \
    && echo "init" > README.md && git add README.md && git commit -qm "init" ) >/dev/null 2>&1
  t0=$(date +%s)
  rc11=0
  out11=$(cd "$TMP11" && QL_RESPAWN_CMD="claude --version" bash -c "source '$LIB' && wrap_orchestrator_dispatch 2 1" 2>&1) || rc11=$?
  t1=$(date +%s)
  elapsed=$((t1 - t0))
  assert "Test 11: real-CLI respawn rc=0" "0" "$rc11"
  TOTAL=$((TOTAL + 1))
  if (( elapsed <= 30 )); then  # v0.8.2 / US-003 audit-followup: bumped 15 -> 30s for Git Bash jitter (observed 20s; real-CLI invocation has extra startup overhead)
    echo "  PASS: real-CLI respawn completed within 30s (got ${elapsed}s)"; PASS=$((PASS + 1))
  else
    echo "  FAIL: real-CLI respawn took ${elapsed}s (>30s — investigate; refer to references/test-wallclock-baselines.md)"; FAIL=$((FAIL + 1))
  fi
  TOTAL=$((TOTAL + 1))
  # Soliton-fix: anchor regex to claude-specific output line to avoid false-positive
  # matches against unrelated diagnostic numbers (e.g. liveness timeouts).
  if printf '%s' "$out11" | grep -qE '(^|[^0-9])[0-9]+\.[0-9]+\.[0-9]+ \(Claude'; then
    echo "  PASS: claude --version stdout matches Claude-specific version pattern"; PASS=$((PASS + 1))
  elif printf '%s' "$out11" | grep -qE 'claude/[0-9]+\.[0-9]+\.[0-9]+'; then
    echo "  PASS: claude --version stdout matches claude/X.Y.Z pattern"; PASS=$((PASS + 1))
  else
    echo "  FAIL: claude --version output missing recognizable Claude version pattern — out: $out11"; FAIL=$((FAIL + 1))
  fi
  rm -rf "$TMP11"
fi

# Test 12: US-002 (v0.8.0 N33) — worktree-aware poll_orchestrator_commits, STALE worktree
echo ""
echo "Test 12: poll_orchestrator_commits with WORKTREE_PATH on stale worktree -> rc=1"
TMP12=$(mktemp -d)
( cd "$TMP12" && git init -q && git config user.email "t@t.t" && git config user.name "t" \
  && echo "init" > README.md && git add README.md && git commit -qm "init" ) >/dev/null 2>&1
mkdir -p "$TMP12/wt"
( cd "$TMP12" && git worktree add -q "$TMP12/wt" -b feature ) >/dev/null 2>&1
rc12=0
# Use poll_orchestrator_commits with a 4th arg = worktree path; STALE on the worktree path
out12=$(cd "$TMP12" && bash -c "source '$LIB' && poll_orchestrator_commits 2 1 \"\" '$TMP12/wt'" 2>&1 || true)
rc12=$(cd "$TMP12" && bash -c "source '$LIB' && poll_orchestrator_commits 2 1 \"\" '$TMP12/wt' >/dev/null 2>&1; echo \$?")
assert "Test 12: worktree-path STALE rc=1" "1" "$rc12"
TOTAL=$((TOTAL + 1))
if printf '%s' "$out12" | grep -qE '\[LIVENESS\] STALE'; then
  echo "  PASS: STALE log emitted for worktree path"; PASS=$((PASS + 1))
else
  echo "  FAIL: STALE log missing for worktree path — out: $out12"; FAIL=$((FAIL + 1))
fi
rm -rf "$TMP12"

# Test 13: US-002 — worktree-aware poll detects LIVE when worktree HEAD advances
echo ""
echo "Test 13: poll_orchestrator_commits with WORKTREE_PATH detects worktree HEAD advance"
TMP13=$(mktemp -d)
( cd "$TMP13" && git init -q && git config user.email "t@t.t" && git config user.name "t" \
  && echo "init" > README.md && git add README.md && git commit -qm "init" ) >/dev/null 2>&1
( cd "$TMP13" && git worktree add -q "$TMP13/wt" -b feature ) >/dev/null 2>&1
( sleep 2 && cd "$TMP13/wt" && echo "B" > a.txt && git add a.txt && git commit -qm "advance" >/dev/null 2>&1 ) &
bg_pid=$!
rc13=0
out13=$(cd "$TMP13" && bash -c "source '$LIB' && poll_orchestrator_commits 10 1 \"\" '$TMP13/wt'" 2>&1) || rc13=$?
wait $bg_pid 2>/dev/null
assert "Test 13: worktree-path LIVE rc=0" "0" "$rc13"
TOTAL=$((TOTAL + 1))
if printf '%s' "$out13" | grep -qE '\[LIVENESS\] new commit'; then
  echo "  PASS: new-commit log emitted for worktree path"; PASS=$((PASS + 1))
else
  echo "  FAIL: new-commit log missing for worktree path — out: $out13"; FAIL=$((FAIL + 1))
fi
rm -rf "$TMP13"

# Test 14: v0.10.11 / US-001 (N46 closure) — respawn output is re-parsed
# and updates SIGNAL_RESULT/SIGNAL_CONFIDENCE.
echo ""
echo "Test 14: wrap_orchestrator_dispatch re-parses QL_RESPAWN_CMD output (N46 closure)"
TMP14=$(mktemp -d)
( cd "$TMP14" && git init -q && git config user.email "t@t.t" && git config user.name "t" \
  && echo "init" > README.md && git add README.md && git commit -qm "init" ) >/dev/null 2>&1

# Mock respawn: emit STORY_PASSED signal then exit 0.
RESPAWN_SCRIPT="$TMP14/mock-respawn.sh"
cat > "$RESPAWN_SCRIPT" <<'EOSH'
#!/usr/bin/env bash
echo "<quantum>STORY_PASSED</quantum>"
exit 0
EOSH
chmod +x "$RESPAWN_SCRIPT"

# Run wrap with tiny timeout (forces STALE path) + QL_RESPAWN_CMD set.
# Pre-set SIGNAL_RESULT=STORY_FAILED to simulate prior failed parse.
RUNNER_LIB="$REPO_ROOT/lib/runner.sh"
out14=$(cd "$TMP14" && bash -c "
  source '$RUNNER_LIB' >/dev/null 2>&1
  source '$LIB'
  SIGNAL_RESULT='STORY_FAILED'
  SIGNAL_CONFIDENCE='high'
  export QL_RESPAWN_CMD='bash $RESPAWN_SCRIPT'
  wrap_orchestrator_dispatch 1 1 >/dev/null 2>&1
  echo \"SIGNAL_RESULT=\$SIGNAL_RESULT SIGNAL_CONFIDENCE=\$SIGNAL_CONFIDENCE\"
" 2>&1)

TOTAL=$((TOTAL + 1))
if printf '%s' "$out14" | grep -q "SIGNAL_RESULT=STORY_PASSED"; then
  echo "  PASS: SIGNAL_RESULT updated to STORY_PASSED after respawn re-parse"
  PASS=$((PASS + 1))
else
  echo "  FAIL: SIGNAL_RESULT not updated — out: $out14"
  FAIL=$((FAIL + 1))
fi

TOTAL=$((TOTAL + 1))
if printf '%s' "$out14" | grep -q "SIGNAL_CONFIDENCE=exact"; then
  echo "  PASS: SIGNAL_CONFIDENCE updated to exact after respawn re-parse"
  PASS=$((PASS + 1))
else
  echo "  FAIL: SIGNAL_CONFIDENCE not updated to exact — out: $out14"
  FAIL=$((FAIL + 1))
fi
rm -rf "$TMP14"

# Test 15: v0.10.11 / US-001 (N46) — graceful when runner_parse_output is
# NOT sourced (standalone usage); respawn rc still propagates.
echo ""
echo "Test 15: wrap_orchestrator_dispatch graceful without runner_parse_output"
TMP15=$(mktemp -d)
( cd "$TMP15" && git init -q && git config user.email "t@t.t" && git config user.name "t" \
  && echo "init" > README.md && git add README.md && git commit -qm "init" ) >/dev/null 2>&1

RESPAWN_SCRIPT15="$TMP15/mock-respawn.sh"
cat > "$RESPAWN_SCRIPT15" <<'EOSH'
#!/usr/bin/env bash
echo "respawn-output-without-signal"
exit 0
EOSH
chmod +x "$RESPAWN_SCRIPT15"

# Source ONLY orchestrator-liveness.sh (not runner.sh) — runner_parse_output
# undefined. Wrap should not error; respawn rc=0 should propagate.
rc15=$(cd "$TMP15" && bash -c "
  source '$LIB'
  export QL_RESPAWN_CMD='bash $RESPAWN_SCRIPT15'
  wrap_orchestrator_dispatch 1 1 >/dev/null 2>&1
  echo \$?
")

assert "Test 15: respawn rc=0 propagates without runner_parse_output" "0" "$rc15"
rm -rf "$TMP15"

echo ""
echo "=== Results: $PASS/$TOTAL passed, $FAIL failed ==="
[[ $FAIL -eq 0 ]] || exit 1
