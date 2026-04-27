#!/usr/bin/env bash
# v0.7.0 / US-004 (G16) -- references/finding-severity.md rubric +
# spec-reviewer cross-link tests.
#
# Doc-conformance: verifies the rubric doc structure (3 mode sections,
# 4 severity rows each) and the cross-link line in agents/spec-reviewer.md.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$SCRIPT_DIR/.."
RUBRIC="$REPO_ROOT/references/finding-severity.md"
SPEC_REV="$REPO_ROOT/agents/spec-reviewer.md"
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

assert_section_has_severity_rows() {
  local mode="$1"   # design-review | prd-review | plan-review
  # Extract the section bounded by ## $mode and the next ## heading,
  # then count rows that begin with | and contain critical/high/medium/low.
  TOTAL=$((TOTAL + 1))
  local section
  section=$(awk -v hdr="## $mode" '
    $0 == hdr { in_sec = 1; next }
    in_sec && /^## / { exit }
    in_sec { print }
  ' "$RUBRIC")
  local crit high med low
  crit=$(printf '%s\n' "$section" | grep -cE '^\| *critical *\|' || true)
  high=$(printf '%s\n' "$section" | grep -cE '^\| *high *\|'     || true)
  med=$(printf '%s\n' "$section"  | grep -cE '^\| *medium *\|'   || true)
  low=$(printf '%s\n' "$section"  | grep -cE '^\| *low *\|'      || true)
  if [[ "$crit" -ge 1 && "$high" -ge 1 && "$med" -ge 1 && "$low" -ge 1 ]]; then
    echo "  PASS: $mode section has all 4 severity rows (crit/high/med/low present)"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: $mode section missing severity rows (got crit=$crit high=$high med=$med low=$low)"
    FAIL=$((FAIL + 1))
  fi
}

assert_section_examples_nonempty() {
  local mode="$1"
  TOTAL=$((TOTAL + 1))
  local section
  section=$(awk -v hdr="## $mode" '
    $0 == hdr { in_sec = 1; next }
    in_sec && /^## / { exit }
    in_sec { print }
  ' "$RUBRIC")
  # For every severity row, the line must contain >= 3 pipe-separated fields
  # AND the third (Example) field must be non-empty (not just whitespace).
  local rows ok=0
  rows=$(printf '%s\n' "$section" | grep -cE '^\| *(critical|high|medium|low) *\|' || true)
  if [[ "$rows" -lt 4 ]]; then
    echo "  FAIL: $mode section has <4 severity rows for example-check"
    FAIL=$((FAIL + 1))
    return
  fi
  while IFS= read -r row; do
    # Strip CRLF defensively per CLAUDE.md Platform Notes.
    row="${row%$'\r'}"
    # Split on pipes; use awk for reliable field separation.
    local example
    example=$(printf '%s' "$row" | awk -F'|' '{print $4}' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
    if [[ -n "$example" && "$example" != "" ]]; then
      ok=$((ok + 1))
    fi
  done < <(printf '%s\n' "$section" | grep -E '^\| *(critical|high|medium|low) *\|')
  if [[ "$ok" -ge 4 ]]; then
    echo "  PASS: $mode section: all 4 severity rows have non-empty Example column"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: $mode section: only $ok/4 severity rows have non-empty Example column"
    FAIL=$((FAIL + 1))
  fi
}

echo "=== v0.7.0 US-004 finding-severity rubric tests ==="

# Test 1: rubric doc exists
echo ""
echo "Test 1: references/finding-severity.md exists"
TOTAL=$((TOTAL + 1))
if [[ -f "$RUBRIC" ]]; then
  echo "  PASS: $RUBRIC exists"
  PASS=$((PASS + 1))
else
  echo "  FAIL: $RUBRIC missing"
  FAIL=$((FAIL + 1))
  echo ""
  echo "=== Results: $PASS/$TOTAL passed, $FAIL failed ==="
  exit 1
fi

# Test 2: 3 mode sections present (## design-review, ## prd-review, ## plan-review)
echo ""
echo "Test 2: 3 mode section headers"
assert_grep "## design-review heading" "## design-review" "$RUBRIC"
assert_grep "## prd-review heading"    "## prd-review"    "$RUBRIC"
assert_grep "## plan-review heading"   "## plan-review"   "$RUBRIC"

# Test 3: each mode section has 4 severity rows (crit/high/med/low)
echo ""
echo "Test 3: each mode section has 4 severity rows"
assert_section_has_severity_rows "design-review"
assert_section_has_severity_rows "prd-review"
assert_section_has_severity_rows "plan-review"

# Test 4: each row's Example column is non-empty
echo ""
echo "Test 4: severity row Examples are non-empty"
assert_section_examples_nonempty "design-review"
assert_section_examples_nonempty "prd-review"
assert_section_examples_nonempty "plan-review"

# Test 5: spec-reviewer.md has cross-link line for each mode
echo ""
echo "Test 5: spec-reviewer.md cross-link presence"
assert_grep "design-review cross-link" "references/finding-severity.md#design-review" "$SPEC_REV"
assert_grep "prd-review cross-link"    "references/finding-severity.md#prd-review"    "$SPEC_REV"
assert_grep "plan-review cross-link"   "references/finding-severity.md#plan-review"   "$SPEC_REV"

# Test 6: cross-links use kebab-case anchors (matching mode section heading)
# (This is implicitly covered by Test 5 substring matches; we add an
# explicit pattern check to guard against typos like #DesignReview.)
echo ""
echo "Test 6: cross-link anchors are kebab-case"
TOTAL=$((TOTAL + 1))
if grep -qE '#design-review' "$SPEC_REV" && \
   grep -qE '#prd-review'    "$SPEC_REV" && \
   grep -qE '#plan-review'   "$SPEC_REV"; then
  echo "  PASS: all 3 anchors are kebab-case (design-review / prd-review / plan-review)"
  PASS=$((PASS + 1))
else
  echo "  FAIL: at least one cross-link uses non-kebab-case anchor"
  FAIL=$((FAIL + 1))
fi

echo ""
echo "=== Results: $PASS/$TOTAL passed, $FAIL failed ==="
exit $((FAIL > 0 ? 1 : 0))
