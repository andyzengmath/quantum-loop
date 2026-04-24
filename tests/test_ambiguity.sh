#!/usr/bin/env bash
# Phase 19 / P2.8 — ambiguity scoring + gate + challenge mode tests.

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
source "$REPO_ROOT/lib/ambiguity.sh"

echo "=== Phase 19 ambiguity-gate tests ==="

# Test 1: score_ambiguity boundary conditions
echo ""
echo "Test 1: score_ambiguity arithmetic"
assert "all 10s -> 0"   "0"   "$(score_ambiguity 10 10 10)"
assert "all 0s -> 100"  "100" "$(score_ambiguity 0 0 0)"
assert "all 5s -> 50"   "50"  "$(score_ambiguity 5 5 5)"
# goal weighs more: (10,0,0) -> 100 - (40+0+0) = 60
assert "goal only -> 60" "60" "$(score_ambiguity 10 0 0)"
# constraints only: 100 - (0+30+0) = 70
assert "constraints only -> 70" "70" "$(score_ambiguity 0 10 0)"
# criteria only: 100 - (0+0+30) = 70
assert "criteria only -> 70" "70" "$(score_ambiguity 0 0 10)"

# Test 2: score_ambiguity rejects non-integer / out-of-range
echo ""
echo "Test 2: score_ambiguity input validation"
score_ambiguity 11 5 5 2>/dev/null
assert "11 rejected" "1" "$?"
score_ambiguity -1 5 5 2>/dev/null
assert "-1 rejected" "1" "$?"
score_ambiguity abc 5 5 2>/dev/null
assert "abc rejected" "1" "$?"

# Test 3: check_gate default threshold 20
echo ""
echo "Test 3: check_gate semantics"
check_gate 0;   assert "score 0 passes"   "0" "$?"
check_gate 19;  assert "score 19 passes"  "0" "$?"
check_gate 20;  assert "score 20 blocks"  "1" "$?"
check_gate 50;  assert "score 50 blocks"  "1" "$?"
check_gate 100; assert "score 100 blocks" "1" "$?"
# Custom threshold
check_gate 30 50; assert "30 < 50 passes" "0" "$?"
check_gate 60 50; assert "60 >= 50 blocks" "1" "$?"

# Test 4: challenge_mode transitions
echo ""
echo "Test 4: challenge_mode thresholds"
assert "round 1, score 100 -> normal"     "normal"      "$(challenge_mode 1 100)"
assert "round 2, score 80  -> normal"     "normal"      "$(challenge_mode 2 80)"
assert "round 3, score 45  -> contrarian" "contrarian"  "$(challenge_mode 3 45)"
assert "round 3, score 35  -> normal"     "normal"      "$(challenge_mode 3 35)"
assert "round 4, score 35  -> simplifier" "simplifier"  "$(challenge_mode 4 35)"
assert "round 4, score 25  -> normal"     "normal"      "$(challenge_mode 4 25)"
assert "round 5, score 25  -> ontologist" "ontologist"  "$(challenge_mode 5 25)"
assert "round 5, score 15  -> normal"     "normal"      "$(challenge_mode 5 15)"
assert "round 6, score 50  -> ontologist" "ontologist"  "$(challenge_mode 6 50)"

# Test 5: ontology_extract basics
echo ""
echo "Test 5: ontology_extract"
out=$(ontology_extract "Build a priority system for tasks with filtering")
# Expected alphabetized unique tokens (each ≥4 chars, excluding stopwords)
# "build priority system tasks filtering"  (alphabetical: build filtering priority system tasks)
assert "extract tokens sorted+unique" "build filtering priority system tasks" "$out"
# Empty input returns empty
assert "empty -> empty" "" "$(ontology_extract "")"
# Stopwords dropped
out=$(ontology_extract "the user will have a feature that does something work")
# After dropping "the, user, will, have, feature, that", remaining ≥4-char
# non-stopword tokens: does, something, work
assert "stopwords dropped" "does something work" "$out"

# Test 6: ontology_diff carries, adds, removes, stability
echo ""
echo "Test 6: ontology_diff"
prior="apple banana cherry"
current="banana cherry durian"
diff=$(ontology_diff "$prior" "$current")
added_n=$(jq '.added | length' <<< "$diff")
removed_n=$(jq '.removed | length' <<< "$diff")
carried_n=$(jq '.carried | length' <<< "$diff")
assert "1 added"   "1" "$added_n"
assert "1 removed" "1" "$removed_n"
assert "2 carried" "2" "$carried_n"
stab=$(jq -r '.stability' <<< "$diff")
# 2 carried out of 4 total -> 0.50
assert "stability 0.50" "0.50" "$stab"

# Identical sets -> stability 1.0
diff2=$(ontology_diff "x y z" "x y z")
assert "identical stability 1.0" "1.0" "$(jq -r '.stability' <<< "$diff2")"

# Empty prior + non-empty current -> 0.0
diff3=$(ontology_diff "" "a b c")
assert "empty prior stability 0.00" "0.00" "$(jq -r '.stability' <<< "$diff3")"

# Test 7: CLI entry
echo ""
echo "Test 7: CLI subcommands"
cli_score=$(bash "$REPO_ROOT/lib/ambiguity.sh" score 5 5 5 | tr -d '\n')
assert "CLI score 5 5 5 = 50" "50" "$cli_score"
bash "$REPO_ROOT/lib/ambiguity.sh" gate 10 >/dev/null 2>&1
assert "CLI gate 10 passes" "0" "$?"
bash "$REPO_ROOT/lib/ambiguity.sh" gate 25 >/dev/null 2>&1
assert "CLI gate 25 blocks" "1" "$?"
cli_mode=$(bash "$REPO_ROOT/lib/ambiguity.sh" mode 5 30 | tr -d '\n')
assert "CLI mode 5 30 = ontologist" "ontologist" "$cli_mode"

# Test 8: ql-brainstorm wires the ambiguity gate
echo ""
echo "Test 8: ql-brainstorm wires lib/ambiguity.sh"
BS="$REPO_ROOT/skills/ql-brainstorm/SKILL.md"
check_in() {
  local name="$1" needle="$2"
  TOTAL=$((TOTAL + 1))
  if grep -qF -- "$needle" "$BS"; then
    echo "  PASS: $name"; PASS=$((PASS + 1))
  else
    echo "  FAIL: $name — needle [$needle] not in $BS"
    FAIL=$((FAIL + 1))
  fi
}
check_in "Phase 0B ambiguity gate section" "Phase 0B: Ambiguity gate"
check_in "calls lib/ambiguity.sh score"    "lib/ambiguity.sh score"
check_in "calls lib/ambiguity.sh gate"     "lib/ambiguity.sh gate"
check_in "calls lib/ambiguity.sh mode"     "lib/ambiguity.sh mode"
check_in "ontology stability tracking"     "lib/ambiguity.sh extract"
check_in "ontology diff call"              "lib/ambiguity.sh diff"
check_in "contrarian mode described"       "contrarian"
check_in "simplifier mode described"       "simplifier"
check_in "ontologist mode described"       "ontologist"
check_in "thrashing ontology escalation"   "stability < 0.5"
check_in "handoff records final_score"     "final_score"

echo ""
echo "=== Results: $PASS/$TOTAL passed, $FAIL failed ==="
exit $((FAIL > 0 ? 1 : 0))
