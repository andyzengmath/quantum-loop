#!/usr/bin/env bash
# lib/orchestrator-liveness.sh — N6-followup / US-001 (v0.6.9)
#
# Parent-side commit-poll helper for orchestrator stale detection. v0.6.7 +
# v0.6.8 both saw the orchestrator subagent abandon its cycle mid-execution
# (LLM context-drift). v0.6.8 N6 shipped a prose-only Self-monitoring guard
# subsection in agents/orchestrator.md — advisory only. This v0.6.9 helper
# is the runtime side: a callable function that polls git HEAD on a
# configurable interval and emits a stale signal when no new commits land
# within timeout_sec. The CALLER (parent agent or /ql-execute SKILL wrapper)
# decides recovery action — re-spawn, hand off to parent, log + continue.
#
# Functions:
#   poll_orchestrator_commits TIMEOUT_SEC INTERVAL_SEC BASE_SHA
#     Defaults: TIMEOUT_SEC=600 (10 min), INTERVAL_SEC=60 (1 min),
#               BASE_SHA=$(git rev-parse HEAD) at call time.
#     Returns: 0 (live) when a new commit is observed; 1 (stale) on timeout.
#     Stderr log:
#       [LIVENESS] new commit XXXXXXXX observed at +Ns   (live path)
#       [LIVENESS] STALE: no commits in Ns (base=XXXXXXXX) (stale path)
#
# Library contract: NO shell flags at source time. CLI mode (bottom of the
# file) enables strict mode locally. Mirrors lib/handoff.sh / lib/finding-*.sh.
#
# Usage example:
#   source lib/orchestrator-liveness.sh
#   if poll_orchestrator_commits 600 60; then
#     echo "Orchestrator alive — proceeding"
#   else
#     echo "Orchestrator stale — see references/orchestrator-takeover.md"
#   fi

# Guard against double-source.
if [[ -z "${ORCHESTRATOR_LIVENESS_LIB+x}" ]]; then
readonly ORCHESTRATOR_LIVENESS_LIB=1

# poll_orchestrator_commits(timeout_sec, interval_sec, base_sha)
poll_orchestrator_commits() {
  local timeout_sec="${1:-600}"
  local interval_sec="${2:-60}"
  local base_sha="${3:-$(git rev-parse HEAD 2>/dev/null)}"

  # N16 / US-004 (v0.7.0) — fail-fast on bad interval_sec. Without this guard,
  # interval_sec=0 makes `sleep 0` a no-op and `elapsed` never increases past 0
  # — the loop runs forever burning CPU. Soliton-pr-review caught at confidence
  # 82 on PR #70 (v0.6.9 sub-threshold; carried forward to v0.7.0).
  if (( interval_sec <= 0 )); then
    printf "[LIVENESS] ERROR: interval_sec must be > 0 (got %s)\n" "$interval_sec" >&2
    return 1
  fi

  local elapsed=0
  while (( elapsed < timeout_sec )); do
    sleep "$interval_sec"
    elapsed=$((elapsed + interval_sec))
    local cur_sha
    cur_sha=$(git rev-parse HEAD 2>/dev/null)
    if [[ "$cur_sha" != "$base_sha" ]]; then
      printf "[LIVENESS] new commit %s observed at +%ds\n" "${cur_sha:0:8}" "$elapsed" >&2
      return 0
    fi
  done
  printf "[LIVENESS] STALE: no commits in %ds (base=%s)\n" "$timeout_sec" "${base_sha:0:8}" >&2
  return 1
}

# wrap_orchestrator_dispatch [timeout_sec] [interval_sec]
#
# N20 / US-002 (v0.7.1) — extracts the v0.7.0 N14 SKILL.md inline wrapping
# logic into a callable function. The /ql-execute SKILL invokes this
# function instead of inlining the conditional + handoff message.
#
# Honors QL_LIVENESS_ENABLE env var:
#   unset / "true"  -> wrap with poll_orchestrator_commits (default behavior).
#   "false"         -> silent skip (preserves v0.6.9 dispatch semantics).
#   any other value -> treated as "true".
#
# On STALE: emits the canonical handoff message to stdout (pointer to the
# orchestrator-takeover SOP + numbered recovery steps) and returns 1.
# On LIVE / OPT-OUT: returns 0 without printing.
#
# Defaults: timeout_sec=600 (10 min), interval_sec=60 (1 min).
wrap_orchestrator_dispatch() {
  local timeout_sec="${1:-600}"
  local interval_sec="${2:-60}"

  if [[ "${QL_LIVENESS_ENABLE:-true}" == "false" ]]; then
    return 0
  fi

  if poll_orchestrator_commits "$timeout_sec" "$interval_sec"; then
    return 0
  fi

  cat <<'HANDOFF'
[QL-EXECUTE] orchestrator-stale signal. Recovery procedure:
  1. Read references/orchestrator-takeover.md (manual-takeover SOP).
  2. Verify drift via git log <BASE>..HEAD --oneline + jq status query.
  3. Continue the in-progress story manually; commit normally.
HANDOFF
  return 1
}

fi  # ORCHESTRATOR_LIVENESS_LIB guard

# CLI entry — only when invoked directly (bash lib/orchestrator-liveness.sh).
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  set -uo pipefail
  poll_orchestrator_commits "$@"
  exit $?
fi
