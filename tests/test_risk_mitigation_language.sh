#!/usr/bin/env bash
# G28 / US-004 (v0.6.5) -- structural tests for the risk-mitigation-language
# checklist doc. The doc itself is prose; we assert the checklist sections
# and the cautionary-tale citation are present, so future edits cannot
# silently delete the load-bearing parts.
#
# The doc derives from the v0.6.4 cautionary tale: the design-doc Risk
# section said "use flock-style atomic append" but the implementation
# wrote the CSV header outside the lock, leaving a race window the
# soliton finding (confidence 90) caught and commit c89ba13 closed.
# Test 9-10 enforce that the doc cites both the SHA and "soliton" so
# the cautionary tale stays attached to the rule.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$SCRIPT_DIR/.."
DOC="$REPO_ROOT/references/risk-mitigation-language.md"
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

# Case-insensitive variant: same fixed-string semantics as assert_grep but
# matches regardless of letter case. Used for checklist headers that read
# naturally as "Shared mutable state" (Title-Case bold label) but were
# spec'd in the user-story acceptance criterion in lowercase.
assert_grep_ci() {
  local name="$1" needle="$2" file="$3"
  TOTAL=$((TOTAL + 1))
  if grep -qFi -- "$needle" "$file"; then
    echo "  PASS: $name"; PASS=$((PASS + 1))
  else
    echo "  FAIL: $name -- needle [$needle] not in $(basename "$file") (case-insensitive)"
    FAIL=$((FAIL + 1))
  fi
}

echo "=== G28 / US-004 risk-mitigation-language doc tests ==="

# Test 1: doc file exists at the expected path
echo ""
echo "Test 1: references/risk-mitigation-language.md exists"
TOTAL=$((TOTAL + 1))
if [[ -f "$DOC" ]]; then
  echo "  PASS: doc file present"; PASS=$((PASS + 1))
else
  echo "  FAIL: doc file missing at $DOC"; FAIL=$((FAIL + 1))
  echo ""
  echo "=== Results: $PASS/$TOTAL passed, $FAIL failed ==="
  exit 1
fi

# Test 2-4: required section headers (per acceptance criterion 1)
echo ""
echo "Test 2-4: required section headers"
assert_grep "section: Risk-mitigation prose"      "## Risk-mitigation prose: enumerate operations" "$DOC"
assert_grep "section: Concurrency checklist"      "## Concurrency checklist"                        "$DOC"
assert_grep "section: Other risk-mitigation"      "## Other risk-mitigation language patterns"     "$DOC"

# Test 5-8: concurrency checklist requirements (per acceptance criterion 2).
# The doc's natural form Title-Cases the bold checklist labels (e.g.,
# "Shared mutable state."), so we use the case-insensitive matcher; the
# AC was written in lowercase prose but the rendered doc reads more
# naturally with Title-Case labels. Either form satisfies the AC's intent.
echo ""
echo "Test 5-8: concurrency checklist enumerates 4 requirements"
assert_grep_ci "checklist: shared mutable state"        "shared mutable state"        "$DOC"
assert_grep_ci "checklist: observably-coupled ops"      "observably-coupled operations" "$DOC"
assert_grep_ci "checklist: race window without"         "race window without"         "$DOC"
assert_grep_ci "checklist: race window with"            "race window with"            "$DOC"

# Test 9-10: cautionary-tale citation (per acceptance criterion 3)
echo ""
echo "Test 9-10: cautionary tale cites c89ba13 + soliton"
assert_grep "citation: commit c89ba13" "c89ba13" "$DOC"
assert_grep "citation: soliton finding" "soliton" "$DOC"

echo ""
echo "=== Results: $PASS/$TOTAL passed, $FAIL failed ==="
exit $((FAIL > 0 ? 1 : 0))
