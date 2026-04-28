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

# G30 / US-004 (v0.6.6) — should_dispatch_deep_review(diff_path)
#
# Decides whether to invoke the multi-reviewer ql-deep-review pipeline based
# on the supplied unified-diff patch file. Honors the QL_DEEP_REVIEW env-var
# override (force=always dispatch, skip=always skip; otherwise tier-gated).
# Default rule: dispatch on tier >= MEDIUM (i.e., risk score > 30).
#
# Returns 0 (dispatch) or 1 (skip). Logs the tier + decision to stderr so
# operators can audit the choice from CI logs.
#
# Implementation: parses `diff --git` headers from the patch file to count
# changed files + sensitive-path hits + production-without-test signals,
# then computes the risk score using the same weights as compute_risk_score.
# The diff-path entry-point exists because callers in retrospective contexts
# (US-007 T-003) have a captured patch but no live SHAs.
should_dispatch_deep_review() {
  local diff_path="${1:-}"
  local override="${QL_DEEP_REVIEW:-}"

  # Override path: short-circuit before parsing, so even a missing diff_path
  # works for force/skip decisions.
  case "$override" in
    force)
      printf "[DEEP-REVIEW] QL_DEEP_REVIEW=force override → dispatch\n" >&2
      return 0 ;;
    skip)
      printf "[DEEP-REVIEW] QL_DEEP_REVIEW=skip override → skip\n" >&2
      return 1 ;;
    "") : ;;  # no override; fall through to tier gate
    *)
      printf "[DEEP-REVIEW] WARN: unrecognized QL_DEEP_REVIEW=%q (expected 'force' or 'skip'); ignoring\n" "$override" >&2 ;;
  esac

  # Tier-gated path: parse the diff to derive a tier.
  if [[ -z "$diff_path" || ! -f "$diff_path" ]]; then
    printf "[DEEP-REVIEW] WARN: diff_path missing or unreadable (%q) → skip\n" "$diff_path" >&2
    return 1
  fi

  # Enumerate changed files via `diff --git a/X b/Y` headers. Take the b/-side
  # path (post-image) since that's the new state's filename.
  local files
  files=$(grep -E '^diff --git ' "$diff_path" | sed -E 's|^diff --git a/.* b/||')
  local files_changed=0
  files_changed=$(printf '%s\n' "$files" | grep -cv '^$' || true)

  # Sensitive-path hits — same glob list as compute_risk_score.
  local sensitive_hits=0
  while IFS= read -r f; do
    [[ -z "$f" ]] && continue
    for glob in "${DEEP_REVIEW_SENSITIVE_GLOBS[@]}"; do
      # shellcheck disable=SC2053
      case "$f" in *$glob*) sensitive_hits=$((sensitive_hits + 1)); break ;; esac
    done
  done <<< "$files"

  # Coverage gap — production files touched without any matching test file.
  local has_test_file=false
  while IFS= read -r f; do
    [[ -z "$f" ]] && continue
    if [[ "$f" == tests/* || "$f" == test/* || "$f" == *.test.* || "$f" == *_test.* ]]; then
      has_test_file=true; break
    fi
  done <<< "$files"
  # G36 / US-002 (v0.6.7) — defense-in-depth guard. The `|$` alternative
  # inside the regex below already excludes the empty trailing newline that
  # `printf '%s\n' ""` produces on a 0-files diff (verified by Test 5 in
  # tests/test_deep_review_dispatch.sh), so prod_count IS 0 on empty input
  # today. The explicit `files_changed > 0` short-circuit hardens against
  # any future refactor that removes the `|$` anchor — without it, the
  # spurious empty-line count would inflate cg from 0 to 2 (still LOW tier,
  # but operators would see misleading score=2 in the diagnostic log).
  # Mirrors the structure used in compute_risk_score above.
  local prod_count=0
  if (( files_changed > 0 )); then
    prod_count=$(printf '%s\n' "$files" | grep -cvE '^(tests?/|$)|(\.test\.|_test\.)' || true)
  fi
  local prod_without_test=0
  if [[ "$has_test_file" == false && "$prod_count" -gt 0 ]]; then
    prod_without_test="$prod_count"
  fi

  # Same weights as compute_risk_score (intent-drift signal not available
  # from a captured patch — set to 0).
  local br=$(( files_changed > 10 ? 25 : files_changed * 25 / 10 ))
  local sp=$(( sensitive_hits > 2 ? 20 : sensitive_hits * 20 / 2 ))
  local cg=$(( prod_without_test > 5 ? 10 : prod_without_test * 10 / 5 ))
  local score=$(( br + sp + cg ))
  (( score > 100 )) && score=100

  local tier
  tier=$(tier_of_score "$score")

  case "$tier" in
    MEDIUM|HIGH|CRITICAL)
      printf "[DEEP-REVIEW] tier=%s score=%d files=%d sensitive=%d → dispatch\n" \
        "$tier" "$score" "$files_changed" "$sensitive_hits" >&2
      return 0 ;;
    *)
      printf "[DEEP-REVIEW] tier=%s score=%d files=%d sensitive=%d → skip\n" \
        "$tier" "$score" "$files_changed" "$sensitive_hits" >&2
      return 1 ;;
  esac
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
# Phase 23 / P3.3 — KBI-FAR reviewer split (arXiv:2505.17928)
# ------------------------------------------------------------------------------
#
# The ICML 2025 paper decomposes review into two stages:
#   KBI (Known-Bug-Inspection)  — broad, high-recall sweep: each reviewer
#                                  aggressively flags anything suspicious.
#   FAR (False-Alarm-Reduction) — precision filter: drop low-confidence,
#                                  suppress known-false-positives, boost
#                                  multi-agent agreement.
#
# Our existing actionability_filter + dedup + hallucination_check already do
# part of FAR. This section adds the explicit precision filter to complete
# the split: confidence cutoff, multi-agent agreement boost, and known-FP
# regex suppression from quantum.json.knownFalsePositives[].

: "${FAR_CONFIDENCE_CUTOFF:=60}"
: "${FAR_AGREEMENT_BOOST:=15}"

# far_filter(findings_json, [quantum_json_path])
# Input: JSON array of findings on stdin (already actionability-filtered,
# deduped, and hallucination-checked). Outputs:
#   { "kept":      [<findings that survived the precision filter>],
#     "suppressed":[<findings that were dropped, each with .far_reason>] }
#
# Steps applied in order:
#   1. Multi-agent agreement boost: findings whose .agents array has ≥2
#      distinct entries get +FAR_AGREEMENT_BOOST on their confidence
#      (capped at 100). Rewrites the input findings in place.
#   2. Known-FP pattern suppression: if quantum_json_path is provided and
#      .knownFalsePositives is an array of regexes, drop any finding whose
#      title OR description matches any regex.
#   3. Confidence cutoff: drop any finding whose (boosted) confidence is
#      below FAR_CONFIDENCE_CUTOFF.
#
# Preserves original confidence in .original_confidence on boosted findings.
far_filter() {
  local qj="${1:-}"
  local cutoff="${FAR_CONFIDENCE_CUTOFF:-60}"
  local boost="${FAR_AGREEMENT_BOOST:-15}"

  # Load known-FP regex list (array of strings). Empty if no quantum.json
  # or field absent.
  local fp_json='[]'
  if [[ -n "$qj" && -f "$qj" ]]; then
    fp_json=$(jq -c '.knownFalsePositives // []' "$qj" 2>/dev/null || echo '[]')
  fi

  jq -c \
    --argjson cutoff "$cutoff" \
    --argjson boost  "$boost" \
    --argjson fps    "$fp_json" \
    '
    def apply_boost:
      map(
        if ((.agents // []) | length) >= 2
        then . + {
          original_confidence: (.confidence // 0),
          confidence: ([.confidence // 0, 0] | max + $boost | if . > 100 then 100 else . end)
        }
        else .
        end
      );

    def matches_fp:
      . as $f
      | any($fps[]?;
          ((. // "") as $re | $re != "" and
           (($f.title // "") | test($re)) or
           (($f.description // "") | test($re))));

    def classify:
      . as $f
      | if matches_fp then . + {__suppress: true, far_reason: "matched knownFalsePositives pattern"}
        elif (.confidence // 0) < $cutoff then . + {__suppress: true, far_reason: ("confidence " + ((.confidence // 0) | tostring) + " below cutoff " + ($cutoff | tostring))}
        else .
        end;

    . | apply_boost
      | map(classify)
      | {
          kept:       map(select(.__suppress != true)),
          suppressed: map(select(.__suppress == true) | del(.__suppress))
        }
    '
}

# ------------------------------------------------------------------------------
# Phase 12 / P1.3 — risk-adaptive reviewer dispatch
# ------------------------------------------------------------------------------

# _critic_agent_for(provider)
# P5.A2 / US-002 — map a critic provider name to its agent identifier.
# 'auto' returns the canonical CRITICAL-tier critic (omc:ask-codex-critic);
# 'none' returns empty (caller should skip critic dispatch entirely).
_critic_agent_for() {
  case "${1:-auto}" in
    auto|codex) printf 'omc:ask-codex-critic' ;;
    gemini)     printf 'omc:ask-gemini-critic' ;;
    claude)     printf 'oh-my-claudecode:critic' ;;
    none)       printf '' ;;
    *)          printf 'omc:ask-codex-critic' ;;  # unknown -> auto default
  esac
}

# dispatch_set(tier)
# Echoes a JSON array of reviewer agent IDs that SHOULD be dispatched at the
# given tier. Canonical table from skills/ql-deep-review/SKILL.md §"Risk
# scoring". Each tier is a strict superset of the previous, so HIGH includes
# all MEDIUM reviewers, and CRITICAL includes all HIGH reviewers plus the
# cross-provider critic.
#
# P5.A2 / US-002: when QL_CRITIC env var is set to a non-'auto' value, the
# CRITICAL-tier critic agent is overridden (or omitted entirely for 'none').
# This allows operators to swap codex<->gemini<->claude or disable the critic
# without modifying the tier-driven core.
dispatch_set() {
  local tier="${1:?dispatch_set: tier required (LOW|MEDIUM|HIGH|CRITICAL)}"
  local critic_choice="${QL_CRITIC:-auto}"
  local critic_agent
  critic_agent=$(_critic_agent_for "$critic_choice")
  case "$tier" in
    LOW)
      jq -cn '["oh-my-claudecode:code-reviewer","soliton:synthesizer"]' ;;
    MEDIUM)
      jq -cn '["oh-my-claudecode:code-reviewer","soliton:synthesizer","oh-my-claudecode:security-reviewer","oh-my-claudecode:test-engineer"]' ;;
    HIGH)
      jq -cn '["oh-my-claudecode:code-reviewer","soliton:synthesizer","oh-my-claudecode:security-reviewer","oh-my-claudecode:test-engineer","oh-my-claudecode:critic","oh-my-claudecode:architect"]' ;;
    CRITICAL)
      if [[ -z "$critic_agent" ]]; then
        # QL_CRITIC=none -> drop the cross-provider critic from dispatch.
        jq -cn '["oh-my-claudecode:code-reviewer","soliton:synthesizer","oh-my-claudecode:security-reviewer","oh-my-claudecode:test-engineer","oh-my-claudecode:critic","oh-my-claudecode:architect"]'
      else
        jq -cn --arg crit "$critic_agent" \
          '["oh-my-claudecode:code-reviewer","soliton:synthesizer","oh-my-claudecode:security-reviewer","oh-my-claudecode:test-engineer","oh-my-claudecode:critic","oh-my-claudecode:architect", $crit]'
      fi
      ;;
    *)
      printf 'ERROR: unknown tier %q (expected LOW|MEDIUM|HIGH|CRITICAL)\n' "$tier" >&2
      return 1 ;;
  esac
}

# risk_score_from_quantum(quantum_json_path, base_sha, head_sha)
# Reads intentDrift critical count from quantum.json and feeds it into
# compute_risk_score. Convenience wrapper so callers don't have to
# re-extract the drift signal.
risk_score_from_quantum() {
  local qj="${1:?risk_score_from_quantum: quantum.json path required}"
  local base="${2:-}"
  local head="${3:-}"
  local drift_crit=0
  if [[ -f "$qj" ]]; then
    drift_crit=$(jq -r '[.intentDrift // {} | to_entries[] | .value.summary.critical // 0] | add // 0' "$qj" 2>/dev/null || echo 0)
  fi
  compute_risk_score "$base" "$head" "" "$drift_crit"
}

# prepare_review_context(base, head, prd_path, intent_snapshot_text, tier)
# Emits a JSON context package that each reviewer agent receives. The shape
# matches the skill's documented handshake — callers dispatch the agent
# with this JSON as the argument payload.
prepare_review_context() {
  local base="${1:?prepare_review_context: base_sha required}"
  local head="${2:?prepare_review_context: head_sha required}"
  local prd_path="${3:-}"
  local intent_text="${4:-}"
  local tier="${5:-MEDIUM}"
  local files
  files=$(git diff --name-only "$base..$head" 2>/dev/null | jq -R . | jq -s '.')
  [[ -z "$files" ]] && files='[]'
  jq -cn \
    --arg base "$base" --arg head "$head" \
    --arg prd "$prd_path" --arg intent "$intent_text" \
    --arg tier "$tier" \
    --argjson files "$files" \
    '{
      base_sha: $base,
      head_sha: $head,
      prd_path: $prd,
      user_intent: $intent,
      tier: $tier,
      changed_files: $files,
      evidence_requirements: {
        must_cite: ["file", "line", "evidence_type"],
        severity: ["critical","high","medium","low","info"]
      }
    }'
}

# aggregate_reviews(repo_root, [quantum_json])
# Input: JSON array of finding arrays — one per reviewer — on stdin. Chains:
#   flatten → actionability_filter → dedup_findings → hallucination_check →
#   far_filter → synthesize_verdict, and emits a single JSON object:
#   { verdict, findings: [kept], suppressed: [with reasons] }
# far_filter applies the KBI-FAR precision pass (Phase 23/P3.3): agreement
# boost, confidence cutoff, known-FP regex suppression from
# quantum.json.knownFalsePositives[].
aggregate_reviews() {
  local repo_root="${1:-.}"
  local quantum_json="${2:-}"
  local flat
  flat=$(jq -c '[.[] | .[]]')
  local actionable
  actionable=$(printf '%s' "$flat" | actionability_filter)
  local kept_action sup_action
  kept_action=$(printf '%s' "$actionable" | jq -c '.kept')
  sup_action=$(printf '%s' "$actionable"  | jq -c '.suppressed')
  local deduped
  deduped=$(printf '%s' "$kept_action" | dedup_findings)
  local checked kept_after_hall sup_hall
  checked=$(printf '%s' "$deduped" | hallucination_check "$repo_root")
  kept_after_hall=$(printf '%s' "$checked" | jq -c '.kept')
  sup_hall=$(printf '%s'  "$checked" | jq -c '.suppressed')
  # Phase 23 / P3.3 precision stage
  local far kept_final sup_far
  far=$(printf '%s' "$kept_after_hall" | far_filter "$quantum_json")
  kept_final=$(printf '%s' "$far" | jq -c '.kept')
  sup_far=$(printf '%s' "$far" | jq -c '.suppressed')
  local verdict
  verdict=$(printf '%s' "$kept_final" | synthesize_verdict)
  jq -cn \
    --argjson k "$kept_final" \
    --argjson sa "$sup_action" \
    --argjson sh "$sup_hall" \
    --argjson sf "$sup_far" \
    --arg v "$verdict" \
    '{verdict: $v, findings: $k, suppressed: ($sa + $sh + $sf)}'
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
    far)           far_filter "$@" ;;
    verdict)       synthesize_verdict ;;
    dispatch-set)  dispatch_set "$@"; printf "\n" ;;
    context)       prepare_review_context "$@"; printf "\n" ;;
    aggregate)     aggregate_reviews "$@" ;;
    score-from-quantum) risk_score_from_quantum "$@"; printf "\n" ;;
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
