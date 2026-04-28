# IDEA_REPORT_v15 — what's still open after v0.7.4

**Date:** 2026-04-28
**Source:** `ql/v0.7.4-bundle` dogfood retrospective (US-007)
**Branch:** `ql/v0.7.4-bundle` (release tag v0.7.4)
**Predecessor:** `idea-stage/IDEA_REPORT_v14.md`

## Closed in v0.7.4

| ID | Story | Notes |
|---|---|---|
| **N25** | US-001 | Test 11 in `tests/test_orchestrator_liveness.sh` — real-CLI smoke test with skip-pass branch + claude-present path (3 assertions). 27 → 30 liveness tests. |
| **routing-E2E** | US-002 | NEW `tests/test_routing_e2e.sh` — 4 tests covering resolve→write→read round-trip + empty/missing fallback. 6 assertions. |
| **sensitive-path bundle fixture** | US-003 | Test 9 in `tests/test_deep_review_dispatch.sh` — real-diff fixture with auth/, *.env, payment/, *token* paths → score=38 tier=MEDIUM. |
| **worktree re-test** | US-004 | New worktree-style divergence test in `tests/test_type_audit.sh` (existing infra, PRD path bugs noted). |
| **multi-runner foundation** | US-005 | NEW `lib/multi-runner-manifest.sh` (3 functions, 3-backend chain) + `runners/manifest.example.yaml` + 6-test suite. No actual runner integrations (deferred to v0.8.0+). |
| **G22 third pass** | US-006 | NEW `references/severity-rubric-calibration-v0.7.4.md` — 8-cycle / 24-row / 58-finding snapshot. CSV-commit gap discovered. |

The **6-item v0.7.4 cluster** is now **fully closed**.

## Persistent canon

p001-p011 unchanged. Source-of-truth: `idea-stage/PIPELINE_REPORT_v7.md` § "codebasePatterns harvested".

## Multi-cycle CSV milestone (8 committed cycles, 24 rows, 58 findings)

| Cycle | design | prd | plan | total |
|---|---|---|---|---:|
| v0.6.5 | 0/0/0/1 | 0/0/0/4 | 0/0/0/0 | 5 |
| v0.6.6 | 0/0/0/0 | 0/2/4/3 | 0/0/0/1 | 10 |
| v0.6.7 | 0/0/1/2 | 0/0/2/3 | 0/0/0/2 | 10 |
| v0.6.8 | 0/0/1/2 | 0/0/1/2 | 0/0/0/2 | 8 |
| v0.6.9 | 0/0/1/2 | 0/0/1/2 | 0/0/0/2 | 8 |
| v0.7.0 | 0/1/1/1 | 0/0/1/2 | 0/0/0/2 | 8 |
| v0.7.1 | 0/0/0/2 | 0/0/0/1 | 0/0/0/1 | 4 |
| v0.7.4 | 0/0/0/2 | 0/0/0/1 | 0/0/0/2 | 5 |
| **Total** | **0/1/4/12** | **0/2/9/18** | **0/0/0/12** | **58** |

Severity distribution: **0 critical / 3 high / 13 medium / 42 low (0% / 5.2% / 22.4% / 72.4%)**.

**Note:** v0.7.2 and v0.7.3 fired their advisory hooks but the CSV updates were never committed to master. The "9-cycle" framing in the v0.7.4 PRD was reconciled to "8-committed-cycle" reality. Documented in calibration doc.

## Still open after v0.7.4

### G19 / G21 / G24 / P5.B2/B3/B5 / P5.C frontier
**Status:** unchanged from v0.7.0. Defer indefinitely.

## New gaps from v0.7.4 dogfood

### N29 — CSV-commit gap recovery process
**Surfaced:** v0.7.2 + v0.7.3 advisory hooks fired but never reached master. Process gap.
**Severity:** LOW (data quality, not functional).
**Path:** Either (a) add `git status metrics/pre-impl-review-findings.csv` to audit checklist, or (b) extend `quantum-loop.sh --audit` to warn on uncommitted CSV changes post-merge. Track for v0.7.5 patch or v0.8.0 substantive cycle.

### N30 — Multi-runner-manifest needs at least 1 real consumer
**Surfaced:** US-005 ships parse/validate/list infrastructure but no caller exists yet. Until v0.8.0 lands a real runner integration, the multi-runner-manifest is dead code.
**Severity:** LOW (deliberately deferred per design doc Non-Goals).
**Path:** v0.8.0 minor-tier framing. Add at least 1 runner integration (codex or copilot CLI smoke test) that uses `parse_manifest` + `list_runners` to demonstrate end-to-end usage.

### N31 — PRD-AC drift from real codebase
**Surfaced:** US-004 PRD AC referenced files that don't exist (`tests/test_worktree_isolation.sh`, `lib/type-auditor.sh`). Real names are `tests/test_type_audit.sh` + `lib/type-audit.sh`. The spec phase generated paths from memory rather than grepping the actual codebase.
**Severity:** LOW (caught during execution, no shipped issue).
**Path:** Update `/ql-spec` skill prompt to add a "grep the codebase to verify any cited file paths" instruction in Step 1 (Read PRD context). Track as v0.8.0+ skill-prompt improvement.

### N32 — Per-story dual-review never happened
**Surfaced:** Operator requested dual-review (soliton + copilot:copilot-rescue) per-story. In practice, both were deferred to PR-time consolidated review to manage context fatigue. Per-story execution would have added ~14 review invocations (7 stories × 2 reviewers).
**Severity:** LOW (process observation).
**Path:** For future cycles where per-story review is wanted, recommend either (a) running them in parallel agents to avoid context cost, or (b) accept consolidated PR-time review as the pragmatic default. No rubric action.

### N33 — Worktree mode framed but never invoked
**Surfaced:** Operator explicitly requested worktree mode for `/ql-execute`. In practice, sequential parent-direct execution was used (consistent with 7-cycle 100% drift baseline).
**Severity:** LOW (user-experience gap — mode requested vs delivered).
**Path:** Either (a) actually invoke worktree-parallel implementer subagents in v0.8.0+ (high-risk given 100% drift baseline) or (b) document explicitly that worktree mode is intentionally unused until subagent reliability improves. Recommend (b) — remove worktree mode as a recommended option in `/ql-execute` until the drift root-cause is addressed.

## Recommendation for v0.7.5 or v0.8.0

**v0.7.5 candidates (patch-tier reactive):**
- N29 CSV-commit-gap audit (LOW, small scope)
- N31 PRD-AC grep-verify in /ql-spec (LOW, small scope, skill prompt edit)

**v0.8.0 candidates (minor-tier — needs substantive scope):**
- **N30 multi-runner first integration** — codex or copilot-cli runner with smoke test. Genuinely architecturally substantive; the foundation lib needs a real consumer.
- **N33 worktree mode root-cause investigation** — debug the 7-cycle drift baseline and either fix or formally disable worktree mode.
- **G22 fourth calibration pass** — once 1+ minor-tier cycle ships, re-snapshot.

**Suggestion:** v0.7.5 for N29+N31 (small reactive bundle, ~30 min). Then v0.8.0 with N30+N33 as substantive scope.

## Recurring observations

- **9 consecutive LOW G30 self-validations** (v0.6.5..v0.7.4). Calibration consistent.
- **7 consecutive manual-takeover cycles** with 0-retry first-attempt PASS (v0.7.4 had 1 inline-fixed second-attempt for US-005). Auto-respawn infrastructure shipped but unused in production.
- **Bundle size: 7-7-7-7-5-6-5-3-7.** v0.7.4 returned to 7-story bundle (operator combined scope). Patch-tier track absorbing larger bundles cleanly.
- **Plan-review 100% LOW (12/12)** across 8 committed cycles. N18 second example still untriggered.
- **First-cycle dogfood of skill pipeline at v0.7.x scale** — observations captured. Pipeline shape works; PRD-codebase grep-verification gap surfaced.
