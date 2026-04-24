#!/usr/bin/env bash
# lib/wave-boundary.sh — cross-story wave-boundary scans.
#
# The Phase 8 post-pipeline review hook (skills/ql-execute/SKILL.md) calls
# for a "cross-story constant scan" that catches the Math-Research class of
# regressions: two stories both merged green but referenced the same concept
# under different literal constants (e.g. 'google' vs 'google-api-key').
# Per-story review is blind to this because the two stories are correct in
# isolation; the defect surfaces only once both are on the trunk together.
#
# This library ships the deterministic scan. The LLM-driven interpretation
# of "same concept" lives in the ql-deep-review skill; here we supply the
# canonicalization + grouping primitives that flag suspicious variants.
#
# Functions:
#   extract_string_literals BASE HEAD
#     — prints "file|line|literal" triples for every quoted string added
#       across the BASE..HEAD diff.
#   canonicalize LITERAL
#     — strips known suffixes (-api-key, -token, -secret, -id, -key),
#       lowercases, collapses hyphens/underscores; echoes canonical form.
#   scan_divergent_constants BASE HEAD
#     — emits a JSON array of findings: one per canonical form that has
#       ≥2 distinct literal variants across ≥2 distinct files.
#   has_divergence BASE HEAD
#     — exits 0 if any findings, exits 1 if clean. Convenient gate.
#
# Library contract (same as Phase 5/8/9 libs): does NOT set shell flags at
# source time. Strict mode only inside the CLI-entry block at bottom.

WAVE_BOUNDARY_LIB_DIR="${WAVE_BOUNDARY_LIB_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)}"

# Known trailing tokens that mark a literal as a "key-like" identifier.
# When canonicalizing we strip these so "google" and "google-api-key"
# collide into a single canonical form.
if [[ -z "${WAVE_BOUNDARY_SUFFIXES+x}" ]]; then
readonly WAVE_BOUNDARY_SUFFIXES=(
  "-api-key" "_api_key" ".api.key"
  "-api-token" "_api_token"
  "-secret" "_secret"
  "-token" "_token"
  "-key" "_key"
  "-id" "_id"
  "-url" "_url"
)
fi

# canonicalize(literal)
# Strips known suffixes, lowercases, normalizes separators.
# Echoes the canonical form.
canonicalize() {
  local lit="${1:-}"
  # lowercase
  lit="${lit,,}"
  # strip each known suffix (longest-match first by iterating ordered)
  local s
  for s in "${WAVE_BOUNDARY_SUFFIXES[@]}"; do
    local s_lc="${s,,}"
    if [[ "$lit" == *"$s_lc" ]]; then
      lit="${lit%"$s_lc"}"
      break
    fi
  done
  # collapse - and _ to a single token separator (empty)
  lit="${lit//-/}"
  lit="${lit//_/}"
  printf "%s" "$lit"
}

# extract_string_literals(base_sha, head_sha)
# Prints one "file|line|literal" record per quoted string literal appearing
# on an ADDED line in the diff. Only captures literals that look like
# identifier-style keys (alphanumeric + - + _ + .), length 3-40.
extract_string_literals() {
  local base="${1:?extract_string_literals: base_sha required}"
  local head="${2:?extract_string_literals: head_sha required}"
  # diff with line-numbers via --unified=0 + patch parser
  local cur_file=""
  local cur_line=0
  git diff --unified=0 "$base..$head" 2>/dev/null | \
  while IFS= read -r line; do
    # Track file
    if [[ "$line" == "+++ b/"* ]]; then
      cur_file="${line#+++ b/}"
      continue
    fi
    # Track hunk start: @@ -OLD,OCOUNT +NEW,NCOUNT @@
    if [[ "$line" == "@@ "* ]]; then
      local tmp="${line#@@ *+}"
      cur_line="${tmp%%,*}"
      cur_line="${cur_line%% *}"
      continue
    fi
    # Only added lines
    if [[ "$line" == +* && "$line" != "+++"* ]]; then
      # Content of the added line (drop leading +)
      local content="${line#+}"
      # Extract quoted strings via grep -o; match 'single' and "double"
      # -style literals containing only identifier-safe characters.
      while read -r match; do
        [[ -z "$match" ]] && continue
        # Strip quotes; keep only identifier-style
        local raw="${match:1:-1}"
        # Accept only [a-zA-Z0-9_.-], length 3-40
        if [[ "$raw" =~ ^[A-Za-z0-9_.-]{3,40}$ ]]; then
          printf '%s|%s|%s\n' "$cur_file" "$cur_line" "$raw"
        fi
      done < <(printf '%s' "$content" | grep -oE "'[^']*'|\"[^\"]*\"" 2>/dev/null || true)
      cur_line=$((cur_line + 1))
    fi
  done
}

# scan_divergent_constants(base_sha, head_sha)
# Runs extract_string_literals, canonicalizes, groups by canonical form,
# and emits findings as a JSON array. Each finding:
#   { canonical: "google",
#     variants: [{literal:"google", file:"a.ts", line:10},
#                {literal:"google-api-key", file:"b.ts", line:20}],
#     severity: "medium" }
#
# Severity rule: 2 distinct literals mapping to the same canonical across
# 2+ files = "medium". 3+ distinct literals = "high".
scan_divergent_constants() {
  local base="${1:?scan_divergent_constants: base_sha required}"
  local head="${2:?scan_divergent_constants: head_sha required}"

  # Gather raw triples
  local triples
  triples=$(extract_string_literals "$base" "$head" || true)
  if [[ -z "$triples" ]]; then
    printf "[]\n"
    return 0
  fi

  # Build JSON array of {file, line, literal, canonical}
  local input_json='[]'
  while IFS='|' read -r f l lit; do
    [[ -z "$lit" ]] && continue
    local canon
    canon=$(canonicalize "$lit")
    input_json=$(
      jq -c --arg f "$f" --argjson l "$l" --arg lit "$lit" --arg c "$canon" \
        '. + [{file:$f, line:$l, literal:$lit, canonical:$c}]' <<< "$input_json"
    )
  done <<< "$triples"

  # Group by canonical, keep groups whose literals span ≥2 distinct values
  # across ≥2 distinct files.
  printf '%s' "$input_json" | jq -c '
    group_by(.canonical)
    | map({
        canonical: .[0].canonical,
        variants: (map({literal, file, line}) | unique_by([.literal, .file])),
        distinct_literals: (map(.literal) | unique | length),
        distinct_files: (map(.file) | unique | length)
      })
    | map(select(.distinct_literals >= 2 and .distinct_files >= 2))
    | map(. + {severity: (if .distinct_literals >= 3 then "high" else "medium" end)})
    | map({canonical, variants, severity})
  '
}

# has_divergence(base_sha, head_sha)
# Exits 0 if scan_divergent_constants found findings (non-empty array),
# exits 1 otherwise. Suitable as a pipeline gate.
has_divergence() {
  local base="${1:?has_divergence: base_sha required}"
  local head="${2:?has_divergence: head_sha required}"
  local findings
  findings=$(scan_divergent_constants "$base" "$head")
  local n
  n=$(printf '%s' "$findings" | jq 'length')
  [[ "$n" -gt 0 ]]
}

# ------------------------------------------------------------------------------
# CLI entry
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  set -euo pipefail
  subcmd="${1:-}"
  shift || true
  case "$subcmd" in
    canonicalize)        canonicalize "$@"; printf "\n" ;;
    extract)             extract_string_literals "$@" ;;
    scan)                scan_divergent_constants "$@" ;;
    gate)                has_divergence "$@" ;;
    *)
      cat >&2 <<USAGE
Usage: bash lib/wave-boundary.sh <subcmd> [args...]
  canonicalize LITERAL        — echo canonical form
  extract BASE HEAD           — emit file|line|literal triples from diff
  scan BASE HEAD              — emit JSON findings of divergent constants
  gate BASE HEAD              — exit 0 if divergent, 1 if clean
USAGE
      exit 2
      ;;
  esac
fi
