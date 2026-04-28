#!/usr/bin/env bash
# N13 / US-002 (v0.6.9) — references/orchestrator-takeover.md presence + structure tests.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$SCRIPT_DIR/.."
DOC="$REPO_ROOT/references/orchestrator-takeover.md"
PASS=0
FAIL=0
TOTAL=0

echo "=== US-002 N13 orchestrator-takeover doc tests ==="

# Test 1: file exists
echo ""
echo "Test 1: references/orchestrator-takeover.md exists"
TOTAL=$((TOTAL + 1))
if [[ -f "$DOC" ]]; then
  echo "  PASS: file exists"; PASS=$((PASS + 1))
else
  echo "  FAIL: file missing"; FAIL=$((FAIL + 1))
fi

# Test 2: 4 expected sections present
echo ""
echo "Test 2: 4 sections present (When / What / How / Recovery)"
TOTAL=$((TOTAL + 1))
if grep -qE '^## When' "$DOC" \
   && grep -qE '^## What' "$DOC" \
   && grep -qE '^## How' "$DOC" \
   && grep -qE '^## Recovery' "$DOC"; then
  echo "  PASS: all 4 sections present"; PASS=$((PASS + 1))
else
  echo "  FAIL: missing one of When/What/How/Recovery"
  printf '    headers found: %s\n' "$(grep -oE '^## [A-Za-z]+' "$DOC" | tr '\n' ',' || true)"
  FAIL=$((FAIL + 1))
fi

# Test 3: worked example cites v0.6.7 or v0.6.8
echo ""
echo "Test 3: worked example cites v0.6.7 or v0.6.8 takeover narrative"
TOTAL=$((TOTAL + 1))
if grep -qE 'v0\.6\.(7|8)' "$DOC"; then
  echo "  PASS: worked example references v0.6.7 or v0.6.8"; PASS=$((PASS + 1))
else
  echo "  FAIL: no worked-example version reference"; FAIL=$((FAIL + 1))
fi

# Test 4: verification-failure-driven amendment rule documented
echo ""
echo "Test 4: verification-failure-driven amendment rule documented"
TOTAL=$((TOTAL + 1))
if grep -qE 'verification.failure.driven amendment' "$DOC"; then
  echo "  PASS: amendment rule documented"; PASS=$((PASS + 1))
else
  echo "  FAIL: amendment rule phrase missing"; FAIL=$((FAIL + 1))
fi

# Test 5: CLAUDE.md cross-link present
echo ""
echo "Test 5: CLAUDE.md cross-links to references/orchestrator-takeover.md"
TOTAL=$((TOTAL + 1))
if grep -q 'orchestrator-takeover' "$REPO_ROOT/CLAUDE.md"; then
  echo "  PASS: CLAUDE.md cross-link present"; PASS=$((PASS + 1))
else
  echo "  FAIL: no cross-link from CLAUDE.md"; FAIL=$((FAIL + 1))
fi

echo ""
echo "=== Results: $PASS/$TOTAL passed, $FAIL failed ==="
[[ $FAIL -eq 0 ]] || exit 1
