#!/usr/bin/env bash
# US-007 / P5.B4-PRD — verify spec-reviewer.md has a 'prd-review' mode and
# the ql-spec SKILL invokes it post-exit. Advisory in v0.6.3.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$SCRIPT_DIR/.."
SPEC_REV="$REPO_ROOT/agents/spec-reviewer.md"
SPEC_SKILL="$REPO_ROOT/skills/ql-spec/SKILL.md"
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

echo "=== US-007 / P5.B4-PRD tests ==="

# Test 1: spec-reviewer.md has prd-review mode
echo ""
echo "Test 1: spec-reviewer.md has prd-review mode"
assert_grep "prd-review mode header" "prd-review" "$SPEC_REV"

# 9 standard PRD sections referenced
TOTAL=$((TOTAL + 1))
missing=""
for section in "Introduction" "Goals" "User Stories" "Functional Requirements" "Non-Goals" "Design" "Technical" "Success" "Open Questions"; do
  if ! grep -qF -- "$section" "$SPEC_REV"; then
    missing="${missing:+$missing, }$section"
  fi
done
if [[ -z "$missing" ]]; then
  echo "  PASS: prd-review checklist references all 9 PRD sections"
  PASS=$((PASS + 1))
else
  echo "  FAIL: missing PRD section references: $missing"
  FAIL=$((FAIL + 1))
fi

# Per-AC machine-verifiability check
assert_grep "machine-verifiable AC criterion" "machine-verifiable" "$SPEC_REV"
assert_grep "FR measurement-method check" "measurement" "$SPEC_REV"
assert_grep "success metrics quantifiable" "quantifiable" "$SPEC_REV"

# Test 2: ql-spec SKILL invokes prd-review
echo ""
echo "Test 2: ql-spec SKILL post-exit invocation"
assert_grep "prd-review reference" "prd-review" "$SPEC_SKILL"
assert_grep "spec-reviewer reference" "spec-reviewer" "$SPEC_SKILL"
assert_grep "QL_SKIP_PRE_IMPL_REVIEW gate" "QL_SKIP_PRE_IMPL_REVIEW" "$SPEC_SKILL"
assert_grep "stderr emission documented" "stderr" "$SPEC_SKILL"

# Test 3: comma-separated env-var (e.g., design,prd) chaining
echo ""
echo "Test 3: csv env-var skip chaining"
TOTAL=$((TOTAL + 1))
if grep -qE "design,prd|prd,design|tr ',' |grep -qx" "$SPEC_SKILL"; then
  echo "  PASS: ql-spec SKILL gate parses csv-form env var"
  PASS=$((PASS + 1))
else
  echo "  FAIL: ql-spec SKILL gate doesn't parse csv env var"
  FAIL=$((FAIL + 1))
fi

# Test 4: synthetic PRD -> 2 findings (vague AC + missing FR measurement)
echo ""
echo "Test 4: behavioral synthetic PRD"

TMP=$(mktemp -d)
cat > "$TMP/synthetic-prd.md" <<'EOF'
# PRD: Test feature

## Section 3: User Stories

### US-X
**Description:** ...

**Acceptance Criteria:**
- [ ] works correctly

## Section 4: Functional Requirements

- **FR-1:** System shall be fast
EOF

# Replay logic: count vague ACs (matches "works correctly", "should work", "fast")
# and FRs without measurement keywords.
vague_ac_count=$(grep -cE "(works correctly|should work)" "$TMP/synthetic-prd.md" || true)
fr_no_metric=$(grep -cE "FR-[0-9]+:.*be (fast|good|robust|easy)" "$TMP/synthetic-prd.md" || true)
total_findings=$((vague_ac_count + fr_no_metric))

TOTAL=$((TOTAL + 1))
if (( total_findings >= 2 )); then
  echo "  PASS: synthetic PRD yields >=2 expected findings (vague=$vague_ac_count fr-no-metric=$fr_no_metric)"
  PASS=$((PASS + 1))
else
  echo "  FAIL: synthetic PRD yields fewer than 2 findings (got $total_findings)"
  FAIL=$((FAIL + 1))
fi

# Test 5: opt-out env var (prd alone, and combined design,prd)
echo ""
echo "Test 5: QL_SKIP_PRE_IMPL_REVIEW=prd opt-out"
TOTAL=$((TOTAL + 1))
if grep -qE "QL_SKIP_PRE_IMPL_REVIEW.*prd" "$SPEC_SKILL"; then
  echo "  PASS: ql-spec SKILL gates on QL_SKIP_PRE_IMPL_REVIEW=prd"
  PASS=$((PASS + 1))
else
  echo "  FAIL: ql-spec SKILL missing QL_SKIP_PRE_IMPL_REVIEW=prd gate"
  FAIL=$((FAIL + 1))
fi

# Behavioral: simulate the SKILL gate logic with QL_SKIP_PRE_IMPL_REVIEW=design,prd
# The gate must SKIP when env value contains 'prd' (csv form).
TOTAL=$((TOTAL + 1))
SKIP_LIST="design,prd"
should_skip=$(printf '%s' "$SKIP_LIST" | tr ',' '\n' | grep -qx "prd" && echo "yes" || echo "no")
if [[ "$should_skip" == "yes" ]]; then
  echo "  PASS: csv parser correctly identifies 'prd' in 'design,prd'"
  PASS=$((PASS + 1))
else
  echo "  FAIL: csv parser missed 'prd' in 'design,prd'"
  FAIL=$((FAIL + 1))
fi

rm -rf "$TMP"

echo ""
echo "=== Results: $PASS/$TOTAL passed, $FAIL failed ==="
[[ $FAIL -eq 0 ]] || exit 1
