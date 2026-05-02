# PRD: v0.10.8 — patch-tier (wave-cycle-3: N48 + ANSI passthrough sanitization)

**Status:** Approved per `.omc/plans/2026-05-02-v0.11.0-wave-dogfood-driven-low-sweep.md` cycle-3.
**Date:** 2026-05-02
**Branch:** `ql/v0.10.8-bundle`
**Target version:** 0.10.7 → 0.10.8 (patch).
**Total effort:** ~1.5 hours.

## Section 1: Introduction / Overview

4-story patch shipping wave-plan cycle-3. Closes N48 (field-ownership runtime enforcement; defense-in-depth) + ANSI control-char passthrough sanitization (security LOW carried since v0.10.0; re-flagged in v0.10.7 review).

## Section 2: Goals

- Add field-ownership snapshot-diff guard at coordinator-mode dispatch boundary. WARN if parent-owned fields (`.stories[].status`, `.retries.*`) modified by the coordinator subagent.
- Strip ANSI control chars from jq stderr before printing in `json_atomic_update*` error messages.
- 17th p014 review.
- Bump 0.10.7 → 0.10.8.
- 36 consecutive LOW G30.

## Section 3: User Stories

### US-001: N48 — Field-ownership runtime enforcement

**Acceptance Criteria:**
- [ ] `lib/iteration-loop.sh` coordinator-mode branch (after `WAVE_STORY_IDS_JSON` mark-in-progress at ~line 150, BEFORE dispatch at ~line 200): snapshot parent-owned fields for wave stories: `PARENT_OWNED_BEFORE=$(jq -c --argjson ids "$WAVE_STORY_IDS_JSON" '[.stories[] | select(.id as $id | $ids | index($id)) | {id, status, retries}]' quantum.json)`.
- [ ] Post-dispatch (after `bash -c "$COORD_CMD"`, before parent-side HEAD guard): same jq snapshot to `PARENT_OWNED_AFTER`. Compare via string equality.
- [ ] If different: emit `[FIELD-OWNERSHIP] WARN: parent-owned fields modified during dispatch` + `before:` + `after:` lines to stderr. Do NOT abort or change signal classification — observability only (defense-in-depth complement to v0.9.5 parent-side HEAD guard).
- [ ] No new test required (functional integration test would need a stub coordinator that violates field-ownership; defer to v0.11.0 dogfood).
- [ ] `bash -n lib/iteration-loop.sh` clean.

### US-002: ANSI control-char passthrough sanitization

**Acceptance Criteria:**
- [ ] `lib/json-atomic.sh:302, 349` (printf statements that include `$err` from captured jq stderr; line numbers as of v0.10.10 — original PRD cited 296/341 prior to ANSI-sanitization insertion shifting printf sites by +6) sanitize `$err` before printing: strip ANSI ESC sequences + non-printable control chars except newline/tab.
- [ ] Sanitization helper added at top of `lib/json-atomic.sh` (or inline): `err=$(printf '%s' "$err" | tr -d '\001-\010\013-\037\177' | sed 's/\x1b\[[0-9;]*[a-zA-Z]//g')` OR equivalent compatible pattern.
- [ ] Existing Test 14 (jq stderr surfaces in error message) still passes — sanitization preserves the actual jq error text, only strips control chars.
- [ ] `bash -n lib/json-atomic.sh` clean.
- [ ] `bash tests/test_json_atomic.sh` rc=0; 35/35.

### US-003: Multi-perspective post-merge review (17th application)

**Acceptance Criteria:**
- [ ] 3 reviewer agents (architect + code-reviewer + security) invoked in parallel.
- [ ] No score-≥85 finding deferred.

### US-004: Retrospective + IDEA_REPORT_v42 + version bump 0.10.7 → 0.10.8

**Acceptance Criteria:**
- [ ] `idea-stage/PIPELINE_REPORT_v42.md` documents v0.10.8 (4 stories).
- [ ] `idea-stage/IDEA_REPORT_v42.md` rolling forward state.
- [ ] `CHANGELOG.md [0.10.8]` entry.
- [ ] 4 plugin manifest version fields bumped 0.10.7 → 0.10.8.
- [ ] G30 self-validation (36th consecutive LOW expected).

## Section 4: Functional Requirements

- **FR-1:** US-001 N48 guard is observability-only; does NOT abort or change signal classification.
- **FR-2:** US-002 sanitization preserves jq error text content; only strips control chars.
- **FR-3:** Plugin version 0.10.7 → 0.10.8 (4 fields).

## Section 5: Non-Goals

- No `--coordinator` dispatch (v0.11.0 reserved).
- No new architectural work.
- No automated test for N48 violation case (would require stub coordinator that violates contract; defer to dogfood).

## Section 6: Design Notes

- N48 snapshot-diff window: BETWEEN mark-in-progress (line ~150) AND parent's per-story aggregation (line ~382/406/438). Captures coordinator-owned writes to parent-owned fields; ignores parent's own writes.
- ANSI sanitization preserves: `\n`, `\t`, printable ASCII. Strips: ESC `\x1b` + bracketed sequences, other control chars (`\x01-\x08`, `\x0b-\x1f`, `\x7f`).

## Section 7: Technical Notes

Bash 4.3+. No new dependencies; `tr`/`sed` available everywhere.

## Section 8: Success Metrics

- All 4 stories first-attempt PASS.
- 5 test suites green: 15+21+44+35+18 = 133.
- 36 consecutive LOW G30.
