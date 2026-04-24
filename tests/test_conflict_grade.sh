#!/usr/bin/env bash
# Phase 26 / P3.2 — conflict-grade tests.

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
source "$REPO_ROOT/lib/conflict-grade.sh"

echo "=== Phase 26 conflict-grade tests ==="

# Test 1: Grade 1 — whitespace-only difference
echo ""
echo "Test 1: whitespace-only → grade 1"
g=$(grade_hunk_text "let x = 42" "let x  =  42")
assert "single-ws diff" "1" "$g"
g=$(grade_hunk_text $'function a() {\n  return 1\n}' $'function a(){\nreturn 1\n}')
assert "bracket-indent diff" "1" "$g"

# Test 2: Grade 2 — comment-only change
echo ""
echo "Test 2: comment-only → grade 2"
g=$(grade_hunk_text "let x = 42 // old" "let x = 42 // new")
assert "line comment change" "2" "$g"
g=$(grade_hunk_text "let x = 42 # the answer" "let x = 42 # the truth")
assert "python-style comment change" "2" "$g"
g=$(grade_hunk_text "let x = 42 /* A */" "let x = 42 /* B */")
assert "block comment change" "2" "$g"

# Test 3: Grade 2 — single-token rename
echo ""
echo "Test 3: single-token rename → grade 2"
g=$(grade_hunk_text "const count = 5" "const total = 5")
assert "single identifier rename" "2" "$g"

# Test 4: Grade 3 — small body edit (≤5 non-empty lines each side)
echo ""
echo "Test 4: small body edit → grade 3"
g=$(grade_hunk_text $'foo(1)\nbar(2)' $'baz(1)\nqux(2)\nquux(3)')
assert "3-line small body edit" "3" "$g"

# Test 5: Grade 4 — moderate overlap (>5 lines, same region)
echo ""
echo "Test 5: moderate overlap → grade 4"
ours=$'a=1\nb=2\nc=3\nd=4\ne=5\nf=6\ng=7'
theirs=$'A=1\nB=2\nC=3\nD=4\nE=5\nF=6\nG=7'
g=$(grade_hunk_text "$ours" "$theirs")
assert "7-line overlap" "4" "$g"

# Test 6: Grade 5 — structural (≥2 function boundaries)
echo ""
echo "Test 6: structural reorg → grade 5"
ours=$'function alpha() { return 1 }\nfunction beta() { return 2 }'
theirs=$'function beta() { return 2 }\nfunction alpha() { return 1 }'
g=$(grade_hunk_text "$ours" "$theirs")
assert "2-function reorder" "5" "$g"
# Python variant
ours_py=$'def alpha():\n    pass\ndef beta():\n    pass'
theirs_py=$'def gamma():\n    pass\ndef delta():\n    pass'
g=$(grade_hunk_text "$ours_py" "$theirs_py")
assert "2-def reorg (python)" "5" "$g"

# Test 7: split_conflict_hunks — single conflict
echo ""
echo "Test 7: split_conflict_hunks single"
TEST_TMPDIR=$(mktemp -d)
cat > "$TEST_TMPDIR/file.txt" << 'EOF'
line before
<<<<<<< HEAD
our version line 1
our version line 2
=======
their version line 1
>>>>>>> branch
line after
EOF
hunks=$(split_conflict_hunks "$TEST_TMPDIR/file.txt")
count=$(printf '%s' "$hunks" | jq 'length')
assert "1 conflict parsed" "1" "$count"
ours=$(printf '%s' "$hunks" | jq -r '.[0].ours')
theirs=$(printf '%s' "$hunks" | jq -r '.[0].theirs')
case "$ours" in *"our version line 1"*"our version line 2"*) echo "  PASS: ours buffer captured"; PASS=$((PASS + 1));;
                *) echo "  FAIL: ours=[$ours]"; FAIL=$((FAIL + 1));;
esac
TOTAL=$((TOTAL + 1))
case "$theirs" in *"their version line 1"*) echo "  PASS: theirs buffer captured"; PASS=$((PASS + 1));;
                  *) echo "  FAIL: theirs=[$theirs]"; FAIL=$((FAIL + 1));;
esac
TOTAL=$((TOTAL + 1))
start=$(printf '%s' "$hunks" | jq -r '.[0].start_line')
end=$(printf '%s' "$hunks" | jq -r '.[0].end_line')
assert "start_line=2" "2" "$start"
assert "end_line=7" "7" "$end"
rm -rf "$TEST_TMPDIR"

# Test 8: split_conflict_hunks — multiple conflicts
echo ""
echo "Test 8: split_conflict_hunks multiple"
TEST_TMPDIR=$(mktemp -d)
cat > "$TEST_TMPDIR/file.txt" << 'EOF'
a
<<<<<<< HEAD
x
=======
y
>>>>>>> b
middle
<<<<<<< HEAD
p
=======
q
>>>>>>> b
end
EOF
hunks=$(split_conflict_hunks "$TEST_TMPDIR/file.txt")
count=$(printf '%s' "$hunks" | jq 'length')
assert "2 conflicts parsed" "2" "$count"
rm -rf "$TEST_TMPDIR"

# Test 9: grade_file — end-to-end with mixed grades
echo ""
echo "Test 9: grade_file end-to-end"
TEST_TMPDIR=$(mktemp -d)
cat > "$TEST_TMPDIR/file.ts" << 'EOF'
line 1
<<<<<<< HEAD
let x = 42 // old comment
=======
let x = 42 // new comment
>>>>>>> branch
middle
<<<<<<< HEAD
function alpha() { return 1 }
function beta() { return 2 }
=======
function gamma() { return 3 }
function delta() { return 4 }
>>>>>>> branch
end
EOF
graded=$(grade_file "$TEST_TMPDIR/file.ts")
max_g=$(printf '%s' "$graded" | jq -r '.max_grade')
n_hunks=$(printf '%s' "$graded" | jq -r '.hunks | length')
assert "2 hunks graded" "2" "$n_hunks"
assert "max_grade = 5 (structural)" "5" "$max_g"
first_grade=$(printf '%s' "$graded" | jq -r '.hunks[0].grade')
second_grade=$(printf '%s' "$graded" | jq -r '.hunks[1].grade')
assert "first hunk grade 2 (comment)" "2" "$first_grade"
assert "second hunk grade 5 (structural)" "5" "$second_grade"
rm -rf "$TEST_TMPDIR"

# Test 10: grade_file — no conflicts
echo ""
echo "Test 10: grade_file clean file"
TEST_TMPDIR=$(mktemp -d)
echo "no conflicts here" > "$TEST_TMPDIR/clean.txt"
graded=$(grade_file "$TEST_TMPDIR/clean.txt")
max_g=$(printf '%s' "$graded" | jq -r '.max_grade')
n_hunks=$(printf '%s' "$graded" | jq -r '.hunks | length')
assert "clean file max_grade=0" "0" "$max_g"
assert "clean file 0 hunks" "0" "$n_hunks"
rm -rf "$TEST_TMPDIR"

# Test 11: routing_recommendation
echo ""
echo "Test 11: routing_recommendation"
assert "grade 0 → none"      "none"      "$(routing_recommendation 0)"
assert "grade 1 → auto-git"  "auto-git"  "$(routing_recommendation 1)"
assert "grade 2 → auto-git"  "auto-git"  "$(routing_recommendation 2)"
assert "grade 3 → diff3"     "diff3"     "$(routing_recommendation 3)"
assert "grade 4 → llm-merge" "llm-merge" "$(routing_recommendation 4)"
assert "grade 5 → escalate"  "escalate"  "$(routing_recommendation 5)"

# Test 12: CLI subcommands
echo ""
echo "Test 12: CLI subcommands"
TEST_TMPDIR=$(mktemp -d)
cat > "$TEST_TMPDIR/f.txt" << 'EOF'
<<<<<<< HEAD
foo
=======
bar
>>>>>>> b
EOF
cli_graded=$(bash "$REPO_ROOT/lib/conflict-grade.sh" grade "$TEST_TMPDIR/f.txt")
mg=$(printf '%s' "$cli_graded" | jq -r '.max_grade')
# single word rename — grade 2
assert "CLI grade single-word rename" "2" "$mg"
route=$(bash "$REPO_ROOT/lib/conflict-grade.sh" route 4 | tr -d '\n')
assert "CLI route 4 → llm-merge" "llm-merge" "$route"
rm -rf "$TEST_TMPDIR"

echo ""
echo "=== Results: $PASS/$TOTAL passed, $FAIL failed ==="
exit $((FAIL > 0 ? 1 : 0))
