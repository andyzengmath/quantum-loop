# Module: Step 4B — Full-Feature Code Review

**Activation:** runs after Step 4 passes (always-on; Step 4B.5 deep-review dispatch is gated by `should_dispatch_deep_review`).

After Step 4 passes, run a holistic review of the **entire feature branch diff** — not per-story, but the combined change set. Per-story reviews catch local issues; this step catches cross-story problems that only emerge when viewed as a whole.

```bash
git diff main...HEAD --stat    # overview of all files changed
git diff main...HEAD           # full diff for review
```

### 4B.1: Cross-Story Consistency
- **Naming:** Did parallel agents use different names for the same concept? (e.g., `image_mode` vs `imageMode`, `_build_images_used` vs `_create_image_refs`)
- **Duplicate logic:** Did two stories implement overlapping helpers or utility functions? If so, consolidate into one and update callers.
- **Contradictory design:** Did one story return a list where another expects a dict? Check type consistency across story boundaries.

### 4B.2: Architecture Coherence
- Read the PRD goals section. For each goal, verify the combined implementation achieves it end-to-end (not just per-story acceptance criteria).
- Check that the feature's data flow is complete: config → filtering → generation → validation → output. No stage should be half-wired.
- Verify backward compatibility: run the test suite with the feature **disabled** (default config) and confirm identical behavior to the base branch.

### 4B.3: Security and Quality
- Grep the full diff for hardcoded secrets, TODO/FIXME/HACK comments, disabled tests, and `# type: ignore` suppressions.
- Check error handling at feature boundaries: what happens when image_mode=True but no images exist? When the Vision API is unreachable?
- Review any new async code for missing `await`, unhandled exceptions, or resource leaks.

### 4B.4: Disposition
- **If issues found:** Fix them inline, re-run tests, commit with `fix: <description>`.
- **If clean:** Proceed to Step 5.
- **Log:** Print a summary: `[FEATURE REVIEW] N files changed, M issues found (X fixed, Y deferred)`

This review is NOT optional. Per-story reviews miss cross-cutting concerns. Field data: the most common post-merge issues (duplicate helpers, inconsistent naming, half-wired pipelines) are only visible at the full-feature level.

### 4B.5: Deep-review aggregation (Phase 17 wiring, P1.1 + P1.2 + P1.3)

After the manual checks above pass, dispatch the risk-adaptive multi-reviewer pipeline using `lib/deep-review.sh`.

**Dispatch decision rule (G30 / US-004 — v0.6.6):** the gate is the documented helper `should_dispatch_deep_review` in `lib/deep-review.sh`. Default behavior: dispatch when `compute_tier(diff) >= MEDIUM` (risk score > 30); skip when LOW. Operators can override via the `QL_DEEP_REVIEW` env var:

| `QL_DEEP_REVIEW=` | Effect |
|---|---|
| `force`  | always dispatch regardless of tier |
| `skip`   | always skip regardless of tier |
| (unset) or any other value | tier-gated default (dispatch on MEDIUM/HIGH/CRITICAL) |

The decision is recorded in `quantum.json.reviews[<feature-id>].deepReview` with shape `{tier, decision, rationale, automated}`. The `automated: true` flag distinguishes rule-driven decisions from hand-edited entries.

N1 / US-004 (v0.6.7) — the gate is now load-bearing: explicit `if/else` containment ensures the dispatch pipeline runs ONLY when `should_dispatch_deep_review` returns 0. Pre-N1, the if-block recorded the skip decision and execution fell through to the live pipeline (steps 1-7 ran unconditionally). Post-N1, steps 1-7 live inside the else branch.

```bash
# 0. Apply the dispatch gate FIRST. Skip the entire pipeline on LOW (or skip override).
git diff "$BASE_SHA..HEAD" > "$REPO_ROOT/.quantum-feature-diff.patch"
if ! bash -c "source '$REPO_ROOT/lib/deep-review.sh' && should_dispatch_deep_review '$REPO_ROOT/.quantum-feature-diff.patch'"; then
  echo "[DEEP-REVIEW] gate=skip — recording decision and continuing past 4B.5"
  jq --arg fid "$FEATURE_ID" --arg t "LOW-or-override" --arg r "should_dispatch_deep_review returned skip" \
    '.reviews[$fid] = {deepReview: {tier: $t, decision: "skip", rationale: $r, automated: true}}' \
    "$JSON_PATH" > "$JSON_PATH.tmp" && mv "$JSON_PATH.tmp" "$JSON_PATH"
  rm -f "$REPO_ROOT/.quantum-feature-diff.patch"
  # proceed to Step 4C
else
  # 1. Compute risk score + tier from feature diff + intent-drift signal
  SCORE=$(bash "$REPO_ROOT/lib/deep-review.sh" score-from-quantum "$JSON_PATH" "$BASE_SHA" "HEAD")
  TIER=$(bash  "$REPO_ROOT/lib/deep-review.sh" tier "$SCORE")
  echo "[DEEP-REVIEW] Risk score=$SCORE tier=$TIER"

  # 2. Get the reviewer set for the tier
  REVIEWERS=$(bash "$REPO_ROOT/lib/deep-review.sh" dispatch-set "$TIER")

  # 3. Build the context package passed to every reviewer
  INTENT_TEXT=$(jq -r '.userIntent.text // ""' "$JSON_PATH")
  CONTEXT=$(bash "$REPO_ROOT/lib/deep-review.sh" context "$BASE_SHA" "HEAD" "$PRD_PATH" "$INTENT_TEXT" "$TIER")

  # 4. Dispatch each reviewer in parallel via the Agent tool, passing CONTEXT
  #    as the argument payload. Collect each reviewer's findings array into a
  #    single JSON array-of-arrays ALL_FINDINGS.

  # 5. Run the aggregation pipeline
  AGG=$(printf '%s' "$ALL_FINDINGS" | bash "$REPO_ROOT/lib/deep-review.sh" aggregate "$REPO_ROOT")
  VERDICT=$(jq -r '.verdict' <<< "$AGG")

  # 6. Persist into quantum.reviews[<feature-id>].deepReview
  jq --arg fid "$FEATURE_ID" --argjson agg "$AGG" --argjson score "$SCORE" --arg tier "$TIER" \
    '.reviews[$fid] = {deepReview: ($agg + {risk_score: $score, tier: $tier})}' \
    "$JSON_PATH" > "$JSON_PATH.tmp" && mv "$JSON_PATH.tmp" "$JSON_PATH"

  # 7. Act on verdict
  case "$VERDICT" in
    BLOCKS_MERGE)          echo "[DEEP-REVIEW] BLOCKED — refusing COMPLETE" >&2; exit 1 ;;
    REQUEST_CHANGES)       echo "[DEEP-REVIEW] REQUEST_CHANGES — creating fix-story" >&2 ;;
    APPROVE_WITH_COMMENTS) echo "[DEEP-REVIEW] comments logged to codebasePatterns" >&2 ;;
    APPROVE)               echo "[DEEP-REVIEW] clean" >&2 ;;
  esac

  # N11 / US-006 (v0.6.8): cleanup-at-end-of-branch. When verdict=BLOCKS_MERGE
  # the case above `exit 1`s and skips this rm — the patch file remains for
  # forensic inspection by the operator triaging the blocked merge. Other
  # verdicts (REQUEST_CHANGES / APPROVE_WITH_COMMENTS / APPROVE) fall through
  # the case and reach this cleanup. Pre-N11 the cleanup ran at the START of
  # the else-branch, deleting the patch before steps 1-7 ran — operators lost
  # the ability to inspect the patch when a step (jq error, missing dep, etc.)
  # failed mid-pipeline.
  rm -f "$REPO_ROOT/.quantum-feature-diff.patch"
fi
```

The tier table scales reviewer count from 2 (LOW) to 7 (CRITICAL, adds cross-provider critic via `omc ask codex --agent-prompt critic`). See `skills/ql-deep-review/SKILL.md` for per-tier reviewer mapping.
