# PRD: v0.11.5 — patch-tier (Pre-Path-B: field-ownership escalation policy via opt-in env var)

**Status:** Operator-approved Option C (opt-in escalation; pattern-consistent with v0.11.1 N43 `QL_PARALLEL_POLL`).
**Date:** 2026-05-03
**Predecessor:** `tasks/prd-v0.11.4-bundle.md`.
**Branch:** `ql/v0.11.5-bundle`.
**Target version:** 0.11.4 → 0.11.5 (patch).
**Total effort:** ~1 hour.

## Section 1: Introduction / Overview

4-story patch closing **Pre-Path-B field-ownership escalation policy** (operator-decision item from v0.11.4). Adds `QL_FIELD_OWNERSHIP_STRICT=true` env var that escalates the v0.10.8 N48 WARN to WAVE_FAILED on contract violation. Default OFF preserves backwards compatibility (Tests 9 + 10 unchanged); Path B real-feature dispatch can opt in for hardened data-integrity guarantee.

## Section 2: Goals

- Add `QL_FIELD_OWNERSHIP_STRICT=true` opt-in gate at `lib/iteration-loop.sh:306-310` (the existing N48 WARN site).
- When opt-in active and snapshot diff detected: emit additional `[FIELD-OWNERSHIP] FAIL` log + force `SIGNAL_RESULT="WAVE_FAILED"` + `SIGNAL_CONFIDENCE="exact"`.
- Add Test 11 to `tests/test_coordinator_e2e.sh` validating strict-mode escalation.
- Document `QL_FIELD_OWNERSHIP_STRICT` in CLAUDE.md "Coordinator-related" section.
- 30th p014 review.
- Bump 0.11.4 → 0.11.5.
- 49 consecutive LOW G30.

## Section 3: User Stories

### US-001: `QL_FIELD_OWNERSHIP_STRICT` opt-in escalation

**Acceptance Criteria:**
- [ ] `lib/iteration-loop.sh` lines 306-310 (the existing `if [[ "$PARENT_OWNED_BEFORE" != "$PARENT_OWNED_AFTER" ]]` block): add escalation hook after the 3 existing printf lines:
```bash
if [[ "${QL_FIELD_OWNERSHIP_STRICT:-false}" == "true" ]]; then
  printf "[FIELD-OWNERSHIP] FAIL: strict mode enabled (QL_FIELD_OWNERSHIP_STRICT=true); forcing WAVE_FAILED\n" >&2
  SIGNAL_RESULT="WAVE_FAILED"
  SIGNAL_CONFIDENCE="exact"
fi
```
- [ ] Default behavior unchanged: when env var unset or empty or `false`, WARN-only behavior preserved (Tests 9 + 10 still pass).
- [ ] `bash -n lib/iteration-loop.sh` clean.

### US-002: Test 11 strict-mode escalation

**Acceptance Criteria:**
- [ ] New Test 11 added to `tests/test_coordinator_e2e.sh` after Test 10 (before "=== Results:" line).
- [ ] Reuses existing `field_ownership_violation` stub mode (line 145-161; was added at v0.11.0 for Test 9).
- [ ] Sets `QL_FIELD_OWNERSHIP_STRICT=true` env var in dispatch invocation.
- [ ] **5 sub-asserts:**
  - `assert_contains` "stderr emits [FIELD-OWNERSHIP] WARN" (still fires; same as Test 9).
  - `assert_contains` "stderr emits [FIELD-OWNERSHIP] FAIL with strict-mode message".
  - `assert_contains` "Wave (wave-1) FAILED" (escalation worked).
  - US-A status=failed (parent processed WAVE_FAILED aggregation; no review fields counted).
  - US-B status=failed (same).
- [ ] Test counter increments: 32 → 37 (5 new sub-asserts).
- [ ] `bash -n tests/test_coordinator_e2e.sh` clean.
- [ ] `bash tests/test_coordinator_e2e.sh` rc=0; 37/37.

### US-003: CLAUDE.md `QL_FIELD_OWNERSHIP_STRICT` doc + Multi-perspective review (30th)

**Acceptance Criteria:**
- [ ] CLAUDE.md "Coordinator-related" section: add new bullet documenting `QL_FIELD_OWNERSHIP_STRICT=true`. Include: default OFF, opt-in for Path B real-feature dispatch, escalates v0.10.8 N48 WARN → WAVE_FAILED, wire site `lib/iteration-loop.sh:306-310`, and pattern-consistency note (mirrors v0.11.1 `QL_PARALLEL_POLL` opt-in design).
- [ ] 3 reviewer agents (architect + code-reviewer + security) invoked in parallel.
- [ ] Architect specifically: validate that escalation does NOT cascade into infinite-loop scenarios (e.g., parent's per-story aggregation under WAVE_FAILED branch should still complete normally).
- [ ] No score-≥85 finding deferred.

### US-004: Retrospective + IDEA_REPORT_v55 + version bump 0.11.4 → 0.11.5

**Acceptance Criteria:**
- [ ] `idea-stage/PIPELINE_REPORT_v55.md` documents v0.11.5 (4 stories) + Pre-Path-B closure.
- [ ] `idea-stage/IDEA_REPORT_v55.md` rolling forward state. **Path B unblocked** post-v0.11.5.
- [ ] `CHANGELOG.md [0.11.5]` entry.
- [ ] 4 plugin manifest version fields bumped 0.11.4 → 0.11.5.
- [ ] G30 self-validation (49th consecutive LOW expected).

## Section 4: Functional Requirements

- **FR-1:** `QL_FIELD_OWNERSHIP_STRICT=true` opt-in escalates WARN→WAVE_FAILED.
- **FR-2:** Default OFF preserves backwards compat (Tests 9 + 10 unchanged).
- **FR-3:** Strict mode emits BOTH the WARN log AND the FAIL log (operator-visible escalation evidence).
- **FR-4:** Escalation modifies `SIGNAL_RESULT` + `SIGNAL_CONFIDENCE` BEFORE the parent's per-story aggregation runs (so aggregation processes as WAVE_FAILED).
- **FR-5:** Plugin version 0.11.4 → 0.11.5 (4 fields).

## Section 5: Non-Goals

- No `--coordinator` real-feature dispatch (still v0.11.6+ Path B; this cycle just unblocks it).
- No always-on escalation (Option B was rejected; backwards-compat preserved).
- No retroactive update to v0.10.8 N48 framing (it remains "WARN-only by default; opt-in strict").

## Section 6: Design Notes

**Pattern consistency with v0.11.1 N43 (`QL_PARALLEL_POLL`):**
- v0.11.1 added `QL_PARALLEL_POLL=true` for opt-in parallel-with-dispatch wrap.
- v0.11.5 adds `QL_PARALLEL_POLL` sibling: `QL_FIELD_OWNERSHIP_STRICT=true` for opt-in field-ownership escalation.
- Both: default OFF, gated via `${VAR:-false}` check, documented in CLAUDE.md "Coordinator-related" section.

**Escalation order matters:** the FORCE_WAVE_FAILED must run BEFORE the parent's per-story aggregation (which lives further down at lines ~382/406/438). The wire site at line 306-310 is correct because aggregation happens AFTER that block.

**Test 11 strict-mode setup:**
```bash
# Reuse existing field_ownership_violation stub mode + QL_FIELD_OWNERSHIP_STRICT=true.
OUT=$(cd "$TEST_ROOT/work" && \
  PATH="$STUB_DIR:$PATH" \
  QL_FIELD_OWNERSHIP_STRICT=true \
  bash "$QL_BIN" --coordinator --tool claude --max-iterations 1 --non-interactive 2>&1)
```

## Section 7: Technical Notes

Bash 4.3+. No new dependencies.

## Section 8: Success Metrics

- All 4 stories first-attempt PASS.
- `tests/test_coordinator_e2e.sh`: 32 → 37 tests (+5 sub-asserts in Test 11).
- 8 baseline test suites green: 217 → 222 total.
- 49 consecutive LOW G30.
- **Path B unblocked** (operator can queue real-feature dispatch with `QL_FIELD_OWNERSHIP_STRICT=true` for hardened data-integrity).
