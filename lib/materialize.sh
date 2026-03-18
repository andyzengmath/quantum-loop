#!/usr/bin/env bash
# lib/materialize.sh -- Materialization functions for quantum-loop
# Source this file to use detect_language() and future materialization utilities.

# Source shared utilities
MATERIALIZE_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$MATERIALIZE_LIB_DIR/common.sh" || { printf "ERROR: common.sh not found\n" >&2; return 1 2>/dev/null || exit 1; }

# detect_language(repo_root)
# Detects the primary programming language of a project by checking for config files.
# Priority order: tsconfig.json -> typescript, pyproject.toml/setup.py -> python, go.mod -> go
# Outputs one of: typescript, python, go, unknown
# Returns 0 always; outputs "unknown" for missing/invalid repo_root.
detect_language() {
  local repo_root="$1"

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
