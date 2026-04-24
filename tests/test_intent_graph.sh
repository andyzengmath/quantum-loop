#!/usr/bin/env bash
# Phase 32 / P3.6 — semantic intent graph tests.

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
source "$REPO_ROOT/lib/intent-graph.sh"

echo "=== Phase 32 intent-graph tests ==="

# Test 1: _decompose_function_name — camelCase and snake_case
echo ""
echo "Test 1: function name decomposition"
assert "camelCase: getUserById"     "get user by id" "$(_decompose_function_name "getUserById")"
assert "snake_case: create_order"   "create order"   "$(_decompose_function_name "create_order")"
assert "mixed: fetch_data_v2"       "fetch data v2"  "$(_decompose_function_name "fetch_data_v2")"
assert "single: validate"           "validate"       "$(_decompose_function_name "validate")"

# Test 2: _is_verb
echo ""
echo "Test 2: verb detection"
_is_verb "create" && echo "  PASS: create is verb" && PASS=$((PASS + 1)) || { echo "  FAIL: create not detected"; FAIL=$((FAIL + 1)); }
TOTAL=$((TOTAL + 1))
_is_verb "delete" && echo "  PASS: delete is verb" && PASS=$((PASS + 1)) || { echo "  FAIL"; FAIL=$((FAIL + 1)); }
TOTAL=$((TOTAL + 1))
_is_verb "hamburger" && { echo "  FAIL: hamburger flagged as verb"; FAIL=$((FAIL + 1)); } || echo "  PASS: hamburger not a verb (PASS=$((++PASS)))"
TOTAL=$((TOTAL + 1))

# Test 3: extract_story_intents — basic description
echo ""
echo "Test 3: extract intents from story description"
story=$(jq -cn '{
  title: "Widget delete endpoint",
  description: "Users should be able to delete expired tokens and create new sessions.",
  acceptanceCriteria: ["System must validate the session token", "System sends welcome email"],
  tasks: [{description: "Add route to remove stale records"}]
}')
intents=$(extract_story_intents "$story")
count=$(jq 'length' <<< "$intents")
# Expected triples: delete tokens, create sessions (from desc), validate token (from AC),
# sends welcome email (from AC), remove stale records (from task).
# Plus "delete endpoint" from title.
TOTAL=$((TOTAL + 1))
if (( count >= 5 )); then
  echo "  PASS: extracted $count intents (>=5 expected)"; PASS=$((PASS + 1))
else
  echo "  FAIL: expected >=5 intents, got $count"; FAIL=$((FAIL + 1))
fi

# Specific verb/object checks
has_delete=$(jq '[.[] | select(.verb == "delete" and (.object | test("token")))] | length' <<< "$intents")
TOTAL=$((TOTAL + 1))
if [[ "$has_delete" -ge 1 ]]; then
  echo "  PASS: 'delete tokens' captured"; PASS=$((PASS + 1))
else
  echo "  FAIL: 'delete tokens' missing"; FAIL=$((FAIL + 1))
fi

has_create_session=$(jq '[.[] | select(.verb == "create" and (.object | test("session")))] | length' <<< "$intents")
TOTAL=$((TOTAL + 1))
if [[ "$has_create_session" -ge 1 ]]; then
  echo "  PASS: 'create sessions' captured"; PASS=$((PASS + 1))
else
  echo "  FAIL: 'create sessions' missing"; FAIL=$((FAIL + 1))
fi

# Test 4: sources are correctly tagged
echo ""
echo "Test 4: source tagging"
sources=$(jq -r '[.[].source] | sort | unique | join(",")' <<< "$intents")
case "$sources" in
  *"title"*) TOTAL=$((TOTAL + 1)); echo "  PASS: title source tagged"; PASS=$((PASS + 1));;
  *) TOTAL=$((TOTAL + 1)); echo "  FAIL: no title source"; FAIL=$((FAIL + 1));;
esac
case "$sources" in
  *"description"*) TOTAL=$((TOTAL + 1)); echo "  PASS: description source tagged"; PASS=$((PASS + 1));;
  *) TOTAL=$((TOTAL + 1)); echo "  FAIL: no description source"; FAIL=$((FAIL + 1));;
esac
case "$sources" in
  *"ac"*) TOTAL=$((TOTAL + 1)); echo "  PASS: ac source tagged"; PASS=$((PASS + 1));;
  *) TOTAL=$((TOTAL + 1)); echo "  FAIL: no ac source"; FAIL=$((FAIL + 1));;
esac
case "$sources" in
  *"task"*) TOTAL=$((TOTAL + 1)); echo "  PASS: task source tagged"; PASS=$((PASS + 1));;
  *) TOTAL=$((TOTAL + 1)); echo "  FAIL: no task source"; FAIL=$((FAIL + 1));;
esac

# Test 5: extract_code_intents — TypeScript file
echo ""
echo "Test 5: extract code intents from TS"
TEST_TMPDIR=$(mktemp -d)
cat > "$TEST_TMPDIR/app.ts" << 'EOF'
export function createOrder(id: number): Order { return new Order(id); }
export function deleteOrder(id: number): void {}
export const getOrder = (id: number): Order => null;
export function useCache(): void {}
export class Foo {}
EOF
ci=$(extract_code_intents "$TEST_TMPDIR/app.ts")
count=$(jq 'length' <<< "$ci")
# Expected 3: createOrder, deleteOrder, getOrder. NOT useCache (use not in verb list),
# NOT Foo (not a function).
assert "3 verb-led functions found" "3" "$count"
verbs=$(jq -r '[.[].verb] | sort | unique | join(",")' <<< "$ci")
assert "verbs = create,delete,get" "create,delete,get" "$verbs"
rm -rf "$TEST_TMPDIR"

# Test 6: extract_code_intents — Python file
echo ""
echo "Test 6: extract code intents from Python"
TEST_TMPDIR=$(mktemp -d)
cat > "$TEST_TMPDIR/app.py" << 'EOF'
def create_user(name: str):
    pass
def delete_user(uid: int):
    pass
async def fetch_profile(uid: int):
    pass
def xyz():
    pass
EOF
ci=$(extract_code_intents "$TEST_TMPDIR/app.py")
count=$(jq 'length' <<< "$ci")
assert "3 verb-led (xyz excluded)" "3" "$count"
rm -rf "$TEST_TMPDIR"

# Test 7: extract_code_intents — directory walk
echo ""
echo "Test 7: dir walk across extensions"
TEST_TMPDIR=$(mktemp -d)
mkdir -p "$TEST_TMPDIR/src"
cat > "$TEST_TMPDIR/src/a.ts" << 'EOF'
export function createFoo(): void {}
EOF
cat > "$TEST_TMPDIR/src/b.py" << 'EOF'
def delete_bar():
    pass
EOF
cat > "$TEST_TMPDIR/src/c.go" << 'EOF'
package main
func FetchBaz() {}
EOF
ci=$(extract_code_intents "$TEST_TMPDIR/src")
count=$(jq 'length' <<< "$ci")
assert "3 intents across TS+PY+GO" "3" "$count"
rm -rf "$TEST_TMPDIR"

# Test 8: match_intents — full overlap
echo ""
echo "Test 8: match full overlap"
story_intents='[{"verb":"create","object":"order","source":"title"}]'
code_intents='[{"verb":"create","object":"order","source":"createOrder"}]'
m=$(match_intents "$story_intents" "$code_intents")
assert "matched count=1"       "1" "$(jq '.matched | length' <<< "$m")"
assert "unmatched_story=0"     "0" "$(jq '.unmatched_story | length' <<< "$m")"
assert "unmatched_code=0"      "0" "$(jq '.unmatched_code | length' <<< "$m")"
assert "jaccard=1"             "1" "$(jq '.jaccard' <<< "$m")"

# Test 9: match_intents — partial overlap exposes drift
echo ""
echo "Test 9: partial overlap - story says delete, code says filter"
story_intents='[
  {"verb":"delete","object":"expired tokens","source":"description"},
  {"verb":"create","object":"session","source":"description"}
]'
code_intents='[
  {"verb":"filter","object":"expired tokens","source":"filterExpiredTokens"},
  {"verb":"create","object":"session","source":"createSession"}
]'
m=$(match_intents "$story_intents" "$code_intents")
assert "matched (create session)" "1" "$(jq '.matched | length' <<< "$m")"
# story has delete not in code -> unmatched_story
unmatched_s_verb=$(jq -r '.unmatched_story[0].verb' <<< "$m")
assert "unmatched_story verb=delete" "delete" "$unmatched_s_verb"
# code has filter not in story -> unmatched_code
unmatched_c_verb=$(jq -r '.unmatched_code[0].verb' <<< "$m")
assert "unmatched_code verb=filter" "filter" "$unmatched_c_verb"

# Test 10: match_intents — object-order insensitive normalization
echo ""
echo "Test 10: object token order normalized"
story_intents='[{"verb":"validate","object":"user email","source":"ac"}]'
code_intents='[{"verb":"validate","object":"email user","source":"validateUserEmail"}]'
m=$(match_intents "$story_intents" "$code_intents")
assert "token-order-insensitive match" "1" "$(jq '.matched | length' <<< "$m")"

# Test 11: match_intents — empty inputs
echo ""
echo "Test 11: empty inputs"
m=$(match_intents "[]" "[]")
assert "empty: matched=0"   "0" "$(jq '.matched | length' <<< "$m")"
assert "empty: jaccard=0"   "0" "$(jq '.jaccard' <<< "$m")"
m=$(match_intents '[{"verb":"x","object":"y","source":"s"}]' "[]")
assert "empty code: unmatched_story=1" "1" "$(jq '.unmatched_story | length' <<< "$m")"

# Test 12: end-to-end — story + code → match report
echo ""
echo "Test 12: end-to-end story→code match"
story=$(jq -cn '{
  title: "Token lifecycle",
  description: "Create tokens and delete expired tokens.",
  acceptanceCriteria: [],
  tasks: []
}')
s_intents=$(extract_story_intents "$story")
# Code file
TEST_TMPDIR=$(mktemp -d)
cat > "$TEST_TMPDIR/t.ts" << 'EOF'
export function createToken(): Token { return null; }
export function deleteExpiredToken(): void {}
EOF
c_intents=$(extract_code_intents "$TEST_TMPDIR/t.ts")
m=$(match_intents "$s_intents" "$c_intents")
matched_count=$(jq '.matched | length' <<< "$m")
TOTAL=$((TOTAL + 1))
if [[ "$matched_count" -ge 1 ]]; then
  echo "  PASS: end-to-end matched $matched_count intent(s)"; PASS=$((PASS + 1))
else
  echo "  FAIL: end-to-end matched 0"; FAIL=$((FAIL + 1))
fi
rm -rf "$TEST_TMPDIR"

# Test 13: CLI subcommands
echo ""
echo "Test 13: CLI subcommands"
story=$(jq -cn '{title: "", description: "delete tokens", acceptanceCriteria: [], tasks: []}')
cli_story=$(printf '%s' "$story" | bash "$REPO_ROOT/lib/intent-graph.sh" story)
assert "CLI story count>=1" "1" "$(jq 'length' <<< "$cli_story")"
TEST_TMPDIR=$(mktemp -d)
cat > "$TEST_TMPDIR/f.ts" << 'EOF'
export function deleteToken(): void {}
EOF
cli_code=$(bash "$REPO_ROOT/lib/intent-graph.sh" code "$TEST_TMPDIR/f.ts")
assert "CLI code count=1" "1" "$(jq 'length' <<< "$cli_code")"
# CLI match
echo "$cli_story" > "$TEST_TMPDIR/s.json"
echo "$cli_code"  > "$TEST_TMPDIR/c.json"
cli_match=$(bash "$REPO_ROOT/lib/intent-graph.sh" match "$TEST_TMPDIR/s.json" "$TEST_TMPDIR/c.json")
assert "CLI match jaccard=1" "1" "$(jq '.jaccard' <<< "$cli_match")"
rm -rf "$TEST_TMPDIR"

# Test 14: verb not at start of function — NOT extracted
echo ""
echo "Test 14: non-action function name"
TEST_TMPDIR=$(mktemp -d)
cat > "$TEST_TMPDIR/n.ts" << 'EOF'
export function Constructor(): void {}
export function userManager(): void {}
export function hamburger(): void {}
EOF
ci=$(extract_code_intents "$TEST_TMPDIR/n.ts")
assert "no intents (no verb prefix)" "0" "$(jq 'length' <<< "$ci")"
rm -rf "$TEST_TMPDIR"

echo ""
echo "=== Results: $PASS/$TOTAL passed, $FAIL failed ==="
exit $((FAIL > 0 ? 1 : 0))
