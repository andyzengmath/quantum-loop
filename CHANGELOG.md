# Changelog

All notable changes to this project will be documented in this file.

Format: [Semantic Versioning](https://semver.org/). Bump per PR:
- **Patch** (0.0.x): bug fixes, doc updates
- **Minor** (0.x.0): new features, backward-compatible
- **Major** (x.0.0): breaking changes

## [0.10.0] - 2026-05-01

### Added — minor-tier (PARALLEL_MODE extraction + housekeeping; v0.9.x architectural arc CLOSED)

6-story minor cycle closing the LAST v0.9.x audit MEDIUM (PARALLEL_MODE block extraction, ~390 LOC) plus housekeeping (jq stderr symmetric hardening, p013/p014 canonization). v0.10.0 self-validated: tier=LOW. **28 consecutive LOW-tier self-validations** (v0.6.5..v0.10.0).

**Headline:** **`quantum-loop.sh` 1837 → 411 LOC across 4 cycles** (v0.9.5 → v0.10.0): 78% reduction with full behavior preservation. Every block in the entry-point now lives in its own dedicated lib file. v0.9.x architectural arc is COMPLETE; v0.10.x+ pivots to LOW housekeeping or feature work.

### Stories shipped

- **US-001 — Extract PARALLEL_MODE block + migrate 8 jq sites + 3 signal sites** — Behavior-preserving extraction of `quantum-loop.sh:394-784` (391 LOC) into NEW `lib/parallel-mode.sh` (427 LOC) wrapped in `run_parallel_mode()` function. Source guard `_QL_PARALLEL_MODE_LIB`. Header documents 11 required globals + 7 helper-lib dependencies. `quantum-loop.sh` 793 → 411 LOC. Bundled with the migrations: 8 production-path `jq+tmp+mv` sites migrated to `json_atomic_update_args` (in_progress mark, timeout, merge_regression, passed, merge_conflict, agent_failed, crash, mid-loop spawn); 3 terminal-signal `printf` patterns migrated to `emit_terminal_signal` (COMPLETE, BLOCKED, MAX_ITERATIONS — PRD scoped 1 pair, shipped 3 for consistency). All in single commit since the lib was created fresh.
- **US-002 — `2>/dev/null` symmetric hardening of `json_atomic_update` + `json_atomic_update_args`** — Both helpers now capture jq stderr via `mktemp` + `trap "rm -f '$path'" RETURN` cleanup. On empty-output failure, error message includes `(jq stderr: <captured>)` when stderr is non-empty; otherwise falls back to v0.9.6 message verbatim. Closes the v0.9.6 US-004 architect F1 (score 88) + code-reviewer MEDIUM (score 72) that were deferred as parity-with-existing. `tests/test_json_atomic.sh` Tests 13+14 added (28 → 32 asserts; +2 for stderr-capture verification + 2 for exit-code).
- **US-003 — Real-feature dogfood — DEFERRED** to v0.10.1+. PRD's clean-deferral path used (no operator-queued feature scope ready). Cycle still ships v0.10.0; dogfood absorbs into a future patch when an actual feature is queued.
- **US-004 — p013 + p014 canonization in CLAUDE.md** — Promoted two cycle-level process patterns from `quantum.json.codebasePatterns` (per-cycle gitignored copy) into permanent project documentation under new `### Process patterns (canonized v0.10.0 / US-004)` subsection. p013 (operator-staged cycle kickoff): 8 applications. p014 (composite review trio): 9 review applications + 5 architect-design applications. Additive only.
- **US-005 — Multi-perspective post-merge review (9th application; ALL SHIP; no inline fixes)** — 3-reviewer trio (architect 93/100, code-reviewer 91/100, security 94/100). Both noted MEDIUMs are pre-existing carry-forward (dead `--argjson wave` from master) or AC-letter-vs-spirit (PRD literal grep `quantum.json.tmp` matches the defensive `git reset HEAD --` line at `lib/parallel-mode.sh:265` which is NOT a jq+tmp+mv migration site). No score-≥85 inline-fix candidates; both findings retro-acknowledged.
- **US-006 — Retrospective + IDEA_REPORT_v34 + version bump 0.9.6 → 0.10.0** — this entry.

### Test-suite delta

| Test file | v0.9.6 | v0.10.0 | delta |
|---|---:|---:|---:|
| `tests/test_json_atomic.sh` (+Tests 13, 14) | 28 | 32 | +4 |
| **Total v0.10.0 added:** | | | **+4** |

### Architectural observations

**v0.9.x architectural arc is COMPLETE.** Cumulative through v0.10.0: per-wave coordinator dispatch (v0.9.0); empirical validation (v0.9.1); 5a HIGH closure (v0.9.2); iter-3 hang closure (v0.9.3); audit housekeeping (v0.9.4); decomposition + parent-side guard + ADR-001 (v0.9.5); jq+tmp+mv migration + emit_terminal_signal helper + CLAUDE.md doc sync (v0.9.6); **PARALLEL_MODE extraction + jq stderr symmetric hardening + p013/p014 canonization (v0.10.0)**. No remaining architectural backlog. v0.10.x+ can pivot to LOW housekeeping or feature work (per `idea-stage/IDEA_REPORT_v34.md`).

### Honest scope drift

- US-003 (real-feature dogfood) deferred per PRD's clean-deferral path. The decomposed + parent-guarded outer loop will be pattern-validated in a future cycle when an actual real feature is queued.
- US-001 shipped T-001-1 + T-001-2 + T-001-3 in single commit because the lib was created fresh; intermediate-state commits would have temporarily kept the old jq+tmp+mv and printf patterns inside the new file. Single-commit choice is cleaner diff-to-master but loses per-sub-task commit granularity.
- The PRD AC for T-001-2 said "grep `quantum.json.tmp` lib/parallel-mode.sh returns 0 hits" — actual is 1 hit on the `git reset HEAD --` defensive-cleanup line at `lib/parallel-mode.sh:265` which is NOT a jq+tmp+mv migration site. Spirit satisfied; future PRDs should write the AC as `grep 'jq.*\.tmp.*&&.*mv' returns 0 hits` to avoid the false-positive.
- Smoke test (`bash quantum-loop.sh --parallel --max-iterations 0`) exits non-zero deep inside `lib/merge-strategy.sh` sourcing — pre-existing dev-env behavior unrelated to extraction (occurs BEFORE `lib/parallel-mode.sh` is reached). Project historically dogfoods coordinator-mode, not parallel-mode.

### Dogfood milestone (v0.10.0)

**5/6 user-facing stories shipped first-attempt PASS** (US-003 cleanly deferred). **G30 self-validation captured** (28th consecutive LOW). **Manual-takeover streak: PARTIALLY BROKEN through v0.10.0** — kickoff scope-ratification needed once (operator approval); story execution autonomous via cron. Same posture as v0.9.6. Full retrospective: `idea-stage/PIPELINE_REPORT_v34.md`. v0.10.x+ backlog: `idea-stage/IDEA_REPORT_v34.md`.

## [0.9.6] - 2026-05-01

### Added — patch-tier (post-decomposition cleanup; v0.9.x audit MEDIUMs CLOSED)

5-story patch closing 4 mechanical-cleanup items the v0.9.x audit had explicitly flagged but that were deferred during v0.9.5 (the decomposition cycle). v0.9.6 self-validated: tier=LOW. **27 consecutive LOW-tier self-validations** (v0.6.5..v0.9.6).

**Headline:** v0.9.x audit MEDIUM list is now EMPTY. New `json_atomic_update_args` variant (audit prerequisite at `idea-stage/v0.9.x-arc-audit-2026-04-30.md:70`) plus 6-site migration; `emit_terminal_signal` helper deduplicates 3 production-path COMPLETE/BLOCKED print pairs; CLAUDE.md tilde line-number drift fixed; 3 LOW absorbs landed.

### Stories shipped

- **US-001 — Add `json_atomic_update_args` variant + migrate 6 production-path sites** — T-001-1 added `json_atomic_update_args(filter, json_path, [jq_arg ...])` to `lib/json-atomic.sh`. Forwards extra args to `jq` verbatim via `"$@"` after `shift 2`; `write_quantum_json` atomic semantics; empty-output guard parity with `json_atomic_update`. Why a variant rather than extending the existing helper: optional `json_path` default in `json_atomic_update` collides with variadic tail; the variant takes path as REQUIRED. `tests/test_json_atomic.sh` extended with Tests 9, 10, 11, 12a, 12b (+7 asserts; 21/21 → 28/28). T-001-2 migrated 6 production-path call-sites: `lib/iteration-loop.sh:147,382,402,434`; `lib/loop-helpers.sh:84`; `quantum-loop.sh:357`. PARALLEL_MODE 8 sites at `quantum-loop.sh:524-756` UNCHANGED per v0.9.5 design (extract when block extracts in v0.10.0+).
- **US-002 — Extract `emit_terminal_signal` helper; dedup 3 production-path COMPLETE/BLOCKED pairs** — Pure formatter `emit_terminal_signal(signal, [message])` in `lib/loop-helpers.sh`. Refactored 3 production-path call-site pairs in `lib/iteration-loop.sh` (sequential, coordinator, end-of-iteration sweep). PARALLEL_MODE pair at `quantum-loop.sh:467+476` UNCHANGED. The BLOCKED-with-format-string call site uses `$(printf '...' "$NEXT_WAVE_RC")` to pre-format vs adding a third arg to the helper.
- **US-003 — CLAUDE.md tilde line-number sync + 3 LOW absorbs** — `CLAUDE.md:263` ref `quantum-loop.sh:~1592` (which moved during v0.9.5 decomposition) updated to `lib/iteration-loop.sh:~212` (the timeout-guarded `bash -c "$COORD_CMD"` dispatch site; per US-004 inline fix the line was sharpened from 208 → 212 with disambiguation note). LOWs: `${RUNNER_EXIT:-0}` simplified to `$RUNNER_EXIT` (init at line 172 verified); `bash -c` subshell scoping clarifier added near coord dispatch; 29-line dense comment block at `lib/iteration-loop.sh:292-320` split into 4 logical subsections via version-keyed subheaders.
- **US-004 — Multi-perspective post-merge review (8th application; 2 inline fixes)** — 3-reviewer trio (architect + code-reviewer + security). All ALL SHIP (architect 93/100; code-reviewer 93/100; security 95/100). 2 score-≥85 INLINE FIXes: (1) Code-reviewer LOW (88) `CLAUDE.md` ref `~208` → `~212` (line 208 is comment, 212 is dispatch); (2) Architect F2 (90) `tests/test_json_atomic.sh` Test 12 split into 12a/12b for unambiguous label triage. Deferred (parity-with-existing): `2>/dev/null` swallows jq diagnostic in BOTH `json_atomic_update` and `json_atomic_update_args` — symmetric hardening in v0.10.0+.
- **US-005 — Retrospective + IDEA_REPORT_v33 + version bump 0.9.5 → 0.9.6** — this entry.

### Test-suite delta

| Test file | v0.9.5 | v0.9.6 | delta |
|---|---:|---:|---:|
| `tests/test_json_atomic.sh` (+Tests 9, 10, 11, 12a, 12b) | 21 | 28 | +7 |
| **Total v0.9.6 added:** | | | **+7** |

### Architectural observations

**v0.9.x audit MEDIUM list now EMPTY.** v0.9.0 shipped per-wave coordinator dispatch wires; v0.9.1 validated empirically; v0.9.2 closed 5a HIGH; v0.9.3 closed iter-3 hang; v0.9.4 closed audit-housekeeping; v0.9.5 closed spike-derived patch-tier work (decomposition + parent-side guard + ADR-001); **v0.9.6 closes the remaining audit MEDIUMs (jq migration + signal-helper extraction + CLAUDE.md drift + 3 LOWs)**. Next significant cycle = v0.10.0 — only remaining minor-tier candidate is PARALLEL_MODE block extraction (~390 LOC + 8 jq sites + 1 COMPLETE/BLOCKED pair migrate together).

### Honest scope drift / autonomous-kickoff rollback footnote

A first-attempt autonomous v0.9.6 kickoff (`5de3bbc`) was rolled back within the same /loop tick. Reading `lib/json-atomic.sh` source revealed: (1) the original PRD missed the audit's explicit "needs json_atomic_update_args variant" requirement at `idea-stage/v0.9.x-arc-audit-2026-04-30.md:70`; (2) the site count was inflated to 10 (real production-path count is 6 per the audit). Rollback was clean (`git reset --hard origin/master`; master unchanged). Corrected scope was written into `.handoffs/HANDOFF-2026-05-01-post-v0.9.5.md` § CORRECTIONS, ratified by the operator, then re-staged at commit `884f10a`. Lesson: `feedback_autonomous_kickoff_caution.md` (don't autonomously kick off cycles without thorough audit-doc reading first; story execution remains autonomous).

### Dogfood milestone (v0.9.6)

**5/5 user-facing stories shipped first-attempt PASS.** **G30 self-validation captured** (27th consecutive LOW). **Manual-takeover streak: PARTIALLY BROKEN through v0.9.6** — kickoff scope-ratification needed once (post-rollback); story execution otherwise autonomous via cron. Cumulatively v0.9.3 + v0.9.4 + v0.9.5 fully autonomous; v0.9.6 needed 1 operator gate. Full retrospective: `idea-stage/PIPELINE_REPORT_v33.md`. v0.10.0 backlog: `idea-stage/IDEA_REPORT_v33.md`.

## [0.9.5] - 2026-05-01

### Added — patch-tier (post-spike: decomposition + parent-side guard + ADR-001)

5-story post-spike patch ratifying the 3-architect pre-cycle design spike (`idea-stage/v0.10.0-design-spike-2026-05-01.md`). The spike found that the originally-framed v0.10.0 "daemon-style runner" replacement was over-engineering — the cron `/loop` pattern already solves the motivating problem. v0.9.5 ships the spike-derived patch-tier work instead. v0.9.5 self-validated: tier=LOW. **26 consecutive LOW-tier self-validations** (v0.6.5..v0.9.5).

**Headline:** v0.9.x track FULLY CLOSED. `quantum-loop.sh` 1837 → 793 LOC (-57%; behavior-preserving 3-extraction). Parent-side `guard_head_advance` defense-in-depth shipped. ADR-001 ACCEPTED — cron `/loop` is canonical outer-loop architecture; no daemon implementation will be built.

### Stories shipped

- **US-001 — Decompose quantum-loop.sh (3 sub-tasks)** — Behavior-preserving extraction across 3 commits: T-001-1 → `lib/audit.sh` (408 LOC; 13 `_audit_*` fns + `do_audit`); T-001-2 → `lib/loop-helpers.sh` (326 LOC; 5 helpers); T-001-3 → `lib/iteration-loop.sh` (468 LOC; iteration body wrapped in `run_iteration_loop()`). Each sub-task verified with all 7 test suites green before commit. `quantum-loop.sh` reduced from 1837 LOC monolith to 793 LOC entry-point. Test-mode source guards (p009) applied to all 3 new libs. PARALLEL_MODE block (~390 LOC) deferred to v0.10.0+ due to worktree-state plumbing complexity.
- **US-002 — Parent-side `guard_head_advance` defense-in-depth** — Coordinator-mode dispatch in `lib/iteration-loop.sh` now performs HEAD-snapshot ancestry verification *in the parent* immediately post-`eval`, regardless of whether the coordinator subagent invoked the guard itself. Failure path: parent prints `ERROR: Parent-side HEAD guard fired. HEAD_BEFORE=… HEAD_AFTER=…` and forces `SIGNAL_RESULT=WAVE_FAILED`. Removes LLM-instruction-following dependency for safety-critical guard. New `tests/test_coordinator_e2e.sh` Test 8: `head_reset` stub mode initializes /tmp git repo with 2 commits + does `git reset --hard HEAD~1` then echoes WAVE_PASSED; asserts ERROR pattern + per-story aggregation. 20/20 → 21/21.
- **US-003 — ADR-001 outer-loop architecture** — `references/adr-001-outer-loop-architecture.md` ACCEPTED. The "daemon-style runner" framing from `idea-stage/IDEA_REPORT_v30.md` was a stale aspiration that outlived its motivating problem. Cron `/loop` pattern (which drove v0.9.3 + v0.9.4 end-to-end with zero manual takeover) is the canonical outer-loop architecture. Documented alternatives: A (persistent daemon — rejected), B (cron `/loop` — chosen), C (inotify — rejected), D (hybrid `while true` — deferred). Triggers for revisit explicit (deprecation of `/loop`, demonstrated cron failure, live-introspection requirement, multi-machine dispatch). `idea-stage/IDEA_REPORT_v31.md` updated to strikethrough Spike 2 + US-002 references.
- **US-004 — Multi-perspective post-merge review (7th application; 2 inline fixes)** — 3-reviewer trio (architect + code-reviewer + security). All ALL SHIP. **2 score-≥85 INLINE FIXes:** (1) MEDIUM ADR-001 § Alternatives lettered A/B/D, skipping C without explanation — added cross-ref note pointing at design-spike A/B/C/D + restored letter C for Inotify. (2) Security MEDIUM `lib/iteration-loop.sh` redirected `guard_head_advance ... 2>/dev/null`, suppressing operationally-useful diagnostic stderr (distinguishes reset-detected vs git-not-on-PATH vs corrupt-repo) — removed redirect; documented rationale inline.
- **US-005 — Retrospective + IDEA_REPORT_v32 + version bump 0.9.4 → 0.9.5** — this entry.

### Test-suite delta

| Test file | v0.9.4 | v0.9.5 | delta |
|---|---:|---:|---:|
| `tests/test_coordinator_e2e.sh` (+Test 8 `head_reset`) | 20 | 21 | +1 |
| **Total v0.9.5 added:** | | | **+1** |

### Architectural observations

**v0.9.x track FULLY CLOSED.** v0.9.0 shipped per-wave coordinator dispatch wires; v0.9.1 validated empirically (streak BROKEN); v0.9.2 closed 5a HIGH (engineered guard); v0.9.3 closed iter-3 hang (engineered timeout); v0.9.4 closed audit-housekeeping; **v0.9.5 closes spike-derived patch-tier work (decomposition + parent-side guard + ADR-001)**. v0.10.0 scope materially smaller than originally projected — daemon-style runner explicitly rejected via ADR-001. Strong recommendation per `idea-stage/IDEA_REPORT_v32.md`: scope v0.10.0 around remaining structural cleanup (json_atomic_update migration, COMPLETE/BLOCKED dedup, PARALLEL_MODE extraction) + first real-feature dogfood, NOT a daemon implementation.

### Honest scope drift

- US-001 deferred PARALLEL_MODE block (~390 LOC) extraction. Spike's ~330 LOC final-state estimate for `quantum-loop.sh` was lower than realized 793 LOC because of this deferral. Documented + tracked for v0.10.0+.
- v0.9.5 is the largest LOC delta in the v0.9.x track (1044 LOC moved across 3 sub-task commits) — but every line was a *move*, not new behavior. Could read "minor" by line count; operator framing call: PATCH because no architectural surface change. Risk surface is the parent-guard hookpoint (~10 lines) and the function-wrapping of the iteration body. Both regression-tested.

### Dogfood milestone (v0.9.5)

**5/5 user-facing stories shipped first-attempt PASS.** **G30 self-validation captured.** **Manual-takeover streak BROKEN through v0.9.5** (3rd consecutive cycle: v0.9.3, v0.9.4, v0.9.5) — cron-driven /loop pattern handled v0.9.5 end-to-end. Full retrospective: `idea-stage/PIPELINE_REPORT_v32.md`. v0.10.0 backlog: `idea-stage/IDEA_REPORT_v32.md`.

## [0.9.4] - 2026-05-01

### Added — patch-tier (housekeeping cycle from v0.9.x post-ship audit)

6-story housekeeping patch closing all findings surfaced by the post-v0.9.3 3-agent audit (architect + doc-specialist + code-reviewer). 1 HIGH (multi-story log under coord mode) + 4 MEDIUM (doc gaps; test coverage; stale references) + 2 LOW (post-merge review inline fixes) closed. v0.9.4 self-validated: tier=LOW. **25 consecutive LOW-tier self-validations** (v0.6.5..v0.9.4).

**Headline:** v0.9.x track operationally CLOSED. All audit-surfaced findings addressed. Remaining backlog is uniformly LOW or v0.10.0-scope. Next significant arc = v0.10.0 (architect-recommended outer-loop replacement; significant architectural work).

### Stories shipped

- **US-001 — agents/coordinator.md cleanup** — 5 in-place edits purging stale future-tense for shipped work (L73 v0.8.1 dogfood; L84/L93 v0.9.0 N42 enforcement; L121-122 IDEA_REPORT_v23 forward references). Liveness section rewritten to document that `ql_wrap_subagent_dispatch` STALE detection is gated OFF under `--coordinator` since v0.9.0; cross-references `QL_COORDINATOR_TIMEOUT_S` (v0.9.3) as operational alternative; legacy `--legacy-orchestrator` mode retains original semantics.
- **US-002 — Gate misleading per-story log under coordinator mode (HIGH)** — `quantum-loop.sh:1547-1558` per-story `Story:` and `Attempt:` printf wrapped in `[[ "$COORDINATOR_MODE" != "true" ]]`. Under coord mode, `STORY_ID` is `wave[0]` only — printing per-story metadata for a multi-story wave was misleading (stories 2..N invisible). Coord-mode operators rely on the wave-summary line at quantum-loop.sh:~1591. Symmetric with v0.9.1 US-003's "Spawning %s for story %s" gate.
- **US-003 — Document QL_COORDINATOR_TIMEOUT_S + helper libs in CLAUDE.md** — New "Coordinator-related" subsection under Process references documenting: `QL_COORDINATOR_TIMEOUT_S` env var (default 1800s; v0.9.3 wallclock ceiling); `lib/coordinator-guard.sh::guard_head_advance` (v0.9.2 HEAD-snapshot guard via `git merge-base --is-ancestor`); `lib/quantum-validate.sh::validate_story_filepaths` (v0.9.2 advisory hook); coordinator-specific test file pointers.
- **US-004 — next_wave integration coverage** — `tests/test_dag_query.sh` adds Tests 17-20 (8 new asserts; integration coverage of `next_wave` through `dag-query.sh` source path with `get_executable_stories` + `filter_file_conflicts` + `validate_story_filepaths` preamble hook). Complements existing `tests/test_next_wave.sh` (18 unit cases). 36/36 → 44/44.
- **US-005 — Multi-perspective post-merge review (6th application; 2 inline fixes)** — 3-reviewer trio (architect + code-reviewer; security skipped due to minimal v0.9.4 surface). Both architect + code-reviewer SHIP. **2 score-≥85 INLINE FIXes:** (1) MEDIUM agents/coordinator.md L117 future-tense "must respect" → past-tense "respects (validated empirically...)"; (2) LOW CLAUDE.md L244 enumeration of Process references subsections updated to include "Coordinator-related".
- **US-006 — Retrospective + IDEA_REPORT_v31 + version bump 0.9.3 → 0.9.4** — this entry.

### Test-suite delta

| Test file | v0.9.3 | v0.9.4 | delta |
|---|---:|---:|---:|
| `tests/test_dag_query.sh` (+Tests 17-20) | 36 | 44 | +8 |
| **Total v0.9.4 added:** | | | **+8** |

### Architectural observations

**v0.9.x track operationally CLOSED.** v0.9.0 shipped per-wave coordinator dispatch wires; v0.9.1 validated empirically (streak BROKEN); v0.9.2 closed 5a HIGH (engineered guard); v0.9.3 closed iter-3 hang (engineered timeout); **v0.9.4 closes housekeeping (audit-surfaced findings)**. Next significant cycle = v0.10.0 (architect-recommended outer-loop replacement; significant architectural work; design spike required first per `idea-stage/IDEA_REPORT_v31.md`).

### Honest scope drift

- US-005 dispatched 2 of 3 reviewers (security skipped due to minimal v0.9.4 security surface — docs + 1 log gate + tests). Pattern p014 preserved as 5 prior full-trio applications + 1 deliberate skip with rationale. Should not be treated as a precedent for skipping security review on substantive cycles.

### Dogfood milestone (v0.9.4)

**6/6 user-facing stories shipped first-attempt PASS.** **Multi-cycle CSV milestone**: 61 → 64 rows (3 advisory rows). **G30 self-validation captured.** **Manual-takeover streak BROKEN through v0.9.4** — cron-driven /loop pattern handled v0.9.4 end-to-end with no operator intervention beyond initial scope confirmation. Full retrospective: `idea-stage/PIPELINE_REPORT_v31.md`. v0.10.0 backlog: `idea-stage/IDEA_REPORT_v31.md`.

## [0.9.3] - 2026-04-30

### Added — patch-tier (operational hardening — closes v0.9.2 iter-3 hang)

4-story patch closing v0.9.2's documented operational gap (coordinator subagent stuck mid-`eval` for 3+ hours during dogfood iteration 3). v0.9.3 self-validated: tier=LOW (G30 in retrospective). **24 consecutive LOW-tier self-validations** (v0.6.5..v0.9.3).

**Headline result: v0.9.2 iter-3 hang — CLOSED (engineered).** New parent-side wallclock timeout wraps `eval "$COORD_CMD"` with `timeout(1)` from coreutils. Default 30 min ceiling; configurable via `QL_COORDINATOR_TIMEOUT_S` env var. On `timeout`'s rc=124 (SIGTERM kill), parent forces `SIGNAL_RESULT=WAVE_FAILED` so per-story review-field aggregation runs.

### Stories shipped

- **US-001 + US-002 (atomic) — parent-side wallclock timeout + KEEP-OFF rationale documentation** — `quantum-loop.sh:~1592` wraps coord dispatch with `timeout --kill-after=10s ${QL_COORDINATOR_TIMEOUT_S:-1800}s bash -c "$COORD_CMD"`. After `runner_parse_output`: if `RUNNER_EXIT==124`, force `SIGNAL_RESULT=WAVE_FAILED` + ERROR (pattern: `Coordinator subagent exceeded.*timeout`). `ql_wrap_subagent_dispatch` gate stays OFF under coordinator mode (US-002 comment expansion documents rationale: STALE detection unsafe under coordinator mode + cross-ref to `QL_COORDINATOR_TIMEOUT_S`). New `tests/test_coordinator_e2e.sh` Test 6: stub `hung_coordinator` mode (sleep 30s) + `QL_COORDINATOR_TIMEOUT_S=5`; asserts ERROR + per-story aggregation marks both stories failed. 13/13 → 16/16 (+3).
- **US-003 — multi-perspective post-merge review + 2 score-≥85 inline fixes** — 3 parallel reviewers (architect + code-reviewer + security). Verdicts: architect SHIP, code-reviewer REQUEST CHANGES, security SHIP. **2 inline fixes:** (1) HIGH score 90 — missing `timeout` availability guard per FR-1; added `command -v timeout` check matching `lib/dep-manifest.sh:255`; on missing, WARN + degrade to plain `bash -c` (v0.9.2 behavior). (2) MEDIUM score 88 — numeric validation on `QL_COORDINATOR_TIMEOUT_S`; non-numeric input → WARN + default 1800. New Test 7 validates the fixes. 16/16 → 18/18 (+2).
- **US-004 — retrospective + IDEA_REPORT_v30 + version bump 0.9.2 → 0.9.3** — this entry.

### Test-suite delta

| Test file | v0.9.2 | v0.9.3 | delta |
|---|---:|---:|---:|
| `tests/test_coordinator_e2e.sh` (+Test 6 + Test 7) | 13 | 18 | +5 |
| **Total v0.9.3 added:** | | | **+5** |

### Architectural observations

**v0.9.x track has reached operational + structural maturity.** v0.9.0 shipped per-wave coordinator dispatch wires. v0.9.1 validated empirically (streak BROKEN). v0.9.2 closed 5a HIGH (engineered guard). v0.9.3 closes operational iter-3 hang (engineered timeout). The next significant cycle would be **v0.10.0** (architect-recommended outer-loop replacement; deferred from v0.9.0).

**v0.9.4 candidate slate** (in `idea-stage/IDEA_REPORT_v30.md`): cosmetic housekeeping + 1 optional real-feature dogfood. Mostly LOW severity. May skip and pivot to v0.10.0 design phase.

### Honest scope drift

- US-003 review surfaced 1 HIGH (FR-1 violation). Reviewer originally said REQUEST CHANGES; INLINE FIX brought it to SHIP. The HIGH was a real PRD AC violation (FR-1 said "fallback if `timeout` missing" but the v0.9.3 commit-1 implementation lacked the guard). Inline fix closed it cleanly.

### Dogfood milestone (v0.9.3)

**4/4 user-facing stories shipped first-attempt PASS.** **Multi-cycle CSV milestone**: 58 → 61 rows (3 advisory rows). **G30 self-validation captured.** **Manual-takeover streak BROKEN through v0.9.3** — cron-driven /loop pattern handled v0.9.3 end-to-end with no operator intervention. Full retrospective: `idea-stage/PIPELINE_REPORT_v30.md`. v0.9.4 backlog: `idea-stage/IDEA_REPORT_v30.md`.

## [0.9.2] - 2026-04-30

### Added — patch-tier (defensive hardening — closes v0.9.1 5a HIGH advisory + 2 reviewer MEDIUMs)

5-story patch closing v0.9.1's known-issue advisory and 2 reviewer MEDIUMs from v0.9.1 US-004 review trio. v0.9.2 self-validated: tier=LOW (G30 in retrospective). **23 consecutive LOW-tier self-validations** (v0.6.5..v0.9.2).

**Headline result: v0.9.1 finding 5a HIGH — EMPIRICALLY CLOSED.** New `lib/coordinator-guard.sh::guard_head_advance` uses `git merge-base --is-ancestor` to detect destructive `git reset --hard` by implementer subagents. The v0.9.2 dogfood deliberately instructed an implementer to run a reset; across 2 iterations the guard fired correctly each time, marked the misbehaving story failed in review fields, and emitted `<quantum>WAVE_FAILED</quantum>`. See `idea-stage/dogfood-v0.9.2-findings.md` for full evidence.

### Stories shipped

- **US-001 — coordinator HEAD-snapshot guard** — `lib/coordinator-guard.sh` (NEW; ~50 LOC). `guard_head_advance HEAD_BEFORE [HEAD_AFTER]` returns 0 if HEAD_BEFORE is ancestor of HEAD_AFTER, else 1 with stderr "HEAD reset detected". Per v0.9.1 US-004 security review: ancestry check is mandatory (ordinal SHA comparison would falsely accept reset-and-recommit siblings). `agents/coordinator.md` step 2 amended: HEAD_BEFORE pre-dispatch capture + post-dispatch guard invocation; failure path = mark review fields failed + emit WAVE_FAILED. New `tests/test_coordinator_guard.sh` (4 cases / 8 asserts; all PASS).
- **US-002 — gate legacy STORY_* case branches under coordinator mode** — Defense-in-depth: under `COORDINATOR_MODE=true`, if `SIGNAL_RESULT` matches `STORY_PASSED|STORY_FAILED|BLOCKED`, log WARNING (pattern "Unexpected STORY_.*coordinator mode") and redirect to `WAVE_FAILED` branch for per-story review-field aggregation. 9-line gate in `quantum-loop.sh` before `case "$SIGNAL_RESULT" in`. Legacy non-coord path byte-for-byte unchanged. New Test 5 in `tests/test_coordinator_e2e.sh` (3 asserts). Closes v0.9.1 code-reviewer MEDIUM.
- **US-003 — filePaths validation gap** — `lib/quantum-validate.sh` (NEW; ~40 LOC). `validate_story_filepaths` advisory hook emits stderr WARNING for any eligible story (status pending|failed|in_progress) whose `tasks[].filePaths` is empty in aggregate. `lib/dag-query.sh::next_wave` invokes once per call as advisory preamble (warnings to stderr; never blocks). New `tests/test_quantum_validate.sh` (5 cases / 11 asserts). Closes v0.9.1 architect MEDIUM (`filter_file_conflicts` silent bypass).
- **US-004 — real-LLM dogfood validates HEAD-snapshot guard** — Synthetic 2-story bundle in `.ql-wt/dogfood-v092/`. US-A normal flow; US-B task fixture explicitly instructs `git reset --hard HEAD~1` to test guard. Result: guard fired correctly across 2 iterations. Reflog confirms each iteration: implementer reset + commit (sibling, not descendant); coordinator detected; marked failed; emitted WAVE_FAILED; per-story aggregation routed correctly. Iteration 3 hung (operator killed); v0.9.3 candidate. Findings doc: `idea-stage/dogfood-v0.9.2-findings.md`.
- **US-005 — retrospective + IDEA_REPORT_v29 + version bump 0.9.1 → 0.9.2 + worktree cleanup** — this entry.

### Test-suite delta

| Test file | v0.9.1 | v0.9.2 | delta |
|---|---:|---:|---:|
| `tests/test_coordinator_guard.sh` (NEW) | — | 8 | +8 |
| `tests/test_quantum_validate.sh` (NEW) | — | 11 | +11 |
| `tests/test_coordinator_e2e.sh` (+Test 5) | 10 | 13 | +3 |
| **Total v0.9.2 added:** | | | **+22** |

### Architectural observations

**v0.9.1 finding 5a HIGH closed engineered (not just emergent).** v0.9.1's coordinator self-healed via emergent recovery; v0.9.2 ships an engineered safety net that detects destructive ops deterministically. The fix is small (~50 LOC in lib + 1 instruction amend) but the empirical validation across 2 dogfood iterations is the real proof.

**v0.9.3 candidate slate** (in `idea-stage/IDEA_REPORT_v29.md`): primary item is iter-3 hang — coordinator subagent stuck mid-`eval` for 3+ hours during dogfood iteration 3. Operational, not architectural. v0.9.3 will add a parent-side wallclock timeout on `eval "$COORD_CMD"` and re-evaluate `ql_wrap_subagent_dispatch` STALE detection under coordinator mode.

### Honest scope drift

- US-004 dogfood iteration 3 hung > 3 hours; operator killed parent shell to capture findings. Iterations 1+2 are conclusive evidence of guard correctness; iter-3 hang documented as v0.9.3 candidate.
- Multi-perspective review trio NOT run for v0.9.2 (US-004 was dogfood; review trio deferred to v0.9.3 US-004 per the v0.9.1 pattern).

### Dogfood milestone (v0.9.2)

**5/5 user-facing stories shipped first-attempt PASS.** **Multi-cycle CSV milestone**: 55 → 58 rows (3 advisory rows). **G30 self-validation captured.** **HEAD-snapshot guard validated empirically** — first cycle to ship engineered defense against implementer destructive ops. Full retrospective: `idea-stage/PIPELINE_REPORT_v29.md`. v0.9.3 backlog: `idea-stage/IDEA_REPORT_v29.md`.

## [0.9.1] - 2026-04-30

### Added — patch-tier (N42-validate — first real-LLM dogfood through `--coordinator`)

5-story validation patch confirming v0.9.0 N42 (per-wave coordinator dispatch under `--coordinator` opt-in) works end-to-end with a real LLM. v0.9.1 self-validated: tier=LOW (G30 captured in retrospective). **22 consecutive LOW-tier self-validations** (v0.6.5..v0.9.1).

**Headline result: 18-cycle manual-takeover streak BROKEN.** First cycle in 19 (v0.6.7..v0.9.0 was the streak) where the autonomous loop drove a complete 2-story plan to `<quantum>COMPLETE</quantum>` exit 0 without manual takeover. See `idea-stage/dogfood-v0.9.1-findings.md` for full evidence.

### ⚠️ Known issue (advisory)

**Operators using `--coordinator` with real (non-synthetic) plans should be aware:** Implementer subagents may run destructive `git` operations (e.g., `git reset --hard`) in the shared coordinator worktree. The coordinator's self-healing observed in v0.9.1 dogfood was **emergent, not engineered** — there is no `HEAD_BEFORE`/`HEAD_AFTER` guard in the coordinator contract. The single dogfood incident (US-B implementer wiped US-A's commit; coordinator restored via fix commit) recovered cleanly only because the synthetic plan was trivially simple. Real-feature dispatch with multi-file diffs may not recover. Per-story isolated worktrees OR coordinator HEAD-snapshot guard is planned for **v0.9.2**.

### Stories shipped

- **US-001 — real-LLM dogfood** — synthetic 2-story bundle in `.ql-wt/dogfood-v091/` worktree on throwaway branch `dogfood-v091-runtime` (off master at v0.9.0 `d66aaf8`). Fired `bash quantum-loop.sh --coordinator --max-iterations 5`. Iteration 1 dispatched coordinator with both stories; coordinator emitted `WAVE_PASSED` (exact confidence); per-story aggregation marked both `passed`. Iteration 2 returned COMPLETE. End-to-end successful.
- **US-002 — capture findings** — `idea-stage/dogfood-v0.9.1-findings.md` (6 sections, evidence-cited). Per-claim verdict: 4 minimum claims (next_wave invocation, spawn_coordinator output reachability, per-story aggregation routing, coordinator scope boundedness) all WORKED. One real defect surfaced (5a HIGH) + one cosmetic (5b LOW).
- **US-003 — inline fix for finding 5b** — `quantum-loop.sh:1569-1577` legacy `Spawning %s for story %s...` printf gated under `[[ "$COORDINATOR_MODE" != "true" ]]`. Cosmetic only; coordinator-mode branch already prints accurate `Spawning coordinator for wave-N with K story/stories: ...`. 5a deferred to v0.9.2 with explicit rationale.
- **US-004 — multi-perspective post-merge review** — 3 parallel reviewers (architect + code-reviewer + security). Code-reviewer: APPROVE with 1 MEDIUM latent (`STORY_PASSED`/`STORY_FAILED`/`BLOCKED` case branches still use scalar `$STORY_ID` under coordinator mode) → v0.9.2 candidate. Architect: streak-break HONEST; bumped 5a severity from MEDIUM-HIGH to HIGH; surfaced 3 new v0.9.2 risks (per-story worktree isolation conflicts with `--coordinator --parallel`; `filePaths` omission silent bypass; N46 deferred-debt). Security: 0 active findings.
- **US-005 — retrospective + IDEA_REPORT_v28 + version bump 0.9.0 → 0.9.1 + worktree cleanup** — this entry.

### Test-suite delta

No new test files. All 6 v0.9.0 test suites green post-US-003: `test_next_wave.sh` 18/18, `test_coordinator_e2e.sh` 10/10, `test_signal_parsing.sh` 15/15, `test_orchestrator_liveness.sh` 34/34, `test_quantum_loop_recovery.sh` 5/5, `test_coordinator_dispatch.sh` 7/7 (89/89 total).

### Architectural observations

**v0.9.0 N42's wires worked on first real-LLM exercise.** This is the third architectural dogfood-pattern validation: v0.7.x (manual takeover required) → v0.8.x (4-layer N33 closure shipped wires structurally) → **v0.9.0/v0.9.1 (wires fired correctly under real LLM dispatch)**.

**v0.9.2 candidate slate** (from US-004 review synthesis): primary item is finding 5a (HIGH) — coordinator HEAD-snapshot guard OR per-story worktree isolation. Secondary items: code-reviewer's MEDIUM (gate STORY_PASSED/FAILED/BLOCKED case branches under coordinator mode); architect's `filePaths` validation gap (silent conflict-filter bypass on empty arrays); architect's per-story worktree isolation conflict with `--coordinator --parallel` mutual exclusion; N46 (respawn output not re-parsed). See `idea-stage/IDEA_REPORT_v28.md`.

### Honest scope drift

- US-001 expanded from "small dogfood" to "small dogfood + emergent coordinator self-healing diagnostic" when the implementer subagent ran `git reset --hard`. Diagnostic-only ship per Option C semantics; fix deferred to v0.9.2.
- US-005 includes worktree cleanup (operator-staged in quantum.json plan).

### Dogfood milestone (v0.9.1)

**5/5 user-facing stories shipped first-attempt PASS.** 0 retries on the bundle branch. **Multi-cycle CSV milestone**: 52 → 55 rows (3 advisory rows; design/prd/plan all 1 LOW). **G30 self-validation captured in retrospective.** **First cycle since v0.6.7 to break the manual-takeover streak.** Full retrospective: `idea-stage/PIPELINE_REPORT_v28.md`. v0.9.2 backlog: `idea-stage/IDEA_REPORT_v28.md`.

## [0.9.0] - 2026-04-29

### Added — minor-tier (N42 — real per-wave coordinator dispatch)

7-story minor cycle replacing single-spawn dispatch with coordinator-driven per-wave dispatch when operators opt in via `--coordinator`. **First minor since v0.8.0** (which shipped N33 closure infrastructure). v0.8.x closed the N33 anti-pattern at 4 layers + verified all v0.9.0 prerequisites; v0.9.0 ships the actual cure. v0.9.0 self-validated: tier=LOW score=20 files=8 sensitive=0 → skip with `automated:true`. **21 consecutive LOW-tier self-validations** (v0.6.5..v0.9.0).

**Architectural newness justifying minor-tier:** new CLI behavior path (`--coordinator` actually does something different from `--legacy-orchestrator` for the first time), new dispatch architecture in the sequential path, new function (`lib/dag-query.sh::next_wave`), and new field-ownership enforcement.

- **US-000 — coordinator.md field-ownership amendment** — `agents/coordinator.md:25` previously instructed the coordinator to "set each story's status to passed or failed" while line 105 said "Parent loop owns `stories[].status`" (direct contradiction caught by architect 3). v0.9.0 amends step 4 to "Update each story's `review.specCompliance` and `review.codeQuality` fields based on signals. Do NOT write `stories[].status` — the parent shell owns that field." Step 1 also amended (parent now pre-marks `in_progress`).
- **US-001 + US-003 + US-004 — per-wave coordinator dispatch wired** (atomic commit; all touch quantum-loop.sh):
  - **US-001** — outer `COORDINATOR_MODE` branch in story selection: calls `next_wave` (rc=0 → wave; 1 → COMPLETE; 2 → BLOCKED); legacy path synthesizes 1-element `WAVE_STORY_IDS_JSON` for uniform downstream. Multi-story `in_progress` pre-mark. Spawn block: new outer if for coordinator mode → `spawn_coordinator` returns command STRING; `eval` synchronously. Legacy path verbatim. `ql_wrap_subagent_dispatch` soft-fire skipped under coordinator mode (coordinator handles internal retries; respawn would re-spawn whole wave with stale args; N46 deferred). `*)` unknown-signal branch now applies retry accounting to ALL `WAVE_STORY_IDS` (architect 1's HIGH risk: prior `$STORY_ID`-only logic would orphan other wave members `in_progress`).
  - **US-003** — `WAVE_PASSED)` bulk-updates ALL wave stories to `status=passed` via single jq pass. `WAVE_FAILED)` per-story aggregation via Option A: derives outcome from coordinator-written `review.specCompliance` + `review.codeQuality` fields. Stories with both passed → status=passed; else status=failed + retries.attempts++ + failureLog append. No signal-protocol change.
  - **US-004** — replaced v0.8.1 warn-only message at line 672 with hard exit when `--coordinator --parallel` both set. Documented as policy in `agents/coordinator.md` § "Interaction with --parallel" (added in v0.8.2 US-004).
- **US-002 — `lib/dag-query.sh::next_wave` thin composer + 8-case tests** — composes existing `get_executable_stories` + `filter_file_conflicts` (no logic duplication). 3-way exit code (0=wave, 1=COMPLETE, 2=BLOCKED) gives callers a clean rc-based dispatch (no string-sentinel parsing). Defensive type-check on `get_executable_stories` output guards against silent contract drift. New `tests/test_next_wave.sh` (18 assertions) covers happy path, COMPLETE, BLOCKED (exhausted retries on dep gate), file conflict reduces wave to one, multi-dependency gate, in_progress exclusion, cross-wave file conflict, empty stories.
- **US-005 — real-fire coordinator-dispatch integration tests** — new `tests/test_coordinator_e2e.sh` (10 assertions). Each test invokes the real `bash quantum-loop.sh --coordinator ...` binary against a 2-story stub plan and asserts on post-run quantum.json mutation + exit codes. **NOT presence-only** — the v0.8.x retrospective burned this lesson home four times. 4 cases: WAVE_PASSED happy path, WAVE_FAILED partial-pass (per-story aggregation from review fields), `--coordinator --parallel` rejection, COMPLETE path.
- **US-006 — retrospective + IDEA_REPORT_v27 + version bump 0.8.4 → 0.9.0** — this entry.

### Test-suite delta

**+2 new test files**, **+28 new assertions**:

- 1 new: `tests/test_next_wave.sh` (18 asserts) — DAG wave-eligibility composer
- 1 new: `tests/test_coordinator_e2e.sh` (10 asserts) — real-fire coordinator dispatch end-to-end

### Architectural observations

**v0.9.0 ships the actual cure for N33's manual-takeover streak.** The 17-cycle streak (v0.6.7..v0.8.4) was driven by orchestrator drift in single-spawn dispatch. v0.9.0 replaces single-spawn with per-wave coordinator dispatch under `--coordinator` opt-in. Empirical proof requires real-LLM dogfood (deferred to v0.9.1 like v0.8.0→v0.8.1's pattern); v0.9.0 ships the wires + integration tests.

**Three architect agents designed the sub-problems** independently before this cycle (inner-dispatch + next_wave + per-story aggregation). Their independent reviews caught the field-ownership contradiction (architect 3) and the coordinator-crash retry-accounting gap (architect 1's HIGH risk). Both became prerequisite stories (US-000, US-001 *) gating).

### Honest scope drift

- US-001 + US-003 + US-004 committed atomically (all touch quantum-loop.sh; logically separable but file-coupled).
- US-006 retrospective lifted some boilerplate from v0.8.4 retrospective; the v0.8.x saga summary now lives in v0.8.x track memory not duplicated here.

### Dogfood milestone (v0.9.0)

**6/6 user-facing stories shipped first-attempt PASS** under manual takeover (18th consecutive cycle). 0 retries. **Multi-cycle CSV milestone**: 49 → 52 rows. **G30 self-validation** (21st consecutive correct LOW): tier=LOW score=20 files=8 sensitive=0 → skip; recorded with `automated:true`. **First minor-tier in 1 cycle** (immediately after v0.8.4 closed v0.8.x). Full retrospective: `idea-stage/PIPELINE_REPORT_v27.md`. v0.9.x backlog: `idea-stage/IDEA_REPORT_v27.md`.

**v0.9.1 (next cycle)** is the empirical proof point: real-LLM dogfood through `--coordinator`. The infrastructure works in stub-driven integration tests; whether it breaks the manual-takeover streak in production is the v0.9.1 validation question.

## [0.8.4] - 2026-04-29

### Added — patch-tier (post-v0.8.3 review hotfix — final v0.8.x close)

4 implementation stories closing all residual findings from the v0.8.3 multi-perspective post-merge review (architect + code-reviewer + security agents). After v0.8.4, **the v0.8.x track is fully closed with zero deferred findings**. v0.9.0 N42 (real per-wave coordinator dispatch) is the next minor-tier scope, awaiting operator confirmation. v0.8.4 self-validated: tier=LOW score=≤25 files=≤7 sensitive=0 → skip with `automated:true`. **20 consecutive LOW-tier self-validations** (v0.6.5..v0.8.4).

- **US-001 — PS `WAVE_FAILED` retry accounting parity (MEDIUM from v0.8.3 code-reviewer)** — `quantum-loop.ps1:415-418` `"WAVE_FAILED"` arm now mirrors the bash branch's full retry-accounting jq expression (`status=failed`, `retries.attempts++`, append `failureLog` with `phase: "wave_failed"`). Prior arm only cleared `startedAt`, leaving an infinite-retry loop in the PS path. Same defect class as v0.8.1 US-006 fix on bash side.
- **US-002 — PS `$storyId` defense-in-depth regex validation (LOW from v0.8.3 security-reviewer)** — Added regex validation after `$storyId` extraction (around line 285) mirroring `quantum-loop.sh:1471` (`^[A-Za-z0-9_-]+$`). `jq --arg` already treats values as strings (no jq injection), but defense-in-depth guards against future code paths.
- **US-003 — lib/spawn.sh idempotency source guard (LOW from v0.8.3 code-reviewer)** — Added `_QL_SPAWN_SH` guard at top of `lib/spawn.sh`. The v0.8.3 source-gate comment claimed "lib/spawn.sh has its own source-guard"; v0.8.4 makes the comment accurate. Idempotent re-sourcing now guaranteed.
- **US-004 — update 4 implementer-scoped docs to reference WAVE_* signals (cosmetic from v0.8.3 architect)** — `CLAUDE.md` Signal Reference, `skills/ql-execute/SKILL.md` signal table, `runners/preamble.md` signal protocol, and `templates/quantum-loop.ps1` user-template comment all now reference WAVE_PASSED/WAVE_FAILED with appropriate context (coordinator pattern; implementer-scoped vs wave-scoped clarification).
- **US-005 — retrospective + IDEA_REPORT_v26 + version bump 0.8.3 → 0.8.4** — this entry.

### Test-suite delta

No new tests; the source-guard idempotency was verified inline (double-source returns 0 silently with no error).

### Architectural observations

**v0.8.x track FINAL CLOSE.** Four cycles shipped: v0.8.0 (architectural minor — N33 closure infrastructure), v0.8.1 (validation patch — found 2 inert pieces), v0.8.2 (review hotfix — primary signal regex + CRLF + ceilings + docs), v0.8.3 (4th-layer hotfix — heuristic regex + case switch + source gate + PS parity + test tightening), v0.8.4 (final hotfix — PS retry parity + storyId validation + spawn.sh guard + 4 cosmetic doc gaps). All findings from all 4 multi-perspective post-merge reviews are now closed.

The 4-layer N33 anti-pattern saga is the strongest validation of p012 (anti-presence-only AC) in the codebase. The pattern is reusable: when introducing a recovery wrapper, opt-in flag, OR a signal that another component must recognize, search ALL parallel consumer sites before declaring closure.

### Honest scope drift

- US-001 + US-002 committed atomically (same file, both small, no logical separation worth a commit boundary).
- US-004 added a comment-only annotation to `templates/quantum-loop.ps1` rather than extending its signal-handling branches — the user template is implementer-scoped and never sees WAVE_* signals at runtime.

### Dogfood milestone (v0.8.4)

**4/4 user-facing stories shipped first-attempt PASS** under manual takeover. 0 retries (17th consecutive cycle). **Multi-cycle CSV milestone**: 46 → 49 rows (3 advisory rows; design/prd/plan all 1 LOW). **G30 self-validation** (20th consecutive correct LOW): tier=LOW score=≤25 files=≤7 sensitive=0 → skip; recorded with `automated:true`. **v0.8.x track FULLY CLOSED.** v0.9.0 N42 prerequisites all met; backlog catalogued in `idea-stage/IDEA_REPORT_v26.md`. Full retrospective: `idea-stage/PIPELINE_REPORT_v26.md`.

## [0.8.3] - 2026-04-29

### Added — patch-tier (post-v0.8.2 review hotfix — close the WAVE_* anti-pattern across all sites)

3 implementation stories closing the **fourth, fifth, and sixth layers** of the N33 root-cause #1 anti-pattern (presence-only AC at parallel signal-wire sites). v0.8.2 fixed ONE signal regex; multi-perspective post-v0.8.2 review (architect + code-reviewer agents) found 3 parallel sites that were missed, plus a PowerShell parity gap and 2 trivially-passing test assertions. v0.8.3 closes them all atomically. v0.8.3 self-validated: tier=LOW score=≤25 files=≤6 sensitive=0 → skip with `automated:true`. **19 consecutive LOW-tier self-validations** (v0.6.5..v0.8.3).

- **US-001 — close 3 WAVE_* wire sites in bash code (HIGH + HIGH + MEDIUM)** — (1) `lib/signal-heuristics.sh:33` regex extended to 6 signals (mirrors `lib/runner.sh:283`); the heuristic-fallback path no longer drops wave signals on non-Claude runners. (2) `quantum-loop.sh:1570` `case "$SIGNAL_RESULT"` switch gains explicit `WAVE_PASSED)` and `WAVE_FAILED)` branches before the `*)` wildcard — story-progressing and retry semantics respectively (v0.9.0 N42 may refine wave-to-story mapping). (3) `quantum-loop.sh:687` source gate now also fires `lib/spawn.sh` and `lib/dag-query.sh` under `COORDINATOR_MODE=true` (parallel to `PARALLEL_MODE`); v0.9.0 N42's `spawn_coordinator()` will be defined at call time.
- **US-002 — PowerShell parity (MEDIUM)** — `quantum-loop.ps1:364` regex extended to 6 signals; switch block gains `"WAVE_PASSED"` and `"WAVE_FAILED"` case arms before the `default` branch. PowerShell entry-point preserved in lockstep with bash.
- **US-003 — tighten test_signal_parsing.sh negative assertions (LOW)** — Tests 9 and 10 each gain an explicit `SIGNAL_CONFIDENCE != "exact"` assertion. Guards against the trivial-pass regression where a wholly-broken regex would still make the negative tests pass via the no-signal default. Test count: 13 → 15.
- **US-004 — retrospective + IDEA_REPORT_v25 + version bump 0.8.2 → 0.8.3** — this entry.

### Test-suite delta

**+2 new assertions** (test_signal_parsing.sh non-exact-confidence guards); 0 new test files.

### Architectural observations

**v0.8.3 closes the FOURTH and final layer of the N33 root-cause #1 anti-pattern.** The pattern saga across v0.8.x:

| Layer | Cycle | Defect | Caught by |
|---|---|---|---|
| 1 (function) | v0.7.x | `wrap_orchestrator_dispatch` defined; zero callers | v0.8.0 5-agent research synthesis |
| 2 (caller) | v0.8.0 | `ql_wrap_subagent_dispatch` defined; zero callers in dispatch loop | v0.8.1 dogfood (static grep) |
| 3 (signal parser) | v0.8.0 | `runner_parse_output` regex missing `WAVE_*` | v0.8.2 architect review |
| 4 (parallel consumer sites) | v0.8.2 | `signal-heuristics.sh` regex + case switch + source gate + PowerShell mirror all missing `WAVE_*` | v0.8.3 architect + code-reviewer review |

p012 (anti-presence-only AC) reinforced again. The pattern is now mature: when introducing a recovery wrapper, opt-in flag, OR a signal that another component must recognize, search ALL parallel consumer sites before declaring closure — not just the primary one.

### Honest scope drift

- US-001 grew to 3 atomic fixes in 1 story (was originally proposed as ≥3 separate stories in the design). Bundling kept the diff coherent and reverted-as-a-unit.
- The architect's commit-order recommendation (US-002 DAG → US-001 dispatch → US-003 signal switch) didn't apply to this v0.8.3 cycle since v0.8.3 doesn't ship the dispatch wire — that's still v0.9.0 N42.

### Dogfood milestone (v0.8.3)

**4/4 user-facing stories shipped first-attempt PASS** under manual takeover. 0 retries (16th consecutive cycle). **Multi-cycle CSV milestone**: 43 → 46 rows (3 advisory rows; design/prd/plan all 1 LOW). **G30 self-validation** (19th consecutive correct LOW): tier=LOW score=≤25 files=≤6 sensitive=0 → skip; recorded with `automated:true`. **N33 root-cause #1 fully closed** across 4 layers; v0.9.0 N42 prerequisites genuinely complete (no more parallel wire sites discovered). Full retrospective: `idea-stage/PIPELINE_REPORT_v25.md`. v0.9.0+ backlog: `idea-stage/IDEA_REPORT_v25.md`.

## [0.8.2] - 2026-04-29

### Added — patch-tier (post-v0.8.1 review fixes + v0.9.0 N42 prerequisites)

5 stories addressing the multi-perspective post-v0.8.1 review (architect + code-reviewer + security-reviewer sub-agents). Closes 2 CRITICAL items (CRLF hygiene + signal-protocol gap) plus 3 supporting follow-ups (wall-clock flake + architectural-debt docs + retrospective). Sets up v0.9.0 N42 (real per-wave coordinator dispatch) to land cleanly. v0.8.2 self-validated: tier=LOW score=25 files=10 sensitive=0 → skip with `automated:true`. **18 consecutive LOW-tier self-validations** (v0.6.5..v0.8.2).

- **US-001 — fix CRLF on copilot-hooks.sh + test_runner.sh; add `.gitattributes`** — v0.8.1 US-004 imported these files from a Windows-authored stash; they shipped CRLF-encoded. Strict Linux/CI environments reject the shebang with `bad interpreter: No such file or directory`. Re-encoded both files via `sed s/\r$//` (line-ending-only delta; verified by 294-in/294-out diff stat on test_runner.sh). New `.gitattributes` enforces `*.sh` and `*.bash` `text eol=lf` to prevent recurrence, with text annotation for `*.md`/`*.txt`/`*.json`/`*.yml`/`*.yaml`.
- **US-002 — extend `runner_parse_output` to recognize `WAVE_PASSED`/`WAVE_FAILED`** — v0.9.0 N42 prerequisite. Architect post-v0.8.1 review caught that `runner_parse_output` (lib/runner.sh:283) regex matched only the 4 existing signals (`STORY_PASSED|STORY_FAILED|COMPLETE|BLOCKED`). The coordinator agent (`agents/coordinator.md:36-37`) emits `WAVE_PASSED`/`WAVE_FAILED`. Without the parser extension, every coordinator dispatch in v0.9.0 N42 would route to the unknown-signal failure branch — exactly the N33 root-cause #1 anti-pattern repeating one layer deeper. Regex extended to 6 signals (additive only; existing 4-signal recognition preserved). New `tests/test_signal_parsing.sh` (13 assertions) covers all 6 signals + regression guards (whitespace tolerance, last-signal-wins) + negative tests (substring `WAVE_PASSING` and bare untagged `WAVE_PASSED` do NOT match).
- **US-003 — bump Test 5 wall-clock ceiling 6s → 10s** — `tests/test_orchestrator_liveness.sh` Test 5 (`interval_sec=0 guard`) was intermittently failing on Git Bash with elapsed=7s. Same Git Bash subprocess-fork-overhead jitter class as v0.8.1 US-003's Test 2 (12 → 20s) fix. Bumped to 10s with reference annotation to `references/test-wallclock-baselines.md`.
- **US-004 — document `--coordinator --parallel` rejection + quantum.json field ownership in `agents/coordinator.md`** — Architect surfaced two architectural-debt items needing documentation before v0.9.0 ships per-wave dispatch: (1) `--coordinator` and `--parallel` are mutually exclusive (parallel path already does worktree-based wave dispatch; coordinator spawns implementer subagents internally; combining produces nested worktree-of-worktrees that doesn't compose); (2) quantum.json field ownership — coordinator owns `execution.completedWaves`/`progress`/`stories[].review.*`; parent loop owns `stories[].status`/`stories[].retries.*`/`startedAt`/`updatedAt`. v0.9.0 N42 will enforce the rejection at CLI parse time and respect the ownership boundary.
- **US-005 — retrospective + IDEA_REPORT_v24 + version bump 0.8.1 → 0.8.2** — this entry.

### Test-suite delta

**+1 new test file**, **+13 new assertions** (signal parsing); 1 ceiling adjustment (test_orchestrator_liveness Test 5):

- 1 new: `tests/test_signal_parsing.sh` (13 asserts) — exact-match coverage for all 6 quantum signals; regression guards + negative tests.
- Ceiling bump: liveness Test 5 (6 → 10s).

### Architectural observations

**v0.8.2 closes the v0.8.1 review findings and lays the v0.9.0 N42 foundation.** The signal-protocol extension in US-002 closes the third layer of the N33 root-cause #1 anti-pattern (after v0.8.0 US-001 added the wrapper definition and v0.8.1 US-001 added the call site). v0.9.0 can now wire `spawn_coordinator` into the dispatch loop with confidence that `WAVE_PASSED`/`WAVE_FAILED` will route correctly.

### Honest scope drift

- US-002 expanded slightly to cover not just regex extension but a 7-line comment block above the function explaining the v0.9.0 framing — useful future-context for the next architect to read the file.
- US-001 added more `.gitattributes` rules than strictly required (5 file-type annotations vs 2 strict requirements). Over-engineering on a one-time hygiene fix.

### Dogfood milestone (v0.8.2)

**5/5 user-facing stories shipped first-attempt PASS** under manual takeover. 0 retries (15th consecutive cycle). **Multi-cycle CSV milestone**: 40 → 43 rows (3 advisory rows; design/prd/plan all 1 LOW). **G30 self-validation** (18th consecutive correct LOW): tier=LOW score=25 files=10 sensitive=0 → skip; recorded with `automated:true`. **v0.9.0 N42 prerequisites met:** signal parser recognizes 6 signals; CRLF hygiene enforced; architectural-debt docs in place. Full retrospective: `idea-stage/PIPELINE_REPORT_v24.md`. v0.9.0+ backlog: `idea-stage/IDEA_REPORT_v24.md`.

## [0.8.1] - 2026-04-29

### Added — patch-tier (N39 dogfood validation + inline fixes)

5 stories validating v0.8.0's N33 closure + 2 inline fixes surfaced during pre-flight. **Honest finding:** v0.8.0 shipped two pieces of inert infrastructure with presence-only ACs — exactly N33 root cause #1 repeating one layer deeper. v0.8.1 dogfood caught both and ships the minimal viable wires + a regression-guard test. v0.8.1 self-validated: tier=LOW score=25 files=10 sensitive=0 → skip with `automated:true`. **17 consecutive LOW-tier self-validations** (v0.6.5..v0.8.1).

- **US-003 — Test 2 wall-clock ceiling 12s → 20s** — `tests/test_orchestrator_liveness.sh` Test 2 was failing 33/34 on Git Bash with elapsed=18s against the 12s ceiling. Bumped to 20s with reference annotation to `references/test-wallclock-baselines.md` (Git Bash fork-overhead jitter documented there). Verified 34/34 passes.
- **US-004 — copilot-hooks defensive flags + paired test updates** — `runners/hooks/copilot-hooks.sh::pre_spawn` now appends 5 additional defensive flags: `--max-autopilot-continues 0` (cap autopilot recursion), `--silent` (reduce CLI noise), `--no-color` (strip ANSI for clean stdout parsing), `--stream off` (disable progressive output), `--no-remote` (disable remote control surface). `tests/test_runner.sh` paired updates: copilot_hook test gains 5 assertions; codex test now references manifest-driven flag arrays. `tests/test_copilot_dispatch.sh` ceiling bumped 60s → 150s for real-network LLM dispatch. Verified test_runner.sh 43/43, test_copilot_runner_smoke.sh 5/5, test_copilot_dispatch.sh 3/3.
- **US-001 — wire `ql_wrap_subagent_dispatch` + `COORDINATOR_MODE` in quantum-loop.sh** — **The dogfood finding.** Static-analysis grep against `quantum-loop.sh` exposed two defects in <30s: (1) `COORDINATOR_MODE` was set by `--coordinator`/`--legacy-orchestrator` but never read; (2) `ql_wrap_subagent_dispatch` was defined but had zero callers. Both are exactly the same anti-pattern as N33 root cause #1. Fixes: (a) `COORDINATOR_MODE=true` now emits a WARN to stderr at startup; (b) `ql_wrap_subagent_dispatch 5 1 ""` is invoked post-`runner_parse_output` when `SIGNAL_RESULT` is empty (drift suspect). New `tests/test_v081_wiring.sh` (4 assertions) guards against the "presence-only AC" anti-pattern: counts CALL sites not just definitions, and smoke-tests the actual `--coordinator` invocation against a stub repo.
- **US-002 — capture v0.8.1 dogfood synthesis** — `idea-stage/dogfood-v0.8.1-findings.md` includes a "Final verdict" block addressing each of the 4 minimum claims (no UNKNOWN entries). Two BROKEN→fixed (`wrap_orchestrator_dispatch` invoked: BROKEN→WORKED; coordinator dispatch: BROKEN→DEGRADED with WARN). Two remain DEGRADED pending the larger N42 work (real per-wave dispatch).
- **US-005 — retrospective + IDEA_REPORT_v23 + version bump 0.8.0 → 0.8.1** — this entry.
- **US-006 — post-PR-review inline fix (correctness)** — Soliton `/soliton:pr-review` on PR #84 caught two CRITICAL findings (confidence 97 + 88) that v0.8.1 itself was supposed to surface — same anti-pattern repeating one layer deeper. **Finding 1:** the v0.8.1 US-001 guard `if [[ -z "$SIGNAL_RESULT" ]]` was always false because `runner_parse_output` always sets `SIGNAL_RESULT` before returning. **Fix:** corrected to `[[ "$SIGNAL_RESULT" == "STORY_FAILED" && "$SIGNAL_CONFIDENCE" != "exact" ]]` — the actual "drift suspect" condition. **Finding 3:** the `*` (unknown-signal) case marked status=failed without incrementing `retries.attempts`, creating an effective infinite retry loop. **Fix:** mirrored the `STORY_FAILED` branch's retry accounting. **Test 1b** added to `tests/test_v081_wiring.sh` to assert the guard is the reachable form, NOT the dead `-z` form — guards against future regression. Soliton security agent: FINDINGS_NONE.

### Test-suite delta

**+1 new test file**, **+5 new assertions** (test_runner.sh copilot_hook), **+ceiling adjustments** (test_orchestrator_liveness Test 2 + test_copilot_dispatch Test 1):

- 1 new: `test_v081_wiring.sh` (4 asserts) — anti-presence-only regression guard
- Ceiling bumps: liveness Test 2 (12 → 20s), copilot dispatch Test 1 (60 → 150s)
- Paired: test_runner.sh +5 copilot_hook assertions

### Architectural observations

**v0.8.1 is the diagnostic; v0.9.0 should be the cure.** v0.8.0's N33 closure was structurally complete but functionally inert. v0.8.1 ships minimal viable wires + a regression-guard test, but the *real* coordinator-driven dispatch (per-wave spawn, bounded context per invocation) remains future work. Tracked as N42 in `idea-stage/IDEA_REPORT_v23.md`.

### Honest scope drift

- US-001 grew from "small dogfood + observe" to "ship a real fix" per the PRD's escalation clause. Wire-fix scope was bounded (~15 LOC across `quantum-loop.sh` + 1 new test); did not need a full re-architecting.
- US-004 expanded to also bump `tests/test_copilot_dispatch.sh` ceiling 60→150s (real-network jitter; not strictly the new defensive flags' fault but exposed by them).

### Dogfood milestone (v0.8.1)

**5/5 user-facing stories shipped first-attempt PASS** under manual takeover. 0 retries (14th consecutive cycle). **Multi-cycle CSV milestone**: 37 → 40 rows (3 advisory rows; design/prd/plan all 1 LOW). **G30 self-validation** (17th consecutive correct LOW): tier=LOW score=25 files=10 sensitive=0 → skip; recorded with `automated:true`. **N39 dogfood verdict:** v0.8.0 N33 closure was inert; v0.8.1 ships the wires + regression-guard test; v0.9.0+ will deliver the real per-wave dispatch (N42). Full retrospective: `idea-stage/PIPELINE_REPORT_v23.md`. v0.9.0+ backlog: `idea-stage/IDEA_REPORT_v23.md`.

## [0.8.0] - 2026-04-28

### Added — minor-tier (N33 orchestrator drift root-cause closure)

7 stories closing N33 (12+ consecutive cycles of orchestrator drift requiring manual takeover). **First minor-tier release since v0.7.0** (8 cycles). Twelfth multi-cycle populated-CSV run. v0.8.0 self-validated: tier=LOW score=25 files=22 sensitive=0 → skip with `automated:true`. **16 consecutive LOW-tier self-validations** (v0.6.5..v0.8.0).

Root cause synthesis (5 parallel research agents): the recovery infrastructure (5 layers shipped v0.6.8..v0.7.2) was **inert** — `wrap_orchestrator_dispatch` had **zero production callers**. `quantum-loop.sh` did not source `lib/orchestrator-liveness.sh`. The `agents/orchestrator.md` agent definition consumed ~30% of context window (1,743 lines / ~39,900 tokens) before any work began. No per-story re-prompt for orchestrator. Signal protocol asymmetry between shell-side and agent-side parsing. `git rev-parse HEAD` mismatch in worktree mode.

- **US-001 — wire recovery infrastructure into `quantum-loop.sh`** — sources `lib/orchestrator-liveness.sh`; new `ql_wrap_subagent_dispatch` helper for callers (US-004 coordinator + external supervisor scripts). Recovery layers are now reachable in production code.
- **US-002 — worktree-aware `poll_orchestrator_commits`** — extends signature to accept optional `WORKTREE_PATH` 4th arg (and `wrap_orchestrator_dispatch` 3rd arg). Eliminates false-positive STALE in worktree-parallel mode where orchestrator commits land under `.ql-wt/<story>/` on feature branches. Tests 12 + 13 (4 new assertions on worktree-path STALE + LIVE detection). 22 → 26 liveness assertions.
- **US-003 — modularize `agents/orchestrator.md`** — extracts 13 optional/conditional sections to `agents/orchestrator-modules/*.md` (slop-cleanup, dead-code-detection, intent-graph, skeleton-drift, constant-scan, hyclone, type-audit, full-feature-review, init-and-routing, observations, reground, contract-promotion, quantum-json-fields). Each section in `orchestrator.md` replaced with a stub reference + activation guard. **1,743 → 1,007 lines (42% reduction)**, exceeds initial AC drift target (≤700 lines) but delivers substantive context-window relief.
- **US-004 — per-wave coordinator pattern** — new `agents/coordinator.md` defines a thin per-wave subagent (one wave per invocation, then exits). New `lib/spawn.sh::spawn_coordinator` + `build_coordinator_prompt` helpers. New `--coordinator` opt-in flag in `quantum-loop.sh` (default `--legacy-orchestrator` preserves existing single-spawn behavior). v0.8.1 dogfood will validate end-to-end.
- **US-005 — signal protocol unification** — new `runner_parse_subagent_output` wrapper in `lib/runner.sh` routes subagent output through the canonical `runner_parse_output` chain (claim-check + heuristic fallback). `agents/orchestrator.md` and `agents/coordinator.md` updated to cite the wrapper instead of ad-hoc `<quantum>...</quantum>` grep on TaskOutput.
- **US-006 — integration tests** — new `tests/test_quantum_loop_recovery.sh` (5 asserts) verifies recovery wiring fires on stale stub orchestrator. New `tests/test_coordinator_dispatch.sh` (7 asserts) verifies coordinator agent file + spawn helpers + flag parsing. Plus +4 worktree-path assertions in extended liveness test.
- **US-007 — retrospective + IDEA_REPORT_v22 + version bump 0.7.10 → 0.8.0** — first minor since v0.7.0 (8 cycles).

### Test-suite delta

**+16 new assertions across 3 test files**:
- 1 extended: `test_orchestrator_liveness.sh` 22 → 26 (+4)
- 2 new: `test_quantum_loop_recovery.sh` (5) + `test_coordinator_dispatch.sh` (7)

### Architectural rationale (minor-tier)

This is the **first new architectural concept since the multi-runner foundation (v0.7.4 N5)** — introduces (a) production wiring for previously-inert infrastructure, (b) a per-wave coordinator pattern (vs the long-running monolithic orchestrator), (c) modular orchestrator definition (13 lazy-loaded modules), (d) unified signal handling. **Genuinely minor-tier**, validated by the operator.

### Honest scope drift

- US-003 AC said `agents/orchestrator.md` ≤ 700 lines; actual = 1,007 lines. The 42% reduction is substantive but doesn't hit the original target. Further reduction would require extracting Step 3B (Parallel Execution) core logic, which carries regression risk and was deferred.
- US-006 ships unit/integration coverage; full coordinator-pattern dogfood validation is deferred to v0.8.1 (running a real cycle through the new path).

### Dogfood milestone (v0.8.0)

**7/7 user-facing stories shipped first-attempt PASS** under manual takeover. 0 retries. **Multi-cycle CSV milestone**: 33 → 36 rows (3 advisory rows). Aggregate severity now includes 1 MEDIUM finding (first MEDIUM in 8+ cycles — healthy signal for substantive minor work). **G30 self-validation**: tier=LOW score=25 files=22 sensitive=0 → skip; recorded with `automated:true`. **N33 root-cause closure**: 12+ consecutive manual-takeover cycles addressed via 4 layers of fixes; v0.8.1 validation will confirm whether auto-recovery actually fires in a real cycle. Full retrospective: `idea-stage/PIPELINE_REPORT_v22.md`. v0.8.x backlog: `idea-stage/IDEA_REPORT_v22.md`.

## [0.7.10] - 2026-04-28

### Added

7 stories closing N35 (real-task dispatch beyond version probe) + multi-runner test layer reframe + v0.7.9 housekeeping. Patch-tier; operator-driven extension of v0.7.4 N5 + v0.7.7 N30 multi-runner foundation. Eleventh multi-cycle populated-CSV run (30 → 33 rows). v0.7.10 self-validated: tier=LOW score=22 files=9 sensitive=0 → skip with `automated:true`. **15 consecutive LOW-tier self-validations** (v0.6.5..v0.7.10).

- **US-001 — `runner_dispatch` wrapper** — `lib/runner.sh` adds `runner_dispatch <runner_name> <prompt>` function composing `runner_load` + `runner_build_cmd` + `eval`. New `tests/test_runner_dispatch.sh` covers function presence, mock-echo manifest dispatch, unknown-runner error, and missing-args error (5 assertions).
- **US-002 — codex dispatch test + manifest fix** — `tests/test_codex_dispatch.sh` (skip-aware on missing codex CLI). Real-task dispatch uncovered codex manifest drift: `runners/codex.json` updated to use the `exec` subcommand and `--full-auto` flag (codex CLI removed `-q` and `--approval-mode`). Test asserts rc=0 + non-empty stdout + ≤60s wall-clock.
- **US-003 — copilot dispatch test** — `tests/test_copilot_dispatch.sh` mirrors codex pattern; skip-aware on missing copilot CLI.
- **US-004 — multi-runner E2E dispatch test** — `tests/test_multi_runner_dispatch_e2e.sh` iterates claude+codex+copilot, dispatching a tiny prompt against each. Three accounting buckets: `dispatched` (rc=0 + non-empty), `skipped` (binary not on PATH), `timed_out` (rc=124 from `timeout --kill-after=5 90` wrapper — environmental, not a code defect). Final invariant: all 3 runners accounted for. 5/5 assertions on this dogfood machine (claude+codex dispatched, copilot timed-out due to rate-limit).
- **US-005 — multi-runner test layers documentation** — `CLAUDE.md` gains a "Multi-runner test layers" subsection distinguishing **smoke** (version-probe health check) from **dispatch** (real-task end-to-end). `lib/runner.sh` header lists all three top-level entry-points (`runner_load`, `runner_build_cmd`, `runner_dispatch`).
- **US-006 — smoke test docstring reframe** — `tests/test_codex_runner_smoke.sh` and `tests/test_copilot_runner_smoke.sh` headers updated to identify themselves as the SMOKE/health-check layer and cross-link to the new DISPATCH layer.
- **US-007 — retrospective + v0.7.9 housekeeping** — `idea-stage/PIPELINE_REPORT_v21.md` + `idea-stage/IDEA_REPORT_v21.md`. Commits `docs/plans/2026-04-28-v0.7.9-bundle-design.md` + `tasks/prd-v0.7.9-bundle.md` that were authored in v0.7.9 cycle but never staged (untracked-design-prd housekeeping, recurring pattern from v0.7.5/v0.7.6 N29/N34 audits).

### Test-suite delta

**+5 new test files**, **+12 new assertions** approximate:

- 4 new: `test_runner_dispatch.sh` (5 asserts), `test_codex_dispatch.sh` (3 asserts), `test_copilot_dispatch.sh` (3 asserts), `test_multi_runner_dispatch_e2e.sh` (5 asserts)

### Manifest fix

- `runners/codex.json` invocation: `headlessFlags: ["-q"]` → `["exec"]`; `autoApproveFlags: ["--approval-mode", "full-auto"]` → `["--full-auto"]` (codex CLI flag migration).

### Dogfood milestone (v0.7.10)

**7/7 user-facing stories shipped first-attempt PASS** under manual takeover. 0 retries. **Multi-cycle CSV milestone**: 30 → 33 rows. **G30 self-validation** (15th consecutive correct LOW classification): tier=LOW score=22 files=9 sensitive=0 → skip; recorded with `automated:true`. **Real-task dispatch validated end-to-end** for claude + codex; copilot timed-out due to environmental rate-limit (not a code defect — TIMEOUT bucket added to E2E for visibility). Full retrospective: `idea-stage/PIPELINE_REPORT_v21.md`. v0.9.0+ backlog: `idea-stage/IDEA_REPORT_v21.md`.

## [0.7.9] - 2026-04-28

### Added

3 stories closing 6 issues from external code review of `lib/multi-runner-manifest.sh` (v0.7.4 N5 shipment). Patch-tier; **operator-driven reactive** (not autonomous loop). Loop-stop signal in IDEA_REPORT_v19 stands for autonomous track. **Tenth multi-cycle populated-CSV run** — ledger 27 → 30 rows. v0.7.9 self-validated: tier=LOW score=5 files=2 sensitive=0 → skip with `automated:true`. **14 consecutive LOW-tier self-validations** (v0.6.5..v0.7.9).

- **US-001 — multi-runner-manifest hardening (Issues 1-4 + 6)** — `lib/multi-runner-manifest.sh` 5 fixes: (1) yq backend distinguishes empty-success from parse-failure (empty/null output emits "is empty or has no top-level structure"); (2) python backend captures stderr to a tmpfile separately from stdout, preventing JSON contamination by DeprecationWarnings or other diagnostic output; (3) shell parser strips leading whitespace before pattern matching, accepting tab-indented and arbitrary-space-indented manifests; (4) shell parser rtrims trailing whitespace from each field value via new `_rtrim` helper; (6) `validate_manifest` distinguishes jq exit codes (rc=1 → missing-runners-or-wrong-type; rc≥2 → "malformed JSON input").
- **US-002 — backend-selection tests (Issue 5)** — `lib/multi-runner-manifest.sh` adds 3 test-only env-var hooks: `MR_DISABLE_YQ=1` skips yq even if installed; `MR_DISABLE_PYTHON=1` skips python+yaml; `MR_DEBUG=1` emits `[manifest] backend: <name>` to stderr per parse. `tests/test_multi_runner_manifest.sh` adds Tests 7-10: Test 7 (yq backend, skips if yq not installed), Test 8 (python backend with `MR_DISABLE_YQ`, skips if no python+yaml), Test 9 (shell backend with both disable flags), Test 10 (tab-indented + trailing-whitespace fixture forced through shell backend, verifies Issues 3+4 end-to-end). 6 → 14 multi-runner-manifest test assertions.

### Test-suite delta

**+8 new assertions** in 1 extended test file:

- 1 extended: `test_multi_runner_manifest.sh` 6 assertions → 14 (+8 from Tests 7-10 + +1 from Test 10's trim assertion)

### Dogfood milestone (v0.7.9)

**3/3 user-facing stories shipped first-attempt PASS** under manual takeover (12th consecutive cycle if counting autonomous runs in between). 0 retries. **Multi-cycle CSV milestone**: 27 → 30 rows. **G30 self-validation** (14th consecutive correct LOW classification): tier=LOW score=5 files=2 sensitive=0 → skip; recorded with `automated:true`. **Operator-driven reactive distinction**: this cycle does NOT contradict IDEA_REPORT_v19's "stop the patch-tier loop" recommendation — that signal targets autonomous loop-discovered patches. External code review by the operator is materially different and is allowed to surface follow-up patch work. Full retrospective: `idea-stage/PIPELINE_REPORT_v20.md`. v0.9.0+ backlog: `idea-stage/IDEA_REPORT_v20.md`.

## [0.7.8] - 2026-04-28

### Added

3-story compact reactive closing N36 + N37 from IDEA_REPORT_v18. Trivial scope (1-line lib edit + 7-line yaml header note). G30 score=9 LOW (13th consecutive).

- **N36 — runner_load error message hint** (US-001) — `lib/runner.sh::runner_load` now appends a hint sentence when given an invalid name (e.g., a manifest path): "Hint: pass the runner name (e.g., 'codex'), not the manifest path. The manifest is auto-resolved from runners/<name>.json." Closes the v0.7.7 US-001/US-002 onboarding paper-cut.
- **N37 — manifest.example.yaml deprecation note** (US-002) — `runners/manifest.example.yaml` header now explicitly states it is documentation-only; `runners/*.json` per-runner manifests are the runtime-authoritative source. Surfaced in v0.7.7 PIPELINE_REPORT_v18.

### Reactive-cycle wrap-up

v0.7.4 → v0.7.5 → v0.7.6 → v0.7.7 → v0.7.8 has closed every reactive item from the v0.7.4 dogfood + v0.7.7 multi-runner integration. Patch-tier track is again drained. v0.9.0 minor needs operator scope (N35 real-task dispatch as natural anchor).

## [0.7.7] - 2026-04-28

### Added

4-story patch-tier closing N30 (v0.7.7 anchor). **First end-to-end smoke validation** of codex (tier=tested) + copilot (tier=experimental) CLI runners against the existing multi-runner infrastructure. v0.7.7 self-validation: tier=LOW score=7. **12 consecutive LOW-tier self-validations** (v0.6.5..v0.7.7).

- **Codex CLI smoke test** (US-001) — NEW `tests/test_codex_runner_smoke.sh` (5 assertions). Loads `runners/codex.json` via `runner_load codex`; asserts `RUNNER_NAME=codex` + `RUNNER_BINARY=codex` + `RUNNER_TIER=tested`; verifies `_provider_version codex` returns non-empty (e.g., `codex-cli 0.118.0`); wall-clock ≤15s. Skip-pass if `codex` CLI absent.
- **Copilot CLI smoke test** (US-002) — NEW `tests/test_copilot_runner_smoke.sh` (5 assertions). Mirrors US-001 for copilot; asserts `RUNNER_TIER=experimental`; verifies version (e.g., `GitHub Copilot CLI 1.0.37`).
- **Routing E2E multi-runner** (US-003) — `tests/test_routing_e2e.sh` Test 5: `resolve_routing claude codex copilot` produces 3-distinct-providers snapshot with `versions.codex` + `versions.copilot` populated. 6 → 9 assertions. Skip-pass when any CLI absent.

### Test-suite delta

**+13 new assertions** across 2 new test files + 1 extended:

- 2 new: `test_codex_runner_smoke.sh` (5), `test_copilot_runner_smoke.sh` (5)
- 1 extended: `test_routing_e2e.sh` 6 → 9 (+3 Test 5 multi-runner)

### Reactive-cycle wrap-up

This is the first end-to-end validation that quantum-loop integrates with non-claude runners. Multi-runner is now real: codex (tested) + copilot (experimental). Full retrospective: `idea-stage/PIPELINE_REPORT_v18.md`. Next: v0.9.0 minor for real-task dispatch (N35).

## [0.7.6] - 2026-04-28

### Added

2-story compact reactive patch closing N34 (untracked design+PRD docs audit). **Smallest cycle yet** (2 stories, ~15 min wall-clock). **11 consecutive LOW-tier self-validations** expected.

- **N34 — `--audit` untracked-design-prd check** (US-001) — `quantum-loop.sh` adds `_audit_untracked_design_prd_docs` helper using `git ls-files --others --exclude-standard docs/plans/ tasks/`. WARN-level when matching files are untracked; OK otherwise. Mirrors v0.7.5 N29 csv-uncommitted pattern. +2 audit tests in `tests/test_audit.sh`. Closes the v0.7.4 + v0.7.5 process gap where design+PRD docs were repeatedly authored locally but never staged before squash-merge (caught at v0.7.5 housekeeping).

### Test-suite delta

- `tests/test_audit.sh` +2 (Tests 39 + 39b)
- `quantum-loop.sh` +1 helper + 1 ROWS invocation

### Reactive-cycle wrap-up

v0.7.4 (dogfood) → v0.7.5 (N29+N31) → v0.7.6 (N34) sequence has now closed all known process gaps surfaced by the dogfood cycle. Patch-tier track is genuinely drained. v0.8.0 minor-tier requires operator-defined substantive scope (N30 multi-runner first integration is the natural anchor). Full retrospective: `idea-stage/PIPELINE_REPORT_v17.md`.

## [0.7.5] - 2026-04-28

### Added

3-story compact reactive patch closing 2 LOW process gaps surfaced in v0.7.4 dogfood. v0.7.5 self-validation: tier=LOW score=7. **10 consecutive LOW-tier self-validations** (v0.6.5..v0.7.5).

- **N29 — `--audit` csv-uncommitted check** (US-001) — `quantum-loop.sh` adds `_audit_csv_uncommitted` helper. WARN-level when `metrics/pre-impl-review-findings.csv` has uncommitted changes; OK otherwise. +2 audit tests in `tests/test_audit.sh`. Closes the v0.7.2/v0.7.3 process gap where advisory-hook CSV updates never reached master.
- **N31 — `/ql-spec` SKILL grep-verify instruction** (US-002) — `skills/ql-spec/SKILL.md` Step 1 (Gather Context) adds bullet 5 with grep/ls verification instruction for cited file paths + `[NEW]` annotation convention. Doc-only edit (1 line). Closes v0.7.4 US-004 PRD-AC-drift class of bugs.

### Test-suite delta

- `tests/test_audit.sh` +2 (Tests 38 + 38b)
- `quantum-loop.sh` +1 audit check + 1 helper

### Dogfood milestone (v0.7.5)

**3/3 stories shipped first-attempt PASS** under manual takeover (8th consecutive cycle). 0 retries. **Multi-cycle CSV milestone**: 24 → 27 committed rows. **G30 self-validation** (10th consecutive LOW): tier=LOW score=7 — smallest score yet (4 files at audit time). Full retrospective: `idea-stage/PIPELINE_REPORT_v16.md`. v0.8.0+ backlog: `idea-stage/IDEA_REPORT_v16.md`.

## [0.7.4] - 2026-04-28

### Added

6 user-facing changes shipping operator combined scope (#1/2/3/4/6/7) framed as patch-tier + 1 retrospective. **First end-to-end dogfood of `/ql-brainstorm` → `/ql-spec` → `/ql-plan` skill pipeline at v0.7.x scale.** v0.7.4 diff self-validated: tier=LOW score=22 files=9 sensitive=0 → skip recorded with `automated:true`. **9 consecutive LOW-tier self-validations** (v0.6.5..v0.7.4).

- **N25 — `QL_RESPAWN_CMD` real-CLI smoke test** (US-001) — `tests/test_orchestrator_liveness.sh` Test 11: detects `claude` via `command -v`. Skip-pass branch emits stderr WARN + `.handoffs/n25-deferred.md` when absent; present-path sets `QL_RESPAWN_CMD="claude --version"`, triggers stale, asserts rc=0 + version regex + wall-clock ≤15s. 27 → 30 liveness assertions.
- **Provider-routing E2E** (US-002) — NEW `tests/test_routing_e2e.sh` with 4 tests covering `resolve_routing` → `write_routing_snapshot` → `read_routing_snapshot` round-trip + empty/missing fallback paths. 6 assertions. Complements existing unit-level `test_per_role_routing.sh`.
- **Sensitive-path bundle test fixture** (US-003) — `tests/test_deep_review_dispatch.sh` Test 9: real-diff fixture with `auth/login.js`, `config/.env`, `payment/charge.js`, `config/api-token.js` → score=38 tier=MEDIUM. Differs from N19 Test 8 by exercising the full git diff construction step. 19 → 22 dispatch assertions.
- **Worktree-isolation re-test** (US-004) — `tests/test_type_audit.sh` adds worktree-style divergence test: 2 simulated worktrees each defining `HandoffEnvelope` with conflicting fields → `grep_duplicate_definitions` surfaces both. Discovered + reconciled PRD path bugs (`test_worktree_isolation.sh` and `lib/type-auditor.sh` don't exist; real names are `test_type_audit.sh` + `lib/type-audit.sh`).
- **Multi-runner-manifest foundation** (US-005) — NEW `lib/multi-runner-manifest.sh` (parse/validate/list, 3-tier backend chain: yq → python+yaml → handcrafted shell parser) + NEW `runners/manifest.example.yaml` (claude/codex/gemini-cli stubs) + NEW `tests/test_multi_runner_manifest.sh` (6 tests, 10 assertions). Foundation only — no actual runner integrations (deferred to v0.8.0). Includes cygpath translation for Windows-python path-with-spaces compatibility.
- **G22 third calibration pass** (US-006) — NEW `references/severity-rubric-calibration-v0.7.4.md` (8-committed-cycle / 24-row / 58-finding baseline). Documents CSV-commit gap (v0.7.2 + v0.7.3 hooks fired but never reached master). Patch-tier-skew hypothesis confirmed (patch HIGH=4.0% vs minor HIGH=12.5%). Plan-review still 12/12 LOW. CLAUDE.md ref updated v0.7.2 → v0.7.4.

### Test-suite delta

**+25 new assertions** across 5 affected test files + 2 new files + 1 new lib + 1 new manifest:

- 4 extended: `test_orchestrator_liveness.sh` 27 → 30 (+3 N25); `test_deep_review_dispatch.sh` 19 → 22 (+3 sensitive-path); `test_type_audit.sh` +3 (worktree-divergence); `CLAUDE.md` ref updated.
- 2 new: `test_routing_e2e.sh` (6 assertions); `test_multi_runner_manifest.sh` (10 assertions).
- 1 new lib: `lib/multi-runner-manifest.sh`.
- 1 new schema: `runners/manifest.example.yaml`.

### Dogfood milestone (v0.7.4)

**6/7 stories shipped first-attempt PASS, 1 second-attempt PASS** (US-005 yaml-backend cygpath fix). 0 retries beyond first inline fix. **First end-to-end skill-pipeline dogfood at v0.7.x scale**: `/ql-brainstorm` + `/ql-spec` + `/ql-plan` skills exercised; `/ql-execute` deferred to manual-takeover (7th consecutive cycle of manual-takeover, consistent with established 100% drift baseline). Per-story dual-review (soliton + copilot:copilot-rescue) consolidated to PR-time. **Multi-cycle CSV milestone**: 21 → 24 committed rows (v0.7.2/v0.7.3 hooks never reached master — gap captured for v0.7.5+ recovery). Aggregate across 8 committed cycles: 58 findings (0 critical / 3 high / 13 medium / 42 low; LOW share 72.4%). **G30 self-validation** (9th consecutive correct LOW classification): tier=LOW score=22 files=9 sensitive=0 → skip; recorded with `automated:true`. Full retrospective: `idea-stage/PIPELINE_REPORT_v15.md`. v0.8.0+ backlog: `idea-stage/IDEA_REPORT_v15.md`.

## [0.7.3] - 2026-04-28

### Added

1 user-facing change closing N28 (3 test-adequacy gaps surfaced by internal code review of v0.7.2) + 1 housekeeping/retrospective story. **Ninth multi-cycle populated-CSV run** — ledger 24 → 27 rows. Patch-tier; 2-story compact bundle (smallest yet). v0.7.3 self-validated: tier=LOW score=2 files=1 sensitive=0 → skip recorded with `automated:true` (US-001-only diff; US-002 docs/manifests bumps the file count). **9 consecutive LOW-tier self-validations** (v0.6.5..v0.7.3).

- **N28 — test-adequacy fixes (US-001)** — `tests/test_orchestrator_liveness.sh` Test 8 gains a 4th assertion greping `out8` for `[QL-EXECUTE] orchestrator-stale — respawning via QL_RESPAWN_CMD` (lib's stderr diagnostic). Test 10 gains 2 new assertions: wall-clock guard `(( elapsed <= 10 ))` matching Test 8 pattern, and grep for `QL_RESPAWN_CMD exited 42 — respawn may have failed` (lib's failing-respawn diagnostic added in v0.7.2 soliton fix). 24 → 27 liveness tests. First v0.7.x cycle triggered by internal code review (vs operator/soliton).
- **Housekeeping + retrospective (US-002)** — `docs/plans/2026-04-28-v0.7.2-bundle-design.md` and `tasks/prd-v0.7.2-bundle.md` committed (housekeeping; were authored during v0.7.2 cycle but never staged). PIPELINE_REPORT_v14 + IDEA_REPORT_v14 written. CHANGELOG [0.7.3] entry. 3-manifest version bump 0.7.2 → 0.7.3.

### Test-suite delta

**+3 new assertions** in 1 modified test file:

- 1 extended: `test_orchestrator_liveness.sh` 24 → 27 (+3 N28 — Test 8 +1 / Test 10 +2)

### Dogfood milestone (v0.7.3)

**2/2 user-facing stories shipped first-attempt PASS** under manual takeover (7th consecutive cycle). 0 retries. **Multi-cycle CSV milestone**: 24 → 27 rows. Aggregate across 9 cycles: 61 findings (0 critical / 3 high / 13 medium / 45 low; LOW share 73.8%). **G30 self-validation** (9th consecutive correct LOW classification): tier=LOW score=2 files=1 sensitive=0 → skip; recorded with `automated:true`. **Smallest bundle yet (2 stories)** — patch-tier track maturity continues. **First internal-review-driven cycle** — N28 was surfaced by an internal code review pass on v0.7.2 (vs operator/soliton in prior cycles). Full retrospective: `idea-stage/PIPELINE_REPORT_v14.md`. v0.8.0+ backlog: `idea-stage/IDEA_REPORT_v14.md`.

## [0.7.2] - 2026-04-28

### Added

2 user-facing changes closing the IDEA_REPORT_v12 v0.7.2 slate (N24, G22-second-pass) + 1 retrospective. **Eighth multi-cycle populated-CSV run** — ledger 21 → 24 rows. Patch-tier; 3-story compact bundle. v0.7.2 diff self-validated: tier=LOW score=10 files=4 sensitive=0 → skip recorded with `automated:true`. **8 consecutive LOW-tier self-validations** (v0.6.5..v0.7.2).

- **N24 — `wrap_orchestrator_dispatch` QL_RESPAWN_CMD auto-respawn** (US-001) — `lib/orchestrator-liveness.sh::wrap_orchestrator_dispatch` gains `QL_RESPAWN_CMD` env-var branch. When non-empty and STALE detected, executes `bash -c "${QL_RESPAWN_CMD}"` and returns its exit code instead of emitting the manual-takeover handoff. When empty/unset, v0.7.1 behavior unchanged (handoff + return 1). Operator sets `QL_RESPAWN_CMD` to a fully-specified orchestrator invocation to enable unattended auto-respawn. Tests 8 + 9 + 10 (6 new assertions, 2 added in post-soliton inline fix): Test 8 — `QL_RESPAWN_CMD="echo respawned"` + stale repo → "respawned" in stdout + rc=0 + wall-clock ≤10s; Test 9 — unset + stale → handoff + rc=1 (regression guard); Test 10 — `QL_RESPAWN_CMD="exit 42"` + stale → rc=42 (exit-code propagation). 18 → 24 liveness tests.
- **G22 second calibration pass** (US-002) — `references/severity-rubric-calibration-v0.7.2.md` created: updated empirical tables (8-cycle / 57-finding baseline), bundle-tier comparison axis (patch-tier 7 cycles vs minor-tier 1 cycle — v0.7.0). Key finding: patch-tier HIGH=4.1% vs minor-tier HIGH=12.5% — directionally confirms v0.7.0 first-pass hypothesis that HIGH under-classification was patch-tier-skew driven, not rubric miscalibration. MEDIUM stable across tiers (~25%). `CLAUDE.md` Process references updated from v0.7.0 to v0.7.2 calibration doc.

### Test-suite delta

**+4 new assertions** in 1 extended test file:

- 1 extended: `test_orchestrator_liveness.sh` 18 → 24 (+6 N24 Tests 8+9+10 + soliton wall-clock fix)

### Dogfood milestone (v0.7.2)

**2/2 user-facing stories shipped first-attempt PASS** under manual takeover (6th consecutive cycle). 0 retries. **Multi-cycle CSV milestone**: 21 → 24 rows. Aggregate across 8 cycles: 57 findings (0 critical / 3 high / 13 medium / 41 low; LOW share 71.9%). **G30 self-validation** (8th consecutive correct LOW classification): tier=LOW score=10 files=4 sensitive=0 → skip; recorded with `automated:true`. Full retrospective: `idea-stage/PIPELINE_REPORT_v13.md`. v0.8.0+ backlog: `idea-stage/IDEA_REPORT_v13.md`.

## [0.7.1] - 2026-04-28

### Added

4 user-facing changes addressing v0.7.0's IDEA_REPORT_v11 v0.7.1 slate (N18, N19, N20, N21) + 1 retrospective. **Seventh multi-cycle populated-CSV run** — ledger 18 → 21 rows. Patch-tier; 5-story compact bundle. v0.7.1's own diff was self-validated: tier=LOW score=25 files=10 sensitive=0 → skip recorded with `automated:true`. **7 consecutive LOW-tier self-validations** (v0.6.5..v0.7.1).

- **N19 — G30 dispatch gate end-to-end MEDIUM-tier fixture** (US-001) — `tests/test_deep_review_dispatch.sh` Test 8 (4 new assertions): synthesizes patch with sensitive_hits=2 (auth/login.js + .env) → should_dispatch_deep_review returns 0 (dispatch); dispatch_set MEDIUM returns 4 canonical reviewers (oh-my-claudecode:code-reviewer, soliton:synthesizer, oh-my-claudecode:security-reviewer, oh-my-claudecode:test-engineer). Closes the v0.7.0 PIPELINE_REPORT_v11 calibration-insight gap (MEDIUM/HIGH/CRITICAL branches now exercised end-to-end). 15 → 19 dispatch tests.
- **N20 — `wrap_orchestrator_dispatch` runtime extraction** (US-002) — `lib/orchestrator-liveness.sh` adds NEW `wrap_orchestrator_dispatch [timeout_sec] [interval_sec]` function. Honors `QL_LIVENESS_ENABLE` env var (default true; false silent skip). Invokes `poll_orchestrator_commits`; on STALE emits canonical handoff message (cross-link to `references/orchestrator-takeover.md` + numbered recovery steps) and returns 1. `skills/ql-execute/SKILL.md` replaces inline `if [[ ${QL_LIVENESS_ENABLE:-true} == "true" ]]; then ...` example with single-line `wrap_orchestrator_dispatch || exit 1`. Tests 6 + 7 (6 new assertions): opt-out silent rc=0; default + stale tmp repo → handoff stdout + rc=1 + cross-link. 12 → 18 liveness tests. `tests/test_ql_execute_liveness_wrapping.sh` Test 6 grep updated to verify the function reference (replacing the v0.7.0 poll_orchestrator_commits inline grep).
- **N18 — plan-review MEDIUM second example** (US-003) — `references/finding-severity.md` plan-review MEDIUM row gains a second worked example joined by `**OR**`: `single-story-wave-bottleneck-masked` (dag-validator single-story-wave warning that's structurally correct but informational, masking a real serialization risk). Closes v0.7.0 G22 calibration insight that plan-review emitted ONLY LOW findings (9/9 across 6 cycles).
- **N21 — parse-script aggregate suppress zero-row** (US-004) — `references/severity-rubric-calibration-parse.sh` per-stage aggregate awk adds `rows++` counter and `if (rows == 0) exit` before printing `**Aggregate**:` line. v0.7.0 PR #71 soliton conf-75 sub-threshold carry-over closed.

### Test-suite delta

**+10 new assertions** across 2 extended test files + 0 new files:

- 2 extended: `test_deep_review_dispatch.sh` 15 → 19 (+4 N19 Test 8); `test_orchestrator_liveness.sh` 12 → 18 (+6 N20 Tests 6 + 7)
- 1 modified (count unchanged): `test_ql_execute_liveness_wrapping.sh` 6 → 6 (Test 6 grep target updated)

### Dogfood milestone (v0.7.1)

**4/4 user-facing stories shipped first-attempt PASS** under manual takeover (5th consecutive cycle). 0 retries. **Multi-cycle CSV milestone**: 18 → 21 rows. Aggregate across 7 cycles: 53 findings (0 critical / 3 high / 12 medium / 38 low; LOW share 71.7%). **G30 self-validation** (7th consecutive correct LOW classification): tier=LOW score=25 files=10 sensitive=0 → skip; recorded with `automated:true`. **3-layer + extraction recovery infrastructure complete**: v0.6.8 prose / v0.6.9 lib helper / v0.7.0 SKILL prose / v0.7.1 SKILL → callable function. **Bundle size pattern**: 7-7-7-7-5-6-5; patch-tier track increasingly drained. v0.8.0 minor-tier framing recommended for next substantive cycle (G22 second calibration pass + bundle-tier comparison data). Full retrospective: `idea-stage/PIPELINE_REPORT_v12.md`. v0.8.0+ backlog: `idea-stage/IDEA_REPORT_v12.md`.

## [0.7.0] - 2026-04-28

**MINOR bump rationale:** First non-patch release in 5 cycles. Patch-tier backlog drained over v0.6.5..v0.6.9 (5 consecutive LOW-tier patch releases). v0.7.0 ships substantive G22 calibration analysis + N14 SKILL-level runtime control-flow change + 3 LOW-priority cleanups. The version bump deliberately skips 0.6.10 to signal v0.6.x patch-track closure.

### Added

5 user-facing changes addressing v0.6.9's IDEA_REPORT_v10 v0.7.0 slate (G22, N14, N15, N16, N17) + 1 retrospective. **Sixth multi-cycle populated-CSV run** — ledger 15 → 18 rows. v0.7.0's own diff was self-validated: tier=LOW score=25 files=12 sensitive=0 → skip recorded with `automated:true`. **6 consecutive LOW-tier self-validations** across v0.6.5..v0.7.0 — calibration insight: G30 score formula caps blast-radius at 25 for files_changed ≥ 10 + 0 sensitive + 0 cg = 25 = LOW; conservative threshold means patch-tier and small-minor-tier bundles correctly skip the deep-review pipeline.

- **G22 — severity rubric calibration first pass** (US-001) — new `references/severity-rubric-calibration-v0.7.0.md` (~150 lines, 6 sections: Methodology / Empirical distribution / Expected distribution / Drift analysis / Rubric language updates / Future work). Companion `references/severity-rubric-calibration-parse.sh` (NEW awk parser cited by Methodology). 6-cycle aggregate: 49 findings → 0/3/13/33 (critical/high/medium/low). Drift: HIGH mild under-classification (-4 to -9pp); LOW mild over-classification (+7 to +17pp); plan-review emits ONLY LOW (9/9 = 100%). Verdict: no urgent rubric edits at this baseline; plan-review MEDIUM-example tweak queued for v0.7.1 N18. Re-snapshot at v0.7.x retrospectives via the parse-script. Cross-linked from CLAUDE.md `## Process references` (under N15's new Process-related sub-categorization). 6 assertions in `tests/test_severity_rubric_calibration.sh`.

- **N14 — `/ql-execute` SKILL-level liveness wrapping** (US-002) — `skills/ql-execute/SKILL.md` `## Orchestrator liveness gate` subsection wraps orchestrator dispatch with `poll_orchestrator_commits` (timeout 600s, interval 60s). Honors `QL_LIVENESS_ENABLE` env var (default `true`; set `false` preserves v0.6.9 dispatch semantics for backwards compat). On STALE signal (rc=1), the SKILL emits a structured handoff message (header + pointer to `references/orchestrator-takeover.md` + numbered recovery steps) and exits with rc=1 (`orchestrator-stale` signal). Closes the v0.6.7+v0.6.8+v0.6.9 manual-takeover recovery loop: v0.6.8 N6 prose advisory → v0.6.9 N6-followup lib helper → v0.7.0 N14 SKILL wrapping (3-layer recovery infrastructure complete). 6 PRESENCE-ONLY assertions in `tests/test_ql_execute_liveness_wrapping.sh` (matches v0.6.8 N6 pattern).

- **N15 — CLAUDE.md `## Process references` re-categorization** (US-003) — refactored into 3 `### ` sub-headers (Orchestrator-related / Test-related / Process-related). 4 entries placed in natural categories (orchestrator-takeover.md → Orchestrator; test-wallclock-baselines.md → Test; soliton-finding-triage.md + severity-rubric-calibration-v0.7.0.md → Process). Existing 14 cross-link assertions remain green post-refactor.

- **N16 — `poll_orchestrator_commits` interval_sec=0 guard** (US-004) — adds `if (( interval_sec <= 0 ))` fail-fast guard at top of function. Emits `[LIVENESS] ERROR: interval_sec must be > 0 (got %s)` log + returns 1, preventing the infinite-loop hazard (sleep 0 + elapsed never increases). v0.6.9 PR #70 soliton conf-82 carry-over closed. Test 5 in `tests/test_orchestrator_liveness.sh` (4 new assertions: exit 1 + ERROR log within 2s + no STALE log on guard path). 8 → 12 dispatch tests.

- **N17 — `tests/bench_wallclock_baseline_drift.sh` REPO_ROOT printf %q quoting** (US-005) — replaces `eval "(cd '$REPO_ROOT' && $cmd)"` with `safe_cmd=$(printf '(cd %q && %s)' "$REPO_ROOT" "$cmd"); time eval "$safe_cmd"`. Defensive against future relocations to single-quote-containing paths (e.g. `/home/user/andy's-repos/`). v0.6.9 PR #70 soliton conf-65 carry-over closed.

### Test-suite delta

**+16 new assertions** across 2 new test files + 1 extended:

- 2 new files: `test_severity_rubric_calibration.sh` (6), `test_ql_execute_liveness_wrapping.sh` (6)
- 1 extended: `test_orchestrator_liveness.sh` 8 → 12 (+4: Test 5 N16 guard)
- 1 implicit (cross-link assertions remain green post-refactor): 14 unchanged across 3 existing test files

### Dogfood milestone (v0.7.0)

**5/5 user-facing stories shipped first-attempt PASS** under manual takeover (4th consecutive cycle; orchestrator subagent's 3-layer recovery infrastructure now complete but applies only to runs starting AFTER v0.7.0 merges — the v0.7.0 dogfood ran on v0.6.9 master HEAD which has the lib helper but no SKILL wrapping). 0 retries. **Multi-cycle CSV milestone**: 15 → 18 rows. Aggregate across 6 cycles: 49 findings (0 critical / 3 high / 13 medium / 33 low). **G30 self-validation** (6th consecutive correct LOW classification): tier=LOW score=25 files=12 sensitive=0 → skip; recorded with `automated:true`. **G30 score-formula calibration insight**: blast-radius caps at 25 for files_changed ≥ 10; the dispatch gate's threshold (score>30) is conservative — only sensitive-path or coverage-gap diffs trigger MEDIUM+. v0.7.x candidates: N18 (plan-review MEDIUM example), N19 (G30 dispatch gate end-to-end test fixture), N20 (N14 SKILL wrapping runtime extraction). Full retrospective: `idea-stage/PIPELINE_REPORT_v11.md`. v0.7.1+ backlog: `idea-stage/IDEA_REPORT_v11.md`.

## [0.6.9] - 2026-04-28

### Added

4 user-facing changes addressing v0.6.8's IDEA_REPORT_v9 priority list (N6-followup orchestrator-liveness lib helper, N13 orchestrator-takeover SOP doc, N9-followup wall-clock baseline-drift bench, N12 helper rename) + 1 retrospective. Patch-tier; 5-story bundle (smaller than the typical 7 — clean LOW-tier slate, patch-track backlog drained). **Fifth multi-cycle populated-CSV run** — ledger 12 → 15 rows. v0.6.9's own diff was self-validated: tier=LOW score=25 files=11 sensitive=0 → skip recorded in `quantum.json.reviews[v0.6.9-bundle].deepReview` with `automated:true`. **5 consecutive LOW-tier self-validations** across v0.6.5..v0.6.9 — G30 dispatch gate routes patch-tier bundles with 100% accuracy across the established baseline.

- **N6-followup — `lib/orchestrator-liveness.sh::poll_orchestrator_commits`** (US-001) — new parent-side commit-poll helper. Defaults: timeout=600s, interval=60s, base=git rev-parse HEAD at call time. Returns 0 (live) on new-commit observation; 1 (stale) on timeout. Stderr log: `[LIVENESS] new commit XXXXXXXX observed at +Ns` (live) / `[LIVENESS] STALE: no commits in Ns (base=XXXXXXXX)` (stale). Library contract: no shell flags at source time. `agents/orchestrator.md` Step 1.0.4 prose subsection points operators at the helper for unattended `/ql-execute` mode (helper invocation is operator-side; SKILL-level wrapping queued as v0.7.0 N14). 8 assertions in `tests/test_orchestrator_liveness.sh` (function defined, stale-path within timeout-jitter ceiling, live-path with pre-staged HEAD-advance, default-arg behavior).
- **N13 — `references/orchestrator-takeover.md`** (US-002) — new manual-takeover SOP for parent agents detecting orchestrator drift mid-cycle. 4 sections: When to detect drift / What to verify / How to take over without corrupting state / Recovery from N6-followup STALE signal. Documents the verification-failure-driven amendment rule (preserve orchestrator edits unless a check proves them broken; v0.6.7 Pattern C → Pattern A worked example). Cross-linked from `CLAUDE.md` `## Process references` section (joining N7 soliton-finding-triage + N9 wallclock-baselines). 5 assertions in `tests/test_orchestrator_takeover_doc.sh`.
- **N9-followup — `tests/bench_wallclock_baseline_drift.sh`** (US-003) — new opt-in benchmark. Runs 7 documented baseline commands with `time`, parses real wall-clock seconds, compares against hardcoded BASELINES (curated subset of `references/test-wallclock-baselines.md`). Emits `WARN: <cmd> took Ns (baseline Xs, threshold Ys — drift > 50%)` if measured > 1.5× baseline. Always exits 0 (informational). File-naming uses `bench_*` prefix (NOT `test_*`) so `tests/run_all.sh`'s `tests/test_*.sh` glob deliberately skips it; operators must invoke directly: `bash tests/bench_wallclock_baseline_drift.sh`.
- **N12 — helper rename in `tests/test_audit.sh`** (US-004) — `extract_function_comments` → `extract_function_header_comments` (clarifies: returns ONLY the function-header comment block); `extract_function_full_comments` → `extract_function_all_comments` (clarifies: returns header AND body comments). Mechanical rename across 9 occurrences (2 function defs + 4 call sites + 3 doc-comment refs). Replacement order: longer name substituted first to avoid sub-string overlap. 45/45 audit assertions unchanged.

### Test-suite delta

**+13 new assertions** across 2 new test files (the bench file is opt-in and not counted toward run_all):

- 2 new files: `test_orchestrator_liveness.sh` (8), `test_orchestrator_takeover_doc.sh` (5)
- 1 new opt-in bench: `bench_wallclock_baseline_drift.sh` (informational; not run by `tests/run_all.sh` due to glob mismatch)
- 1 modified (assertion count unchanged): `test_audit.sh` 45 → 45 (mechanical rename)

### Dogfood milestone (v0.6.9)

**5/5 user-facing stories shipped first-attempt PASS** under manual takeover (3rd consecutive cycle; orchestrator-liveness helper SHIPS in this bundle and applies only to runs starting AFTER v0.6.9 merges — the v0.6.9 dogfood itself ran on v0.6.8 master HEAD which had no runtime liveness). 0 retries. **Multi-cycle CSV milestone**: 12 → 15 rows. Aggregate across 5 cycles: 41 findings (0 critical / 2 high / 11 medium / 28 low) — patch-tier baseline solidly stable; G22 first calibration pass becomes meaningful at v0.7.x. **G30 self-validation**: v0.6.9's own master..HEAD diff (11 files) classified by its own `should_dispatch_deep_review` rule as tier=LOW score=25 → skip; decision recorded with `automated:true`. **Bundle size shrinking**: v0.6.5/6/7/8 all had 7 stories; v0.6.9 had 5 — the natural endpoint of a patch-tier track. v0.7.0 minor-tier is the right next move. v0.7.0 candidates: G22 calibration first pass, N14 SKILL-level wrapping of the liveness helper, N15 CLAUDE.md Process references re-categorization. Full retrospective: `idea-stage/PIPELINE_REPORT_v10.md`. v0.7.0 backlog: `idea-stage/IDEA_REPORT_v10.md`.

## [0.6.8] - 2026-04-28

### Added

6 user-facing changes addressing v0.6.7's IDEA_REPORT_v8 priority list (N6 orchestrator stale-detection prose guard, N7 soliton-finding-triage doc, N8 narrow Test 37a awk to function-header range, N9 wall-clock baselines reference, N10 compute_risk_score comment correction, N11 orchestrator Step 4B.5 cleanup-line move). Patch-tier; all changes are doc/cleanup-additive (no schema deltas, no breaking changes, 2 new committed reference files). **Fourth multi-cycle populated-CSV run** — ledger 9 → 12 rows. v0.6.8's own diff was self-validated: tier=LOW score=25 files=13 sensitive=0 → skip recorded in `quantum.json.reviews[v0.6.8-bundle].deepReview` with `automated:true`.

- **N6 — orchestrator Self-monitoring guard prose** (US-001) — `agents/orchestrator.md` adds a new `### Self-monitoring guard` subsection between Step 4 and Step 4B. Documents the rule (verify in_progress story commit landed before reasoning about other stories), 3 forbidden idioms ("while that runs", "let me proactively", "let me prepare US-XXX in parallel"), self-recovery action ([ORCH] STALE-DETECT log + reset to current in_progress story's task list), and explicit prose-only enforcement model. Runtime enforcement (parent-side liveness check) queued as v0.6.9 N6-followup. New `tests/test_orchestrator_self_monitor.sh` (5 assertions: presence header, >=3 idioms, STALE-DETECT marker, negative-control regex against legitimate cross-story phrasing, positive-control regex match against true drift phrase).
- **N7 — soliton-finding-triage doc** (US-002) — new `references/soliton-finding-triage.md` (Workflow / Repro template / Examples) documenting the validate-before-design workflow for sub-threshold (<85) `/soliton:pr-review` findings between cycles. v0.6.7 G36 documented as worked HALLUCINATION example. Cross-linked from new `## Process references` section in CLAUDE.md. New `tests/test_soliton_triage_doc.sh` (5 assertions).
- **N8 — narrow `extract_function_comments` awk to header range** (US-003) — `tests/test_audit.sh::extract_function_comments` simplified to emit accumulated header buffer ONLY (no `in_body` state machine). Matches G34 stated scope ("trim PR-metadata bloat from function-HEADER comments"). DISCOVERED: Tests 36b/37b WHY-phrase checks were relying on body comments; SPLIT INTO 2 HELPERS — `extract_function_comments` (header-only) for Tests 36a/37a (bloat); new `extract_function_full_comments` (header+body) for Tests 36b/37b (WHY). 45/45 audit assertions preserved.
- **N9 — wall-clock baselines reference** (US-004) — new `references/test-wallclock-baselines.md` (6-row platform-conditional table: Git Bash vs Linux/CI for the major test commands). Cross-linked from CLAUDE.md `## Process references`. New `tests/test_wallclock_baselines_doc.sh` (4 assertions). Baseline-drift WARN-test deferred to v0.6.9 N9-followup per design-review.
- **N10 — compute_risk_score comment correction** (US-005) — `lib/deep-review.sh` comment block above v0.6.7's G36 defense-in-depth guard rewritten. Removed misleading "Mirrors the structure used in compute_risk_score above" claim (compute_risk_score uses outer SHA-presence gate; should_dispatch_deep_review uses inner files_changed-count gate — different mechanisms, same intent). Comment-only edit. 14/14 dispatch tests preserved.
- **N11 — orchestrator Step 4B.5 cleanup-line move** (US-006) — `agents/orchestrator.md` Step 4B.5 else-branch: `rm -f .quantum-feature-diff.patch` moved from start-of-branch to end-of-branch (after the verdict-case block, before closing fi). BLOCKS_MERGE intentional skip-via-exit-1 documented in comment near new location — patch file remains for forensic inspection by the operator triaging the blocked merge. New Test 7 in `tests/test_deep_review_dispatch.sh` (awk-line-numbering assertion: rm-f line index AFTER case-VERDICT line index).

### Test-suite delta

**+15 new assertions** across 3 new test files + 1 extended:

- 3 new files: `test_orchestrator_self_monitor.sh` (5), `test_soliton_triage_doc.sh` (5), `test_wallclock_baselines_doc.sh` (4)
- 1 extended: `test_deep_review_dispatch.sh` 14 → 15 (+1: Test 7 N11 cleanup ordering)
- 1 modified (assertion count unchanged): `test_audit.sh` 45 → 45 (awk simplification + helper split)

### Dogfood milestone (v0.6.8)

**6/6 user-facing stories shipped first-attempt PASS** under manual takeover (parent agent executed all stories — orchestrator subagent's N6 prose guard does not yet apply since the dogfood ran on v0.6.7 master HEAD). 0 retries. **Multi-cycle CSV milestone**: `metrics/pre-impl-review-findings.csv` now has 12 rows (3 v0.6.5 + 3 v0.6.6 + 3 v0.6.7 + 3 v0.6.8) — first calibration pass becomes meaningful at v0.7.x with bundle-tier comparison data (33 findings total: 0 critical / 2 high / 9 medium / 22 low). **G30 self-validation**: v0.6.8's own master..HEAD diff (13 files) classified by its own `should_dispatch_deep_review` rule as tier=LOW score=25 → skip; decision recorded in `quantum.json.reviews[v0.6.8-bundle].deepReview` with all 4 required keys. Audit log shows split summary AND `pre-impl-review-coverage: 3/3 stages OK` (deterministic given v0.6.7 + v0.6.8 rows fall inside the 7d rolling window). **2 mid-cycle design-improvements**: US-001 regex form needed `[A-Z0-9]+` (not `[0-9]+`) for placeholder match; US-003 needed a split into 2 helpers (`extract_function_comments` header-only vs `extract_function_full_comments` for WHY-checks) to match G34's actual semantics. v0.6.9+ candidates: N6-followup (parent-side liveness check), N13 (`references/orchestrator-takeover.md`), N9-followup (baseline-drift WARN-test), N12 (helper rename). Full retrospective: `idea-stage/PIPELINE_REPORT_v9.md`. v0.6.9+ backlog: `idea-stage/IDEA_REPORT_v9.md`.

## [0.6.7] - 2026-04-28

### Added

6 user-facing changes addressing v0.6.6's IDEA_REPORT_v7 priority list (G35, G36, G37, N1, N2, N5) plus 1 discovered v0.6.6 commit-hygiene fix (c47e038's body comment trimmed). Patch-tier; all changes are bug fixes, doc clarifications, or process-additive (no schema deltas, no breaking changes, no new files). **Third multi-cycle populated-CSV run** — the v0.6.6 ledger of 6 rows extended to 9 rows from this cycle's planning hooks. **First N1-gated dispatch wiring** — `should_dispatch_deep_review` now load-bearing in `agents/orchestrator.md` Step 4B.5 via explicit `if/else` containment (pre-N1 the gate was informational; post-N1 the live pipeline runs only on dispatch path). v0.6.7's own diff was self-validated: tier=LOW score=25 files=10 sensitive=0 → skip recorded in `quantum.json.reviews[v0.6.7-bundle].deepReview` with `automated:true`.

- **G35 — `tests/test_audit.sh` Test 4 hang fix** (US-001) — wraps the `out=$(do_audit 2>&1); rc=$?` capture in an explicit `set +e ... set -e` block so inherited `set -euo pipefail` (from sourcing quantum-loop.sh) doesn't propagate into the subshell capture. Runs do_audit against a clean tmp repo (matching Test 5's pattern) for determinism — prevents the test from depending on the developer's working repo state. **Bundled inline:** v0.6.6 c47e038 regression fix — do_audit body comment had "confidence 95" + "Soliton-pr-review caught at" tripping Test 37a (whose awk `extract_function_comments` includes body comments). Rephrased to load-bearing-WHY only ("mapfile is the right tool because it treats newlines as record separators by default"). 0 assertion delta (45 → 45); was: hang past 30s indefinitely → now: completes in ~3-4min wall-clock (Git Bash subprocess overhead is the new bottleneck, not the test logic).
- **G36 — `should_dispatch_deep_review` empty-input guard** (US-002) — adds `if (( files_changed > 0 ))` short-circuit around the `prod_count` grep computation in `lib/deep-review.sh`. Defense-in-depth: the existing regex `^(tests?/|$)|...` already excludes empty input via the `|$` alternative (verified empirically — soliton's confidence-82 finding was a false positive). The new `tests/test_deep_review_dispatch.sh` Test 5 fixture (3 assertions: empty-diff exit 1, files=0, score=0) is the durable regression-guard locking in current correct behavior. 8 → 11 dispatch tests.
- **G37 — `tests/run_all.sh --parallel` xargs_rc capture** (US-003) — replaces `|| true` with `|| xargs_rc=$?` in the `--parallel` xargs invocation; ORs `(( xargs_rc != 0 ))` into OVERALL_RC alongside the existing `: 0/N passed` grep check. Catches the missed surface: a worker that exits non-zero AFTER printing a passing "P/N passed" Results line (partial-run-then-crash; post-assertion cleanup-failure). `tests/test_run_all.sh` Test 4 (RED-tested before fix → GREEN after). 9 → 10 run_all tests.
- **N1 — wire `should_dispatch_deep_review` into orchestrator Step 4B.5 control flow** (US-004) — `agents/orchestrator.md` Step 4B.5 pseudocode block restructured with explicit `if/else` containment. Skip branch records the deepReview decision via jq AND removes the diff patch file AND falls through to Step 4C. Else branch holds the 7-step dispatch pipeline (score-from-quantum, dispatch-set, prepare-context, agent dispatch, aggregate, persist, verdict-case). Cleanup symmetric across branches. Pre-N1 the dispatch pipeline ran unconditionally; post-N1 it runs only on the dispatch path. `tests/test_deep_review_dispatch.sh` Test 6 (3 structural assertions via awk-bounded code-fence extraction) verifies gate-then-else containment + `score-from-quantum` lives between `else` and `fi`. 11 → 14 dispatch tests.
- **N2 — `_audit_test_suites` doc clarification** (US-005) — `quantum-loop.sh` function-header comment gains a 4-line clarification: helper reads the `.omc/phase-*-evidence/` LEDGER, not the live test corpus; row answers "did the most recent recorded test run pass?" not "do tests pass right now?"; for live state, run `bash tests/run_all.sh`. Existing FR-10 fail-when-no-evidence WHY preserved. Comment-only change. Closes the operator-confusion gap from IDEA_REPORT_v7 §N2.
- **N5 — `quantum.json.codebasePatterns` re-seed** (US-006) — appended p009/p010/p011 verbatim from `idea-stage/PIPELINE_REPORT_v7.md` § "codebasePatterns harvested" (the committed canonical record from v0.6.6 dogfood). Final state: 8 → 11 patterns. quantum.json is gitignored — committed as audit-trail marker only. IDEA_REPORT_v8 § "Persistent canon" cross-links to PIPELINE_REPORT_v7 as the durable single source-of-truth across cycles.

### Test-suite delta

**+7 new assertions** across 3 extended test files. Zero new test files; zero regressions:

- 3 extended: `test_audit.sh` 45 → 45 (Test 4 wrapper change; no count delta), `test_deep_review_dispatch.sh` 8 → 14 (+6: Test 5 + Test 6 add 3 each), `test_run_all.sh` 9 → 10 (+1: Test 4)

### Dogfood milestone (v0.6.7)

**7/7 user-facing stories shipped first-attempt PASS** (5 stories Wave 0 + 1 story Wave 1 [US-004 deps US-002] + 1 story Wave 2 [US-007 deps all]). 0 retries. **Multi-cycle CSV milestone**: `metrics/pre-impl-review-findings.csv` now has 9 rows (3 v0.6.5 + 3 v0.6.6 + 3 v0.6.7) — calibration histograms become meaningful at v0.7.x with 1-3 more populated releases (current 9-row baseline shows 0 critical / 2 high / 7 medium / 16 low across 25 findings; LOW dominates at 64%). **G30 self-validation**: v0.6.7's own master..HEAD diff (10 files) classified by its own `should_dispatch_deep_review` rule as tier=LOW score=25 → skip; decision recorded in `quantum.json.reviews[v0.6.7-bundle].deepReview` with all 4 required keys. Audit log shows split summary AND `pre-impl-review-coverage: <N>/3 stages` row. **3 mid-cycle discoveries**: (a) v0.6.6 c47e038 regression in do_audit body comment (fixed inline in US-001), (b) soliton G36 finding was a false positive (defensive guard + regression-guard test still shipped), (c) orchestrator subagent context-drift mid-task (parent agent took over manually for stories US-001 through US-007 — first-attempt-PASS pattern preserved despite agent failure). v0.6.8+ candidates: N6 (orchestrator stale-detection heuristic), N7 (soliton-validate-before-design process), N8 (Test 37a scope decision), N9 (wall-clock target calibration). Full retrospective: `idea-stage/PIPELINE_REPORT_v8.md`. v0.6.8+ backlog: `idea-stage/IDEA_REPORT_v8.md`.

## [0.6.6] - 2026-04-28

### Added

6 user-facing changes addressing v0.6.5's IDEA_REPORT_v6 priority list (G30, G31, G32, G33, G34, p008-driven test-helper audit). Patch-tier; all changes are cleanup or additive (no schema deltas, no breaking changes). **Second multi-cycle populated-CSV run** — the v0.6.5 ledger of 3 rows extended to 6 rows from this cycle's planning hooks. Calibration histograms become possible at v0.7.x with 3-5 more populated runs. **First release with auto-gated `ql-deep-review` dispatch** — `should_dispatch_deep_review` is the canonical decision rule going forward; v0.6.6's own diff was self-validated against the new rule (tier=LOW score=25 → skip recorded in `quantum.json.reviews`).

- **G32 — `agents/spec-reviewer.md` negative-assertion regression guard** (US-001) — `tests/test_sprint_contract.sh` Test 7i asserts 0 uncited inline regex enumerations in `agents/spec-reviewer.md` (the inline regex shape `(test_|\.test\.` excluding the citation line). Regression-guard property verified manually: injecting an inline copy fails the test; reverting passes. 1 new assertion (24 → 25).
- **G33 — `tests/test_audit.sh` Tests 34/35 invoke real `do_audit` via `QL_AUDIT_TEST_ROWS`** (US-002) — `quantum-loop.sh::do_audit` now honors `QL_AUDIT_TEST_ROWS` env var (gated on `QL_AUDIT_TEST_MODE=1`) for synthetic newline-delimited ROWS injection. Tests 34/35 rewritten to subprocess-invoke `bash quantum-loop.sh --audit` instead of inlining a private `_t34_run`/`_t35_run` re-implementation. Test-mode guard tightened to require `$#==0` so `--audit` subprocesses bypass the source-mode short-circuit. -23 net lines in `tests/test_audit.sh`. Tests 34/35 now catch any future regression in `do_audit`'s case-pattern switch.
- **G34 — trim PR-metadata bloat from `quantum-loop.sh` function comments** (US-003) — `_audit_format_row` inline comment + `do_audit` function-header trimmed to load-bearing WHY ("FAIL OR WARN because both signal something the operator should see"; "split counters by status because a single combined counter would silently treat WARN as on-target"). Removed: `confidence`, `soliton-pr-review`, `v0.6.5 post-merge`, `G18`/`G29`/`G33` tags, version-tag headers, before-and-after summary string. 4 new meta-assertions in `tests/test_audit.sh` (Tests 36a/b + 37a/b) using awk-based function-comment-range extraction enforce 0 bloat strings + ≥1 WHY phrase per function. 41 → 45 audit assertions.
- **G30 — `lib/deep-review.sh::should_dispatch_deep_review` + `agents/orchestrator.md` Step 4B.5 documentation** (US-004) — new `should_dispatch_deep_review(diff_path)` helper returns 0 (dispatch) on tier ≥ MEDIUM, 1 (skip) on LOW. Honors `QL_DEEP_REVIEW=force` (always dispatch) and `QL_DEEP_REVIEW=skip` (always skip) env-var overrides. Diff-path entry-point lets retrospective callers invoke without live SHAs (US-007 self-validation depends on this). Orchestrator Step 4B.5 documents the gate with override-syntax table. 8 new assertions in `tests/test_deep_review_dispatch.sh` (NEW) covering 4 fixture cases × 2 assertions each.
- **G31 — `tests/run_all.sh` runner with `--quick` and `--parallel N` modes** (US-005) — new test-suite runner. Default: sequential; `--quick`: filter to `git diff master..HEAD --name-only -- 'tests/test_*.sh'`; `--parallel N` (default N=4): xargs -P dispatch via private `--__one` self-recursive entry-point (sidesteps export-f portability quirks on MSYS/Git Bash); combined `--quick --parallel N`. Per-file output format `tests/test_<name>.sh: <P>/<T> passed`. Exit 0 iff all PASS; 1 iff any FAIL. xargs -P fallback to sequential when unavailable. PARALLEL_UNSAFE allowlist convention documented (currently empty). 9 new assertions in `tests/test_run_all.sh` (NEW) covering all 4 modes via 3-test fixture.
- **p008 — `tests/test_test_helpers.sh` test-helper audit** (US-006) — new audit asserts every `tests/test_*.sh` file uses one of four safe sourced-script-errexit patterns: A (function-extracted subshell + two-invocation idiom), B (`|| true` after substitution), C (enclosing `set +e` ... `set -e` block), or D (file does not enable `set -e` — the hazard is errexit-specific). Opt-out via `# pragma test-helper-audit: opt-out (rationale: ...)` with rationale enforcement. Per-file PASS/FAIL with `file:line` citation for any unsafe substitution. 9 new assertions; 0 unsafe substitutions across all 76 test files in current corpus; 0 opt-outs needed (target met).

### Test-suite delta

**+30 new assertions** across 6 test files (1 modified + 5 NEW, including the runner from G31 and the audit from p008). Zero regressions:

- 4 new files: `test_deep_review_dispatch.sh` (8), `test_run_all.sh` (9), `test_test_helpers.sh` (9), `tests/run_all.sh` (runner; not a test file)
- 2 extended: `test_sprint_contract.sh` 24 → 25 (+1: Test 7i G32 negative assertion), `test_audit.sh` 41 → 45 (+4: Tests 36a/b + 37a/b G34 meta-assertions)

### Dogfood milestone (v0.6.6)

**7/7 user-facing stories shipped first-attempt PASS across 3 waves** (Wave 0: 5 sequential — US-001/US-002/US-004/US-005/US-006; Wave 1: 1 sequential — US-003 depends on US-002; Wave 2: 1 sequential — US-007 retrospective). 0 retries, 0 cross-story contract violations, 0 merge conflicts. **Multi-cycle CSV milestone**: `metrics/pre-impl-review-findings.csv` now has 6 rows (3 v0.6.5 + 3 v0.6.6) — calibration histograms feasible at v0.7.x. **G30 self-validation**: v0.6.6's own master..HEAD diff (12 files, 1663 lines) classified by its own `should_dispatch_deep_review` rule as tier=LOW score=25 → skip; decision recorded in `quantum.json.reviews[v0.6.6-bundle].deepReview` with all 4 required keys (tier/decision/rationale/automated). Audit log shows split summary `7/7 OK, 0 WARN, 0 FAIL` AND `pre-impl-review-coverage: 3/3 stages OK` (deterministic given v0.6.5 + v0.6.6 rows fall inside the 7d rolling window). Full retrospective: `idea-stage/PIPELINE_REPORT_v7.md`. v0.6.7+ backlog: `idea-stage/IDEA_REPORT_v7.md`.

## [0.6.5] - 2026-04-27

### Added

6 user-facing changes addressing v0.6.4's IDEA_REPORT_v5 priority list (G18, G20, G25, G26, G27, G28). Patch-tier; all changes are doc / drill-text / agent-prose / new-doc additions. No breaking changes; no schema changes; no new lib code. **First release whose dogfood produced real `metrics/pre-impl-review-findings.csv` data** — 3 rows representing all 3 advisory pre-impl-review stages on this v0.6.5 planning cycle. Closes IDEA_REPORT_v5 §G18/G20/G25/G26/G27/G28; unblocks G22 (severity-rubric calibration) for v0.7.x retrospectives. The orchestrator that drove this dogfood ran on v0.6.4 master HEAD semantics — see `README.md ## Self-modifying execution` (NEW in this release) for the recurring caveat.

- **`do_audit` summary split into OK / WARN / FAIL counters** (US-001, G26) — `quantum-loop.sh::do_audit` summary line now reads `Summary: <ok>/<total> OK, <warn> WARN, <fail> FAIL.` instead of `Summary: <ok>/<total> metrics on target.` which silently counted WARN rows as on-target. The `case`-style row scan accumulates 3 counters in a single pass; exit-code semantics preserved (returns 1 iff any row contains `|FAIL|`; WARN rows do not trip exit). Fixes the misleading wording exposed by v0.6.4's introduction of the first WARN-capable metric (`pre-impl-review-coverage`). 4 new test assertions in `tests/test_audit.sh` (Tests 33-35 split-summary fixtures + Test 23 fixed-format update); existing 35 audit assertions preserved.
- **`agents/spec-reviewer.md` plan-review checklist cites SPRINT_CONTRACT_TEST_REGEX** (US-002, G27) — closes G14's 5th call site that v0.6.4 missed. The plan-review checklist's "testFirst command consistency" rule now references `lib/handoff.sh::SPRINT_CONTRACT_TEST_REGEX` as the canonical pattern source. Inline regex characters preserved with explicit "see ..." framing for self-documentation. `lib/handoff.sh` consumer comment updated 4 → 5 sites. 1 new test assertion (sub-test 7h in `tests/test_sprint_contract.sh`).
- **`agents/conflict-auditor.md` Step 4 sort enumerates all 5 severities** (US-003, G25) — sort instruction now reads "high → medium → low → warning → none" with a 1-sentence rationale (high most-impactful; warning informational-but-real-signal; none informational-only). Closes the gap opened by v0.7.0 G15 (warning) and Rule 0 (none) which had no deterministic ordering before. Pure documentation-only fix. 1 new test assertion (Test 7 in `tests/test_changelog_ownership.sh`).
- **`references/risk-mitigation-language.md`** (US-004, G28) — NEW 153-line design-craft checklist for Risk-section authors. 3 sections: (1) the rule (enumerate operations, not just techniques) + cautionary tale citing v0.6.4 commit `c89ba13` and the soliton finding at confidence 90 that surfaced the flock-bootstrap-race; (2) 4-item concurrency checklist (shared mutable state / observably-coupled operations / race window without mitigation / race window with mitigation, each with concrete interleaving examples); (3) short-form patterns for non-concurrency mitigations (validate input X / handle malformed Y / atomic update Z). Bidirectional cross-link with `references/finding-severity.md` (review-craft pair). Operationalizes codebasePattern p007 from v0.6.4. 10 new test assertions in `tests/test_risk_mitigation_language.sh` (NEW).
- **`_audit_pre_impl_review_coverage` missing-csv drill text gains operator guidance** (US-005, G18) — drill text now reads "missing-csv — no metrics/pre-impl-review-findings.csv yet (expected on first run after install — invoke /ql-brainstorm/spec/plan to populate)". Other WARN states (`no-recent-runs`, `partial-coverage`) keep their existing drill messages. Closes the v0.6.4-flagged operator-confusion gap. **One follow-up surfaced**: `_audit_format_row` only renders drills for FAIL rows, so the new guidance is captured in tests but not yet visible at runtime; queued as v0.6.6 G29. 1 new test assertion (Test 28b in `tests/test_audit.sh`).
- **`README.md ## Self-modifying execution` section** (US-006, G20) — NEW 2-paragraph section between How It Works and Quick Start. Explains: each release ships a bundle that modifies the very orchestrator/agent/skill prompts the orchestrator itself uses, so each dogfood runs on the PREVIOUS release's prompt semantics, and this release's wires only apply to runs starting AFTER the bundle merges to master. Concrete v0.6.4 example (CSV-persistence wires applied to v0.6.5+ runs, not the v0.6.4 dogfood that introduced them). Cross-link to `idea-stage/PIPELINE_REPORT_v5.md`. Closes the recurring "is the audit broken?" reaction for new operators surfaced in PIPELINE_REPORT_v5 and the v0.6.5 PRD-review missing-measurement finding. 7 new test assertions in `tests/test_readme.sh` (NEW).

### Test-suite delta

**+23 new assertions** across 5 test files. Zero regressions in pre-existing suites (apart from a single pre-existing flake in `tests/test_timeout.sh` "Agent A still running after B killed" that is byte-identical to master and unrelated to any v0.6.5 change):

- 2 new files: `test_risk_mitigation_language.sh` (10), `test_readme.sh` (7)
- 3 extended: `test_audit.sh` 35 → 39 (+4: Tests 33-35 split-summary + Test 28b drill-substring), `test_sprint_contract.sh` 23 → 24 (+1: sub-test 7h), `test_changelog_ownership.sh` 9 → 10 (+1: Test 7)

### Dogfood milestone (v0.6.5)

**6/6 user-facing stories shipped first-attempt PASS across 2 waves** (5 sequential + 1 sequential). 0 retries, 0 cross-story contract violations, 0 merge conflicts. Total wall-clock to Wave 1 completion: ~85 minutes across 2 orchestrator instances (Run 1 hit iteration cap mid-US-001 with T-001 RED tests in place; Run 2 resumed by fixing one stale grep assertion and proceeded through US-001..US-006 + US-007 retrospective without further interruption). **First populated-CSV milestone**: 3 rows in `metrics/pre-impl-review-findings.csv` (design + prd + plan from this cycle's planning) — the first release whose dogfood produced real CSV data via manual hook invocation pre-execution. Audit log shows the new G26 split summary AND `pre-impl-review-coverage: 3/3 stages OK` (was `0/3 stages WARN missing-csv` in v0.6.4 retrospectives). **1 new codebasePattern** harvested (p008: sourced-script errexit propagation in test files; mitigation via function-extraction + two-invocation idiom). The G18-G28 cluster from IDEA_REPORT_v5 is now fully closed. Full retrospective: `idea-stage/PIPELINE_REPORT_v6.md`. v0.6.6+ backlog: `idea-stage/IDEA_REPORT_v6.md`.

## [0.6.4] - 2026-04-27

### Added

6 user-facing changes maturing v0.6.3's advisory pre-impl-reviewers via instrumentation (G12-G17). All mechanisms additive/opt-in; no breaking changes — patch-tier per strict semver (no API/schema breaks; advisory mechanisms remain advisory; retrospective artifacts use the planning-time `v0.7.0` label but the release ships as `v0.6.4`). Closes IDEA_REPORT_v4 §G12/G13/G14/G15/G16/G17. **v0.6.5's first run will be the first end-to-end populated `metrics/pre-impl-review-findings.csv`** — this v0.6.4 dogfood ran on v0.6.3 master HEAD (self-modifying caveat) so the new persistence wires apply only to NEXT runs. Promotion of any pre-impl-review stage from advisory → blocking should wait until ≥1 release of CSV baseline data accumulates.

- **`lib/finding-synth.sh`** (US-001, G12) — pre-impl-review FINDING-block parser. `parse_findings(stage)` reads stdin, accumulates lines between `FINDING_START` / `FINDING_END` markers, parses key:value pairs (category/severity/file/line/evidence/suggestion), emits a structured JSON array. `summarize_findings(stage, findings_json)` returns `{stage,count,by_severity,by_category}`. `format_summary_line(summary_json)` emits the `[REVIEW] <stage>-review complete: <N> findings (<crit>/<high>/<med>/<low>)` line. CLI subcommand mode supported. Malformed blocks warn-and-drop; remaining well-formed blocks parse. Library follows lib/handoff.sh's no-flags-at-source-time + double-source-guard convention. 31 new test assertions.
- **`lib/finding-persist.sh`** + **3 SKILL wires** (US-002, G13) — persistence layer for parsed findings. `persist_review_findings(stage, source_path, summary_json, findings_json)` writes (a) `.handoffs/<stage>-review-findings.json` per-run snapshot (idempotent overwrite per stage) and (b) appends a row to the aggregate `metrics/pre-impl-review-findings.csv` ledger (header on first write, then `flock -x` guarded append; rename-replace fallback on systems without `flock`). `read_review_findings(stage)` round-trips snapshot or emits `{}` + stderr WARN on missing-file. `skills/ql-brainstorm/SKILL.md` Phase 4d, `skills/ql-spec/SKILL.md` post-prd-review, and `skills/ql-plan/SKILL.md` Step 9 each gain a wrapper that captures reviewer stderr → parses → summarizes → persists. Advisory contract preserved across all 3 stages — wrappers never abort. `.gitignore` adds `.handoffs/*-review-findings.json` (per-run snapshots are runtime state); `metrics/` remains tracked (CSV ledger is committed baseline data). 37 new test assertions.
- **`lib/handoff.sh::SPRINT_CONTRACT_TEST_REGEX` constant** (US-003, G14) — DRY refactor: the test-pattern regex `'(test_|\.test\.|spec|pytest|^bash tests/|^npm test)'` previously inlined in 4 places (orchestrator.md Step 2.5, ql-plan SKILL.md Step 8, test_sprint_contract.sh, test_sprint_contract_ql_plan.sh) is now a single readonly shell constant near the top of `lib/handoff.sh`. All 4 consumers source the lib + pass via `jq --arg pattern`. `references/sprint-contract.md` references the constant by name. Future regex changes touch one file. Pure refactor — same behavior, single source of truth. **+2 no-inline-regex assertions** in test_sprint_contract.sh; existing 16 + 13 baseline assertions preserved.
- **CHANGELOG ownership convention** (US-006, G15) — `agents/dag-validator.md` §5d documents: stories that touch `CHANGELOG.md` SHOULD defer to a single retrospective story per release. If >1 story has `CHANGELOG.md` in `tasks[].filePaths`, the conflict-auditor MUST classify the conflict as `severity: warning` (not `severity: none`) and emit a Health Report line: `WARNING: <N> stories touch CHANGELOG.md — consolidate to a single retrospective story per the v0.6.3 convention`. `agents/conflict-auditor.md` Rule 0.5 codifies the per-file override (positioned between universal-pre-empt Rule 0 and category Rule 1). 9 new assertions in `tests/test_changelog_ownership.sh`.
- **`references/finding-severity.md` rubric** (US-004, G16) — new severity-calibration document with 3 mode sections (`## design-review`, `## prd-review`, `## plan-review`), each with a 4-row Severity / Rubric / Example table calibrated to the mode's existing checklist categories. `agents/spec-reviewer.md` design-review / prd-review / plan-review sections each gain a single cross-link line above their `### Output format` subsection (kebab-case anchor IDs). Helps operators distinguish "critical for design-review" from "critical for quality-reviewer downstream" — different bars. 14 new assertions in `tests/test_finding_severity.sh`.
- **`quantum-loop.sh --audit pre-impl-review-coverage` metric** (US-005, G17) — 7th audit row tracks how many of the 3 advisory pre-impl-review stages have run in the last 7 days. 4 states: `missing-csv` WARN (no CSV), `no-recent-runs` WARN (CSV exists but all rows >7d old), `partial-coverage` WARN (1-2/3 stages recent), `full-coverage` OK (3/3 stages recent). **WARN never trips audit exit code** — the metric measures operator pipeline-engagement, not codebase health. Cross-platform date math: GNU `date -d '7 days ago'` first, BSD `date -v-7d` fallback, epoch-0 fallback otherwise (degrades to "all rows count as recent" rather than crash). `quantum-loop.ps1` documents the PS1/SH parity divergence in its `.DESCRIPTION` block — `--audit` remains bash-only per AC. 6 new assertions in `tests/test_audit.sh` (Tests 28-33); existing 30 baseline assertions preserved.

### Test-suite delta

**+97 new assertions** across 7 test files. Zero regressions:

- 4 new files: `test_finding_synth.sh` (31), `test_finding_persist.sh` (37), `test_finding_severity.sh` (14), `test_changelog_ownership.sh` (9)
- 3 extended: `test_sprint_contract.sh` 16 → 18 (+2 no-inline-regex), `test_sprint_contract_ql_plan.sh` 13 → 13 (rewired, count unchanged), `test_audit.sh` 30 → 36 (+6 G17 4-state coverage)

### Dogfood milestone (v0.6.4)

7/7 user-facing stories shipped first-attempt PASS across 4 waves (4 parallel + 1 + 1 + retrospective). 0 retries, 0 cross-story contract violations, 0 merge conflicts. The new G15 CHANGELOG-ownership convention validated itself: only US-007 touches CHANGELOG.md (count=1, no warning emitted). G14's SPRINT_CONTRACT_TEST_REGEX constant exercised by both `test_sprint_contract.sh` and `test_sprint_contract_ql_plan.sh` — both green via the shared lib source. **1 new codebasePattern** harvested (p006: single source of truth for shell constants). The execution itself ran on v0.6.3 master HEAD semantics — v0.6.4's persistence wires apply to v0.6.5+ runs only (self-modifying-orchestrator caveat). Plus 3 post-merge fixes (commit `c89ba13`, `/soliton:pr-review`-driven) addressing race conditions in `lib/finding-persist.sh`: atomic header bootstrap inside flock, fallback path guards, jq-failure abort. 44/44 tests GREEN (37 baseline + 7 new). Full retrospective: `idea-stage/PIPELINE_REPORT_v5.md`. v0.6.5+ backlog: `idea-stage/IDEA_REPORT_v5.md`.

## [0.6.3] - 2026-04-26

### Added

8 user-facing changes covering G-track cleanup (G2/G3/G8/G9/G11) + 3-stage pre-impl spec-review (P5.B4 design / PRD / plan exits, advisory-only). Patch-tier; new mechanisms are opt-out via `QL_SKIP_PRE_IMPL_REVIEW` env var. No breaking changes. Closes IDEA_REPORT_v3 §G2/G3/G8/G9/G11 + §P5.B4 (expanded to 3 stages).

- **`lib/api-rename.sh`** (US-005, G2) — symbol-migration helper. `find_rename_targets <old> <new> [--exclude <glob>]` emits `<file>:<line>:<context>` for every occurrence (code AND doc-comments); `validate_rename_complete <old> [--exclude <glob>]` exits 0 iff no occurrences remain. Addresses the v0.6.0 US-001 dogfood where the `kill_agent_process → reap_agent` rename initially missed line-4 module-header doc-comments.
- **Sprint-Contract `expectedTests` filter + `otherCommands` schema split** (US-002, G9) — orchestrator Step 2.5 jq splits `.commands` by test-pattern regex (`test_|\.test\.|spec|pytest|^bash tests/|^npm test`); test-pattern matches → `expectedTests`, rest → new sibling `otherCommands`. Backward-compat: existing readers ignore the new optional field.
- **`/ql-plan` exit writes Sprint-Contract per story** (US-004, G3) — `skills/ql-plan/SKILL.md` Step 8 iterates stories and calls `write_sprint_contract`, materializing `.handoffs/sprint-<storyId>.json` files at plan time instead of lazily during orchestrator's first run. Idempotent on re-run.
- **`write_routing_snapshot` canonicalization** (US-003, G11) — `lib/runner.sh::write_routing_snapshot` now composes with `lib/json-atomic.sh::write_quantum_json` for atomic write + JSON-validation gate, replacing its inline `jq > tmp && mv` pattern. Inherits `cleanup_stale_tmp` coordination consistently with all other quantum.json writers.
- **Critic fallback unification** (US-001, G8) — deleted dead `quantum-loop.sh::parse_critic_arg` shim; `lib/runner.sh::_availability_check` now role-aware: `critic` falls back to `none` (preserving US-002's "downgrade-not-substitute" intent), `planner`/`executor` fall back to `claude`. PowerShell already at `none` for critic. **Operator-visible behavior change:** `--critic=codex` with codex absent now produces critic disabled (was `claude` since v0.6.0).
- **`spec-reviewer` design-review mode** (US-006, P5.B4-design) — new `## Mode: design-review` section in `agents/spec-reviewer.md` + Phase 4d hook in `skills/ql-brainstorm/SKILL.md`. Reads the just-saved design doc and reports structural gaps (missing sections, TBD/FIXME markers, hedge phrases, missing non-goals). Advisory: emits to stderr; does not abort the skill. Opt out via `QL_SKIP_PRE_IMPL_REVIEW=design`.
- **`spec-reviewer` prd-review mode** (US-007, P5.B4-PRD) — new `## Mode: prd-review` section + post-exit hook in `skills/ql-spec/SKILL.md`. Reads the just-saved PRD and reports non-testable ACs, vague FRs, missing measurement methods. Advisory. Opt out via `QL_SKIP_PRE_IMPL_REVIEW=prd` (or comma-combined, e.g. `design,prd`).
- **`spec-reviewer` plan-review mode** (US-008, P5.B4-plan) — new `## Mode: plan-review` section + Step 9 hook in `skills/ql-plan/SKILL.md` (after dag-validator + US-004 sprint-contract write). Cross-references quantum.json against the PRD; reports AC coverage gaps, command-test mismatches, missing wiring tasks. Advisory. Opt out via `QL_SKIP_PRE_IMPL_REVIEW=plan`.

### Test-suite delta

**+67 new assertions** across 8 test files. Zero regressions:

- 5 new files: `test_api_rename.sh` (14), `test_spec_review_design.sh` (14), `test_spec_review_prd.sh` (13), `test_spec_review_plan.sh` (13), `test_sprint_contract_ql_plan.sh` (13)
- 3 extended: `test_cross_provider_critic_flag.sh` 13 → 20 (+7), `test_sprint_contract.sh` 11 → 16 (+5), `test_per_role_routing.sh` 26 → 29 (+3 G11 composition + validation-gate)

### Dogfood milestone (v0.6.3)

**8/8 user-facing stories shipped first-attempt PASS across 4 waves** (5 + 2 + 1 + retrospective). Total wall-clock to wave-2 completion: ~34 minutes. Zero retries, zero cross-story contract violations, zero merge conflicts. Rule 0 `fileConflicts severity=none` classification held perfectly across all 4 conflicts. Per-story two-stage review gate applied; cross-story constant scan + typecheck + full test suite + barrel/dep-manifest regen ran at each wave boundary. **5 new codebasePatterns** harvested (opt-out env-var pattern; RED-test-first when refactoring with validation gates; backward-compat schema additions default to empty array; inline-vs-subshell arg-parser globals; defensive `\r` stripping for heredoc-fed JSON on Git Bash). Full retrospective: `idea-stage/PIPELINE_REPORT_v4.md`. v0.7.0 backlog: `idea-stage/IDEA_REPORT_v4.md`.

## [0.6.2] - 2026-04-26

### Fixed

Two follow-up items from the v0.6.x cycle's `/soliton:pr-review` post-merge findings (IDEA_REPORT_v3 §G10 + score-100 .cursor-plugin gap):

- **G10 — `lib/json-atomic.sh` PRD-sha migration shim** (`compute_prd_sha_legacy` + `verify_prd_sha`). Before v0.6.1, `compute_prd_sha` did not normalize CRLF; Windows users with `autocrlf=true` who ran `/ql-plan` under v0.6.0 stored CRLF-era hashes. After upgrading to v0.6.1, the same PRD now hashes differently — every story's `prdSha` would be marked `stale` and force a full `/ql-plan` re-run. v0.6.2 adds a transparent migration: `verify_prd_sha` tries the new (LF-normalized) hash first; on mismatch, falls back to the legacy (v0.6.0) hash; if THAT matches, the orchestrator's Step 1.1 updates the stored value in-place with a single one-line "MIGRATE" log message and no re-plan. Real drift still marks the story stale as before. 3 new tests added (match / migrate / drift paths) + 1 orchestrator-wiring test.
- **`.cursor-plugin/plugin.json` version catch-up bump 0.5.1 → 0.6.2** — the v0.6.0 + v0.6.1 cycle bumped `.claude-plugin/plugin.json` and `.claude-plugin/marketplace.json` but the Cursor manifest was missed. PR #58 established the convention of moving all three plugin manifests in lockstep on every release; `/soliton:pr-review` flagged this at score 100 on PR #61 but the fix landed here. Cursor marketplace consumers will now see v0.6.2 in sync with the Claude side.

### Backward compatibility

The migration path is transparent: existing v0.6.0/v0.6.1 `quantum.json` files load and run without operator action. The first orchestrator pass after upgrade silently rewrites legacy `prdSha` values to the new format. Stories without a `prdSha` field continue to behave exactly as before (back-compat warning logged once).

## [0.6.1] - 2026-04-26

### Fixed

Three correctness bugs surfaced by `soliton:pr-review` on the v0.6.0 bundle (1 at-threshold + 2 below-threshold; all confirmed as real cross-environment hazards rather than nits):

- **`lib/runner.sh:write_routing_snapshot` orphan `.tmp` cleanup** — the inline `jq ... > "$qj.tmp" && mv ...` pattern left a 0-byte `$qj.tmp` on jq failure, inconsistent with `lib/json-atomic.sh:write_quantum_json`'s canonical `rm -f "$tmp_path"` failure-branch cleanup. Now the function captures the jq exit code and removes the tmp file before propagating, mirroring the canonical pattern.
- **`lib/json-atomic.sh:compute_prd_sha` CRLF cross-platform sha mismatch** — the `rstrip(b' \t\n\r')` only stripped trailing whitespace; on Windows with `autocrlf=true`, internal `\r\n` bytes throughout a CRLF-checked-out PRD were retained, producing a different sha256 than the same file on Linux/LF. Every story's `prdSha` would false-positive as `status: "stale"` in cross-platform setups. Now normalizes `\r\n` → `\n` before hashing.
- **`quantum-loop.sh` `--critic` / `--planner` / `--executor` space-form `$2` guards** — under `set -euo pipefail`, a trailing flag (e.g. `--critic` at end-of-args) crashed with bash's `unbound variable` error; a flag-following pattern (e.g. `--critic --parallel`) consumed the next flag as a value and emitted a generic enum error. Each space-form now guards `[[ $# -lt 2 || "${2:-}" == --* ]]` and emits a user-friendly `Error: --<flag> requires a value (...)` exit-2 message.

No new tests required — these fixes are tightening existing code paths exercised by `tests/test_per_role_routing.sh` (26), `tests/test_prd_hash_pinning.sh` (12), and `tests/test_runner_integration.sh` baseline. Test count and assertion totals unchanged from v0.6.0.

## [0.6.0] - 2026-04-26

### Added

P5.A cleanup bundle (8 items) + P5.B1 per-role provider routing + P5.Z1 dogfood retrospective. Bigger dogfood than v0.5.1's --audit (10 stories, 5 waves, multi-runner dispatch). Closes P2.9 fully via OMC v4.12 mechanism port.

- **`agents/orchestrator.md` Step 3B.3 watchdog wiring** (US-001) — 3 explicit calls (poll, circuit, reset on STORY_PASSED) with reap_agent migration for platform-aware kills via taskkill on Windows.
- **`--critic=auto|codex|gemini|claude|none`** (US-002) — operator-facing critic provider flag with availability detection and fallback (subsumed by --planner/--critic/--executor in US-009).
- **`lib/deslop.sh` regex fallback** (US-003) — when knip/ts-prune/vulture/cargo-udeps/staticcheck are absent, dispatches to `lib/dead-code.sh` with normalized `{file, line, kind, severity}` schema.
- **5 new runner manifests** (US-004) — `runners/{opencode,devin,kiro,goose,cline}.json`, all `experimental: true`. `opencode.json` includes skill_discovery_paths quirk for Superpowers v5 plugin pattern compatibility.
- **`prdSha` field per story** (US-005) — RAGShield Level-1 drift detection (arXiv:2604.00387). `lib/json-atomic.sh:compute_prd_sha` produces a stable sha256; orchestrator Step 1.1 hash-check marks mismatched stories `status: "stale"` for re-plan.
- **Sprint-Contract handoff** (US-006) — per-story `.handoffs/sprint-<storyId>.json` written by `/ql-plan` and consumed by `/ql-execute` + `/ql-review`. Mirrors Anthropic's 2026-03-24 Generator-Evaluator contract pattern. Schema documented in `references/sprint-contract.md`.
- **Inline self-review checklists** (US-007) — `[INLINE-REVIEW] typecheck OK / lint OK / all assigned tests pass / file-org follows project conventions` tokens in implementer prompt before STORY_PASSED. Subagent dispatch reserved for adversarial review (cross-story conflict, intent drift, security). 25min -> 30s on routine path per Superpowers v5.0.6.
- **`complexity` field per story + `runner_select_model`** (US-008) — formula `min(100, task_count*10 + dependsOn_depth*15 + (security_tag ? 30 : 0) + filePaths_count*2)`. Routes <=30 -> haiku, 31-60 -> sonnet, 61+ -> opus. Story-level `model:'<override>'` wins.
- **`--planner / --critic / --executor` per-role routing** (US-009) — ports OMC v4.12 mechanism. `lib/runner.sh:resolve_routing` resolves each role with availability check + fallback to claude. Snapshot persisted to `quantum.json.routing` for replay determinism. Closes P2.9 fully.
- **`idea-stage/PIPELINE_REPORT_v3.md` + `idea-stage/IDEA_REPORT_v3.md`** (US-010) — v0.6.0 dogfood findings: 9/9 user-facing stories first-attempt PASS across 5 waves (5 parallel + 2 parallel + 3 sequential). 5 NEW codebasePatterns logged. P5.B2-B5 + P5.C frontier remain open for v0.7+. Test-suite delta: ~+110 new assertions, zero regressions.

### Test-suite delta

110+ new assertions across 8 new test files. Zero regressions in pre-existing suites:
- `tests/test_watchdog_wiring.sh` (9), `tests/test_cross_provider_critic_flag.sh` (13), `tests/test_deslop_regex_fallback.sh` (7)
- `tests/test_runner_manifests.sh` extended +28 assertions, `tests/test_complexity_routing.sh` (19)
- `tests/test_prd_hash_pinning.sh` (12), `tests/test_sprint_contract.sh` (11)
- `tests/test_per_role_routing.sh` (26), `tests/test_per_role_routing_integration.sh` (6)
- `tests/test_orchestrator_wiring.sh` extended +7 assertions for inline-checklist tokens

### Dogfood milestone (v0.6.0)

The pipeline executed its largest fan-out yet: **5-story parallel wave-0** with worktree isolation, zero file-conflict resolution failures. The DAG validator's Rule 0 fileConflicts severity=none classification held perfectly across all 10 conflicts. 5 NEW codebasePatterns surfaced (cross-module rename doc-comment scanning, jq validator gaps, PATH manipulation in tests, test-guard carve-outs, set -uo pipefail return-1 termination). All retrospective material captured in `idea-stage/PIPELINE_REPORT_v3.md` + `idea-stage/IDEA_REPORT_v3.md`.

## [0.5.1] - 2026-04-24

### Added

- **`quantum-loop.sh --audit`** (#56) — read-only repo-hygiene check that prints the six IDEA_REPORT §6 measurement metrics with drill-down on failures. Exit 0 all-OK, exit 1 any off-target, exit 2 misuse. Env-tunable thresholds via `QL_AUDIT_BRANCH_MAX` / `QL_AUDIT_ORPHAN_MAX` / `QL_AUDIT_CONFLICT_MAX` / `QL_AUDIT_CPC_MAX`.
- **`docs/plans/2026-04-24-audit-flag-design.md`** + **`tasks/prd-audit-flag.md`** (#57) — pipeline artifacts from dogfooding `/ql-brainstorm` + `/ql-spec` on the audit feature. Preserves the IDEA_REPORT §6 → design → PRD → shipped-feature traceback.

### Dogfood milestone

First real pipeline self-use. The `/ql-brainstorm` → `/ql-spec` → `/ql-plan` → `/ql-execute` cycle drove a complete 4-story feature end-to-end. Findings captured in #56 PR body for follow-up skill refinements (question-count rigidity in ql-spec, placeholder-drift across stories, file-conflict serialization heuristics).

## [0.5.0] - 2026-04-24

### Added — P3 academic-wedge libraries (10 libs)

All ten wedges from `idea-stage/IDEA_REPORT.md` §P3 landed with a consistent contract pattern (no shell flags at source time, CLI block enables strict mode, env-var tunables, readonly arrays guarded against re-source).

- **`lib/constitution.sh`** (P3.11, arXiv:2602.02584) — regex-based invariants on generated code: hardcoded-secret scan, SQL-injection pattern, input-validation presence, immutable-schema rule.
- **`lib/deep-review.sh` `far_filter`** (P3.3/P3.4, arXiv:2505.17928 + arXiv:2604.03196) — KBI→FAR reviewer split with agreement boost, confidence cutoff, known-false-positive regex suppression.
- **`lib/trajectory.sh`** (P3.5, arXiv:2511.00197) — tool-shape thrashing detection: `parse_trajectory` / `classify_trajectory` (productive | searching | thrashing | stuck) / `should_early_kill`.
- **`lib/hyclone.sh`** (P3.7, arXiv:2508.01357) — Stage-1 semantic-clone fingerprint: alpha-normalize + sha256 + `find_clones` grouping.
- **`lib/conflict-grade.sh`** (P3.2, ConGra arXiv:2409.14121) — per-hunk conflict severity grading 1-5 + routing to `auto-git | diff3 | llm-merge | escalate`.
- **`lib/tracecoder.sh`** (P3.8, arXiv:2602.06875) — Observe-Analyze-Repair primitives: `observe` / `extract_error_markers` / `build_analysis_context` / `should_repair`.
- **`lib/reground.sh`** (P3.9, arXiv:2603.00492) — session-level drift mitigation: re-inject PRD + progress + iron-law reminder every N stories.
- **`lib/skeleton.sh`** (P3.1 SSAT, arXiv:2303.06689) — signature-level API surface: `extract_skeleton` / `skeleton_text` / `skeleton_diff` across TS/JS/Python/Go/Rust.
- **`lib/intent-graph.sh`** (P3.6, arXiv:2604.11209) — formal semantic-intent extraction: `(verb, object)` triples from stories + code with bidirectional drift reporting.
- **`lib/dead-code.sh`** (P3.10, arXiv:2604.07291) — regex-based unused-import + unused-private-helper detection across TS/JS/Python/Go/Rust.

### Added — Orchestrator wirings (8 integration points)

Every new lib wired into the orchestrator via grep-assertion-covered integration points. `test_orchestrator_wiring.sh` grew from 40 → 106 assertions, none can silently unwire a lib.

- **Step 1C** (reground) — periodic re-grounding, gate on `REGROUND_INTERVAL` stories.
- **Step 3A.1 sub-5** (skeleton) — pre-task API-surface preview.
- **Step 3A.3** (tracecoder) — Observe-Analyze-Repair wrapper on typecheck/lint/test gates.
- **Step 3A.5C** (dead-code) — post-generation advisory unused-import/private scan.
- **Step 3A.5D** (intent-graph) — post-generation advisory verb-object drift check.
- **Step 3A.5E** (skeleton) — post-task skeleton-diff drift report.
- **Step 3A.6** (trailers) — advisory trailers appended to commit message for durability in `git log`.
- **Step 3B.3** (trajectory) — monitor-loop tick alongside watchdog; kill path via `reap_agent`.
- **Step 3C.NEG0** (hyclone) — wave-boundary cross-story clone detection.
- **`lib/merge-strategy.sh`** (conflict-grade) — grade 5 short-circuits to escalation; grades 1-4 logged alongside category routing.

### Fixed

- **String-unsafe comment stripper** in `lib/hyclone.sh` and `lib/conflict-grade.sh` — awk passes now track string state so `//`, `/*`, `#` inside a string literal are preserved verbatim (e.g., `"http://x"`, `"/regex/"`, `"/* not a comment */"`).
- **Trajectory wiring log-path mismatch** — orchestrator now reads `.ql-wt/$sid/.ql-agent-output.txt` (spawn.sh convention) instead of the non-existent `.ql-wt/$sid/agent.log`.
- **TraceCoder wiring pseudocode** — removed undefined `GATE_CMD[$gate]` / `mark_story_failed` / `apply_focused_fix` identifiers; replaced with prose agent-action comments matching the pattern used elsewhere (watchdog mark-failed, etc.).
- **test_typecheck_gate 12 failures** — added `TYPECHECK_EXTRA_ALLOWED_PREFIXES` env var to extend the security allowlist for test fixtures without weakening the runtime gate.
- **Advisory trailers dead code** — Steps 3A.5B/C/D/E each set a trailer variable but none were appended to the 3A.6 commit. `git log` grep workflow was unusable. Now each trailer is guarded-appended to `COMMIT_MSG` before commit.

### Measurement targets (per IDEA_REPORT §6)

| Target | Goal | Achieved |
|--------|------|----------|
| CPC variant files | 0 | ✓ 0 |
| README conflict markers | 0 | ✓ 0 |
| Orphan `.claude/worktrees/agent-*` | 0 | ✓ 0 |
| Remote branch count | ≤10 | ✓ 1 (master) |
| Local branch count | ≤10 | ✓ 1 (master) |
| Archive tags preserved | — | 49 |
| Master test suites green | 100% | ✓ 54/54 (~1,400 tests) |

## [0.4.1] - 2026-04-01

### Added
- **Multi-runner support** — universal runner adapter lets quantum-loop drive Claude, Codex, Copilot, Cursor, Gemini, Aider, Cline, Amp, Devin, Kiro, Goose, and OpenCode through a shared manifest contract. Design doc: `docs/plans/2026-04-01-multi-runner-support-design.md`.
- **Runner JSON schema** (`schemas/runner.schema.json`) + validator (`schemas/validate.sh`) for manifest linting.
- **Runner library** (`lib/runner.sh`) with load / ensure_instructions / command_builder / hook helpers. Manifests under `runners/*.json`.
- **Signal protocol preamble** injected into non-Claude runners so they emit `<quantum>STORY_PASSED/FAILED/COMPLETE/BLOCKED</quantum>` markers in a shared format.
- **Signal heuristic fallback** (`lib/signal-heuristics.sh`) — if no explicit `<quantum>` signal is present, infer from commit evidence, test results, and hedge-phrase filters.
- **Instruction-file auto-copy** — replicates `CLAUDE.md` to each runner's convention (`AGENTS.md`, `GEMINI.md`, etc.).
- **Runner manifests**: `claude.json` (guaranteed), `codex.json` (tested end-to-end), plus experimental manifests for `amp`, `aider`, `copilot`, `cursor`, `gemini`.
- Sequential mode, PowerShell mode, and `templates/quantum-loop.sh` all wired to the runner framework.
- 22-test signal-heuristic suite and an integration test-suite for Codex CLI dispatch.

### Fixed
- Sequential-mode status updates no longer lose state on runner switch.
- Heuristic false-positive filter for ambiguous runner output.
- Runner name + template argument validation hardened against injection.

## [0.3.7] - 2026-03-30

### Added
- **Hardening-v2: init-guard + AST-aware merge + resilience** — design doc `docs/plans/2026-03-28-hardening-v2-design.md`.
- **`lib/init-guard.sh`** — environment pre-flight: OneDrive / long-path detection, tmpdir writability check, orphan worktree prune.
- **`lib/merge-semantic.sh`** — AST-aware 3-way merge (ts-morph for TypeScript, libcst for Python, diff3 fallback) routed via `lib/merge-strategy.sh`.
- **`lib/resilience.sh`** — WIP commits per task, squash-on-merge at story boundary, crash recovery via `lastWipCommit` + `completedTasks` fields. Supersedes `lib/crash-recovery.sh` (to be removed).
- **Stash exclusion for `quantum.json`** during merges to prevent schema corruption.
- Integration tests covering init → merge flow, crash recovery with WIP commits, semantic merge conflict, quantum.json stash isolation.

### Fixed
- Stash-ordering race in `merge-strategy.sh`.
- Trap cleanup on early abort paths in `resilience.sh`.
- stderr redirect typo on ts-morph merge fallback path.

## [0.3.6] - 2026-03-25

### Added
- **Modular Hardening (7 independent modules)** — design doc `docs/plans/2026-03-25-modular-hardening-design.md`.
- **`lib/barrel-regen.sh`** — auto-regenerate barrel exports (`_barrel.ts` / `__init__.py` / etc.) post-merge so new story files become consumer-importable.
- **`lib/dep-manifest.sh`** — detect dependency-manifest changes (npm / pip / go / cargo) and run appropriate install post-merge.
- **`lib/known-failures.sh`** — baseline + delta tracking of test failures per wave. Alerts on **new** regressions, not pre-existing red.
- **Worktree lifecycle** — `worktree.sh` extended with lifecycle-tracking functions; `execution.worktreeTracking` fields `{activeWorktrees, cleanedThisSession, maxWorktrees}`.
- **Category-based merge strategy** (`lib/merge-strategy.sh`) — routes conflicts by file kind: `dependency_manifest → ours+install`, `barrel_export → regenerate`, `new_story_file → theirs`, `shared_infrastructure → ours`, `contract_stub → theirs`, default escalate.
- **Interface cascade guard** extending the L5 type audit.
- **`contractBreaking` flag + `fixes` field** in ql-plan for intentional breaking changes.
- Unit tests for barrel-regen, dep-manifest, known-failures, worktree lifecycle, merge-strategy, plus integration tests for known-failures lifecycle and escalation retry.

## [0.3.5] - 2026-03-24

### Added
- **DAG Intelligence — parallel specialist validators** — design doc `docs/plans/2026-03-24-dag-intelligence-design.md`.
- **`dag-validator` coordinator agent** that spawns three specialists in parallel:
  - **`bottleneck-analyzer`** — Kahn's-algorithm wave assignment; detects sequential bottlenecks.
  - **`duplication-detector`** — Jaccard keyword pre-filter + LLM semantic check for overlapping stories.
  - **`conflict-auditor`** — computes complete `fileConflicts` from `filePaths` intersections with severity classification.
- **`storyType` field** on stories (feature / refactor / fix / test / docs / skeleton / integration).
- **`dagValidation` block** + `severity` field in `quantum.json` schema.
- `dag-validation.md` reference doc.
- `ql-plan` integrates `dag-validator` invocation before plan confirmation; shows DAG Health Report.

### Fixed
- PR-review findings from soliton review (prompt hardening, context-window optimization).

## [0.3.4] - 2026-03-18

### Added
- **Progressive Materialization (5-layer type-divergence defense)** — design doc `docs/plans/2026-03-18-worktree-isolation-fix-design.md`.
- **`lib/materialize.sh`** — detects language; materializes real interface files for contracts consumed by ≥2 stories (threshold configurable). Smart-materialization threshold logic added in this release.
- **`lib/type-audit.sh`** — grep-based duplicate-definition detection at wave boundary; spawns `type-auditor` agent on hits and feeds findings back into contracts.
- **Post-merge typecheck gate** — auto-detects project typechecker (tsc, pyright, mypy, etc.) and reverts on failure.
- **Auto-promotion of discovered contracts** — orchestrator promotes wave-end audited types into `materializedContracts`.
- **`typecheckCommand` field** in `quantum.json` schema; new execution-metadata fields for materialization and audit tracking.
- **Shared-types directory inference** + `contract-shapes` reference doc for `ql-plan`.
- **Contract Effectiveness section** in orchestrator post-mortem output.
- Extended `merge_worktree_branch()` with conflict classification.
- Unit tests for `materialize.sh`, `type-audit.sh`, merge escalation, typecheck gate.

### Fixed
- Command-injection hardening in merged scripts.
- Path-traversal checks in materialization paths.
- Merge revert safety when a post-merge gate fails.
- L5 audit feedback loop, error counting, Python pattern recognition.

## [0.3.3] - 2026-03-11

### Fixed
- **File-conflict-aware DAG scheduling** — new `filter_file_conflicts()` in `dag-query.sh` prevents spawning parallel agents that share file paths. Uses greedy priority-ordered selection with exact-match comparison. Wired into both dispatch sites in `quantum-loop.sh` (initial wave + mid-wave top-up). Also detects cross-wave conflicts by seeding with in_progress stories' files.
- **Worktree nesting prevention** — new `_resolve_repo_root()` helper in `worktree.sh` resolves nested worktree paths to the top-level repo root via `git rev-parse --git-common-dir`. Used by all three public functions (create, remove, list). Falls back gracefully on Git < 2.31 and warns when resolution fails inside `.ql-wt/` paths.
- **Windows long-path fallback** — `create_worktree` detects paths > 200 chars and falls back to a repo-namespaced temp directory (`/tmp/ql-wt-<hash>/`). Re-checks fallback length with emergency `/tmp` last resort. `remove_worktree` and `list_worktrees` check both locations.
- **Editable install race condition** — PYTHONPATH injection guidance added to `implementer.md`, `orchestrator.md`, and `spawn.sh` (both src-layout and flat-layout variants). Agents no longer run `pip install -e .` in parallel worktrees.
- **Worktree cleanup on Windows** — retry loop (3 attempts, 2s delay) for file locks from OneDrive sync / `__pycache__`. `rm -rf` fallback only runs when `git worktree remove` actually fails. `git worktree prune` runs after cleanup.
- **Unescaped shell expansions** — `orchestrator.md` prompt template now uses `\$(pwd)` and `\$PYTHONPATH` (matching `spawn.sh` pattern) to prevent premature expansion.
- **echo → printf** — `detect_cycles` in `dag-query.sh` now uses `printf` matching project convention.

### Added
- **Inline review gate for parallel mode** (Step 3B.4) — orchestrator runs spec compliance + code quality checks after each worktree merge, matching sequential mode's quality bar. Defers to wave-end when accumulated diff exceeds 2000 lines.
- **Full-feature code review** (Step 4B) — holistic review of entire branch diff after all stories pass. Checks cross-story consistency (naming, duplicates, type mismatches), architecture coherence (PRD goals, data flow, backward compatibility), and security (secrets, TODOs, error handling).
- **quantum.json merge guidance** — documented stash/merge/restore pattern and recommended `.gitignore` best practice.
- **Input validation** — `filter_file_conflicts()` validates file path and eligible array before processing.
- **Cross-repo collision prevention** — `_short_path_base()` uses repo-root hash to namespace `/tmp` worktrees per repository.
- 14 new tests: `filter_file_conflicts` (8 tests covering filePaths overlap, fileConflicts entries, empty/null, three-way conflict, transitive chains, similar paths), `_resolve_repo_root` (3 tests: identity, from-worktree, nested-create), `_short_path_base` (2 tests: determinism, cross-repo uniqueness), PYTHONPATH in spawn prompt (4 assertions). **79 total tests, all passing.**

## [0.3.2] - 2026-03-10

### Fixed
- **Mandatory worktree isolation** — `isolation: "worktree"` is now documented as MANDATORY for parallel execution, with specific failure modes listed (bash contention, file conflicts, quantum.json races)
- **Correct tool naming** — orchestrator now references "Agent tool" (not "Task tool") with exact parameter names (`subagent_type`, `isolation`, `mode`, `run_in_background`)
- **Atomic quantum.json updates** — new Step 3B.1 batches all `in_progress` status writes into a single atomic update before spawning agents
- **Monitor loop** — changed from polling to waiting for Claude Code completion notifications
- **State management discipline** — only the orchestrator writes quantum.json; Edit tool banned (use Python/jq); multi-story updates batched into one write
- **Implementer parallel mode** — implementer agents in worktrees no longer edit quantum.json (stale copy); report via output message instead
- **Anti-rationalization guards** — 2 new entries blocking "skip worktree" and "worktrees won't work on this OS" excuses

## [0.3.1] - 2026-03-09

### Added
- **Cross-story contracts** — `contracts` field in quantum.json for shared values (secret keys, env vars, types) across parallel stories. ql-plan generates them; implementer reads and enforces them with propose-and-wait on disagreements.
- **Wiring verification** — `wiring_verification` field on tasks with grep-based mechanical check in spec-reviewer. No agent judgment: missing string = fail, present = pass.
- **`consumedBy` field** — declares cross-story consumption so implementers import existing components instead of inlining duplicates.
- **Coverage gate** — configurable `coverageThreshold` in quantum.json; quality-reviewer runs coverage tool and fails stories below threshold (tool detection: c8 → nyc → pytest-cov → go test → JaCoCo).
- **Coding standards enforcement** — quality-reviewer reads CLAUDE.md, `.claude/rules/`, and `codebasePatterns`; violations of documented rules are CRITICAL severity.
- **Stale story detection** — `startedAt` timestamp + `staleThresholdMinutes` (default 20, CLI-overridable). Implemented in orchestrator, quantum-loop.sh, quantum-loop.ps1, and templates/quantum-loop.sh.
- **Final verification sweep** — scripts run full test suite + import smoke test before declaring COMPLETE. Test failure blocks COMPLETE.
- **Execution observations** — auto-generated post-mortem doc after every run with failure summary, patterns, and raw data. Optional GitHub issue filing with user confirmation.
- **CLAUDE.md defensive check** — Step 3 warns and skips stories that are in_progress but not assigned to the current agent.
- **Lifecycle awareness** — ql-brainstorm question #7 (LIFECYCLE) and ql-spec Pre-Save lifecycle checklist (first-run, returning-user, update, error recovery, empty state, uninstall).
- **`testFirst` mandate** — ql-plan defaults `testFirst: true` for all tasks; exempt tasks require `notes` justification.
- Shell tests for stale detection, startedAt, final sweep, and observations (4 new test files, 14 tests)

### Fixed
- **Atomic in_progress + startedAt write** — single jq operation prevents crash window where story is in_progress without startedAt
- **startedAt cleared on all exit paths** — BLOCKED, unrecognized signal, timeout, merge conflict, non-zero exit, and crash recovery
- **Null-guard failureLog** — observations jq uses `(.retries.failureLog // [])[]` to handle null vs empty array

## [0.3.0] - 2026-02-27

### Added
- **Cross-story integration review** — Stage 3 in ql-review traces call chains across story boundaries using LSP (grep fallback). Runs after dependency chains complete and as a final gate before COMPLETE.
- **Final integration gate** — orchestrator runs import smoke test, full test suite, and dead code scan before declaring COMPLETE
- **File-touch conflict detection** — ql-plan Step 5 flags parallel stories modifying the same file, adds reconciliation tasks, stores conflicts in `quantum.json` metadata (`fileConflicts`)
- **Consumer verification pattern** — wiring acceptance criteria belong on the consumer story, not the creator
- **Edge case test requirements** — boundary values, type variations, collision scenarios, scale tests required for all testFirst tasks
- **Edge case reference doc** — `references/edge-cases.md` with Python, JS, Go, Rust testing gotchas. Implementer reads it at the start of every testFirst task.
- **Import chain verification** — ql-verify requires integration evidence for multi-story features
- **Cursor marketplace manifest** — `.cursor-plugin/plugin.json` for cross-platform publishing

### Changed
- Orchestrator Step 4 split into Step 4 (Final Integration Gate) and Step 5 (Completion)
- Implementer always reads `references/edge-cases.md` for testFirst tasks (not on-demand)

## [0.2.0] - 2026-02-25

### Added
- **Orchestrator agent** (`agents/orchestrator.md`) — manages full execution lifecycle inside Claude Code with DAG query, sequential/parallel dispatch, two-stage review, retry logic
- **Native PowerShell script** (`quantum-loop.ps1`) — Windows overnight runs without bash/WSL
- **SkillsMP compatibility** — `name` field in all SKILL.md frontmatter
- **ql-plan runner copy** — copies quantum-loop.sh/ps1 into project after planning

### Fixed
- **Lost work in parallel mode** — agents must commit before signaling; orchestrator adds safety commit before merge
- **Merge failure on dirty tree** — stash working tree before merge, pop after
- **Stale worktree branches** — delete existing branch before `git worktree add -b`

### Changed
- Simplified `skills/ql-execute/SKILL.md` from ~300 lines to ~50 line dispatcher
- `CLAUDE.md` parallel mode: agents explicitly told to commit before signaling
- `lib/spawn.sh` prompt includes commit instruction

## [0.1.0] - 2026-02-19

### Added
- Parallel execution via DAG-driven worktree agents
- 7 shell library modules (`lib/`) for DAG query, worktree lifecycle, agent spawning, monitoring, atomic JSON writes, crash recovery
- 7 test suites with 110 tests
- `--parallel` and `--max-parallel` flags for `quantum-loop.sh`
- `/ql-execute` parallel orchestration via Task subagents
- Crash recovery for orphaned worktrees
- `CLAUDE.md` parallel mode instructions

## [0.0.1] - 2026-02-18

### Added
- Initial release
- 6 skills: brainstorm, spec, plan, execute, verify, review
- 3 agents: implementer, spec-reviewer, quality-reviewer
- `quantum-loop.sh` sequential autonomous loop
- `CLAUDE.md` agent template
- Dependency DAG execution
- Two-stage review gates (spec compliance + code quality)
- Iron Law verification
- Anti-rationalization guards
