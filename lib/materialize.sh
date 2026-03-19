#!/usr/bin/env bash
# lib/materialize.sh -- Materialization functions for quantum-loop
# Source this file to use detect_language() and future materialization utilities.

# Source shared utilities
MATERIALIZE_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$MATERIALIZE_LIB_DIR/common.sh" || { printf "ERROR: common.sh not found\n" >&2; return 1 2>/dev/null || exit 1; }
source "$MATERIALIZE_LIB_DIR/json-atomic.sh" || { printf "ERROR: json-atomic.sh not found\n" >&2; return 1 2>/dev/null || exit 1; }

# detect_language(repo_root)
# Detects the primary programming language of a project by checking for config files.
# Priority order: tsconfig.json -> typescript, pyproject.toml/setup.py -> python, go.mod -> go
# Outputs one of: typescript, python, go, unknown
# Returns 0 always; outputs "unknown" for missing/invalid repo_root.
detect_language() {
  local repo_root="$1"
  local def_file_hint="${2:-}"

  # If hint provided, use extension as primary signal
  if [[ -n "$def_file_hint" ]]; then
    case "$def_file_hint" in
      *.ts|*.tsx) printf "typescript"; return 0 ;;
      *.py) printf "python"; return 0 ;;
      *.go) printf "go"; return 0 ;;
    esac
  fi

  if [[ -z "$repo_root" || ! -d "$repo_root" ]]; then
    printf "unknown"
    return 0
  fi

  if [[ -f "$repo_root/tsconfig.json" ]]; then
    printf "typescript"
    return 0
  fi

  if [[ -f "$repo_root/pyproject.toml" || -f "$repo_root/setup.py" ]]; then
    printf "python"
    return 0
  fi

  if [[ -f "$repo_root/go.mod" ]]; then
    printf "go"
    return 0
  fi

  printf "unknown"
  return 0
}

# infer_shared_types_dir(repo_root, language)
# Infers the shared types directory from the project's existing structure.
# Checks for existing directories in priority order:
#   1. src/shared/types/
#   2. src/types/
#   3. src/interfaces/
#   4. types/
#   5. shared/
# If none exist, returns a language-specific default:
#   typescript -> src/shared/types
#   python     -> src/shared
#   go         -> internal/shared
#   unknown/*  -> src/shared/types
# Does NOT create any directories (idempotent).
# Outputs the inferred relative path on stdout. Returns 0 always.
infer_shared_types_dir() {
  local repo_root="$1"
  local language="$2"

  # Check for existing directories in priority order
  local candidate_dirs=(
    "src/shared/types"
    "src/types"
    "src/interfaces"
    "types"
    "shared"
  )

  if [[ -n "$repo_root" && -d "$repo_root" ]]; then
    for dir in "${candidate_dirs[@]}"; do
      if [[ -d "$repo_root/$dir" ]]; then
        printf "%s" "$dir"
        return 0
      fi
    done
  fi

  # No existing directory found; return language-specific default
  case "$language" in
    python)
      printf "src/shared"
      ;;
    go)
      printf "internal/shared"
      ;;
    typescript|*)
      printf "src/shared/types"
      ;;
  esac
  return 0
}

# generate_definition_file(type_name, type_entry_json, language, repo_root)
# Generates or writes a type definition file based on contract entry.
# - If definition field present: writes verbatim to definitionFile path
# - If shape present but no definition: generates from shape template
# - If neither: logs warning and skips
# - If file exists with same content: skips (idempotent)
# - If file exists with different content: logs [MATERIALIZE] SKIP and returns
# - Creates parent directories with mkdir -p
# Outputs status messages to stderr. Returns 0 on success/skip, 1 on error.
generate_definition_file() {
  local type_name="$1"
  local type_entry_json="$2"
  local language="$3"
  local repo_root="$4"

  if [[ -z "$type_name" ]]; then
    printf "[MATERIALIZE] WARNING: empty type_name, skipping\n" >&2
    return 0
  fi

  if [[ -z "$type_entry_json" || "$type_entry_json" == "{}" ]]; then
    printf "[MATERIALIZE] WARNING: empty or minimal JSON for %s, skipping\n" "$type_name" >&2
    return 0
  fi

  # Extract definitionFile from JSON
  local def_file
  def_file=$(printf '%s' "$type_entry_json" | jq -r '.definitionFile // ""' 2>/dev/null)

  if [[ -z "$def_file" ]]; then
    # Infer directory from project structure
    local inferred_dir
    inferred_dir=$(infer_shared_types_dir "$repo_root" "$language")
    # Build filename from type_name: convert CamelCase to kebab-case
    local kebab_name
    kebab_name=$(printf '%s' "$type_name" | sed 's/\([A-Z]\)/-\L\1/g' | sed 's/^-//')
    # Determine extension by language
    local ext
    case "$language" in
      typescript) ext="ts" ;;
      python) ext="py" ;;
      go) ext="go" ;;
      *) ext="ts" ;;
    esac
    def_file="${inferred_dir}/${kebab_name}.${ext}"
    printf "[MATERIALIZE] Inferred definitionFile for %s: %s\n" "$type_name" "$def_file" >&2
  fi

  local full_path="$repo_root/$def_file"

  # Extract definition and shape
  local definition
  definition=$(printf '%s' "$type_entry_json" | jq -r '.definition // ""' 2>/dev/null)

  local has_shape
  has_shape=$(printf '%s' "$type_entry_json" | jq -r 'if .shape then "true" else "false" end' 2>/dev/null)

  # Determine content to write
  local content=""

  if [[ -n "$definition" ]]; then
    # Write definition verbatim (interpret escape sequences)
    content=$(printf '%b' "$definition")
  elif [[ "$has_shape" == "true" ]]; then
    # Generate from shape based on language
    content=$(_generate_from_shape "$type_name" "$type_entry_json" "$language")
  else
    printf "[MATERIALIZE] WARNING: no definition or shape for %s, skipping\n" "$type_name" >&2
    return 0
  fi

  # Check if file already exists
  if [[ -f "$full_path" ]]; then
    local existing_content
    existing_content=$(cat "$full_path")
    if [[ "$existing_content" == "$content" ]]; then
      # Same content, skip (idempotent)
      printf "[MATERIALIZE] SKIP %s — file already exists with same content\n" "$type_name" >&2
      return 0
    else
      # Different content, do NOT overwrite
      printf "[MATERIALIZE] SKIP %s — file already exists with different content\n" "$type_name" >&2
      return 0
    fi
  fi

  # Create parent directories
  local parent_dir
  parent_dir=$(dirname "$full_path")
  mkdir -p "$parent_dir"

  # Write the file
  printf '%s' "$content" > "$full_path"
  printf "[MATERIALIZE] Wrote %s to %s\n" "$type_name" "$def_file" >&2
  printf "%s" "$def_file"
  return 0
}

# _generate_from_shape(type_name, type_entry_json, language)
# Internal helper: generates a type definition from the shape field.
# Outputs the generated content on stdout.
_generate_from_shape() {
  local type_name="$1"
  local type_entry_json="$2"
  local language="$3"

  case "$language" in
    typescript)
      _generate_ts_from_shape "$type_name" "$type_entry_json"
      ;;
    python)
      _generate_py_from_shape "$type_name" "$type_entry_json"
      ;;
    go)
      _generate_go_from_shape "$type_name" "$type_entry_json"
      ;;
    *)
      # Default to TypeScript
      _generate_ts_from_shape "$type_name" "$type_entry_json"
      ;;
  esac
}

# _generate_ts_from_shape(type_name, type_entry_json)
# Generates a TypeScript interface from shape JSON.
_generate_ts_from_shape() {
  local type_name="$1"
  local type_entry_json="$2"
  local result="export interface ${type_name} {"

  # Add properties
  local prop_count
  prop_count=$(printf '%s' "$type_entry_json" | jq '.shape.properties | length' 2>/dev/null)
  prop_count=${prop_count:-0}

  local i=0
  while [[ $i -lt $prop_count ]]; do
    local prop_name prop_type is_readonly
    prop_name=$(printf '%s' "$type_entry_json" | jq -r ".shape.properties[$i].name" 2>/dev/null)
    prop_type=$(printf '%s' "$type_entry_json" | jq -r ".shape.properties[$i].type" 2>/dev/null)
    is_readonly=$(printf '%s' "$type_entry_json" | jq -r ".shape.properties[$i].readonly // false" 2>/dev/null)

    if [[ "$is_readonly" == "true" ]]; then
      result="${result}
  readonly ${prop_name}: ${prop_type};"
    else
      result="${result}
  ${prop_name}: ${prop_type};"
    fi
    i=$((i + 1))
  done

  # Add methods
  local method_count
  method_count=$(printf '%s' "$type_entry_json" | jq '.shape.methods | length' 2>/dev/null)
  method_count=${method_count:-0}

  local j=0
  while [[ $j -lt $method_count ]]; do
    local method_name method_returns
    method_name=$(printf '%s' "$type_entry_json" | jq -r ".shape.methods[$j].name" 2>/dev/null)
    method_returns=$(printf '%s' "$type_entry_json" | jq -r ".shape.methods[$j].returns" 2>/dev/null)

    # Build params
    local param_count
    param_count=$(printf '%s' "$type_entry_json" | jq ".shape.methods[$j].params | length" 2>/dev/null)
    param_count=${param_count:-0}

    local params=""
    local k=0
    while [[ $k -lt $param_count ]]; do
      local p_name p_type
      p_name=$(printf '%s' "$type_entry_json" | jq -r ".shape.methods[$j].params[$k].name" 2>/dev/null)
      p_type=$(printf '%s' "$type_entry_json" | jq -r ".shape.methods[$j].params[$k].type" 2>/dev/null)
      if [[ $k -gt 0 ]]; then
        params="${params}, "
      fi
      params="${params}${p_name}: ${p_type}"
      k=$((k + 1))
    done

    result="${result}
  ${method_name}(${params}): ${method_returns};"
    j=$((j + 1))
  done

  result="${result}
}"
  printf '%s' "$result"
}

# _generate_py_from_shape(type_name, type_entry_json)
# Generates a Python Protocol from shape JSON.
_generate_py_from_shape() {
  local type_name="$1"
  local type_entry_json="$2"
  local result="from typing import Protocol


class ${type_name}(Protocol):"

  local has_members=false

  # Add properties
  local prop_count
  prop_count=$(printf '%s' "$type_entry_json" | jq '.shape.properties | length' 2>/dev/null)
  prop_count=${prop_count:-0}

  local i=0
  while [[ $i -lt $prop_count ]]; do
    local prop_name prop_type
    prop_name=$(printf '%s' "$type_entry_json" | jq -r ".shape.properties[$i].name" 2>/dev/null)
    prop_type=$(printf '%s' "$type_entry_json" | jq -r ".shape.properties[$i].type" 2>/dev/null)
    result="${result}
    ${prop_name}: ${prop_type}"
    has_members=true
    i=$((i + 1))
  done

  # Add methods
  local method_count
  method_count=$(printf '%s' "$type_entry_json" | jq '.shape.methods | length' 2>/dev/null)
  method_count=${method_count:-0}

  local j=0
  while [[ $j -lt $method_count ]]; do
    local method_name method_returns
    method_name=$(printf '%s' "$type_entry_json" | jq -r ".shape.methods[$j].name" 2>/dev/null)
    method_returns=$(printf '%s' "$type_entry_json" | jq -r ".shape.methods[$j].returns" 2>/dev/null)

    local param_count
    param_count=$(printf '%s' "$type_entry_json" | jq ".shape.methods[$j].params | length" 2>/dev/null)
    param_count=${param_count:-0}

    local params="self"
    local k=0
    while [[ $k -lt $param_count ]]; do
      local p_name p_type
      p_name=$(printf '%s' "$type_entry_json" | jq -r ".shape.methods[$j].params[$k].name" 2>/dev/null)
      p_type=$(printf '%s' "$type_entry_json" | jq -r ".shape.methods[$j].params[$k].type" 2>/dev/null)
      params="${params}, ${p_name}: ${p_type}"
      k=$((k + 1))
    done

    result="${result}

    def ${method_name}(${params}) -> ${method_returns}: ..."
    has_members=true
    j=$((j + 1))
  done

  if [[ "$has_members" == "false" ]]; then
    result="${result}
    ..."
  fi

  printf '%s' "$result"
}

# _generate_go_from_shape(type_name, type_entry_json)
# Generates a Go interface from shape JSON.
_generate_go_from_shape() {
  local type_name="$1"
  local type_entry_json="$2"
  local pkg_name
  pkg_name=$(printf '%s' "$type_entry_json" | jq -r '.definitionFile // ""' 2>/dev/null | xargs dirname 2>/dev/null | xargs basename 2>/dev/null)
  pkg_name="${pkg_name:-shared}"
  local result="package ${pkg_name}

type ${type_name} interface {"

  # Go interfaces only have methods
  local method_count
  method_count=$(printf '%s' "$type_entry_json" | jq '.shape.methods | length' 2>/dev/null)
  method_count=${method_count:-0}

  local j=0
  while [[ $j -lt $method_count ]]; do
    local method_name method_returns
    method_name=$(printf '%s' "$type_entry_json" | jq -r ".shape.methods[$j].name" 2>/dev/null)
    method_returns=$(printf '%s' "$type_entry_json" | jq -r ".shape.methods[$j].returns" 2>/dev/null)

    local param_count
    param_count=$(printf '%s' "$type_entry_json" | jq ".shape.methods[$j].params | length" 2>/dev/null)
    param_count=${param_count:-0}

    local params=""
    local k=0
    while [[ $k -lt $param_count ]]; do
      local p_name p_type
      p_name=$(printf '%s' "$type_entry_json" | jq -r ".shape.methods[$j].params[$k].name" 2>/dev/null)
      p_type=$(printf '%s' "$type_entry_json" | jq -r ".shape.methods[$j].params[$k].type" 2>/dev/null)
      if [[ $k -gt 0 ]]; then
        params="${params}, "
      fi
      params="${params}${p_name} ${p_type}"
      k=$((k + 1))
    done

    result="${result}
	${method_name}(${params}) ${method_returns}"
    j=$((j + 1))
  done

  result="${result}
}"
  printf '%s' "$result"
}

# materialize_contracts(json_path, repo_root, wave_num)
# Reads contracts.shared_types and execution.discoveredContracts from quantum.json.
# Filters to types with consumers.length >= 2. Calls detect_language() and
# generate_definition_file() for each. Commits materialized files with git.
# Updates execution.materializedContracts via atomic JSON write.
# Prints materialized type names to stdout (newline-separated).
# Returns 0 on success, 1 on error.
materialize_contracts() {
  local json_path="$1"
  local repo_root="$2"
  local wave_num="$3"

  if [[ -z "$json_path" ]]; then
    printf "[MATERIALIZE] ERROR: json_path is required\n" >&2
    return 1
  fi

  if [[ ! -f "$json_path" ]]; then
    printf "[MATERIALIZE] ERROR: quantum.json not found at %s\n" "$json_path" >&2
    return 1
  fi

  if [[ -z "$repo_root" ]]; then
    printf "[MATERIALIZE] ERROR: repo_root is required\n" >&2
    return 1
  fi

  wave_num="${wave_num:-1}"

  # Detect language
  local language
  language=$(detect_language "$repo_root")

  # Collect type entries from contracts.shared_types with consumers >= 2
  local materialized_names=()
  local materialized_files=()

  # Process contracts.shared_types
  local type_names
  type_names=$(jq -r '.contracts.shared_types // {} | keys[]' "$json_path" 2>/dev/null | tr -d '\r')

  while IFS= read -r type_name; do
    [[ -z "$type_name" ]] && continue
    local type_entry
    type_entry=$(jq -r --arg tn "$type_name" '.contracts.shared_types[$tn]' "$json_path" 2>/dev/null)

    # Check consumers count
    local consumer_count
    consumer_count=$(printf '%s' "$type_entry" | jq '.consumers // [] | length' 2>/dev/null)
    consumer_count=${consumer_count:-0}

    if [[ $consumer_count -lt 2 ]]; then
      printf "[MATERIALIZE] SKIP %s — only %d consumer(s)\n" "$type_name" "$consumer_count" >&2
      continue
    fi

    # Call generate_definition_file and capture the written path
    local actual_path
    actual_path=$(generate_definition_file "$type_name" "$type_entry" "$language" "$repo_root" 2>/dev/null)
    if [[ -n "$actual_path" ]]; then
      materialized_names+=("$type_name")
      materialized_files+=("$actual_path")
    fi
  done <<< "$type_names"

  # Process execution.discoveredContracts
  local discovered_names
  discovered_names=$(jq -r '.execution.discoveredContracts // {} | keys[]' "$json_path" 2>/dev/null | tr -d '\r')

  while IFS= read -r type_name; do
    [[ -z "$type_name" ]] && continue
    local disc_entry
    disc_entry=$(jq -r --arg tn "$type_name" '.execution.discoveredContracts[$tn]' "$json_path" 2>/dev/null)

    # Check consumers count
    local consumer_count
    consumer_count=$(printf '%s' "$disc_entry" | jq '.consumers // [] | length' 2>/dev/null)
    consumer_count=${consumer_count:-0}

    if [[ $consumer_count -lt 2 ]]; then
      printf "[MATERIALIZE] SKIP discovered %s — only %d consumer(s)\n" "$type_name" "$consumer_count" >&2
      continue
    fi

    # Build a type_entry_json compatible with generate_definition_file
    # Use consolidatedFile as definitionFile if available
    local def_file
    def_file=$(printf '%s' "$disc_entry" | jq -r '.consolidatedFile // ""' 2>/dev/null)
    local definition
    definition=$(printf '%s' "$disc_entry" | jq -r '.definition // ""' 2>/dev/null)

    if [[ -n "$def_file" ]]; then
      local synth_entry
      synth_entry=$(printf '%s' "$disc_entry" | jq --arg df "$def_file" '. + {definitionFile: $df}' 2>/dev/null)
      local actual_path
      actual_path=$(generate_definition_file "$type_name" "$synth_entry" "$language" "$repo_root" 2>/dev/null)

      if [[ -n "$actual_path" ]]; then
        materialized_names+=("$type_name")
        materialized_files+=("$actual_path")
      fi
    fi
  done <<< "$discovered_names"

  # If nothing was materialized, log and return
  if [[ ${#materialized_names[@]} -eq 0 ]]; then
    printf "[MATERIALIZE] No multi-consumer contracts to materialize for Wave %s\n" "$wave_num" >&2
    return 0
  fi

  # Git add and commit materialized files
  (
    cd "$repo_root" || return 1
    for f in "${materialized_files[@]}"; do
      git add "$f" 2>/dev/null
    done
    git commit -m "chore: materialize contracts for Wave $wave_num" -q 2>/dev/null
  )

  # Update execution.materializedContracts in quantum.json via atomic write
  local names_json
  names_json=$(printf '%s\n' "${materialized_names[@]}" | jq -R . | jq -s .)

  local updated
  updated=$(jq --argjson names "$names_json" \
    '.execution.materializedContracts = ((.execution.materializedContracts // []) + $names | unique)' \
    "$json_path" 2>/dev/null)

  if [[ -n "$updated" ]]; then
    write_quantum_json "$json_path" "$updated"
  fi

  # Print materialized names to stdout
  for name in "${materialized_names[@]}"; do
    printf '%s\n' "$name"
  done

  return 0
}
