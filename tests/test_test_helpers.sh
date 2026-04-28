#!/usr/bin/env bash
# p008 / US-006 (v0.6.6) — test-helper audit.
#
# Asserts every tests/test_*.sh file in the corpus is safe with respect to
# the v0.6.5 codebasePattern p008 (sourced-script errexit propagation).
# An out=$(...) substitution under `set -e` will silently abort the test
# script if the inner command exits non-zero. Mitigation patterns:
#
#   Pattern A: function-extracted subshell + two-invocation idiom
#              (`out=$(_t_run 2>&1 || true); rc=$(_t_run >/dev/null 2>&1 ; echo $?)`)
#   Pattern B: `|| true` immediately on the same line
#              (`out=$(cmd 2>&1 || true)`)
#   Pattern C: enclosing `set +e` ... `set -e` block scope
#   Pattern D: file does not enable `set -e` (the hazard is set-e-specific —
#              `set -uo pipefail` is unaffected, since errexit is the trigger)
#
# Opt-out: a file may declare `# pragma test-helper-audit: opt-out (rationale: ...)`
# in its top 10 lines to suppress the audit; the rationale string is required.
#
# Output: per-file PASS/FAIL with file:line citation when an unsafe substitution
# is found. Self-tests synthesize 4 fixture files (one for each scenario A/B/C/D)
# plus an unsafe baseline + a corpus pass.

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

# check_test_file <path>
# Echos one of:
#   "OK"                 — file is safe (matches A/B/C/D pattern, or has opt-out)
#   "FAIL <file>:<line>" — first unsafe substitution location
#
# The check is line-by-line: for each `out=$(...)` (or any `<varname>=$(`),
# we look at:
#   1. The same line for `|| true` → Pattern B
#   2. The next 5 lines for `; echo $?` → Pattern A
#   3. Whether the line is enclosed in a `set +e ... set -e` window → Pattern C
#   4. Whether the file has `set -e` enabled at all → Pattern D
# A file with a top-of-file opt-out marker is unconditionally OK.
check_test_file() {
  local f="$1"

  # Top-of-file opt-out marker (must appear in first 10 lines).
  if head -10 "$f" | grep -qE '^# pragma test-helper-audit: opt-out \(rationale: .+\)'; then
    printf 'OK'
    return 0
  fi

  # Pattern D: does the file enable errexit? `set -e` (with optional u/o suffix
  # in any order) is the only trigger. Files using `set -uo pipefail` (the
  # quantum-loop default) are NOT under errexit and are safe by construction.
  local has_errexit=0
  if grep -qE '^[[:space:]]*set[[:space:]]+-[uo]*e[uo]*[[:space:]]?' "$f" \
     || grep -qE '^[[:space:]]*set[[:space:]]+-e[[:space:]]?' "$f"; then
    has_errexit=1
  fi
  if (( has_errexit == 0 )); then
    printf 'OK'
    return 0
  fi

  # Hazard active. Walk the file. State for set+e ... set-e windows.
  local lineno=0 in_set_plus_e=0
  local found_unsafe=""
  while IFS= read -r line; do
    lineno=$((lineno + 1))
    # Track set +e / set -e window for Pattern C.
    if [[ "$line" =~ ^[[:space:]]*set[[:space:]]+\+e[[:space:]]?$ ]]; then
      in_set_plus_e=1; continue
    fi
    if [[ "$line" =~ ^[[:space:]]*set[[:space:]]+-[a-z]*e ]] && (( in_set_plus_e == 1 )); then
      in_set_plus_e=0; continue
    fi
    # Look for a substitution assignment: VAR=$(... )
    if [[ "$line" =~ ^[[:space:]]*[A-Za-z_][A-Za-z0-9_]*=\$\( ]]; then
      # Pattern B: `|| true` on the same line
      if [[ "$line" == *'|| true'* ]]; then continue; fi
      # Pattern A (variant 1): same line ends with `; echo $?` (the captures-rc
      # half of the two-invocation idiom)
      if [[ "$line" =~ \;[[:space:]]*echo[[:space:]]+\$\?[[:space:]]*\) ]]; then
        continue
      fi
      # Pattern C: in set +e window
      if (( in_set_plus_e == 1 )); then continue; fi
      # Pattern A (variant 2): next 5 lines contain `; echo $?` (the captures-rc
      # half of the two-invocation idiom on a sibling line)
      local ahead
      ahead=$(awk -v start="$((lineno + 1))" 'NR>=start && NR<start+5' "$f")
      if printf '%s' "$ahead" | grep -qE '\;[[:space:]]*echo[[:space:]]+\$\?'; then
        continue
      fi
      # No safe pattern matched → record first unsafe location and stop.
      found_unsafe="$f:$lineno"
      break
    fi
  done < "$f"

  if [[ -n "$found_unsafe" ]]; then
    printf 'FAIL %s' "$found_unsafe"
  else
    printf 'OK'
  fi
}

echo "=== US-006 p008 test-helper audit ==="

# ---------- Synthetic fixtures ----------
TMP=$(mktemp -d)

# Fixture A: errexit + Pattern A (function + two-invocation)
cat > "$TMP/a.sh" <<'A'
#!/usr/bin/env bash
set -e
_t_run() { exit 0; }
out=$(_t_run 2>&1 || true)
rc=$(_t_run >/dev/null 2>&1 ; echo $?)
A

# Fixture B: errexit + Pattern B (|| true on same line)
cat > "$TMP/b.sh" <<'B'
#!/usr/bin/env bash
set -e
out=$(false 2>&1 || true)
B

# Fixture C: errexit + Pattern C (set +e block)
cat > "$TMP/c.sh" <<'C'
#!/usr/bin/env bash
set -e
set +e
out=$(false)
set -e
C

# Fixture D: errexit + UNSAFE (no mitigation, no opt-out)
cat > "$TMP/d-unsafe.sh" <<'D'
#!/usr/bin/env bash
set -e
out=$(false)
D

# Fixture E: NO errexit (Pattern D — safe by construction)
cat > "$TMP/e-no-errexit.sh" <<'E'
#!/usr/bin/env bash
set -uo pipefail
out=$(false)
E

# Fixture F: errexit + opt-out marker (with rationale)
cat > "$TMP/f-optout.sh" <<'F'
#!/usr/bin/env bash
# pragma test-helper-audit: opt-out (rationale: tests intentional errexit propagation)
set -e
out=$(false)
F

# ---------- Assertions ----------

# 1. Pattern A — OK
echo ""
echo "Test 1: Pattern A (function + two-invocation) → OK"
out=$(check_test_file "$TMP/a.sh")
assert "Fixture A audits OK" "OK" "$out"

# 2. Pattern B — OK
echo ""
echo "Test 2: Pattern B (|| true on same line) → OK"
out=$(check_test_file "$TMP/b.sh")
assert "Fixture B audits OK" "OK" "$out"

# 3. Pattern C — OK
echo ""
echo "Test 3: Pattern C (set +e block) → OK"
out=$(check_test_file "$TMP/c.sh")
assert "Fixture C audits OK" "OK" "$out"

# 4. UNSAFE — FAIL with file:line
echo ""
echo "Test 4: UNSAFE (no mitigation, no opt-out) → FAIL"
out=$(check_test_file "$TMP/d-unsafe.sh")
TOTAL=$((TOTAL + 1))
if [[ "$out" =~ ^FAIL.*d-unsafe\.sh:[0-9]+$ ]]; then
  echo "  PASS: Fixture D audits FAIL with file:line citation ($out)"; PASS=$((PASS + 1))
else
  echo "  FAIL: Fixture D produced [$out]"; FAIL=$((FAIL + 1))
fi

# 5. Pattern D (no errexit) — OK
echo ""
echo "Test 5: Pattern D (set -uo pipefail, no -e) → OK"
out=$(check_test_file "$TMP/e-no-errexit.sh")
assert "Fixture E audits OK (no errexit hazard)" "OK" "$out"

# 6. Opt-out marker — OK
echo ""
echo "Test 6: opt-out marker → OK"
out=$(check_test_file "$TMP/f-optout.sh")
assert "Fixture F audits OK (opt-out)" "OK" "$out"

# 7. Corpus baseline cleanliness — every tests/test_*.sh in the real repo passes.
echo ""
echo "Test 7: corpus baseline cleanliness"
shopt -s nullglob
declare -a ALL=("$SCRIPT_DIR"/test_*.sh)
shopt -u nullglob
unsafe_count=0
unsafe_files=""
for f in "${ALL[@]}"; do
  # Skip self to avoid recursion.
  [[ "$f" == "$SCRIPT_DIR/test_test_helpers.sh" ]] && continue
  res=$(check_test_file "$f")
  if [[ "$res" =~ ^FAIL ]]; then
    unsafe_count=$((unsafe_count + 1))
    unsafe_files+="\n    $res"
  fi
done
TOTAL=$((TOTAL + 1))
if (( unsafe_count == 0 )); then
  echo "  PASS: 0 unsafe substitutions across $((${#ALL[@]} - 1)) test files"; PASS=$((PASS + 1))
else
  echo "  FAIL: $unsafe_count test file(s) have unsafe substitutions:"; FAIL=$((FAIL + 1))
  printf "$unsafe_files\n"
fi

# 8. Opt-out rationale enforcement — non-empty string after the colon.
echo ""
echo "Test 8: opt-out marker requires non-empty rationale"
# Verify our regex rejects an empty rationale.
cat > "$TMP/g-empty-rationale.sh" <<'G'
#!/usr/bin/env bash
# pragma test-helper-audit: opt-out (rationale: )
set -e
out=$(false)
G
out=$(check_test_file "$TMP/g-empty-rationale.sh")
TOTAL=$((TOTAL + 1))
# Empty rationale should NOT short-circuit — file should be evaluated as unsafe
if [[ "$out" =~ ^FAIL ]]; then
  echo "  PASS: empty-rationale opt-out rejected; file audited normally and is FAIL"; PASS=$((PASS + 1))
else
  echo "  FAIL: empty-rationale opt-out incorrectly accepted (out=$out)"; FAIL=$((FAIL + 1))
fi

# 9. Count of opt-outs in current corpus (target: 0). Excludes this file
# itself, whose heredoc fixture content matches the pragma string by design.
echo ""
echo "Test 9: opt-out count in current corpus = 0 (excluding self)"
optout_files=$(grep -lE '^# pragma test-helper-audit: opt-out' "$SCRIPT_DIR"/test_*.sh 2>/dev/null \
               | grep -v "$SCRIPT_DIR/test_test_helpers.sh" || true)
optout_count=$(printf '%s\n' "$optout_files" | grep -cv '^$' || true)
TOTAL=$((TOTAL + 1))
if [[ "$optout_count" == "0" ]]; then
  echo "  PASS: 0 opt-outs in current corpus (excluding self)"; PASS=$((PASS + 1))
else
  echo "  FAIL: $optout_count opt-out marker(s) found (target: 0):"; FAIL=$((FAIL + 1))
  printf '%s\n' "$optout_files"
fi

rm -rf "$TMP"

echo ""
echo "=== Results: $PASS/$TOTAL passed, $FAIL failed ==="
[[ $FAIL -eq 0 ]] || exit 1
