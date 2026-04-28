#!/usr/bin/env bash
# G30 / US-004 (v0.6.6) — should_dispatch_deep_review tier-decision tests.
#
# Covers 4 fixture cases:
#   LOW-tier  + no env var          → exit 1 (skip)
#   MEDIUM-tier + no env var        → exit 0 (dispatch)
#   LOW-tier  + QL_DEEP_REVIEW=force → exit 0 (force-dispatch)
#   MEDIUM-tier + QL_DEEP_REVIEW=skip → exit 1 (force-skip)
# Each fixture asserts both the exit code AND the observable tier-derivation
# message on stderr (the function MUST log which tier it computed and which
# decision it made, so operators can debug from the audit log).

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$SCRIPT_DIR/.."
LIB="$REPO_ROOT/lib/deep-review.sh"
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

assert_grep() {
  local name="$1" pattern="$2" haystack="$3"
  TOTAL=$((TOTAL + 1))
  if printf '%s' "$haystack" | grep -qE "$pattern"; then
    echo "  PASS: $name"; PASS=$((PASS + 1))
  else
    echo "  FAIL: $name (pattern [$pattern] not in output)"
    printf '    --- haystack ---\n%s\n    ----------------\n' "$haystack" | head -10
    FAIL=$((FAIL + 1))
  fi
}

echo "=== US-004 G30 should_dispatch_deep_review tier-decision tests ==="

# Fixture A: LOW-tier diff. Exactly 1 .md file, 1 line changed. Score 2 → LOW.
TMP=$(mktemp -d)
LOW_DIFF="$TMP/low.patch"
cat > "$LOW_DIFF" <<'PATCH'
diff --git a/README.md b/README.md
index 1111111..2222222 100644
--- a/README.md
+++ b/README.md
@@ -1,3 +1,3 @@
 # Title
-Old line.
+New line.
 End.
PATCH

# Fixture B: MEDIUM-tier diff. 6 changed files including 1 in auth/ + 1 .env
# but no test files. files_changed=6 → br=15; sensitive_hits=2 → sp=20;
# coverage gap → cg=10; total=45 → MEDIUM (31-60).
MED_DIFF="$TMP/med.patch"
cat > "$MED_DIFF" <<'PATCH'
diff --git a/src/a.js b/src/a.js
index 1111111..2222222 100644
--- a/src/a.js
+++ b/src/a.js
@@ -1,3 +1,3 @@
-1
+11
diff --git a/src/b.js b/src/b.js
index 1111111..2222222 100644
--- a/src/b.js
+++ b/src/b.js
@@ -1,3 +1,3 @@
-2
+22
diff --git a/auth/login.js b/auth/login.js
index 1111111..2222222 100644
--- a/auth/login.js
+++ b/auth/login.js
@@ -1,3 +1,3 @@
-3
+33
diff --git a/.env b/.env
index 1111111..2222222 100644
--- a/.env
+++ b/.env
@@ -1,3 +1,3 @@
-4
+44
diff --git a/src/c.js b/src/c.js
index 1111111..2222222 100644
--- a/src/c.js
+++ b/src/c.js
@@ -1,3 +1,3 @@
-5
+55
diff --git a/src/d.js b/src/d.js
index 1111111..2222222 100644
--- a/src/d.js
+++ b/src/d.js
@@ -1,3 +1,3 @@
-6
+66
PATCH

# ----- 1. LOW-tier + no env var → exit 1 (skip) -----
echo ""
echo "Test 1: LOW-tier diff + no env var → exit 1 (skip)"
out=$(bash -c "source '$LIB' && should_dispatch_deep_review '$LOW_DIFF'" 2>&1 || true)
rc=$(bash -c "source '$LIB' && should_dispatch_deep_review '$LOW_DIFF' >/dev/null 2>&1 ; echo \$?")
assert "LOW + no-env exit code" "1" "$rc"
assert_grep "LOW + no-env logs tier=LOW" 'tier=LOW|LOW.*skip' "$out"

# ----- 2. MEDIUM-tier + no env var → exit 0 (dispatch) -----
echo ""
echo "Test 2: MEDIUM-tier diff + no env var → exit 0 (dispatch)"
out=$(bash -c "source '$LIB' && should_dispatch_deep_review '$MED_DIFF'" 2>&1 || true)
rc=$(bash -c "source '$LIB' && should_dispatch_deep_review '$MED_DIFF' >/dev/null 2>&1 ; echo \$?")
assert "MEDIUM + no-env exit code" "0" "$rc"
assert_grep "MEDIUM + no-env logs tier=MEDIUM" 'tier=MEDIUM|MEDIUM.*dispatch' "$out"

# ----- 3. LOW-tier + QL_DEEP_REVIEW=force → exit 0 (force-dispatch) -----
echo ""
echo "Test 3: LOW-tier diff + QL_DEEP_REVIEW=force → exit 0 (force-dispatch)"
out=$(QL_DEEP_REVIEW=force bash -c "source '$LIB' && should_dispatch_deep_review '$LOW_DIFF'" 2>&1 || true)
rc=$(QL_DEEP_REVIEW=force bash -c "source '$LIB' && should_dispatch_deep_review '$LOW_DIFF' >/dev/null 2>&1 ; echo \$?")
assert "LOW + force exit code" "0" "$rc"
assert_grep "LOW + force logs override" 'force|QL_DEEP_REVIEW=force' "$out"

# ----- 4. MEDIUM-tier + QL_DEEP_REVIEW=skip → exit 1 (force-skip) -----
echo ""
echo "Test 4: MEDIUM-tier diff + QL_DEEP_REVIEW=skip → exit 1 (force-skip)"
out=$(QL_DEEP_REVIEW=skip bash -c "source '$LIB' && should_dispatch_deep_review '$MED_DIFF'" 2>&1 || true)
rc=$(QL_DEEP_REVIEW=skip bash -c "source '$LIB' && should_dispatch_deep_review '$MED_DIFF' >/dev/null 2>&1 ; echo \$?")
assert "MEDIUM + skip exit code" "1" "$rc"
assert_grep "MEDIUM + skip logs override" 'skip|QL_DEEP_REVIEW=skip' "$out"

rm -rf "$TMP"

echo ""
echo "=== Results: $PASS/$TOTAL passed, $FAIL failed ==="
[[ $FAIL -eq 0 ]] || exit 1
