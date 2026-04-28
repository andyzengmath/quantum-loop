# IDEA_REPORT_v9 — what's still open after v0.6.8

**Date:** 2026-04-28
**Source:** `ql/v0.6.8-bundle` dogfood retrospective (US-007)
**Branch:** `ql/v0.6.8-bundle` (release tag v0.6.8)
**Predecessor:** `idea-stage/IDEA_REPORT_v8.md`

## Closed in v0.6.8

| ID | Story | Notes |
|---|---|---|
| **N6** | US-001 | `agents/orchestrator.md` § "Self-monitoring guard" — prose-only advisory listing 3 forbidden idioms ("while that runs", "let me proactively", "let me prepare US-XXX in parallel") + STALE-DETECT recovery action. Presence-only AC (5 assertions in `tests/test_orchestrator_self_monitor.sh`). Runtime enforcement queued as v0.6.9 N6-followup. |
| **N7** | US-002 | `references/soliton-finding-triage.md` (NEW): Workflow / Repro template / Examples sections. v0.6.7 G36 documented as worked HALLUCINATION example. Cross-linked from new `## Process references` section in CLAUDE.md. 5 assertions in `tests/test_soliton_triage_doc.sh`. |
| **N8** | US-003 | `tests/test_audit.sh::extract_function_comments` simplified to header-only. New `extract_function_full_comments` (header+body) added for Tests 36b/37b WHY-checks. Bloat-checks (Tests 36a/37a) keep header-only scope per G34's stated intent. 45/45 audit assertions preserved. |
| **N9** | US-004 | `references/test-wallclock-baselines.md` (NEW): 6-row platform-conditional baseline table (Git Bash vs Linux/CI). Cross-linked from CLAUDE.md `## Process references`. 4 assertions in `tests/test_wallclock_baselines_doc.sh`. Baseline-drift WARN-test deferred to v0.6.9 N9-followup. |
| **N10** | US-005 | `lib/deep-review.sh` comment block above the v0.6.7 G36 guard rewritten. Removed misleading "Mirrors compute_risk_score" claim; replaced with accurate explanation of structural difference (outer SHA-presence gate vs inner files_changed-count gate). Comment-only edit. 14/14 dispatch tests preserved. |
| **N11** | US-006 | `agents/orchestrator.md` Step 4B.5 else-branch: `rm -f .quantum-feature-diff.patch` moved from start-of-branch to end-of-branch. BLOCKS_MERGE skip-via-exit-1 documented as intentional behavior (patch remains for forensic inspection). 1 new assertion in `tests/test_deep_review_dispatch.sh` Test 7. |

The **N6-N11 cluster** (the v0.6.8 priority list from IDEA_REPORT_v8) is now **fully closed**. All 6 stories shipped first-attempt PASS in manual takeover. 0 retries.

## Persistent canon

**For codebasePatterns p009/p010/p011 verbatim definitions, see `idea-stage/PIPELINE_REPORT_v7.md` § "codebasePatterns harvested"** — the durable single source-of-truth across cycles. quantum.json is gitignored, so each new cycle's quantum.json author should re-seed from PIPELINE_REPORT_v7's table. v0.6.8 carried over p001-p011 unchanged; no new patterns harvested.

## Multi-cycle CSV milestone (12 rows, 33 findings, 4 cycles)

| Cycle | design | prd | plan | total |
|---|---|---|---|---:|
| v0.6.5 | 0/0/0/1 | 0/0/0/4 | 0/0/0/0 | 5 |
| v0.6.6 | 0/0/0/0 | 0/2/4/3 | 0/0/0/1 | 10 |
| v0.6.7 | 0/0/1/2 | 0/0/2/3 | 0/0/0/2 | 10 |
| v0.6.8 | 0/0/1/2 | 0/0/1/2 | 0/0/0/2 | 8 |
| **Total** | **0/0/3/5** | **0/2/7/12** | **0/0/0/5** | **33** |

Severity distribution: **0 crit / 2 high / 9 med / 22 low**. LOW remains 67 %. HIGH stable at 2 total (v0.6.6 prd-only).

**G22 retrospective territory at v0.7.x:** the patch-tier baseline (4 cycles, 12 rows) is now stable enough to use as a reference distribution. The next minor-tier or scope-shifted bundle can be histogrammed against this baseline to test whether the LOW-skew is a calibration artifact or genuine tier-correlation.

## Still open after v0.6.8

### G19 — 3-SKILL-wrapper centralization
**Status:** unchanged. Defer until a 4th pre-impl-review stage is added. ETA: indefinite.

### G21 — metrics CSV rotation
**Status:** premature. v0.6.8 ships at 12 rows. ETA: ~v1.0+.

### G22 — severity rubric calibration
**Status:** **first calibration pass feasible at v0.7.x.** 12-row patch-tier baseline is stable. Need 1-3 minor-tier bundles for the comparison axis. ETA: v0.7.0 retrospective should be the first pass.

### G24 — audit relative-path inconsistency
**Status:** unchanged.

### P5.B2 — schema validation for sprint-contract.json
**Status:** unchanged.

### P5.B3 — orchestrator state-machine formalization
**Status:** unchanged.

### P5.B5 — ql-execute idempotency proof
**Status:** unchanged. Empirically idempotent across v0.6.5..v0.6.8 (all 4 cycles 0-retry first-attempt PASS, 2 of which under manual-takeover recovery).

### P5.C frontier
**Status:** all deferred.

## Carried forward from v0.6.8 dogfood (already known)

### N6-followup — parent-side liveness check (orchestrator runtime enforcement)
**Surfaced:** v0.6.7 N6 (orchestrator subagent context-drift) → v0.6.8 N6 prose guard ships, but is presence-only.
**Severity:** MEDIUM. The prose guard is advisory; the LLM may not honor it. Two consecutive cycles (v0.6.7, v0.6.8) needed manual takeover.
**Path:** add a parent-side liveness check in `/ql-execute` SKILL or an orchestrator-spawning wrapper script: poll for committed changes after a configurable wall-clock; re-spawn or hand off to parent if no commits in N minutes. 0.5-1 stories.

### N9-followup — baseline-drift WARN-test
**Surfaced:** v0.6.8 N9 baselines reference shipped, but no automated drift detection.
**Severity:** LOW (process gap). Hand-update during retrospectives works for now.
**Path:** new `tests/test_wallclock_baseline_drift.sh` runs each baseline command with `time`, emits WARNING (not FAIL) if measured > 50 % over documented baseline. 0.25-0.5 stories.

## New gaps from v0.6.8 dogfood

### N12 — extract_function_comments / extract_function_full_comments naming clarity
**Surfaced:** v0.6.8 US-003 — split into 2 helpers required separate names. Current names work but the suffix `_comments` vs `_full_comments` is subtle.
**Severity:** LOW (naming taste).
**Path:** rename to e.g. `extract_function_header_comments` / `extract_function_all_comments` for sharper distinction. 0.1 stories. Defer indefinitely unless a confused future-maintainer surfaces it.

### N13 — manual-takeover pattern is the de facto recovery for orchestrator failures
**Surfaced:** v0.6.7 + v0.6.8 (2 consecutive cycles).
**Severity:** MEDIUM (process formalization). The pattern works but is unwritten.
**Path:** document in `references/orchestrator-takeover.md` (NEW) — when to detect drift, what to verify (git log, story status), how to take over without corrupting quantum.json state. Bundle with N6-followup (MEDIUM-priority v0.6.9 candidate). 0.25 stories.

## Recommendation for v0.6.9 or v0.7.0

**v0.6.9 candidate slate (patch-tier):**
1. **N6-followup** — parent-side liveness check (highest priority — closes the orchestrator-failure gap; MEDIUM).
2. **N13** — `references/orchestrator-takeover.md` (companion to N6-followup; MEDIUM).
3. **N9-followup** — baseline-drift WARN-test (LOW).
4. **N12** — helper rename for naming clarity (LOW; defer if no surfacing).

**v0.7.0 candidate slate (minor tier):**
1. **G22** — severity rubric calibration first pass against the 4-cycle 12-row baseline.
2. **G19** — 3-SKILL-wrapper centralization if a 4th pre-impl stage is added.
3. **P5.B2 / B3 / B5** — same as prior cycles' verdicts.

**Long-tail (deferred indefinitely):**
- G21, G24, P5.C frontier.

## Recurring observations

- **Manual takeover is the durable recovery mechanism**, not a one-off. v0.6.7 + v0.6.8 both shipped via parent-side execution after orchestrator drift. The N6 prose guard is the first formalized response; runtime enforcement (N6-followup) is the next step.
- **Patch-tier bundles structurally cluster at LOW tier.** v0.6.5/6/7/8 all produced LOW-tier diffs (score=25 in v0.6.6/7/8). The G30 dispatch gate routes them all to skip — 4 consecutive correct decisions.
- **0-retry execution record extends to v0.6.8** under manual takeover. Held since v0.6.0 across 4 patch-tier cycles.
- **Sequential mode is the right default.** All 7-story patch-tier bundles work cleanly in priority order with 1-2 dependsOn edges.
- **Mid-cycle discoveries continue to be productive.** v0.6.8 surfaced (a) US-001 regex form needed `[A-Z0-9]+` not `[0-9]+` for prose-placeholder match, (b) US-003 needed split-helper for accurate header-only-bloat / any-range-WHY semantics. Both became durable design improvements.
