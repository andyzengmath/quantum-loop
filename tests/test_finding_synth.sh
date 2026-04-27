#!/usr/bin/env bash
# v0.7.0 / US-001 (G12) — lib/finding-synth.sh parser tests.
#
# Validates parse_findings, summarize_findings, format_summary_line.
# Modeled on tests/test_handoff.sh: PASS/FAIL counters, sourced library,
# mktemp -d sandboxes per test isolation.

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

assert_contains() {
  local name="$1" needle="$2" haystack="$3"
  TOTAL=$((TOTAL + 1))
  if [[ "$haystack" == *"$needle"* ]]; then
    echo "  PASS: $name"; PASS=$((PASS + 1))
  else
    echo "  FAIL: $name (needle [$needle] not in haystack)"
    FAIL=$((FAIL + 1))
  fi
}

# shellcheck disable=SC1091
source "$REPO_ROOT/lib/finding-synth.sh"

echo "=== v0.7.0 US-001 finding-synth tests ==="

# Test 1: empty stdin → empty array, summary count 0
echo ""
echo "Test 1: empty stdin produces empty array"
out=$(printf '' | parse_findings "design")
assert "empty stdin → []" "[]" "$out"
summary=$(summarize_findings "design" "$out")
assert "empty summary count = 0" "0" "$(jq -r '.count' <<< "$summary")"
assert "empty summary stage = design" "design" "$(jq -r '.stage' <<< "$summary")"

# Test 2: single well-formed block → 1-element array with all 6 fields
echo ""
echo "Test 2: single well-formed FINDING block"
single=$(cat <<'EOF'
FINDING_START
  category: missing-section
  severity: critical
  file: docs/plans/x-design.md
  line: 0
  evidence: "## Non-Goals" section absent
  suggestion: Add a Non-Goals section enumerating out-of-scope items.
FINDING_END
EOF
)
out=$(printf '%s\n' "$single" | parse_findings "design")
assert "single block → length 1" "1" "$(jq 'length' <<< "$out")"
assert "category populated" "missing-section" "$(jq -r '.[0].category' <<< "$out")"
assert "severity populated" "critical" "$(jq -r '.[0].severity' <<< "$out")"
assert "file populated" "docs/plans/x-design.md" "$(jq -r '.[0].file' <<< "$out")"
assert "line populated" "0" "$(jq -r '.[0].line' <<< "$out")"
assert "evidence populated" '"## Non-Goals" section absent' "$(jq -r '.[0].evidence' <<< "$out")"
assert "suggestion populated" "Add a Non-Goals section enumerating out-of-scope items." "$(jq -r '.[0].suggestion' <<< "$out")"

# Test 3: 4 mixed-severity blocks → severity counts 1/1/2/0
echo ""
echo "Test 3: four mixed-severity blocks"
mixed=$(cat <<'EOF'
FINDING_START
  category: missing-section
  severity: critical
  file: a.md
  line: 0
  evidence: e1
  suggestion: s1
FINDING_END
FINDING_START
  category: hedge-phrase
  severity: high
  file: b.md
  line: 12
  evidence: e2
  suggestion: s2
FINDING_END
FINDING_START
  category: tbd-marker
  severity: medium
  file: c.md
  line: 5
  evidence: e3
  suggestion: s3
FINDING_END
FINDING_START
  category: missing-non-goals
  severity: medium
  file: d.md
  line: 0
  evidence: e4
  suggestion: s4
FINDING_END
EOF
)
out=$(printf '%s\n' "$mixed" | parse_findings "design")
assert "4 blocks → length 4" "4" "$(jq 'length' <<< "$out")"
summary=$(summarize_findings "design" "$out")
assert "summary count = 4" "4" "$(jq -r '.count' <<< "$summary")"
assert "by_severity.critical = 1" "1" "$(jq -r '.by_severity.critical' <<< "$summary")"
assert "by_severity.high = 1" "1" "$(jq -r '.by_severity.high' <<< "$summary")"
assert "by_severity.medium = 2" "2" "$(jq -r '.by_severity.medium' <<< "$summary")"
assert "by_severity.low = 0" "0" "$(jq -r '.by_severity.low' <<< "$summary")"
# by_category should have 4 distinct keys, each count 1
assert "by_category.missing-section = 1" "1" "$(jq -r '.by_category."missing-section"' <<< "$summary")"

# Test 4: malformed block (no FINDING_END) → stderr warning + remaining blocks parsed
echo ""
echo "Test 4: malformed block tolerance"
malformed=$(cat <<'EOF'
FINDING_START
  category: missing-section
  severity: critical
  file: a.md
  line: 0
  evidence: open-no-close
  suggestion: this block has no FINDING_END
FINDING_START
  category: hedge-phrase
  severity: low
  file: b.md
  line: 1
  evidence: well-formed
  suggestion: keep me
FINDING_END
EOF
)
err_log=$(mktemp)
out=$(printf '%s\n' "$malformed" | parse_findings "design" 2>"$err_log")
# At least the well-formed second block should parse
assert "malformed → at least 1 parsed" "1" "$(jq 'length' <<< "$out")"
assert "well-formed survived" "hedge-phrase" "$(jq -r '.[0].category' <<< "$out")"
# stderr should contain a warning (any 'WARN' or 'malformed' substring)
err_content=$(cat "$err_log")
case "$err_content" in
  *WARN*|*malformed*|*warn*)
    echo "  PASS: malformed → stderr warning emitted"; PASS=$((PASS + 1));;
  *)
    echo "  FAIL: malformed → no stderr warning (got: [$err_content])"
    FAIL=$((FAIL + 1));;
esac
TOTAL=$((TOTAL + 1))
rm -f "$err_log"

# Test 5: format_summary_line round-trip
echo ""
echo "Test 5: format_summary_line"
summary='{"stage":"prd","count":4,"by_severity":{"critical":1,"high":1,"medium":2,"low":0},"by_category":{}}'
line=$(format_summary_line "$summary")
assert_contains "format mentions stage"     "prd-review complete"        "$line"
assert_contains "format mentions count"     "4 findings"                 "$line"
assert_contains "format mentions severities" "(1/1/2/0)"                 "$line"
assert_contains "format begins with [REVIEW]" "[REVIEW]"                  "$line"

# Test 6: zero-finding format string is "(clean)" per existing convention
echo ""
echo "Test 6: zero-finding format"
summary_clean='{"stage":"plan","count":0,"by_severity":{"critical":0,"high":0,"medium":0,"low":0},"by_category":{}}'
line_clean=$(format_summary_line "$summary_clean")
assert_contains "0-find → (clean)"  "(clean)"  "$line_clean"
assert_contains "0-find → plan-review" "plan-review complete: 0 findings" "$line_clean"

# Test 7: CLI subcommand mode
echo ""
echo "Test 7: CLI parse subcommand"
cli_out=$(printf '%s\n' "$single" | bash "$REPO_ROOT/lib/finding-synth.sh" parse "design")
assert "CLI parse → 1 element" "1" "$(jq 'length' <<< "$cli_out")"
assert "CLI parse category"    "missing-section" "$(jq -r '.[0].category' <<< "$cli_out")"

# Test 8: CLI summarize subcommand
echo ""
echo "Test 8: CLI summarize subcommand"
cli_findings='[{"category":"x","severity":"high","file":"f","line":"0","evidence":"e","suggestion":"s"}]'
cli_sum=$(bash "$REPO_ROOT/lib/finding-synth.sh" summarize "design" "$cli_findings")
assert "CLI summarize count = 1" "1" "$(jq -r '.count' <<< "$cli_sum")"
assert "CLI summarize by_severity.high = 1" "1" "$(jq -r '.by_severity.high' <<< "$cli_sum")"

# Test 9: empty stdin via CLI
echo ""
echo "Test 9: CLI parse empty stdin"
cli_empty=$(bash "$REPO_ROOT/lib/finding-synth.sh" parse "design" < /dev/null)
assert "CLI empty parse → []" "[]" "$cli_empty"

echo ""
echo "=== Results: $PASS/$TOTAL passed, $FAIL failed ==="
exit $((FAIL > 0 ? 1 : 0))
