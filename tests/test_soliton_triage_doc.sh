#!/usr/bin/env bash
# N7 / US-002 (v0.6.8) — references/soliton-finding-triage.md presence + structure tests.
#
# Asserts the validate-before-design workflow doc exists, has the 3 expected
# sections (Workflow / Repro / Examples), includes the v0.6.7 G36 worked
# example, and is cross-linked from CLAUDE.md.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$SCRIPT_DIR/.."
DOC="$REPO_ROOT/references/soliton-finding-triage.md"
PASS=0
FAIL=0
TOTAL=0

echo "=== US-002 N7 soliton-finding-triage doc tests ==="

# Test 1: file exists
echo ""
echo "Test 1: references/soliton-finding-triage.md exists"
TOTAL=$((TOTAL + 1))
if [[ -f "$DOC" ]]; then
  echo "  PASS: file exists"; PASS=$((PASS + 1))
else
  echo "  FAIL: file missing"; FAIL=$((FAIL + 1))
fi

# Test 2: 3 expected sections present (Workflow / Repro / Examples)
echo ""
echo "Test 2: 3 sections present (Workflow / Repro / Examples)"
TOTAL=$((TOTAL + 1))
if grep -qE '^## Workflow' "$DOC" \
   && grep -qE '^## Repro' "$DOC" \
   && grep -qE '^## Examples' "$DOC"; then
  echo "  PASS: all 3 sections present"; PASS=$((PASS + 1))
else
  echo "  FAIL: missing one of Workflow / Repro / Examples"
  printf '    headers found: %s\n' "$(grep -oE '^## [A-Za-z]+' "$DOC" | tr '\n' ',' || true)"
  FAIL=$((FAIL + 1))
fi

# Test 3: v0.6.7 G36 worked example present
echo ""
echo "Test 3: v0.6.7 G36 case included as worked example"
TOTAL=$((TOTAL + 1))
if grep -q 'v0.6.7 G36' "$DOC"; then
  echo "  PASS: G36 worked example referenced"; PASS=$((PASS + 1))
else
  echo "  FAIL: v0.6.7 G36 example missing"; FAIL=$((FAIL + 1))
fi

# Test 4: HALLUCINATION verdict marker present (per the worked example)
echo ""
echo "Test 4: HALLUCINATION verdict marker present (validates the verdict-outcome rubric is documented)"
TOTAL=$((TOTAL + 1))
if grep -q 'HALLUCINATION' "$DOC"; then
  echo "  PASS: HALLUCINATION verdict documented"; PASS=$((PASS + 1))
else
  echo "  FAIL: HALLUCINATION verdict missing — rubric incomplete"; FAIL=$((FAIL + 1))
fi

# Test 5: CLAUDE.md cross-link present
echo ""
echo "Test 5: CLAUDE.md cross-links to references/soliton-finding-triage.md"
TOTAL=$((TOTAL + 1))
if grep -q 'soliton-finding-triage' "$REPO_ROOT/CLAUDE.md"; then
  echo "  PASS: CLAUDE.md cross-link present"; PASS=$((PASS + 1))
else
  echo "  FAIL: no cross-link from CLAUDE.md"; FAIL=$((FAIL + 1))
fi

echo ""
echo "=== Results: $PASS/$TOTAL passed, $FAIL failed ==="
[[ $FAIL -eq 0 ]] || exit 1
