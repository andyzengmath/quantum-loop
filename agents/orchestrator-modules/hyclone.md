# Module: 3C.NEG0 — Wave-boundary semantic clone scan (Phase 25 / P3.7 wiring)

**Activation guard:** `lib/hyclone.sh` is sourced AND `HYCLONE_AVAILABLE=true`.

After divergent-constants and before the type audit, scan the wave's newly-added functions for **alpha-renamed duplicates**. Complements the wave-boundary constant scan (which catches the 'google' vs 'google-api-key' class) by catching the parallel-story duplicate-implementation class: two stories that both, from their own perspective correctly, ended up coding the same function with different names.

HyClone Stage-1 is fingerprint-only — false positives are possible (alpha-renamed bodies that incidentally look identical but have different semantics). The check is **advisory**: findings are logged and passed to deep-review, never block the wave.

```bash
# Phase 25 wiring: cross-story clone detection at wave boundary.
if [[ "$HYCLONE_AVAILABLE" != "false" ]]; then
  # Collect each changed file's functions as {id, body} entries.
  # id = "path:funcname" so collisions across files surface distinctly.
  # We use lib/skeleton.sh if available for signature line extraction;
  # otherwise a grep-based fallback pulls function/method headers.
  CLONE_INPUT='[]'
  for f in $(git diff --name-only "$WAVE_BASE_SHA" HEAD); do
    [[ -f "$f" ]] || continue
    case "$f" in
      *.ts|*.tsx|*.js|*.jsx|*.mjs|*.py|*.go|*.rs) : ;;
      *) continue ;;
    esac
    # Pull each function body (crude: from signature line to next top-level
    # decl). Good enough for fingerprint purposes — HyClone Stage-1 is
    # meant to be a coarse pre-screen.
    # body = the full source of the function; for Stage-1, entire file
    # can be the "body" — clones within a file are not the main concern;
    # cross-file is.
    body=$(cat "$f")
    id="$f"
    CLONE_INPUT=$(jq -c --arg id "$id" --arg body "$body" \
      '. + [{id: $id, body: $body}]' <<< "$CLONE_INPUT")
  done

  CLONE_GROUPS=$(printf '%s' "$CLONE_INPUT" | find_clones)
  N_GROUPS=$(printf '%s' "$CLONE_GROUPS" | jq 'length')
  if (( N_GROUPS > 0 )); then
    printf '[HYCLONE] %s clone group(s) detected at wave boundary:\n' "$N_GROUPS" >&2
    printf '%s\n' "$CLONE_GROUPS" | jq -r '.[] | "  - fingerprint " + .fingerprint[0:12] + " members: " + (.members | join(", "))' >&2
    # Persist for deep-review ingestion at Step 4B
    printf '%s' "$CLONE_GROUPS" > "$REPO_ROOT/.quantum-hyclone-wave.json"
  fi
fi
```

Why per-file fingerprints (not per-function): Stage-1 is a coarse pre-screen; function-level extraction is language-specific and adds false-negative risk (methods inside a class may not share a fingerprint across files even when semantically identical). File-level comparison catches the most important class — two stories landing the same helper in two different paths. Stage-2 execution validation (owned by the duplication-detector agent) is where false positives get eliminated.
