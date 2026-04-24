#!/usr/bin/env bash
# Phase 13 / P2.2 — verify the over-building hunter additions to
# agents/spec-reviewer.md. The actual over-building detection runs inside
# the LLM-driven spec-reviewer agent at review time; this test locks the
# prompt-side surface that specifies the behavior so future edits don't
# silently regress it.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$SCRIPT_DIR/.."
AGENT="$REPO_ROOT/agents/spec-reviewer.md"
PASS=0
FAIL=0
TOTAL=0

check() {
  local name="$1" needle="$2" file="$3"
  TOTAL=$((TOTAL + 1))
  if grep -qF -- "$needle" "$file"; then
    echo "  PASS: $name"; PASS=$((PASS + 1))
  else
    echo "  FAIL: $name — needle [$needle] not in $file"
    FAIL=$((FAIL + 1))
  fi
}

check_regex() {
  local name="$1" pattern="$2" file="$3"
  TOTAL=$((TOTAL + 1))
  if grep -qE -- "$pattern" "$file"; then
    echo "  PASS: $name"; PASS=$((PASS + 1))
  else
    echo "  FAIL: $name — regex [$pattern] not in $file"
    FAIL=$((FAIL + 1))
  fi
}

echo "=== Phase 13 over-building hunter prompt tests ==="

# Test 1: Step 5 upgraded to an Over-building Audit
echo ""
echo "Test 1: Step 5 header upgrade"
check "Step 5 renamed to Over-building Audit" "Over-building Audit" "$AGENT"
check "Mentions Superpowers v4 borrow" "Superpowers spec-reviewer v4" "$AGENT"
check "Acknowledges the missing-vs-extra asymmetry" "better at catching" "$AGENT"

# Test 2: The four required sub-checks are present
echo ""
echo "Test 2: Sub-checks 5a–5d all present"
check "5a Scope creep retained" "5a — Scope creep" "$AGENT"
check "5b Non-goals cross-check" "5b — PRD non-goals cross-check" "$AGENT"
check "5c Exported-symbol justification" "5c — Exported-symbol justification" "$AGENT"
check "5d Single-caller abstraction" "5d — Single-caller abstraction detection" "$AGENT"

# Test 3: Output schema extended with new arrays
echo ""
echo "Test 3: JSON output schema extensions"
check "nonGoalsViolated array in schema" "\"nonGoalsViolated\":" "$AGENT"
check "overBuilding array in schema" "\"overBuilding\":" "$AGENT"
check "sample kind unjustified-export" "unjustified-export" "$AGENT"
check "sample kind single-caller-abstraction" "single-caller-abstraction" "$AGENT"

# Test 4: PASS criteria extended to cover the new gates
echo ""
echo "Test 4: Decision-rule updates"
check "PASS requires nonGoalsViolated empty" "\`nonGoalsViolated\` array is empty" "$AGENT"
check "PASS blocks HIGH overBuilding" "No HIGH over-building findings without user acknowledgement" "$AGENT"

# Test 5: Cross-references to ql-intent-check Rule 4 + ql-deep-review
echo ""
echo "Test 5: Cross-skill references are correct"
check_regex "references ql-intent-check Rule 4" "ql-intent-check/SKILL.md.*Rule 4" "$AGENT"
check "references ql-deep-review complementary scope" "ql-deep-review" "$AGENT"
check "test-only exports exempted" "Test-only exports" "$AGENT"

# Test 6: Contract-boundary exemption for single-caller rule (no false positives on contracts)
echo ""
echo "Test 6: Exception paths documented"
check "consumedBy exemption" "consumedBy" "$AGENT"
check "PRD-mandated refinement exemption" "narrow a PRD-mandated interface" "$AGENT"
check "info finding when PRD has no §5" "PRD missing §5 Non-goals" "$AGENT"

# Test 7: Severity levels clearly assigned
echo ""
echo "Test 7: Severity levels on each detector"
check "non-goal violation is CRITICAL" "**CRITICAL**" "$AGENT"
check "unjustified-export is HIGH" "**HIGH**" "$AGENT"
check "single-caller is MEDIUM" "**MEDIUM**" "$AGENT"

echo ""
echo "=== Results: $PASS/$TOTAL passed, $FAIL failed ==="
exit $((FAIL > 0 ? 1 : 0))
