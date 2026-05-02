# PIPELINE_REPORT_v39 — v0.10.5 retrospective (CLAUDE.md drift fixes + missing-arg-guard parity)

**Date:** 2026-05-01
**Bundle:** `ql/v0.10.5-bundle` (release tag v0.10.5 — pending push/PR/merge/tag/release)
**Predecessor report:** `idea-stage/PIPELINE_REPORT_v38.md`
**Master parent:** `d7e8b1c` (v0.10.4 ship state)
**Source:** 3rd p015 doc-vs-code audit (post-v0.10.4) + v0.10.4 code-reviewer deferred MEDIUM.

## Overview

3-story patch closing 3 CLAUDE.md drift findings + 1 deferred MEDIUM + 1 inline-fixed HIGH (--tool missing-arg guard, caught by US-002 review).

## Headline result

**v0.10.x housekeeping arc TRULY COMPLETE.** All p015-flagged drift fixed; missing-arg-guard parity now covers all 5 value-taking CLI flags (--max-iterations, --max-retries, --max-parallel, --stale-timeout, --tool); CLAUDE.md p013/p014 counts current; p013 retro-ref corrected. v0.10.5 closes the longest-running v0.10.x housekeeping series at 5 patches (v0.10.1 → v0.10.5).

## The 3 stories

| # | ID | Title | Outcome |
|:-:|---|---|:-:|
| 0 | (cycle setup) | chore: v0.10.5 cycle kickoff | committed at `4051145` |
| 1 | US-001 | 4 sub-task fixes (CLAUDE.md drift + missing-arg-guard parity) | first-attempt PASS at `0aa9377` |
| 2 | US-002 | 14th p014 review trio + 1 HIGH inline fix (--tool missing-arg guard) | first-attempt PASS at `9dcb41d` |
| 3 | US-003 | Retrospective + IDEA_REPORT_v39 + version bump 0.10.4 → 0.10.5 | this report |

## 3rd p015 audit findings closed

| Finding | Severity | Source | Resolution |
|---|---|---|---|
| CLAUDE.md p013 count "9 applications" → 12 | MEDIUM | architect | T-001-1 |
| CLAUDE.md p014 count "10 review applications" → 13 | MEDIUM | architect | T-001-2 |
| CLAUDE.md p013 retro-ref `PIPELINE_REPORT_v33.md` → `v34.md` | MEDIUM | doc-specialist | T-001-3 |
| --max-* missing-arg-guard parity (4 flags) | MEDIUM (deferred from v0.10.4) | code-reviewer | T-001-4 |
| **--tool missing-arg-guard parity (5th flag, missed by initial PRD)** | **HIGH** | US-002 review | inline-fixed at `9dcb41d` |

## Multi-perspective review synthesis (US-002, 14th application)

| Reviewer | Verdict | Score | Key finding |
|---|---|---:|---|
| **Architect** | SHIP | 91/100 | Counts verified correct. Retro-ref correction acceptable. 1 LOW exit-code cosmetic (new guards use `exit 1` matching --max-* family; differs from --critic/--planner `exit 2` — self-consistent, not blocking). |
| **Code-reviewer** | REQUEST CHANGES → SHIP | 82 → ~92 | **HIGH: `--tool` flag missed initial PRD parity scope.** Inline-fixed at `9dcb41d`. Pattern parity confirmed: all 5 value-taking flags now have identical `if [[ $# -lt 2 || "${2:-}" == --* ]]` guards. |
| **Security** | SHIP | 95/100 | Zero actionable findings. Guard ordering correct (BEFORE assignment + regex). printf safe. |

## Notable: 3rd p014 review-gate catch in 14 applications

Pattern stable. Catches:
- v0.10.2 (12th p014): CRITICAL regex regression caught by code-reviewer
- v0.10.3 (13th p014): MEDIUM doc-honesty (overstated subsumption) caught by architect
- **v0.10.5 (14th p014): HIGH parity gap (--tool missed) caught by code-reviewer**

p014 hit-rate: 3 / 14 = ~21%. Validates the review-gate's spec-compliance-beyond-implementer-testing value over a meaningful sample size.

## v0.10.5 fixes shipped + deferrals

### Closed

All 4 v0.10.4-deferred items + 1 newly-found HIGH from US-002 review.

### Deferred

None. v0.10.x housekeeping arc complete.

### Standing backlog (unchanged from v0.10.4)

- Real-feature dogfood (blocked-on-operator-feature-queue).
- N40, N43, N46-N50, N38/N41/N44/N45/copilot-rate-limit (LOW carried).
- Pre-existing security LOWs (trap RETURN, ANSI passthrough; theoretical).

## G30 self-validation — 33rd consecutive LOW

Patch-tier delta: 4 mechanical doc/code edits + 1 inline-fixed parity addition + retro + version bump. **33 consecutive LOW** (v0.6.5..v0.10.5).

## Test-suite delta vs v0.10.4

No delta. Existing 5 suites green: test_signal_parsing 15/15, test_coordinator_e2e 21/21, test_dag_query 44/44, test_json_atomic 32/32, test_next_wave 18/18.

## Manual-takeover streak

v0.10.5 driven via autonomous /loop cron pattern + 1 mid-cycle operator scope-ratification ("let's kickoff" after the 3rd p015 audit synthesis). Once scoped, US-001 + US-002 + US-003 all first-attempt PASS via cron + agent dispatch (with 1 inline HIGH fix during US-002 review). **Streak: PARTIALLY BROKEN through v0.10.5** — 7 consecutive cycles with 1 operator gate at scope-ratification time.

## codebasePatterns

p001-p015 carried forward. v0.10.5 is the 3rd p015 application — pattern remains canonized at 2 applications (v0.10.1 + v0.10.2 retros explicitly flagged); v0.10.5 implicitly applied via operator request "go over all the docs and check wit with the implementation so far". May warrant updating CLAUDE.md p015 entry to "3 applications" in next cycle.

## Recommendation pointer

See `idea-stage/IDEA_REPORT_v39.md`. v0.10.x arc is now genuinely complete. v0.11.0 = feature-work return when operator queues something.
