#!/usr/bin/env bash
# validate.sh — Validate a runner manifest against required fields using jq.
#
# Usage: bash schemas/validate.sh <manifest-path>
#
# Validates that a runner JSON manifest has all required top-level and nested
# fields. Exits 0 on success, 1 on validation failure with a descriptive message.
#
# Note: This uses jq field-presence checks rather than full JSON Schema
# validation (which would require ajv or similar). For CI, pair with ajv-cli
# if full schema validation is needed.

set -euo pipefail

MANIFEST="${1:?Usage: validate.sh <manifest-path>}"

if [[ ! -f "$MANIFEST" ]]; then
  echo "ERROR: File not found: $MANIFEST" >&2
  exit 1
fi

# Verify it's valid JSON
if ! jq empty "$MANIFEST" 2>/dev/null; then
  echo "ERROR: Invalid JSON: $MANIFEST" >&2
  exit 1
fi

ERRORS=0

check_field() {
  local path="$1"
  local desc="$2"
  if [[ "$(jq -r "$path // empty" "$MANIFEST" 2>/dev/null)" == "" ]]; then
    echo "ERROR: Missing required field: $desc ($path)" >&2
    ERRORS=$((ERRORS + 1))
  fi
}

check_field '.name' 'name'
check_field '.displayName' 'displayName'
check_field '.binary' 'binary'
check_field '.tier' 'tier'
check_field '.installHint' 'installHint'
check_field '.version' 'version'
check_field '.invocation.promptDelivery' 'invocation.promptDelivery'
check_field '.invocation.headlessFlags' 'invocation.headlessFlags'
check_field '.invocation.autoApproveFlags' 'invocation.autoApproveFlags'
check_field '.instructionFile.native' 'instructionFile.native'
check_field '.signals' 'signals'

# Validate tier enum
TIER=$(jq -r '.tier' "$MANIFEST" 2>/dev/null)
if [[ "$TIER" != "guaranteed" && "$TIER" != "tested" && "$TIER" != "experimental" ]]; then
  echo "ERROR: Invalid tier '$TIER'. Must be one of: guaranteed, tested, experimental" >&2
  ERRORS=$((ERRORS + 1))
fi

# Validate promptDelivery enum
PD=$(jq -r '.invocation.promptDelivery' "$MANIFEST" 2>/dev/null)
if [[ "$PD" != "flag" && "$PD" != "positional" && "$PD" != "stdin" ]]; then
  echo "ERROR: Invalid promptDelivery '$PD'. Must be one of: flag, positional, stdin" >&2
  ERRORS=$((ERRORS + 1))
fi

if [[ $ERRORS -gt 0 ]]; then
  echo "FAILED: $ERRORS validation error(s) in $MANIFEST" >&2
  exit 1
fi

echo "OK: $MANIFEST is valid"
exit 0
