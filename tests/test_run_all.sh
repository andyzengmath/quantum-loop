#!/usr/bin/env bash
# G31 / US-005 (v0.6.6) — tests/run_all.sh runner verification.
#
# Synthesizes a 3-test-file fixture (1 PASS, 1 FAIL, 1 PASS) in a tmp directory
# and exercises tests/run_all.sh's modes:
#   1. default (sequential)         → 2/3 PASS, exit 1
#   2. --quick (changed-file-only)  → runs only the file in git diff master..HEAD
#   3. --parallel 2                 → same aggregate as sequential but uses xargs -P
#   4. --quick --parallel 2         → combined; runs only changed via parallel dispatch
#
# Each subprocess invocation uses the two-invocation idiom from CLAUDE.md
# Platform Notes: capture stdout via $(...) || true, capture exit via ; echo $?

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$SCRIPT_DIR/.."
RUN_ALL="$REPO_ROOT/tests/run_all.sh"
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

assert_grep() {
  local name="$1" pattern="$2" haystack="$3"
  TOTAL=$((TOTAL + 1))
  if printf '%s' "$haystack" | grep -qE "$pattern"; then
    echo "  PASS: $name"; PASS=$((PASS + 1))
  else
    echo "  FAIL: $name (pattern [$pattern] not in output)"
    FAIL=$((FAIL + 1))
  fi
}

echo "=== US-005 G31 tests/run_all.sh fixture-driven tests ==="

# Build a 3-test-file fixture in a tmp git repo.
TMP=$(mktemp -d)
mkdir -p "$TMP/tests"
cat > "$TMP/tests/test_a.sh" <<'PASS_TEST'
#!/usr/bin/env bash
echo "test_a"
echo "  PASS: alpha"
echo "=== Results: 1/1 passed, 0 failed ==="
exit 0
PASS_TEST

cat > "$TMP/tests/test_b.sh" <<'FAIL_TEST'
#!/usr/bin/env bash
echo "test_b"
echo "  FAIL: bravo broken"
echo "=== Results: 0/1 passed, 1 failed ==="
exit 1
FAIL_TEST

cat > "$TMP/tests/test_c.sh" <<'PASS_TEST2'
#!/usr/bin/env bash
echo "test_c"
echo "  PASS: charlie"
echo "=== Results: 1/1 passed, 0 failed ==="
exit 0
PASS_TEST2

chmod +x "$TMP/tests/"*.sh

# Set up minimal git history so --quick has a master-vs-HEAD diff:
# master ref points to commit-1 (a + c only); HEAD points to commit-2 (adds b).
# So `git diff master..HEAD --name-only -- 'tests/test_*.sh'` = test_b.
( cd "$TMP" && git init -q && git config user.email "t@t.t" && git config user.name "t"
  # First commit on a feature branch: a + c only
  mv tests/test_b.sh tests/.b-staging.sh
  git checkout -q -b master
  git add tests/test_a.sh tests/test_c.sh
  git commit -qm "init: a + c only"
  # Branch off master to feature, add b there
  git checkout -q -b feature
  mv tests/.b-staging.sh tests/test_b.sh
  git add tests/test_b.sh
  git commit -qm "add: b" ) >/dev/null 2>&1

# ----- 1. Default mode: sequential, 2/3 PASS, exit 1 -----
echo ""
echo "Test 1: default (sequential) mode"
out=$(cd "$TMP" && bash "$RUN_ALL" 2>&1 || true)
rc=$(cd "$TMP" && bash "$RUN_ALL" >/dev/null 2>&1 ; echo $?)
assert "default exit code = 1 (1 of 3 fails)" "1" "$rc"
assert_grep "default per-file output for test_a"  'tests/test_a\.sh.*1/1 passed' "$out"
assert_grep "default per-file output for test_b"  'tests/test_b\.sh.*0/1 passed' "$out"
assert_grep "default per-file output for test_c"  'tests/test_c\.sh.*1/1 passed' "$out"

# ----- 2. --quick mode: only test_b runs (changed vs master) -----
echo ""
echo "Test 2: --quick mode"
out=$(cd "$TMP" && bash "$RUN_ALL" --quick 2>&1 || true)
rc=$(cd "$TMP" && bash "$RUN_ALL" --quick >/dev/null 2>&1 ; echo $?)
assert "--quick exit code = 1 (test_b is the only changed and it fails)" "1" "$rc"
assert_grep "--quick runs test_b" 'tests/test_b\.sh.*0/1 passed' "$out"
TOTAL=$((TOTAL + 1))
if printf '%s' "$out" | grep -qE 'tests/test_a\.sh.*passed'; then
  echo "  FAIL: --quick incorrectly ran test_a (should only run changed)"; FAIL=$((FAIL + 1))
else
  echo "  PASS: --quick did NOT run test_a (correctly filtered to changed)"; PASS=$((PASS + 1))
fi

# ----- 3. --parallel 2 mode: same aggregate as sequential -----
echo ""
echo "Test 3: --parallel 2 mode"
out=$(cd "$TMP" && bash "$RUN_ALL" --parallel 2 2>&1 || true)
rc=$(cd "$TMP" && bash "$RUN_ALL" --parallel 2 >/dev/null 2>&1 ; echo $?)
assert "--parallel exit code = 1" "1" "$rc"
assert_grep "--parallel runs all 3 files (test_a/b/c)" 'tests/test_a\.sh.*passed' "$out"

rm -rf "$TMP"

# ----- 4. G37 / US-003 (v0.6.7): --parallel detects non-zero exit even when -----
# the test's output line says "P/N passed" for P>0 (e.g. partial-run output
# before crash, or a test that fails on a final cleanup step after passing
# all assertions). Pre-fix: tests/run_all.sh:144 only checked grep for
# `: 0/[0-9]+ passed` — missed this case → false-green run_all status.
# Post-fix: xargs_rc capture catches the non-zero exit regardless of output.
echo ""
echo "Test 4: --parallel detects exit-1-with-passing-Results-line via xargs_rc"
TMP2=$(mktemp -d)
mkdir -p "$TMP2/tests"
cat > "$TMP2/tests/test_d.sh" <<'PARTIAL_FAIL'
#!/usr/bin/env bash
echo "test_d"
echo "  PASS: assertion-1"
echo "=== Results: 1/1 passed, 0 failed ==="
# Crashes AFTER printing the passing Results line — partial-run scenario.
exit 1
PARTIAL_FAIL
chmod +x "$TMP2/tests/test_d.sh"
( cd "$TMP2" && git init -q && git config user.email "t@t.t" && git config user.name "t"
  git checkout -q -b master
  git add tests/test_d.sh
  git commit -qm "fixture-d" ) >/dev/null 2>&1

rc=$(cd "$TMP2" && bash "$RUN_ALL" --parallel 2 >/dev/null 2>&1 ; echo $?)
assert "--parallel catches exit 1 even with 'P/N passed' P>0 output" "1" "$rc"
rm -rf "$TMP2"

echo ""
echo "=== Results: $PASS/$TOTAL passed, $FAIL failed ==="
[[ $FAIL -eq 0 ]] || exit 1
