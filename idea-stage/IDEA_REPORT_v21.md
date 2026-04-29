# IDEA_REPORT_v21 — what's open after v0.7.10

**Date:** 2026-04-28
**Source:** Operator-driven N35 closure (`runner_dispatch` + real-task tests + smoke→dispatch reframe)
**Branch:** `ql/v0.7.10-bundle` (release tag v0.7.10)
**Predecessor:** `idea-stage/IDEA_REPORT_v20.md`

## Closed in v0.7.10

| ID | Story | Notes |
|---|---|---|
| **N35** | US-001..004 | `runner_dispatch` wrapper in `lib/runner.sh` + 3 real-task dispatch tests (codex / copilot / multi-runner E2E) + mock-echo unit test. Real-task dispatch validated end-to-end. Caught codex CLI flag drift (manifest fix included). |
| **Smoke→dispatch reframe** | US-005, US-006 | CLAUDE.md gains "Multi-runner test layers" subsection; smoke test header comments updated to clarify health-check layer. |
| **v0.7.9 housekeeping** | US-007 | `docs/plans/2026-04-28-v0.7.9-bundle-design.md` + `tasks/prd-v0.7.9-bundle.md` committed (untracked from prior cycle). |

The **N35 cluster** is now **fully closed**. Real-task dispatch is addressable via `runner_dispatch <name> <prompt>` and tested across all 3 first-tier runners.

## Persistent canon

p001-p011 unchanged. Source-of-truth: `idea-stage/PIPELINE_REPORT_v7.md` § "codebasePatterns harvested".

## Still open

### N33 — Worktree mode root-cause investigation
**Status:** unchanged. 12+ consecutive manual-takeover cycles. Substantive minor anchor candidate for v0.9.0.

### Copilot rate-limit observability
**Status:** new. v0.7.10's E2E dispatch test exposed that copilot can exceed 90s on back-to-back invocations. The TIMEOUT bucket handles it gracefully but doesn't address the root cause. May warrant per-runner cooldown logic in a future cycle if copilot becomes a primary runner.
**Severity:** LOW (environmental, currently mitigated by TIMEOUT bucket).
**Path:** Track for v0.8.x or v0.9.0 if copilot is brought into core dispatch flow.

## New gaps from v0.7.10

### N38 — codex CLI flag drift detection automation
**Surfaced:** v0.7.10 found that `runners/codex.json` was using out-of-date flags (`-q`, `--approval-mode full-auto`) that the current codex CLI rejects. The dispatch test caught this manually. A periodic CI job that runs all dispatch tests against installed runners would surface manifest drift earlier.
**Severity:** LOW (tooling enhancement).
**Path:** Track for a future cycle. Could be a cron-style health check separate from per-PR test gates.

## Recommendation for next

**v0.7.11 candidate slate (patch-tier):**
- N38 (manifest drift detection) is the only fresh actionable item. Could ship as a small reactive patch if operator adopts copilot for dispatch.
- Copilot rate-limit observability is environmental, not actionable yet.

**v0.9.0 candidates (next minor — needs operator scope):**
- **N33** — worktree subagent drift root-cause investigation (12+ consecutive manual takeovers, recurring pattern)
- New feature TBD (operator-defined)

## Recurring observations

- **15 consecutive LOW G30 self-validations** (v0.6.5..v0.7.10).
- **Bundle size: 7-7-7-7-5-6-5-3-7-3-2-4-3-3-7.** v0.7.10 is back to 7-story (N35 was substantive enough to warrant the larger bundle).
- **Real-task dispatch infrastructure complete.** `runner_load` → `runner_build_cmd` → `runner_dispatch` chain is now testable end-to-end with mock-echo + 3 real runner adapters.
- **Operator-driven reactive cycles continue to deliver high signal.** v0.7.9 (multi-runner-manifest hardening) + v0.7.10 (real-task dispatch) both surfaced from operator code review or operator scope decisions, not autonomous loop discovery. The 4-cycle pattern is: autonomous loop drained patch-tier → operator review surfaces real bugs → reactive patch closes them.
