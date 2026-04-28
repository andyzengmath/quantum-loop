#!/usr/bin/env bash
# lib/multi-runner-manifest.sh — US-005 (v0.7.4)
#
# Foundation library for multi-runner manifest support. Runner integrations
# (codex, gemini, copilot, etc.) defer to v0.8.0+. This library provides only
# the parse/validate/list primitives so future cycles can build on a stable
# schema.
#
# Functions:
#   parse_manifest <yaml_path>
#     Reads a YAML manifest and emits a JSON envelope on stdout.
#     Backend chain: yq (preferred) -> python3+yaml -> handcrafted shell parser
#     for the trivial 3-field schema. Returns rc=0 on success, rc=1 + stderr
#     ERROR on parse failure.
#
#   validate_manifest <json_envelope>
#     Validates that .runners is an array of objects with required fields
#     name, command, version_flag. Emits stderr WARN per missing field.
#     Returns rc=0 if all entries pass, rc=1 if any entry has missing fields
#     or input is malformed.
#
#   list_runners <json_envelope>
#     Emits one .runners[].name per line on stdout. Returns rc=0.
#
# Library contract: NO shell flags at source time (mirrors lib/handoff.sh,
# lib/finding-persist.sh). CLI mode at file bottom enables strict mode.

if [[ -z "${MULTI_RUNNER_MANIFEST_LIB+x}" ]]; then
readonly MULTI_RUNNER_MANIFEST_LIB=1

# parse_manifest(yaml_path) -> JSON envelope on stdout
parse_manifest() {
  local path="${1:?parse_manifest: yaml_path required}"
  if [[ ! -f "$path" ]]; then
    printf "[manifest] ERROR: file not found: %s\n" "$path" >&2
    return 1
  fi

  # Backend 1: yq (preferred — fast, JSON output)
  if command -v yq >/dev/null 2>&1; then
    local out
    if out=$(yq -o=json '.' "$path" 2>/dev/null) && [[ -n "$out" ]]; then
      printf '%s\n' "$out"
      return 0
    fi
    printf "[manifest] ERROR: yq failed to parse %s\n" "$path" >&2
    return 1
  fi

  # Backend 2: python3 + yaml
  if command -v python3 >/dev/null 2>&1; then
    # Translate Unix-style path to native Windows path on Git Bash / MinGW
    # so Windows python can open it. cygpath -w is the canonical fix.
    local py_path="$path"
    if command -v cygpath >/dev/null 2>&1; then
      py_path=$(cygpath -w "$path" 2>/dev/null || echo "$path")
    fi
    local out
    if out=$(python3 -c '
import sys, json, yaml
try:
    with open(sys.argv[1]) as f: data = yaml.safe_load(f)
    print(json.dumps(data))
except Exception as e:
    sys.stderr.write("[manifest] ERROR: %s\n" % e)
    sys.exit(1)
' "$py_path" 2>&1); then
      printf '%s\n' "$out"
      return 0
    fi
    printf "[manifest] ERROR: python3+yaml failed for %s\n" "$path" >&2
    return 1
  fi

  # Backend 3: handcrafted shell parser for trivial 3-field schema
  # Schema: top-level `runners:` then list of `- name: ... / command: ... / version_flag: ...`
  local in_runners=0
  local current_name="" current_command="" current_version_flag=""
  local first_entry=1
  local result='{"runners":['
  while IFS= read -r line || [[ -n "$line" ]]; do
    line="${line%$'\r'}"
    case "$line" in
      runners:*) in_runners=1 ;;
      "  - name:"*)
        if (( in_runners == 1 )); then
          if [[ -n "$current_name" ]]; then
            (( first_entry == 0 )) && result+=','
            result+='{"name":"'"$current_name"'","command":"'"$current_command"'","version_flag":"'"$current_version_flag"'"}'
            first_entry=0
          fi
          current_name="${line#*name: }"
          current_command=""
          current_version_flag=""
        fi
        ;;
      "    command:"*) current_command="${line#*command: }" ;;
      "    version_flag:"*) current_version_flag="${line#*version_flag: }" ;;
    esac
  done < "$path"
  if [[ -n "$current_name" ]]; then
    (( first_entry == 0 )) && result+=','
    result+='{"name":"'"$current_name"'","command":"'"$current_command"'","version_flag":"'"$current_version_flag"'"}'
  fi
  result+=']}'
  if (( in_runners == 0 )); then
    printf "[manifest] ERROR: shell parser found no runners: section in %s\n" "$path" >&2
    return 1
  fi
  printf '%s\n' "$result"
  return 0
}

# validate_manifest(json_envelope) -> rc=0/1, WARN to stderr per missing field
validate_manifest() {
  local json="${1:?validate_manifest: json_envelope required}"
  if ! printf '%s' "$json" | jq -e '.runners | type == "array"' >/dev/null 2>&1; then
    printf "[manifest] ERROR: input missing .runners array\n" >&2
    return 1
  fi
  local n_missing=0
  local fields_check
  fields_check=$(printf '%s' "$json" | jq -r '
    .runners | to_entries[] |
    [.key,
     (.value.name // ""),
     (.value.command // ""),
     (.value.version_flag // "")
    ] | @tsv
  ')
  while IFS=$'\t' read -r idx name cmd vflag; do
    if [[ -z "$name" ]]; then
      printf "[manifest] WARN: runner index %s missing required field: name\n" "$idx" >&2
      n_missing=$((n_missing + 1))
    fi
    if [[ -z "$cmd" ]]; then
      printf "[manifest] WARN: runner index %s missing required field: command\n" "$idx" >&2
      n_missing=$((n_missing + 1))
    fi
    if [[ -z "$vflag" ]]; then
      printf "[manifest] WARN: runner index %s missing required field: version_flag\n" "$idx" >&2
      n_missing=$((n_missing + 1))
    fi
  done <<< "$fields_check"
  (( n_missing == 0 )) || return 1
  return 0
}

# list_runners(json_envelope) -> one name per line on stdout, rc=0
list_runners() {
  local json="${1:?list_runners: json_envelope required}"
  printf '%s' "$json" | jq -r '.runners[].name'
}

fi  # MULTI_RUNNER_MANIFEST_LIB guard

# CLI entry — only when invoked directly.
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  set -uo pipefail
  subcmd="${1:-}"
  shift || true
  case "$subcmd" in
    parse)    parse_manifest "$@" ;;
    validate) validate_manifest "$@" ;;
    list)     list_runners "$@" ;;
    *)
      cat >&2 <<USAGE
Usage: bash lib/multi-runner-manifest.sh <subcmd> [args...]
  parse    <yaml_path>      -- read YAML, emit JSON envelope
  validate <json_envelope>  -- check required fields, rc=0/1
  list     <json_envelope>  -- emit one runner name per line
USAGE
      exit 2
      ;;
  esac
fi
