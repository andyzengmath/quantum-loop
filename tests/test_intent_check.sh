#!/usr/bin/env bash
# Phase 7 / P1.4 — tests for the ql-intent-check wiring + schema.
#
# Scope: this test covers the *plumbing* added in Phase 7. The LLM-driven
# drift-detection rules live inside the skill prompt (invoked via Agent tool)
# and are not deterministically unit-testable from bash. What we DO verify
# here:
#   1. quantum.json.example validates as JSON and contains the new fields.
#   2. The ql-intent-check SKILL.md exists and references the expected rules.
#   3. The ql-brainstorm SKILL.md Phase 4 references userIntent snapshot.
#   4. The ql-verify SKILL.md references intentDrift as a blocking gate.
#   5. A synthetic quantum.json containing a CRITICAL intentDrift verdict is
#      recognizable by a simple jq-based gate (the same gate orchestrator
#      would use to refuse STORY_PASSED).

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$SCRIPT_DIR/.."
PASS=0
FAIL=0
TOTAL=0

assert() {
  local name="$1" expected="$2" actual="$3"
  TOTAL=$((TOTAL + 1))
  if [[ "$expected" == "$actual" ]]; then
    echo "  PASS: $name"; PASS=$((PASS + 1))
  else
    echo "  FAIL: $name"
    echo "    expected: [$expected]"
    echo "    actual:   [$actual]"
    FAIL=$((FAIL + 1))
  fi
}

assert_contains_file() {
  local name="$1" needle="$2" file="$3"
  TOTAL=$((TOTAL + 1))
  if grep -qF -- "$needle" "$file"; then
    echo "  PASS: $name"; PASS=$((PASS + 1))
  else
    echo "  FAIL: $name"
    echo "    expected [$file] to contain: [$needle]"
    FAIL=$((FAIL + 1))
  fi
}

echo "=== Phase 7 ql-intent-check wiring tests ==="

# Test 1: quantum.json.example still parses as JSON after schema extension
echo ""
echo "Test 1: quantum.json.example JSON validity"
if jq empty "$REPO_ROOT/quantum.json.example" 2>/dev/null; then
  echo "  PASS: quantum.json.example is valid JSON"
  PASS=$((PASS + 1))
else
  echo "  FAIL: quantum.json.example is NOT valid JSON after schema change"
  FAIL=$((FAIL + 1))
fi
TOTAL=$((TOTAL + 1))

# Test 2: userIntent field present with required sub-keys
echo ""
echo "Test 2: userIntent schema shape"
has_text=$(jq -r '.userIntent.text // "MISSING"' "$REPO_ROOT/quantum.json.example")
has_ts=$(jq -r '.userIntent.timestamp // "MISSING"' "$REPO_ROOT/quantum.json.example")
assert "userIntent.text populated" "false" "$([[ "$has_text" == "MISSING" || -z "$has_text" ]] && echo true || echo false)"
assert "userIntent.timestamp populated" "false" "$([[ "$has_ts" == "MISSING" || -z "$has_ts" ]] && echo true || echo false)"

# Test 3: userClarifications + intentDrift fields present (and of correct type)
echo ""
echo "Test 3: userClarifications + intentDrift containers"
clar_type=$(jq -r '.userClarifications | type' "$REPO_ROOT/quantum.json.example")
drift_type=$(jq -r '.intentDrift | type' "$REPO_ROOT/quantum.json.example")
assert "userClarifications is array" "array" "$clar_type"
assert "intentDrift is object" "object" "$drift_type"

# Test 4: ql-intent-check skill exists and contains the rule table
echo ""
echo "Test 4: ql-intent-check skill content"
SKILL="$REPO_ROOT/skills/ql-intent-check/SKILL.md"
assert "skill file exists" "yes" "$([[ -f "$SKILL" ]] && echo yes || echo no)"
assert_contains_file "references Rule 4 — Non-goals violated" "Non-goals violated" "$SKILL"
assert_contains_file "references CRITICAL_DRIFT_BLOCKS_MERGE verdict" "CRITICAL_DRIFT_BLOCKS_MERGE" "$SKILL"
assert_contains_file "lists Rule 7 scope creep" "Rule 7" "$SKILL"

# Test 5: ql-brainstorm references the userIntent snapshot step
echo ""
echo "Test 5: ql-brainstorm Phase 4b references userIntent"
BS="$REPO_ROOT/skills/ql-brainstorm/SKILL.md"
assert_contains_file "mentions Phase 4b snapshot" "Snapshot user intent" "$BS"
assert_contains_file "references immutable snapshot" "immutable" "$BS"
assert_contains_file "points at json-atomic helper" "json-atomic.sh" "$BS"

# Test 6: ql-verify references intentDrift as a gate
echo ""
echo "Test 6: ql-verify treats CRITICAL_DRIFT_BLOCKS_MERGE as blocking"
VER="$REPO_ROOT/skills/ql-verify/SKILL.md"
assert_contains_file "mentions intent-drift audit step" "Intent-drift audit" "$VER"
assert_contains_file "mentions CRITICAL verdict blocks PASSED" "CRITICAL_DRIFT_BLOCKS_MERGE" "$VER"
assert_contains_file "references claim-check signal too" "SIGNAL_CLAIM_FINDINGS" "$VER"

# Test 7: Machine-checkable gate — jq can read verdict from a fixture
echo ""
echo "Test 7: jq gate reads intentDrift verdict correctly"
TMP=$(mktemp)
cat > "$TMP" << 'EOF'
{
  "intentDrift": {
    "feature-X": {"verdict": "CRITICAL_DRIFT_BLOCKS_MERGE", "summary": {"critical": 1}}
  }
}
EOF
verdict=$(jq -r '.intentDrift["feature-X"].verdict' "$TMP")
assert "critical verdict readable" "CRITICAL_DRIFT_BLOCKS_MERGE" "$verdict"
# Gate behavior: exit 1 if critical
if [[ "$verdict" == "CRITICAL_DRIFT_BLOCKS_MERGE" ]]; then
  gate_exit=1
else
  gate_exit=0
fi
assert "gate blocks on critical" "1" "$gate_exit"

# Negative case: NO_DRIFT verdict should allow through
cat > "$TMP" << 'EOF'
{"intentDrift": {"feature-Y": {"verdict": "NO_DRIFT", "summary": {"critical": 0}}}}
EOF
verdict=$(jq -r '.intentDrift["feature-Y"].verdict' "$TMP")
[[ "$verdict" == "CRITICAL_DRIFT_BLOCKS_MERGE" ]] && gate_exit=1 || gate_exit=0
assert "gate passes on NO_DRIFT" "0" "$gate_exit"
rm -f "$TMP"

# Test 8: Missing intentDrift handled gracefully (degrade, not crash)
echo ""
echo "Test 8: Missing intentDrift degrades gracefully"
TMP=$(mktemp)
echo '{"stories": []}' > "$TMP"
verdict=$(jq -r '.intentDrift["feature-Z"].verdict // "NOT_AUDITED"' "$TMP")
assert "missing verdict returns sentinel" "NOT_AUDITED" "$verdict"
rm -f "$TMP"

echo ""
echo "=== Results: $PASS/$TOTAL passed, $FAIL failed ==="
exit $((FAIL > 0 ? 1 : 0))
