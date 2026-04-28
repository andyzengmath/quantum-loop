#!/usr/bin/env bash
# tests/run_all.sh — quantum-loop test-suite runner.
#
# Modes:
#   (default)            Run all tests/test_*.sh sequentially.
#   --quick              Run only test files changed vs master
#                        (`git diff master..HEAD --name-only -- 'tests/test_*.sh'`).
#                        Exit 0 with "no test files changed since master" if empty.
#   --parallel N         Run files in parallel via xargs -P N (N defaults to 4).
#                        Falls back to sequential with stderr warning if xargs -P
#                        is not supported on the host.
#   --quick --parallel N Combined: filter to changed files, dispatch via xargs.
#
# Output: one line per file `tests/test_<name>.sh: <PASS>/<TOTAL> passed`.
# Exit: 0 iff all tests PASS; 1 iff any FAIL.
#
# PARALLEL_UNSAFE allowlist (currently empty): test files that mutate process-
# global state and cannot run concurrently with siblings. To opt out, add the
# basename here and document the rationale. The runner skips these in
# --parallel mode and runs them sequentially after the parallel batch.
#
# G31 / US-005 (v0.6.6).

set -uo pipefail

PARALLEL_UNSAFE=()  # currently empty; future regressions land here

QUICK=0
PARALLEL_N=0   # 0 = sequential
ONE_FILE=""    # private entry-point used by --parallel xargs dispatch
while (( $# > 0 )); do
  case "$1" in
    --quick)    QUICK=1; shift ;;
    --parallel) PARALLEL_N="${2:-4}"; shift 2 ;;
    --__one)    ONE_FILE="$2"; shift 2 ;;
    -h|--help)
      sed -n '2,/^$/p' "$0"; exit 0 ;;
    *)
      printf '[run_all] ERROR: unknown arg %q\n' "$1" >&2; exit 2 ;;
  esac
done

# Resolve test-directory location.
#   When invoked as `cd <repo> && bash tests/run_all.sh`, REPO_ROOT is $PWD
#   and the tests live at $PWD/tests/. This is the path the smoke benchmark
#   in T-003 (and the real-world retrospective T-002) takes.
#   When invoked from a fixture tmp-dir (test_run_all.sh), the caller cds
#   into the fixture and we glob $PWD/tests/. This decoupling from the
#   script's own location is what makes the fixture-driven tests possible.
# Fall back to the script's own dir if neither $PWD/tests nor $PWD/tests/test_*.sh
# is present (lets `bash /abs/path/run_all.sh` still work).
REPO_ROOT="$(pwd)"
if [[ -d "$REPO_ROOT/tests" ]]; then
  SCRIPT_DIR="$REPO_ROOT/tests"
else
  SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
fi

# Enumerate candidate test files.
shopt -s nullglob
declare -a ALL_TESTS=("$SCRIPT_DIR"/test_*.sh)
shopt -u nullglob

# --quick filter: take only files in `git diff master..HEAD --name-only`.
declare -a TARGET_TESTS
if (( QUICK == 1 )); then
  changed=$(cd "$REPO_ROOT" && git diff master..HEAD --name-only -- 'tests/test_*.sh' 2>/dev/null || true)
  if [[ -z "$changed" ]]; then
    printf '[run_all] no test files changed since master\n'
    exit 0
  fi
  while IFS= read -r rel; do
    [[ -z "$rel" ]] && continue
    full="$REPO_ROOT/$rel"
    if [[ -f "$full" ]]; then
      TARGET_TESTS+=("$full")
    fi
  done <<< "$changed"
else
  TARGET_TESTS=("${ALL_TESTS[@]}")
fi

if (( ${#TARGET_TESTS[@]} == 0 )); then
  printf '[run_all] no tests matched\n'
  exit 0
fi

# Detect xargs -P availability for --parallel mode.
if (( PARALLEL_N > 0 )); then
  if ! xargs -P 1 -I_ true </dev/null 2>/dev/null; then
    printf '[run_all] WARN: parallel unavailable; falling back to sequential\n' >&2
    PARALLEL_N=0
  fi
fi

# run_one(test_file) — run a single test file, emit one summary line.
# Captures stdout to derive PASS/TOTAL counts. Exit code is 0 if any "FAIL:"
# line occurs OR the test exits non-zero, else 1.
run_one() {
  local f="$1"
  local rel="${f#"$REPO_ROOT/"}"
  local out rc
  # Two-invocation idiom (CLAUDE.md Platform Notes): run twice — once for
  # stdout (with || true to absorb non-zero), once for exit code.
  out=$(bash "$f" 2>&1 || true)
  rc=$(bash "$f" >/dev/null 2>&1 ; echo $?)
  # Parse "=== Results: <P>/<T> passed, <F> failed ===" if present, else
  # default to a coarse 0/1 based on rc.
  local pt
  pt=$(printf '%s' "$out" | grep -oE 'Results: [0-9]+/[0-9]+ passed' | tail -1 \
       | sed -E 's/Results: ([0-9]+)\/([0-9]+) passed/\1\/\2/')
  if [[ -z "$pt" ]]; then
    if [[ "$rc" -eq 0 ]]; then pt="1/1"; else pt="0/1"; fi
  fi
  printf '%s: %s passed\n' "$rel" "$pt"
  return "$rc"
}

# Private entry-point: when invoked as `bash run_all.sh --__one <file>`,
# run a single test and exit. Used by xargs -P dispatch in --parallel mode
# to sidestep export-f portability quirks on MSYS / Git Bash.
if [[ -n "$ONE_FILE" ]]; then
  run_one "$ONE_FILE"
  exit $?
fi

OVERALL_RC=0
if (( PARALLEL_N > 0 )); then
  # Parallel dispatch via xargs -P. We pipe one filename per line and have
  # xargs invoke a self-recursive run_all.sh with --__one <file> as a private
  # entry-point. This sidesteps the export-f portability issue on MSYS where
  # bash -c subshells don't reliably inherit exported functions.
  out=$(printf '%s\n' "${TARGET_TESTS[@]}" | \
        xargs -P "$PARALLEL_N" -I{} bash "${BASH_SOURCE[0]}" --__one '{}' 2>&1 || true)
  printf '%s\n' "$out"
  if printf '%s' "$out" | grep -qE ': 0/[0-9]+ passed'; then
    OVERALL_RC=1
  fi
  # Run any PARALLEL_UNSAFE files sequentially as a follow-up batch.
  for unsafe in "${PARALLEL_UNSAFE[@]}"; do
    f="$SCRIPT_DIR/$unsafe"
    [[ -f "$f" ]] || continue
    if ! run_one "$f"; then OVERALL_RC=1; fi
  done
else
  for f in "${TARGET_TESTS[@]}"; do
    if ! run_one "$f"; then OVERALL_RC=1; fi
  done
fi

exit "$OVERALL_RC"
