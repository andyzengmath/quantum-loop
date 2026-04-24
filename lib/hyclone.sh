#!/usr/bin/env bash
# lib/hyclone.sh — two-stage semantic clone detection (Phase 25 / P3.7).
#
# Source: HyClone arXiv:2508.01357. Two-stage detection:
#   Stage 1: LLM or canonical-form pre-screen to find CANDIDATE clones
#            (cheap, broad, may have false positives).
#   Stage 2: Execution validation — run both candidates against shared
#            inputs, compare outputs to confirm semantic equivalence.
#
# This library ships Stage 1 — the canonical-form fingerprint. Stage 2
# (execution validation) is inherently language-specific and is delegated
# to the duplication-detector agent, which can invoke the fingerprint
# checker from here, then call project-specific test harnesses for the
# actual equivalence check.
#
# Functions:
#   alpha_normalize TEXT
#     Canonicalize a snippet: strip comments, collapse whitespace, rename
#     identifiers to sequential placeholders (_v0, _v1, …) in order of
#     first appearance. Two snippets that differ only in variable names
#     and formatting produce identical normalized output.
#   fingerprint TEXT
#     sha256 of alpha_normalize(TEXT). Stable across whitespace + naming
#     differences.
#   find_clones JSON_ARRAY
#     Input JSON: [{id, body}, ...]. Emits JSON of clone-pair groups:
#     [{fingerprint, members: [id, id, …]}, …] where each group has ≥2
#     members (i.e., only genuine clone candidates are returned).
#
# Language-agnostic by design. Alpha-renaming is regex-based, so it works
# best on languages where identifiers look like [A-Za-z_][A-Za-z0-9_]*
# (TypeScript, JavaScript, Python, Go, Rust, Java, C). Languages with
# distinct identifier grammars (Lisp :keyword, Perl @array) should pre-
# process before calling fingerprint.
#
# Library contract: no shell flags at source time; CLI-entry block enables
# strict mode locally.

HYCLONE_LIB_DIR="${HYCLONE_LIB_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)}"

# Reserved keyword list — tokens that MUST NOT be renamed, else alpha-
# normalization would change semantics. Covers TS/JS/Py/Go/Rust/Java/C
# common intersection. If a reserved keyword overlaps with a local name
# in some language, false positives are acceptable — clones are still
# flagged; just with slightly lower recall.
if [[ -z "${HYCLONE_KEYWORDS+x}" ]]; then
readonly -a HYCLONE_KEYWORDS=(
  # Control flow
  if then else elif fi for while do done case esac switch break continue return yield
  # Declarations
  let const var function func def class interface struct enum type trait impl pub
  # Booleans / special values
  true false null undefined None True False nil
  # Operators / keywords
  and or not in is new delete throw throws try catch finally as of from import export default
  # Type-ish
  string number boolean int float double char void bool
  # Async
  async await asyncio Promise
  # Access
  public private protected readonly static final abstract
  # Test-ish
  describe it test expect assert
)
fi

# _is_keyword(token)
# Return 0 if token is in HYCLONE_KEYWORDS, 1 otherwise.
_is_keyword() {
  local t="${1:-}"
  local kw
  for kw in "${HYCLONE_KEYWORDS[@]}"; do
    [[ "$t" == "$kw" ]] && return 0
  done
  return 1
}

# alpha_normalize(text)
# Emits the canonical form on stdout:
#   1. Remove line comments (# ... or // ... to end of line)
#   2. Remove block comments (/* ... */) — non-greedy
#   3. Collapse runs of whitespace to a single space
#   4. Rename identifiers to _v0, _v1, … in order of first appearance
#      (keywords are untouched)
#   5. Trim leading/trailing whitespace
#
# Input may be any length. Uses awk for the tokenize-and-rename pass so
# the whole function stays portable (no python dependency for alphabet).
alpha_normalize() {
  local text="${1:-}"
  [[ -z "$text" ]] && { printf ""; return 0; }
  # Step 1-2: strip comments with string-state tracking so `//`, `/*`, or
  # `#` inside a string literal (e.g. "http://x", "/regex/") is preserved.
  # Without string tracking the naive stripper truncates URLs/regexes/paths.
  local stripped
  stripped=$(printf '%s' "$text" | awk '
    BEGIN { in_block = 0 }
    {
      line = $0
      out = ""
      i = 1
      in_string = ""
      while (i <= length(line)) {
        c  = substr(line, i, 1)
        c2 = substr(line, i, 2)
        if (in_string != "") {
          # Inside a string — copy through; handle backslash escape
          out = out c
          if (c == "\\" && i + 1 <= length(line)) {
            out = out substr(line, i+1, 1)
            i += 2
          } else if (c == in_string) {
            in_string = ""
            i += 1
          } else {
            i += 1
          }
        } else if (in_block) {
          if (c2 == "*/") { in_block = 0; i += 2 } else { i += 1 }
        } else if (c == "\"" || c == "'\''") {
          in_string = c
          out = out c
          i += 1
        } else if (c2 == "/*") {
          in_block = 1; i += 2
        } else if (c2 == "//" || c == "#") {
          break  # line comment — skip rest of line
        } else {
          out = out c
          i += 1
        }
      }
      print out
    }
  ')

  # Step 3: collapse whitespace
  stripped=$(printf '%s' "$stripped" | tr -s '[:space:]' ' ')

  # Step 4: tokenize + alpha-rename. Build the keyword set on the awk side
  # so we don't have to roundtrip to shell. Identifiers: [A-Za-z_][A-Za-z0-9_]*
  # Strings ("..." / '...') are preserved verbatim (they're not identifiers).
  local keyword_list="${HYCLONE_KEYWORDS[*]}"
  printf '%s' "$stripped" | awk -v kws="$keyword_list" '
    BEGIN {
      n = split(kws, kwlist, " ")
      for (i = 1; i <= n; i++) kwset[kwlist[i]] = 1
      next_id = 0
    }
    {
      out = ""
      s = $0
      while (length(s) > 0) {
        c = substr(s, 1, 1)
        # String literals — copy through unchanged
        if (c == "\"" || c == "'\''") {
          quote = c
          out = out quote
          s = substr(s, 2)
          while (length(s) > 0) {
            c = substr(s, 1, 1)
            out = out c
            if (c == "\\") {
              out = out substr(s, 2, 1)
              s = substr(s, 3)
            } else if (c == quote) {
              s = substr(s, 2)
              break
            } else {
              s = substr(s, 2)
            }
          }
          continue
        }
        # Identifier
        if (match(s, /^[A-Za-z_][A-Za-z0-9_]*/)) {
          tok = substr(s, 1, RLENGTH)
          s = substr(s, RLENGTH + 1)
          if (tok in kwset) {
            out = out tok
          } else {
            if (!(tok in idmap)) {
              idmap[tok] = "_v" next_id
              next_id++
            }
            out = out idmap[tok]
          }
          continue
        }
        # Number literal — copy through
        if (match(s, /^[0-9]+(\.[0-9]+)?/)) {
          out = out substr(s, 1, RLENGTH)
          s = substr(s, RLENGTH + 1)
          continue
        }
        # Any other character (punctuation, operator) — copy single char
        out = out c
        s = substr(s, 2)
      }
      # Trim leading/trailing
      gsub(/^ +| +$/, "", out)
      # Aggressive: drop spaces adjacent to non-alphanumeric tokens so
      # formatting differences (e.g., `fn(a, b)` vs `fn(a,b)`) collide
      # into the same fingerprint. This loses readability but is what
      # HyClone Stage-1 wants — maximum recall across styles.
      # Keep single space between two identifier-tail/head chars to
      # preserve token boundaries (e.g., `return _v0` must stay as two
      # tokens, not `return_v0`).
      prev = ""
      out2 = ""
      for (j = 1; j <= length(out); j++) {
        c  = substr(out, j, 1)
        if (c == " ") {
          nxt = substr(out, j + 1, 1)
          # Keep the space only if BOTH prev and nxt are word-chars
          # ([A-Za-z0-9_]); otherwise drop it.
          if (prev ~ /[A-Za-z0-9_]/ && nxt ~ /[A-Za-z0-9_]/) {
            out2 = out2 c
            prev = c
          }
        } else {
          out2 = out2 c
          prev = c
        }
      }
      print out2
    }
  '
}

# fingerprint(text)
# sha256 of alpha_normalize(text). 64-char lowercase hex.
fingerprint() {
  local text="${1:-}"
  local norm
  norm=$(alpha_normalize "$text")
  printf '%s' "$norm" | sha256sum | awk '{print $1}'
}

# find_clones(json_array)
# Input JSON: [{id, body}, ...]. Computes fingerprint(body) for each
# entry, groups by fingerprint, emits the groups with ≥2 members.
# Output: [{fingerprint, members: [id, id, ...]}, ...]
find_clones() {
  local input="${1:-}"
  [[ -z "$input" ]] && input=$(cat)
  local tmp
  tmp=$(mktemp)
  # Build lines of "fingerprint<TAB>id"
  local n
  n=$(printf '%s' "$input" | jq 'length')
  local i=0
  while (( i < n )); do
    local id body fp
    id=$(printf '%s' "$input" | jq -r ".[$i].id")
    body=$(printf '%s' "$input" | jq -r ".[$i].body")
    fp=$(fingerprint "$body")
    printf '%s\t%s\n' "$fp" "$id" >> "$tmp"
    i=$((i + 1))
  done
  # Group by fingerprint, retain only groups with ≥2 entries
  local out='[]'
  while IFS= read -r fp; do
    [[ -z "$fp" ]] && continue
    local members
    members=$(awk -F '\t' -v fp="$fp" '$1 == fp {print $2}' "$tmp" \
      | jq -R . | jq -s .)
    local count
    count=$(printf '%s' "$members" | jq 'length')
    (( count >= 2 )) || continue
    out=$(jq -c --arg fp "$fp" --argjson m "$members" \
      '. + [{fingerprint: $fp, members: $m}]' <<< "$out")
  done < <(awk -F '\t' '{print $1}' "$tmp" | sort -u)
  rm -f "$tmp"
  printf '%s' "$out"
}

# ------------------------------------------------------------------------------
# CLI entry
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  set -euo pipefail
  subcmd="${1:-}"
  shift || true
  case "$subcmd" in
    normalize)   alpha_normalize "$@"; printf "\n" ;;
    fingerprint) fingerprint "$@"; printf "\n" ;;
    clones)      find_clones "$@" ;;
    *)
      cat >&2 <<USAGE
Usage: bash lib/hyclone.sh <subcmd> [args...]
  normalize TEXT                    — canonical form
  fingerprint TEXT                  — sha256 of canonical form
  clones [JSON]                     — find clone groups; reads stdin if no arg
USAGE
      exit 2
      ;;
  esac
fi
