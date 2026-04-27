#!/usr/bin/env bash
# v0.7.0 / US-006 (G15) -- CHANGELOG-ownership convention tests.
#
# The conflict-auditor agent is LLM-driven (no shell module computes
# fileConflicts severity). We therefore test the convention via:
#   (a) doc-grep against dag-validator.md for the convention paragraph
#   (b) doc-grep against conflict-auditor.md for the new severity rule
#   (c) doc-grep that the rule references "CHANGELOG.md" + the severity
#       label "warning" + the "consolidate to a single retrospective story"
#       Health Report line
#
# Behavioral coverage of the rule's runtime emission lives in the
# agent's instruction text — the agent reads its prompt every spawn.
# A deterministic shell-side check would require duplicating the
# severity-classification logic in two places (the very anti-pattern
# v0.7.0 G14 just removed via SPRINT_CONTRACT_TEST_REGEX). We assert
# the rule is documented; the runtime adherence is the agent's contract.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$SCRIPT_DIR/.."
DAG_DOC="$REPO_ROOT/agents/dag-validator.md"
AUDIT_DOC="$REPO_ROOT/agents/conflict-auditor.md"
PASS=0
FAIL=0
TOTAL=0

assert_grep() {
  local name="$1" needle="$2" file="$3"
  TOTAL=$((TOTAL + 1))
  if grep -qF -- "$needle" "$file"; then
    echo "  PASS: $name"; PASS=$((PASS + 1))
  else
    echo "  FAIL: $name -- needle [$needle] not in $(basename "$file")"
    FAIL=$((FAIL + 1))
  fi
}

assert_grep_E() {
  # Same as assert_grep but uses extended-regex (-E) instead of fixed string.
  local name="$1" pattern="$2" file="$3"
  TOTAL=$((TOTAL + 1))
  if grep -qE -- "$pattern" "$file"; then
    echo "  PASS: $name"; PASS=$((PASS + 1))
  else
    echo "  FAIL: $name -- pattern [$pattern] not in $(basename "$file")"
    FAIL=$((FAIL + 1))
  fi
}

echo "=== v0.7.0 US-006 CHANGELOG-ownership convention tests ==="

# Sanity: agent docs exist
echo ""
echo "Sanity: agent docs present"
TOTAL=$((TOTAL + 1))
if [[ -f "$DAG_DOC" && -f "$AUDIT_DOC" ]]; then
  echo "  PASS: agents/dag-validator.md + agents/conflict-auditor.md exist"
  PASS=$((PASS + 1))
else
  echo "  FAIL: missing required agent doc(s)"
  FAIL=$((FAIL + 1))
  echo ""
  echo "=== Results: $PASS/$TOTAL passed, $FAIL failed ==="
  exit 1
fi

# Test 1: dag-validator.md gains a convention paragraph naming CHANGELOG.md
echo ""
echo "Test 1: dag-validator.md documents the CHANGELOG ownership convention"
assert_grep "CHANGELOG.md mentioned"               "CHANGELOG.md"                                    "$DAG_DOC"
assert_grep "consolidate-to-retrospective phrase"  "consolidate to a single retrospective story"    "$DAG_DOC"

# Test 2: conflict-auditor.md (or a Rule 6 entry) names the CHANGELOG rule
echo ""
echo "Test 2: conflict-auditor.md gains the CHANGELOG severity rule"
assert_grep "CHANGELOG.md mentioned"   "CHANGELOG.md" "$AUDIT_DOC"
assert_grep "warning severity label"   "warning"      "$AUDIT_DOC"

# Test 3: severity:warning explicitly tied to >1 stories case
# (Look for a phrase mentioning >1 / multiple / stories.length / count > 1
#  near the CHANGELOG line in conflict-auditor.md.)
echo ""
echo "Test 3: severity rule encodes the >1 stories trigger"
assert_grep_E "CHANGELOG +>1 trigger condition" "CHANGELOG\.md.*(>[[:space:]]*1|2 or more|stories.length|multiple|>= ?2)" "$AUDIT_DOC"

# Test 4: Health Report line text appears in dag-validator.md
echo ""
echo "Test 4: Health Report warning text"
assert_grep "Health-Report warning text"   "stories touch CHANGELOG.md"   "$DAG_DOC"

# Test 5: not-severity-none — verify the rule explicitly contrasts warning vs none
# (the whole point of G15 is to override the existing default severity:none for
#  CHANGELOG-only conflicts when count > 1)
echo ""
echo "Test 5: rule documents the warning-not-none distinction"
assert_grep_E "warning not none distinction" "(not[[:space:]]+severity:[[:space:]]*none|warning[^a-z]+not[^a-z]+severity:[[:space:]]*none|severity:[[:space:]]*warning.*not[[:space:]]+severity:[[:space:]]*none|warning.*not.*none)" "$AUDIT_DOC"

# Test 6: CHANGELOG-touch counts of 0 and 1 produce no warning.
# Verified at the doc level: the rule paragraph must scope the trigger to
# multiple-stories ("more than one" / "> 1" / "2+") so a single-story owner
# (the v0.7.0 retrospective US-007) is explicitly NOT flagged.
echo ""
echo "Test 6: rule scopes warning to multi-story case (single-story = no warning)"
assert_grep_E "single-story-ok scope" "(more than one|> ?1|2\+|two or more|stories.length > 1|when[[:space:]]+more[[:space:]]+than[[:space:]]+one)" "$DAG_DOC"

echo ""
echo "=== Results: $PASS/$TOTAL passed, $FAIL failed ==="
exit $((FAIL > 0 ? 1 : 0))
