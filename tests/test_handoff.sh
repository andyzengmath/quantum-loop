#!/usr/bin/env bash
# Phase 15 / P2.3 — stage-handoff document protocol tests.

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
source "$REPO_ROOT/lib/handoff.sh"

echo "=== Phase 15 handoff-protocol tests ==="

# Test 1: write_handoff + read_handoff round-trip
echo ""
echo "Test 1: round-trip write → read"
TEST_TMPDIR=$(mktemp -d)
cd "$TEST_TMPDIR"
git init -q
git commit --allow-empty -m "init" -q
body='{
  "decided":   ["use existing auth", "scope to v1"],
  "rejected":  ["build new auth", "include v2 notifications"],
  "risks":     ["Windows long-paths"],
  "files":     ["docs/plans/x.md"],
  "remaining": ["choose DB migration"],
  "notes":     "Free-form tail."
}'
out=$(write_handoff "brainstorm" "$body" "$TEST_TMPDIR")
[[ -f "$out" ]] && { echo "  PASS: handoff file created"; PASS=$((PASS + 1)); } \
               || { echo "  FAIL: no file"; FAIL=$((FAIL + 1)); }
TOTAL=$((TOTAL + 1))
parsed=$(read_handoff "brainstorm" "$TEST_TMPDIR")
assert "stage round-trips" "brainstorm" "$(jq -r '.stage' <<< "$parsed")"
assert "decided[0] round-trips" "use existing auth" "$(jq -r '.decided[0]' <<< "$parsed")"
assert "rejected[1] round-trips" "include v2 notifications" "$(jq -r '.rejected[1]' <<< "$parsed")"
assert "risks length 1" "1" "$(jq '.risks | length' <<< "$parsed")"
assert "files[0]" "docs/plans/x.md" "$(jq -r '.files[0]' <<< "$parsed")"
assert "remaining[0]" "choose DB migration" "$(jq -r '.remaining[0]' <<< "$parsed")"
# timestamp and sha present
ts=$(jq -r '.timestamp' <<< "$parsed")
sha=$(jq -r '.sha' <<< "$parsed")
[[ -n "$ts" ]] && { echo "  PASS: timestamp non-empty"; PASS=$((PASS + 1)); } \
              || { echo "  FAIL: ts empty"; FAIL=$((FAIL + 1)); }
TOTAL=$((TOTAL + 1))
[[ -n "$sha" ]] && { echo "  PASS: sha non-empty"; PASS=$((PASS + 1)); } \
               || { echo "  FAIL: sha empty"; FAIL=$((FAIL + 1)); }
TOTAL=$((TOTAL + 1))
cd "$REPO_ROOT"; rm -rf "$TEST_TMPDIR"

# Test 2: missing handoff returns {}
echo ""
echo "Test 2: missing handoff returns empty object"
TEST_TMPDIR=$(mktemp -d)
parsed=$(read_handoff "nonexistent" "$TEST_TMPDIR")
assert "missing handoff → {}" "{}" "$parsed"
rm -rf "$TEST_TMPDIR"

# Test 3: missing fields filled with empty arrays
echo ""
echo "Test 3: sparse body fills missing fields"
TEST_TMPDIR=$(mktemp -d)
cd "$TEST_TMPDIR"
git init -q
git commit --allow-empty -m "init" -q
sparse='{"decided": ["only decision"]}'
write_handoff "spec" "$sparse" "$TEST_TMPDIR" >/dev/null
parsed=$(read_handoff "spec" "$TEST_TMPDIR")
assert "decided kept"        "only decision" "$(jq -r '.decided[0]' <<< "$parsed")"
assert "rejected empty []"   "0" "$(jq '.rejected | length' <<< "$parsed")"
assert "risks empty []"      "0" "$(jq '.risks | length' <<< "$parsed")"
assert "files empty []"      "0" "$(jq '.files | length' <<< "$parsed")"
assert "remaining empty []"  "0" "$(jq '.remaining | length' <<< "$parsed")"
cd "$REPO_ROOT"; rm -rf "$TEST_TMPDIR"

# Test 4: read_all_handoffs returns them in canonical stage order
echo ""
echo "Test 4: read_all_handoffs canonical order"
TEST_TMPDIR=$(mktemp -d)
cd "$TEST_TMPDIR"
git init -q
git commit --allow-empty -m "init" -q
# Write out of order
write_handoff "plan"       '{"decided":["plan decision"]}'       "$TEST_TMPDIR" >/dev/null
write_handoff "brainstorm" '{"decided":["brainstorm decision"]}' "$TEST_TMPDIR" >/dev/null
write_handoff "spec"       '{"decided":["spec decision"]}'       "$TEST_TMPDIR" >/dev/null
all=$(read_all_handoffs "$TEST_TMPDIR")
assert "all returns 3 handoffs" "3" "$(jq 'length' <<< "$all")"
assert "order[0] is brainstorm" "brainstorm" "$(jq -r '.[0].stage' <<< "$all")"
assert "order[1] is spec"       "spec"       "$(jq -r '.[1].stage' <<< "$all")"
assert "order[2] is plan"       "plan"       "$(jq -r '.[2].stage' <<< "$all")"
cd "$REPO_ROOT"; rm -rf "$TEST_TMPDIR"

# Test 5: list_prior_stages
echo ""
echo "Test 5: list_prior_stages"
assert "prior of brainstorm empty" "" "$(list_prior_stages brainstorm)"
assert "prior of spec"             "brainstorm" "$(list_prior_stages spec)"
assert "prior of plan"             "brainstorm spec" "$(list_prior_stages plan)"
assert "prior of execute"          "brainstorm spec plan" "$(list_prior_stages execute)"
assert "prior of review"           "brainstorm spec plan execute" "$(list_prior_stages review)"
assert "prior of verify"           "brainstorm spec plan execute review" "$(list_prior_stages verify)"

# Test 6: frontmatter shape on disk is readable YAML-ish
echo ""
echo "Test 6: written file shape"
TEST_TMPDIR=$(mktemp -d)
cd "$TEST_TMPDIR"
git init -q
git commit --allow-empty -m "init" -q
write_handoff "execute" '{"decided":["ran"],"files":["a","b"]}' "$TEST_TMPDIR" >/dev/null
content=$(cat "$TEST_TMPDIR/.handoffs/execute.md")
case "$content" in *"stage: execute"*)       echo "  PASS: stage line present";    PASS=$((PASS + 1));; *) echo "  FAIL: stage missing";    FAIL=$((FAIL + 1));; esac; TOTAL=$((TOTAL + 1))
case "$content" in *"decided:"*)              echo "  PASS: decided line present";  PASS=$((PASS + 1));; *) echo "  FAIL: decided missing";  FAIL=$((FAIL + 1));; esac; TOTAL=$((TOTAL + 1))
case "$content" in *'"a","b"'*)               echo "  PASS: files JSON serialized"; PASS=$((PASS + 1));; *) echo "  FAIL: files not serialized"; FAIL=$((FAIL + 1));; esac; TOTAL=$((TOTAL + 1))
case "$content" in *"---"*"---"*)             echo "  PASS: frontmatter fences";    PASS=$((PASS + 1));; *) echo "  FAIL: fences missing";    FAIL=$((FAIL + 1));; esac; TOTAL=$((TOTAL + 1))
cd "$REPO_ROOT"; rm -rf "$TEST_TMPDIR"

# Test 7: CLI subcommands
echo ""
echo "Test 7: CLI subcommands"
TEST_TMPDIR=$(mktemp -d)
cd "$TEST_TMPDIR"
git init -q; git commit --allow-empty -m init -q
bash "$REPO_ROOT/lib/handoff.sh" write "brainstorm" '{"decided":["x"]}' "$TEST_TMPDIR" >/dev/null
out=$(bash "$REPO_ROOT/lib/handoff.sh" read "brainstorm" "$TEST_TMPDIR" | jq -r '.decided[0]')
assert "CLI write+read round-trip" "x" "$out"
prior=$(bash "$REPO_ROOT/lib/handoff.sh" prior plan | tr -d '\n')
assert "CLI prior plan" "brainstorm spec" "$prior"
cd "$REPO_ROOT"; rm -rf "$TEST_TMPDIR"

# Test 8: Skills reference the handoff protocol
echo ""
echo "Test 8: skills wire the handoff protocol"
check_in() {
  local name="$1" needle="$2" file="$3"
  TOTAL=$((TOTAL + 1))
  if grep -qF -- "$needle" "$REPO_ROOT/$file"; then
    echo "  PASS: $name"; PASS=$((PASS + 1))
  else
    echo "  FAIL: $name — needle [$needle] not in $file"
    FAIL=$((FAIL + 1))
  fi
}
check_in "brainstorm writes handoff"             "bash lib/handoff.sh write brainstorm" "skills/ql-brainstorm/SKILL.md"
check_in "spec reads prior handoffs"             "bash lib/handoff.sh all"              "skills/ql-spec/SKILL.md"
check_in "spec writes its handoff"               "bash lib/handoff.sh write spec"       "skills/ql-spec/SKILL.md"
check_in "plan reads prior handoffs"             "bash lib/handoff.sh all"              "skills/ql-plan/SKILL.md"
check_in "plan writes its handoff"               "bash lib/handoff.sh write plan"       "skills/ql-plan/SKILL.md"
check_in "spec references brainstorm.remaining"  "brainstorm.remaining"                 "skills/ql-spec/SKILL.md"
check_in "plan references spec.decided binding"  "spec.decided"                         "skills/ql-plan/SKILL.md"

echo ""
echo "=== Results: $PASS/$TOTAL passed, $FAIL failed ==="
exit $((FAIL > 0 ? 1 : 0))
