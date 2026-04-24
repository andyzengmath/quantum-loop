#!/usr/bin/env bash
# Phase 22 / P3.11 — tests for lib/constitution.sh constitutional constraints.

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
source "$REPO_ROOT/lib/constitution.sh"

echo "=== Phase 22 constitution tests ==="

# Test 1: load_constitution reads rule IDs from quantum.json
echo ""
echo "Test 1: load_constitution"
TEST_TMPDIR=$(mktemp -d)
cat > "$TEST_TMPDIR/quantum.json" << 'EOF'
{
  "constitution": ["no-secrets", "no-sql-injection"]
}
EOF
load_constitution "$TEST_TMPDIR/quantum.json"
assert "loads 2 rules" "no-secrets no-sql-injection" "$CONSTITUTION_ACTIVE_RULES"
# Missing field -> empty
echo '{}' > "$TEST_TMPDIR/empty.json"
load_constitution "$TEST_TMPDIR/empty.json"
assert "missing constitution -> empty" "" "$CONSTITUTION_ACTIVE_RULES"
# Missing file -> empty, no error
load_constitution "$TEST_TMPDIR/nope.json"
assert "missing file -> empty" "" "$CONSTITUTION_ACTIVE_RULES"
# Object form
cat > "$TEST_TMPDIR/obj.json" << 'EOF'
{"constitution":[{"rule":"no-secrets","enabled":true}]}
EOF
load_constitution "$TEST_TMPDIR/obj.json"
assert "object form with .rule" "no-secrets" "$CONSTITUTION_ACTIVE_RULES"
rm -rf "$TEST_TMPDIR"

# Test 2: check_no_secrets catches known provider tokens
echo ""
echo "Test 2: check_no_secrets detects provider tokens"
DIFF=$(mktemp)
cat > "$DIFF" << 'EOF'
diff --git a/src/config.js b/src/config.js
+++ b/src/config.js
@@ -1,3 +1,3 @@
+const stripeKey = "sk-live_abcdef1234567890XYZ"
+const githubToken = "ghp_aBcDeFgHiJkLmNoPqRsTuVwXyZ012345"
+const okayLine = "just a comment about passwords"
EOF
findings=$(check_no_secrets "$DIFF")
found_stripe=$(echo "$findings" | grep -c "stripeKey" || true)
found_github=$(echo "$findings" | grep -c "ghp_" || true)
benign=$(echo "$findings" | grep -c "okayLine" || true)
assert "detects sk-live token" "1" "$found_stripe"
assert "detects ghp_ token" "1" "$found_github"
assert "ignores comment about passwords (no literal)" "0" "$benign"
rm -f "$DIFF"

# Test 3: check_no_secrets — generic password= "..." pattern
echo ""
echo "Test 3: generic password/api_key literal"
DIFF=$(mktemp)
cat > "$DIFF" << 'EOF'
diff --git a/app/db.ts b/app/db.ts
+++ b/app/db.ts
@@ -1,3 +1,3 @@
+const password = "supersecretpassword1234"
+const api_key = "s3cretApiK3y-longE-nough"
+const short = "short"
EOF
findings=$(check_no_secrets "$DIFF")
pw=$(echo "$findings" | grep -c "password" || true)
ak=$(echo "$findings" | grep -c "api_key" || true)
sh=$(echo "$findings" | grep -c "short" || true)
assert "password= long literal flagged" "1" "$pw"
assert "api_key= long literal flagged" "1" "$ak"
assert "short literal not flagged" "0" "$sh"
rm -f "$DIFF"

# Test 4: check_sql_injection detects ${} interpolation + string concat
echo ""
echo "Test 4: check_sql_injection"
DIFF=$(mktemp)
cat > "$DIFF" << 'EOF'
diff --git a/db.js b/db.js
+++ b/db.js
@@ -1,4 +1,4 @@
+const q = `SELECT * FROM users WHERE id = ${userId}`
+const q2 = "SELECT * FROM users WHERE id = " + userId
+const safe = prepareStatement("SELECT * FROM users WHERE id = ?")
+const comment = "-- not SQL, just text"
EOF
findings=$(check_sql_injection "$DIFF")
injected=$(echo "$findings" | grep -c "userId" || true)
assert "flags 2 SQL injections (template + concat)" "2" "$injected"
safe_line=$(echo "$findings" | grep -c "prepareStatement" || true)
assert "parameterized query not flagged" "0" "$safe_line"
rm -f "$DIFF"

# Test 5: check_input_validation surfaces handler reads
echo ""
echo "Test 5: check_input_validation"
DIFF=$(mktemp)
cat > "$DIFF" << 'EOF'
diff --git a/api.js b/api.js
+++ b/api.js
@@ -1,3 +1,3 @@
+const { name, age } = req.body
+const q = req.query.filter
+const unrelated = data.name
EOF
findings=$(check_input_validation "$DIFF")
c=$(echo "$findings" | grep -c "req.body\|req.query" || true)
assert "flags 2 unvalidated handler reads" "2" "$c"
rm -f "$DIFF"

# Test 6: check_commit_integrity flags schema deletions
echo ""
echo "Test 6: check_commit_integrity"
FLIST=$(mktemp)
cat > "$FLIST" << 'EOF'
migrations/001_create_users.sql
prisma/schema.prisma
.env.example
src/app.ts
EOF
findings=$(check_commit_integrity "$FLIST")
migration=$(echo "$findings" | grep -c "migrations/001" || true)
prisma=$(echo "$findings" | grep -c "schema.prisma" || true)
envex=$(echo "$findings" | grep -c ".env.example" || true)
untouched=$(echo "$findings" | grep -c "src/app.ts" || true)
assert "flags migration file" "1" "$migration"
assert "flags schema.prisma" "1" "$prisma"
assert "flags .env.example" "1" "$envex"
assert "does NOT flag regular source file" "0" "$untouched"
rm -f "$FLIST"

# Test 7: enforce_constitution runs active rules and skips inactive ones
echo ""
echo "Test 7: enforce_constitution end-to-end"
TEST_TMPDIR=$(mktemp -d)
cat > "$TEST_TMPDIR/quantum.json" << 'EOF'
{"constitution":["no-secrets","no-sql-injection"]}
EOF
cat > "$TEST_TMPDIR/diff.patch" << 'EOF'
diff --git a/app.ts b/app.ts
+++ b/app.ts
@@ -1,2 +1,2 @@
+const key = "sk-live_0123456789ABCDEFGHIJ"
+const q = `SELECT * FROM users WHERE id = ${userId}`
+const body = req.body
EOF
out=$(enforce_constitution "$TEST_TMPDIR/quantum.json" "$TEST_TMPDIR/diff.patch")
count=$(echo "$out" | jq 'length')
assert "enforce finds 2 secret+sql findings" "2" "$count"
# input-validation is NOT in active rules, so req.body not reported
iv=$(echo "$out" | jq '[.[] | select(.rule=="input-validation")] | length')
assert "input-validation skipped when not active" "0" "$iv"

# Add input-validation and re-run
cat > "$TEST_TMPDIR/quantum.json" << 'EOF'
{"constitution":["no-secrets","no-sql-injection","input-validation"]}
EOF
out=$(enforce_constitution "$TEST_TMPDIR/quantum.json" "$TEST_TMPDIR/diff.patch")
iv=$(echo "$out" | jq '[.[] | select(.rule=="input-validation")] | length')
assert "input-validation active -> finds req.body" "1" "$iv"

# Empty constitution => empty output
echo '{}' > "$TEST_TMPDIR/quantum.json"
out=$(enforce_constitution "$TEST_TMPDIR/quantum.json" "$TEST_TMPDIR/diff.patch")
assert "no constitution -> empty JSON array" "[]" "$out"

# Unknown rule ID logs warning but doesn't fail
cat > "$TEST_TMPDIR/quantum.json" << 'EOF'
{"constitution":["nonexistent-rule"]}
EOF
out=$(enforce_constitution "$TEST_TMPDIR/quantum.json" "$TEST_TMPDIR/diff.patch" 2>/dev/null)
assert "unknown rule -> empty findings (warn only)" "[]" "$out"
rm -rf "$TEST_TMPDIR"

# Test 8: Severity + description populated from rule catalog
echo ""
echo "Test 8: finding metadata"
TEST_TMPDIR=$(mktemp -d)
echo '{"constitution":["no-secrets"]}' > "$TEST_TMPDIR/quantum.json"
cat > "$TEST_TMPDIR/diff.patch" << 'EOF'
+++ b/x.ts
@@ -0,0 +1 @@
+const k = "sk-live_0123456789ABCDEFGHIJ"
EOF
out=$(enforce_constitution "$TEST_TMPDIR/quantum.json" "$TEST_TMPDIR/diff.patch")
sev=$(echo "$out" | jq -r '.[0].severity')
desc=$(echo "$out" | jq -r '.[0].description')
rule=$(echo "$out" | jq -r '.[0].rule')
assert "severity critical" "critical" "$sev"
assert "description set" "hardcoded credentials or API keys" "$desc"
assert "rule id set" "no-secrets" "$rule"
rm -rf "$TEST_TMPDIR"

# Test 9: CLI subcommand works end-to-end
echo ""
echo "Test 9: CLI enforce"
TEST_TMPDIR=$(mktemp -d)
echo '{"constitution":["no-secrets"]}' > "$TEST_TMPDIR/quantum.json"
cat > "$TEST_TMPDIR/diff.patch" << 'EOF'
+++ b/x.ts
@@ -0,0 +1 @@
+const k = "sk-live_0123456789ABCDEFGHIJ"
EOF
cli_out=$(bash "$REPO_ROOT/lib/constitution.sh" enforce "$TEST_TMPDIR/quantum.json" "$TEST_TMPDIR/diff.patch")
cli_count=$(echo "$cli_out" | jq 'length')
assert "CLI enforce returns findings" "1" "$cli_count"
rm -rf "$TEST_TMPDIR"

# Test 10: Schema — quantum.json.example has constitution field
echo ""
echo "Test 10: quantum.json.example schema"
constitution_type=$(jq -r '.constitution | type' "$REPO_ROOT/quantum.json.example")
assert "constitution is array" "array" "$constitution_type"
if jq empty "$REPO_ROOT/quantum.json.example" 2>/dev/null; then
  echo "  PASS: quantum.json.example still valid JSON"; PASS=$((PASS + 1))
else
  echo "  FAIL: quantum.json.example INVALID"; FAIL=$((FAIL + 1))
fi
TOTAL=$((TOTAL + 1))

echo ""
echo "=== Results: $PASS/$TOTAL passed, $FAIL failed ==="
exit $((FAIL > 0 ? 1 : 0))
