# PRD: v0.11.3 — patch-tier (copilot-hooks::post_output test coverage)

**Status:** Operator-approved. Continues v0.11.x autonomous progression after v0.11.2 D-medium ship.
**Date:** 2026-05-03
**Predecessor:** `tasks/prd-v0.11.2-bundle.md`.
**Branch:** `ql/v0.11.3-bundle`.
**Target version:** 0.11.2 → 0.11.3 (patch).
**Total effort:** ~1 hour.

## Section 1: Introduction / Overview

3-story patch closing **`runners/hooks/copilot-hooks.sh::post_output` coverage gap** — flagged MEDIUM by the post-v0.11.1 comprehensive-review critic. This is the largest real coverage gap surfaced by the review.

**Note on scope reduction:** the critic also flagged `build_coordinator_prompt` content assertions as a MEDIUM gap, but pre-PRD verification confirmed `tests/test_coordinator_dispatch.sh:99-106` (Test 7) already validates wave-id + story-ids embedding via grep. That finding was a false positive (audit miss); documented in IDEA_REPORT_v53 retro for future-audit calibration. v0.11.3 reduces to 3 stories instead of 4.

## Section 2: Goals

- Cover `runners/hooks/copilot-hooks.sh::post_output` with direct unit tests (rate-limit pattern detection + Retry-After extraction including v0.10.13 folded-header fallback).
- 28th p014 review.
- Bump 0.11.2 → 0.11.3.
- 47 consecutive LOW G30.

## Section 3: User Stories

### US-001: `copilot-hooks::post_output` test coverage

**Acceptance Criteria:**
- [ ] New `tests/test_copilot_hooks.sh` file (does not require copilot CLI; pure string-parsing tests).
- [ ] Sources `runners/hooks/copilot-hooks.sh` and invokes `post_output "$mock_output"` with hand-crafted inputs.
- [ ] **Tests for rate-limit detection (5 patterns):**
  - Test 1: `rate-limit` substring → `[RATE-LIMIT] copilot rate-limit detected:` emitted.
  - Test 2: `429` (word-boundary) → emitted.
  - Test 3: `Retry-After` header keyword → emitted.
  - Test 4: `quota-exceeded` → emitted.
  - Test 5: `too many requests` (case-insensitive) → emitted.
- [ ] **Tests for Retry-After extraction:**
  - Test 6: single-line `Retry-After: 30` → `[RATE-LIMIT] copilot suggests Retry-After: 30s` emitted.
  - Test 7: HTTP/1.1 `429 Retry-After: 60` → 60 extracted (not 1 from HTTP/1.1; not 429; v0.10.7 anchor-sed fix).
  - Test 8: folded-header form `Retry-After:\n   45` → 45 extracted (v0.10.13 awk fallback).
  - Test 9: digit-mix continuation `Retry-After:\n   30 something 99` → 30 extracted (not 3099; v0.10.13 match/substr fix).
- [ ] **Tests for negative cases:**
  - Test 10: benign output without rate-limit keywords → NO `[RATE-LIMIT]` emission.
  - Test 11: idempotency — multiple rate-limit lines in same output → emitted once (head -1 dedup).
- [ ] **Total: 11 sub-asserts (10 PASS/FAIL test cases + 1 idempotency check).**
- [ ] `bash -n tests/test_copilot_hooks.sh` clean.
- [ ] `bash tests/test_copilot_hooks.sh` rc=0; 11/11.

### US-002: Multi-perspective post-merge review (28th application)

**Acceptance Criteria:**
- [ ] 3 reviewer agents (architect + code-reviewer + security) invoked in parallel.
- [ ] Architect specifically: validate the test inputs match real copilot CLI output formats (not just synthetic patterns).
- [ ] No score-≥85 finding deferred.

### US-003: Retrospective + IDEA_REPORT_v53 + version bump 0.11.2 → 0.11.3

**Acceptance Criteria:**
- [ ] `idea-stage/PIPELINE_REPORT_v53.md` documents v0.11.3 (3 stories) + critic false-positive filter (build_coordinator_prompt already covered).
- [ ] `idea-stage/IDEA_REPORT_v53.md` rolling forward state. Updated v0.11.4+ candidates: only `emit_terminal_signal` direct test + Path E test split + Path B real-feature dispatch + pre-Path-B field-ownership policy.
- [ ] `CHANGELOG.md [0.11.3]` entry.
- [ ] 4 plugin manifest version fields bumped 0.11.2 → 0.11.3.
- [ ] G30 self-validation (47th consecutive LOW expected).

## Section 4: Functional Requirements

- **FR-1:** `post_output` test file does NOT require copilot CLI installed (pure string parsing).
- **FR-2:** Tests cover all rate-limit patterns documented in `copilot-hooks.sh:20` (case-insensitive: `rate.?limit`, `\b429\b`, `retry-after`, `quota.?exceeded`, `too.many.requests`).
- **FR-3:** Tests cover both single-line and folded-header Retry-After forms (v0.10.7 + v0.10.13 fixes).
- **FR-4:** Plugin version 0.11.2 → 0.11.3 (4 fields).

## Section 5: Non-Goals

- No build_coordinator_prompt assertions (already covered; critic false positive).
- No emit_terminal_signal coverage (deferred; needs fixture-driven test cycle).
- No real copilot CLI integration test (out of scope; covered by `tests/test_copilot_dispatch.sh` which is skip-aware).
- No Path E test file split.
- No pre-Path-B field-ownership policy decision.

## Section 6: Design Notes

**Test framework conformance:** new `tests/test_copilot_hooks.sh` follows the established pattern in `tests/test_orchestrator_liveness.sh`:
- `set -uo pipefail` + assert helpers.
- `source` the hooks file directly (no PATH injection).
- Capture `post_output` stderr emissions via `2>&1`.
- TOTAL/PASS/FAIL counters.

**Test inputs:** real-world copilot CLI rate-limit emissions vary; tests use representative samples documented in `runners/hooks/copilot-hooks.sh:20` regex patterns. Tests do NOT require a live CLI.

## Section 7: Technical Notes

Bash 4.3+. No new dependencies.

## Section 8: Success Metrics

- All 3 stories first-attempt PASS.
- New test suite: `tests/test_copilot_hooks.sh` 11/11.
- 7 baseline test suites green: 15+32+44+39+18+46+11 = 205.
- 47 consecutive LOW G30.
- copilot-hooks::post_output coverage gap CLOSED.
