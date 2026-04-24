#!/usr/bin/env bash
# lib/conflict-grade.sh — merge-conflict severity grading (Phase 26 / P3.2).
#
# Source: ConGra (arXiv:2409.14121) — grade each conflict hunk by
# operation complexity before routing resolution. Cheap grades can be
# auto-merged by git; expensive grades need LLM assistance; structural
# grades escalate to operator.
#
# Grade scale:
#   1  whitespace / formatting only
#   2  single-token rename or comment-only change
#   3  small body edit (≤5 lines each side)
#   4  moderate overlap (>5 lines each side, within one function)
#   5  structural reorganization (spans multiple function/class boundaries)
#
# Complements lib/merge-strategy.sh (classify_and_merge) which routes by
# FILE KIND (dependency_manifest, barrel_export, etc). ConGra routes by
# CONFLICT SHAPE within a file.
#
# Functions:
#   split_conflict_hunks FILE
#     Emits one JSON object per conflict marker block:
#       {start_line, end_line, ours, theirs}
#   grade_hunk_text OURS THEIRS
#     Returns an integer 1-5 for a single hunk.
#   grade_file FILE
#     Emits JSON: {max_grade, hunks: [{start_line, end_line, grade}, ...]}
#   routing_recommendation GRADE
#     Echoes one of: auto-git | diff3 | llm-merge | escalate
#
# Library contract: no shell flags at source time; CLI block enables
# strict mode locally.

CONFLICT_GRADE_LIB_DIR="${CONFLICT_GRADE_LIB_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)}"

# _count_nonempty_lines(text)
# Count lines that contain at least one non-whitespace character.
_count_nonempty_lines() {
  local text="${1:-}"
  [[ -z "$text" ]] && { printf "0"; return; }
  printf '%s' "$text" | awk 'NF > 0 { c++ } END { print c+0 }'
}

# _strip_ws(text)
# Strip ALL whitespace. Used to detect whitespace-only differences
# (Grade 1). Two snippets comparing equal after this strip differ only in
# indentation / newline / spacing.
#
# Known edge case: `return x` vs `returnx` both strip to `returnx`. In
# practice this happens in hand-crafted adversarial inputs, not in real
# merge conflicts — accepted as a narrow false-positive for Grade 1.
_strip_ws() {
  local text="${1:-}"
  printf '%s' "$text" | tr -d '[:space:]'
}

# _strip_comments(text)
# Remove line comments (# and //) and block comments (/* ... */) for
# grade-2 detection (comment-only change). String literals are preserved
# verbatim so `//` or `/*` inside "http://x" or "/regex/" is not treated
# as a comment marker.
_strip_comments() {
  local text="${1:-}"
  printf '%s' "$text" | awk '
    BEGIN { in_block = 0 }
    {
      line = $0
      out = ""
      i = 1
      in_string = ""
      while (i <= length(line)) {
        c2 = substr(line, i, 2)
        c  = substr(line, i, 1)
        if (in_string != "") {
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
          break
        } else {
          out = out c
          i += 1
        }
      }
      print out
    }
  '
}

# _function_boundary_count(text)
# Count function/class/method definition starts in the text. Heuristic for
# grade-5 detection (structural reorganization). Patterns cover TS/JS/Py/
# Go/Rust/Java/C.
_function_boundary_count() {
  local text="${1:-}"
  [[ -z "$text" ]] && { printf "0"; return; }
  # grep -c ALWAYS prints a count to stdout (including "0"), so don't
  # add a `|| echo 0` fallback — that would yield "0\n0" on no-match
  # and break the numeric comparison in the caller.
  { printf '%s' "$text" | grep -cE '^\s*(function |def |class |interface |struct |func |pub fn |impl |module )' ; } || true
}

# split_conflict_hunks(file)
# Parses a file with conflict markers; for each hunk emits a JSON object:
#   {start_line, end_line, ours, theirs}
# Returns a JSON array of such objects.
split_conflict_hunks() {
  local file="${1:?file required}"
  [[ -f "$file" ]] || { printf "[]"; return 0; }

  local out='[]'
  local in_conflict=0
  local in_theirs=0
  local start_line=0
  local line_no=0
  local ours_buf=""
  local theirs_buf=""

  while IFS= read -r line || [[ -n "$line" ]]; do
    line_no=$((line_no + 1))
    case "$line" in
      "<<<<<<<"*)
        in_conflict=1; in_theirs=0
        start_line=$line_no
        ours_buf=""
        theirs_buf=""
        ;;
      "======="*)
        in_theirs=1
        ;;
      ">>>>>>>"*)
        # Emit the hunk
        out=$(jq -c \
          --argjson s "$start_line" --argjson e "$line_no" \
          --arg ours "$ours_buf" --arg theirs "$theirs_buf" \
          '. + [{start_line: $s, end_line: $e, ours: $ours, theirs: $theirs}]' \
          <<< "$out")
        in_conflict=0; in_theirs=0
        ;;
      *)
        if (( in_conflict )); then
          if (( in_theirs )); then
            theirs_buf+="${line}"$'\n'
          else
            ours_buf+="${line}"$'\n'
          fi
        fi
        ;;
    esac
  done < "$file"

  printf '%s' "$out"
}

# grade_hunk_text(ours_text, theirs_text)
# Returns 1-5 integer grade for a single hunk.
grade_hunk_text() {
  local ours="${1:-}"
  local theirs="${2:-}"

  # Grade 1: whitespace only
  local ours_ws theirs_ws
  ours_ws=$(_strip_ws "$ours")
  theirs_ws=$(_strip_ws "$theirs")
  if [[ "$ours_ws" == "$theirs_ws" ]]; then
    printf "1"; return 0
  fi

  # Grade 2: comment-only or single-token rename
  local ours_nc theirs_nc
  ours_nc=$(_strip_comments "$ours" | tr -s '[:space:]' ' ' | sed 's/^ //; s/ $//')
  theirs_nc=$(_strip_comments "$theirs" | tr -s '[:space:]' ' ' | sed 's/^ //; s/ $//')
  if [[ "$ours_nc" == "$theirs_nc" ]]; then
    # Code identical once comments stripped
    printf "2"; return 0
  fi
  # Single-token diff check: if both sides have same word count AND differ
  # in exactly one word at the same position, it's a rename.
  local ours_words theirs_words ours_n theirs_n
  ours_words=$(printf '%s' "$ours_nc" | tr -s ' ' '\n' | grep -v '^$')
  theirs_words=$(printf '%s' "$theirs_nc" | tr -s ' ' '\n' | grep -v '^$')
  ours_n=$(printf '%s\n' "$ours_words" | wc -l)
  theirs_n=$(printf '%s\n' "$theirs_words" | wc -l)
  # Sanitize wc output (leading/trailing whitespace)
  ours_n=$(echo "$ours_n" | tr -d '[:space:]')
  theirs_n=$(echo "$theirs_n" | tr -d '[:space:]')
  [[ -z "$ours_n" ]]   && ours_n=0
  [[ -z "$theirs_n" ]] && theirs_n=0
  if [[ "$ours_n" -eq "$theirs_n" && "$ours_n" -gt 0 ]]; then
    local diff_count
    # grep -c always prints a count (including "0") — no `|| echo 0` needed
    diff_count=$({ diff <(printf '%s' "$ours_words") <(printf '%s' "$theirs_words") 2>/dev/null | grep -cE '^[<>]' ; } || true)
    diff_count=$(echo "$diff_count" | tr -d '[:space:]')
    [[ -z "$diff_count" ]] && diff_count=0
    # Each differing word shows as `<` once and `>` once, so total 2 for one rename.
    if (( diff_count <= 2 )); then
      printf "2"; return 0
    fi
  fi

  # Grade 5: structural reorganization (spans multiple function boundaries)
  local ours_funcs theirs_funcs
  ours_funcs=$(_function_boundary_count "$ours" | tr -d '[:space:]')
  theirs_funcs=$(_function_boundary_count "$theirs" | tr -d '[:space:]')
  [[ -z "$ours_funcs" ]]   && ours_funcs=0
  [[ -z "$theirs_funcs" ]] && theirs_funcs=0
  if (( ours_funcs >= 2 || theirs_funcs >= 2 )); then
    printf "5"; return 0
  fi

  # Grade 3 vs 4: by line count of meaningful changes
  local ours_lines theirs_lines
  ours_lines=$(_count_nonempty_lines "$ours")
  theirs_lines=$(_count_nonempty_lines "$theirs")
  local max_lines=$ours_lines
  (( theirs_lines > max_lines )) && max_lines=$theirs_lines
  if (( max_lines <= 5 )); then
    printf "3"; return 0
  fi
  printf "4"
}

# grade_file(file)
# Emits JSON:
#   {max_grade, hunks: [{start_line, end_line, grade}, ...]}
# Empty hunks array if file has no conflicts.
grade_file() {
  local file="${1:?file required}"
  local hunks
  hunks=$(split_conflict_hunks "$file")
  local n
  n=$(printf '%s' "$hunks" | jq 'length')
  if (( n == 0 )); then
    printf '{"max_grade":0,"hunks":[]}'
    return 0
  fi

  local i=0
  local out='[]'
  local max_g=0
  while (( i < n )); do
    local h ours theirs grade s e
    h=$(printf '%s' "$hunks" | jq -c ".[$i]")
    ours=$(printf '%s' "$h" | jq -r '.ours')
    theirs=$(printf '%s' "$h" | jq -r '.theirs')
    s=$(printf '%s' "$h" | jq -r '.start_line')
    e=$(printf '%s' "$h" | jq -r '.end_line')
    grade=$(grade_hunk_text "$ours" "$theirs")
    (( grade > max_g )) && max_g=$grade
    out=$(jq -c \
      --argjson s "$s" --argjson e "$e" --argjson g "$grade" \
      '. + [{start_line: $s, end_line: $e, grade: $g}]' \
      <<< "$out")
    i=$((i + 1))
  done
  jq -cn --argjson m "$max_g" --argjson hunks "$out" \
    '{max_grade: $m, hunks: $hunks}'
}

# routing_recommendation(grade)
# Given a grade (1-5 or 0), echo the recommended resolution path:
#   0  — no conflict (nothing to route)
#   1  — auto-git (git merge -X ours|theirs by policy)
#   2  — auto-git
#   3  — diff3 (3-way textual merge)
#   4  — llm-merge (semantic/AST-aware via lib/merge-semantic.sh)
#   5  — escalate (operator intervention)
routing_recommendation() {
  local grade="${1:?grade required}"
  case "$grade" in
    0)   printf "none" ;;
    1|2) printf "auto-git" ;;
    3)   printf "diff3" ;;
    4)   printf "llm-merge" ;;
    5)   printf "escalate" ;;
    *)   printf "unknown" ;;
  esac
}

# ------------------------------------------------------------------------------
# CLI entry
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  set -euo pipefail
  subcmd="${1:-}"
  shift || true
  case "$subcmd" in
    split)   split_conflict_hunks "$@" ;;
    grade)   grade_file "$@" ;;
    grade-hunk)
      # grade-hunk OURS_FILE THEIRS_FILE
      _ours=$(cat "${1:?ours file}")
      _theirs=$(cat "${2:?theirs file}")
      grade_hunk_text "$_ours" "$_theirs"; printf "\n"
      ;;
    route)   routing_recommendation "$@"; printf "\n" ;;
    *)
      cat >&2 <<USAGE
Usage: bash lib/conflict-grade.sh <subcmd> [args...]
  split FILE                          — emit JSON array of hunks
  grade FILE                          — grade every conflict in FILE
  grade-hunk OURS_FILE THEIRS_FILE    — grade a single pre-split hunk
  route GRADE                         — recommend auto-git|diff3|llm-merge|escalate
USAGE
      exit 2
      ;;
  esac
fi
