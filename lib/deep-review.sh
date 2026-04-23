#!/usr/bin/env bash
# lib/deep-review.sh — machine-testable helpers for the ql-deep-review skill.
#
# The skill prompt (skills/ql-deep-review/SKILL.md) drives the LLM-side
# dispatch of 2-7 reviewer agents in parallel. This library covers the
# deterministic parts that ship alongside the prompt and can be unit-tested:
#
#   compute_risk_score   — 0-100 composite from file-count / sensitive-paths /
#                          coverage-gap / intent-drift signals.
#   tier_of_score        — LOW / MEDIUM / HIGH / CRITICAL.
#   actionability_filter — drop findings without line-level evidence.
#   dedup_findings       — group by (file, line_start, severity).
#   hallucination_check  — suppress findings citing files that don't exist.
#   synthesize_verdict   — APPROVE / APPROVE_WITH_COMMENTS / REQUEST_CHANGES / BLOCKS_MERGE.
#
# Contract: library NEVER sets shell flags at source time. CLI mode (bottom
# of the file) enables strict mode locally.

DEEP_REVIEW_LIB_DIR="${DEEP_REVIEW_LIB_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)}"

# ------------------------------------------------------------------------------
# Sensitive-path glob patterns (Rule-2 of the skill's risk scoring)

if [[ -z "${DEEP_REVIEW_SENSITIVE_GLOBS+x}" ]]; then
readonly DEEP_REVIEW_SENSITIVE_GLOBS=(
  "auth/"
  "payment/"
  "*.env"
  "*secret*"
  "*password*"
  "*token*"
  "*credentials*"
)
fi

# ------------------------------------------------------------------------------
# compute_risk_score(base_sha, head_sha, [prd_path], [intent_drift_critical_count])
#
# Echos an integer 0-100. Uses `git diff --name-only base..head` to enumerate
# changed files. Missing base/head falls back to a score of 0 (no-change).
# If git fails (e.g., refs don't exist), returns 0 and emits WARN to stderr.
compute_risk_score() {
  local base_sha="${1:-}"
  local head_sha="${2:-}"
  local intent_drift_critical="${4:-0}"

  local files_changed=0
  local sensitive_hits=0
  local prod_without_test=0

  if [[ -n "$base_sha" && -n "$head_sha" ]]; then
    local namelist
    namelist=$(git diff --name-only "$base_sha..$head_sha" 2>/dev/null || echo "")
    if [[ -z "$namelist" ]]; then
      printf "[DEEP-REVIEW] WARN: no files in diff %s..%s (refs missing?)\n" \
        "$base_sha" "$head_sha" >&2
    fi
    files_changed=$(printf '%s\n' "$namelist" | grep -cv '^$' || true)

    # Sensitive-path match
    while IFS= read -r f; do
      [[ -z "$f" ]] && continue
      for glob in "${DEEP_REVIEW_SENSITIVE_GLOBS[@]}"; do
        # shellcheck disable=SC2053
        case "$f" in *$glob*) sensitive_hits=$((sensitive_hits + 1)); break ;; esac
      done
    done <<< "$namelist"

    # Coverage gap: a prod file touched without any matching test file in the diff
    local has_test_file=false
    while IFS= read -r f; do
      [[ -z "$f" ]] && continue
      if [[ "$f" == tests/* || "$f" == test/* || "$f" == *.test.* || "$f" == *_test.* ]]; then
        has_test_file=true; break
      fi
    done <<< "$namelist"
    local prod_count
    prod_count=$(printf '%s\n' "$namelist" | grep -cvE '^(tests?/|$)|(\.test\.|_test\.)' || true)
    if [[ "$has_test_file" == false && "$prod_count" -gt 0 ]]; then
      prod_without_test="$prod_count"
    fi
  fi

  # Weighted composite — clamped to 100.
  # Blast radius 25 * min(files_changed/10, 1)
  # Sensitive paths 20 * min(sensitive_hits/2, 1)
  # Coverage gap 10 * min(prod_without_test/5, 1)
  # Intent drift 10 * min(intent_drift_critical/1, 1)
  # Base slack 35 (size + AI-author + complexity defaults; detailed decomp
  # left to specialist agents, see SKILL.md §"Risk scoring")
  local br=$(( files_changed > 10 ? 25 : files_changed * 25 / 10 ))
  local sp=$(( sensitive_hits > 2 ? 20 : sensitive_hits * 20 / 2 ))
  local cg=$(( prod_without_test > 5 ? 10 : prod_without_test * 10 / 5 ))
  local id=$(( intent_drift_critical > 0 ? 10 : 0 ))
  local score=$(( br + sp + cg + id ))
  (( score > 100 )) && score=100
  printf "%s" "$score"
}

# tier_of_score(score)
# Echoes LOW / MEDIUM / HIGH / CRITICAL.
tier_of_score() {
  local s="${1:-0}"
  if   (( s <= 30 )); then printf "LOW"
  elif (( s <= 60 )); then printf "MEDIUM"
  elif (( s <= 80 )); then printf "HIGH"
  else printf "CRITICAL"
  fi
}

# actionability_filter(findings_json)
# Input: JSON array of findings on stdin. Drops entries without `file` AND
# (`line` or `line_start`) AND `evidence_type`. Echoes a new JSON object:
#   { "kept": [...], "suppressed": [...] }
actionability_filter() {
  jq -c '
    {
      kept: map(select(
        (.file // "") != "" and
        ((.line // .line_start // null) | type == "number") and
        (.evidence_type // "") != ""
      )),
      suppressed: map(select(
        (.file // "") == "" or
        ((.line // .line_start // null) | type != "number") or
        (.evidence_type // "") == ""
      ) | . + {reason: "no actionable evidence"})
    }
  '
}

# dedup_findings(findings_json)
# Input: JSON array of findings on stdin. Groups by (file, line_start, severity)
# — concatenating agents and keeping the highest confidence. Echoes the deduped array.
dedup_findings() {
  jq -c '
    group_by([.file, (.line_start // .line // 0), .severity])
    | map(
        .[0] + {
          agents: ([.[] | (.agents // [.agent // "unknown"])] | flatten | unique),
          confidence: ([.[] | (.confidence // 0)] | max)
        }
      )
  '
}

# hallucination_check(findings_json, [repo_root])
# Suppresses findings whose `.file` does not exist under repo_root.
# Input JSON array on stdin. Echoes { kept: [...], suppressed: [...] }.
hallucination_check() {
  local repo_root="${1:-.}"
  # Normalize the path for jq
  local root_esc
  root_esc=$(printf '%s' "$repo_root" | sed 's|/$||')
  # Read all findings, check each file's existence, split into two arrays.
  local findings kept='[]' suppressed='[]'
  findings=$(cat)
  # Use jq to enumerate
  local count
  count=$(printf '%s' "$findings" | jq 'length')
  local i=0
  while (( i < count )); do
    local file entry
    entry=$(printf '%s' "$findings" | jq -c ".[$i]")
    file=$(printf '%s' "$entry" | jq -r '.file // ""')
    if [[ -n "$file" && -e "$root_esc/$file" ]]; then
      kept=$(jq -c --argjson new "$entry" '. + [$new]' <<< "$kept")
    else
      local tagged
      tagged=$(printf '%s' "$entry" | jq -c '. + {reason: "reviewer hallucinated target"}')
      suppressed=$(jq -c --argjson new "$tagged" '. + [$new]' <<< "$suppressed")
    fi
    i=$((i + 1))
  done
  jq -cn --argjson k "$kept" --argjson s "$suppressed" '{kept: $k, suppressed: $s}'
}

# synthesize_verdict(findings_json)
# Input: JSON array of findings on stdin. Echoes one of:
#   APPROVE | APPROVE_WITH_COMMENTS | REQUEST_CHANGES | BLOCKS_MERGE
# Rules:
#   BLOCKS_MERGE       = any critical with confidence >=80
#   REQUEST_CHANGES    = any high with confidence >=70
#   APPROVE_WITH_COMMENTS = any medium with confidence >=50 (no high/critical)
#   APPROVE            = otherwise
synthesize_verdict() {
  jq -r '
    def has(sev; min_conf): any(.[]; (.severity // "") == sev and (.confidence // 0) >= min_conf);
    if has("critical"; 80) then "BLOCKS_MERGE"
    elif has("high"; 70) then "REQUEST_CHANGES"
    elif has("medium"; 50) then "APPROVE_WITH_COMMENTS"
    else "APPROVE"
    end
  '
}

# ------------------------------------------------------------------------------
# CLI entry: `bash lib/deep-review.sh <subcmd>`
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  set -euo pipefail
  subcmd="${1:-}"
  shift || true
  case "$subcmd" in
    score)
      compute_risk_score "$@"
      printf "\n"
      ;;
    tier)
      tier_of_score "$@"
      printf "\n"
      ;;
    actionability) actionability_filter ;;
    dedup)         dedup_findings ;;
    hallucination) hallucination_check "$@" ;;
    verdict)       synthesize_verdict ;;
    *)
      cat >&2 <<USAGE
Usage: bash lib/deep-review.sh <subcmd> [args...]
  score BASE HEAD [PRD] [INTENT_DRIFT_CRITICAL]     — compute risk score 0-100
  tier SCORE                                        — map score to LOW/MEDIUM/HIGH/CRITICAL
  actionability  < findings.json                    — split by actionability
  dedup          < findings.json                    — dedup by (file, line, severity)
  hallucination [REPO_ROOT]  < findings.json        — suppress findings citing missing files
  verdict        < findings.json                    — synthesize APPROVE/.../BLOCKS_MERGE
USAGE
      exit 2
      ;;
  esac
fi
