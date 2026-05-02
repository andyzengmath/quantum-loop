# PRD: v0.10.6 — patch-tier (wave-cycle-1 housekeeping; --coordinator deferred)

**Status:** Approved (per `.omc/plans/2026-05-02-v0.11.0-wave-dogfood-driven-low-sweep.md` cycle-1 content + tier re-framing)
**Date:** 2026-05-02
**Design doc:** `docs/plans/2026-05-02-v0.10.6-bundle-design.md`
**Source:** Wave-plan cycle-1 work content; v0.11.0 minor framing deferred to first actual --coordinator dispatch.
**Branch:** `ql/v0.10.6-bundle`
**Target version:** 0.10.6 (patch from 0.10.5)
**Total effort:** ~2 hours

## Section 1: Introduction / Overview

4-story patch shipping wave-plan cycle-1 work content (N50 + Trap RETURN hardening) as direct-commits. The wave plan's `--coordinator` dispatch validation is deferred to a future operator-run session; the LOW work itself ships now to keep the wave's backlog-clearing aim progressing.

## Section 2: Goals

- Close N50 (Iteration vs Wave counter naming clarity).
- Close Trap RETURN re-entry hardening (security LOW from v0.10.0 review).
- 15th application of multi-perspective post-merge review.
- Bump 0.10.5 → 0.10.6 (4 manifest fields).
- 34 consecutive LOW G30.
- Document wave-plan progress + v0.11.0 reservation in retrospective.

## Section 3: User Stories

### US-001: N50 — Iteration vs Wave counter naming clarity

**Acceptance Criteria:**
- [ ] `lib/parallel-mode.sh` outer-loop `WAVE` counter renamed to `WAVE_COUNTER` to disambiguate from `ITERATION` outer counter and from `--coordinator` mode's `WAVE_ID` (which has different semantics).
- [ ] All references updated in same file: `WAVE=0` initialization, `WAVE=$((WAVE + 1))` increments, `printf [SPAWNED] ... wave %d` interpolations, `--argjson wave ...` jq bindings (note: per v0.10.4 the unused `--argjson wave` was removed; verify no re-introduction).
- [ ] `bash -n lib/parallel-mode.sh` clean.
- [ ] `tests/test_orchestrator_liveness.sh` 34/34 (the suite that exercises parallel-mode helpers).
- [ ] Negative grep: post-rename `grep -wE 'WAVE=|WAVE\+\+|=\$WAVE' lib/parallel-mode.sh` returns 0 hits (only `WAVE_COUNTER` or `WAVE_ID` should remain).
- [ ] Comment added to `lib/parallel-mode.sh` documenting the disambiguation rationale.

### US-002: Trap RETURN re-entry hardening

**Acceptance Criteria:**
- [ ] `lib/json-atomic.sh` docstrings for both `json_atomic_update` and `json_atomic_update_args` extended to explicitly document: (a) cleanup happens via `trap RETURN`; (b) callers MUST NOT wrap these helpers in functions with their own `trap ... RETURN` (would silently replace inner trap; tmp file leak); (c) if a caller needs nesting, use explicit `rm -f` cleanup instead of relying on the helper's trap.
- [ ] `tests/test_json_atomic.sh` adds 1 new test case (Test 15): assert that calling `json_atomic_update` from inside another function does NOT leak the tmp file (current pattern correctness verification).
- [ ] `bash -n lib/json-atomic.sh` clean.
- [ ] `bash tests/test_json_atomic.sh` rc=0 with all new tests passing.
- [ ] Test count: 32/32 → 33/33 (+1 nesting-safety assertion).

### US-003: Multi-perspective post-merge review (15th application)

**Acceptance Criteria:**
- [ ] 3 reviewer agents (architect + code-reviewer + security) invoked in parallel.
- [ ] No score-≥85 finding deferred.

### US-004: Retrospective + IDEA_REPORT_v40 + version bump 0.10.5 → 0.10.6

**Acceptance Criteria:**
- [ ] `idea-stage/PIPELINE_REPORT_v40.md` documents v0.10.6 (4 stories) + wave-plan cycle-1 content shipped + v0.11.0 reservation rationale.
- [ ] `idea-stage/IDEA_REPORT_v40.md` rolling forward state. Wave plan referenced; remaining wave cycles re-numbered (v0.10.7+ patches; v0.11.0 minor reserved for first --coordinator dispatch).
- [ ] `CHANGELOG.md [0.10.6]` entry.
- [ ] 4 plugin manifest version fields bumped 0.10.5 → 0.10.6.
- [ ] G30 self-validation captured (34th consecutive LOW expected).

## Section 4: Functional Requirements

- **FR-1:** US-001 rename is mechanical and behavior-preserving.
- **FR-2:** US-002 is documentation + 1 verification test; no production code change.
- **FR-3:** Plugin version 0.10.5 → 0.10.6 (4 fields).

## Section 5: Non-Goals

- No `--coordinator` dispatch (deferred to v0.11.0 when operator runs it).
- No new architectural work.

## Section 6: Design Notes

See `docs/plans/2026-05-02-v0.10.6-bundle-design.md` and `.omc/plans/2026-05-02-v0.11.0-wave-dogfood-driven-low-sweep.md`.

## Section 7: Technical Notes

Bash 4.3+. Mechanical rename + docstring edit + 1 test addition.

## Section 8: Success Metrics

- All 4 stories first-attempt PASS.
- 9 test suites green; test_json_atomic 32 → 33.
- 34 consecutive LOW G30.

## Section 9: Open Questions

- **Q1:** Tier — patch (v0.10.6)? **Decision:** Yes; wave plan's v0.11.0 minor framing requires actual `--coordinator` dispatch which this autonomous cycle cannot perform.
- **Q2:** Wait for operator vs ship now? **Decision:** Ship now; LOW work is real; v0.11.0 reservation preserved cleanly.
