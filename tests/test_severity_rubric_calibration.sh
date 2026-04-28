#!/usr/bin/env bash
# G22 / US-001 (v0.7.0) — severity-rubric calibration doc + parse-script tests.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$SCRIPT_DIR/.."
DOC="$REPO_ROOT/references/severity-rubric-calibration-v0.7.0.md"
PARSE="$REPO_ROOT/references/severity-rubric-calibration-parse.sh"
PASS=0
FAIL=0
TOTAL=0

echo "=== US-001 G22 severity-rubric calibration tests ==="

# Test 1: doc exists
echo ""
echo "Test 1: references/severity-rubric-calibration-v0.7.0.md exists"
TOTAL=$((TOTAL + 1))
if [[ -f "$DOC" ]]; then
  echo "  PASS: doc exists"; PASS=$((PASS + 1))
else
  echo "  FAIL: doc missing"; FAIL=$((FAIL + 1))
fi

# Test 2: 6 sections present
echo ""
echo "Test 2: 6 sections present (Methodology / Empirical distribution / Expected distribution / Drift analysis / Rubric language updates / Future work)"
TOTAL=$((TOTAL + 1))
n_sections=0
for h in '^## Methodology' '^## Empirical distribution' '^## Expected distribution' '^## Drift analysis' '^## Rubric language updates' '^## Future work'; do
  if grep -qE "$h" "$DOC"; then
    n_sections=$((n_sections + 1))
  fi
done
if (( n_sections == 6 )); then
  echo "  PASS: all 6 sections present"; PASS=$((PASS + 1))
else
  echo "  FAIL: only $n_sections of 6 sections found"; FAIL=$((FAIL + 1))
fi

# Test 3: parse-script invokable + non-empty output
echo ""
echo "Test 3: parse-script invokable + non-empty output"
TOTAL=$((TOTAL + 1))
out=$(bash "$PARSE" 2>&1 || true)
if [[ -n "$out" ]] && [[ $(printf '%s' "$out" | wc -l) -gt 10 ]]; then
  echo "  PASS: parse-script produces non-empty output ($(printf '%s' "$out" | wc -l) lines)"; PASS=$((PASS + 1))
else
  echo "  FAIL: parse-script output empty or too short"; FAIL=$((FAIL + 1))
fi

# Test 4: parse-script output contains all 4 severity tier names for each of design/prd/plan stages
echo ""
echo "Test 4: parse-script output contains severity tier names for all 3 stages"
TOTAL=$((TOTAL + 1))
all_present=1
for stage in design prd plan; do
  for sev in critical high medium low; do
    if ! printf '%s' "$out" | grep -qE "^## $stage" ; then
      all_present=0
      echo "    missing stage section: $stage"
    fi
  done
done
# Also verify all 4 severity tier names appear in the table headers
for sev in critical high medium low; do
  if ! printf '%s' "$out" | grep -qi "$sev"; then
    all_present=0
    echo "    missing severity name: $sev"
  fi
done
if (( all_present == 1 )); then
  echo "  PASS: all 3 stages + 4 severity names present in parse-script output"; PASS=$((PASS + 1))
else
  echo "  FAIL: stage/severity coverage incomplete"; FAIL=$((FAIL + 1))
fi

# Test 5: companion-script citation in Methodology section
echo ""
echo "Test 5: companion parse-script cited in Methodology section"
TOTAL=$((TOTAL + 1))
if grep -q 'severity-rubric-calibration-parse.sh' "$DOC"; then
  echo "  PASS: parse-script cited"; PASS=$((PASS + 1))
else
  echo "  FAIL: parse-script not cited"; FAIL=$((FAIL + 1))
fi

# Test 6: drift analysis section flags drift OR documents 'no updates required'
echo ""
echo "Test 6: drift analysis section reaches a verdict"
TOTAL=$((TOTAL + 1))
if grep -qE 'No urgent rubric edits|drift|under-classification|over-classification' "$DOC"; then
  echo "  PASS: drift analysis verdict documented"; PASS=$((PASS + 1))
else
  echo "  FAIL: no drift analysis verdict"; FAIL=$((FAIL + 1))
fi

echo ""
echo "=== Results: $PASS/$TOTAL passed, $FAIL failed ==="
[[ $FAIL -eq 0 ]] || exit 1
