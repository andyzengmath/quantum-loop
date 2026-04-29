# Module: 3C.NEG1 — Wave-boundary cross-story constant scan (Phase 17 wiring, P1.1)

**Activation:** runs at every wave boundary (no module-availability guard).

Before any other wave-boundary check, scan the merged diff for divergent constants across stories — the Math-Research class where story A uses `'google'` and story B uses `'google-api-key'` for the same concept. Per-story review is blind to this because each story is correct in isolation.

```bash
# BASE is the wave's pre-merge SHA; HEAD is the post-merge tip
FINDINGS=$(bash lib/wave-boundary.sh scan "$WAVE_BASE_SHA" HEAD)
if [[ $(printf '%s' "$FINDINGS" | jq 'length') -gt 0 ]]; then
  printf '[WAVE-BOUNDARY] Divergent constants detected:\n%s\n' "$FINDINGS" >&2
  # Severity "high" (3+ variants) routes to a targeted fix-story;
  # "medium" (2 variants) is logged + passed to ql-deep-review as input.
  HIGH_COUNT=$(printf '%s' "$FINDINGS" | jq '[.[] | select(.severity=="high")] | length')
  if [[ "$HIGH_COUNT" -gt 0 ]]; then
    # Emit a fix-story via the same path as 3C.3 integration failures
    echo "[WAVE-BOUNDARY] HIGH severity — routing to fix-story." >&2
  fi
fi
```

Findings propagate into the deep-review context (Step 4B) even if non-blocking here.
