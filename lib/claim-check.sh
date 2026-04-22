#!/usr/bin/env bash
# lib/claim-check.sh -- completion-claim linter for quantum-loop agent output
#
# Provides: claim_check_scan(), claim_check_block(), claim_check_verdict()
#
# Purpose: Enforce the Iron Law by grep-level lint of agent output. Detects:
#   - Hedge phrases ("should work", "probably passes", "might be fine") that
#     signal a completion claim without verification.
#   - Stale-evidence patterns ("passed earlier", "previously verified") that
#     cite verification from a past run rather than the current turn.
#   - Polite-stop anti-pattern: reporting "APPROVED" or "DONE" without moving
#     to the next step in the same turn (per OMC Ralph prohibition).
#
# Borrowed from: Superpowers' verification-before-completion rationalization
# table + OMC Ralph's polite-stop ban. Grounded by FUR arXiv:2502.14829 which
# shows verbalized CoT is often NOT parametrically faithful — claims need
# artifacts, not rephrasing.
#
# Library contract: does NOT set shell flags at source-time. Sourcing scripts
# keep their existing set -e / set -u semantics. (Direct CLI invocation at
# the bottom of this file enables strict mode locally.)

# ------------------------------------------------------------------------------
# Configuration

# Hedge phrases that usually indicate unverified completion claims.
# Case-insensitive match. Each phrase should be a rationalization, not a
# description of degree (so "approximately 5 items" is fine; "should work"
# is not).
if [[ -z "${CLAIM_CHECK_HEDGE_PHRASES+x}" ]]; then
readonly CLAIM_CHECK_HEDGE_PHRASES=(
  "should work"
  "should pass"
  "probably passes"
  "probably works"
  "probably fine"
  "likely passes"
  "likely works"
  "almost certainly"
  "i'm confident"
  "i believe"
  "i think it"
  "seems to work"
  "seems correct"
  "appears to work"
  "appears correct"
  "must work"
  "should be good"
  "should be ready"
  "ready to ship"
  "close enough"
  "good enough"
)
readonly CLAIM_CHECK_STALE_PHRASES=(
  "passed earlier"
  "worked before"
  "previously verified"
  "previously passed"
  "last run passed"
  "i already tested"
  "tested earlier"
  "checked before"
  "verified last time"
)
readonly CLAIM_CHECK_POLITE_STOP_PHRASES=(
  "work is complete"
  "implementation is done"
  "ready for your review"
  "awaiting confirmation"
  "let me know if"
  "handing off to"
  "now awaiting"
  "will stop here"
)
fi  # guard against double-source

# ------------------------------------------------------------------------------
# Helpers

# Print a single finding to stdout as a pipe-separated record.
# Fields: category | phrase | line-number | excerpt
_claim_check_emit() {
  local category="$1"
  local phrase="$2"
  local lineno="$3"
  local excerpt="$4"
  printf '%s|%s|%s|%s\n' "$category" "$phrase" "$lineno" "$excerpt"
}

# ------------------------------------------------------------------------------
# Public API

# claim_check_scan <file-or-stdin>
# Scans input for hedge / stale / polite-stop patterns and emits one
# finding per hit. Returns 0 even on findings — caller inspects output
# to decide action.
#
# Examples:
#   claim_check_scan agent-output.txt
#   echo "$response" | claim_check_scan /dev/stdin
claim_check_scan() {
  local source="${1:--}"
  local content
  if [[ "$source" == "-" || "$source" == "/dev/stdin" ]]; then
    content=$(cat)
  elif [[ -f "$source" ]]; then
    content=$(cat "$source")
  else
    printf 'ERROR: claim_check_scan: %s is not a file or stdin\n' "$source" >&2
    return 2
  fi

  # Iterate phrase tables; grep -in gives line-number prefix.
  local phrase lineno excerpt
  for phrase in "${CLAIM_CHECK_HEDGE_PHRASES[@]}"; do
    while IFS=':' read -r lineno excerpt; do
      [[ -z "$lineno" ]] && continue
      _claim_check_emit "hedge" "$phrase" "$lineno" "${excerpt:0:120}"
    done < <(printf '%s\n' "$content" | grep -in -F "$phrase" 2>/dev/null || true)
  done

  for phrase in "${CLAIM_CHECK_STALE_PHRASES[@]}"; do
    while IFS=':' read -r lineno excerpt; do
      [[ -z "$lineno" ]] && continue
      _claim_check_emit "stale-evidence" "$phrase" "$lineno" "${excerpt:0:120}"
    done < <(printf '%s\n' "$content" | grep -in -F "$phrase" 2>/dev/null || true)
  done

  for phrase in "${CLAIM_CHECK_POLITE_STOP_PHRASES[@]}"; do
    while IFS=':' read -r lineno excerpt; do
      [[ -z "$lineno" ]] && continue
      _claim_check_emit "polite-stop" "$phrase" "$lineno" "${excerpt:0:120}"
    done < <(printf '%s\n' "$content" | grep -in -F "$phrase" 2>/dev/null || true)
  done
}

# claim_check_verdict <findings>
# Reads pipe-separated findings on stdin. Emits one line:
#   "clean"                         — zero findings
#   "hedge:N stale:M polite-stop:K" — summary counts
claim_check_verdict() {
  local hedge=0 stale=0 polite=0
  local cat rest
  while IFS='|' read -r cat rest; do
    [[ -z "$cat" ]] && continue
    case "$cat" in
      hedge) ((hedge++)) ;;
      stale-evidence) ((stale++)) ;;
      polite-stop) ((polite++)) ;;
    esac
  done
  if (( hedge + stale + polite == 0 )); then
    printf 'clean\n'
  else
    printf 'hedge:%d stale:%d polite-stop:%d\n' "$hedge" "$stale" "$polite"
  fi
}

# claim_check_block <threshold-category> [findings-file]
# Exits non-zero (1) if the input contains any findings of the specified
# category. Intended for CI / pre-commit gating.
#
# Examples:
#   claim_check_scan output.txt | claim_check_block hedge
#   claim_check_scan output.txt | claim_check_block polite-stop
claim_check_block() {
  local threshold="${1:?threshold category required: hedge | stale-evidence | polite-stop}"
  local hit=0
  local cat rest
  while IFS='|' read -r cat rest; do
    [[ "$cat" == "$threshold" ]] && { hit=1; break; }
  done
  return $((1 - hit))  # 0 if hit, 1 if none
}

# ------------------------------------------------------------------------------
# CLI mode — if script is invoked directly (not sourced), run scan + verdict.

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  set -euo pipefail
  if [[ $# -eq 0 ]]; then
    cat >&2 <<USAGE
Usage: $(basename "$0") [file | -]
  Scans input for hedge / stale / polite-stop claim patterns.
  With no argument, reads stdin.
  Prints findings then a verdict line.
  Exit code: 0 = clean, 1 = at least one hedge finding.

Examples:
  bash lib/claim-check.sh < agent-output.log
  bash lib/claim-check.sh output.txt
  echo "tests should pass" | bash lib/claim-check.sh -
USAGE
    exit 2
  fi

  findings=$(claim_check_scan "$1")
  if [[ -n "$findings" ]]; then
    printf 'Findings:\n%s\n\n' "$findings"
  fi
  verdict=$(printf '%s\n' "$findings" | claim_check_verdict)
  printf 'Verdict: %s\n' "$verdict"

  if [[ "$verdict" == "clean" ]]; then
    exit 0
  else
    exit 1
  fi
fi
