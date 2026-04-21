---
name: working-notes
description: Scratch pad of observations during Stage-1 idea discovery. Gets merged into IDEA_REPORT.
status: draft
last_updated: 2026-04-21
---

# Working Notes — Quantum-Loop Improvement Research

## Strategic Context (from ai-native-project)

Quantum-loop is **Layer 2 (BUILD)** of a three-layer AI-native subsidiary stack:
- L1 UNDERSTAND: Logical_inference/graph-code-indexing
- L2 BUILD: quantum-loop
- L3 REVIEW: soliton

**Business-critical requirements quantum-loop must satisfy:**
- Produce machine-auditable evidence bundle per shadow PR (source in `ai-native-project/STACK_THESIS.md §3`)
- Consume `FeaturePartition` + `ContextPack` from L1 as brainstorm input
- Emit SLSA v1.0 provenance + in-toto attestations (Tier-A A10)
- Behavioral-replay equivalence harness per feature partition (Tier-A A12)
- Feature-partition-aware PR chunking (Tier-A A13)
- Close the loop with soliton's `AgentInstruction[]` feedback mode

**Listed moats involving quantum-loop**: M1 (evidence bundle), M4 (DAG+worktree+Iron-Law+anti-rationalization).

## Observed Problems in Current Quantum-Loop State

### Housekeeping / self-reflection failure

- **109 git branches** (`git branch -a | wc -l`). Majority are stale: `ql/*`, `fix/*`, `worktree-agent-*`.
- **66 orphan worktree directories** under `.claude/worktrees/`. Crash recovery doesn't reliably clean these up across machines.
- **3 unresolved merge conflict markers in README.md** (user-facing doc). Evidence the two-stage review gate didn't catch the conflict during the last merge.
- **CPC-variant files** (`*-CPC-andyz-ZH84K.*`) duplicated across agents, skills, tests — OneDrive auto-renamed copies. Not in git, but present in working tree and in agent worktree copies.
- **CHANGELOG.md stops at 0.2.0** but `plugin.json` is at 0.4.1. Undocumented 0.3.x and 0.4.x releases. Self-discipline violation.
- **`package.json` is a placeholder** (`{"name":"test","scripts":{"test":"exit 0"}}`), yet the project defines real NPM-plugin semantics.
- **Stale `quantum.json`** still describes the Feb 2026 parallel-execution PRD (v0.1.0) while the codebase has advanced through v0.4.1 multi-runner. quantum-loop is not using itself for its own work.

### Parallel-execution gaps (user-named pain)

Based on `docs/post-mortems/*.md` + `docs/plans/2026-03-{09,18,24,25,28}-*.md` (audit-agent detail pending):
- **Wiring issues**: parallel stories produce code whose imports/types don't line up post-merge
- **Merge conflicts**: file-level conflicts not auto-resolved; require manual `fix/resolve-merge-conflicts` branches
- **Duplicate code**: two stories independently implement similar helpers under different names
- **Dead code**: orphaned tests + unused exports accumulate post-merge
- **Review gap**: two-stage review is per-story in isolation; cross-story semantic conflicts, post-merge regressions, and whole-feature coherence are never reviewed

### Review pipeline gaps

- Two-stage review (spec-compliance → code-quality) runs PER story in ISOLATION inside each worktree
- No post-merge (whole-feature) review
- No risk-adaptive dispatch (soliton has this, quantum-loop doesn't integrate it yet)
- No multi-perspective aggregation (security + architecture + consistency + cross-file)
- No debate/adversarial review
- User-reported: "need to perform multiple review, using code-review, pr-review, and many other review tools after implementation finishes"

### Intent preservation gaps

- PRD → design → plan → code drift: each stage compresses/reinterprets upstream artifacts; no traceability anchor
- User's first-message intent is not preserved verbatim in quantum.json
- ACs can be reinterpreted by implementer agents (fresh-context rewrite)

### Workflow efficiency

- Fresh context per story means every agent re-reads `codebasePatterns`, `quantum.json`, PRD. Amortization opportunity.
- 6 skills (brainstorm/spec/plan/execute/verify/review) — some consolidation possible for small features
- Many fix/ branches chase review findings that should have been caught earlier (shift-left opportunity)

## Candidate Idea Bank (pre-agent-data, ~25 ideas)

### Category A: Repo hygiene (immediate wins)
- **I-A1 Housekeeper skill** — detect: conflict markers, orphan worktrees, stale branches, CPC-variants, duplicated test files; emit report + guarded auto-fix
- **I-A2 Self-hosted quantum.json** — dogfood: the project's own active work must be tracked in its quantum.json
- **I-A3 Plugin-manifest consistency linter** — plugin.json ↔ marketplace.json ↔ CHANGELOG.md ↔ README.md

### Category B: Parallel-execution correctness
- **I-B1 Semantic wire verifier** — after each worktree merge, run import/type/signature resolution across the merged code; fail the merge if broken
- **I-B2 Pre-merge conflict predictor** — before spawning parallel waves, analyze file overlap between stories; serialize conflicting pairs
- **I-B3 Shared-contract story** — ql-plan extracts inter-story contracts (types, signatures, interfaces) into a single story that runs first
- **I-B4 Cross-story type audit (expand type-auditor)** — detect duplicate type names, enum drift, API signature divergence
- **I-B5 Duplicate function detector** — post-merge AST scan for near-duplicate implementations from independent stories
- **I-B6 Wave-level integration test** — after each wave merges, run integration tests that span stories in the wave

### Category C: Review pipeline enhancement
- **I-C1 Post-merge holistic review** — run multi-perspective review after all stories pass; covers cross-story coherence
- **I-C2 Risk-adaptive review dispatch** — port soliton's 0-100 scorer + 2-7 agent dispatch into ql-review
- **I-C3 Intent-drift audit** — compare user-intent → PRD → design → plan → code; flag stages where intent changed
- **I-C4 Debate reviewer** — two reviewers disagree-then-debate; third arbitrates
- **I-C5 Reviewer memory** — findings from story N+1 informed by findings on stories 1..N

### Category D: Workflow efficiency
- **I-D1 Fast path for simple features** — allow brainstorm → plan (skip formal PRD) for features under complexity threshold
- **I-D2 Progressive materialization** — commit per task inside worktree, materialize to main only after whole story passes
- **I-D3 Early feedback checkpoints** — mid-story user-confirmation when AUTO_PROCEED=false
- **I-D4 Cache codebasePatterns in context** — avoid re-reading quantum.json verbatim each story

### Category E: Intent preservation
- **I-E1 Immutable intent snapshot** — store user's first-message + key clarifications verbatim in quantum.json
- **I-E2 Traceability chain** — every artifact cites its upstream (code→task→story→AC→PRD→design→intent); verify at merge time
- **I-E3 Socratic re-confirmation** — agents quote original intent before major decisions

### Category F: External tool adoption
- **I-F1 Superpowers skill port** — borrow: `verification-before-completion`, `finishing-a-development-branch`, `using-git-worktrees`, `subagent-driven-development`
- **I-F2 Ralph prd.json compat** — optionally emit Ralph-compatible prd.json alongside quantum.json
- **I-F3 OMC-style tri-model cross-check** — optional debate between Claude + Codex + Gemini
- **I-F4 Multi-runner parity** — audit whether aider/amp/codex/copilot/cursor/gemini actually work end-to-end

### Category G: AI-native-rebuild integration
- **I-G1 ContextPack consumption** — ql-brainstorm accepts `FeaturePartition` + `ContextPack` from Logical_inference as structured input
- **I-G2 EvidenceBundle emission** — post-merge output JSON conforming to `evidence-bundle-schema/v0.1`
- **I-G3 SLSA v1.0 provenance** — emit attestations at merge time
- **I-G4 Behavioral-replay harness** — new `skills/ql-replay` for shadow-legacy diff
- **I-G5 Feature-partition PR chunking** — respect partition boundaries in plan generation

### Category H: Observability
- **I-H1 Structured execution telemetry** — per-story costs, retries, review rounds; feeds dashboard
- **I-H2 Failure pattern accumulator** — expand known-failures.sh with heuristics + machine learning
- **I-H3 Plan critique skill** — review ql-plan's DAG BEFORE execution (dependency sanity, story sizing, AC verifiability)

### Category I: Anti-rationalization strengthening
- **I-I1 Completion-claim linter** — detect hedge phrases ("should work", "probably passes") in review output and block
- **I-I2 Fresh-evidence timestamp enforcement** — verify command evidence timestamp ≤ N minutes
- **I-I3 Post-mortem capture skill** — on failures, record WHY; feed to next planning

## Ranking Heuristic (pending agent data)

Score each idea on:
- **Impact** (1-5): how much it addresses user-named pain (parallel issues, review gaps, intent drift, workflow efficiency)
- **Effort** (S/M/L): implementation cost
- **Novelty** (0-2): 0=exists in superpowers/ralph/omc, 1=partially novel, 2=new contribution
- **Strategic fit** (1-3): alignment with AI-native-rebuild mission

Target: pick 4-6 **high-impact + low-effort** ideas for Stage 2-3 implementation in this pipeline run; document the rest as roadmap.

## **CRITICAL DISCOVERY: Integration debt dwarfs missing-ideas problem**

Feature branches carrying ~991 unmerged commits:

| Branch | Unmerged commits | Represents |
|--------|-----------------:|------------|
| ql/multi-runner | 256 | universal CLI orchestrator (aider/amp/codex/copilot/cursor/gemini) |
| ql/hardening-v2 | 226 | late-stage merge hardening |
| ql/modular-hardening | 185 | modular merge hardening foundation |
| ql/dag-intelligence | 148 | DAG validator + bottleneck/duplication/conflict agents |
| ql/progressive-materialization | 126 | progressive commit-per-task inside worktree |
| ql/post-mortem-fixes | 50 | post-mortem-driven fixes |
| fix/* (6 branches) | 7-16 each | review-finding cleanups |

Specific commits showing that many user-named problems ARE ALREADY SOLVED on branches but not on master:
- **d88b39a** (Feb 26): "add integration wiring checks to prevent dead code" — ql-plan + orchestrator now require wiring task per module-creating story; Step 3C integration check after each wave
- **5b078a2** (Feb 26): "resolve 11 parallel isolation/merge/wiring gaps" — safety-commit excludes quantum.json, worktree branch preserved on conflict, crash-recovery skips already-merged, post-merge test suite, DAG `.status != "in_progress"` exclusion, wiring check after each merge
- **37da7af** (Feb 26): "resolve 13 gaps from systemic workflow review" — including GAP-03 (integration wiring), GAP-04 (parallel agents self-review before signaling)
- **a067948** (fix/resolve-merge-conflicts): 1 commit that fixes the README conflict markers — **not merged**

### The reframe

User says: "wiring issues, conflicts, duplicate code, dead code [...] not yet fully addressed."

Observed reality: fixes exist on branches; master has regressed. The actual problems are:

1. **Integration debt** — ql/* branches with 50-256 unmerged commits each. No one branch is a clean integration of the full intended feature set. ql/multi-runner is presumably furthest along (v0.4.1 = multi-runner release) but hasn't absorbed hardening-v2 / dag-intelligence / progressive-materialization.
2. **Release-train discipline absent** — plugin.json=0.4.1 but CHANGELOG stops at 0.2.0; README has stale sections + unresolved conflict markers; idea-to-release audit trail is broken.
3. **Dogfooding gap** — quantum.json is stuck on Feb 2026 US-001 DAG-query story. The project is not using its own tooling to plan/execute its own improvements. Each ql/* branch is ad-hoc, not quantum-loop-driven.
4. **Verification of branch correctness unknown** — are those 256 commits on ql/multi-runner individually green? Is the full test suite passing on each ql/* tip? No visible evidence.
5. **Branch-proliferation cleanup absent** — 109 branches, 66 orphan worktree dirs. No tooling automates pruning.

This means two of Stage-1's proposed idea categories (A: Repo hygiene; most of B: Parallel execution) are **partially implemented on branches** — the improvement isn't "design new mechanisms," it's **"triage + integrate + verify existing mechanisms, then extend."**

### Per-branch deliverables (from git log summaries)

| Branch | Theme | Key deliverables on branch (not on master) |
|--------|-------|---------------------------------------------|
| ql/multi-runner | v0.4.x multi-runner support | Runner manifests (aider/amp/claude/codex/copilot/cursor/gemini), signal heuristics + fallback, runner library US-001..US-019, auto-generated instruction files, integration tests, security hardening |
| ql/hardening-v2 | Late-stage merge hardening | US-005 squash-on-merge, stash isolation tests, extended merge-strategy tests, init-guard hardening, init→merge integration |
| **ql/dag-intelligence** | **DAG validator + specialist agents** | **dag-validator coordinator + bottleneck-analyzer + duplication-detector + conflict-auditor + type-auditor** (addresses user's exact wiring/conflict/dup pain), agent-prompt context-window optimization |
| ql/modular-hardening | Modular merge hardening foundation | Worktree-lifecycle tests, known-failures lifecycle, merge-module integration into orchestrator, escalation-retry tests |
| ql/progressive-materialization | Progressive commit-per-task | Contract materialization, contract effectiveness tracking, auto-promotion of discovered contracts, path-traversal + merge-revert hardening |
| ql/post-mortem-fixes | Post-mortem-driven fixes | startedAt lifecycle, stale detection, final verification sweep, auto-generated execution observations, optional GitHub issue filing |

Observation: `agents/dag-validator.md`, `agents/bottleneck-analyzer.md`, `agents/duplication-detector.md`, `agents/conflict-auditor.md`, `agents/type-auditor.md` are **already present in the working tree** (git status shows `??`), but not committed to master. They are the heart of `ql/dag-intelligence`. They directly address the user's wiring/conflict/dup complaints.

### Implication for ranking

- **Priority 0 (pre-requisite)**: Consolidate `ql/hardening-v2` + `ql/dag-intelligence` + `ql/progressive-materialization` + `ql/multi-runner` into a clean integration branch. Without this, any new work will layer on top of an inconsistent base.
- **Priority 1 (new capability)**: Things the branches do NOT already address — multi-perspective post-merge review (C), intent preservation (E), AI-native-rebuild integration (G), observability (H), external-tool skill port (F1).
- **Priority 2 (polish)**: Repo hygiene automation (A) and workflow efficiency (D), assuming P0/P1 expose a stable base.

## Audit agent findings (from idea-stage/AUDIT_QL.md)

**Headline**: Plain files (Feb 15-25) and CPC-variant files (Mar 18-30) are **two complete parallel pipelines in one repo**. All post-mortem fixes live on CPC; plain files regress to pre-hardening-v1 behavior. Runtime loading order determines whether quantum-loop runs the hardened or vulnerable track — this is observable non-determinism.

### Specific gaps catalogued (G1-G21 in AUDIT_QL.md):

**Wiring (G1-G3)**: plain `ql-plan/SKILL.md` omits `wiring_verification` + `consumedBy` fields; plain `spec-reviewer` lacks the machine-verifiable import grep; no "post-merge import smoke test" in plain orchestrator.

**Conflicts (G4-G6)**: plain `lib/monitor.sh:85` is the exact `git merge --no-edit` flagged as Pattern-2 destructive-merge in `docs/post-mortems/2026-03-18-worktree-isolation-research.md:48-54`; `merge-strategy.sh` (563 LOC) + CPC-`monitor.sh` (417 LOC) provide the fix but only on CPC track; `dag-validator` never invoked from plain `ql-plan`, so `fileConflicts` enrichment is gated on CPC.

**Duplicates (G7-G9)**: `type-audit.sh` + `type-auditor` agent are wave-end triggered ONLY in CPC-orchestrator; plain track has no wave-end audit. Self-inflicted: `crash-recovery.sh` explicitly superseded by `resilience.sh:3` but not removed.

**Dead code / orphans (G10-G13)**: 6 plain `lib/*.sh` that have CPC duplicates are abandoned; `crash-recovery.sh` dead; plain orchestrator never calls `init-guard.sh`/`resilience.sh`/`known-failures.sh`/`materialize.sh`; ~10 untracked `-CPC-andyz-ZH84K.*` root-level files (marketplace, plugin, changelog, readme, quantum-loop scripts) look like abandoned in-progress rebrand.

**Review gaps (G14-G17)**: spec-reviewer is story-LOCAL (cross-story divergence structurally invisible); quality-reviewer refuses to examine unchanged code (Pattern-2 regressions out-of-scope BY DESIGN); Stage-3 cross-story review documented in 2026-02-27 design but never implemented in plain `ql-review/SKILL.md`; no AC-to-test mapping check.

**Intent preservation (G18-G21)**: ACs paraphrased at each stage; PRD non-goals not propagated to quantum.json; every design doc ends with "run /quantum-loop:ql-spec to generate a formal PRD" but **none of the designs were actually executed through the pipeline — the team never dogfoods its own hardening**; stub post-mortems at `2026-03-09-ql-test-feature-observations.md:1-15` + `2026-03-18-ql-test-feature-observations.md:1-15` show the post-mortem generator emits a file but doesn't populate Progress Log. Learning loop back into `codebasePatterns` is **broken**.

### Math-Research post-mortem failure catalog (2026-03-09, 34 stories / 80 tasks)

7 failure modes recorded; fix status per-mode:
1. Components built but never imported — ~80% addressed on CPC, not in plain `ql-plan`
2. Sibling stories with divergent `'google'` vs `'google-api-key'` constants — ~50% addressed via CPC `contracts.secret_keys`
3. Immutability-rule violations passed review — ~10% addressed (CPC adds dimension 8)
4. `BranchCard.tsx`/`PersonaSelector.tsx` created but inlined replacements in consumer — ~80%, but `consumedBy` still absent from plain track
5. US-004 stuck `in_progress` / 0 retries while 33 others passed — Partial; stale-detector in `resilience.sh`, `startedAt` in CPC orchestrator only
6. PRD missed lifecycle question — **Unfixed**; plain `ql-brainstorm` still lacks #7 LIFECYCLE
7. EntityDetector/PaperManager/TexParser 0 tests despite TDD mandate — **Unfixed in plain**

## Known Unknowns (remaining agents)

1. ✅ **Agent A (quantum-loop audit)** — COMPLETED. Report at `idea-stage/AUDIT_QL.md`.
2. ⏳ **Agent B (competitor survey)** — in progress.
3. ⏳ **Agent C (literature survey)** — in progress.

Once B and C return, finalize IDEA_REPORT ranking with the P0 → P1 → P2 framing below.

## Draft priority framing (pre-B-C-synthesis)

### P0 — Consolidation / integration (1-2 weeks, blocks all other work)
- **P0.1 Promote CPC-variant track to canonical**. For every `*-CPC-andyz-ZH84K.*`, verify it's the intended authoritative version and rename-over-plain. After verification, delete the abandoned plain copies and `crash-recovery.sh`. Capture evidence that the promoted track is functionally stable.
- **P0.2 Consolidate `ql/hardening-v2` + `ql/dag-intelligence` + `ql/progressive-materialization` + `ql/multi-runner` into a single integration branch**. Test the resulting composite on the quantum-loop repo itself.
- **P0.3 Merge `fix/resolve-merge-conflicts`** (1 commit) or manually apply its patch to master. Fix stale CHANGELOG.md. Reconcile plugin.json ↔ marketplace.json ↔ CHANGELOG.md ↔ README.md.
- **P0.4 Clean up 109 branches → ≤10 active** and 66 orphan worktree dirs. Add a `ql-housekeep` skill.
- **P0.5 Dogfood**: Every step in P0 is itself tracked in a new `quantum.json`; the project uses its own pipeline to fix itself.

### P1 — Close the review / intent gap the user named (2-3 weeks)
- **P1.1 Stage-3 cross-story review**. Ship the 2026-02-27 cross-story integration review as a first-class stage in `ql-review` on the canonical (post-P0) track. Must detect cross-story constant divergence, duplicated function names, unresolved symbol references.
- **P1.2 Post-merge holistic review skill**. After all stories pass, run multi-perspective review (security + architecture + correctness + consistency + hallucination) on the whole-feature diff, not per-story diffs.
- **P1.3 Risk-adaptive dispatch**. Port soliton's 0-100 scorer + 2-7 agent dispatch.
- **P1.4 Intent-drift audit**. New skill / pre-commit check comparing original user intent → design.md → PRD → quantum.json → code. Flag semantic drift with file:line evidence.
- **P1.5 Completion-claim linter**. Agent output scanner that rejects hedge phrases ("should work", "probably passes", "passed earlier") in review output.
- **P1.6 Learning-loop repair**. Post-mortem generator must populate Progress Log; auto-append new lessons to `codebasePatterns`; next iteration reads the updated patterns.

### P2 — New capability and external feature ports (ongoing)
- To be informed by Agent B (competitor survey) and Agent C (literature survey). Likely candidates:
  - Ralph prd.json compatibility (ecosystem interop)
  - OMC tri-model cross-check (disagreement as finding)
  - Superpowers `finishing-a-development-branch` + `subagent-driven-development` skill port
  - AI-native-rebuild EvidenceBundle emission
  - AST-aware semantic merge (already partly in merge-semantic.sh — promote + test)
  - Mutation testing nightly gate

### P3 — Long-term research wedges
- Behavioral-replay harness (Tier-A A12 from AI-native-rebuild roadmap)
- SLSA v1.0 provenance
- Formal verification of critical modules (Tier-C)
