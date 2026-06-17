#!/usr/bin/env bash
# lib/dead-code.sh — post-generation dead-code detection (Phase 33 / P3.10).
#
# Sources:
#   arXiv:2604.07291 — "Generated Code Hygiene: Dead Symbols in LLM
#                       Output" — LLM completions leave 12% unused
#                       imports and 7% unused private helpers on
#                       average across HumanEval+.
#   Tooling analogs: knip (TS/JS), vulture (Python), `go vet` + staticcheck,
#                    `cargo udeps` (Rust).
#
# Why in-repo regex heuristics (vs. calling the above tools):
#   1. Runtime availability: quantum-loop runs in a bare Git Bash shell
#      on Windows; we can't assume any of knip/vulture/staticcheck are
#      installed.
#   2. Cheap pre-filter: if we find obvious unused imports on a patch
#      with these regex checks, we don't need to spin up the heavier
#      language tool. If the regex comes back clean we optionally let
#      the caller defer to the proper tool.
#   3. Deterministic: no tool-version skew across developer machines.
#
# Language support (extension-dispatched):
#   .ts .tsx .js .jsx .mjs  — imports + private functions (leading _)
#   .py                     — imports + private functions (leading _)
#   .go                     — imports (subset)
#   .rs                     — use statements
#
# Out of scope (ship tools for these if we need them):
#   C/C++, Java, Kotlin, Scala, Lua, Perl — no dogfood demand yet.
#   Tree-shaking across modules — this is purely per-file.
#   Unused parameters — too noisy without type-aware analysis.
#
# Functions:
#   scan_unused_imports FILE
#     Emits JSON array: [{kind:"import", file, line, name}, ...]
#
#   scan_unused_privates FILE
#     Emits JSON array: [{kind:"private", file, line, name}, ...]
#     Private = name starts with "_" (TS/JS/Py convention).
#
#   scan_dead_code FILE_OR_DIR
#     Emits JSON: {unused_imports: [...], unused_privates: [...],
#                  summary: {total, by_kind: {import: N, private: M}}}
#
#   find_post_commit_dead BASE_SHA HEAD_SHA [PATH_FILTER]
#     Walks `git diff --name-only BASE..HEAD`; scans each live file.
#     Emits an aggregated JSON identical in shape to scan_dead_code.
#
# Library contract: no shell flags at source time; CLI block enables
# strict mode locally.

DEAD_CODE_LIB_DIR="${DEAD_CODE_LIB_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)}"

# _detect_lang(file)
_detect_lang() {
  local f="${1:-}"
  case "$f" in
    *.ts|*.tsx|*.js|*.jsx|*.mjs) printf "ts" ;;
    *.py)                        printf "py" ;;
    *.go)                        printf "go" ;;
    *.rs)                        printf "rs" ;;
    *)                           printf "unknown" ;;
  esac
}

# _extract_ts_imports(file)
# Emit one "line|name" per import binding.
_extract_ts_imports() {
  local f="${1:?file required}"
  awk '
    # default import: import foo from "..."
    match($0, /^[[:space:]]*import[[:space:]]+(type[[:space:]]+)?([A-Za-z_][A-Za-z0-9_]*)[[:space:]]+from[[:space:]]+/, m) {
      printf "%d|%s\n", NR, m[2]; next
    }
    # namespace: import * as foo from "..."
    match($0, /^[[:space:]]*import[[:space:]]+\*[[:space:]]+as[[:space:]]+([A-Za-z_][A-Za-z0-9_]*)/, m) {
      printf "%d|%s\n", NR, m[1]; next
    }
    # named: import { a, b as c, type D } from "..."
    match($0, /^[[:space:]]*import[[:space:]]+(type[[:space:]]+)?\{([^}]+)\}[[:space:]]+from/, m) {
      n = NR
      names = m[2]
      # Strip newlines and split on commas
      gsub(/[[:space:]]+/, " ", names)
      count = split(names, parts, ",")
      for (i = 1; i <= count; i++) {
        tok = parts[i]
        gsub(/^[[:space:]]+|[[:space:]]+$/, "", tok)
        if (tok == "") continue
        # Handle "A as B" -> we track B (the local binding)
        if (match(tok, /[[:space:]]+as[[:space:]]+([A-Za-z_][A-Za-z0-9_]*)/, am)) {
          tok = am[1]
        }
        # Handle "type X" -> we track X
        if (match(tok, /^type[[:space:]]+([A-Za-z_][A-Za-z0-9_]*)/, tm)) {
          tok = tm[1]
        }
        # Only keep things matching an identifier
        if (tok ~ /^[A-Za-z_][A-Za-z0-9_]*$/) {
          printf "%d|%s\n", n, tok
        }
      }
    }
  ' "$f"
}

# _extract_py_imports(file)
_extract_py_imports() {
  local f="${1:?file required}"
  awk '
    # import module           -> binding = module
    # import module as alias  -> binding = alias
    match($0, /^[[:space:]]*import[[:space:]]+([A-Za-z_][A-Za-z0-9_]*)([[:space:]]+as[[:space:]]+([A-Za-z_][A-Za-z0-9_]*))?/, m) {
      binding = (m[3] != "") ? m[3] : m[1]
      printf "%d|%s\n", NR, binding; next
    }
    # from module import foo, bar as baz
    match($0, /^[[:space:]]*from[[:space:]]+[A-Za-z_.][A-Za-z0-9_.]*[[:space:]]+import[[:space:]]+(.*)$/, m) {
      names = m[1]
      # Strip "(" ")" and split on commas
      gsub(/[\(\)]/, "", names)
      count = split(names, parts, ",")
      for (i = 1; i <= count; i++) {
        tok = parts[i]
        gsub(/^[[:space:]]+|[[:space:]]+$/, "", tok)
        if (tok == "" || tok == "*") continue
        if (match(tok, /[[:space:]]+as[[:space:]]+([A-Za-z_][A-Za-z0-9_]*)/, am)) {
          tok = am[1]
        }
        if (tok ~ /^[A-Za-z_][A-Za-z0-9_]*$/) {
          printf "%d|%s\n", NR, tok
        }
      }
    }
  ' "$f"
}

# _extract_go_imports(file)
# Handles both single-line and grouped import blocks.
_extract_go_imports() {
  local f="${1:?file required}"
  awk '
    BEGIN { in_block = 0 }
    /^[[:space:]]*import[[:space:]]+\(/ { in_block = 1; next }
    in_block && /^\)/ { in_block = 0; next }
    {
      line = $0
      # Strip inline // comments so they do not bleed into the package name
      sub(/\/\/.*$/, "", line)
      # Match optional alias then a quoted path.
      # import "pkg"  OR  alias "pkg/path"  OR  _ "pkg"
      if (match(line, /^[[:space:]]*(import[[:space:]]+)?([A-Za-z_][A-Za-z0-9_]*|_|\.)?[[:space:]]*"([^"]+)"/, m)) {
        alias = m[2]
        path  = m[3]
        # Alias "_" is the blank import — intentional side-effect, skip
        if (alias == "_") next
        # If no alias, binding = last path segment
        if (alias == "" || alias == ".") {
          n = split(path, segs, "/")
          binding = segs[n]
        } else {
          binding = alias
        }
        # Only in the import line or grouped block
        if (in_block || match($0, /^[[:space:]]*import[[:space:]]+/)) {
          printf "%d|%s\n", NR, binding
        }
      }
    }
  ' "$f"
}

# _extract_rs_uses(file)
# Very rough — Rust `use` items. Only flags single-identifier uses.
_extract_rs_uses() {
  local f="${1:?file required}"
  awk '
    # use foo::bar::baz;           -> binding = baz
    # use foo::bar::baz as qux;    -> binding = qux
    match($0, /^[[:space:]]*use[[:space:]]+([A-Za-z_][A-Za-z0-9_:]*)[[:space:]]*(as[[:space:]]+([A-Za-z_][A-Za-z0-9_]*))?;/, m) {
      if (m[3] != "") { binding = m[3] }
      else {
        # Take last segment after last ::
        path = m[1]
        n = split(path, segs, "::")
        binding = segs[n]
      }
      printf "%d|%s\n", NR, binding
    }
  ' "$f"
}

# _count_name_in_rest(file, name, import_line)
# Count occurrences of `name` as a whole word anywhere in file EXCEPT
# on the given line. Returns a numeric count.
_count_name_in_rest() {
  local f="$1" name="$2" import_line="$3"
  awk -v target="$name" -v skip="$import_line" '
    BEGIN { c = 0; pat = "\\<" target "\\>" }
    NR != skip { if ($0 ~ pat) c++ }
    END { print c }
  ' "$f"
}

# scan_unused_imports(file)
scan_unused_imports() {
  local f="${1:?file required}"
  [[ -f "$f" ]] || { printf "[]"; return 0; }
  local lang; lang=$(_detect_lang "$f")
  local imports=""
  case "$lang" in
    ts) imports=$(_extract_ts_imports "$f") ;;
    py) imports=$(_extract_py_imports "$f") ;;
    go) imports=$(_extract_go_imports "$f") ;;
    rs) imports=$(_extract_rs_uses "$f") ;;
    *)  printf "[]"; return 0 ;;
  esac
  [[ -z "$imports" ]] && { printf "[]"; return 0; }

  local out='[]'
  local line name
  while IFS='|' read -r line name; do
    [[ -z "$name" ]] && continue
    local cnt
    cnt=$(_count_name_in_rest "$f" "$name" "$line")
    if [[ "$cnt" -eq 0 ]]; then
      out=$(jq -c \
        --arg f "$f" --argjson l "$line" --arg n "$name" \
        '. + [{kind: "import", file: $f, line: $l, name: $n}]' <<< "$out")
    fi
  done <<< "$imports"
  printf '%s' "$out"
}

# _extract_ts_privates(file)
# Emit "line|name" per top-level `function _foo` / `const _foo = `.
_extract_ts_privates() {
  local f="${1:?file required}"
  awk '
    match($0, /^[[:space:]]*(export[[:space:]]+)?function[[:space:]]+(_[A-Za-z_][A-Za-z0-9_]*)/, m) {
      # Even if exported, a name starting with _ is a convention for
      # "internal" — but exported _foo is intentional, so skip those.
      if (m[1] == "") { printf "%d|%s\n", NR, m[2] }
      next
    }
    match($0, /^[[:space:]]*(const|let|var)[[:space:]]+(_[A-Za-z_][A-Za-z0-9_]*)[[:space:]]*[:=]/, m) {
      printf "%d|%s\n", NR, m[2]; next
    }
  ' "$f"
}

# _extract_py_privates(file)
_extract_py_privates() {
  local f="${1:?file required}"
  awk '
    # module-level def _name — not indented
    /^def[[:space:]]+_/ {
      match($0, /def[[:space:]]+(_[A-Za-z_][A-Za-z0-9_]*)/, m)
      printf "%d|%s\n", NR, m[1]
    }
  ' "$f"
}

# scan_unused_privates(file)
scan_unused_privates() {
  local f="${1:?file required}"
  [[ -f "$f" ]] || { printf "[]"; return 0; }
  local lang; lang=$(_detect_lang "$f")
  local privates=""
  case "$lang" in
    ts) privates=$(_extract_ts_privates "$f") ;;
    py) privates=$(_extract_py_privates "$f") ;;
    *)  printf "[]"; return 0 ;;
  esac
  [[ -z "$privates" ]] && { printf "[]"; return 0; }

  local out='[]'
  local line name
  while IFS='|' read -r line name; do
    [[ -z "$name" ]] && continue
    local cnt
    cnt=$(_count_name_in_rest "$f" "$name" "$line")
    if [[ "$cnt" -eq 0 ]]; then
      out=$(jq -c \
        --arg f "$f" --argjson l "$line" --arg n "$name" \
        '. + [{kind: "private", file: $f, line: $l, name: $n}]' <<< "$out")
    fi
  done <<< "$privates"
  printf '%s' "$out"
}

# scan_dead_code(path)
# Walks file or dir; aggregates unused_imports and unused_privates.
scan_dead_code() {
  local path="${1:?path required}"
  local imports='[]' privates='[]'

  if [[ -f "$path" ]]; then
    imports=$(scan_unused_imports "$path")
    privates=$(scan_unused_privates "$path")
  elif [[ -d "$path" ]]; then
    while IFS= read -r f; do
      local imp priv
      imp=$(scan_unused_imports "$f")
      priv=$(scan_unused_privates "$f")
      imports=$(jq -c --argjson a "$imports" --argjson b "$imp" \
        -n '$a + $b')
      privates=$(jq -c --argjson a "$privates" --argjson b "$priv" \
        -n '$a + $b')
    done < <(find "$path" -type f \( \
      -name '*.ts' -o -name '*.tsx' -o -name '*.js' -o -name '*.jsx' \
      -o -name '*.mjs' -o -name '*.py' -o -name '*.go' -o -name '*.rs' \))
  else
    imports='[]'; privates='[]'
  fi

  jq -cn --argjson imp "$imports" --argjson priv "$privates" '
    {
      unused_imports: $imp,
      unused_privates: $priv,
      summary: {
        total: (($imp | length) + ($priv | length)),
        by_kind: {
          import: ($imp | length),
          private: ($priv | length)
        }
      }
    }
  '
}

# find_post_commit_dead(base_sha, head_sha, [path_filter])
# Runs scan_dead_code on files changed between base..head that currently
# exist. Optional path_filter is a grep regex applied to the path list.
find_post_commit_dead() {
  local base="${1:?base_sha required}"
  local head="${2:?head_sha required}"
  local filter="${3:-}"
  # `git diff --name-only` lists added/modified/renamed files. Deleted
  # paths are handled naturally by the [[ -f ]] guard below.
  local files
  files=$(git diff --name-only "$base" "$head" 2>/dev/null || true)
  [[ -z "$files" ]] && { printf '{"unused_imports":[],"unused_privates":[],"summary":{"total":0,"by_kind":{"import":0,"private":0}}}'; return 0; }

  local imports='[]' privates='[]'
  local f
  while IFS= read -r f; do
    [[ -z "$f" ]] && continue
    [[ -f "$f" ]] || continue
    if [[ -n "$filter" ]] && ! grep -qE "$filter" <<< "$f"; then continue; fi
    local imp priv
    imp=$(scan_unused_imports "$f")
    priv=$(scan_unused_privates "$f")
    imports=$(jq -c --argjson a "$imports" --argjson b "$imp" \
      -n '$a + $b')
    privates=$(jq -c --argjson a "$privates" --argjson b "$priv" \
      -n '$a + $b')
  done <<< "$files"

  jq -cn --argjson imp "$imports" --argjson priv "$privates" '
    {
      unused_imports: $imp,
      unused_privates: $priv,
      summary: {
        total: (($imp | length) + ($priv | length)),
        by_kind: {
          import: ($imp | length),
          private: ($priv | length)
        }
      }
    }
  '
}

# dead_code_blocking_verdict(report_json) -> 0 (ok) | 1 (block)
# Track A / Q4 — OPT-IN quality gate. Default OFF: returns 0 (advisory) so the
# documented advisory-by-design behavior is unchanged. Under QL_QUALITY_BLOCKING
# (1|true|yes|on) it returns 1 when the diff introduces HIGH-PRECISION dead code
# — an unused NEW import (.summary.by_kind.import > 0). Unused PRIVATES stay
# advisory even when blocking is on (documented false-positive: a private helper
# exercised only by a later commit's test). report_json is the output of
# find_post_commit_dead / scan_dead_code. Mirrors the QL_VALIDATE_BLOCKING opt-in
# so default pipelines keep the one-retry-budget behavior.
dead_code_blocking_verdict() {
  local report="${1:?dead_code_blocking_verdict: report json required}"
  case "${QL_QUALITY_BLOCKING:-}" in
    1|true|TRUE|yes|on) ;;
    *) return 0 ;;
  esac
  local imports
  imports=$(jq -r '.summary.by_kind.import // 0' <<< "$report" 2>/dev/null)
  [[ "${imports:-0}" -eq 0 ]]
}

# ------------------------------------------------------------------------------
# CLI entry
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  set -euo pipefail
  subcmd="${1:-}"
  shift || true
  case "$subcmd" in
    imports)   scan_unused_imports "$@" ;;
    privates)  scan_unused_privates "$@" ;;
    scan)      scan_dead_code "$@" ;;
    commit)    find_post_commit_dead "$@" ;;
    verdict)   dead_code_blocking_verdict "$@" ;;
    *)
      cat >&2 <<USAGE
Usage: bash lib/dead-code.sh <subcmd> [args...]
  imports  FILE                  — JSON array of unused imports
  privates FILE                  — JSON array of unused private symbols
  scan     FILE_OR_DIR           — aggregated dead-code report
  commit   BASE HEAD [FILTER]    — scan files changed between two SHAs
  verdict  REPORT_JSON           — rc 1 under QL_QUALITY_BLOCKING if unused new imports > 0
USAGE
      exit 2
      ;;
  esac
fi
