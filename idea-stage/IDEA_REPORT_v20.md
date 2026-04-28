# IDEA_REPORT_v20 — what's open after v0.7.9

**Date:** 2026-04-28
**Source:** Operator-driven reactive bundle (external code review of v0.7.4 N5)
**Branch:** `ql/v0.7.9-bundle` (release tag v0.7.9)
**Predecessor:** `idea-stage/IDEA_REPORT_v19.md`

## Closed in v0.7.9

| ID | Story | Notes |
|---|---|---|
| **Review-Issue-1** | US-001 | yq backend empty-YAML success no longer reports as parse failure. |
| **Review-Issue-2** | US-001 | python backend stderr captured separately, JSON output uncontaminated. |
| **Review-Issue-3** | US-001 | shell parser handles arbitrary leading-whitespace indent (tab + n-space). |
| **Review-Issue-4** | US-001 | shell parser rtrims trailing whitespace from field values. |
| **Review-Issue-5** | US-002 | `MR_DISABLE_YQ` / `MR_DISABLE_PYTHON` / `MR_DEBUG` env-var hooks + Tests 7-10. |
| **Review-Issue-6** | US-001 | `validate_manifest` distinguishes missing-runners (jq rc=1) from malformed JSON (jq rc≥2). |

The **6-issue cluster** from external operator code review of v0.7.4 N5 is now **fully closed**.

## Persistent canon

p001-p011 unchanged. Source-of-truth: `idea-stage/PIPELINE_REPORT_v7.md` § "codebasePatterns harvested".

## Still open

### N33 — Worktree mode root-cause investigation
**Status:** unchanged. 11 consecutive manual-takeover cycles. Substantive minor anchor candidate for v0.9.0.

### N35 — Real-task dispatch (codex/copilot beyond version probe)
**Status:** unchanged. Substantive minor anchor candidate for v0.9.0.

## New gaps from v0.7.9

None substantive. The 6 review issues are now closed; no new gaps surfaced by the bundle itself.

## Recommendation for next

**Patch-tier track:** drained again. The autonomous loop is cancelled (per IDEA_REPORT_v19's recommendation, honored). Future patch-tier work should be operator-driven reactive (as v0.7.9 was) — not loop-restart.

**v0.9.0 candidates (next minor — needs operator scope):**
- **N35** — codex/copilot real-task dispatch (substantive minor anchor; would naturally fold in any further `lib/multi-runner-manifest.sh` polish needed)
- **N33** — worktree subagent drift root-cause investigation (11 consecutive manual takeovers — finally addressing the recurring pattern)
- New feature TBD (operator-defined)

## Process distinction worth preserving

**Operator-driven reactive patches are allowed even when the autonomous loop is paused.** The signal that triggered v0.7.9 was external human code review — high signal, not loop-churn. Keeping this channel open while the autonomous loop sits idle is the right balance.

## Recurring observations

- **14 consecutive LOW G30 self-validations** (v0.6.5..v0.7.9). G30 calibration consistent.
- **Bundle size: 7-7-7-7-5-6-5-3-7-3-2-4-3-3.** v0.7.9 is 3-story.
- Test-suite delta this cycle: **+4** (Tests 7-10 in `test_multi_runner_manifest.sh`).
- Plan-review still 100% LOW after 12 cycles (12/12 rows). N18 second-MEDIUM-example has not yet triggered a real MEDIUM finding.
