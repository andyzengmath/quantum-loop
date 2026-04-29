#!/usr/bin/env bash
# US-006 (v0.8.0) — N33 coordinator pattern dispatch test.
#
# Verifies the v0.8.0 / US-004 coordinator infrastructure:
#   - agents/coordinator.md exists and contains required sections
#   - lib/spawn.sh defines spawn_coordinator and build_coordinator_prompt
#   - spawn_coordinator builds a non-empty command for a sample wave
#   - quantum-loop.sh recognizes --coordinator flag

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$SCRIPT_DIR/.."
COORD_AGENT="$REPO_ROOT/agents/coordinator.md"
SPAWN_LIB="$REPO_ROOT/lib/spawn.sh"
QUANTUM_LOOP="$REPO_ROOT/quantum-loop.sh"
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

echo "=== US-006 v0.8.0 coordinator dispatch tests ==="

# Test 1: agents/coordinator.md exists
echo ""
echo "Test 1: agents/coordinator.md exists"
TOTAL=$((TOTAL + 1))
if [[ -f "$COORD_AGENT" ]]; then
  echo "  PASS: file exists"; PASS=$((PASS + 1))
else
  echo "  FAIL: coordinator agent file not found at $COORD_AGENT"; FAIL=$((FAIL + 1))
fi

# Test 2: coordinator.md contains required sections
echo ""
echo "Test 2: coordinator.md has expected sections (Inputs, Output Signals, Scope)"
TOTAL=$((TOTAL + 1))
if grep -qE '^## Inputs' "$COORD_AGENT" && grep -qE '^## Scope' "$COORD_AGENT" && grep -qE '^## Output Signals' "$COORD_AGENT"; then
  echo "  PASS: required sections present"; PASS=$((PASS + 1))
else
  echo "  FAIL: missing one or more required sections"; FAIL=$((FAIL + 1))
fi

# Test 3: lib/spawn.sh defines spawn_coordinator
echo ""
echo "Test 3: spawn_coordinator function defined after sourcing lib/spawn.sh"
TOTAL=$((TOTAL + 1))
fn_defined=$(bash -c "source '$SPAWN_LIB' && declare -F spawn_coordinator >/dev/null && echo yes || echo no" 2>/dev/null)
if [[ "$fn_defined" == "yes" ]]; then
  echo "  PASS: spawn_coordinator defined"; PASS=$((PASS + 1))
else
  echo "  FAIL: spawn_coordinator not defined after sourcing"; FAIL=$((FAIL + 1))
fi

# Test 4: lib/spawn.sh defines build_coordinator_prompt
echo ""
echo "Test 4: build_coordinator_prompt function defined"
TOTAL=$((TOTAL + 1))
fn_defined=$(bash -c "source '$SPAWN_LIB' && declare -F build_coordinator_prompt >/dev/null && echo yes || echo no" 2>/dev/null)
if [[ "$fn_defined" == "yes" ]]; then
  echo "  PASS: build_coordinator_prompt defined"; PASS=$((PASS + 1))
else
  echo "  FAIL: build_coordinator_prompt not defined"; FAIL=$((FAIL + 1))
fi

# Test 5: spawn_coordinator builds a non-empty command
echo ""
echo "Test 5: spawn_coordinator wave-0 'US-001 US-002' builds non-empty command"
TOTAL=$((TOTAL + 1))
cmd=$(bash -c "source '$SPAWN_LIB' && spawn_coordinator wave-0 'US-001 US-002' tasks/prd.md quantum.json" 2>&1)
if [[ -n "$cmd" ]] && [[ "$cmd" == *"claude"* || "$cmd" == *"codex"* || "$cmd" == *"copilot"* ]]; then
  echo "  PASS: command non-empty (${#cmd} chars)"; PASS=$((PASS + 1))
else
  echo "  FAIL: empty or non-runner-binary command — got: $cmd"; FAIL=$((FAIL + 1))
fi

# Test 6: quantum-loop.sh recognizes --coordinator flag (presence-only)
echo ""
echo "Test 6: quantum-loop.sh recognizes --coordinator and --legacy-orchestrator flags"
TOTAL=$((TOTAL + 1))
if grep -q '\-\-coordinator' "$QUANTUM_LOOP" && grep -q '\-\-legacy-orchestrator' "$QUANTUM_LOOP"; then
  echo "  PASS: both flags handled in quantum-loop.sh"; PASS=$((PASS + 1))
else
  echo "  FAIL: missing --coordinator or --legacy-orchestrator handling"; FAIL=$((FAIL + 1))
fi

# Test 7: prompt contains expected wave-id and story-ids in the output
echo ""
echo "Test 7: build_coordinator_prompt embeds wave-id and story-ids"
TOTAL=$((TOTAL + 1))
prompt=$(bash -c "source '$SPAWN_LIB' && build_coordinator_prompt wave-7 'US-A US-B US-C' tasks/prd.md quantum.json" 2>&1)
if printf '%s' "$prompt" | grep -q 'wave-7' && printf '%s' "$prompt" | grep -q 'US-A US-B US-C'; then
  echo "  PASS: prompt embeds wave id and story ids"; PASS=$((PASS + 1))
else
  echo "  FAIL: prompt missing wave id or story ids"; FAIL=$((FAIL + 1))
fi

echo ""
echo "=== Results: $PASS/$TOTAL passed, $FAIL failed ==="
[[ $FAIL -eq 0 ]] || exit 1
