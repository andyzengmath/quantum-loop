#!/usr/bin/env bash
# Phase 11 — tests for lib/wave-boundary.sh divergent-constants scan.
# Creates a tempdir git repo with two stories whose constants diverge
# (the Math-Research 'google' vs 'google-api-key' regression class) and
# verifies the scan flags it, while clean cases pass through.

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
source "$REPO_ROOT/lib/wave-boundary.sh"

echo "=== Phase 11 wave-boundary helper tests ==="

# Test 1: canonicalize strips known suffixes
echo ""
echo "Test 1: canonicalize"
assert "google stays google"                "google"     "$(canonicalize "google")"
assert "google-api-key -> google"           "google"     "$(canonicalize "google-api-key")"
assert "GOOGLE_API_KEY -> google"           "google"     "$(canonicalize "GOOGLE_API_KEY")"
assert "openai-token -> openai"             "openai"     "$(canonicalize "openai-token")"
assert "slack_secret -> slack"              "slack"      "$(canonicalize "slack_secret")"
assert "database-url -> database"           "database"   "$(canonicalize "database-url")"
assert "user_id -> user"                    "user"       "$(canonicalize "user_id")"
assert "my-token -> my (token suffix stripped)" "my" "$(canonicalize "my-token")"

# Test 2: scan detects divergent constants across stories
echo ""
echo "Test 2: divergent constants flagged"
TEST_TMPDIR=$(mktemp -d)
cd "$TEST_TMPDIR"
git init -q
git commit --allow-empty -m "init" -q
BASE=$(git rev-parse HEAD)
# Story A: uses 'google' as the provider key
cat > provider_a.ts << 'EOF'
export const providers = {};
providers['google'] = { enabled: true };
EOF
git add provider_a.ts; git commit -q -m "story A: google provider"
# Story B: uses 'google-api-key' for the same concept — different literal
cat > provider_b.ts << 'EOF'
export function getGoogleKey() {
  return process.env['google-api-key'];
}
EOF
git add provider_b.ts; git commit -q -m "story B: google key lookup"
HEAD_S=$(git rev-parse HEAD)

findings=$(scan_divergent_constants "$BASE" "$HEAD_S")
count=$(printf '%s' "$findings" | jq 'length')
assert "one finding emitted" "1" "$count"
canonical=$(printf '%s' "$findings" | jq -r '.[0].canonical')
assert "canonical is google" "google" "$canonical"
n_variants=$(printf '%s' "$findings" | jq '.[0].variants | length')
assert "2 variants recorded" "2" "$n_variants"
severity=$(printf '%s' "$findings" | jq -r '.[0].severity')
assert "severity is medium (2 distinct literals)" "medium" "$severity"

# has_divergence gate
has_divergence "$BASE" "$HEAD_S"
assert "gate exits 0 when divergent" "0" "$?"

cd "$REPO_ROOT"
rm -rf "$TEST_TMPDIR"

# Test 3: clean case (same literal across stories) does not flag
echo ""
echo "Test 3: clean case — same literal reused"
TEST_TMPDIR=$(mktemp -d)
cd "$TEST_TMPDIR"
git init -q
git commit --allow-empty -m "init" -q
BASE=$(git rev-parse HEAD)
cat > a.ts << 'EOF'
export const K = 'google';
EOF
git add a.ts; git commit -q -m "story A"
cat > b.ts << 'EOF'
export const USE = 'google';
EOF
git add b.ts; git commit -q -m "story B"
HEAD_S=$(git rev-parse HEAD)

findings=$(scan_divergent_constants "$BASE" "$HEAD_S")
count=$(printf '%s' "$findings" | jq 'length')
assert "clean case has no findings" "0" "$count"

has_divergence "$BASE" "$HEAD_S"
assert "gate exits 1 when clean" "1" "$?"

cd "$REPO_ROOT"
rm -rf "$TEST_TMPDIR"

# Test 4: three distinct variants → severity high
echo ""
echo "Test 4: three distinct variants → severity high"
TEST_TMPDIR=$(mktemp -d)
cd "$TEST_TMPDIR"
git init -q
git commit --allow-empty -m "init" -q
BASE=$(git rev-parse HEAD)
echo "const x = 'openai';"          > a.ts; git add a.ts; git commit -q -m "A"
echo "const y = 'openai-api-key';"  > b.ts; git add b.ts; git commit -q -m "B"
echo "const z = 'openai-token';"    > c.ts; git add c.ts; git commit -q -m "C"
HEAD_S=$(git rev-parse HEAD)

findings=$(scan_divergent_constants "$BASE" "$HEAD_S")
severity=$(printf '%s' "$findings" | jq -r '.[0].severity')
assert "severity is high (3 distinct literals)" "high" "$severity"

cd "$REPO_ROOT"
rm -rf "$TEST_TMPDIR"

# Test 5: single-file divergence is ignored (must span ≥2 files)
echo ""
echo "Test 5: single-file divergence not flagged"
TEST_TMPDIR=$(mktemp -d)
cd "$TEST_TMPDIR"
git init -q
git commit --allow-empty -m "init" -q
BASE=$(git rev-parse HEAD)
# Two variants but in the same file (refactor artifact, not a wave defect)
cat > only.ts << 'EOF'
const legacy = 'google';
const current = 'google-api-key';
EOF
git add only.ts; git commit -q -m "refactor in one file"
HEAD_S=$(git rev-parse HEAD)

findings=$(scan_divergent_constants "$BASE" "$HEAD_S")
count=$(printf '%s' "$findings" | jq 'length')
assert "single-file divergence not flagged" "0" "$count"

cd "$REPO_ROOT"
rm -rf "$TEST_TMPDIR"

# Test 6: short / non-identifier literals filtered out (no false positives on sentences)
echo ""
echo "Test 6: short and sentence-style literals filtered"
TEST_TMPDIR=$(mktemp -d)
cd "$TEST_TMPDIR"
git init -q
git commit --allow-empty -m "init" -q
BASE=$(git rev-parse HEAD)
cat > a.ts << 'EOF'
throw new Error('xx');
const greeting = 'hello world';
EOF
git add a.ts; git commit -q -m "A"
cat > b.ts << 'EOF'
throw new Error('zz');
const other = 'hello there';
EOF
git add b.ts; git commit -q -m "B"
HEAD_S=$(git rev-parse HEAD)

findings=$(scan_divergent_constants "$BASE" "$HEAD_S")
count=$(printf '%s' "$findings" | jq 'length')
assert "short/sentence literals don't spurious-match" "0" "$count"

cd "$REPO_ROOT"
rm -rf "$TEST_TMPDIR"

# Test 7: CLI entry works
echo ""
echo "Test 7: CLI canonicalize subcommand"
out=$(bash "$REPO_ROOT/lib/wave-boundary.sh" canonicalize "slack-api-token" | tr -d '\n')
assert "CLI canonicalize slack-api-token -> slack" "slack" "$out"

echo ""
echo "=== Results: $PASS/$TOTAL passed, $FAIL failed ==="
exit $((FAIL > 0 ? 1 : 0))
