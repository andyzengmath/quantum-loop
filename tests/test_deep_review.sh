#!/usr/bin/env bash
# Phase 8 / P1.1 + P1.2 — tests for lib/deep-review.sh helpers + schema wiring.

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

# shellcheck disable=SC1091
source "$REPO_ROOT/lib/deep-review.sh"

echo "=== Phase 8 ql-deep-review helper tests ==="

# Test 1: tier_of_score
echo ""
echo "Test 1: tier_of_score mapping"
assert "0 -> LOW"        "LOW"      "$(tier_of_score 0)"
assert "30 -> LOW"       "LOW"      "$(tier_of_score 30)"
assert "31 -> MEDIUM"    "MEDIUM"   "$(tier_of_score 31)"
assert "60 -> MEDIUM"    "MEDIUM"   "$(tier_of_score 60)"
assert "61 -> HIGH"      "HIGH"     "$(tier_of_score 61)"
assert "80 -> HIGH"      "HIGH"     "$(tier_of_score 80)"
assert "81 -> CRITICAL"  "CRITICAL" "$(tier_of_score 81)"
assert "100 -> CRITICAL" "CRITICAL" "$(tier_of_score 100)"

# Test 2: compute_risk_score clamping + no-refs safe
echo ""
echo "Test 2: compute_risk_score bounds"
score=$(compute_risk_score "" "" 2>/dev/null)
assert "empty refs -> 0" "0" "$score"
# Intent drift only -> 10
score=$(compute_risk_score "" "" "" 1 2>/dev/null)
assert "intent drift contributes 10" "10" "$score"

# Test 3: actionability_filter — kept vs suppressed
echo ""
echo "Test 3: actionability_filter"
raw='[
  {"file":"src/a.ts","line":10,"evidence_type":"code-reference","severity":"high","confidence":80},
  {"file":"src/b.ts","severity":"medium","confidence":50},
  {"file":"src/c.ts","line_start":20,"evidence_type":"diff-hunk","severity":"low","confidence":30},
  {"severity":"info","confidence":10}
]'
filtered=$(printf '%s' "$raw" | actionability_filter)
kept_count=$(printf '%s' "$filtered" | jq '.kept | length')
sup_count=$(printf '%s' "$filtered" | jq '.suppressed | length')
assert "kept count" "2" "$kept_count"
assert "suppressed count" "2" "$sup_count"
sup_reason=$(printf '%s' "$filtered" | jq -r '.suppressed[0].reason')
assert "suppressed has reason" "no actionable evidence" "$sup_reason"

# Test 4: dedup_findings — same (file, line, severity) merges agents + keeps max confidence
echo ""
echo "Test 4: dedup_findings"
raw='[
  {"file":"x.ts","line_start":5,"severity":"high","confidence":70,"agents":["code-reviewer"]},
  {"file":"x.ts","line_start":5,"severity":"high","confidence":88,"agents":["synthesizer"]},
  {"file":"x.ts","line_start":6,"severity":"high","confidence":60,"agents":["critic"]}
]'
deduped=$(printf '%s' "$raw" | dedup_findings)
count=$(printf '%s' "$deduped" | jq 'length')
assert "dedup reduces 3 -> 2" "2" "$count"
line5_entry=$(printf '%s' "$deduped" | jq -c '.[] | select(.line_start == 5)')
agent_count=$(printf '%s' "$line5_entry" | jq '.agents | length')
max_conf=$(printf '%s' "$line5_entry" | jq '.confidence')
assert "merged agents count" "2" "$agent_count"
assert "kept max confidence" "88" "$max_conf"

# Test 5: hallucination_check — suppresses missing files
echo ""
echo "Test 5: hallucination_check suppresses missing files"
TMP=$(mktemp -d)
cd "$TMP"
mkdir -p real
echo "x" > real/exists.ts
raw='[
  {"file":"real/exists.ts","line":10,"severity":"high"},
  {"file":"real/missing.ts","line":20,"severity":"high"}
]'
checked=$(printf '%s' "$raw" | hallucination_check "$TMP")
kept=$(printf '%s' "$checked" | jq '.kept | length')
sup=$(printf '%s' "$checked" | jq '.suppressed | length')
assert "1 file kept" "1" "$kept"
assert "1 file suppressed as hallucination" "1" "$sup"
hreason=$(printf '%s' "$checked" | jq -r '.suppressed[0].reason')
assert "suppressed reason" "reviewer hallucinated target" "$hreason"
cd "$REPO_ROOT"; rm -rf "$TMP"

# Test 6: synthesize_verdict — 4 severity branches
echo ""
echo "Test 6: synthesize_verdict"
assert "empty -> APPROVE" "APPROVE" "$(printf '[]' | synthesize_verdict)"
raw_low='[{"severity":"low","confidence":80}]'
assert "only low -> APPROVE" "APPROVE" "$(printf '%s' "$raw_low" | synthesize_verdict)"
raw_med='[{"severity":"medium","confidence":60}]'
assert "medium 60 -> APPROVE_WITH_COMMENTS" "APPROVE_WITH_COMMENTS" \
  "$(printf '%s' "$raw_med" | synthesize_verdict)"
raw_high='[{"severity":"high","confidence":75}]'
assert "high 75 -> REQUEST_CHANGES" "REQUEST_CHANGES" \
  "$(printf '%s' "$raw_high" | synthesize_verdict)"
raw_crit='[{"severity":"critical","confidence":85}]'
assert "critical 85 -> BLOCKS_MERGE" "BLOCKS_MERGE" \
  "$(printf '%s' "$raw_crit" | synthesize_verdict)"
raw_crit_lowconf='[{"severity":"critical","confidence":50}]'
assert "critical 50 (below threshold) -> APPROVE" "APPROVE" \
  "$(printf '%s' "$raw_crit_lowconf" | synthesize_verdict)"

# Test 7: Schema extension — quantum.json.example has reviews object
echo ""
echo "Test 7: quantum.json.example schema"
reviews_type=$(jq -r '.reviews | type' "$REPO_ROOT/quantum.json.example")
assert "reviews is object" "object" "$reviews_type"
jq_valid=$(jq empty "$REPO_ROOT/quantum.json.example" 2>&1 || echo "INVALID")
assert "quantum.json.example still valid JSON" "" "$jq_valid"

# Test 8: ql-execute SKILL.md references the deep-review hook
echo ""
echo "Test 8: ql-execute mentions the post-pipeline hook"
if grep -q "Post-pipeline review hook" "$REPO_ROOT/skills/ql-execute/SKILL.md"; then
  echo "  PASS: post-pipeline hook header present"
  PASS=$((PASS + 1))
else
  echo "  FAIL: ql-execute/SKILL.md missing 'Post-pipeline review hook'"
  FAIL=$((FAIL + 1))
fi
TOTAL=$((TOTAL + 1))
if grep -q "lib/deep-review.sh" "$REPO_ROOT/skills/ql-execute/SKILL.md"; then
  echo "  PASS: references lib/deep-review.sh"
  PASS=$((PASS + 1))
else
  echo "  FAIL: ql-execute/SKILL.md missing lib/deep-review.sh reference"
  FAIL=$((FAIL + 1))
fi
TOTAL=$((TOTAL + 1))

# Test 9: CLI subcommands
echo ""
echo "Test 9: CLI subcommands work"
assert "CLI tier 50 -> MEDIUM" "MEDIUM" "$(bash "$REPO_ROOT/lib/deep-review.sh" tier 50 | tr -d '\n')"
assert "CLI tier 100 -> CRITICAL" "CRITICAL" "$(bash "$REPO_ROOT/lib/deep-review.sh" tier 100 | tr -d '\n')"

echo ""
echo "=== Results: $PASS/$TOTAL passed, $FAIL failed ==="
exit $((FAIL > 0 ? 1 : 0))
