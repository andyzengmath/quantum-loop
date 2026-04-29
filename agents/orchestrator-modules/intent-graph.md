# Module: 3A.5D — Intent-graph drift check (Phase 32 / P3.6 wiring)

**Activation guard:** `lib/intent-graph.sh` is sourced AND `INTENT_GRAPH_AVAILABLE=true`.

After the dead-code pass, run an **advisory** verb-object intent check between the story's declared intents (title / description / AC / task descriptions) and the code's realized intents (function-name decomposition on changed files). Surfaces action drift: story says "delete expired tokens", code ships `filter_expired_tokens` — same object, different verb = implementation diverged from intent.

Like 3A.5C, this check is **non-blocking**: drift doesn't fail the story. It's a review signal recorded on the commit trailer and in a JSON side-file.

```bash
# Phase 32 wiring: intent-graph advisory drift check.
if [[ "$INTENT_GRAPH_AVAILABLE" != "false" ]]; then
  # Extract story intents once from quantum.json for this story ID.
  STORY_JSON=$(jq -c --arg sid "$STORY_ID" '.stories[] | select(.id == $sid)' "$JSON_PATH")
  STORY_INTENTS=$(printf '%s' "$STORY_JSON" | extract_story_intents)

  # Extract code intents from ONLY the files this story changed.
  # Write names to a temp list, loop each, aggregate.
  CODE_INTENTS='[]'
  for f in $(git diff --name-only "$BASE_SHA" "HEAD"); do
    [[ -f "$f" ]] || continue
    f_intents=$(extract_code_intents "$f")
    CODE_INTENTS=$(jq -c --argjson a "$CODE_INTENTS" --argjson b "$f_intents" -n '$a + $b')
  done

  INTENT_REPORT=$(match_intents "$STORY_INTENTS" "$CODE_INTENTS")
  J_SCORE=$(jq -r '.jaccard' <<< "$INTENT_REPORT")
  N_UNMATCHED_STORY=$(jq -r '.unmatched_story | length' <<< "$INTENT_REPORT")
  N_UNMATCHED_CODE=$(jq -r '.unmatched_code | length' <<< "$INTENT_REPORT")

  # Two signals, both advisory:
  # - unmatched_story = story asked for an action the code did not realize
  # - unmatched_code  = code shipped actions the story never requested
  INTENT_TRAILER="Intent-Graph: jaccard=$J_SCORE | unmatched_story=$N_UNMATCHED_STORY | unmatched_code=$N_UNMATCHED_CODE"
  printf '%s' "$INTENT_REPORT" > "$REPO_ROOT/.quantum-intent-graph.$STORY_ID.json"
else
  INTENT_TRAILER="Intent-Graph: skipped | lib/intent-graph.sh absent"
fi
```

Why the (verb, object) graph beats keyword-set overlap:
- Keyword set says "both mention 'tokens'" → flags nothing wrong.
- Graph says "story: `delete|tokens`, code: `filter|tokens`" → surfaces the verb mismatch. Same object doesn't make the actions equivalent.

The check is **bidirectional**: unmatched_story catches missing features; unmatched_code catches over-building (scope creep). Each story gets both numbers on the trailer so reviewers can see which direction drifted.
