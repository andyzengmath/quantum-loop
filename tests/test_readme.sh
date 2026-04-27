#!/usr/bin/env bash
# G20 / US-006 (v0.6.5) -- README structural tests for the new
# "## Self-modifying execution" section. Closes the operator-confusion
# gap surfaced in PIPELINE_REPORT_v5: a fresh-checkout operator
# misreading the empty pre-impl-review CSV as a regression. The
# README section explains that quantum-loop modifies the very
# orchestrator/agent/skill prompts the orchestrator itself uses, so
# each release's wires apply to the NEXT run, not the current dogfood.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$SCRIPT_DIR/.."
README="$REPO_ROOT/README.md"
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
  local name="$1" pattern="$2" file="$3"
  TOTAL=$((TOTAL + 1))
  if grep -qE -- "$pattern" "$file"; then
    echo "  PASS: $name"; PASS=$((PASS + 1))
  else
    echo "  FAIL: $name -- pattern [$pattern] not in $(basename "$file")"
    FAIL=$((FAIL + 1))
  fi
}

echo "=== G20 / US-006 README self-modifying-execution tests ==="

# Sanity: README exists
echo ""
echo "Sanity: README.md present"
TOTAL=$((TOTAL + 1))
if [[ -f "$README" ]]; then
  echo "  PASS: README.md exists"; PASS=$((PASS + 1))
else
  echo "  FAIL: README.md absent"; FAIL=$((FAIL + 1))
  echo ""
  echo "=== Results: $PASS/$TOTAL passed, $FAIL failed ==="
  exit 1
fi

# Test 1: section heading present (per AC #1)
echo ""
echo "Test 1: ## Self-modifying execution heading"
assert_grep "section heading" "## Self-modifying execution" "$README"

# Test 2: contains 'self-modifying' phrase (per AC #1, #2)
echo ""
echo "Test 2: 'self-modifying' phrase present"
assert_grep "self-modifying phrase" "self-modifying" "$README"

# Test 3: contains 'previous release' or equivalent (per AC #2)
# Use extended regex to allow either "previous release" or
# "PREVIOUS release" (the AC says "or equivalent").
echo ""
echo "Test 3: previous-release reference"
assert_grep_E "previous release reference" "(previous release|PREVIOUS release)" "$README"

# Test 4: concrete example release (per AC #3)
echo ""
echo "Test 4: concrete v0.6.4 example"
assert_grep "v0.6.4 concrete example" "v0.6.4" "$README"

# Test 5: 'after the bundle merges' phrase (per AC #5, closes the
# missing-measurement v0.6.5 PRD-review finding)
echo ""
echo "Test 5: 'after the bundle merges' phrase"
assert_grep "after-the-bundle-merges phrase" "after the bundle merges" "$README"

# Test 6: cross-link to PIPELINE_REPORT (per AC #4)
echo ""
echo "Test 6: cross-link to PIPELINE_REPORT_v5 or equivalent"
assert_grep_E "PIPELINE_REPORT cross-link" "PIPELINE_REPORT(_v[0-9]+)?" "$README"

echo ""
echo "=== Results: $PASS/$TOTAL passed, $FAIL failed ==="
exit $((FAIL > 0 ? 1 : 0))
