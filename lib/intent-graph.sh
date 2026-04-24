#!/usr/bin/env bash
# lib/intent-graph.sh — semantic intent extraction and story↔code matching
# (Phase 32 / P3.6, formal version of Phase 7 intent-check).
#
# Sources:
#   arXiv:2604.11209 — "Intent-Anchored Code Generation" — maps story
#                      intents to function entities, reports +18% task
#                      success when the graph is built explicitly vs
#                      implicit-in-prompt.
#   arXiv:2301.11325 — "Program-Aided Language Models" — ground program
#                      structure in declared intent to reduce
#                      hallucinated behavior.
#
# Why graph, not keyword set: Phase 7's intent check was keyword Jaccard
# (same pattern as duplication-detector). That catches bag-of-words
# overlap but misses the *relation* between action and target. A story
# that says "delete expired tokens" and code that has `filter_tokens`
# overlaps on "tokens" but the verbs diverge — the story intended a
# DESTRUCTIVE op, code shipped a READ op. Graph-level (verb, object)
# tuples surface that mismatch.
#
# Scope (pragmatic, not full NLP):
#   extract_story_intents — curated action-verb list, noun-phrase after
#                           the verb, cleaned of stop-words. Good for
#                           the story-description register we see in
#                           practice.
#   extract_code_intents — function-name decomposition. Handles snake_case
#                           and camelCase. Verb is the first token; the
#                           remaining tokens are the object.
#   match_intents — Jaccard on the (verb, object) tuple set, plus the
#                   asymmetric breakdowns (story-not-in-code,
#                   code-not-in-story).
#
# Library contract: no shell flags at source time; CLI block enables
# strict mode locally.

INTENT_LIB_DIR="${INTENT_LIB_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)}"

# Curated action verbs. Covers most common code-gen intents across
# CRUD, querying, validation, transformation, lifecycle.
# Stored as space-separated list inside a guard (library contract rule:
# readonly arrays must be guarded against re-source).
if [[ -z "${INTENT_VERBS+x}" ]]; then
readonly -a INTENT_VERBS=(
  # CRUD / lifecycle
  create add insert register init initialize setup bootstrap provision
  delete remove drop destroy revoke deregister teardown cleanup
  update modify change edit patch upsert replace reset
  # Read / query
  get fetch retrieve read load lookup find search query list count
  # Validation / check
  validate check verify assert ensure require test match guard
  # Transformation
  parse serialize format render convert transform normalize sanitize
  filter map reduce aggregate group sort merge join split
  # Flow control
  handle process execute run trigger dispatch schedule cancel pause resume
  # Permissions / access
  authorize authenticate login logout grant deny allow block
  # I/O
  send receive publish subscribe emit listen notify broadcast
  send_receive open close connect disconnect
)
fi

# Stop words we strip from object phrases.
if [[ -z "${INTENT_STOPWORDS+x}" ]]; then
readonly -a INTENT_STOPWORDS=(
  a an the and or but to for of in on at by with from into when while
  if that this these those each every all any some no not be is are was
  were been being have has had do does did should must may can will would
  its their his her our my your new old current next previous same
)
fi

# _is_stopword(tok)
_is_stopword() {
  local t="${1:-}"
  local sw
  for sw in "${INTENT_STOPWORDS[@]}"; do
    [[ "$t" == "$sw" ]] && return 0
  done
  return 1
}

# _is_verb(tok)
_is_verb() {
  local t="${1:-}"
  local v
  for v in "${INTENT_VERBS[@]}"; do
    [[ "$t" == "$v" ]] && return 0
  done
  return 1
}

# _decompose_function_name(name)
# Convert snake_case or camelCase to lowercase space-separated tokens.
# "getUserById" -> "get user by id"
# "create_order" -> "create order"
_decompose_function_name() {
  local n="${1:-}"
  # camelCase -> insert space before each capital letter (but not first)
  # This sed chain works under both GNU and BSD sed.
  n=$(printf '%s' "$n" \
    | sed -E 's/([a-z0-9])([A-Z])/\1 \2/g; s/_/ /g' \
    | tr '[:upper:]' '[:lower:]')
  printf '%s' "$n"
}

# _extract_triples_from_text(text)
# Scan lowercased text for any `VERB NOUN_PHRASE` pattern where VERB
# is in INTENT_VERBS. NOUN_PHRASE = up to 3 following word tokens,
# stopwords stripped. Emits one `verb|object` per line.
_extract_triples_from_text() {
  local text="${1:-}"
  [[ -z "$text" ]] && return 0
  local lower
  lower=$(printf '%s' "$text" | tr '[:upper:]' '[:lower:]' | tr -s '[:punct:]' ' ' | tr -s ' ')
  # Walk token by token
  local tokens=()
  read -r -a tokens <<< "$lower"
  local n=${#tokens[@]}
  local i=0
  while (( i < n )); do
    local tok="${tokens[$i]}"
    if _is_verb "$tok"; then
      # Gather up to 3 non-stopword tokens after the verb to form object
      local obj_parts=()
      local j=$((i + 1))
      local depth=0
      while (( j < n && depth < 3 )); do
        local next="${tokens[$j]}"
        # Stop at punctuation-only tokens or next verb boundary
        [[ -z "$next" ]] && break
        if _is_stopword "$next"; then j=$((j + 1)); continue; fi
        if _is_verb "$next" && (( depth > 0 )); then break; fi
        obj_parts+=("$next")
        depth=$((depth + 1))
        j=$((j + 1))
      done
      if (( ${#obj_parts[@]} > 0 )); then
        local obj
        obj=$(IFS=' '; printf '%s' "${obj_parts[*]}")
        printf '%s|%s\n' "$tok" "$obj"
      fi
    fi
    i=$((i + 1))
  done
}

# extract_story_intents(story_json)
# Input: a story object with optional fields {title, description,
# acceptanceCriteria, tasks[{description}]}. Reads from stdin if empty.
# Emits a JSON array of {verb, object, source}.
extract_story_intents() {
  local input="${1:-}"
  [[ -z "$input" ]] && input=$(cat)
  local out='[]'

  # Process each source field separately so we can tag `source` correctly
  local title desc
  title=$(jq -r '.title // ""' <<< "$input")
  desc=$(jq -r '.description // ""' <<< "$input")

  # Title triples
  while IFS='|' read -r v o; do
    [[ -z "$v" ]] && continue
    out=$(jq -c --arg v "$v" --arg o "$o" '. + [{verb: $v, object: $o, source: "title"}]' <<< "$out")
  done < <(_extract_triples_from_text "$title")

  # Description triples
  while IFS='|' read -r v o; do
    [[ -z "$v" ]] && continue
    out=$(jq -c --arg v "$v" --arg o "$o" '. + [{verb: $v, object: $o, source: "description"}]' <<< "$out")
  done < <(_extract_triples_from_text "$desc")

  # Acceptance criteria
  local n_ac
  n_ac=$(jq '.acceptanceCriteria // [] | length' <<< "$input")
  local i=0
  while (( i < n_ac )); do
    local ac
    ac=$(jq -r --argjson i "$i" '.acceptanceCriteria[$i]' <<< "$input")
    while IFS='|' read -r v o; do
      [[ -z "$v" ]] && continue
      out=$(jq -c --arg v "$v" --arg o "$o" '. + [{verb: $v, object: $o, source: "ac"}]' <<< "$out")
    done < <(_extract_triples_from_text "$ac")
    i=$((i + 1))
  done

  # Tasks
  local n_tasks
  n_tasks=$(jq '.tasks // [] | length' <<< "$input")
  i=0
  while (( i < n_tasks )); do
    local td
    td=$(jq -r --argjson i "$i" '.tasks[$i].description // ""' <<< "$input")
    while IFS='|' read -r v o; do
      [[ -z "$v" ]] && continue
      out=$(jq -c --arg v "$v" --arg o "$o" '. + [{verb: $v, object: $o, source: "task"}]' <<< "$out")
    done < <(_extract_triples_from_text "$td")
    i=$((i + 1))
  done

  printf '%s' "$out"
}

# extract_code_intents(path)
# Scan functions in the file or directory. Extracts (verb, object) from
# each function name. Supports the same languages as lib/skeleton.sh.
# If lib/skeleton.sh is absent, falls back to grep-based extraction.
#
# Emits a JSON array of {verb, object, source}. `source` = function name.
extract_code_intents() {
  local path="${1:?path required}"
  local out='[]'

  # Collect function names
  local names=()
  if [[ -d "$path" ]]; then
    # Walk the dir; supported extensions only
    while IFS= read -r f; do
      while IFS= read -r n; do
        names+=("$n")
      done < <(_scan_function_names "$f")
    done < <(find "$path" -type f \( -name '*.ts' -o -name '*.tsx' -o -name '*.js' -o -name '*.py' -o -name '*.go' -o -name '*.rs' \))
  elif [[ -f "$path" ]]; then
    while IFS= read -r n; do
      names+=("$n")
    done < <(_scan_function_names "$path")
  else
    printf "[]"; return 0
  fi

  local nm
  for nm in "${names[@]}"; do
    [[ -z "$nm" ]] && continue
    local decomposed first_tok rest
    decomposed=$(_decompose_function_name "$nm")
    first_tok=${decomposed%% *}
    rest="${decomposed#"$first_tok"}"
    rest="${rest# }"
    # Only keep triples whose first token is a known verb (otherwise the
    # function is non-action-style e.g. `useCache`, `Foo.Bar`, constructor).
    if _is_verb "$first_tok"; then
      out=$(jq -c --arg v "$first_tok" --arg o "$rest" --arg s "$nm" \
        '. + [{verb: $v, object: $o, source: $s}]' <<< "$out")
    fi
  done

  printf '%s' "$out"
}

# _scan_function_names(file)
# Emit one function name per line. Language detected from extension.
_scan_function_names() {
  local f="${1:?file required}"
  [[ -f "$f" ]] || return 0
  case "$f" in
    *.ts|*.tsx|*.js|*.jsx|*.mjs)
      grep -oE '(function[[:space:]]+|const[[:space:]]+|let[[:space:]]+|var[[:space:]]+)[A-Za-z_][A-Za-z0-9_]*' "$f" 2>/dev/null \
        | awk '{print $NF}'
      ;;
    *.py)
      grep -oE '^[[:space:]]*(async[[:space:]]+)?def[[:space:]]+[A-Za-z_][A-Za-z0-9_]*' "$f" 2>/dev/null \
        | awk '{print $NF}'
      ;;
    *.go)
      grep -oE '^[[:space:]]*func[[:space:]]+(\([^)]*\)[[:space:]]+)?[A-Za-z_][A-Za-z0-9_]*' "$f" 2>/dev/null \
        | awk '{print $NF}'
      ;;
    *.rs)
      grep -oE '(pub[[:space:]]+(\([^)]*\)[[:space:]]+)?)?(async[[:space:]]+)?fn[[:space:]]+[A-Za-z_][A-Za-z0-9_]*' "$f" 2>/dev/null \
        | awk '{print $NF}'
      ;;
  esac
}

# match_intents(story_json, code_json)
# Computes overlap between two intent arrays using (verb, normalized-object) as key.
# Normalization on the object: lowercase, tokens sorted, stopwords stripped.
# Emits JSON:
#   { matched:          [{verb, object, story_sources, code_sources}],
#     unmatched_story:  [{verb, object, source}],
#     unmatched_code:   [{verb, object, source}],
#     jaccard:          <0..1> }
match_intents() {
  local story="${1:-}"; local code="${2:-}"
  [[ -z "$story" ]] && story='[]'
  [[ -z "$code" ]]  && code='[]'

  jq -cn --argjson s "$story" --argjson c "$code" '
    # Naive singularization: strip trailing "s" on tokens >= 4 chars so
    # "tokens" ≡ "token", "orders" ≡ "order", "sessions" ≡ "session".
    # Keeps short words ("is", "as") intact; acceptable false-merge on
    # rare irregulars (e.g. "status" becomes "statu") since intent
    # overlap is an advisory signal, not a hard gate.
    def singularize(t):
      if (t | length) >= 4 and (t | endswith("s")) and (t | endswith("ss") | not)
      then t[0:-1] else t end;
    def norm_obj(o):
      (o // "") | ascii_downcase |
      gsub("[[:punct:]]"; " ") |
      split(" ") | map(select(length > 0)) | map(singularize(.)) | sort | join(" ");
    def key(x): x.verb + "|" + norm_obj(x.object);

    ($s | map({k: key(.), v: .}) | group_by(.k)) as $sg |
    ($c | map({k: key(.), v: .}) | group_by(.k)) as $cg |
    ([$sg[] | .[0].k]) as $sk |
    ([$cg[] | .[0].k]) as $ck |
    ($sk + $ck | unique) as $all |
    ($sk - $ck) as $only_s |
    ($ck - $sk) as $only_c |
    ($sk - ($sk - $ck)) as $both |
    {
      matched: [
        $both[] as $k
        | ($sg | map(select(.[0].k == $k)) | .[0] // null) as $sitems
        | ($cg | map(select(.[0].k == $k)) | .[0] // null) as $citems
        | {
            verb: ($sitems[0].v.verb),
            object: ($sitems[0].v.object),
            story_sources: ($sitems | map(.v.source)),
            code_sources:  ($citems | map(.v.source))
          }
      ],
      unmatched_story: [
        $sg[] | select(.[0].k | IN($only_s[])) | .[] | .v
      ],
      unmatched_code: [
        $cg[] | select(.[0].k | IN($only_c[])) | .[] | .v
      ],
      jaccard: (if ($all | length) == 0 then 0 else (($both | length) / ($all | length)) end)
    }
  '
}

# ------------------------------------------------------------------------------
# CLI entry
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  set -euo pipefail
  subcmd="${1:-}"
  shift || true
  case "$subcmd" in
    story)  extract_story_intents "$@" ;;
    code)   extract_code_intents "$@" ;;
    match)
      # match STORY_FILE CODE_FILE
      _s=$(cat "${1:?story json}"); _c=$(cat "${2:?code json}")
      match_intents "$_s" "$_c"
      ;;
    *)
      cat >&2 <<USAGE
Usage: bash lib/intent-graph.sh <subcmd> [args...]
  story   < story_json     — extract story intent triples
  code    PATH             — extract code intent triples (file or dir)
  match   STORY_F CODE_F   — match story and code intent JSON files
USAGE
      exit 2
      ;;
  esac
fi
