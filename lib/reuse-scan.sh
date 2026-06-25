#!/usr/bin/env bash
# lib/reuse-scan.sh — reuse-first candidate search + gate (Track A / Q2).
#
# Forces the build agent to REUSE existing code instead of reinventing it.
# Two pieces:
#   scan_reuse_candidates — the graph-FREE fallback: grep the existing tree for
#                           symbol DEFINITIONS whose name relates to a story's
#                           concept terms, so ql-plan can populate
#                           story.reuseCandidates[]. When the code graph is
#                           available, prefer the relational_envelope verb (see
#                           skills/ql-plan/SKILL.md); this is the no-graph path.
#   reuse_gate            — reuse-or-justify check: if a story has reuseCandidates
#                           and the implementer's diff neither references one nor
#                           records a noReuseJustification, warn (advisory) or
#                           fail (under QL_QUALITY_BLOCKING).
#
# Why grep not a language tool: quantum-loop runs in a bare Git Bash shell on
# Windows; grep + jq are the only guaranteed deps (same rationale as
# lib/dead-code.sh). This is a coarse candidate finder, not a precise index.
#
# Library contract: no shell flags at source time; strict mode only in the CLI
# block at bottom.

if [[ -n "${_QL_REUSE_SCAN_LIB:-}" ]]; then
  return 0 2>/dev/null || true
fi
readonly _QL_REUSE_SCAN_LIB=1

_REUSE_DEF_KW='(def|function|func|class|interface|type|struct)'
_REUSE_INCLUDES=(--include='*.py' --include='*.ts' --include='*.tsx' --include='*.js' --include='*.jsx' --include='*.mjs' --include='*.go' --include='*.rs' --include='*.java')
_REUSE_TEST_RE='(/tests?/|/__tests__/|_test\.|\.test\.|\.spec\.)'

# scan_reuse_candidates(terms_csv, [path]) -> JSON array
# Existing symbol definitions whose name contains any term (test files excluded).
scan_reuse_candidates() {
  local terms="${1:?scan_reuse_candidates: terms (csv) required}"
  local path="${2:-.}"
  local out='[]'
  local -a term_arr
  IFS=',' read -r -a term_arr <<< "$terms"
  local term file line text sym hits
  for term in "${term_arr[@]}"; do
    term=$(printf '%s' "$term" | tr -cd '[:alnum:]_')
    [[ -z "$term" ]] && continue
    hits=$(grep -rEIni "${_REUSE_INCLUDES[@]}" \
             "${_REUSE_DEF_KW}[[:space:]]+[A-Za-z0-9_]*${term}[A-Za-z0-9_]*" "$path" 2>/dev/null \
           | grep -vEi "$_REUSE_TEST_RE" || true)
    [[ -z "$hits" ]] && continue
    while IFS=: read -r file line text; do
      [[ -z "$file" || -z "$line" ]] && continue
      sym=$(printf '%s' "$text" | grep -oiE "${_REUSE_DEF_KW}[[:space:]]+[A-Za-z_][A-Za-z0-9_]*" | head -1 | awk '{print $NF}')
      [[ -z "$sym" ]] && continue
      out=$(jq -c --arg s "$sym" --arg f "$file" --argjson l "$line" --arg t "$term" \
        '. + [{symbol:$s, file:$f, line:$l, term:$t}]' <<< "$out")
    done <<< "$hits"
  done
  jq -c 'unique_by(.symbol + "@" + .file + ":" + (.line|tostring))' <<< "$out"
}

# reuse_gate(candidates_json, text) -> 0 | 1
# Pass if: no candidates, OR text has a noReuseJustification marker, OR text
# references at least one candidate symbol. Otherwise advisory (rc 0 + warn) by
# default; rc 1 under QL_QUALITY_BLOCKING (the Q4 opt-in pattern).
reuse_gate() {
  local candidates="${1:?reuse_gate: candidates json required}"
  local text="${2:?reuse_gate: text required}"
  local n; n=$(jq 'length' <<< "$candidates" 2>/dev/null)
  [[ "${n:-0}" -eq 0 ]] && return 0
  if printf '%s' "$text" | grep -qiE 'noReuseJustification|NO-REUSE:'; then return 0; fi
  local sym matched=0
  while IFS= read -r sym; do
    sym="${sym%$'\r'}"   # jq -r on Git Bash/MSYS appends CR; strip it (repo convention)
    [[ -z "$sym" ]] && continue
    if printf '%s' "$text" | grep -qwF -- "$sym"; then matched=1; break; fi
  done < <(jq -r '.[].symbol' <<< "$candidates")
  [[ "$matched" -eq 1 ]] && return 0
  case "${QL_QUALITY_BLOCKING:-}" in
    1|true|TRUE|yes|on)
      printf "[REUSE] BLOCK: %s existing candidate(s) not reused and no noReuseJustification.\n" "$n" >&2
      return 1 ;;
    *)
      printf "WARNING: [REUSE] %s existing candidate(s) available but not reused (advisory).\n" "$n" >&2
      return 0 ;;
  esac
}

# ------------------------------------------------------------------------------
# CLI entry. Strict mode only here.
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  set -euo pipefail
  subcmd="${1:-}"; shift || true
  case "$subcmd" in
    scan)  scan_reuse_candidates "$@" ;;
    gate)  reuse_gate "$@" ;;
    *)
      cat >&2 <<USAGE
Usage: bash lib/reuse-scan.sh <subcmd> [args...]
  scan TERMS_CSV [PATH]        — JSON array of existing symbol defs matching terms (tests excluded)
  gate CANDIDATES_JSON TEXT    — reuse-or-justify; rc 1 under QL_QUALITY_BLOCKING if violated
USAGE
      exit 2 ;;
  esac
fi
