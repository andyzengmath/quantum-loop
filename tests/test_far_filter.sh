#!/usr/bin/env bash
# Phase 23 / P3.3 — tests for far_filter (KBI-FAR precision stage).

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

echo "=== Phase 23 KBI-FAR far_filter tests ==="

# Test 1: below-cutoff findings suppressed
echo ""
echo "Test 1: confidence cutoff"
raw='[
  {"file":"a.ts","line":1,"severity":"high","confidence":75,"agents":["r1"],"title":"X","description":"bug X"},
  {"file":"b.ts","line":2,"severity":"low","confidence":40,"agents":["r1"],"title":"Y","description":"nit Y"},
  {"file":"c.ts","line":3,"severity":"medium","confidence":30,"agents":["r1"],"title":"Z","description":"minor Z"}
]'
out=$(printf '%s' "$raw" | far_filter)
kept=$(printf '%s' "$out" | jq '.kept | length')
supp=$(printf '%s' "$out" | jq '.suppressed | length')
assert "1 kept (conf ≥60)" "1" "$kept"
assert "2 suppressed (conf <60)" "2" "$supp"
# Check suppression reason mentions confidence
reason=$(printf '%s' "$out" | jq -r '.suppressed[0].far_reason')
case "$reason" in
  *"confidence"*) echo "  PASS: reason mentions confidence"; PASS=$((PASS + 1)) ;;
  *) echo "  FAIL: reason [$reason]"; FAIL=$((FAIL + 1)) ;;
esac
TOTAL=$((TOTAL + 1))

# Test 2: multi-agent agreement boost
echo ""
echo "Test 2: agreement boost lifts across cutoff"
# Baseline confidence 50 (below cutoff 60), but with 2 reviewers, +15 → 65 (above)
raw='[
  {"file":"a.ts","line":1,"severity":"high","confidence":50,"agents":["r1","r2"],"title":"X","description":"agreed bug"}
]'
out=$(printf '%s' "$raw" | far_filter)
kept=$(printf '%s' "$out" | jq '.kept | length')
boosted=$(printf '%s' "$out" | jq -r '.kept[0].confidence')
orig=$(printf '%s' "$out" | jq -r '.kept[0].original_confidence // empty')
assert "agreement-boosted finding kept" "1" "$kept"
assert "confidence boosted 50 -> 65" "65" "$boosted"
assert "original_confidence preserved" "50" "$orig"
# Single-agent version of same finding gets cut
raw_single='[{"file":"a.ts","line":1,"severity":"high","confidence":50,"agents":["r1"],"title":"X"}]'
out2=$(printf '%s' "$raw_single" | far_filter)
kept2=$(printf '%s' "$out2" | jq '.kept | length')
assert "single-agent below-cutoff suppressed" "0" "$kept2"

# Test 3: Agreement boost capped at 100
echo ""
echo "Test 3: confidence cap at 100"
raw='[{"file":"a.ts","line":1,"severity":"critical","confidence":95,"agents":["r1","r2","r3"],"title":"X"}]'
out=$(printf '%s' "$raw" | far_filter)
conf=$(printf '%s' "$out" | jq -r '.kept[0].confidence')
assert "confidence capped at 100" "100" "$conf"

# Test 4: known-FP regex suppression
echo ""
echo "Test 4: knownFalsePositives regex suppression"
TEST_TMPDIR=$(mktemp -d)
cat > "$TEST_TMPDIR/quantum.json" << 'EOF'
{
  "knownFalsePositives": [
    "TODO comment",
    "eslint disable.*next-line"
  ]
}
EOF
raw='[
  {"file":"a.ts","line":1,"severity":"high","confidence":85,"agents":["r1"],"title":"TODO comment in code","description":"bad practice"},
  {"file":"b.ts","line":2,"severity":"medium","confidence":75,"agents":["r1"],"title":"real issue","description":"eslint disable-next-line misuse"},
  {"file":"c.ts","line":3,"severity":"high","confidence":85,"agents":["r1"],"title":"genuine bug","description":"null deref"}
]'
out=$(printf '%s' "$raw" | far_filter "$TEST_TMPDIR/quantum.json")
kept=$(printf '%s' "$out" | jq '.kept | length')
supp=$(printf '%s' "$out" | jq '.suppressed | length')
assert "genuine finding kept" "1" "$kept"
assert "2 suppressed by regex" "2" "$supp"
# Suppression reasons should mention FP
reasons=$(printf '%s' "$out" | jq -r '.suppressed[].far_reason' | sort -u)
case "$reasons" in
  *"knownFalsePositives"*) echo "  PASS: suppression reasons reference knownFalsePositives"; PASS=$((PASS + 1)) ;;
  *) echo "  FAIL: reasons [$reasons]"; FAIL=$((FAIL + 1)) ;;
esac
TOTAL=$((TOTAL + 1))
rm -rf "$TEST_TMPDIR"

# Test 5: missing quantum.json - no FP suppression
echo ""
echo "Test 5: missing quantum.json graceful fallback"
raw='[{"file":"a.ts","line":1,"severity":"high","confidence":80,"agents":["r1"],"title":"ok"}]'
out=$(printf '%s' "$raw" | far_filter "/nonexistent.json")
kept=$(printf '%s' "$out" | jq '.kept | length')
assert "finding kept with missing quantum.json" "1" "$kept"

# Test 6: empty input yields empty kept and suppressed
echo ""
echo "Test 6: empty input"
out=$(printf '[]' | far_filter)
kept=$(printf '%s' "$out" | jq '.kept | length')
supp=$(printf '%s' "$out" | jq '.suppressed | length')
assert "empty kept" "0" "$kept"
assert "empty suppressed" "0" "$supp"

# Test 7: CLI subcommand
echo ""
echo "Test 7: CLI subcommand"
cli_out=$(printf '[{"file":"a.ts","line":1,"severity":"high","confidence":80,"title":"X","agents":["r1"]}]' | \
  bash "$REPO_ROOT/lib/deep-review.sh" far)
cli_kept=$(printf '%s' "$cli_out" | jq '.kept | length')
assert "CLI far kept 1" "1" "$cli_kept"

# Test 8: aggregate_reviews pipeline integrates far_filter
echo ""
echo "Test 8: aggregate_reviews wires far_filter"
TEST_TMPDIR=$(mktemp -d)
cd "$TEST_TMPDIR"
mkdir -p src
echo "real" > src/real.ts
echo '{"knownFalsePositives":["skipme"]}' > "$TEST_TMPDIR/quantum.json"
# Two reviewers, one finding each.
# Finding A: high 80 real file — kept
# Finding B: medium 30 real file — suppressed by FAR cutoff
# Finding C: high 90 real file, title contains "skipme" — suppressed by FP
reviewer_a='[
  {"file":"src/real.ts","line":1,"severity":"high","confidence":80,"evidence_type":"code-reference","agents":["code-reviewer"],"title":"real bug"},
  {"file":"src/real.ts","line":2,"severity":"medium","confidence":30,"evidence_type":"code-reference","agents":["code-reviewer"],"title":"minor"}
]'
reviewer_b='[
  {"file":"src/real.ts","line":3,"severity":"high","confidence":90,"evidence_type":"code-reference","agents":["critic"],"title":"skipme pattern"}
]'
input=$(jq -cn --argjson a "$reviewer_a" --argjson b "$reviewer_b" '[$a,$b]')
agg=$(printf '%s' "$input" | aggregate_reviews "$TEST_TMPDIR" "$TEST_TMPDIR/quantum.json")
agg_kept=$(printf '%s' "$agg" | jq '.findings | length')
agg_supp=$(printf '%s' "$agg" | jq '.suppressed | length')
agg_verdict=$(printf '%s' "$agg" | jq -r '.verdict')
assert "aggregate kept 1 real finding" "1" "$agg_kept"
assert "aggregate suppressed 2 (cutoff + FP)" "2" "$agg_supp"
assert "verdict REQUEST_CHANGES (high ≥70)" "REQUEST_CHANGES" "$agg_verdict"
# Confirm FP suppression present
has_fp=$(printf '%s' "$agg" | jq '[.suppressed[] | select(.far_reason // "" | test("knownFalsePositives"))] | length')
assert "FP reason present" "1" "$has_fp"
cd "$REPO_ROOT"
rm -rf "$TEST_TMPDIR"

# Test 9: Phase 22 quantum.json.example has knownFalsePositives field
echo ""
echo "Test 9: schema extension"
kfp_type=$(jq -r '.knownFalsePositives | type' "$REPO_ROOT/quantum.json.example")
assert "knownFalsePositives is array" "array" "$kfp_type"

echo ""
echo "=== Results: $PASS/$TOTAL passed, $FAIL failed ==="
exit $((FAIL > 0 ? 1 : 0))
