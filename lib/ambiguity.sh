#!/usr/bin/env bash
# lib/ambiguity.sh — ambiguity scoring + gate (P2.8, OMC deep-interview).
#
# Blocks PRD generation until the brainstorm agent self-assesses that the
# feature request is clear along three weighted dimensions:
#
#   goal         40%   "Can I state what this feature does in one sentence?"
#   constraints  30%   "Can I list every constraint (time/tech/compliance)?"
#   criteria     30%   "Can I list every success/acceptance criterion?"
#
# Each dimension is a 0-10 self-assessed clarity score. The ambiguity score is
#   100 - (goal*4 + constraints*3 + criteria*3)
# so a fully-clear design (all 10s) has ambiguity 0 and a completely-vague
# request (all 0s) has ambiguity 100.
#
# Gate: default threshold is 20. The ql-brainstorm skill refuses to produce
# a design doc — and ql-spec refuses to produce a PRD — while ambiguity >= 20.
#
# Challenge modes kick in when questioning rounds accumulate without progress:
#   round 3, score > 40  -> contrarian (oppose every assumption)
#   round 4, score > 30  -> simplifier ("what's the minimum 80% solution?")
#   round 5, score > 20  -> ontologist (every named object must have a
#                                       precise definition)
#   otherwise            -> normal
#
# Ontology stability: extracts noun-ish tokens from the accumulated Q&A and
# measures how many are carried vs replaced between rounds. A thrashing
# ontology (>50% churn/round) is a signal the conversation is spiraling; the
# challenge mode escalates to ontologist regardless of round number.
#
# Library contract (matches every prior lib): no shell flags at source time,
# strict mode only in CLI-entry block.

AMBIGUITY_LIB_DIR="${AMBIGUITY_LIB_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)}"

: "${AMBIGUITY_THRESHOLD:=20}"
: "${AMBIGUITY_CONTRARIAN_ROUND:=3}"
: "${AMBIGUITY_CONTRARIAN_SCORE:=40}"
: "${AMBIGUITY_SIMPLIFIER_ROUND:=4}"
: "${AMBIGUITY_SIMPLIFIER_SCORE:=30}"
: "${AMBIGUITY_ONTOLOGIST_ROUND:=5}"
: "${AMBIGUITY_ONTOLOGIST_SCORE:=20}"

# score_ambiguity(goal, constraints, criteria)
# Each argument is a 0-10 integer clarity score from the agent's self-assessment.
# Echoes an integer 0-100 ambiguity score. Lower = clearer.
score_ambiguity() {
  local g="${1:?score_ambiguity: goal (0-10) required}"
  local c="${2:?score_ambiguity: constraints (0-10) required}"
  local a="${3:?score_ambiguity: criteria (0-10) required}"
  # Clamp each input to [0, 10]
  for v in "$g" "$c" "$a"; do
    if ! [[ "$v" =~ ^[0-9]+$ ]] || (( v < 0 || v > 10 )); then
      printf "ERROR: ambiguity input must be integer 0-10 (got %q)\n" "$v" >&2
      return 1
    fi
  done
  # 100 - (goal*4 + constraints*3 + criteria*3)
  local total=$(( g * 4 + c * 3 + a * 3 ))
  local score=$(( 100 - total ))
  (( score < 0 )) && score=0
  (( score > 100 )) && score=100
  printf "%s" "$score"
}

# check_gate(score, [threshold])
# Exit 0 if score < threshold (gate passes, proceed). Exit 1 otherwise.
# Default threshold = $AMBIGUITY_THRESHOLD.
check_gate() {
  local score="${1:?check_gate: score required}"
  local threshold="${2:-$AMBIGUITY_THRESHOLD}"
  (( score < threshold )) && return 0
  return 1
}

# challenge_mode(round, score)
# Echoes one of: normal | contrarian | simplifier | ontologist.
challenge_mode() {
  local round="${1:?challenge_mode: round required}"
  local score="${2:?challenge_mode: score required}"
  if   (( round >= AMBIGUITY_ONTOLOGIST_ROUND && score > AMBIGUITY_ONTOLOGIST_SCORE )); then printf "ontologist"
  elif (( round >= AMBIGUITY_SIMPLIFIER_ROUND && score > AMBIGUITY_SIMPLIFIER_SCORE )); then printf "simplifier"
  elif (( round >= AMBIGUITY_CONTRARIAN_ROUND && score > AMBIGUITY_CONTRARIAN_SCORE )); then printf "contrarian"
  else printf "normal"
  fi
}

# ontology_extract(text)
# Crude noun-ish token extractor for stability tracking. Lowercases, strips
# punctuation, drops short tokens and common stopwords. Echoes space-separated
# unique tokens.
ontology_extract() {
  local text="${1:-}"
  [[ -z "$text" ]] && { printf ""; return 0; }
  printf '%s' "$text" \
    | tr '[:upper:]' '[:lower:]' \
    | tr -c '[:alnum:]' '\n' \
    | awk 'length($0) >= 4' \
    | grep -vxE '(the|this|that|with|from|have|will|would|could|should|about|what|when|where|which|been|their|them|they|then|than|there|what|some|such|only|also|into|over|like|more|most|many|much|very|just|user|users|feature|features)' \
    | sort -u \
    | tr '\n' ' ' \
    | sed 's/ $//'
}

# ontology_diff(prior_tokens, current_tokens)
# Echoes JSON: {added, removed, carried, stability}
# stability = carried / (carried + removed + added)  [0.0 - 1.0]
ontology_diff() {
  local prior="${1:-}"
  local current="${2:-}"
  local added removed carried
  added=$(comm -13 <(printf '%s\n' $prior   | sort -u) <(printf '%s\n' $current | sort -u) | tr '\n' ' ' | sed 's/ $//')
  removed=$(comm -23 <(printf '%s\n' $prior | sort -u) <(printf '%s\n' $current | sort -u) | tr '\n' ' ' | sed 's/ $//')
  carried=$(comm -12 <(printf '%s\n' $prior | sort -u) <(printf '%s\n' $current | sort -u) | tr '\n' ' ' | sed 's/ $//')
  local a_n r_n c_n total
  a_n=$(printf '%s\n' $added   | grep -cv '^$')
  r_n=$(printf '%s\n' $removed | grep -cv '^$')
  c_n=$(printf '%s\n' $carried | grep -cv '^$')
  total=$(( a_n + r_n + c_n ))
  local stability="1.0"
  if (( total > 0 )); then
    # integer fixed-point: 100 * carried / total
    local stab_x100=$(( 100 * c_n / total ))
    stability="0.$(printf '%02d' "$stab_x100")"
    (( stab_x100 == 100 )) && stability="1.0"
  fi
  jq -cn --arg added "$added" --arg removed "$removed" --arg carried "$carried" \
         --arg stab "$stability" \
    '{added: ($added | split(" ") | map(select(length>0))),
      removed: ($removed | split(" ") | map(select(length>0))),
      carried: ($carried | split(" ") | map(select(length>0))),
      stability: ($stab | tonumber)}'
}

# ------------------------------------------------------------------------------
# CLI entry
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  set -euo pipefail
  subcmd="${1:-}"
  shift || true
  case "$subcmd" in
    score)     score_ambiguity "$@"; printf "\n" ;;
    gate)      check_gate "$@" ;;
    mode)      challenge_mode "$@"; printf "\n" ;;
    extract)   ontology_extract "$@"; printf "\n" ;;
    diff)      ontology_diff "$@" ;;
    *)
      cat >&2 <<USAGE
Usage: bash lib/ambiguity.sh <subcmd> [args...]
  score GOAL CONSTRAINTS CRITERIA  — 0-100 ambiguity score (all 0-10)
  gate SCORE [THRESHOLD]           — exit 0 if below threshold
  mode ROUND SCORE                 — normal|contrarian|simplifier|ontologist
  extract TEXT                     — space-sep unique tokens
  diff PRIOR CURRENT               — JSON {added, removed, carried, stability}
USAGE
      exit 2
      ;;
  esac
fi
