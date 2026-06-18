#!/usr/bin/env bash
# tests/test_reuse_scan.sh — Track A / Q2 reuse-first search + gate tests.

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
    echo "  FAIL: $name (expected [$expected] got [$actual])"; FAIL=$((FAIL + 1))
  fi
}

# shellcheck disable=SC1091
source "$REPO_ROOT/lib/reuse-scan.sh"
unset QL_QUALITY_BLOCKING

echo "=== Track A Q2 reuse-scan tests ==="

# Build a fixture tree: src defs + a test-file def that must be excluded.
TEST_TMPDIR=$(mktemp -d)
mkdir -p "$TEST_TMPDIR/src" "$TEST_TMPDIR/tests"
cat > "$TEST_TMPDIR/src/config.py" << 'PY'
def parse_config(path):
    return {}


class ConfigLoader:
    pass
PY
cat > "$TEST_TMPDIR/tests/test_config.py" << 'PY'
def parse_config_helper():
    pass
PY

# Test 1: scan finds existing src symbols for term "config"
echo ""
echo "Test 1: scan finds existing symbols"
cands=$(scan_reuse_candidates "config" "$TEST_TMPDIR")
assert "2 candidates (parse_config + ConfigLoader)" "2" "$(jq 'length' <<< "$cands")"
assert "symbols sorted" "ConfigLoader,parse_config" "$(jq -r '[.[].symbol] | sort | join(",")' <<< "$cands")"

# Test 2: test files are excluded
echo ""
echo "Test 2: test files excluded"
assert "no candidate from tests/" "false" "$(jq -c '[.[].file | test("tests/")] | any' <<< "$cands")"

# Test 3: no match -> empty
echo ""
echo "Test 3: unmatched term -> []"
assert "empty for nonexistent term" "[]" "$(scan_reuse_candidates "zzznotathing" "$TEST_TMPDIR")"
rm -rf "$TEST_TMPDIR"

CANDS='[{"symbol":"parse_config","file":"src/config.py","line":1}]'

# Test 4: gate passes when no candidates
echo ""
echo "Test 4: gate passes with no candidates"
reuse_gate '[]' "def my_new_thing(): pass" >/dev/null 2>&1
assert "no candidates -> rc 0" "0" "$?"

# Test 5: gate passes when a candidate is referenced
echo ""
echo "Test 5: gate passes when candidate reused"
QL_QUALITY_BLOCKING=1 reuse_gate "$CANDS" "cfg = parse_config(path)" >/dev/null 2>&1
assert "candidate referenced -> rc 0" "0" "$?"

# Test 6: gate passes with a noReuseJustification marker
echo ""
echo "Test 6: gate passes with justification"
QL_QUALITY_BLOCKING=1 reuse_gate "$CANDS" "noReuseJustification: needs a streaming parser" >/dev/null 2>&1
assert "justification present -> rc 0" "0" "$?"

# Test 7: advisory by default when candidate ignored
echo ""
echo "Test 7: ignored candidate is advisory by default"
unset QL_QUALITY_BLOCKING
reuse_gate "$CANDS" "def my_own_parser(): pass" >/dev/null 2>&1
assert "ignored, env unset -> rc 0 (advisory)" "0" "$?"

# Test 8: blocking when candidate ignored under QL_QUALITY_BLOCKING
echo ""
echo "Test 8: ignored candidate blocks under QL_QUALITY_BLOCKING"
QL_QUALITY_BLOCKING=1 reuse_gate "$CANDS" "def my_own_parser(): pass" >/dev/null 2>&1
assert "ignored, blocking -> rc 1" "1" "$?"
unset QL_QUALITY_BLOCKING

echo ""
echo "=== Results: $PASS/$TOTAL passed, $FAIL failed ==="
exit $((FAIL > 0 ? 1 : 0))
