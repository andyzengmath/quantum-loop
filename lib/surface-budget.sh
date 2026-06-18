#!/usr/bin/env bash
# lib/surface-budget.sh — per-story NEW-surface budget gate (Track A / Q3).
#
# Stops slop being born by capping how much NEW surface a single story may add
# before it reaches the two-stage review gate. A story that blows its budget is
# failed back to re-plan (split the story) rather than reviewed — so oversized
# files, runaway diffs, and speculative abstraction layers can't land inside one
# story.
#
# Why in-repo regex heuristics (same rationale as lib/dead-code.sh):
#   1. quantum-loop runs in a bare Git Bash shell on Windows — we can't assume
#      lizard/radon/tree-sitter are installed.
#   2. Deterministic, 0-token, no tool-version skew.
#   3. The budget is a coarse guardrail, not a precise AST metric — a regex
#      count of new definitions is sufficient to catch "this story added 9 new
#      abstractions / 600 new lines".
#
# Functions:
#   compute_surface BASE HEAD [PATH_FILTER]
#     Emits JSON {newFiles, addedLines, newSymbols, newAbstractions} for the
#     diff BASE..HEAD. PATH_FILTER is an optional grep -E regex on file paths.
#
#   check_budget SURFACE_JSON BUDGET_JSON
#     Pure (no git). Prints a JSON array of breached axes to stdout. Returns 0
#     if within budget, 1 if any axis is over. BUDGET_JSON fields are optional:
#     {maxNewFiles, maxNewLines, maxNewPublicSymbols, maxNewAbstractions} — an
#     absent field = no cap on that axis.
#
#   gate_budget BASE HEAD BUDGET_JSON [PATH_FILTER]
#     compute_surface | check_budget. Returns 0 within budget, 1 on breach.
#
# Library contract: no shell flags at source time; strict mode only in the CLI
# entry block at bottom (mirrors lib/dead-code.sh, lib/quantum-validate.sh).

# Source-guard
if [[ -n "${_QL_SURFACE_BUDGET_LIB:-}" ]]; then
  return 0 2>/dev/null || true
fi
readonly _QL_SURFACE_BUDGET_LIB=1

# compute_surface(base, head, [path_filter]) -> JSON
compute_surface() {
  local base="${1:?compute_surface: base required}"
  local head="${2:?compute_surface: head required}"
  local filter="${3:-}"

  local namestatus numstat diff
  namestatus=$(git diff --name-status "$base" "$head" 2>/dev/null || true)
  numstat=$(git diff --numstat "$base" "$head" 2>/dev/null || true)
  diff=$(git diff "$base" "$head" 2>/dev/null || true)

  local new_files=0 added_lines=0

  # New files = status A (added). Renames (R) are not "new".
  local status path
  while IFS=$'\t' read -r status path _rest; do
    [[ -z "$status" ]] && continue
    [[ -n "$filter" ]] && ! grep -qE "$filter" <<< "$path" && continue
    [[ "$status" == A* ]] && new_files=$((new_files + 1))
  done <<< "$namestatus"

  # Added lines = sum of the first numstat column (skip binary "-").
  local add del npath
  while IFS=$'\t' read -r add del npath; do
    [[ -z "$npath" ]] && continue
    [[ "$add" == "-" ]] && continue
    [[ -n "$filter" ]] && ! grep -qE "$filter" <<< "$npath" && continue
    added_lines=$((added_lines + add))
  done <<< "$numstat"

  # Symbol / abstraction counts from ADDED diff lines only ('+' but not '+++').
  local added_only
  added_only=$(grep -E '^\+' <<< "$diff" | grep -vE '^\+\+\+' || true)

  local new_symbols new_abstractions
  new_symbols=$(grep -cE \
    '^\+[[:space:]]*((export[[:space:]]+)?(async[[:space:]]+)?(function|func|def|class|interface|type|struct)[[:space:]]+[A-Za-z_])' \
    <<< "$added_only" || true)
  new_abstractions=$(grep -cE \
    '^\+[[:space:]]*(export[[:space:]]+)?((abstract[[:space:]]+class|interface)[[:space:]]+[A-Za-z_]|type[[:space:]]+[A-Za-z_][A-Za-z0-9_]*[[:space:]]*=|class[[:space:]]+[A-Za-z_][A-Za-z0-9_]*\((ABC|Protocol))' \
    <<< "$added_only" || true)

  jq -cn \
    --argjson nf "$new_files" \
    --argjson al "$added_lines" \
    --argjson ns "${new_symbols:-0}" \
    --argjson na "${new_abstractions:-0}" \
    '{newFiles: $nf, addedLines: $al, newSymbols: $ns, newAbstractions: $na}'
}

# check_budget(surface_json, budget_json) -> prints breaches[], rc 0|1
check_budget() {
  local surface="${1:?check_budget: surface json required}"
  local budget="${2:?check_budget: budget json required}"

  local breaches
  breaches=$(jq -cn --argjson s "$surface" --argjson b "$budget" '
    [
      {axis: "newFiles",        limit: ($b.maxNewFiles // null),         actual: $s.newFiles},
      {axis: "addedLines",      limit: ($b.maxNewLines // null),         actual: $s.addedLines},
      {axis: "newSymbols",      limit: ($b.maxNewPublicSymbols // null), actual: $s.newSymbols},
      {axis: "newAbstractions", limit: ($b.maxNewAbstractions // null),  actual: $s.newAbstractions}
    ]
    | map(select(.limit != null and .actual > .limit))
  ')

  printf '%s' "$breaches"
  [[ "$(jq 'length' <<< "$breaches")" -eq 0 ]]
}

# gate_budget(base, head, budget_json, [path_filter]) -> rc 0|1
gate_budget() {
  local base="${1:?gate_budget: base required}"
  local head="${2:?gate_budget: head required}"
  local budget="${3:?gate_budget: budget json required}"
  local filter="${4:-}"
  local surface
  surface=$(compute_surface "$base" "$head" "$filter")
  check_budget "$surface" "$budget"
}

# ------------------------------------------------------------------------------
# CLI entry. Strict mode only here.
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  set -euo pipefail
  subcmd="${1:-}"
  shift || true
  case "$subcmd" in
    compute) compute_surface "$@" ;;
    check)   check_budget "$@" ;;
    gate)    gate_budget "$@" ;;
    *)
      cat >&2 <<USAGE
Usage: bash lib/surface-budget.sh <subcmd> [args...]
  compute BASE HEAD [PATH_FILTER]          — JSON {newFiles, addedLines, newSymbols, newAbstractions}
  check   SURFACE_JSON BUDGET_JSON         — prints breached axes; rc 1 on breach
  gate    BASE HEAD BUDGET_JSON [FILTER]   — compute + check; rc 1 on breach
USAGE
      exit 2
      ;;
  esac
fi
