# PRD: v0.9.1 — patch-tier (N42-validate — real-LLM dogfood through `--coordinator`)

**Status:** Approved
**Date:** 2026-04-29
**Design doc:** `docs/plans/2026-04-29-v0.9.1-bundle-design.md`
**Source:** `idea-stage/IDEA_REPORT_v27.md` § "N42-validate" (PRIMARY follow-up after v0.9.0)
**Branch:** `ql/v0.9.1-bundle`
**Target version:** 0.9.1 (patch bump from 0.9.0)
**Total effort estimate:** ~3-5 hours (real-LLM wallclock dominates)

## Section 1: Introduction / Overview

5-story patch cycle empirically validating v0.9.0's `--coordinator` per-wave dispatch wires. v0.9.0 shipped infrastructure with stub-driven integration tests (10/10 pass) — v0.9.1 fires the real-LLM path end-to-end against a small synthetic bundle, captures findings, ships inline fixes for any v0.9.0 issues surfaced, runs the standardized post-merge multi-perspective review.

**Patch-tier framing rationale:** No new architecture. No new functions. No new flags. Mirrors v0.8.0 → v0.8.1's pattern (architectural minor → validation patch). Per `feedback_version_tier_calibration.md`, default to patch unless genuinely architectural.

**Empirical break point for the 18-cycle manual-takeover streak.** v0.9.1's outcome answers: did the per-wave coordinator dispatch actually break the streak in production?

## Section 2: Goals

- Fire `bash quantum-loop.sh --coordinator` end-to-end against a synthetic 2-story bundle inside `.ql-wt/dogfood-v091/`.
- Capture verbatim findings on whether `next_wave` fired, `spawn_coordinator` produced reachable output, per-story aggregation routed correctly, coordinator stayed bounded per wave.
- Ship inline fixes for any v0.9.0 defects surfaced (closes empty if v0.9.0 holds up).
- Run multi-perspective post-merge review (architect + code-reviewer + security) — STANDARD pattern.
- Bump plugin version 0.9.0 → 0.9.1 (4 manifest fields).
- Populate `metrics/pre-impl-review-findings.csv` with 3 new rows (total ≥55).

## Section 3: User Stories

### US-001: Real-LLM dogfood — synthetic 2-story bundle through `--coordinator`

**Acceptance Criteria:**
- [ ] `.ql-wt/dogfood-v091/` worktree exists, branched from master HEAD on throwaway branch `dogfood-v091-runtime`.
- [ ] Worktree contains `tasks/prd-dogfood-v091.md` (synthetic 2-story PRD), worktree-local `quantum.json` with stories US-A and US-B (each on a disjoint file `dogfood/target-A.sh` / `dogfood/target-B.sh`), and the two pre-created target files.
- [ ] `bash quantum-loop.sh --coordinator --max-iterations 5` invoked from inside the worktree with `RUNNER_NAME=claude` (default).
- [ ] Full stdout captured at `.ql-wt/dogfood-v091/dogfood-stdout.log`; non-empty; contains either a `<quantum>WAVE_*` signal OR an explicit failure mode.
- [ ] Post-run `quantum.json` snapshot saved at `.ql-wt/dogfood-v091/quantum.post.json`; `stories[].status` and `stories[].review.*` populated for analysis.
- [ ] Wallclock + rough token-count noted (estimate via duration; real measurement deferred).
- [ ] If the dogfood deadlocks / drifts >15min, parent process killed; partial state captured; explicit "did not complete" recorded for US-002.

### US-002: Capture findings into structured retrospective notes

**Acceptance Criteria:**
- [ ] `idea-stage/dogfood-v0.9.1-findings.md` exists with sections:
  1. **`next_wave` invocation** — verbatim cite from `dogfood-stdout.log` showing wave id + story id list, OR documented absence.
  2. **`spawn_coordinator` output reachability** — verbatim quote of the coordinator's first 20 lines (or first 1KB) of output, OR "empty / unreachable" with rationale.
  3. **Per-story aggregation routing** — pre/post `quantum.json` snapshot diff for `stories[].status` field; expected vs actual.
  4. **Coordinator scope boundedness** — did the coordinator subagent's transcript stay scoped to ONE wave (per `agents/coordinator.md` § "Scope")?
  5. **Unexpected behaviors** — anything surprising vs the v0.9.0 design intent.
  6. **Streak status** — explicit "broken (cycle 19)" OR "extended to cycle 19 (operator intervened)" statement.
- [ ] Each section cites specific log lines or `quantum.json` excerpts; no summary-only sections.

### US-003: Soliton-driven inline fixes for v0.9.0 issues surfaced

**Acceptance Criteria:**
- [ ] Each finding from US-002 mapped to one of: (a) inline fix with regression-guard test OR (b) deferred with explicit rationale (LOW severity / out-of-scope).
- [ ] If no defects surfaced: explicit "no defects surfaced; v0.9.0 holds up empirically" recorded in `idea-stage/dogfood-v0.9.1-findings.md` § 5.
- [ ] After any fixes, `tests/test_next_wave.sh`, `tests/test_coordinator_e2e.sh`, `tests/test_signal_parsing.sh`, `tests/test_orchestrator_liveness.sh`, `tests/test_quantum_loop_recovery.sh`, `tests/test_coordinator_dispatch.sh` all green.
- [ ] No fix without a regression-guard test (per p012).

### US-004: Multi-perspective post-merge review (architect + code-reviewer + security)

**Acceptance Criteria:**
- [ ] 3 reviewer agents invoked in parallel via Agent tool: `oh-my-claudecode:architect`, `oh-my-claudecode:code-reviewer`, `oh-my-claudecode:security-reviewer`.
- [ ] Each agent receives the v0.9.1 cycle diff (`git diff origin/master...HEAD`) as their review scope.
- [ ] Each agent's findings logged in retrospective.
- [ ] Synthesis section: which findings were addressed inline (in this cycle), which deferred (with rationale).
- [ ] No score-≥85 finding deferred.

### US-005: Retrospective + IDEA_REPORT_v28 + version bump 0.9.0 → 0.9.1

**Acceptance Criteria:**
- [ ] `idea-stage/PIPELINE_REPORT_v28.md` documents v0.9.1 (5 stories, outcomes, empirical validation summary, streak status).
- [ ] `idea-stage/IDEA_REPORT_v28.md` lists open after v0.9.1; carries forward N43, N46, N48, N49, N50 (or updates per US-003 outcomes); documents streak status.
- [ ] `CHANGELOG.md [0.9.1]` entry covering all 5 stories + empirical validation rationale + honest caveats.
- [ ] All 4 plugin manifest version fields bumped 0.9.0 → 0.9.1: `.claude-plugin/plugin.json`, `.claude-plugin/marketplace.json` (metadata.version + plugins[0].version), `.cursor-plugin/plugin.json`.
- [ ] G30 self-validation captured.
- [ ] Worktree `.ql-wt/dogfood-v091/` removed; throwaway branch `dogfood-v091-runtime` deleted (local). Confirm with `git worktree list` and `git branch -a`.

## Section 4: Functional Requirements

- **FR-1:** US-001 must produce a captured stdout log (non-empty) — empty output blocks US-002 from analysis and is a hard failure.
- **FR-2:** US-002's findings doc cites real evidence — no summary-only fabrications.
- **FR-3:** US-003 ships inline regression tests for any v0.9.0 fix.
- **FR-4:** US-004 invokes 3 reviewers in parallel (single message, multiple Agent calls).
- **FR-5:** Worktree cleanup is mandatory — `.ql-wt/dogfood-v091/` MUST not survive merge.
- **FR-6:** CSV ≥55 rows; plugin version 0.9.0 → 0.9.1; reviews recorded with `automated:true`.

## Section 5: Non-Goals

- No N43 (parallel-with-dispatch wrap pattern); defer to v0.9.2+.
- No N46 (respawn output re-parsing); defer.
- No outer-loop replacement; architect-recommended for v0.10.0.
- No PowerShell parity for the dogfood — bash only.
- No multi-wave dogfood — 1 wave / 2 stories sufficient.
- No N48 (snapshot-diff guard) unless drift surfaces in US-001.
- No bundle branch cleanup (N47) — operator-decision-pending.

## Section 6: Design Notes

See `docs/plans/2026-04-29-v0.9.1-bundle-design.md`.

## Section 7: Technical Notes

Cross-platform: bash 4.3+ (Git Bash on Windows for the dogfood). PowerShell parity not exercised. No new dependencies. No schema changes. Worktree pattern uses existing `.ql-wt/` convention from v0.7.x parallel mode.

## Section 8: Success Metrics

- All 5 stories first-attempt PASS.
- CSV at ≥55 rows.
- US-001 captures non-empty `dogfood-stdout.log` and post-run `quantum.json`.
- US-002 cites real evidence in all 6 sections.
- US-003 ships 0+ fixes with regression tests; closes empty if v0.9.0 holds up.
- US-004 invokes 3 parallel reviewers; no score-≥85 findings deferred.
- Streak status documented explicitly.

## Section 9: Open Questions

- **Q1:** What if `claude --dangerously-skip-permissions --print` produces unexpected output format under the coordinator prompt? **Decision in design:** capture verbatim regardless; document in US-002 § 5; if format breaks the parser, ship US-003 fix to either (a) tolerate format OR (b) tighten coordinator prompt.
- **Q2:** Should the worktree be created via `git worktree add` or `git clone`? **Decision:** `git worktree add` — cheaper, shares object store, matches existing `.ql-wt/` convention.
- **Q3:** What if multiple iterations of the parent loop fire (the synthetic plan only needs 1)? **Decision:** `--max-iterations 5` ceiling; if iteration 2+ fires unexpectedly, that itself is a finding for US-002.
