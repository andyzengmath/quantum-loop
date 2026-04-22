# Phase 4 Review — Why D.1/D.3 became no-ops

Date: 2026-04-22
Outcome: All 9 ql/* branches archived + deleted without merge or cherry-pick

## Hypothesis

The CPC-variant working-tree files promoted in Phase 2 ARE the integrated result of all 9 ql/* branches. Therefore:
- D.1 (merge ql/multi-runner) would introduce no new content.
- D.3 (cherry-pick net-new files from other ql/*) would yield no commits.

## Verification

For each branch, `git log HEAD..<branch> --oneline | wc -l` and `git diff HEAD..<branch> --name-status | grep '^A'`:

| Branch | "Ahead" commits | Added files missing from HEAD | Action |
|--------|----------------:|-------------------------------|--------|
| ql/orchestrator-and-fixes | 0 | — | already in HEAD |
| ql/parallel-execution | 0 | — | already in HEAD |
| ql/research-p0-bundle | 0 | — | direct predecessor |
| ql/multi-runner | 256 | root `plugin.json` (dup, removed in P2), `tests/test_crash_recovery.sh` (removed in P3) | no real additions |
| ql/hardening-v2 | 226 | same pattern | no real additions |
| ql/dag-intelligence | 148 | `lib/crash-recovery.sh` (removed in P3 per resilience.sh:3), `plugin.json`, test_crash_recovery | no real additions |
| ql/progressive-materialization | 126 | same + HEAD's `materialize.sh` is NEWER than branch's | no real additions |
| ql/modular-hardening | 185 | same pattern | no real additions |
| ql/post-mortem-fixes | 50 | same pattern | no real additions |

**Every `A`-classified file on a branch turned out to be a file we had already either (a) promoted via CPC and renamed to canonical, (b) removed as a deliberate duplicate, or (c) removed as superseded.**

## Diff-size signal

Every branch's diff against HEAD is net-negative (anywhere from -8,595 to -36,039 lines). This confirms HEAD is a strict superset: the branches are older, simpler precursors to the consolidated state on HEAD.

## Recovery

All 9 branches tagged under `archive/pre-delete-ql-<name>-20260422` before deletion. Recovery:

    git checkout archive/pre-delete-ql-multi-runner-20260422

81 total archive tags preserve the complete pre-consolidation state.

## Post-P4 branch state

- `master`
- `ql/bug-gap-fix-2026-04` (current work — 4 commits ahead of master, ready to PR)
- All `ql/*` integration work preserved in archive tags.

Metric target (≤15 local branches): achieved (2 local).
