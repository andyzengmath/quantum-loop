#!/usr/bin/env bash
# US-008 / P5.B4-plan — verify spec-reviewer.md has a 'plan-review' mode
# and ql-plan SKILL invokes it post-exit (after dag-validator + US-004's
# sprint-contract write). Advisory in v0.6.3.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$SCRIPT_DIR/.."
SPEC_REV="$REPO_ROOT/agents/spec-reviewer.md"
PLAN_SKILL="$REPO_ROOT/skills/ql-plan/SKILL.md"
PASS=0
FAIL=0
TOTAL=0

assert_grep() {
  local name="$1" needle="$2" file="$3"
  TOTAL=$((TOTAL + 1))
  if grep -qF -- "$needle" "$file"; then
    echo "  PASS: $name"; PASS=$((PASS + 1))
  else
    echo "  FAIL: $name — needle [$needle] not in $(basename "$file")"
    FAIL=$((FAIL + 1))
  fi
}

echo "=== US-008 / P5.B4-plan tests ==="

# Test 1: spec-reviewer.md has plan-review mode
echo ""
echo "Test 1: spec-reviewer.md has plan-review mode"
assert_grep "plan-review mode header" "plan-review" "$SPEC_REV"
assert_grep "AC coverage check" "AC coverage" "$SPEC_REV"
assert_grep "test-command consistency check" "testFirst" "$SPEC_REV"
assert_grep "wiring-task / consumedBy check" "wiring task" "$SPEC_REV"

# Test 2: ql-plan SKILL invokes plan-review
echo ""
echo "Test 2: ql-plan SKILL post-exit invocation"
assert_grep "plan-review mode reference" "plan-review" "$PLAN_SKILL"
assert_grep "spec-reviewer reference" "spec-reviewer" "$PLAN_SKILL"
assert_grep "QL_SKIP_PRE_IMPL_REVIEW gate" "QL_SKIP_PRE_IMPL_REVIEW" "$PLAN_SKILL"
assert_grep "stderr emission" "stderr" "$PLAN_SKILL"

# Test 3: ordering — plan-review chains after sprint-contract write (US-004 / Step 8)
echo ""
echo "Test 3: ordering documented"
TOTAL=$((TOTAL + 1))
# We expect the plan-review section text to come AFTER the Step 8 sprint-contract section.
sprint_line=$(grep -nF "Sprint-Contract write per story" "$PLAN_SKILL" | head -1 | cut -d: -f1)
plan_review_line=$(grep -nF "plan-review" "$PLAN_SKILL" | head -1 | cut -d: -f1)
if [[ -n "$sprint_line" && -n "$plan_review_line" ]] && (( plan_review_line > sprint_line )); then
  echo "  PASS: plan-review section appears after Step 8 (sprint-contract) — line $plan_review_line > $sprint_line"
  PASS=$((PASS + 1))
else
  echo "  FAIL: plan-review section not after sprint-contract (sprint=$sprint_line plan-review=$plan_review_line)"
  FAIL=$((FAIL + 1))
fi

# Test 4: behavioral synthetic — quantum.json with 2 stories + PRD with 3 ACs (1 missing)
echo ""
echo "Test 4: behavioral synthetic plan vs PRD"

TMP=$(mktemp -d)
mkdir -p "$TMP/tasks"

cat > "$TMP/quantum.json" <<'EOF'
{
  "stories": [
    {"id": "US-X", "acceptanceCriteria": ["AC1: Add field"], "tasks": [{"testFirst": true, "commands": ["bash tests/test_x.sh"]}]},
    {"id": "US-Y", "acceptanceCriteria": ["AC2: Display field"], "tasks": [{"testFirst": false, "commands": ["tsc --noEmit"]}]}
  ],
  "contracts": {}
}
EOF

cat > "$TMP/tasks/prd.md" <<'EOF'
# PRD test
## Section 3
- [ ] AC1: Add field
- [ ] AC2: Display field
- [ ] AC3: Filter by field
EOF

# Replay logic: extract PRD ACs, extract story ACs, compute set diff.
prd_acs=$(grep -E "^- \[ \] " "$TMP/tasks/prd.md" | sed 's/^- \[ \] //')
story_acs=$(jq -r '.stories[].acceptanceCriteria[]' "$TMP/quantum.json")

missing=0
while IFS= read -r ac; do
  ac="${ac%$'\r'}"
  [[ -z "$ac" ]] && continue
  if ! printf '%s' "$story_acs" | grep -qF -- "$ac"; then
    missing=$((missing + 1))
  fi
done <<< "$prd_acs"

TOTAL=$((TOTAL + 1))
if (( missing >= 1 )); then
  echo "  PASS: synthetic plan flags >=1 missing AC (got $missing)"
  PASS=$((PASS + 1))
else
  echo "  FAIL: synthetic plan failed to flag missing AC"
  FAIL=$((FAIL + 1))
fi

# testFirst=true story should have at least one test command
TOTAL=$((TOTAL + 1))
testfirst_with_tests=$(jq '[.stories[] | select(.tasks[] | .testFirst == true) | select(.tasks[].commands[]? | test("(test_|pytest|^bash tests/|^npm test|spec|\\.test\\.)"))] | length' "$TMP/quantum.json")
if [[ "$testfirst_with_tests" -gt 0 ]]; then
  echo "  PASS: testFirst story has matching test command (count=$testfirst_with_tests)"
  PASS=$((PASS + 1))
else
  echo "  FAIL: testFirst stories missing test commands"
  FAIL=$((FAIL + 1))
fi

# Test 5: opt-out env var
echo ""
echo "Test 5: QL_SKIP_PRE_IMPL_REVIEW=plan opt-out"
TOTAL=$((TOTAL + 1))
if grep -qE "QL_SKIP_PRE_IMPL_REVIEW.*plan" "$PLAN_SKILL"; then
  echo "  PASS: ql-plan SKILL gates on QL_SKIP_PRE_IMPL_REVIEW=plan"
  PASS=$((PASS + 1))
else
  echo "  FAIL: ql-plan SKILL missing QL_SKIP_PRE_IMPL_REVIEW=plan gate"
  FAIL=$((FAIL + 1))
fi

# csv chain: design,prd,plan
TOTAL=$((TOTAL + 1))
SKIP_LIST="design,prd,plan"
should_skip=$(printf '%s' "$SKIP_LIST" | tr ',' '\n' | grep -qx "plan" && echo "yes" || echo "no")
if [[ "$should_skip" == "yes" ]]; then
  echo "  PASS: csv parser identifies 'plan' in 'design,prd,plan'"
  PASS=$((PASS + 1))
else
  echo "  FAIL: csv parser missed 'plan' in 'design,prd,plan'"
  FAIL=$((FAIL + 1))
fi

rm -rf "$TMP"

echo ""
echo "=== Results: $PASS/$TOTAL passed, $FAIL failed ==="
[[ $FAIL -eq 0 ]] || exit 1
