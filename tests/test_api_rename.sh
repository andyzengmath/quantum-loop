#!/usr/bin/env bash
# US-005 / G2 — verify lib/api-rename.sh helper functions:
#   find_rename_targets(old_symbol, new_symbol, scope_glob, [--exclude <glob>])
#   validate_rename_complete(old_symbol, scope_glob, [--exclude <glob>])
#
# Addresses the v0.6.0 US-001 dogfood pattern where a line-4 module-header
# doc-comment was missed during a rename. The helper scans both code-call
# sites AND comments containing the symbol.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$SCRIPT_DIR/.."
RENAME_SH="$REPO_ROOT/lib/api-rename.sh"
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

assert_grep() {
  local name="$1" needle="$2" haystack="$3"
  TOTAL=$((TOTAL + 1))
  if printf '%s' "$haystack" | grep -qF -- "$needle"; then
    echo "  PASS: $name"; PASS=$((PASS + 1))
  else
    echo "  FAIL: $name — needle [$needle] not in output"
    FAIL=$((FAIL + 1))
  fi
}

echo "=== US-005 / G2 lib/api-rename.sh tests ==="

# Test 0: file exists
echo ""
echo "Test 0: lib/api-rename.sh exists"
TOTAL=$((TOTAL + 1))
if [[ -f "$RENAME_SH" ]]; then
  echo "  PASS: lib/api-rename.sh present"; PASS=$((PASS + 1))
else
  echo "  FAIL: lib/api-rename.sh missing"; FAIL=$((FAIL + 1))
  echo ""
  echo "=== Results: $PASS/$TOTAL passed, $FAIL failed ==="
  exit 1
fi

# shellcheck disable=SC1090
source "$RENAME_SH"

# Test 1: both functions exist
echo ""
echo "Test 1: function declarations"
TOTAL=$((TOTAL + 1))
if declare -f find_rename_targets >/dev/null 2>&1; then
  echo "  PASS: find_rename_targets declared"; PASS=$((PASS + 1))
else
  echo "  FAIL: find_rename_targets not declared"; FAIL=$((FAIL + 1))
fi

TOTAL=$((TOTAL + 1))
if declare -f validate_rename_complete >/dev/null 2>&1; then
  echo "  PASS: validate_rename_complete declared"; PASS=$((PASS + 1))
else
  echo "  FAIL: validate_rename_complete not declared"; FAIL=$((FAIL + 1))
fi

# Test 2: synthetic 3-file fixture
echo ""
echo "Test 2: 3-file fixture — find_rename_targets emits 3 occurrences"
TMP=$(mktemp -d)
mkdir -p "$TMP/src"

# File A: function call site
cat > "$TMP/src/a.sh" <<'A_EOF'
#!/usr/bin/env bash
result=$(foo_helper "arg")
echo "$result"
A_EOF

# File B: doc comment with symbol
cat > "$TMP/src/b.sh" <<'B_EOF'
#!/usr/bin/env bash
# Module: example
# This module historically called foo_helper for legacy reasons.
do_thing() {
  : # no-op now
}
B_EOF

# File C: string literal containing symbol
cat > "$TMP/src/c.sh" <<'C_EOF'
#!/usr/bin/env bash
echo "Calling foo_helper from this script"
exit 0
C_EOF

# find_rename_targets foo_helper bar_helper "src/*.sh"
out=$(cd "$TMP" && find_rename_targets foo_helper bar_helper "src/*.sh" 2>&1 || true)
line_count=$(printf '%s\n' "$out" | grep -cE '^src/(a|b|c)\.sh:[0-9]+:' || true)
assert_eq "find_rename_targets emits 3 file:line lines" "3" "$line_count"

# Each file should be referenced
assert_grep "src/a.sh present in output" "src/a.sh:" "$out"
assert_grep "src/b.sh present in output" "src/b.sh:" "$out"
assert_grep "src/c.sh present in output" "src/c.sh:" "$out"

# Test 3: validate_rename_complete fails until each is migrated
echo ""
echo "Test 3: validate_rename_complete progressive migration"

(cd "$TMP" && validate_rename_complete foo_helper "src/*.sh" >/dev/null 2>&1)
rc=$?
assert_eq "validate_rename_complete returns non-zero with 3 occurrences" "1" "$rc"

# Migrate file A
sed -i 's/foo_helper/bar_helper/' "$TMP/src/a.sh"
(cd "$TMP" && validate_rename_complete foo_helper "src/*.sh" >/dev/null 2>&1)
rc=$?
assert_eq "validate_rename_complete still non-zero with 2 occurrences" "1" "$rc"

# Migrate file B
sed -i 's/foo_helper/bar_helper/' "$TMP/src/b.sh"
(cd "$TMP" && validate_rename_complete foo_helper "src/*.sh" >/dev/null 2>&1)
rc=$?
assert_eq "validate_rename_complete still non-zero with 1 occurrence" "1" "$rc"

# Migrate file C
sed -i 's/foo_helper/bar_helper/' "$TMP/src/c.sh"
(cd "$TMP" && validate_rename_complete foo_helper "src/*.sh" >/dev/null 2>&1)
rc=$?
assert_eq "validate_rename_complete returns 0 after full migration" "0" "$rc"

# Test 4: --exclude flag
echo ""
echo "Test 4: --exclude flag"

# Re-introduce occurrence in a 'historical' file
mkdir -p "$TMP/docs"
cat > "$TMP/docs/CHANGELOG.md" <<'CL_EOF'
# Changelog
- Renamed foo_helper to bar_helper in v2.0
CL_EOF

# Without exclude: still finds the historical reference if globbed
out=$(cd "$TMP" && find_rename_targets foo_helper bar_helper "docs/*.md" 2>&1 || true)
line_count=$(printf '%s\n' "$out" | grep -cE '^docs/CHANGELOG\.md:[0-9]+:' || true)
assert_eq "find_rename_targets finds historical reference (no exclude)" "1" "$line_count"

# With exclude: filters out CHANGELOG.md
out=$(cd "$TMP" && find_rename_targets foo_helper bar_helper "docs/*.md" --exclude "CHANGELOG.md" 2>&1 || true)
line_count=$(printf '%s\n' "$out" | grep -cE '^docs/CHANGELOG\.md:[0-9]+:' || true)
assert_eq "find_rename_targets excludes CHANGELOG.md when --exclude given" "0" "$line_count"

# validate_rename_complete with --exclude returns 0 even when occurrences exist in excluded files
(cd "$TMP" && validate_rename_complete foo_helper "docs/*.md" --exclude "CHANGELOG.md" >/dev/null 2>&1)
rc=$?
assert_eq "validate_rename_complete returns 0 when only excluded files have occurrences" "0" "$rc"

# Cleanup
rm -rf "$TMP"

echo ""
echo "=== Results: $PASS/$TOTAL passed, $FAIL failed ==="
[[ $FAIL -eq 0 ]] || exit 1
