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

# ----- 5. G36 / US-002 (v0.6.7): 0-files diff (empty patch) → exit 1 (skip) -----
# Empty input edge case: the diff file has 0 `diff --git` headers. Without
# a `files_changed > 0` guard around the prod_count computation, the bug
# at lib/deep-review.sh:176 has `printf '%s\n' ""` produce a single empty
# line which `grep -cv` counts as 1 non-matching line, spuriously inflating
# prod_count → cg=2 → score=2 (instead of 0). Decision still resolves to
# LOW → skip (since 2 ≤ 30), but the diagnostic log shows the wrong
# intermediate value. Asserting score=0 catches the bug cleanly.
echo ""
echo "Test 5: 0-files diff (empty patch) → exit 1 (skip), score=0 files=0"
EMPTY_DIFF="$TMP/empty.patch"
: > "$EMPTY_DIFF"
out=$(bash -c "source '$LIB' && should_dispatch_deep_review '$EMPTY_DIFF'" 2>&1 || true)
rc=$(bash -c "source '$LIB' && should_dispatch_deep_review '$EMPTY_DIFF' >/dev/null 2>&1 ; echo \$?")
assert "empty-diff exit code" "1" "$rc"
assert_grep "empty-diff logs files=0" 'files=0' "$out"
assert_grep "empty-diff logs score=0 (no spurious cg inflation)" 'score=0' "$out"

rm -rf "$TMP"

# ----- 6. N1 / US-004 (v0.6.7): orchestrator.md Step 4B.5 wires the gate -----
# Structural assertion: agents/orchestrator.md Step 4B.5 must contain BOTH
# the `if ! ` invocation of should_dispatch_deep_review AND a standalone
# `else` line, AND `score-from-quantum` (the first live-pipeline step)
# must live BETWEEN the `else` and the closing `fi`. Pre-N1, the dispatch
# pipeline ran unconditionally because there was no `else` containing it.
echo ""
echo "Test 6: orchestrator.md Step 4B.5 wires should_dispatch_deep_review with else-branch containment"
ORCH="$REPO_ROOT/agents/orchestrator.md"
# Extract the Step 4B.5 region: from the bash code-fence after the
# "### 4B.5: Deep-review aggregation" header through the closing fence.
# Strip trailing \r defensively per CLAUDE.md Platform Notes — orchestrator.md
# may be checked out with CRLF line endings (Git autocrlf=true on Windows OR
# mixed encoding from prior edits). awk preserves \r on lines it reads from a
# CRLF file, so the downstream `grep -qE '^else$'` and `awk /^else$/` patterns
# would fail to match `else\r`. The `tr -d '\r'` strip neutralizes this.
step_4b5=$(awk '
  /^### 4B\.5: Deep-review aggregation/ {found=1}
  found && /^```bash/ {inblock=1; next}
  found && inblock && /^```/ {inblock=0; exit}
  found && inblock {print}
' "$ORCH" | tr -d '\r')
TOTAL=$((TOTAL + 1))
if printf '%s' "$step_4b5" | grep -qE '^if ! .*should_dispatch_deep_review'; then
  echo "  PASS: Step 4B.5 contains 'if ! ...should_dispatch_deep_review' gate invocation"
  PASS=$((PASS + 1))
else
  echo "  FAIL: Step 4B.5 missing 'if ! ...should_dispatch_deep_review'"
  FAIL=$((FAIL + 1))
fi
TOTAL=$((TOTAL + 1))
if printf '%s' "$step_4b5" | grep -qE '^else$'; then
  echo "  PASS: Step 4B.5 contains standalone 'else' line"
  PASS=$((PASS + 1))
else
  echo "  FAIL: Step 4B.5 missing 'else' branch (gate is informational, not load-bearing)"
  FAIL=$((FAIL + 1))
fi
TOTAL=$((TOTAL + 1))
# Use awk to confirm score-from-quantum line index is BETWEEN `else` and closing `fi` line index.
contained=$(printf '%s' "$step_4b5" | awk '
  /^else$/ {else_idx=NR}
  /score-from-quantum/ {score_idx=NR}
  /^fi$/ {fi_idx=NR}
  END {
    if (else_idx > 0 && score_idx > else_idx && (fi_idx == 0 || score_idx < fi_idx))
      print "yes"
    else
      print "no"
  }
')
if [[ "$contained" == "yes" ]]; then
  echo "  PASS: score-from-quantum lives inside else-branch (between else and fi)"
  PASS=$((PASS + 1))
else
  echo "  FAIL: score-from-quantum is NOT contained in the else-branch"
  FAIL=$((FAIL + 1))
fi

# ----- 7. N11 / US-006 (v0.6.8): cleanup-line moved to end of else-branch -----
# Pre-N11 the else-branch's `rm -f .quantum-feature-diff.patch` ran as the
# FIRST line (immediately after `else`), deleting the patch before steps 1-7
# could be inspected on failure. Post-N11 the cleanup runs at end-of-branch
# (after the `case "$VERDICT"` block, before `fi`). Verify the rm -f line
# index is AFTER the case-line index using the same awk-line-numbering
# pattern as Test 6 above.
echo ""
echo "Test 7: Step 4B.5 else-branch cleanup-rm-f lives AFTER case \$VERDICT (end-of-branch ordering)"
TOTAL=$((TOTAL + 1))
cleanup_after_case=$(printf '%s' "$step_4b5" | awk '
  /^else$/ {else_idx=NR}
  /^[[:space:]]*case "\$VERDICT"/ {case_idx=NR}
  /^[[:space:]]*rm -f .*quantum-feature-diff/ {
    # First rm-f after else marks the else-branch cleanup; ignore the
    # if-branch rm-f that occurs before else.
    if (else_idx > 0 && NR > else_idx && rm_idx == 0) rm_idx = NR
  }
  /^fi$/ {fi_idx=NR}
  END {
    if (else_idx > 0 && case_idx > else_idx && rm_idx > case_idx && (fi_idx == 0 || rm_idx < fi_idx))
      print "yes"
    else
      print "no"
  }
')
if [[ "$cleanup_after_case" == "yes" ]]; then
  echo "  PASS: else-branch rm -f lives after case \$VERDICT (end-of-branch)"
  PASS=$((PASS + 1))
else
  echo "  FAIL: else-branch rm -f not found at end-of-branch (post-case, pre-fi)"
  FAIL=$((FAIL + 1))
fi

echo ""
echo "=== Results: $PASS/$TOTAL passed, $FAIL failed ==="
[[ $FAIL -eq 0 ]] || exit 1
