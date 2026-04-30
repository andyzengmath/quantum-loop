# PIPELINE_REPORT_v27 — v0.9.0 retrospective (N42 — real per-wave coordinator dispatch)

**Date:** 2026-04-29
**Bundle:** `ql/v0.9.0-bundle` (release tag v0.9.0 — pending push/PR/merge/tag)
**Predecessor report:** `idea-stage/PIPELINE_REPORT_v26.md`
**Master parent:** `fec03f0` (v0.8.4 ship state)
**Source:** Operator-scoped post-v0.8.4 close. 3 architect agents designed sub-problems independently; cycle implements their consolidated design.

## Overview

v0.9.0 N42 ships the actual cure for the N33 manual-takeover streak. v0.8.x closed the anti-pattern across 4 layers + verified all v0.9.0 prerequisites; v0.9.0 wires the per-wave coordinator dispatch when operators opt in via `--coordinator`.

**First minor since v0.8.0.** Genuinely architectural — `--coordinator` now does something different from `--legacy-orchestrator` for the first time. New CLI behavior path + new dispatch architecture in the sequential path + new function in `lib/dag-query.sh` + new field-ownership enforcement.

## The 7 stories

| # | ID | Title | Outcome |
|:-:|---|---|:-:|
| 1 | US-000 | Amend coordinator.md to align with field-ownership contract | first-attempt PASS |
| 2 | US-002 | lib/dag-query.sh::next_wave thin composer + 18-assert tests | first-attempt PASS |
| 3 | US-001 + US-003 + US-004 | Inner-dispatch replacement + per-story aggregation + CLI guard (atomic) | first-attempt PASS |
| 4 | US-005 | Real-fire coordinator-dispatch integration tests (10 asserts) | first-attempt PASS |
| 5 | US-006 | Retrospective + IDEA_REPORT_v27 + version bump | this report |

## Three-architect design (pre-cycle)

Operator scoped v0.9.0 with explicit "use agent teams to design carefully". Three architect agents ran in parallel pre-cycle:

| Architect | Focus | Key finding |
|---|---|---|
| 1 (inner-dispatch) | quantum-loop.sh:1515 spawn block replacement | HIGH risk: `*)` branch references undefined `$STORY_ID` under coordinator mode → must gate to apply retry accounting to ALL wave stories |
| 2 (next_wave) | lib/dag-query.sh new composer | Recommended thin composer over existing helpers; 3-way exit code (no string-sentinel parsing) |
| 3 (output capture + per-story aggregation) | WAVE_PASSED/WAVE_FAILED branches | Found `agents/coordinator.md:25` (step 4) directly contradicts the field-ownership contract at line 105 — promoted to US-000 prereq |

All three findings became implementation stories. The architect-designed risks all materialized in implementation and were addressed.

## What v0.9.0 ships

### US-001: outer COORDINATOR_MODE branch + multi-story pre-mark + spawn coord + retry-accounting gates
- Outer `COORDINATOR_MODE` if/else replaces single-story DAG selection with `next_wave` call (rc=0 → wave; 1 → COMPLETE; 2 → BLOCKED).
- Legacy path synthesizes 1-element `WAVE_STORY_IDS_JSON` for uniform downstream multi-story logic.
- `in_progress` pre-mark via single jq pass keyed on `WAVE_STORY_IDS_JSON`.
- Spawn block: new outer `if [[ "$COORDINATOR_MODE" == "true" ]]` → `spawn_coordinator` returns command STRING; `eval` synchronously. Legacy if/else preserved verbatim.
- `ql_wrap_subagent_dispatch` soft-fire skipped under coordinator mode (coordinator handles internal retries).
- `*)` unknown-signal branch applies retry accounting to ALL `WAVE_STORY_IDS` (architect 1's HIGH risk addressed).

### US-002: lib/dag-query.sh::next_wave
- Thin composer over `get_executable_stories` + `filter_file_conflicts` (no logic duplication).
- 3-way exit code: 0=wave (JSON array on stdout), 1=COMPLETE, 2=BLOCKED.
- Defensive type-check on `get_executable_stories` output (guards against silent contract drift).

### US-003: per-story aggregation in WAVE_PASSED/WAVE_FAILED
- `WAVE_PASSED)` bulk-updates ALL wave stories to `status=passed`.
- `WAVE_FAILED)` per-story aggregation via Option A: derives outcome from coordinator-written `review.specCompliance` + `review.codeQuality` fields. No signal-protocol change.

### US-004: --coordinator --parallel mutual exclusion
- Hard exit at parse time replacing v0.8.1 warn-only message.

### US-005: real-fire integration tests
- Stub `claude` script on PATH (resolves spawn_coordinator's eval'd command).
- 4 cases: WAVE_PASSED happy path, WAVE_FAILED partial-pass, `--coordinator --parallel` rejection, COMPLETE path.
- 10 assertions; **NOT presence-only** (v0.8.x burned that lesson 4 times).

## Wave plan vs. realized

US-000 + US-002 + US-004 independent. US-001 dependsOn US-000 + US-002. US-003 dependsOn US-001 (case branches). US-005 dependsOn US-001 + US-002 + US-003 + US-004. US-006 dependsOn all.

Realized order under manual takeover (18th consecutive cycle):
1. US-000 → coordinator.md amendment (1-line; unblocks downstream)
2. US-002 → next_wave + 8-case tests (independent)
3. US-001 + US-003 + US-004 → atomic commit (file-coupled; tightly logically related)
4. US-005 → real-fire integration tests
5. US-006 → this retrospective

## G30 self-validation — 21st consecutive LOW

`bash lib/deep-review.sh score $BASE $HEAD` → **score=20 tier=LOW files=8 sensitive=0 → skip**. Recorded with `automated:true`. **21 consecutive LOW-tier self-validations** (v0.6.5..v0.9.0). Note: score=20 is LOWER than v0.8.4's 25 — surprising for a minor-tier cycle (more files changed = higher score expected). The rubric appears to discount additive changes (new files outweigh modifications).

## Multi-cycle CSV milestone (sixteenth populated run)

`metrics/pre-impl-review-findings.csv` → 52 rows. Advisory hook findings for v0.9.0: design=1 (LOW: missing-rollout — aggregate LOC estimate), prd=1 (LOW: ac-precision — US-005 stub strategy), plan=1 (LOW: dependency-graph — US-001→US-000+US-002 chain). All 3 LOW.

## Test-suite delta vs v0.8.4

| Test file | v0.8.4 | v0.9.0 | delta |
|---|---:|---:|---:|
| `tests/test_next_wave.sh` (NEW) | — | 18 | +18 |
| `tests/test_coordinator_e2e.sh` (NEW) | — | 10 | +10 |
| **Total v0.9.0 added:** | | | **+28** |

## Manual-takeover (18th consecutive cycle)

v0.9.0 ships under manual takeover. **The empirical break point is v0.9.1**: real-LLM dogfood through `--coordinator`. v0.9.0 has stub-driven integration tests (10/10 pass) but no production proof. Mirror of v0.8.0 → v0.8.1's pattern: ship infrastructure in minor; validate in patch.

## codebasePatterns

p001-p012 carried over. No new patterns this cycle — the architectural changes leverage existing patterns (atomic critical sections, jq-based json mutations, runner adapter abstraction).

## Architect-design pattern — STANDARDIZED

Pre-cycle architect-team design phase before architectural work is now standard. v0.9.0 validates the pattern:
- 3 parallel agents (inner-dispatch + helper function + output aggregation)
- Each surfaced different risks/insights
- Synthesis caught a HIGH-severity findings (architect 1's coordinator-crash gap, architect 3's contract contradiction) that became blocking stories before implementation

This complements the standardized post-merge multi-perspective review pattern (architect + code-reviewer + security; validated 4 cycles in v0.8.x).

## Recommendation pointer

See `idea-stage/IDEA_REPORT_v27.md` for what's open after v0.9.0.
