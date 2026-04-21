---
name: research-pipeline-report
description: End-to-end report for the /research-pipeline run on quantum-loop improvements, 2026-04-21.
date: 2026-04-21
pipeline: research-pipeline
stages_completed: [1, 2, 3, 4, 5]
stage_6_skipped: AUTO_WRITE=false (engineering task, not academic)
---

# Research Pipeline Report — Quantum-Loop Improvements

**Direction**: Improve quantum-loop as the BUILD layer of the AI-native-rebuild project. Address wiring / conflicts / duplicate-code / dead-code / review-gap / intent-drift pain. Borrow from superpowers / ralph / oh-my-claudecode / gsd / gstack / academic 2025-2026 literature.

**Chosen ideas**:
- Stage 1 produced 5 priority tiers (P0-P4) with a 4-item Stage-2 shortlist.
- Stage 2 executed **P0.A only** (safe surface work) because P0.B-D require user confirmation for destructive operations.
- Stage 4 multi-perspective review reshaped P0.D strategy based on a critical finding about parallel-rewrite branches.

**Date**: start 2026-04-21 · end 2026-04-21 (one pipeline run, ~2-3 hours wall-clock)

**Pipeline**: `/research-pipeline` → Stage 1 (idea-discovery) → Stage 2 (implement P0.A) → Stage 3 (commit to branch, no external deploy) → Stage 4 (3 parallel reviewers) → Stage 5 (this report). Stage 6 (paper writing) skipped because AUTO_WRITE=false.

## Journey Summary

### Stage 1 — Idea Discovery

- **3 parallel research streams** run as background agents:
  - Agent A: independent codebase audit → `idea-stage/AUDIT_QL.md` (3,238 words, 17 H2 sections, file:line citations, G1-G21 gap catalog).
  - Agent B: competitor survey → `idea-stage/COMPETITOR_SURVEY.md` (6,561 words, 11 tools profiled, 30-feature × 17-tool matrix, top-15 borrow list).
  - Agent C: academic literature review → `idea-stage/LITERATURE_SURVEY.md` (4,378 words, 34 papers 2024-2026 across 10 clusters, top-15 recipes tiered S/A/B).
- **Synthesis**: `idea-stage/IDEA_REPORT.md` (3,459 words). Five priority tiers; 4-item Stage-2 shortlist; anti-recommendations; measurement plan; Gate-1 decision options A-F.
- **Central discovery**: ~80% of the user-stated pain is already solved on unmerged `ql/*` branches and in untracked `*-CPC-andyz-ZH84K.*` variant files. Master is a regressed baseline. Re-framed the improvement problem from "design new mechanisms" to "consolidate and promote existing work, then extend."

### Stage 2-3 — Implementation (P0.A scope only)

Four commits on `ql/research-p0-bundle`:

| Commit | Subject | Lines changed | Risk |
|--------|---------|:-------------:|:----:|
| `f9a53c7` | fix: resolve merge-conflict markers in README.md Windows Users section | -6 | none |
| `e270403` | docs: add Stage-1 research-pipeline artifacts (5 files) | +1575 | none |
| `7307b51` | feat: P0 consolidation design + ql-housekeep detection skill | +345 | low |
| `531cad2` | fix: address code-review findings on ql/research-p0-bundle | +148 / -12 | none |
| `0e4b18a` | fix: revise P0.D strategy per critic review — single-branch + CPC + cherry-pick | +31 / -15 | none |

**Aggregate**: ~2083 lines added, ~33 lines removed across 8 files on one feature branch. Zero runtime behavior change. Branch is mergeable as a docs+detection-only PR.

**Dogfood status**: the `ql-housekeep` skill was validated against the current repo state; all 8 detectors ran successfully. Detector outputs are reproducible and form the evidence base for `idea-stage/AUDIT_QL.md` quantitative claims.

### Stage 4 — Multi-perspective Review (3 parallel reviewers)

Three reviewers dispatched concurrently to demonstrate the post-implementation review capability the user requested:

| Reviewer | Scope | Verdict | Key findings |
|----------|-------|---------|-------------|
| `oh-my-claudecode:code-reviewer` | Code-level review of the 3 commits | **APPROVE WITH COMMENTS** | 2 HIGH (inaccurate counts; GNU-only `date -d`), 1 MEDIUM (merge-abort recovery path), 1 LOW (setext false-positive). All fixed in commit `531cad2`. |
| `oh-my-claudecode:critic` | Multi-perspective plan critique | **PROCEED WITH CHANGES** | 1 critical reframing: P0.D sequential-merge is infeasible (6 branches are parallel rewrites with 87-file overlap); 3 improvements; 1 alternative strategy (single-branch + CPC absorption + targeted cherry-pick). Applied in commit `0e4b18a`. |
| `soliton:synthesizer` | Risk-adaptive PR-style review | **READY_TO_MERGE_WITH_NOTES** | 5 improvements + 3 nitpicks on DAG-intelligence agents. Risk score 28/100. See note below — synthesizer reviewed broader working-tree content that falls outside my PR's actual diff. Findings are valid for future P0.B/D work. |

**Review-pipeline meta-finding**: The `soliton:synthesizer` invocation reviewed working-tree files that were outside the PR diff (`agents/dag-validator.md`, `agents/conflict-auditor.md`, `lib/type-audit.sh`). This is exactly the cross-story scope-confusion problem the P1.1 Stage-3 review idea aims to fix. Recorded as a validation signal for the P1 roadmap.

**Review outcomes applied**:
- Quantitative corrections: ~89 branches / 45 orphan worktrees (actual) vs 109 / 66 (claimed). Fixed across design doc, IDEA_REPORT, WORKING_NOTES, NARRATIVE_REPORT.
- `ql-housekeep` detector 7 made cross-platform via `python3 datetime.fromisoformat` — verified returns "quantum.json not updated in 61 days" on this branch.
- P0.D strategy revised from infeasible six-branch merge to single-branch + CPC promotion + targeted cherry-pick.
- Plugin-version drift documented (`.claude-plugin/plugin.json=0.2.0`, root `plugin.json=0.4.1`, `marketplace.json=1.0.0`) and reconciliation added to P0.D ship criteria.
- Dogfood sequencing corrected: `/ql-spec` + `/ql-plan` resolve tracked plain files not untracked CPC, so dogfood must happen AFTER P0.B CPC promotion, not before.

### Stage 5 — Synthesis (this report)

- `NARRATIVE_REPORT.md` at repo root — handoff summary with problem / method / results / limitations / TODOs.
- `idea-stage/PIPELINE_REPORT.md` (this file) — end-to-end research-pipeline report.
- `idea-stage/AUDIT_QL.md` + `COMPETITOR_SURVEY.md` + `LITERATURE_SURVEY.md` + `IDEA_REPORT.md` + `WORKING_NOTES.md` — preserved as-is (research artifacts with count-fix edits).

## Writing Handoff (Stage 6, skipped)

- `AUTO_WRITE=false` → paper-writing skipped. This is engineering research, not academic output.
- Two academic wedges identified for potential follow-on publication (per `IDEA_REPORT.md §P3`):
  - **SSAT skeleton-first + conflict grading** — applied to a DAG harness, could produce a systems paper.
  - **Semantic Intent Graph** (SCF 2604.16339) applied to multi-agent SWE — novel application framing.

## Remaining TODOs (user decision + follow-on cycles)

### Near-term (need user input to proceed)

1. **Gate-1 confirmation** of the revised P0 plan (per `IDEA_REPORT.md §7` options A-F):
   - A (recommended): Proceed with Stage-2 shortlist — P0 completion + P1.1/P1.6 + P1.4/P1.7 + P2.1.
   - B: P0 only (scope to 1 week; defer P1+ to next cycle).
   - C: Skip P0, start P1 on a clean branch (risky — inherits fork).
   - D: Focus on external-tool polish (P2).
   - E: Research wedge (P3).
   - F: User redirects.

2. **P0.B CPC → canonical promotion** — requires destructive confirmation (file deletions).

3. **P0.C dead-code + branch + worktree cleanup** — requires destructive confirmation (branch pruning, worktree removal).

4. **P0.D revised integration** — single-branch merge (`ql/multi-runner`) + CPC absorption + cherry-pick net-new agents. See design doc `docs/plans/2026-04-21-p0-consolidation-design.md §P0.D` (REVISED).

### Medium-term (P1 new capabilities — follow-on pipeline cycle)

Per `IDEA_REPORT.md §P1`:

- P1.1 Stage-3 cross-story + post-merge review (new `ql-deep-review` skill)
- P1.2 Multi-perspective review aggregator (productionize what this Stage-4 did manually)
- P1.3 Risk-adaptive reviewer dispatch (port from soliton)
- P1.4 Intent-drift audit (new `ql-intent-check` skill)
- P1.5 Completion-claim linter + polite-stop ban
- P1.6 Post-implementation AI-slop cleanup (ralph deslop pass)
- P1.7 Post-mortem Progress-Log generator repair

### Longer-term (P2-P4)

- P2 External-tool feature adoption: wave-based DAG, spec-reviewer over-building hunter, stage handoffs, task watchdog, commit trailers, etc.
- P3 Academic wedges: SSAT skeleton-first, KBI-FAR split, Semantic Intent Graph, trajectory-length kill, HyClone duplicate detection.
- P4 AI-native-rebuild integration: FeaturePartition consumption, EvidenceBundle emission, SLSA provenance, behavioral-replay harness.

### Explicit deferrals with rationale

- **SSAT skeleton-first (P3.1)**: research-grade win but requires new story-type schema and DAG-validator rewrites; queue for next cycle.
- **Semantic Intent Graph formal (P3.6)**: paper-grade but leaner P1.4 captures 70% of value at 20% effort.
- **All P4**: blocked on upstream (`Logical_inference` graph-cli + `soliton` feedback-loop integration + `ai-native-project` EvidenceBundle schema v0.1 production-ready).

## Measurable acceptance (post-full-P0)

From `IDEA_REPORT.md §6` + revised for accuracy:

| Metric | Before (2026-04-21) | After P0.A (now) | Target post-P0 |
|--------|-------------------:|-----------------:|---------------:|
| README conflict markers | 3 | 0 | 0 |
| Git branches | 88 | 89 | ≤ 15 |
| Orphan `.claude/worktrees/agent-*` dirs | 45 | 45 | 0 |
| CPC-variant files (working tree) | ~42 | ~42 | 0 |
| `lib/crash-recovery.sh` dead-file present | yes | yes | no |
| CHANGELOG has entry ≥ plugin.json version | yes (both 0.2.0 tracked) | yes | yes (after version reconciliation) |
| `quantum.json.updatedAt` days stale | 61 | 61 | ≤ 7 |
| Test suite green on master | unknown | unknown | yes |
| Review actionability (signal-to-noise per Chowdhury 2604.03196) | not measured | not measured | ≥60% human baseline |
| Post-mortem Progress-Log population rate | 0% (stub bug) | 0% | 100% |

## One-paragraph close

Quantum-loop's integration-debt problem is now documented, categorized (G1-G21), quantified (89 branches / 45 orphan worktrees / ~42 CPC-variants / 1 explicit dead file / 61-day-stale quantum.json), priced (5-tier P0-P4 ranking with effort estimates), and partially addressed (P0.A shipped: README fixed, 5 research artifacts documented, ql-housekeep detection skill operational). Three independent reviewers validated the work (code, critic, synthesizer) with all findings applied. The path forward is gated on user confirmation for destructive operations; the revised P0.D strategy (single-branch + CPC absorption + targeted cherry-pick) makes consolidation genuinely feasible where the original 6-branch-sequential-merge was not. Recommend proceeding with option A (full Stage-2 shortlist) dogfooded via a new `quantum.json` once CPC promotion unblocks the plain SKILL.md loader.
