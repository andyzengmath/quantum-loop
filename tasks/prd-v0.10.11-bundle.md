# PRD: v0.10.11 — patch-tier (N46 closure: respawn output re-parsing)

**Status:** Auto-approved per `/loop` step 4-5; recommended path per architect's p015 4th-application audit (architecturally autonomously achievable, contained scope).
**Date:** 2026-05-02
**Predecessor:** `tasks/prd-v0.10.10-bundle.md`.
**Branch:** `ql/v0.10.11-bundle`.
**Target version:** 0.10.10 → 0.10.11 (patch).
**Total effort:** ~1 hour.

## Section 1: Introduction / Overview

4-story patch closing **N46** — `QL_RESPAWN_CMD` respawn-output not re-parsed. Per architect's audit (post-v0.10.9), the fix is contained: capture respawn stdout/stderr in `wrap_orchestrator_dispatch` (`lib/orchestrator-liveness.sh:125`), re-feed through `runner_parse_output`, update `SIGNAL_RESULT`/`SIGNAL_CONFIDENCE` so the iteration loop's post-wrap case-statement reflects the respawned run rather than the original failed parse.

**Acknowledged in code (pre-fix):** `lib/iteration-loop.sh:342-353` documents the exact limitation — "the respawn's output is NOT re-parsed (SIGNAL_RESULT stays at STORY_FAILED). Tracked as N46 for v0.9.0+ alongside N42."

## Section 2: Goals

- Capture respawn output via `tee` while preserving live operator-visible streaming.
- Call `runner_parse_output` on captured output + respawn rc to update SIGNAL_RESULT/SIGNAL_CONFIDENCE.
- Add test coverage: mock `QL_RESPAWN_CMD` that emits `<quantum>STORY_PASSED</quantum>`, assert SIGNAL_RESULT updates from STORY_FAILED to STORY_PASSED post-wrap.
- 20th p014 review.
- Bump 0.10.10 → 0.10.11.
- 39 consecutive LOW G30.

## Section 3: User Stories

### US-001: N46 — respawn output re-parsing

**Acceptance Criteria:**
- [ ] `lib/orchestrator-liveness.sh::wrap_orchestrator_dispatch` (around lines 122-131): replace `bash -c "${QL_RESPAWN_CMD}"; respawn_rc=$?` with a tee-and-capture pattern. Use `mktemp` + `tee` so live output streams to operator AND is captured for re-parse. Recover bash rc via `${PIPESTATUS[0]}` (Git Bash compatible).
- [ ] After respawn completes: if `runner_parse_output` is available (`type runner_parse_output >/dev/null 2>&1`), call it with `(respawn_out, respawn_rc, worktree_path)`. SIGNAL_RESULT and SIGNAL_CONFIDENCE will be updated to reflect the respawn.
- [ ] If `runner_parse_output` is NOT available (library not sourced; standalone usage), fall through gracefully — do not introduce a hard dependency on `lib/runner.sh`.
- [ ] Update the comment block at `lib/iteration-loop.sh:342-353` to reflect that N46 is now closed (replace "tracked as N46" language with "closed in v0.10.11").
- [ ] Cleanup: `rm -f "$tmpfile"` on all exit paths (success + failure).
- [ ] `bash -n lib/orchestrator-liveness.sh` clean.

### US-002: Test coverage for N46

**Acceptance Criteria:**
- [ ] New test in `tests/test_orchestrator_liveness.sh` (create file if absent; add to existing if present): mock scenario where `QL_RESPAWN_CMD` is set to a script that prints `<quantum>STORY_PASSED</quantum>` then exits 0.
- [ ] Force STALE path by setting a tiny `QL_LIVENESS_TIMEOUT` (or directly invoking the post-stale code path via test scaffolding).
- [ ] Pre-respawn: SIGNAL_RESULT="STORY_FAILED" (initial value).
- [ ] Post-wrap: SIGNAL_RESULT="STORY_PASSED" (updated by re-parse).
- [ ] Test rc=0 from the test harness.
- [ ] Smoke check on the 5-suite baseline (15+21+44+35+18 = 133): no regressions.
- [ ] If `tests/test_orchestrator_liveness.sh` is created, register it in any test-runner enumeration (e.g., `tests/run_all.sh` if present); skip registration if test-runner enumeration is implicit/glob-based.

### US-003: Multi-perspective post-merge review (20th application)

**Acceptance Criteria:**
- [ ] 3 reviewer agents (architect + code-reviewer + security) invoked in parallel.
- [ ] No score-≥85 finding deferred.

### US-004: Retrospective + IDEA_REPORT_v45 + version bump 0.10.10 → 0.10.11

**Acceptance Criteria:**
- [ ] `idea-stage/PIPELINE_REPORT_v45.md` documents v0.10.11 (4 stories) + N46 closure.
- [ ] `idea-stage/IDEA_REPORT_v45.md` rolling forward state.
- [ ] `CHANGELOG.md [0.10.11]` entry.
- [ ] 4 plugin manifest version fields bumped 0.10.10 → 0.10.11.
- [ ] G30 self-validation (39th consecutive LOW expected).

## Section 4: Functional Requirements

- **FR-1:** N46 fix preserves operator-visible live streaming via `tee` (not silent capture-only).
- **FR-2:** N46 fix is graceful when `runner_parse_output` is not sourced (no hard dep).
- **FR-3:** Cleanup of tmpfile on all paths (success + failure).
- **FR-4:** Plugin version 0.10.10 → 0.10.11 (4 fields).

## Section 5: Non-Goals

- No `--coordinator` dispatch (still v0.11.0 reserved).
- No N43 (operator-gated; out of scope).
- No new architectural work beyond the contained N46 fix.

## Section 6: Design Notes

**tee-and-capture pattern (Git Bash compatible):**

```bash
local tmpfile=$(mktemp)
bash -c "${QL_RESPAWN_CMD}" 2>&1 | tee "$tmpfile"
local respawn_rc=${PIPESTATUS[0]}
local respawn_out=$(cat "$tmpfile")
rm -f "$tmpfile"
if type runner_parse_output >/dev/null 2>&1; then
  runner_parse_output "$respawn_out" "$respawn_rc" "${3:-.}"
fi
```

`PIPESTATUS[0]` recovers the rc of the LHS (`bash -c`), unaffected by the `tee` exit code. Git Bash 4+ supports `PIPESTATUS`.

## Section 7: Technical Notes

Bash 4.3+. No new dependencies (`tee`, `mktemp` available everywhere).

## Section 8: Success Metrics

- All 4 stories first-attempt PASS.
- 5 test suites + 1 new test green: 15+21+44+35+18+N = 133+N.
- 39 consecutive LOW G30.
- N46 closed.
