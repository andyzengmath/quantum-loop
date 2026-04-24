#!/usr/bin/env bash
# Phase 31 / P3.1 — skeleton-first extraction / diff tests.

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
source "$REPO_ROOT/lib/skeleton.sh"

echo "=== Phase 31 skeleton tests ==="

# Test 1: extract_skeleton — TypeScript functions + class + interface + type
echo ""
echo "Test 1: TS signatures"
TEST_TMPDIR=$(mktemp -d)
cat > "$TEST_TMPDIR/app.ts" << 'EOF'
export function add(a: number, b: number): number {
  return a + b;
}
export const sub = (a: number, b: number): number => a - b;
export class Adder {
  constructor(private base: number) {}
}
export interface IAdder {
  add(x: number): number;
}
export type Pair = [number, number];
enum Color { Red, Green }
EOF
skel=$(extract_skeleton "$TEST_TMPDIR/app.ts")
assert "TS: 6 entries"     "6"          "$(jq 'length' <<< "$skel")"
assert "TS: function add"  "function"   "$(jq -r '.[] | select(.name == "add") | .kind' <<< "$skel")"
assert "TS: function sub"  "function"   "$(jq -r '.[] | select(.name == "sub") | .kind' <<< "$skel")"
assert "TS: class Adder"   "class"      "$(jq -r '.[] | select(.name == "Adder") | .kind' <<< "$skel")"
assert "TS: interface IAdder" "interface" "$(jq -r '.[] | select(.name == "IAdder") | .kind' <<< "$skel")"
assert "TS: type Pair"     "type"       "$(jq -r '.[] | select(.name == "Pair") | .kind' <<< "$skel")"
assert "TS: enum Color"    "enum"       "$(jq -r '.[] | select(.name == "Color") | .kind' <<< "$skel")"
rm -rf "$TEST_TMPDIR"

# Test 2: extract_skeleton — Python function + method + class
echo ""
echo "Test 2: Python signatures"
TEST_TMPDIR=$(mktemp -d)
cat > "$TEST_TMPDIR/app.py" << 'EOF'
def add(a: int, b: int) -> int:
    return a + b

async def fetch_data(url: str) -> dict:
    return {}

class Adder:
    def __init__(self, base: int) -> None:
        self.base = base

    def add(self, x: int) -> int:
        return self.base + x
EOF
skel=$(extract_skeleton "$TEST_TMPDIR/app.py")
assert "PY: 5 entries"    "5"        "$(jq 'length' <<< "$skel")"
assert "PY: function add"  "function" "$(jq -r '.[] | select(.name == "add" and .kind == "function") | .kind' <<< "$skel")"
assert "PY: async fetch_data" "function" "$(jq -r '.[] | select(.name == "fetch_data") | .kind' <<< "$skel")"
assert "PY: class Adder"   "class"    "$(jq -r '.[] | select(.name == "Adder") | .kind' <<< "$skel")"
# method add is distinguished from top-level function add by kind
method_count=$(jq '[.[] | select(.kind == "method")] | length' <<< "$skel")
assert "PY: 2 methods (__init__, add)" "2" "$method_count"
rm -rf "$TEST_TMPDIR"

# Test 3: extract_skeleton — Go function + method + type
echo ""
echo "Test 3: Go signatures"
TEST_TMPDIR=$(mktemp -d)
cat > "$TEST_TMPDIR/app.go" << 'EOF'
package main

func Add(a, b int) int {
    return a + b
}

func (r *Adder) Sum() int {
    return r.base
}

type Adder struct {
    base int
}

type Summer interface {
    Sum() int
}
EOF
skel=$(extract_skeleton "$TEST_TMPDIR/app.go")
assert "GO: 4 entries"        "4"          "$(jq 'length' <<< "$skel")"
assert "GO: func Add"         "function"   "$(jq -r '.[] | select(.name == "Add") | .kind' <<< "$skel")"
assert "GO: method Sum"       "method"     "$(jq -r '.[] | select(.name == "Sum") | .kind' <<< "$skel")"
assert "GO: struct Adder"     "struct"     "$(jq -r '.[] | select(.name == "Adder") | .kind' <<< "$skel")"
assert "GO: interface Summer" "interface"  "$(jq -r '.[] | select(.name == "Summer") | .kind' <<< "$skel")"
rm -rf "$TEST_TMPDIR"

# Test 4: extract_skeleton — Rust function + struct + trait + enum
echo ""
echo "Test 4: Rust signatures"
TEST_TMPDIR=$(mktemp -d)
cat > "$TEST_TMPDIR/app.rs" << 'EOF'
pub fn add(a: i32, b: i32) -> i32 {
    a + b
}

async fn fetch(url: &str) -> String {
    String::new()
}

pub struct Adder { base: i32 }

pub trait Summer { fn sum(&self) -> i32; }

pub enum Color { Red, Green }
EOF
skel=$(extract_skeleton "$TEST_TMPDIR/app.rs")
assert "RS: 5 entries"     "5"         "$(jq 'length' <<< "$skel")"
assert "RS: pub fn add"    "function"  "$(jq -r '.[] | select(.name == "add") | .kind' <<< "$skel")"
assert "RS: async fn fetch" "function" "$(jq -r '.[] | select(.name == "fetch") | .kind' <<< "$skel")"
assert "RS: struct Adder"  "struct"    "$(jq -r '.[] | select(.name == "Adder") | .kind' <<< "$skel")"
assert "RS: trait Summer"  "trait"     "$(jq -r '.[] | select(.name == "Summer") | .kind' <<< "$skel")"
assert "RS: enum Color"    "enum"      "$(jq -r '.[] | select(.name == "Color") | .kind' <<< "$skel")"
rm -rf "$TEST_TMPDIR"

# Test 5: extract_skeleton — empty / missing file
echo ""
echo "Test 5: empty / missing file handling"
skel=$(extract_skeleton "/nonexistent/foo.ts")
assert "missing file -> []" "[]" "$skel"
TEST_TMPDIR=$(mktemp -d)
: > "$TEST_TMPDIR/empty.ts"
skel=$(extract_skeleton "$TEST_TMPDIR/empty.ts")
assert "empty file -> []" "[]" "$skel"
rm -rf "$TEST_TMPDIR"

# Test 6: extract_skeleton — unknown extension falls back to []
echo ""
echo "Test 6: unknown extension"
TEST_TMPDIR=$(mktemp -d)
echo "function foo() {}" > "$TEST_TMPDIR/app.xyz"
skel=$(extract_skeleton "$TEST_TMPDIR/app.xyz")
assert "unknown ext -> []" "[]" "$skel"
# But LANG override works
skel=$(extract_skeleton "$TEST_TMPDIR/app.xyz" "ts")
assert "unknown ext + LANG=ts picks up foo" "1" "$(jq 'length' <<< "$skel")"
rm -rf "$TEST_TMPDIR"

# Test 7: skeleton_text — one signature per line, body trimmed
echo ""
echo "Test 7: skeleton_text output shape"
TEST_TMPDIR=$(mktemp -d)
cat > "$TEST_TMPDIR/a.ts" << 'EOF'
export function add(a: number): number {
  return a + 1;
}
export class Foo {
  bar(): void {}
}
EOF
text=$(skeleton_text "$TEST_TMPDIR/a.ts")
case "$text" in *"function add(a: number): number"*) echo "  PASS: function sig present"; PASS=$((PASS + 1));;
                *) echo "  FAIL: function sig missing"; FAIL=$((FAIL + 1));;
esac
TOTAL=$((TOTAL + 1))
case "$text" in *"{"*) echo "  FAIL: trailing { not stripped"; FAIL=$((FAIL + 1));;
                *) echo "  PASS: trailing { stripped from output"; PASS=$((PASS + 1));;
esac
TOTAL=$((TOTAL + 1))
rm -rf "$TEST_TMPDIR"

# Test 8: skeleton_diff — added / removed / changed
echo ""
echo "Test 8: skeleton_diff basic matching"
TEST_TMPDIR=$(mktemp -d)
cat > "$TEST_TMPDIR/before.ts" << 'EOF'
export function add(a: number, b: number): number {
  return a + b;
}
export function sub(a: number, b: number): number {
  return a - b;
}
EOF
cat > "$TEST_TMPDIR/after.ts" << 'EOF'
export function add(a: number, b: number, c: number): number {
  return a + b + c;
}
export function mul(a: number, b: number): number {
  return a * b;
}
EOF
diff_out=$(skeleton_diff "$TEST_TMPDIR/before.ts" "$TEST_TMPDIR/after.ts")
assert "added count=1"   "1"   "$(jq '.added | length' <<< "$diff_out")"
assert "added name=mul"  "mul" "$(jq -r '.added[0].name' <<< "$diff_out")"
assert "removed count=1" "1"   "$(jq '.removed | length' <<< "$diff_out")"
assert "removed name=sub" "sub" "$(jq -r '.removed[0].name' <<< "$diff_out")"
assert "changed count=1" "1"   "$(jq '.changed | length' <<< "$diff_out")"
assert "changed name=add" "add" "$(jq -r '.changed[0].name' <<< "$diff_out")"
rm -rf "$TEST_TMPDIR"

# Test 9: skeleton_diff — body-only change NOT flagged as changed
echo ""
echo "Test 9: body-only change → no skeleton drift"
TEST_TMPDIR=$(mktemp -d)
cat > "$TEST_TMPDIR/before.ts" << 'EOF'
export function add(a: number, b: number): number {
  return a + b;
}
EOF
cat > "$TEST_TMPDIR/after.ts" << 'EOF'
export function add(a: number, b: number): number {
  // pedantic comment, but signature identical
  const result = a + b;
  return result;
}
EOF
diff_out=$(skeleton_diff "$TEST_TMPDIR/before.ts" "$TEST_TMPDIR/after.ts")
assert "body-only: 0 added"   "0" "$(jq '.added | length' <<< "$diff_out")"
assert "body-only: 0 removed" "0" "$(jq '.removed | length' <<< "$diff_out")"
assert "body-only: 0 changed" "0" "$(jq '.changed | length' <<< "$diff_out")"
rm -rf "$TEST_TMPDIR"

# Test 10: skeleton_diff — across languages (Python rename)
echo ""
echo "Test 10: Python rename detected as remove+add"
TEST_TMPDIR=$(mktemp -d)
cat > "$TEST_TMPDIR/before.py" << 'EOF'
def calculate(x: int) -> int:
    return x * 2
EOF
cat > "$TEST_TMPDIR/after.py" << 'EOF'
def compute(x: int) -> int:
    return x * 2
EOF
diff_out=$(skeleton_diff "$TEST_TMPDIR/before.py" "$TEST_TMPDIR/after.py")
assert "py rename: 1 added"   "1" "$(jq '.added | length' <<< "$diff_out")"
assert "py rename: 1 removed" "1" "$(jq '.removed | length' <<< "$diff_out")"
assert "py added=compute"     "compute"   "$(jq -r '.added[0].name' <<< "$diff_out")"
assert "py removed=calculate" "calculate" "$(jq -r '.removed[0].name' <<< "$diff_out")"
rm -rf "$TEST_TMPDIR"

# Test 11: extract_skeleton — signature includes return type
echo ""
echo "Test 11: return-type preserved in signature"
TEST_TMPDIR=$(mktemp -d)
cat > "$TEST_TMPDIR/t.ts" << 'EOF'
export function stringify(n: number): string {
  return String(n);
}
EOF
skel=$(extract_skeleton "$TEST_TMPDIR/t.ts")
sig=$(jq -r '.[0].signature' <<< "$skel")
case "$sig" in *"string"*) echo "  PASS: return type 'string' preserved"; PASS=$((PASS + 1));;
                *) echo "  FAIL: return type missing from sig: $sig"; FAIL=$((FAIL + 1));;
esac
TOTAL=$((TOTAL + 1))
rm -rf "$TEST_TMPDIR"

# Test 12: CLI subcommands
echo ""
echo "Test 12: CLI subcommands"
TEST_TMPDIR=$(mktemp -d)
cat > "$TEST_TMPDIR/a.ts" << 'EOF'
export function only(): void {}
EOF
cat > "$TEST_TMPDIR/b.ts" << 'EOF'
export function only(): void {}
export function extra(x: number): number { return x; }
EOF
cli_ex=$(bash "$REPO_ROOT/lib/skeleton.sh" extract "$TEST_TMPDIR/a.ts")
assert "CLI extract count=1" "1" "$(jq 'length' <<< "$cli_ex")"
cli_text=$(bash "$REPO_ROOT/lib/skeleton.sh" text "$TEST_TMPDIR/a.ts")
case "$cli_text" in *"only"*) echo "  PASS: CLI text contains name"; PASS=$((PASS + 1));;
                    *) echo "  FAIL: CLI text missing name"; FAIL=$((FAIL + 1));;
esac
TOTAL=$((TOTAL + 1))
cli_diff=$(bash "$REPO_ROOT/lib/skeleton.sh" diff "$TEST_TMPDIR/a.ts" "$TEST_TMPDIR/b.ts")
assert "CLI diff added=1" "1" "$(jq '.added | length' <<< "$cli_diff")"
rm -rf "$TEST_TMPDIR"

# Test 13: extract_skeleton — does NOT pick up call sites as signatures
echo ""
echo "Test 13: call sites are not signatures"
TEST_TMPDIR=$(mktemp -d)
cat > "$TEST_TMPDIR/calls.ts" << 'EOF'
import { foo } from './foo';
foo();
const r = foo();
EOF
skel=$(extract_skeleton "$TEST_TMPDIR/calls.ts")
# `const r = foo()` does NOT match our arrow-function regex (no =>), so
# it should NOT be extracted as a function declaration.
sigs=$(jq 'length' <<< "$skel")
# It's OK if the extractor returns 0. If the regex happens to match
# `const r = foo()` as const+name+=(, flag this as a false positive.
TOTAL=$((TOTAL + 1))
if [[ "$sigs" -eq 0 ]]; then
  echo "  PASS: no false positives from call sites"; PASS=$((PASS + 1))
else
  echo "  FAIL: $sigs entries — check regex precision"; FAIL=$((FAIL + 1))
  jq '.' <<< "$skel" | head -6 | sed 's/^/    /'
fi
rm -rf "$TEST_TMPDIR"

echo ""
echo "=== Results: $PASS/$TOTAL passed, $FAIL failed ==="
exit $((FAIL > 0 ? 1 : 0))
