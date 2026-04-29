# Module: 3A.5B — Post-review slop-cleanup (Phase 17 wiring, P1.6)

**Activation guard:** `lib/deslop.sh` is sourced AND `DESLOP_AVAILABLE=true` AND story.deslop.skip != true.

Between the review gate passing and the final commit, run the per-story slop-cleanup pass using `lib/deslop.sh`. Opt-out: if `story.deslop.skip = true` in quantum.json, record trailer `Deslop: skipped | <reason>` and jump to 3A.6.

```bash
# Phase 21 fix: graceful fallback guard matching every other hardening
# module in this orchestrator. Without the guard, a missing lib/deslop.sh
# under `set -euo pipefail` would abort the story AFTER the review gate
# passed, leaving it permanently stuck in in_progress.
DESLOP_AVAILABLE=true
[[ -f "$REPO_ROOT/lib/deslop.sh" ]] || DESLOP_AVAILABLE=false

if [[ "$DESLOP_AVAILABLE" == "false" ]]; then
  echo "[DESLOP] lib/deslop.sh not found — skipping cleanup pass for $STORY_ID" >&2
  # Record trailer + jump to 3A.6
  DESLOP_TRAILER="Deslop: skipped | lib/deslop.sh absent"
else
  STORY_FILES=$(jq -r --arg sid "$STORY_ID" \
    '.stories[] | select(.id==$sid) | .tasks[].filePaths // [] | .[]' "$JSON_PATH")

  # 1. Baseline snapshot BEFORE any cleanup edits
  bash "$REPO_ROOT/lib/deslop.sh" baseline "/tmp/ql-deslop-$STORY_ID-before.json"

  # 2. Dispatch /quantum-loop:ql-deslop (LLM-driven smell detection)
  #    The skill MUST restrict every edit to STORY_FILES via validate_scope.
  #    Use BASE_SHA from 3A.1 (not STORY_BASE_SHA — that variable is
  #    undefined; Phase 21 fix for PR #28 correctness finding).
  for f in $STORY_FILES; do
    bash "$REPO_ROOT/lib/deslop.sh" scope "$f" "$BASE_SHA" "HEAD" || {
      echo "[DESLOP] out-of-scope attempt on $f — rejected" >&2
      continue
    }
  done

  # 3. After the pass applies its edits, snapshot again and compare
  bash "$REPO_ROOT/lib/deslop.sh" baseline "/tmp/ql-deslop-$STORY_ID-after.json"
  if ! bash "$REPO_ROOT/lib/deslop.sh" compare \
       "/tmp/ql-deslop-$STORY_ID-before.json" "/tmp/ql-deslop-$STORY_ID-after.json"; then
    # 4. Rollback on regression, emit DESLOP_ROLLED_BACK
    bash "$REPO_ROOT/lib/deslop.sh" rollback "$BASE_SHA" $STORY_FILES
    echo "<quantum>DESLOP_ROLLED_BACK</quantum>"
    # Do NOT advance to the next pass until user inspects.
  fi

  # 5. Persist per-pass report into quantum.deslop[<story-id>].pass_<n>
fi
```

`lib/deslop.sh detect-language` picks the appropriate dead-code detector (knip / ts-prune / vulture / staticcheck / cargo-udeps); tooling-missing → skip-clean (not fail).
