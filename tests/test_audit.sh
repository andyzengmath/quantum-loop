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

# Test 4: do_audit stub returns 0 and prints header
echo ""
echo "Test 4: do_audit stub happy path"
out=$(do_audit 2>&1)
rc=$?
assert "do_audit exits 0" "0" "$rc"
case "$out" in
  *"=== Quantum-loop audit ==="*"Summary:"*)
    echo "  PASS: header + summary present"; PASS=$((PASS + 1));;
  *)
    echo "  FAIL: do_audit output — got [$out]"; FAIL=$((FAIL + 1));;
esac
TOTAL=$((TOTAL + 1))

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

echo ""
echo "=== Results: $PASS/$TOTAL passed, $FAIL failed ==="
exit $((FAIL > 0 ? 1 : 0))
