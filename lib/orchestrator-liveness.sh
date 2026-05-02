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

# poll_orchestrator_commits(timeout_sec, interval_sec, base_sha, worktree_path)
#
# US-002 / v0.8.0 (N33) — when WORKTREE_PATH (4th arg) is set and not "."
# or empty, all git rev-parse calls target that path via `git -C <path>`.
# This eliminates false-positive STALE in worktree-parallel mode where the
# orchestrator subagent commits to .ql-wt/<story>/ on a feature branch and
# the parent repo's HEAD does not advance.
poll_orchestrator_commits() {
  local timeout_sec="${1:-600}"
  local interval_sec="${2:-60}"
  local base_sha_arg="${3:-}"
  local worktree_path="${4:-}"

  # Build git -C prefix when polling a worktree path.
  local git_dir_arg=()
  if [[ -n "$worktree_path" && "$worktree_path" != "." ]]; then
    git_dir_arg=(-C "$worktree_path")
  fi

  local base_sha
  if [[ -n "$base_sha_arg" ]]; then
    base_sha="$base_sha_arg"
  else
    base_sha=$(git "${git_dir_arg[@]}" rev-parse HEAD 2>/dev/null)
  fi

  # N16 / US-004 (v0.7.0) — fail-fast on bad interval_sec. Without this guard,
  # interval_sec=0 makes `sleep 0` a no-op and `elapsed` never increases past 0
  # — the loop runs forever burning CPU.
  if (( interval_sec <= 0 )); then
    printf "[LIVENESS] ERROR: interval_sec must be > 0 (got %s)\n" "$interval_sec" >&2
    return 1
  fi

  local elapsed=0
  while (( elapsed < timeout_sec )); do
    sleep "$interval_sec"
    elapsed=$((elapsed + interval_sec))
    local cur_sha
    cur_sha=$(git "${git_dir_arg[@]}" rev-parse HEAD 2>/dev/null)
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
# N24 / US-001 (v0.7.2) — adds QL_RESPAWN_CMD auto-respawn path. When set
# to a non-empty string, the command is executed via `bash -c` on STALE
# instead of emitting the manual-takeover handoff. QL_RESPAWN_CMD is an
# operator-controlled env var (trusted invocation, not user input).
#
# Honors env vars:
#   QL_LIVENESS_ENABLE  unset/"true" -> wrap with poll (default).
#                       "false"      -> silent skip, return 0.
#   QL_RESPAWN_CMD      non-empty    -> execute via `bash -c` on STALE, return its rc.
#                       empty/unset  -> emit canonical handoff message, return 1.
#
# On LIVE / OPT-OUT: returns 0 without printing.
# Defaults: timeout_sec=600 (10 min), interval_sec=60 (1 min).
wrap_orchestrator_dispatch() {
  local timeout_sec="${1:-600}"
  local interval_sec="${2:-60}"
  # US-002 / v0.8.0 (N33) — optional 3rd arg propagates to poll_orchestrator_commits
  # for worktree-aware polling. When set and not "."/"", liveness polls the
  # worktree's HEAD instead of the caller's pwd HEAD.
  local worktree_path="${3:-}"

  if [[ "${QL_LIVENESS_ENABLE:-true}" == "false" ]]; then
    return 0
  fi

  if poll_orchestrator_commits "$timeout_sec" "$interval_sec" "" "$worktree_path"; then
    return 0
  fi

  # N24: auto-respawn path — operator supplies a fully-specified orchestrator
  # invocation (e.g. `claude --skill ql-execute`) via QL_RESPAWN_CMD.
  #
  # v0.10.11 / US-001 (N46 closure): capture respawn stdout/stderr via tee
  # (preserves live operator-visible streaming) and re-feed through
  # runner_parse_output so SIGNAL_RESULT/SIGNAL_CONFIDENCE reflect the
  # respawned run. Without this, a successful respawn (rc=0) emitting
  # <quantum>STORY_PASSED</quantum> would leave the iteration loop's
  # earlier STORY_FAILED signal intact, causing false story-failure marks.
  # Graceful when runner_parse_output is not sourced (standalone usage):
  # falls through without re-parse, preserving prior behavior.
  if [[ -n "${QL_RESPAWN_CMD:-}" ]]; then
    printf "[QL-EXECUTE] orchestrator-stale — respawning via QL_RESPAWN_CMD\n" >&2
    local respawn_tmpfile
    respawn_tmpfile=$(mktemp)
    # v0.10.11 / US-003 review fix (security MEDIUM): chmod 600 closes the
    # Git Bash mode-644-by-default gap where co-tenant on shared host could
    # read respawn output during the brief tee-write/rm-f window.
    chmod 600 "$respawn_tmpfile" 2>/dev/null || true
    # v0.10.11 / US-003 review fix (architect MEDIUM): trap RETURN cleans
    # up tmpfile even if SIGTERM/abort interrupts between tee and rm.
    trap 'rm -f "$respawn_tmpfile"' RETURN
    # tee preserves live streaming to stderr while capturing for re-parse.
    # v0.10.11 / US-003 review fix (architect MEDIUM): use a subshell to
    # locally disable `errexit` so the pipeline + PIPESTATUS read both run
    # regardless of the caller's `set -euo pipefail`. tee output goes to
    # stderr (>&2) which propagates through the subshell; rc is emitted
    # to stdout via printf and captured into respawn_rc. Works in both
    # production (set -euo pipefail) and test contexts (set -uo pipefail).
    local respawn_rc
    respawn_rc=$(
      set +e
      bash -c "${QL_RESPAWN_CMD}" 2>&1 | tee "$respawn_tmpfile" >&2
      printf '%s' "${PIPESTATUS[0]}"
    )
    local respawn_out
    respawn_out=$(cat "$respawn_tmpfile")
    if [[ "$respawn_rc" -ne 0 ]]; then
      printf "[QL-EXECUTE] QL_RESPAWN_CMD exited %d — respawn may have failed\n" "$respawn_rc" >&2
    fi
    # N46 closure: re-parse respawn output to update SIGNAL_RESULT /
    # SIGNAL_CONFIDENCE. No-op when runner_parse_output not in scope.
    if type runner_parse_output >/dev/null 2>&1; then
      # runner_parse_output references RUNNER_HEURISTIC_FALLBACK; production
      # sets this via runner_load before reaching here. Defensive default
      # avoids unbound-var abort under `set -u` if invoked pre-runner_load.
      : "${RUNNER_HEURISTIC_FALLBACK:=false}"
      runner_parse_output "$respawn_out" "$respawn_rc" "${worktree_path:-.}"
    fi
    return $respawn_rc
  fi

  cat <<'HANDOFF'
[QL-EXECUTE] orchestrator-stale signal. Recovery procedure:
  1. Read references/orchestrator-takeover.md (manual-takeover SOP).
  2. Verify drift via git log <BASE>..HEAD --oneline + jq status query.
  3. Continue the in-progress story manually; commit normally.
HANDOFF
  return 1
}

# v0.11.1 / US-001 (N43): parallel-with-dispatch wrap pattern.
#
# Spawns CMD in background, polls commits in foreground, kills child if
# STALE (no commits within timeout window). Each new commit resets the
# timeout window — commit-progress signals liveness.
#
# Contract:
#   dispatch_with_parallel_poll TIMEOUT_SEC INTERVAL_SEC CMD
#     TIMEOUT_SEC   — max wallclock without commit progress (default 600)
#     INTERVAL_SEC  — poll cadence (default 60)
#     CMD           — shell command string (executed via bash -c)
#   Output: child's stdout+stderr emitted on this function's stdout.
#   Stderr logs:
#     [LIVENESS] new commit XXXXXXXX observed at +Ns   (commit progress)
#     [LIVENESS] STALE: no commits in Ns; killing PID X (kill cascade)
#   Returns: child's rc on natural completion, or signal-kill rc (143/137).
#
# Opt-in only: caller (lib/iteration-loop.sh) gates on QL_PARALLEL_POLL=true.
# Coordinator mode is NOT a wire site — it has its own wallclock kill via
# QL_COORDINATOR_TIMEOUT_S (v0.9.3).
#
# Git Bash bg-process notes:
#   - `kill -0 PID` reliably probes liveness.
#   - SIGTERM may not deliver to all bg-spawned children; SIGKILL fallback.
#   - `wait` after kill cascade may return early if process is already
#     reaped — rc capture proceeds either way.
#   - tmpfile cleanup via trap RETURN handles abort/SIGTERM-to-parent paths.
dispatch_with_parallel_poll() {
  local timeout_sec="${1:-600}"
  local interval_sec="${2:-60}"
  local cmd="${3:?dispatch_with_parallel_poll: cmd required}"

  local tmpfile child_pid base_sha rc=0
  tmpfile=$(mktemp)
  chmod 600 "$tmpfile" 2>/dev/null || true
  trap 'rm -f "$tmpfile"' RETURN

  # Spawn CMD in background; capture stdout+stderr to tmpfile.
  bash -c "$cmd" >"$tmpfile" 2>&1 &
  child_pid=$!
  base_sha=$(git rev-parse HEAD 2>/dev/null || echo "INIT")

  # Poll loop: each window resets on new commit; STALE-kill if no commits.
  while kill -0 "$child_pid" 2>/dev/null; do
    if poll_orchestrator_commits "$timeout_sec" "$interval_sec" "$base_sha" >&2; then
      # New commit observed — child is making progress, reset window.
      base_sha=$(git rev-parse HEAD 2>/dev/null || echo "$base_sha")
      continue
    fi
    # poll timed out. Race: child may have completed DURING the poll
    # (poll blocks up to timeout_sec; child can exit mid-poll without
    # being detected by the outer loop's `kill -0` gate). Re-check
    # liveness before emitting STALE log + kill cascade — avoids
    # false-positive STALE on natural completion.
    if ! kill -0 "$child_pid" 2>/dev/null; then
      break  # child already exited; let `wait` capture rc cleanly.
    fi
    # STALE: no commits within timeout window AND child still alive.
    printf "[LIVENESS] STALE: no commits in %ds; killing PID %s\n" "$timeout_sec" "$child_pid" >&2
    kill -TERM "$child_pid" 2>/dev/null || true
    sleep 2
    kill -KILL "$child_pid" 2>/dev/null || true
    break
  done

  # Wait for child (natural or killed); capture rc.
  wait "$child_pid" 2>/dev/null
  rc=$?
  cat "$tmpfile"
  return "$rc"
}

fi  # ORCHESTRATOR_LIVENESS_LIB guard

# CLI entry — only when invoked directly (bash lib/orchestrator-liveness.sh).
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  set -uo pipefail
  poll_orchestrator_commits "$@"
  exit $?
fi
