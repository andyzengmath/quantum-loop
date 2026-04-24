#!/usr/bin/env bash
# Phase 28 / P3.9 — re-grounding tests.

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

# shellcheck disable=SC1091
source "$REPO_ROOT/lib/reground.sh"

echo "=== Phase 28 re-grounding tests ==="

# Test 1: should_reground — at interval triggers
echo ""
echo "Test 1: should_reground at interval"
state=$(jq -cn '{iteration: 5, state: {lastGroundedIteration: 0}}')
should_reground "$state"
assert "iter=5, last=0, interval=5 -> 0" "0" "$?"

# Test 2: should_reground — below interval does not trigger
echo ""
echo "Test 2: below interval"
state=$(jq -cn '{iteration: 3, state: {lastGroundedIteration: 0}}')
should_reground "$state"
assert "iter=3, last=0, interval=5 -> 1" "1" "$?"

# Test 3: should_reground — past interval triggers
echo ""
echo "Test 3: past interval (delta 6)"
state=$(jq -cn '{iteration: 10, state: {lastGroundedIteration: 4}}')
should_reground "$state"
assert "iter=10, last=4, interval=5 -> 0" "0" "$?"

# Test 4: should_reground — just after grounding doesn't re-trigger
echo ""
echo "Test 4: just-grounded state"
state=$(jq -cn '{iteration: 5, state: {lastGroundedIteration: 5}}')
should_reground "$state"
assert "iter=5, last=5 -> 1" "1" "$?"

# Test 5: should_reground — missing state field defaults to 0
echo ""
echo "Test 5: missing lastGroundedIteration defaults to 0"
state=$(jq -cn '{iteration: 5}')
should_reground "$state"
assert "no state field, iter=5 -> 0" "0" "$?"

# Test 6: should_reground — env override REGROUND_INTERVAL
echo ""
echo "Test 6: REGROUND_INTERVAL override"
state=$(jq -cn '{iteration: 3, state: {lastGroundedIteration: 0}}')
REGROUND_INTERVAL=3 should_reground "$state"
assert "interval=3, delta=3 -> 0" "0" "$?"
REGROUND_INTERVAL=10 should_reground "$state"
assert "interval=10, delta=3 -> 1" "1" "$?"

# Test 7: should_reground — reads from stdin when no arg
echo ""
echo "Test 7: stdin input"
state=$(jq -cn '{iteration: 5, state: {lastGroundedIteration: 0}}')
printf '%s' "$state" | should_reground
assert "stdin trigger" "0" "$?"

# Test 8: build_reground_context — basic shape
echo ""
echo "Test 8: build_reground_context shape"
q=$(jq -cn '{
  iteration: 7,
  branchName: "feat/x",
  prdPath: "/nonexistent/spec.md",
  stories: [
    {id: "S1", status: "passed", priority: 1, title: "a"},
    {id: "S2", status: "passed", priority: 2, title: "b"},
    {id: "S3", status: "pending", priority: 3, title: "c"},
    {id: "S4", status: "failed", priority: 4, title: "d"},
    {id: "S5", status: "pending", priority: 5, title: "e"}
  ]
}')
ctx=$(printf '%s' "$q" | build_reground_context)
case "$ctx" in *"## Re-grounding (iteration 7)"*) echo "  PASS: header with iteration"; PASS=$((PASS + 1));;
                *) echo "  FAIL: no header"; FAIL=$((FAIL + 1));;
esac
TOTAL=$((TOTAL + 1))
case "$ctx" in *"feat/x"*) echo "  PASS: branch rendered"; PASS=$((PASS + 1));;
                *) echo "  FAIL: no branch"; FAIL=$((FAIL + 1));;
esac
TOTAL=$((TOTAL + 1))
case "$ctx" in *"2/5 passed"*"1 failed"*"2 pending"*) echo "  PASS: progress counts"; PASS=$((PASS + 1));;
                *) echo "  FAIL: progress counts missing"; FAIL=$((FAIL + 1));;
esac
TOTAL=$((TOTAL + 1))
case "$ctx" in *"Goal reminder"*"Verify EACH claim"*) echo "  PASS: goal reminder"; PASS=$((PASS + 1));;
                *) echo "  FAIL: no goal reminder"; FAIL=$((FAIL + 1));;
esac
TOTAL=$((TOTAL + 1))

# Test 9: build_reground_context — next stories listed in priority order
echo ""
echo "Test 9: next pending stories listed"
case "$ctx" in *"S3"*"S5"*) echo "  PASS: pending stories S3, S5 listed"; PASS=$((PASS + 1));;
                *) echo "  FAIL: pending stories missing"; FAIL=$((FAIL + 1));;
esac
TOTAL=$((TOTAL + 1))
# Passed/failed stories should NOT appear in the next-up list
case "$ctx" in
  *"- **S1**"*|*"- **S2**"*|*"- **S4**"*)
    echo "  FAIL: non-pending story in next-up list"; FAIL=$((FAIL + 1));;
  *)
    echo "  PASS: only pending stories in next-up"; PASS=$((PASS + 1));;
esac
TOTAL=$((TOTAL + 1))

# Test 10: build_reground_context — PRD head included when file exists
echo ""
echo "Test 10: PRD head included when file exists"
TEST_TMPDIR=$(mktemp -d)
cat > "$TEST_TMPDIR/spec.md" << 'EOF'
# Feature X

Build widget that does Y. Users should be able to Z.

## Acceptance criteria

- Widget exists
- Widget works
EOF
q=$(jq -cn --arg p "$TEST_TMPDIR/spec.md" '{
  iteration: 5, branchName: "b", prdPath: $p,
  stories: [{id: "S1", status: "pending", priority: 1, title: "t"}]
}')
ctx=$(printf '%s' "$q" | build_reground_context)
case "$ctx" in *"### PRD head"*"Build widget that does Y"*) echo "  PASS: PRD head rendered"; PASS=$((PASS + 1));;
                *) echo "  FAIL: no PRD head content"; FAIL=$((FAIL + 1));;
esac
TOTAL=$((TOTAL + 1))
rm -rf "$TEST_TMPDIR"

# Test 11: build_reground_context — missing PRD file gracefully skipped
echo ""
echo "Test 11: missing PRD handled"
q=$(jq -cn '{
  iteration: 1, prdPath: "/does/not/exist.md",
  stories: [{id: "S1", status: "pending", priority: 1, title: "t"}]
}')
ctx=$(printf '%s' "$q" | build_reground_context)
case "$ctx" in *"PRD head"*) echo "  FAIL: PRD head section rendered for missing file"; FAIL=$((FAIL + 1));;
                *) echo "  PASS: missing PRD skipped cleanly"; PASS=$((PASS + 1));;
esac
TOTAL=$((TOTAL + 1))

# Test 12: build_reground_context — empty quantum.json (no stories)
echo ""
echo "Test 12: empty stories array"
q=$(jq -cn '{iteration: 0, stories: []}')
ctx=$(printf '%s' "$q" | build_reground_context)
case "$ctx" in *"0/0 passed"*) echo "  PASS: empty progress rendered"; PASS=$((PASS + 1));;
                *) echo "  FAIL: empty progress wrong"; FAIL=$((FAIL + 1));;
esac
TOTAL=$((TOTAL + 1))

# Test 13: mark_grounded — writes lastGroundedIteration
echo ""
echo "Test 13: mark_grounded updates state"
TEST_TMPDIR=$(mktemp -d)
echo '{"iteration": 7, "state": {"other": "keep"}}' > "$TEST_TMPDIR/q.json"
mark_grounded "$TEST_TMPDIR/q.json"
after=$(jq -r '.state.lastGroundedIteration' "$TEST_TMPDIR/q.json")
assert "lastGroundedIteration = 7" "7" "$after"
# Verify other state fields preserved
other=$(jq -r '.state.other' "$TEST_TMPDIR/q.json")
assert "other state preserved" "keep" "$other"
rm -rf "$TEST_TMPDIR"

# Test 14: mark_grounded — creates state object if missing
echo ""
echo "Test 14: mark_grounded creates state if absent"
TEST_TMPDIR=$(mktemp -d)
echo '{"iteration": 3}' > "$TEST_TMPDIR/q.json"
mark_grounded "$TEST_TMPDIR/q.json"
after=$(jq -r '.state.lastGroundedIteration' "$TEST_TMPDIR/q.json")
assert "state created, lastGroundedIteration = 3" "3" "$after"
rm -rf "$TEST_TMPDIR"

# Test 15: mark_grounded — missing file returns non-zero
echo ""
echo "Test 15: mark_grounded missing file"
mark_grounded "/nonexistent/q.json" 2>/dev/null
assert "missing file -> exit 1" "1" "$?"

# Test 16: mark_grounded then should_reground == false on that state
echo ""
echo "Test 16: mark_grounded resets the should_reground signal"
TEST_TMPDIR=$(mktemp -d)
echo '{"iteration": 10}' > "$TEST_TMPDIR/q.json"
# Before marking: delta = 10 - 0 = 10, >= 5 → should_reground
cat "$TEST_TMPDIR/q.json" | should_reground
assert "before mark: should -> 0" "0" "$?"
mark_grounded "$TEST_TMPDIR/q.json"
# After marking: delta = 10 - 10 = 0 → no
cat "$TEST_TMPDIR/q.json" | should_reground
assert "after mark: should -> 1" "1" "$?"
rm -rf "$TEST_TMPDIR"

# Test 17: CLI subcommands
echo ""
echo "Test 17: CLI subcommands"
state=$(jq -cn '{iteration: 5, state: {lastGroundedIteration: 0}}')
printf '%s' "$state" | bash "$REPO_ROOT/lib/reground.sh" should
assert "CLI should -> 0" "0" "$?"
# CLI context
q=$(jq -cn '{iteration: 2, stories: [{id: "X", status: "pending", priority: 1, title: "t"}]}')
cli_ctx=$(printf '%s' "$q" | bash "$REPO_ROOT/lib/reground.sh" context)
case "$cli_ctx" in *"Re-grounding (iteration 2)"*) echo "  PASS: CLI context"; PASS=$((PASS + 1));;
                    *) echo "  FAIL: CLI context missing header"; FAIL=$((FAIL + 1));;
esac
TOTAL=$((TOTAL + 1))
# CLI mark
TEST_TMPDIR=$(mktemp -d)
echo '{"iteration": 9}' > "$TEST_TMPDIR/q.json"
bash "$REPO_ROOT/lib/reground.sh" mark "$TEST_TMPDIR/q.json"
after=$(jq -r '.state.lastGroundedIteration' "$TEST_TMPDIR/q.json")
assert "CLI mark updates field" "9" "$after"
rm -rf "$TEST_TMPDIR"

echo ""
echo "=== Results: $PASS/$TOTAL passed, $FAIL failed ==="
exit $((FAIL > 0 ? 1 : 0))
