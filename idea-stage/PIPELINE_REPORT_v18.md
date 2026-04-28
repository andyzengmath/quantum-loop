# PIPELINE_REPORT_v18 — v0.7.7 patch-tier retrospective

**Date:** 2026-04-28
**Bundle:** `ql/v0.7.7-bundle` (release tag v0.7.7)
**Predecessor:** `idea-stage/PIPELINE_REPORT_v17.md`
**Master parent:** v0.7.6 (+ chore PR #78)
**Source:** `idea-stage/IDEA_REPORT_v17.md` v0.7.7 anchor (N30)

## Overview

**First patch-tier release in 8 cycles** (since v0.7.0). Closes N30: first end-to-end smoke validation of codex + copilot CLI runners against the existing multi-runner infrastructure. Operator framing: real-CLI integration is architecturally substantive even though no production code changed.

## Stories

| # | ID | Title | Outcome |
|:-:|---|---|:-:|
| 1 | US-001 | Codex CLI smoke test | first-attempt PASS (5/5; codex-cli 0.118.0) — 1 inline fix needed (runner_load takes name not path) |
| 2 | US-002 | Copilot CLI smoke test | first-attempt PASS after same inline fix (5/5; GitHub Copilot CLI 1.0.37) |
| 3 | US-003 | Routing E2E multi-runner (Test 5) | first-attempt PASS (9/9; claude/codex/copilot 3-way snapshot with versions populated) |
| 4 | US-004 | Retrospective + IDEA_REPORT_v18 + 0.7.6 → 0.7.7 | this report |

## G30 — 12th consecutive LOW

`bash lib/deep-review.sh score $BASE $HEAD` → **score=7 tier=LOW files=3**. 12 consecutive LOW (v0.6.5..v0.7.7).

Notable: v0.7.7 is patch-tier but G30 score is at the floor (3 files, all in tests/). Score≠tier-implies-importance.

## Test-suite delta

| Test file | before | after | delta |
|---|---:|---:|---:|
| tests/test_codex_runner_smoke.sh | NEW | 5 | +5 |
| tests/test_copilot_runner_smoke.sh | NEW | 5 | +5 |
| tests/test_routing_e2e.sh | 6 | 9 | +3 (Test 5 multi-runner) |
| **Total v0.7.7 added:** | | | **+13 assertions** |

## Discoveries this cycle

1. **runner_load API drift:** initial smoke tests passed paths instead of names. Fixed inline (5min). Documents the convention: `runner_load <name>` not `runner_load <manifest_path>`.
2. **Real-CLI versions captured:** `codex-cli 0.118.0` (tier=tested) and `GitHub Copilot CLI 1.0.37` (tier=experimental). Multi-runner integration is real, not vapor.
3. **3-way routing snapshot works:** `resolve_routing claude codex copilot` produces a JSON snapshot with all 3 providers + populated versions on a real machine. First validated end-to-end.

## Manual-takeover (10th consecutive cycle)

Continued. v0.7.7 is the 10th cycle on the manual-takeover track (v0.6.7..v0.7.7). 0-retry first-attempt PASS holds (with 1 inline fix counted as second-attempt for US-001).

## codebasePatterns

No new patterns. p001-p011 carried over.

## Recommendation pointer

See `idea-stage/IDEA_REPORT_v18.md` for what's open after v0.7.7.
