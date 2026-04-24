#!/usr/bin/env bash
# Phase 27 / P3.8 — tracecoder observe/extract/context tests.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$SCRIPT_DIR/.."
PASS=0
FAIL=0
TOTAL=0

assert() {
  local name="$1" expected="$2" actual="$3"
  TOTAL=$((TOTAL + 1))
  if [[ "$expected" == "$actual" ]]; then
    echo "  PASS: $name"; PASS=$((PASS + 1))
  else
    echo "  FAIL: $name (expected [$expected] got [$actual])"
    FAIL=$((FAIL + 1))
  fi
}

# shellcheck disable=SC1091
source "$REPO_ROOT/lib/tracecoder.sh"

echo "=== Phase 27 TraceCoder tests ==="

# Test 1: observe captures exit + stdout+stderr merged + duration
echo ""
echo "Test 1: observe a passing command"
obs=$(observe "echo hello" "greeting")
assert "exit=0" "0" "$(jq -r '.exit' <<< "$obs")"
assert "name=greeting" "greeting" "$(jq -r '.name' <<< "$obs")"
tail=$(jq -r '.tail' <<< "$obs")
case "$tail" in *hello*) echo "  PASS: tail contains hello"; PASS=$((PASS + 1));;
                *) echo "  FAIL: tail=[$tail]"; FAIL=$((FAIL + 1));;
esac
TOTAL=$((TOTAL + 1))

# Test 2: observe captures non-zero exit
echo ""
echo "Test 2: observe a failing command"
obs=$(observe "false" "fails")
assert "exit=1" "1" "$(jq -r '.exit' <<< "$obs")"

# Test 3: observe merges stdout and stderr into tail
echo ""
echo "Test 3: observe merges stderr"
obs=$(observe "echo out; echo err 1>&2" "mixed")
tail=$(jq -r '.tail' <<< "$obs")
case "$tail" in *"out"*"err"*) echo "  PASS: both streams in tail"; PASS=$((PASS + 1));;
                *) echo "  FAIL: tail=[$tail]"; FAIL=$((FAIL + 1));;
esac
TOTAL=$((TOTAL + 1))

# Test 4: extract_error_markers — tsc-style file:line:col: msg
echo ""
echo "Test 4: extract tsc-style markers"
obs_json=$(jq -cn '{tail: "src/app.ts:42:9: error: Cannot find name foo"}')
markers=$(printf '%s' "$obs_json" | extract_error_markers)
count=$(printf '%s' "$markers" | jq 'length')
assert "1 marker parsed" "1" "$count"
assert "file=src/app.ts" "src/app.ts" "$(printf '%s' "$markers" | jq -r '.[0].file')"
assert "line=42" "42" "$(printf '%s' "$markers" | jq -r '.[0].line')"
msg=$(printf '%s' "$markers" | jq -r '.[0].message')
case "$msg" in *"Cannot find name foo"*) echo "  PASS: message captured"; PASS=$((PASS + 1));;
                *) echo "  FAIL: msg=[$msg]"; FAIL=$((FAIL + 1));;
esac
TOTAL=$((TOTAL + 1))

# Test 5: extract — python-style `File "foo.py", line N`
echo ""
echo "Test 5: extract python traceback"
obs_json=$(jq -cn '{tail: "File \"src/main.py\", line 18, in handler"}')
markers=$(printf '%s' "$obs_json" | extract_error_markers)
count=$(printf '%s' "$markers" | jq 'length')
assert "1 marker parsed" "1" "$count"
assert "python file" "src/main.py" "$(printf '%s' "$markers" | jq -r '.[0].file')"
assert "python line" "18" "$(printf '%s' "$markers" | jq -r '.[0].line')"

# Test 6: extract — node stack trace `at fn (path:L:C)`
echo ""
echo "Test 6: extract node stack"
obs_json=$(jq -cn '{tail: "    at Object.handler (dist/server.js:100:5)"}')
markers=$(printf '%s' "$obs_json" | extract_error_markers)
count=$(printf '%s' "$markers" | jq 'length')
assert "node stack parsed" "1" "$count"
assert "node file" "dist/server.js" "$(printf '%s' "$markers" | jq -r '.[0].file')"
assert "node line" "100" "$(printf '%s' "$markers" | jq -r '.[0].line')"

# Test 7: extract — multiple markers + ignores URLs
echo ""
echo "Test 7: multiple markers + URL noise filtering"
tail_text='src/a.ts:10:1: error: bad
src/b.ts:20:2: error: worse
see https://example.com:80/path for more'
obs_json=$(jq -cn --arg t "$tail_text" '{tail: $t}')
markers=$(printf '%s' "$obs_json" | extract_error_markers)
count=$(printf '%s' "$markers" | jq 'length')
assert "2 real markers (URL filtered)" "2" "$count"

# Test 8: extract — empty tail returns []
echo ""
echo "Test 8: empty tail"
obs_json='{"tail":""}'
markers=$(printf '%s' "$obs_json" | extract_error_markers)
assert "empty tail -> []" "[]" "$markers"

# Test 9: build_analysis_context produces structured markdown
echo ""
echo "Test 9: build_analysis_context shape"
obs=$(observe "bash -c 'echo error >&2; exit 1'" "compile")
ctx=$(printf '%s' "$obs" | build_analysis_context)
case "$ctx" in *"## Observation: compile"*) echo "  PASS: header present"; PASS=$((PASS + 1));;
                *) echo "  FAIL: no header"; FAIL=$((FAIL + 1));;
esac
TOTAL=$((TOTAL + 1))
case "$ctx" in *"**exit**: 1"*) echo "  PASS: exit code visible"; PASS=$((PASS + 1));;
                *) echo "  FAIL: no exit"; FAIL=$((FAIL + 1));;
esac
TOTAL=$((TOTAL + 1))
case "$ctx" in *"### Output tail"*) echo "  PASS: tail section present"; PASS=$((PASS + 1));;
                *) echo "  FAIL: no tail section"; FAIL=$((FAIL + 1));;
esac
TOTAL=$((TOTAL + 1))

# Test 10: build_analysis_context includes markers section
echo ""
echo "Test 10: context includes markers"
# Craft an observation with recognizable errors
obs_json=$(jq -cn --arg t "src/x.ts:5:3: error: oops" \
  '{name: "tsc", cmd: "tsc", exit: 1, duration: 1, lines: 1, tail: $t}')
ctx=$(printf '%s' "$obs_json" | build_analysis_context)
case "$ctx" in *"src/x.ts"*"5"*"oops"*) echo "  PASS: marker rendered in context"; PASS=$((PASS + 1));;
                *) echo "  FAIL: marker not rendered"; FAIL=$((FAIL + 1));;
esac
TOTAL=$((TOTAL + 1))

# Test 11: should_repair — pass on failure with markers
echo ""
echo "Test 11: should_repair semantics"
# Failure + markers → repair
obs_json=$(jq -cn '{exit: 1, tail: "src/x.ts:5:3: error: oops"}')
printf '%s' "$obs_json" | should_repair
assert "failure + markers -> 0" "0" "$?"
# Pass → no repair
obs_json=$(jq -cn '{exit: 0, tail: "all passed"}')
printf '%s' "$obs_json" | should_repair
assert "pass -> no repair (1)" "1" "$?"
# Failure but no markers → no repair (opaque, mark failed directly)
obs_json=$(jq -cn '{exit: 1, tail: "segfault"}')
printf '%s' "$obs_json" | should_repair
assert "opaque failure -> no repair (1)" "1" "$?"

# Test 12: observe handles long output
echo ""
echo "Test 12: tail truncates to TRACECODER_TAIL_LINES"
cmd='for i in $(seq 1 200); do echo line_$i; done'
obs=$(TRACECODER_TAIL_LINES=10 observe "$cmd" "noisy")
tail=$(jq -r '.tail' <<< "$obs")
tail_lines=$(printf '%s' "$tail" | awk 'END{print NR}')
assert "tail is 10 lines" "10" "$tail_lines"
# First line of tail should be line_191 (last 10 of 200)
first=$(printf '%s' "$tail" | head -1)
assert "tail starts at line_191" "line_191" "$first"

# Test 13: CLI subcommands
echo ""
echo "Test 13: CLI subcommands"
cli_obs=$(bash "$REPO_ROOT/lib/tracecoder.sh" observe "echo hi" "cli")
cli_exit=$(printf '%s' "$cli_obs" | jq -r '.exit')
assert "CLI observe exit=0" "0" "$cli_exit"
cli_markers=$(printf '{"tail":"src/x.ts:1:1: error: e"}' \
  | bash "$REPO_ROOT/lib/tracecoder.sh" markers | jq 'length')
assert "CLI markers count=1" "1" "$cli_markers"
cli_repair=$(printf '{"exit":1,"tail":"src/x.ts:1:1: error: e"}' \
  | bash "$REPO_ROOT/lib/tracecoder.sh" should-repair ; echo $?)
assert "CLI should-repair exits 0" "0" "$cli_repair"

echo ""
echo "=== Results: $PASS/$TOTAL passed, $FAIL failed ==="
exit $((FAIL > 0 ? 1 : 0))
