#!/usr/bin/env bash
# lib/finding-persist.sh -- pre-impl-review persistence layer (v0.7.0 / G13).
#
# Companion to lib/finding-synth.sh (US-001). Persists each parsed-summary
# pair as:
#   1. .handoffs/<stage>-review-findings.json  -- per-run snapshot,
#      overwritten on each invocation of the same stage.
#   2. metrics/pre-impl-review-findings.csv     -- append-only ledger
#      with header written once on first call.
#
# Snapshot schema:
#   {
#     "stage":       "design" | "prd" | "plan",
#     "timestamp":   "<ISO 8601 UTC>",
#     "source_path": "<reviewed file path>",
#     "summary":     {stage,count,by_severity,by_category},
#     "findings":    [<parser output array>]
#   }
#
# CSV schema:
#   timestamp,stage,source_path,count,critical,high,medium,low
#
# Functions:
#   persist_review_findings STAGE SOURCE_PATH SUMMARY_JSON FINDINGS_JSON [REPO_ROOT]
#     Validates STAGE against the {design,prd,plan} enum, writes the snapshot,
#     appends to the CSV (with header on first write). Auto-creates .handoffs/
#     and metrics/ if missing. Append uses flock -x when available; falls
#     back to atomic rename-replace otherwise.
#
#   read_review_findings STAGE [REPO_ROOT]
#     Reads the snapshot for STAGE; emits the JSON object on stdout. If the
#     snapshot file is missing, emits "{}" and writes a one-line WARN to
#     stderr. Never fails on missing-file.
#
# Library contract: no shell flags at source time; strict mode only in the
# CLI-entry block at bottom (mirrors lib/handoff.sh).

# Guard against double-source.
if [[ -z "${FINDING_PERSIST_LIB+x}" ]]; then
readonly FINDING_PERSIST_LIB=1

# Stage enum (closed set per US-002 contract).
if [[ -z "${FINDING_PERSIST_STAGES+x}" ]]; then
readonly FINDING_PERSIST_STAGES=("design" "prd" "plan")
fi

# _is_valid_stage(stage)  -> 0/1 exit code.
_is_valid_stage() {
  local s="${1:-}"
  local x
  for x in "${FINDING_PERSIST_STAGES[@]}"; do
    [[ "$s" == "$x" ]] && return 0
  done
  return 1
}

# _ts() -- emit ISO-8601 UTC timestamp.
_ts() {
  date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date -u
}

# _csv_escape(field)
# CSV field escaper. Quote and double-internal-quotes IF the field contains
# comma, quote, or newline. Otherwise emit as-is.
_csv_escape() {
  local f="${1:-}"
  case "$f" in
    *,* | *\"* | *$'\n'*)
      # Replace " with ""; wrap in quotes.
      f="${f//\"/\"\"}"
      printf '"%s"' "$f"
      ;;
    *)
      printf '%s' "$f"
      ;;
  esac
}

# _csv_append_locked(csv_path, row, [header])
# Append a row to the CSV file under flock -x when available; fall back to
# tmpfile + atomic rename-replace otherwise. The optional `header` is
# written iff the file is missing or empty AT THE MOMENT THE LOCK IS HELD —
# this keeps the header check and write inside the same critical section
# as the row append, so concurrent writers cannot truncate each other's
# rows by re-writing the header outside the lock (v0.7.0 post-merge fix).
_csv_append_locked() {
  local csv="${1:?csv path required}"
  local row="${2:?row required}"
  local header="${3:-}"
  if command -v flock >/dev/null 2>&1; then
    # flock acquires an exclusive lock on the FD; safe across concurrent
    # writers on POSIX-compliant filesystems. Both the header bootstrap
    # and the row append run under this lock.
    (
      flock -x 200 || return 1
      [[ -n "$header" && ! -s "$csv" ]] && printf '%s\n' "$header" >> "$csv"
      printf '%s\n' "$row" >> "$csv"
    ) 200>>"$csv"
  else
    # Fallback: copy → append → rename. Not concurrent-safe but the only
    # option on systems without flock (older Git Bash, BusyBox). When the
    # CSV is missing or empty we seed it with `header` instead of cp'ing
    # an empty source. All disk operations are guarded with || return 1
    # so a partial failure cleans up the tmp file rather than silently
    # promoting a corrupt CSV.
    local tmp
    tmp=$(mktemp "${csv}.XXXXXX") || return 1
    if [[ -s "$csv" ]]; then
      cp "$csv" "$tmp" || { rm -f "$tmp"; return 1; }
    elif [[ -n "$header" ]]; then
      printf '%s\n' "$header" > "$tmp" || { rm -f "$tmp"; return 1; }
    fi
    printf '%s\n' "$row" >> "$tmp" || { rm -f "$tmp"; return 1; }
    mv -f "$tmp" "$csv" || { rm -f "$tmp"; return 1; }
  fi
}

# persist_review_findings(stage, source_path, summary_json, findings_json, [repo_root])
persist_review_findings() {
  local stage="${1:?persist_review_findings: stage required}"
  local source_path="${2:?persist_review_findings: source_path required}"
  local summary="${3:?persist_review_findings: summary_json required}"
  local findings="${4:?persist_review_findings: findings_json required}"
  local root="${5:-.}"
  root="${root%/}"

  # Validate stage enum.
  if ! _is_valid_stage "$stage"; then
    printf "ERR: persist_review_findings: invalid stage '%s' (must be one of: %s)\n" \
      "$stage" "${FINDING_PERSIST_STAGES[*]}" >&2
    return 2
  fi

  local handoffs_dir="$root/.handoffs"
  local metrics_dir="$root/metrics"
  local snap="$handoffs_dir/${stage}-review-findings.json"
  local csv="$metrics_dir/pre-impl-review-findings.csv"

  mkdir -p "$handoffs_dir" "$metrics_dir"

  local ts
  ts=$(_ts)

  # Build snapshot. Use jq to ensure clean JSON regardless of shell-escape
  # quirks in source_path / findings. If jq fails (malformed --argjson
  # input), abort the whole call: do NOT write a CSV row that has no
  # corroborating snapshot file (v0.7.0 post-merge fix).
  local snap_tmp
  snap_tmp=$(mktemp "${snap}.XXXXXX") || return 1
  if ! jq -nc \
      --arg stage "$stage" \
      --arg ts "$ts" \
      --arg src "$source_path" \
      --argjson summary "$summary" \
      --argjson findings "$findings" \
      '{stage: $stage, timestamp: $ts, source_path: $src, summary: $summary, findings: $findings}' \
      > "$snap_tmp"; then
    rm -f "$snap_tmp"
    printf "ERR: persist_review_findings: jq failed building snapshot for stage '%s'\n" "$stage" >&2
    return 1
  fi
  # Atomic rename — readers never see a half-written file.
  mv -f "$snap_tmp" "$snap" || { rm -f "$snap_tmp"; return 1; }

  # Extract summary fields for the CSV row.
  local count crit high med low
  count=$(jq -r '.count // 0'                  <<< "$summary")
  crit=$(jq  -r '.by_severity.critical // 0'   <<< "$summary")
  high=$(jq  -r '.by_severity.high // 0'       <<< "$summary")
  med=$(jq   -r '.by_severity.medium // 0'     <<< "$summary")
  low=$(jq   -r '.by_severity.low // 0'        <<< "$summary")

  # Build the row with proper escaping of source_path. The CSV header is
  # bootstrapped INSIDE the flock by _csv_append_locked (no longer here —
  # see v0.7.0 post-merge fix in _csv_append_locked).
  local csv_header='timestamp,stage,source_path,count,critical,high,medium,low'
  local row
  row="${ts},${stage},$(_csv_escape "$source_path"),${count},${crit},${high},${med},${low}"
  _csv_append_locked "$csv" "$row" "$csv_header"

  # Echo the snapshot path so callers can log/chain.
  printf '%s\n' "$snap"
}

# read_review_findings(stage, [repo_root])
# Emits the snapshot JSON on stdout, or "{}" with stderr WARN if missing.
read_review_findings() {
  local stage="${1:?read_review_findings: stage required}"
  local root="${2:-.}"
  root="${root%/}"

  if ! _is_valid_stage "$stage"; then
    printf "WARN: read_review_findings: invalid stage '%s' — emitting {}\n" "$stage" >&2
    printf '{}'
    return 0
  fi

  local snap="$root/.handoffs/${stage}-review-findings.json"
  if [[ ! -f "$snap" ]]; then
    printf "WARN: read_review_findings: missing snapshot at %s — emitting {}\n" "$snap" >&2
    printf '{}'
    return 0
  fi

  cat "$snap"
}

fi  # FINDING_PERSIST_LIB guard

# ------------------------------------------------------------------------------
# CLI entry. Strict mode only here.
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  set -euo pipefail
  subcmd="${1:-}"
  shift || true
  case "$subcmd" in
    persist)
      # persist STAGE SRC SUMMARY_JSON FINDINGS_JSON [REPO_ROOT]
      persist_review_findings "$@"
      ;;
    read)
      # read STAGE [REPO_ROOT]
      read_review_findings "$@"
      printf '\n'
      ;;
    *)
      cat >&2 <<USAGE
Usage: bash lib/finding-persist.sh <subcmd> [args...]
  persist STAGE SRC SUMMARY_JSON FINDINGS_JSON [REPO_ROOT]
                                    -- write snapshot + append CSV row
  read    STAGE [REPO_ROOT]         -- read snapshot, emit "{}" if missing
USAGE
      exit 2
      ;;
  esac
fi
