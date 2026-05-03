#!/usr/bin/env bash
# lib/iteration-loop.sh -- sequential/coordinator iteration loop body
# (v0.9.5 / US-001 decomposition refactor; spike 1).
#
# Extracted from quantum-loop.sh in v0.9.5 / US-001 (decomposition refactor;
# spike 1 from idea-stage/v0.10.0-design-spike-2026-05-01.md). Source from
# quantum-loop.sh AFTER all other lib/*.sh sources (uses next_wave from
# dag-query.sh, runner_parse_output from runner.sh, spawn_coordinator from
# spawn.sh, helpers from loop-helpers.sh, audit from audit.sh).
#
# Entry point: run_iteration_loop()
# Caller invokes: bash quantum-loop.sh dispatches via mode branch
#   (parallel mode stays in quantum-loop.sh per spike-1 scope) — sequential
#   and coordinator modes call this function.
#
# Required globals (set in quantum-loop.sh before invocation):
#   - $SCRIPT_DIR, $BRANCH, $MAX_ITERATIONS, $MAX_RETRIES, $STALE_TIMEOUT
#   - $COORDINATOR_MODE, $PARALLEL_MODE
#   - $RUNNER_NAME, $RUNNER_BINARY, $RUNNER_TIER, $RUNNER_INSTRUCTION_NATIVE
#   - $TOOL, $QL_CRITIC, $QL_PLANNER, $QL_EXECUTOR
#   - $QL_COORDINATOR_TIMEOUT_S (optional; defaulted in coordinator branch)
#
# Behavior contracts:
#   - exit 0 / exit 1 / exit 2 from inside this function terminate the
#     entire script (bash exit semantics; same as pre-extraction).
#   - continue from inside the for-loop continues to next iteration
#     (same as pre-extraction; for loop is local to this function).
#
# Library contract: no shell flags at source time; parent's set -euo pipefail
# carries through naturally.

# Source-guard
if [[ -n "${_QL_ITERATION_LOOP_LIB:-}" ]]; then
  return 0 2>/dev/null || true
fi
readonly _QL_ITERATION_LOOP_LIB=1

run_iteration_loop() {
# =============================================================================
# Sequential execution mode (original behavior)
# =============================================================================

for ITERATION in $(seq 1 "$MAX_ITERATIONS"); do
  printf "\n=== Iteration %d / %d ===\n\n" "$ITERATION" "$MAX_ITERATIONS"

  # Detect stale stories before DAG query
  detect_stale_stories

  # -------------------------------------------------------------------------
  # Select next executable story (legacy single-spawn) OR wave (coordinator)
  # -------------------------------------------------------------------------
  #
  # v0.9.0 / US-001 (N42 minor): branch on COORDINATOR_MODE.
  #   - true  → call lib/dag-query.sh::next_wave for a wave of parallel-safe
  #     story IDs; spawn coordinator (later in the loop) with the full set.
  #   - false → existing single-story selection (verbatim).
  # WAVE_STORY_IDS is the canonical wave-member array used by pre-mark,
  # case branches, and *) fallback. Under legacy mode it has 1 element
  # (the selected $STORY_ID) so multi-story logic still works correctly.

  WAVE_STORY_IDS_JSON=""    # JSON array string; set under both modes
  WAVE_ID=""                # Only set under coordinator mode

  if [[ "$COORDINATOR_MODE" == "true" ]]; then
    # next_wave returns rc=0 (wave) | 1 (COMPLETE) | 2 (BLOCKED).
    # Output: JSON array of story IDs (only on rc=0).
    WAVE_STORY_IDS_JSON=$(next_wave quantum.json) || NEXT_WAVE_RC=$?
    NEXT_WAVE_RC="${NEXT_WAVE_RC:-0}"
    case "$NEXT_WAVE_RC" in
      0)
        STORY_ID=$(echo "$WAVE_STORY_IDS_JSON" | jq -r '.[0]')
        WAVE_ID="wave-${ITERATION}"
        ;;
      1)
        final_verification_sweep
        emit_terminal_signal "COMPLETE" "All stories passed! Feature is done."
        print_summary_table
        exit 0
        ;;
      *)
        emit_terminal_signal "BLOCKED" \
          "$(printf 'No executable stories remain (next_wave rc=%s).' "$NEXT_WAVE_RC")"
        print_summary_table
        exit 1
        ;;
    esac
    unset NEXT_WAVE_RC
  else
    STORY_ID=$(jq -r '
      .stories as $all |
      [.stories[] |
        select(
          (.status == "pending" or (.status == "failed" and .retries.attempts < .retries.maxAttempts)) and
          (if (.dependsOn | length) == 0 then true
           else [.dependsOn[] | . as $dep | $all | map(select(.id == $dep)) | .[0].status] | all(. == "passed")
           end)
        )
      ] |
      sort_by(.priority) |
      .[0].id // empty
    ' quantum.json)

    # Validate story ID format to prevent jq injection in downstream json_atomic_update calls
    if [[ -n "$STORY_ID" && "$STORY_ID" != "null" && ! "$STORY_ID" =~ ^[A-Za-z0-9_-]+$ ]]; then
      printf "ERROR: invalid story ID format: %s\n" "$STORY_ID" >&2
      exit 1
    fi

    if [[ -z "$STORY_ID" || "$STORY_ID" == "null" ]]; then
      # Check if all stories are passed
      ALL_PASSED=$(jq '[.stories[].status] | all(. == "passed")' quantum.json)
      if [[ "$ALL_PASSED" == "true" ]]; then
        final_verification_sweep
        emit_terminal_signal "COMPLETE" "All stories passed! Feature is done."
        print_summary_table
        exit 0
      else
        emit_terminal_signal "BLOCKED" "No executable stories remain."
        print_summary_table
        exit 1
      fi
    fi

    # Legacy mode: synthesize a 1-element wave array from $STORY_ID so
    # multi-story logic (pre-mark, case branches) works uniformly.
    WAVE_STORY_IDS_JSON=$(jq -nc --arg sid "$STORY_ID" '[$sid]')
  fi

  STORY_TITLE=$(jq -r --arg id "$STORY_ID" '.stories[] | select(.id == $id) | .title' quantum.json)
  STORY_ATTEMPT=$(jq -r --arg id "$STORY_ID" '.stories[] | select(.id == $id) | .retries.attempts' quantum.json)

  # v0.9.4 / US-002 (post-v0.9.x audit code-reviewer HIGH): under coordinator
  # mode, STORY_ID is `.[0]` of the wave only — printing per-story metadata
  # here would mislead the operator about the wave (stories 2..N invisible).
  # The wave-level summary at the spawn block (~line 1591) prints the full
  # wave under coordinator mode. Gate the legacy single-story metadata
  # print behind non-coord mode. Symmetric with v0.9.1 US-003's "Spawning"
  # printf gate.
  if [[ "$COORDINATOR_MODE" != "true" ]]; then
    printf "Story:   %s - %s\n" "$STORY_ID" "$STORY_TITLE"
    printf "Attempt: %d\n" "$((STORY_ATTEMPT + 1))"
    printf "\n"
  fi

  # Mark wave story/stories as in_progress (multi-story under coordinator
  # mode; single-story under legacy). v0.9.0 / US-001 (N42 minor) — uses
  # WAVE_STORY_IDS_JSON which is always a JSON array (1-element under
  # legacy, N-element under coordinator).
  now=$(date -u +'%Y-%m-%dT%H:%M:%SZ')
  json_atomic_update_args '
    .stories |= map(
      if (.id as $sid | $ids | index($sid))
      then .status = "in_progress" | .startedAt = $now
      else . end
    ) |
    .updatedAt = (now | todate)
  ' quantum.json --argjson ids "$WAVE_STORY_IDS_JSON" --arg now "$now"

  # -------------------------------------------------------------------------
  # Spawn fresh AI instance
  # -------------------------------------------------------------------------

  # v0.9.1 / US-003 (post-v0.9.0 dogfood finding 5b): gate this legacy
  # single-story print under non-coordinator mode. Under coordinator
  # dispatch, the spawn block prints its own "Spawning coordinator for
  # wave-N with K story/stories: ..." message, which is more accurate
  # than this single-story framing.
  if [[ "$COORDINATOR_MODE" != "true" ]]; then
    printf "Spawning %s for story %s...\n" "$RUNNER_NAME" "$STORY_ID"
  fi

  RUNNER_EXIT=0
  if [[ "$COORDINATOR_MODE" == "true" ]]; then
    # v0.9.0 / US-001 (N42 minor): per-wave coordinator dispatch.
    # spawn_coordinator returns a command STRING (via runner_build_cmd or
    # fallback printf) — not an execution. Caller evals it synchronously.
    # The coordinator spawns implementer subagents internally per wave;
    # parent loop blocks until coordinator emits WAVE_PASSED/WAVE_FAILED.
    STORY_IDS_STR=$(echo "$WAVE_STORY_IDS_JSON" | jq -r 'join(" ")')
    PRD_PATH=$(jq -r '.prdPath // "tasks/prd.md"' quantum.json)
    COORD_CMD=$(spawn_coordinator "$WAVE_ID" "$STORY_IDS_STR" "$PRD_PATH" quantum.json) || {
      printf "ERROR: spawn_coordinator failed for wave %s\n" "$WAVE_ID" >&2
      continue
    }
    printf "Spawning coordinator for %s with %d story/stories: %s\n" "$WAVE_ID" "$(echo "$WAVE_STORY_IDS_JSON" | jq 'length')" "$STORY_IDS_STR"
    # v0.9.5 / US-002: parent-side defense-in-depth for HEAD-snapshot guard.
    # Capture HEAD BEFORE coordinator dispatch. Even if the coordinator skips
    # the LLM-side guard_head_advance instruction (per agents/coordinator.md
    # step 2) — e.g., model drift, escaped worktree, or rogue implementer —
    # the parent will detect a destructive `git reset --hard` post-eval (see
    # the post-runner_parse_output gate ~line 1675). Captures empty when the
    # CWD is not a git repo (test fixtures); guard skips on empty.
    HEAD_BEFORE_COORD=$(git rev-parse HEAD 2>/dev/null || echo "")
    # v0.10.8 / US-001 (N48): field-ownership runtime enforcement (defense-
    # in-depth complement to v0.9.5 parent-side HEAD guard). Snapshot the
    # parent-owned fields (status, retries.*) for wave stories BEFORE
    # coordinator dispatch. After dispatch, compare; if changed, the
    # coordinator violated the field-ownership contract documented in
    # agents/coordinator.md § "quantum.json field ownership" (parent owns
    # status + retries; coordinator owns review.*). WARN-only — does NOT
    # alter signal classification or abort. Observability-only.
    PARENT_OWNED_BEFORE=$(jq -c \
      --argjson ids "$WAVE_STORY_IDS_JSON" \
      '[.stories[] | select(.id as $id | $ids | index($id)) | {id, status, retries}]' \
      quantum.json 2>/dev/null || echo "[]")
    # v0.9.3 / US-001: wallclock timeout guard. Default 30 min ceiling
    # (configurable via QL_COORDINATOR_TIMEOUT_S env). On rc=124 (SIGTERM
    # kill from `timeout`), the override below sets SIGNAL_RESULT to
    # WAVE_FAILED so per-story aggregation runs from review fields. Closes
    # v0.9.2 dogfood iter-3 hang (coordinator subagent stuck > 3 hours).
    # v0.9.3 / US-003 review fixes: validate numeric (default 1800 on bad
    # input) + degrade gracefully if `timeout` is not on PATH (warn + run
    # without wallclock guard).
    QL_COORDINATOR_TIMEOUT_S="${QL_COORDINATOR_TIMEOUT_S:-1800}"
    if ! [[ "$QL_COORDINATOR_TIMEOUT_S" =~ ^[0-9]+$ ]]; then
      printf "WARN: QL_COORDINATOR_TIMEOUT_S must be a non-negative integer (got '%s'); using default 1800.\n" "$QL_COORDINATOR_TIMEOUT_S" >&2
      QL_COORDINATOR_TIMEOUT_S=1800
    fi
    # v0.9.6 / US-003 LOW absorb: bash -c spawns a subshell — locals from
    # this function (run_iteration_loop) are NOT inherited; rely on env
    # vars and positional args inside $COORD_CMD (which spawn_coordinator
    # constructs accordingly).
    if command -v timeout >/dev/null 2>&1; then
      OUTPUT=$(timeout --kill-after=10s "${QL_COORDINATOR_TIMEOUT_S}s" bash -c "$COORD_CMD" 2>&1) || RUNNER_EXIT=$?
    else
      printf "WARN: timeout(1) not on PATH; coordinator dispatch running without wallclock guard. v0.9.2 iter-3 hang scenario possible.\n" >&2
      OUTPUT=$(bash -c "$COORD_CMD" 2>&1) || RUNNER_EXIT=$?
    fi
  elif [[ "$RUNNER_NAME" == "claude" ]]; then
    # Claude Code: preserve original command structure — CLAUDE.md via -p, story instruction via --
    PROMPT_FILE="$SCRIPT_DIR/CLAUDE.md"
    OUTPUT=$(claude --dangerously-skip-permissions --print \
      -p "$(cat "$PROMPT_FILE")" \
      -- "Implement story $STORY_ID from quantum.json. This is iteration $ITERATION." 2>&1) || RUNNER_EXIT=$?
  else
    # Non-Claude runners: use runner adapter with preamble injection
    AGENT_PROMPT="Implement story $STORY_ID from quantum.json. This is iteration $ITERATION."
    RUNNER_CMD=$(runner_build_cmd "$AGENT_PROMPT") || {
      printf "ERROR: runner_build_cmd failed for %s\n" "$RUNNER_NAME" >&2
      continue
    }
    # v0.11.1 / US-002 (N43): opt-in parallel-with-dispatch wrap.
    # When QL_PARALLEL_POLL=true, dispatch runs in bg + commit-poll runs
    # in fg + stuck child is killed via SIGTERM/SIGKILL cascade. Default
    # OFF preserves backwards compat (Git Bash bg-process supervision is
    # known fragile; opt-in lets operators try it on stable hosts).
    if [[ "${QL_PARALLEL_POLL:-false}" == "true" ]]; then
      local _ppoll_timeout="${QL_PARALLEL_POLL_TIMEOUT_S:-600}"
      local _ppoll_interval="${QL_PARALLEL_POLL_INTERVAL_S:-60}"
      OUTPUT=$(dispatch_with_parallel_poll "$_ppoll_timeout" "$_ppoll_interval" "$RUNNER_CMD" 2>&1) || RUNNER_EXIT=$?
    else
      OUTPUT=$(eval "$RUNNER_CMD" 2>&1) || RUNNER_EXIT=$?
    fi
  fi

  # -------------------------------------------------------------------------
  # Process output
  # -------------------------------------------------------------------------

  # Invoke post_output() hook if defined (for non-Claude runners with hooks)
  if [[ "$RUNNER_NAME" != "claude" ]]; then
    local hooks_dir="${SCRIPT_DIR}/runners/hooks"
    local hook_file="${hooks_dir}/${RUNNER_NAME}-hooks.sh"
    if [[ -f "$hook_file" ]]; then
      # shellcheck source=/dev/null
      source "$hook_file"
      if type post_output &>/dev/null; then
        post_output "$OUTPUT"
      fi
      unset -f post_output pre_spawn 2>/dev/null
    fi
    # Check if hook forced a signal override
    if [[ -n "${RUNNER_OVERRIDE_SIGNAL:-}" ]]; then
      SIGNAL_RESULT="$RUNNER_OVERRIDE_SIGNAL"
      SIGNAL_CONFIDENCE="hook"
      RUNNER_OVERRIDE_SIGNAL=""
    fi
  fi

  # Parse runner output for signals (uses heuristics if enabled for non-Claude runners)
  runner_parse_output "$OUTPUT" "$RUNNER_EXIT"

  # v0.9.3 / US-001: timeout override. If `timeout` killed the coordinator
  # subagent (rc=124), force SIGNAL_RESULT=WAVE_FAILED regardless of what
  # runner_parse_output classified the (possibly empty/partial) output as.
  # This ensures the WAVE_FAILED branch's per-story review-field aggregation
  # runs uniformly. Closes v0.9.2 dogfood iter-3 hang.
  # v0.9.6 / US-003 LOW absorb: $RUNNER_EXIT is unconditionally initialized
  # to 0 at line 172 before all dispatch sites (208/211/218/226), so the
  # `${VAR:-0}` default is redundant. Simplified to direct expansion.
  if [[ "$COORDINATOR_MODE" == "true" && "$RUNNER_EXIT" == "124" ]]; then
    printf "ERROR: Coordinator subagent exceeded %ss timeout; marking wave failed.\n" "$QL_COORDINATOR_TIMEOUT_S" >&2
    SIGNAL_RESULT="WAVE_FAILED"
  fi

  # v0.10.8 / US-001 (N48): field-ownership runtime enforcement diff check.
  # Compare PARENT_OWNED_BEFORE (captured pre-dispatch) against current
  # state. If different, coordinator violated the field-ownership contract
  # by writing parent-owned fields (status, retries.*). WARN-only;
  # parent's per-story aggregation below still runs uniformly.
  if [[ "$COORDINATOR_MODE" == "true" && -n "${PARENT_OWNED_BEFORE:-}" ]]; then
    PARENT_OWNED_AFTER=$(jq -c \
      --argjson ids "$WAVE_STORY_IDS_JSON" \
      '[.stories[] | select(.id as $id | $ids | index($id)) | {id, status, retries}]' \
      quantum.json 2>/dev/null || echo "[]")
    if [[ "$PARENT_OWNED_BEFORE" != "$PARENT_OWNED_AFTER" ]]; then
      printf "[FIELD-OWNERSHIP] WARN: parent-owned fields modified during dispatch (coordinator contract violation)\n" >&2
      printf "  before: %s\n" "$PARENT_OWNED_BEFORE" >&2
      printf "  after:  %s\n" "$PARENT_OWNED_AFTER" >&2
      # v0.11.5 / US-001 (Pre-Path-B): opt-in escalation via env var.
      # Default OFF preserves v0.10.8 WARN-only behavior (Tests 9+10).
      # Operator queuing real-feature dispatch (Path B) sets
      # QL_FIELD_OWNERSHIP_STRICT=true for hardened data-integrity guarantee
      # (silent acceptance of contract violation could leave quantum.json
      # inconsistent under real-coordinator dispatch). Pattern-consistent
      # with v0.11.1 N43 QL_PARALLEL_POLL opt-in design.
      if [[ "${QL_FIELD_OWNERSHIP_STRICT:-false}" == "true" ]]; then
        printf "[FIELD-OWNERSHIP] FAIL: strict mode enabled (QL_FIELD_OWNERSHIP_STRICT=true); forcing WAVE_FAILED\n" >&2
        SIGNAL_RESULT="WAVE_FAILED"
        SIGNAL_CONFIDENCE="exact"
      fi
    fi
    unset PARENT_OWNED_AFTER
  fi

  # v0.9.5 / US-002: parent-side HEAD-snapshot guard (defense-in-depth).
  # Removes the LLM-instruction-following dependency for the safety-critical
  # check that v0.9.2 introduced via agents/coordinator.md step 2. Compares
  # captured HEAD_BEFORE_COORD (from before eval) against current HEAD via
  # `git merge-base --is-ancestor` (see lib/coordinator-guard.sh). On
  # non-ancestor (i.e., destructive reset by coordinator or escaped
  # implementer): print ERROR, force WAVE_FAILED so per-story aggregation
  # runs from review.* fields. Empty HEAD_BEFORE_COORD (non-git context) =>
  # skip; the LLM-side guard remains active for that path.
  if [[ "$COORDINATOR_MODE" == "true" && -n "${HEAD_BEFORE_COORD:-}" ]]; then
    # shellcheck source=lib/coordinator-guard.sh
    source "$SCRIPT_DIR/lib/coordinator-guard.sh"
    # v0.9.5 / US-004 review fix (security MEDIUM): do NOT redirect guard
    # stderr to /dev/null — the guard's own diagnostic ("HEAD reset
    # detected — <SHA1> not ancestor of <SHA2>") is operationally useful
    # for distinguishing reset-detected vs git-not-on-PATH vs corrupt-repo.
    # Parent's printf below adds the captured SHAs as additional context.
    if ! guard_head_advance "$HEAD_BEFORE_COORD"; then
      _HEAD_AFTER_COORD=$(git rev-parse HEAD 2>/dev/null || echo "")
      printf "ERROR: Parent-side HEAD guard fired. HEAD_BEFORE=%s HEAD_AFTER=%s\n" \
        "$HEAD_BEFORE_COORD" "$_HEAD_AFTER_COORD" >&2
      SIGNAL_RESULT="WAVE_FAILED"
      unset _HEAD_AFTER_COORD
    fi
  fi

  # ql_wrap_subagent_dispatch soft-fire — v0.8.1 wire + v0.9.0/v0.9.3 gating.
  # ---------------------------------------------------------------------------
  # v0.8.1 / US-001 (N39 dogfood): wire `ql_wrap_subagent_dispatch` into the
  # production runner loop. The function was defined in v0.8.0 US-001 but
  # had zero callers in quantum-loop.sh — exactly N33 root cause #1
  # repeating.
  #
  # v0.8.1 / US-006 (post-PR-review guard fix):
  # The original guard was `[[ -z "$SIGNAL_RESULT" ]]` which is always false
  # because runner_parse_output ALWAYS sets SIGNAL_RESULT before returning
  # (exact match, heuristic fallback, or "STORY_FAILED" no-signal default).
  # The corrected guard fires on STORY_FAILED with non-exact confidence —
  # the actual "drift suspect" condition: the runner failed but we used
  # heuristics or fallback to classify it.
  #
  # v0.10.11 / US-001 (N46 CLOSED): when QL_RESPAWN_CMD is set and the
  # wrap respawns successfully, the respawn's stdout/stderr is now
  # captured via tee + re-fed through runner_parse_output, so
  # SIGNAL_RESULT/SIGNAL_CONFIDENCE reflect the respawned run. See
  # lib/orchestrator-liveness.sh::wrap_orchestrator_dispatch.
  #
  # v0.9.0 / US-001 (N42 minor) — skip wrap under coordinator mode:
  # The coordinator handles its own internal retries (per
  # agents/coordinator.md), and the wrap's QL_RESPAWN_CMD path was
  # designed for single-story respawn — re-running it under coordinator
  # mode would re-spawn the entire wave with stale story arguments.
  # N46 (respawn output re-parsing) closed in v0.10.11; coordinator-mode
  # skip remains correct policy independent of the N46 closure.
  #
  # v0.9.3 / US-002 follow-up — gate kept OFF, rationale documented:
  # STALE detection is unsafe under coordinator mode — the coordinator
  # may legitimately spend minutes aggregating signals + writing review
  # fields without producing new commits, which would false-positive STALE.
  # The v0.9.3 US-001 wallclock timeout (QL_COORDINATOR_TIMEOUT_S, default
  # 1800s) is the operational alternative: blanket wallclock kill rather
  # than commit-progress poll. (N46 closed in v0.10.11; the coordinator-mode
  # skip rationale here is unrelated and remains in force.)
  if [[ "$COORDINATOR_MODE" != "true" \
        && "${SIGNAL_RESULT:-}" == "STORY_FAILED" \
        && "${SIGNAL_CONFIDENCE:-}" != "exact" ]]; then
    ql_wrap_subagent_dispatch 5 1 "" >&2 || true
  fi

  # v0.9.2 / US-002 (defense-in-depth): STORY_* signals are unexpected under
  # coordinator mode (the coordinator contract requires WAVE_* signals).
  # If a STORY_* signal somehow surfaces (coordinator bug, prompt drift,
  # parser misroute), the legacy single-story case branches use scalar
  # $STORY_ID — under coordinator mode that's only the wave's first story,
  # so the other wave members would be orphaned `in_progress`. Redirect
  # to WAVE_FAILED branch so the per-story review-field aggregation runs
  # uniformly across all wave members.
  if [[ "$COORDINATOR_MODE" == "true" && "${SIGNAL_RESULT:-}" =~ ^(STORY_PASSED|STORY_FAILED|BLOCKED)$ ]]; then
    printf "WARNING: Unexpected %s under coordinator mode (expected WAVE_*). Wave members may be orphaned. Treating as WAVE_FAILED for per-story aggregation.\n" "$SIGNAL_RESULT" >&2
    SIGNAL_RESULT="WAVE_FAILED"
  fi

  case "$SIGNAL_RESULT" in
    COMPLETE)
      final_verification_sweep
      emit_terminal_signal "COMPLETE" "All stories passed! Feature is done."
      print_summary_table
      exit 0
      ;;
    STORY_PASSED)
      printf "Story %s PASSED. Continuing to next story...\n" "$STORY_ID"
      json_atomic_update ".stories |= map(if .id == \"$STORY_ID\" then .status = \"passed\" | .startedAt = null else . end)"
      ;;
    STORY_FAILED)
      printf "Story %s FAILED (attempt %d). Will retry if attempts remain.\n" "$STORY_ID" "$((STORY_ATTEMPT + 1))"
      json_atomic_update ".stories |= map(if .id == \"$STORY_ID\" then .status = \"failed\" | .startedAt = null | .retries.attempts += 1 | .retries.failureLog += [{\"phase\": \"agent_failed\", \"timestamp\": (now | todate)}] else . end)"
      ;;
    BLOCKED)
      json_atomic_update ".stories |= map(if .id == \"$STORY_ID\" then .startedAt = null else . end)"
      emit_terminal_signal "BLOCKED" "Agent reports no executable stories."
      print_summary_table
      exit 1
      ;;
    WAVE_PASSED)
      # v0.9.0 / US-003 (N42 minor): multi-story aggregation. Bulk-update
      # ALL wave stories to status=passed via a single jq pass, indexed by
      # WAVE_STORY_IDS_JSON (1-element under legacy mode, N-element under
      # coordinator mode). Replaces v0.8.3's single-story-progressing
      # placeholder.
      WAVE_LEN=$(echo "$WAVE_STORY_IDS_JSON" | jq 'length')
      printf "Wave (%s) PASSED — %d story/stories: %s\n" \
        "${WAVE_ID:-iteration-$ITERATION}" "$WAVE_LEN" "$(echo "$WAVE_STORY_IDS_JSON" | jq -r 'join(", ")')"
      now=$(date -u +'%Y-%m-%dT%H:%M:%SZ')
      json_atomic_update_args '
        .stories |= map(
          if (.id as $sid | $ids | index($sid))
          then .status = "passed" | .startedAt = null
          else . end
        ) |
        .updatedAt = $now
      ' quantum.json --argjson ids "$WAVE_STORY_IDS_JSON" --arg now "$now"
      ;;
    WAVE_FAILED)
      # v0.8.3 / US-001 (4th-layer N33 closure): wave-level failure signal.
      # v0.9.0 / US-003 (N42 minor) — per-story aggregation via Option A:
      # the coordinator owns review.specCompliance + review.codeQuality
      # writes (per agents/coordinator.md field-ownership contract). For
      # each wave story, derive status from those review fields:
      #   review.{spec,quality}.status == "passed" → status=passed
      #   else → status=failed + retries.attempts++ + failureLog append
      # Stories that the coordinator never reached (no review timestamp)
      # are conservatively marked failed (parent cannot infer success
      # from missing data).
      WAVE_LEN=$(echo "$WAVE_STORY_IDS_JSON" | jq 'length')
      printf "Wave (%s) FAILED — %d story/stories. Per-story outcome derived from review fields.\n" \
        "${WAVE_ID:-iteration-$ITERATION}" "$WAVE_LEN"
      now=$(date -u +'%Y-%m-%dT%H:%M:%SZ')
      json_atomic_update_args '
        .stories |= map(
          if (.id as $sid | $ids | index($sid)) then
            if (.review.specCompliance.status == "passed"
                and .review.codeQuality.status == "passed") then
              .status = "passed" | .startedAt = null
            else
              .status = "failed" | .startedAt = null
              | .retries.attempts += 1
              | .retries.failureLog += [{"phase": "wave_failed", "timestamp": $now}]
            end
          else . end
        ) |
        .updatedAt = $now
      ' quantum.json --argjson ids "$WAVE_STORY_IDS_JSON" --arg now "$now"
      ;;
    *)
      # v0.8.1 / US-006 (post-PR-review fix): increment retries.attempts and
      # append to failureLog so a story that repeatedly hits the unknown-signal
      # branch eventually exhausts retries and surfaces as BLOCKED.
      #
      # v0.9.0 / US-001 (N42 minor): apply retry accounting to ALL wave
      # stories (not just $STORY_ID) under coordinator mode. The original
      # single-story logic referenced $STORY_ID which under coordinator
      # mode is set to the wave's first story only — leaving other wave
      # members orphaned in_progress (HIGH risk per architect 1's design
      # review). The new jq uses WAVE_STORY_IDS_JSON which is 1-element
      # under legacy mode (preserves existing semantics).
      printf "WARNING: No recognized signal in output. Wave may not have completed cleanly.\n"
      printf "Last 10 lines of output:\n"
      echo "$OUTPUT" | tail -10
      now=$(date -u +'%Y-%m-%dT%H:%M:%SZ')
      json_atomic_update_args '
        .stories |= map(
          if (.id as $sid | $ids | index($sid))
          then .status = "failed" | .startedAt = null
               | .retries.attempts += 1
               | .retries.failureLog += [{"phase": "no_signal", "timestamp": $now}]
          else . end
        ) |
        .updatedAt = $now
      ' quantum.json --argjson ids "$WAVE_STORY_IDS_JSON" --arg now "$now"
      ;;
  esac

  # Brief pause between iterations
  sleep 2
done

# v0.10.1 / US-001 T-001-1: closes IDEA_REPORT_v34 'all migrated' claim
# gap (parallel-mode.sh was migrated in v0.10.0, iteration-loop.sh side
# missed). Symmetric with parallel-mode.sh:423-424.
emit_terminal_signal "MAX_ITERATIONS" \
  "$(printf 'Reached maximum of %d iterations.' "$MAX_ITERATIONS")"
print_summary_table
generate_observations
exit 2
}
