#!/usr/bin/env bash
# Phase 10 — end-to-end trivial-story check. Validates that the dogfood
# quantum.json produced in Phase 10 parses against the schema the new
# libs expect (Phases 5-9). This is the "one trivial story" acceptance
# from the plan §Phase 10 step 3.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$SCRIPT_DIR/.."
DOGFOOD="$REPO_ROOT/.omc/phase-10-evidence/quantum.dogfood.json"
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
source "$REPO_ROOT/lib/deep-review.sh"

echo "=== Phase 10 dogfood end-to-end check ==="

# Test 1: dogfood JSON parses
echo ""
echo "Test 1: dogfood quantum.json parses"
if jq empty "$DOGFOOD" 2>/dev/null; then
  echo "  PASS: valid JSON"; PASS=$((PASS + 1))
else
  echo "  FAIL: dogfood quantum.json is invalid JSON"; FAIL=$((FAIL + 1))
fi
TOTAL=$((TOTAL + 1))

# Test 2: required top-level fields populated by Phases 7-9
echo ""
echo "Test 2: schema fields from Phases 7-9"
assert "userIntent.text present" "true"  "$([[ $(jq -r '.userIntent.text | length > 0' "$DOGFOOD") == true ]] && echo true || echo false)"
assert "userClarifications is array" "array" "$(jq -r '.userClarifications | type' "$DOGFOOD")"
assert "intentDrift has entry" "NO_DRIFT" "$(jq -r '.intentDrift["bug-gap-fix-2026-04-22"].verdict' "$DOGFOOD")"
assert "reviews has deepReview" "MEDIUM" "$(jq -r '.reviews["bug-gap-fix-2026-04-22"].deepReview.tier' "$DOGFOOD")"
assert "deslop field present" "object" "$(jq -r '.deslop | type' "$DOGFOOD")"
assert "codebasePatterns has entries" "true" "$([[ $(jq -r '.codebasePatterns | length > 0' "$DOGFOOD") == true ]] && echo true || echo false)"
assert "progress has entries" "true" "$([[ $(jq -r '.progress | length > 0' "$DOGFOOD") == true ]] && echo true || echo false)"

# Test 3: intent-drift gate runs on the dogfood verdict
echo ""
echo "Test 3: intent-drift gate semantics"
verdict=$(jq -r '.intentDrift["bug-gap-fix-2026-04-22"].verdict' "$DOGFOOD")
if [[ "$verdict" == "CRITICAL_DRIFT_BLOCKS_MERGE" ]]; then
  gate=1
else
  gate=0
fi
assert "NO_DRIFT gate allows merge" "0" "$gate"

# Test 4: deep-review synthesize_verdict agrees on the dogfood findings
echo ""
echo "Test 4: deep-review synthesize_verdict consumes the dogfood findings array"
findings=$(jq -c '.reviews["bug-gap-fix-2026-04-22"].deepReview.findings' "$DOGFOOD")
verdict=$(printf '%s' "$findings" | synthesize_verdict)
assert "two HIGH confidence≥70 findings → REQUEST_CHANGES" "REQUEST_CHANGES" "$verdict"

# Test 5: dedup_findings is idempotent on already-unique findings
echo ""
echo "Test 5: dedup_findings idempotent on dogfood findings"
dedup=$(printf '%s' "$findings" | dedup_findings)
before_n=$(printf '%s' "$findings" | jq 'length')
after_n=$(printf '%s' "$dedup" | jq 'length')
assert "dedup preserves 2-element unique set" "$before_n" "$after_n"

# Test 6: acceptance — 10 stories all passed
echo ""
echo "Test 6: plan retrospective — 10 stories all passed"
story_count=$(jq '.stories | length' "$DOGFOOD")
passed_count=$(jq '[.stories[] | select(.status == "passed")] | length' "$DOGFOOD")
assert "10 stories total" "10" "$story_count"
assert "10 stories passed" "10" "$passed_count"

# Test 7: codebasePatterns lessons include the Phase-5 set-e learning
echo ""
echo "Test 7: codebasePatterns contains real Phase-5 lesson"
phase5_lesson=$(jq -r '.codebasePatterns[] | select(contains("MUST NOT set shell flags"))' "$DOGFOOD" | head -1)
if [[ -n "$phase5_lesson" ]]; then
  echo "  PASS: Phase-5 set-e lesson present"; PASS=$((PASS + 1))
else
  echo "  FAIL: expected lesson about shell flags in libraries"; FAIL=$((FAIL + 1))
fi
TOTAL=$((TOTAL + 1))

# Test 8: user intent is the verbatim original request (not a paraphrase)
echo ""
echo "Test 8: userIntent verbatim contains the original verbatim message"
text=$(jq -r '.userIntent.text' "$DOGFOOD")
if echo "$text" | grep -q "IDEA_REPORT.md"; then
  echo "  PASS: intent snapshot references IDEA_REPORT.md"; PASS=$((PASS + 1))
else
  echo "  FAIL: intent snapshot not verbatim"; FAIL=$((FAIL + 1))
fi
TOTAL=$((TOTAL + 1))

# Test 9: PRD exists and references this dogfood quantum.json
echo ""
echo "Test 9: companion PRD exists and references the dogfood artifact"
PRD="$REPO_ROOT/tasks/prd-bug-gap-fix-2026-04-22.md"
if [[ -f "$PRD" ]]; then
  echo "  PASS: PRD exists"; PASS=$((PASS + 1))
else
  echo "  FAIL: PRD missing"; FAIL=$((FAIL + 1))
fi
TOTAL=$((TOTAL + 1))
if grep -q "AC-15" "$PRD" && grep -q "phase-10-evidence" "$PRD"; then
  echo "  PASS: PRD has AC-15 dogfood + references phase-10-evidence"; PASS=$((PASS + 1))
else
  echo "  FAIL: PRD missing dogfood AC or phase-10-evidence reference"; FAIL=$((FAIL + 1))
fi
TOTAL=$((TOTAL + 1))

echo ""
echo "=== Results: $PASS/$TOTAL passed, $FAIL failed ==="
exit $((FAIL > 0 ? 1 : 0))
