#!/usr/bin/env bash
# US-005 (v0.7.4) — multi-runner-manifest foundation tests.
#
# Foundation only: schema + parse/validate/list. No actual runner integrations.
# Runner integrations (codex, gemini, copilot) deferred to v0.8.0+.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$SCRIPT_DIR/.."
LIB="$REPO_ROOT/lib/multi-runner-manifest.sh"
EXAMPLE="$REPO_ROOT/runners/manifest.example.yaml"
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

echo "=== US-005 v0.7.4 multi-runner-manifest tests ==="

# Skip suite cleanly if lib missing (RED phase signal)
if [[ ! -f "$LIB" ]]; then
  echo "SKIP: lib/multi-runner-manifest.sh not found (RED phase)"
  exit 1
fi
if [[ ! -f "$EXAMPLE" ]]; then
  echo "SKIP: runners/manifest.example.yaml not found (RED phase)"
  exit 1
fi

# Test 1: parse-valid — manifest.example.yaml -> JSON envelope, rc=0
echo ""
echo "Test 1: parse_manifest manifest.example.yaml -> JSON, rc=0"
out1=$(bash -c "source '$LIB' && parse_manifest '$EXAMPLE'" 2>/dev/null)
rc1=$?
assert "Test 1: parse-valid rc=0" "0" "$rc1"
TOTAL=$((TOTAL + 1))
if printf '%s' "$out1" | jq -e '.runners | type == "array"' >/dev/null 2>&1; then
  echo "  PASS: parse output has .runners array"; PASS=$((PASS + 1))
else
  echo "  FAIL: parse output missing .runners array — out: $out1"; FAIL=$((FAIL + 1))
fi

# Test 2: parse-malformed-yaml -> rc=1 + stderr ERROR
echo ""
echo "Test 2: parse_manifest on malformed YAML -> rc=1 + stderr ERROR"
TMP_BAD=$(mktemp -d)
cat > "$TMP_BAD/bad.yaml" <<'EOF'
this is: not
  - valid yaml
    structure: [[[
EOF
out2=$(bash -c "source '$LIB' && parse_manifest '$TMP_BAD/bad.yaml'" 2>&1)
rc2=$?
assert "Test 2: malformed yaml rc=1" "1" "$rc2"
TOTAL=$((TOTAL + 1))
if printf '%s' "$out2" | grep -qE 'ERROR|error'; then
  echo "  PASS: malformed yaml emits ERROR"; PASS=$((PASS + 1))
else
  echo "  FAIL: malformed yaml missing ERROR — out: $out2"; FAIL=$((FAIL + 1))
fi
rm -rf "$TMP_BAD"

# Test 3: validate-missing-name -> rc=1 + stderr WARN
echo ""
echo "Test 3: validate_manifest with missing name -> rc=1 + stderr WARN"
JSON_NO_NAME='{"runners":[{"command":"foo","version_flag":"--version"}]}'
out3=$(bash -c "source '$LIB' && validate_manifest '$JSON_NO_NAME'" 2>&1)
rc3=$?
assert "Test 3: missing-name rc=1" "1" "$rc3"
TOTAL=$((TOTAL + 1))
if printf '%s' "$out3" | grep -qE 'WARN|name'; then
  echo "  PASS: missing-name emits WARN about name"; PASS=$((PASS + 1))
else
  echo "  FAIL: missing-name WARN missing — out: $out3"; FAIL=$((FAIL + 1))
fi

# Test 4: validate-ok -> rc=0
echo ""
echo "Test 4: validate_manifest with all required fields -> rc=0"
JSON_OK='{"runners":[{"name":"claude","command":"claude","version_flag":"--version"}]}'
out4=$(bash -c "source '$LIB' && validate_manifest '$JSON_OK'" 2>&1) || true
rc4=$(bash -c "source '$LIB' && validate_manifest '$JSON_OK' >/dev/null 2>&1; echo \$?")
assert "Test 4: valid manifest rc=0" "0" "$rc4"

# Test 5: list-runners -> 3 names
echo ""
echo "Test 5: list_runners on valid manifest with 3 entries -> 3 names"
JSON_3='{"runners":[{"name":"claude","command":"claude","version_flag":"--version"},{"name":"codex","command":"codex","version_flag":"--version"},{"name":"gemini","command":"gemini-cli","version_flag":"--version"}]}'
out5=$(bash -c "source '$LIB' && list_runners '$JSON_3'" 2>/dev/null)
# Count via grep -c to handle missing trailing newline correctly
n5=$(printf '%s\n' "$out5" | grep -c .)
assert "Test 5: list_runners returns 3 names" "3" "$n5"

# Test 6: cli-mode invocation
echo ""
echo "Test 6: bash lib/multi-runner-manifest.sh parse manifest.example.yaml -> JSON"
out6=$(bash "$LIB" parse "$EXAMPLE" 2>/dev/null)
rc6=$?
assert "Test 6: cli-mode parse rc=0" "0" "$rc6"
TOTAL=$((TOTAL + 1))
if printf '%s' "$out6" | jq -e '.runners | length >= 1' >/dev/null 2>&1; then
  echo "  PASS: cli-mode emits valid JSON with at least 1 runner"; PASS=$((PASS + 1))
else
  echo "  FAIL: cli-mode JSON malformed or empty — out: $out6"; FAIL=$((FAIL + 1))
fi

echo ""
echo "=== Results: $PASS/$TOTAL passed, $FAIL failed ==="
[[ $FAIL -eq 0 ]] || exit 1
