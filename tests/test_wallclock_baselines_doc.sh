#!/usr/bin/env bash
# N9 / US-004 (v0.6.8) — references/test-wallclock-baselines.md presence + structure tests.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$SCRIPT_DIR/.."
DOC="$REPO_ROOT/references/test-wallclock-baselines.md"
PASS=0
FAIL=0
TOTAL=0

echo "=== US-004 N9 wallclock-baselines doc tests ==="

# Test 1: file exists
echo ""
echo "Test 1: references/test-wallclock-baselines.md exists"
TOTAL=$((TOTAL + 1))
if [[ -f "$DOC" ]]; then
  echo "  PASS: file exists"; PASS=$((PASS + 1))
else
  echo "  FAIL: file missing"; FAIL=$((FAIL + 1))
fi

# Test 2: >=4 baseline rows (markdown table rows starting with `| \`bash`)
echo ""
echo "Test 2: >=4 baseline rows present in markdown table"
TOTAL=$((TOTAL + 1))
n_rows=$(grep -cE '^\| `bash' "$DOC" 2>/dev/null || true)
if (( n_rows >= 4 )); then
  echo "  PASS: $n_rows baseline rows found"
  PASS=$((PASS + 1))
else
  echo "  FAIL: only $n_rows baseline rows (expected >=4)"
  FAIL=$((FAIL + 1))
fi

# Test 3: Git Bash + Linux/CI columns mentioned
echo ""
echo "Test 3: table headers reference Git Bash and Linux/CI"
TOTAL=$((TOTAL + 1))
if grep -q 'Git Bash' "$DOC" && grep -q 'Linux/CI' "$DOC"; then
  echo "  PASS: both platform columns present"; PASS=$((PASS + 1))
else
  echo "  FAIL: missing Git Bash or Linux/CI column"; FAIL=$((FAIL + 1))
fi

# Test 4: CLAUDE.md cross-link present
echo ""
echo "Test 4: CLAUDE.md cross-links to references/test-wallclock-baselines.md"
TOTAL=$((TOTAL + 1))
if grep -q 'test-wallclock-baselines' "$REPO_ROOT/CLAUDE.md"; then
  echo "  PASS: CLAUDE.md cross-link present"; PASS=$((PASS + 1))
else
  echo "  FAIL: no cross-link from CLAUDE.md"; FAIL=$((FAIL + 1))
fi

echo ""
echo "=== Results: $PASS/$TOTAL passed, $FAIL failed ==="
[[ $FAIL -eq 0 ]] || exit 1
