# Module: Step 1C — Periodic Re-grounding (Phase 28 / P3.9 wiring)

**Activation guard:** `lib/reground.sh` is sourced AND `REGROUND_AVAILABLE=true`.

After stale-detection and before the DAG query, check whether enough iterations have elapsed since the last re-grounding. If so, emit a re-grounding block that will be prepended to the next implementer/subagent prompt to mitigate PRD drift over long sessions.

```bash
# Phase 28 wiring: re-grounding gate. Guards against PRD drift after
# many story iterations. No-op when the library is not installed.
if [[ "$REGROUND_AVAILABLE" != "false" ]]; then
  if cat "$JSON_PATH" | should_reground; then
    echo "[REGROUND] iteration gate triggered — emitting re-grounding context"
    REGROUND_BLOCK=$(cat "$JSON_PATH" | build_reground_context)
    # Stash the block for 3A.1 / 3B.2 to prepend to the implementer prompt.
    # Path is stable within this orchestrator iteration.
    printf '%s' "$REGROUND_BLOCK" > "$REPO_ROOT/.quantum-reground.md"
    mark_grounded "$JSON_PATH"
  else
    # No-op: delta below REGROUND_INTERVAL. Clear any stale file from
    # a prior iteration so 3A.1/3B.2 don't re-inject outdated context.
    rm -f "$REPO_ROOT/.quantum-reground.md"
  fi
fi
```

Tunables (all env-overrideable, defaults applied at source time):
- `REGROUND_INTERVAL=5` — re-ground every N stories
- `REGROUND_PRD_HEAD_LINES=20` — PRD excerpt length in the block
- `REGROUND_NEXT_STORIES=3` — upcoming-stories preview count

The block lives in `.quantum-reground.md` during this iteration. Sequential mode (Step 3A.1) reads it and prepends to the implementer prompt. Parallel mode (Step 3B.2) reads it and prepends to each subagent prompt. The file is cleared on the next iteration when `should_reground` returns false, preventing repeated re-grounding across consecutive iterations.

If `lib/reground.sh` is not present (older installations), `REGROUND_AVAILABLE=false` and this step is skipped — execution continues normally.
