#!/usr/bin/env bash
# US-008 / P5.A8 — verify complexity-based model routing per task.
# compute_complexity formula: min(100, task_count*10 + dependsOn_depth*15
# + (has_security_tag ? 30 : 0) + filePaths_count*2). Routing thresholds:
# <=30 -> haiku, 31-60 -> sonnet, 61+ -> opus.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$SCRIPT_DIR/.."
RUNNER="$REPO_ROOT/lib/runner.sh"
PASS=0
FAIL=0
TOTAL=0

assert_eq() {
  local name="$1" expected="$2" actual="$3"
  TOTAL=$((TOTAL + 1))
  if [[ "$expected" == "$actual" ]]; then
    echo "  PASS: $name"; PASS=$((PASS + 1))
  else
    echo "  FAIL: $name (expected [$expected] got [$actual])"
    FAIL=$((FAIL + 1))
  fi
}

# shellcheck disable=SC1090
source "$RUNNER"

echo "=== US-008 complexity routing tests ==="

# Test 1: compute_complexity formula
echo ""
echo "Test 1: compute_complexity scoring"
# 2 tasks, no deps, no security, 2 files -> 20 + 0 + 0 + 4 = 24
assert_eq "minimal story (2 tasks, 2 files) = 24" "24" "$(compute_complexity 2 0 false 2)"
# 5 tasks, 1 dep depth, no security, 4 files -> 50 + 15 + 0 + 8 = 73
assert_eq "5 tasks, 1 dep, 4 files = 73" "73" "$(compute_complexity 5 1 false 4)"
# 3 tasks, no deps, security tag, 3 files -> 30 + 0 + 30 + 6 = 66
assert_eq "3 tasks + security = 66" "66" "$(compute_complexity 3 0 true 3)"
# 10 tasks, 4 dep depth, security, 10 files -> 100 + 60 + 30 + 20 = 210, capped at 100
assert_eq "huge story caps at 100" "100" "$(compute_complexity 10 4 true 10)"
# 0 tasks, 0 dep depth, no sec, 0 files -> 0
assert_eq "minimum = 0" "0" "$(compute_complexity 0 0 false 0)"

# Test 2: runner_select_model thresholds
echo ""
echo "Test 2: runner_select_model thresholds"
assert_eq "score 0 -> haiku" "haiku" "$(runner_select_model 0)"
assert_eq "score 30 -> haiku" "haiku" "$(runner_select_model 30)"
assert_eq "score 31 -> sonnet" "sonnet" "$(runner_select_model 31)"
assert_eq "score 60 -> sonnet" "sonnet" "$(runner_select_model 60)"
assert_eq "score 61 -> opus" "opus" "$(runner_select_model 61)"
assert_eq "score 100 -> opus" "opus" "$(runner_select_model 100)"

# Test 3: story-level model override
echo ""
echo "Test 3: story-level model override"
assert_eq "explicit override wins (override=opus, score=10)" "opus" "$(runner_select_model 10 opus)"
assert_eq "explicit override wins (override=haiku, score=80)" "haiku" "$(runner_select_model 80 haiku)"
assert_eq "empty override falls through to score" "haiku" "$(runner_select_model 25 '')"

# Test 4: missing complexity field default
echo ""
echo "Test 4: missing complexity field default behavior"
# When complexity is empty/absent, default to opus (preserves v0.5.x semantics
# where every story used default model regardless of size).
assert_eq "empty complexity -> opus default" "opus" "$(runner_select_model '')"
assert_eq "non-numeric complexity -> opus default" "opus" "$(runner_select_model abc)"

# Test 5: quantum.json.example documents the field
echo ""
echo "Test 5: quantum.json.example documents complexity field"
TOTAL=$((TOTAL + 1))
if grep -qF '"complexity"' "$REPO_ROOT/quantum.json.example"; then
  echo "  PASS: complexity field documented in quantum.json.example"; PASS=$((PASS + 1))
else
  echo "  FAIL: complexity field not documented in quantum.json.example"
  FAIL=$((FAIL + 1))
fi

# Test 6: dag-validator.md captures the formula
echo ""
echo "Test 6: dag-validator.md documents complexity formula"
TOTAL=$((TOTAL + 1))
if grep -qF "task_count*10" "$REPO_ROOT/agents/dag-validator.md"; then
  echo "  PASS: dag-validator captures complexity formula"; PASS=$((PASS + 1))
else
  echo "  FAIL: dag-validator does not document complexity formula"
  FAIL=$((FAIL + 1))
fi

# Test 7: implementer.md acknowledges model selection
echo ""
echo "Test 7: implementer.md mentions model selection"
TOTAL=$((TOTAL + 1))
if grep -qE "model selection|complexity.*haiku|haiku.*sonnet.*opus" "$REPO_ROOT/agents/implementer.md"; then
  echo "  PASS: implementer.md mentions model selection / complexity routing"; PASS=$((PASS + 1))
else
  echo "  FAIL: implementer.md does not mention model selection"
  FAIL=$((FAIL + 1))
fi

echo ""
echo "=== Results: $PASS/$TOTAL passed, $FAIL failed ==="
[[ $FAIL -eq 0 ]] || exit 1
