#!/usr/bin/env bash
# Phase 9 / P1.6 — tests for lib/deslop.sh helpers + schema + wiring.

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
    echo "  FAIL: $name"
    echo "    expected: [$expected]"
    echo "    actual:   [$actual]"
    FAIL=$((FAIL + 1))
  fi
}

assert_exit_code() {
  local name="$1" expected="$2" rc="$3"
  TOTAL=$((TOTAL + 1))
  if [[ "$rc" == "$expected" ]]; then
    echo "  PASS: $name (exit $rc)"; PASS=$((PASS + 1))
  else
    echo "  FAIL: $name (expected $expected, got $rc)"
    FAIL=$((FAIL + 1))
  fi
}

# shellcheck disable=SC1091
source "$REPO_ROOT/lib/deslop.sh"

echo "=== Phase 9 ql-deslop helper tests ==="

# Test 1: validate_scope accepts files in diff, rejects out-of-scope
echo ""
echo "Test 1: validate_scope"
TEST_TMPDIR=$(mktemp -d)
cd "$TEST_TMPDIR"
git init -q
git commit --allow-empty -m "init" -q
BASE=$(git rev-parse HEAD)
echo "in" > in-scope.txt
git add in-scope.txt
git commit -q -m "add in-scope"
echo "modified" >> in-scope.txt
git add in-scope.txt
git commit -q -m "modify"
HEAD_S=$(git rev-parse HEAD)
# out-of-scope file exists in workspace but not in BASE..HEAD
echo "out" > out-of-scope.txt
validate_scope in-scope.txt "$BASE" "$HEAD_S" 2>/dev/null; rc=$?
assert_exit_code "in-scope file accepted" "0" "$rc"
validate_scope out-of-scope.txt "$BASE" "$HEAD_S" 2>/dev/null; rc=$?
assert_exit_code "out-of-scope file rejected" "1" "$rc"
cd "$REPO_ROOT"
rm -rf "$TEST_TMPDIR"

# Test 2: take_baseline writes a valid JSON snapshot
echo ""
echo "Test 2: take_baseline snapshot shape"
BL=$(mktemp)
take_baseline "$BL" "true" "true" "true"
has_test=$(jq 'has("test_exit")' "$BL")
has_lint=$(jq 'has("lint_exit")' "$BL")
has_tc=$(jq 'has("typecheck_exit")' "$BL")
assert "snapshot has test_exit" "true" "$has_test"
assert "snapshot has lint_exit" "true" "$has_lint"
assert "snapshot has typecheck_exit" "true" "$has_tc"
# Values should be 0 because we passed `true` as each cmd
test_val=$(jq '.test_exit' "$BL")
assert "snapshot test_exit = 0" "0" "$test_val"
rm -f "$BL"

# Test 3: compare_baseline detects regressions
echo ""
echo "Test 3: compare_baseline regression detection"
BEFORE=$(mktemp); AFTER=$(mktemp)
printf '{"test_exit":0,"lint_exit":0,"typecheck_exit":0,"captured_at":1}\n' > "$BEFORE"
printf '{"test_exit":0,"lint_exit":0,"typecheck_exit":0,"captured_at":2}\n' > "$AFTER"
compare_baseline "$BEFORE" "$AFTER" >/dev/null 2>&1
assert "matching baselines -> clean (exit 0)" "0" "$?"
printf '{"test_exit":1,"lint_exit":0,"typecheck_exit":0,"captured_at":2}\n' > "$AFTER"
compare_baseline "$BEFORE" "$AFTER" >/dev/null 2>&1
assert "test regression -> dirty (exit 1)" "1" "$?"
# Improvement case: before was red, after is green -> not a regression
printf '{"test_exit":1,"lint_exit":1,"typecheck_exit":1,"captured_at":1}\n' > "$BEFORE"
printf '{"test_exit":0,"lint_exit":0,"typecheck_exit":0,"captured_at":2}\n' > "$AFTER"
compare_baseline "$BEFORE" "$AFTER" >/dev/null 2>&1
assert "improvement -> clean (exit 0)" "0" "$?"
rm -f "$BEFORE" "$AFTER"

# Test 4: rollback_pass restores files
echo ""
echo "Test 4: rollback_pass restores baseline content"
TEST_TMPDIR=$(mktemp -d)
cd "$TEST_TMPDIR"
git init -q
echo "original" > afile.txt
git add afile.txt
git commit -q -m "baseline"
BASE=$(git rev-parse HEAD)
echo "poisoned" > afile.txt
pre=$(cat afile.txt)
rollback_pass "$BASE" afile.txt
post=$(cat afile.txt)
assert "pre-rollback content" "poisoned" "$pre"
assert "post-rollback content" "original" "$post"
cd "$REPO_ROOT"
rm -rf "$TEST_TMPDIR"

# Test 5: detect_language dispatch
echo ""
echo "Test 5: detect_language marker-file dispatch"
TEST_TMPDIR=$(mktemp -d)
# unknown dir
assert "empty dir -> unknown|skip" "unknown|skip" "$(detect_language "$TEST_TMPDIR")"
# TypeScript
echo '{}' > "$TEST_TMPDIR/tsconfig.json"
lang=$(detect_language "$TEST_TMPDIR")
# The exact tool suffix depends on env (ts-prune present or not); assert on language prefix
assert "tsconfig.json -> typescript" "typescript" "${lang%%|*}"
rm -rf "$TEST_TMPDIR"
TEST_TMPDIR=$(mktemp -d)
echo '{}' > "$TEST_TMPDIR/package.json"
lang=$(detect_language "$TEST_TMPDIR")
assert "package.json -> javascript" "javascript" "${lang%%|*}"
rm -rf "$TEST_TMPDIR"
TEST_TMPDIR=$(mktemp -d)
echo 'module m' > "$TEST_TMPDIR/go.mod"
lang=$(detect_language "$TEST_TMPDIR")
assert "go.mod -> go" "go" "${lang%%|*}"
rm -rf "$TEST_TMPDIR"
TEST_TMPDIR=$(mktemp -d)
echo 'package' > "$TEST_TMPDIR/Cargo.toml"
lang=$(detect_language "$TEST_TMPDIR")
assert "Cargo.toml -> rust" "rust" "${lang%%|*}"
rm -rf "$TEST_TMPDIR"

# Test 6: Schema extension — quantum.json.example has deslop field
echo ""
echo "Test 6: quantum.json.example schema"
deslop_type=$(jq -r '.deslop | type' "$REPO_ROOT/quantum.json.example")
assert "deslop is object" "object" "$deslop_type"
if jq empty "$REPO_ROOT/quantum.json.example" 2>/dev/null; then
  echo "  PASS: quantum.json.example still valid JSON"
  PASS=$((PASS + 1))
else
  echo "  FAIL: quantum.json.example INVALID JSON"
  FAIL=$((FAIL + 1))
fi
TOTAL=$((TOTAL + 1))

# Test 7: ql-execute SKILL.md references the deslop hook
echo ""
echo "Test 7: ql-execute mentions ql-deslop hook"
if grep -q "Post-review slop-cleanup hook" "$REPO_ROOT/skills/ql-execute/SKILL.md"; then
  echo "  PASS: slop-cleanup hook header present"; PASS=$((PASS + 1))
else
  echo "  FAIL: header missing"; FAIL=$((FAIL + 1))
fi
TOTAL=$((TOTAL + 1))
if grep -q "lib/deslop.sh" "$REPO_ROOT/skills/ql-execute/SKILL.md"; then
  echo "  PASS: references lib/deslop.sh"; PASS=$((PASS + 1))
else
  echo "  FAIL: missing lib/deslop.sh reference"; FAIL=$((FAIL + 1))
fi
TOTAL=$((TOTAL + 1))
if grep -q "DESLOP_ROLLED_BACK" "$REPO_ROOT/skills/ql-execute/SKILL.md"; then
  echo "  PASS: mentions DESLOP_ROLLED_BACK signal"; PASS=$((PASS + 1))
else
  echo "  FAIL: missing rollback signal"; FAIL=$((FAIL + 1))
fi
TOTAL=$((TOTAL + 1))

# Test 8: CLI subcommands
echo ""
echo "Test 8: CLI entrypoints"
TEST_TMPDIR=$(mktemp -d)
echo '{}' > "$TEST_TMPDIR/tsconfig.json"
cli_out=$(bash "$REPO_ROOT/lib/deslop.sh" detect-language "$TEST_TMPDIR")
assert "CLI detect-language typescript prefix" "typescript" "${cli_out%%|*}"
rm -rf "$TEST_TMPDIR"

echo ""
echo "=== Results: $PASS/$TOTAL passed, $FAIL failed ==="
exit $((FAIL > 0 ? 1 : 0))
