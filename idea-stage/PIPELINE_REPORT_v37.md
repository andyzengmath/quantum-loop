# PIPELINE_REPORT_v37 — v0.10.3 retrospective (--max-retries parity + test_v081_wiring delete + 4th dogfood deferral)

**Date:** 2026-05-01
**Bundle:** `ql/v0.10.3-bundle` (release tag v0.10.3 — pending push/PR/merge/tag/release)
**Predecessor report:** `idea-stage/PIPELINE_REPORT_v36.md`
**Master parent:** `bd3df91` (v0.10.2 ship state)
**Source:** Operator-approved scope post-v0.10.2: "--max-retries parity validation + test_v081_wiring.sh restore-or-delete + deferred dogfood".

## Overview

5-story patch closing 2 deferred items + 1 explicit-defer + standard cycle ceremony.

## Headline result

**v0.10.2 deferral list FULLY CLOSED** (--max-retries parity + test_v081_wiring decision). Real-feature dogfood deferred for the 4th cycle (v0.10.0 → v0.10.3). New honest framing: dogfood is **blocked-on-operator-feature-queue**, not an infinite-deferral pattern — manufacturing synthetic features adds ceremony without value.

## The 5 stories

| # | ID | Title | Outcome |
|:-:|---|---|:-:|
| 0 | (cycle setup) | chore: v0.10.3 cycle kickoff | committed at `125fd25` |
| 1 | US-001 + US-002 + US-003 | --max-retries parity + test_v081_wiring delete + dogfood deferral (single commit) | first-attempt PASS at `87b3998` |
| 2 | US-004 | 12th multi-perspective post-merge review (SHIP; 1 inline fix) | first-attempt PASS at `ed7533c` |
| 3 | US-005 | Retrospective + IDEA_REPORT_v37 + version bump 0.10.2 → 0.10.3 | this report |

## Audit-trail summary

### Closed

| Finding | Severity | Story | Resolution |
|---|---|---|---|
| --max-retries argparse integer-validation parity gap | security LOW (deferred from v0.10.2 US-005) | US-001 | Same regex pattern as --max-iterations applied |
| test_v081_wiring.sh 4/5 stale failures (v0.8.1-era assertions) | LOW (deferred from v0.10.2 retro) | US-002 | DELETED (138 LOC); v0.8.1 placeholders v0.9.0 superseded; coverage subsumed by current suites (with caveats — see Honest scope drift below) |
| US-004 code-reviewer MEDIUM: stale `tests/test_v081_wiring.sh:121` ref in `quantum-loop.sh:165` comment | MEDIUM | US-004 inline | Comment refreshed; self-contained explanation of 0 sentinel semantics |

### Deferred to v0.10.4+ backlog

| Finding | Severity | Source |
|---|---|---|
| --max-parallel + --stale-timeout integer validation parity (matches --max-iterations + --max-retries pattern) | LOW (operator-only attack surface; bash integer compares fail safely) | architect + security agreed |
| Subsumption-claim wording correction in this retro: technically test_v081_wiring's wiring-reachability checks (`ql_wrap_subagent_dispatch` caller, `COORDINATOR_MODE` consultation, dead-`-z` guard form) have NO direct equivalent in current suites — only `test_quantum_loop_recovery.sh:49` does definition-only grep. The deletion is still defensible (the v0.8.1 placeholders v0.9.0 replaced; the wiring is exercised functionally by test_coordinator_e2e even if not asserted by symbol grep), but "subsumed" was overstated. **Honest framing: obsoleted-by-v0.9.0-rewrite; residual wiring-reachability gap accepted as low-risk.** | LOW (honesty/doc) | architect |
| US-003 dogfood story should become a standing backlog item (not per-cycle deferral) | LOW (process) | architect |
| Real-feature dogfood (4th cycle of deferral) | MEDIUM | blocked-on-operator-feature-queue |

## Multi-perspective review synthesis (US-004, 12th application)

| Reviewer | Verdict | Score | Key finding |
|---|---|---:|---|
| **Architect** | SHIP | 78/100 | 1 MEDIUM (overstated subsumption claim); 1 LOW (--max-parallel/--stale-timeout parity gap); recommends dropping US-003 dogfood as carried story. |
| **Code-reviewer** | SHIP | 92/100 | 1 MEDIUM (stale comment at quantum-loop.sh:165 referencing just-deleted file). Inline-fixed at ed7533c. |
| **Security** | SHIP | 95/100 | ZERO actionable findings. Pre-existing observation: --max-parallel/--stale-timeout same gap (LOW). |

US-004 review pattern: **12th application** (post-v0.8.1, v0.8.2, v0.8.3, v0.8.4, v0.9.1, v0.9.3-v0.10.2; SKIPPED v0.9.2). p014 stable + canonized in CLAUDE.md per v0.10.0 US-004.

## Notable: Architect score dropped to 78/100

Lowest p014 architect score in the 12-cycle history. Reason: the architect's MEDIUM (overstated subsumption claim) was a real honesty gap — the design doc claimed "subsumed by 5 test suites" but spot-grep for `ql_wrap_subagent_dispatch` + `COORDINATOR_MODE` returned ZERO hits in those 5 suites. The deletion is still defensible (different framing: "obsoleted by v0.9.0 rewrite"), but the original wording was inaccurate. **This 2nd p014 catch in 12 applications validates the review-gate value beyond the implementer's local verification — the implementer wrote the subsumption claim from the design doc, didn't verify the grep evidence themselves.**

## US-003 (4th cycle dogfood deferral)

Cumulative deferral history:
- v0.10.0 US-003: deferred (no operator scope ready)
- v0.10.1: not in scope (audit-cleanup cycle)
- v0.10.2: not in scope (audit-cleanup cycle)
- v0.10.3 US-003: STILL DEFERRED (no operator-queued feature)

**New framing:** "Blocked-on-operator-feature-queue" — dogfood requires a real feature to dispatch through `quantum-loop.sh --coordinator`. Synthesizing a fake feature (e.g., dispatching v0.10.3's own work via --coordinator) would be ceremony without value: the cycle's housekeeping work is BY DESIGN low-risk and direct-commit-friendly; routing it through coordinator dispatch tests the dispatch path, not the housekeeping work. Architect recommends dropping US-003 as a per-cycle story and tracking it as a standing backlog item.

**Decision: accepted.** v0.10.4+ will not carry US-003 unless a real feature is queued.

## G30 self-validation — 31st consecutive LOW

Patch-tier delta: 1 trivial regex addition + 138-line file deletion + 1 inline comment fix + retro + version bump. **31 consecutive LOW** (v0.6.5..v0.10.3).

## Test-suite delta vs v0.10.2

| Test file | v0.10.2 | v0.10.3 | delta |
|---|---:|---:|---:|
| `tests/test_v081_wiring.sh` | 5 (1 passing) | DELETED | -5 (file removed) |
| **Net change:** | | | **-1 file, ~-5 nominal cases** |

Remaining suites: `test_signal_parsing` 15/15, `test_coordinator_e2e` 21/21, `test_dag_query` 44/44, `test_json_atomic` 32/32, `test_next_wave` 18/18 — all green.

## Manual-takeover streak

v0.10.3 driven via the autonomous /loop cron pattern with 1 mid-cycle operator scope-ratification ("Let's continue with v0.10.3 patch: ..."). Once scope ratified, US-001 + US-002 + US-003 + US-004 + US-005 all first-attempt PASS via cron + agent dispatch (with 1 inline fix during US-004 review). **Streak: PARTIALLY BROKEN through v0.10.3** — same posture as v0.9.6 + v0.10.0 + v0.10.1 + v0.10.2 (1 operator gate at scope-ratification time; story execution autonomous).

## codebasePatterns

p001-p015 carried forward. No new patterns identified.

## Recommendation pointer

See `idea-stage/IDEA_REPORT_v37.md` for what's open after v0.10.3. v0.10.4+ optional patch for --max-parallel/--stale-timeout parity + standing-backlog conversion of US-003. Otherwise pivot to v0.11.0 feature work when operator queues something.
