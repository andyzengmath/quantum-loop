#!/usr/bin/env bash
# lib/handoff.sh — stage-handoff document protocol (P2.3, OMC Team pattern).
#
# Each pipeline stage (brainstorm → spec → plan → execute → review → verify)
# writes a handoff document when it finishes. The next stage reads ALL
# prior handoffs before its first response. Handoffs survive context
# compaction — they're a durable audit trail of decisions the LLM made
# across a pipeline run.
#
# Storage: .handoffs/<stage>.md. Repo-relative by default.
#
# Shape (markdown with YAML frontmatter):
#
#   ---
#   stage: brainstorm
#   timestamp: 2026-04-23T10:00:00Z
#   sha: <HEAD sha at write time>
#   decided:    ["use existing auth middleware", "scope to v1 features only"]
#   rejected:   ["build new auth", "include v2 notifications"]
#   risks:      ["Windows long-paths", "OneDrive file locking"]
#   files:      ["docs/plans/2026-04-23-feature-design.md"]
#   remaining:  ["choose DB migration approach", "decide on telemetry"]
#   ---
#
#   <freeform notes>
#
# Functions:
#   write_handoff STAGE JSON_BODY [repo_root]
#     — writes a markdown+frontmatter file. JSON_BODY supplies the
#       decided/rejected/risks/files/remaining arrays.
#   read_handoff STAGE [repo_root]
#     — emits just the frontmatter as JSON, or "{}" if missing.
#   read_all_handoffs [repo_root]
#     — emits JSON array of every handoff present, sorted by stage order.
#   list_prior_stages CURRENT_STAGE
#     — echoes space-separated list of stages that should have been
#       consumed before CURRENT_STAGE. Used by skill prompts to tell
#       the LLM which files to read.
#
# Library contract: no shell flags at source time; strict mode only in
# the CLI-entry block at file bottom.

HANDOFF_LIB_DIR="${HANDOFF_LIB_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)}"

# Canonical stage order. Guarded against double-source.
if [[ -z "${HANDOFF_STAGE_ORDER+x}" ]]; then
readonly HANDOFF_STAGE_ORDER=(
  "brainstorm" "spec" "plan" "execute" "review" "verify"
)
fi

# _handoff_dir(repo_root)
_handoff_dir() {
  local root="${1:-.}"
  printf "%s/.handoffs" "${root%/}"
}

# write_handoff(stage, json_body, [repo_root])
# JSON body keys: decided, rejected, risks, files, remaining (each an array).
# notes (optional string) is appended below the frontmatter as freeform.
write_handoff() {
  local stage="${1:?write_handoff: stage required}"
  local body="${2:?write_handoff: json body required}"
  local root="${3:-.}"
  local dir
  dir=$(_handoff_dir "$root")
  mkdir -p "$dir"
  local ts sha
  ts=$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date -u)
  sha=$(git -C "$root" rev-parse --short HEAD 2>/dev/null || echo "unknown")
  # Normalize: ensure the 5 array fields exist (fill with empty array if absent)
  local norm
  norm=$(jq -c '
    {
      decided:   (.decided   // []),
      rejected:  (.rejected  // []),
      risks:     (.risks     // []),
      files:     (.files     // []),
      remaining: (.remaining // []),
      notes:     (.notes     // "")
    }
  ' <<< "$body")
  local decided rejected risks files remaining notes
  decided=$(jq  -c '.decided'   <<< "$norm")
  rejected=$(jq -c '.rejected'  <<< "$norm")
  risks=$(jq    -c '.risks'     <<< "$norm")
  files=$(jq    -c '.files'     <<< "$norm")
  remaining=$(jq -c '.remaining' <<< "$norm")
  notes=$(jq -r '.notes' <<< "$norm")
  local out="$dir/$stage.md"
  {
    printf -- "---\n"
    printf "stage: %s\n" "$stage"
    printf "timestamp: %s\n" "$ts"
    printf "sha: %s\n" "$sha"
    printf "decided: %s\n"   "$decided"
    printf "rejected: %s\n"  "$rejected"
    printf "risks: %s\n"     "$risks"
    printf "files: %s\n"     "$files"
    printf "remaining: %s\n" "$remaining"
    printf -- "---\n\n"
    if [[ -n "$notes" ]]; then
      printf "%s\n" "$notes"
    fi
  } > "$out"
  printf "%s" "$out"
}

# read_handoff(stage, [repo_root])
# Emits the frontmatter as JSON, or "{}" if the handoff file doesn't exist.
read_handoff() {
  local stage="${1:?read_handoff: stage required}"
  local root="${2:-.}"
  local path
  path="$(_handoff_dir "$root")/$stage.md"
  [[ -f "$path" ]] || { printf "{}"; return 0; }

  # Extract content between the first two "---" lines.
  local in_front=0
  local stage_v="" ts="" sha=""
  local decided='[]' rejected='[]' risks='[]' files='[]' remaining='[]'
  while IFS= read -r line; do
    if [[ "$line" == "---" ]]; then
      if [[ "$in_front" -eq 0 ]]; then in_front=1; continue; fi
      break
    fi
    [[ "$in_front" -eq 1 ]] || continue
    case "$line" in
      "stage: "*)     stage_v="${line#stage: }" ;;
      "timestamp: "*) ts="${line#timestamp: }" ;;
      "sha: "*)       sha="${line#sha: }" ;;
      "decided: "*)   decided="${line#decided: }" ;;
      "rejected: "*)  rejected="${line#rejected: }" ;;
      "risks: "*)     risks="${line#risks: }" ;;
      "files: "*)     files="${line#files: }" ;;
      "remaining: "*) remaining="${line#remaining: }" ;;
    esac
  done < "$path"

  jq -cn \
    --arg stage "$stage_v" --arg ts "$ts" --arg sha "$sha" \
    --argjson decided   "$decided" \
    --argjson rejected  "$rejected" \
    --argjson risks     "$risks" \
    --argjson files     "$files" \
    --argjson remaining "$remaining" \
    '{stage: $stage, timestamp: $ts, sha: $sha,
      decided: $decided, rejected: $rejected, risks: $risks,
      files: $files, remaining: $remaining}'
}

# read_all_handoffs([repo_root])
# Emits JSON array of every handoff frontmatter present, sorted by canonical
# stage order.
read_all_handoffs() {
  local root="${1:-.}"
  local out='[]'
  local stage
  for stage in "${HANDOFF_STAGE_ORDER[@]}"; do
    local path
    path="$(_handoff_dir "$root")/$stage.md"
    [[ -f "$path" ]] || continue
    local entry
    entry=$(read_handoff "$stage" "$root")
    out=$(jq -c --argjson e "$entry" '. + [$e]' <<< "$out")
  done
  printf "%s" "$out"
}

# list_prior_stages(current_stage)
# Echoes space-separated list of stages that precede current_stage in the
# canonical order. Used by skill prompts ("read .handoffs/brainstorm.md
# and .handoffs/spec.md before your first response").
list_prior_stages() {
  local current="${1:?list_prior_stages: current stage required}"
  local out=""
  local s
  for s in "${HANDOFF_STAGE_ORDER[@]}"; do
    [[ "$s" == "$current" ]] && break
    out="${out:+$out }$s"
  done
  printf "%s" "$out"
}

# ------------------------------------------------------------------------------
# CLI entry
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  set -euo pipefail
  subcmd="${1:-}"
  shift || true
  case "$subcmd" in
    write) write_handoff "$@" ;;
    read)  read_handoff "$@" ;;
    all)   read_all_handoffs "$@" ;;
    prior) list_prior_stages "$@"; printf "\n" ;;
    *)
      cat >&2 <<USAGE
Usage: bash lib/handoff.sh <subcmd> [args...]
  write STAGE JSON_BODY [REPO_ROOT]     — write .handoffs/STAGE.md
  read  STAGE [REPO_ROOT]               — parse frontmatter → JSON
  all   [REPO_ROOT]                     — JSON array of all handoffs
  prior STAGE                           — list prior stages
USAGE
      exit 2
      ;;
  esac
fi
