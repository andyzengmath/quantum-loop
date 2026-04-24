---
name: narrative-report
description: Narrative handoff for quantum-loop improvement research — summary of Stage-1 findings, Stage-2 deliverables, review status, and remaining TODOs. Produced by /research-pipeline 2026-04-21.
date: 2026-04-21
---

# Quantum-Loop Improvement Research — Narrative Report

## Problem statement and core claim

**Problem**: quantum-loop — the BUILD layer of the AI-native-rebuild project's three-layer stack — has accumulated ~991 commits of hardening work on six unmerged `ql/*` branches plus a parallel `*-CPC-andyz-ZH84K.*` variant track, leaving master as a regressed baseline. The user-observed pain (wiring failures, merge conflicts, duplicate code, dead code, review gaps, intent drift across stages) is largely addressed in the unmerged work but invisible on master.

**Core claim**: The highest-leverage improvement to quantum-loop is not to design new mechanisms; it is to **consolidate and promote existing work** (P0), then **close the remaining user-stated review and intent gaps** (P1), then **adopt selected external-tool features** (P2), then pursue academic wedges (P3) and AI-native-rebuild integration (P4) in follow-on cycles.

## Method summary

Three-stream parallel investigation run via `/research-pipeline` on 2026-04-21:

1. **Independent codebase audit** (agent A): file:line analysis of `skills/`, `agents/`, `lib/`, `docs/plans/`, `docs/post-mortems/`. Output: `idea-stage/AUDIT_QL.md` (3,238 words; 17 H2 sections; G1-G21 gap catalog).

2. **External harness survey** (agent B): 11 tools profiled in depth (superpowers, ralph, oh-my-claudecode, gsd, gstack, aider, OpenHands, SWE-agent, Cursor BG, Devin, Cline, Roo Code, Composio); 30-feature × 17-tool matrix; top-15 borrow list. Output: `idea-stage/COMPETITOR_SURVEY.md` (6,561 words).

3. **Academic literature review** (agent C): 34 papers 2024-2026 across 10 clusters (SWE benchmarks / parallel DAG / conflict resolution / duplicate detection / dead code / review automation / intent alignment / verification / planning quality / observability); top-15 ranked recipes tiered S/A/B. Output: `idea-stage/LITERATURE_SURVEY.md` (4,378 words).

Synthesized into `idea-stage/IDEA_REPORT.md` (3,459 words) with five-tier priority ranking (P0-P4) and a four-item Stage-2 shortlist.

Stage-2 execution focused on **P0.A (safe surface work)**: non-destructive changes mergeable as a standalone PR. Destructive work (P0.B/C/D) is gated on user confirmation.

## Key quantitative results (with evidence)

| Metric | Pre-P0 | After P0.A (this branch) | Target Post-P0.D |
|--------|-------:|-------------------------:|-----------------:|
| README.md merge-conflict markers | 3 (lines 368, 372, 399) | 0 | 0 |
| Tracked files touched | — | 1 modified | + ~20 promoted/deleted |
| New research artifacts | — | 5 (idea-stage/*.md) | — |
| New design docs | — | 1 (`docs/plans/2026-04-21-p0-consolidation-design.md`) | — |
| New skills | — | 1 (`ql-housekeep`, detection-only) | — |
| Commits added | — | 3 on `ql/research-p0-bundle` | many more |
| Git branches (re-verified by code-reviewer) | ~88 | 89 (added ql/research-p0-bundle) | ≤ 15 |
| Orphan worktree dirs (`.claude/worktrees/agent-*`) re-verified by code-reviewer | 45 | 45 | 0 |
| CPC-variant files detected | ~20 tracked | 42 total in working tree | 0 |
| `lib/crash-recovery.sh` dead-file status | present | present (detected by ql-housekeep) | deleted |
| `quantum.json.updatedAt` | 2026-02-18 (62 days stale) | 2026-02-18 | within 7 days |

Evidence basis: `idea-stage/AUDIT_QL.md` (file:line citations throughout), `idea-stage/COMPETITOR_SURVEY.md` §Cross-Tool Feature Matrix, `idea-stage/LITERATURE_SURVEY.md` Tier-S / Tier-A recipes.

## Commits delivered on `ql/research-p0-bundle`

| Commit | Subject | Risk |
|--------|---------|:----:|
| `f9a53c7` | fix: resolve merge-conflict markers in README.md Windows Users section | none (docs) |
| `e270403` | docs: add Stage-1 research-pipeline artifacts for quantum-loop improvements | none (new files) |
| `7307b51` | feat: add P0 consolidation design + ql-housekeep detection skill | low (new skill, no auto-fix) |

Branch is mergeable to master as a docs+detection PR with no runtime behavior change. Full commit log: `git log master..ql/research-p0-bundle --oneline`.

## Figure / table inventory

**Tables generated in reports (no figures required for this engineering work):**

- `idea-stage/AUDIT_QL.md` — Skills inventory (6 rows), Agents inventory (9 rows), Library inventory (24 rows), Design-docs (8 rows), Post-mortem failures (7 rows), Gaps by category G1-G21.
- `idea-stage/COMPETITOR_SURVEY.md` — 30-feature × 17-tool matrix; Top-15 borrow list.
- `idea-stage/LITERATURE_SURVEY.md` — 10 clusters × ~3.5 papers each; Top-15 ranked recipes in 3 tiers.
- `idea-stage/IDEA_REPORT.md` — Five priority tiers (P0-P4) with per-idea impact/effort/novelty; Stage-2 shortlist; anti-recommendations; success metrics.

No manual figure creation needed — this is an engineering research pipeline, not an academic paper.

## Review status (Stage 4 complete)

Three parallel reviewers returned on 2026-04-21. All findings addressed via commits `531cad2` and `0e4b18a`.

| Reviewer | Scope | Verdict | Key findings fixed |
|----------|-------|---------|------|
| `oh-my-claudecode:code-reviewer` | Code review of 3 commits | APPROVE WITH COMMENTS | Inaccurate counts (89 not 109; 45 not 66), GNU-only `date -d` → portable python3, P0.D merge-abort recovery, setext false-positive note |
| `oh-my-claudecode:critic` | Multi-perspective plan critique | PROCEED WITH CHANGES | P0.D strategy infeasible (6 parallel rewrites with 87-file overlap) → revised to single-branch + CPC + cherry-pick; 3-way plugin-version drift documented; dogfood sequencing corrected |
| `soliton:synthesizer` | Risk-adaptive PR review | READY_TO_MERGE_WITH_NOTES | Risk score 28/100; 5 improvements on DAG-intelligence agents (future P0.B/D work); scope-confusion meta-finding reinforces the P1.1 cross-story review need |

Full review synthesis in `idea-stage/PIPELINE_REPORT.md`.

## Limitations and remaining follow-up items

### Limitations of this Stage-1/2 pass

1. **Stage 2 scope is intentionally narrow.** P0.A (safe surface work) is 3 commits / ~6 file changes — far smaller than the full P0 consolidation. P0.B-D require destructive ops (file deletions, branch pruning) and user confirmation.

2. **ql-housekeep is detection-only.** No auto-fix path. The user must translate findings into action. Intentional to avoid silent destructive ops.

3. **No runtime behavior change.** The skills, agents, and libs on master still load as before. The CPC-variant fork issue is identified, documented, but not resolved.

4. **No dogfood loop closed.** The design doc ends with "Run `/ql-spec` + `/ql-plan` on this design." That execution is deferred to the next cycle.

5. **P4 (AI-native-rebuild integration) is blocked on upstream.** EvidenceBundle schema v0.1 exists; graph-cli + ContextPack are not shipped.

### Remaining TODOs (in priority order)

**Near-term (P0 completion)**:
- **P0.B**: CPC → canonical file promotion across 6 skills + 4 agents + 6 libs + 3 test files + 10 root-level files.
- **P0.C**: Delete `lib/crash-recovery.sh`, remove 45-66 orphan `.claude/worktrees/agent-*` dirs, prune ≥90 stale branches with `archive/` tags.
- **P0.D**: Merge integration branch from `ql/post-mortem-fixes` → `ql/progressive-materialization` → `ql/modular-hardening` → `ql/dag-intelligence` → `ql/hardening-v2` → `ql/multi-runner`.
- **CHANGELOG backfill**: Document v0.3.x and v0.4.x entries after P0.D lands (plugin.json on master is actually v0.2.0; the 0.4.1 is only on unmerged branches).

**Medium-term (P1 user-stated gap closure, follow-on cycle)**:
- P1.1 Stage-3 cross-story + post-merge review
- P1.2 Multi-perspective review aggregator (`ql-deep-review` skill)
- P1.4 Intent-drift audit (`ql-intent-check` skill)
- P1.6 Post-implementation AI-slop cleanup (ralph deslop pass)
- P1.7 Post-mortem Progress-Log generator repair

**Longer-term (P2-P4)**:
- P2.1 Wave-based DAG execution with sync-point validation
- P2.2 Spec-reviewer over-building hunter
- P2.3 Stage-handoff documents
- P3.1 SSAT skeleton-first story type
- P3.3 KBI-then-FAR reviewer split
- P3.6 Semantic Intent Graph + Drift Monitor
- P4.1-P4.6 AI-native-rebuild integration (blocked on upstream deps)

### Deferred decisions (for user input)

1. Which `ql/*` branch is the intended base for P0.D integration? My recommendation: `ql/hardening-v2` as the base, with `ql/multi-runner` merged last (since it's largest and newest).
2. Which CPC-variant files should be preserved as archive references vs. deleted outright?
3. Should P0.B proceed as a single big promotion commit or one commit per file? (Former = easier to review; latter = easier to revert individually.)

## Handoff to next stage

**If `AUTO_WRITE=false` (default)**: This narrative report is the end of the research-pipeline autonomous portion. Stage 6 (paper writing) is skipped because this is engineering work, not academic output.

**If continuing**: Run `/quantum-loop:ql-spec` on `docs/plans/2026-04-21-p0-consolidation-design.md` to generate a PRD, then `/quantum-loop:ql-plan` to generate a new `quantum.json` — dogfooding the pipeline for the first time.
