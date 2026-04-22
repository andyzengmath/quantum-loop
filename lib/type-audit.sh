#!/usr/bin/env bash
# lib/type-audit.sh -- Type audit functions for quantum-loop
# Source this file to use grep_duplicate_definitions() and future audit utilities.

# Source shared utilities
TYPE_AUDIT_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$TYPE_AUDIT_LIB_DIR/common.sh" || { printf "ERROR: common.sh not found\n" >&2; return 1 2>/dev/null || exit 1; }
source "$TYPE_AUDIT_LIB_DIR/json-atomic.sh" || { printf "ERROR: json-atomic.sh not found\n" >&2; return 1 2>/dev/null || exit 1; }
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

    # Additional pass for Python @dataclass decorated classes
    if [[ "$ext" == "py" ]] || { [[ "$ext" != "ts" && "$ext" != "tsx" && "$ext" != "go" ]] && [[ "$language" == "python" ]]; }; then
      local dataclass_names
      dataclass_names=$(grep -A1 '@dataclass' "$file" 2>/dev/null | grep -oE 'class[[:space:]]+[A-Za-z_][A-Za-z0-9_]*' | sed 's/class[[:space:]]*//' || true)
      if [[ -n "$dataclass_names" ]]; then
        while IFS= read -r dc_name; do
          if [[ -n "$dc_name" ]]; then
            printf '%s\t%s\n' "$dc_name" "$file" >> "$tmp_pairs"
          fi
        done <<< "$dataclass_names"
      fi
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

# audit_wave_types(json_path, repo_root, wave_num, base_sha)
# Audits type definitions changed in the current wave for duplicates.
# Collects changed files via git diff, calls grep_duplicate_definitions().
# If no duplicates: logs [AUDIT] skip message, returns 0.
# If duplicates: logs each duplicate, checks for contract shapes in quantum.json,
# builds type-auditor prompt and outputs it to stdout. Returns duplicate count.
#
# Arguments:
#   json_path   - Path to quantum.json
#   repo_root   - Path to the repository root
#   wave_num    - Current wave number
#   base_sha    - Base SHA for git diff (defaults to HEAD~1 if not provided)
#
# Output: type-auditor prompt on stdout (when duplicates found)
# Logs: [AUDIT] messages on stderr
# Returns: 0 if no duplicates, else count of duplicate type names
audit_wave_types() {
  local json_path="$1"
  local repo_root="$2"
  local wave_num="$3"
  # Base SHA for git diff; defaults to HEAD~1 if not provided
  local base_sha="${4:-HEAD~1}"

  # Validate inputs
  if [[ -z "$json_path" || -z "$repo_root" ]]; then
    printf '[AUDIT] Skipping audit: missing json_path or repo_root\n' >&2
    return 0
  fi

  if [[ ! -d "$repo_root" ]]; then
    printf '[AUDIT] Skipping audit: repo_root is not a directory: %s\n' "$repo_root" >&2
    return 0
  fi

  # Default wave_num to 1
  wave_num="${wave_num:-1}"

  # Collect changed files via git diff
  # Compare HEAD against HEAD~1 to find files changed in the most recent commit(s)
  local changed_files
  changed_files=$(cd "$repo_root" && git diff --name-only "$base_sha" HEAD 2>/dev/null | while IFS= read -r f; do
    printf '%s/%s ' "$repo_root" "$f"
  done)

  # If no changed files, skip
  if [[ -z "$changed_files" ]]; then
    printf '[AUDIT] Grep found 0 duplicate type definitions. Skipping agent audit.\n' >&2
    return 0
  fi

  # Call grep_duplicate_definitions
  local duplicates_json
  duplicates_json=$(grep_duplicate_definitions "$repo_root" "$changed_files")

  # Count duplicates
  local dup_count
  dup_count=$(printf '%s' "$duplicates_json" | jq 'length')

  if [[ "$dup_count" -eq 0 ]]; then
    printf '[AUDIT] Grep found 0 duplicate type definitions. Skipping agent audit.\n' >&2
    return 0
  fi

  # Log each duplicate
  printf '[AUDIT] Found %d duplicate type definition(s) in wave %s:\n' "$dup_count" "$wave_num" >&2
  printf '%s' "$duplicates_json" | jq -r '.[] | "  [AUDIT] \(.name) defined in: \(.files | join(", "))"' >&2

  # Check for contract shapes in quantum.json
  local contracts_json=""
  if [[ -f "$json_path" ]]; then
    contracts_json=$(jq -r '.contracts // {}' "$json_path" 2>/dev/null || printf '{}')
  fi

  # Build type-auditor prompt for each duplicate
  local prompt=""
  local i=0
  while IFS= read -r dup_entry; do
    local type_name
    type_name=$(printf '%s' "$dup_entry" | jq -r '.name')
    local file_paths
    file_paths=$(printf '%s' "$dup_entry" | jq -c '.files')

    # Check if contract shape exists for this type
    local contract_shape=""
    if [[ -n "$contracts_json" && "$contracts_json" != "{}" ]]; then
      contract_shape=$(printf '%s' "$contracts_json" | jq -c --arg tn "$type_name" '
        (.shared_types[$tn] // null)
      ' 2>/dev/null || printf 'null')
    fi

    # Build prompt section for this duplicate
    prompt="${prompt}--- Duplicate Type #$((i + 1)) ---
TYPE_NAME: ${type_name}
FILE_PATHS: ${file_paths}
WAVE: ${wave_num}
"

    if [[ -n "$contract_shape" && "$contract_shape" != "null" ]]; then
      prompt="${prompt}CONTRACTS: ${contract_shape}
"
    fi

    prompt="${prompt}
"
    i=$((i + 1))
  done < <(printf '%s' "$duplicates_json" | jq -c '.[]')

  # Output the complete prompt to stdout
  printf 'type-auditor prompt for wave %s:\n%s' "$wave_num" "$prompt"

  return "$dup_count"
}

# update_contracts_for_next_wave(json_path, type_name, source_files, consolidated_file, wave_num)
# Writes a discovered contract entry to execution.discoveredContracts in quantum.json.
# Initializes execution.discoveredContracts if absent.
# Uses atomic jq write pattern (temp file + mv).
#
# Arguments:
#   json_path         - Path to quantum.json
#   type_name         - Name of the discovered type (e.g., "UserConfig")
#   source_files      - Space-separated list of source file paths
#   consolidated_file - Path to the consolidated definition file
#   wave_num          - Wave number where the type was discovered
#
# Returns: 0 on success, 1 on failure
update_contracts_for_next_wave() {
  local json_path="$1"
  local type_name="$2"
  local source_files="$3"
  local consolidated_file="$4"
  local wave_num="$5"

  # Validate required inputs
  if [[ -z "$json_path" ]]; then
    printf 'ERROR: update_contracts_for_next_wave requires json_path\n' >&2
    return 1
  fi

  if [[ -z "$type_name" ]]; then
    printf 'ERROR: update_contracts_for_next_wave requires type_name\n' >&2
    return 1
  fi

  if [[ ! -f "$json_path" ]]; then
    printf 'ERROR: update_contracts_for_next_wave: json_path does not exist: %s\n' "$json_path" >&2
    return 1
  fi

  # Default wave_num to 1
  wave_num="${wave_num:-1}"

  # Convert space-separated source_files to JSON array
  local source_files_json
  source_files_json=$(printf '%s' "$source_files" | tr ' ' '\n' | jq -R -s 'split("\n") | map(select(length > 0))')

  # Use jq to update quantum.json atomically:
  # 1. Initialize execution if absent
  # 2. Initialize execution.discoveredContracts if absent
  # 3. Add the new entry
  local updated
  updated=$(jq \
    --arg tn "$type_name" \
    --argjson wave "$wave_num" \
    --argjson sf "$source_files_json" \
    --arg cf "$consolidated_file" \
    '
    # Initialize execution if absent
    .execution = (.execution // {}) |
    # Initialize discoveredContracts if absent
    .execution.discoveredContracts = (.execution.discoveredContracts // {}) |
    # Add the new entry
    .execution.discoveredContracts[$tn] = {
      discoveredInWave: $wave,
      sourceFiles: $sf,
      consumers: $sf,
      consolidated: true,
      consolidatedFile: $cf
    }
    ' "$json_path" 2>/dev/null)

  if [[ -z "$updated" ]]; then
    printf 'ERROR: update_contracts_for_next_wave: jq transform failed\n' >&2
    return 1
  fi

  # Atomic write via write_quantum_json
  if ! write_quantum_json "$json_path" "$updated"; then
    printf 'ERROR: update_contracts_for_next_wave: atomic write failed\n' >&2
    return 1
  fi

  printf '[CONTRACTS] Added discovered contract: %s (wave %s)\n' "$type_name" "$wave_num" >&2
  return 0
}
