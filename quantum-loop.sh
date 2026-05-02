#!/usr/bin/env bash
set -euo pipefail

# =============================================================================
# quantum-loop.sh -- PLUGIN-LEVEL autonomous development loop.
#
# THIS SCRIPT IS FOR THE QUANTUM-LOOP PLUGIN REPO ITSELF.
# It requires lib/*.sh modules and jq. It operates at the STORY level
# (one story per agent invocation) and uses CLAUDE.md as the agent prompt.
#
# FOR USER PROJECTS: Use templates/quantum-loop.sh instead.
# That script is self-contained (no lib/ dependency), uses node for JSON,
# and operates at the TASK level. Download it via:
#   curl -sO https://raw.githubusercontent.com/andyzengmath/quantum-loop/main/templates/quantum-loop.sh
#
# Features: DAG-based story selection, two-stage review gates,
# structured error recovery, parallel execution via worktree agents.
#
# Usage:
#   ./quantum-loop.sh [OPTIONS]
#
# Options:
#   --audit              Print §6 measurement metrics and exit (read-only).
#   --max-iterations N   Maximum iterations before stopping (default: 20)
#   --max-retries N      Max retry attempts per story (default: 3)
#   --tool TOOL          AI tool to use (default: "claude"). Any runner in runners/*.json.
#   --parallel           Enable parallel execution of independent stories
#   --max-parallel N     Maximum concurrent agents in parallel mode (default: 4)
#   --help               Show this help message
#
# Prerequisites:
#   - quantum.json must exist in the current directory (run /quantum-loop:plan first)
#   - jq must be installed
#   - The selected runner CLI must be installed (see runners/*.json)
# =============================================================================

# Defaults
MAX_ITERATIONS=20
MAX_RETRIES=3
TOOL="claude"
PARALLEL_MODE=false
MAX_PARALLEL=4
# v0.8.0 / US-004 (N33) — coordinator mode: per-wave subagent dispatch instead
# of long-running orchestrator. Default false (legacy orchestrator) for v0.8.0;
# v0.8.1 dogfood will validate before flipping default.
COORDINATOR_MODE=false
STALE_TIMEOUT=20
QL_CRITIC="${QL_CRITIC:-auto}"      # P5.A2 / US-002 default
QL_PLANNER="${QL_PLANNER:-auto}"    # P5.B1 / US-009 default
QL_EXECUTOR="${QL_EXECUTOR:-auto}"  # P5.B1 / US-009 default
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# =============================================================================
# P5.B1 / US-009 — Per-role provider routing (--planner / --critic / --executor)
# Subsumes US-002's --critic flag; adds --planner and --executor with the
# same availability-check + fallback semantics. Resolved choices are
# snapshotted to quantum.json.routing at run start for replay determinism.
# =============================================================================

# parse_role_arg ROLE VALUE
# Validates VALUE against the per-role enum and runs availability check.
# Roles: planner | critic | executor.
# Enums:
#   planner:  auto | claude | codex | gemini
#   critic:   auto | claude | codex | gemini | none  (critic may be disabled)
#   executor: auto | claude | codex | gemini
# On absence of codex/gemini, emits WARN to stderr and rewrites to 'claude'.
parse_role_arg() {
  local role="${1:-}"
  local value="${2:-}"
  case "$role" in
    planner|critic|executor) : ;;
    *) printf "Error: parse_role_arg: unknown role %q\n" "$role" >&2; return 1 ;;
  esac

  case "$value" in
    auto|claude|codex|gemini) : ;;
    none)
      if [[ "$role" != "critic" ]]; then
        printf "Error: --%s=none not supported (only --critic accepts 'none')\n" "$role" >&2
        return 1
      fi
      ;;
    *)
      local extra=""
      [[ "$role" == "critic" ]] && extra='|none'
      printf "Error: --%s value must be auto|claude|codex|gemini%s (got [%s])\n" \
        "$role" "$extra" "$value" >&2
      return 1
      ;;
  esac

  # Availability check for non-claude/auto/none providers.
  # US-001 / G8: role-aware fallback. The critic role degrades to 'none'
  # (preserving US-002's "downgrade rather than substitute" design intent
  # and matching quantum-loop.ps1). Planner/executor degrade to 'claude'
  # because their role is "execute the work, just maybe with a different
  # model" — disabling them entirely would break the run.
  case "$value" in
    codex|gemini)
      if ! command -v "$value" >/dev/null 2>&1; then
        local _fallback="claude"
        [[ "$role" == "critic" ]] && _fallback="none"
        printf "WARN: per-role routing: %s provider %s not available, falling back to %s\n" "$role" "$value" "$_fallback" >&2
        value="$_fallback"
      fi
      ;;
  esac
  printf '%s' "$value"
}

# =============================================================================
# P5.A2 / US-002 — --critic=auto|codex|gemini|claude|none flag.
# US-001 / G8 (v0.6.3): legacy parse_critic_arg removed as dead code.
# parse_role_arg above is the unified entry point with role-aware fallback:
# critic role degrades to 'none' (preserving the "downgrade rather than
# substitute" design intent), planner/executor degrade to 'claude'.
# =============================================================================


# =============================================================================
# Audit subsystem (v0.9.5 / US-001 decomposition refactor: extracted to
# lib/audit.sh per idea-stage/v0.10.0-design-spike-2026-05-01.md spike 1).
# Sourced BEFORE the test-mode guard so audit functions are defined when
# QL_AUDIT_TEST_MODE=1 sourcing returns. Test-mode guard MUST remain at
# top-level so 'return 0' exits this script's source (cannot be moved into
# lib/audit.sh because 'return' from a sourced sub-lib does not exit the
# parent source).
# =============================================================================
source "$SCRIPT_DIR/lib/audit.sh"


# Test-mode guard (Phase 44 / US-001): when QL_AUDIT_TEST_MODE=1 is set,
# sourcing this file returns here so unit tests can reach the audit
# helpers defined above without triggering the main arg-loop or any
# state-mutating code below.
# G33 / US-002 (v0.6.6): require $#==0 so subprocess `bash quantum-loop.sh
# --audit` with QL_AUDIT_TEST_MODE=1 + QL_AUDIT_TEST_ROWS set still reaches
# the --audit branch below. Sourcing always passes 0 args (verified across
# all current test_*.sh files), so this is backward-compatible.
#
# Companion test-only env var: QL_AUDIT_TEST_ROWS (read by do_audit above).
# Newline-delimited synthetic ROWS for fixture testing. Honored only when
# QL_AUDIT_TEST_MODE=1; ignored in production. See do_audit body.
[[ "${QL_AUDIT_TEST_MODE:-0}" == "1" && "$#" -eq 0 ]] && return 0 2>/dev/null

# Pre-arg-loop audit shortcut: --audit is exclusive and takes no other args.
# Must run BEFORE the normal arg-parsing loop so any stray sibling flag
# (--audit --parallel) is rejected with exit 2.
if [[ " $* " == *" --audit "* ]]; then
  if [[ "$#" -ne 1 ]]; then
    printf "Error: --audit is exclusive and takes no other arguments\n" >&2
    exit 2
  fi
  _audit_validate_env
  do_audit
  exit $?
fi

# Parse arguments
while [[ $# -gt 0 ]]; do
  case $1 in
    --max-iterations)
      # v0.10.2 / US-001 T-001-5: integer-validate to close pre-existing security LOW.
      # Accepts 0 (deliberate smoke-test sentinel; produces empty `seq 1 0` and falls
      # through to MAX_ITERATIONS terminal signal). Rejects negatives, decimals,
      # leading-zero forms (e.g. 0042), and non-numeric input.
      # v0.10.3 / US-001: stale-file ref removed (test_v081_wiring.sh deleted).
      if ! [[ "$2" =~ ^(0|[1-9][0-9]*)$ ]]; then
        printf "ERROR: --max-iterations requires a non-negative integer, got '%s'\n" "$2" >&2
        exit 1
      fi
      MAX_ITERATIONS="$2"
      shift 2
      ;;
    --max-retries)
      # v0.10.3 / US-001: parity validation with --max-iterations (closes
      # v0.10.2 US-005 deferred MEDIUM/LOW review finding). Same regex
      # rationale: 0 retries is a legitimate sentinel ("disable retries").
      if ! [[ "$2" =~ ^(0|[1-9][0-9]*)$ ]]; then
        printf "ERROR: --max-retries requires a non-negative integer, got '%s'\n" "$2" >&2
        exit 1
      fi
      MAX_RETRIES="$2"
      shift 2
      ;;
    --tool)
      TOOL="$2"
      shift 2
      ;;
    --parallel)
      PARALLEL_MODE=true
      shift
      ;;
    --coordinator)
      # v0.8.0 / US-004 (N33) — opt-in per-wave coordinator pattern.
      # Default in v0.8.0 is --legacy-orchestrator (preserves single-spawn).
      # See agents/coordinator.md for the agent definition.
      COORDINATOR_MODE=true
      shift
      ;;
    --legacy-orchestrator)
      # Explicit opt-out from --coordinator (v0.8.0 default; for forward
      # compat when a future release flips the default to coordinator).
      COORDINATOR_MODE=false
      shift
      ;;
    --max-parallel)
      # v0.10.4 / US-001: parity validation. Positive integer only — 0
      # parallel agents is degenerate (nothing to dispatch).
      if ! [[ "$2" =~ ^[1-9][0-9]*$ ]]; then
        printf "ERROR: --max-parallel requires a positive integer, got '%s'\n" "$2" >&2
        exit 1
      fi
      MAX_PARALLEL="$2"
      shift 2
      ;;
    --stale-timeout)
      # v0.10.4 / US-001: parity validation. Positive integer only — 0
      # minute stale threshold would immediately mark every story stale.
      if ! [[ "$2" =~ ^[1-9][0-9]*$ ]]; then
        printf "ERROR: --stale-timeout requires a positive integer, got '%s'\n" "$2" >&2
        exit 1
      fi
      STALE_TIMEOUT="$2"
      shift 2
      ;;
    --critic=*)
      # P5.A2 / US-002 -- critic provider routing (subsumed by US-009 per-role)
      _ql_critic_raw="${1#--critic=}"
      QL_CRITIC=$(parse_role_arg critic "$_ql_critic_raw") || exit 2
      export QL_CRITIC
      shift
      ;;
    --critic)
      if [[ $# -lt 2 || "${2:-}" == --* ]]; then
        printf "Error: --critic requires a value (auto|claude|codex|gemini|none)\n" >&2
        exit 2
      fi
      QL_CRITIC=$(parse_role_arg critic "$2") || exit 2
      export QL_CRITIC
      shift 2
      ;;
    --planner=*)
      # P5.B1 / US-009 — per-role planner routing
      _ql_planner_raw="${1#--planner=}"
      QL_PLANNER=$(parse_role_arg planner "$_ql_planner_raw") || exit 2
      export QL_PLANNER
      shift
      ;;
    --planner)
      if [[ $# -lt 2 || "${2:-}" == --* ]]; then
        printf "Error: --planner requires a value (auto|claude|codex|gemini)\n" >&2
        exit 2
      fi
      QL_PLANNER=$(parse_role_arg planner "$2") || exit 2
      export QL_PLANNER
      shift 2
      ;;
    --executor=*)
      # P5.B1 / US-009 — per-role executor routing
      _ql_executor_raw="${1#--executor=}"
      QL_EXECUTOR=$(parse_role_arg executor "$_ql_executor_raw") || exit 2
      export QL_EXECUTOR
      shift
      ;;
    --executor)
      if [[ $# -lt 2 || "${2:-}" == --* ]]; then
        printf "Error: --executor requires a value (auto|claude|codex|gemini)\n" >&2
        exit 2
      fi
      QL_EXECUTOR=$(parse_role_arg executor "$2") || exit 2
      export QL_EXECUTOR
      shift 2
      ;;
    --non-interactive)
      NON_INTERACTIVE=true
      shift
      ;;
    --help)
      head -29 "$0" | tail -24
      exit 0
      ;;
    *)
      printf "Unknown option: %s\n" "$1"
      exit 1
      ;;
  esac
done

# Validate dependencies
if ! command -v jq &>/dev/null; then
  printf "ERROR: jq is required. Install it: https://jqlang.github.io/jq/download/\n"
  exit 1
fi

# Validate quantum.json
if [[ ! -f quantum.json ]]; then
  printf "ERROR: quantum.json not found. Run /quantum-loop:plan first to create it.\n"
  exit 1
fi

# Source library functions
source "$SCRIPT_DIR/lib/common.sh" || { printf "ERROR: lib/common.sh not found\n"; exit 1; }
source "$SCRIPT_DIR/lib/json-atomic.sh" || { printf "ERROR: lib/json-atomic.sh not found\n"; exit 1; }
source "$SCRIPT_DIR/lib/runner.sh" || { printf "ERROR: lib/runner.sh not found\n"; exit 1; }
source "$SCRIPT_DIR/lib/orchestrator-liveness.sh" || { printf "ERROR: lib/orchestrator-liveness.sh not found\n"; exit 1; }

# v0.8.0 / US-001 (N33) — Wire recovery infrastructure for orchestrator/coordinator
# subagent dispatch. Callers wrap their long-running agent-spawn (e.g., the
# v0.8.0 coordinator pattern in US-004, or external supervisor scripts) with
# this helper so STALE detection actually fires in production. Honors
# QL_LIVENESS_ENABLE (default true) and QL_RESPAWN_CMD env vars.
#
# Usage: ql_wrap_subagent_dispatch [TIMEOUT_SEC] [INTERVAL_SEC] [WORKTREE_PATH]
#   Returns rc=0 when commits land within timeout (LIVE / OPT-OUT).
#   Returns rc=1 when STALE (emits canonical handoff message to stdout).
ql_wrap_subagent_dispatch() {
  wrap_orchestrator_dispatch "$@"
}

# v0.9.0 / US-004 (N42 minor) — enforce --coordinator and --parallel
# mutual exclusion at parse time (replaces v0.8.1 US-001's warn-only
# message that documented the gap). The combination would produce
# nested parallelism (worktree-of-worktrees) that does not compose:
# the parallel path already does worktree-driven wave dispatch, and
# the coordinator agent spawns implementer subagents internally.
# Documented as policy in agents/coordinator.md § "Interaction with
# --parallel" (added in v0.8.2 US-004).
if [[ "$COORDINATOR_MODE" == "true" && "$PARALLEL_MODE" == "true" ]]; then
  printf "ERROR: --coordinator and --parallel are mutually exclusive (see agents/coordinator.md § \"Interaction with --parallel\")\n" >&2
  exit 1
fi

# Load runner manifest (validates tool name, binary existence, sets RUNNER_* vars)
runner_load "$TOOL" || exit 1
runner_ensure_instructions || true

# Experimental tier warning
if [[ "$RUNNER_TIER" == "experimental" && "${NON_INTERACTIVE:-}" != "true" ]]; then
  printf "\nWARNING: Runner '%s' is experimental (tier: %s).\n" "$RUNNER_NAME" "$RUNNER_TIER"
  printf "Experimental runners may not reliably emit quantum signals.\n"
  printf "Press Enter to continue or Ctrl-C to abort...\n"
  read -r
fi
if [[ "$PARALLEL_MODE" == "true" ]]; then
  source "$SCRIPT_DIR/lib/dag-query.sh" || { printf "ERROR: lib/dag-query.sh not found\n"; exit 1; }
  source "$SCRIPT_DIR/lib/worktree.sh" || { printf "ERROR: lib/worktree.sh not found\n"; exit 1; }
  source "$SCRIPT_DIR/lib/spawn.sh" || { printf "ERROR: lib/spawn.sh not found\n"; exit 1; }
  source "$SCRIPT_DIR/lib/monitor.sh" || { printf "ERROR: lib/monitor.sh not found\n"; exit 1; }
  source "$SCRIPT_DIR/lib/resilience.sh" || { printf "ERROR: lib/resilience.sh not found\n"; exit 1; }
fi

# v0.8.3 / US-001 (4th-layer N33 closure): also source lib/spawn.sh under
# COORDINATOR_MODE so v0.9.0 N42's spawn_coordinator() is defined at call
# time. Without this, --coordinator path hits "command not found" before
# reaching the dispatch loop. Architect post-v0.8.2 review caught this gap.
# Idempotent: lib/spawn.sh has its own source-guard so re-sourcing is safe.
if [[ "$COORDINATOR_MODE" == "true" ]]; then
  source "$SCRIPT_DIR/lib/dag-query.sh" || { printf "ERROR: lib/dag-query.sh not found\n"; exit 1; }
  source "$SCRIPT_DIR/lib/spawn.sh" || { printf "ERROR: lib/spawn.sh not found\n"; exit 1; }
fi

# =============================================================================
# Archive previous run if branch changed
# =============================================================================

BRANCH=$(jq -r '.branchName' quantum.json)
LAST_BRANCH_FILE=".last-ql-branch"

if [[ -f "$LAST_BRANCH_FILE" ]]; then
  LAST_BRANCH=$(cat "$LAST_BRANCH_FILE")
  if [[ "$LAST_BRANCH" != "$BRANCH" ]]; then
    ARCHIVE_DIR="archive/$(date +%Y-%m-%d)-${BRANCH//\//-}"
    printf "Branch changed from %s to %s\n" "$LAST_BRANCH" "$BRANCH"
    printf "Archiving previous run to %s\n" "$ARCHIVE_DIR"
    mkdir -p "$ARCHIVE_DIR"
    cp quantum.json "$ARCHIVE_DIR/quantum.json" 2>/dev/null || true
    printf "Archive complete.\n"
  fi
fi

printf "%s" "$BRANCH" > "$LAST_BRANCH_FILE"

# Update maxAttempts in quantum.json if different from default
json_atomic_update_args '
  .stories |= map(.retries.maxAttempts = $max)
' quantum.json --argjson max "$MAX_RETRIES"

# =============================================================================
# Iteration helpers (v0.9.5 / US-001 decomposition refactor: extracted to
# lib/loop-helpers.sh per idea-stage/v0.10.0-design-spike-2026-05-01.md).
# Sourced AFTER lib/runner.sh (uses RUNNER_NAME) and BEFORE the main loop.
# =============================================================================
source "$SCRIPT_DIR/lib/loop-helpers.sh"


# =============================================================================
# Main header
# =============================================================================

printf "===========================================\n"
printf "  Quantum-Loop Autonomous Development\n"
printf "===========================================\n"
printf "  Branch:      %s\n" "$BRANCH"
printf "  Runner:      %s (%s)\n" "$RUNNER_NAME" "$RUNNER_BINARY"
printf "  Tier:        %s\n" "$RUNNER_TIER"
printf "  Instruction: %s\n" "$RUNNER_INSTRUCTION_NATIVE"
printf "  Max Iter:    %s\n" "$MAX_ITERATIONS"
printf "  Max Retries: %s\n" "$MAX_RETRIES"
if [[ "$PARALLEL_MODE" == "true" ]]; then
  printf "  Mode:        Parallel (max %s concurrent)\n" "$MAX_PARALLEL"
else
  printf "  Mode:        Sequential\n"
fi
printf "===========================================\n\n"

# =============================================================================
# Parallel execution mode
# =============================================================================

# v0.10.0 / US-001: extracted to lib/parallel-mode.sh (last block-extraction
# completing the v0.9.5 decomposition arc). Wrapped in run_parallel_mode().
# Sources lib/parallel-mode.sh after lib/json-atomic.sh + lib/loop-helpers.sh
# (uses json_atomic_update_args + emit_terminal_signal + several helpers).
# shellcheck source=lib/parallel-mode.sh
source "$SCRIPT_DIR/lib/parallel-mode.sh"
if [[ "$PARALLEL_MODE" == "true" ]]; then
  run_parallel_mode
fi

# =============================================================================
# Sequential / coordinator iteration loop (v0.9.5 / US-001 decomposition:
# extracted to lib/iteration-loop.sh per spike 1). Wrapped in
# run_iteration_loop() so 'local' declarations work properly. Parallel mode
# block above stays in this file (deferred to v0.10.0+).
# =============================================================================
source "$SCRIPT_DIR/lib/iteration-loop.sh"
run_iteration_loop
