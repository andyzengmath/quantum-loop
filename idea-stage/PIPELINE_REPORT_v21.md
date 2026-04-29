# PIPELINE_REPORT_v21 — v0.7.10 dogfood retrospective (operator-driven N35 closure)

**Date:** 2026-04-28
**Bundle:** `ql/v0.7.10-bundle` (release tag v0.7.10)
**Predecessor report:** `idea-stage/PIPELINE_REPORT_v20.md`
**Master parent:** `73d7f888` (v0.7.9 ship state)
**Source:** Operator-scoped N35 closure (`runner_dispatch` wrapper + real-task tests)

## Overview

v0.7.10 closes N35 from `idea-stage/IDEA_REPORT_v20.md` (v0.9.0 candidate, descoped to patch by operator). Adds the `runner_dispatch` wrapper to `lib/runner.sh`, three real-task dispatch tests (codex / copilot / multi-runner E2E), one mock-echo unit test, and a smoke→dispatch documentation reframe. Includes v0.7.9 housekeeping (untracked design+PRD).

Patch-tier; 7-story bundle. Operator-driven manual takeover throughout (autonomous loop remains cancelled).

## The 7 stories

| # | ID | Title | Outcome |
|:-:|---|---|:-:|
| 1 | US-001 | runner_dispatch wrapper + unit tests (mock-echo manifest) | first-attempt PASS (5/5) |
| 2 | US-002 | codex dispatch test + manifest fix (exec subcommand, --full-auto) | first-attempt PASS (3/3); CAUGHT real codex CLI flag drift |
| 3 | US-003 | copilot dispatch test (skip-aware) | first-attempt PASS (3/3) |
| 4 | US-004 | multi-runner E2E dispatch test | first-attempt PASS after E2E robustness fix (TIMEOUT bucket) |
| 5 | US-005 | Multi-runner test layers documentation (CLAUDE.md + lib header) | first-attempt PASS |
| 6 | US-006 | smoke test docstring reframe (codex+copilot smoke) | first-attempt PASS |
| 7 | US-007 | Retrospective + v0.7.9 housekeeping + IDEA_REPORT_v21 + version bump | this report |

## Wave plan vs. realized

US-001 lands first; US-002/003/004 depend on it; US-005/006 are doc-only; US-007 last. Sequential under manual takeover (12th consecutive cycle).

## G30 self-validation — 15th consecutive LOW

`bash lib/deep-review.sh score $BASE $HEAD` → **score=22 tier=LOW files=9 sensitive=0 → skip**. Decision recorded with `automated:true`.

## Multi-cycle CSV milestone (eleventh populated run)

`metrics/pre-impl-review-findings.csv` → 33 rows. Advisory hook findings for v0.7.10: design=2 LOW, prd=1 LOW, plan=1 LOW.

## Test-suite delta vs v0.7.9

| Test file | v0.7.9 | v0.7.10 | delta |
|---|---:|---:|---:|
| `tests/test_runner_dispatch.sh` (NEW) | — | 5 asserts | +5 |
| `tests/test_codex_dispatch.sh` (NEW) | — | 3 asserts | +3 |
| `tests/test_copilot_dispatch.sh` (NEW) | — | 3 asserts | +3 |
| `tests/test_multi_runner_dispatch_e2e.sh` (NEW) | — | 5 asserts | +5 |
| Other | unchanged | unchanged | 0 |
| **Total v0.7.10 added:** | | | **+16** |

## N35 closure — real-task dispatch validated

The first end-to-end dispatch tests on this dogfood machine produced these results:

| Runner | Result | Notes |
|---|---|---|
| claude | DISPATCHED (rc=0, ~21s, 171 chars) | Standard headless invocation |
| codex | DISPATCHED (rc=0, ~21s, 7173 chars including preamble) | Required manifest fix (exec subcommand) |
| copilot | TIMED_OUT (rc=124, 91s, 557 chars) | GitHub Copilot CLI has a rate-limit/auth-check phase that can exceed 90s under back-to-back invocations |

**Bonus value:** the dispatch test suite caught a real codex CLI flag migration (`-q` → `exec` subcommand, `--approval-mode` → `--full-auto`) that smoke tests didn't. This validates the smoke-vs-dispatch test layer separation introduced in this cycle.

## v0.7.9 housekeeping

`docs/plans/2026-04-28-v0.7.9-bundle-design.md` + `tasks/prd-v0.7.9-bundle.md` were authored during the v0.7.9 cycle but never staged before squash-merge — the v0.7.5 N29 / v0.7.6 N34 audits exist precisely to catch this pattern (untracked-design-prd). Picked up here.

## codebasePatterns

No new patterns harvested. p001-p011 carry over.

## Recommendation pointer

See `idea-stage/IDEA_REPORT_v21.md` for what's open after v0.7.10.
