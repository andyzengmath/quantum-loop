# PRD: v0.10.7 — patch-tier (wave-cycle-2: copilot-rate-limit + N49 closure verification)

**Status:** Approved per `.omc/plans/2026-05-02-v0.11.0-wave-dogfood-driven-low-sweep.md` cycle-2.
**Date:** 2026-05-02
**Predecessor:** `tasks/prd-v0.10.6-bundle.md`.
**Branch:** `ql/v0.10.7-bundle`.
**Target version:** 0.10.6 → 0.10.7 (patch).
**Total effort:** ~1.5 hours.

## Section 1: Introduction / Overview

4-story patch shipping wave-plan cycle-2. Closes copilot-rate-limit-observability (real new feature) + N49 closure verification (likely already implicitly closed by v0.9.0 N42 wires).

## Section 2: Goals

- Add copilot-rate-limit-observability: detect rate-limit error patterns from copilot CLI runner stderr; emit visible `[RATE-LIMIT]` log lines.
- Verify N49 status: confirm whether the 4 WAVE-branch `json_atomic_update_args` calls in `lib/iteration-loop.sh` already implement the "single-jq bulk-update" optimization OR identify remaining work.
- 16th p014 review.
- Bump 0.10.6 → 0.10.7.
- 35 consecutive LOW G30.

## Section 3: User Stories

### US-001: copilot-rate-limit-observability

**Acceptance Criteria:**
- [ ] `runners/hooks/copilot-hooks.sh` (or equivalent) gains a `post_output` hook implementation that pattern-matches rate-limit signals in copilot CLI output. Patterns: case-insensitive `rate.?limit`, `429`, `Retry-After`, `quota.?exceeded`, `too many requests`.
- [ ] On match, emit `[RATE-LIMIT] copilot rate-limit detected: <captured-line>` to stderr.
- [ ] If `Retry-After: <N>` header is parseable, include the suggested wait in the log line.
- [ ] Hook is idempotent: doesn't double-emit if multiple rate-limit lines in same output.
- [ ] No new test required (post_output hook tested via test_runner_dispatch.sh stub mode).
- [ ] `bash -n runners/hooks/copilot-hooks.sh` clean.

### US-002: N49 closure verification

**Acceptance Criteria:**
- [ ] Audit `lib/iteration-loop.sh:150, 382, 406, 438` (4 WAVE-branch `json_atomic_update_args` sites) for "single-jq bulk-update" pattern. If each already uses `.stories |= map(...)` to update all wave stories in 1 jq invocation, N49 is implicitly closed.
- [ ] Document closure rationale in `idea-stage/IDEA_REPORT_v41.md`: when was the implicit closure (likely v0.9.0 N42), why no follow-up needed.
- [ ] If closure NOT verified (e.g., per-story jq calls still exist somewhere), extend AC to add the consolidation refactor.

### US-003: Multi-perspective post-merge review (16th application)

**Acceptance Criteria:**
- [ ] 3 reviewer agents (architect + code-reviewer + security) invoked in parallel.
- [ ] No score-≥85 finding deferred.

### US-004: Retrospective + IDEA_REPORT_v41 + version bump 0.10.6 → 0.10.7

**Acceptance Criteria:**
- [ ] `idea-stage/PIPELINE_REPORT_v41.md` documents v0.10.7 (4 stories).
- [ ] `idea-stage/IDEA_REPORT_v41.md` rolling forward state. N49 closure documented.
- [ ] `CHANGELOG.md [0.10.7]` entry.
- [ ] 4 plugin manifest version fields bumped 0.10.6 → 0.10.7.
- [ ] G30 self-validation (35th consecutive LOW expected).

## Section 4: Functional Requirements

- **FR-1:** US-001 hook-based observability — no behavior change to dispatch path; only adds visibility.
- **FR-2:** US-002 verification-only; if real refactor needed, AC extends.
- **FR-3:** Plugin version 0.10.6 → 0.10.7 (4 fields).

## Section 5: Non-Goals

- No `--coordinator` dispatch (still reserved for v0.11.0).
- No actual rate-limit handling (e.g., automatic retry with Retry-After). Just observability.

## Section 6: Design Notes

See `.omc/plans/2026-05-02-v0.11.0-wave-dogfood-driven-low-sweep.md` § Cycle 2.

## Section 7: Technical Notes

Bash 4.3+. Hook-based (no core code change for observability).

## Section 8: Success Metrics

- All 4 stories first-attempt PASS.
- 35 consecutive LOW G30.
