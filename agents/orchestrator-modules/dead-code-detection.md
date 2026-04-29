# Module: 3A.5C — Post-generation dead-code check (Phase 33 / P3.10 wiring)

**Activation guard:** `lib/dead-code.sh` is sourced AND `DEAD_CODE_AVAILABLE=true`.

Before the commit in 3A.6, run an **advisory** dead-code pass over the files this story just changed. Complements 3A.5B (deslop) which is language-tool-driven; 3A.5C is regex-based and tool-free, so it lands findings even when knip/vulture/staticcheck aren't installed.

This check is **non-blocking by design**: unused imports or unused private helpers don't fail the story — they get recorded on the commit as a trailer and surfaced in the per-story progress entry. Blocking here would fight the deslop pass; advisory status lets reviewers see both signals without either forcing a retry.

```bash
# Phase 33 wiring: post-generation dead-code advisory check.
# Runs against the story's changed files only (not the whole repo).
if [[ "$DEAD_CODE_AVAILABLE" != "false" ]]; then
  DEAD_CODE_REPORT=$(find_post_commit_dead "$BASE_SHA" "HEAD")
  DEAD_TOTAL=$(jq -r '.summary.total // 0' <<< "$DEAD_CODE_REPORT")
  if (( DEAD_TOTAL > 0 )); then
    DEAD_IMP=$(jq -r '.summary.by_kind.import // 0' <<< "$DEAD_CODE_REPORT")
    DEAD_PRIV=$(jq -r '.summary.by_kind.private // 0' <<< "$DEAD_CODE_REPORT")
    echo "[DEAD-CODE] advisory: $DEAD_TOTAL finding(s) — $DEAD_IMP unused imports, $DEAD_PRIV unused privates"
    # Record trailer to be appended in 3A.6 commit message. Non-blocking.
    DEAD_CODE_TRAILER="Dead-Code: advisory | $DEAD_IMP imports, $DEAD_PRIV privates"
    # Persist the full finding list into .quantum-dead-code.$STORY_ID.json
    # so 3A.6 can attach it to the progress entry for later review.
    printf '%s' "$DEAD_CODE_REPORT" > "$REPO_ROOT/.quantum-dead-code.$STORY_ID.json"
  else
    DEAD_CODE_TRAILER="Dead-Code: clean"
  fi
else
  DEAD_CODE_TRAILER="Dead-Code: skipped | lib/dead-code.sh absent"
fi
```

Why advisory not blocking:
- False positives are real. A private helper called only from a test file in a future commit would be flagged here incorrectly. Blocking would train the loop to retry-until-empty, breaking the one-retry budget.
- Deslop (3A.5B) already has the blocking authority when it wants to. Dead-code is a secondary read for reviewer context.
- The advisory trailer makes the signal durable in `git log`; the JSON side-file makes it queryable later without re-running the scan.
