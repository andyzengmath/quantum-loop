#!/usr/bin/env bash
# Phase 44 / US-001..US-004 — --audit flag tests.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$SCRIPT_DIR/.."
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

setup_audit_repo() {
  local d; d=$(mktemp -d)
  (
    cd "$d"
    git init -q
    git config user.email "t@t.t"
    git config user.name  "t"
    echo "initial" > README.md
    git add README.md && git commit -qm init
  )
  printf '%s' "$d"
}

# Source quantum-loop.sh in test mode — skips main arg-loop, just defines helpers.
# shellcheck disable=SC1091
QL_AUDIT_TEST_MODE=1 source "$REPO_ROOT/quantum-loop.sh"

echo "=== Phase 44 audit-flag tests ==="

# --- US-001 tests -----------------------------------------------------------

# Test 1: format_row OK shape
echo ""
echo "Test 1: _audit_format_row OK shape"
out=$(_audit_format_row 'branches-local|5|≤10|OK|')
case "$out" in
  *"branches-local:"*"5"*"(target ≤10)"*"OK"*)
    echo "  PASS: format_row OK shape"; PASS=$((PASS + 1));;
  *)
    echo "  FAIL: format_row OK shape — got [$out]"; FAIL=$((FAIL + 1));;
esac
TOTAL=$((TOTAL + 1))

# Test 2: format_row FAIL shape with drill
echo ""
echo "Test 2: _audit_format_row FAIL shape"
out=$(_audit_format_row 'cpc-files|2|0|FAIL|plugin-CPC.json, README-CPC.md')
case "$out" in
  *"cpc-files:"*"FAIL"*"└─"*"plugin-CPC.json"*)
    echo "  PASS: format_row FAIL shape with drill"; PASS=$((PASS + 1));;
  *)
    echo "  FAIL: format_row FAIL shape — got [$out]"; FAIL=$((FAIL + 1));;
esac
TOTAL=$((TOTAL + 1))

# Test 3: format_row FAIL with empty drill — no drill line
echo ""
echo "Test 3: _audit_format_row FAIL empty drill omits drill line"
out=$(_audit_format_row 'x|1|0|FAIL|')
line_count=$(printf '%s' "$out" | awk 'END{print NR}')
assert "empty-drill FAIL = 1 line" "1" "$line_count"

# Test 3b: format_row WARN with drill — drill line MUST render
# v0.6.5 post-merge soliton fix (conf 97). Before the fix, _audit_format_row
# only emitted the drill line on FAIL. G18's whole point — telling the
# operator "(expected on first run after install)" — was invisible.
echo ""
echo "Test 3b: _audit_format_row WARN renders drill line (G18 visibility)"
out=$(_audit_format_row 'pre-impl-review-coverage|0/3 stages|3/3|WARN|missing-csv (expected on first run after install)')
case "$out" in
  *"pre-impl-review-coverage:"*"WARN"*"└─"*"missing-csv"*"(expected on first run"*)
    echo "  PASS: WARN drill rendered with G18 hint"; PASS=$((PASS + 1));;
  *)
    echo "  FAIL: WARN drill suppressed — got [$out]"; FAIL=$((FAIL + 1));;
esac
TOTAL=$((TOTAL + 1))

# Test 3c: format_row WARN with empty drill — no drill line (symmetric to Test 3)
echo ""
echo "Test 3c: _audit_format_row WARN empty drill omits drill line"
out=$(_audit_format_row 'x|1|0|WARN|')
line_count=$(printf '%s' "$out" | awk 'END{print NR}')
assert "empty-drill WARN = 1 line" "1" "$line_count"

# Test 4: do_audit stub returns 0 and prints header
# G35 / US-001 (v0.6.7): use the two-invocation idiom (Platform Notes /
# pattern p008-A) to capture stdout AND exit code separately, with
# `|| true` on the stdout capture. Sourcing quantum-loop.sh inherits its
# `set -euo pipefail`. Without the `|| true`, any non-zero exit inside
# the do_audit subshell propagates errexit out of the $(...) substitution
# and aborts the test script silently — Test 4 (and every test after it)
# would never run to completion, hanging tests/run_all.sh's run_one
# capture indefinitely. v0.6.6's run_one fix exposed this previously-
# swallowed abort. Pattern A is preferred over an inline `set +e ... set -e`
# block here so this file stays under Pattern D (no literal set -e in
# the file), keeping the test_test_helpers.sh corpus audit clean.
#
# Run do_audit in a clean tmp repo (matching Test 5's pattern) so the
# "stub happy path" test does not depend on the developer's working repo
# state (e.g. >10 remote branches makes do_audit exit 1 environmentally).
# do_audit is read-only — invoking twice (once for stdout, once for rc)
# has no observable side effects.
echo ""
echo "Test 4: do_audit stub happy path"
TMP=$(setup_audit_repo)
mkdir -p "$TMP/.omc/phase-99-evidence"
printf '=== Results: 1/1 passed, 0 failed ===\n' > "$TMP/.omc/phase-99-evidence/test_x.log"
out=$(cd "$TMP" && do_audit 2>&1 || true)
rc=$(cd "$TMP" && do_audit >/dev/null 2>&1 ; echo $?)
assert "do_audit exits 0" "0" "$rc"
case "$out" in
  *"=== Quantum-loop audit ==="*"Summary:"*)
    echo "  PASS: header + summary present"; PASS=$((PASS + 1));;
  *)
    echo "  FAIL: do_audit output — got [$out]"; FAIL=$((FAIL + 1));;
esac
TOTAL=$((TOTAL + 1))
rm -rf "$TMP"

# Test 5: --audit clean repo exit 0 (seed green evidence so test-suites is OK)
echo ""
echo "Test 5: --audit clean repo exit 0"
TMP=$(setup_audit_repo)
mkdir -p "$TMP/.omc/phase-99-evidence"
printf '=== Results: 1/1 passed, 0 failed ===\n' > "$TMP/.omc/phase-99-evidence/test_x.log"
out=$(cd "$TMP" && bash "$REPO_ROOT/quantum-loop.sh" --audit 2>&1 || true)
rc=$(cd "$TMP" && bash "$REPO_ROOT/quantum-loop.sh" --audit >/dev/null 2>&1 ; echo $?)
TOTAL=$((TOTAL + 1))
if [[ "$rc" -eq 0 ]] && printf '%s' "$out" | grep -q '=== Quantum-loop audit ==='; then
  echo "  PASS: --audit clean repo exit 0"; PASS=$((PASS + 1))
else
  echo "  FAIL: --audit clean repo exit (rc=$rc, out=$out)"; FAIL=$((FAIL + 1))
fi
rm -rf "$TMP"

# Test 6: --audit exclusive-flag guard
echo ""
echo "Test 6: --audit exclusive"
out=$(bash "$REPO_ROOT/quantum-loop.sh" --audit --parallel 2>&1 || true)
rc=$(bash "$REPO_ROOT/quantum-loop.sh" --audit --parallel >/dev/null 2>&1 ; echo $?)
TOTAL=$((TOTAL + 1))
if [[ "$rc" -eq 2 ]] && printf '%s' "$out" | grep -q -- '--audit is exclusive'; then
  echo "  PASS: --audit exclusive exits 2 with clear error"; PASS=$((PASS + 1))
else
  echo "  FAIL: --audit exclusive guard (rc=$rc)"; FAIL=$((FAIL + 1))
fi

# --- US-002 tests -----------------------------------------------------------

# Test 7: _audit_branches_local OK on clean repo
echo ""
echo "Test 7: _audit_branches_local OK on clean tmp repo"
TMP=$(setup_audit_repo)
out=$(cd "$TMP" && _audit_branches_local)
case "$out" in
  branches-local\|0\|≤10\|OK\|*)
    echo "  PASS: branches_local OK on clean repo"; PASS=$((PASS + 1));;
  *)
    echo "  FAIL: branches_local OK — got [$out]"; FAIL=$((FAIL + 1));;
esac
TOTAL=$((TOTAL + 1))
rm -rf "$TMP"

# Test 8: _audit_branches_local FAIL when 12 branches exist
echo ""
echo "Test 8: _audit_branches_local FAIL over threshold"
TMP=$(setup_audit_repo)
(cd "$TMP" && for i in $(seq 1 12); do git branch "extra-$i" 2>/dev/null; done)
out=$(cd "$TMP" && _audit_branches_local)
case "$out" in
  branches-local\|12\|≤10\|FAIL\|*extra-*)
    echo "  PASS: branches_local FAIL with drill"; PASS=$((PASS + 1));;
  *)
    echo "  FAIL: branches_local FAIL — got [$out]"; FAIL=$((FAIL + 1));;
esac
TOTAL=$((TOTAL + 1))
rm -rf "$TMP"

# Test 9: _audit_branches_remote OK on clean repo
echo ""
echo "Test 9: _audit_branches_remote OK"
TMP=$(setup_audit_repo)
out=$(cd "$TMP" && _audit_branches_remote)
case "$out" in
  branches-remote\|0\|≤10\|OK\|*)
    echo "  PASS: branches_remote OK"; PASS=$((PASS + 1));;
  *)
    echo "  FAIL: branches_remote OK — got [$out]"; FAIL=$((FAIL + 1));;
esac
TOTAL=$((TOTAL + 1))
rm -rf "$TMP"

# Test 10: _audit_readme_conflicts OK on clean README
echo ""
echo "Test 10: _audit_readme_conflicts OK"
TMP=$(setup_audit_repo)
out=$(cd "$TMP" && _audit_readme_conflicts)
case "$out" in
  readme-conflicts\|0\|0\|OK\|*)
    echo "  PASS: readme_conflicts OK"; PASS=$((PASS + 1));;
  *)
    echo "  FAIL: readme_conflicts OK — got [$out]"; FAIL=$((FAIL + 1));;
esac
TOTAL=$((TOTAL + 1))
rm -rf "$TMP"

# Test 11: _audit_readme_conflicts FAIL when markers present
echo ""
echo "Test 11: _audit_readme_conflicts FAIL with markers"
TMP=$(setup_audit_repo)
(
  cd "$TMP"
  cat > README.md <<'EOF'
line before
<<<<<<< HEAD
ours
=======
theirs
>>>>>>> branch
EOF
)
out=$(cd "$TMP" && _audit_readme_conflicts)
case "$out" in
  readme-conflicts\|3\|0\|FAIL\|*)
    echo "  PASS: readme_conflicts FAIL with drill"; PASS=$((PASS + 1));;
  *)
    echo "  FAIL: readme_conflicts FAIL — got [$out]"; FAIL=$((FAIL + 1));;
esac
TOTAL=$((TOTAL + 1))
rm -rf "$TMP"

# Test 12: env-override BRANCH_MAX raises threshold
echo ""
echo "Test 12: env-override BRANCH_MAX"
TMP=$(setup_audit_repo)
(cd "$TMP" && for i in $(seq 1 12); do git branch "extra-$i" 2>/dev/null; done)
# Seed green evidence so test-suites does not independently fail
mkdir -p "$TMP/.omc/phase-99-evidence"
printf '=== Results: 1/1 passed, 0 failed ===\n' > "$TMP/.omc/phase-99-evidence/test_x.log"
# Default threshold (10) → 12 branches should FAIL → exit 1
rc_default=$(cd "$TMP" && bash "$REPO_ROOT/quantum-loop.sh" --audit >/dev/null 2>&1 ; echo $?)
# With QL_AUDIT_BRANCH_MAX=20 → 12 <= 20 → exit 0
rc_override=$(cd "$TMP" && QL_AUDIT_BRANCH_MAX=20 bash "$REPO_ROOT/quantum-loop.sh" --audit >/dev/null 2>&1 ; echo $?)
assert "default BRANCH_MAX=10 → exit 1" "1" "$rc_default"
assert "override BRANCH_MAX=20 → exit 0" "0" "$rc_override"
rm -rf "$TMP"

# --- US-003 tests -----------------------------------------------------------

# Test 13: _audit_orphan_worktrees OK when no agent-* dirs
echo ""
echo "Test 13: _audit_orphan_worktrees OK"
TMP=$(setup_audit_repo)
out=$(cd "$TMP" && _audit_orphan_worktrees)
case "$out" in
  orphan-worktrees\|0\|0\|OK\|*)
    echo "  PASS: orphan_worktrees OK on clean repo"; PASS=$((PASS + 1));;
  *)
    echo "  FAIL: orphan_worktrees OK — got [$out]"; FAIL=$((FAIL + 1));;
esac
TOTAL=$((TOTAL + 1))
rm -rf "$TMP"

# Test 14: _audit_orphan_worktrees FAIL when agent-* dir present
echo ""
echo "Test 14: _audit_orphan_worktrees FAIL"
TMP=$(setup_audit_repo)
mkdir -p "$TMP/.claude/worktrees/agent-foo"
out=$(cd "$TMP" && _audit_orphan_worktrees)
case "$out" in
  orphan-worktrees\|1\|0\|FAIL\|*agent-foo*)
    echo "  PASS: orphan_worktrees FAIL with drill"; PASS=$((PASS + 1));;
  *)
    echo "  FAIL: orphan_worktrees FAIL — got [$out]"; FAIL=$((FAIL + 1));;
esac
TOTAL=$((TOTAL + 1))
rm -rf "$TMP"

# Test 15: _audit_cpc_files FAIL when CPC file present
echo ""
echo "Test 15: _audit_cpc_files FAIL"
TMP=$(setup_audit_repo)
touch "$TMP/plugin-CPC-xyz.json"
out=$(cd "$TMP" && _audit_cpc_files)
case "$out" in
  cpc-files\|1\|0\|FAIL\|*plugin-CPC-xyz.json*)
    echo "  PASS: cpc_files FAIL with drill"; PASS=$((PASS + 1));;
  *)
    echo "  FAIL: cpc_files FAIL — got [$out]"; FAIL=$((FAIL + 1));;
esac
TOTAL=$((TOTAL + 1))
rm -rf "$TMP"

# Test 16: _audit_test_suites OK when green evidence log present
echo ""
echo "Test 16: _audit_test_suites OK"
TMP=$(setup_audit_repo)
mkdir -p "$TMP/.omc/phase-99-evidence"
# Canonical evidence format: '=== Results: ...' on its own line (no prefix)
printf '=== Results: 5/5 passed, 0 failed ===\n' > "$TMP/.omc/phase-99-evidence/test_x.log"
out=$(cd "$TMP" && _audit_test_suites)
case "$out" in
  test-suites\|5/5\ passed\|green\|OK\|*)
    echo "  PASS: test_suites OK"; PASS=$((PASS + 1));;
  *)
    echo "  FAIL: test_suites OK — got [$out]"; FAIL=$((FAIL + 1));;
esac
TOTAL=$((TOTAL + 1))
rm -rf "$TMP"

# Test 17: _audit_test_suites FAIL when log shows failures
echo ""
echo "Test 17: _audit_test_suites FAIL"
TMP=$(setup_audit_repo)
mkdir -p "$TMP/.omc/phase-99-evidence"
printf '=== Results: 3/5 passed, 2 failed ===\n' > "$TMP/.omc/phase-99-evidence/test_x.log"
out=$(cd "$TMP" && _audit_test_suites)
case "$out" in
  test-suites\|3/5\ passed\|green\|FAIL\|*test_x*)
    echo "  PASS: test_suites FAIL with drill"; PASS=$((PASS + 1));;
  *)
    echo "  FAIL: test_suites FAIL — got [$out]"; FAIL=$((FAIL + 1));;
esac
TOTAL=$((TOTAL + 1))
rm -rf "$TMP"

# Test 18: _audit_test_suites unknown when no evidence dir (FR-10)
echo ""
echo "Test 18: _audit_test_suites unknown (no evidence dir)"
TMP=$(setup_audit_repo)
out=$(cd "$TMP" && _audit_test_suites)
case "$out" in
  test-suites\|unknown\|green\|FAIL\|no\ evidence*)
    echo "  PASS: test_suites unknown (no evidence)"; PASS=$((PASS + 1));;
  *)
    echo "  FAIL: test_suites unknown — got [$out]"; FAIL=$((FAIL + 1));;
esac
TOTAL=$((TOTAL + 1))
rm -rf "$TMP"

# Test 19: failure-path integration (cpc + orphans + green test-suites → exit 1)
echo ""
echo "Test 19: failure-path integration"
TMP=$(setup_audit_repo)
touch "$TMP/plugin-CPC-xyz.json"
mkdir -p "$TMP/.claude/worktrees/agent-stale"
mkdir -p "$TMP/.omc/phase-99-evidence"
echo 'test_x: === Results: 1/1 passed, 0 failed ===' > "$TMP/.omc/phase-99-evidence/test_x.log"
out=$(cd "$TMP" && bash "$REPO_ROOT/quantum-loop.sh" --audit 2>&1 || true)
rc=$(cd "$TMP" && bash "$REPO_ROOT/quantum-loop.sh" --audit >/dev/null 2>&1 ; echo $?)
TOTAL=$((TOTAL + 1))
if [[ "$rc" -eq 1 ]] \
   && printf '%s' "$out" | grep -q 'cpc-files.*FAIL' \
   && printf '%s' "$out" | grep -q 'orphan-worktrees.*FAIL' \
   && printf '%s' "$out" | grep -q 'test-suites.*OK' \
   && printf '%s' "$out" | grep -q '└─'; then
  echo "  PASS: failure-path exit 1 with drill-down"; PASS=$((PASS + 1))
else
  echo "  FAIL: failure-path integration (rc=$rc)"; FAIL=$((FAIL + 1))
  echo "    out=$out" | head -5
fi
rm -rf "$TMP"

# --- US-004 tests -----------------------------------------------------------

# Test 20: --help output contains --audit line
echo ""
echo "Test 20: --help documents --audit"
help_out=$(bash "$REPO_ROOT/quantum-loop.sh" --help 2>&1)
TOTAL=$((TOTAL + 1))
if printf '%s' "$help_out" | grep -- '--audit' | grep -q 'measurement metrics'; then
  echo "  PASS: --help contains --audit line"; PASS=$((PASS + 1))
else
  echo "  FAIL: --help missing --audit"; FAIL=$((FAIL + 1))
fi

# Test 21: format_row byte-exact regression (OK)
echo ""
echo "Test 21: format_row byte-exact OK regression"
expected='branches-local:    5 (target ≤10)     OK'
actual=$(_audit_format_row 'branches-local|5|≤10|OK|')
assert "format_row OK byte-exact" "$expected" "$actual"

# Test 22: format_row byte-exact regression (FAIL with drill)
echo ""
echo "Test 22: format_row byte-exact FAIL regression"
expected_main='cpc-files:         2 (target 0)   FAIL'
expected_drill='                   └─ plugin-CPC.json, README-CPC.md'
actual=$(_audit_format_row 'cpc-files|2|0|FAIL|plugin-CPC.json, README-CPC.md')
line1=$(printf '%s\n' "$actual" | sed -n '1p')
line2=$(printf '%s\n' "$actual" | sed -n '2p')
assert "format_row FAIL line 1"   "$expected_main"  "$line1"
assert "format_row FAIL drill line" "$expected_drill" "$line2"

# Test 23: full-flow happy-path integration (all 6 OK + 1 WARN from clean
# tmp's missing pre-impl-review CSV, exit 0)
echo ""
echo "Test 23: full-flow happy path 6/7 OK + 1 WARN"
TMP=$(setup_audit_repo)
mkdir -p "$TMP/.omc/phase-99-evidence"
printf '=== Results: 1/1 passed, 0 failed ===\n' > "$TMP/.omc/phase-99-evidence/test_x.log"
out=$(cd "$TMP" && bash "$REPO_ROOT/quantum-loop.sh" --audit 2>&1 || true)
rc=$(cd "$TMP" && bash "$REPO_ROOT/quantum-loop.sh" --audit >/dev/null 2>&1 ; echo $?)
TOTAL=$((TOTAL + 1))
nonfail_count=$(printf '%s' "$out" | grep -cE '^[a-z].*(OK|WARN)$')
# v0.7.0 / G17: new pre-impl-review-coverage metric raises total from 6 → 7.
# In a clean tmp repo there is no metrics/pre-impl-review-findings.csv, so the
# new helper emits WARN (missing-csv). WARN does not fail the audit (AC).
# v0.6.5 / G26 / US-001: split summary distinguishes OK / WARN / FAIL — the
# clean-tmp fixture is 6 OK + 1 WARN + 0 FAIL, so summary reads
# "Summary: 6/7 OK, 1 WARN, 0 FAIL." (was: "Summary: 7/7 metrics on target.")
if [[ "$rc" -eq 0 ]] && [[ "$nonfail_count" -eq 7 ]] && printf '%s' "$out" | grep -q 'Summary: 6/7 OK, 1 WARN, 0 FAIL\.'; then
  echo "  PASS: full-flow happy 6/7 OK + 1 WARN"; PASS=$((PASS + 1))
else
  echo "  FAIL: full-flow happy (rc=$rc, nonfail_count=$nonfail_count)"; FAIL=$((FAIL + 1))
fi
rm -rf "$TMP"

# Test 24: full-flow all-fail integration
echo ""
echo "Test 24: full-flow all-fail"
TMP=$(setup_audit_repo)
# Seed all 5 non-remote failure conditions
(cd "$TMP" && for i in $(seq 1 15); do git branch "extra-$i" 2>/dev/null; done)
touch "$TMP/plugin-CPC-xyz.json"
mkdir -p "$TMP/.claude/worktrees/agent-stale"
cat > "$TMP/README.md" <<'EOF'
<<<<<<< HEAD
ours
=======
theirs
>>>>>>> branch
EOF
mkdir -p "$TMP/.omc/phase-99-evidence"
printf '=== Results: 3/5 passed, 2 failed ===\n' > "$TMP/.omc/phase-99-evidence/test_x.log"
out=$(cd "$TMP" && bash "$REPO_ROOT/quantum-loop.sh" --audit 2>&1 || true)
rc=$(cd "$TMP" && bash "$REPO_ROOT/quantum-loop.sh" --audit >/dev/null 2>&1 ; echo $?)
TOTAL=$((TOTAL + 1))
fail_count=$(printf '%s' "$out" | grep -cE 'FAIL$')
if [[ "$rc" -eq 1 ]] && (( fail_count == 5 )) \
   && printf '%s' "$out" | grep -q 'branches-local.*FAIL' \
   && printf '%s' "$out" | grep -q 'cpc-files.*FAIL' \
   && printf '%s' "$out" | grep -q 'orphan-worktrees.*FAIL' \
   && printf '%s' "$out" | grep -q 'readme-conflicts.*FAIL' \
   && printf '%s' "$out" | grep -q 'test-suites.*FAIL'; then
  echo "  PASS: full-flow all-fail (rc=$rc, fail_count=5, all 5 metrics FAIL)"; PASS=$((PASS + 1))
else
  echo "  FAIL: full-flow all-fail (rc=$rc, fail_count=$fail_count)"; FAIL=$((FAIL + 1))
  printf '%s\n' "$out" | sed 's/^/    /' | head -10
fi
rm -rf "$TMP"

# --- Review-followup tests (PR #56 improvement + bug fix) ------------------

# Test 25: QL_AUDIT_TEST_GLOB validation rejects shell metacharacters
echo ""
echo "Test 25: QL_AUDIT_TEST_GLOB validation"
TMP=$(setup_audit_repo)
mkdir -p "$TMP/.omc/phase-99-evidence"
printf '=== Results: 1/1 passed, 0 failed ===\n' > "$TMP/.omc/phase-99-evidence/test_x.log"
out=$(cd "$TMP" && QL_AUDIT_TEST_GLOB='; rm -rf /' bash "$REPO_ROOT/quantum-loop.sh" --audit 2>&1 || true)
rc=$(cd "$TMP" && QL_AUDIT_TEST_GLOB='; rm -rf /' bash "$REPO_ROOT/quantum-loop.sh" --audit >/dev/null 2>&1 ; echo $?)
TOTAL=$((TOTAL + 1))
# Validation must fire BEFORE header is printed (clean-exit, no half-audit)
if [[ "$rc" -eq 2 ]] \
   && printf '%s' "$out" | grep -q 'invalid QL_AUDIT_TEST_GLOB' \
   && ! printf '%s' "$out" | grep -q '=== Quantum-loop audit ==='; then
  echo "  PASS: invalid TEST_GLOB rejected clean (no half-audit frame)"; PASS=$((PASS + 1))
else
  echo "  FAIL: TEST_GLOB validation (rc=$rc)"; FAIL=$((FAIL + 1))
  printf '%s\n' "$out" | head -5 | sed 's/^/    /'
fi
rm -rf "$TMP"

# Test 26: QL_AUDIT_TEST_GLOB filter narrows which logs are considered
echo ""
echo "Test 26: QL_AUDIT_TEST_GLOB filter"
TMP=$(setup_audit_repo)
mkdir -p "$TMP/.omc/phase-99-evidence"
# Two logs: one with failures, one all-green. Default "*" considers both.
printf '=== Results: 1/1 passed, 0 failed ===\n' > "$TMP/.omc/phase-99-evidence/test_good.log"
printf '=== Results: 3/5 passed, 2 failed ===\n' > "$TMP/.omc/phase-99-evidence/test_bad.log"
# Filter to test_good only → OK, exit 0 (on test-suites alone)
out_filter=$(cd "$TMP" && QL_AUDIT_TEST_GLOB='test_good' _audit_test_suites)
# Default filter → includes test_bad → FAIL
out_default=$(cd "$TMP" && _audit_test_suites)
TOTAL=$((TOTAL + 1))
case "$out_filter" in
  test-suites\|1/1\ passed\|green\|OK\|*) pass_filter=1 ;;
  *) pass_filter=0 ;;
esac
case "$out_default" in
  test-suites\|4/6\ passed\|green\|FAIL\|*) pass_default=1 ;;
  *) pass_default=0 ;;
esac
if [[ "$pass_filter" -eq 1 && "$pass_default" -eq 1 ]]; then
  echo "  PASS: TEST_GLOB filter isolates logs correctly"; PASS=$((PASS + 1))
else
  echo "  FAIL: filter=[$out_filter] default=[$out_default]"; FAIL=$((FAIL + 1))
fi
rm -rf "$TMP"

# Test 27: Numeric sort picks phase-43 over phase-9 (regression guard)
echo ""
echo "Test 27: phase-dir sort is numeric, not lexicographic"
TMP=$(setup_audit_repo)
# Seed phase-9 with FAILING results and phase-43 with PASSING results.
# Lexicographic sort picks phase-9 (bug); numeric sort picks phase-43 (fixed).
# Correct behavior: audit reads phase-43 → OK.
mkdir -p "$TMP/.omc/phase-9-evidence" "$TMP/.omc/phase-43-evidence"
printf '=== Results: 0/1 passed, 1 failed ===\n' > "$TMP/.omc/phase-9-evidence/test_z.log"
printf '=== Results: 5/5 passed, 0 failed ===\n' > "$TMP/.omc/phase-43-evidence/test_z.log"
out=$(cd "$TMP" && _audit_test_suites)
case "$out" in
  test-suites\|5/5\ passed\|green\|OK\|*)
    echo "  PASS: numeric sort picks phase-43 (not phase-9)"; PASS=$((PASS + 1));;
  *)
    echo "  FAIL: phase-sort regression — got [$out]"; FAIL=$((FAIL + 1));;
esac
TOTAL=$((TOTAL + 1))
rm -rf "$TMP"

# --- v0.7.0 / G17 / US-005: pre-impl-review-coverage metric --------------
#
# The new helper _audit_pre_impl_review_coverage reads
# metrics/pre-impl-review-findings.csv and counts unique stage values in rows
# newer than 7 days. Four states per AC (all use status=WARN or OK; never
# fails the audit):
#   missing-csv      → WARN (no metrics/pre-impl-review-findings.csv)
#   no-recent-runs   → WARN (CSV exists but all rows are >7d old)
#   partial-coverage → WARN (1-2 of 3 stages have a recent row)
#   full-coverage    → OK   (all 3 stages have a recent row)
#
# Cross-platform date math: GNU `date -d '7 days ago'` first; BSD `date -v-7d`
# fallback; epoch-0 fallback otherwise (so the helper degrades to "all rows
# count as recent" rather than crashing — never breaks the audit).

echo ""
echo "=== v0.7.0 / G17 / US-005 pre-impl-review-coverage tests ==="

# Helper: synthesize a CSV with a header + N data rows. Each row's timestamp
# is current_unix - $age_secs.
_synth_csv() {
  local csv="$1"; shift
  mkdir -p "$(dirname "$csv")"
  printf 'timestamp,stage,source_path,count,critical,high,medium,low\n' > "$csv"
  while (( $# >= 2 )); do
    local stage="$1" age="$2"; shift 2
    # Compute ISO 8601 UTC for `now - age` seconds. GNU first, BSD fallback.
    local ts
    ts=$(date -u -d "@$(( $(date -u +%s) - age ))" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null) \
      || ts=$(date -u -r "$(( $(date -u +%s) - age ))" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null) \
      || ts="1970-01-01T00:00:00Z"
    printf '%s,%s,docs/x.md,4,1,1,2,0\n' "$ts" "$stage" >> "$csv"
  done
}

# Test 28: missing-csv state (no metrics/ at all) → WARN
echo ""
echo "Test 28: pre-impl-review-coverage missing-csv → WARN"
TMP=$(setup_audit_repo)
out=$(cd "$TMP" && _audit_pre_impl_review_coverage)
case "$out" in
  pre-impl-review-coverage\|0/3\ stages\|*\|WARN\|*missing-csv*)
    echo "  PASS: missing-csv → WARN"; PASS=$((PASS + 1));;
  *)
    echo "  FAIL: missing-csv unexpected — got [$out]"; FAIL=$((FAIL + 1));;
esac
TOTAL=$((TOTAL + 1))

# Test 28b (G18 / US-005 / v0.6.5): missing-csv drill text now clarifies that
# the empty-CSV state is the expected first-run state after install (not a
# regression). Substring "(expected on first run" tells the operator to invoke
# the planning skills to populate the CSV. Same TMP fixture as Test 28.
TOTAL=$((TOTAL + 1))
if printf '%s' "$out" | grep -qF '(expected on first run'; then
  echo "  PASS: missing-csv drill mentions '(expected on first run'"
  PASS=$((PASS + 1))
else
  echo "  FAIL: missing-csv drill missing '(expected on first run' substring"
  echo "    got: [$out]"
  FAIL=$((FAIL + 1))
fi
rm -rf "$TMP"

# Test 29: no-recent-runs state (CSV exists, all rows >7d old) → WARN
echo ""
echo "Test 29: pre-impl-review-coverage no-recent-runs → WARN"
TMP=$(setup_audit_repo)
# 14 days = 1209600 seconds; 21 days = 1814400; 30 days = 2592000.
_synth_csv "$TMP/metrics/pre-impl-review-findings.csv" \
  design 1209600  prd 1814400  plan 2592000
out=$(cd "$TMP" && _audit_pre_impl_review_coverage)
case "$out" in
  pre-impl-review-coverage\|0/3\ stages\|*\|WARN\|*no-recent-runs*)
    echo "  PASS: no-recent-runs → WARN"; PASS=$((PASS + 1));;
  *)
    echo "  FAIL: no-recent-runs unexpected — got [$out]"; FAIL=$((FAIL + 1));;
esac
TOTAL=$((TOTAL + 1))
rm -rf "$TMP"

# Test 30: partial-coverage state (2 of 3 stages recent) → WARN
echo ""
echo "Test 30: pre-impl-review-coverage partial-coverage → WARN"
TMP=$(setup_audit_repo)
# 1 hour + 6 hours = 2 recent stages; plan @14 days = stale.
_synth_csv "$TMP/metrics/pre-impl-review-findings.csv" \
  design 3600  prd 21600  plan 1209600
out=$(cd "$TMP" && _audit_pre_impl_review_coverage)
case "$out" in
  pre-impl-review-coverage\|2/3\ stages\|*\|WARN\|*partial-coverage*)
    echo "  PASS: partial-coverage 2/3 → WARN"; PASS=$((PASS + 1));;
  *)
    echo "  FAIL: partial-coverage unexpected — got [$out]"; FAIL=$((FAIL + 1));;
esac
TOTAL=$((TOTAL + 1))
rm -rf "$TMP"

# Test 31: full-coverage state (all 3 stages recent) → OK
echo ""
echo "Test 31: pre-impl-review-coverage full-coverage → OK"
TMP=$(setup_audit_repo)
_synth_csv "$TMP/metrics/pre-impl-review-findings.csv" \
  design 3600  prd 21600  plan 86400
out=$(cd "$TMP" && _audit_pre_impl_review_coverage)
case "$out" in
  pre-impl-review-coverage\|3/3\ stages\|*\|OK\|*)
    echo "  PASS: full-coverage 3/3 → OK"; PASS=$((PASS + 1));;
  *)
    echo "  FAIL: full-coverage unexpected — got [$out]"; FAIL=$((FAIL + 1));;
esac
TOTAL=$((TOTAL + 1))
rm -rf "$TMP"

# Test 32: WARN does not fail the audit; full-flow with full-coverage → exit 0
echo ""
echo "Test 32: WARN never fails the audit (do_audit exit 0 with WARN row)"
TMP=$(setup_audit_repo)
mkdir -p "$TMP/.omc/phase-99-evidence"
printf '=== Results: 1/1 passed, 0 failed ===\n' > "$TMP/.omc/phase-99-evidence/test_x.log"
# No CSV → missing-csv WARN; everything else OK
rc=$(cd "$TMP" && bash "$REPO_ROOT/quantum-loop.sh" --audit >/dev/null 2>&1 ; echo $?)
out=$(cd "$TMP" && bash "$REPO_ROOT/quantum-loop.sh" --audit 2>&1 || true)
TOTAL=$((TOTAL + 1))
if [[ "$rc" -eq 0 ]] && printf '%s' "$out" | grep -q 'pre-impl-review-coverage'; then
  echo "  PASS: WARN row present + audit exit 0"; PASS=$((PASS + 1))
else
  echo "  FAIL: full-flow WARN (rc=$rc)"; FAIL=$((FAIL + 1))
fi
rm -rf "$TMP"

# Test 33: row is wired into do_audit ROWS as the 7th metric
echo ""
echo "Test 33: do_audit emits 7 metric rows + split summary (G26 / v0.6.5)"
TMP=$(setup_audit_repo)
mkdir -p "$TMP/.omc/phase-99-evidence"
printf '=== Results: 1/1 passed, 0 failed ===\n' > "$TMP/.omc/phase-99-evidence/test_x.log"
out=$(cd "$TMP" && bash "$REPO_ROOT/quantum-loop.sh" --audit 2>&1 || true)
metric_lines=$(printf '%s' "$out" | grep -cE '^[a-z][a-z-]+:')
TOTAL=$((TOTAL + 1))
# v0.6.5 / G26: summary now reports split OK / WARN / FAIL counters.
# Clean tmp repo: 6 OK + 1 WARN (pre-impl-review-coverage missing-csv) + 0 FAIL.
if (( metric_lines == 7 )) && printf '%s' "$out" | grep -q 'Summary: 6/7 OK, 1 WARN, 0 FAIL\.'; then
  echo "  PASS: 7 metric rows + split summary (6/7 OK, 1 WARN, 0 FAIL)"; PASS=$((PASS + 1))
else
  echo "  FAIL: expected 7 metric rows + split summary, got [$metric_lines] / out:"; FAIL=$((FAIL + 1))
  printf '%s\n' "$out" | tail -5 | sed 's/^/    /'
fi
rm -rf "$TMP"

# --- v0.6.5 / G26 / US-001 + v0.6.6 / G33 / US-002: split-summary tests ---
# v0.6.6 / G33: Tests 34 + 35 now invoke real do_audit via subprocess
# (`bash quantum-loop.sh --audit`) with QL_AUDIT_TEST_MODE=1 + QL_AUDIT_TEST_ROWS
# set, instead of inlining a do_audit re-implementation. A future regression
# in do_audit's case-pattern switch is now caught by these tests too.
#
# Subshell exit-code capture pattern (see CLAUDE.md "Platform Notes"): under
# `set -uo pipefail`, `out=$(bash ...)` returning non-zero does NOT abort the
# test script (no `-e`), but capturing both stdout AND exit code requires the
# two-invocation idiom: one captures stdout with `|| true`, one captures the
# exit code via explicit `; echo $?`.

QL_SH="$REPO_ROOT/quantum-loop.sh"

# Test 34: 3-row all-OK fixture → "Summary: 3/3 OK, 0 WARN, 0 FAIL." + exit 0
echo ""
echo "Test 34: split summary all-OK fixture (G26 + G33 real-do_audit)"
t34_rows=$(printf 'foo|1|0|OK|\nbar|2|0|OK|\nbaz|3|0|OK|')
out=$(QL_AUDIT_TEST_MODE=1 QL_AUDIT_TEST_ROWS="$t34_rows" bash "$QL_SH" --audit 2>&1 || true)
rc=$(QL_AUDIT_TEST_MODE=1 QL_AUDIT_TEST_ROWS="$t34_rows" bash "$QL_SH" --audit >/dev/null 2>&1 ; echo $?)
TOTAL=$((TOTAL + 1))
if [[ "$rc" -eq 0 ]] && printf '%s' "$out" | grep -q 'Summary: 3/3 OK, 0 WARN, 0 FAIL\.'; then
  echo "  PASS: 3-OK fixture → 'Summary: 3/3 OK, 0 WARN, 0 FAIL.' exit 0"; PASS=$((PASS + 1))
else
  echo "  FAIL: 3-OK fixture (rc=$rc, summary missing or wrong)"; FAIL=$((FAIL + 1))
  printf '%s\n' "$out" | sed 's/^/    /'
fi

# Test 35: mixed 1-OK / 1-WARN / 1-FAIL fixture → exit 1 + "1/3 OK, 1 WARN, 1 FAIL."
echo ""
echo "Test 35: split summary mixed-3-state fixture (G26 + G33 real-do_audit)"
t35_rows=$(printf 'foo|1|0|OK|\nbar|2|0|WARN|partial-coverage\nbaz|3|0|FAIL|broken')
out=$(QL_AUDIT_TEST_MODE=1 QL_AUDIT_TEST_ROWS="$t35_rows" bash "$QL_SH" --audit 2>&1 || true)
rc=$(QL_AUDIT_TEST_MODE=1 QL_AUDIT_TEST_ROWS="$t35_rows" bash "$QL_SH" --audit >/dev/null 2>&1 ; echo $?)
TOTAL=$((TOTAL + 1))
if [[ "$rc" -eq 1 ]] && printf '%s' "$out" | grep -q 'Summary: 1/3 OK, 1 WARN, 1 FAIL\.'; then
  echo "  PASS: mixed-3-state → 'Summary: 1/3 OK, 1 WARN, 1 FAIL.' exit 1"; PASS=$((PASS + 1))
else
  echo "  FAIL: mixed-3-state (rc=$rc, summary missing or wrong)"; FAIL=$((FAIL + 1))
  printf '%s\n' "$out" | sed 's/^/    /'
fi

# --- v0.6.6 / G34 / US-003: comment-meta-strip assertions -----------------
#
# Bloated PR-metadata strings (G-numbers, version tags, soliton-confidence
# scores) belong in git log + CHANGELOG + retrospective docs, not in the code.
# These tests scope to the comment ranges associated with _audit_format_row
# and do_audit and assert two properties:
#   (a) zero matches of the bloat regex (confidence|G[0-9]+|v0.X.Y|soliton)
#   (b) at least one load-bearing-WHY phrase (because|why|so that|the WHY)
#
# The comment ranges are derived programmatically: for each function, walk
# from the function-definition line backwards to the previous blank line
# (function-header), and forward through the body until the closing brace
# (function-body). Both ranges are concatenated for the regex check.

# extract_function_header_comments <function_name>
# Echoes the function-header comment block (^[[:space:]]*#) — the contiguous
# comment lines immediately preceding `function_name() {`.
#
# N8 / US-003 (v0.6.8): HEADER RANGE ONLY. Body comments are out of scope per
# G34 design intent ("trim PR-metadata bloat from quantum-loop.sh function-
# header comments"). Pre-N8 this awk also emitted body comments, which caused
# Test 37a to false-positive on c47e038's body comment containing "confidence
# 95" — fixed inline in v0.6.7 US-001 but the over-broad awk remained. v0.6.8
# narrows the awk to match G34's stated scope so a future post-merge fix that
# legitimately needs a soliton-style comment in a function BODY does not trip
# this audit.
extract_function_header_comments() {
  local fn="$1"
  awk -v fn="$fn" '
    /^'"$fn"'\(\) \{/ {
      # Function definition reached. Emit accumulated header buffer, exit.
      for (i=1; i<=hbuf_n; i++) print hbuf[i]
      exit
    }
    /^[[:space:]]*#/ {
      # Buffer header comment (cleared on blank line, flushed on fn-def).
      hbuf_n++
      hbuf[hbuf_n] = $0
      next
    }
    /^[[:space:]]*$/ { hbuf_n=0 }
    { hbuf_n=0 }
  ' "$REPO_ROOT/quantum-loop.sh"
}

# extract_function_all_comments <function_name>
# Echoes ALL comment lines in the function-header block AND the function-body.
# Used by the WHY-phrase audit (Tests 36b/37b) — G34 trimmed function-headers
# heavily, so the WHY explanation often legitimately lives in body comments.
# Body-comment scanning is preserved for that audit only; the bloat audit
# (Tests 36a/37a) uses extract_function_header_comments (header-only) per N8.
extract_function_all_comments() {
  local fn="$1"
  awk -v fn="$fn" '
    /^'"$fn"'\(\) \{/ {
      for (i=1; i<=hbuf_n; i++) print hbuf[i]
      in_body=1
      hbuf_n=0
      next
    }
    in_body && /^\}/ { in_body=0; next }
    in_body && /^[[:space:]]*#/ { print }
    /^[[:space:]]*#/ {
      hbuf_n++
      hbuf[hbuf_n] = $0
      next
    }
    /^[[:space:]]*$/ { hbuf_n=0 }
    { hbuf_n=0 }
  ' "$REPO_ROOT/quantum-loop.sh"
}

echo ""
echo "Test 36a: _audit_format_row comments contain no PR-metadata bloat (G34)"
fmt_comments=$(extract_function_header_comments '_audit_format_row')
TOTAL=$((TOTAL + 1))
if printf '%s' "$fmt_comments" | grep -qE '(confidence|G[0-9]+|v0\.[0-9]+\.[0-9]+|soliton)'; then
  echo "  FAIL: _audit_format_row comments still contain PR-metadata bloat:"; FAIL=$((FAIL + 1))
  printf '%s' "$fmt_comments" | grep -E '(confidence|G[0-9]+|v0\.[0-9]+\.[0-9]+|soliton)' | sed 's/^/    /'
else
  echo "  PASS: 0 PR-metadata bloat strings in _audit_format_row comments"; PASS=$((PASS + 1))
fi

echo ""
echo "Test 36b: _audit_format_row comments retain explanatory WHY (G34)"
# N8 / US-003 (v0.6.8): WHY-phrase check uses full (header + body) range —
# G34 trimmed function-headers heavily, so WHY often legitimately lives
# in body comments. Test 36a (bloat) stays header-only per G34's stated
# scope; Test 36b (WHY-presence) widens to body for accurate signal.
fmt_comments_full=$(extract_function_all_comments '_audit_format_row')
TOTAL=$((TOTAL + 1))
if printf '%s' "$fmt_comments_full" | grep -qE '(because|why|so that|the WHY)'; then
  echo "  PASS: _audit_format_row comments retain >=1 WHY phrase (header+body)"; PASS=$((PASS + 1))
else
  echo "  FAIL: _audit_format_row comments have no WHY phrase (over-trim)"; FAIL=$((FAIL + 1))
fi

echo ""
echo "Test 37a: do_audit comments contain no PR-metadata bloat (G34)"
do_comments=$(extract_function_header_comments 'do_audit')
TOTAL=$((TOTAL + 1))
if printf '%s' "$do_comments" | grep -qE '(confidence|G[0-9]+|v0\.[0-9]+\.[0-9]+|soliton)'; then
  echo "  FAIL: do_audit comments still contain PR-metadata bloat:"; FAIL=$((FAIL + 1))
  printf '%s' "$do_comments" | grep -E '(confidence|G[0-9]+|v0\.[0-9]+\.[0-9]+|soliton)' | sed 's/^/    /'
else
  echo "  PASS: 0 PR-metadata bloat strings in do_audit comments"; PASS=$((PASS + 1))
fi

echo ""
echo "Test 37b: do_audit comments retain explanatory WHY (G34)"
# N8 / US-003 (v0.6.8): same scope-widening as Test 36b — WHY-check uses
# full (header + body) range; bloat-check (Test 37a) stays header-only.
do_comments_full=$(extract_function_all_comments 'do_audit')
TOTAL=$((TOTAL + 1))
if printf '%s' "$do_comments_full" | grep -qE '(because|why|so that|the WHY)'; then
  echo "  PASS: do_audit comments retain >=1 WHY phrase (header+body)"; PASS=$((PASS + 1))
else
  echo "  FAIL: do_audit comments have no WHY phrase (over-trim)"; FAIL=$((FAIL + 1))
fi

echo ""
echo "=== Results: $PASS/$TOTAL passed, $FAIL failed ==="
exit $((FAIL > 0 ? 1 : 0))
