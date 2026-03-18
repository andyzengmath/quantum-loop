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
