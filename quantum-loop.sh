#!/usr/bin/env bash
set -euo pipefail

# =============================================================================
# quantum-loop.sh -- Autonomous development loop with DAG-based story selection,
# two-stage review gates, and structured error recovery.
#
# Usage:
#   ./quantum-loop.sh [OPTIONS]
#
# Options:
#   --max-iterations N   Maximum iterations before stopping (default: 20)
#   --max-retries N      Max retry attempts per story (default: 3)
#   --tool TOOL          AI tool to use: "claude" (default) or "amp"
#   --help               Show this help message
#
# Prerequisites:
#   - quantum.json must exist in the current directory (run /quantum-loop:plan first)
#   - jq must be installed
#   - claude or amp CLI must be installed
# =============================================================================

# Defaults
MAX_ITERATIONS=20
MAX_RETRIES=3
TOOL="claude"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Parse arguments
while [[ $# -gt 0 ]]; do
  case $1 in
    --max-iterations)
      MAX_ITERATIONS="$2"
      shift 2
      ;;
    --max-retries)
      MAX_RETRIES="$2"
      shift 2
      ;;
    --tool)
      TOOL="$2"
      shift 2
      ;;
    --help)
      head -20 "$0" | tail -15
      exit 0
      ;;
    *)
      echo "Unknown option: $1"
      exit 1
      ;;
  esac
done

# Validate tool
if [[ "$TOOL" != "claude" && "$TOOL" != "amp" ]]; then
  echo "ERROR: --tool must be 'claude' or 'amp'. Got: $TOOL"
  exit 1
fi

# Validate dependencies
if ! command -v jq &>/dev/null; then
  echo "ERROR: jq is required. Install it: https://jqlang.github.io/jq/download/"
  exit 1
fi

if ! command -v "$TOOL" &>/dev/null; then
  echo "ERROR: $TOOL CLI not found. Please install it first."
  exit 1
fi

# Validate quantum.json
if [[ ! -f quantum.json ]]; then
  echo "ERROR: quantum.json not found. Run /quantum-loop:plan first to create it."
  exit 1
fi

# =============================================================================
# Archive previous run if branch changed
# =============================================================================

BRANCH=$(jq -r '.branchName' quantum.json)
LAST_BRANCH_FILE=".last-ql-branch"

if [[ -f "$LAST_BRANCH_FILE" ]]; then
  LAST_BRANCH=$(cat "$LAST_BRANCH_FILE")
  if [[ "$LAST_BRANCH" != "$BRANCH" ]]; then
    ARCHIVE_DIR="archive/$(date +%Y-%m-%d)-${LAST_BRANCH//\//-}"
    echo "Branch changed from $LAST_BRANCH to $BRANCH"
    echo "Archiving previous run to $ARCHIVE_DIR"
    mkdir -p "$ARCHIVE_DIR"
    cp quantum.json "$ARCHIVE_DIR/quantum.json" 2>/dev/null || true
    echo "Archive complete."
  fi
fi

echo "$BRANCH" > "$LAST_BRANCH_FILE"

# Update maxAttempts in quantum.json if different from default
jq --argjson max "$MAX_RETRIES" '
  .stories |= map(.retries.maxAttempts = $max)
' quantum.json > quantum.json.tmp && mv quantum.json.tmp quantum.json

# =============================================================================
# Main loop
# =============================================================================

echo "==========================================="
echo "  Quantum-Loop Autonomous Development"
echo "==========================================="
echo "  Branch:     $BRANCH"
echo "  Tool:       $TOOL"
echo "  Max Iter:   $MAX_ITERATIONS"
echo "  Max Retries: $MAX_RETRIES"
echo "==========================================="
echo ""

for ITERATION in $(seq 1 "$MAX_ITERATIONS"); do
  echo ""
  echo "=== Iteration $ITERATION / $MAX_ITERATIONS ==="
  echo ""

  # -------------------------------------------------------------------------
  # Select next executable story from the dependency DAG
  # -------------------------------------------------------------------------
  # A story is executable when:
  #   1. status is "pending" or "failed" (with retries remaining)
  #   2. all stories in dependsOn have status "passed"
  # Among eligible stories, pick the one with lowest priority number.
  # -------------------------------------------------------------------------

  STORY_ID=$(jq -r '
    .stories as $all |
    [.stories[] |
      select(
        (.status == "pending" or (.status == "failed" and .retries.attempts < .retries.maxAttempts)) and
        (if (.dependsOn | length) == 0 then true
         else [.dependsOn[] | . as $dep | $all | map(select(.id == $dep)) | .[0].status] | all(. == "passed")
         end)
      )
    ] |
    sort_by(.priority) |
    .[0].id // empty
  ' quantum.json)

  if [[ -z "$STORY_ID" || "$STORY_ID" == "null" ]]; then
    # Check if all stories are passed
    ALL_PASSED=$(jq '[.stories[].status] | all(. == "passed")' quantum.json)
    if [[ "$ALL_PASSED" == "true" ]]; then
      echo ""
      echo "==========================================="
      echo "  <quantum>COMPLETE</quantum>"
      echo "  All stories passed! Feature is done."
      echo "==========================================="
      exit 0
    else
      echo ""
      echo "==========================================="
      echo "  <quantum>BLOCKED</quantum>"
      echo "  No executable stories remain."
      echo "  Remaining stories are blocked or have"
      echo "  exhausted their retry attempts."
      echo "==========================================="
      echo ""
      echo "Story statuses:"
      jq -r '.stories[] | "  \(.id): \(.status) (retries: \(.retries.attempts)/\(.retries.maxAttempts))"' quantum.json
      exit 1
    fi
  fi

  STORY_TITLE=$(jq -r --arg id "$STORY_ID" '.stories[] | select(.id == $id) | .title' quantum.json)
  STORY_ATTEMPT=$(jq -r --arg id "$STORY_ID" '.stories[] | select(.id == $id) | .retries.attempts' quantum.json)

  echo "Story:   $STORY_ID - $STORY_TITLE"
  echo "Attempt: $((STORY_ATTEMPT + 1))"
  echo ""

  # Mark story as in_progress
  jq --arg id "$STORY_ID" '
    .stories |= map(if .id == $id then .status = "in_progress" else . end) |
    .updatedAt = (now | todate)
  ' quantum.json > quantum.json.tmp && mv quantum.json.tmp quantum.json

  # -------------------------------------------------------------------------
  # Spawn fresh AI instance
  # -------------------------------------------------------------------------

  PROMPT_FILE="$SCRIPT_DIR/CLAUDE.md"
  if [[ "$TOOL" == "amp" && -f "$SCRIPT_DIR/prompt.md" ]]; then
    PROMPT_FILE="$SCRIPT_DIR/prompt.md"
  fi

  echo "Spawning $TOOL for story $STORY_ID..."

  if [[ "$TOOL" == "claude" ]]; then
    OUTPUT=$(claude --dangerously-skip-permissions --print \
      -p "$(cat "$PROMPT_FILE")" \
      -- "Implement story $STORY_ID from quantum.json. This is iteration $ITERATION." 2>&1) || true
  else
    OUTPUT=$(echo "$(cat "$PROMPT_FILE")

Implement story $STORY_ID from quantum.json. This is iteration $ITERATION." | amp 2>&1) || true
  fi

  # -------------------------------------------------------------------------
  # Process output
  # -------------------------------------------------------------------------

  if echo "$OUTPUT" | grep -q "<quantum>COMPLETE</quantum>"; then
    echo ""
    echo "==========================================="
    echo "  <quantum>COMPLETE</quantum>"
    echo "  All stories passed! Feature is done."
    echo "==========================================="
    exit 0

  elif echo "$OUTPUT" | grep -q "<quantum>STORY_PASSED</quantum>"; then
    echo "Story $STORY_ID PASSED. Continuing to next story..."

  elif echo "$OUTPUT" | grep -q "<quantum>STORY_FAILED</quantum>"; then
    echo "Story $STORY_ID FAILED (attempt $((STORY_ATTEMPT + 1))). Will retry if attempts remain."

  elif echo "$OUTPUT" | grep -q "<quantum>BLOCKED</quantum>"; then
    echo ""
    echo "==========================================="
    echo "  <quantum>BLOCKED</quantum>"
    echo "  Agent reports no executable stories."
    echo "==========================================="
    jq -r '.stories[] | "  \(.id): \(.status) (retries: \(.retries.attempts)/\(.retries.maxAttempts))"' quantum.json
    exit 1

  else
    echo "WARNING: No recognized signal in output. Story may not have completed cleanly."
    echo "Last 10 lines of output:"
    echo "$OUTPUT" | tail -10
  fi

  # Brief pause between iterations
  sleep 2
done

echo ""
echo "==========================================="
echo "  <quantum>MAX_ITERATIONS</quantum>"
echo "  Reached maximum of $MAX_ITERATIONS iterations."
echo "==========================================="
echo ""
echo "Story statuses:"
jq -r '.stories[] | "  \(.id): \(.status) (retries: \(.retries.attempts)/\(.retries.maxAttempts))"' quantum.json
exit 2
