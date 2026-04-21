---
name: quantum-loop-improvement-ideas-2026-04
description: Ranked improvement ideas for quantum-loop Stage-1 research pipeline, integrating audit + competitor survey + literature review.
date: 2026-04-21
pipeline: research-pipeline (Stage 1, Gate 1 pending)
inputs:
  - idea-stage/AUDIT_QL.md
  - idea-stage/COMPETITOR_SURVEY.md
  - idea-stage/LITERATURE_SURVEY.md
  - idea-stage/WORKING_NOTES.md
strategic_anchor: AI-native-rebuild project, BUILD layer (ai-native-project/STACK_THESIS.md)
---

# Quantum-Loop Improvement Ideas — Ranked

## 0. Context and direction

Quantum-loop is the **BUILD layer** of a three-layer AI-native subsidiary stack (`UNDERSTAND = Logical_inference/graph-code-indexing`, `BUILD = quantum-loop`, `REVIEW = soliton`). Its asserted moats (per `ai-native-project/TECHNICAL_MOAT.md`) are **M1 EvidenceBundle** and **M4 complexity moat (DAG + parallel worktree + Iron Law + anti-rationalization)**. The user-stated goals for this research pipeline:

1. Resolve persistent **parallel-execution gaps**: wiring issues, conflicts, duplicate code, dead code.
2. Upgrade **post-implementation review** beyond the per-story two-stage gate — invoke multiple external review tools (code-review, pr-review, etc.).
3. Make the pipeline **more efficient** and **faithful to user intent** / provided docs.
4. Adopt fresh features from **superpowers / ralph / oh-my-claudecode / gsd / gstack** and other harnesses.
5. Integrate relevant **academic progress** (2025-2026 multi-agent SWE literature).

## 1. The central discovery (reframes the improvement problem)

Independent audit of the codebase (`idea-stage/AUDIT_QL.md`) + git log analysis reveals that **the ideas addressing 80% of the user-stated pain already exist in this repo** — they live on feature branches and in `*-CPC-andyz-ZH84K.*` variant files that **have not been promoted to the canonical track**. Master has a **regressed baseline** relative to what's been built.

| Evidence | Detail |
|---------|--------|
| Plain `lib/monitor.sh:85` | Still uses `git merge --no-edit` — the exact destructive-merge pattern flagged as Pattern-2 weakness in `docs/post-mortems/2026-03-18-worktree-isolation-research.md:48-54`. The fix (AST-aware `lib/merge-semantic.sh` + classified routing in `lib/merge-strategy.sh`) exists but is wired only into the CPC-orchestrator. |
| Plain `ql-plan/SKILL.md` | Missing `wiring_verification` + `consumedBy` fields that exist only in `SKILL-CPC-andyz-ZH84K.md`. Root-cause fix for wiring is on the CPC track. |
| `agents/dag-validator.md` + bottleneck + duplication + conflict auditors | All present in working tree (untracked in `git status`), shipped on `ql/dag-intelligence` (148 commits ahead). The agents that **literally address** user-named concerns (bottleneck, duplication, conflict) exist but are not on master. |
| README.md | Has **3 unresolved merge conflict markers** on master right now. `fix/resolve-merge-conflicts` is 1 commit ahead of master and resolves them — **not merged**. |
| CHANGELOG.md | Stops at v0.2.0. Plugin.json is v0.4.1. Two minor releases undocumented. |
| `quantum.json` | Frozen on the Feb-2026 US-001 DAG-query story. The project **has not dogfooded its own pipeline on any of the 7 hardening cycles since** (AUDIT §6, G20). |
| 109 git branches, 66 orphan `.claude/worktrees/agent-*` directories | Crash-recovery exists but is inconsistently applied; branch hygiene is manual. |

Consequence for ranking: **"Design new mechanisms" is a lower priority than "consolidate and promote existing work, then extend."** Without a clean base, any new idea will accrete on an inconsistent substrate.

## 2. Ranking framework

Ideas scored on five criteria (1-5 unless otherwise noted):

- **Impact** — how directly the idea addresses a user-stated pain (wiring / conflicts / dup / dead / review / intent / efficiency).
- **Effort** (inverted in score, S/M/L): S=1-3 days, M=1-2 weeks, L=3+ weeks.
- **Novelty** (0-2): 0 = exists in superpowers/ralph/omc and we adopt, 1 = extends existing work, 2 = new in the OSS field.
- **Strategic fit** — alignment with AI-native-rebuild (evidence bundle, context pack consumption, behavioral replay).
- **Pre-requisite status** — blocked by P0 consolidation? (yes → deferred regardless of other scores).

Composite priority tiers: **P0** (prerequisite, must ship first), **P1** (close user-stated gap), **P2** (external-tool feature adoption), **P3** (literature wedge), **P4** (AI-native-rebuild integration).

## 3. Ranked idea table

### P0 — Consolidation / integration (prerequisite, ~1-2 weeks)

The only tier the project **cannot skip**. Without this, every P1-P4 idea layers on inconsistent base.

| ID | Idea | Key actions | Effort | Blocks |
|----|------|------------|:------:|-------|
| **P0.1** | **CPC → canonical promotion** | For every `*-CPC-andyz-ZH84K.*`, verify correctness, promote over plain file, delete plain orphan. Same for root-level (`plugin-CPC…json`, `marketplace-CPC…json`, `CHANGELOG-CPC…md`, `README-CPC…md`, `quantum-loop-CPC…{sh,ps1}`, `quantum-CPC…json`). Delete `crash-recovery.sh` (superseded per `resilience.sh:3`). | S–M | Everything |
| **P0.2** | **Merge integration branch from `ql/hardening-v2` + `ql/dag-intelligence` + `ql/progressive-materialization` + `ql/multi-runner`** | Create `ql/integrate-2026-04`, cherry-pick / merge + fix conflicts. Gate: full test suite green on the integrated tip. Delete branches after successful merge. | M | All hardening work |
| **P0.3** | **Apply `fix/resolve-merge-conflicts` + reconcile plugin.json / marketplace.json / CHANGELOG.md / README.md** | 1-commit apply + hand-written CHANGELOG backfill for 0.3.x and 0.4.x. Verify plugin displays correct version after reinstall. | S | Public perception, release discipline |
| **P0.4** | **Branch + worktree hygiene skill (`ql-housekeep`)** | New skill that: detects merge-conflict markers, orphan `.claude/worktrees/agent-*`, stale `ql/*` / `worktree-agent-*` branches, duplicated `-CPC…` files; emits report + guarded auto-fix (`--dry-run` default). Register as recurring pre-pipeline hook. | S | Recurrence prevention |
| **P0.5** | **Dogfood**: Every action above goes through a new `quantum.json` generated by `/ql-spec` + `/ql-plan`. First real test of the pipeline consuming its own design docs. | The pipeline's first real self-use. Forces the team to feel the rough edges they've shipped for users. | S (overhead) | Credibility of the moat |

### P1 — Close the user-stated review / wiring / intent gap (~2-3 weeks after P0)

| ID | Idea | Backing | Mechanism (condensed) | Impact | Effort | Novelty |
|----|------|---------|-----------------------|:------:|:------:|:-------:|
| **P1.1** | **Stage-3 cross-story + post-merge holistic review** (close structural review-gate blind spot G14-G16) | AUDIT §6 (G14-G16), `docs/plans/2026-02-27-cross-story-integration-design.md:89-104`, MARS 2509.20502 | After all stories in a wave pass, run a whole-feature review pass that (a) scans for cross-story constant divergence (the `'google'` vs `'google-api-key'` Math-Research class), (b) runs import/type resolution across the wave's merged tree, (c) runs full test suite, (d) regenerates barrel + dep manifests. Failure routes to a targeted fix-story, not a per-story retry. | 5 | M | 1 |
| **P1.2** | **Multi-perspective review aggregator** (invokes `soliton:pr-review`, `oh-my-claudecode:code-reviewer`, `superpowers:code-reviewer`, and `oh-my-claudecode:architect` in parallel) | Competitor #5, MARS 2509.20502, RevAgent 2511.00517, Devin critic-before-execution | New skill `ql-deep-review`. For each reviewer: pass story diff + full-feature diff + acceptance criteria + evidence requirements. Aggregate findings by category (correctness / security / architecture / consistency / hallucination) with dedup + severity + evidence filter (drop findings with no `file:line` cite). Only CRITICAL + HIGH issues block; others logged to `progress.txt`. Opt-in via `--deep-review` flag; mandatory for the final wave. | 5 | M | 2 |
| **P1.3** | **Risk-adaptive reviewer dispatch** (port from soliton) | Competitor #5 (Adversarial critic), soliton M3 in `ai-native-project/TECHNICAL_MOAT.md` | Per-story 0-100 risk score (blast radius from graph signals if available, complexity, sensitive paths, file-size, AI-authored signals, test-coverage gap, taint path). Score → dispatch: LOW=2 reviewers, MEDIUM=4, HIGH=6, CRITICAL=7 + multi-pass. | 4 | M | 1 |
| **P1.4** | **Intent-drift audit skill (`ql-intent-check`)** | SCF 2604.16339 (Semantic Intent Graph), Agent-Drift 2601.04170, AUDIT §6 G18-G21 | New skill that compares original user intent → design.md → PRD → quantum.json story ACs → per-story task list → merged code. Flags semantic divergence with file:line evidence. Immutable `userIntent` snapshot stored in quantum.json at `/ql-brainstorm` exit. Forces `/ql-verify` to re-read this snapshot before signaling STORY_PASSED. | 4 | M | 2 |
| **P1.5** | **Completion-claim linter + polite-stop ban** | Competitor #15 (Superpowers + Ralph), FUR 2502.14829 | Lightweight grep-based lint on every agent output before orchestrator acts: reject hedge phrases (`should work`, `probably passes`, `passed earlier`), reject non-fresh evidence (timestamp > N minutes), reject approval messages that don't proceed directly to commit. Embedded in `lib/signal-heuristics.sh`. | 4 | S | 0 |
| **P1.6** | **Post-implementation AI-slop cleanup** (Ralph/OMC 7.5 + 7.6) | Competitor #1, DePA 2502.20246 | After the review gate passes each story, mandatory pass: `knip` / `ts-prune` / DePA line-perplexity check → propose deletions → regression test → roll back if any test fails. Scoped to story's changed files (never widens). Opt-out via `--no-deslop` only. | 5 | S | 1 |
| **P1.7** | **Post-mortem Progress-Log generator repair + auto-append to `codebasePatterns`** (close learning loop) | AUDIT §6 G21; the empty stub files at `docs/post-mortems/2026-03-{09,18}-ql-test-feature-observations.md:1-15` | Fix the generator that currently emits the heading but not the rows. Each failed / retried story emits: `{story_id, phase, error_summary, root_cause, fix_applied, lesson}`. Promote to a `codebasePatterns` entry if the lesson is generalizable. Next iteration reads the updated patterns. | 4 | S | 1 |

### P2 — External harness feature adoption (~2-3 weeks, parallelizable with P1)

| ID | Idea | Source | Mechanism | Impact | Effort |
|----|------|--------|-----------|:------:|:------:|
| **P2.1** | **Wave-based DAG execution with explicit sync-point validation** | GSD, OMC Team, Flash-Searcher 2509.25301 | Explicit wave compilation from `dependsOn` graph. Between waves, run sync-point checks: wire verification, barrel regen, type audit, integration tests. Replaces current ad-hoc "re-query after each merge" with structured wave ticks. | 5 | M |
| **P2.2** | **Spec-reviewer hunts OVER-building** (not just under-building) | Superpowers v4.x spec-reviewer | Prompt update to explicitly look for: missing reqs + **EXTRA features not requested** + misinterpretations. Compare diff against PRD non-goals (which are now propagated per P1.4). | 5 | S |
| **P2.3** | **Stage-handoff documents accumulating across pipeline** (`.handoffs/<stage>.md`) | OMC Team | Each skill writes a handoff: `{decided, rejected_with_reason, risks, files, remaining}`. Next skill reads all prior handoffs before first response. Survives context compaction. | 4 | S |
| **P2.4** | **Phase-skipping via artifact detection** | OMC Autopilot | Each skill checks for prior-stage artifacts (e.g., `ql-spec` detects an existing PRD whose hash matches current design doc → skip). Enables composing `brainstorm → plan` for simple features without forced PRD. | 3 | S |
| **P2.5** | **Implementer self-review checklist before STORY_PASSED signal** | Superpowers, OMC Team, gsd | Structured self-audit (Completeness / Quality / Discipline / Testing) inside the worktree agent before it signals. Fix obvious issues locally. Raises the floor of what the reviewer sees. | 4 | S |
| **P2.6** | **Task watchdog + circuit breaker** | OMC Team, Self-improve | In-progress age tracking (5min → status check, 10min → reassign, 3 consecutive same-error → "fundamental issue", stop). Wires into `lib/resilience.sh`. | 4 | S |
| **P2.7** | **Commit trailer protocol for decision preservation** | OMC (ubiquitous) | Standardize trailers: `Constraint:`, `Rejected: opt \| reason`, `Directive:`, `Confidence:`, `Scope-risk:`, `Not-tested:`. Implementer appends to every commit. `git log --grep="Rejected:"` surfaces history of considered-and-rejected. | 3 | S |
| **P2.8** | **Ambiguity-gated brainstorm** | OMC deep-interview | Score ambiguity across weighted dimensions (goal 40% / constraints 30% / criteria 30%) + ontology stability tracking across rounds. Refuse to write PRD until ambiguity < 20%. Adds Contrarian / Simplifier / Ontologist challenge modes at round thresholds. | 4 | M |
| **P2.9** | **Cross-provider critic option** (`--critic=codex`) | OMC Ralph | Optional final review by a different provider (Codex or Gemini) with structured prompt including ACs + related files + optimality question. Different failure modes = higher catch rate. Requires `lib/runner.sh` support for non-Claude critics (already present). | 3 | S |
| **P2.10** | **Tournament selection + re-benchmark-on-merge** (for stories with measurable criteria) | OMC Self-improve | For stories where multiple approaches viable: N parallel implementers with distinct `approach_family` tags, rank by score, merge winner, re-benchmark, revert if regression. Archive losers as git tags. Opt-in per-story in `quantum.json`. | 3 | M |

### P3 — Academic technique adoption (~2-4 weeks, parallelizable)

Tier S + A from `LITERATURE_SURVEY.md`. Many co-locate with P1/P2 — noted where overlap.

| ID | Idea | Paper | Overlaps P1/P2 | Impact | Effort |
|----|------|-------|----------------|:------:|:------:|
| **P3.1** | **Skeleton-first story type (SSAT)** — generate interfaces / types / empty exports as a dedicated story before body-fill stories | arXiv:2511.03404 | **Wiring fix, subsumes P1.1 data path** | 5 | M |
| **P3.2** | **Conflict grading pre-merge** — grade by AST-operation complexity; route 1-2 → git, 3-4 → LLM-merge, 5 → escalate | ConGra 2409.14121 | Extends `lib/merge-strategy.sh` | 4 | S |
| **P3.3** | **KBI-then-FAR reviewer split** — high-recall bug-finder then precision filter | ICML 2505.17928 | Implements P1.2 architecture | 5 | M |
| **P3.4** | **Actionability signal-to-noise gate** — every review comment must cite file:line evidence; drop comments below threshold | arXiv:2604.03196 | Part of P1.5 / P1.2 | 4 | S |
| **P3.5** | **Trajectory-length early kill** — score each story by (step count, search/read/edit ratio); kill outliers before retry budget wasted | arXiv:2511.00197 + TRAJEVAL 2603.24631 | Extends `lib/resilience.sh` | 4 | S |
| **P3.6** | **Semantic Intent Graph + Drift Monitor** — extract `{objects, verbs, constraints}` from ACs; check incoming merges against peer intents | SCF arXiv:2604.16339 | Implements P1.4 formally | 5 | M-L |
| **P3.7** | **Two-stage semantic clone detection** — LLM screen → execution validation for duplicates | HyClone 2508.01357 | Upgrades existing `duplication-detector` agent | 4 | S-M |
| **P3.8** | **TraceCoder Observe-Analyze-Repair for verify loop** | arXiv:2602.06875 | Refactor `ql-verify` into three sub-agents with `codebasePatterns` as lesson memory | 4 | M |
| **P3.9** | **Re-grounding every N stories** — inject PRD re-read + intent snapshot check every 5 stories | Agent-Drift 2601.04170 + Goal-Drift 2505.02709 | Part of P1.4 | 3 | S |
| **P3.10** | **Dead-code post-generation pass** — `knip` / `tsr` + DePA perplexity z-score | DePA 2502.20246 | Part of P1.6 | 4 | S |
| **P3.11** | **Constitutional constraints** in `quantum.json.constitution` array (no secrets, no mutation, input validation, etc.); spec-reviewer refuses violating specs | arXiv:2602.02584 | 73% security defect reduction | 3 | S |

### P4 — AI-native-rebuild strategic integration (~4-6 weeks, parallelizable)

| ID | Idea | Source | Impact | Effort |
|----|------|--------|:------:|:------:|
| **P4.1** | **Consume `FeaturePartition` + `ContextPack`** from Logical_inference as input to `ql-brainstorm` | `ai-native-project/STACK_THESIS.md §2.4` | 4 | M |
| **P4.2** | **Emit EvidenceBundle per merged PR** conforming to `ai-native-project/evidence-bundle-schema/v0.1` | `STACK_THESIS.md §3`, AI-native moat M1 | 5 | M |
| **P4.3** | **SLSA v1.0 provenance + in-toto attestations** at merge time | `ALGORITHM_ROADMAP.md Tier-A A10` | 3 | S |
| **P4.4** | **Behavioral-replay harness** (`skills/ql-replay`) for shadow vs. legacy equivalence | `ALGORITHM_ROADMAP.md Tier-A A12` | 4 | L |
| **P4.5** | **Feature-partition-aware PR chunking** in plan generation | `ALGORITHM_ROADMAP.md Tier-A A13` | 3 | M |
| **P4.6** | **Close the soliton feedback loop** — consume soliton's `AgentInstruction[]` output as a new retry-input for failed stories | `STACK_THESIS.md §2.2` | 4 | M |

## 4. Stage-2 shortlist (pick-4 recommendation)

Given AUTO_PROCEED=true, budget = one pipeline run, and the constraint that P0 is a prerequisite, the recommended Stage-2 implementation shortlist is:

| Choice | Idea | Why | Approximate sizing |
|--------|------|-----|-------------------|
| **#1** | **P0 bundle (P0.1 + P0.2 + P0.3 + P0.4 + P0.5)** | The single highest-leverage work. Without this, every other idea accretes on inconsistent base, and the project's own moat claim (M4 complexity + Iron Law) is contradicted by the repo state. Dogfooding (P0.5) turns this into the first genuine pipeline self-use. | 1-2 weeks |
| **#2** | **P1.1 Stage-3 cross-story + post-merge review** + **P1.6 Post-implementation AI-slop cleanup** | Close the structural review blind spot (G14-G16) AND the dup/dead-code gap in one coherent capability. Mechanism ships as two new skills: `ql-deep-review` (whole-feature) and `ql-deslop` (per-story cleanup). | 1 week |
| **#3** | **P1.4 Intent-drift audit + P1.7 Post-mortem generator repair** | Address the two intent-preservation failures (G18-G21) and fix the learning loop. User's top non-parallel concern ("stick to original user's intent"). | 1 week |
| **#4** | **P2.1 Wave-based DAG execution with sync-point validation** (also subsumes P2.5 self-review + P3.5 trajectory kill) | Concrete structural fix for the parallel-execution gap. Sync-point between waves is where wiring / conflicts / type-audit get validated. | 1 week |

Parallel-track (P3 academic work, P4 integration) is deferred to a follow-on pipeline run because (a) it's lower-leverage relative to P0+P1 given current base-state instability, (b) P4 depends on Logical_inference delivering a working `graph-cli` + EvidenceBundle schema (status: schema v0.1 exists, CLI not shipped per `ai-native-project/STACK_THESIS.md §4`).

### What the shortlist explicitly defers

- **P2.8 Ambiguity-gated brainstorm** — high-quality, but a big UX change; pilot after P0+P1 land.
- **P3.1 SSAT skeleton-first** — research-grade win, but requires a new story-type schema and significant DAG-validator rewrites. Queue for next cycle.
- **P3.6 Semantic Intent Graph formal** — paper-grade, but its leaner cousin (P1.4) captures 70% of value at 20% of effort.
- **All P4** — strategic but blocked on Logical_inference + soliton ecosystem maturity.

## 5. Anti-recommendation (explicit "do not do this" list)

- **Do not** design a new hardening skill without first promoting the CPC track. Stacking more mechanisms on an unresolved fork makes the problem worse.
- **Do not** add new reviewer agents before the actionability signal-to-noise gate (P1.5 / P3.4) lands. More low-signal noise kills throughput faster than it raises quality.
- **Do not** port OMC's tournament selection (P2.10) as a default mode. Great for research stories; cost-prohibitive for the common case.
- **Do not** attempt AI-native-rebuild EvidenceBundle emission (P4.2) before the schema has settled in the upstream ai-native-project repo. Ship integration glue, not schema versions.
- **Do not** introduce runtime self-evolution patterns (Live-SWE-agent 2511.13646) until post-P0. Agents mutating their own scaffold on an inconsistent base is an incident generator.

## 6. Measurement plan (what will prove the improvements worked)

After the Stage-2 shortlist ships, the following metrics become the evidence base:

| Metric | Target | Measured on |
|--------|--------|-------------|
| `master` branch count reduced from 109 → ≤10 | yes/no | git branch -a |
| Orphan worktrees in `.claude/worktrees/` | 0 | ls |
| Test suite green on master (all 29 unit + 10 integration tests) | yes/no | bash tests/*.sh |
| README conflict markers | 0 | grep |
| CPC-variant file count | 0 | find |
| `quantum.json` last-updated date | within 7 days | jq |
| Cross-story wire failures per 10 merged stories | 0 | post-merge audit |
| Duplicate-function findings per 10 merged stories | ≤1 | duplication-detector agent |
| Dead exports introduced per merged story | 0 | knip / tsr |
| Intent-drift findings per feature (P1.4) | 0 CRITICAL | ql-intent-check output |
| Review-comment actionability (P3.4) | ≥60% (human baseline from Sun 2025) | manual sample |
| Post-mortem Progress Log population rate | 100% of failed stories | doc-inspection |
| **Dogfooding metric**: Was this feature implemented via the pipeline itself? | yes | `codebasePatterns` traceback |

## 7. Gate-1 decision checkpoint

**Recommendation**: proceed with the Stage-2 shortlist in priority order (#1 → #2 → #3 → #4), dogfooding the pipeline (P0.5) so that this research-pipeline run itself becomes the project's first real self-use of `/ql-spec` → `/ql-plan` → `/ql-execute`.

**Alternative options** for user override:
- **A. P0 only** (scope to 1 week; defer P1+ to follow-on pipeline).
- **B. Skip P0, do P1+P2 on a clean branch** (risky — inherits the fork problem, but fastest path to visible new capability).
- **C. Shift focus to P4** (AI-native-rebuild integration) — requires Logical_inference + soliton delivery first; most likely blocked.
- **D. Academic wedge**: run P3.1 + P3.3 + P3.6 as a publishable research experiment (SSAT + KBI-FAR + SCF).

Defaulting to **the recommendation** (#1-#4 bundle) unless user overrides.

## 8. Supporting documents

- `idea-stage/AUDIT_QL.md` — 3,238 words, file:line citations for every finding.
- `idea-stage/COMPETITOR_SURVEY.md` — 552 lines; 11 tools deep-profiled; 30-feature × 17-tool matrix; top-15 borrow list.
- `idea-stage/LITERATURE_SURVEY.md` — 402 lines; 35 papers (2024-2026) across 10 clusters; top-15 ranked recipes.
- `idea-stage/WORKING_NOTES.md` — Scratch-pad with my own independent analysis (CPC reframe, branch characterization, priority framing).
- `ai-native-project/STACK_THESIS.md`, `TECHNICAL_MOAT.md`, `ALGORITHM_ROADMAP.md` — Strategic anchor docs the pipeline must serve.

## 9. Rationale summary (for the user's Gate-1 decision)

- The project has **substantially solved the user-stated pain** (wiring / conflicts / dup / dead code) — but those fixes live on CPC-variant files and unmerged branches. Master has a regressed baseline. Consolidation (P0) is the single highest-leverage lever.
- User-stated **review-pipeline** concern maps to the structural G14-G16 blind spots. P1.1 + P1.2 + P1.6 close them with a sequence of three cohesive skills.
- User-stated **intent preservation** concern maps to G18-G21. P1.4 + P1.7 close them. Literature (SCF, Agent-Drift) formally names this phenomenon as "Semantic Intent Divergence" and validates the approach.
- External-tool adoption (P2) is mostly **low-effort polish** (watchdog, trailers, self-review checklist, handoff docs). Adopt incrementally.
- Academic wedge (P3) has real research value but **no direct user-requested pain reduction**. Queue for a follow-on cycle.
- AI-native-rebuild integration (P4) is **blocked on dependencies** outside this repo. Defer.

The improvement plan is therefore: **Consolidate first (P0). Fix the named pain (P1). Borrow polish (P2). Research-wedge later (P3/P4).**
