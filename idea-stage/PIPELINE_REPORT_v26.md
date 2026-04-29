# PIPELINE_REPORT_v26 — v0.8.4 retrospective (final v0.8.x close)

**Date:** 2026-04-29
**Bundle:** `ql/v0.8.4-bundle` (release tag v0.8.4 — pending push/PR/merge/tag)
**Predecessor report:** `idea-stage/PIPELINE_REPORT_v25.md`
**Master parent:** `a11e5c2` (v0.8.3 ship state)
**Source:** Multi-perspective post-v0.8.3 review surfaced 1 MEDIUM + 2 LOW + 4 cosmetic doc gaps; v0.8.4 closes them atomically.

## Overview

v0.8.4 is the **final close** of the v0.8.x track. After this cycle, all findings from all 4 multi-perspective post-merge reviews (across v0.8.0 → v0.8.4) are closed with zero deferred items. v0.9.0 N42 starts from a truly clean baseline.

## The 4 stories

| # | ID | Title | Outcome |
|:-:|---|---|:-:|
| 1 | US-001+US-002 | PS `WAVE_FAILED` retry accounting + `$storyId` defense-in-depth (atomic) | first-attempt PASS |
| 2 | US-003 | lib/spawn.sh idempotency source guard | first-attempt PASS |
| 3 | US-004 | 4 implementer-scoped doc updates to reference WAVE_* signals | first-attempt PASS |
| 4 | US-005 | Retrospective + IDEA_REPORT_v26 + version bump 0.8.3 → 0.8.4 | this report |

## Multi-perspective post-v0.8.3 review findings — disposition

| Finding | Severity | Disposition | Story |
|---|---|---|---|
| PS `WAVE_FAILED` arm missing retry accounting | MEDIUM | Closed | US-001 |
| `lib/spawn.sh` source-guard comment vs implementation mismatch | LOW | Closed | US-003 |
| PS `$storyId` defense-in-depth missing | LOW | Closed | US-002 |
| `CLAUDE.md` Signal Reference table lists only 4 signals | cosmetic | Closed | US-004 |
| `skills/ql-execute/SKILL.md` signal table lists only 4 signals | cosmetic | Closed | US-004 |
| `runners/preamble.md` signal protocol lists only 4 signals | cosmetic | Closed | US-004 |
| `templates/quantum-loop.ps1` 4-signal if-chain | cosmetic | Closed | US-004 (annotation only — implementer-scoped) |

## Five-cycle v0.8.x close (FULL SAGA)

| Cycle | Tier | Theme | Anti-pattern layer closed |
|---|---|---|---|
| v0.8.0 | minor | N33 closure infrastructure | (sets up) |
| v0.8.1 | patch | dogfood — wired inert pieces | layer 2 (caller) |
| v0.8.2 | patch | review hotfix — primary signal regex | layer 3 (signal parser) |
| v0.8.3 | patch | 4th-layer hotfix — parallel consumer sites | layer 4 (parallel consumers) |
| **v0.8.4** | **patch** | **final hotfix — residual polish** | **(no new layer; cosmetic + small fixes)** |

p012 (anti-presence-only AC) is now the strongest pattern in the codebase, validated at 4 distinct layers across 5 cycles.

## v0.9.0 N42 prerequisites — confirmed COMPLETE

- ✅ Signal parser recognizes 6 signals (lib/runner.sh:283 + lib/signal-heuristics.sh:36)
- ✅ Bash case switch routes WAVE_* (quantum-loop.sh:1607-1625)
- ✅ PowerShell parity (regex + switch arms + retry accounting + storyId validation)
- ✅ lib/spawn.sh sourced under both PARALLEL_MODE and COORDINATOR_MODE; idempotent guard
- ✅ CRLF hygiene + .gitattributes
- ✅ --coordinator --parallel rejection policy doc
- ✅ quantum.json field ownership doc
- ✅ Anti-presence-only regression-guard tests at 3 layers
- ✅ Implementer-scoped docs reference WAVE_* signals for cross-context clarity
- ❌ `lib/dag-query.sh::next_wave` does NOT exist — v0.9.0 US-002 must add it (in slate)

## Wave plan vs. realized

US-001 + US-002 (same file: quantum-loop.ps1, both small) committed atomically. US-003 + US-004 independent. US-005 dependsOn all.

Realized order under manual takeover (17th consecutive cycle):
1. US-001+US-002 → PS retry + storyId (atomic)
2. US-003 → spawn.sh source guard
3. US-004 → 4 doc updates
4. US-005 → this retrospective

## G30 self-validation — 20th consecutive LOW

`bash lib/deep-review.sh score $BASE $HEAD` → **score=≤25 tier=LOW files=≤7 sensitive=0 → skip**. Decision recorded with `automated:true`.

## Multi-cycle CSV milestone (sixteenth populated run)

`metrics/pre-impl-review-findings.csv` → 49 rows. Advisory hook findings for v0.8.4: design=1 (LOW: missing-rollout — v0.9.0 housekeeping shrink), prd=1 (LOW: ac-precision — US-004 templates form), plan=1 (LOW: dependency-graph — US-002→US-001 file conflict). All 3 LOW.

## Test-suite delta vs v0.8.3

No new test files. The lib/spawn.sh source-guard idempotency was verified inline via `bash -c 'source lib/spawn.sh; source lib/spawn.sh && echo OK'` (returned OK). Existing 6-signal coverage in test_signal_parsing.sh remains the regression baseline.

## Manual-takeover (17th consecutive cycle)

Pure reactive cycle. 4 stories, 0 retries. Multi-perspective review pattern is now standardized (4 cycles validated): architect + code-reviewer + security trio catches one anti-pattern layer per cycle until exhausted. v0.8.4 confirmed exhaustion — no new layer, only residual polish.

## codebasePatterns

p012 (anti-presence-only AC) — STRONGLY validated across 4 layers + 5 cycles. The pattern is mature enough to formalize into a checklist:

> When introducing a recovery wrapper, opt-in mode flag, OR a signal that another component must recognize:
> 1. Add the function/flag/signal definition.
> 2. Verify ≥1 non-test caller exists at every parallel consumer site (grep for the literal pattern across the entire repo).
> 3. Add a regression-guard test that exercises the actual call path, not just the definition's presence.
> 4. If the new signal/flag has cross-platform parity (bash + PowerShell), update both atomically.
> 5. If the new signal needs to appear in user-facing docs (CLAUDE.md, SKILL.md, preamble.md, templates), update them in the same cycle.

p013 candidate (multi-cycle layered-defect retrospective insight) — defer until v0.9.0+ proves it reusable.

## Recommendation pointer

See `idea-stage/IDEA_REPORT_v26.md` for what's open after v0.8.4.
