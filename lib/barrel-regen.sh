#!/usr/bin/env bash
# lib/barrel-regen.sh -- Barrel/index file auto-regeneration for quantum-loop
# Source this file to use detect_barrel_files(), should_regenerate(), regenerate_barrel()
# Supports TypeScript, JavaScript, Python, and Rust barrel files.

# Source shared utilities
BARREL_REGEN_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$BARREL_REGEN_LIB_DIR/common.sh" || { printf 'ERROR: common.sh not found\n' >&2; return 1 2>/dev/null || exit 1; }

# detect_barrel_files(repo_root)
# Scans repo_root for barrel/index files: index.ts, index.js, __init__.py, mod.rs
# Returns newline-separated relative paths from repo_root.
# Returns empty string if no barrel files found.
detect_barrel_files() {
  local repo_root="$1"

  if [[ -z "$repo_root" ]]; then
    printf 'ERROR: detect_barrel_files requires repo_root\n' >&2
    return 1
  fi

  if [[ ! -d "$repo_root" ]]; then
    printf 'ERROR: detect_barrel_files: directory not found: %s\n' "$repo_root" >&2
    return 1
  fi

  # Find all barrel files, output paths relative to repo_root
  # Use -mindepth 1 to exclude the root directory itself
  local results
  results=$(find "$repo_root" -mindepth 1 \
    \( -name "index.ts" -o -name "index.js" -o -name "__init__.py" -o -name "mod.rs" \) \
    -not -path "*/node_modules/*" \
    -not -path "*/.git/*" \
    -not -path "*/.ql-wt/*" \
    2>/dev/null | sort)

  # Convert absolute paths to relative paths from repo_root
  if [[ -n "$results" ]]; then
    local repo_root_normalized
    # Normalize trailing slash
    repo_root_normalized="${repo_root%/}/"
    echo "$results" | while IFS= read -r line; do
      # Strip the repo_root prefix to get relative path
      printf '%s\n' "${line#"$repo_root_normalized"}"
    done
  fi
}

# should_regenerate(barrel_path, conflict_files)
# Checks if barrel_path appears in the space-separated conflict_files list.
# Returns 0 if barrel_path is in the conflict list, 1 otherwise.
should_regenerate() {
  local barrel_path="$1"
  local conflict_files="$2"

  if [[ -z "$barrel_path" ]]; then
    return 1
  fi

  if [[ -z "$conflict_files" ]]; then
    return 1
  fi

  # Check if barrel_path appears in the space-separated conflict list
  local file
  for file in $conflict_files; do
    if [[ "$file" == "$barrel_path" ]]; then
      return 0
    fi
  done

  return 1
}

# regenerate_barrel(barrel_path, language)
# Regenerates a barrel/index file by scanning its directory for source files.
# Supported languages: typescript, javascript, python, rust
# Preserves lines with '// manual' or '# manual' markers.
# Preserves lines not matching the auto-gen pattern (fallback preservation).
# Empty directory produces a language-appropriate '// No exports' comment.
# Logs: [BARREL-REGEN] Regenerated <path> (N exports)
# Returns 0 on success, 1 on failure.
regenerate_barrel() {
  local barrel_path="$1"
  local language="$2"

  if [[ -z "$barrel_path" || -z "$language" ]]; then
    printf 'ERROR: regenerate_barrel requires barrel_path and language\n' >&2
    return 1
  fi

  if [[ ! -f "$barrel_path" ]]; then
    printf 'ERROR: regenerate_barrel: file not found: %s\n' "$barrel_path" >&2
    return 1
  fi

  # Capture start time for wall-clock timing
  local start_ms
  start_ms=$(date +%s%3N 2>/dev/null || echo "0")

  local barrel_dir
  barrel_dir="$(dirname "$barrel_path")"
  local barrel_name
  barrel_name="$(basename "$barrel_path")"

  # Non-pure barrel detection: check if file contains non-import/export statements
  if [[ -s "$barrel_path" ]] && _is_non_pure_barrel "$barrel_path" "$language"; then
    printf '[BARREL-REGEN] SKIP %s -- contains non-export logic\n' "$barrel_path"
    local end_ms
    end_ms=$(date +%s%3N 2>/dev/null || echo "0")
    local elapsed_ms=$(( end_ms - start_ms ))
    printf '[BARREL-REGEN] Completed in %dms\n' "$elapsed_ms"
    return 0
  fi

  # Collect preserved lines from existing content (manual markers and non-matching lines)
  local preserved_lines=""
  if [[ -s "$barrel_path" ]]; then
    preserved_lines=$(_collect_preserved_lines "$barrel_path" "$language")
  fi

  # Scan for source files and generate exports
  local auto_exports=""
  case "$language" in
    typescript)
      auto_exports=$(_generate_ts_exports "$barrel_dir" "$barrel_name")
      ;;
    javascript)
      auto_exports=$(_generate_js_exports "$barrel_dir" "$barrel_name")
      ;;
    python)
      auto_exports=$(_generate_py_exports "$barrel_dir" "$barrel_name")
      ;;
    rust)
      auto_exports=$(_generate_rs_exports "$barrel_dir" "$barrel_name")
      ;;
    *)
      printf 'ERROR: regenerate_barrel: unsupported language: %s\n' "$language" >&2
      return 1
      ;;
  esac

  # Count auto-generated exports
  local export_count=0
  if [[ -n "$auto_exports" ]]; then
    export_count=$(printf '%s\n' "$auto_exports" | wc -l | tr -d ' ')
  fi

  # Write the barrel file
  {
    # Preserved lines first (manual markers and non-matching lines)
    if [[ -n "$preserved_lines" ]]; then
      printf '%s\n' "$preserved_lines"
    fi

    # Auto-generated exports
    if [[ -n "$auto_exports" ]]; then
      printf '%s\n' "$auto_exports"
    elif [[ -z "$preserved_lines" ]]; then
      # Empty directory with no preserved lines: write comment
      case "$language" in
        typescript|javascript|rust)
          printf '// No exports -- directory is empty\n'
          ;;
        python)
          printf '# No exports -- directory is empty\n'
          ;;
      esac
    fi
  } > "$barrel_path"

  printf '[BARREL-REGEN] Regenerated %s (%d exports)\n' "$barrel_path" "$export_count"

  # Log wall-clock timing
  local end_ms
  end_ms=$(date +%s%3N 2>/dev/null || echo "0")
  local elapsed_ms=$(( end_ms - start_ms ))
  printf '[BARREL-REGEN] Completed in %dms\n' "$elapsed_ms"

  return 0
}

# _collect_preserved_lines(barrel_path, language)
# Reads existing barrel file and returns lines that should be preserved:
# - Lines with '// manual' or '# manual' markers (explicit preservation)
# - Lines not matching auto-gen patterns (fallback preservation)
_collect_preserved_lines() {
  local barrel_path="$1"
  local language="$2"
  local auto_pattern

  case "$language" in
    typescript|javascript)
      auto_pattern="^export \* from "
      ;;
    python)
      auto_pattern="^from \."
      ;;
    rust)
      auto_pattern="^pub mod "
      ;;
  esac

  while IFS= read -r line; do
    # Always preserve lines with manual markers
    if [[ "$line" == *"// manual"* ]] || [[ "$line" == *"# manual"* ]]; then
      printf '%s\n' "$line"
      continue
    fi
    # Preserve lines that do NOT match the auto-gen pattern
    # Skip blank lines and comment-only lines (they will be regenerated or are noise)
    if [[ -n "$line" ]] && ! printf '%s' "$line" | grep -qE "$auto_pattern"; then
      # Skip pure whitespace lines
      if [[ "$line" =~ ^[[:space:]]*$ ]]; then
        continue
      fi
      printf '%s\n' "$line"
    fi
  done < "$barrel_path"
}

# _is_non_pure_barrel(barrel_path, language)
# Checks if a barrel file contains non-import/export logic.
# Returns 0 (true) if the barrel contains lines that are NOT one of:
#   - import/export statements (language-specific)
#   - comments
#   - blank/whitespace lines
# Returns 1 (false) if the barrel is pure (only imports/exports/comments/blanks).
_is_non_pure_barrel() {
  local barrel_path="$1"
  local language="$2"
  local pure_pattern

  case "$language" in
    typescript|javascript)
      # Pure lines: export, import, //-comments, blank/whitespace
      pure_pattern='^export |^import |^//|^$|^[[:space:]]*$'
      ;;
    python)
      # Pure lines: from . import, import, #-comments, blank/whitespace
      pure_pattern='^from |^import |^#|^$|^[[:space:]]*$'
      ;;
    rust)
      # Pure lines: pub mod, mod, pub use, use, //-comments, blank/whitespace
      pure_pattern='^pub mod |^mod |^pub use |^use |^//|^$|^[[:space:]]*$'
      ;;
    *)
      # Unknown language: assume non-pure to be safe (skip)
      return 0
      ;;
  esac

  while IFS= read -r line; do
    # Blank and whitespace-only lines are always pure
    if [[ -z "$line" ]] || [[ "$line" =~ ^[[:space:]]*$ ]]; then
      continue
    fi
    if ! printf '%s' "$line" | grep -qE "$pure_pattern"; then
      # Found a non-pure line
      return 0
    fi
  done < "$barrel_path"

  # All lines matched pure patterns
  return 1
}

# _generate_ts_exports(dir, barrel_name)
# Scans dir for *.ts files (excluding barrel_name), generates sorted export lines.
_generate_ts_exports() {
  local dir="$1"
  local barrel_name="$2"
  local exports=""

  while IFS= read -r file; do
    local name
    name="$(basename "$file" .ts)"
    exports="${exports}export * from './${name}'\n"
  done < <(find "$dir" -maxdepth 1 -name "*.ts" -not -name "$barrel_name" 2>/dev/null | sort)

  if [[ -n "$exports" ]]; then
    printf '%b' "$exports" | sort
  fi
}

# _generate_js_exports(dir, barrel_name)
# Scans dir for *.js files (excluding barrel_name), generates sorted export lines.
_generate_js_exports() {
  local dir="$1"
  local barrel_name="$2"
  local exports=""

  while IFS= read -r file; do
    local name
    name="$(basename "$file" .js)"
    exports="${exports}export * from './${name}'\n"
  done < <(find "$dir" -maxdepth 1 -name "*.js" -not -name "$barrel_name" 2>/dev/null | sort)

  if [[ -n "$exports" ]]; then
    printf '%b' "$exports" | sort
  fi
}

# _generate_py_exports(dir, barrel_name)
# Scans dir for *.py files (excluding barrel_name and __private.py pattern),
# generates sorted 'from .module import *' lines.
_generate_py_exports() {
  local dir="$1"
  local barrel_name="$2"
  local exports=""

  while IFS= read -r file; do
    local name
    name="$(basename "$file" .py)"
    # Skip files matching __private.py pattern (double underscore prefix)
    if [[ "$name" == __* ]]; then
      continue
    fi
    exports="${exports}from .${name} import *\n"
  done < <(find "$dir" -maxdepth 1 -name "*.py" -not -name "$barrel_name" 2>/dev/null | sort)

  if [[ -n "$exports" ]]; then
    printf '%b' "$exports" | sort
  fi
}

# _generate_rs_exports(dir, barrel_name)
# Scans dir for *.rs files (excluding barrel_name), generates sorted 'pub mod name;' lines.
_generate_rs_exports() {
  local dir="$1"
  local barrel_name="$2"
  local exports=""

  while IFS= read -r file; do
    local name
    name="$(basename "$file" .rs)"
    exports="${exports}pub mod ${name};\n"
  done < <(find "$dir" -maxdepth 1 -name "*.rs" -not -name "$barrel_name" 2>/dev/null | sort)

  if [[ -n "$exports" ]]; then
    printf '%b' "$exports" | sort
  fi
}
