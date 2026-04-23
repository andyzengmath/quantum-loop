#!/usr/bin/env bash
# Phase 12 / P1.3 — tests for lib/deep-review.sh risk-adaptive dispatch.
# Covers dispatch_set, risk_score_from_quantum, prepare_review_context,
# aggregate_reviews.

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
    echo "  FAIL: $name (expected [$expected] got [$actual])"
    FAIL=$((FAIL + 1))
  fi
}

# shellcheck disable=SC1091
source "$REPO_ROOT/lib/deep-review.sh"

echo "=== Phase 12 dispatch-set tests ==="

# Test 1: dispatch_set returns the correct reviewer count per tier
echo ""
echo "Test 1: dispatch_set cardinality per tier"
low=$(dispatch_set LOW | jq 'length')
med=$(dispatch_set MEDIUM | jq 'length')
high=$(dispatch_set HIGH | jq 'length')
crit=$(dispatch_set CRITICAL | jq 'length')
assert "LOW has 2 reviewers" "2" "$low"
assert "MEDIUM has 4 reviewers" "4" "$med"
assert "HIGH has 6 reviewers" "6" "$high"
assert "CRITICAL has 7 reviewers" "7" "$crit"

# Test 2: dispatch_set supersets (LOW ⊆ MEDIUM ⊆ HIGH ⊆ CRITICAL)
echo ""
echo "Test 2: tier subset invariant"
low_in_med=$(jq -n --argjson l "$(dispatch_set LOW)" --argjson m "$(dispatch_set MEDIUM)" \
  '$l | all(. as $x | $m | any(. == $x))')
med_in_high=$(jq -n --argjson m "$(dispatch_set MEDIUM)" --argjson h "$(dispatch_set HIGH)" \
  '$m | all(. as $x | $h | any(. == $x))')
high_in_crit=$(jq -n --argjson h "$(dispatch_set HIGH)" --argjson c "$(dispatch_set CRITICAL)" \
  '$h | all(. as $x | $c | any(. == $x))')
assert "LOW ⊆ MEDIUM" "true" "$low_in_med"
assert "MEDIUM ⊆ HIGH" "true" "$med_in_high"
assert "HIGH ⊆ CRITICAL" "true" "$high_in_crit"

# Test 3: required core reviewers present at every tier
echo ""
echo "Test 3: core reviewers always present"
for tier in LOW MEDIUM HIGH CRITICAL; do
  has_code=$(dispatch_set "$tier" | jq 'any(. == "oh-my-claudecode:code-reviewer")')
  has_synth=$(dispatch_set "$tier" | jq 'any(. == "soliton:synthesizer")')
  assert "$tier has code-reviewer" "true" "$has_code"
  assert "$tier has synthesizer" "true" "$has_synth"
done

# Test 4: CRITICAL tier adds cross-provider critic
echo ""
echo "Test 4: CRITICAL tier includes cross-provider critic"
has_xprov=$(dispatch_set CRITICAL | jq 'any(. == "omc:ask-codex-critic")')
assert "CRITICAL has omc:ask-codex-critic" "true" "$has_xprov"
has_xprov_high=$(dispatch_set HIGH | jq 'any(. == "omc:ask-codex-critic")')
assert "HIGH does NOT include cross-provider critic" "false" "$has_xprov_high"

# Test 5: unknown tier returns error
echo ""
echo "Test 5: unknown tier errors"
dispatch_set "UNKNOWN" >/dev/null 2>&1
assert "unknown tier exits 1" "1" "$?"

# Test 6: risk_score_from_quantum reads intentDrift
echo ""
echo "Test 6: risk_score_from_quantum extracts critical count"
TEST_TMPDIR=$(mktemp -d)
cat > "$TEST_TMPDIR/quantum.json" << 'EOF'
{"intentDrift": {"feature-a": {"summary": {"critical": 1}}}}
EOF
score=$(risk_score_from_quantum "$TEST_TMPDIR/quantum.json" "" "" 2>/dev/null)
assert "intent drift critical=1 contributes 10" "10" "$score"
rm -rf "$TEST_TMPDIR"
# Missing quantum.json gracefully yields 0
score=$(risk_score_from_quantum "/nonexistent/quantum.json" "" "" 2>/dev/null)
assert "missing quantum.json yields 0" "0" "$score"

# Test 7: prepare_review_context emits valid JSON with required keys
echo ""
echo "Test 7: prepare_review_context shape"
TEST_TMPDIR=$(mktemp -d)
cd "$TEST_TMPDIR"
git init -q
git commit --allow-empty -m "init" -q
BASE=$(git rev-parse HEAD)
echo hi > f.txt; git add f.txt; git commit -q -m "add f"
HEAD_S=$(git rev-parse HEAD)
ctx=$(prepare_review_context "$BASE" "$HEAD_S" "tasks/prd.md" "verbatim user intent" "HIGH")
has_base=$(printf '%s' "$ctx" | jq -r '.base_sha')
has_tier=$(printf '%s' "$ctx" | jq -r '.tier')
has_intent=$(printf '%s' "$ctx" | jq -r '.user_intent')
has_files=$(printf '%s' "$ctx" | jq '.changed_files | length')
has_evidence_req=$(printf '%s' "$ctx" | jq '.evidence_requirements.must_cite | length')
assert "context has base_sha" "$BASE" "$has_base"
assert "context has tier" "HIGH" "$has_tier"
assert "context has verbatim intent" "verbatim user intent" "$has_intent"
assert "context has 1 changed file" "1" "$has_files"
assert "context has evidence_requirements.must_cite with 3 entries" "3" "$has_evidence_req"
cd "$REPO_ROOT"
rm -rf "$TEST_TMPDIR"

# Test 8: aggregate_reviews chains filters end-to-end
echo ""
echo "Test 8: aggregate_reviews chain"
# Create a fixture with 2 reviewers' outputs. Files exist under $PWD/tests/
# so hallucination_check doesn't suppress them.
reviewer_a='[
  {"file":"tests/test_deep_review.sh","line":10,"severity":"high","confidence":85,"evidence_type":"code-reference","agents":["code-reviewer"]},
  {"file":"tests/test_deep_review.sh","severity":"medium","confidence":60,"agents":["code-reviewer"]}
]'
reviewer_b='[
  {"file":"tests/test_deep_review.sh","line":10,"severity":"high","confidence":78,"evidence_type":"code-reference","agents":["synthesizer"]},
  {"file":"ghost/missing.ts","line":1,"severity":"critical","confidence":95,"evidence_type":"code-reference","agents":["critic"]}
]'
input=$(jq -cn --argjson a "$reviewer_a" --argjson b "$reviewer_b" '[$a, $b]')
agg=$(printf '%s' "$input" | aggregate_reviews "$REPO_ROOT")
verdict=$(printf '%s' "$agg" | jq -r '.verdict')
findings_n=$(printf '%s' "$agg" | jq '.findings | length')
suppressed_n=$(printf '%s' "$agg" | jq '.suppressed | length')
# Real files line 10 finding dedups from 2 reviewers → 1 kept.
# Ghost file suppressed by hallucination check → 1 suppressed with reason "reviewer hallucinated target".
# No-line finding suppressed by actionability → 1 suppressed with reason "no actionable evidence".
assert "aggregate kept 1 finding" "1" "$findings_n"
assert "aggregate suppressed 2 findings" "2" "$suppressed_n"
assert "verdict REQUEST_CHANGES (high ≥70)" "REQUEST_CHANGES" "$verdict"

# Test 9: CLI subcommands
echo ""
echo "Test 9: CLI subcommands"
cli_low=$(bash "$REPO_ROOT/lib/deep-review.sh" dispatch-set LOW | tr -d '\n' | jq 'length')
assert "CLI dispatch-set LOW -> 2" "2" "$cli_low"

echo ""
echo "=== Results: $PASS/$TOTAL passed, $FAIL failed ==="
exit $((FAIL > 0 ? 1 : 0))
