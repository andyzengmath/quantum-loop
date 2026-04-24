#!/usr/bin/env bash
# lib/deslop.sh — machine-testable helpers for the ql-deslop skill.
#
# The skill (skills/ql-deslop/SKILL.md) drives the LLM-side detection of
# duplication / dead-code / needless-abstraction / boundary-violation /
# missing-test smells. This library covers the deterministic safety rails
# that MUST run regardless of the LLM's proposals:
#
#   validate_scope        — refuse edits to files outside the story's
#                           BASE..HEAD diff (the scope-fence anti-pattern
#                           guard from SKILL.md §"Scope — strict file-list
#                           only").
#   take_baseline         — snapshot test / lint / typecheck exit codes
#                           before any edits for later comparison.
#   compare_baseline      — detect regressions introduced by a deslop pass;
#                           returns 0 if clean, 1 if any check regressed.
#   rollback_pass         — reset changed files to the baseline SHA
#                           (used when compare_baseline reports regression).
#   detect_language       — dispatch a language-specific dead-code linter.
#                           Returns empty + skip-reason when tooling missing
#                           (graceful degradation rather than hard-fail).
#
# Library contract: does NOT set shell flags at source time. Strict mode
# applies only inside the CLI-entry branch at file bottom.

DESLOP_LIB_DIR="${DESLOP_LIB_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)}"

# ------------------------------------------------------------------------------
# validate_scope(file_path, base_sha, head_sha)
#
# Exits 0 if file_path appears in `git diff --name-only BASE..HEAD`.
# Exits 1 otherwise — the deslop pass is attempting to reach outside the
# story's changed-files list, which is the #1 anti-pattern from SKILL.md.
validate_scope() {
  local file="${1:?validate_scope: file required}"
  local base="${2:?validate_scope: base_sha required}"
  local head="${3:?validate_scope: head_sha required}"
  if [[ -z "$file" ]]; then return 1; fi
  local in_scope
  in_scope=$(git diff --name-only "$base..$head" 2>/dev/null | grep -Fxc -- "$file" || true)
  if [[ "$in_scope" -ge 1 ]]; then
    return 0
  fi
  printf "[DESLOP] OUT-OF-SCOPE REJECT: %s not in diff %s..%s\n" \
    "$file" "$base" "$head" >&2
  return 1
}

# take_baseline(out_file, [test_cmd], [lint_cmd], [typecheck_cmd])
#
# Runs the three checks and writes a JSON snapshot of their exit codes to
# out_file. Commands default to bash wrappers commonly available in the
# quantum-loop repo. Returns 0 always (a baseline "fail" is still a valid
# baseline to compare against).
take_baseline() {
  local out="${1:?take_baseline: out_file required}"
  local test_cmd="${2:-bash tests/test_dag_query.sh}"
  local lint_cmd="${3:-true}"       # no lint by default
  local typecheck_cmd="${4:-true}"  # no tsc by default
  local te le tc
  $test_cmd     >/dev/null 2>&1; te=$?
  $lint_cmd     >/dev/null 2>&1; le=$?
  $typecheck_cmd >/dev/null 2>&1; tc=$?
  jq -cn --argjson t "$te" --argjson l "$le" --argjson c "$tc" \
    '{test_exit: $t, lint_exit: $l, typecheck_exit: $c, captured_at: (now|floor)}' \
    > "$out"
}

# compare_baseline(before_file, after_file)
#
# Returns 0 when after matches OR improves on before across all three
# checks. Returns 1 on any regression. Echoes a short human diff.
compare_baseline() {
  local before="${1:?compare_baseline: before file required}"
  local after="${2:?compare_baseline: after file required}"
  [[ -f "$before" && -f "$after" ]] || { echo "[DESLOP] missing baseline snapshot" >&2; return 1; }
  local t_b t_a l_b l_a c_b c_a
  t_b=$(jq -r '.test_exit'      "$before")
  t_a=$(jq -r '.test_exit'      "$after")
  l_b=$(jq -r '.lint_exit'      "$before")
  l_a=$(jq -r '.lint_exit'      "$after")
  c_b=$(jq -r '.typecheck_exit' "$before")
  c_a=$(jq -r '.typecheck_exit' "$after")

  local reg=0
  if (( t_a != 0 && t_b == 0 )); then
    echo "[DESLOP] REGRESSION: test was passing ($t_b), now $t_a"; reg=1
  fi
  if (( l_a != 0 && l_b == 0 )); then
    echo "[DESLOP] REGRESSION: lint was passing ($l_b), now $l_a"; reg=1
  fi
  if (( c_a != 0 && c_b == 0 )); then
    echo "[DESLOP] REGRESSION: typecheck was passing ($c_b), now $c_a"; reg=1
  fi
  return "$reg"
}

# rollback_pass(base_sha, file1, [file2, ...])
#
# For each listed file, restore its contents from base_sha so a failed
# deslop pass does not leave bad state. Uses `git checkout BASE -- FILE`.
# Returns 0 on success, 1 if any restore fails.
rollback_pass() {
  local base="${1:?rollback_pass: base_sha required}"
  shift
  local fail=0
  for f in "$@"; do
    if ! git checkout "$base" -- "$f" 2>/dev/null; then
      echo "[DESLOP] rollback failed for $f" >&2
      fail=1
    fi
  done
  return "$fail"
}

# detect_language(dir)
#
# Echoes the language name + recommended tool (or skip-reason). Heuristic
# based on marker files so callers can dispatch the right dead-code
# detector. One of:
#   typescript|ts-prune
#   javascript|knip
#   python|vulture
#   go|staticcheck
#   rust|cargo-udeps
#   unknown|skip
detect_language() {
  local dir="${1:-.}"
  if [[ -f "$dir/tsconfig.json" ]]; then
    if command -v ts-prune &>/dev/null; then
      printf "typescript|ts-prune"
    else
      printf "typescript|skip-missing-tool"
    fi
  elif [[ -f "$dir/package.json" ]]; then
    if command -v knip &>/dev/null; then
      printf "javascript|knip"
    else
      printf "javascript|skip-missing-tool"
    fi
  elif [[ -f "$dir/pyproject.toml" || -f "$dir/setup.py" ]]; then
    if command -v vulture &>/dev/null; then
      printf "python|vulture"
    else
      printf "python|skip-missing-tool"
    fi
  elif [[ -f "$dir/go.mod" ]]; then
    if command -v staticcheck &>/dev/null; then
      printf "go|staticcheck"
    else
      printf "go|skip-missing-tool"
    fi
  elif [[ -f "$dir/Cargo.toml" ]]; then
    if command -v cargo-udeps &>/dev/null; then
      printf "rust|cargo-udeps"
    else
      printf "rust|skip-missing-tool"
    fi
  else
    printf "unknown|skip"
  fi
}

# ------------------------------------------------------------------------------
# CLI entry
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  set -euo pipefail
  subcmd="${1:-}"
  shift || true
  case "$subcmd" in
    scope)           validate_scope "$@" ;;
    baseline)        take_baseline "$@" ;;
    compare)         compare_baseline "$@" ;;
    rollback)        rollback_pass "$@" ;;
    detect-language) detect_language "$@"; printf "\n" ;;
    *)
      cat >&2 <<USAGE
Usage: bash lib/deslop.sh <subcmd> [args...]
  scope FILE BASE HEAD             — exit 0 if FILE is in BASE..HEAD diff
  baseline OUT [TEST] [LINT] [TC]  — snapshot exit codes into OUT
  compare BEFORE AFTER             — exit 0 if no regression
  rollback BASE FILE [FILE...]     — restore files to BASE
  detect-language [DIR]            — echo language|tool
USAGE
      exit 2
      ;;
  esac
fi
