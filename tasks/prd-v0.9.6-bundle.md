# PRD: v0.9.6 — patch-tier (post-decomposition cleanup)

**Status:** Approved
**Date:** 2026-05-01
**Design doc:** `docs/plans/2026-05-01-v0.9.6-bundle-design.md`
**Source:** `.handoffs/HANDOFF-2026-05-01-post-v0.9.5.md` § CORRECTIONS + `idea-stage/v0.9.x-arc-audit-2026-04-30.md:48,70`.
**Branch:** `ql/v0.9.6-bundle`
**Target version:** 0.9.6 (patch from 0.9.5)
**Total effort:** ~3 hours

## Section 1: Introduction / Overview

5-story patch closing mechanical-cleanup items deferred from v0.9.5 (the decomposition cycle): jq atomic-update migration via new `json_atomic_update_args` variant + COMPLETE/BLOCKED helper extraction + CLAUDE.md doc sync. Patch-tier per operator memory. PARALLEL_MODE extraction (the only minor-tier item from IDEA_REPORT_v32) deferred — needs design pass.

## Section 2: Goals

- Add `json_atomic_update_args` variant to `lib/json-atomic.sh` supporting jq `--arg`/`--argjson` passthrough (per audit prerequisite at `idea-stage/v0.9.x-arc-audit-2026-04-30.md:70`).
- Migrate 6 production-path `jq <expr> quantum.json > quantum.json.tmp && mv` sites to the new variant.
- Extract `emit_terminal_signal <COMPLETE|BLOCKED> [message]` helper into `lib/loop-helpers.sh`; dedup 3 production-path print pairs.
- CLAUDE.md tilde line-number sync (post-decomposition drift) + 3 LOW absorbs.
- 8th application of multi-perspective post-merge review pattern.
- Bump 0.9.5 → 0.9.6 (4 manifest fields).
- 27 consecutive LOW G30 self-validation.

## Section 3: User Stories

### US-001: Add `json_atomic_update_args` variant + migrate 6 production-path sites

**Acceptance Criteria:**

T-001-1 (variant + tests):
- [ ] `lib/json-atomic.sh` adds `json_atomic_update_args(filter, json_path, [jq_arg ...])` function. Required: filter, json_path. Optional: zero-or-more jq arg pairs forwarded verbatim. Uses `write_quantum_json` for atomic semantics. Empty-output guard same as `json_atomic_update`.
- [ ] `tests/test_json_atomic.sh` adds ≥3 new test cases covering: (a) `--arg` string passthrough; (b) `--argjson` JSON passthrough; (c) error on missing filter or missing json_path.
- [ ] `bash -n lib/json-atomic.sh` clean.
- [ ] `bash tests/test_json_atomic.sh` rc=0 with all new tests passing.
- [ ] Existing `json_atomic_update` callers unchanged (`lib/iteration-loop.sh:363, 367, 370`).

T-001-2 (migrate 6 production-path sites):
- [ ] `lib/iteration-loop.sh:161-168` (wave-mark in_progress) uses `json_atomic_update_args`.
- [ ] `lib/iteration-loop.sh:388-395` (WAVE_PASSED) uses `json_atomic_update_args`.
- [ ] `lib/iteration-loop.sh:412-426` (WAVE_FAILED per-story aggregation) uses `json_atomic_update_args`.
- [ ] `lib/iteration-loop.sh:444-453` (unknown-signal retries++) uses `json_atomic_update_args`.
- [ ] `lib/loop-helpers.sh:82-89` (stale-detection reset) uses `json_atomic_update_args`.
- [ ] `quantum-loop.sh:358-360` (pre-loop maxAttempts setup) uses `json_atomic_update_args`.
- [ ] `lib/json-atomic.sh` is sourced before each consumer (or via existing chain). Verify by `grep -l 'json_atomic_update_args' lib/iteration-loop.sh lib/loop-helpers.sh quantum-loop.sh` returns all three.
- [ ] PARALLEL_MODE sites (`quantum-loop.sh:526-756`) UNCHANGED.
- [ ] Production-path negative grep: `grep -rEn 'quantum\.json\.tmp' --include='*.sh' lib/iteration-loop.sh lib/loop-helpers.sh` returns 0 hits (confirms no leftover inline tmp+mv in iteration-loop or loop-helpers production paths).
- [ ] All 9 test suites green.
- [ ] `bash quantum-loop.sh --audit` output identical to pre-migration (behavior preservation).

### US-002: Extract `emit_terminal_signal` helper; dedup 3 production-path print pairs

**Acceptance Criteria:**
- [ ] New function `emit_terminal_signal <signal> [message]` in `lib/loop-helpers.sh`. Prints separator + `<quantum>$signal</quantum>` + optional message + separator. No exit; no control flow. Pure formatter.
- [ ] 3 production-path pair refactors in `lib/iteration-loop.sh`:
  - `:73-89` (sequential mode COMPLETE + BLOCKED branches)
  - `:116-131` (coordinator mode COMPLETE + BLOCKED branches)
  - `:351-376` (end-of-iteration sweep COMPLETE + BLOCKED branches)
- [ ] PARALLEL_MODE pair (`quantum-loop.sh:467, 476`) UNCHANGED.
- [ ] After refactor, grep `'printf .*<quantum>(COMPLETE|BLOCKED)</quantum>'` in `lib/iteration-loop.sh` returns 0 raw printf hits (only `emit_terminal_signal` callers).
- [ ] `tests/test_signal_parsing.sh` unchanged (operates on output strings; behavior-preserving).
- [ ] `bash -n` clean on modified files.
- [ ] `bash tests/test_coordinator_e2e.sh` rc=0 (21/21).

### US-003: CLAUDE.md tilde line-number sync + 3 LOW absorbs

**Acceptance Criteria:**
- [ ] `CLAUDE.md:263` reference `quantum-loop.sh:~1592` updated to `lib/iteration-loop.sh:237` (the `eval "$RUNNER_CMD"` site post-decomposition).
- [ ] LOW absorb 1 (`${RUNNER_EXIT:-0}` redundant default): audit `lib/iteration-loop.sh:272` site. Either simplify to `$RUNNER_EXIT` (if guaranteed set) OR keep with a 1-line comment explaining why default is needed.
- [ ] LOW absorb 2 (comment-block density): identify the post-decomp dense block (was `quantum-loop.sh:1664-1692`; now in `lib/iteration-loop.sh`) and split into 2 logical subsections OR add subheaders.
- [ ] LOW absorb 3 (`bash -c` subshell scoping comment): add 1-line clarifier near the coord dispatch — `# bash -c subshell: locals not exported; rely on env/positional args`.
- [ ] After update: `! grep -q 'quantum-loop\.sh:~1592' CLAUDE.md` (the stale ref is gone).
- [ ] `bash -n` clean on modified files.
- [ ] All 9 test suites green.

### US-004: Multi-perspective post-merge review (8th application)

**Acceptance Criteria:**
- [ ] 3 reviewer agents invoked in parallel: architect + code-reviewer + security.
- [ ] Findings logged in retrospective.
- [ ] Synthesis section: which findings addressed inline + which deferred.
- [ ] No score-≥85 finding deferred.

### US-005: Retrospective + IDEA_REPORT_v33 + version bump 0.9.5 → 0.9.6

**Acceptance Criteria:**
- [ ] `idea-stage/PIPELINE_REPORT_v33.md` documents v0.9.6 (5 stories, US-004 review synthesis, cleanup metrics).
- [ ] `idea-stage/IDEA_REPORT_v33.md` rolling forward state. PARALLEL_MODE extraction tracked as remaining v0.10.0 candidate.
- [ ] `CHANGELOG.md [0.9.6]` entry.
- [ ] 4 plugin manifest version fields bumped 0.9.5 → 0.9.6 (`.claude-plugin/plugin.json`, `.claude-plugin/marketplace.json` ×2, `.cursor-plugin/plugin.json`).
- [ ] G30 self-validation captured (27th consecutive LOW expected).

## Section 4: Functional Requirements

- **FR-1:** Migration is behavior-preserving (atomic-update semantics identical to inline idiom; all tests green).
- **FR-2:** `json_atomic_update_args` forwards arbitrary args verbatim to jq via `"$@"`. Empty-output guard parity with `json_atomic_update`.
- **FR-3:** `emit_terminal_signal` is a pure formatting wrapper; no exit/control-flow side effects.
- **FR-4:** No new dependencies; no schema changes; no CLI changes.
- **FR-5:** US-004 review surfaces no blocking findings (or all addressed inline).
- **FR-6:** Plugin version 0.9.5 → 0.9.6 (4 fields).

## Section 5: Non-Goals

- No PARALLEL_MODE block extraction (deferred — design pass needed).
- No PARALLEL_MODE jq-site migration (8 sites stay; migrate when block extracts).
- No PARALLEL_MODE COMPLETE/BLOCKED pair migration (1 pair stays; migrate when block extracts).
- No real-feature dogfood.
- No N40, N43, N46, N47-N50.
- No PowerShell parity.
- No p013/p014 canonization (operator decision pending).
- No daemon-style work (per ADR-001).

## Section 6: Design Notes

See `docs/plans/2026-05-01-v0.9.6-bundle-design.md` for API designs (variant + helper) and full migration site map.

## Section 7: Technical Notes

Bash 4.3+. `lib/json-atomic.sh::json_atomic_update` already exists + tested via `tests/test_json_atomic.sh`. The args variant extends but doesn't replace the existing helper. Mechanical refactor preserves all existing flows (production + PARALLEL_MODE deferred sites).

## Section 8: Success Metrics

- All 5 stories first-attempt PASS.
- 0 `jq.tmp&&mv` in `lib/iteration-loop.sh` + `lib/loop-helpers.sh` after migration.
- `quantum-loop.sh` retains exactly 1 production-path `jq.tmp&&mv` site at line 358-360 only if it migrates; otherwise 0 in production-path region. PARALLEL_MODE sites (lines 526+) UNCHANGED.
- 0 raw `printf "  <quantum>(COMPLETE|BLOCKED)</quantum>"` in `lib/iteration-loop.sh` after extraction (only helper callers).
- 9 test suites green.
- `tests/test_json_atomic.sh` test count grows by ≥3.
- 27 consecutive LOW G30 self-validation.

## Section 9: Open Questions

- **Q1:** Tier — patch (0.9.6) or minor (0.10.0)? **Decision:** patch (0.9.6) per operator memory; mechanical cleanup + small additive helper.
- **Q2:** Replace existing `json_atomic_update` callers with `json_atomic_update_args`? **Decision:** No. Existing 3 callers using inline-validated `STORY_ID` stay on the simpler API.
- **Q3:** Cover test fixtures in jq migration? **Decision:** No; fixtures intentionally use raw idiom.
- **Q4:** Migrate PARALLEL_MODE sites in this cycle? **Decision:** No. They migrate when the block extracts (v0.10.0 candidate).
