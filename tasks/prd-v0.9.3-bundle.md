# PRD: v0.9.3 — patch-tier (operational hardening — closes v0.9.2 iter-3 hang)

**Status:** Approved
**Date:** 2026-04-30
**Design doc:** `docs/plans/2026-04-30-v0.9.3-bundle-design.md`
**Source:** `idea-stage/IDEA_REPORT_v29.md` § "v0.9.3 candidate slate"
**Branch:** `ql/v0.9.3-bundle`
**Target version:** 0.9.3 (patch from 0.9.2)
**Total effort estimate:** ~2-3 hours

## Section 1: Introduction / Overview

4-story patch closing the operational gap surfaced by v0.9.2's dogfood iteration 3 hang (coordinator subagent stuck > 3 hours mid-`eval "$COORD_CMD"`). Adds a parent-side wallclock timeout; re-evaluates the v0.9.0 `ql_wrap_subagent_dispatch` gating decision; resumes the post-merge multi-perspective review pattern (5th application; SKIPPED in v0.9.2 because US-004 was dogfood).

## Section 2: Goals

- Add `timeout`-based wallclock guard around `eval "$COORD_CMD"` in `quantum-loop.sh`.
- Configurable via `QL_COORDINATOR_TIMEOUT_S` env var (default 1800 = 30 min).
- On timeout: surface as `WAVE_FAILED` for per-story aggregation.
- Update `ql_wrap_subagent_dispatch` gate comment with explicit rationale (KEEP OFF) + cross-ref to US-001.
- Spawn 3 parallel reviewers (architect + code-reviewer + security) on the v0.9.3 diff.
- Bump plugin version 0.9.2 → 0.9.3 (4 manifest fields).
- Populate `metrics/pre-impl-review-findings.csv` with 3 new rows (total ≥61).

## Section 3: User Stories

### US-001: Parent-side wallclock timeout on `eval "$COORD_CMD"`

**Acceptance Criteria:**
- [ ] `quantum-loop.sh` line ~1585 (the `eval "$COORD_CMD"` invocation) wrapped with `timeout --kill-after=10s "${QL_COORDINATOR_TIMEOUT_S}s" bash -c "$COORD_CMD"`.
- [ ] `QL_COORDINATOR_TIMEOUT_S` env var with default 1800 (30 min) read at top of the spawn block.
- [ ] On timeout (rc=124 from `timeout`): set `SIGNAL_RESULT="WAVE_FAILED"`; print ERROR to stderr (pattern: `Coordinator subagent exceeded.*timeout`).
- [ ] `tests/test_coordinator_e2e.sh` adds Test 6 (`hung_coordinator` mode): stub `claude` script that sleeps > timeout; uses `QL_COORDINATOR_TIMEOUT_S=5` to keep test wallclock < 30s; asserts ERROR pattern + per-story aggregation runs.
- [ ] Existing Tests 1-5 in `test_coordinator_e2e.sh` continue to pass (13/13 → 14/14).
- [ ] `bash -n quantum-loop.sh` clean.

### US-002: Re-evaluate `ql_wrap_subagent_dispatch` gating under coordinator mode

**Acceptance Criteria:**
- [ ] `quantum-loop.sh:~1657-1661` ql_wrap gate has updated multi-line comment explaining:
   1. Why STALE detection is unsafe under coordinator mode (false-positive on aggregation pauses where the coordinator legitimately doesn't commit for minutes).
   2. Cross-reference to `QL_COORDINATOR_TIMEOUT_S` from US-001 as the operational alternative.
   3. Reaffirm N46 (respawn output re-parsing) still unresolved.
- [ ] Behavioral change: NONE (the gate stays OFF — this is documentation only).
- [ ] `bash -n quantum-loop.sh` clean.

### US-003: Multi-perspective post-merge review (architect + code-reviewer + security)

**Acceptance Criteria:**
- [ ] 3 reviewer agents invoked in parallel via Agent tool: `oh-my-claudecode:architect`, `oh-my-claudecode:code-reviewer`, `oh-my-claudecode:security-reviewer`.
- [ ] Each agent receives the v0.9.3 cycle diff (`git diff origin/master...HEAD`) as scope.
- [ ] Each agent's findings logged in retrospective.
- [ ] Synthesis: which findings addressed inline + which deferred.
- [ ] No score-≥85 finding deferred.

### US-004: Retrospective + IDEA_REPORT_v30 + version bump 0.9.2 → 0.9.3

**Acceptance Criteria:**
- [ ] `idea-stage/PIPELINE_REPORT_v30.md` documents v0.9.3 (4 stories, outcomes, US-003 review synthesis).
- [ ] `idea-stage/IDEA_REPORT_v30.md` lists open after v0.9.3; carries forward N40, N43, N46, N47, N49, N50.
- [ ] `CHANGELOG.md [0.9.3]` entry.
- [ ] 4 plugin manifest version fields bumped 0.9.2 → 0.9.3.
- [ ] G30 self-validation captured.

## Section 4: Functional Requirements

- **FR-1:** `timeout` from coreutils MUST be available (validated at install time; falls back to no-timeout with warning if missing — but this is unlikely on Git Bash + Linux).
- **FR-2:** `QL_COORDINATOR_TIMEOUT_S` MUST be respected when set; default 1800 otherwise.
- **FR-3:** Test 6 in `test_coordinator_e2e.sh` MUST exercise the actual `timeout` rc=124 path.
- **FR-4:** US-002 is documentation-only; no behavioral change.
- **FR-5:** CSV ≥61 rows; plugin version 0.9.2 → 0.9.3.

## Section 5: Non-Goals

- No N43, N46, N47, N48, N49, N50.
- No real-feature dogfood (defer to v0.10.0+).
- No PowerShell parity for the new timeout.

## Section 6: Design Notes

See `docs/plans/2026-04-30-v0.9.3-bundle-design.md`.

## Section 7: Technical Notes

`timeout(1)` from GNU coreutils. Available on Git Bash + Linux + macOS. Returns 124 on SIGTERM kill, 137 on SIGKILL. `--kill-after=10s` adds grace before SIGKILL.

## Section 8: Success Metrics

- All 4 stories first-attempt PASS.
- CSV at ≥61 rows.
- Test count: 111 → 112 (+1 from Test 6).
- US-003 review trio runs without surfacing score-≥85 findings (or ≥85 findings addressed inline).
- v0.9.2 iter-3 hang: CLOSED (engineered).

## Section 9: Open Questions

- **Q1:** What's the right default timeout? **Decision:** 1800s (30 min). Rationale: v0.9.1 dogfood completed in ~18 min; v0.9.2 dogfood iters 1+2 each ~10-30 min; iter 3 hung > 3 hours. 30 min ceiling catches hangs without false-positive on legitimate slow waves.
- **Q2:** Should US-002 actually re-enable `ql_wrap_subagent_dispatch`? **Decision:** No. The new timeout is sufficient + simpler. Document rationale only.
