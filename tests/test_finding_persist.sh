#!/usr/bin/env bash
# v0.7.0 / US-002 (G13) -- lib/finding-persist.sh persistence tests.
#
# Covers: snapshot write + idempotent overwrite, CSV header-once + append,
# 3-stage end-to-end, missing dir auto-create, missing file → {} read.
# Plus skill-wire grep assertions: each of the 3 SKILLs sources the
# parser+persister and calls persist_review_findings for its stage.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$SCRIPT_DIR/.."
LIB_DIR="$REPO_ROOT/lib"
PASS=0
FAIL=0
TOTAL=0

# Sanity guards
if ! command -v jq &>/dev/null; then
  echo "SKIP: jq not found"; exit 1
fi
if [[ ! -f "$LIB_DIR/finding-synth.sh" ]]; then
  echo "SKIP: lib/finding-synth.sh not found (US-001 dep)"; exit 1
fi
if [[ ! -f "$LIB_DIR/finding-persist.sh" ]]; then
  echo "SKIP: lib/finding-persist.sh not found (RED phase)"; exit 1
fi

# shellcheck disable=SC1091
source "$LIB_DIR/finding-synth.sh"
# shellcheck disable=SC1091
source "$LIB_DIR/finding-persist.sh"

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

assert_true() {
  local name="$1" cond="$2"
  TOTAL=$((TOTAL + 1))
  if [[ "$cond" == "true" ]]; then
    echo "  PASS: $name"; PASS=$((PASS + 1))
  else
    echo "  FAIL: $name"; FAIL=$((FAIL + 1))
  fi
}

# Build a synthetic findings JSON + summary for a given stage.
# Severity counts: 1 crit, 1 high, 2 medium, 0 low.
mock_findings() {
  cat << 'EOF'
[
  {"category":"missing-section","severity":"critical","file":"docs/x.md","line":"0","evidence":"no Functional Requirements","suggestion":"add FR section"},
  {"category":"tbd-marker","severity":"high","file":"docs/x.md","line":"42","evidence":"TBD","suggestion":"resolve TBD"},
  {"category":"hedge-phrase","severity":"medium","file":"docs/x.md","line":"50","evidence":"may need to","suggestion":"specify"},
  {"category":"hedge-phrase","severity":"medium","file":"docs/x.md","line":"55","evidence":"could include","suggestion":"specify"}
]
EOF
}
mock_summary() {
  local stage="$1"
  jq -nc --arg s "$stage" '{
    stage: $s,
    count: 4,
    by_severity: { critical: 1, high: 1, medium: 2, low: 0 },
    by_category: { "missing-section": 1, "tbd-marker": 1, "hedge-phrase": 2 }
  }'
}

echo "=== v0.7.0 US-002 finding-persist tests ==="

# Test 1: persist_review_findings creates snapshot file with valid schema
echo ""
echo "Test 1: snapshot creation + schema"
TMP=$(mktemp -d)
findings_json=$(mock_findings)
summary_json=$(mock_summary design)
persist_review_findings "design" "docs/foo-design.md" "$summary_json" "$findings_json" "$TMP" >/dev/null
SNAP="$TMP/.handoffs/design-review-findings.json"
[[ -f "$SNAP" ]] && { echo "  PASS: snapshot file created at $SNAP"; PASS=$((PASS + 1)); } \
                 || { echo "  FAIL: no snapshot at $SNAP"; FAIL=$((FAIL + 1)); }
TOTAL=$((TOTAL + 1))
assert "snapshot.stage"       "design"             "$(jq -r '.stage'        "$SNAP")"
assert "snapshot.source_path" "docs/foo-design.md" "$(jq -r '.source_path'  "$SNAP")"
assert "snapshot.summary.count" "4"                "$(jq -r '.summary.count' "$SNAP")"
assert "snapshot.findings|length" "4"              "$(jq    '.findings | length' "$SNAP")"
TS=$(jq -r '.timestamp' "$SNAP")
[[ -n "$TS" && "$TS" != "null" ]] && { echo "  PASS: snapshot.timestamp non-empty"; PASS=$((PASS + 1)); } \
                                  || { echo "  FAIL: snapshot.timestamp empty"; FAIL=$((FAIL + 1)); }
TOTAL=$((TOTAL + 1))
rm -rf "$TMP"

# Test 2: CSV created with header on first call; data row appended.
echo ""
echo "Test 2: CSV header-once + data row"
TMP=$(mktemp -d)
findings_json=$(mock_findings)
summary_json=$(mock_summary design)
persist_review_findings "design" "docs/x.md" "$summary_json" "$findings_json" "$TMP" >/dev/null
CSV="$TMP/metrics/pre-impl-review-findings.csv"
[[ -f "$CSV" ]] && { echo "  PASS: metrics/ auto-created + CSV present"; PASS=$((PASS + 1)); } \
                || { echo "  FAIL: $CSV missing"; FAIL=$((FAIL + 1)); }
TOTAL=$((TOTAL + 1))
HEADER=$(head -1 "$CSV")
assert "CSV header" "timestamp,stage,source_path,count,critical,high,medium,low" "$HEADER"
LINES=$(wc -l < "$CSV")
LINES=$(echo "$LINES" | tr -d '[:space:]')
assert "CSV total lines (header + 1 row)" "2" "$LINES"
ROW1=$(sed -n '2p' "$CSV")
case "$ROW1" in
  *",design,docs/x.md,4,1,1,2,0"*)
    echo "  PASS: CSV row1 matches schema (stage=design, count=4, 1/1/2/0)"; PASS=$((PASS + 1)) ;;
  *)
    echo "  FAIL: CSV row1 unexpected: $ROW1"; FAIL=$((FAIL + 1)) ;;
esac
TOTAL=$((TOTAL + 1))
rm -rf "$TMP"

# Test 3: re-running same stage overwrites snapshot but appends new CSV row
echo ""
echo "Test 3: idempotent snapshot overwrite + CSV append"
TMP=$(mktemp -d)
findings_json=$(mock_findings)
summary_json=$(mock_summary design)
persist_review_findings "design" "docs/x.md"  "$summary_json" "$findings_json" "$TMP" >/dev/null
SNAP1_TS=$(jq -r '.timestamp' "$TMP/.handoffs/design-review-findings.json")
sleep 1
persist_review_findings "design" "docs/x2.md" "$summary_json" "$findings_json" "$TMP" >/dev/null
SNAP2_TS=$(jq -r '.timestamp' "$TMP/.handoffs/design-review-findings.json")
SNAP2_SRC=$(jq -r '.source_path' "$TMP/.handoffs/design-review-findings.json")
TOTAL=$((TOTAL + 1))
if [[ "$SNAP1_TS" != "$SNAP2_TS" ]]; then
  echo "  PASS: snapshot timestamp updated on second write"; PASS=$((PASS + 1))
else
  echo "  FAIL: snapshot timestamp unchanged ($SNAP1_TS == $SNAP2_TS)"; FAIL=$((FAIL + 1))
fi
assert "snapshot source_path overwritten" "docs/x2.md" "$SNAP2_SRC"
LINES=$(wc -l < "$TMP/metrics/pre-impl-review-findings.csv")
LINES=$(echo "$LINES" | tr -d '[:space:]')
assert "CSV now header + 2 data rows" "3" "$LINES"
rm -rf "$TMP"

# Test 4: 3-stage end-to-end (design + prd + plan) → 3 snapshots + 3 data rows
echo ""
echo "Test 4: 3-stage end-to-end"
TMP=$(mktemp -d)
for stage in design prd plan; do
  src="docs/$stage-source.md"
  persist_review_findings "$stage" "$src" "$(mock_summary "$stage")" "$(mock_findings)" "$TMP" >/dev/null
done
N_SNAP=$(ls "$TMP/.handoffs/"*-review-findings.json 2>/dev/null | wc -l)
N_SNAP=$(echo "$N_SNAP" | tr -d '[:space:]')
assert "3 snapshot files" "3" "$N_SNAP"
LINES=$(wc -l < "$TMP/metrics/pre-impl-review-findings.csv")
LINES=$(echo "$LINES" | tr -d '[:space:]')
assert "CSV header + 3 data rows" "4" "$LINES"
# Each stage appears in its row's stage column
for stage in design prd plan; do
  TOTAL=$((TOTAL + 1))
  if grep -qE ",${stage}," "$TMP/metrics/pre-impl-review-findings.csv"; then
    echo "  PASS: CSV contains row for stage=$stage"; PASS=$((PASS + 1))
  else
    echo "  FAIL: CSV missing row for stage=$stage"; FAIL=$((FAIL + 1))
  fi
done
rm -rf "$TMP"

# Test 5: missing metrics/ dir auto-created (covered by Test 2 already, but
# explicit because the AC calls it out separately)
echo ""
echo "Test 5: missing metrics/ dir auto-created on first call"
TMP=$(mktemp -d)
[[ ! -d "$TMP/metrics" ]] && { echo "  PASS: pre-call: metrics/ does not exist"; PASS=$((PASS + 1)); } \
                          || { echo "  FAIL: metrics/ existed pre-call"; FAIL=$((FAIL + 1)); }
TOTAL=$((TOTAL + 1))
persist_review_findings "design" "docs/x.md" "$(mock_summary design)" "$(mock_findings)" "$TMP" >/dev/null
[[ -d "$TMP/metrics" ]] && { echo "  PASS: post-call: metrics/ auto-created"; PASS=$((PASS + 1)); } \
                        || { echo "  FAIL: metrics/ not created"; FAIL=$((FAIL + 1)); }
TOTAL=$((TOTAL + 1))
rm -rf "$TMP"

# Test 6: read_review_findings on missing snapshot returns {} with stderr WARN
echo ""
echo "Test 6: read_review_findings missing → {}"
TMP=$(mktemp -d)
out=$(read_review_findings "design" "$TMP" 2> "$TMP/stderr.log")
assert "missing snapshot returns {}" "{}" "$out"
TOTAL=$((TOTAL + 1))
if grep -qiE 'warn|missing' "$TMP/stderr.log"; then
  echo "  PASS: stderr emits WARN on missing snapshot"; PASS=$((PASS + 1))
else
  echo "  FAIL: no stderr WARN on missing snapshot"
  cat "$TMP/stderr.log" >&2
  FAIL=$((FAIL + 1))
fi
rm -rf "$TMP"

# Test 7: read_review_findings on existing snapshot round-trips
echo ""
echo "Test 7: read_review_findings on existing snapshot"
TMP=$(mktemp -d)
persist_review_findings "prd" "tasks/prd-x.md" "$(mock_summary prd)" "$(mock_findings)" "$TMP" >/dev/null
got=$(read_review_findings "prd" "$TMP")
assert "round-trip stage" "prd"            "$(jq -r '.stage'        <<< "$got")"
assert "round-trip src"   "tasks/prd-x.md" "$(jq -r '.source_path'  <<< "$got")"
assert "round-trip count" "4"              "$(jq -r '.summary.count' <<< "$got")"
rm -rf "$TMP"

# Test 8: stage validation — unknown stage rejected with stderr error
echo ""
echo "Test 8: unknown stage rejected"
TMP=$(mktemp -d)
TOTAL=$((TOTAL + 1))
if persist_review_findings "BOGUS" "x" "{}" "[]" "$TMP" 2>/dev/null; then
  echo "  FAIL: bogus stage accepted (should have errored)"; FAIL=$((FAIL + 1))
else
  echo "  PASS: bogus stage rejected (non-zero exit)"; PASS=$((PASS + 1))
fi
rm -rf "$TMP"

# Test 9 — .gitignore wires the snapshot suffix; metrics/ not gitignored
echo ""
echo "Test 9: .gitignore wires"
GI="$REPO_ROOT/.gitignore"
TOTAL=$((TOTAL + 1))
if grep -qE '\-review-findings\.json' "$GI"; then
  echo "  PASS: .gitignore ignores *-review-findings.json"; PASS=$((PASS + 1))
else
  echo "  FAIL: .gitignore missing *-review-findings.json rule"; FAIL=$((FAIL + 1))
fi
TOTAL=$((TOTAL + 1))
if grep -qE '^metrics/?$' "$GI"; then
  echo "  FAIL: .gitignore ignores metrics/ — must NOT be ignored"; FAIL=$((FAIL + 1))
else
  echo "  PASS: .gitignore does NOT ignore metrics/"; PASS=$((PASS + 1))
fi

# Test 10 — skill wires: each SKILL.md sources the persister + calls
# persist_review_findings for its stage.
echo ""
echo "Test 10: 3 SKILL.md files wire lib/finding-persist.sh"
check_in() {
  local name="$1" needle="$2" file="$3"
  TOTAL=$((TOTAL + 1))
  if grep -qF -- "$needle" "$REPO_ROOT/$file"; then
    echo "  PASS: $name"; PASS=$((PASS + 1))
  else
    echo "  FAIL: $name -- needle [$needle] not in $file"
    FAIL=$((FAIL + 1))
  fi
}
check_in "ql-brainstorm sources finding-synth.sh"   "lib/finding-synth.sh"   "skills/ql-brainstorm/SKILL.md"
check_in "ql-brainstorm sources finding-persist.sh" "lib/finding-persist.sh" "skills/ql-brainstorm/SKILL.md"
check_in "ql-brainstorm calls persist_review_findings design" "persist_review_findings"      "skills/ql-brainstorm/SKILL.md"
check_in "ql-spec sources finding-synth.sh"         "lib/finding-synth.sh"   "skills/ql-spec/SKILL.md"
check_in "ql-spec sources finding-persist.sh"       "lib/finding-persist.sh" "skills/ql-spec/SKILL.md"
check_in "ql-spec calls persist_review_findings"    "persist_review_findings" "skills/ql-spec/SKILL.md"
check_in "ql-plan sources finding-synth.sh"         "lib/finding-synth.sh"   "skills/ql-plan/SKILL.md"
check_in "ql-plan sources finding-persist.sh"       "lib/finding-persist.sh" "skills/ql-plan/SKILL.md"
check_in "ql-plan calls persist_review_findings"    "persist_review_findings" "skills/ql-plan/SKILL.md"

echo ""
echo "=== Results: $PASS/$TOTAL passed, $FAIL failed ==="
exit $((FAIL > 0 ? 1 : 0))
