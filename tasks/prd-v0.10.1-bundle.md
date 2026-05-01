# PRD: v0.10.1 — patch-tier (audit-driven doc-cleanup + 1 code fix)

**Status:** Approved
**Date:** 2026-05-01
**Design doc:** `docs/plans/2026-05-01-v0.10.1-bundle-design.md`
**Source:** Operator-initiated 3-agent doc-vs-code audit post-v0.10.0 ship.
**Branch:** `ql/v0.10.1-bundle`
**Target version:** 0.10.1 (patch from 0.10.0)
**Total effort:** ~1 hour

## Section 1: Introduction / Overview

3-story patch closing 6 gaps surfaced by the post-v0.10.0 doc-vs-code audit. 1 code fix (raw MAX_ITERATIONS printf migration in `lib/iteration-loop.sh`) + 5 doc fixes (ADR-001 line refs; IDEA_REPORT_v30 daemon annotation; IDEA_REPORT_v34 amendments).

## Section 2: Goals

- Close the architect-flagged MEDIUM gap: `lib/iteration-loop.sh:456-457` raw MAX_ITERATIONS printf migrated to `emit_terminal_signal` (matches the v0.10.0 IDEA_REPORT_v34 "all migrated" claim).
- Close the doc-specialist HIGH gap: ADR-001 line-refs updated to current decomposed state.
- Close the architect LOW gaps: IDEA_REPORT_v30 daemon annotation; IDEA_REPORT_v34 silent-dropped item re-acknowledgment + STORY_ID validation re-tracking + bundle-count clarification.
- 10th application of multi-perspective post-merge review pattern.
- Bump 0.10.0 → 0.10.1 (4 manifest fields).
- 29 consecutive LOW G30 self-validation.

## Section 3: User Stories

### US-001: Audit-driven fixes (1 code + 5 doc edits)

**Acceptance Criteria:**

T-001-1 (code fix):
- [ ] `lib/iteration-loop.sh:456-457` `printf "  <quantum>MAX_ITERATIONS</quantum>\n"` + `printf "  Reached maximum of %d iterations.\n" "$MAX_ITERATIONS"` replaced with single `emit_terminal_signal "MAX_ITERATIONS" "$(printf 'Reached maximum of %d iterations.' "$MAX_ITERATIONS")"` call.
- [ ] After: `grep -E 'printf .*<quantum>MAX_ITERATIONS</quantum>' lib/iteration-loop.sh` returns 0 hits.
- [ ] `bash -n lib/iteration-loop.sh` clean.
- [ ] `tests/test_signal_parsing.sh` 15/15.
- [ ] `tests/test_coordinator_e2e.sh` 21/21.

T-001-2 (ADR-001 line refs):
- [ ] `references/adr-001-outer-loop-architecture.md:10` reference `quantum-loop.sh:~1447` updated to reference `lib/iteration-loop.sh::run_iteration_loop()` (the post-decomposition canonical location).
- [ ] `references/adr-001-outer-loop-architecture.md:85` reference `quantum-loop.sh:~1447-1838` updated similarly.
- [ ] After: `! grep -q 'quantum-loop\.sh:~144' references/adr-001-outer-loop-architecture.md`.

T-001-3 (IDEA_REPORT_v30 annotation):
- [ ] `idea-stage/IDEA_REPORT_v30.md:52` daemon-style entry annotated with `[Superseded by ADR-001 — see references/adr-001-outer-loop-architecture.md and IDEA_REPORT_v31]`.
- [ ] No removal of original content (additive annotation only).

T-001-4 (IDEA_REPORT_v34 amendments):
- [ ] "Closed in v0.10.0" table MAX_ITERATIONS migration claim updated to reflect that v0.10.1 closed the iteration-loop.sh side (parallel-mode.sh was already migrated in v0.10.0).
- [ ] "Still open" section re-acknowledges N38, N41, N44, N45, copilot-rate-limit-observability (silently dropped from carried-forward between v30 and v31; re-added as sub-threshold LOW with rationale note).
- [ ] "Still open" section adds STORY_ID validation deferral from `idea-stage/v0.9.x-arc-audit-2026-04-30.md:73` as accepted-risk-tracked LOW (audit itself downgraded: "data is jq-injection-safe").
- [ ] Bundle-size sequence framing clarified: "v0.10.0 = 5 shipped stories (US-003 deferred to v0.10.1)" instead of "v0.10.0 = 6 stories (US-003 deferred but counted)".

### US-002: Multi-perspective post-merge review (10th application)

**Acceptance Criteria:**
- [ ] 3 reviewer agents invoked in parallel: architect + code-reviewer + security.
- [ ] No score-≥85 finding deferred.
- [ ] Findings logged in retrospective.

### US-003: Retrospective + IDEA_REPORT_v35 + version bump 0.10.0 → 0.10.1

**Acceptance Criteria:**
- [ ] `idea-stage/PIPELINE_REPORT_v35.md` documents v0.10.1 (3 stories incl. audit-finding closure).
- [ ] `idea-stage/IDEA_REPORT_v35.md` rolling forward state. Re-affirms v0.10.0's "architectural arc CLOSED" claim with audit-finding closure footnote.
- [ ] `CHANGELOG.md [0.10.1]` entry.
- [ ] 4 plugin manifest version fields bumped 0.10.0 → 0.10.1.
- [ ] G30 self-validation captured (29th consecutive LOW expected).

## Section 4: Functional Requirements

- **FR-1:** Code fix is behavior-preserving (`emit_terminal_signal` is a pure formatter; same output text).
- **FR-2:** Doc fixes are accuracy-improving only (no semantic content changes; line-ref updates + annotations).
- **FR-3:** US-002 review surfaces no blocking findings.
- **FR-4:** Plugin version 0.10.0 → 0.10.1 (4 fields).

## Section 5: Non-Goals

- No real-feature dogfood (still deferred to v0.11.0+).
- No dead `--argjson wave` cleanup (deferred per v0.10.0 US-005).
- No new architectural work.
- No N40, N43, N46, N47-N50.
- No PowerShell parity.

## Section 6: Design Notes

See `docs/plans/2026-05-01-v0.10.1-bundle-design.md` for full audit-finding analysis.

## Section 7: Technical Notes

Bash 4.3+. Mechanical fixes; no new helpers, no schema changes.

## Section 8: Success Metrics

- All 3 stories first-attempt PASS.
- 0 raw `printf <quantum>MAX_ITERATIONS</quantum>` in `lib/iteration-loop.sh`.
- 0 stale `quantum-loop.sh:~144` refs in `references/adr-001-outer-loop-architecture.md`.
- IDEA_REPORT_v34 amendments verified by re-grep (silent-dropped items present in "Still open").
- 9 test suites green.
- 29 consecutive LOW G30 self-validation.

## Section 9: Open Questions

- **Q1:** Tier — patch (0.10.1) or just unreleased commit? **Decision:** patch (0.10.1) for consistency + the operationally-misleading HIGH (ADR-001 stale ref) deserves release marker.
- **Q2:** Re-add silently-dropped LOWs vs document as accepted-risk-dropped? **Decision:** re-add with rationale note (honest tracking).
- **Q3:** Retroactively annotate v31/v32/v33 with daemon-supersession? **Decision:** No (v30 alone suffices; v31+ already cite ADR-001).
