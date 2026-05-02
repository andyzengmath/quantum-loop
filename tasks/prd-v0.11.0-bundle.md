# PRD: v0.11.0 — minor (FIRST `--coordinator` dispatch dogfood: N48 stub-coordinator field-ownership test)

**Status:** Approved by operator. First `--coordinator` dispatch on live repo since v0.9.0 N42 wires shipped.
**Date:** 2026-05-02
**Predecessor:** `tasks/prd-v0.10.15-bundle.md`.
**Branch:** `ql/v0.11.0-bundle`.
**Target version:** 0.10.15 → 0.11.0 (minor; established convention: first `--coordinator` dispatch = minor-tier ship).
**Total effort:** ~1.5 hours.

## Section 1: Introduction / Overview

4-story minor closing **N48 stub-coordinator test coverage** (deferred MEDIUM since v0.10.8). Adds end-to-end test that:
1. Authors a stub coordinator deliberately violating field-ownership contract (writes to parent-owned `.stories[].status`).
2. Dispatches via `bash quantum-loop.sh --coordinator` (real binary, not function-presence check).
3. Asserts the v0.10.8 N48 `[FIELD-OWNERSHIP] WARN:` observability fires + parent's signal classification proceeds normally (WARN is observability-only, does NOT abort).

**v0.11.0 entry rationale:** This is the FIRST actual operator-staged `--coordinator` dispatch on live repo. The 15-cycle hardening arc (v0.10.6..v0.10.15) prepared every infrastructure piece for this; the dogfood validates dispatch end-to-end in a contained, lowest-risk scenario before tackling more substantive operator-gated items (N43 architectural).

## Section 2: Goals

- Add `field_ownership_violation` mode to `tests/test_coordinator_e2e.sh` stub-claude.
- Add Test 5 (or similar) that asserts:
  - `[FIELD-OWNERSHIP] WARN: parent-owned fields modified during dispatch` appears in stderr.
  - WAVE_PASSED still classified correctly (WARN is non-blocking).
  - Both stories complete normally despite the contract violation.
- Validate `quantum-loop.sh --coordinator` dispatches the stub via PATH-injection and the parent's snapshot-diff (`PARENT_OWNED_BEFORE` vs `_AFTER` at `lib/iteration-loop.sh:202,291`) detects the violation.
- 25th p014 review.
- Bump 0.10.15 → 0.11.0.
- 44 consecutive LOW G30.

## Section 3: User Stories

### US-001: Add `field_ownership_violation` stub-claude mode

**Acceptance Criteria:**
- [ ] `tests/test_coordinator_e2e.sh` STUB_EOF heredoc gets a new `field_ownership_violation)` case.
- [ ] Behavior: stub mutates `.stories[] | select(.id == "US-A") | .status` from `"in_progress"` → `"passed"` (writing to parent-owned field; this is the contract violation). Also writes review.* fields for both stories normally so WAVE_PASSED outcome is unambiguous.
- [ ] Stub emits `<quantum>WAVE_PASSED</quantum>` to stdout.
- [ ] Stub exits 0 (does NOT abort on the violation; the violation is the parent's job to detect).

### US-002: Add Test 5 — field-ownership violation detected via WARN

**Acceptance Criteria:**
- [ ] New test case (Test 5 or similar) in `tests/test_coordinator_e2e.sh`.
- [ ] Setup: `write_2story_plan` + `run_ql_coord field_ownership_violation`.
- [ ] Assertions:
  - `assert_contains "Test 5: stderr emits FIELD-OWNERSHIP WARN" "[FIELD-OWNERSHIP] WARN" "$OUT"`
  - `assert_contains "Test 5: WARN includes 'before:' line" "before:" "$OUT"`
  - `assert_contains "Test 5: WARN includes 'after:' line" "after:" "$OUT"`
  - `assert_contains "Test 5: WAVE_PASSED still classified" "Wave (wave-1) PASSED" "$OUT"` (verifies observability-only behavior).
  - `assert_eq "Test 5: US-A status=passed" "passed" "$US_A_STATUS"` (parent post-aggregation processed WAVE_PASSED normally).
- [ ] Test counter increments: total goes from 21 → 27 (6 new asserts).
- [ ] `bash -n tests/test_coordinator_e2e.sh` clean.
- [ ] `bash tests/test_coordinator_e2e.sh` rc=0.

### US-003: Multi-perspective post-merge review (25th application)

**Acceptance Criteria:**
- [ ] 3 reviewer agents (architect + code-reviewer + security) invoked in parallel.
- [ ] Architect specifically: validate the dogfood validates the actual N48 path (lib/iteration-loop.sh:290-300) — i.e., the test is not a stub-of-the-stub.
- [ ] No score-≥85 finding deferred.

### US-004: Retrospective + IDEA_REPORT_v50 + version bump 0.10.15 → 0.11.0

**Acceptance Criteria:**
- [ ] `idea-stage/PIPELINE_REPORT_v50.md` documents v0.11.0 (4 stories) + first-`--coordinator`-dispatch outcome + N48 closure.
- [ ] `idea-stage/IDEA_REPORT_v50.md` rolling forward state. v0.11.0 entry rationale + remaining v0.11.x backlog (N43, real-feature dogfood).
- [ ] `CHANGELOG.md [0.11.0]` entry.
- [ ] 4 plugin manifest version fields bumped 0.10.15 → 0.11.0.
- [ ] G30 self-validation (44th consecutive LOW expected; minor-tier delta justified by first-dispatch milestone).

## Section 4: Functional Requirements

- **FR-1:** N48 WARN observability validated end-to-end via real `quantum-loop.sh --coordinator` dispatch.
- **FR-2:** WARN is non-blocking — WAVE_PASSED still classified correctly; story status proceeds to "passed".
- **FR-3:** Plugin version 0.10.15 → 0.11.0 (4 fields).

## Section 5: Non-Goals

- No N43 implementation (defer to v0.11.1+ per operator decision).
- No real-feature dogfood (N48 dogfood is infrastructure-only, not real-feature).
- No production behavior change — only test coverage addition.

## Section 6: Design Notes

**Stub field-ownership violation pattern:**
```bash
field_ownership_violation)
  # v0.11.0 / US-001 (N48 dogfood): violate parent-owned field contract
  # by writing to .stories[].status (parent owns; coordinator must not
  # touch). Parent's PARENT_OWNED_BEFORE/AFTER snapshot-diff at
  # lib/iteration-loop.sh:202,291 should detect the change and emit
  # `[FIELD-OWNERSHIP] WARN:` to stderr. Pure observability — non-blocking.
  jq '.stories |= map(
    if .id == "US-A" then
      .status = "passed"  # VIOLATION: parent owns .status
      | .review.specCompliance = {"status": "passed"}
      | .review.codeQuality = {"status": "passed"}
    elif .id == "US-B" then
      .review.specCompliance = {"status": "passed"}
      | .review.codeQuality = {"status": "passed"}
    else . end
  )' quantum.json > quantum.json.tmp && mv quantum.json.tmp quantum.json
  echo "<quantum>WAVE_PASSED</quantum>"
  ;;
```

**v0.11.0 minor-tier rationale:** per established convention, first `--coordinator` dispatch on live repo = minor-tier ship even when scope is small. Marks entry into operator-gated tier.

## Section 7: Technical Notes

Bash 4.3+. jq required (already a hard dep for the existing test). No new dependencies.

## Section 8: Success Metrics

- All 4 stories first-attempt PASS.
- `tests/test_coordinator_e2e.sh`: 21 → 27 tests (6 new asserts in Test 9).
- 5 baseline test suites + extended e2e suite green.
- 44 consecutive LOW G30.
- N48 stub-coordinator test coverage CLOSED (was deferred MEDIUM since v0.10.8).
