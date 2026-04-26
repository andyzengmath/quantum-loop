#!/usr/bin/env bash
# lib/api-rename.sh — symbol-migration helpers (US-005 / G2 / v0.6.3).
#
# Addresses the v0.6.0 US-001 dogfood pattern where a line-4 module-header
# doc-comment was missed during a rename. These helpers scan BOTH code call
# sites AND comments/string-literals so renames can be validated as fully
# applied.
#
# Functions:
#   find_rename_targets(old_symbol, new_symbol, scope_glob, [--exclude <glob>])
#     - Emits one line per occurrence: <file>:<line>:<context>
#     - Matches both code references AND comments/string-literals containing
#       the symbol (grep -nE with word boundaries to avoid substring
#       matches like 'foo_helper2').
#
#   validate_rename_complete(old_symbol, scope_glob, [--exclude <glob>])
#     - Exits 0 if no occurrences remain after exclude filtering.
#     - Exits 1 with the file:line list on stderr otherwise.
#
# Both functions accept --exclude <glob> (comma-separated) to skip historical
# paths (e.g., --exclude CHANGELOG.md,docs/post-mortems/**).
#
# Library contract: no shell flags at source time; safe to source from
# tests, hooks, or interactive shells.

# _api_rename_parse_args ARGS...
# Splits args into positional + --exclude pattern, in-process (no subshell).
# Sets globals:
#   _API_RENAME_POSITIONAL   — array of non-flag args
#   _API_RENAME_EXCLUDE      — comma-separated exclude glob (or empty)
_api_rename_parse_args() {
  _API_RENAME_POSITIONAL=()
  _API_RENAME_EXCLUDE=""
  local skip_next=0
  for arg in "$@"; do
    if (( skip_next )); then
      _API_RENAME_EXCLUDE="$arg"
      skip_next=0
      continue
    fi
    case "$arg" in
      --exclude)
        skip_next=1
        ;;
      --exclude=*)
        _API_RENAME_EXCLUDE="${arg#--exclude=}"
        ;;
      *)
        _API_RENAME_POSITIONAL+=("$arg")
        ;;
    esac
  done
}

# find_rename_targets(old_symbol, new_symbol, scope_glob, [--exclude <pat>])
# Emits "file:line:context" for each occurrence of old_symbol in files
# matching scope_glob, optionally filtered through --exclude.
find_rename_targets() {
  _api_rename_parse_args "$@"
  local -a positional=("${_API_RENAME_POSITIONAL[@]}")
  local EXCLUDE_PATTERN="$_API_RENAME_EXCLUDE"

  if (( ${#positional[@]} < 3 )); then
    printf "ERROR: find_rename_targets needs old_symbol, new_symbol, scope_glob\n" >&2
    return 2
  fi

  local old_sym="${positional[0]}"
  local new_sym="${positional[1]}"
  local scope_glob="${positional[2]}"

  # Use grep with word-boundary regex (\b) so we don't match substrings.
  # -n: line numbers; -E: extended regex; -H: include filename even when 1 file.
  # Use shell glob expansion for scope_glob.
  shopt -s nullglob
  local -a files=( $scope_glob )
  shopt -u nullglob

  local out=""
  for f in "${files[@]}"; do
    [[ -f "$f" ]] || continue
    # Apply exclude filter
    if [[ -n "$EXCLUDE_PATTERN" ]]; then
      local skip=0
      local IFS_OLD="$IFS"
      IFS=','
      for ex in $EXCLUDE_PATTERN; do
        IFS="$IFS_OLD"
        # Strip whitespace
        ex="${ex# }"
        ex="${ex% }"
        # Match against the file path's basename or full path.
        if [[ "$f" == *"$ex"* ]] || [[ "$(basename "$f")" == $ex ]]; then
          skip=1
          break
        fi
      done
      IFS="$IFS_OLD"
      (( skip )) && continue
    fi

    # Use grep -nE with \b for word boundary match.
    while IFS= read -r match; do
      [[ -z "$match" ]] && continue
      out+="$f:$match"$'\n'
    done < <(grep -nE "\b${old_sym}\b" "$f" 2>/dev/null || true)
  done

  # Suppress trailing blank line; printf with %s avoids extra newline.
  if [[ -n "$out" ]]; then
    printf '%s' "$out"
  fi

  # Suppress unused-variable warning
  : "$new_sym"
}

# validate_rename_complete(old_symbol, scope_glob, [--exclude <pat>])
# Returns 0 if no occurrences remain (rename complete), 1 otherwise.
# On non-zero, prints the offending lines to stderr.
validate_rename_complete() {
  _api_rename_parse_args "$@"
  local -a positional=("${_API_RENAME_POSITIONAL[@]}")
  local EXCLUDE_PATTERN="$_API_RENAME_EXCLUDE"

  if (( ${#positional[@]} < 2 )); then
    printf "ERROR: validate_rename_complete needs old_symbol, scope_glob\n" >&2
    return 2
  fi

  local old_sym="${positional[0]}"
  local scope_glob="${positional[1]}"

  # Re-use find_rename_targets with a stub new_symbol (it doesn't apply renames).
  local results
  if [[ -n "$EXCLUDE_PATTERN" ]]; then
    results=$(find_rename_targets "$old_sym" "_unused" "$scope_glob" --exclude "$EXCLUDE_PATTERN" 2>/dev/null || true)
  else
    results=$(find_rename_targets "$old_sym" "_unused" "$scope_glob" 2>/dev/null || true)
  fi

  if [[ -z "$results" ]]; then
    return 0
  fi
  printf "%s\n" "$results" >&2
  return 1
}
