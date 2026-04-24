#!/usr/bin/env bash
# Phase 24 / P3.5 — trajectory-length early kill tests.

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
source "$REPO_ROOT/lib/trajectory.sh"

echo "=== Phase 24 trajectory-kill tests ==="

# Helper to emit a Claude-style output with N occurrences of each tool marker.
gen_output() {
  local out="$1" reads="$2" greps="$3" edits="$4" writes="$5" bashes="$6"
  : > "$out"
  for ((i=0; i<reads;  i++)); do echo "⏺ Read(src/file.ts)"     >> "$out"; done
  for ((i=0; i<greps;  i++)); do echo "⏺ Grep('pattern', foo)"  >> "$out"; done
  for ((i=0; i<edits;  i++)); do echo "⏺ Edit(src/x.ts)"        >> "$out"; done
  for ((i=0; i<writes; i++)); do echo "⏺ Write(src/new.ts)"     >> "$out"; done
  for ((i=0; i<bashes; i++)); do echo "⏺ Bash(command)"         >> "$out"; done
}

# Test 1: parse_trajectory on missing file returns exists:false
echo ""
echo "Test 1: parse on missing file"
j=$(parse_trajectory /nonexistent/foo.log)
assert "exists=false"   "false" "$(jq -r '.exists' <<< "$j")"
assert "total=0"        "0"     "$(jq -r '.total_calls' <<< "$j")"

# Test 2: parse_trajectory counts tool calls correctly
echo ""
echo "Test 2: parse counts tools"
TMP=$(mktemp -d)
gen_output "$TMP/out.log" 5 3 2 1 4  # 15 total: 5R 3G 2E 1W 4B
j=$(parse_trajectory "$TMP/out.log")
assert "reads=5"        "5"  "$(jq -r '.reads' <<< "$j")"
assert "greps=3"        "3"  "$(jq -r '.greps' <<< "$j")"
assert "edits=2"        "2"  "$(jq -r '.edits' <<< "$j")"
assert "writes=1"       "1"  "$(jq -r '.writes' <<< "$j")"
assert "bashes=4"       "4"  "$(jq -r '.bashes' <<< "$j")"
assert "total=15"       "15" "$(jq -r '.total_calls' <<< "$j")"
# read_pct = (5+3)/15 * 100 = 53
assert "read_pct=53"    "53" "$(jq -r '.read_pct' <<< "$j")"
# edit_pct = (2+1)/15 * 100 = 20
assert "edit_pct=20"    "20" "$(jq -r '.edit_pct' <<< "$j")"
rm -rf "$TMP"

# Test 3: classify — productive (healthy mix of reads + edits)
echo ""
echo "Test 3: productive trajectory"
TMP=$(mktemp -d)
gen_output "$TMP/out.log" 5 2 8 3 2  # 20 total: 35% reads, 55% edits
j=$(parse_trajectory "$TMP/out.log")
cls=$(classify_trajectory "$j")
assert "classify productive" "productive" "$cls"
should_early_kill "$j"
assert "productive -> no kill (exit 1)" "1" "$?"
rm -rf "$TMP"

# Test 4: classify — searching (mostly reads, early phase)
echo ""
echo "Test 4: searching trajectory"
TMP=$(mktemp -d)
gen_output "$TMP/out.log" 8 4 1 1 1  # 15 total: 80% reads, 13% edits
j=$(parse_trajectory "$TMP/out.log")
cls=$(classify_trajectory "$j")
# <20 total calls so even high read % is "searching" not "thrashing"
assert "classify searching (below thrash min)" "searching" "$cls"
should_early_kill "$j"
assert "searching -> no kill" "1" "$?"
rm -rf "$TMP"

# Test 5: classify — thrashing (many reads, no edits, past threshold)
echo ""
echo "Test 5: thrashing trajectory"
TMP=$(mktemp -d)
gen_output "$TMP/out.log" 20 5 0 0 1  # 26 total: 96% reads, 0% edits
j=$(parse_trajectory "$TMP/out.log")
# Total >= 20 AND read% >= 70 AND edit% <= 5
cls=$(classify_trajectory "$j")
# Note: prod=0 with total=26 ≥ STUCK_MIN_CALLS (30) — actually with total=26 stuck is NOT triggered (needs >= 30). Thrashing IS triggered.
# Wait let me recompute — default STUCK_MIN_CALLS=30. total=26 < 30 so stuck NOT fired.
# Default THRASH_MIN_CALLS=20. total=26 ≥ 20. read%=25/26*100=96 >= 70. edit%=0 <= 5. → thrashing.
assert "classify thrashing" "thrashing" "$cls"
should_early_kill "$j"
assert "thrashing -> kill (exit 0)" "0" "$?"
rm -rf "$TMP"

# Test 6: classify — stuck (many calls, zero edits)
echo ""
echo "Test 6: stuck trajectory"
TMP=$(mktemp -d)
gen_output "$TMP/out.log" 15 10 0 0 10  # 35 total, 0 edits — triggers STUCK (>=30, prod=0)
j=$(parse_trajectory "$TMP/out.log")
cls=$(classify_trajectory "$j")
assert "classify stuck" "stuck" "$cls"
should_early_kill "$j"
assert "stuck -> kill (exit 0)" "0" "$?"
rm -rf "$TMP"

# Test 7: threshold overrides via env vars
echo ""
echo "Test 7: env-var overrides take effect"
TMP=$(mktemp -d)
gen_output "$TMP/out.log" 8 0 0 0 0  # 8 total, all reads
j=$(parse_trajectory "$TMP/out.log")
# default thresholds: total=8 < THRASH_MIN=20, so "searching"
cls=$(classify_trajectory "$j")
assert "default: searching" "searching" "$cls"
# With THRASH_MIN=5, total=8 >= 5, read=100>=70, edit=0<=5 → thrashing
cls_override=$(TRAJECTORY_THRASH_MIN_CALLS=5 classify_trajectory "$j")
assert "override THRASH_MIN=5: thrashing" "thrashing" "$cls_override"
rm -rf "$TMP"

# Test 8: empty file is "productive" (no signal to act on)
echo ""
echo "Test 8: empty file handling"
TMP=$(mktemp -d)
: > "$TMP/empty.log"
j=$(parse_trajectory "$TMP/empty.log")
total=$(jq -r '.total_calls' <<< "$j")
cls=$(classify_trajectory "$j")
assert "empty file total=0" "0" "$total"
assert "empty file classify=productive (no signal)" "productive" "$cls"
rm -rf "$TMP"

# Test 9: CLI subcommands
echo ""
echo "Test 9: CLI subcommands"
TMP=$(mktemp -d)
gen_output "$TMP/out.log" 20 5 0 0 1  # thrashing shape
# CLI parse
cli_parse=$(bash "$REPO_ROOT/lib/trajectory.sh" parse "$TMP/out.log")
assert "CLI parse total=26" "26" "$(jq -r '.total_calls' <<< "$cli_parse")"
# CLI classify via stdin (NOT supported — CLI passes $@ as literal) — use arg
cli_cls=$(bash "$REPO_ROOT/lib/trajectory.sh" classify "$cli_parse" | tr -d '\n')
assert "CLI classify thrashing" "thrashing" "$cli_cls"
# CLI kill
bash "$REPO_ROOT/lib/trajectory.sh" kill "$cli_parse" 2>/dev/null
assert "CLI kill exits 0 for thrashing" "0" "$?"
rm -rf "$TMP"

# Test 10: classify_trajectory reads stdin if no arg
echo ""
echo "Test 10: classify reads stdin"
TMP=$(mktemp -d)
gen_output "$TMP/out.log" 5 2 8 3 2
j=$(parse_trajectory "$TMP/out.log")
cls_stdin=$(printf '%s' "$j" | classify_trajectory)
assert "stdin classify productive" "productive" "$cls_stdin"
rm -rf "$TMP"

echo ""
echo "=== Results: $PASS/$TOTAL passed, $FAIL failed ==="
exit $((FAIL > 0 ? 1 : 0))
