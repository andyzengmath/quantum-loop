#!/usr/bin/env bash
# Phase 6 / P1.7 — End-to-end test for generate_observations() in quantum-loop.sh.
# Verifies:
#   (1) Progress Log markdown table is populated when retries.failureLog has rows
#   (2) The "(empty)" fallback copy appears when there are no failures
#   (3) Generalizable lessons are promoted into codebasePatterns
#   (4) test_observations_generator never writes outside its tempdir
#       (regression guard for the Apr-22 stub-leak incident)

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$SCRIPT_DIR/.."
CANON_REPO_ROOT=$(cd "$REPO_ROOT" && pwd -P)
PASS=0
FAIL=0
TOTAL=0

assert() {
  local name="$1" expected="$2" actual="$3"
  TOTAL=$((TOTAL + 1))
  if [[ "$expected" == "$actual" ]]; then
    echo "  PASS: $name"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: $name"
    echo "    expected: [$expected]"
    echo "    actual:   [$actual]"
    FAIL=$((FAIL + 1))
  fi
}

assert_contains() {
  local name="$1" needle="$2" haystack_file="$3"
  TOTAL=$((TOTAL + 1))
  if grep -qF "$needle" "$haystack_file"; then
    echo "  PASS: $name"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: $name"
    echo "    expected file $haystack_file to contain: [$needle]"
    echo "    --- file head ---"
    head -30 "$haystack_file" | sed 's/^/    /'
    FAIL=$((FAIL + 1))
  fi
}

assert_not_contains() {
  local name="$1" needle="$2" haystack_file="$3"
  TOTAL=$((TOTAL + 1))
  if ! grep -qF "$needle" "$haystack_file"; then
    echo "  PASS: $name"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: $name ($needle unexpectedly present in $haystack_file)"
    FAIL=$((FAIL + 1))
  fi
}

# Extract generate_observations body from quantum-loop.sh and run it in a tempdir
run_generator_in_tempdir() {
  local tmpdir="$1"
  cd "$tmpdir" || return 1
  local canon_cwd
  canon_cwd=$(pwd -P)
  if [[ "$canon_cwd" == "$CANON_REPO_ROOT"* ]]; then
    echo "FATAL: cwd is still inside real repo ($canon_cwd) — aborting" >&2
    return 2
  fi
  git init -q
  git commit --allow-empty -m "init" -q
  # Stub PARALLEL_MODE so the function's ternary works
  PARALLEL_MODE=false
  NON_INTERACTIVE=true
  export PARALLEL_MODE NON_INTERACTIVE
  # Source just the generator function
  # shellcheck disable=SC1091
  source <(awk '/^generate_observations\(\) \{/,/^\}$/' "$REPO_ROOT/quantum-loop.sh")
  generate_observations
}

echo "=== Phase 6 Observation-Generator Tests ==="

# Test 1: Failures produce a populated Progress Log table
echo ""
echo "Test 1: Failed story -> populated Progress Log table"
TMP1=$(mktemp -d)
cat > "$TMP1/quantum.json" << 'EOF'
{
  "branchName": "ql/test-feature",
  "stories": [
    {
      "id": "US-001", "title": "Implement widget", "status": "failed",
      "retries": {"attempts": 2, "maxAttempts": 3, "failureLog": [
        {"phase": "typecheck", "timestamp": "2026-04-22T10:00:00Z", "error": "Type X is missing"}
      ]}
    }
  ],
  "progress": [
    {"timestamp": "2026-04-22T10:05:00Z", "storyId": "US-001", "action": "story_failed", "learnings": "Always materialize cross-story contracts before wave start"}
  ]
}
EOF
(run_generator_in_tempdir "$TMP1" >/dev/null 2>&1) || echo "  WARN: generator exited non-zero"
obs1=$(find "$TMP1/docs/post-mortems" -name "*-observations.md" 2>/dev/null | head -1)
if [[ -z "$obs1" ]]; then
  echo "  FAIL: observation file not created"
  FAIL=$((FAIL + 1)); TOTAL=$((TOTAL + 1))
else
  assert_contains "Progress Log header present" "## Progress Log" "$obs1"
  assert_contains "table column header" "| Story | Phase / Action |" "$obs1"
  assert_contains "US-001 row emitted" "US-001" "$obs1"
  assert_contains "typecheck phase noted" "typecheck" "$obs1"
  assert_contains "Type X error excerpt" "Type X is missing" "$obs1"
  assert_not_contains "no empty-log fallback" "_No failed / retried stories" "$obs1"
fi
rm -rf "$TMP1"

# Test 2: No failures -> explicit "empty" copy, not a blank section
echo ""
echo "Test 2: All-passed run -> explicit empty-log copy"
TMP2=$(mktemp -d)
cat > "$TMP2/quantum.json" << 'EOF'
{
  "branchName": "ql/clean-run",
  "stories": [
    {"id": "US-001", "title": "Happy path", "status": "passed",
     "retries": {"attempts": 0, "maxAttempts": 3, "failureLog": []}}
  ],
  "progress": []
}
EOF
(run_generator_in_tempdir "$TMP2" >/dev/null 2>&1) || true
obs2=$(find "$TMP2/docs/post-mortems" -name "*-observations.md" 2>/dev/null | head -1)
if [[ -z "$obs2" ]]; then
  echo "  FAIL: observation file not created"
  FAIL=$((FAIL + 1)); TOTAL=$((TOTAL + 1))
else
  assert_contains "empty-log copy shown" "_No failed / retried stories" "$obs2"
  assert_not_contains "no stray table header" "| Story | Phase / Action |" "$obs2"
fi
rm -rf "$TMP2"

# Test 3: Lessons promoted into codebasePatterns
echo ""
echo "Test 3: Generalizable lessons promoted into codebasePatterns"
TMP3=$(mktemp -d)
cat > "$TMP3/quantum.json" << 'EOF'
{
  "branchName": "ql/lesson-promo",
  "stories": [
    {"id": "US-001", "title": "learned a lesson", "status": "passed",
     "retries": {"attempts": 1, "maxAttempts": 3, "failureLog": []}}
  ],
  "progress": [
    {"timestamp": "2026-04-22T11:00:00Z", "storyId": "US-001", "action": "story_passed",
     "learnings": "Run bash tests in isolated tempdir to avoid leaking files into repo."}
  ],
  "codebasePatterns": []
}
EOF
(run_generator_in_tempdir "$TMP3" >/dev/null 2>&1) || true
pattern_count=$(jq -r '.codebasePatterns | length' "$TMP3/quantum.json" 2>/dev/null || echo 0)
assert "codebasePatterns grew by 1" "1" "$pattern_count"
promoted=$(jq -r '.codebasePatterns[0]' "$TMP3/quantum.json" 2>/dev/null)
assert_contains_str() {
  local name="$1" needle="$2" haystack="$3"
  TOTAL=$((TOTAL + 1))
  if echo "$haystack" | grep -qF "$needle"; then
    echo "  PASS: $name"; PASS=$((PASS + 1))
  else
    echo "  FAIL: $name (needle=[$needle] in [$haystack])"; FAIL=$((FAIL + 1))
  fi
}
assert_contains_str "lesson text promoted" "Run bash tests in isolated tempdir" "$promoted"
rm -rf "$TMP3"

# Test 4: Regression guard — generator must NOT write into the real repo
echo ""
echo "Test 4: Regression guard — no stub leaks into real docs/post-mortems/"
before_count=$(find "$REPO_ROOT/docs/post-mortems" -type f 2>/dev/null | wc -l)
TMP4=$(mktemp -d)
cat > "$TMP4/quantum.json" << 'EOF'
{"branchName": "ql/no-leak-probe", "stories": [], "progress": []}
EOF
(run_generator_in_tempdir "$TMP4" >/dev/null 2>&1) || true
after_count=$(find "$REPO_ROOT/docs/post-mortems" -type f 2>/dev/null | wc -l)
assert "real post-mortems dir unchanged" "$before_count" "$after_count"
rm -rf "$TMP4"

echo ""
echo "=== Results: $PASS/$TOTAL passed, $FAIL failed ==="
exit $((FAIL > 0 ? 1 : 0))
