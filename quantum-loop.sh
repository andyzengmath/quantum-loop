#!/usr/bin/env bash
set -euo pipefail

# =============================================================================
# quantum-loop.sh -- PLUGIN-LEVEL autonomous development loop.
#
# THIS SCRIPT IS FOR THE QUANTUM-LOOP PLUGIN REPO ITSELF.
# It requires lib/*.sh modules and jq. It operates at the STORY level
# (one story per agent invocation) and uses CLAUDE.md as the agent prompt.
#
# FOR USER PROJECTS: Use templates/quantum-loop.sh instead.
# That script is self-contained (no lib/ dependency), uses node for JSON,
# and operates at the TASK level. Download it via:
#   curl -sO https://raw.githubusercontent.com/andyzengmath/quantum-loop/main/templates/quantum-loop.sh
#
# Features: DAG-based story selection, two-stage review gates,
# structured error recovery, parallel execution via worktree agents.
#
# Usage:
#   ./quantum-loop.sh [OPTIONS]
#
# Options:
#   --audit              Print §6 measurement metrics and exit (read-only).
#   --max-iterations N   Maximum iterations before stopping (default: 20)
#   --max-retries N      Max retry attempts per story (default: 3)
#   --tool TOOL          AI tool to use (default: "claude"). Any runner in runners/*.json.
#   --parallel           Enable parallel execution of independent stories
#   --max-parallel N     Maximum concurrent agents in parallel mode (default: 4)
#   --help               Show this help message
#
# Prerequisites:
#   - quantum.json must exist in the current directory (run /quantum-loop:plan first)
#   - jq must be installed
#   - The selected runner CLI must be installed (see runners/*.json)
# =============================================================================

# Defaults
MAX_ITERATIONS=20
MAX_RETRIES=3
TOOL="claude"
PARALLEL_MODE=false
MAX_PARALLEL=4
# v0.8.0 / US-004 (N33) — coordinator mode: per-wave subagent dispatch instead
# of long-running orchestrator. Default false (legacy orchestrator) for v0.8.0;
# v0.8.1 dogfood will validate before flipping default.
COORDINATOR_MODE=false
STALE_TIMEOUT=20
QL_CRITIC="${QL_CRITIC:-auto}"      # P5.A2 / US-002 default
QL_PLANNER="${QL_PLANNER:-auto}"    # P5.B1 / US-009 default
QL_EXECUTOR="${QL_EXECUTOR:-auto}"  # P5.B1 / US-009 default
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# =============================================================================
# P5.B1 / US-009 — Per-role provider routing (--planner / --critic / --executor)
# Subsumes US-002's --critic flag; adds --planner and --executor with the
# same availability-check + fallback semantics. Resolved choices are
# snapshotted to quantum.json.routing at run start for replay determinism.
# =============================================================================

# parse_role_arg ROLE VALUE
# Validates VALUE against the per-role enum and runs availability check.
# Roles: planner | critic | executor.
# Enums:
#   planner:  auto | claude | codex | gemini
#   critic:   auto | claude | codex | gemini | none  (critic may be disabled)
#   executor: auto | claude | codex | gemini
# On absence of codex/gemini, emits WARN to stderr and rewrites to 'claude'.
parse_role_arg() {
  local role="${1:-}"
  local value="${2:-}"
  case "$role" in
    planner|critic|executor) : ;;
    *) printf "Error: parse_role_arg: unknown role %q\n" "$role" >&2; return 1 ;;
  esac

  case "$value" in
    auto|claude|codex|gemini) : ;;
    none)
      if [[ "$role" != "critic" ]]; then
        printf "Error: --%s=none not supported (only --critic accepts 'none')\n" "$role" >&2
        return 1
      fi
      ;;
    *)
      local extra=""
      [[ "$role" == "critic" ]] && extra='|none'
      printf "Error: --%s value must be auto|claude|codex|gemini%s (got [%s])\n" \
        "$role" "$extra" "$value" >&2
      return 1
      ;;
  esac

  # Availability check for non-claude/auto/none providers.
  # US-001 / G8: role-aware fallback. The critic role degrades to 'none'
  # (preserving US-002's "downgrade rather than substitute" design intent
  # and matching quantum-loop.ps1). Planner/executor degrade to 'claude'
  # because their role is "execute the work, just maybe with a different
  # model" — disabling them entirely would break the run.
  case "$value" in
    codex|gemini)
      if ! command -v "$value" >/dev/null 2>&1; then
        local _fallback="claude"
        [[ "$role" == "critic" ]] && _fallback="none"
        printf "WARN: per-role routing: %s provider %s not available, falling back to %s\n" "$role" "$value" "$_fallback" >&2
        value="$_fallback"
      fi
      ;;
  esac
  printf '%s' "$value"
}

# =============================================================================
# P5.A2 / US-002 — --critic=auto|codex|gemini|claude|none flag.
# US-001 / G8 (v0.6.3): legacy parse_critic_arg removed as dead code.
# parse_role_arg above is the unified entry point with role-aware fallback:
# critic role degrades to 'none' (preserving the "downgrade rather than
# substitute" design intent), planner/executor degrade to 'claude'.
# =============================================================================

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

# Test-mode guard (Phase 44 / US-001): when QL_AUDIT_TEST_MODE=1 is set,
# sourcing this file returns here so unit tests can reach the audit
# helpers defined above without triggering the main arg-loop or any
# state-mutating code below.
# G33 / US-002 (v0.6.6): require $#==0 so subprocess `bash quantum-loop.sh
# --audit` with QL_AUDIT_TEST_MODE=1 + QL_AUDIT_TEST_ROWS set still reaches
# the --audit branch below. Sourcing always passes 0 args (verified across
# all current test_*.sh files), so this is backward-compatible.
#
# Companion test-only env var: QL_AUDIT_TEST_ROWS (read by do_audit above).
# Newline-delimited synthetic ROWS for fixture testing. Honored only when
# QL_AUDIT_TEST_MODE=1; ignored in production. See do_audit body.
[[ "${QL_AUDIT_TEST_MODE:-0}" == "1" && "$#" -eq 0 ]] && return 0 2>/dev/null

# Pre-arg-loop audit shortcut: --audit is exclusive and takes no other args.
# Must run BEFORE the normal arg-parsing loop so any stray sibling flag
# (--audit --parallel) is rejected with exit 2.
if [[ " $* " == *" --audit "* ]]; then
  if [[ "$#" -ne 1 ]]; then
    printf "Error: --audit is exclusive and takes no other arguments\n" >&2
    exit 2
  fi
  _audit_validate_env
  do_audit
  exit $?
fi

# Parse arguments
while [[ $# -gt 0 ]]; do
  case $1 in
    --max-iterations)
      MAX_ITERATIONS="$2"
      shift 2
      ;;
    --max-retries)
      MAX_RETRIES="$2"
      shift 2
      ;;
    --tool)
      TOOL="$2"
      shift 2
      ;;
    --parallel)
      PARALLEL_MODE=true
      shift
      ;;
    --coordinator)
      # v0.8.0 / US-004 (N33) — opt-in per-wave coordinator pattern.
      # Default in v0.8.0 is --legacy-orchestrator (preserves single-spawn).
      # See agents/coordinator.md for the agent definition.
      COORDINATOR_MODE=true
      shift
      ;;
    --legacy-orchestrator)
      # Explicit opt-out from --coordinator (v0.8.0 default; for forward
      # compat when a future release flips the default to coordinator).
      COORDINATOR_MODE=false
      shift
      ;;
    --max-parallel)
      MAX_PARALLEL="$2"
      shift 2
      ;;
    --stale-timeout)
      STALE_TIMEOUT="$2"
      shift 2
      ;;
    --critic=*)
      # P5.A2 / US-002 -- critic provider routing (subsumed by US-009 per-role)
      _ql_critic_raw="${1#--critic=}"
      QL_CRITIC=$(parse_role_arg critic "$_ql_critic_raw") || exit 2
      export QL_CRITIC
      shift
      ;;
    --critic)
      if [[ $# -lt 2 || "${2:-}" == --* ]]; then
        printf "Error: --critic requires a value (auto|claude|codex|gemini|none)\n" >&2
        exit 2
      fi
      QL_CRITIC=$(parse_role_arg critic "$2") || exit 2
      export QL_CRITIC
      shift 2
      ;;
    --planner=*)
      # P5.B1 / US-009 — per-role planner routing
      _ql_planner_raw="${1#--planner=}"
      QL_PLANNER=$(parse_role_arg planner "$_ql_planner_raw") || exit 2
      export QL_PLANNER
      shift
      ;;
    --planner)
      if [[ $# -lt 2 || "${2:-}" == --* ]]; then
        printf "Error: --planner requires a value (auto|claude|codex|gemini)\n" >&2
        exit 2
      fi
      QL_PLANNER=$(parse_role_arg planner "$2") || exit 2
      export QL_PLANNER
      shift 2
      ;;
    --executor=*)
      # P5.B1 / US-009 — per-role executor routing
      _ql_executor_raw="${1#--executor=}"
      QL_EXECUTOR=$(parse_role_arg executor "$_ql_executor_raw") || exit 2
      export QL_EXECUTOR
      shift
      ;;
    --executor)
      if [[ $# -lt 2 || "${2:-}" == --* ]]; then
        printf "Error: --executor requires a value (auto|claude|codex|gemini)\n" >&2
        exit 2
      fi
      QL_EXECUTOR=$(parse_role_arg executor "$2") || exit 2
      export QL_EXECUTOR
      shift 2
      ;;
    --non-interactive)
      NON_INTERACTIVE=true
      shift
      ;;
    --help)
      head -29 "$0" | tail -24
      exit 0
      ;;
    *)
      printf "Unknown option: %s\n" "$1"
      exit 1
      ;;
  esac
done

# Validate dependencies
if ! command -v jq &>/dev/null; then
  printf "ERROR: jq is required. Install it: https://jqlang.github.io/jq/download/\n"
  exit 1
fi

# Validate quantum.json
if [[ ! -f quantum.json ]]; then
  printf "ERROR: quantum.json not found. Run /quantum-loop:plan first to create it.\n"
  exit 1
fi

# Source library functions
source "$SCRIPT_DIR/lib/common.sh" || { printf "ERROR: lib/common.sh not found\n"; exit 1; }
source "$SCRIPT_DIR/lib/json-atomic.sh" || { printf "ERROR: lib/json-atomic.sh not found\n"; exit 1; }
source "$SCRIPT_DIR/lib/runner.sh" || { printf "ERROR: lib/runner.sh not found\n"; exit 1; }
source "$SCRIPT_DIR/lib/orchestrator-liveness.sh" || { printf "ERROR: lib/orchestrator-liveness.sh not found\n"; exit 1; }

# v0.8.0 / US-001 (N33) — Wire recovery infrastructure for orchestrator/coordinator
# subagent dispatch. Callers wrap their long-running agent-spawn (e.g., the
# v0.8.0 coordinator pattern in US-004, or external supervisor scripts) with
# this helper so STALE detection actually fires in production. Honors
# QL_LIVENESS_ENABLE (default true) and QL_RESPAWN_CMD env vars.
#
# Usage: ql_wrap_subagent_dispatch [TIMEOUT_SEC] [INTERVAL_SEC] [WORKTREE_PATH]
#   Returns rc=0 when commits land within timeout (LIVE / OPT-OUT).
#   Returns rc=1 when STALE (emits canonical handoff message to stdout).
ql_wrap_subagent_dispatch() {
  wrap_orchestrator_dispatch "$@"
}

# v0.9.0 / US-004 (N42 minor) — enforce --coordinator and --parallel
# mutual exclusion at parse time (replaces v0.8.1 US-001's warn-only
# message that documented the gap). The combination would produce
# nested parallelism (worktree-of-worktrees) that does not compose:
# the parallel path already does worktree-driven wave dispatch, and
# the coordinator agent spawns implementer subagents internally.
# Documented as policy in agents/coordinator.md § "Interaction with
# --parallel" (added in v0.8.2 US-004).
if [[ "$COORDINATOR_MODE" == "true" && "$PARALLEL_MODE" == "true" ]]; then
  printf "ERROR: --coordinator and --parallel are mutually exclusive (see agents/coordinator.md § \"Interaction with --parallel\")\n" >&2
  exit 1
fi

# Load runner manifest (validates tool name, binary existence, sets RUNNER_* vars)
runner_load "$TOOL" || exit 1
runner_ensure_instructions || true

# Experimental tier warning
if [[ "$RUNNER_TIER" == "experimental" && "${NON_INTERACTIVE:-}" != "true" ]]; then
  printf "\nWARNING: Runner '%s' is experimental (tier: %s).\n" "$RUNNER_NAME" "$RUNNER_TIER"
  printf "Experimental runners may not reliably emit quantum signals.\n"
  printf "Press Enter to continue or Ctrl-C to abort...\n"
  read -r
fi
if [[ "$PARALLEL_MODE" == "true" ]]; then
  source "$SCRIPT_DIR/lib/dag-query.sh" || { printf "ERROR: lib/dag-query.sh not found\n"; exit 1; }
  source "$SCRIPT_DIR/lib/worktree.sh" || { printf "ERROR: lib/worktree.sh not found\n"; exit 1; }
  source "$SCRIPT_DIR/lib/spawn.sh" || { printf "ERROR: lib/spawn.sh not found\n"; exit 1; }
  source "$SCRIPT_DIR/lib/monitor.sh" || { printf "ERROR: lib/monitor.sh not found\n"; exit 1; }
  source "$SCRIPT_DIR/lib/resilience.sh" || { printf "ERROR: lib/resilience.sh not found\n"; exit 1; }
fi

# v0.8.3 / US-001 (4th-layer N33 closure): also source lib/spawn.sh under
# COORDINATOR_MODE so v0.9.0 N42's spawn_coordinator() is defined at call
# time. Without this, --coordinator path hits "command not found" before
# reaching the dispatch loop. Architect post-v0.8.2 review caught this gap.
# Idempotent: lib/spawn.sh has its own source-guard so re-sourcing is safe.
if [[ "$COORDINATOR_MODE" == "true" ]]; then
  source "$SCRIPT_DIR/lib/dag-query.sh" || { printf "ERROR: lib/dag-query.sh not found\n"; exit 1; }
  source "$SCRIPT_DIR/lib/spawn.sh" || { printf "ERROR: lib/spawn.sh not found\n"; exit 1; }
fi

# =============================================================================
# Archive previous run if branch changed
# =============================================================================

BRANCH=$(jq -r '.branchName' quantum.json)
LAST_BRANCH_FILE=".last-ql-branch"

if [[ -f "$LAST_BRANCH_FILE" ]]; then
  LAST_BRANCH=$(cat "$LAST_BRANCH_FILE")
  if [[ "$LAST_BRANCH" != "$BRANCH" ]]; then
    ARCHIVE_DIR="archive/$(date +%Y-%m-%d)-${BRANCH//\//-}"
    printf "Branch changed from %s to %s\n" "$LAST_BRANCH" "$BRANCH"
    printf "Archiving previous run to %s\n" "$ARCHIVE_DIR"
    mkdir -p "$ARCHIVE_DIR"
    cp quantum.json "$ARCHIVE_DIR/quantum.json" 2>/dev/null || true
    printf "Archive complete.\n"
  fi
fi

printf "%s" "$BRANCH" > "$LAST_BRANCH_FILE"

# Update maxAttempts in quantum.json if different from default
jq --argjson max "$MAX_RETRIES" '
  .stories |= map(.retries.maxAttempts = $max)
' quantum.json > quantum.json.tmp && mv quantum.json.tmp quantum.json

# =============================================================================
# Summary table function
# =============================================================================

print_summary_table() {
  printf "\n"
  printf "Summary\n"
  printf "%-10s %-40s %-8s %-6s %-8s\n" "Story" "Title" "Status" "Wave" "Retries"
  printf "%-10s %-40s %-8s %-6s %-8s\n" "----------" "----------------------------------------" "--------" "------" "--------"
  jq -r '.stories[] | "\(.id)|\(.title)|\(.status)|\(.retries.attempts)/\(.retries.maxAttempts)"' quantum.json | \
  while IFS='|' read -r sid title status retries; do
    printf "%-10s %-40s %-8s %-6s %-8s\n" "$sid" "${title:0:40}" "$status" "-" "$retries"
  done
  printf "\n"

  local total passed failed
  total=$(jq '.stories | length' quantum.json)
  passed=$(jq '[.stories[] | select(.status == "passed")] | length' quantum.json)
  failed=$((total - passed))
  printf "Result: %d/%d stories passed\n" "$passed" "$total"
}

# =============================================================================
# Stale story detection
# =============================================================================

detect_stale_stories() {
  local threshold="${STALE_TIMEOUT:-20}"
  local now_epoch
  now_epoch=$(date +%s)

  # Find all in_progress stories with startedAt set
  local stale_ids
  stale_ids=$(jq -r --argjson threshold "$threshold" '
    .stories[] |
    select(.status == "in_progress" and .startedAt != null) |
    select(
      ((now | floor) - (.startedAt | fromdateiso8601)) > ($threshold * 60)
    ) |
    .id
  ' quantum.json 2>/dev/null) || return 0

  if [[ -z "$stale_ids" ]]; then
    return 0
  fi

  while IFS= read -r sid; do
    [[ -z "$sid" ]] && continue
    printf "[STALE] %s - resetting to failed (exceeded %d minute threshold)\n" "$sid" "$threshold"
    jq --arg id "$sid" --argjson threshold "$threshold" '
      .stories |= map(if .id == $id then
        .status = (if .retries.attempts + 1 >= .retries.maxAttempts then "blocked" else "failed" end) |
        .startedAt = null |
        .retries.attempts += 1 |
        .retries.failureLog += [{"phase": "stale_detection", "timestamp": (now | todate), "error": ("Story exceeded " + ($threshold | tostring) + " minute stale threshold")}]
      else . end)
    ' quantum.json > quantum.json.tmp && mv quantum.json.tmp quantum.json
  done <<< "$stale_ids"
}

# =============================================================================
# Safe test command execution (allowlist + metacharacter rejection)
# =============================================================================

# Allowlist of known-safe test command prefixes
ALLOWED_TEST_PREFIXES=("npm test" "npx jest" "npx vitest" "yarn test" "pnpm test" "python -m pytest" "pytest" "cargo test" "go test" "make test" "bash tests/" "shellcheck")

# validate_and_run_test_cmd(cmd, [work_dir])
# Validates a test command against the allowlist and rejects shell metacharacters.
# Executes via array splitting (no eval). Returns the command's exit code.
validate_and_run_test_cmd() {
  local cmd="$1"
  local work_dir="${2:-.}"

  if [[ -z "$cmd" ]]; then
    return 1
  fi

  # Reject shell metacharacters
  if [[ "$cmd" =~ [\;\|\&\$\`\(\)\>\<\!] ]] || [[ "$cmd" == *$'\n'* ]]; then
    printf "ERROR: Test command contains unsafe characters: %s\n" "$cmd" >&2
    return 1
  fi

  # Check allowlist
  local allowed=false
  for prefix in "${ALLOWED_TEST_PREFIXES[@]}"; do
    if [[ "$cmd" == "$prefix" || "$cmd" == "$prefix "* ]]; then
      allowed=true
      break
    fi
  done

  if [[ "$allowed" != "true" ]]; then
    printf "ERROR: Test command '%s' does not match any allowed prefix — refusing to execute\n" "$cmd" >&2
    return 1
  fi

  # Execute as array to prevent shell interpretation
  local -a cmd_array
  read -ra cmd_array <<< "$cmd"
  (cd "$work_dir" && "${cmd_array[@]}" >/dev/null 2>&1)
}

# =============================================================================
# Final verification sweep before declaring COMPLETE
# =============================================================================

final_verification_sweep() {
  printf "\n[FINAL SWEEP] Running test suite before declaring COMPLETE...\n"

  # Detect test command
  local TEST_CMD=""
  if [[ -f "package.json" ]]; then TEST_CMD="npm test"
  elif [[ -f "pyproject.toml" ]] || [[ -f "setup.py" ]]; then TEST_CMD="python -m pytest -x -q"
  elif [[ -f "Cargo.toml" ]]; then TEST_CMD="cargo test"
  elif [[ -f "go.mod" ]]; then TEST_CMD="go test ./..."
  fi

  if [[ -n "$TEST_CMD" ]]; then
    if validate_and_run_test_cmd "$TEST_CMD"; then
      printf "[FINAL SWEEP] Test suite passed.\n"
    else
      printf "[FINAL SWEEP] FAILED: test suite. Cannot declare COMPLETE.\n"
      print_summary_table
      exit 1
    fi
  else
    printf "[FINAL SWEEP] No test suite detected, skipping.\n"
  fi

  # Import smoke test (warning only)
  if [[ -f "package.json" ]]; then
    local entry
    entry=$(jq -r '.main // empty' package.json 2>/dev/null)
    if [[ -n "$entry" ]]; then
      if node -e "require('./$entry')" >/dev/null 2>&1; then
        printf "[FINAL SWEEP] Import smoke test passed.\n"
      else
        printf "[FINAL SWEEP] WARNING: Import smoke test failed for %s (non-blocking).\n" "$entry"
      fi
    fi
  elif [[ -f "go.mod" ]]; then
    if go build ./... >/dev/null 2>&1; then
      printf "[FINAL SWEEP] Go build passed.\n"
    else
      printf "[FINAL SWEEP] WARNING: go build failed (non-blocking).\n"
    fi
  fi
}

# =============================================================================
# Generate execution observations document
# =============================================================================

generate_observations() {
  local branch
  branch=$(jq -r '.branchName' quantum.json)
  local date_str
  date_str=$(date +%Y-%m-%d)
  local obs_file="docs/post-mortems/${date_str}-${branch//\//-}-observations.md"

  mkdir -p docs/post-mortems

  local total passed failed blocked
  total=$(jq '.stories | length' quantum.json)
  passed=$(jq '[.stories[] | select(.status == "passed")] | length' quantum.json)
  failed=$(jq '[.stories[] | select(.status == "failed")] | length' quantum.json)
  blocked=$(jq '[.stories[] | select(.status == "blocked")] | length' quantum.json)

  {
    printf "# Execution Observations: %s\n\n" "$branch"
    printf "**Date:** %s\n" "$date_str"
    printf "**Stories:** %d passed, %d failed, %d blocked (of %d total)\n" "$passed" "$failed" "$blocked" "$total"
    printf "**Mode:** %s\n\n" "$(if $PARALLEL_MODE; then echo 'parallel'; else echo 'sequential'; fi)"

    printf "## Failure Summary\n\n"
    local failures
    # Sanitize pipe characters in title so the markdown table stays aligned
    failures=$(jq -r '.stories[] | select(.status == "failed" or .status == "blocked") | "\(.id)|\(.title | gsub("\\|"; "/"))|\(.status)|\(.retries.attempts)/\(.retries.maxAttempts)"' quantum.json 2>/dev/null)
    if [[ -n "$failures" ]]; then
      printf "| Story | Title | Status | Retries |\n"
      printf "|-------|-------|--------|--------|\n"
      while IFS='|' read -r sid title status retries; do
        printf "| %s | %s | %s | %s |\n" "$sid" "${title:0:40}" "$status" "$retries"
      done <<< "$failures"
    else
      printf "No failures.\n"
    fi

    # Phase 6 / P1.7 — Progress Log table: one row per failed-story phase
    # so the learning loop has structured data (previously this block was
    # just an empty <details> block when .progress was []).
    printf "\n## Progress Log\n\n"
    local progress_rows
    progress_rows=$(jq -r '
      [
        (.stories[] | select(.retries.failureLog // [] | length > 0)
          | .id as $sid
          | (.retries.failureLog // [])[]
          | [ $sid,
              (.phase // "unknown"),
              ((.error // "") | gsub("\\|"; "/") | .[0:80]),
              "",
              "",
              "" ]
          | @tsv),
        (.progress // []
          | .[]
          | [ (.storyId // "(pipeline)"),
              (.action // "unknown"),
              ((.details // "") | gsub("\\|"; "/") | .[0:80]),
              "",
              "",
              (.learnings // "") ]
          | @tsv)
      ] | .[]
    ' quantum.json 2>/dev/null)
    if [[ -n "$progress_rows" ]]; then
      printf "| Story | Phase / Action | Error / Detail | Root cause | Fix applied | Lesson |\n"
      printf "|-------|----------------|----------------|-----------|-------------|--------|\n"
      while IFS=$'\t' read -r sid phase detail rc fix lesson; do
        [[ -z "$sid" && -z "$phase" ]] && continue
        printf "| %s | %s | %s | %s | %s | %s |\n" \
          "${sid:-(pipeline)}" "${phase:-unknown}" "${detail:-}" "${rc:-}" "${fix:-}" "${lesson:-}"
      done <<< "$progress_rows"
    else
      printf "_No failed / retried stories. Progress log is empty._\n"
    fi

    printf "\n## Raw Data\n\n"
    printf "<details>\n<summary>Progress JSON</summary>\n\n"
    printf '```json\n'
    jq '.progress' quantum.json
    printf '```\n\n'
    printf "</details>\n\n"

    printf "<details>\n<summary>Failure Logs</summary>\n\n"
    printf '```json\n'
    jq '[.stories[] | select(.retries.failureLog | length > 0) | {id, failureLog: .retries.failureLog}]' quantum.json
    printf '```\n\n'
    printf "</details>\n"
  } > "$obs_file"

  # Phase 6 / P1.7 — promote generalizable lessons from progress entries into
  # codebasePatterns so the next iteration inherits them.
  local new_patterns
  new_patterns=$(jq '[.progress // [] | .[] | select(.learnings? and (.learnings | length > 0)) | .learnings]' quantum.json 2>/dev/null)
  if [[ "$new_patterns" != "[]" && -n "$new_patterns" ]]; then
    local tmpfile
    tmpfile=$(mktemp 2>/dev/null || mktemp -t qlobs)
    jq --argjson newlessons "$new_patterns" '
      .codebasePatterns = ((.codebasePatterns // []) + $newlessons | unique)
    ' quantum.json > "$tmpfile" 2>/dev/null
    if [[ -s "$tmpfile" ]]; then
      mv "$tmpfile" quantum.json
      printf "[OBSERVATIONS] Promoted %s lessons into codebasePatterns.\n" \
        "$(echo "$new_patterns" | jq 'length')"
    else
      rm -f "$tmpfile"
    fi
  fi

  git add "$obs_file" && git commit -m "docs: execution observations for $branch" >/dev/null 2>&1 || true
  printf "[OBSERVATIONS] Generated %s\n" "$obs_file"

  # Check if observations contain issues worth reporting
  local has_blocked has_recurring
  has_blocked=$(jq '[.stories[] | select(.status == "blocked" or .status == "failed")] | length' quantum.json)
  has_recurring=$(jq '[.stories[] | (.retries.failureLog // [])[] | .phase] | group_by(.) | map(select(length > 1)) | length' quantum.json 2>/dev/null || echo "0")

  if [[ "$has_blocked" -gt 0 || "$has_recurring" -gt 0 ]]; then
    # Skip prompt if non-interactive
    if [[ ! -t 0 ]] || [[ "${NON_INTERACTIVE:-false}" == "true" ]]; then
      printf "[OBSERVATIONS] Skipping GitHub issue prompt (non-interactive mode).\n"
      return
    fi

    printf "\n[OBSERVATIONS] Found issues worth reporting (%d blocked/failed, %d recurring patterns).\n" "$has_blocked" "$has_recurring"
    read -rp "File observations as GitHub issue on quantum-loop? [y/N] " response
    if [[ "$response" =~ ^[Yy]$ ]]; then
      if command -v gh >/dev/null 2>&1; then
        gh issue create --repo andyzengmath/quantum-loop \
          --title "Execution observations: $branch ($date_str)" \
          --body "$(cat "$obs_file")" \
          --label "execution-feedback" 2>/dev/null && \
          printf "[OBSERVATIONS] GitHub issue filed.\n" || \
          printf "[OBSERVATIONS] Failed to file GitHub issue (gh error). Local doc is available.\n"
      else
        printf "[OBSERVATIONS] gh CLI not found. Local doc is available at %s\n" "$obs_file"
      fi
    fi
  fi
}

# =============================================================================
# Main header
# =============================================================================

printf "===========================================\n"
printf "  Quantum-Loop Autonomous Development\n"
printf "===========================================\n"
printf "  Branch:      %s\n" "$BRANCH"
printf "  Runner:      %s (%s)\n" "$RUNNER_NAME" "$RUNNER_BINARY"
printf "  Tier:        %s\n" "$RUNNER_TIER"
printf "  Instruction: %s\n" "$RUNNER_INSTRUCTION_NATIVE"
printf "  Max Iter:    %s\n" "$MAX_ITERATIONS"
printf "  Max Retries: %s\n" "$MAX_RETRIES"
if [[ "$PARALLEL_MODE" == "true" ]]; then
  printf "  Mode:        Parallel (max %s concurrent)\n" "$MAX_PARALLEL"
else
  printf "  Mode:        Sequential\n"
fi
printf "===========================================\n\n"

# =============================================================================
# Parallel execution mode
# =============================================================================

if [[ "$PARALLEL_MODE" == "true" ]]; then
  # Phase 20 / P2.11 — platform-aware reaper. Load lib/reaper.sh so the trap
  # cascades through `taskkill //T //F` on Git Bash (where `kill` on a subshell
  # pid does NOT reach the native claude.exe child) and via `kill -TERM -pgid`
  # on POSIX where available. Durable pidfiles live in REAPER_PID_DIR so a
  # separate `ql-housekeep --reap-orphans` can clean up anything this trap
  # misses (terminal close, crash, Agent-tool grandchildren).
  REAPER_PID_DIR="${REAPER_PID_DIR:-.ql-agent-pids}"
  export REAPER_PID_DIR
  if [[ -f "$REPO_ROOT/lib/reaper.sh" ]]; then
    # shellcheck source=lib/reaper.sh
    source "$REPO_ROOT/lib/reaper.sh"
  fi

  declare -a AGENT_PIDS=()
  declare -a AGENT_STORIES=()
  cleanup_on_exit() {
    printf "\n[INTERRUPT] Cleaning up agents...\n"
    if type reap_agent &>/dev/null; then
      # Phase 21 fix: background each reap so the SIGTERM → grace → SIGKILL
      # escalation happens IN PARALLEL across all agents. Without this,
      # Ctrl+C blocks for N × REAPER_GRACE_SECS (20+ seconds with
      # MAX_PARALLEL=4). Waits ≤ 1 × REAPER_GRACE_SECS regardless of
      # agent count.
      local -a REAP_PIDS=()
      for sid in "${AGENT_STORIES[@]+"${AGENT_STORIES[@]}"}"; do
        reap_agent "$REAPER_PID_DIR" "$sid" &
        REAP_PIDS+=("$!")
      done
      for rp in "${REAP_PIDS[@]+"${REAP_PIDS[@]}"}"; do
        wait "$rp" 2>/dev/null || true
      done
    else
      # Fallback: legacy best-effort kill if reaper missing
      for pid in "${AGENT_PIDS[@]+"${AGENT_PIDS[@]}"}"; do
        kill "$pid" 2>/dev/null || true
      done
      for pid in "${AGENT_PIDS[@]+"${AGENT_PIDS[@]}"}"; do
        wait "$pid" 2>/dev/null || true
      done
    fi
    exit 130
  }
  trap cleanup_on_exit INT TERM

  # Crash recovery on startup
  REPO_ROOT="$(pwd)"
  recover_orphaned_worktrees "$REPO_ROOT/quantum.json" "$REPO_ROOT" || true
  cleanup_stale_tmp "$REPO_ROOT/quantum.json" || true
  # Phase 20 / P2.11 — reap any claude processes left by a prior crashed run
  # (their pidfiles will be in REAPER_PID_DIR with start_epoch older than
  # REAPER_STALE_SECS, default 1h). No-op if reaper not loaded.
  if type reap_orphans &>/dev/null; then
    REAPED=$(reap_orphans "$REPO_ROOT/$REAPER_PID_DIR" 2>/dev/null || echo 0)
    if [[ -n "$REAPED" && "$REAPED" != "0" ]]; then
      printf "[REAPER] reaped %s orphan agent(s) from prior run\n" "$REAPED"
    fi
  fi

  WAVE=0

  for ITERATION in $(seq 1 "$MAX_ITERATIONS"); do
    printf "\n=== Iteration %d / %d ===\n\n" "$ITERATION" "$MAX_ITERATIONS"

    # Detect stale stories before DAG query
    detect_stale_stories

    # Get executable stories from DAG
    EXECUTABLE=$(get_executable_stories "$REPO_ROOT/quantum.json")

    if [[ "$EXECUTABLE" == "COMPLETE" ]]; then
      final_verification_sweep
      printf "\n===========================================\n"
      printf "  <quantum>COMPLETE</quantum>\n"
      printf "  All stories passed! Feature is done.\n"
      printf "===========================================\n"
      print_summary_table
      exit 0
    fi

    if [[ "$EXECUTABLE" == "BLOCKED" ]]; then
      printf "\n===========================================\n"
      printf "  <quantum>BLOCKED</quantum>\n"
      printf "  No executable stories remain.\n"
      printf "===========================================\n"
      print_summary_table
      exit 1
    fi

    if [[ -z "$EXECUTABLE" ]]; then
      printf "WARNING: No executable stories found\n"
      print_summary_table
      exit 1
    fi

    # Filter out stories that share files with higher-priority stories in this wave
    EXECUTABLE=$(filter_file_conflicts "$REPO_ROOT/quantum.json" "$EXECUTABLE")

    # Count executable stories
    EXEC_COUNT=$(echo "$EXECUTABLE" | jq '. | length')
    WAVE=$((WAVE + 1))

    # Setup execution metadata
    update_execution_field "$REPO_ROOT/quantum.json" "parallel" "$MAX_PARALLEL" "$WAVE" || true

    # Arrays to track spawned agents
    declare -a AGENT_PIDS=()
    declare -a AGENT_STORIES=()
    declare -a AGENT_WORKTREES=()
    declare -a AGENT_START_TIMES=()

    # Spawn agents for each executable story (up to MAX_PARALLEL)
    SPAWN_COUNT=0
    for i in $(seq 0 $((EXEC_COUNT - 1))); do
      if [[ "$SPAWN_COUNT" -ge "$MAX_PARALLEL" ]]; then
        break
      fi

      SID=$(echo "$EXECUTABLE" | jq -r ".[$i]")
      STITLE=$(jq -r --arg id "$SID" '.stories[] | select(.id == $id) | .title' "$REPO_ROOT/quantum.json")

      # Create worktree
      WT_PATH="$REPO_ROOT/.ql-wt/$SID"
      if ! create_worktree "$SID" "$BRANCH" "$REPO_ROOT"; then
        printf "[ERROR] Failed to create worktree for %s\n" "$SID"
        continue
      fi

      # Update quantum.json
      set_story_worktree "$REPO_ROOT/quantum.json" "$SID" ".ql-wt/$SID" || true
      jq --arg id "$SID" --arg now "$(date -u +'%Y-%m-%dT%H:%M:%SZ')" '
        .stories |= map(if .id == $id then .status = "in_progress" | .startedAt = $now else . end)
      ' "$REPO_ROOT/quantum.json" > "$REPO_ROOT/quantum.json.tmp" \
        && mv "$REPO_ROOT/quantum.json.tmp" "$REPO_ROOT/quantum.json"

      # Spawn agent
      PID_FILE=$(mktemp)
      spawn_autonomous "$SID" "$WT_PATH" > "$PID_FILE"
      AGENT_PID=$(cat "$PID_FILE")
      rm -f "$PID_FILE"

      AGENT_PIDS+=("$AGENT_PID")
      AGENT_STORIES+=("$SID")
      AGENT_WORKTREES+=("$WT_PATH")
      AGENT_START_TIMES+=("$(date +%s)")
      SPAWN_COUNT=$((SPAWN_COUNT + 1))

      printf "[SPAWNED] %s - %s (wave %d, PID %s)\n" "$SID" "$STITLE" "$WAVE" "$AGENT_PID"
    done

    if [[ "$SPAWN_COUNT" -eq 0 ]]; then
      printf "WARNING: No agents spawned this iteration\n"
      continue
    fi

    # Monitoring loop
    while [[ ${#AGENT_PIDS[@]} -gt 0 ]]; do
      sleep 5

      local_completed=()
      for idx in "${!AGENT_PIDS[@]}"; do
        PID="${AGENT_PIDS[$idx]}"
        SID="${AGENT_STORIES[$idx]}"
        WT="${AGENT_WORKTREES[$idx]}"
        START="${AGENT_START_TIMES[$idx]}"

        # Check timeout
        TIMED_OUT=$(check_agent_timeout "$START" "$DEFAULT_AGENT_TIMEOUT")
        if [[ "$TIMED_OUT" == "true" ]]; then
          # Phase 21 fix: on Git Bash, kill_agent_process sends SIGTERM
          # only to the MSYS wrapper PID — claude.exe survives. Prefer
          # reap_agent which does MSYS→winpid translation + taskkill //T
          # //F. This was the exact orphan bug PR #29 was filed for, but
          # the watchdog path wasn't migrated in the original commit.
          if type reap_agent &>/dev/null && [[ -n "${REAPER_PID_DIR:-}" ]]; then
            reap_agent "$REAPER_PID_DIR" "$SID" || true
          else
            kill_agent_process "$PID"
          fi
          printf "[TIMEOUT] %s\n" "$SID"
          # Mark failed with phase timeout
          jq --arg id "$SID" '
            .stories |= map(if .id == $id then
              .status = "failed" |
              .startedAt = null |
              .retries.attempts += 1 |
              .retries.failureLog += [{"phase": "timeout", "timestamp": (now | todate)}]
            else . end)
          ' "$REPO_ROOT/quantum.json" > "$REPO_ROOT/quantum.json.tmp" \
            && mv "$REPO_ROOT/quantum.json.tmp" "$REPO_ROOT/quantum.json"
          remove_worktree "$SID" "$REPO_ROOT" || true
          clear_story_worktree "$REPO_ROOT/quantum.json" "$SID" || true
          local_completed+=("$idx")
          continue
        fi

        # Check status
        STATUS=$(check_agent_status "$PID" "$WT")

        case "$STATUS" in
          RUNNING)
            ;;
          STORY_PASSED)
            # Give agent a few seconds to finish after signaling (#9: post-signal timeout)
            local wait_start
            wait_start=$(date +%s)
            while kill -0 "$PID" 2>/dev/null; do
              local wait_elapsed=$(( $(date +%s) - wait_start ))
              if [[ $wait_elapsed -ge 30 ]]; then
                kill "$PID" 2>/dev/null || true
                break
              fi
              sleep 1
            done
            wait "$PID" 2>/dev/null || true
            WT_BRANCH="ql-wt/${SID}"
            # Safety commit: ensure agent changes are committed before merge
            # Exclude junk files (#4) and quantum.json (#5)
            if git -C "$WT" status --porcelain 2>/dev/null | grep -q .; then
              git -C "$WT" add -A >/dev/null 2>&1 || true
              git -C "$WT" reset HEAD -- quantum.json .ql-agent-output.txt quantum.json.tmp >/dev/null 2>&1 || true
              git -C "$WT" checkout -- quantum.json >/dev/null 2>&1 || true
              if ! git -C "$WT" diff --cached --quiet 2>/dev/null; then
                git -C "$WT" commit -m "feat: ${SID} - auto-commit by orchestrator" >/dev/null 2>&1 || true
              fi
            fi
            local STATUS_MERGE=0
            # merge_worktree_branch outputs conflict file list on failure (before aborting)
            local MERGE_OUTPUT
            MERGE_OUTPUT=$(merge_worktree_branch "$REPO_ROOT" "$WT_BRANCH" 2>&1)
            if [[ $? -eq 0 ]]; then
              # Post-merge regression test: verify the merge didn't break anything
              # Detect test command from quantum.json or common patterns
              local TEST_CMD
              TEST_CMD=$(jq -r '.testCommand // empty' "$REPO_ROOT/quantum.json" 2>/dev/null)
              if [[ -z "$TEST_CMD" ]]; then
                # Auto-detect: try common test runners
                if [[ -f "$REPO_ROOT/package.json" ]]; then TEST_CMD="npm test"
                elif [[ -f "$REPO_ROOT/pyproject.toml" ]] || [[ -f "$REPO_ROOT/setup.py" ]]; then TEST_CMD="python -m pytest -x -q"
                elif [[ -f "$REPO_ROOT/Cargo.toml" ]]; then TEST_CMD="cargo test"
                fi
              fi
              if [[ -n "$TEST_CMD" ]]; then
                if ! validate_and_run_test_cmd "$TEST_CMD" "$REPO_ROOT"; then
                  printf "[REGRESSION] %s - tests fail after merge, reverting\n" "$SID"
                  git -C "$REPO_ROOT" revert -m 1 HEAD --no-edit >/dev/null 2>&1 || true
                  jq --arg id "$SID" '
                    .stories |= map(if .id == $id then
                      .status = "failed" |
                      .startedAt = null |
                      .retries.attempts += 1 |
                      .retries.failureLog += [{"phase": "merge_regression", "timestamp": (now | todate)}]
                    else . end)
                  ' "$REPO_ROOT/quantum.json" > "$REPO_ROOT/quantum.json.tmp" \
                    && mv "$REPO_ROOT/quantum.json.tmp" "$REPO_ROOT/quantum.json"
                  STATUS_MERGE=1
                fi
              fi
              if [[ "$STATUS_MERGE" -eq 0 ]]; then
                printf "[PASSED] %s\n" "$SID"
                jq --arg id "$SID" --argjson wave "$WAVE" '
                  .stories |= map(if .id == $id then .status = "passed" | .startedAt = null else . end)
                ' "$REPO_ROOT/quantum.json" > "$REPO_ROOT/quantum.json.tmp" \
                  && mv "$REPO_ROOT/quantum.json.tmp" "$REPO_ROOT/quantum.json"
              fi
            else
              CONFLICT_FILES="${MERGE_OUTPUT:-unknown}"
              STATUS_MERGE=1
              printf "[CONFLICT] %s - merge conflict in: %s\n" "$SID" "$CONFLICT_FILES"
              printf "[INFO] Branch %s preserved for manual resolution\n" "$WT_BRANCH"
              jq --arg id "$SID" --arg files "$CONFLICT_FILES" '
                .stories |= map(if .id == $id then
                  .status = "failed" |
                  .startedAt = null |
                  .retries.attempts += 1 |
                  .retries.failureLog += [{"phase": "merge_conflict", "files": $files, "timestamp": (now | todate)}]
                else . end)
              ' "$REPO_ROOT/quantum.json" > "$REPO_ROOT/quantum.json.tmp" \
                && mv "$REPO_ROOT/quantum.json.tmp" "$REPO_ROOT/quantum.json"
            fi
            # Only remove worktree dir, preserve branch on conflict for manual resolution (#3)
            if [[ "$STATUS_MERGE" == "0" ]]; then
              remove_worktree "$SID" "$REPO_ROOT" || true
            else
              # Remove worktree dir but keep the branch
              git -C "$REPO_ROOT" worktree remove --force ".ql-wt/$SID" 2>/dev/null || true
            fi
            clear_story_worktree "$REPO_ROOT/quantum.json" "$SID" || true
            local_completed+=("$idx")
            ;;
          STORY_FAILED)
            wait "$PID" 2>/dev/null || true
            printf "[FAILED] %s\n" "$SID"
            jq --arg id "$SID" '
              .stories |= map(if .id == $id then
                .status = "failed" |
                .startedAt = null |
                .retries.attempts += 1 |
                .retries.failureLog += [{"phase": "agent_failed", "timestamp": (now | todate)}]
              else . end)
            ' "$REPO_ROOT/quantum.json" > "$REPO_ROOT/quantum.json.tmp" \
              && mv "$REPO_ROOT/quantum.json.tmp" "$REPO_ROOT/quantum.json"
            remove_worktree "$SID" "$REPO_ROOT" || true
            clear_story_worktree "$REPO_ROOT/quantum.json" "$SID" || true
            local_completed+=("$idx")
            ;;
          CRASH)
            printf "[CRASH] %s\n" "$SID"
            jq --arg id "$SID" '
              .stories |= map(if .id == $id then
                .status = "failed" |
                .startedAt = null |
                .retries.attempts += 1 |
                .retries.failureLog += [{"phase": "crash", "timestamp": (now | todate)}]
              else . end)
            ' "$REPO_ROOT/quantum.json" > "$REPO_ROOT/quantum.json.tmp" \
              && mv "$REPO_ROOT/quantum.json.tmp" "$REPO_ROOT/quantum.json"
            remove_worktree "$SID" "$REPO_ROOT" || true
            clear_story_worktree "$REPO_ROOT/quantum.json" "$SID" || true
            local_completed+=("$idx")
            ;;
        esac
      done

      # Remove completed agents from tracking arrays (reverse order to preserve indices)
      for ((ci=${#local_completed[@]}-1; ci>=0; ci--)); do
        ridx="${local_completed[$ci]}"
        unset 'AGENT_PIDS[ridx]'
        unset 'AGENT_STORIES[ridx]'
        unset 'AGENT_WORKTREES[ridx]'
        unset 'AGENT_START_TIMES[ridx]'
      done
      # Re-index arrays
      AGENT_PIDS=("${AGENT_PIDS[@]+"${AGENT_PIDS[@]}"}")
      AGENT_STORIES=("${AGENT_STORIES[@]+"${AGENT_STORIES[@]}"}")
      AGENT_WORKTREES=("${AGENT_WORKTREES[@]+"${AGENT_WORKTREES[@]}"}")
      AGENT_START_TIMES=("${AGENT_START_TIMES[@]+"${AGENT_START_TIMES[@]}"}")

      # After completions, check if new stories are unblocked
      if [[ ${#local_completed[@]} -gt 0 && ${#AGENT_PIDS[@]} -lt $MAX_PARALLEL ]]; then
        NEW_EXEC=$(get_executable_stories "$REPO_ROOT/quantum.json")
        if [[ "$NEW_EXEC" != "COMPLETE" && "$NEW_EXEC" != "BLOCKED" && -n "$NEW_EXEC" ]]; then
          NEW_EXEC=$(filter_file_conflicts "$REPO_ROOT/quantum.json" "$NEW_EXEC")
          NEW_COUNT=$(echo "$NEW_EXEC" | jq '. | length')
          WAVE=$((WAVE + 1))
          for ni in $(seq 0 $((NEW_COUNT - 1))); do
            if [[ ${#AGENT_PIDS[@]} -ge $MAX_PARALLEL ]]; then
              break
            fi
            NSID=$(echo "$NEW_EXEC" | jq -r ".[$ni]")
            NSTITLE=$(jq -r --arg id "$NSID" '.stories[] | select(.id == $id) | .title' "$REPO_ROOT/quantum.json")

            NWT="$REPO_ROOT/.ql-wt/$NSID"
            if ! create_worktree "$NSID" "$BRANCH" "$REPO_ROOT"; then
              printf "[ERROR] Failed to create worktree for %s\n" "$NSID"
              continue
            fi

            set_story_worktree "$REPO_ROOT/quantum.json" "$NSID" ".ql-wt/$NSID" || true
            jq --arg id "$NSID" --arg now "$(date -u +'%Y-%m-%dT%H:%M:%SZ')" '
              .stories |= map(if .id == $id then .status = "in_progress" | .startedAt = $now else . end)
            ' "$REPO_ROOT/quantum.json" > "$REPO_ROOT/quantum.json.tmp" \
              && mv "$REPO_ROOT/quantum.json.tmp" "$REPO_ROOT/quantum.json"

            NPID_FILE=$(mktemp)
            spawn_autonomous "$NSID" "$NWT" > "$NPID_FILE"
            NAGENT_PID=$(cat "$NPID_FILE")
            rm -f "$NPID_FILE"

            AGENT_PIDS+=("$NAGENT_PID")
            AGENT_STORIES+=("$NSID")
            AGENT_WORKTREES+=("$NWT")
            AGENT_START_TIMES+=("$(date +%s)")

            printf "[SPAWNED] %s - %s (wave %d, PID %s)\n" "$NSID" "$NSTITLE" "$WAVE" "$NAGENT_PID"
          done
        fi
      fi
    done

    # Brief pause between iterations
    sleep 2
  done

  printf "\n===========================================\n"
  printf "  <quantum>MAX_ITERATIONS</quantum>\n"
  printf "  Reached maximum of %d iterations.\n" "$MAX_ITERATIONS"
  printf "===========================================\n"
  print_summary_table
  exit 2
fi

# =============================================================================
# Sequential execution mode (original behavior)
# =============================================================================

for ITERATION in $(seq 1 "$MAX_ITERATIONS"); do
  printf "\n=== Iteration %d / %d ===\n\n" "$ITERATION" "$MAX_ITERATIONS"

  # Detect stale stories before DAG query
  detect_stale_stories

  # -------------------------------------------------------------------------
  # Select next executable story (legacy single-spawn) OR wave (coordinator)
  # -------------------------------------------------------------------------
  #
  # v0.9.0 / US-001 (N42 minor): branch on COORDINATOR_MODE.
  #   - true  → call lib/dag-query.sh::next_wave for a wave of parallel-safe
  #     story IDs; spawn coordinator (later in the loop) with the full set.
  #   - false → existing single-story selection (verbatim).
  # WAVE_STORY_IDS is the canonical wave-member array used by pre-mark,
  # case branches, and *) fallback. Under legacy mode it has 1 element
  # (the selected $STORY_ID) so multi-story logic still works correctly.

  WAVE_STORY_IDS_JSON=""    # JSON array string; set under both modes
  WAVE_ID=""                # Only set under coordinator mode

  if [[ "$COORDINATOR_MODE" == "true" ]]; then
    # next_wave returns rc=0 (wave) | 1 (COMPLETE) | 2 (BLOCKED).
    # Output: JSON array of story IDs (only on rc=0).
    WAVE_STORY_IDS_JSON=$(next_wave quantum.json) || NEXT_WAVE_RC=$?
    NEXT_WAVE_RC="${NEXT_WAVE_RC:-0}"
    case "$NEXT_WAVE_RC" in
      0)
        STORY_ID=$(echo "$WAVE_STORY_IDS_JSON" | jq -r '.[0]')
        WAVE_ID="wave-${ITERATION}"
        ;;
      1)
        final_verification_sweep
        printf "\n===========================================\n"
        printf "  <quantum>COMPLETE</quantum>\n"
        printf "  All stories passed! Feature is done.\n"
        printf "===========================================\n"
        print_summary_table
        exit 0
        ;;
      *)
        printf "\n===========================================\n"
        printf "  <quantum>BLOCKED</quantum>\n"
        printf "  No executable stories remain (next_wave rc=%s).\n" "$NEXT_WAVE_RC"
        printf "===========================================\n"
        print_summary_table
        exit 1
        ;;
    esac
    unset NEXT_WAVE_RC
  else
    STORY_ID=$(jq -r '
      .stories as $all |
      [.stories[] |
        select(
          (.status == "pending" or (.status == "failed" and .retries.attempts < .retries.maxAttempts)) and
          (if (.dependsOn | length) == 0 then true
           else [.dependsOn[] | . as $dep | $all | map(select(.id == $dep)) | .[0].status] | all(. == "passed")
           end)
        )
      ] |
      sort_by(.priority) |
      .[0].id // empty
    ' quantum.json)

    # Validate story ID format to prevent jq injection in downstream json_atomic_update calls
    if [[ -n "$STORY_ID" && "$STORY_ID" != "null" && ! "$STORY_ID" =~ ^[A-Za-z0-9_-]+$ ]]; then
      printf "ERROR: invalid story ID format: %s\n" "$STORY_ID" >&2
      exit 1
    fi

    if [[ -z "$STORY_ID" || "$STORY_ID" == "null" ]]; then
      # Check if all stories are passed
      ALL_PASSED=$(jq '[.stories[].status] | all(. == "passed")' quantum.json)
      if [[ "$ALL_PASSED" == "true" ]]; then
        final_verification_sweep
        printf "\n===========================================\n"
        printf "  <quantum>COMPLETE</quantum>\n"
        printf "  All stories passed! Feature is done.\n"
        printf "===========================================\n"
        print_summary_table
        exit 0
      else
        printf "\n===========================================\n"
        printf "  <quantum>BLOCKED</quantum>\n"
        printf "  No executable stories remain.\n"
        printf "===========================================\n"
        print_summary_table
        exit 1
      fi
    fi

    # Legacy mode: synthesize a 1-element wave array from $STORY_ID so
    # multi-story logic (pre-mark, case branches) works uniformly.
    WAVE_STORY_IDS_JSON=$(jq -nc --arg sid "$STORY_ID" '[$sid]')
  fi

  STORY_TITLE=$(jq -r --arg id "$STORY_ID" '.stories[] | select(.id == $id) | .title' quantum.json)
  STORY_ATTEMPT=$(jq -r --arg id "$STORY_ID" '.stories[] | select(.id == $id) | .retries.attempts' quantum.json)

  # v0.9.4 / US-002 (post-v0.9.x audit code-reviewer HIGH): under coordinator
  # mode, STORY_ID is `.[0]` of the wave only — printing per-story metadata
  # here would mislead the operator about the wave (stories 2..N invisible).
  # The wave-level summary at the spawn block (~line 1591) prints the full
  # wave under coordinator mode. Gate the legacy single-story metadata
  # print behind non-coord mode. Symmetric with v0.9.1 US-003's "Spawning"
  # printf gate.
  if [[ "$COORDINATOR_MODE" != "true" ]]; then
    printf "Story:   %s - %s\n" "$STORY_ID" "$STORY_TITLE"
    printf "Attempt: %d\n" "$((STORY_ATTEMPT + 1))"
    printf "\n"
  fi

  # Mark wave story/stories as in_progress (multi-story under coordinator
  # mode; single-story under legacy). v0.9.0 / US-001 (N42 minor) — uses
  # WAVE_STORY_IDS_JSON which is always a JSON array (1-element under
  # legacy, N-element under coordinator).
  now=$(date -u +'%Y-%m-%dT%H:%M:%SZ')
  jq --argjson ids "$WAVE_STORY_IDS_JSON" --arg now "$now" '
    .stories |= map(
      if (.id as $sid | $ids | index($sid))
      then .status = "in_progress" | .startedAt = $now
      else . end
    ) |
    .updatedAt = (now | todate)
  ' quantum.json > quantum.json.tmp && mv quantum.json.tmp quantum.json

  # -------------------------------------------------------------------------
  # Spawn fresh AI instance
  # -------------------------------------------------------------------------

  # v0.9.1 / US-003 (post-v0.9.0 dogfood finding 5b): gate this legacy
  # single-story print under non-coordinator mode. Under coordinator
  # dispatch, the spawn block prints its own "Spawning coordinator for
  # wave-N with K story/stories: ..." message, which is more accurate
  # than this single-story framing.
  if [[ "$COORDINATOR_MODE" != "true" ]]; then
    printf "Spawning %s for story %s...\n" "$RUNNER_NAME" "$STORY_ID"
  fi

  RUNNER_EXIT=0
  if [[ "$COORDINATOR_MODE" == "true" ]]; then
    # v0.9.0 / US-001 (N42 minor): per-wave coordinator dispatch.
    # spawn_coordinator returns a command STRING (via runner_build_cmd or
    # fallback printf) — not an execution. Caller evals it synchronously.
    # The coordinator spawns implementer subagents internally per wave;
    # parent loop blocks until coordinator emits WAVE_PASSED/WAVE_FAILED.
    STORY_IDS_STR=$(echo "$WAVE_STORY_IDS_JSON" | jq -r 'join(" ")')
    PRD_PATH=$(jq -r '.prdPath // "tasks/prd.md"' quantum.json)
    COORD_CMD=$(spawn_coordinator "$WAVE_ID" "$STORY_IDS_STR" "$PRD_PATH" quantum.json) || {
      printf "ERROR: spawn_coordinator failed for wave %s\n" "$WAVE_ID" >&2
      continue
    }
    printf "Spawning coordinator for %s with %d story/stories: %s\n" "$WAVE_ID" "$(echo "$WAVE_STORY_IDS_JSON" | jq 'length')" "$STORY_IDS_STR"
    # v0.9.3 / US-001: wallclock timeout guard. Default 30 min ceiling
    # (configurable via QL_COORDINATOR_TIMEOUT_S env). On rc=124 (SIGTERM
    # kill from `timeout`), the override below sets SIGNAL_RESULT to
    # WAVE_FAILED so per-story aggregation runs from review fields. Closes
    # v0.9.2 dogfood iter-3 hang (coordinator subagent stuck > 3 hours).
    # v0.9.3 / US-003 review fixes: validate numeric (default 1800 on bad
    # input) + degrade gracefully if `timeout` is not on PATH (warn + run
    # without wallclock guard).
    QL_COORDINATOR_TIMEOUT_S="${QL_COORDINATOR_TIMEOUT_S:-1800}"
    if ! [[ "$QL_COORDINATOR_TIMEOUT_S" =~ ^[0-9]+$ ]]; then
      printf "WARN: QL_COORDINATOR_TIMEOUT_S must be a non-negative integer (got '%s'); using default 1800.\n" "$QL_COORDINATOR_TIMEOUT_S" >&2
      QL_COORDINATOR_TIMEOUT_S=1800
    fi
    if command -v timeout >/dev/null 2>&1; then
      OUTPUT=$(timeout --kill-after=10s "${QL_COORDINATOR_TIMEOUT_S}s" bash -c "$COORD_CMD" 2>&1) || RUNNER_EXIT=$?
    else
      printf "WARN: timeout(1) not on PATH; coordinator dispatch running without wallclock guard. v0.9.2 iter-3 hang scenario possible.\n" >&2
      OUTPUT=$(bash -c "$COORD_CMD" 2>&1) || RUNNER_EXIT=$?
    fi
  elif [[ "$RUNNER_NAME" == "claude" ]]; then
    # Claude Code: preserve original command structure — CLAUDE.md via -p, story instruction via --
    PROMPT_FILE="$SCRIPT_DIR/CLAUDE.md"
    OUTPUT=$(claude --dangerously-skip-permissions --print \
      -p "$(cat "$PROMPT_FILE")" \
      -- "Implement story $STORY_ID from quantum.json. This is iteration $ITERATION." 2>&1) || RUNNER_EXIT=$?
  else
    # Non-Claude runners: use runner adapter with preamble injection
    AGENT_PROMPT="Implement story $STORY_ID from quantum.json. This is iteration $ITERATION."
    RUNNER_CMD=$(runner_build_cmd "$AGENT_PROMPT") || {
      printf "ERROR: runner_build_cmd failed for %s\n" "$RUNNER_NAME" >&2
      continue
    }
    OUTPUT=$(eval "$RUNNER_CMD" 2>&1) || RUNNER_EXIT=$?
  fi

  # -------------------------------------------------------------------------
  # Process output
  # -------------------------------------------------------------------------

  # Invoke post_output() hook if defined (for non-Claude runners with hooks)
  if [[ "$RUNNER_NAME" != "claude" ]]; then
    local hooks_dir="${SCRIPT_DIR}/runners/hooks"
    local hook_file="${hooks_dir}/${RUNNER_NAME}-hooks.sh"
    if [[ -f "$hook_file" ]]; then
      # shellcheck source=/dev/null
      source "$hook_file"
      if type post_output &>/dev/null; then
        post_output "$OUTPUT"
      fi
      unset -f post_output pre_spawn 2>/dev/null
    fi
    # Check if hook forced a signal override
    if [[ -n "${RUNNER_OVERRIDE_SIGNAL:-}" ]]; then
      SIGNAL_RESULT="$RUNNER_OVERRIDE_SIGNAL"
      SIGNAL_CONFIDENCE="hook"
      RUNNER_OVERRIDE_SIGNAL=""
    fi
  fi

  # Parse runner output for signals (uses heuristics if enabled for non-Claude runners)
  runner_parse_output "$OUTPUT" "$RUNNER_EXIT"

  # v0.9.3 / US-001: timeout override. If `timeout` killed the coordinator
  # subagent (rc=124), force SIGNAL_RESULT=WAVE_FAILED regardless of what
  # runner_parse_output classified the (possibly empty/partial) output as.
  # This ensures the WAVE_FAILED branch's per-story review-field aggregation
  # runs uniformly. Closes v0.9.2 dogfood iter-3 hang.
  if [[ "$COORDINATOR_MODE" == "true" && "${RUNNER_EXIT:-0}" == "124" ]]; then
    printf "ERROR: Coordinator subagent exceeded %ss timeout; marking wave failed.\n" "$QL_COORDINATOR_TIMEOUT_S" >&2
    SIGNAL_RESULT="WAVE_FAILED"
  fi

  # v0.8.1 / US-001 (N39 dogfood) — wire ql_wrap_subagent_dispatch into the
  # production runner loop. The function was defined in v0.8.0 US-001 but
  # had zero callers in quantum-loop.sh — exactly N33 root cause #1
  # repeating. v0.8.1 / US-006 (post-PR-review fix): the original guard was
  # `[[ -z "$SIGNAL_RESULT" ]]` which is always false because
  # runner_parse_output ALWAYS sets SIGNAL_RESULT before returning (exact
  # match, heuristic fallback, or "STORY_FAILED" no-signal default). The
  # corrected guard fires on STORY_FAILED with non-exact confidence — the
  # actual "drift suspect" condition: the runner failed but we used
  # heuristics or fallback to classify it. Limitation: when QL_RESPAWN_CMD
  # is set and the wrap respawns successfully, the respawn's output is NOT
  # re-parsed (SIGNAL_RESULT stays at STORY_FAILED). This is a soft-fire
  # diagnostic only. Operators wanting full re-entry should use the
  # quantum-loop iteration loop's natural retry path. Tracked as N46 for
  # v0.9.0+ along with N42 (real per-wave dispatch).
  # v0.9.0 / US-001 (N42 minor): skip the soft-fire wrap under coordinator
  # mode. The coordinator handles its own internal retries (per
  # agents/coordinator.md), and the wrap's QL_RESPAWN_CMD path was
  # designed for single-story respawn — re-running it under coordinator
  # mode would re-spawn the entire wave with stale story arguments.
  # N46 (respawn output re-parsing) is the proper v0.9.1+ fix.
  # v0.9.3 / US-002 follow-up: re-evaluation kept gate OFF.
  # Rationale: STALE detection unsafe under coordinator mode — the coordinator
  # may legitimately spend minutes aggregating signals + writing review
  # fields without producing new commits, which would false-positive STALE.
  # The v0.9.3 US-001 wallclock timeout (QL_COORDINATOR_TIMEOUT_S, default
  # 1800s) is the operational alternative: blanket wallclock kill rather
  # than commit-progress poll. N46 (respawn output re-parsing) remains
  # unresolved as of v0.9.3.
  if [[ "$COORDINATOR_MODE" != "true" \
        && "${SIGNAL_RESULT:-}" == "STORY_FAILED" \
        && "${SIGNAL_CONFIDENCE:-}" != "exact" ]]; then
    ql_wrap_subagent_dispatch 5 1 "" >&2 || true
  fi

  # v0.9.2 / US-002 (defense-in-depth): STORY_* signals are unexpected under
  # coordinator mode (the coordinator contract requires WAVE_* signals).
  # If a STORY_* signal somehow surfaces (coordinator bug, prompt drift,
  # parser misroute), the legacy single-story case branches use scalar
  # $STORY_ID — under coordinator mode that's only the wave's first story,
  # so the other wave members would be orphaned `in_progress`. Redirect
  # to WAVE_FAILED branch so the per-story review-field aggregation runs
  # uniformly across all wave members.
  if [[ "$COORDINATOR_MODE" == "true" && "${SIGNAL_RESULT:-}" =~ ^(STORY_PASSED|STORY_FAILED|BLOCKED)$ ]]; then
    printf "WARNING: Unexpected %s under coordinator mode (expected WAVE_*). Wave members may be orphaned. Treating as WAVE_FAILED for per-story aggregation.\n" "$SIGNAL_RESULT" >&2
    SIGNAL_RESULT="WAVE_FAILED"
  fi

  case "$SIGNAL_RESULT" in
    COMPLETE)
      final_verification_sweep
      printf "\n===========================================\n"
      printf "  <quantum>COMPLETE</quantum>\n"
      printf "  All stories passed! Feature is done.\n"
      printf "===========================================\n"
      print_summary_table
      exit 0
      ;;
    STORY_PASSED)
      printf "Story %s PASSED. Continuing to next story...\n" "$STORY_ID"
      json_atomic_update ".stories |= map(if .id == \"$STORY_ID\" then .status = \"passed\" | .startedAt = null else . end)"
      ;;
    STORY_FAILED)
      printf "Story %s FAILED (attempt %d). Will retry if attempts remain.\n" "$STORY_ID" "$((STORY_ATTEMPT + 1))"
      json_atomic_update ".stories |= map(if .id == \"$STORY_ID\" then .status = \"failed\" | .startedAt = null | .retries.attempts += 1 | .retries.failureLog += [{\"phase\": \"agent_failed\", \"timestamp\": (now | todate)}] else . end)"
      ;;
    BLOCKED)
      json_atomic_update ".stories |= map(if .id == \"$STORY_ID\" then .startedAt = null else . end)"
      printf "\n===========================================\n"
      printf "  <quantum>BLOCKED</quantum>\n"
      printf "  Agent reports no executable stories.\n"
      printf "===========================================\n"
      print_summary_table
      exit 1
      ;;
    WAVE_PASSED)
      # v0.9.0 / US-003 (N42 minor): multi-story aggregation. Bulk-update
      # ALL wave stories to status=passed via a single jq pass, indexed by
      # WAVE_STORY_IDS_JSON (1-element under legacy mode, N-element under
      # coordinator mode). Replaces v0.8.3's single-story-progressing
      # placeholder.
      WAVE_LEN=$(echo "$WAVE_STORY_IDS_JSON" | jq 'length')
      printf "Wave (%s) PASSED — %d story/stories: %s\n" \
        "${WAVE_ID:-iteration-$ITERATION}" "$WAVE_LEN" "$(echo "$WAVE_STORY_IDS_JSON" | jq -r 'join(", ")')"
      now=$(date -u +'%Y-%m-%dT%H:%M:%SZ')
      jq --argjson ids "$WAVE_STORY_IDS_JSON" --arg now "$now" '
        .stories |= map(
          if (.id as $sid | $ids | index($sid))
          then .status = "passed" | .startedAt = null
          else . end
        ) |
        .updatedAt = $now
      ' quantum.json > quantum.json.tmp && mv quantum.json.tmp quantum.json
      ;;
    WAVE_FAILED)
      # v0.8.3 / US-001 (4th-layer N33 closure): wave-level failure signal.
      # v0.9.0 / US-003 (N42 minor) — per-story aggregation via Option A:
      # the coordinator owns review.specCompliance + review.codeQuality
      # writes (per agents/coordinator.md field-ownership contract). For
      # each wave story, derive status from those review fields:
      #   review.{spec,quality}.status == "passed" → status=passed
      #   else → status=failed + retries.attempts++ + failureLog append
      # Stories that the coordinator never reached (no review timestamp)
      # are conservatively marked failed (parent cannot infer success
      # from missing data).
      WAVE_LEN=$(echo "$WAVE_STORY_IDS_JSON" | jq 'length')
      printf "Wave (%s) FAILED — %d story/stories. Per-story outcome derived from review fields.\n" \
        "${WAVE_ID:-iteration-$ITERATION}" "$WAVE_LEN"
      now=$(date -u +'%Y-%m-%dT%H:%M:%SZ')
      jq --argjson ids "$WAVE_STORY_IDS_JSON" --arg now "$now" '
        .stories |= map(
          if (.id as $sid | $ids | index($sid)) then
            if (.review.specCompliance.status == "passed"
                and .review.codeQuality.status == "passed") then
              .status = "passed" | .startedAt = null
            else
              .status = "failed" | .startedAt = null
              | .retries.attempts += 1
              | .retries.failureLog += [{"phase": "wave_failed", "timestamp": $now}]
            end
          else . end
        ) |
        .updatedAt = $now
      ' quantum.json > quantum.json.tmp && mv quantum.json.tmp quantum.json
      ;;
    *)
      # v0.8.1 / US-006 (post-PR-review fix): increment retries.attempts and
      # append to failureLog so a story that repeatedly hits the unknown-signal
      # branch eventually exhausts retries and surfaces as BLOCKED.
      #
      # v0.9.0 / US-001 (N42 minor): apply retry accounting to ALL wave
      # stories (not just $STORY_ID) under coordinator mode. The original
      # single-story logic referenced $STORY_ID which under coordinator
      # mode is set to the wave's first story only — leaving other wave
      # members orphaned in_progress (HIGH risk per architect 1's design
      # review). The new jq uses WAVE_STORY_IDS_JSON which is 1-element
      # under legacy mode (preserves existing semantics).
      printf "WARNING: No recognized signal in output. Wave may not have completed cleanly.\n"
      printf "Last 10 lines of output:\n"
      echo "$OUTPUT" | tail -10
      now=$(date -u +'%Y-%m-%dT%H:%M:%SZ')
      jq --argjson ids "$WAVE_STORY_IDS_JSON" --arg now "$now" '
        .stories |= map(
          if (.id as $sid | $ids | index($sid))
          then .status = "failed" | .startedAt = null
               | .retries.attempts += 1
               | .retries.failureLog += [{"phase": "no_signal", "timestamp": $now}]
          else . end
        ) |
        .updatedAt = $now
      ' quantum.json > quantum.json.tmp && mv quantum.json.tmp quantum.json
      ;;
  esac

  # Brief pause between iterations
  sleep 2
done

printf "\n===========================================\n"
printf "  <quantum>MAX_ITERATIONS</quantum>\n"
printf "  Reached maximum of %d iterations.\n" "$MAX_ITERATIONS"
printf "===========================================\n"
print_summary_table
generate_observations
exit 2
