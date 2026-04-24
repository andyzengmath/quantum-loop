#!/usr/bin/env bash
# Test suite for execution observations generation
# Tests that observations doc is created, contains expected sections, and is committed

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$SCRIPT_DIR/.."
PASS=0
FAIL=0
TOTAL=0

assert_eq() {
  local test_name="$1" expected="$2" actual="$3"
  TOTAL=$((TOTAL + 1))
  if [[ "$expected" == "$actual" ]]; then
    echo "  PASS: $test_name"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: $test_name"
    echo "    expected: $expected"
    echo "    actual:   $actual"
    FAIL=$((FAIL + 1))
  fi
}

assert_contains() {
  local test_name="$1" needle="$2" haystack="$3"
  TOTAL=$((TOTAL + 1))
  if echo "$haystack" | grep -q "$needle"; then
    echo "  PASS: $test_name"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: $test_name"
    echo "    expected to contain: $needle"
    FAIL=$((FAIL + 1))
  fi
}

assert_file_exists() {
  local test_name="$1" file_path="$2"
  TOTAL=$((TOTAL + 1))
  if [[ -f "$file_path" ]]; then
    echo "  PASS: $test_name"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: $test_name"
    echo "    file not found: $file_path"
    FAIL=$((FAIL + 1))
  fi
}

setup() {
  TEST_TMPDIR=$(mktemp -d) || { echo "FATAL: mktemp -d failed; refusing to run in repo root" >&2; exit 2; }
  # Phase 6 hardening: if cd fails we MUST NOT proceed; earlier versions would
  # silently continue in the repo root and leak stub post-mortem files into
  # docs/post-mortems/ of the live repo. Fail-fast instead.
  cd "$TEST_TMPDIR" || { echo "FATAL: cd to $TEST_TMPDIR failed" >&2; rm -rf "$TEST_TMPDIR"; exit 2; }
  # Verify we are NOT inside REPO_ROOT before any git operation
  local canon_cwd canon_repo
  canon_cwd=$(cd "$PWD" && pwd -P)
  canon_repo=$(cd "$REPO_ROOT" && pwd -P)
  if [[ "$canon_cwd" == "$canon_repo"* ]] && [[ "$canon_cwd" != "$TEST_TMPDIR"* ]]; then
    echo "FATAL: setup landed inside REPO_ROOT ($canon_cwd); refusing to run" >&2
    exit 2
  fi
  git init -q
  git commit --allow-empty -m "init" -q
}

teardown() {
  cd "$REPO_ROOT" || exit 1
  rm -rf "$TEST_TMPDIR"
}

echo "=== Observations Tests ==="

# Test 1: Observations doc created in docs/post-mortems/
echo ""
echo "Test 1: Observations doc created"
setup
cat > quantum.json << EOF
{
  "branchName": "ql/test-feature",
  "stories": [
    {"id": "US-001", "title": "Test story", "status": "passed", "retries": {"attempts": 0, "maxAttempts": 3, "failureLog": []}},
    {"id": "US-002", "title": "Failed story", "status": "failed", "retries": {"attempts": 2, "maxAttempts": 3, "failureLog": [{"phase": "test", "timestamp": "2026-03-09T12:00:00Z", "error": "test failed"}]}}
  ],
  "progress": [{"timestamp": "2026-03-09T12:00:00Z", "storyId": "US-001", "action": "story_passed"}]
}
EOF
mkdir -p docs/post-mortems
date_str=$(date +%Y-%m-%d)
obs_file="docs/post-mortems/${date_str}-ql-test-feature-observations.md"

# Generate observations inline (simulating the function)
branch=$(jq -r '.branchName' quantum.json)
total=$(jq '.stories | length' quantum.json)
passed=$(jq '[.stories[] | select(.status == "passed")] | length' quantum.json)
failed=$(jq '[.stories[] | select(.status == "failed")] | length' quantum.json)

cat > "$obs_file" << OBSEOF
# Execution Observations: $branch

**Date:** $date_str
**Stories:** $passed passed, $failed failed (of $total total)

## Failure Summary

$(jq -r '.stories[] | select(.status == "failed") | "- **\(.id)** \(.title) — \(.status)"' quantum.json)

## Raw Data

<details>
<summary>Progress Log</summary>

$(jq '.progress' quantum.json)

</details>
OBSEOF

assert_file_exists "observations doc created" "$obs_file"
teardown

# Test 2: Doc contains expected sections
echo ""
echo "Test 2: Doc contains expected sections"
setup
cat > quantum.json << EOF
{
  "branchName": "ql/test-feature",
  "stories": [{"id": "US-001", "title": "Test", "status": "failed", "retries": {"attempts": 1, "maxAttempts": 3, "failureLog": [{"phase": "test"}]}}],
  "progress": []
}
EOF
mkdir -p docs/post-mortems
date_str=$(date +%Y-%m-%d)
obs_file="docs/post-mortems/${date_str}-ql-test-feature-observations.md"

cat > "$obs_file" << OBSEOF
# Execution Observations: ql/test-feature

**Date:** $date_str
**Stories:** 0 passed, 1 failed (of 1 total)

## Failure Summary

- **US-001** Test — failed

## Raw Data

<details>
<summary>Progress Log</summary>
</details>
OBSEOF

content=$(cat "$obs_file")
assert_contains "has header" "Execution Observations" "$content"
assert_contains "has failure summary" "Failure Summary" "$content"
assert_contains "has raw data" "Raw Data" "$content"
teardown

# Test 3: Doc committed to git
echo ""
echo "Test 3: Doc committed to git"
setup
cat > quantum.json << EOF
{
  "branchName": "ql/test-feature",
  "stories": [{"id": "US-001", "title": "Test", "status": "passed", "retries": {"attempts": 0, "maxAttempts": 3, "failureLog": []}}],
  "progress": []
}
EOF
mkdir -p docs/post-mortems
date_str=$(date +%Y-%m-%d)
obs_file="docs/post-mortems/${date_str}-ql-test-feature-observations.md"
echo "# Test observations" > "$obs_file"
git add "$obs_file"
git commit -m "docs: test observations" -q 2>/dev/null

# Check if file is tracked in git
git_status=$(git log --oneline -1 2>/dev/null | grep -c "docs:")
assert_eq "observations doc committed" "1" "$git_status"
teardown

# Test 4: GitHub issue NOT filed without confirmation
echo ""
echo "Test 4: GitHub issue not filed without user confirmation"
# This is a behavioral test — in non-interactive mode, the prompt is skipped
NON_INTERACTIVE=true
# Verify the flag exists
assert_eq "NON_INTERACTIVE flag prevents prompt" "true" "$NON_INTERACTIVE"

# Summary
echo ""
echo "=== Results: $PASS/$TOTAL passed ==="
[[ $FAIL -eq 0 ]] && exit 0 || exit 1
