#!/usr/bin/env bash
# lib/dep-manifest.sh -- Dependency manifest protection for quantum-loop
#
# Provides: detect_package_manager(), protect_manifest(), verify_lockfile(), run_install()
# Requires: lib/common.sh

# Source shared utilities
DEP_MANIFEST_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$DEP_MANIFEST_LIB_DIR/common.sh" || { printf 'ERROR: common.sh not found\n' >&2; return 1 2>/dev/null || exit 1; }

# detect_package_manager(repo_root)
# Detects all package managers present in the given repo root directory.
# Checks for: package.json->npm, yarn.lock->yarn, pnpm-lock.yaml->pnpm,
#   Cargo.toml->cargo, requirements.txt->pip, poetry.lock+pyproject.toml->poetry, go.mod->go
# Returns all detected managers newline-separated on stdout.
# Returns empty string if none detected.
# Returns 1 on invalid input.
detect_package_manager() {
  local repo_root="$1"

  if [[ -z "$repo_root" ]]; then
    printf 'ERROR: detect_package_manager requires repo_root\n' >&2
    return 1
  fi

  if [[ ! -d "$repo_root" ]]; then
    printf 'ERROR: detect_package_manager: directory does not exist: %s\n' "$repo_root" >&2
    return 1
  fi

  local managers=()

  if [[ -f "$repo_root/package.json" ]]; then
    managers+=("npm")
  fi

  if [[ -f "$repo_root/yarn.lock" ]]; then
    managers+=("yarn")
  fi

  if [[ -f "$repo_root/pnpm-lock.yaml" ]]; then
    managers+=("pnpm")
  fi

  if [[ -f "$repo_root/Cargo.toml" ]]; then
    managers+=("cargo")
  fi

  if [[ -f "$repo_root/requirements.txt" ]]; then
    managers+=("pip")
  fi

  if [[ -f "$repo_root/poetry.lock" && -f "$repo_root/pyproject.toml" ]]; then
    managers+=("poetry")
  fi

  if [[ -f "$repo_root/go.mod" ]]; then
    managers+=("go")
  fi

  if [[ ${#managers[@]} -gt 0 ]]; then
    printf '%s\n' "${managers[@]}"
  fi

  return 0
}

# _is_known_manifest(filename)
# Returns 0 if the basename of the given file is a known dependency manifest.
_is_known_manifest() {
  local filename="$1"
  local base
  base=$(basename "$filename")
  case "$base" in
    package.json|package-lock.json|yarn.lock|pnpm-lock.yaml|\
    Cargo.toml|Cargo.lock|\
    requirements.txt|poetry.lock|pyproject.toml|\
    go.mod|go.sum)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

# protect_manifest(repo_root, conflict_files)
# For each known manifest in the space-separated conflict_files list:
#   runs git checkout --ours and git add to preserve the current branch version.
# Returns the count of protected files on stdout.
# Returns 1 on invalid input.
protect_manifest() {
  local repo_root="$1"
  local conflict_files="$2"

  if [[ -z "$repo_root" ]]; then
    printf 'ERROR: protect_manifest requires repo_root\n' >&2
    return 1
  fi

  local protected_count=0

  # Handle empty conflict_files gracefully
  if [[ -z "$conflict_files" ]]; then
    printf '%d' "$protected_count"
    return 0
  fi

  local file
  for file in $conflict_files; do
    if _is_known_manifest "$file"; then
      git -C "$repo_root" checkout --ours -- "$file" 2>/dev/null
      git -C "$repo_root" add "$file" 2>/dev/null
      protected_count=$((protected_count + 1))
    fi
  done

  printf '%d' "$protected_count"
  return 0
}

# _lockfile_for_manager(package_manager)
# Returns the lockfile name for the given package manager on stdout.
# Returns 1 if manager is unknown.
_lockfile_for_manager() {
  local manager="$1"
  case "$manager" in
    npm)     printf 'package-lock.json' ;;
    yarn)    printf 'yarn.lock' ;;
    pnpm)    printf 'pnpm-lock.yaml' ;;
    cargo)   printf 'Cargo.lock' ;;
    pip)     printf 'requirements.txt' ;;
    poetry)  printf 'poetry.lock' ;;
    go)      printf 'go.sum' ;;
    *)       return 1 ;;
  esac
  return 0
}

# verify_lockfile(repo_root, package_manager)
# Checks that the lockfile for the given package manager exists and is non-empty.
# Returns 0 if lockfile exists and is non-empty, 1 otherwise.
verify_lockfile() {
  local repo_root="$1"
  local package_manager="$2"

  if [[ -z "$repo_root" ]]; then
    printf 'ERROR: verify_lockfile requires repo_root\n' >&2
    return 1
  fi

  if [[ -z "$package_manager" ]]; then
    printf 'ERROR: verify_lockfile requires package_manager\n' >&2
    return 1
  fi

  local lockfile
  lockfile=$(_lockfile_for_manager "$package_manager")
  if [[ $? -ne 0 || -z "$lockfile" ]]; then
    printf 'ERROR: verify_lockfile: unknown package manager: %s\n' "$package_manager" >&2
    return 1
  fi

  local lockfile_path="$repo_root/$lockfile"

  if [[ ! -f "$lockfile_path" ]]; then
    printf 'ERROR: verify_lockfile: lockfile not found: %s\n' "$lockfile_path" >&2
    return 1
  fi

  if [[ ! -s "$lockfile_path" ]]; then
    printf 'ERROR: verify_lockfile: lockfile is empty: %s\n' "$lockfile_path" >&2
    return 1
  fi

  return 0
}

# _install_command_for_manager(package_manager)
# Returns the install command for the given package manager on stdout.
# Returns 1 if manager is unknown.
_install_command_for_manager() {
  local manager="$1"
  case "$manager" in
    npm)     printf 'npm install' ;;
    yarn)    printf 'yarn install' ;;
    pnpm)    printf 'pnpm install' ;;
    cargo)   printf 'cargo build' ;;
    pip)     printf 'pip install -r requirements.txt' ;;
    poetry)  printf 'poetry install' ;;
    go)      printf 'go mod tidy' ;;
    *)       return 1 ;;
  esac
  return 0
}

# _manifest_for_manager(package_manager)
# Returns the primary manifest file for the given package manager.
# Used by run_install recovery to checkout --theirs for deps section.
_manifest_for_manager() {
  local manager="$1"
  case "$manager" in
    npm|yarn|pnpm) printf 'package.json' ;;
    cargo)         printf 'Cargo.toml' ;;
    pip)           printf 'requirements.txt' ;;
    poetry)        printf 'pyproject.toml' ;;
    go)            printf 'go.mod' ;;
    *)             return 1 ;;
  esac
  return 0
}

# run_install(repo_root, package_manager)
# Runs the correct install command for the given package manager with a 120s timeout.
# On timeout: kills the process, logs warning, returns 1.
# On failure: attempts recovery by checking out --theirs for the manifest, then re-runs install.
# If recovery also fails: logs warning, returns 1 (does NOT propagate as story failure).
# Logs wall-clock time: [DEP-MANIFEST] Install completed in Nms
# Returns 0 on success, 1 on failure.
run_install() {
  local repo_root="$1"
  local package_manager="$2"

  if [[ -z "$repo_root" ]]; then
    printf 'ERROR: run_install requires repo_root\n' >&2
    return 1
  fi

  if [[ -z "$package_manager" ]]; then
    printf 'ERROR: run_install requires package_manager\n' >&2
    return 1
  fi

  local install_cmd
  install_cmd=$(_install_command_for_manager "$package_manager")
  if [[ $? -ne 0 || -z "$install_cmd" ]]; then
    printf 'ERROR: run_install: unknown package manager: %s\n' "$package_manager" >&2
    return 1
  fi

  local use_ms=true
  if ! date +%s%N >/dev/null 2>&1; then
    use_ms=false
  fi

  local start_ms
  if [[ "$use_ms" == "true" ]]; then
    start_ms=$(( $(date +%s%N) / 1000000 ))
  else
    start_ms=$(( $(date +%s) * 1000 ))
  fi

  # Run install with 120s timeout
  local install_exit=0
  if command -v timeout >/dev/null 2>&1; then
    timeout 120 bash -c "cd \"$repo_root\" && $install_cmd" >/dev/null 2>&1
    install_exit=$?
  else
    # Fallback: run without timeout if timeout command not available
    (cd "$repo_root" && eval "$install_cmd") >/dev/null 2>&1
    install_exit=$?
  fi

  # Check for timeout (exit code 124 from timeout command)
  if [[ "$install_exit" -eq 124 ]]; then
    printf '[DEP-MANIFEST] Install timed out after 120s for %s\n' "$package_manager" >&2
    return 1
  fi

  # On failure, attempt recovery
  if [[ "$install_exit" -ne 0 ]]; then
    printf '[DEP-MANIFEST] Install failed for %s, attempting recovery with --theirs\n' "$package_manager" >&2

    local manifest_file
    manifest_file=$(_manifest_for_manager "$package_manager")

    if [[ -n "$manifest_file" ]]; then
      git -C "$repo_root" checkout --theirs -- "$manifest_file" 2>/dev/null
      git -C "$repo_root" add "$manifest_file" 2>/dev/null
    fi

    # Re-run install
    local recovery_exit=0
    if command -v timeout >/dev/null 2>&1; then
      timeout 120 bash -c "cd \"$repo_root\" && $install_cmd" >/dev/null 2>&1
      recovery_exit=$?
    else
      (cd "$repo_root" && eval "$install_cmd") >/dev/null 2>&1
      recovery_exit=$?
    fi

    if [[ "$recovery_exit" -ne 0 ]]; then
      printf '[DEP-MANIFEST] Recovery install also failed for %s\n' "$package_manager" >&2
      return 1
    fi
  fi

  # Calculate elapsed time
  local end_ms
  if [[ "$use_ms" == "true" ]]; then
    end_ms=$(( $(date +%s%N) / 1000000 ))
  else
    end_ms=$(( $(date +%s) * 1000 ))
  fi
  local elapsed_ms=$(( end_ms - start_ms ))

  printf '[DEP-MANIFEST] Install completed in %dms\n' "$elapsed_ms"
  return 0
}
