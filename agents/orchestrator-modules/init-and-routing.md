# Module: Step 1.0.4 / 1.0.5 / 1.1 — Liveness wrapping, routing snapshot, PRD hash-check

**Activation:** runs at orchestrator init (always-on; degrades gracefully when libs absent).

### Step 1.0.4: Parent-side liveness wrapping (N6-followup / US-001 — v0.6.9)

Operators running `/ql-execute` in **unattended mode** (no human watching the orchestrator's per-iteration output) can wrap the orchestrator with a parent-side commit-poll helper. The helper detects orchestrator stale (the v0.6.7 + v0.6.8 LLM context-drift symptom — agent edits a file, sets story to `in_progress`, then stops committing) by polling git HEAD on a configurable interval.

```bash
# Library function — caller decides recovery action on stale signal.
source lib/orchestrator-liveness.sh
if poll_orchestrator_commits 600 60; then
  echo "Orchestrator alive — at least one new commit in 10 min"
else
  echo "Orchestrator STALE — read references/orchestrator-takeover.md"
fi
```

Defaults: timeout_sec=600 (10 min), interval_sec=60 (1 min), base_sha=$(git rev-parse HEAD) at call time. v0.8.0 / US-002 (N33) — optional 4th arg `WORKTREE_PATH` enables polling a worktree's HEAD instead. Returns 0 (live) or 1 (stale). Helper invocation is operator-side. Manual takeover SOP: `references/orchestrator-takeover.md`. v0.8.0 ships parent-side wiring via `quantum-loop.sh::ql_wrap_subagent_dispatch`.

### Step 1.0.5: Per-role Routing Snapshot (P5.B1 / US-009)

After sourcing `lib/runner.sh`, read the persisted routing snapshot from `quantum.json.routing` and use it as the default per-role provider when CLI flags are absent. This ports OMC v4.12.0 mechanism to make provider choice operator-visible and replayable.

```bash
SNAPSHOT=$(read_routing_snapshot "$JSON_PATH")
# CLI flags (QL_PLANNER/CRITIC/EXECUTOR) override the snapshot when set.
PLANNER="${QL_PLANNER:-$(printf '%s' "$SNAPSHOT" | jq -r '.planner // "auto"')}"
CRITIC="${QL_CRITIC:-$(printf '%s' "$SNAPSHOT" | jq -r '.critic // "auto"')}"
EXECUTOR="${QL_EXECUTOR:-$(printf '%s' "$SNAPSHOT" | jq -r '.executor // "auto"')}"

# Re-resolve to handle availability changes since the snapshot was written
ROUTING=$(resolve_routing "$PLANNER" "$CRITIC" "$EXECUTOR")
write_routing_snapshot "$JSON_PATH" "$ROUTING"

# Export for downstream consumers (lib/deep-review.sh, lib/spawn.sh)
export QL_ROLE_PLANNER=$(printf '%s' "$ROUTING" | jq -r '.planner')
export QL_ROLE_CRITIC=$(printf '%s' "$ROUTING" | jq -r '.critic')
export QL_ROLE_EXECUTOR=$(printf '%s' "$ROUTING" | jq -r '.executor')
```

If a role's provider becomes unavailable on replay, `_availability_check` falls back per role: `claude` for `planner` / `executor` (substitute a different model), `none` for `critic` (downgrade the review gate rather than substitute). Each fallback emits a one-line WARN. Replay determinism: when no CLI flags are passed, the orchestrator re-uses the prior snapshot's choices verbatim (modulo availability).

### Step 1.1: PRD Hash-Check (P5.A5 / US-005)

After reading the PRD, compute its sha256 via `compute_prd_sha` (from `lib/json-atomic.sh`) and compare against each story's `prdSha` field. This is the cheapest possible mitigation against PRD drift (RAGShield Level-1, arXiv:2604.00387).

```bash
source "$REPO_ROOT/lib/json-atomic.sh"
CURRENT_PRD_SHA=$(compute_prd_sha "$PRD_PATH")

for story_id in $(jq -r '.stories[].id' "$JSON_PATH"); do
  STORED_SHA=$(jq -r --arg id "$story_id" '.stories[] | select(.id==$id) | .prdSha // ""' "$JSON_PATH")
  if [[ -z "$STORED_SHA" || "$STORED_SHA" == "null" ]]; then
    # Backward-compat: stories without prdSha proceed unchanged. Log warning once.
    echo "[PRD-HASH] $story_id has no prdSha — proceeding (back-compat)" >&2
    continue
  fi
  # G10 / v0.6.2 — verify_prd_sha returns:
  #   "match"                  — story is up-to-date
  #   "migrate <new-sha>"      — stored is the v0.6.0 legacy form (pre-CRLF-fix);
  #                              update field instead of marking stale (transparent
  #                              upgrade for Windows users with autocrlf=true).
  #   exit 1 + stderr "drift…" — real PRD drift; mark story stale as before.
  VERIFY_RESULT=$(verify_prd_sha "$STORED_SHA" "$PRD_PATH" 2>/dev/null) || VERIFY_RESULT="drift"
  case "$VERIFY_RESULT" in
    match)
      : # silent — story is up-to-date
      ;;
    migrate*)
      NEW_SHA="${VERIFY_RESULT#migrate }"
      echo "[PRD-HASH] $story_id MIGRATE: legacy v0.6.0 prdSha format detected; updating in-place to v0.6.1+ LF-normalized hash (no re-plan needed)" >&2
      jq --arg id "$story_id" --arg sha "$NEW_SHA" '
        (.stories[] | select(.id==$id) | .prdSha) = $sha
      ' "$JSON_PATH" > "$JSON_PATH.tmp" && mv "$JSON_PATH.tmp" "$JSON_PATH"
      ;;
    *)
      echo "[PRD-HASH] $story_id WARNING: stored prdSha=${STORED_SHA:0:12} != current=${CURRENT_PRD_SHA:0:12}; marking stale (re-plan needed)" >&2
      jq --arg id "$story_id" '
        (.stories[] | select(.id==$id) | .status) = "stale"
      ' "$JSON_PATH" > "$JSON_PATH.tmp" && mv "$JSON_PATH.tmp" "$JSON_PATH"
      ;;
  esac
done
```

Stories with `status: "stale"` are excluded from the eligible-stories DAG query in Step 2. They remain in quantum.json so the operator (or `/ql-plan` re-run) can re-validate them against the updated PRD.

### Init-Guard and Resilience Integration

After branch verification and before counting stories, source the init-guard and resilience modules:

```bash
# Source init-guard module (graceful fallback)
INIT_GUARD_AVAILABLE=true
source "$REPO_ROOT/lib/init-guard.sh" 2>/dev/null || INIT_GUARD_AVAILABLE=false

# Source resilience module (graceful fallback)
RESILIENCE_AVAILABLE=true
source "$REPO_ROOT/lib/resilience.sh" 2>/dev/null || RESILIENCE_AVAILABLE=false

# Source re-grounding module (Phase 28 / P3.9 wiring, graceful fallback)
REGROUND_AVAILABLE=true
source "$REPO_ROOT/lib/reground.sh" 2>/dev/null || REGROUND_AVAILABLE=false

# Source tracecoder module (Phase 27 / P3.8 wiring, graceful fallback)
TRACECODER_AVAILABLE=true
source "$REPO_ROOT/lib/tracecoder.sh" 2>/dev/null || TRACECODER_AVAILABLE=false

# Source dead-code module (Phase 33 / P3.10 wiring, graceful fallback)
DEAD_CODE_AVAILABLE=true
source "$REPO_ROOT/lib/dead-code.sh" 2>/dev/null || DEAD_CODE_AVAILABLE=false

# Source intent-graph module (Phase 32 / P3.6 wiring, graceful fallback)
INTENT_GRAPH_AVAILABLE=true
source "$REPO_ROOT/lib/intent-graph.sh" 2>/dev/null || INTENT_GRAPH_AVAILABLE=false

# Source skeleton module (Phase 31 / P3.1 wiring, graceful fallback)
SKELETON_AVAILABLE=true
source "$REPO_ROOT/lib/skeleton.sh" 2>/dev/null || SKELETON_AVAILABLE=false

# Source trajectory module (Phase 24 / P3.5 wiring, graceful fallback)
TRAJECTORY_AVAILABLE=true
source "$REPO_ROOT/lib/trajectory.sh" 2>/dev/null || TRAJECTORY_AVAILABLE=false

# Source hyclone module (Phase 25 / P3.7 wiring, graceful fallback)
HYCLONE_AVAILABLE=true
source "$REPO_ROOT/lib/hyclone.sh" 2>/dev/null || HYCLONE_AVAILABLE=false

# Run pre-flight checks (idempotent within 1 hour)
if [[ "$INIT_GUARD_AVAILABLE" != "false" ]]; then
  run_preflight "$REPO_ROOT" "$JSON_PATH"
fi

# Check forceSequential
if jq -e '.execution.initGuard.forceSequential == true' "$JSON_PATH" 2>/dev/null; then
  echo "[ORCHESTRATOR] forceSequential=true — parallel execution disabled"
  # Force sequential mode even if 2+ stories are eligible
fi
```

`run_preflight` performs environment validation (disk space, git version, tool availability) and records results in `execution.initGuard`. It is idempotent: if `execution.initGuard.ranAt` is within the last hour, it skips re-running. If `init-guard.sh` is not present (e.g., older installations), execution continues normally without pre-flight checks.

The `forceSequential` flag, when set by `run_preflight` or manually by the user, forces the orchestrator to use sequential execution (Step 3A) even when 2+ stories are eligible. This is useful when the environment cannot support parallel worktrees (e.g., insufficient disk space or filesystem limitations).
