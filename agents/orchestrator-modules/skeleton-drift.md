# Module: 3A.5E — Skeleton drift check (Phase 31 / P3.1 wiring)

**Activation guard:** `lib/skeleton.sh` is sourced AND `SKELETON_AVAILABLE=true`.

Pair to the 3A.1 pre-skeleton preview. For each file the story modified, compute `skeleton_diff` between BASE_SHA and HEAD and surface added / removed / changed signatures. Advisory — never blocks, always records a trailer.

Unlike the dead-code (3A.5C) and intent-graph (3A.5D) checks which operate on raw text, this check operates on **parsed API surface**: a body-only change shows 0 drift, a signature change shows up as `changed`, and a new function shows up as `added`. That makes the trailer tight and reviewer-meaningful.

```bash
# Phase 31 wiring: skeleton drift check. One diff per changed file.
if [[ "$SKELETON_AVAILABLE" != "false" ]]; then
  SKEL_ADDED=0; SKEL_REMOVED=0; SKEL_CHANGED=0
  : > "$REPO_ROOT/.quantum-skeleton-diff.$STORY_ID.json"
  DIFF_AGG='[]'

  for f in $(git diff --name-only "$BASE_SHA" "HEAD"); do
    # Only files the skeleton lib supports
    case "$f" in
      *.ts|*.tsx|*.js|*.jsx|*.mjs|*.py|*.go|*.rs) : ;;
      *) continue ;;
    esac
    # Materialize BASE and HEAD versions side by side for diff
    PRE_TMP=$(mktemp --suffix=".$(basename "$f")")
    POST_TMP=$(mktemp --suffix=".$(basename "$f")")
    git show "$BASE_SHA:$f" > "$PRE_TMP" 2>/dev/null || : > "$PRE_TMP"
    [[ -f "$f" ]] && cp "$f" "$POST_TMP" || : > "$POST_TMP"
    D=$(skeleton_diff "$PRE_TMP" "$POST_TMP")
    rm -f "$PRE_TMP" "$POST_TMP"
    ADD_N=$(jq '.added   | length' <<< "$D")
    REM_N=$(jq '.removed | length' <<< "$D")
    CHG_N=$(jq '.changed | length' <<< "$D")
    SKEL_ADDED=$((SKEL_ADDED + ADD_N))
    SKEL_REMOVED=$((SKEL_REMOVED + REM_N))
    SKEL_CHANGED=$((SKEL_CHANGED + CHG_N))
    DIFF_AGG=$(jq -c --arg f "$f" --argjson d "$D" \
      '. + [{file: $f, diff: $d}]' <<< "$DIFF_AGG")
  done

  printf '%s' "$DIFF_AGG" > "$REPO_ROOT/.quantum-skeleton-diff.$STORY_ID.json"
  SKELETON_TRAILER="Skeleton: added=$SKEL_ADDED | removed=$SKEL_REMOVED | changed=$SKEL_CHANGED"
else
  SKELETON_TRAILER="Skeleton: skipped | lib/skeleton.sh absent"
fi
```

Why a parsed-surface view matters here: a reviewer looking at a 300-line diff usually wants to know what the **shape** change is — "did this story add a new public function? did it change an exported signature?" The `added/removed/changed` counts answer those questions in one line. The JSON side-file holds the full detail (name, kind, before/after signatures) for deeper review.
