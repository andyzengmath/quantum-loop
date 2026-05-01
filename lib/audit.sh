#!/usr/bin/env bash
# lib/audit.sh -- quantum-loop audit subsystem (v0.9.5 / US-001 decomposition).
#
# Extracted from quantum-loop.sh in v0.9.5 / US-001 (decomposition refactor;
# spike 1 from idea-stage/v0.10.0-design-spike-2026-05-01.md). Source this
# from quantum-loop.sh BEFORE the test-mode guard + --audit shortcut.
#
# Functions exported to caller's scope:
#   _audit_format_row, _audit_drill_join, _audit_trim_branch_line,
#   _audit_branches_local, _audit_branches_remote, _audit_readme_conflicts,
#   _audit_orphan_worktrees, _audit_cpc_files, _audit_untracked_design_prd_docs,
#   _audit_csv_uncommitted, _audit_validate_env, _audit_test_suites,
#   _audit_pre_impl_review_coverage, do_audit
#
# Required globals (set in quantum-loop.sh before sourcing): none at source
# time. do_audit reads QL_AUDIT_TEST_MODE / QL_AUDIT_TEST_ROWS at call-time.
#
# Library contract: no shell flags at source time; parent's set -euo pipefail
# carries through naturally.

# Source-guard
if [[ -n "${_QL_AUDIT_LIB:-}" ]]; then
  return 0 2>/dev/null || true
fi
readonly _QL_AUDIT_LIB=1

# =============================================================================
# --audit flag support (Phase 44 / US-001 -- US-004). Read-only repo-hygiene
# check per idea-stage/IDEA_REPORT.md §6 measurement plan.
# Helpers live near the top so the pre-arg-loop audit shortcut can call them.
# =============================================================================

# _audit_format_row PIPE_ROW
# Takes one pipe-delimited string "name|value|target|status|drill" and emits
# formatted output on stdout. Single line for OK, two lines for FAIL (main
# line + indented drill-down with └─ prefix). Column widths locked so CI
# scripts can grep reliably.
_audit_format_row() {
  local row="${1:-}"
  local name value target status drill
  IFS='|' read -r name value target status drill <<< "$row"
  # Main line: "<name>: <value> (target <target>) <status>"
  # Column widths: name: padded to 18, value+target padded to 30, status right.
  printf "%-18s %s (target %s) %6s\n" "${name}:" "$value" "$target" "$status"
  # Drill prints on FAIL OR WARN because both signal something the operator
  # should see — a FAIL-only gate would silently suppress WARN drill messages.
  if [[ ( "$status" == "FAIL" || "$status" == "WARN" ) && -n "$drill" ]]; then
    printf "                   └─ %s\n" "$drill"
  fi
}

# _audit_drill_join NAMES_VAR_REF  (bash-4 nameref pattern)
# Given an array of offending names, emit at most the first 3 joined with
# ", " plus "(+N more)" when there's a tail. Empty input → empty string.
# Requires bash 4.3+ (uses `local -n` nameref). All audit code paths are
# bash-4-only; older bashes (e.g., macOS default 3.2) are unsupported.
_audit_drill_join() {
  local -n _arr="$1"  # nameref (bash 4.3+)
  local n="${#_arr[@]}"
  if (( n == 0 )); then printf ""; return 0; fi
  local head_count=3
  (( n < head_count )) && head_count=$n
  local i=0 out=""
  while (( i < head_count )); do
    if (( i > 0 )); then out+=", "; fi
    out+="${_arr[$i]}"
    i=$((i + 1))
  done
  if (( n > head_count )); then
    out+=" (+$((n - head_count)) more)"
  fi
  printf '%s' "$out"
}

_audit_trim_branch_line() {
  local branch_line="${1:-}"
  branch_line="${branch_line#\*}"
  branch_line="${branch_line#"${branch_line%%[![:space:]]*}"}"
  printf '%s' "$branch_line"
}

# _audit_branches_local
# Counts local branches excluding master/HEAD; emits OK row if count <=
# QL_AUDIT_BRANCH_MAX (default 10) else FAIL with first-3 drill.
_audit_branches_local() {
  local max="${QL_AUDIT_BRANCH_MAX:-10}"
  local -a names=()
  local b
  while IFS= read -r b; do
    b=$(_audit_trim_branch_line "$b")
    [[ -z "$b" || "$b" == "master" || "$b" == "HEAD" ]] && continue
    names+=("$b")
  done < <({ git branch 2>/dev/null ; } || true)
  local n="${#names[@]}"
  if (( n <= max )); then
    printf 'branches-local|%d|≤%d|OK|\n' "$n" "$max"
  else
    local drill
    drill=$(_audit_drill_join names)
    printf 'branches-local|%d|≤%d|FAIL|%s\n' "$n" "$max" "$drill"
  fi
}

# _audit_branches_remote
# Same as _audit_branches_local but against `git branch -r`, excluding
# HEAD pointers and origin/master.
_audit_branches_remote() {
  local max="${QL_AUDIT_BRANCH_MAX:-10}"
  local -a names=()
  local b
  while IFS= read -r b; do
    b=$(_audit_trim_branch_line "$b")
    [[ -z "$b" ]] && continue
    [[ "$b" == *"HEAD"* ]] && continue
    [[ "$b" == "origin/master" ]] && continue
    names+=("$b")
  done < <({ git branch -r 2>/dev/null ; } || true)
  local n="${#names[@]}"
  if (( n <= max )); then
    printf 'branches-remote|%d|≤%d|OK|\n' "$n" "$max"
  else
    local drill
    drill=$(_audit_drill_join names)
    printf 'branches-remote|%d|≤%d|FAIL|%s\n' "$n" "$max" "$drill"
  fi
}

# _audit_readme_conflicts
# Counts merge-conflict markers in README.md. Guards against missing file.
# Target QL_AUDIT_CONFLICT_MAX (default 0). Drill = first 3 line numbers.
_audit_readme_conflicts() {
  local max="${QL_AUDIT_CONFLICT_MAX:-0}"
  local n=0
  local -a lines=()
  if [[ -f README.md ]]; then
    local ln
    while IFS=: read -r ln _; do
      [[ -n "$ln" ]] && lines+=("$ln")
    done < <({ grep -nE '^(<<<<<<<|=======|>>>>>>>)' README.md 2>/dev/null ; } || true)
    n="${#lines[@]}"
  fi
  if (( n <= max )); then
    printf 'readme-conflicts|%d|%d|OK|\n' "$n" "$max"
  else
    local drill
    drill=$(_audit_drill_join lines)
    printf 'readme-conflicts|%d|%d|FAIL|%s\n' "$n" "$max" "$drill"
  fi
}

# _audit_orphan_worktrees
# Counts .claude/worktrees/agent-* directories. Target QL_AUDIT_ORPHAN_MAX
# (default 0). Drill = first 3 basenames.
_audit_orphan_worktrees() {
  local max="${QL_AUDIT_ORPHAN_MAX:-0}"
  local -a names=()
  local d
  while IFS= read -r d; do
    [[ -z "$d" ]] && continue
    [[ -d "$d" ]] || continue
    names+=("$(basename "$d")")
  done < <({ ls -d .claude/worktrees/agent-* 2>/dev/null ; } || true)
  local n="${#names[@]}"
  if (( n <= max )); then
    printf 'orphan-worktrees|%d|%d|OK|\n' "$n" "$max"
  else
    local drill
    drill=$(_audit_drill_join names)
    printf 'orphan-worktrees|%d|%d|FAIL|%s\n' "$n" "$max" "$drill"
  fi
}

# _audit_cpc_files
# Counts CPC-variant files (legacy *-CPC-*.json / *-CPC-*.md / etc).
# Target QL_AUDIT_CPC_MAX (default 0). Drill = first 3 paths.
_audit_cpc_files() {
  local max="${QL_AUDIT_CPC_MAX:-0}"
  local -a names=()
  local f
  while IFS= read -r f; do
    [[ -z "$f" ]] && continue
    names+=("$f")
  done < <({ find . -maxdepth 3 -name '*-CPC-*' -not -path './.git/*' 2>/dev/null ; } || true)
  local n="${#names[@]}"
  if (( n <= max )); then
    printf 'cpc-files|%d|%d|OK|\n' "$n" "$max"
  else
    local drill
    drill=$(_audit_drill_join names)
    printf 'cpc-files|%d|%d|FAIL|%s\n' "$n" "$max" "$drill"
  fi
}

# _audit_untracked_design_prd_docs
# N34 / US-001 (v0.7.6) — warns when docs/plans/*-design.md or tasks/prd-*.md
# files are untracked. v0.7.4/v0.7.5 cycles repeatedly left these uncommitted
# until housekeeping caught them. Mirrors _audit_csv_uncommitted pattern.
_audit_untracked_design_prd_docs() {
  local untracked
  untracked=$(git ls-files --others --exclude-standard docs/plans/ tasks/ 2>/dev/null \
              | grep -E '^(docs/plans/.+-design\.md|tasks/prd-.+\.md)$' || true)
  if [[ -z "$untracked" ]]; then
    printf 'untracked-design-prd|0|0|OK|\n'
  else
    local n
    n=$(printf '%s\n' "$untracked" | grep -c .)
    printf 'untracked-design-prd|%d|0|WARN|%s\n' "$n" "$(printf '%s' "$untracked" | head -1)"
  fi
}

# _audit_csv_uncommitted
# N29 / US-001 (v0.7.5) — warns when metrics/pre-impl-review-findings.csv has
# uncommitted changes. v0.7.2 + v0.7.3 advisory hooks fired but their CSV
# updates never reached master because operators forgot to stage the file
# before squash-merge. This is advisory (WARN), not blocking — operators may
# legitimately have pending hooks mid-cycle.
_audit_csv_uncommitted() {
  local csv="metrics/pre-impl-review-findings.csv"
  if [[ ! -f "$csv" ]]; then
    printf 'csv-uncommitted|0|0|OK|\n'
    return
  fi
  local porcelain
  porcelain=$(git status --porcelain "$csv" 2>/dev/null)
  if [[ -z "$porcelain" ]]; then
    printf 'csv-uncommitted|0|0|OK|\n'
  else
    printf 'csv-uncommitted|1|0|WARN|%s\n' "$(printf '%s' "$porcelain" | head -1)"
  fi
}

# _audit_validate_env
# Validate env-var inputs to the audit before any output is emitted.
# Per PRD FR-11: QL_AUDIT_TEST_GLOB must match ^[A-Za-z0-9._/*-]+$. On
# mismatch print error + exit 2. Called from the pre-arg-loop audit
# shortcut so invalid input never produces a half-rendered audit frame.
_audit_validate_env() {
  local test_glob="${QL_AUDIT_TEST_GLOB:-*}"
  if [[ ! "$test_glob" =~ ^[A-Za-z0-9._/*-]+$ ]]; then
    printf "Error: invalid QL_AUDIT_TEST_GLOB (must match [A-Za-z0-9._/*-]+)\n" >&2
    exit 2
  fi
}

# _audit_test_suites
# Inspects the most-recent .omc/phase-*-evidence/ dir for evidence logs
# matching `=== Results: <P>/<T> passed, <F> failed ===`. Sums P/T/F.
# OK iff F == 0. When no evidence dir exists, emits unknown/FAIL per FR-10.
#
# N2 / US-005 (v0.6.7) — reads the phase-evidence LEDGER, not the live
# test corpus. The row answers "did the most recent recorded test run
# pass?" not "do tests pass right now?". For live state, run
# `bash tests/run_all.sh` (sequential or `--parallel N`).
#
# Filtered by QL_AUDIT_TEST_GLOB (default "*", validated by
# _audit_validate_env before this helper runs).
_audit_test_suites() {
  local test_glob="${QL_AUDIT_TEST_GLOB:-*}"
  local -a dirs=()
  local d
  while IFS= read -r d; do
    [[ -z "$d" || ! -d "$d" ]] && continue
    dirs+=("$d")
  done < <({ ls -d .omc/phase-*-evidence 2>/dev/null ; } || true)
  if (( ${#dirs[@]} == 0 )); then
    printf 'test-suites|unknown|green|FAIL|no evidence logs found — run tests first\n'
    return 0
  fi
  # Pick latest by NUMERIC phase number. Plain `sort` is lexicographic so
  # phase-9 sorts after phase-43 (wrong). `sort -V` handles version-style
  # numeric-aware sorting and is available on GNU + BSD + Git Bash.
  local latest
  latest=$(printf '%s\n' "${dirs[@]}" | sort -V | tail -1)
  local sum_p=0 sum_t=0 sum_f=0
  local -a failing=()
  local log line p t f
  # shellcheck disable=SC2231  # intentional glob expansion of validated TEST_GLOB
  for log in "$latest"/${test_glob}.log; do
    [[ -f "$log" ]] || continue
    line=$({ grep -E '^=== (Final )?Results: [0-9]+/[0-9]+ passed' "$log" 2>/dev/null ; } || true)
    [[ -z "$line" ]] && continue
    if [[ "$line" =~ ([0-9]+)/([0-9]+)\ passed(,\ ([0-9]+)\ failed)? ]]; then
      p="${BASH_REMATCH[1]}"
      t="${BASH_REMATCH[2]}"
      f="${BASH_REMATCH[4]:-0}"
      sum_p=$((sum_p + p))
      sum_t=$((sum_t + t))
      sum_f=$((sum_f + f))
      if (( f > 0 )); then
        failing+=("$(basename "$log" .log)")
      fi
    fi
  done
  if (( sum_f == 0 )); then
    printf 'test-suites|%d/%d passed|green|OK|\n' "$sum_p" "$sum_t"
  else
    local drill
    drill=$(_audit_drill_join failing)
    printf 'test-suites|%d/%d passed|green|FAIL|%s\n' "$sum_p" "$sum_t" "$drill"
  fi
}

# _audit_pre_impl_review_coverage  (v0.7.0 / G17 / US-005)
# Counts unique stage values in metrics/pre-impl-review-findings.csv whose
# timestamp is within the last 7 days. Four states (per AC):
#   missing-csv      → WARN (no CSV at all)
#   no-recent-runs   → WARN (CSV exists, all rows >7d old)
#   partial-coverage → WARN (1-2 of 3 stages have a recent row)
#   full-coverage    → OK   (all 3 stages have a recent row)
#
# Cross-platform date math: GNU `date -d '7 days ago'` first, BSD
# `date -v-7d` fallback, epoch-0 fallback otherwise. Last fallback degrades
# to "all rows count as recent" rather than crashing — never fails the audit
# (per AC: "WARN does not fail the audit").
_audit_pre_impl_review_coverage() {
  local csv="metrics/pre-impl-review-findings.csv"
  if [[ ! -f "$csv" ]]; then
    # G18 / US-005 (v0.6.5): drill text clarifies that the empty-CSV state
    # is the expected first-run state after install (per README ## Self-
    # modifying execution). Without this guidance an operator running
    # --audit on a fresh checkout reads a WARN row and assumes a
    # regression. Other WARN states (no-recent-runs, partial-coverage)
    # keep their existing drill messages.
    printf 'pre-impl-review-coverage|0/3 stages|3/3|WARN|missing-csv — no metrics/pre-impl-review-findings.csv yet (expected on first run after install — invoke /ql-brainstorm/spec/plan to populate)\n'
    return 0
  fi
  # Compute the cutoff ISO 8601 string for "7 days ago" UTC.
  local cutoff_ts
  cutoff_ts=$(date -u -d '7 days ago' +%Y-%m-%dT%H:%M:%SZ 2>/dev/null) \
    || cutoff_ts=$(date -u -v-7d +%Y-%m-%dT%H:%M:%SZ 2>/dev/null) \
    || cutoff_ts="1970-01-01T00:00:00Z"
  # awk: skip header (NR==1); split on comma; field 1 = timestamp, field 2 = stage.
  # ISO 8601 strings are lexicographically comparable when zero-padded — the
  # date library guarantees that. We accumulate unique stage names whose
  # timestamp >= cutoff into a hash.
  local recent_stages
  recent_stages=$(awk -F',' -v cutoff="$cutoff_ts" '
    NR == 1 { next }   # header
    $1 >= cutoff {
      seen[$2] = 1
    }
    END {
      n = 0
      for (s in seen) {
        if (s == "design" || s == "prd" || s == "plan") {
          out = out (n > 0 ? "," : "") s
          n++
        }
      }
      print n "|" out
    }
  ' "$csv" 2>/dev/null) || recent_stages="0|"
  local n stages_csv
  n="${recent_stages%%|*}"
  stages_csv="${recent_stages#*|}"
  case "$n" in
    0) printf 'pre-impl-review-coverage|0/3 stages|3/3|WARN|no-recent-runs — no rows in last 7 days\n' ;;
    1|2) printf 'pre-impl-review-coverage|%d/3 stages|3/3|WARN|partial-coverage — recent: %s\n' "$n" "$stages_csv" ;;
    3) printf 'pre-impl-review-coverage|3/3 stages|3/3|OK|full-coverage — all stages recent\n' ;;
    *) printf 'pre-impl-review-coverage|%d/3 stages|3/3|WARN|partial-coverage — recent: %s\n' "$n" "$stages_csv" ;;
  esac
}

# do_audit
# Driver for --audit. Calls all metric helpers in canonical order, renders
# each row via _audit_format_row, returns 0 if all OK or WARN, else 1.
# Walk ROWS once and split counters by status because a single combined
# counter would silently treat WARN as on-target and mislead the operator.
# WARN does not trip exit — only FAIL rows do, so a partial-coverage state
# surfaces visibly without breaking CI.
do_audit() {
  printf "=== Quantum-loop audit ===\n"
  local -a ROWS=()
  ROWS+=("$(_audit_branches_local)")
  ROWS+=("$(_audit_branches_remote)")
  ROWS+=("$(_audit_orphan_worktrees)")
  ROWS+=("$(_audit_readme_conflicts)")
  ROWS+=("$(_audit_cpc_files)")
  ROWS+=("$(_audit_test_suites)")
  ROWS+=("$(_audit_pre_impl_review_coverage)")
  ROWS+=("$(_audit_csv_uncommitted)")
  ROWS+=("$(_audit_untracked_design_prd_docs)")
  # Test-only injection hook: replace the helper-driven ROWS with synthetic
  # newline-delimited rows so tests can exercise the split-summary arithmetic
  # + exit-semantics against the real do_audit, not a private re-implementation.
  # Gated on QL_AUDIT_TEST_MODE=1 because honoring it in production would let
  # any environment override audit input.
  if [[ -n "${QL_AUDIT_TEST_ROWS:-}" && "${QL_AUDIT_TEST_MODE:-0}" == "1" ]]; then
    # mapfile splits on newlines into ROWS[]. An earlier "read -d ''" idiom
    # set NUL as the record delimiter, making IFS=$'\n' irrelevant — every
    # synthetic row collapsed into ROWS[0]. mapfile is the right tool because
    # it treats newlines as record separators by default.
    mapfile -t ROWS <<< "$QL_AUDIT_TEST_ROWS"
  fi
  local any_fail=0 ok_count=0 warn_count=0 fail_count=0 total=0
  local row
  for row in "${ROWS[@]}"; do
    _audit_format_row "$row"
    total=$((total + 1))
    case "$row" in
      *"|FAIL|"*) any_fail=1; fail_count=$((fail_count + 1)) ;;
      *"|WARN|"*) warn_count=$((warn_count + 1)) ;;
      *"|OK|"*)   ok_count=$((ok_count + 1)) ;;
    esac
  done
  printf "\nSummary: %d/%d OK, %d WARN, %d FAIL.\n" "$ok_count" "$total" "$warn_count" "$fail_count"
  return "$any_fail"
}
