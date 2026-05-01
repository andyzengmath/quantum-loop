# PIPELINE_REPORT_v33 — v0.9.6 retrospective (post-decomposition cleanup)

**Date:** 2026-05-01
**Bundle:** `ql/v0.9.6-bundle` (release tag v0.9.6 — pending push/PR/merge/tag/release)
**Predecessor report:** `idea-stage/PIPELINE_REPORT_v32.md`
**Master parent:** `486ced9` (v0.9.5 ship state)
**Source:** Operator-staged plan from `.handoffs/HANDOFF-2026-05-01-post-v0.9.5.md` § CORRECTIONS + `idea-stage/v0.9.x-arc-audit-2026-04-30.md:48,70`.

## Overview

v0.9.6 is a focused **post-decomposition cleanup** patch closing 4 mechanical-cleanup items that the v0.9.x audit had explicitly flagged but had been deferred during v0.9.5 (the decomposition cycle). 5-story patch closing: 6-site `jq+tmp+mv` migration (+args-variant prerequisite); 3-pair `emit_terminal_signal` extraction; CLAUDE.md doc sync; 3 LOW absorbs.

## Headline result

**v0.9.x audit findings FULLY CLOSED.** All MEDIUM-tier audit items now shipped (decomposition v0.9.5; parent-side guard v0.9.5; ADR-001 v0.9.5; jq migration v0.9.6; signal-helper extraction v0.9.6; LOW absorbs v0.9.6). Remaining backlog is uniformly v0.10.0+ scope (PARALLEL_MODE extraction = the only remaining minor-tier candidate).

## Operator-correction footnote (transparency)

A first-attempt autonomous v0.9.6 kickoff was committed at `5de3bbc` and **rolled back** within the same /loop tick when reading `lib/json-atomic.sh` source revealed two scope errors:

1. The `json_atomic_update <filter> [path]` API does not accept `--arg`/`--argjson` passthrough; the audit at `idea-stage/v0.9.x-arc-audit-2026-04-30.md:70` had explicitly flagged "needs json_atomic_update_args variant" — the original PRD missed this line and called the migration "mechanical".
2. Site count was inflated to 10; the real production-path count is 6 (8 PARALLEL_MODE sites are deferred per v0.9.5 design).

The rollback was clean (`git reset --hard origin/master` on the kickoff branch; master unchanged at `486ced9`). The corrected scope was written into the handoff, ratified by the operator, then re-staged at commit `884f10a`. Lesson preserved in `feedback_autonomous_kickoff_caution.md`: don't autonomously kick off cycles without thorough audit-doc reading.

## The 5 stories

| # | ID | Title | Outcome |
|:-:|---|---|:-:|
| 0 | (cycle setup) | chore: v0.9.6 cycle kickoff (corrected scope post-rollback) | committed at `884f10a` |
| 1a | US-001 T-001-1 | Add json_atomic_update_args variant + Tests 9-12 | first-attempt PASS at `df751b0` |
| 1b | US-001 T-001-2 | Migrate 6 production-path jq+tmp+mv sites | first-attempt PASS at `e75e6d3` |
| 2 | US-002 | Extract emit_terminal_signal helper; dedup 3 production-path COMPLETE/BLOCKED pairs | first-attempt PASS at `65a9195` |
| 3 | US-003 | CLAUDE.md tilde sync (`quantum-loop.sh:~1592` → `lib/iteration-loop.sh:~212`) + 3 LOW absorbs | first-attempt PASS at `c4f04e0` |
| 4 | US-004 | Multi-perspective post-merge review (8th application) + 2 inline fixes | first-attempt PASS at `5a9c08e` |
| 5 | US-005 | Retrospective + IDEA_REPORT_v33 + version bump 0.9.5 → 0.9.6 | this report |

## json_atomic_update_args API design

Required positional args: `filter`, `json_path`. Optional variadic tail: zero-or-more jq arg pairs forwarded via `"$@"` after `shift 2`. Empty-output guard parity with `json_atomic_update`. `write_quantum_json` atomic semantics (validates JSON before write; tmp+mv).

**Why a separate variant rather than extending `json_atomic_update`?** The existing helper takes `json_path` as the OPTIONAL second arg with default `quantum.json`. A variadic tail would collide with that default ambiguously. The variant takes path as REQUIRED; callers needing `--arg`/`--argjson` use this; callers with pre-validated inline values (existing 3 STORY_ID callers in `lib/iteration-loop.sh:363, 367, 370`) stay on the simpler API.

## Migration site map (US-001 T-001-2)

| Site | Args | Filter shape |
|---|---|---|
| `lib/iteration-loop.sh:147` | `--argjson ids` `--arg now` | wave-mark in_progress |
| `lib/iteration-loop.sh:382` | `--argjson ids` `--arg now` | WAVE_PASSED |
| `lib/iteration-loop.sh:402` | `--argjson ids` `--arg now` | WAVE_FAILED per-story aggregation |
| `lib/iteration-loop.sh:434` | `--argjson ids` `--arg now` | unknown-signal retries++ |
| `lib/loop-helpers.sh:84` | `--arg id` `--argjson threshold` | stale-detection reset |
| `quantum-loop.sh:357` | `--argjson max` | pre-loop maxAttempts setup |

PARALLEL_MODE 8 sites at `quantum-loop.sh:524-756` UNCHANGED per v0.9.5 design (extract when block extracts; v0.10.0 candidate).

## emit_terminal_signal helper (US-002)

Pure formatter, no exit, no control flow. 3 production-path call-site refactors:
- `lib/iteration-loop.sh:73-89` (sequential mode COMPLETE + BLOCKED)
- `lib/iteration-loop.sh:114-119` (coordinator mode COMPLETE + BLOCKED)
- `lib/iteration-loop.sh:343-368` (end-of-iteration sweep COMPLETE + BLOCKED)

PARALLEL_MODE pair at `quantum-loop.sh:467+476` UNCHANGED (deferred with the rest of the block).

The BLOCKED-with-format-string call site uses `$(printf '...' "$NEXT_WAVE_RC")` to pre-format vs adding a third format-string arg to the helper. Reviewer agreement: minimal interface, single-call-site convenience does not justify expanding the helper signature.

## Multi-perspective review synthesis (US-004, 8th application of pattern)

| Reviewer | Verdict | Score | Key finding |
|---|---|---:|---|
| **Architect** | SHIP | 93/100 | 2 LOW. F1: `2>/dev/null` swallows jq diagnostic in both helpers (parity-with-existing — DEFER to future hardening pass; score 88). F2: Test 12 ambiguous label split into 12a/12b (score 90 — INLINE FIX). |
| **Code-reviewer** | SHIP | 93/100 | 1 MEDIUM (parity-with-existing 2>/dev/null — same finding as architect F1; score 72 — DEFER). 1 LOW: CLAUDE.md `~208` should be `~212` (line 208 is comment, 212 is dispatch; score 88 — INLINE FIX). Comment-block restructure semantic-content-preservation verified via diff. |
| **Security** | SHIP | 95/100 | Zero findings. `"$@"` forwarding to jq preserves `--arg`/`--argjson` safe-binding (no injection vector). `printf "%s"` usage in `emit_terminal_signal` is safe. `RUNNER_EXIT` simplification verified safe under `set -u` (init at line 172 before all dispatch sites). All 6 migration sites preserved their pre-existing safety properties; migration also UPGRADES atomicity (write_quantum_json validates JSON pre-write). |

US-004 review pattern: **8th application** (post-v0.8.1, v0.8.2, v0.8.3, v0.8.4, v0.9.1, v0.9.3, v0.9.4, v0.9.5; SKIPPED v0.9.2 because US-004 was dogfood). Pattern stable.

## v0.9.6 fixes shipped + deferrals

### Closed

| Finding | Severity | Story |
|---|---|---|
| Audit MEDIUM (6 inline jq+tmp+mv migration; needs args variant) | MEDIUM | US-001 |
| Audit MEDIUM (3x duplicated COMPLETE/BLOCKED exit blocks — production paths) | MEDIUM | US-002 |
| Audit LOW (CLAUDE.md tilde line-number drift post-decomp) | LOW | US-003 |
| Code-reviewer LOW (`${RUNNER_EXIT:-0}` redundant default) | LOW | US-003 |
| Architect MEDIUM (~70 in original audit: bash -c subshell scoping comment) | LOW | US-003 |
| Code-reviewer LOW (29-line comment-block density) | LOW | US-003 |
| US-004 architect F2 (Test 12 ambiguous label) | LOW | US-004 inline |
| US-004 code-reviewer LOW (CLAUDE.md `~208` should be `~212`) | LOW | US-004 inline |

### Deferred to v0.10.0+

| Finding | Severity | Path |
|---|---|---|
| `2>/dev/null` swallows jq diagnostic in both helpers (parity-with-existing) | LOW | Future hardening pass touching both helpers symmetrically |
| PARALLEL_MODE block extraction (~390 LOC) | MEDIUM | v0.10.0 design pass needed |
| PARALLEL_MODE 8 jq sites + 1 COMPLETE/BLOCKED pair | (covered by above) | Migrate when block extracts |
| Real-feature dogfood (first non-synthetic dispatch) | MEDIUM | Separate cycle |
| p013/p014 canonization | LOW | Operator decision pending |
| **N40, N43, N46, N47-N50** | LOW | carried forward |

## Wave plan vs realized

US-001 sub-tasks T-001-1/2 are sequential (T-001-2 depends on the variant existing). US-002 dependsOn US-001 (touches same files). US-003 dependsOn US-002 (CLAUDE.md ref must point at post-extraction code). US-004 dependsOn first 3. US-005 dependsOn all.

Realized order under autonomous /loop:
1. cycle kickoff at `884f10a` (post-rollback corrected scope)
2. US-001 T-001-1 args variant + tests at `df751b0`
3. US-001 T-001-2 migrate 6 sites at `e75e6d3`
4. US-002 emit_terminal_signal at `65a9195`
5. US-003 doc sync + 3 LOWs at `c4f04e0`
6. US-004 review + 2 inline fixes at `5a9c08e`
7. US-005 (this retrospective)

## G30 self-validation — 27th consecutive LOW

Patch-tier framing held. `quantum-loop.sh` LOC unchanged at 793 (only 1 line touched in T-001-2). `lib/iteration-loop.sh` LOC slightly down (-12 net from US-002 dedup; +12 from comment subheaders; ≈neutral). Total cycle change: small additive helper (+30 LOC in json-atomic.sh) + 6 mechanical migrations + 3 print-pair refactors + comment restructure + doc edit. **27 consecutive LOW** (v0.6.5..v0.9.6).

## Test-suite delta vs v0.9.5

| Test file | v0.9.5 | v0.9.6 | delta |
|---|---:|---:|---:|
| `tests/test_json_atomic.sh` (+Tests 9, 10, 11, 12a, 12b) | 21 | 28 | +7 |
| **Total v0.9.6 added:** | | | **+7** |

Cumulative: ~125 → ~132 assertions.

## Manual-takeover streak

v0.9.6 driven via the autonomous /loop cron pattern (10-min cadence) **with 1 mid-cycle operator intervention**: the kickoff staging required explicit operator approval ("sure, let's proceed with staging v0.9.6") after the autonomous-kickoff rollback. Once kickoff was staged, US-001 through US-005 all first-attempt PASS via cron. **Streak: PARTIALLY BROKEN through v0.9.6** — operator scope-ratification needed once; story execution otherwise autonomous. Cumulatively: v0.9.3, v0.9.4, v0.9.5 fully autonomous; v0.9.6 needed 1 operator gate.

This is the EXPECTED behavior post `feedback_autonomous_kickoff_caution.md` save: autonomous-kickoff is gated on operator ratification when the scope assumes unverified facts. The /loop cron handled story execution end-to-end.

## codebasePatterns

p001-p012 carried forward. **p013 + p014 still ready for canonization** (now 7+ applications each; v0.9.6 was the 8th p014 application). Operator decision pending.

## Recommendation pointer

See `idea-stage/IDEA_REPORT_v33.md` for what's open after v0.9.6. **Recommendation:** v0.10.0 next (only remaining minor-tier candidate is PARALLEL_MODE extraction; everything else is LOW or operator-decision). Strong recommendation: v0.10.0 scope around (a) PARALLEL_MODE extraction, (b) the deferred `2>/dev/null` symmetric hardening of both jq helpers, (c) real-feature dogfood, (d) p013/p014 canonization.
