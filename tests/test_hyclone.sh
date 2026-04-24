#!/usr/bin/env bash
# Phase 25 / P3.7 — HyClone Stage-1 fingerprint tests.

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
source "$REPO_ROOT/lib/hyclone.sh"

echo "=== Phase 25 HyClone Stage-1 tests ==="

# Test 1: alpha_normalize — whitespace collapse + identifier rename
# Note: aggressive normalization drops spaces adjacent to non-word chars,
# keeping only single spaces between two word-character runs (e.g.
# "return x" stays "return _v0" but "x = 42" becomes "_v0=42").
echo ""
echo "Test 1: alpha_normalize basics"
n1=$(alpha_normalize "let x = 42")
# "let " (word to word-space-word), " x " (word), "= 42" (eq drops spaces)
assert "whitespace-only renames x" "let _v0=42" "$n1"
n2=$(alpha_normalize "let  x   =   42")
assert "extra whitespace collapsed" "let _v0=42" "$n2"
n3=$(alpha_normalize "let x = y + z")
assert "multiple identifiers numbered" "let _v0=_v1+_v2" "$n3"

# Test 2: alpha_normalize — repeated identifiers get same placeholder
echo ""
echo "Test 2: repeated identifiers reuse placeholder"
n=$(alpha_normalize "let x = x + 1; let y = x")
assert "repeated identifier reuses placeholder" "let _v0=_v0+1;let _v1=_v0" "$n"

# Test 3: alpha_normalize — keywords not renamed
echo ""
echo "Test 3: keywords preserved"
n=$(alpha_normalize "if x then return true else return false")
assert "keywords preserved" "if _v0 then return true else return false" "$n"

# Test 4: alpha_normalize — comments stripped
echo ""
echo "Test 4: comments stripped"
n=$(alpha_normalize "let x = 5 // the answer")
assert "line comment // stripped" "let _v0=5" "$n"
n=$(alpha_normalize "let y = 10 # comment here")
assert "line comment # stripped" "let _v0=10" "$n"
n=$(alpha_normalize "let /* unused */ z = 7")
assert "block comment stripped" "let _v0=7" "$n"

# Test 5: alpha_normalize — strings not renamed
echo ""
echo "Test 5: string literals preserved"
n=$(alpha_normalize 'let msg = "hello world"')
assert "double-quoted string preserved" 'let _v0="hello world"' "$n"
n=$(alpha_normalize "let m = 'single quotes'")
assert "single-quoted string preserved" "let _v0='single quotes'" "$n"

# Test 6: fingerprint — same content, different names → same hash
echo ""
echo "Test 6: clone fingerprints match"
f1=$(fingerprint "function add(a, b) { return a + b }")
f2=$(fingerprint "function sum(x, y) { return x + y }")
assert "different names → same fingerprint" "$f1" "$f2"
# Different whitespace
f3=$(fingerprint "function add(a,b){return a+b}")
assert "different whitespace → same fingerprint" "$f1" "$f3"

# Test 7: fingerprint — truly different behavior → different hash
echo ""
echo "Test 7: semantic difference → different fingerprints"
f_add=$(fingerprint "function add(a, b) { return a + b }")
f_sub=$(fingerprint "function sub(a, b) { return a - b }")
TOTAL=$((TOTAL + 1))
if [[ "$f_add" != "$f_sub" ]]; then
  echo "  PASS: operator difference changes fingerprint"; PASS=$((PASS + 1))
else
  echo "  FAIL: add vs sub collided"; FAIL=$((FAIL + 1))
fi
# Different control flow
f_loop=$(fingerprint "while (x > 0) { x = x - 1 }")
f_if=$(fingerprint "if (x > 0) { x = x - 1 }")
TOTAL=$((TOTAL + 1))
if [[ "$f_loop" != "$f_if" ]]; then
  echo "  PASS: while vs if different"; PASS=$((PASS + 1))
else
  echo "  FAIL: while and if collided"; FAIL=$((FAIL + 1))
fi

# Test 8: find_clones — groups ≥2-member candidates
echo ""
echo "Test 8: find_clones detects a clone pair"
input='[
  {"id":"fnA","body":"function add(a, b) { return a + b }"},
  {"id":"fnB","body":"function sum(x, y) { return x + y }"},
  {"id":"fnC","body":"function mul(a, b) { return a * b }"}
]'
out=$(find_clones "$input")
groups=$(printf '%s' "$out" | jq 'length')
assert "finds 1 clone group" "1" "$groups"
members=$(printf '%s' "$out" | jq -r '.[0].members | length')
assert "group has 2 members" "2" "$members"
# Members should be fnA and fnB
contains_A=$(printf '%s' "$out" | jq '.[0].members | contains(["fnA"])')
contains_B=$(printf '%s' "$out" | jq '.[0].members | contains(["fnB"])')
contains_C=$(printf '%s' "$out" | jq '.[0].members | contains(["fnC"])')
assert "fnA in clone group" "true" "$contains_A"
assert "fnB in clone group" "true" "$contains_B"
assert "fnC NOT in clone group" "false" "$contains_C"

# Test 9: find_clones — no clones
echo ""
echo "Test 9: find_clones with all unique functions"
input='[
  {"id":"fn1","body":"function a() { return 1 }"},
  {"id":"fn2","body":"function b() { return 2 }"},
  {"id":"fn3","body":"function c() { return 3 }"}
]'
out=$(find_clones "$input")
groups=$(printf '%s' "$out" | jq 'length')
assert "no clone groups" "0" "$groups"

# Test 10: find_clones — 3-way clone (triple)
echo ""
echo "Test 10: find_clones with triple"
input='[
  {"id":"a","body":"function one(x) { return x * 2 }"},
  {"id":"b","body":"function two(y) { return y * 2 }"},
  {"id":"c","body":"function three(z) { return z * 2 }"}
]'
out=$(find_clones "$input")
groups=$(printf '%s' "$out" | jq 'length')
members=$(printf '%s' "$out" | jq -r '.[0].members | length')
assert "3-way clone grouped" "1" "$groups"
assert "triple has 3 members" "3" "$members"

# Test 11: CLI subcommands
echo ""
echo "Test 11: CLI subcommands"
cli_norm=$(bash "$REPO_ROOT/lib/hyclone.sh" normalize "let x = 42" | tr -d '\n')
assert "CLI normalize" "let _v0=42" "$cli_norm"
cli_fp=$(bash "$REPO_ROOT/lib/hyclone.sh" fingerprint "let x = 42" | tr -d '\n')
# Sha256 = 64 hex chars
TOTAL=$((TOTAL + 1))
if [[ "${#cli_fp}" -eq 64 ]]; then
  echo "  PASS: CLI fingerprint is 64 hex chars"; PASS=$((PASS + 1))
else
  echo "  FAIL: CLI fp length [${#cli_fp}]"; FAIL=$((FAIL + 1))
fi

# Test 12: strings containing comment markers are preserved
# (The aggressive whitespace-strip post-process collapses spaces adjacent
# to non-word chars even inside strings — acceptable for clone-detection
# since "a b" and "a  b" should map to the same fingerprint.)
echo ""
echo "Test 12: comment markers inside string literals not treated as comments"
# URL in double-quoted string
n=$(alpha_normalize 'let url = "http://example.com" // real comment')
assert "URL preserved, trailing double-slash stripped" 'let _v0="http://example.com"' "$n"
# Regex-like in single-quoted string
n=$(alpha_normalize "let re = '/foo/bar/' # trailing")
assert "regex preserved, trailing hash stripped" "let _v0='/foo/bar/'" "$n"
# Block-comment start inside string should NOT enter block-comment state
# (spaces adjacent to punctuation collapse — that's the aggressive strip,
# not the comment bug we're fixing; the important check is the content
# after */ survives.)
n=$(alpha_normalize 'let s = "/* not a comment */"')
assert "block markers in string do not consume rest" 'let _v0="/*not a comment*/"' "$n"
# Escaped quote inside string does not end string
n=$(alpha_normalize 'let s = "he said \"hi\" // nope"')
assert "escaped quotes do not terminate string" 'let _v0="he said\"hi\"//nope"' "$n"
# Two snippets with same logic but different URL strings should produce
# different fingerprints (the URLs themselves differ post-strip).
f1=$(fingerprint 'fetch("http://a.com/api")')
f2=$(fingerprint 'fetch("http://b.net/api")')
TOTAL=$((TOTAL + 1))
if [[ "$f1" != "$f2" ]]; then
  echo "  PASS: different URLs -> different fingerprints (Stage-2 would catch)"; PASS=$((PASS + 1))
else
  echo "  FAIL: different URLs collided"; FAIL=$((FAIL + 1))
fi

# Test 13: empty input -> empty output
echo ""
echo "Test 13: empty input handling"
n=$(alpha_normalize "")
assert "empty normalize -> empty" "" "$n"
out=$(find_clones "[]")
assert "empty find_clones -> []" "[]" "$out"

echo ""
echo "=== Results: $PASS/$TOTAL passed, $FAIL failed ==="
exit $((FAIL > 0 ? 1 : 0))
