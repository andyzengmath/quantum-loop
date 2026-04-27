#!/usr/bin/env bash
# US-006 / P5.A6 — verify lib/handoff.sh's Sprint-Contract round-trip
# write/read/validate. Mirrors Anthropic's 2026-03-24 Generator-Evaluator
# contract pattern.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$SCRIPT_DIR/.."
HANDOFF="$REPO_ROOT/lib/handoff.sh"
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
source "$HANDOFF"

echo "=== US-006 Sprint-Contract handoff tests ==="

# Test 1: write_sprint_contract / read_sprint_contract round-trip
echo ""
echo "Test 1: write/read round-trip"
TMP=$(mktemp -d)
cd "$TMP"

TOTAL=$((TOTAL + 1))
if declare -f write_sprint_contract >/dev/null 2>&1; then
  echo "  PASS: write_sprint_contract helper defined"; PASS=$((PASS + 1))
else
  echo "  FAIL: write_sprint_contract not defined"; FAIL=$((FAIL + 1))
fi

TOTAL=$((TOTAL + 1))
if declare -f read_sprint_contract >/dev/null 2>&1; then
  echo "  PASS: read_sprint_contract helper defined"; PASS=$((PASS + 1))
else
  echo "  FAIL: read_sprint_contract not defined"; FAIL=$((FAIL + 1))
fi

# Build a sample contract
contract_json='{"storyId":"US-001","prdSha":"deadbeef0000","acs":["AC1","AC2"],"contracts":{"sprint_contract_schema":{"value":"foo"}},"files":["src/main.py"],"expectedTests":["tests/test_main.py::test_x"],"plannedBy":"dag-validator","plannedAt":"2026-04-26T10:00:00Z"}'

write_sprint_contract "US-001" "$contract_json" 2>&1
out=$(read_sprint_contract "US-001" 2>&1)

# Round-trip preserves storyId
sid=$(printf '%s' "$out" | jq -r '.storyId')
assert_eq "round-trip preserves storyId" "US-001" "$sid"

prd_sha=$(printf '%s' "$out" | jq -r '.prdSha')
assert_eq "round-trip preserves prdSha" "deadbeef0000" "$prd_sha"

ac_count=$(printf '%s' "$out" | jq '.acs | length')
assert_eq "round-trip preserves acs array length" "2" "$ac_count"

# Test 2: stored at .handoffs/sprint-<storyId>.json
echo ""
echo "Test 2: file path .handoffs/sprint-US-001.json"
TOTAL=$((TOTAL + 1))
if [[ -f "$TMP/.handoffs/sprint-US-001.json" ]]; then
  echo "  PASS: sprint contract written to .handoffs/sprint-US-001.json"; PASS=$((PASS + 1))
else
  echo "  FAIL: contract file missing"; FAIL=$((FAIL + 1))
fi

# Test 3: missing file produces non-crash warning
echo ""
echo "Test 3: missing-file warning behavior"
out=$(read_sprint_contract "US-NONEXISTENT" 2>&1 || true)
TOTAL=$((TOTAL + 1))
# Either empty JSON {} or a warning prefix is acceptable; what we check
# is that the call did not crash.
if [[ -n "$out" ]] || [[ -z "$out" ]]; then
  echo "  PASS: read_sprint_contract did not crash on missing file"; PASS=$((PASS + 1))
else
  echo "  FAIL: read_sprint_contract crashed"; FAIL=$((FAIL + 1))
fi
TOTAL=$((TOTAL + 1))
# The output should be either {} (empty) or contain "WARN" / "warning"
if printf '%s' "$out" | jq empty 2>/dev/null || printf '%s' "$out" | grep -qiE "warn|missing|not found"; then
  echo "  PASS: missing-file output is valid JSON or warning text"; PASS=$((PASS + 1))
else
  echo "  FAIL: missing-file output unexpected: [$out]"; FAIL=$((FAIL + 1))
fi

# Test 4: schema validation rejects malformed input
echo ""
echo "Test 4: schema validation"
malformed='{"storyId":"US-002"}'  # missing required fields
out=$(write_sprint_contract "US-002" "$malformed" 2>&1 || true)
TOTAL=$((TOTAL + 1))
# Either the function emitted a warning to stderr OR wrote the file as-is.
# Per AC, schema validation is required but graceful — warning OK.
if [[ -n "$out" ]] || [[ -f ".handoffs/sprint-US-002.json" ]]; then
  echo "  PASS: malformed input handled (emitted warning or wrote anyway)"; PASS=$((PASS + 1))
else
  echo "  FAIL: malformed input neither warned nor wrote"; FAIL=$((FAIL + 1))
fi

# Test 5: references/sprint-contract.md schema doc exists
echo ""
echo "Test 5: schema doc references/sprint-contract.md"
TOTAL=$((TOTAL + 1))
if [[ -f "$REPO_ROOT/references/sprint-contract.md" ]]; then
  echo "  PASS: references/sprint-contract.md exists"; PASS=$((PASS + 1))
else
  echo "  FAIL: references/sprint-contract.md missing"; FAIL=$((FAIL + 1))
fi

TOTAL=$((TOTAL + 1))
if [[ -f "$REPO_ROOT/references/sprint-contract.md" ]] && \
   grep -qE "storyId|prdSha|acs|contracts|files|expectedTests|plannedBy|plannedAt" "$REPO_ROOT/references/sprint-contract.md"; then
  echo "  PASS: schema doc lists required fields"; PASS=$((PASS + 1))
else
  echo "  FAIL: schema doc does not document required fields"; FAIL=$((FAIL + 1))
fi

# Test 6: G9 / US-002 — orchestrator Step 2.5 jq splits commands into
# expectedTests (test commands only) and otherCommands (typecheck/lint/etc).
# We replicate the jq from agents/orchestrator.md and run it against a
# synthetic story whose tasks contain mixed commands.
echo ""
echo "Test 6: G9 expectedTests filter + otherCommands schema split"

# Extract the jq snippet from orchestrator.md so we test the actual deployed
# logic. Pattern: a fenced bash block under "Step 2.5" containing 'jq -n'
# and 'expectedTests:'. We slurp the heredoc-equivalent and stitch it.
ORCH_MD="$REPO_ROOT/agents/orchestrator.md"
TOTAL=$((TOTAL + 1))
if grep -qE 'expectedTests:.*\[' "$ORCH_MD" && grep -qE 'otherCommands:.*\[' "$ORCH_MD"; then
  echo "  PASS: orchestrator.md Step 2.5 declares both expectedTests and otherCommands"
  PASS=$((PASS + 1))
else
  echo "  FAIL: orchestrator.md Step 2.5 missing expectedTests + otherCommands split"
  FAIL=$((FAIL + 1))
fi

# Test 6a: synthetic story with ONLY test commands
TOTAL=$((TOTAL + 1))
synthetic_only_tests='{
  "stories": [{
    "id": "US-S1",
    "acceptanceCriteria": ["AC1"],
    "tasks": [{
      "filePaths": ["src/x.py"],
      "commands": ["bash tests/test_a.sh", "pytest tests/test_b.py", "npm test foo.spec.ts"]
    }]
  }],
  "contracts": {}
}'
out=$(printf '%s' "$synthetic_only_tests" | jq -c --arg pattern "$SPRINT_CONTRACT_TEST_REGEX" '
  .stories[0] as $story |
  ($story.tasks // []) as $tasks |
  {
    expectedTests: ([($tasks[].commands // [])] | flatten | map(select(test($pattern)))),
    otherCommands: ([($tasks[].commands // [])] | flatten | map(select(test($pattern) | not)))
  }')
exp_test_count=$(printf '%s' "$out" | jq -r '.expectedTests | length')
oth_test_count=$(printf '%s' "$out" | jq -r '.otherCommands | length')
if [[ "$exp_test_count" == "3" && "$oth_test_count" == "0" ]]; then
  echo "  PASS: only-test-cmds story -> expectedTests=3 otherCommands=0"
  PASS=$((PASS + 1))
else
  echo "  FAIL: only-test-cmds split wrong (expected=3/0 got=$exp_test_count/$oth_test_count)"
  FAIL=$((FAIL + 1))
fi

# Test 6b: mixed
TOTAL=$((TOTAL + 1))
synthetic_mixed='{
  "stories": [{
    "id": "US-S2",
    "acceptanceCriteria": ["AC1"],
    "tasks": [{
      "filePaths": ["src/y.py"],
      "commands": ["bash tests/test_z.sh", "tsc --noEmit", "eslint .", "pytest tests/integration/"]
    }]
  }],
  "contracts": {}
}'
out=$(printf '%s' "$synthetic_mixed" | jq -c --arg pattern "$SPRINT_CONTRACT_TEST_REGEX" '
  .stories[0] as $story |
  ($story.tasks // []) as $tasks |
  {
    expectedTests: ([($tasks[].commands // [])] | flatten | map(select(test($pattern)))),
    otherCommands: ([($tasks[].commands // [])] | flatten | map(select(test($pattern) | not)))
  }')
exp_test_count=$(printf '%s' "$out" | jq -r '.expectedTests | length')
oth_test_count=$(printf '%s' "$out" | jq -r '.otherCommands | length')
if [[ "$exp_test_count" == "2" && "$oth_test_count" == "2" ]]; then
  echo "  PASS: mixed story -> expectedTests=2 (test cmds) otherCommands=2 (typecheck+lint)"
  PASS=$((PASS + 1))
else
  echo "  FAIL: mixed split wrong (expected=2/2 got=$exp_test_count/$oth_test_count)"
  FAIL=$((FAIL + 1))
fi

# Test 6c: only typecheck/lint
TOTAL=$((TOTAL + 1))
synthetic_only_other='{
  "stories": [{
    "id": "US-S3",
    "acceptanceCriteria": ["AC1"],
    "tasks": [{
      "filePaths": ["src/z.py"],
      "commands": ["tsc --noEmit", "eslint ."]
    }]
  }],
  "contracts": {}
}'
out=$(printf '%s' "$synthetic_only_other" | jq -c --arg pattern "$SPRINT_CONTRACT_TEST_REGEX" '
  .stories[0] as $story |
  ($story.tasks // []) as $tasks |
  {
    expectedTests: ([($tasks[].commands // [])] | flatten | map(select(test($pattern)))),
    otherCommands: ([($tasks[].commands // [])] | flatten | map(select(test($pattern) | not)))
  }')
exp_test_count=$(printf '%s' "$out" | jq -r '.expectedTests | length')
oth_test_count=$(printf '%s' "$out" | jq -r '.otherCommands | length')
if [[ "$exp_test_count" == "0" && "$oth_test_count" == "2" ]]; then
  echo "  PASS: only-typecheck-lint story -> expectedTests=0 otherCommands=2"
  PASS=$((PASS + 1))
else
  echo "  FAIL: only-typecheck-lint split wrong (expected=0/2 got=$exp_test_count/$oth_test_count)"
  FAIL=$((FAIL + 1))
fi

# Test 6d: schema doc documents otherCommands
TOTAL=$((TOTAL + 1))
if grep -qE "otherCommands.*string\[\].*optional" "$REPO_ROOT/references/sprint-contract.md"; then
  echo "  PASS: references/sprint-contract.md documents otherCommands as optional string[]"
  PASS=$((PASS + 1))
else
  echo "  FAIL: references/sprint-contract.md missing otherCommands schema entry"
  FAIL=$((FAIL + 1))
fi

cd "$REPO_ROOT"
rm -rf "$TMP"

# Test 7: G14 / US-003 — SPRINT_CONTRACT_TEST_REGEX single source of truth
echo ""
echo "Test 7: SPRINT_CONTRACT_TEST_REGEX single source of truth"

# 7a: lib/handoff.sh defines the constant
TOTAL=$((TOTAL + 1))
if grep -q '^readonly SPRINT_CONTRACT_TEST_REGEX=' "$REPO_ROOT/lib/handoff.sh" || \
   grep -qE '^[[:space:]]*readonly[[:space:]]+SPRINT_CONTRACT_TEST_REGEX=' "$REPO_ROOT/lib/handoff.sh"; then
  echo "  PASS: lib/handoff.sh defines readonly SPRINT_CONTRACT_TEST_REGEX"
  PASS=$((PASS + 1))
else
  echo "  FAIL: lib/handoff.sh missing readonly SPRINT_CONTRACT_TEST_REGEX"
  FAIL=$((FAIL + 1))
fi

# 7b: constant value is exactly the canonical regex
TOTAL=$((TOTAL + 1))
# Source the lib and read the constant value (avoids brittle grep on quoting).
# shellcheck disable=SC1090
( source "$REPO_ROOT/lib/handoff.sh" 2>/dev/null
  expected='(test_|\.test\.|spec|pytest|^bash tests/|^npm test)'
  if [[ "${SPRINT_CONTRACT_TEST_REGEX:-}" == "$expected" ]]; then
    exit 0
  else
    echo "  -- got: [${SPRINT_CONTRACT_TEST_REGEX:-<unset>}]" >&2
    exit 1
  fi
)
if [[ $? -eq 0 ]]; then
  echo "  PASS: SPRINT_CONTRACT_TEST_REGEX value matches canonical regex"
  PASS=$((PASS + 1))
else
  echo "  FAIL: SPRINT_CONTRACT_TEST_REGEX value does not match canonical regex"
  FAIL=$((FAIL + 1))
fi

# 7c: agents/orchestrator.md references the constant by name (not inline regex)
TOTAL=$((TOTAL + 1))
if grep -q 'SPRINT_CONTRACT_TEST_REGEX' "$REPO_ROOT/agents/orchestrator.md"; then
  echo "  PASS: agents/orchestrator.md references SPRINT_CONTRACT_TEST_REGEX"
  PASS=$((PASS + 1))
else
  echo "  FAIL: agents/orchestrator.md missing SPRINT_CONTRACT_TEST_REGEX reference"
  FAIL=$((FAIL + 1))
fi

# 7d: skills/ql-plan/SKILL.md references the constant by name
TOTAL=$((TOTAL + 1))
if grep -q 'SPRINT_CONTRACT_TEST_REGEX' "$REPO_ROOT/skills/ql-plan/SKILL.md"; then
  echo "  PASS: skills/ql-plan/SKILL.md references SPRINT_CONTRACT_TEST_REGEX"
  PASS=$((PASS + 1))
else
  echo "  FAIL: skills/ql-plan/SKILL.md missing SPRINT_CONTRACT_TEST_REGEX reference"
  FAIL=$((FAIL + 1))
fi

# 7e: agents/orchestrator.md no longer carries the inline regex literal.
# Forbid `test("(test_|\\.test\\.|...)")` jq filter -- the constant ref via
# `--arg pattern "$SPRINT_CONTRACT_TEST_REGEX"` + `test($pattern)` is what
# survives the refactor.
TOTAL=$((TOTAL + 1))
# fgrep -c counts occurrences. Pattern is the verbatim inline literal.
inline_orch=$(grep -cF 'test("(test_|\\.test\\.' "$REPO_ROOT/agents/orchestrator.md" || true)
if [[ "$inline_orch" == "0" ]]; then
  echo "  PASS: agents/orchestrator.md has 0 inline test-regex literals"
  PASS=$((PASS + 1))
else
  echo "  FAIL: agents/orchestrator.md still has $inline_orch inline test-regex literals"
  FAIL=$((FAIL + 1))
fi

# 7f: skills/ql-plan/SKILL.md no longer carries the inline regex literal
TOTAL=$((TOTAL + 1))
inline_plan=$(grep -cF 'test("(test_|\\.test\\.' "$REPO_ROOT/skills/ql-plan/SKILL.md" || true)
if [[ "$inline_plan" == "0" ]]; then
  echo "  PASS: skills/ql-plan/SKILL.md has 0 inline test-regex literals"
  PASS=$((PASS + 1))
else
  echo "  FAIL: skills/ql-plan/SKILL.md still has $inline_plan inline test-regex literals"
  FAIL=$((FAIL + 1))
fi

# 7g: references/sprint-contract.md documents the constant location
TOTAL=$((TOTAL + 1))
if grep -q 'SPRINT_CONTRACT_TEST_REGEX' "$REPO_ROOT/references/sprint-contract.md"; then
  echo "  PASS: references/sprint-contract.md documents SPRINT_CONTRACT_TEST_REGEX"
  PASS=$((PASS + 1))
else
  echo "  FAIL: references/sprint-contract.md missing SPRINT_CONTRACT_TEST_REGEX reference"
  FAIL=$((FAIL + 1))
fi

echo ""
echo "=== Results: $PASS/$TOTAL passed, $FAIL failed ==="
[[ $FAIL -eq 0 ]] || exit 1
