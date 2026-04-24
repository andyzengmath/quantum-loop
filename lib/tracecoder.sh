#!/usr/bin/env bash
# lib/tracecoder.sh — Observe-Analyze-Repair failure-triage primitives
# (Phase 27 / P3.8, arXiv:2602.06875).
#
# Source: TraceCoder decomposes the repair loop into three explicit stages:
#   Observe  — collect evidence from the failing state (test output, type
#              errors, file:line markers) in a structured form.
#   Analyze  — reason about the root cause from the observation (an LLM
#              task; this lib prepares the analysis context package).
#   Repair   — apply one minimal change + re-Observe.
#
# The benefit over a single-pass verify: each stage has a clear input and
# output contract, so the LLM reasoning pass operates on parsed structured
# evidence instead of raw logs, and the repair step always re-validates
# with fresh observations. Matches the paper's "evidence-first" principle.
#
# This library ships the deterministic pieces: running the command,
# parsing error markers, packaging the context for LLM analysis. The
# actual analyze step (which must reason) stays in the skill prompt.
#
# Functions:
#   observe CMD [NAME]
#     Runs CMD; captures stdout, stderr, exit, wall-clock duration, and a
#     truncated tail. Emits a JSON object describing the observation.
#
#   extract_error_markers OBSERVATION_JSON
#     Parses the combined output for file:line: error patterns (compiler-
#     typical). Emits a JSON array of {file, line, message}.
#
#   build_analysis_context OBSERVATION_JSON CMD_NAME
#     Packages the observation into a prompt-friendly context block
#     ready to hand to an LLM Analyze stage. Includes: command name,
#     exit code, duration, extracted error markers, tail of output.
#     Output: plain text (markdown-ish) on stdout.
#
#   should_repair OBSERVATION_JSON
#     Exit 0 if the observation indicates a repairable failure (non-zero
#     exit AND at least one recognizable error marker). Exit 1 on pass
#     or unrecognizable failure. Callers use this to decide whether to
#     enter the repair loop vs immediately failing the story.
#
# Library contract: no shell flags at source time; CLI block enables
# strict mode locally.

TRACECODER_LIB_DIR="${TRACECODER_LIB_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)}"

: "${TRACECODER_TAIL_LINES:=40}"  # how many lines of output to retain in the observation tail

# observe(cmd, [name])
# Runs `cmd` via bash -c, captures stdout+stderr into a single stream,
# records the exit code and wall-clock duration. Emits JSON:
#   {
#     "name":     <name or "anonymous">,
#     "cmd":      <literal command string>,
#     "exit":     <integer>,
#     "duration": <seconds>,
#     "lines":    <total-line count of combined output>,
#     "tail":     <last TRACECODER_TAIL_LINES lines>
#   }
observe() {
  local cmd="${1:?observe: command required}"
  local name="${2:-anonymous}"
  local tmp
  tmp=$(mktemp)
  local start end duration exit_code
  start=$(date +%s 2>/dev/null || echo 0)
  bash -c "$cmd" > "$tmp" 2>&1
  exit_code=$?
  end=$(date +%s 2>/dev/null || echo 0)
  duration=$(( end - start ))

  local lines tail_block
  lines=$(wc -l < "$tmp" 2>/dev/null | tr -d '[:space:]')
  [[ -z "$lines" ]] && lines=0
  tail_block=$(tail -n "$TRACECODER_TAIL_LINES" "$tmp" 2>/dev/null)
  rm -f "$tmp"

  jq -cn \
    --arg name "$name" \
    --arg cmd "$cmd" \
    --argjson exit "$exit_code" \
    --argjson duration "$duration" \
    --argjson lines "$lines" \
    --arg tail "$tail_block" \
    '{name: $name, cmd: $cmd, exit: $exit, duration: $duration,
      lines: $lines, tail: $tail}'
}

# extract_error_markers(observation_json)
# Parses the .tail field for file:line: error patterns. Covers common
# compiler / test-runner formats:
#   path/to/file.ts:42:9: error: ...        (tsc, generic)
#   path/to/file.py:18: ...                   (python tracebacks)
#   File "foo.py", line 42, in ...            (python)
#   at .../file.js:100:5                      (node stacks)
#
# Emits a JSON array of {file, line, message}. `message` is the rest of
# the line after the file:line prefix, trimmed.
extract_error_markers() {
  local obs
  obs=$(cat)
  local tail
  tail=$(jq -r '.tail // ""' <<< "$obs")
  [[ -z "$tail" ]] && { printf "[]"; return 0; }

  # Build the JSON array by parsing each line.
  local markers='[]'
  while IFS= read -r line; do
    [[ -z "$line" ]] && continue
    local f ln msg
    f=""
    ln=""
    msg=""
    # Pattern 1: path:LINE:COL: msg  OR  path:LINE: msg
    if [[ "$line" =~ ^([^:]+):([0-9]+):([0-9]+):[[:space:]]*(.*)$ ]]; then
      f="${BASH_REMATCH[1]}"
      ln="${BASH_REMATCH[2]}"
      msg="${BASH_REMATCH[4]}"
    elif [[ "$line" =~ ^([^[:space:]]+):([0-9]+):[[:space:]]*(.*)$ ]]; then
      f="${BASH_REMATCH[1]}"
      ln="${BASH_REMATCH[2]}"
      msg="${BASH_REMATCH[3]}"
    elif [[ "$line" =~ File\ \"([^\"]+)\",\ line\ ([0-9]+) ]]; then
      f="${BASH_REMATCH[1]}"
      ln="${BASH_REMATCH[2]}"
      msg=""
    elif [[ "$line" =~ at[[:space:]].*\(([^:]+):([0-9]+):([0-9]+)\) ]]; then
      f="${BASH_REMATCH[1]}"
      ln="${BASH_REMATCH[2]}"
      msg=""
    fi
    if [[ -n "$f" && -n "$ln" ]]; then
      # Drop obvious non-path noise (e.g., "http://example.com:80" gets f=http)
      # Heuristic: file must contain "/" OR "." (extension)
      if [[ "$f" == *"/"* || "$f" == *"."* ]]; then
        markers=$(jq -c --arg f "$f" --argjson l "$ln" --arg m "$msg" \
          '. + [{file: $f, line: $l, message: $m}]' <<< "$markers")
      fi
    fi
  done <<< "$tail"
  printf '%s' "$markers"
}

# build_analysis_context(observation_json, [extra_hints])
# Emits a markdown-ish plain-text block suitable for handing to an LLM
# Analyze stage. Structure:
#
#   ## Observation: <name>
#   **exit**: <n>   **duration**: <s>s   **lines**: <n>
#   ### Error markers
#   - file:line: message
#   - ...
#   ### Output tail
#   <last N lines>
#
# If no markers parsed, the section reads "(none parsed — rely on tail)".
build_analysis_context() {
  local obs
  obs=$(cat)
  local markers
  markers=$(printf '%s' "$obs" | extract_error_markers)
  local name cmd exit_code duration tail_block lines n_markers
  name=$(jq -r '.name // "anonymous"' <<< "$obs")
  cmd=$(jq -r '.cmd // ""' <<< "$obs")
  exit_code=$(jq -r '.exit // 0' <<< "$obs")
  duration=$(jq -r '.duration // 0' <<< "$obs")
  lines=$(jq -r '.lines // 0' <<< "$obs")
  tail_block=$(jq -r '.tail // ""' <<< "$obs")
  n_markers=$(printf '%s' "$markers" | jq 'length')

  {
    printf "## Observation: %s\n" "$name"
    printf "**cmd**: \`%s\`\n" "$cmd"
    printf "**exit**: %s  **duration**: %ss  **lines**: %s\n\n" "$exit_code" "$duration" "$lines"
    printf "### Error markers (%s)\n" "$n_markers"
    if (( n_markers == 0 )); then
      printf "_(none parsed — rely on output tail)_\n"
    else
      printf '%s' "$markers" | jq -r '.[] | "- `\(.file):\(.line)` — \(.message // "(no message)")"'
    fi
    printf "\n### Output tail\n"
    printf '```\n%s\n```\n' "$tail_block"
  }
}

# should_repair(observation_json)
# Exit 0 (YES, repair) iff exit != 0 AND at least one recognizable error
# marker was parsed. Exit 1 otherwise.
# Rationale: if exit==0 we passed. If exit!=0 but no markers, the failure
# is opaque — the LLM has no grounding, better to mark the story failed
# directly than send it into a low-signal repair loop.
should_repair() {
  local obs
  obs=$(cat)
  local exit_code markers_len
  exit_code=$(jq -r '.exit // 0' <<< "$obs")
  markers_len=$(printf '%s' "$obs" | extract_error_markers | jq 'length')
  if [[ "$exit_code" -ne 0 && "$markers_len" -gt 0 ]]; then
    return 0
  fi
  return 1
}

# ------------------------------------------------------------------------------
# CLI entry
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  set -euo pipefail
  subcmd="${1:-}"
  shift || true
  case "$subcmd" in
    observe)  observe "$@" ;;
    markers)  extract_error_markers ;;
    context)  build_analysis_context "$@" ;;
    should-repair) should_repair ;;
    *)
      cat >&2 <<USAGE
Usage: bash lib/tracecoder.sh <subcmd> [args...]
  observe CMD [NAME]           — run + capture observation as JSON
  markers       < observation  — parse error markers into JSON array
  context [hints] < observation — emit LLM-ready analysis prompt
  should-repair < observation  — exit 0 if repairable failure
USAGE
      exit 2
      ;;
  esac
fi
