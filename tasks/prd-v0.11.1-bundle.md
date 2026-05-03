# PRD: v0.11.1 — patch-tier (N43: parallel-with-dispatch wrap pattern)

**Status:** Operator-approved (Path A). Architectural follow-on to v0.11.0 first-dispatch milestone.
**Date:** 2026-05-02
**Predecessor:** `tasks/prd-v0.11.0-bundle.md`.
**Branch:** `ql/v0.11.1-bundle`.
**Target version:** 0.11.0 → 0.11.1 (patch; opt-in feature with backwards-compat default off).
**Total effort:** ~2 hours.

## Section 1: Introduction / Overview

4-story patch closing **N43** (parallel-with-dispatch wrap pattern; deferred MEDIUM since v0.8.1; tracked through 8+ IDEA_REPORTs). Implements pre-emptive stuck-agent detection via background dispatch + foreground commit-poll + kill-on-STALE. Opt-in via env var to preserve backwards compatibility on Git Bash where bg-process supervision is fragile.

**Architecture rationale:** Current `ql_wrap_subagent_dispatch` (v0.8.1) is post-dispatch — fires AFTER runner returns, only as diagnostic. N43's parallel-with-dispatch design proactively kills stuck agents before they exhaust the iteration budget.

## Section 2: Goals

- Add `lib/orchestrator-liveness.sh::dispatch_with_parallel_poll` function with contract:
  - Spawns CMD in background; captures stdout+stderr to tmpfile.
  - Polls commits in foreground via existing `poll_orchestrator_commits`.
  - Resets poll window on each new commit (commit-progress = liveness signal).
  - Kills child via `SIGTERM` then `SIGKILL` if no commits within timeout window.
  - Returns child's rc (or 143/137 on signal-kill).
- Wire opt-in via `QL_PARALLEL_POLL=true` env var at the LEGACY (non-coordinator) dispatch site in `lib/iteration-loop.sh`.
- Default OFF: existing behavior preserved unless operator opts in.
- Test coverage: hung-implementer scenario + clean-completion scenario.
- 26th p014 review.
- Bump 0.11.0 → 0.11.1.
- 45 consecutive LOW G30.

## Section 3: User Stories

### US-001: `dispatch_with_parallel_poll` function

**Acceptance Criteria:**
- [ ] New function `dispatch_with_parallel_poll TIMEOUT_SEC INTERVAL_SEC CMD` in `lib/orchestrator-liveness.sh` (after `wrap_orchestrator_dispatch`).
- [ ] Behavior:
  - `mktemp` + `chmod 600` for tmpfile (security pattern from v0.10.11 N46).
  - `trap 'rm -f "$tmpfile"' RETURN` (cleanup).
  - `bash -c "$cmd" >"$tmpfile" 2>&1 &`; capture `$!` as child_pid.
  - Outer loop: while child alive, run `poll_orchestrator_commits TIMEOUT_SEC INTERVAL_SEC BASE_SHA`. On commit (return 0), reset BASE_SHA + continue. On STALE (return 1), `kill -TERM child_pid`, `sleep 2`, `kill -KILL child_pid`, `break`.
  - After loop: `wait child_pid 2>/dev/null`; capture rc.
  - Print captured output via `cat "$tmpfile"`.
  - Return child's rc.
- [ ] Output captured + emitted on stdout (caller can capture with `$(...)`).
- [ ] STALE log emitted to stderr: `[LIVENESS] STALE: no commits in Ns; killing PID X`.
- [ ] Graceful when `poll_orchestrator_commits` not in scope (impossible by design; same lib file). N/A.
- [ ] `bash -n lib/orchestrator-liveness.sh` clean.

### US-002: Wire opt-in at legacy dispatch site + tests

**Acceptance Criteria:**
- [ ] `lib/iteration-loop.sh` legacy dispatch (~line 242, the `eval "$RUNNER_CMD"` site): conditional invocation via `QL_PARALLEL_POLL=true`. When set, replace `OUTPUT=$(eval "$RUNNER_CMD" 2>&1) || RUNNER_EXIT=$?` with a call to `dispatch_with_parallel_poll`.
- [ ] Default OFF: when `QL_PARALLEL_POLL` is unset or empty, existing behavior unchanged.
- [ ] New tests in `tests/test_orchestrator_liveness.sh`:
  - Test 16: clean-completion path (CMD exits 0 with output; rc=0 propagates; output captured).
  - Test 17: STALE-kill path (CMD `sleep 30`; timeout=2; assert rc != 0 + STALE log emitted within ~6 sec wallclock).
  - Test 18: commit-progress reset (CMD makes commits during poll; verify each commit resets the timeout window; CMD completes naturally without kill).
- [ ] `bash tests/test_orchestrator_liveness.sh` rc=0; 38 → 41 tests (3 new).

### US-003: Multi-perspective post-merge review (26th application)

**Acceptance Criteria:**
- [ ] 3 reviewer agents (architect + code-reviewer + security) invoked in parallel.
- [ ] Architect specifically: validate kill cascade is correct on Git Bash (SIGTERM with timeout vs SIGKILL fallback) + commit-progress reset semantics.
- [ ] No score-≥85 finding deferred.

### US-004: Retrospective + IDEA_REPORT_v51 + version bump 0.11.0 → 0.11.1

**Acceptance Criteria:**
- [ ] `idea-stage/PIPELINE_REPORT_v51.md` documents v0.11.1 (4 stories) + N43 closure + bg-process supervision design notes.
- [ ] `idea-stage/IDEA_REPORT_v51.md` rolling forward state.
- [ ] `CHANGELOG.md [0.11.1]` entry.
- [ ] 4 plugin manifest version fields bumped 0.11.0 → 0.11.1.
- [ ] G30 self-validation (45th consecutive LOW expected).

## Section 4: Functional Requirements

- **FR-1:** N43 implementation is opt-in (default OFF) for backwards compat.
- **FR-2:** When opt-in active, dispatch is parallelized: child runs in bg, parent polls in fg, kill fires on STALE.
- **FR-3:** Commit-progress signals liveness; timeout window resets on each new commit.
- **FR-4:** Kill cascade: SIGTERM → 2-sec wait → SIGKILL fallback.
- **FR-5:** Output capture preserved (stdout+stderr to tmpfile, cat'd to function stdout).
- **FR-6:** Plugin version 0.11.0 → 0.11.1 (4 fields).

## Section 5: Non-Goals

- No coordinator-mode integration (coordinator already has wallclock kill via `QL_COORDINATOR_TIMEOUT_S`).
- No retroactive rewrite of `ql_wrap_subagent_dispatch` post-dispatch wire (still useful as diagnostic).
- No multi-child supervision (single child per dispatch).
- No bg-job orchestration (no `wait -n`, no parallel children).

## Section 6: Design Notes

**Function signature:**
```bash
# dispatch_with_parallel_poll TIMEOUT_SEC INTERVAL_SEC CMD
# Spawns CMD in bg, polls commits in fg, kills on STALE.
# Output captured to tmpfile, emitted on stdout. Returns child's rc.
dispatch_with_parallel_poll() {
  local timeout_sec="$1" interval_sec="$2" cmd="$3"
  local tmpfile child_pid base_sha rc=0
  tmpfile=$(mktemp); chmod 600 "$tmpfile" 2>/dev/null || true
  trap 'rm -f "$tmpfile"' RETURN
  
  bash -c "$cmd" >"$tmpfile" 2>&1 &
  child_pid=$!
  base_sha=$(git rev-parse HEAD 2>/dev/null || echo "INIT")
  
  while kill -0 "$child_pid" 2>/dev/null; do
    if poll_orchestrator_commits "$timeout_sec" "$interval_sec" "$base_sha" >&2; then
      base_sha=$(git rev-parse HEAD 2>/dev/null || echo "$base_sha")
      continue
    fi
    printf "[LIVENESS] STALE: no commits in %ds; killing PID %s\n" "$timeout_sec" "$child_pid" >&2
    kill -TERM "$child_pid" 2>/dev/null || true
    sleep 2
    kill -KILL "$child_pid" 2>/dev/null || true
    break
  done
  
  wait "$child_pid" 2>/dev/null; rc=$?
  cat "$tmpfile"
  return "$rc"
}
```

**Git Bash bg-process gotchas (mitigated):**
- `kill -0 PID` works on Git Bash for liveness check.
- `kill -TERM` may not deliver to bg processes spawned via `bash -c` if the child has already established its own session; SIGKILL fallback handles this.
- `wait` after `kill` may return 0 if the process is already reaped; that's why we capture rc separately.
- tmpfile race: trap RETURN cleans up on all exit paths.

**Wire site rationale:** legacy mode (line 242) is the right wire — coordinator mode (line 224) already has wallclock kill via `timeout(1)`. Wiring N43 there would be redundant.

## Section 7: Technical Notes

Bash 4.3+. POSIX `kill`, `wait`. `git rev-parse HEAD` (already a hard dep).

## Section 8: Success Metrics

- All 4 stories first-attempt PASS (or first-attempt-after-review).
- `tests/test_orchestrator_liveness.sh`: 38 → 41 tests (3 new).
- 6 baseline test suites green: 175 + 41 = 216.
- 45 consecutive LOW G30.
- N43 CLOSED (was deferred MEDIUM since v0.8.1).
