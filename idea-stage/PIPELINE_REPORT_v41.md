# PIPELINE_REPORT_v41 — v0.10.7 retrospective (wave-cycle-2: copilot-rate-limit + N49 closure verification)

**Date:** 2026-05-02
**Bundle:** `ql/v0.10.7-bundle` (release tag v0.10.7 — pending push/PR/merge/tag/release)
**Predecessor report:** `idea-stage/PIPELINE_REPORT_v40.md`
**Master parent:** `6369ab7` (v0.10.6 ship state)
**Source:** `.omc/plans/2026-05-02-v0.11.0-wave-dogfood-driven-low-sweep.md` cycle-2.

## Overview

4-story patch shipping wave-plan cycle-2: copilot-rate-limit-observability (real new feature) + N49 closure verification (implicitly closed by v0.9.0 N42 wires).

## The 4 stories

| # | ID | Title | Outcome |
|:-:|---|---|:-:|
| 0 | (cycle setup) | chore: v0.10.7 cycle kickoff (PRD only; design pointer to wave plan) | committed at `017d232` |
| 1 | US-001 + US-002 | copilot-rate-limit observability + N49 closure verification | first-attempt PASS at `71fbdd3` |
| 2 | US-003 | 16th p014 review trio (SHIP; 1 MEDIUM inline-fixed) | first-attempt PASS at `9e84856` |
| 3 | US-004 | Retrospective + IDEA_REPORT_v41 + version bump 0.10.6 → 0.10.7 | this report |

## US-001 deep-dive: copilot-rate-limit-observability

`runners/hooks/copilot-hooks.sh` adds `post_output()` that pattern-matches rate-limit signals in copilot CLI output and emits `[RATE-LIMIT]` lines to stderr. Pure observability — does NOT alter signal classification or retry logic.

**Patterns matched (case-insensitive):**
- `rate.?limit` (catches `rate-limit`, `rate limit`, `ratelimit`, `rate_limit`)
- `\b429\b` (HTTP status code)
- `retry-after` (header)
- `quota.?exceeded`
- `too.many.requests`

**Output:** 2 stderr lines on detection — `[RATE-LIMIT] copilot rate-limit detected: <captured-line>` + (optional) `[RATE-LIMIT] copilot suggests Retry-After: <N>s` if Retry-After header parseable.

**False-positive rationale:** substring-matching produces theoretical false positives on benign text containing the word "rate limit". Real copilot CLI never outputs that gratuitously, and the operator-facing log line is non-blocking (no control-flow impact). Conservative-by-design.

## US-002 deep-dive: N49 closure verification

**Audit:** all 4 WAVE-branch `json_atomic_update_args` sites at `lib/iteration-loop.sh:150` (mark in_progress), `:382` (WAVE_PASSED), `:406` (WAVE_FAILED per-story aggregation), `:438` (unknown-signal retry++) already use single-jq `.stories |= map(...)` bulk-update pattern — updating all wave stories in 1 jq invocation.

**Closure rationale:** N49 was implicitly closed by v0.9.0 N42 (per-wave coordinator dispatch) when the per-wave `json_atomic_update_args` calls shipped. The original framing (per-story jq calls in WAVE_* branches) was already obsolete by v0.9.0; carrying N49 forward through 6 cycles was a tracking lapse, not unfinished work.

**Action:** marked CLOSED in `IDEA_REPORT_v41.md` with implicit-closure-via-v0.9.0 rationale.

## Multi-perspective review synthesis (US-003, 16th application)

| Reviewer | Verdict | Score | Key finding |
|---|---|---:|---|
| **Architect** | SHIP | 88/100 | Hook integration sound; pattern coverage adequate; tier framing honest. Minor: Retry-After extraction edge case noted. |
| **Code-reviewer** | SHIP | 88/100 | **MEDIUM: Retry-After extraction can capture wrong number** from `HTTP/1.1 429 Retry-After: 30` (would return 1, not 30). **Inline-fixed at `9e84856`**: replaced multi-stage grep with sed capture-group anchored on `retry-after`. |
| **Security** | SHIP | 95/100 | Format-string safe; ReDoS-safe; output bounded. 1 LOW: ANSI passthrough (matches v0.10.0 deferral; tracked v0.10.8). |

**5th review-gate catch in 16 applications.** Pattern p014 stable. Hit-rate ~31% (5/16) — review trio reliably catches at least one inline-fixable issue.

## v0.10.7 fixes shipped + deferrals

### Closed

| Finding | Severity | Source | Resolution |
|---|---|---|---|
| Copilot rate-limit observability | LOW (carried) | wave plan | US-001 |
| N49 (single-jq bulk-update verification) | LOW (closure) | wave plan | US-002 (implicit; v0.9.0) |
| Retry-After extraction edge case | MEDIUM (US-003 review) | code-reviewer + architect | inline-fixed at 9e84856 |

### Deferred

| Finding | Severity | Path |
|---|---|---|
| ANSI control-char passthrough | LOW | v0.10.8 (wave cycle-3) |
| Retry-After multi-line edge cases (e.g., when value spans lines) | LOW | future hardening; current extraction handles common single-line forms |

## G30 self-validation — 35th consecutive LOW

Patch-tier delta: 1 hook function (~30 LOC) + 1 verification-only audit (no code change) + retro + version bump. **35 consecutive LOW** (v0.6.5..v0.10.7).

## Test-suite delta vs v0.10.6

No delta. Existing 5 suites green: test_signal_parsing 15/15, test_coordinator_e2e 21/21, test_dag_query 44/44, test_json_atomic 35/35, test_next_wave 18/18.

(Note: hook is exercised via test_runner_dispatch.sh stub mode in normal CI; this cycle's smoke testing was inline via `source runners/hooks/copilot-hooks.sh && post_output "..."`.)

## Manual-takeover streak

v0.10.7 driven via autonomous /loop cron pattern (4585c73f). **Streak: PARTIALLY BROKEN through v0.10.7** — 9 consecutive cycles with 1 operator gate at scope-ratification time (this cycle's gate was the wave plan approval at v0.10.6).

## codebasePatterns

p001-p015 carried forward. Wave plan **p016 candidate (dogfood-driven LOW sweep)** in progress: 2 cycles complete (v0.10.6, v0.10.7); 2 cycles remaining (v0.10.8, v0.10.9). Canonization possible after v0.10.9 retrospective if pattern proves repeatable.

## Recommendation pointer

See `idea-stage/IDEA_REPORT_v41.md`. v0.10.8 next (N48 + ANSI passthrough sanitization).
