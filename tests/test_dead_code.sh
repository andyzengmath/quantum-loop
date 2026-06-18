#!/usr/bin/env bash
# Phase 33 / P3.10 — dead-code post-generation detection tests.

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
source "$REPO_ROOT/lib/dead-code.sh"

echo "=== Phase 33 dead-code tests ==="

# Test 1: TS — unused default import flagged
echo ""
echo "Test 1: TS default import"
TEST_TMPDIR=$(mktemp -d)
cat > "$TEST_TMPDIR/a.ts" << 'EOF'
import used from 'used-mod';
import unused from 'unused-mod';
export function go(): void {
  used();
}
EOF
out=$(scan_unused_imports "$TEST_TMPDIR/a.ts")
assert "TS: 1 unused import"  "1"       "$(jq 'length' <<< "$out")"
assert "TS: name=unused"      "unused"  "$(jq -r '.[0].name' <<< "$out")"
rm -rf "$TEST_TMPDIR"

# Test 2: TS — named-import destructuring (partial)
echo ""
echo "Test 2: TS named imports (only some unused)"
TEST_TMPDIR=$(mktemp -d)
cat > "$TEST_TMPDIR/a.ts" << 'EOF'
import { alpha, beta, gamma } from 'lib';
export function go(): number {
  return alpha + gamma;
}
EOF
out=$(scan_unused_imports "$TEST_TMPDIR/a.ts")
assert "TS: only 'beta' flagged (1)" "1"      "$(jq 'length' <<< "$out")"
assert "TS: name=beta"               "beta"   "$(jq -r '.[0].name' <<< "$out")"
rm -rf "$TEST_TMPDIR"

# Test 3: TS — "import X as Y" tracks Y
echo ""
echo "Test 3: TS rename alias"
TEST_TMPDIR=$(mktemp -d)
cat > "$TEST_TMPDIR/a.ts" << 'EOF'
import { original as renamed } from 'lib';
export function go(): number {
  return renamed;
}
EOF
out=$(scan_unused_imports "$TEST_TMPDIR/a.ts")
assert "TS: alias tracks local binding (0 unused)" "0" "$(jq 'length' <<< "$out")"
rm -rf "$TEST_TMPDIR"

# Test 4: TS — namespace import (* as foo)
echo ""
echo "Test 4: TS namespace"
TEST_TMPDIR=$(mktemp -d)
cat > "$TEST_TMPDIR/a.ts" << 'EOF'
import * as utils from 'utils';
export function go(): void {
  utils.foo();
}
EOF
out=$(scan_unused_imports "$TEST_TMPDIR/a.ts")
assert "TS: namespace used (0 unused)" "0" "$(jq 'length' <<< "$out")"
rm -rf "$TEST_TMPDIR"

# Test 5: Python — unused import flagged
echo ""
echo "Test 5: Python import"
TEST_TMPDIR=$(mktemp -d)
cat > "$TEST_TMPDIR/a.py" << 'EOF'
import used_mod
import unused_mod
from lib import alpha, beta
from other import gamma as g
def main():
    used_mod.run()
    print(alpha, g)
EOF
out=$(scan_unused_imports "$TEST_TMPDIR/a.py")
count=$(jq 'length' <<< "$out")
# Expected unused: unused_mod, beta
# Used: used_mod (used_mod.run), alpha (print(alpha,...)), g (alias of gamma)
assert "PY: 2 unused imports" "2" "$count"
# Check names
names=$(jq -r '[.[].name] | sort | join(",")' <<< "$out")
assert "PY: names = beta,unused_mod" "beta,unused_mod" "$names"
rm -rf "$TEST_TMPDIR"

# Test 6: Python — `from x import y as z` tracks z
echo ""
echo "Test 6: PY rename alias"
TEST_TMPDIR=$(mktemp -d)
cat > "$TEST_TMPDIR/a.py" << 'EOF'
from m import original as renamed
def main():
    return renamed()
EOF
out=$(scan_unused_imports "$TEST_TMPDIR/a.py")
assert "PY: alias tracked (0 unused)" "0" "$(jq 'length' <<< "$out")"
rm -rf "$TEST_TMPDIR"

# Test 7: Go — unused import flagged (blank import preserved)
echo ""
echo "Test 7: Go imports"
TEST_TMPDIR=$(mktemp -d)
cat > "$TEST_TMPDIR/a.go" << 'EOF'
package main

import (
    "fmt"
    "strings"
    _ "sideeffect"
)

func main() {
    fmt.Println("hi")
}
EOF
out=$(scan_unused_imports "$TEST_TMPDIR/a.go")
# strings unused; fmt used; _ sideeffect is intentional, skip
count=$(jq 'length' <<< "$out")
assert "Go: 1 unused (strings)" "1" "$count"
assert "Go: name=strings" "strings" "$(jq -r '.[0].name' <<< "$out")"
rm -rf "$TEST_TMPDIR"

# Test 8: Rust — unused `use`
echo ""
echo "Test 8: Rust use"
TEST_TMPDIR=$(mktemp -d)
cat > "$TEST_TMPDIR/a.rs" << 'EOF'
use std::collections::HashMap;
use std::fs::File;

fn main() {
    let m: HashMap<i32, i32> = HashMap::new();
    drop(m);
}
EOF
out=$(scan_unused_imports "$TEST_TMPDIR/a.rs")
assert "RS: 1 unused (File)" "1" "$(jq 'length' <<< "$out")"
assert "RS: name=File"       "File" "$(jq -r '.[0].name' <<< "$out")"
rm -rf "$TEST_TMPDIR"

# Test 9: scan_unused_privates — TS private fn never called
echo ""
echo "Test 9: TS private helpers"
TEST_TMPDIR=$(mktemp -d)
cat > "$TEST_TMPDIR/a.ts" << 'EOF'
function _used(): number { return 1; }
function _orphan(): number { return 2; }
const _var_used = 3;
const _var_orphan = 4;
export function go(): number {
  return _used() + _var_used;
}
EOF
out=$(scan_unused_privates "$TEST_TMPDIR/a.ts")
names=$(jq -r '[.[].name] | sort | join(",")' <<< "$out")
assert "TS: 2 orphans flagged" "2" "$(jq 'length' <<< "$out")"
assert "TS: names = _orphan,_var_orphan" "_orphan,_var_orphan" "$names"
rm -rf "$TEST_TMPDIR"

# Test 10: scan_unused_privates — exported private names are NOT flagged
echo ""
echo "Test 10: exported private NOT flagged"
TEST_TMPDIR=$(mktemp -d)
cat > "$TEST_TMPDIR/a.ts" << 'EOF'
export function _intentional(): void {}
EOF
out=$(scan_unused_privates "$TEST_TMPDIR/a.ts")
assert "export _intentional not flagged" "0" "$(jq 'length' <<< "$out")"
rm -rf "$TEST_TMPDIR"

# Test 11: Python private fn
echo ""
echo "Test 11: PY private helpers"
TEST_TMPDIR=$(mktemp -d)
cat > "$TEST_TMPDIR/a.py" << 'EOF'
def _used():
    return 1

def _orphan():
    return 2

def main():
    return _used()
EOF
out=$(scan_unused_privates "$TEST_TMPDIR/a.py")
assert "PY: 1 orphan" "1" "$(jq 'length' <<< "$out")"
assert "PY: name=_orphan" "_orphan" "$(jq -r '.[0].name' <<< "$out")"
rm -rf "$TEST_TMPDIR"

# Test 12: scan_dead_code — aggregation over directory
echo ""
echo "Test 12: scan_dead_code directory walk"
TEST_TMPDIR=$(mktemp -d)
mkdir -p "$TEST_TMPDIR/src"
cat > "$TEST_TMPDIR/src/a.ts" << 'EOF'
import unused_ts from 'foo';
function _ts_orphan(): void {}
export function go(): void {}
EOF
cat > "$TEST_TMPDIR/src/b.py" << 'EOF'
import unused_py
def _py_orphan(): pass
def main(): pass
EOF
agg=$(scan_dead_code "$TEST_TMPDIR/src")
imp_ct=$(jq '.summary.by_kind.import' <<< "$agg")
priv_ct=$(jq '.summary.by_kind.private' <<< "$agg")
total_ct=$(jq '.summary.total' <<< "$agg")
assert "aggregate imports=2"  "2" "$imp_ct"
assert "aggregate privates=2" "2" "$priv_ct"
assert "aggregate total=4"    "4" "$total_ct"
rm -rf "$TEST_TMPDIR"

# Test 13: scan_dead_code — file with no dead code
echo ""
echo "Test 13: clean file has 0 findings"
TEST_TMPDIR=$(mktemp -d)
cat > "$TEST_TMPDIR/a.ts" << 'EOF'
import x from 'used';
export function go(): void { x(); }
EOF
agg=$(scan_dead_code "$TEST_TMPDIR/a.ts")
assert "clean: total=0" "0" "$(jq '.summary.total' <<< "$agg")"
rm -rf "$TEST_TMPDIR"

# Test 14: scan_dead_code — missing path
echo ""
echo "Test 14: missing path handling"
agg=$(scan_dead_code "/nonexistent/xyz")
assert "missing: total=0"    "0"  "$(jq '.summary.total' <<< "$agg")"
assert "missing: imports=[]" "[]" "$(jq -c '.unused_imports' <<< "$agg")"

# Test 15: find_post_commit_dead — scan files between two commits
echo ""
echo "Test 15: find_post_commit_dead git-diff driven"
TEST_TMPDIR=$(mktemp -d)
(
  cd "$TEST_TMPDIR"
  git init -q
  git config user.email "t@t.t"
  git config user.name "t"
  # Initial commit
  echo 'export function go(): void {}' > clean.ts
  git add -A; git commit -qm init
  BASE=$(git rev-parse HEAD)
  # Change: add a file with dead code
  cat > new.ts << 'EOF'
import unused from 'bar';
function _orphan(): void {}
export function go(): void {}
EOF
  git add -A; git commit -qm add-dead
  HEAD=$(git rev-parse HEAD)
  agg=$(find_post_commit_dead "$BASE" "$HEAD")
  if [[ "$(jq '.summary.total' <<< "$agg")" == "2" ]]; then
    echo "  PASS: post-commit detected 2 dead (1 import + 1 private)"
  else
    echo "  FAIL: post-commit detection — got $(jq '.summary' <<< "$agg")"
    exit 1
  fi
)
rc=$?
TOTAL=$((TOTAL + 1))
if [[ "$rc" -eq 0 ]]; then PASS=$((PASS + 1)); else FAIL=$((FAIL + 1)); fi
rm -rf "$TEST_TMPDIR"

# Test 16: CLI subcommands
echo ""
echo "Test 16: CLI subcommands"
TEST_TMPDIR=$(mktemp -d)
cat > "$TEST_TMPDIR/a.ts" << 'EOF'
import unused from 'x';
export function go(): void {}
EOF
cli_imp=$(bash "$REPO_ROOT/lib/dead-code.sh" imports "$TEST_TMPDIR/a.ts")
assert "CLI imports count=1" "1" "$(jq 'length' <<< "$cli_imp")"
cli_scan=$(bash "$REPO_ROOT/lib/dead-code.sh" scan "$TEST_TMPDIR/a.ts")
assert "CLI scan total=1" "1" "$(jq '.summary.total' <<< "$cli_scan")"
rm -rf "$TEST_TMPDIR"

# Test 17: unknown extension falls back to []
echo ""
echo "Test 17: unknown extension"
TEST_TMPDIR=$(mktemp -d)
echo "import foo" > "$TEST_TMPDIR/a.xyz"
out=$(scan_unused_imports "$TEST_TMPDIR/a.xyz")
assert "unknown ext imports=[]" "[]" "$out"
out=$(scan_unused_privates "$TEST_TMPDIR/a.xyz")
assert "unknown ext privates=[]" "[]" "$out"
rm -rf "$TEST_TMPDIR"

# Test 18-21: Track A Q4 — opt-in blocking verdict (dead_code_blocking_verdict)
R_IMP='{"summary":{"total":1,"by_kind":{"import":1,"private":0}}}'
R_PRIV='{"summary":{"total":1,"by_kind":{"import":0,"private":1}}}'
R_CLEAN='{"summary":{"total":0,"by_kind":{"import":0,"private":0}}}'

echo ""
echo "Test 18: verdict advisory by default (env unset)"
unset QL_QUALITY_BLOCKING
dead_code_blocking_verdict "$R_IMP" >/dev/null 2>&1
assert "default: imports>0 -> rc 0 (advisory)" "0" "$?"

echo ""
echo "Test 19: blocking on unused new import"
QL_QUALITY_BLOCKING=1 dead_code_blocking_verdict "$R_IMP" >/dev/null 2>&1
assert "blocking: imports>0 -> rc 1" "1" "$?"

echo ""
echo "Test 20: privates stay advisory under blocking"
QL_QUALITY_BLOCKING=1 dead_code_blocking_verdict "$R_PRIV" >/dev/null 2>&1
assert "blocking: privates-only -> rc 0" "0" "$?"

echo ""
echo "Test 21: clean report passes under blocking"
QL_QUALITY_BLOCKING=1 dead_code_blocking_verdict "$R_CLEAN" >/dev/null 2>&1
assert "blocking: clean -> rc 0" "0" "$?"
unset QL_QUALITY_BLOCKING

echo ""
echo "=== Results: $PASS/$TOTAL passed, $FAIL failed ==="
exit $((FAIL > 0 ? 1 : 0))
