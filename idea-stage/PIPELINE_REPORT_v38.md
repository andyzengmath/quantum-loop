# PIPELINE_REPORT_v38 — v0.10.4 retrospective (--max-parallel/--stale-timeout parity + subsumption correction + dogfood standing-backlog)

**Date:** 2026-05-01
**Bundle:** `ql/v0.10.4-bundle` (release tag v0.10.4 — pending push/PR/merge/tag/release)
**Predecessor report:** `idea-stage/PIPELINE_REPORT_v37.md`
**Master parent:** `dd8cb8d` (v0.10.3 ship state)
**Source:** Operator-approved scope per `idea-stage/IDEA_REPORT_v37.md` v0.10.4+ candidate slate.

## Overview

5-story patch closing 3 explicit v0.10.3-deferred items + standard cycle ceremony.

## Headline result

**v0.10.x housekeeping arc complete.** All v0.10.0-v0.10.3 review-deferred items closed: --max-parallel/--stale-timeout integer-validation parity (matching v0.10.2/v0.10.3 pattern); subsumption-claim wording correction (architect MEDIUM doc-honesty fix); dogfood reclassified from per-cycle US-003 to standing-backlog item documented in CLAUDE.md.

## The 5 stories

| # | ID | Title | Outcome |
|:-:|---|---|:-:|
| 0 | (cycle setup) | chore: v0.10.4 cycle kickoff | committed at `1dc3e27` |
| 1 | US-001 + US-002 + US-003 | --max-parallel/--stale-timeout parity + subsumption correction + dogfood standing-backlog (single commit) | first-attempt PASS at `97d7329` |
| 2 | US-004 | 13th p014 review trio (ALL SHIP; no inline fixes) | first-attempt PASS at `7e187c7` |
| 3 | US-005 | Retrospective + IDEA_REPORT_v38 + version bump 0.10.3 → 0.10.4 | this report |

## Asymmetric regex rationale (US-001)

| Flag | Regex | 0 accepted? | Rationale |
|---|---|:-:|---|
| `--max-iterations` | `^(0|[1-9][0-9]*)$` | YES | 0 = smoke-test sentinel (empty `seq 1 0` falls through to MAX_ITERATIONS terminal signal) |
| `--max-retries` | `^(0|[1-9][0-9]*)$` | YES | 0 = "disable retries" sentinel |
| `--max-parallel` | `^[1-9][0-9]*$` | NO | 0 parallel agents = nothing to dispatch (degenerate) |
| `--stale-timeout` | `^[1-9][0-9]*$` | NO | 0-min stale threshold = every story immediately stale (degenerate) |

Justified per architect review (consumer-trace verification).

## Multi-perspective review synthesis (US-004, 13th application)

| Reviewer | Verdict | Score | Key finding |
|---|---|---:|---|
| **Architect** | SHIP | 88/100 | All 4 questions answered. Asymmetric regex justified. CLAUDE.md placement appropriate. Doc-edit traceability corrective not revisionist. Tier framing honest. |
| **Code-reviewer** | SHIP | 92/100 | 1 MEDIUM pre-existing missing-argument guard inconsistency (--max-iterations/--max-retries/--max-parallel/--stale-timeout lack explicit `$# -lt 2` guard that --critic/--planner have). Pre-existing on master; not regressed. Track for v0.10.5+. Spec PASS for all 5 ACs. Zero existing usage of `--max-parallel 0` or `--stale-timeout 0` in repo. |
| **Security** | SHIP | 95/100 | ZERO actionable findings. Regex anchored + ReDoS-safe; validation gates assignment; printf %s safe. Confirmed no other un-validated integer CLI flags remain. |

US-004 review pattern: **13th application** (post-v0.8.1, v0.8.2, v0.8.3, v0.8.4, v0.9.1, v0.9.3-v0.10.3; SKIPPED v0.9.2). p014 stable.

## v0.10.4 fixes shipped + deferrals

### Closed

| Finding | Severity | Story |
|---|---|---|
| --max-parallel + --stale-timeout integer validation parity | LOW (deferred from v0.10.3 review) | US-001 |
| Subsumption-claim wording correction in 4 docs | LOW (architect honesty MEDIUM from v0.10.3) | US-002 |
| Dogfood per-cycle deferral → standing-backlog conversion | LOW (process; architect recommendation v0.10.3) | US-003 |

### Deferred to v0.10.5+ backlog

| Finding | Severity | Source |
|---|---|---|
| Missing-argument guard inconsistency across CLI integer flags (no `$# -lt 2` guard on `--max-iterations`/`--max-retries`/`--max-parallel`/`--stale-timeout`; vs explicit guard on `--critic`/`--planner`/`--executor`/`--reviewer`) | MEDIUM (pre-existing) | code-reviewer |
| Real-feature dogfood (now standing backlog) | MEDIUM | blocked-on-operator-feature-queue |

## Wave plan vs realized

US-001/002/003 file-disjoint (CHANGELOG sequentially-safe). US-004 dependsOn first 3. US-005 dependsOn all.

Realized:
1. Cycle kickoff at `1dc3e27`
2. US-001+US-002+US-003 single commit at `97d7329`
3. US-004 review at `7e187c7`
4. US-005 (this retrospective)

## G30 self-validation — 32nd consecutive LOW

Patch-tier delta: 2-line code addition + 4 doc-wording corrections + 1 new CLAUDE.md subsection + retro + version bump. **32 consecutive LOW** (v0.6.5..v0.10.4).

## Test-suite delta vs v0.10.3

No delta. Existing suites green: test_signal_parsing 15/15, test_coordinator_e2e 21/21, test_dag_query 44/44, test_json_atomic 32/32, test_next_wave 18/18.

## Manual-takeover streak

v0.10.4 driven via the autonomous /loop cron pattern with 1 mid-cycle operator scope-ratification ("Let's continue to v0.10.4+ candidates ..."). Once scope ratified, US-001 + US-002 + US-003 + US-004 + US-005 all first-attempt PASS via cron + agent dispatch. **Streak: PARTIALLY BROKEN through v0.10.4** — 6 consecutive cycles with 1 operator gate at scope-ratification time.

## codebasePatterns

p001-p015 carried forward. No new patterns identified.

## Recommendation pointer

See `idea-stage/IDEA_REPORT_v38.md`. v0.10.5+ optional patch for the missing-argument guard parity. Otherwise v0.11.0 feature work when operator queues something.
