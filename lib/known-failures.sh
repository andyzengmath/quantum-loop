#!/usr/bin/env bash
# lib/known-failures.sh -- Known test failures tracking for quantum-loop
#
# Provides: detect_test_runner(), capture_baseline(), capture_wave_snapshot(),
#           delta_check(), format_agent_context()
# Requires: lib/common.sh, python, jq

# Source shared utilities
KF_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$KF_LIB_DIR/common.sh" || { printf "ERROR: common.sh not found\n" >&2; return 1 2>/dev/null || exit 1; }

# _to_native_path(path)
# Converts a MSYS/Cygwin path to a native Windows path when running on Windows.
# On Unix, returns the path unchanged. This is needed because Python on Windows
# cannot read /tmp/ style paths that bash creates via mktemp.
_kf_to_native_path() {
  local p="$1"
  if command -v cygpath &>/dev/null; then
    cygpath -m "$p"
  else
    printf '%s' "$p"
  fi
}

# detect_test_runner(repo_root)
# Detects the test runner for a given repository.
# Checks package.json (jest/vitest), pyproject.toml/pytest.ini/setup.cfg (pytest), go.mod (go test).
# Returns "runner:command" on stdout, or empty string if nothing detected.
detect_test_runner() {
  local repo_root="$1"

  if [[ -z "$repo_root" || ! -d "$repo_root" ]]; then
    printf ""
    return 0
  fi

  # Check for Node.js test runners (jest/vitest) in package.json
  if [[ -f "$repo_root/package.json" ]]; then
    local detected
    local native_pkg
    native_pkg=$(_kf_to_native_path "$repo_root/package.json")
    detected=$(python -c "
import sys, json
try:
    with open(sys.argv[1]) as f:
        d = json.load(f)
    deps = {}
    deps.update(d.get('devDependencies', {}))
    deps.update(d.get('dependencies', {}))
    if 'jest' in deps:
        print('jest:npx jest --json')
    elif 'vitest' in deps:
        print('vitest:npx vitest run --reporter=json')
    else:
        print('')
except Exception:
    print('')
" "$native_pkg" 2>/dev/null)
    if [[ -n "$detected" ]]; then
      printf "%s" "$detected"
      return 0
    fi
  fi

  # Check for pytest in pyproject.toml
  if [[ -f "$repo_root/pyproject.toml" ]]; then
    if grep -qE '\[tool\.pytest|pytest' "$repo_root/pyproject.toml" 2>/dev/null; then
      printf "pytest:pytest -v --tb=line -q"
      return 0
    fi
  fi

  # Check for pytest in pytest.ini
  if [[ -f "$repo_root/pytest.ini" ]]; then
    printf "pytest:pytest -v --tb=line -q"
    return 0
  fi

  # Check for pytest in setup.cfg
  if [[ -f "$repo_root/setup.cfg" ]]; then
    if grep -q '\[tool:pytest\]' "$repo_root/setup.cfg" 2>/dev/null; then
      printf "pytest:pytest -v --tb=line -q"
      return 0
    fi
  fi

  # Check for Go test runner
  if [[ -f "$repo_root/go.mod" ]]; then
    printf "go:go test -v ./..."
    return 0
  fi

  # Nothing detected
  printf ""
  return 0
}

# _parse_jest_output(output)
# Parses jest JSON output and prints "passCount failCount skipCount\nfailing_test_name1\nfailing_test_name2..."
# Returns 0 on success, 1 on parse failure.
_parse_jest_output() {
  local output="$1"
  printf '%s' "$output" | python -c "
import sys, json
try:
    d = json.load(sys.stdin)
    pc = d.get('numPassedTests', 0)
    fc = d.get('numFailedTests', 0)
    sc = d.get('numPendingTests', 0)
    print(f'{pc} {fc} {sc}')
    for t in d.get('testResults', []):
        if t.get('status') == 'failed':
            err = t.get('message', '')
            if err:
                err = err.split(chr(10))[0][:200]
            print(f'{t[\"name\"]}|||{err}')
except Exception:
    sys.exit(1)
" 2>/dev/null
}

# _parse_pytest_output(output)
# Parses pytest -v output and prints "passCount failCount skipCount\nfailing_test_name1\n..."
# Returns 0 on success, 1 on parse failure.
_parse_pytest_output() {
  local output="$1"
  printf '%s' "$output" | python -c "
import sys, re
lines = sys.stdin.read().strip().split(chr(10))
passed = 0
failed = 0
skipped = 0
failing = []
for line in lines:
    stripped = line.strip()
    if stripped.endswith('PASSED'):
        passed += 1
    elif stripped.endswith('FAILED'):
        failed += 1
        name = stripped.rsplit(' ', 1)[0].strip()
        failing.append(name)
    elif stripped.endswith('SKIPPED'):
        skipped += 1
    else:
        m = re.match(r'(\d+) passed', stripped)
        if m:
            passed = int(m.group(1))
        m2 = re.search(r'(\d+) failed', stripped)
        if m2:
            failed = int(m2.group(1))
        m3 = re.search(r'(\d+) skipped', stripped)
        if m3:
            skipped = int(m3.group(1))
if passed == 0 and failed == 0:
    sys.exit(1)
print(f'{passed} {failed} {skipped}')
for name in failing:
    print(f'{name}|||')
" 2>/dev/null
}

# _parse_go_output(output)
# Parses go test -v output and prints "passCount failCount skipCount\nfailing_test_name1\n..."
# Returns 0 on success, 1 on parse failure.
_parse_go_output() {
  local output="$1"
  printf '%s' "$output" | python -c "
import sys, re
lines = sys.stdin.read().strip().split(chr(10))
passed = 0
failed = 0
skipped = 0
failing = []
last_error = {}
current_test = None
for line in lines:
    stripped = line.strip()
    m_pass = re.match(r'--- PASS: (\S+)', stripped)
    m_fail = re.match(r'--- FAIL: (\S+)', stripped)
    m_skip = re.match(r'--- SKIP: (\S+)', stripped)
    m_run = re.match(r'=== RUN\s+(\S+)', stripped)
    if m_run:
        current_test = m_run.group(1)
    elif m_pass:
        passed += 1
        current_test = None
    elif m_fail:
        failed += 1
        name = m_fail.group(1)
        err = last_error.get(name, '')
        failing.append((name, err))
        current_test = None
    elif m_skip:
        skipped += 1
        current_test = None
    elif current_test and stripped and not stripped.startswith('==='):
        last_error[current_test] = stripped[:200]
if passed == 0 and failed == 0 and skipped == 0:
    sys.exit(1)
print(f'{passed} {failed} {skipped}')
for name, err in failing:
    print(f'{name}|||{err}')
" 2>/dev/null
}

# _parse_regex_fallback(output)
# Last resort: count lines containing PASS/FAIL/ERROR keywords.
# Prints "passCount failCount skipCount" on first line, failing test names after.
# Returns 0 on success, 1 if nothing found.
_parse_regex_fallback() {
  local output="$1"
  printf '%s' "$output" | python -c "
import sys, re
lines = sys.stdin.read().strip().split(chr(10))
passed = 0
failed = 0
skipped = 0
failing = []
for line in lines:
    stripped = line.strip()
    if re.match(r'^PASS:', stripped) or re.match(r'.*\bPASS\b', stripped) and re.match(r'^PASS', stripped):
        passed += 1
    elif re.match(r'^FAIL:', stripped):
        failed += 1
        parts = stripped.split(':', 1)
        if len(parts) > 1:
            failing.append(parts[1].strip())
    elif re.match(r'^ERROR:', stripped):
        failed += 1
        parts = stripped.split(':', 1)
        if len(parts) > 1:
            failing.append(parts[1].strip())
if passed == 0 and failed == 0:
    sys.exit(1)
print(f'{passed} {failed} {skipped}')
for name in failing:
    print(f'{name}|||')
" 2>/dev/null
}

# _write_baseline_to_json(json_path, pass_count, fail_count, skip_count, failing_tests_data)
# Writes knownFailures.baseline and knownFailures.current to quantum.json.
# failing_tests_data is newline-separated "name|||error" entries.
_write_baseline_to_json() {
  local json_path="$1"
  local pass_count="$2"
  local fail_count="$3"
  local skip_count="$4"
  local failing_data="$5"
  local native_json_path
  native_json_path=$(_kf_to_native_path "$json_path")

  python -c "
import sys, json
from datetime import datetime, timezone

json_path = sys.argv[1]
pc = int(sys.argv[2])
fc = int(sys.argv[3])
sc = int(sys.argv[4])
failing_raw = sys.argv[5] if len(sys.argv) > 5 else ''

with open(json_path) as f:
    d = json.load(f)

now = datetime.now(timezone.utc).isoformat()
failing_tests = []
if failing_raw.strip():
    for line in failing_raw.strip().split(chr(10)):
        parts = line.split('|||', 1)
        name = parts[0].strip()
        error = parts[1].strip() if len(parts) > 1 else ''
        if name:
            failing_tests.append({
                'name': name,
                'failingSince': 0,
                'introducedBy': None,
                'expectedFix': None,
                'error': error
            })

baseline = {
    'capturedAt': now,
    'wave': 0,
    'passCount': pc,
    'failCount': fc,
    'skipCount': sc,
    'failingTests': failing_tests
}

if 'knownFailures' not in d:
    d['knownFailures'] = {}
d['knownFailures']['baseline'] = baseline
d['knownFailures']['current'] = {
    **baseline,
    'updatedAt': now
}
if 'flakyThreshold' not in d['knownFailures']:
    d['knownFailures']['flakyThreshold'] = 1
if 'fullSuiteTimeout' not in d['knownFailures']:
    d['knownFailures']['fullSuiteTimeout'] = 60

with open(json_path, 'w') as f:
    json.dump(d, f, indent=2)
" "$native_json_path" "$pass_count" "$fail_count" "$skip_count" "$failing_data" 2>/dev/null
}

# capture_baseline(repo_root, json_path)
# Runs the detected test suite, parses output, writes knownFailures.baseline to quantum.json.
# Initializes knownFailures.current as a copy of baseline.
# Falls back to regex counting if structured parse fails.
# If both fail: sets baseline to null and logs warning.
# Returns 0 on success.
capture_baseline() {
  local repo_root="$1"
  local json_path="$2"

  if [[ -z "$repo_root" || -z "$json_path" ]]; then
    printf '[KNOWN-FAILURES] ERROR: capture_baseline requires repo_root and json_path\n' >&2
    return 1
  fi

  local runner_info
  runner_info=$(detect_test_runner "$repo_root")

  local native_json_path
  native_json_path=$(_kf_to_native_path "$json_path")

  if [[ -z "$runner_info" ]]; then
    printf '[KNOWN-FAILURES] No test runner detected -- setting baseline to null\n' >&2
    python -c "
import sys, json
with open(sys.argv[1]) as f:
    d = json.load(f)
if 'knownFailures' not in d:
    d['knownFailures'] = {}
d['knownFailures']['baseline'] = None
d['knownFailures']['current'] = None
with open(sys.argv[1], 'w') as f:
    json.dump(d, f, indent=2)
" "$native_json_path" 2>/dev/null
    return 0
  fi

  local runner="${runner_info%%:*}"
  local cmd="${runner_info#*:}"

  # Run the test suite, capturing output
  local test_output
  test_output=$(cd "$repo_root" && eval "$cmd" 2>&1) || true

  # Try structured parse first
  local parsed=""
  case "$runner" in
    jest|vitest)
      parsed=$(_parse_jest_output "$test_output")
      ;;
    pytest)
      parsed=$(_parse_pytest_output "$test_output")
      ;;
    go)
      parsed=$(_parse_go_output "$test_output")
      ;;
  esac

  # If structured parse failed, try regex fallback
  if [[ -z "$parsed" ]]; then
    printf '[KNOWN-FAILURES] Structured parse failed -- trying regex fallback\n' >&2
    parsed=$(_parse_regex_fallback "$test_output")
  fi

  # If regex also failed, disable tracking
  if [[ -z "$parsed" ]]; then
    printf '[KNOWN-FAILURES] Could not parse test output -- tracking disabled\n' >&2
    python -c "
import sys, json
with open(sys.argv[1]) as f:
    d = json.load(f)
if 'knownFailures' not in d:
    d['knownFailures'] = {}
d['knownFailures']['baseline'] = None
d['knownFailures']['current'] = None
with open(sys.argv[1], 'w') as f:
    json.dump(d, f, indent=2)
" "$native_json_path" 2>/dev/null
    return 0
  fi

  # Extract counts from first line
  local first_line
  first_line=$(printf '%s' "$parsed" | head -1)
  local pass_count fail_count skip_count
  pass_count=$(printf '%s' "$first_line" | awk '{print $1}')
  fail_count=$(printf '%s' "$first_line" | awk '{print $2}')
  skip_count=$(printf '%s' "$first_line" | awk '{print $3}')

  # Extract failing test data (lines after the first)
  local failing_data
  failing_data=$(printf '%s' "$parsed" | tail -n +2)

  _write_baseline_to_json "$json_path" "$pass_count" "$fail_count" "$skip_count" "$failing_data"

  printf '[KNOWN-FAILURES] Baseline: %s pass, %s fail, %s skip\n' "$pass_count" "$fail_count" "$skip_count" >&2
  return 0
}

# _run_and_parse(repo_root)
# Runs the detected test suite and parses the output.
# Prints parsed output (counts line + failing test lines) to stdout.
# Returns 0 on success, 1 if no runner or both parses fail.
_run_and_parse() {
  local repo_root="$1"

  local runner_info
  runner_info=$(detect_test_runner "$repo_root")
  if [[ -z "$runner_info" ]]; then
    return 1
  fi

  local runner="${runner_info%%:*}"
  local cmd="${runner_info#*:}"

  local test_output
  test_output=$(cd "$repo_root" && eval "$cmd" 2>&1) || true

  local parsed=""
  case "$runner" in
    jest|vitest)
      parsed=$(_parse_jest_output "$test_output")
      ;;
    pytest)
      parsed=$(_parse_pytest_output "$test_output")
      ;;
    go)
      parsed=$(_parse_go_output "$test_output")
      ;;
  esac

  if [[ -z "$parsed" ]]; then
    parsed=$(_parse_regex_fallback "$test_output")
  fi

  if [[ -z "$parsed" ]]; then
    return 1
  fi

  printf '%s' "$parsed"
  return 0
}

# capture_wave_snapshot(repo_root, json_path, wave_num)
# Runs the test suite, compares with knownFailures.current, updates with new/resolved failures.
# Logs deltas: '[KNOWN-FAILURES] Wave N: X pass (+/-), Y fail (+/-), Z skip (+/-)'
capture_wave_snapshot() {
  local repo_root="$1"
  local json_path="$2"
  local wave_num="$3"

  if [[ -z "$repo_root" || -z "$json_path" || -z "$wave_num" ]]; then
    printf '[KNOWN-FAILURES] ERROR: capture_wave_snapshot requires repo_root, json_path, wave_num\n' >&2
    return 1
  fi

  local native_json_path
  native_json_path=$(_kf_to_native_path "$json_path")

  local parsed
  parsed=$(_run_and_parse "$repo_root")
  if [[ -z "$parsed" ]]; then
    printf '[KNOWN-FAILURES] Could not parse test output for wave %s\n' "$wave_num" >&2
    return 1
  fi

  local first_line
  first_line=$(printf '%s' "$parsed" | head -1)
  local new_pass new_fail new_skip
  new_pass=$(printf '%s' "$first_line" | awk '{print $1}')
  new_fail=$(printf '%s' "$first_line" | awk '{print $2}')
  new_skip=$(printf '%s' "$first_line" | awk '{print $3}')

  # Extract new failing test names
  local failing_data
  failing_data=$(printf '%s' "$parsed" | tail -n +2)

  # Use Python to compare with current and update
  python -c "
import sys, json
from datetime import datetime, timezone

json_path = sys.argv[1]
wave_num = int(sys.argv[2])
new_pass = int(sys.argv[3])
new_fail = int(sys.argv[4])
new_skip = int(sys.argv[5])
failing_raw = sys.argv[6] if len(sys.argv) > 6 else ''

with open(json_path) as f:
    d = json.load(f)

kf = d.get('knownFailures', {})
if not kf:
    kf = {}
current = kf.get('current', {})
if not current:
    current = {'failingTests': [], 'passCount': 0, 'failCount': 0, 'skipCount': 0}

old_pass = current.get('passCount', 0)
old_fail = current.get('failCount', 0)
old_skip = current.get('skipCount', 0)
old_failing = {t['name']: t for t in current.get('failingTests', [])}

# Parse new failing tests
new_failing_names = set()
new_failing_entries = {}
if failing_raw.strip():
    for line in failing_raw.strip().split(chr(10)):
        parts = line.split('|||', 1)
        name = parts[0].strip()
        error = parts[1].strip() if len(parts) > 1 else ''
        if name:
            new_failing_names.add(name)
            new_failing_entries[name] = error

now = datetime.now(timezone.utc).isoformat()

# Build updated failingTests
updated_tests = []
for name in new_failing_names:
    if name in old_failing:
        # Keep existing entry (already known)
        updated_tests.append(old_failing[name])
    else:
        # NEW failure
        # Try to find introducedBy from git log heuristic
        introduced_by = None
        expected_fix = None
        # Check stories for fixes field
        for story in d.get('stories', []):
            fixes = story.get('fixes', [])
            if isinstance(fixes, list):
                for fid in fixes:
                    if fid == introduced_by:
                        expected_fix = story.get('id')
                        break
        updated_tests.append({
            'name': name,
            'failingSince': wave_num,
            'introducedBy': introduced_by,
            'expectedFix': expected_fix,
            'error': new_failing_entries.get(name, '')
        })

# Update current
current_new = {
    'capturedAt': current.get('capturedAt', now),
    'updatedAt': now,
    'wave': wave_num,
    'passCount': new_pass,
    'failCount': new_fail,
    'skipCount': new_skip,
    'failingTests': updated_tests
}

d['knownFailures'] = kf
d['knownFailures']['current'] = current_new

with open(json_path, 'w') as f:
    json.dump(d, f, indent=2)

# Print delta info for logging
pass_delta = new_pass - old_pass
fail_delta = new_fail - old_fail
skip_delta = new_skip - old_skip
sign = lambda x: f'+{x}' if x > 0 else str(x)
print(f'Wave {wave_num}: {new_pass} pass ({sign(pass_delta)}), {new_fail} fail ({sign(fail_delta)}), {new_skip} skip ({sign(skip_delta)})')
" "$native_json_path" "$wave_num" "$new_pass" "$new_fail" "$new_skip" "$failing_data" 2>/dev/null
  local delta_msg
  delta_msg=$(python -c "
import sys, json
with open(sys.argv[1]) as f:
    d = json.load(f)
kf = d.get('knownFailures', {})
cur = kf.get('current', {})
bl = kf.get('baseline', cur)
p = cur.get('passCount', 0)
f2 = cur.get('failCount', 0)
s = cur.get('skipCount', 0)
bp = bl.get('passCount', 0) if bl else 0
bf = bl.get('failCount', 0) if bl else 0
bs = bl.get('skipCount', 0) if bl else 0
sign = lambda x: f'+{x}' if x > 0 else str(x)
print(f'{p} pass ({sign(p-bp)}), {f2} fail ({sign(f2-bf)}), {s} skip ({sign(s-bs)})')
" "$native_json_path" 2>/dev/null)
  printf '[KNOWN-FAILURES] Wave %s: %s\n' "$wave_num" "$delta_msg" >&2
  return 0
}

# delta_check(repo_root, json_path, story_id)
# Runs test suite, compares to knownFailures.current.
# Returns 0 if all failures are known or below flakyThreshold.
# Returns 1 if new failures exceed flakyThreshold (prints names to stdout).
# Logs wall-clock timing.
delta_check() {
  local repo_root="$1"
  local json_path="$2"
  local story_id="$3"

  if [[ -z "$repo_root" || -z "$json_path" || -z "$story_id" ]]; then
    printf '[KNOWN-FAILURES] ERROR: delta_check requires repo_root, json_path, story_id\n' >&2
    return 1
  fi

  local native_json_path
  native_json_path=$(_kf_to_native_path "$json_path")

  local start_time
  start_time=$SECONDS

  # Read config
  local flaky_threshold full_suite_timeout
  flaky_threshold=$(python -c "
import sys, json
with open(sys.argv[1]) as f:
    d = json.load(f)
print(d.get('knownFailures', {}).get('flakyThreshold', 1))
" "$native_json_path" 2>/dev/null)
  flaky_threshold="${flaky_threshold:-1}"

  full_suite_timeout=$(python -c "
import sys, json
with open(sys.argv[1]) as f:
    d = json.load(f)
print(d.get('knownFailures', {}).get('fullSuiteTimeout', 60))
" "$native_json_path" 2>/dev/null)
  full_suite_timeout="${full_suite_timeout:-60}"

  # Run and parse test output
  local parsed
  parsed=$(_run_and_parse "$repo_root")
  if [[ -z "$parsed" ]]; then
    printf '[KNOWN-FAILURES] Could not parse test output for delta check\n' >&2
    local elapsed=$(( SECONDS - start_time ))
    printf '[KNOWN-FAILURES] Delta check completed in %ss\n' "$elapsed" >&2
    return 0
  fi

  # Extract current failing test names from run
  local run_failing_names
  run_failing_names=$(printf '%s' "$parsed" | tail -n +2 | sed 's/|||.*//' | sed '/^$/d')

  # Read known failing tests from quantum.json
  local known_names
  known_names=$(python -c "
import sys, json
with open(sys.argv[1]) as f:
    d = json.load(f)
kf = d.get('knownFailures', {})
if not kf:
    sys.exit(0)
cur = kf.get('current', {})
if not cur:
    sys.exit(0)
for t in cur.get('failingTests', []):
    print(t['name'])
" "$native_json_path" 2>/dev/null)

  # Find new failures (in run but not in known)
  local new_failures=""
  local new_count=0
  if [[ -n "$run_failing_names" ]]; then
    while IFS= read -r name; do
      if [[ -n "$name" ]] && ! printf '%s\n' "$known_names" | grep -qxF "$name"; then
        new_failures="${new_failures}${name}"$'\n'
        new_count=$((new_count + 1))
      fi
    done <<< "$run_failing_names"
  fi

  local elapsed=$(( SECONDS - start_time ))

  if [[ $new_count -eq 0 ]]; then
    # All failures are known
    local total_known
    total_known=$(printf '%s' "$run_failing_names" | grep -c . 2>/dev/null || echo 0)
    if [[ "$total_known" -gt 0 ]]; then
      printf '[KNOWN-FAILURES] %s known failures present -- PASS\n' "$total_known" >&2
    fi
    printf '[KNOWN-FAILURES] Delta check completed in %ss\n' "$elapsed" >&2
    return 0
  elif [[ $new_count -le $flaky_threshold ]]; then
    # New failures but below threshold
    printf '[KNOWN-FAILURES] %s new failure(s) below flaky threshold -- treating as noise\n' "$new_count" >&2
    printf '[KNOWN-FAILURES] Delta check completed in %ss\n' "$elapsed" >&2
    return 0
  else
    # New failures above threshold
    printf '%s' "$new_failures"
    printf '[KNOWN-FAILURES] %s NEW failure(s) detected above flaky threshold\n' "$new_count" >&2
    printf '[KNOWN-FAILURES] Delta check completed in %ss\n' "$elapsed" >&2
    return 1
  fi
}

# format_agent_context(json_path)
# Reads knownFailures.current.failingTests from quantum.json.
# Returns formatted block for agent prompts, or empty string if no failures.
format_agent_context() {
  local json_path="$1"

  if [[ -z "$json_path" ]]; then
    printf ""
    return 0
  fi

  local native_json_path
  native_json_path=$(_kf_to_native_path "$json_path")

  python -c "
import sys, json

try:
    with open(sys.argv[1]) as f:
        d = json.load(f)
except Exception:
    sys.exit(0)

kf = d.get('knownFailures')
if not kf:
    sys.exit(0)

current = kf.get('current')
if not current:
    sys.exit(0)

tests = current.get('failingTests', [])
if not tests:
    sys.exit(0)

lines = ['Known failing tests (pre-existing, not caused by your story):']
for t in tests:
    name = t.get('name', 'unknown')
    since = t.get('failingSince', '?')
    fix = t.get('expectedFix') or 'unknown'
    lines.append(f'  - {name} (failing since Wave {since}, expected fix: {fix})')
lines.append('If you see ONLY these failures, they are not your fault -- proceed normally.')
lines.append('If you see NEW failures not on this list, they ARE your responsibility -- fix them.')
print(chr(10).join(lines))
" "$native_json_path" 2>/dev/null
}
