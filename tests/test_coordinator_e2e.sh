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
  story_signal)
    # v0.9.2 / US-002 — coordinator emits STORY_PASSED instead of WAVE_*.
    # Tests the defense-in-depth gate that redirects to WAVE_FAILED branch.
    jq '.stories |= map(
      if .id == "US-A" or .id == "US-B" then
        .review.specCompliance = {"status": "passed"}
        | .review.codeQuality = {"status": "passed"}
      else . end
    )' quantum.json > quantum.json.tmp && mv quantum.json.tmp quantum.json
    echo "<quantum>STORY_PASSED</quantum>"
    ;;
  hung_coordinator)
    # v0.9.3 / US-001 — simulate a hung coordinator subagent. Sleep longer
    # than QL_COORDINATOR_TIMEOUT_S so the parent's timeout wrap fires.
    # The stub does NOT write review.* fields (parent's per-story
    # aggregation defaults stories to failed under WAVE_FAILED branch).
    sleep 30
    echo "<quantum>WAVE_PASSED</quantum>"
    ;;
  head_reset)
    # v0.9.5 / US-002 — simulate implementer escaping worktree and
    # resetting main repo HEAD. Tests parent-side guard_head_advance
    # defense-in-depth. The stub claims WAVE_PASSED but the parent's
    # post-eval guard detects HEAD_BEFORE is no longer ancestor of
    # HEAD_AFTER and forces WAVE_FAILED.
    git reset --hard HEAD~1 2>/dev/null || true
    echo "<quantum>WAVE_PASSED</quantum>"
    ;;
  field_ownership_violation)
    # v0.11.0 / US-001 (N48 dogfood) — violate field-ownership contract
    # by writing to .stories[].status (parent-owned per agents/coordinator.md).
    # Parent's PARENT_OWNED_BEFORE/AFTER snapshot-diff at
    # lib/iteration-loop.sh:202,291 should detect the change and emit
    # `[FIELD-OWNERSHIP] WARN:` to stderr. Pure observability — non-blocking;
    # WAVE_PASSED still classified normally.
    jq '.stories |= map(
      if .id == "US-A" then
        .status = "passed"
        | .review.specCompliance = {"status": "passed"}
        | .review.codeQuality = {"status": "passed"}
      elif .id == "US-B" then
        .review.specCompliance = {"status": "passed"}
        | .review.codeQuality = {"status": "passed"}
      else . end
    )' quantum.json > quantum.json.tmp && mv quantum.json.tmp quantum.json
    echo "<quantum>WAVE_PASSED</quantum>"
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

# ─ Test 5: STORY_PASSED under coord mode redirects to WAVE_FAILED ─────────
# v0.9.2 / US-002 — defense-in-depth: STORY_* signals are unexpected under
# coordinator mode (coordinator should emit WAVE_*). Parent should warn and
# redirect to WAVE_FAILED branch for per-story aggregation.
echo ""
echo "Test 5: STORY_PASSED under coord mode -> WAVE_FAILED redirect (US-002)"
mkdir -p "$TEST_ROOT/work"
write_2story_plan "$TEST_ROOT/work/quantum.json"

OUT=$(run_ql_coord story_signal)

US_A_STATUS=$(jq -r '.stories[] | select(.id == "US-A") | .status' "$TEST_ROOT/work/quantum.json")
US_B_STATUS=$(jq -r '.stories[] | select(.id == "US-B") | .status' "$TEST_ROOT/work/quantum.json")
assert_contains "Test 5: WARNING about unexpected STORY_* signal" "Unexpected STORY_PASSED under coordinator mode" "$OUT"
assert_eq "Test 5: US-A status=passed (review fields drove via WAVE_FAILED branch)" "passed" "$US_A_STATUS"
assert_eq "Test 5: US-B status=passed (review fields drove via WAVE_FAILED branch)" "passed" "$US_B_STATUS"

rm -rf "$TEST_ROOT/work"

# ─ Test 6: hung coordinator -> wallclock timeout fires (US-001) ───────────
# v0.9.3 / US-001 — parent-side wallclock timeout on eval "$COORD_CMD".
# Stub coordinator sleeps 30s; QL_COORDINATOR_TIMEOUT_S=5 fires the
# timeout. Parent should print ERROR + redirect to WAVE_FAILED branch
# (per-story aggregation: stories with no review fields -> failed).
echo ""
echo "Test 6: hung coordinator -> wallclock timeout fires (US-001)"
mkdir -p "$TEST_ROOT/work"
write_2story_plan "$TEST_ROOT/work/quantum.json"
printf 'hung_coordinator' > "$TEST_ROOT/work/.test-coord-mode"

OUT=$(cd "$TEST_ROOT/work" && QL_COORDINATOR_TIMEOUT_S=5 PATH="$STUB_DIR:$PATH" bash "$QL_BIN" --coordinator --tool claude --max-iterations 1 --non-interactive 2>&1)

US_A_STATUS=$(jq -r '.stories[] | select(.id == "US-A") | .status' "$TEST_ROOT/work/quantum.json")
US_B_STATUS=$(jq -r '.stories[] | select(.id == "US-B") | .status' "$TEST_ROOT/work/quantum.json")
assert_contains "Test 6: ERROR about timeout exceeded" "Coordinator subagent exceeded" "$OUT"
assert_eq "Test 6: US-A status=failed (no review fields after timeout)" "failed" "$US_A_STATUS"
assert_eq "Test 6: US-B status=failed (no review fields after timeout)" "failed" "$US_B_STATUS"

rm -rf "$TEST_ROOT/work"

# ─ Test 7: invalid QL_COORDINATOR_TIMEOUT_S triggers WARN + default ──────
# v0.9.3 / US-003 review fix (code-reviewer MEDIUM score 88): validate
# numeric. Set non-numeric env value; assert WARN printed + dispatch runs
# successfully (using default 1800). Stub uses `passed` mode so the wave
# completes normally (no actual timeout fires; just validates the WARN
# path doesn't break dispatch).
echo ""
echo "Test 7: invalid QL_COORDINATOR_TIMEOUT_S -> WARN + default (US-003 review fix)"
mkdir -p "$TEST_ROOT/work"
write_2story_plan "$TEST_ROOT/work/quantum.json"
printf 'passed' > "$TEST_ROOT/work/.test-coord-mode"

OUT=$(cd "$TEST_ROOT/work" && QL_COORDINATOR_TIMEOUT_S=thirty PATH="$STUB_DIR:$PATH" bash "$QL_BIN" --coordinator --tool claude --max-iterations 1 --non-interactive 2>&1)

assert_contains "Test 7: WARN about non-numeric" "QL_COORDINATOR_TIMEOUT_S must be a non-negative integer" "$OUT"
US_A_STATUS=$(jq -r '.stories[] | select(.id == "US-A") | .status' "$TEST_ROOT/work/quantum.json")
assert_eq "Test 7: dispatch still completed (US-A passed)" "passed" "$US_A_STATUS"

rm -rf "$TEST_ROOT/work"

# ─ Test 8: parent-side HEAD guard catches reset (US-002) ─────────────────
# v0.9.5 / US-002 — defense-in-depth: even if coordinator skips the
# LLM-side guard_head_advance instruction (or escapes worktree), parent
# captures HEAD_BEFORE pre-dispatch and verifies post-eval that HEAD
# advanced via ancestry. Stub does `git reset --hard HEAD~1` then echoes
# WAVE_PASSED; parent should detect + force WAVE_FAILED.
echo ""
echo "Test 8: parent-side HEAD guard catches reset (US-002)"
mkdir -p "$TEST_ROOT/work"
write_2story_plan "$TEST_ROOT/work/quantum.json"
printf 'head_reset' > "$TEST_ROOT/work/.test-coord-mode"
# Initialize git repo with 2 commits so reset --hard HEAD~1 has a target
( cd "$TEST_ROOT/work" && \
  git init -q && \
  git config user.email t@t.test && git config user.name testuser && \
  git add quantum.json .test-coord-mode 2>/dev/null && \
  git commit -q -m "init" && \
  echo "second" > marker.txt && git add marker.txt && \
  git commit -q -m "second" )

OUT=$(cd "$TEST_ROOT/work" && PATH="$STUB_DIR:$PATH" bash "$QL_BIN" --coordinator --tool claude --max-iterations 1 --non-interactive 2>&1)

US_A_STATUS=$(jq -r '.stories[] | select(.id == "US-A") | .status' "$TEST_ROOT/work/quantum.json")
US_B_STATUS=$(jq -r '.stories[] | select(.id == "US-B") | .status' "$TEST_ROOT/work/quantum.json")
assert_contains "Test 8: ERROR about parent-side HEAD guard" "Parent-side HEAD guard fired" "$OUT"
assert_eq "Test 8: US-A status=failed (no review fields after guard)" "failed" "$US_A_STATUS"
assert_eq "Test 8: US-B status=failed (no review fields after guard)" "failed" "$US_B_STATUS"

rm -rf "$TEST_ROOT/work"

# ─ Test 9: N48 field-ownership WARN observability (v0.11.0 dogfood) ──────
# v0.11.0 / US-002: validates v0.10.8 N48 PARENT_OWNED_BEFORE/AFTER
# snapshot-diff at lib/iteration-loop.sh:202,291. Stub coordinator
# deliberately writes to .stories[].status (parent-owned per
# agents/coordinator.md); parent's diff should detect + emit WARN to
# stderr. WARN is non-blocking — WAVE_PASSED still classified normally.
echo ""
echo "Test 9: N48 field-ownership WARN observability (v0.11.0 dogfood)"
mkdir -p "$TEST_ROOT/work"
write_2story_plan "$TEST_ROOT/work/quantum.json"
printf 'field_ownership_violation' > "$TEST_ROOT/work/.test-coord-mode"
# Initialize git repo (coordinator dispatch captures HEAD_BEFORE_COORD).
( cd "$TEST_ROOT/work" && \
  git init -q && \
  git config user.email t@t.test && git config user.name testuser && \
  git add quantum.json .test-coord-mode 2>/dev/null && \
  git commit -q -m "init" )

OUT=$(cd "$TEST_ROOT/work" && PATH="$STUB_DIR:$PATH" bash "$QL_BIN" --coordinator --tool claude --max-iterations 1 --non-interactive 2>&1)

US_A_STATUS=$(jq -r '.stories[] | select(.id == "US-A") | .status' "$TEST_ROOT/work/quantum.json")
US_B_STATUS=$(jq -r '.stories[] | select(.id == "US-B") | .status' "$TEST_ROOT/work/quantum.json")

assert_contains "Test 9: stderr emits FIELD-OWNERSHIP WARN" "[FIELD-OWNERSHIP] WARN" "$OUT"
assert_contains "Test 9: WARN includes 'before:' line" "before:" "$OUT"
assert_contains "Test 9: WARN includes 'after:' line" "after:" "$OUT"
assert_contains "Test 9: WAVE_PASSED still classified normally" "Wave (wave-1) PASSED" "$OUT"
assert_eq "Test 9: US-A status=passed (parent processed WAVE_PASSED)" "passed" "$US_A_STATUS"
assert_eq "Test 9: US-B status=passed (parent processed WAVE_PASSED)" "passed" "$US_B_STATUS"

rm -rf "$TEST_ROOT/work"

# ─ Test 10: N48 field-ownership negative-path (v0.11.2 / US-001) ──────────
# v0.11.2: pair with Test 9 to validate N48 detection symmetry. Test 9
# proves WARN fires on contract violation; Test 10 proves WARN does NOT
# fire on contract compliance. Together they confirm no false-positive
# WARN emission. Reuses existing 'passed' stub mode (line 97-106) which
# is already field-ownership-compliant by design (writes only review.*
# fields; never touches .stories[].status).
echo ""
echo "Test 10: N48 field-ownership compliance — WARN does NOT fire (v0.11.2 negative-path)"
mkdir -p "$TEST_ROOT/work"
write_2story_plan "$TEST_ROOT/work/quantum.json"
( cd "$TEST_ROOT/work" && \
  git init -q && \
  git config user.email t@t.test && git config user.name testuser && \
  git add quantum.json 2>/dev/null && \
  git commit -q -m "init" )

OUT=$(run_ql_coord passed)

US_A_STATUS=$(jq -r '.stories[] | select(.id == "US-A") | .status' "$TEST_ROOT/work/quantum.json")
US_B_STATUS=$(jq -r '.stories[] | select(.id == "US-B") | .status' "$TEST_ROOT/work/quantum.json")

# Positive control: dispatch must complete normally.
assert_contains "Test 10: stdout mentions Wave PASSED (positive control)" "Wave (wave-1) PASSED" "$OUT"

# Negative — WARN absence: validate N48 detection symmetry.
TOTAL=$((TOTAL + 1))
if echo "$OUT" | grep -qF "[FIELD-OWNERSHIP] WARN"; then
  echo "  FAIL: Test 10: FIELD-OWNERSHIP WARN fired on compliant coordinator (false positive)"
  FAIL=$((FAIL + 1))
else
  echo "  PASS: Test 10: FIELD-OWNERSHIP WARN absent (no false positive)"
  PASS=$((PASS + 1))
fi

# Negative — before:/after: absence (side-effect of WARN absence).
TOTAL=$((TOTAL + 1))
if echo "$OUT" | grep -qE '^\s*before:'; then
  echo "  FAIL: Test 10: before: line appeared without WARN (inconsistent state)"
  FAIL=$((FAIL + 1))
else
  echo "  PASS: Test 10: before:/after: lines absent (consistent with WARN absence)"
  PASS=$((PASS + 1))
fi

# Status correctness: parent processed WAVE_PASSED normally.
assert_eq "Test 10: US-A status=passed (parent processed WAVE_PASSED)" "passed" "$US_A_STATUS"
assert_eq "Test 10: US-B status=passed (parent processed WAVE_PASSED)" "passed" "$US_B_STATUS"

rm -rf "$TEST_ROOT/work"

# ─ Test 11: QL_FIELD_OWNERSHIP_STRICT escalation (v0.11.5 / US-002) ──────
# v0.11.5: validates Pre-Path-B opt-in escalation. Same setup as Test 9
# (stub coordinator violates field-ownership contract by mutating
# .stories[].status), but with QL_FIELD_OWNERSHIP_STRICT=true env var.
# Expected: v0.10.8 WARN still fires (observability preserved), THEN
# v0.11.5 escalation forces WAVE_FAILED + per-story aggregation marks
# both stories as failed (review.* fields ignored under WAVE_FAILED branch).
echo ""
echo "Test 11: QL_FIELD_OWNERSHIP_STRICT=true escalates WARN to WAVE_FAILED (v0.11.5 strict mode)"
mkdir -p "$TEST_ROOT/work"
write_2story_plan "$TEST_ROOT/work/quantum.json"
printf 'field_ownership_violation' > "$TEST_ROOT/work/.test-coord-mode"
( cd "$TEST_ROOT/work" && \
  git init -q && \
  git config user.email t@t.test && git config user.name testuser && \
  git add quantum.json .test-coord-mode 2>/dev/null && \
  git commit -q -m "init" )

# Inline dispatch (run_ql_coord helper doesn't take env vars).
OUT=$(cd "$TEST_ROOT/work" && \
  PATH="$STUB_DIR:$PATH" QL_FIELD_OWNERSHIP_STRICT=true \
  bash "$QL_BIN" --coordinator --tool claude --max-iterations 1 --non-interactive 2>&1)

# Note on v0.11.5 strict-mode semantics: the escalation forces WAVE_FAILED
# at the wave-signal level. Per-story aggregation under WAVE_FAILED branch
# still runs and DERIVES status from review.* fields (cf. Test 2 partial-
# pass semantics). The stub here populates review.* for both stories, so
# both aggregate to status=passed under WAVE_FAILED — the strict-mode
# escalation evidence is the wave-level FAIL, NOT per-story status.
# A violating coordinator that produced trustworthy review.* writes still
# has those reviews preserved; strict mode flags the wave as untrusted.

# WARN still fires (observability preserved; same as Test 9).
assert_contains "Test 11: stderr emits FIELD-OWNERSHIP WARN (observability preserved)" "[FIELD-OWNERSHIP] WARN" "$OUT"
# FAIL escalation log fires (strict mode evidence).
assert_contains "Test 11: stderr emits FIELD-OWNERSHIP FAIL with strict-mode message" "[FIELD-OWNERSHIP] FAIL: strict mode enabled" "$OUT"
# Wave classified as FAILED (escalation worked at wave-signal level).
assert_contains "Test 11: Wave FAILED (escalation forced WAVE_FAILED)" "Wave (wave-1) FAILED" "$OUT"

rm -rf "$TEST_ROOT/work"

echo ""
echo "=== Results: $PASS/$TOTAL passed, $FAIL failed ==="
if (( FAIL > 0 )); then
  exit 1
fi
exit 0
