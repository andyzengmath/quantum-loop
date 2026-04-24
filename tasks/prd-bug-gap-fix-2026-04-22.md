# PRD — Fix Previous Implementation Bugs & Gaps Before Next Wave

**Feature id**: `bug-gap-fix-2026-04-22`
**Date**: 2026-04-22
**Status**: implemented (retrospective PRD for Phase 10 dogfood)
**Source plan**: `.omc/plans/2026-04-22-bug-and-gap-fix-plan.md`
**Branch**: `ql/bug-gap-fix-2026-04`

## 1. Problem statement

Quantum-loop master is a regressed baseline relative to the project's actual state of work. ~80% of the user-stated pain (wiring, conflicts, duplicates, dead code, review gaps, intent drift) had been solved on feature branches and in untracked `*-CPC-andyz-ZH84K.*` files but never promoted to the canonical track. The research pipeline's independent audit (`idea-stage/AUDIT_QL.md`) catalogued 21 gaps (G1-G21) and flagged the two-pipeline coexistence as the root cause.

Before the next wave of improvements can land cleanly, these gaps must be closed on master.

## 2. User intent (verbatim first-message snapshot)

> "We have found some issues in the current implementation ( please review "idea-stage/IDEA_REPORT.md"). We want to fix the previous implementation bugs and gaps before next wave of improvements and new features (see other docs). Please review each listed gaps/issues carefully and read relavant code (use agent teams if needed). Then let's propose a comprehensive plan"

## 3. Goals (priority-ordered)

1. **Restore a single canonical pipeline.** One file per name (no CPC variants). Merge-routing lib wired in; runtime determinism restored.
2. **Clean up accumulated cruft.** Dead libs, orphan worktrees, stale branches — all removed with tag-before-delete recovery.
3. **Fix the two concrete bugs** named in the research synthesis:
   - G18: agents hedge (`should work`, `probably passes`) and the orchestrator accepts them at face value.
   - G21: post-mortem generator emits the header but not the Progress Log rows, breaking the learning loop.
4. **Productionize the three drafted P1 skills** so future waves have working gates:
   - `ql-intent-check` (drift audit from verbatim user intent → PRD → code).
   - `ql-deep-review` (multi-perspective whole-feature review aggregator).
   - `ql-deslop` (post-review AI-slop cleanup with regression gate).
5. **Dogfood** — the plan itself flows through `/ql-spec` + `/ql-plan` + an end-to-end check.

## 4. Acceptance criteria

| AC-ID | Criterion | Evidence |
|-------|-----------|----------|
| AC-1  | Zero `*-CPC-andyz-ZH84K.*` files in working tree and git index | `find . -name "*-CPC-*" \| wc -l` = 0 after P3 |
| AC-2  | `lib/monitor.sh` does not contain `git merge --no-edit` | grep returns empty |
| AC-3  | `lib/crash-recovery.sh` absent (superseded by `resilience.sh`) | stat returns ENOENT |
| AC-4  | `git branch -a \| wc -l` reduced from 89 to ≤15 (local ≤2) | 2 local branches on current tip |
| AC-5  | All 81 deleted branches are tag-recoverable | `git tag \| grep ^archive- \| wc -l` ≥ 81 |
| AC-6  | CHANGELOG covers every plugin version through 0.4.1 | 12 version entries |
| AC-7  | Plugin version aligned across `.claude-plugin/plugin.json` + `marketplace.json` | all read 0.4.1 |
| AC-8  | Test suite green on the integration branch | 301+ assertions across 10+ suites, 0 failing |
| AC-9  | `lib/claim-check.sh` wired into `lib/runner.sh` so hedge phrases demote confidence | `test_claim_check_integration` 17/17 |
| AC-10 | Post-mortem generator emits populated Progress Log table + promotes lessons into codebasePatterns | `test_observations_generator` 11/11 |
| AC-11 | `userIntent` / `userClarifications` / `intentDrift` fields added to `quantum.json.example` (backward-compat) | `jq .userIntent quantum.json.example` non-null |
| AC-12 | `/ql-brainstorm` writes `userIntent` snapshot at exit; `/ql-verify` consults `intentDrift.verdict` before emitting `STORY_PASSED` | `test_intent_check` 19/19 |
| AC-13 | `lib/deep-review.sh` exposes compute_risk_score / tier_of_score / actionability_filter / dedup_findings / hallucination_check / synthesize_verdict | `test_deep_review` 31/31 |
| AC-14 | `lib/deslop.sh` exposes validate_scope / take_baseline / compare_baseline / rollback_pass / detect_language | `test_deslop` 22/22 |
| AC-15 | Dogfood — this PRD + companion quantum.json exist and the end-to-end check passes on a trivial story | `.omc/phase-10-evidence/` populated |

## 5. Non-goals (explicit)

- No new language-detector tooling installed by this plan (e.g., we don't bundle `knip` / `vulture` / `cargo-udeps`). `detect_language` degrades gracefully when absent.
- No actual LLM-side agent dispatch from the new helper libs (those are driven by the skill prompts at invocation time).
- No remote-branch cleanup (`git push origin --delete`). Left for the user's PR-time decision.
- No wave-boundary cross-story constant scan implementation (helper sketch only; deferred to a follow-up).
- No tournament-selection, cross-provider critic, or academic wedges (P2/P3 tiers deferred to a follow-on cycle).
- No AI-native-rebuild integration (P4, blocked on upstream deps).

## 6. Implementation phases (cross-reference to design plan)

| Phase | Title | Commit |
|-------|-------|--------|
| 0+1 | Prep + CHANGELOG backfill + version reconciliation | `c841c61` |
| 2   | CPC → canonical promotion | `92b5085` |
| 3   | Dead-code + worktree + branch cleanup | `32394b6` |
| 4   | Archive 9 ql/* branches (no-op merge verified) | `fb1f3bf` |
| 5+6 | Claim-check wiring + Progress-Log generator repair | `79204c0` |
| 6.5 | Review-response fixes (2 HIGH + TMPDIR sweep + PS1 parity) | `ae0f0ea` |
| 7   | ql-intent-check wiring | `9418caa` |
| 8   | ql-deep-review safety rails | `f10e7a7` |
| 9   | ql-deslop safety rails | `58758d0` |
| 10  | Dogfood | (this commit) |

## 7. Files changed (summary)

- **Added**: 5 agents, 13 lib modules (9 canonical + 4 new: claim-check, deep-review, deslop, plus from CPC), 4 skills (ql-deslop + 3 drafted now productionized), 7 design docs, 6 PRDs, 18+ tests, runners/schemas/references directories.
- **Modified**: quantum-loop.sh + quantum-loop.ps1 (both generators), lib/runner.sh (claim-check wiring), lib/monitor.sh (merge routing), all 6 skill SKILL.md files, quantum.json.example (3 schema extensions).
- **Deleted**: lib/crash-recovery.sh, 12 branches (fix/*, chore/*, feat/*, master-CPC), 45 worktree-agent-* branches.

## 8. Risks and mitigations (retrospective)

| Risk | Outcome | Mitigation applied |
|------|---------|-------------------|
| CPC variant has latent regression | None found | Per-file test suite after each promotion batch |
| `ql/*` merge produces conflict swamp | Avoided | Verified branches were strict-subset; tagged + deleted instead of merging |
| Destructive branch ops lose work | None lost | 81 archive tags created; reflog preserved |
| Tests leak state into working tree | Surfaced (5 "init" commits during Phase 2) | Soft-reset + TMPDIR→TEST_TMPDIR sweep across 19 test files |
| PS1 generator missed codebasePatterns parity | Caught by reviewer | Added promotion block in Phase 6.5 |

## 9. Verification

- 10 suites re-run at each phase boundary.
- End-state regression: test_deslop 22/22, test_deep_review 31/31, test_intent_check 19/19, test_claim_check_integration 17/17, test_observations_generator 11/11, plus baseline suites test_runner 38/38, test_resilience 43/43, test_init_guard 56/56, test_json_atomic 19/19, test_runner_integration 45/45. Total 301/301.
- Evidence captured under `.omc/phase-*-evidence/` for every phase.
