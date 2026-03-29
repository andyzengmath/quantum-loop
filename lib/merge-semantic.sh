#!/usr/bin/env bash
# lib/merge-semantic.sh -- AST-aware 3-way merge for quantum-loop
#
# Provides: can_semantic_merge(), semantic_merge(), get_semantic_merge_status()
# Requires: lib/common.sh
# Optional tooling: ts-morph (Node.js), libcst (Python), diff3 (system)

# shellcheck disable=SC1091,SC2317

# Source shared utilities
MERGE_SEMANTIC_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$MERGE_SEMANTIC_LIB_DIR/common.sh" || { printf "ERROR: common.sh not found\n" >&2; return 1 2>/dev/null || exit 1; }

# ---------------------------------------------------------------------------
# Tooling detection
# ---------------------------------------------------------------------------

# diff3
if command -v diff3 &>/dev/null; then
  DIFF3_AVAILABLE=true
else
  DIFF3_AVAILABLE=false
fi

# ts-morph (Node.js)
if command -v node &>/dev/null && node -e "require('ts-morph')" 2>/dev/null; then
  TSMORPH_AVAILABLE=true
else
  TSMORPH_AVAILABLE=false
fi

# libcst (Python)
if command -v python &>/dev/null && python -c "import libcst" 2>/dev/null; then
  LIBCST_AVAILABLE=true
elif command -v python3 &>/dev/null && python3 -c "import libcst" 2>/dev/null; then
  LIBCST_AVAILABLE=true
else
  LIBCST_AVAILABLE=false
fi

# Log available tooling
printf "[MERGE-SEMANTIC] diff3=%s, ts-morph=%s, libcst=%s\n" \
  "$DIFF3_AVAILABLE" "$TSMORPH_AVAILABLE" "$LIBCST_AVAILABLE" >&2

# ---------------------------------------------------------------------------
# get_semantic_merge_status()
# Returns comma-separated list of available backend names (e.g., "ts-morph,diff3")
# or "none" if no backends are available.
# ---------------------------------------------------------------------------
get_semantic_merge_status() {
  local backends=()
  [[ "$TSMORPH_AVAILABLE" == "true" ]] && backends+=("ts-morph")
  [[ "$LIBCST_AVAILABLE" == "true" ]] && backends+=("libcst")
  [[ "$DIFF3_AVAILABLE" == "true" ]] && backends+=("diff3")
  if [[ ${#backends[@]} -eq 0 ]]; then
    printf "none"
  else
    local IFS=','
    printf "%s" "${backends[*]}"
  fi
}

# ---------------------------------------------------------------------------
# Known binary extensions (always return 1 from can_semantic_merge)
# ---------------------------------------------------------------------------
_SEMANTIC_BINARY_EXTENSIONS="png|jpg|jpeg|gif|bmp|ico|svg|webp|wasm|exe|dll|so|dylib|bin|o|a|lib|zip|tar|gz|bz2|xz|7z|rar|pdf|doc|docx|xls|xlsx|ppt|pptx|mp3|mp4|avi|mov|mkv|flac|wav|ogg|ttf|otf|woff|woff2|eot|class|pyc|pyo"

# ---------------------------------------------------------------------------
# can_semantic_merge(file_path)
# Returns 0 if the file can be semantically merged, 1 otherwise.
# Checks: .ts/.tsx need TSMORPH or DIFF3, .py needs LIBCST or DIFF3,
# other text files need DIFF3. Binary files always return 1.
# ---------------------------------------------------------------------------
can_semantic_merge() {
  local file_path="$1"

  # Empty path is not mergeable
  if [[ -z "$file_path" ]]; then
    return 1
  fi

  # Extract extension (lowercase)
  local ext=""
  if [[ "$file_path" == *.* ]]; then
    ext="${file_path##*.}"
    ext="${ext,,}"
  fi

  # Check binary extensions
  if [[ -n "$ext" ]]; then
    local binary_pattern
    binary_pattern="^(${_SEMANTIC_BINARY_EXTENSIONS})$"
    if [[ "$ext" =~ $binary_pattern ]]; then
      return 1
    fi
  fi

  # Route by extension
  case "$ext" in
    ts|tsx)
      if [[ "$TSMORPH_AVAILABLE" == "true" || "$DIFF3_AVAILABLE" == "true" ]]; then
        return 0
      fi
      return 1
      ;;
    py)
      if [[ "$LIBCST_AVAILABLE" == "true" || "$DIFF3_AVAILABLE" == "true" ]]; then
        return 0
      fi
      return 1
      ;;
    *)
      # All other text files: need diff3
      if [[ "$DIFF3_AVAILABLE" == "true" ]]; then
        return 0
      fi
      return 1
      ;;
  esac
}

# ---------------------------------------------------------------------------
# _semantic_diff3_merge(base, ours, theirs, output)
# Performs a standard diff3 3-way merge.
# Returns 0 on clean merge, 1 on conflicts.
# Does NOT modify input files.
# ---------------------------------------------------------------------------
_semantic_diff3_merge() {
  local base_file="$1"
  local ours_file="$2"
  local theirs_file="$3"
  local output_file="$4"

  if [[ "$DIFF3_AVAILABLE" != "true" ]]; then
    printf "ERROR: diff3 not available\n" >&2
    return 1
  fi

  # diff3 -m: merge mode. exit 0=clean, 1=conflicts, 2=error
  diff3 -m "$ours_file" "$base_file" "$theirs_file" > "$output_file"
  local rc=$?

  if [[ $rc -eq 0 ]]; then
    printf "[MERGE-SEMANTIC] diff3 clean merge succeeded\n" >&2
    return 0
  elif [[ $rc -eq 1 ]]; then
    printf "[MERGE-SEMANTIC] diff3 merge has conflicts\n" >&2
    return 1
  else
    printf "ERROR: diff3 failed with exit code %d\n" "$rc" >&2
    return 1
  fi
}

# ---------------------------------------------------------------------------
# _semantic_tsmorph_merge(base, ours, theirs, output)
# AST-aware merge for TypeScript files using ts-morph.
# Operates at top-level declaration level only.
# Non-overlapping additions are merged cleanly.
# Same-name declarations modified on both sides return 1 (conflict).
# On parse failure, returns 1 with log (caller falls through to diff3).
# Does NOT modify input files.
# ---------------------------------------------------------------------------
_semantic_tsmorph_merge() {
  local base_file="$1"
  local ours_file="$2"
  local theirs_file="$3"
  local output_file="$4"

  local base_native ours_native theirs_native output_native
  base_native=$(_to_native_path "$base_file")
  ours_native=$(_to_native_path "$ours_file")
  theirs_native=$(_to_native_path "$theirs_file")
  output_native=$(_to_native_path "$output_file")

  node -e "
const { Project, SyntaxKind } = require('ts-morph');
const fs = require('fs');
const path = require('path');

const basePath = process.argv[1];
const oursPath = process.argv[2];
const theirsPath = process.argv[3];
const outputPath = process.argv[4];

function getDeclName(node) {
  // Get the name of a top-level declaration
  if (node.getName) return node.getName();
  if (node.getDeclarations) {
    const decls = node.getDeclarations();
    if (decls.length > 0 && decls[0].getName) return decls[0].getName();
  }
  return null;
}

function getTopLevelDecls(sourceFile) {
  const decls = new Map();
  for (const child of sourceFile.getChildren()[0].getChildren()) {
    const kind = child.getKindName();
    if (kind === 'EndOfFileToken') continue;
    const name = getDeclName(child);
    const text = child.getFullText().trim();
    decls.set(name || ('__anon_' + decls.size), { name, text, kind });
  }
  return decls;
}

try {
  const project = new Project({ useInMemoryFileSystem: true });

  const baseSource = project.createSourceFile('base.ts', fs.readFileSync(basePath, 'utf8'));
  const oursSource = project.createSourceFile('ours.ts', fs.readFileSync(oursPath, 'utf8'));
  const theirsSource = project.createSourceFile('theirs.ts', fs.readFileSync(theirsPath, 'utf8'));

  const baseDecls = getTopLevelDecls(baseSource);
  const oursDecls = getTopLevelDecls(oursSource);
  const theirsDecls = getTopLevelDecls(theirsSource);

  const merged = [];
  const seen = new Set();

  // Process declarations from ours
  for (const [name, ourDecl] of oursDecls) {
    const baseDecl = baseDecls.get(name);
    const theirDecl = theirsDecls.get(name);
    seen.add(name);

    if (baseDecl && theirDecl) {
      // Exists in all three: check for conflict
      const oursChanged = ourDecl.text !== baseDecl.text;
      const theirsChanged = theirDecl.text !== baseDecl.text;
      if (oursChanged && theirsChanged && ourDecl.text !== theirDecl.text) {
        // True conflict: same name modified differently on both sides
        process.stderr.write('[MERGE-SEMANTIC] ts-morph conflict on declaration: ' + name + '\\n');
        process.exit(1);
      }
      // Take whichever changed, or ours if both same
      merged.push(oursChanged ? ourDecl.text : theirDecl.text);
    } else if (baseDecl && !theirDecl) {
      // Deleted on theirs side -- respect deletion (skip)
    } else {
      // New on ours or unchanged
      merged.push(ourDecl.text);
    }
  }

  // Add declarations only in theirs (new additions)
  for (const [name, theirDecl] of theirsDecls) {
    if (!seen.has(name)) {
      merged.push(theirDecl.text);
    }
  }

  fs.writeFileSync(outputPath, merged.join('\\n\\n') + '\\n');
  process.exit(0);
} catch (err) {
  process.stderr.write('[MERGE-SEMANTIC] ts-morph parse failure: ' + err.message + '\\n');
  process.exit(1);
}
" "$base_native" "$ours_native" "$theirs_native" "$output_native" 2>&1
  return $?
}

# ---------------------------------------------------------------------------
# _semantic_libcst_merge(base, ours, theirs, output)
# AST-aware merge for Python files using libcst.
# Operates at top-level statement level only.
# Non-overlapping additions are merged cleanly.
# Same-name declarations modified on both sides return 1 (conflict).
# On parse failure, returns 1 with log (caller falls through to diff3).
# Does NOT modify input files.
# ---------------------------------------------------------------------------
_semantic_libcst_merge() {
  local base_file="$1"
  local ours_file="$2"
  local theirs_file="$3"
  local output_file="$4"

  local base_native ours_native theirs_native output_native
  base_native=$(_to_native_path "$base_file")
  ours_native=$(_to_native_path "$ours_file")
  theirs_native=$(_to_native_path "$theirs_file")
  output_native=$(_to_native_path "$output_file")

  # Determine python command (python or python3)
  local py_cmd="python"
  if ! command -v python &>/dev/null; then
    py_cmd="python3"
  fi

  "$py_cmd" - "$base_native" "$ours_native" "$theirs_native" "$output_native" << 'PYMERGE'
import sys
import libcst as cst

def get_stmt_name(stmt):
    """Extract the name of a top-level statement if it has one."""
    if isinstance(stmt, (cst.FunctionDef, cst.ClassDef)):
        return stmt.name.value
    if isinstance(stmt, cst.SimpleStatementLine):
        for item in stmt.body:
            if isinstance(item, (cst.Assign, cst.AnnAssign)):
                if isinstance(item, cst.Assign) and item.targets:
                    target = item.targets[0].target
                    if isinstance(target, cst.Name):
                        return target.value
                elif isinstance(item, cst.AnnAssign) and isinstance(item.target, cst.Name):
                    return item.target.value
            if isinstance(item, cst.ImportFrom):
                return "__import_" + (item.module.value if isinstance(item.module, cst.Attribute) or isinstance(item.module, cst.Name) else str(item.module))
    return None

def get_stmt_text(stmt):
    """Get the source text of a statement."""
    return cst.parse_module("").code_for_node(stmt).strip()

def get_top_level_stmts(source_code):
    """Parse source and return ordered dict of name -> (stmt, text)."""
    tree = cst.parse_module(source_code)
    stmts = {}
    anon_counter = 0
    for stmt in tree.body:
        name = get_stmt_name(stmt)
        text = tree.code_for_node(stmt).strip()
        if name is None:
            name = f"__anon_{anon_counter}"
            anon_counter += 1
        stmts[name] = {"stmt": stmt, "text": text}
    return stmts

try:
    base_path, ours_path, theirs_path, output_path = sys.argv[1:5]

    with open(base_path, "r") as f:
        base_code = f.read()
    with open(ours_path, "r") as f:
        ours_code = f.read()
    with open(theirs_path, "r") as f:
        theirs_code = f.read()

    base_stmts = get_top_level_stmts(base_code)
    ours_stmts = get_top_level_stmts(ours_code)
    theirs_stmts = get_top_level_stmts(theirs_code)

    merged = []
    seen = set()

    # Process ours declarations
    for name, our_info in ours_stmts.items():
        seen.add(name)
        base_info = base_stmts.get(name)
        their_info = theirs_stmts.get(name)

        if base_info and their_info:
            ours_changed = our_info["text"] != base_info["text"]
            theirs_changed = their_info["text"] != base_info["text"]
            if ours_changed and theirs_changed and our_info["text"] != their_info["text"]:
                print(f"[MERGE-SEMANTIC] libcst conflict on statement: {name}", file=sys.stderr)
                sys.exit(1)
            merged.append(our_info["text"] if ours_changed else their_info["text"])
        elif base_info and not their_info:
            pass  # Deleted on theirs side
        else:
            merged.append(our_info["text"])

    # Add theirs-only declarations
    for name, their_info in theirs_stmts.items():
        if name not in seen:
            merged.append(their_info["text"])

    with open(output_path, "w", newline="\n") as f:
        f.write("\n\n".join(merged) + "\n")

    sys.exit(0)
except Exception as e:
    print(f"[MERGE-SEMANTIC] libcst parse failure: {e}", file=sys.stderr)
    sys.exit(1)
PYMERGE
  return $?
}

# ---------------------------------------------------------------------------
# semantic_merge(base_file, ours_file, theirs_file, output_file)
# AST-aware 3-way merge with diff3 fallback.
# Routes by extension to AST paths or diff3 fallback.
# Returns 0 on clean merge, 1 on conflicts or error.
# Does NOT modify input files.
# ---------------------------------------------------------------------------
semantic_merge() {
  local base_file="$1"
  local ours_file="$2"
  local theirs_file="$3"
  local output_file="$4"

  # Validate arguments
  if [[ -z "$base_file" || -z "$ours_file" || -z "$theirs_file" || -z "$output_file" ]]; then
    printf "ERROR: semantic_merge requires 4 arguments: base ours theirs output\n" >&2
    return 1
  fi

  # Validate input files exist
  if [[ ! -f "$base_file" ]]; then
    printf "ERROR: base file not found: %s\n" "$base_file" >&2
    return 1
  fi
  if [[ ! -f "$ours_file" ]]; then
    printf "ERROR: ours file not found: %s\n" "$ours_file" >&2
    return 1
  fi
  if [[ ! -f "$theirs_file" ]]; then
    printf "ERROR: theirs file not found: %s\n" "$theirs_file" >&2
    return 1
  fi

  # Determine file extension from base file
  local ext=""
  if [[ "$base_file" == *.* ]]; then
    ext="${base_file##*.}"
    ext="${ext,,}"
  fi

  # Route by extension
  case "$ext" in
    ts|tsx)
      if [[ "$TSMORPH_AVAILABLE" == "true" ]]; then
        _semantic_tsmorph_merge "$base_file" "$ours_file" "$theirs_file" "$output_file"
        local ts_rc=$?
        if [[ $ts_rc -eq 0 ]]; then
          return 0
        fi
        printf "[MERGE-SEMANTIC] ts-morph merge failed, falling back to diff3\n" >&2
      fi
      _semantic_diff3_merge "$base_file" "$ours_file" "$theirs_file" "$output_file"
      return $?
      ;;
    py)
      if [[ "$LIBCST_AVAILABLE" == "true" ]]; then
        _semantic_libcst_merge "$base_file" "$ours_file" "$theirs_file" "$output_file"
        local py_rc=$?
        if [[ $py_rc -eq 0 ]]; then
          return 0
        fi
        printf "[MERGE-SEMANTIC] libcst merge failed, falling back to diff3\n" >&2
      fi
      _semantic_diff3_merge "$base_file" "$ours_file" "$theirs_file" "$output_file"
      return $?
      ;;
    *)
      _semantic_diff3_merge "$base_file" "$ours_file" "$theirs_file" "$output_file"
      return $?
      ;;
  esac
}
