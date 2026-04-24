#!/usr/bin/env bash
# lib/constitution.sh — constitutional constraint checks (Phase 22 / P3.11).
#
# Source: arXiv:2602.02584 (Constitutional SDD) reports 73% security-defect
# reduction when spec-driven-development pipelines enforce a per-project
# "constitution" of inviolable rules — distinct from per-story acceptance
# criteria. Rules are universal: no hardcoded secrets, no SQL injection
# via string interpolation, every external input is validated, etc.
#
# This library ships deterministic regex checks for the machine-checkable
# subset. LLM-driven rules (e.g., "immutable data structures", "single-
# responsibility functions") are delegated to spec-reviewer and deep-review
# prompts per the paper's two-tier model.
#
# Functions:
#   load_constitution QUANTUM_JSON
#     Reads quantum.json.constitution[] into the global CONSTITUTION array.
#     Empty array if field absent (backward-compat).
#   check_no_secrets DIFF_FILE
#     grep for hardcoded API keys, tokens, passwords in added lines.
#     Emits finding lines: "no-secrets|file:line|excerpt".
#   check_sql_injection DIFF_FILE
#     grep for raw string interpolation into SQL contexts. Heuristic.
#   check_input_validation DIFF_FILE
#     grep for user-input handlers (req.body, argv, stdin) without
#     nearby validation calls (validate, parse, schema, assert).
#   check_commit_integrity FILE_LIST
#     flag mutations to known-immutable tables (migrations/schema.prisma
#     deletions, .env.example deletions).
#   enforce_constitution QUANTUM_JSON DIFF_FILE
#     Runs every check whose rule-id is active in the loaded constitution.
#     Emits a compact JSON array of findings. Severity and rule metadata
#     come from the constitution entry.
#
# Library contract (matches every prior lib since Phase 5): no shell flags
# at source time; CLI-entry block enables strict mode locally.

CONSTITUTION_LIB_DIR="${CONSTITUTION_LIB_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)}"

# Global — populated by load_constitution
CONSTITUTION_ACTIVE_RULES=""

# Canonical rule catalog. Each rule has an id, severity, and a checker
# function name. Callers can enable a subset via quantum.json.constitution.
if [[ -z "${CONSTITUTION_RULES+x}" ]]; then
readonly -A CONSTITUTION_RULES=(
  [no-secrets]="critical:check_no_secrets:hardcoded credentials or API keys"
  [no-sql-injection]="critical:check_sql_injection:raw string interpolation into SQL contexts"
  [input-validation]="high:check_input_validation:user-input handler without validation"
  [immutable-schema]="high:check_commit_integrity:destructive change to schema/migrations"
)
fi

# load_constitution(quantum_json_path)
# Reads .constitution[] array from quantum.json and stores rule IDs (space
# -separated) in CONSTITUTION_ACTIVE_RULES. Missing field => empty string.
load_constitution() {
  local qj="${1:?load_constitution: quantum.json path required}"
  if [[ ! -f "$qj" ]]; then
    CONSTITUTION_ACTIVE_RULES=""
    return 0
  fi
  # Accept array of strings (rule IDs) or array of objects with .rule field.
  CONSTITUTION_ACTIVE_RULES=$(jq -r '
    .constitution // [] |
    map(if type == "string" then . else .rule // empty end) |
    join(" ")
  ' "$qj" 2>/dev/null || echo "")
}

# _scan_added_lines(diff_file, pattern, [case_flag])
# Helper: runs grep over the added-line bodies of a unified diff (drops the
# leading "+" and skips +++ headers). Emits "file|line|excerpt" records —
# pipe-separated so enforce_constitution can split cleanly with IFS='|'.
_scan_added_lines() {
  local diff_file="${1:?diff_file required}"
  local pattern="${2:?pattern required}"
  local case_flag="${3:-}"
  local grep_opts=(-n -E)
  [[ "$case_flag" == "-i" ]] && grep_opts+=(-i)
  local cur_file=""
  local cur_line=0
  while IFS= read -r line; do
    if [[ "$line" == "+++ b/"* ]]; then
      cur_file="${line#+++ b/}"
      continue
    fi
    if [[ "$line" == "@@ "* ]]; then
      local tmp="${line#@@ *+}"
      cur_line="${tmp%%,*}"
      cur_line="${cur_line%% *}"
      continue
    fi
    if [[ "$line" == +* && "$line" != "+++"* ]]; then
      local content="${line#+}"
      if printf '%s' "$content" | grep "${grep_opts[@]}" -- "$pattern" &>/dev/null; then
        # Escape pipes in excerpt so the field-split downstream is clean
        local excerpt="${content//|/\/}"
        printf '%s|%s|%s\n' "$cur_file" "$cur_line" "${excerpt:0:80}"
      fi
      cur_line=$((cur_line + 1))
    fi
  done < "$diff_file"
}

# check_no_secrets(diff_file)
# Heuristic regex for hardcoded credentials on added lines:
#   - API keys: alphanumeric runs >= 20 chars next to "key", "secret", "token"
#   - Common provider prefixes (sk-, pk_, ghp_, AKIA, xoxb-, AIza, ya29.)
#   - Bearer tokens, basic auth strings
# Emits "no-secrets|file:line|excerpt" findings to stdout.
check_no_secrets() {
  local diff_file="${1:?diff_file required}"
  [[ -f "$diff_file" ]] || return 0
  local patterns=(
    # Provider prefixes (high-precision). Character classes allow [_.-] to
    # cover sk-live_..., ghp_..., etc.
    '(sk-[A-Za-z0-9_.-]{16,}|pk_(live|test)_[A-Za-z0-9_.-]{20,}|ghp_[A-Za-z0-9_.-]{20,}|AKIA[A-Z0-9]{12,}|xoxb-[A-Za-z0-9_.-]{20,}|AIza[A-Za-z0-9_.-]{20,})'
    # Bearer tokens assigned to a variable
    '(Bearer [A-Za-z0-9._\-]{20,})'
    # Generic: (password|secret|api_?key|token)\s*[:=]\s*"[^"]{16,}"
    '(password|passwd|secret|api_?key|apikey|token|access_?token)[[:space:]]*[:=][[:space:]]*["'\''][A-Za-z0-9._+/=\-]{16,}["'\'']'
  )
  # Collect from all patterns then dedup — a single line can match multiple
  # regex families (e.g., a ghp_ token also matches the generic token=... pattern)
  # and we only want one finding per line.
  local accumulated=""
  for p in "${patterns[@]}"; do
    local out
    out=$(_scan_added_lines "$diff_file" "$p" "-i") || true
    [[ -n "$out" ]] && accumulated+="${out}"$'\n'
  done
  [[ -n "$accumulated" ]] && \
    printf '%s' "$accumulated" | sort -u | grep -v '^$' | sed 's/^/no-secrets|/'
}

# check_sql_injection(diff_file)
# Flag raw string-interpolation into strings that look like SQL queries.
# Patterns (lowercase-matching):
#   SELECT/INSERT/UPDATE/DELETE with ${var} or " + var + " concatenation.
check_sql_injection() {
  local diff_file="${1:?diff_file required}"
  [[ -f "$diff_file" ]] || return 0
  # ${VAR} inside a string that also contains an SQL keyword
  _scan_added_lines "$diff_file" '(select|insert|update|delete|from|where).*\$\{[A-Za-z_]' "-i" \
    | sed 's/^/no-sql-injection|/'
  # "..." + var + "..." classic concat pattern with SQL keyword
  _scan_added_lines "$diff_file" '"[^"]*(select|insert|update|delete)[^"]*"[[:space:]]*\+' "-i" \
    | sed 's/^/no-sql-injection|/'
}

# check_input_validation(diff_file)
# Heuristic: added lines that read request body/query/params/argv/stdin
# without a nearby validation/parse/schema call. We report every handler
# read; caller filters false positives via the actionability gate.
check_input_validation() {
  local diff_file="${1:?diff_file required}"
  [[ -f "$diff_file" ]] || return 0
  # Common entry points for external input across JS/Python/Go
  local entrypoints='req\.(body|query|params)|request\.(json|form|args)|process\.argv|sys\.argv|os\.Args|\$ARGV|input\('
  _scan_added_lines "$diff_file" "$entrypoints" "" \
    | sed 's/^/input-validation|/'
}

# check_commit_integrity(file_list)
# file_list is a file with one path per line. Flag:
#   - deleted migration files
#   - deleted .env.example
#   - deleted schema.prisma / schema.sql / *.sql migration
check_commit_integrity() {
  local flist="${1:?file_list required}"
  [[ -f "$flist" ]] || return 0
  local pattern='(migrations?/[0-9]|\.env\.example|schema\.(prisma|sql)|migrations?/.*\.sql)$'
  while IFS= read -r f; do
    [[ -z "$f" ]] && continue
    if [[ "$f" =~ $pattern ]]; then
      printf 'immutable-schema|%s|deleted/renamed schema-critical file\n' "$f"
    fi
  done < "$flist"
}

# enforce_constitution(quantum_json, diff_file, [deleted_files_list])
# Runs every rule named in quantum.json.constitution[]. Emits a compact JSON
# array of findings. Each finding: {rule, severity, description, file,
# line, excerpt}.
enforce_constitution() {
  local qj="${1:?quantum.json required}"
  local diff_file="${2:?diff_file required}"
  local deleted_list="${3:-}"
  load_constitution "$qj"
  [[ -z "$CONSTITUTION_ACTIVE_RULES" ]] && { printf "[]"; return 0; }

  local findings='[]'
  local rule
  for rule in $CONSTITUTION_ACTIVE_RULES; do
    local meta="${CONSTITUTION_RULES[$rule]:-}"
    [[ -z "$meta" ]] && {
      printf "[CONSTITUTION] WARN: unknown rule '%s' in quantum.json.constitution\n" "$rule" >&2
      continue
    }
    local severity="${meta%%:*}"
    local rest="${meta#*:}"
    local checker="${rest%%:*}"
    local description="${rest#*:}"

    local raw=""
    case "$checker" in
      check_no_secrets)      raw=$(check_no_secrets "$diff_file") ;;
      check_sql_injection)   raw=$(check_sql_injection "$diff_file") ;;
      check_input_validation) raw=$(check_input_validation "$diff_file") ;;
      check_commit_integrity)
        [[ -n "$deleted_list" ]] && raw=$(check_commit_integrity "$deleted_list") ;;
    esac

    [[ -z "$raw" ]] && continue
    # Raw format: "rule|file|line|excerpt"
    while IFS='|' read -r r f line excerpt; do
      [[ -z "$r" ]] && continue
      # Guard: line must be numeric, else coerce to 0 for jq
      [[ "$line" =~ ^[0-9]+$ ]] || line=0
      findings=$(jq -c \
        --arg r "$rule" --arg s "$severity" --arg d "$description" \
        --arg f "$f" --argjson l "$line" --arg e "$excerpt" \
        '. + [{rule: $r, severity: $s, description: $d, file: $f, line: $l, excerpt: $e}]' \
        <<< "$findings")
    done <<< "$raw"
  done
  printf "%s" "$findings"
}

# ------------------------------------------------------------------------------
# CLI entry
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  set -euo pipefail
  subcmd="${1:-}"
  shift || true
  case "$subcmd" in
    load)      load_constitution "$@"; printf '%s\n' "$CONSTITUTION_ACTIVE_RULES" ;;
    secrets)   check_no_secrets "$@" ;;
    sqli)      check_sql_injection "$@" ;;
    input)     check_input_validation "$@" ;;
    integrity) check_commit_integrity "$@" ;;
    enforce)   enforce_constitution "$@" ;;
    *)
      cat >&2 <<USAGE
Usage: bash lib/constitution.sh <subcmd> [args...]
  load QUANTUM_JSON                       — print active rule IDs
  secrets DIFF_FILE                       — scan for hardcoded credentials
  sqli DIFF_FILE                          — scan for SQL injection
  input DIFF_FILE                         — scan for unvalidated input reads
  integrity FILE_LIST                     — scan for schema-critical deletions
  enforce QUANTUM_JSON DIFF_FILE [DELETED_LIST] — run all active rules, emit JSON
USAGE
      exit 2
      ;;
  esac
fi
