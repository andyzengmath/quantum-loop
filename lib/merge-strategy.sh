#!/usr/bin/env bash
# lib/merge-strategy.sh -- Category-based merge conflict resolution for quantum-loop
#
# Provides: get_merge_context(), classify_conflict(), resolve_conflict(), classify_and_merge()
# Requires: lib/common.sh
# Optional: lib/barrel-regen.sh (for regenerate action), lib/dep-manifest.sh (for install postAction)

# shellcheck disable=SC1091,SC2317  # SC1091: sourced files resolved at runtime; SC2317: exit 1 fallback reachable at source-time

# Source shared utilities
MERGE_STRATEGY_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$MERGE_STRATEGY_LIB_DIR/common.sh" || { printf "ERROR: common.sh not found\n" >&2; return 1 2>/dev/null || exit 1; }

# Graceful optional module loading (used by resolve_conflict)
BARREL_REGEN_AVAILABLE=true
source "$MERGE_STRATEGY_LIB_DIR/barrel-regen.sh" 2>/dev/null || BARREL_REGEN_AVAILABLE=false

DEP_MANIFEST_AVAILABLE=true
source "$MERGE_STRATEGY_LIB_DIR/dep-manifest.sh" 2>/dev/null || DEP_MANIFEST_AVAILABLE=false

# get_merge_context(json_path)
# Reads quantum.json and extracts merge-related context into a temp file.
# Extracts: materializedContracts, progress[].filesChanged, mergeStrategy.rules, defaultAction.
# Returns the temp file path on stdout.
get_merge_context() {
  local json_path="$1"

  if [[ -z "$json_path" ]]; then
    printf "ERROR: get_merge_context requires json_path\n" >&2
    return 1
  fi

  if [[ ! -f "$json_path" ]]; then
    printf "ERROR: quantum.json not found at %s\n" "$json_path" >&2
    return 1
  fi

  local tmp_file
  tmp_file=$(mktemp)

  # On Windows Git Bash, convert to paths Python understands
  local py_json_path
  local py_tmp_path
  py_json_path=$(_to_native_path "$json_path")
  py_tmp_path=$(_to_native_path "$tmp_file")

  python -c "
import json, sys

try:
    with open('${py_json_path}') as f:
        d = json.load(f)
except Exception as e:
    print(f'ERROR: Failed to parse {\"${py_json_path}\"}: {e}', file=sys.stderr)
    sys.exit(1)

execution = d.get('execution', {})
ms = execution.get('mergeStrategy', {})

rules_list = ms.get('rules', [])
default_action = ms.get('defaultAction', 'escalate')
materialized = execution.get('materializedContracts', [])

# Collect all filesChanged from progress entries
files_changed = []
for entry in d.get('progress', []):
    fc = entry.get('filesChanged', [])
    if isinstance(fc, list):
        files_changed.extend(fc)

# Serialize rules as JSON array (one line)
rules_json = json.dumps(rules_list)

with open('${py_tmp_path}', 'w', newline='\n') as out:
    out.write(f'defaultAction={default_action}\n')
    out.write(f'materializedContracts={\"|\".join(materialized)}\n')
    out.write(f'filesChanged={\"|\".join(files_changed)}\n')
    out.write(f'rules={rules_json}\n')
" 2>&1

  local py_exit=$?
  if [[ $py_exit -ne 0 ]]; then
    rm -f "$tmp_file"
    return 1
  fi

  printf "%s" "$tmp_file"
  return 0
}

# classify_conflict(file_path, context_file)
# Evaluates mergeStrategy rules in order against a conflicting file.
# Pattern matching uses grep against pipe-delimited filePattern values.
# Condition matching evaluates: file_not_on_ours, file_merged_in_earlier_wave, file_in_materializedContracts.
# First match wins. Prints 'category:action:postAction' to stdout.
# No match: prints 'unknown:<defaultAction>:'.
classify_conflict() {
  local file_path="$1"
  local context_file="$2"

  if [[ -z "$file_path" ]]; then
    printf "ERROR: classify_conflict requires file_path\n" >&2
    return 1
  fi

  if [[ -z "$context_file" ]]; then
    printf "ERROR: classify_conflict requires context_file\n" >&2
    return 1
  fi

  if [[ ! -f "$context_file" ]]; then
    printf "ERROR: context file not found at %s\n" "$context_file" >&2
    return 1
  fi

  # Read context values
  local default_action materialized_str files_changed_str rules_json
  while IFS='=' read -r key value; do
    case "$key" in
      defaultAction) default_action="$value" ;;
      materializedContracts) materialized_str="$value" ;;
      filesChanged) files_changed_str="$value" ;;
      rules) rules_json="$value" ;;
    esac
  done < "$context_file"

  default_action="${default_action:-escalate}"

  # Check if file exists on HEAD (for file_not_on_ours condition)
  # Only set to false when inside a git repo and ls-tree returns empty
  local file_on_ours="true"
  if git rev-parse --is-inside-work-tree &>/dev/null; then
    if ! git ls-tree HEAD -- "$file_path" 2>/dev/null | grep -q .; then
      file_on_ours="false"
    fi
  fi

  # Check if file is in filesChanged list
  local file_in_changed="false"
  if [[ -n "$files_changed_str" ]]; then
    # pipe-delimited list
    local IFS='|'
    local fc
    for fc in $files_changed_str; do
      if [[ "$fc" == "$file_path" ]]; then
        file_in_changed="true"
        break
      fi
    done
    unset IFS
  fi

  # Check if file is in materializedContracts
  local file_in_contracts="false"
  if [[ -n "$materialized_str" ]]; then
    local IFS='|'
    local mc
    for mc in $materialized_str; do
      if [[ "$mc" == "$file_path" ]]; then
        file_in_contracts="true"
        break
      fi
    done
    unset IFS
  fi

  # Use Python to iterate rules JSON and find first match
  local result
  result=$(python -c "
import json, sys, fnmatch

file_path = '${file_path}'
file_on_ours = '${file_on_ours}'
file_in_changed = '${file_in_changed}'
file_in_contracts = '${file_in_contracts}'
default_action = '${default_action}'
rules_json = '''${rules_json}'''

try:
    rules = json.loads(rules_json) if rules_json.strip() else []
except Exception:
    rules = []

for rule in rules:
    name = rule.get('name', 'unknown')
    strategy = rule.get('strategy', default_action)
    post_action = rule.get('postAction', '')
    file_pattern = rule.get('filePattern', '')
    condition = rule.get('condition', '')

    matched = False

    # Check pattern first
    if file_pattern:
        # file_pattern is pipe-delimited list of globs
        for pat in file_pattern.split('|'):
            pat = pat.strip()
            if not pat:
                continue
            # Match using fnmatch (supports ** via recursive check)
            if fnmatch.fnmatch(file_path, pat):
                matched = True
                break
            # Also try matching just the basename
            import os
            if fnmatch.fnmatch(os.path.basename(file_path), pat):
                matched = True
                break

    # Check condition if no pattern or pattern did not match
    if not matched and condition:
        if condition == 'file_not_on_ours' and file_on_ours == 'false':
            matched = True
        elif condition == 'file_merged_in_earlier_wave' and file_in_changed == 'true':
            matched = True
        elif condition == 'file_in_materializedContracts' and file_in_contracts == 'true':
            matched = True

    if matched:
        print(f'{name}:{strategy}:{post_action}')
        sys.exit(0)

# No match
print(f'unknown:{default_action}:')
" 2>&1)

  local py_exit=$?
  if [[ $py_exit -ne 0 ]]; then
    printf "ERROR: classify_conflict Python failed: %s\n" "$result" >&2
    return 1
  fi

  printf "[MERGE-STRATEGY] classify %s -> %s\n" "$file_path" "$result" >&2
  printf "%s" "$result"
  return 0
}

# _detect_language(file_path)
# Detects programming language from file extension for barrel regeneration.
# Prints language name on stdout.
_detect_language() {
  local file_path="$1"
  case "$file_path" in
    *.ts|*.tsx) printf "typescript" ;;
    *.js|*.jsx) printf "javascript" ;;
    *.py)       printf "python" ;;
    *.rs)       printf "rust" ;;
    *)          printf "unknown" ;;
  esac
}

# resolve_conflict(file_path, action, post_action, repo_root)
# Resolves a single merge conflict using the specified action.
# Actions: ours, theirs, regenerate, escalate.
# Returns 0 on success, 1 on escalation or failure.
resolve_conflict() {
  local file_path="$1"
  local action="$2"
  local post_action="$3"
  local repo_root="$4"

  if [[ -z "$file_path" ]]; then
    printf "ERROR: resolve_conflict requires file_path\n" >&2
    return 1
  fi

  if [[ -z "$action" ]]; then
    printf "ERROR: resolve_conflict requires action\n" >&2
    return 1
  fi

  case "$action" in
    ours)
      if ! { git -C "$repo_root" checkout --ours -- "$file_path" 2>/dev/null && \
             git -C "$repo_root" add "$file_path" 2>/dev/null; }; then
        printf "ERROR: resolve_conflict ours failed for %s\n" "$file_path" >&2
        return 1
      fi
      ;;
    theirs)
      if ! { git -C "$repo_root" checkout --theirs -- "$file_path" 2>/dev/null && \
             git -C "$repo_root" add "$file_path" 2>/dev/null; }; then
        printf "ERROR: resolve_conflict theirs failed for %s\n" "$file_path" >&2
        return 1
      fi
      ;;
    regenerate)
      if [[ "$BARREL_REGEN_AVAILABLE" == "false" ]]; then
        printf "ERROR: barrel-regen.sh not available for regenerate action on %s\n" "$file_path" >&2
        return 1
      fi
      # During a merge conflict the barrel file contains conflict markers
      # (<<<<<<, =======, >>>>>>>) which the non-pure-barrel check would flag.
      # Checkout --ours to get a clean baseline, then regenerate from directory scan.
      git -C "$repo_root" checkout --ours -- "$file_path" 2>/dev/null || true
      local lang
      lang=$(_detect_language "$file_path")
      if ! regenerate_barrel "$repo_root/$file_path" "$lang" 2>/dev/null; then
        printf "ERROR: regenerate_barrel failed for %s\n" "$file_path" >&2
        return 1
      fi
      git -C "$repo_root" add "$file_path" 2>/dev/null || true
      ;;
    escalate)
      return 1
      ;;
    *)
      printf "ERROR: resolve_conflict unknown action: %s\n" "$action" >&2
      return 1
      ;;
  esac

  # Handle post-action
  if [[ "$post_action" == "install" ]]; then
    if [[ "$DEP_MANIFEST_AVAILABLE" != "false" ]]; then
      protect_manifest "$repo_root" "$file_path" 2>/dev/null || true
      local pm
      pm=$(detect_package_manager "$repo_root" 2>/dev/null | head -1)
      if [[ -n "$pm" ]]; then
        run_install "$repo_root" "$pm" 2>/dev/null || true
      fi
    fi
  fi

  return 0
}

# classify_and_merge(worktree_branch, repo_root, json_path)
# Orchestrates merge of a worktree branch with category-based conflict resolution.
# On clean merge: commits and returns 0.
# On conflict with all resolved: commits and returns 0.
# On escalation: aborts merge, prints CONFLICT lines, returns 1.
# Logs classification decisions and wall-clock time.
classify_and_merge() {
  local worktree_branch="$1"
  local repo_root="$2"
  local json_path="$3"

  if [[ -z "$worktree_branch" ]]; then
    printf "ERROR: classify_and_merge requires worktree_branch\n" >&2
    return 1
  fi

  if [[ -z "$repo_root" ]]; then
    printf "ERROR: classify_and_merge requires repo_root\n" >&2
    return 1
  fi

  if [[ -z "$json_path" ]]; then
    printf "ERROR: classify_and_merge requires json_path\n" >&2
    return 1
  fi

  local start_time
  start_time=$(date +%s%3N 2>/dev/null || date +%s)

  # Stash dirty state
  local stashed=false
  if git -C "$repo_root" status --porcelain 2>/dev/null | grep -q .; then
    git -C "$repo_root" stash push -m "ql-auto-stash-before-merge-${worktree_branch}" -q 2>/dev/null && stashed=true
  fi

  # Attempt merge with --no-commit so we can inspect conflicts
  if git -C "$repo_root" merge --no-ff "$worktree_branch" --no-commit --no-edit -q 2>/dev/null; then
    # Clean merge -- commit and return
    git -C "$repo_root" commit --no-edit -q 2>/dev/null
    [[ "$stashed" == "true" ]] && { git -C "$repo_root" stash pop -q 2>/dev/null || true; }

    local end_time
    end_time=$(date +%s%3N 2>/dev/null || date +%s)
    local elapsed=$((end_time - start_time))
    printf "[MERGE-STRATEGY] Clean merge of %s. Merge completed in %sms\n" "$worktree_branch" "$elapsed" >&2
    return 0
  fi

  # Merge has conflicts -- list them
  local conflict_files
  conflict_files=$(git -C "$repo_root" diff --name-only --diff-filter=U 2>/dev/null) || true

  if [[ -z "$conflict_files" ]]; then
    # No conflicts found despite merge failure -- commit what we have
    git -C "$repo_root" commit --no-edit -q 2>/dev/null
    [[ "$stashed" == "true" ]] && { git -C "$repo_root" stash pop -q 2>/dev/null || true; }
    return 0
  fi

  # Get merge context
  local context_file
  context_file=$(get_merge_context "$json_path")
  if [[ $? -ne 0 || -z "$context_file" ]]; then
    printf "[MERGE-STRATEGY] Failed to get merge context, aborting merge\n" >&2
    git -C "$repo_root" merge --abort 2>/dev/null || true
    [[ "$stashed" == "true" ]] && { git -C "$repo_root" stash pop -q 2>/dev/null || true; }
    return 1
  fi

  local total_conflicts=0
  local resolved_count=0
  local escalated=false
  local escalated_files=""

  # Process each conflict
  while IFS= read -r file; do
    [[ -z "$file" ]] && continue
    total_conflicts=$((total_conflicts + 1))

    # Classify the conflict
    local classification
    if ! classification=$(cd "$repo_root" && classify_conflict "$file" "$context_file"); then
      escalated=true
      escalated_files="${escalated_files}${file}\n"
      continue
    fi

    # Parse classification: category:action:postAction (category used for logging)
    local _category action post_action
    _category=$(echo "$classification" | cut -d: -f1)
    action=$(echo "$classification" | cut -d: -f2)
    post_action=$(echo "$classification" | cut -d: -f3)

    # Resolve
    if resolve_conflict "$file" "$action" "$post_action" "$repo_root"; then
      resolved_count=$((resolved_count + 1))
    else
      escalated=true
      escalated_files="${escalated_files}${file}\n"
    fi
  done <<< "$conflict_files"

  # Clean up context file
  rm -f "$context_file"

  if [[ "$escalated" == "true" ]]; then
    # Abort merge and report
    git -C "$repo_root" merge --abort 2>/dev/null || true
    [[ "$stashed" == "true" ]] && { git -C "$repo_root" stash pop -q 2>/dev/null || true; }

    # Print CONFLICT lines for escalated files
    printf "%b" "$escalated_files" | while IFS= read -r efile; do
      [[ -n "$efile" ]] && printf "CONFLICT: %s\n" "$efile"
    done

    local end_time
    end_time=$(date +%s%3N 2>/dev/null || date +%s)
    local elapsed=$((end_time - start_time))
    printf "[MERGE-STRATEGY] Resolved %s/%s conflicts (escalated). Merge completed in %sms\n" \
      "$resolved_count" "$total_conflicts" "$elapsed" >&2
    return 1
  fi

  # All resolved -- commit
  git -C "$repo_root" commit --no-edit -q 2>/dev/null
  [[ "$stashed" == "true" ]] && { git -C "$repo_root" stash pop -q 2>/dev/null || true; }

  local end_time
  end_time=$(date +%s%3N 2>/dev/null || date +%s)
  local elapsed=$((end_time - start_time))
  printf "[MERGE-STRATEGY] Resolved %s/%s conflicts. Merge completed in %sms\n" \
    "$resolved_count" "$total_conflicts" "$elapsed" >&2
  return 0
}
