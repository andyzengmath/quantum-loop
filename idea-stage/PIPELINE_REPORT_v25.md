# PIPELINE_REPORT_v25 — v0.8.3 retrospective (4th-layer N33 closure)

**Date:** 2026-04-29
**Bundle:** `ql/v0.8.3-bundle` (release tag v0.8.3 — pending push/PR/merge/tag)
**Predecessor report:** `idea-stage/PIPELINE_REPORT_v24.md`
**Master parent:** `1076eef` (v0.8.2 ship state)
**Source:** Multi-perspective post-v0.8.2 review (architect + code-reviewer + security agents)

## Overview

v0.8.3 closes the **fourth, fifth, and sixth layers** of the N33 root-cause #1 anti-pattern (presence-only AC at parallel signal-wire sites). v0.8.2 fixed the primary signal regex; multi-perspective review found that 3 parallel sites in bash code + 1 PowerShell mirror were missed. v0.8.3 closes them atomically + tightens 2 trivially-passing tests.

## The 4 stories

| # | ID | Title | Outcome |
|:-:|---|---|:-:|
| 1 | US-001 | Close 3 WAVE_* wire sites in bash code (signal-heuristics regex + case switch + source gate) | first-attempt PASS |
| 2 | US-002 | PowerShell parity (regex + switch arms in quantum-loop.ps1) | first-attempt PASS |
| 3 | US-003 | Tighten test_signal_parsing.sh negative assertions (Tests 9 & 10) | first-attempt PASS (test count 13 → 15) |
| 4 | US-004 | Retrospective + IDEA_REPORT_v25 + version bump 0.8.2 → 0.8.3 | this report |

## What the multi-perspective review found

| Reviewer | TL;DR | Action in v0.8.3 |
|---|---|---|
| **Architect** | v0.8.2 closes prerequisites; new RISK: case switch missing WAVE_* branches + spawn.sh source-gate scoped to PARALLEL only. | US-001 (case branches + source gate) |
| **Code-reviewer** | REQUEST CHANGES. HIGH: signal-heuristics.sh regex still 4-signal. MEDIUM: PowerShell parity gap. LOW: trivially-passing tests. | US-001 (regex), US-002 (PS parity), US-003 (test tightening) |
| **Security** | NOT a security regression. All surfaces clean. | None required. |

## Four-layer N33 root-cause #1 closure (full saga)

The "presence-only AC" anti-pattern repeated four times across v0.7.x → v0.8.x:

| Layer | Cycle | Defect | Caught by |
|---|---|---|---|
| 1 (function) | v0.7.x | `wrap_orchestrator_dispatch` defined; zero callers | v0.8.0 5-agent research synthesis |
| 2 (caller) | v0.8.0 | `ql_wrap_subagent_dispatch` defined; zero callers in dispatch loop | v0.8.1 dogfood (static grep) |
| 3 (signal parser) | v0.8.0 | `runner_parse_output` regex missing `WAVE_*` | v0.8.2 architect review |
| 4 (parallel consumers) | v0.8.2 | `signal-heuristics.sh` regex + `quantum-loop.sh` case switch + spawn.sh source-gate + PowerShell mirror all missing `WAVE_*` | v0.8.3 architect + code-reviewer review |

Each layer was caught by a different validation pattern. Lesson: **search ALL parallel consumer sites before declaring closure** — not just the primary one. p012 (anti-presence-only AC) reinforced.

## v0.8.3 fixes shipped

### US-001 — 3 atomic wire fixes in bash code

**`lib/signal-heuristics.sh:33`**: regex extended from 4 to 6 signals (mirrors `lib/runner.sh:283`). The heuristic-fallback path now recognizes wave signals on non-Claude runners.

**`quantum-loop.sh:1570` case switch**: explicit `WAVE_PASSED)` and `WAVE_FAILED)` branches added before the `*)` wildcard. WAVE_PASSED maps to story-progressing (continue); WAVE_FAILED maps to retry (increment `retries.attempts` + append to `failureLog`). v0.9.0 N42 may refine wave-to-story mapping.

**`quantum-loop.sh:687` source gate**: extended to source `lib/spawn.sh` and `lib/dag-query.sh` under `COORDINATOR_MODE=true` (parallel to `PARALLEL_MODE=true`). v0.9.0 N42's `spawn_coordinator()` now defined at call time. Idempotent — `lib/spawn.sh` has its own source guard.

### US-002 — PowerShell parity

`quantum-loop.ps1:364` regex extended; switch block gains explicit `"WAVE_PASSED"` and `"WAVE_FAILED"` arms. PowerShell entry-point now in lockstep with bash.

### US-003 — Tighten test_signal_parsing.sh negative assertions

Tests 9 and 10 each gain `SIGNAL_CONFIDENCE != "exact"` assertion. The trivial-pass regression (broken regex returning empty for everything) would no longer be silent. Test count: 13 → 15.

## What v0.8.3 does NOT close

| Open item | Type | v0.9.0 implication |
|---|---|---|
| **N42**: real per-wave dispatch (replace single-spawn loop with `spawn_coordinator`-driven wave loop) | architectural | minor-tier scope; **prerequisites NOW genuinely complete** |
| **N43**: parallel-with-dispatch wrap pattern | implementation refinement | requires Git Bash background-process supervision; defer to v0.9.1+ |

## Wave plan vs. realized

US-001 + US-002 + US-003 are independent. US-004 dependsOn all.

Realized order under manual takeover (16th consecutive cycle):
1. US-001 → 3 atomic wire fixes (largest delta; biggest cycle artifact)
2. US-002 → PowerShell parity
3. US-003 → test tightening
4. US-004 → this retrospective

| File | Stories |
|---|---|
| `lib/signal-heuristics.sh` | US-001 (regex extension) |
| `quantum-loop.sh` | US-001 (case switch + source gate) |
| `quantum-loop.ps1` | US-002 (regex + switch arms) |
| `tests/test_signal_parsing.sh` | US-003 (non-exact-confidence guards) |
| `idea-stage/PIPELINE_REPORT_v25.md` (NEW) | US-004 |
| `idea-stage/IDEA_REPORT_v25.md` (NEW) | US-004 |
| `CHANGELOG.md` + 4 manifests | US-004 |

## G30 self-validation — 19th consecutive LOW

`bash lib/deep-review.sh score $BASE $HEAD` → **score=≤25 tier=LOW files=≤6 sensitive=0 → skip**. Decision recorded with `automated:true`. **19 consecutive LOW-tier self-validations** (v0.6.5..v0.8.3).

## Multi-cycle CSV milestone (fifteenth populated run)

`metrics/pre-impl-review-findings.csv` → 46 rows. Advisory hook findings for v0.8.3: design=1 (LOW: missing-rollout — atomic-rollback semantics for 3-site US-001), prd=1 (LOW: ac-precision — story-status semantics for wave case branch), plan=1 (LOW: dependency-graph — atomicity caveat). All 3 LOW.

## Test-suite delta vs v0.8.2

| Test file | v0.8.2 | v0.8.3 | delta |
|---|---:|---:|---:|
| `tests/test_signal_parsing.sh` | 13 | 15 | +2 (Tests 9/10 non-exact-confidence) |
| **Total v0.8.3 added:** | | | **+2** |

## Manual-takeover (16th consecutive cycle)

v0.8.3 dogfood ran with v0.8.2 master HEAD as parent. Pure reactive cycle. 4 stories, 0 retries.

## codebasePatterns

p012 (anti-presence-only AC) **strongly reinforced** — now caught at 4 distinct layers. The pattern is reusable:

> When introducing a recovery wrapper, opt-in mode flag, OR a signal that another component must recognize, the AC must include "function/flag/signal has ≥1 non-test consumer in production code at EVERY parallel site". Grep-based AC text alone passes for the *definition* and silently leaves the wire dead at any unmentioned site. v0.8.3 ships the third regression-guard test (signal parser tightening) and proves the pattern at 4 layers.

Defer p013 candidate (multi-cycle layered-defect retrospective insight) until empirically proven reusable across an architectural cycle (likely v0.9.0+).

## Recommendation pointer

See `idea-stage/IDEA_REPORT_v25.md` for what's open after v0.8.3.
