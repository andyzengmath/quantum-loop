#!/usr/bin/env bash
# US-009 / P5.B1 — verify per-role provider routing with resolved-routing
# snapshot. Ports OMC v4.12.0 mechanism. Adds --planner / --critic /
# --executor flags with availability detection + per-role fallback to
# claude. Snapshot captured to quantum.json.routing for replay
# determinism. Closes P2.9 fully.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$SCRIPT_DIR/.."
QL_SH="$REPO_ROOT/quantum-loop.sh"
QL_PS1="$REPO_ROOT/quantum-loop.ps1"
RUNNER="$REPO_ROOT/lib/runner.sh"
DR_SH="$REPO_ROOT/lib/deep-review.sh"
ORCH="$REPO_ROOT/agents/orchestrator.md"
EXAMPLE="$REPO_ROOT/quantum.json.example"
PASS=0
FAIL=0
TOTAL=0

assert_grep() {
  local name="$1" needle="$2" file="$3"
  TOTAL=$((TOTAL + 1))
  if grep -qF -- "$needle" "$file"; then
    echo "  PASS: $name"; PASS=$((PASS + 1))
  else
    echo "  FAIL: $name — needle [$needle] not in $(basename "$file")"
    FAIL=$((FAIL + 1))
  fi
}

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

echo "=== US-009 per-role provider routing tests ==="

# Test 1: --planner / --critic / --executor flags present
echo ""
echo "Test 1: 3 per-role flags in quantum-loop.sh"
assert_grep "--planner flag in shell"  "--planner"  "$QL_SH"
assert_grep "--critic flag in shell"   "--critic"   "$QL_SH"
assert_grep "--executor flag in shell" "--executor" "$QL_SH"

echo ""
echo "Test 2: 3 per-role params in quantum-loop.ps1"
assert_grep "Planner param"  "Planner"  "$QL_PS1"
assert_grep "Critic param"   "Critic"   "$QL_PS1"
assert_grep "Executor param" "Executor" "$QL_PS1"

# Test 3: routing snapshot helpers in lib/runner.sh
echo ""
echo "Test 3: lib/runner.sh resolve_routing helper"
assert_grep "resolve_routing helper defined" "resolve_routing"   "$RUNNER"
assert_grep "snapshot writes quantum.json.routing" "routing"     "$RUNNER"
assert_grep "per-role dispatch table"        "QL_ROLE_"          "$RUNNER"

# Test 4: behavioral — resolve_routing produces proper JSON
# Source runner.sh under test mode
echo ""
echo "Test 4: resolve_routing emits well-shaped JSON"
QL_AUDIT_TEST_MODE=1
# shellcheck disable=SC1090
source "$RUNNER" 2>/dev/null || true
unset QL_AUDIT_TEST_MODE

if declare -f resolve_routing >/dev/null 2>&1; then
  out=$(resolve_routing "auto" "auto" "auto" 2>/dev/null)
  TOTAL=$((TOTAL + 1))
  if printf '%s' "$out" | jq -e 'has("planner") and has("critic") and has("executor") and has("resolvedAt") and has("versions")' >/dev/null 2>&1; then
    echo "  PASS: resolve_routing emits {planner,critic,executor,resolvedAt,versions}"; PASS=$((PASS + 1))
  else
    echo "  FAIL: resolve_routing JSON shape wrong (got [$out])"; FAIL=$((FAIL + 1))
  fi
else
  TOTAL=$((TOTAL + 1))
  echo "  FAIL: resolve_routing helper not defined"
  FAIL=$((FAIL + 1))
fi

# Test 5: per-role fallback to claude when binary absent
echo ""
echo "Test 5: per-role fallback to claude on missing binary"
if declare -f resolve_routing >/dev/null 2>&1; then
  ORIG_PATH="$PATH"
  PATH=/nonexistent
  out_stderr=$(resolve_routing "claude" "codex" "gemini" 2>&1 1>/dev/null || true)
  PATH="$ORIG_PATH"
  TOTAL=$((TOTAL + 1))
  if printf '%s' "$out_stderr" | grep -qiE "fallback|fall.*back|warn"; then
    echo "  PASS: missing binaries trigger fallback warnings"; PASS=$((PASS + 1))
  else
    echo "  FAIL: no fallback warning emitted"; FAIL=$((FAIL + 1))
  fi
else
  TOTAL=$((TOTAL + 1))
  FAIL=$((FAIL + 1))
  echo "  FAIL: resolve_routing helper not defined"
fi

# Test 6: lib/deep-review.sh consumes routing.critic
echo ""
echo "Test 6: lib/deep-review.sh references routing.critic"
assert_grep "deep-review references routing.critic OR QL_CRITIC" "QL_CRITIC" "$DR_SH"

# Test 7: orchestrator reads routing on init
echo ""
echo "Test 7: orchestrator.md mentions routing snapshot"
assert_grep "orchestrator references routing" "routing" "$ORCH"

# Test 8: quantum.json.example documents routing
echo ""
echo "Test 8: quantum.json.example documents routing snapshot"
assert_grep "example documents routing" "routing" "$EXAMPLE"

# Test 9-10: snapshot capture on disk (resolve_routing emits + write to JSON)
echo ""
echo "Test 9-10: snapshot persisted to quantum.json.routing"
TMP=$(mktemp -d)
TJ="$TMP/quantum.json"
cat > "$TJ" << 'EOF'
{ "stories": [], "branchName": "test", "prdPath": "prd.md" }
EOF

if declare -f write_routing_snapshot >/dev/null 2>&1; then
  routing_json=$(resolve_routing "auto" "none" "auto" 2>/dev/null)
  write_routing_snapshot "$TJ" "$routing_json" 2>/dev/null
  TOTAL=$((TOTAL + 1))
  if jq -e '.routing | has("planner") and has("critic") and has("executor")' "$TJ" >/dev/null 2>&1; then
    echo "  PASS: routing snapshot persisted to quantum.json"; PASS=$((PASS + 1))
  else
    echo "  FAIL: routing snapshot not persisted (file content: $(cat "$TJ"))"; FAIL=$((FAIL + 1))
  fi
  TOTAL=$((TOTAL + 1))
  critic_v=$(jq -r '.routing.critic' "$TJ")
  if [[ "$critic_v" == "none" ]]; then
    echo "  PASS: critic=none persisted"; PASS=$((PASS + 1))
  else
    echo "  FAIL: critic should be 'none' (got [$critic_v])"; FAIL=$((FAIL + 1))
  fi
else
  TOTAL=$((TOTAL + 2))
  FAIL=$((FAIL + 2))
  echo "  FAIL: write_routing_snapshot not defined"
  echo "  FAIL: write_routing_snapshot not defined"
fi

# Test 11-12: replay reads snapshot when flags absent
echo ""
echo "Test 11-12: replay reads snapshot when flags absent"
if declare -f read_routing_snapshot >/dev/null 2>&1; then
  out=$(read_routing_snapshot "$TJ" 2>/dev/null)
  TOTAL=$((TOTAL + 1))
  planner=$(printf '%s' "$out" | jq -r '.planner // empty')
  if [[ -n "$planner" ]]; then
    echo "  PASS: read_routing_snapshot returns planner field"; PASS=$((PASS + 1))
  else
    echo "  FAIL: read_routing_snapshot returns empty (got [$out])"; FAIL=$((FAIL + 1))
  fi
else
  TOTAL=$((TOTAL + 1))
  FAIL=$((FAIL + 1))
  echo "  FAIL: read_routing_snapshot not defined"
fi

# Test 12 (continued): missing snapshot returns {} gracefully
TJ2="$TMP/quantum-noroute.json"
cat > "$TJ2" << 'EOF'
{ "stories": [], "branchName": "test" }
EOF
if declare -f read_routing_snapshot >/dev/null 2>&1; then
  out=$(read_routing_snapshot "$TJ2" 2>/dev/null || true)
  TOTAL=$((TOTAL + 1))
  if [[ -z "$out" ]] || printf '%s' "$out" | jq empty 2>/dev/null; then
    echo "  PASS: missing snapshot returns {} or empty"; PASS=$((PASS + 1))
  else
    echo "  FAIL: missing snapshot raised error (got [$out])"; FAIL=$((FAIL + 1))
  fi
else
  TOTAL=$((TOTAL + 1))
  FAIL=$((FAIL + 1))
fi

# Test 13-15: per-role override behavior (--planner=codex overrides snapshot)
echo ""
echo "Test 13-15: per-role override semantics"
if declare -f resolve_routing >/dev/null 2>&1; then
  # When all three roles requested explicitly, all three resolve in JSON
  out=$(resolve_routing "claude" "claude" "claude" 2>/dev/null)
  TOTAL=$((TOTAL + 1))
  pl=$(printf '%s' "$out" | jq -r '.planner')
  if [[ "$pl" == "claude" ]]; then
    echo "  PASS: explicit planner=claude resolves to claude"; PASS=$((PASS + 1))
  else
    echo "  FAIL: planner=claude not respected (got [$pl])"; FAIL=$((FAIL + 1))
  fi
  TOTAL=$((TOTAL + 1))
  cr=$(printf '%s' "$out" | jq -r '.critic')
  if [[ "$cr" == "claude" ]]; then
    echo "  PASS: explicit critic=claude resolves to claude"; PASS=$((PASS + 1))
  else
    echo "  FAIL: critic=claude not respected (got [$cr])"; FAIL=$((FAIL + 1))
  fi
  TOTAL=$((TOTAL + 1))
  ex=$(printf '%s' "$out" | jq -r '.executor')
  if [[ "$ex" == "claude" ]]; then
    echo "  PASS: explicit executor=claude resolves to claude"; PASS=$((PASS + 1))
  else
    echo "  FAIL: executor=claude not respected (got [$ex])"; FAIL=$((FAIL + 1))
  fi
else
  TOTAL=$((TOTAL + 3))
  FAIL=$((FAIL + 3))
fi

# Test 16-20: shell flag arg-parsing actually sets QL_ROLE_* env vars
echo ""
echo "Test 16-20: shell flag arg-parsing sets per-role env vars"
QL_AUDIT_TEST_MODE=1
QL_PLANNER="" QL_CRITIC="" QL_EXECUTOR=""
# shellcheck disable=SC1090
source "$QL_SH" 2>/dev/null || true
unset QL_AUDIT_TEST_MODE

# parse_role_arg helper
if declare -f parse_role_arg >/dev/null 2>&1; then
  for r in planner critic executor; do
    out=$(parse_role_arg "$r" auto 2>/dev/null)
    assert_eq "parse_role_arg($r, auto) -> auto" "auto" "$out"
  done
  # planner accepts claude (not none); critic accepts none
  out=$(parse_role_arg "planner" "claude" 2>/dev/null)
  assert_eq "parse_role_arg(planner, claude) -> claude" "claude" "$out"
  out=$(parse_role_arg "critic" "none" 2>/dev/null)
  assert_eq "parse_role_arg(critic, none) -> none" "none" "$out"
else
  TOTAL=$((TOTAL + 5))
  FAIL=$((FAIL + 5))
  echo "  FAIL: parse_role_arg helper not defined (5 cases)"
fi

# Cleanup
rm -rf "$TMP"

echo ""
echo "=== Results: $PASS/$TOTAL passed, $FAIL failed ==="
[[ $FAIL -eq 0 ]] || exit 1
