#!/usr/bin/env bash
# lib/type-audit.sh -- Type audit functions for quantum-loop
# Source this file to use grep_duplicate_definitions() and future audit utilities.

# Source shared utilities
TYPE_AUDIT_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$TYPE_AUDIT_LIB_DIR/common.sh" || { printf "ERROR: common.sh not found\n" >&2; return 1 2>/dev/null || exit 1; }
source "$TYPE_AUDIT_LIB_DIR/materialize.sh" || { printf "ERROR: materialize.sh not found\n" >&2; return 1 2>/dev/null || exit 1; }

# grep_duplicate_definitions(repo_root, changed_files_list)
# Scans only the provided files for type definitions using language-specific patterns.
# Groups definitions by name and returns JSON array of duplicates (2+ files).
# Only flags names defined in 2+ DIFFERENT files (cross-file duplicates).
#
# Arguments:
#   repo_root           - Path to the repository root (used for language detection)
#   changed_files_list  - Space-separated list of file paths to scan
#
# Output: JSON array on stdout, e.g. [{"name":"Foo","files":["a.ts","b.ts"]}]
#         Empty array [] when no duplicates found.
# Returns: 0 always
grep_duplicate_definitions() {
  local repo_root="$1"
  local changed_files_list="$2"

  # Early return for empty inputs
  if [[ -z "$repo_root" || -z "$changed_files_list" ]]; then
    printf '[]'
    return 0
  fi

  local language
  language=$(detect_language "$repo_root")

  # Build language-specific grep patterns
  local ts_pattern='export[[:space:]]+(interface|type|class)[[:space:]]+([A-Za-z_][A-Za-z0-9_]*)'
  local py_pattern='class[[:space:]]+([A-Za-z_][A-Za-z0-9_]*)\((Protocol|BaseModel)\)'
  local go_pattern='type[[:space:]]+([A-Za-z_][A-Za-z0-9_]*)[[:space:]]+(interface|struct)'

  # Temporary file for collecting {name, file} pairs (tab-separated)
  local tmp_pairs
  tmp_pairs=$(mktemp)

  # Scan each file in the changed files list
  local file
  for file in $changed_files_list; do
    if [[ ! -f "$file" ]]; then
      continue
    fi

    local ext="${file##*.}"
    local pattern=""

    # Select pattern based on file extension (primary) or detected language (fallback)
    case "$ext" in
      ts|tsx)
        pattern="$ts_pattern"
        ;;
      py)
        pattern="$py_pattern"
        ;;
      go)
        pattern="$go_pattern"
        ;;
      *)
        # Fallback to detected language
        case "$language" in
          typescript) pattern="$ts_pattern" ;;
          python)     pattern="$py_pattern" ;;
          go)         pattern="$go_pattern" ;;
          *)          continue ;;
        esac
        ;;
    esac

    # Grep for type definitions in this file and extract type names
    local matches
    matches=$(grep -E "$pattern" "$file" 2>/dev/null || true)

    if [[ -n "$matches" ]]; then
      while IFS= read -r line; do
        local type_name=""

        case "$ext" in
          ts|tsx)
            type_name=$(printf '%s' "$line" | sed -E "s/.*export[[:space:]]+(interface|type|class)[[:space:]]+([A-Za-z_][A-Za-z0-9_]*).*/\2/")
            ;;
          py)
            type_name=$(printf '%s' "$line" | sed -E "s/.*class[[:space:]]+([A-Za-z_][A-Za-z0-9_]*)\((Protocol|BaseModel)\).*/\1/")
            ;;
          go)
            type_name=$(printf '%s' "$line" | sed -E "s/.*type[[:space:]]+([A-Za-z_][A-Za-z0-9_]*)[[:space:]]+(interface|struct).*/\1/")
            ;;
          *)
            case "$language" in
              typescript)
                type_name=$(printf '%s' "$line" | sed -E "s/.*export[[:space:]]+(interface|type|class)[[:space:]]+([A-Za-z_][A-Za-z0-9_]*).*/\2/")
                ;;
              python)
                type_name=$(printf '%s' "$line" | sed -E "s/.*class[[:space:]]+([A-Za-z_][A-Za-z0-9_]*)\((Protocol|BaseModel)\).*/\1/")
                ;;
              go)
                type_name=$(printf '%s' "$line" | sed -E "s/.*type[[:space:]]+([A-Za-z_][A-Za-z0-9_]*)[[:space:]]+(interface|struct).*/\1/")
                ;;
            esac
            ;;
        esac

        if [[ -n "$type_name" ]]; then
          printf '%s\t%s\n' "$type_name" "$file" >> "$tmp_pairs"
        fi
      done <<< "$matches"
    fi
  done

  # If no definitions found at all, return empty array
  if [[ ! -s "$tmp_pairs" ]]; then
    rm -f "$tmp_pairs"
    printf '[]'
    return 0
  fi

  # Use jq to build JSON from the pairs file.
  # First deduplicate (name, file) pairs, then group by name and filter to 2+ files.
  local json_result
  json_result=$(sort -u "$tmp_pairs" | jq -R -s '
    # Split into lines, filter empty
    split("\n") | map(select(length > 0)) |
    # Split each line by tab into {name, file}
    map(split("\t") | {name: .[0], file: .[1]}) |
    # Group by name
    group_by(.name) |
    # Keep groups where files come from 2+ distinct files
    map({
      name: .[0].name,
      files: [.[] | .file] | unique
    }) |
    map(select(.files | length >= 2))
  ')

  rm -f "$tmp_pairs"

  printf '%s' "$json_result"
  return 0
}
