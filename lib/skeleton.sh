#!/usr/bin/env bash
# lib/skeleton.sh — skeleton-first / SSAT primitives (Phase 31 / P3.1).
#
# Sources:
#   arXiv:2303.06689 — Self-planning code generation: plan the API
#                      surface (signatures, types, exports) before
#                      generating bodies. Reported +11pp pass-rate on
#                      HumanEval vs. direct generation.
#   arXiv:2307.15337 — Skeleton-of-Thought: generate structure first,
#                      then expand each node. Orthogonal shape, same
#                      principle: shape-before-content.
#
# Why this primitive:
#   Most generation failures in an agent loop are not bug-level (the
#   body is subtly wrong); they are shape-level (the function doesn't
#   exist, or its signature drifted from what the caller expects, or
#   a new interface is missing a declared method). Skeleton-first lets
#   the orchestrator validate the API surface cheaply before burning
#   a retry on body-level work.
#
# Supported languages (extension-dispatched):
#   .ts .tsx .js .jsx .mjs — TypeScript / JavaScript
#   .py                    — Python
#   .go                    — Go
#   .rs                    — Rust
#
# Out of scope (add when we have dogfood pressure):
#   C / C++ — regex fragile on pointer declarations and macros
#   Java   — modifier permutations explode the regex set
#   Lua / Perl / Scala / Kotlin — no current dogfood demand
#
# Functions:
#   extract_skeleton FILE [LANG]
#     Emits a JSON array: [{kind, name, signature, line}, ...]
#     kind ∈ {function, method, class, interface, type, struct, enum, trait}
#
#   skeleton_text FILE [LANG]
#     Emits plain-text skeleton: one signature per line in source order.
#     Not syntactically valid as code — a readable API surface view,
#     suitable for diff-ing. Use extract_skeleton for programmatic use.
#
#   skeleton_diff BEFORE_FILE AFTER_FILE [LANG]
#     Matches entries by (kind, name). Emits JSON:
#       { "added":   [{kind, name, signature, line}, ...],
#         "removed": [{kind, name, signature, line}, ...],
#         "changed": [{kind, name, before_sig, after_sig}] }
#     Rename detection is out of scope (appears as remove + add).
#
# Library contract: no shell flags at source time; CLI block enables
# strict mode locally.

SKELETON_LIB_DIR="${SKELETON_LIB_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)}"

# _detect_lang(file)
# Return a normalized language tag based on the file extension.
# Echoes one of: ts | py | go | rs | unknown
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

# _strip_body_tail(signature)
# Trim the opening-brace / colon that starts a body from a signature
# line so the emitted signature ends at the declaration boundary.
# Example: "function foo(a: int): string {" -> "function foo(a: int): string"
_strip_body_tail() {
  local s="${1:-}"
  # Windows CRLF survives `read -r` — strip trailing CR before matching.
  s="${s%$'\r'}"
  # Drop trailing "{}" (inline empty body), " {" (body start), or ":"
  # (Python sig end). Each strip is conditional on suffix match.
  s="${s%\{\}}"
  s="${s% }"
  s="${s%"{"}"
  s="${s% }"
  s="${s%:}"
  s="${s% }"
  printf '%s' "$s"
}

# _extract_ts(file)
# Emit one JSON object per detected signature for TS/JS source.
_extract_ts() {
  local f="${1:?file required}"
  awk '
    function emit(kind, name, sig, line) {
      gsub(/\\/, "\\\\", sig); gsub(/"/, "\\\"", sig)
      gsub(/\\/, "\\\\", name); gsub(/"/, "\\\"", name)
      printf "{\"kind\":\"%s\",\"name\":\"%s\",\"signature\":\"%s\",\"line\":%d}\n",
        kind, name, sig, line
    }
    # function foo(...)[: T] {
    match($0, /^[[:space:]]*(export[[:space:]]+)?(default[[:space:]]+)?(async[[:space:]]+)?function[[:space:]]+([A-Za-z_][A-Za-z0-9_]*)[[:space:]]*\(/, m) {
      emit("function", m[4], $0, NR); next
    }
    # export const foo = (...) => or export const foo = async (...) =>
    match($0, /^[[:space:]]*(export[[:space:]]+)?(const|let|var)[[:space:]]+([A-Za-z_][A-Za-z0-9_]*)[[:space:]]*[:=][[:space:]]*(async[[:space:]]+)?\(/, m) {
      emit("function", m[3], $0, NR); next
    }
    # class / abstract class Foo
    match($0, /^[[:space:]]*(export[[:space:]]+)?(default[[:space:]]+)?(abstract[[:space:]]+)?class[[:space:]]+([A-Za-z_][A-Za-z0-9_]*)/, m) {
      emit("class", m[4], $0, NR); next
    }
    # interface Foo
    match($0, /^[[:space:]]*(export[[:space:]]+)?interface[[:space:]]+([A-Za-z_][A-Za-z0-9_]*)/, m) {
      emit("interface", m[2], $0, NR); next
    }
    # type Foo = ...
    match($0, /^[[:space:]]*(export[[:space:]]+)?type[[:space:]]+([A-Za-z_][A-Za-z0-9_]*)[[:space:]]*=/, m) {
      emit("type", m[2], $0, NR); next
    }
    # enum Foo
    match($0, /^[[:space:]]*(export[[:space:]]+)?(const[[:space:]]+)?enum[[:space:]]+([A-Za-z_][A-Za-z0-9_]*)/, m) {
      emit("enum", m[3], $0, NR); next
    }
  ' "$f"
}

# _extract_py(file)
_extract_py() {
  local f="${1:?file required}"
  awk '
    function emit(kind, name, sig, line) {
      gsub(/\\/, "\\\\", sig); gsub(/"/, "\\\"", sig)
      printf "{\"kind\":\"%s\",\"name\":\"%s\",\"signature\":\"%s\",\"line\":%d}\n",
        kind, name, sig, line
    }
    # def foo(...) [-> T]:
    match($0, /^[[:space:]]*(async[[:space:]]+)?def[[:space:]]+([A-Za-z_][A-Za-z0-9_]*)[[:space:]]*\(/, m) {
      # Heuristic: if the def is indented, call it a method; otherwise function.
      leading = $0; sub(/[^ \t].*$/, "", leading)
      kind = (length(leading) > 0) ? "method" : "function"
      emit(kind, m[2], $0, NR); next
    }
    # class Foo:  or class Foo(Base):
    match($0, /^[[:space:]]*class[[:space:]]+([A-Za-z_][A-Za-z0-9_]*)/, m) {
      emit("class", m[1], $0, NR); next
    }
  ' "$f"
}

# _extract_go(file)
_extract_go() {
  local f="${1:?file required}"
  awk '
    function emit(kind, name, sig, line) {
      gsub(/\\/, "\\\\", sig); gsub(/"/, "\\\"", sig)
      printf "{\"kind\":\"%s\",\"name\":\"%s\",\"signature\":\"%s\",\"line\":%d}\n",
        kind, name, sig, line
    }
    # func name(...)  or  func (r *Recv) name(...)
    match($0, /^[[:space:]]*func[[:space:]]+(\([^)]*\)[[:space:]]+)?([A-Za-z_][A-Za-z0-9_]*)[[:space:]]*\(/, m) {
      kind = (m[1] != "") ? "method" : "function"
      emit(kind, m[2], $0, NR); next
    }
    # type Name struct | interface | func
    match($0, /^[[:space:]]*type[[:space:]]+([A-Za-z_][A-Za-z0-9_]*)[[:space:]]+(struct|interface|func)/, m) {
      emit(m[2], m[1], $0, NR); next
    }
  ' "$f"
}

# _extract_rs(file)
_extract_rs() {
  local f="${1:?file required}"
  awk '
    function emit(kind, name, sig, line) {
      gsub(/\\/, "\\\\", sig); gsub(/"/, "\\\"", sig)
      printf "{\"kind\":\"%s\",\"name\":\"%s\",\"signature\":\"%s\",\"line\":%d}\n",
        kind, name, sig, line
    }
    # [pub] [async] fn name
    match($0, /^[[:space:]]*(pub([[:space:]]*\([^)]*\))?[[:space:]]+)?(async[[:space:]]+)?fn[[:space:]]+([A-Za-z_][A-Za-z0-9_]*)[[:space:]]*[<(]/, m) {
      emit("function", m[4], $0, NR); next
    }
    # [pub] struct|enum|trait|type Name
    match($0, /^[[:space:]]*(pub([[:space:]]*\([^)]*\))?[[:space:]]+)?(struct|enum|trait|type)[[:space:]]+([A-Za-z_][A-Za-z0-9_]*)/, m) {
      emit(m[3], m[4], $0, NR); next
    }
  ' "$f"
}

# extract_skeleton(file, [lang])
# Dispatches to the language-specific extractor. Emits a JSON array.
extract_skeleton() {
  local f="${1:?file required}"
  local lang="${2:-}"
  [[ -f "$f" ]] || { printf "[]"; return 0; }
  [[ -z "$lang" ]] && lang=$(_detect_lang "$f")

  local items
  case "$lang" in
    ts)      items=$(_extract_ts "$f") ;;
    py)      items=$(_extract_py "$f") ;;
    go)      items=$(_extract_go "$f") ;;
    rs)      items=$(_extract_rs "$f") ;;
    *)       printf "[]"; return 0 ;;
  esac

  # Each line from the extractors is a JSON object. Wrap into an array
  # (handles empty input → []).
  if [[ -z "$items" ]]; then
    printf "[]"
    return 0
  fi
  # Normalize trailing newline: some awk builds emit one per record, some
  # squash the final one. Use jq -s to slurp into an array regardless.
  printf '%s\n' "$items" | jq -sc '
    map({
      kind: .kind,
      name: .name,
      signature: (.signature | ltrimstr(" ") | rtrimstr("\r")),
      line: .line
    })
  '
}

# skeleton_text(file, [lang])
# Emits plain-text view: one raw signature per line in source order,
# with body tails (" {" / trailing ":" ) trimmed for readability.
skeleton_text() {
  local f="${1:?file required}"
  local lang="${2:-}"
  local skel
  skel=$(extract_skeleton "$f" "$lang")
  [[ "$skel" == "[]" ]] && return 0

  printf '%s' "$skel" | jq -r '.[] | .signature' | while IFS= read -r sig; do
    _strip_body_tail "$sig"
    printf '\n'
  done
}

# skeleton_diff(before_file, after_file, [lang])
# Matches by (kind, name). Emits JSON:
#   { "added": [...], "removed": [...], "changed": [{kind, name, before_sig, after_sig}] }
skeleton_diff() {
  local before="${1:?before required}"
  local after="${2:?after required}"
  local lang="${3:-}"
  [[ -z "$lang" && -f "$after" ]] && lang=$(_detect_lang "$after")
  [[ -z "$lang" && -f "$before" ]] && lang=$(_detect_lang "$before")
  local b a
  b=$(extract_skeleton "$before" "$lang")
  a=$(extract_skeleton "$after"  "$lang")

  jq -cn --argjson b "$b" --argjson a "$a" '
    def key(x): x.kind + "|" + x.name;
    ($b | map({(key(.)): .}) | add // {}) as $bi |
    ($a | map({(key(.)): .}) | add // {}) as $ai |
    {
      added:   [ $a[] | select((key(.)) as $k | ($bi[$k] | not)) ],
      removed: [ $b[] | select((key(.)) as $k | ($ai[$k] | not)) ],
      changed: [
        $a[] | select((key(.)) as $k | $bi[$k] != null) |
        . as $aitem |
        ($bi[key($aitem)]) as $bitem |
        select($bitem.signature != $aitem.signature) |
        {kind: $aitem.kind, name: $aitem.name,
         before_sig: $bitem.signature, after_sig: $aitem.signature}
      ]
    }
  '
}

# ------------------------------------------------------------------------------
# CLI entry
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  set -euo pipefail
  subcmd="${1:-}"
  shift || true
  case "$subcmd" in
    extract) extract_skeleton "$@" ;;
    text)    skeleton_text "$@" ;;
    diff)    skeleton_diff "$@" ;;
    *)
      cat >&2 <<USAGE
Usage: bash lib/skeleton.sh <subcmd> [args...]
  extract FILE [LANG]       — JSON array of signatures
  text    FILE [LANG]       — plain-text skeleton (one signature per line)
  diff    BEFORE AFTER [L]  — JSON {added, removed, changed}
USAGE
      exit 2
      ;;
  esac
fi
