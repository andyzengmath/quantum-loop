#!/usr/bin/env bash
# Phase 18 / P2.4 — tests for phase-skip artifact detection.

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
source "$REPO_ROOT/lib/phase-skip.sh"

echo "=== Phase 18 phase-skip tests ==="

# Test 1: artifact_hash stable and returns "" for missing files
echo ""
echo "Test 1: artifact_hash basics"
TEST_TMPDIR=$(mktemp -d)
echo "hello world" > "$TEST_TMPDIR/a.txt"
h1=$(artifact_hash "$TEST_TMPDIR/a.txt")
h2=$(artifact_hash "$TEST_TMPDIR/a.txt")
assert "hash stable across calls" "$h1" "$h2"
[[ ${#h1} -eq 64 ]] && { echo "  PASS: hash is 64 hex chars"; PASS=$((PASS + 1)); } \
                    || { echo "  FAIL: hash not 64 chars"; FAIL=$((FAIL + 1)); }
TOTAL=$((TOTAL + 1))
h_missing=$(artifact_hash "$TEST_TMPDIR/nope.txt")
assert "missing file -> empty hash" "" "$h_missing"
rm -rf "$TEST_TMPDIR"

# Test 2: artifact_hash changes when content changes
echo ""
echo "Test 2: artifact_hash differs on content change"
TEST_TMPDIR=$(mktemp -d)
echo "v1" > "$TEST_TMPDIR/f.txt"
h1=$(artifact_hash "$TEST_TMPDIR/f.txt")
echo "v2" > "$TEST_TMPDIR/f.txt"
h2=$(artifact_hash "$TEST_TMPDIR/f.txt")
if [[ "$h1" != "$h2" ]]; then
  echo "  PASS: hashes differ"; PASS=$((PASS + 1))
else
  echo "  FAIL: hashes should differ"; FAIL=$((FAIL + 1))
fi
TOTAL=$((TOTAL + 1))
rm -rf "$TEST_TMPDIR"

# Test 3: artifact_hash_inline produces a stable 64-char hash
echo ""
echo "Test 3: artifact_hash_inline"
h=$(artifact_hash_inline "some intent text")
h2=$(artifact_hash_inline "some intent text")
assert "inline hash stable" "$h" "$h2"
h3=$(artifact_hash_inline "different")
if [[ "$h" != "$h3" ]]; then
  echo "  PASS: inline hash differs on content change"; PASS=$((PASS + 1))
else
  echo "  FAIL: inline hash should differ"; FAIL=$((FAIL + 1))
fi
TOTAL=$((TOTAL + 1))

# Test 4: record_fingerprint + read_fingerprint round-trip
echo ""
echo "Test 4: record + read round-trip"
TEST_TMPDIR=$(mktemp -d)
mkdir -p "$TEST_TMPDIR/docs/plans"
echo "design v1" > "$TEST_TMPDIR/docs/plans/design.md"
designhash=$(artifact_hash "$TEST_TMPDIR/docs/plans/design.md")
fp_body=$(jq -cn --arg p "docs/plans/design.md" --arg h "$designhash" \
  '{artifacts: [{path: $p, sha256: $h, size: 10}]}')
record_fingerprint "brainstorm" "$fp_body" "$TEST_TMPDIR" >/dev/null
read_out=$(read_fingerprint "brainstorm" "$TEST_TMPDIR")
assert "stage round-trips" "brainstorm" "$(jq -r '.stage' <<< "$read_out")"
assert "artifact count" "1" "$(jq '.artifacts | length' <<< "$read_out")"
assert "sha256 round-trips" "$designhash" "$(jq -r '.artifacts[0].sha256' <<< "$read_out")"
ts=$(jq -r '.recorded_at' <<< "$read_out")
[[ -n "$ts" ]] && { echo "  PASS: recorded_at non-empty"; PASS=$((PASS + 1)); } \
              || { echo "  FAIL: recorded_at empty"; FAIL=$((FAIL + 1)); }
TOTAL=$((TOTAL + 1))
rm -rf "$TEST_TMPDIR"

# Test 5: read_fingerprint returns {} when absent
echo ""
echo "Test 5: read_fingerprint on missing file"
TEST_TMPDIR=$(mktemp -d)
out=$(read_fingerprint "nonexistent" "$TEST_TMPDIR")
assert "missing -> {}" "{}" "$out"
rm -rf "$TEST_TMPDIR"

# Test 6: should_skip_stage — fresh all-match returns 0 (skip)
echo ""
echo "Test 6: should_skip_stage when all artifacts fresh"
TEST_TMPDIR=$(mktemp -d)
mkdir -p "$TEST_TMPDIR/docs/plans"
echo "design" > "$TEST_TMPDIR/docs/plans/design.md"
h=$(cd "$TEST_TMPDIR" && artifact_hash "docs/plans/design.md")
fp=$(jq -cn --arg p "docs/plans/design.md" --arg s "$h" \
  '{artifacts: [{path: $p, sha256: $s}]}')
record_fingerprint "brainstorm" "$fp" "$TEST_TMPDIR" >/dev/null
(cd "$TEST_TMPDIR" && should_skip_stage "brainstorm" "." "docs/plans/design.md")
assert "all-fresh -> skip (exit 0)" "0" "$?"
rm -rf "$TEST_TMPDIR"

# Test 7: should_skip_stage — file changed returns 1 (re-run)
echo ""
echo "Test 7: should_skip_stage after content change"
TEST_TMPDIR=$(mktemp -d)
mkdir -p "$TEST_TMPDIR/docs/plans"
echo "v1" > "$TEST_TMPDIR/docs/plans/design.md"
h=$(cd "$TEST_TMPDIR" && artifact_hash "docs/plans/design.md")
fp=$(jq -cn --arg p "docs/plans/design.md" --arg s "$h" \
  '{artifacts: [{path: $p, sha256: $s}]}')
record_fingerprint "brainstorm" "$fp" "$TEST_TMPDIR" >/dev/null
# Mutate the file
echo "v2" > "$TEST_TMPDIR/docs/plans/design.md"
(cd "$TEST_TMPDIR" && should_skip_stage "brainstorm" "." "docs/plans/design.md")
assert "content changed -> re-run (exit 1)" "1" "$?"
rm -rf "$TEST_TMPDIR"

# Test 8: should_skip_stage — no prior record returns 1
echo ""
echo "Test 8: should_skip_stage without any record"
TEST_TMPDIR=$(mktemp -d)
mkdir -p "$TEST_TMPDIR/docs/plans"
echo "design" > "$TEST_TMPDIR/docs/plans/design.md"
(cd "$TEST_TMPDIR" && should_skip_stage "brainstorm" "." "docs/plans/design.md")
assert "no record -> re-run (exit 1)" "1" "$?"
rm -rf "$TEST_TMPDIR"

# Test 9: should_skip_stage — fingerprint artifact count mismatch returns 1
echo ""
echo "Test 9: artifact count mismatch rejects"
TEST_TMPDIR=$(mktemp -d)
mkdir -p "$TEST_TMPDIR/docs/plans"
echo "d" > "$TEST_TMPDIR/docs/plans/design.md"
echo "x" > "$TEST_TMPDIR/docs/plans/extra.md"
h1=$(cd "$TEST_TMPDIR" && artifact_hash "docs/plans/design.md")
# Record only 1 artifact
fp=$(jq -cn --arg p "docs/plans/design.md" --arg s "$h1" \
  '{artifacts: [{path: $p, sha256: $s}]}')
record_fingerprint "brainstorm" "$fp" "$TEST_TMPDIR" >/dev/null
# Call with 2 artifacts — mismatch
(cd "$TEST_TMPDIR" && should_skip_stage "brainstorm" "." "docs/plans/design.md" "docs/plans/extra.md")
assert "count mismatch -> re-run (exit 1)" "1" "$?"
rm -rf "$TEST_TMPDIR"

# Test 10: should_skip_stage handles inline: escape
echo ""
echo "Test 10: inline: escape class"
TEST_TMPDIR=$(mktemp -d)
intent_h=$(artifact_hash_inline "Build a todo app")
fp=$(jq -cn --arg p "inline://Build a todo app" --arg s "$intent_h" \
  '{artifacts: [{path: $p, sha256: $s}]}')
record_fingerprint "brainstorm" "$fp" "$TEST_TMPDIR" >/dev/null
# Same intent text -> skip
(cd "$TEST_TMPDIR" && should_skip_stage "brainstorm" "." "inline:Build a todo app")
assert "inline matches -> skip" "0" "$?"
# Different intent -> re-run
(cd "$TEST_TMPDIR" && should_skip_stage "brainstorm" "." "inline:different idea")
assert "inline mismatches -> re-run" "1" "$?"
rm -rf "$TEST_TMPDIR"

# Test 11: CLI subcommands
echo ""
echo "Test 11: CLI subcommands"
TEST_TMPDIR=$(mktemp -d)
echo "test" > "$TEST_TMPDIR/f.txt"
cli_h=$(bash "$REPO_ROOT/lib/phase-skip.sh" hash "$TEST_TMPDIR/f.txt" | tr -d '\n')
lib_h=$(artifact_hash "$TEST_TMPDIR/f.txt")
assert "CLI hash matches lib hash" "$lib_h" "$cli_h"
cli_inline=$(bash "$REPO_ROOT/lib/phase-skip.sh" inline "xyz" | tr -d '\n')
lib_inline=$(artifact_hash_inline "xyz")
assert "CLI inline matches lib inline" "$lib_inline" "$cli_inline"
rm -rf "$TEST_TMPDIR"

# Test 12: skill prompts wire the phase-skip protocol
echo ""
echo "Test 12: skills reference lib/phase-skip.sh"
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
check_in "brainstorm Phase 0 section"           "Phase 0: Phase-skip check"       "skills/ql-brainstorm/SKILL.md"
check_in "brainstorm calls phase-skip skip"     "lib/phase-skip.sh skip brainstorm" "skills/ql-brainstorm/SKILL.md"
check_in "brainstorm records fingerprint"       "lib/phase-skip.sh record brainstorm" "skills/ql-brainstorm/SKILL.md"
check_in "spec Phase 0 section"                 "Phase 0: Phase-skip check"       "skills/ql-spec/SKILL.md"
check_in "spec calls phase-skip skip"           "lib/phase-skip.sh skip spec"     "skills/ql-spec/SKILL.md"
check_in "spec records fingerprint"             "lib/phase-skip.sh record spec"   "skills/ql-spec/SKILL.md"
check_in "plan Phase 0 section"                 "Phase 0: Phase-skip check"       "skills/ql-plan/SKILL.md"
check_in "plan calls phase-skip skip"           "lib/phase-skip.sh skip plan"     "skills/ql-plan/SKILL.md"
check_in "plan records fingerprint"             "lib/phase-skip.sh record plan"   "skills/ql-plan/SKILL.md"

echo ""
echo "=== Results: $PASS/$TOTAL passed, $FAIL failed ==="
exit $((FAIL > 0 ? 1 : 0))
