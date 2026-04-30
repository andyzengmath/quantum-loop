#!/usr/bin/env bash
# tests/test_coordinator_e2e.sh
#
# v0.9.0 / US-005 (N42 minor) — real-fire integration tests for the
# coordinator dispatch path. Exercises the actual quantum-loop.sh
# --coordinator binary (not presence-only); asserts at quantum.json
# mutation level using a stub `claude` on PATH that mimics coordinator
# behavior.
#
# Anti-pattern guarded against: presence-only ACs (the v0.8.x retrospective
# burned this lesson home four times — v0.9.0 must not repeat). Each test
# invokes `bash quantum-loop.sh --coordinator ...` and asserts on the
# post-run quantum.json content, not just function presence in source.
#
# 4 test cases per architect 1 + 3 design:
#   1. WAVE_PASSED happy path — both stories status=passed; iteration=1
#   2. WAVE_FAILED partial-pass — derive per-story outcome from review.*
#   3. --coordinator --parallel rejection — exit 1 + ERROR
#   4. COMPLETE path — all stories already passed → COMPLETE signal

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$SCRIPT_DIR/.."
QL_BIN="$REPO_ROOT/quantum-loop.sh"
PASS=0
FAIL=0
TOTAL=0

if ! command -v jq &>/dev/null; then
  echo "SKIP: jq not found"
  exit 1
fi

if [[ ! -f "$QL_BIN" ]]; then
  echo "SKIP: $QL_BIN not found"
  exit 1
fi

assert_eq() {
  local name="$1" expected="$2" actual="$3"
  TOTAL=$((TOTAL + 1))
  if [[ "$expected" == "$actual" ]]; then
    echo "  PASS: $name"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: $name"
    echo "    expected: $expected"
    echo "    actual:   $actual"
    FAIL=$((FAIL + 1))
  fi
}

assert_contains() {
  local name="$1" needle="$2" haystack="$3"
  TOTAL=$((TOTAL + 1))
  if echo "$haystack" | grep -qF -- "$needle"; then
    echo "  PASS: $name"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: $name"
    echo "    expected to contain: $needle"
    echo "    actual: $haystack"
    FAIL=$((FAIL + 1))
  fi
}

echo "=== US-005 v0.9.0 coordinator-dispatch end-to-end tests (N42 minor) ==="

# ─ Stub setup ──────────────────────────────────────────────────────────────
#
# The stub `claude` binary reads its arguments, looks for a control file
# (.test-coord-mode) in the current dir to choose behavior, mutates
# quantum.json (simulating coordinator review writes), and echoes the
# appropriate WAVE_* signal. PATH-prepending the stub dir makes
# spawn_coordinator's `claude --print -p ...` invocation resolve to the
# stub instead of any real claude binary.

TEST_ROOT=$(mktemp -d)
trap 'rm -rf "$TEST_ROOT"' EXIT

STUB_DIR="$TEST_ROOT/stub-bin"
mkdir -p "$STUB_DIR"

cat > "$STUB_DIR/claude" << 'STUB_EOF'
#!/usr/bin/env bash
# Stub `claude` for v0.9.0 US-005 integration tests. Reads control file
# to determine what to emit + which review.* fields to populate.
set -uo pipefail

CTRL=".test-coord-mode"
MODE="passed"
[[ -f "$CTRL" ]] && MODE=$(cat "$CTRL")

# All test fixtures use a 2-story plan with US-A, US-B.
case "$MODE" in
  passed)
    # Coordinator wrote review.* for BOTH stories
    jq '.stories |= map(
      if .id == "US-A" or .id == "US-B" then
        .review.specCompliance = {"status": "passed"}
        | .review.codeQuality = {"status": "passed"}
      else . end
    )' quantum.json > quantum.json.tmp && mv quantum.json.tmp quantum.json
    echo "<quantum>WAVE_PASSED</quantum>"
    ;;
  partial)
    # Coordinator wrote review.* for US-A only (passed); US-B failed mid-wave
    jq '.stories |= map(
      if .id == "US-A" then
        .review.specCompliance = {"status": "passed"}
        | .review.codeQuality = {"status": "passed"}
      else . end
    )' quantum.json > quantum.json.tmp && mv quantum.json.tmp quantum.json
    echo "<quantum>WAVE_FAILED</quantum>"
    ;;
  *)
    echo "<quantum>WAVE_FAILED</quantum>"
    ;;
esac
exit 0
STUB_EOF
chmod +x "$STUB_DIR/claude"

# Stub jq is unaffected; we use the system jq for assertions and the
# stub uses the system jq for its own quantum.json mutations.

write_2story_plan() {
  local target="$1"
  cat > "$target" << 'JSON_EOF'
{
  "prdPath": "tasks/prd.md",
  "branchName": "test-coord-e2e",
  "progress": [],
  "codebasePatterns": [],
  "routing": {},
  "reviews": {},
  "fileConflicts": [],
  "execution": {"materializedContracts": []},
  "stories": [
    {
      "id": "US-A",
      "title": "Story A",
      "status": "pending",
      "priority": 1,
      "dependsOn": [],
      "tasks": [{"id": "T-A-1", "filePaths": ["a.txt"], "status": "pending"}],
      "retries": {"attempts": 0, "maxAttempts": 3, "failureLog": []},
      "review": {"specCompliance": {"status": "pending"}, "codeQuality": {"status": "pending"}}
    },
    {
      "id": "US-B",
      "title": "Story B",
      "status": "pending",
      "priority": 2,
      "dependsOn": [],
      "tasks": [{"id": "T-B-1", "filePaths": ["b.txt"], "status": "pending"}],
      "retries": {"attempts": 0, "maxAttempts": 3, "failureLog": []},
      "review": {"specCompliance": {"status": "pending"}, "codeQuality": {"status": "pending"}}
    }
  ]
}
JSON_EOF
}

write_all_passed_plan() {
  local target="$1"
  cat > "$target" << 'JSON_EOF'
{
  "prdPath": "tasks/prd.md",
  "branchName": "test-coord-e2e",
  "progress": [],
  "codebasePatterns": [],
  "routing": {},
  "reviews": {},
  "fileConflicts": [],
  "execution": {"materializedContracts": []},
  "stories": [
    {
      "id": "US-A",
      "title": "Story A",
      "status": "passed",
      "priority": 1,
      "dependsOn": [],
      "tasks": [],
      "retries": {"attempts": 0, "maxAttempts": 3, "failureLog": []},
      "review": {"specCompliance": {"status": "passed"}, "codeQuality": {"status": "passed"}}
    }
  ]
}
JSON_EOF
}

run_ql_coord() {
  # Args: $1=mode (passed|partial), $@=extra ql args
  local mode="$1"
  shift
  printf '%s' "$mode" > "$TEST_ROOT/work/.test-coord-mode"
  (cd "$TEST_ROOT/work" && PATH="$STUB_DIR:$PATH" bash "$QL_BIN" --coordinator --tool claude --max-iterations 1 --non-interactive "$@" 2>&1) || true
}

# ─ Test 1: WAVE_PASSED happy path ─────────────────────────────────────────
echo ""
echo "Test 1: WAVE_PASSED — both stories status=passed after one wave"
mkdir -p "$TEST_ROOT/work"
write_2story_plan "$TEST_ROOT/work/quantum.json"

OUT=$(run_ql_coord passed)

US_A_STATUS=$(jq -r '.stories[] | select(.id == "US-A") | .status' "$TEST_ROOT/work/quantum.json")
US_B_STATUS=$(jq -r '.stories[] | select(.id == "US-B") | .status' "$TEST_ROOT/work/quantum.json")
assert_eq "Test 1: US-A status=passed" "passed" "$US_A_STATUS"
assert_eq "Test 1: US-B status=passed" "passed" "$US_B_STATUS"
assert_contains "Test 1: stdout mentions Wave PASSED" "Wave (wave-1) PASSED" "$OUT"

rm -rf "$TEST_ROOT/work"

# ─ Test 2: WAVE_FAILED with partial pass ──────────────────────────────────
echo ""
echo "Test 2: WAVE_FAILED partial-pass — US-A passed (review fields), US-B failed"
mkdir -p "$TEST_ROOT/work"
write_2story_plan "$TEST_ROOT/work/quantum.json"

OUT=$(run_ql_coord partial)

US_A_STATUS=$(jq -r '.stories[] | select(.id == "US-A") | .status' "$TEST_ROOT/work/quantum.json")
US_B_STATUS=$(jq -r '.stories[] | select(.id == "US-B") | .status' "$TEST_ROOT/work/quantum.json")
US_B_RETRIES=$(jq -r '.stories[] | select(.id == "US-B") | .retries.attempts' "$TEST_ROOT/work/quantum.json")
assert_eq "Test 2: US-A status=passed (review fields populated)" "passed" "$US_A_STATUS"
assert_eq "Test 2: US-B status=failed (no review fields)" "failed" "$US_B_STATUS"
assert_eq "Test 2: US-B retries.attempts=1" "1" "$US_B_RETRIES"

rm -rf "$TEST_ROOT/work"

# ─ Test 3: --coordinator --parallel rejection ─────────────────────────────
echo ""
echo "Test 3: --coordinator --parallel rejected with ERROR + exit 1"
mkdir -p "$TEST_ROOT/work"
write_2story_plan "$TEST_ROOT/work/quantum.json"

OUT=$(cd "$TEST_ROOT/work" && PATH="$STUB_DIR:$PATH" bash "$QL_BIN" --coordinator --parallel --tool claude --non-interactive 2>&1)
RC=$?

assert_eq "Test 3: exit code 1" "1" "$RC"
assert_contains "Test 3: ERROR message present" "ERROR: --coordinator and --parallel are mutually exclusive" "$OUT"

rm -rf "$TEST_ROOT/work"

# ─ Test 4: COMPLETE path — all stories already passed ─────────────────────
echo ""
echo "Test 4: COMPLETE — all stories already passed → next_wave rc=1 → exit 0"
mkdir -p "$TEST_ROOT/work"
write_all_passed_plan "$TEST_ROOT/work/quantum.json"

# No stub needed; next_wave returns rc=1 BEFORE coordinator dispatch
OUT=$(cd "$TEST_ROOT/work" && PATH="$STUB_DIR:$PATH" bash "$QL_BIN" --coordinator --tool claude --max-iterations 1 --non-interactive 2>&1)
RC=$?

assert_eq "Test 4: exit code 0" "0" "$RC"
assert_contains "Test 4: COMPLETE signal in stdout" "<quantum>COMPLETE</quantum>" "$OUT"

rm -rf "$TEST_ROOT/work"

echo ""
echo "=== Results: $PASS/$TOTAL passed, $FAIL failed ==="
if (( FAIL > 0 )); then
  exit 1
fi
exit 0
