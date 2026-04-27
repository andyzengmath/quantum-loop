#!/usr/bin/env bash
# US-004 / G3 — verify the /ql-plan exit step writes a Sprint-Contract per
# story by iterating quantum.json.stories and calling write_sprint_contract.
# Idempotent: re-running overwrites existing files.
#
# This is a BEHAVIORAL test that simulates the SKILL exit logic against a
# 3-story fixture. We do NOT spawn the actual planner — we replicate the
# bash snippet the SKILL ships and assert the per-story files are written
# with valid schema.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$SCRIPT_DIR/.."
HANDOFF_SH="$REPO_ROOT/lib/handoff.sh"
JSON_ATOMIC_SH="$REPO_ROOT/lib/json-atomic.sh"
PLAN_SKILL="$REPO_ROOT/skills/ql-plan/SKILL.md"
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

assert_grep_skill() {
  local name="$1" needle="$2"
  TOTAL=$((TOTAL + 1))
  if grep -qF -- "$needle" "$PLAN_SKILL"; then
    echo "  PASS: $name"; PASS=$((PASS + 1))
  else
    echo "  FAIL: $name — needle [$needle] not in $(basename "$PLAN_SKILL")"
    FAIL=$((FAIL + 1))
  fi
}

echo "=== US-004 / G3 sprint-contract /ql-plan exit step tests ==="

# Test 1: SKILL.md describes the exit step
echo ""
echo "Test 1: skills/ql-plan/SKILL.md ships the exit step"
assert_grep_skill "Sprint-Contract write step header" "Sprint-Contract write per story"
assert_grep_skill "iterates stories in quantum.json" "stories[]"
assert_grep_skill "calls write_sprint_contract" "write_sprint_contract"
assert_grep_skill "sources lib/handoff.sh" "lib/handoff.sh"
assert_grep_skill "step ordered after dag-validator" "after dag-validator"
assert_grep_skill "writes per-story handoff path" ".handoffs/sprint-"

# Test 2: behavioral — replicate the SKILL exit logic on a 3-story fixture
echo ""
echo "Test 2: 3-story fixture round-trip"

TMP=$(mktemp -d)
cd "$TMP"

# Build a synthetic 3-story quantum.json
cat > quantum.json <<'EOF'
{
  "project": "test",
  "branchName": "test-branch",
  "prdPath": "tasks/prd-test.md",
  "contracts": {
    "env_vars": {"FOO": {"value": "FOO"}},
    "shared_types": {}
  },
  "stories": [
    {
      "id": "US-A",
      "title": "Story A",
      "acceptanceCriteria": ["AC-A1", "AC-A2"],
      "tasks": [
        {"filePaths": ["src/a.py"], "commands": ["bash tests/test_a.sh"]}
      ]
    },
    {
      "id": "US-B",
      "title": "Story B",
      "acceptanceCriteria": ["AC-B1"],
      "tasks": [
        {"filePaths": ["src/b.py"], "commands": ["pytest tests/test_b.py", "tsc --noEmit"]}
      ]
    },
    {
      "id": "US-C",
      "title": "Story C",
      "acceptanceCriteria": ["AC-C1"],
      "tasks": [
        {"filePaths": ["src/c.py"], "commands": ["eslint ."]}
      ]
    }
  ]
}
EOF

# Stub PRD
mkdir -p tasks
echo "# PRD test" > tasks/prd-test.md

# Replicate the SKILL exit logic. The SKILL ships this block:
#   for sid in $(jq -r '.stories[].id' quantum.json); do
#     CONTRACT=$(jq ... build sprint contract per story ...)
#     write_sprint_contract "$sid" "$CONTRACT"
#   done

# shellcheck disable=SC1090
source "$HANDOFF_SH"
# shellcheck disable=SC1090
source "$JSON_ATOMIC_SH" 2>/dev/null || true  # compute_prd_sha optional

PRD_SHA=$(sha256sum tasks/prd-test.md 2>/dev/null | awk '{print $1}' || echo "stub-sha")

while IFS= read -r sid; do
  # CLAUDE.md Platform Notes: strip CRLF from heredoc-fed JSON on Git Bash.
  sid="${sid%$'\r'}"
  [[ -z "$sid" ]] && continue
  CONTRACT=$(jq -n --arg id "$sid" --arg sha "$PRD_SHA" --arg ts "$(date -u +%FT%TZ)" \
    --arg pattern "$SPRINT_CONTRACT_TEST_REGEX" \
    --slurpfile q quantum.json '
      ($q[0].stories[] | select(.id == $id)) as $story |
      ($story.tasks // []) as $tasks |
      {
        storyId: $id,
        prdSha: $sha,
        acs: ($story.acceptanceCriteria // []),
        contracts: ($q[0].contracts // {}),
        files: [$tasks[].filePaths // []] | flatten | unique,
        expectedTests: ([$tasks[].commands // []] | flatten | map(select(test($pattern)))),
        otherCommands: ([$tasks[].commands // []] | flatten | map(select(test($pattern) | not))),
        plannedBy: "ql-plan",
        plannedAt: $ts
      }')
  write_sprint_contract "$sid" "$CONTRACT" >/dev/null 2>&1
done < <(jq -r '.stories[].id' quantum.json)

# Assert 3 sprint files created
TOTAL=$((TOTAL + 1))
sprint_count=$(ls .handoffs/sprint-*.json 2>/dev/null | wc -l)
if [[ "$sprint_count" == "3" ]]; then
  echo "  PASS: 3 sprint-contract files created (one per story)"
  PASS=$((PASS + 1))
else
  echo "  FAIL: expected 3 sprint files, got $sprint_count"
  FAIL=$((FAIL + 1))
fi

# Each file has the expected schema
for sid in US-A US-B US-C; do
  file=".handoffs/sprint-${sid}.json"
  TOTAL=$((TOTAL + 1))
  if [[ ! -f "$file" ]]; then
    echo "  FAIL: $file missing"
    FAIL=$((FAIL + 1))
    continue
  fi
  has_all=$(jq -r 'has("storyId") and has("prdSha") and has("acs") and has("contracts") and has("files") and has("expectedTests") and has("otherCommands") and has("plannedBy") and has("plannedAt")' "$file")
  if [[ "$has_all" == "true" ]]; then
    echo "  PASS: $sid sprint-contract has all required fields (incl. otherCommands)"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: $sid sprint-contract missing required field(s)"
    FAIL=$((FAIL + 1))
  fi
done

# US-B specifically should have a non-empty otherCommands (tsc --noEmit)
TOTAL=$((TOTAL + 1))
b_other=$(jq -r '.otherCommands | length' .handoffs/sprint-US-B.json)
if [[ "$b_other" == "1" ]]; then
  echo "  PASS: US-B otherCommands has 1 entry (tsc --noEmit, the non-test cmd)"
  PASS=$((PASS + 1))
else
  echo "  FAIL: US-B otherCommands wrong (expected 1 entry, got $b_other)"
  FAIL=$((FAIL + 1))
fi

# US-A should have 1 expectedTests (bash tests/test_a.sh)
TOTAL=$((TOTAL + 1))
a_tests=$(jq -r '.expectedTests | length' .handoffs/sprint-US-A.json)
if [[ "$a_tests" == "1" ]]; then
  echo "  PASS: US-A expectedTests has 1 entry"
  PASS=$((PASS + 1))
else
  echo "  FAIL: US-A expectedTests wrong (expected 1, got $a_tests)"
  FAIL=$((FAIL + 1))
fi

# Test 3: idempotency — re-running overwrites without error
echo ""
echo "Test 3: idempotency"

# Capture old mtime + content
OLD_HASH=$(sha256sum .handoffs/sprint-US-A.json | awk '{print $1}')

# Re-run the loop
while IFS= read -r sid; do
  # CLAUDE.md Platform Notes: strip CRLF from heredoc-fed JSON on Git Bash.
  sid="${sid%$'\r'}"
  [[ -z "$sid" ]] && continue
  CONTRACT=$(jq -n --arg id "$sid" --arg sha "$PRD_SHA" --arg ts "$(date -u +%FT%TZ)" \
    --arg pattern "$SPRINT_CONTRACT_TEST_REGEX" \
    --slurpfile q quantum.json '
      ($q[0].stories[] | select(.id == $id)) as $story |
      ($story.tasks // []) as $tasks |
      {
        storyId: $id,
        prdSha: $sha,
        acs: ($story.acceptanceCriteria // []),
        contracts: ($q[0].contracts // {}),
        files: [$tasks[].filePaths // []] | flatten | unique,
        expectedTests: ([$tasks[].commands // []] | flatten | map(select(test($pattern)))),
        otherCommands: ([$tasks[].commands // []] | flatten | map(select(test($pattern) | not))),
        plannedBy: "ql-plan",
        plannedAt: $ts
      }')
  write_sprint_contract "$sid" "$CONTRACT" >/dev/null 2>&1
done < <(jq -r '.stories[].id' quantum.json)

NEW_HASH=$(sha256sum .handoffs/sprint-US-A.json | awk '{print $1}')

# Hash MAY differ because plannedAt changes per call. We just verify the file
# still exists and is valid JSON (idempotent in the "doesn't error" sense).
TOTAL=$((TOTAL + 1))
if [[ -f .handoffs/sprint-US-A.json ]] && jq empty .handoffs/sprint-US-A.json 2>/dev/null; then
  echo "  PASS: re-run produces valid sprint-contract (idempotent, no error)"
  PASS=$((PASS + 1))
else
  echo "  FAIL: re-run broke the contract file"
  FAIL=$((FAIL + 1))
fi

cd "$REPO_ROOT"
rm -rf "$TMP"

echo ""
echo "=== Results: $PASS/$TOTAL passed, $FAIL failed ==="
[[ $FAIL -eq 0 ]] || exit 1
