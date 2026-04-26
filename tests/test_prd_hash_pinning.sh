#!/usr/bin/env bash
# US-005 / P5.A5 — verify PRD hash-pinning (RAGShield Level-1).
# compute_prd_sha() yields a stable sha256 of PRD content.
# Orchestrator pre-flight detects mismatched prdSha and marks the story stale.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$SCRIPT_DIR/.."
JSON_ATOMIC="$REPO_ROOT/lib/json-atomic.sh"
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

assert_neq() {
  local name="$1" forbidden="$2" actual="$3"
  TOTAL=$((TOTAL + 1))
  if [[ "$forbidden" != "$actual" ]]; then
    echo "  PASS: $name"; PASS=$((PASS + 1))
  else
    echo "  FAIL: $name (got the forbidden value [$forbidden])"
    FAIL=$((FAIL + 1))
  fi
}

# shellcheck disable=SC1090
source "$JSON_ATOMIC"

echo "=== US-005 PRD hash-pinning tests ==="

# Test 1: compute_prd_sha helper exists + produces stable hash
echo ""
echo "Test 1: compute_prd_sha produces stable sha256"
TMP=$(mktemp -d)
PRD="$TMP/prd.md"
printf "# PRD\n\nSome content here.\n" > "$PRD"

TOTAL=$((TOTAL + 1))
if declare -f compute_prd_sha >/dev/null 2>&1; then
  echo "  PASS: compute_prd_sha helper defined"; PASS=$((PASS + 1))
else
  echo "  FAIL: compute_prd_sha helper not defined"; FAIL=$((FAIL + 1))
fi

sha1=$(compute_prd_sha "$PRD")
sha2=$(compute_prd_sha "$PRD")
assert_eq "compute_prd_sha is deterministic" "$sha1" "$sha2"

TOTAL=$((TOTAL + 1))
if [[ "$sha1" =~ ^[0-9a-f]{64}$ ]]; then
  echo "  PASS: sha is 64-hex-char sha256"; PASS=$((PASS + 1))
else
  echo "  FAIL: sha is not a sha256 hex string (got [$sha1])"; FAIL=$((FAIL + 1))
fi

# Trailing whitespace should not change the hash
printf "# PRD\n\nSome content here.\n   \n   \t\n" > "$PRD"
sha3=$(compute_prd_sha "$PRD")
assert_eq "trailing whitespace ignored" "$sha1" "$sha3"

# Content change DOES change the hash
printf "# PRD\n\nDifferent content.\n" > "$PRD"
sha4=$(compute_prd_sha "$PRD")
assert_neq "content change yields different hash" "$sha1" "$sha4"

# Test 2: mismatched prdSha sets story stale (via orchestrator pre-flight pseudocode)
echo ""
echo "Test 2: mismatched prdSha -> story marked 'stale'"
# Build a fixture quantum.json with one story having a stale prdSha.
QJ="$TMP/quantum.json"
cat > "$QJ" << 'EOF'
{
  "branchName": "ql/test",
  "prdPath": "prd.md",
  "stories": [
    {"id": "US-001", "status": "pending", "prdSha": "deadbeef0000"},
    {"id": "US-002", "status": "pending", "prdSha": null}
  ]
}
EOF

# Compute current PRD sha (PRD was just rewritten above, so it's sha4)
current_sha=$(compute_prd_sha "$PRD")

# Apply pre-flight check inline (this mirrors orchestrator Step 1.1 logic)
out=$(jq --arg cs "$current_sha" '
  .stories |= map(
    if .prdSha != null and .prdSha != $cs then .status = "stale"
    else . end
  )
' "$QJ")

us1_status=$(printf '%s' "$out" | jq -r '.stories[] | select(.id=="US-001") | .status')
us2_status=$(printf '%s' "$out" | jq -r '.stories[] | select(.id=="US-002") | .status')

assert_eq "US-001 with stale hash -> stale" "stale" "$us1_status"
assert_eq "US-002 with null prdSha -> pending (back-compat)" "pending" "$us2_status"

# Test 3: matching prdSha -> story stays pending
echo ""
echo "Test 3: matching prdSha -> story executes normally"
cat > "$QJ" << EOF
{
  "branchName": "ql/test",
  "prdPath": "prd.md",
  "stories": [
    {"id": "US-001", "status": "pending", "prdSha": "$current_sha"}
  ]
}
EOF
out=$(jq --arg cs "$current_sha" '
  .stories |= map(
    if .prdSha != null and .prdSha != $cs then .status = "stale"
    else . end
  )
' "$QJ")
us1_status=$(printf '%s' "$out" | jq -r '.stories[] | select(.id=="US-001") | .status')
assert_eq "matching prdSha -> still pending" "pending" "$us1_status"

# Test 4: orchestrator.md documents the Step 1.1 hash-check
echo ""
echo "Test 4: orchestrator.md describes Step 1.1 hash-check"
TOTAL=$((TOTAL + 1))
if grep -qF "compute_prd_sha" "$REPO_ROOT/agents/orchestrator.md"; then
  echo "  PASS: orchestrator references compute_prd_sha"; PASS=$((PASS + 1))
else
  echo "  FAIL: orchestrator missing compute_prd_sha reference"; FAIL=$((FAIL + 1))
fi

TOTAL=$((TOTAL + 1))
if grep -qE "prdSha|stale" "$REPO_ROOT/agents/orchestrator.md"; then
  echo "  PASS: orchestrator references prdSha or stale state"; PASS=$((PASS + 1))
else
  echo "  FAIL: orchestrator missing prdSha/stale wording"; FAIL=$((FAIL + 1))
fi

# Test 5: dag-validator emits prdSha when creating story stubs
echo ""
echo "Test 5: dag-validator.md mentions prdSha emission"
TOTAL=$((TOTAL + 1))
if grep -qF "prdSha" "$REPO_ROOT/agents/dag-validator.md"; then
  echo "  PASS: dag-validator references prdSha"; PASS=$((PASS + 1))
else
  echo "  FAIL: dag-validator missing prdSha reference"; FAIL=$((FAIL + 1))
fi

# Test 6: quantum.json.example documents prdSha
echo ""
echo "Test 6: quantum.json.example documents prdSha field"
TOTAL=$((TOTAL + 1))
if grep -qF "prdSha" "$REPO_ROOT/quantum.json.example"; then
  echo "  PASS: quantum.json.example documents prdSha"; PASS=$((PASS + 1))
else
  echo "  FAIL: quantum.json.example missing prdSha"; FAIL=$((FAIL + 1))
fi

# Cleanup
rm -rf "$TMP"

echo ""
echo "=== Results: $PASS/$TOTAL passed, $FAIL failed ==="
[[ $FAIL -eq 0 ]] || exit 1
