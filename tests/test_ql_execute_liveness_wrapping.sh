#!/usr/bin/env bash
# N14 / US-002 (v0.7.0) — /ql-execute SKILL liveness wrapping presence tests.
#
# PRESENCE-ONLY assertions (matches v0.6.8 N6 pattern). Runtime SKILL
# execution is out of scope; this verifies the prose has all the documented
# elements an LLM-consumer + parent agent would need.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$SCRIPT_DIR/.."
SKILL="$REPO_ROOT/skills/ql-execute/SKILL.md"
PASS=0
FAIL=0
TOTAL=0

echo "=== US-002 N14 /ql-execute liveness wrapping tests ==="

# Test 1: '## Orchestrator liveness gate' subsection header present
echo ""
echo "Test 1: '## Orchestrator liveness gate' subsection header present"
TOTAL=$((TOTAL + 1))
if grep -q '^## Orchestrator liveness gate' "$SKILL"; then
  echo "  PASS: subsection header present"; PASS=$((PASS + 1))
else
  echo "  FAIL: subsection header missing"; FAIL=$((FAIL + 1))
fi

# Test 2: QL_LIVENESS_ENABLE env var documented
echo ""
echo "Test 2: QL_LIVENESS_ENABLE env var documented"
TOTAL=$((TOTAL + 1))
if grep -q 'QL_LIVENESS_ENABLE' "$SKILL"; then
  echo "  PASS: QL_LIVENESS_ENABLE env var documented"; PASS=$((PASS + 1))
else
  echo "  FAIL: env var not documented"; FAIL=$((FAIL + 1))
fi

# Test 3: default true documented
echo ""
echo "Test 3: default true documented"
TOTAL=$((TOTAL + 1))
if grep -qE 'unset.+true|default.+true|:-true' "$SKILL"; then
  echo "  PASS: default-true semantics documented"; PASS=$((PASS + 1))
else
  echo "  FAIL: default-true not documented"; FAIL=$((FAIL + 1))
fi

# Test 4: cross-link to references/orchestrator-takeover.md
echo ""
echo "Test 4: cross-link to references/orchestrator-takeover.md"
TOTAL=$((TOTAL + 1))
if grep -q 'references/orchestrator-takeover.md' "$SKILL"; then
  echo "  PASS: cross-link to takeover SOP present"; PASS=$((PASS + 1))
else
  echo "  FAIL: cross-link missing"; FAIL=$((FAIL + 1))
fi

# Test 5: handoff message structure (orchestrator-stale signal phrase)
echo ""
echo "Test 5: handoff message structure (orchestrator-stale signal)"
TOTAL=$((TOTAL + 1))
if grep -q 'orchestrator-stale' "$SKILL"; then
  echo "  PASS: orchestrator-stale signal phrase present"; PASS=$((PASS + 1))
else
  echo "  FAIL: handoff message structure missing"; FAIL=$((FAIL + 1))
fi

# Test 6: wrap_orchestrator_dispatch function reference present
# v0.7.1 N20: SKILL no longer inlines poll_orchestrator_commits; it calls
# wrap_orchestrator_dispatch (which encapsulates the env-var check + poll
# + handoff). Updated assertion to grep for the function reference.
echo ""
echo "Test 6: wrap_orchestrator_dispatch function reference in wrapping example"
TOTAL=$((TOTAL + 1))
if grep -q 'wrap_orchestrator_dispatch' "$SKILL"; then
  echo "  PASS: wrap_orchestrator_dispatch reference present"; PASS=$((PASS + 1))
else
  echo "  FAIL: wrap_orchestrator_dispatch not referenced in wrapping example"; FAIL=$((FAIL + 1))
fi

echo ""
echo "=== Results: $PASS/$TOTAL passed, $FAIL failed ==="
[[ $FAIL -eq 0 ]] || exit 1
