#!/usr/bin/env bash
# Phase 14 / P2.5 + P2.7 — tests for implementer self-review checklist +
# commit-trailer protocol parser.

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

check_prompt() {
  local name="$1" needle="$2" file="$3"
  TOTAL=$((TOTAL + 1))
  if grep -qF -- "$needle" "$file"; then
    echo "  PASS: $name"; PASS=$((PASS + 1))
  else
    echo "  FAIL: $name — needle [$needle] not in $file"
    FAIL=$((FAIL + 1))
  fi
}

# shellcheck disable=SC1091
source "$REPO_ROOT/lib/commit-trailers.sh"

IMP="$REPO_ROOT/agents/implementer.md"

echo "=== Phase 14 P2.5 + P2.7 tests ==="

# Test 1: implementer.md has the self-review checklist section
echo ""
echo "Test 1: P2.5 self-review checklist prompt"
check_prompt "self-review checklist header" "Self-review checklist (P2.5" "$IMP"
check_prompt "four categories Completeness" "**Completeness**" "$IMP"
check_prompt "four categories Quality" "**Quality**" "$IMP"
check_prompt "four categories Discipline" "**Discipline**" "$IMP"
check_prompt "four categories Testing" "**Testing**" "$IMP"
check_prompt "claim-check self-scan item" "Claim-check self-scan" "$IMP"
check_prompt "AC evidence line item" "Every acceptance criterion has a concrete evidence" "$IMP"
check_prompt "wiring_verification item" "wiring_verification.must_contain" "$IMP"
check_prompt "consumedBy item" "consumedBy" "$IMP"
check_prompt "don't modify tests reminder" "did NOT modify a test" "$IMP"

# Test 2: implementer.md has the commit-trailer protocol section
echo ""
echo "Test 2: P2.7 commit-trailer protocol"
check_prompt "Commit Format (P2.7) header" "Commit Format (P2.7" "$IMP"
check_prompt "Confidence trailer" "Confidence: high | medium | low" "$IMP"
check_prompt "Scope-risk trailer" "Scope-risk: none | contained | spreads" "$IMP"
check_prompt "Rejected trailer" "Rejected: <option | reason>" "$IMP"
check_prompt "Deslop trailer" "Deslop: ran | skipped" "$IMP"
check_prompt "Not-tested trailer" "Not-tested: <path" "$IMP"
check_prompt "references lib/commit-trailers.sh" "lib/commit-trailers.sh" "$IMP"
check_prompt "Rejected may repeat" "MAY appear multiple times" "$IMP"

# Test 3: parse_trailers handles a canonical message
echo ""
echo "Test 3: parse_trailers — canonical message"
msg='feat: US-042 - Add priority field

Implement priority column with default medium and migrate existing rows.

Story: US-042
Story-Title: Add priority field
PRD: tasks/prd-task-priority.md#AC-1
Files-changed: 3
Constraint: must preserve existing rows
Rejected: enum at app layer | prefers DB-level constraint
Rejected: new table | too much migration churn
Confidence: high
Scope-risk: contained
Not-tested: migration rollback path | low risk, manual test only
Deslop: ran'
parsed=$(printf '%s\n' "$msg" | parse_trailers)
story=$(jq -r '.Story' <<< "$parsed")
conf=$(jq -r '.Confidence' <<< "$parsed")
risk=$(jq -r '."Scope-risk"' <<< "$parsed")
nt=$(jq -r '."Not-tested"' <<< "$parsed")
rejected_n=$(jq -r '.Rejected | length' <<< "$parsed")
prd=$(jq -r '.PRD' <<< "$parsed")
deslop=$(jq -r '.Deslop' <<< "$parsed")
assert "Story US-042" "US-042" "$story"
assert "Confidence high" "high" "$conf"
assert "Scope-risk contained" "contained" "$risk"
assert "Not-tested populated" "migration rollback path | low risk, manual test only" "$nt"
assert "Rejected array has 2 entries" "2" "$rejected_n"
assert "PRD path captured" "tasks/prd-task-priority.md#AC-1" "$prd"
assert "Deslop captured" "ran" "$deslop"

# Test 4: unknown trailer keys are ignored
echo ""
echo "Test 4: unknown trailer keys ignored"
msg='feat: commit

Story: US-001
Confidence: medium
Scope-risk: none
MadeUpKey: ignore me
Signed-off-by: someone (this is standard-git, not our protocol)'
parsed=$(printf '%s\n' "$msg" | parse_trailers)
has_madeup=$(jq -r 'has("MadeUpKey")' <<< "$parsed")
has_signoff=$(jq -r 'has("Signed-off-by")' <<< "$parsed")
assert "unknown MadeUpKey dropped" "false" "$has_madeup"
assert "unknown Signed-off-by dropped" "false" "$has_signoff"

# Test 5: validate_trailers — well-formed passes
echo ""
echo "Test 5: validate_trailers — well-formed passes"
msg='feat: US-100 - ok

Story: US-100
Confidence: medium
Scope-risk: none'
printf '%s\n' "$msg" | validate_trailers 2>/dev/null
assert "well-formed exits 0" "0" "$?"

# Test 6: validate_trailers — missing Story fails
echo ""
echo "Test 6: validate_trailers — missing Story fails"
msg='feat: bad

Confidence: high
Scope-risk: none'
printf '%s\n' "$msg" | validate_trailers 2>/dev/null
assert "missing Story exits non-zero" "1" "$?"

# Test 7: Confidence: low without Rejected fails
echo ""
echo "Test 7: validate_trailers — low confidence without Rejected fails"
msg='feat: US-200 - low confidence commit

Story: US-200
Confidence: low
Scope-risk: contained'
printf '%s\n' "$msg" | validate_trailers 2>/dev/null
assert "Confidence: low without Rejected fails" "1" "$?"

# Test 8: Confidence: low WITH Rejected passes
echo ""
echo "Test 8: validate_trailers — low confidence WITH Rejected passes"
msg='feat: US-201 - low confidence commit

Story: US-201
Confidence: low
Scope-risk: contained
Rejected: alternative A | too risky'
printf '%s\n' "$msg" | validate_trailers 2>/dev/null
assert "Confidence: low with Rejected passes" "0" "$?"

# Test 9: bad Scope-risk value rejected
echo ""
echo "Test 9: bad Scope-risk value rejected"
msg='feat: US-300 - broken risk

Story: US-300
Confidence: high
Scope-risk: whatever'
printf '%s\n' "$msg" | validate_trailers 2>/dev/null
assert "Scope-risk whatever fails" "1" "$?"

# Test 10: CLI parse subcommand
echo ""
echo "Test 10: CLI parse subcommand"
cli_out=$(printf 'feat: test\n\nStory: US-500\nConfidence: high\nScope-risk: none\n' | bash "$REPO_ROOT/lib/commit-trailers.sh" parse | jq -r '.Story')
assert "CLI parse Story round-trips" "US-500" "$cli_out"

# Test 11: extract_commit on HEAD (integration — this repo's HEAD is well-formed enough)
echo ""
echo "Test 11: extract_commit on a real commit"
parsed=$(extract_commit HEAD)
# HEAD may or may not use the new format. Just verify the parser doesn't crash
# and returns a JSON object with the Rejected key (even if empty array).
has_rejected=$(jq -r 'has("Rejected")' <<< "$parsed")
assert "extract_commit produces JSON with Rejected key" "true" "$has_rejected"

echo ""
echo "=== Results: $PASS/$TOTAL passed, $FAIL failed ==="
exit $((FAIL > 0 ? 1 : 0))
