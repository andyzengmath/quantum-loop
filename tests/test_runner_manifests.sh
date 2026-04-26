#!/usr/bin/env bash
# Validates all shipped runner manifests in runners/
# Checks valid JSON, required fields, correct tiers, and hook file existence.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RUNNERS_DIR="$SCRIPT_DIR/../runners"
HOOKS_DIR="$RUNNERS_DIR/hooks"
PASS=0
FAIL=0
TOTAL=0

if ! command -v jq &>/dev/null; then
  echo "SKIP: jq not found"
  exit 1
fi

assert_eq() {
  local test_name="$1" expected="$2" actual="$3"
  TOTAL=$((TOTAL + 1))
  if [[ "$expected" == "$actual" ]]; then
    echo "  PASS: $test_name"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: $test_name"
    echo "    expected: $expected"
    echo "    actual: $actual"
    FAIL=$((FAIL + 1))
  fi
}

assert_true() {
  local test_name="$1" condition="$2"
  TOTAL=$((TOTAL + 1))
  if [[ "$condition" == "true" ]]; then
    echo "  PASS: $test_name"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: $test_name"
    FAIL=$((FAIL + 1))
  fi
}

# ── Test: all_manifests_valid_json ──
echo "Test: all_manifests_valid_json"
for manifest in "$RUNNERS_DIR"/*.json; do
  name=$(basename "$manifest" .json)
  TOTAL=$((TOTAL + 1))
  if jq empty "$manifest" 2>/dev/null; then
    echo "  PASS: $name is valid JSON"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: $name is NOT valid JSON"
    FAIL=$((FAIL + 1))
  fi
done

# ── Test: all_manifests_have_required_fields ──
echo "Test: all_manifests_have_required_fields"
for manifest in "$RUNNERS_DIR"/*.json; do
  name=$(basename "$manifest" .json)
  valid=true
  for field in name binary tier; do
    if [[ "$(jq -r ".$field // empty" "$manifest")" == "" ]]; then
      valid=false
    fi
  done
  if [[ "$(jq -r '.invocation.promptDelivery // empty' "$manifest")" == "" ]]; then
    valid=false
  fi
  if [[ "$(jq -r '.instructionFile.native // empty' "$manifest")" == "" ]]; then
    valid=false
  fi
  assert_true "$name has required fields" "$valid"
done

# ── Test: tier assignments ──
echo "Test: tier_assignments"
assert_eq "claude tier" "guaranteed" "$(jq -r '.tier' "$RUNNERS_DIR/claude.json")"
assert_eq "codex tier" "tested" "$(jq -r '.tier' "$RUNNERS_DIR/codex.json")"
for runner in copilot cursor gemini amp aider; do
  assert_eq "$runner tier" "experimental" "$(jq -r '.tier' "$RUNNERS_DIR/$runner.json")"
done

# ── P5.A4 / US-004: 5 new experimental runners ──
echo "Test: us004_experimental_runners"
for runner in opencode devin kiro goose cline; do
  assert_eq "$runner manifest exists" "true" "$(test -f "$RUNNERS_DIR/$runner.json" && echo true || echo false)"
  assert_eq "$runner tier" "experimental" "$(jq -r '.tier' "$RUNNERS_DIR/$runner.json")"
  assert_eq "$runner has experimental:true" "true" "$(jq -r '.experimental // false' "$RUNNERS_DIR/$runner.json")"
done

# OpenCode: skill auto-discovery from .opencode/skills/ and .claude/skills/
echo "Test: us004_opencode_skill_discovery"
assert_true ".opencode/skills/ in opencode skill_discovery_paths" \
  "$(jq -r '.quirks.skill_discovery_paths // [] | index(".opencode/skills/") != null' "$RUNNERS_DIR/opencode.json" 2>/dev/null)"
assert_true ".claude/skills/ in opencode skill_discovery_paths" \
  "$(jq -r '.quirks.skill_discovery_paths // [] | index(".claude/skills/") != null' "$RUNNERS_DIR/opencode.json" 2>/dev/null)"

# Manifest count == 12
echo "Test: us004_manifest_count"
assert_eq "exactly 12 runner manifests" "12" \
  "$(find "$RUNNERS_DIR" -maxdepth 1 -name '*.json' -type f | wc -l | tr -d ' ')"

# ── Test: hook_files_exist ──
echo "Test: hook_files_exist"
assert_true "codex-hooks.sh exists" "$(test -f "$HOOKS_DIR/codex-hooks.sh" && echo true || echo false)"
assert_true "copilot-hooks.sh exists" "$(test -f "$HOOKS_DIR/copilot-hooks.sh" && echo true || echo false)"

# ── Summary ──
echo ""
echo "=== Results: $PASS/$TOTAL passed, $FAIL failed ==="
if [[ $FAIL -gt 0 ]]; then
  exit 1
fi
exit 0
