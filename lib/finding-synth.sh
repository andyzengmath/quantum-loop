#!/usr/bin/env bash
# lib/finding-synth.sh -- pre-impl-review FINDING-block parser (v0.7.0 / G12).
#
# Parses spec-reviewer's stderr stream of FINDING_START..FINDING_END blocks
# (emitted by design-review / prd-review / plan-review modes in
# agents/spec-reviewer.md) into a structured JSON array. Downstream tooling
# (US-002 lib/finding-persist.sh) consumes this output to write per-run
# snapshots and an aggregate ledger.
#
# Block shape (one block per finding):
#
#   FINDING_START
#     category: <category-name>
#     severity: critical | high | medium | low
#     file: <path>
#     line: <int, 0 if doc-level>
#     evidence: <verbatim quote or section name>
#     suggestion: <one-line fix>
#   FINDING_END
#
# Functions:
#   parse_findings STAGE
#     Reads stdin, accumulates lines between FINDING_START / FINDING_END
#     markers, parses key:value pairs, emits JSON array of
#     {category,severity,file,line,evidence,suggestion} objects on stdout.
#     Malformed blocks (FINDING_START with no FINDING_END before next
#     FINDING_START or EOF) emit a one-line stderr WARN and are dropped;
#     remaining well-formed blocks still parse.
#
#   summarize_findings STAGE FINDINGS_JSON
#     Pure: takes the parser's array and emits
#     {stage,count,by_severity:{critical,high,medium,low},by_category:{...}}.
#
#   format_summary_line SUMMARY_JSON
#     Pure: emits "[REVIEW] <stage>-review complete: <N> findings (<crit>/<high>/<med>/<low>)"
#     when count>0, or "[REVIEW] <stage>-review complete: 0 findings (clean)"
#     when count==0. Matches the existing spec-reviewer output convention.
#
# Library contract: no shell flags at source time; strict mode only in
# the CLI-entry block at file bottom (mirrors lib/handoff.sh).
#
# Platform note (CLAUDE.md): heredoc-fed input on Git Bash / MSYS may
# carry CRLF line endings. The parser strips trailing \r defensively
# from every line before key:value extraction.

# Guard against double-source.
if [[ -z "${FINDING_SYNTH_LIB+x}" ]]; then
readonly FINDING_SYNTH_LIB=1

# parse_findings(stage)
# Reads stdin; emits JSON array on stdout. Stage argument is currently
# advisory (used by callers for routing); unknown stages are accepted
# without error.
parse_findings() {
  local stage="${1:-unknown}"

  # Accumulator for well-formed blocks. Each entry is one finding object.
  local findings='[]'

  # Per-block state. Empty when not inside a block.
  local in_block=0
  local cur_category="" cur_severity="" cur_file="" cur_line="" cur_evidence="" cur_suggestion=""
  local block_lineno=0   # line of the most recent FINDING_START (for warnings)
  local lineno=0

  local line key val
  while IFS= read -r line || [[ -n "$line" ]]; do
    lineno=$((lineno + 1))
    # Defensive CRLF strip per CLAUDE.md Platform Notes.
    line="${line%$'\r'}"

    # Strip leading whitespace for marker detection AND key:value parsing.
    local trimmed="${line#"${line%%[![:space:]]*}"}"
    case "$trimmed" in
      "FINDING_START")
        if [[ "$in_block" -eq 1 ]]; then
          # Previous block never closed -- warn, drop, restart.
          printf "WARN: malformed FINDING block opened at line %d (no FINDING_END before next FINDING_START); dropping\n" \
            "$block_lineno" >&2
        fi
        in_block=1
        block_lineno=$lineno
        cur_category=""; cur_severity=""; cur_file=""
        cur_line=""; cur_evidence=""; cur_suggestion=""
        ;;
      "FINDING_END")
        if [[ "$in_block" -ne 1 ]]; then
          # Stray END marker -- warn and continue.
          printf "WARN: stray FINDING_END at line %d (no matching FINDING_START); ignoring\n" \
            "$lineno" >&2
          continue
        fi
        # Append the accumulated block.
        findings=$(jq -c \
          --arg cat "$cur_category" \
          --arg sev "$cur_severity" \
          --arg file "$cur_file" \
          --arg line "$cur_line" \
          --arg evidence "$cur_evidence" \
          --arg suggestion "$cur_suggestion" \
          '. + [{
            category: $cat,
            severity: $sev,
            file: $file,
            line: $line,
            evidence: $evidence,
            suggestion: $suggestion
          }]' <<< "$findings")
        in_block=0
        ;;
      *)
        [[ "$in_block" -eq 1 ]] || continue
        # Need at least one ':' to be a key:value (trimmed already computed above).
        case "$trimmed" in
          *:*) ;;
          *) continue ;;
        esac
        key="${trimmed%%:*}"
        val="${trimmed#*:}"
        # Strip leading single space after the colon.
        val="${val# }"
        case "$key" in
          category)   cur_category="$val" ;;
          severity)   cur_severity="$val" ;;
          file)       cur_file="$val" ;;
          line)       cur_line="$val" ;;
          evidence)   cur_evidence="$val" ;;
          suggestion) cur_suggestion="$val" ;;
        esac
        ;;
    esac
  done

  # If EOF arrived inside an open block, warn and drop.
  if [[ "$in_block" -eq 1 ]]; then
    printf "WARN: malformed FINDING block opened at line %d (no FINDING_END before EOF); dropping\n" \
      "$block_lineno" >&2
  fi

  printf '%s' "$findings"
}

# summarize_findings(stage, findings_json)
# Pure: counts and groups. Stage is echoed back into the summary.
summarize_findings() {
  local stage="${1:?summarize_findings: stage required}"
  local findings="${2:?summarize_findings: findings_json required}"

  jq -c --arg stage "$stage" '
    {
      stage: $stage,
      count: length,
      by_severity: {
        critical: ([.[] | select(.severity == "critical")] | length),
        high:     ([.[] | select(.severity == "high")]     | length),
        medium:   ([.[] | select(.severity == "medium")]   | length),
        low:      ([.[] | select(.severity == "low")]      | length)
      },
      by_category: (
        reduce .[] as $f ({}; .[$f.category] = ((.[$f.category] // 0) + 1))
      )
    }
  ' <<< "$findings"
}

# format_summary_line(summary_json)
# Pure: builds the [REVIEW] <stage>-review complete... line. Mirrors the
# existing spec-reviewer convention (see agents/spec-reviewer.md mode
# sections): "(clean)" for zero findings; "(<crit>/<high>/<med>/<low>)"
# otherwise.
format_summary_line() {
  local summary="${1:?format_summary_line: summary_json required}"
  local stage count crit high med low
  stage=$(jq -r '.stage'                <<< "$summary")
  count=$(jq -r '.count'                <<< "$summary")
  crit=$(jq -r '.by_severity.critical'  <<< "$summary")
  high=$(jq -r '.by_severity.high'      <<< "$summary")
  med=$(jq  -r '.by_severity.medium'    <<< "$summary")
  low=$(jq  -r '.by_severity.low'       <<< "$summary")

  if [[ "$count" -eq 0 ]]; then
    printf "[REVIEW] %s-review complete: 0 findings (clean)" "$stage"
  else
    printf "[REVIEW] %s-review complete: %d findings (%d/%d/%d/%d)" \
      "$stage" "$count" "$crit" "$high" "$med" "$low"
  fi
}

fi  # FINDING_SYNTH_LIB guard

# ------------------------------------------------------------------------------
# CLI entry. Strict mode only here; library callers source the file above
# without inheriting flags.
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  set -euo pipefail
  subcmd="${1:-}"
  shift || true
  case "$subcmd" in
    parse)
      # parse STAGE  -- reads stdin, emits JSON array.
      parse_findings "${1:-unknown}"
      printf "\n"
      ;;
    summarize)
      # summarize STAGE FINDINGS_JSON
      summarize_findings "${1:?stage required}" "${2:?findings_json required}"
      printf "\n"
      ;;
    format)
      # format SUMMARY_JSON
      format_summary_line "${1:?summary_json required}"
      printf "\n"
      ;;
    *)
      cat >&2 <<USAGE
Usage: bash lib/finding-synth.sh <subcmd> [args...]
  parse STAGE                       -- read stdin FINDING blocks -> JSON array
  summarize STAGE FINDINGS_JSON     -- counts + per-severity / per-category buckets
  format SUMMARY_JSON               -- "[REVIEW] <stage>-review complete: ..." line
USAGE
      exit 2
      ;;
  esac
fi
