# Literature Survey: Multi-Agent Software Engineering Techniques for Quantum-Loop

**Date:** 2026-04-21
**Scope:** 2025-2026 academic literature applicable to quantum-loop's DAG-based parallel worktree orchestration, two-stage review gate, and Iron-Law verification.
**Goal:** Identify techniques that directly address known gaps: parallel-story wiring issues, merge conflicts, duplicate code, dead code, review gaps missing cross-story semantic issues, intent drift across long pipelines.

---

## Cluster 1: Multi-Agent SWE Benchmarks & Methods

### 1.1 Agentless: Demystifying LLM-based Software Engineering Agents
- **Citation:** Xia, Deng, Dunn, Zhang. arXiv:2407.01489 (2024, seminal, widely cited through 2026).
- **Core claim:** A simple three-phase pipeline (localization → repair → patch validation) beats most agent scaffolds at a fraction of the cost.
- **Technique:** Deterministic phases with no autonomous tool-use loop; uses hierarchical localization (files → classes/functions → edit locations) then samples candidate patches and filters via generated reproduction tests.
- **Applicability to quantum-loop:** Validates quantum-loop's structured skill-phase architecture (brainstorm → spec → plan → execute → review → verify). Suggests that skeleton-regen, barrel-regen, dep-manifest steps should remain deterministic instead of LLM-driven tool loops.
- **Port effort:** Low — pattern already partially matches quantum-loop's design.

### 1.2 Live-SWE-agent: Can Software Engineering Agents Self-Evolve on the Fly?
- **Citation:** Xia, Wang, Yang, Wei, Zhang. arXiv:2511.13646 (2025). Claude Opus 4.5 + Live-SWE-agent = 79.2% SWE-bench Verified.
- **Core claim:** An agent that starts with only bash tools and evolves its own scaffold during a run outperforms hand-engineered scaffolds (77.4% SWE-bench Verified, 45.8% SWE-bench Pro).
- **Technique:** Runtime self-evolution — the agent proposes, tests, and adopts new sub-capabilities mid-task; skill priors are induced rather than predefined.
- **Applicability to quantum-loop:** Orchestrator could let runners log scaffold patches (new lib helpers, new signal heuristics) that survive across stories when validated, instead of hard-coding all scaffolding in `lib/`.
- **Port effort:** High — requires safe scaffold-patch admission + rollback.

### 1.3 Understanding Code Agent Behaviour: Success vs. Failure Trajectories
- **Citation:** Majgaonkar et al. arXiv:2511.00197 (ICSE 2026).
- **Core claim:** Studied OpenHands / SWE-agent / Prometheus trajectories; failed runs are systematically longer with higher variance; fault-localization success ≈72-81% even in failures — success differentiator is approximate vs. exact edit region.
- **Technique:** Empirical trajectory signatures: (a) long-tail step count predicts failure, (b) defensive programming + context gathering predict success, (c) exact edit-region matching predicts acceptance.
- **Applicability to quantum-loop:** Add per-story trajectory-length kill-switch in `lib/resilience.sh`; signal-heuristics.sh should score stories by (steps, token variance, retry count) to escalate early.
- **Port effort:** Low — heuristic thresholds in existing monitor script.

### 1.4 TRAJEVAL: Decomposing Code Agent Trajectories for Fine-Grained Diagnosis
- **Citation:** Kim et al. arXiv:2603.24631 (2026).
- **Core claim:** Splitting trajectories into search/read/edit stages yields Pass@1 prediction within 0.87-2.1% MAE; real-time stage-signal feedback lifts SoTA models by 2.2-4.6 pp at 20-31% lower cost.
- **Technique:** Stage-level telemetry (file-localize, function-comprehend, edit-target) fed back into the agent as a soft signal.
- **Applicability to quantum-loop:** In `lib/monitor-CPC-andyz-ZH84K.sh`, classify each tool call into search/read/edit; when search phase exceeds budget, redirect runner to graph-query.
- **Port effort:** Medium.

---

## Cluster 2: Parallel Code Generation / DAG Execution

### 2.1 Flash-Searcher: Fast and Effective Web Agents via DAG-Based Parallel Execution
- **Citation:** Qin, Chen, Wang et al. arXiv:2509.25301 (2025).
- **Core claim:** Replacing sequential ReAct with a DAG of subtasks yields +accuracy (67.7% BrowseComp, 83% xbench) while cutting execution steps 35%.
- **Technique:** Dynamic workflow optimization — DAG is refined mid-run based on intermediate results; summary module compresses finished branches before dependents execute.
- **Applicability to quantum-loop:** Directly relevant — the orchestrator already builds a story DAG. Adopt (a) mid-run DAG refinement when stories reveal new dependencies (dag-query.sh), (b) branch-summary feeding into dependent stories instead of re-reading the whole codebase.
- **Port effort:** Medium — requires dynamic DAG mutation, which today's design forbids.

### 2.2 Prompt2DAG: Modular LLM-Based Pipeline Generation
- **Citation:** arXiv:2509.13487 (2025).
- **Core claim:** Extracts a canonical DAG JSON from natural-language descriptions and auto-generates executable orchestration code, evaluated via static-analysis, structural, and conformance tests.
- **Technique:** Chained prompts convert NL → structured JSON → platform-neutral spec → target DAG; each stage separately verified.
- **Applicability to quantum-loop:** The ql-plan skill should emit a machine-verifiable DAG JSON (already has quantum.json); add a `dag-validator` agent (matches the one in `agents/dag-validator.md`) to enforce structural/conformance checks before execution, reducing wiring failures at story start.
- **Port effort:** Low — `agents/dag-validator.md` already exists.

### 2.3 Project-Level Code Generation via Multi-Agent Collaboration and Semantic Architecture Modeling
- **Citation:** Zhao et al. arXiv:2511.03404 (2025).
- **Core claim:** CodeProjectEval (18 repos, avg 12.7 files × 2,388 LoC/task). ProjectGen = architecture → skeleton → code-fill, iterative + memory; 10× over baselines.
- **Technique:** Semantic Software Architecture Tree (SSAT) — a structured, semantically rich tree bridging requirements → source; skeleton generation before body fills provides type scaffolding that reduces cross-file wiring bugs.
- **Applicability to quantum-loop:** Addresses the exact wiring-issues gap. Adopt an explicit "skeleton" phase: generate interfaces/types/empty exports first as one story, have downstream stories fill bodies against a stable SSAT. This matches `lib/barrel-regen.sh` + a new skeleton regen pass.
- **Port effort:** Medium — requires new "skeleton" story template and SSAT schema.

### 2.4 Knowledge-Guided Multi-Agent Framework for Application-Level Code Generation (KGACG)
- **Citation:** arXiv:2510.19868 (2025).
- **Core claim:** COPA (plan) + CA (code) + TA (test) closed loop handles application-level SRS → executable code better than flat multi-agent.
- **Technique:** Three specialized roles with explicit SRS+ADD inputs and feedback channels between TA and CA.
- **Applicability to quantum-loop:** The two-stage review gate already provides spec + quality agents; KGACG's lesson is to pipe test-agent feedback into the coding agent (not just spec-reviewer), closing the TDD loop inside a single story execution.
- **Port effort:** Low — add runtime test-feedback injection into ql-execute.

---

## Cluster 3: Conflict Resolution in LLM-Generated Merges

### 3.1 ConGra: Benchmarking Automatic Conflict Resolution
- **Citation:** HKU System Security Lab. arXiv:2409.14121 (2024, seminal).
- **Core claim:** 44,948 conflicts from 34 projects in C/C++/Java/Python, graded by complexity into 7 categories; LLMs with longer context do NOT always improve; LLaMA3-8B/DeepSeek-V2 beat specialized code LLMs.
- **Technique:** Conflict-complexity grading via lightweight AST-level operation analysis; color-coded operations in conflict blocks.
- **Applicability to quantum-loop:** `lib/merge-semantic.sh` and `lib/merge-strategy.sh` should grade conflicts before attempting auto-resolve. Use simple graders (same-line edit, overlapping imports, signature change) and route to different strategies.
- **Port effort:** Low — conflict grading is ~200 lines of shell/TS.

### 3.2 Semantic Consensus Framework (SCF)
- **Citation:** Acharya. arXiv:2604.16339 (March 2026).
- **Core claim:** Identifies "Semantic Intent Divergence" as root cause of multi-agent failures; SCF has 6 components including Drift Monitor and Conflict Detection Engine that identifies contradictory/contention-based/causally-invalid intent combinations.
- **Technique:** Process Context Layer (shared operational semantics) + Semantic Intent Graph (formal intent) + Conflict Detection Engine (real-time) + Policy-Authority-Temporal consensus hierarchy.
- **Applicability to quantum-loop:** Most direct match to quantum-loop's cross-story semantic review gap. Add a Semantic Intent Graph derived from acceptance criteria; every merged commit is checked against it for contradictions with peer stories before the branch lands.
- **Port effort:** High — new layer, but high payoff.

### 3.3 Rethinking Verification for LLM Code Generation: From Generation to Testing (SAGA)
- **Citation:** arXiv:2507.06920 (2025).
- **Core claim:** Human-LLM co-generation of tests achieves 90.62% detection rate; verifier accuracy +10.78% vs. LiveCodeBench-v6.
- **Technique:** Test-as-merge-gate: generate tests orthogonal to the LLM's own hypothesis and run them as merge validation.
- **Applicability to quantum-loop:** After merge in `lib/merge-semantic.sh`, require a test-set union (story-A tests + story-B tests) to pass; if either regresses, block the merge and route back to orchestrator.
- **Port effort:** Medium — requires per-story test manifest preservation across merges.

---

## Cluster 4: Duplicate Code Detection + Type Consolidation

### 4.1 HyClone: Bridging LLM Understanding and Dynamic Execution for Semantic Code Clone Detection
- **Citation:** arXiv:2508.01357 (2025).
- **Core claim:** Two-stage LLM-screen + execution-validation yields +1224% recall, +479% F1 on semantic (Type-4) clones vs. baseline LLM classification.
- **Technique:** Stage 1: LLM screens pairs for semantic similarity. Stage 2: LLM synthesizes test inputs and runs both snippets; functional equivalence = clone.
- **Applicability to quantum-loop:** The `duplication-detector` agent (already in `agents/`) should use this exact two-stage pattern on code regions touched by concurrent stories to detect duplicated helpers before merge.
- **Port effort:** Low-medium — agent spec already exists.

### 4.2 An Empirical Study of LLM-Based Code Clone Detection
- **Citation:** Zhu et al. arXiv:2511.01176 (2025).
- **Core claim:** LLMs achieve F1=0.943 on CodeNet but drop sharply on BigCloneBench — syntactic sensitivity is the dominant failure mode; gives concrete prompt patterns that mitigate it.
- **Technique:** Canonicalization (alpha-rename + AST-normalize) before LLM call.
- **Applicability to quantum-loop:** Canonicalize identifiers in duplication-detector before sending to LLM; otherwise story-A's `parseRequest` and story-B's `parseReq` will be missed.
- **Port effort:** Low.

### 4.3 Code Refactoring with LLM: Few-Shot Evaluation
- **Citation:** arXiv:2511.21788 (Nov 2025).
- **Core claim:** Few-shot LLM refactoring across C/C++/C#/Python/Java; instruction fine-tuning yields meaningful gains on rename/extract/consolidate.
- **Technique:** Few-shot examples of clean refactors + explicit acceptance predicates (tests still pass, semantics unchanged).
- **Applicability to quantum-loop:** After duplication-detector flags a pair, spawn a single "refactor-consolidator" story that extracts the duplicate into a shared lib with a test gate.
- **Port effort:** Medium — new orchestrator hook for consolidation stories.

---

## Cluster 5: Dead-Code / Orphan Detection Post-Generation

### 5.1 Beyond Natural Language Perplexity: Detecting Dead Code Poisoning
- **Citation:** arXiv:2502.20246 (2025).
- **Core claim:** DePA (Dead-code Perplexity Analysis) identifies anomalous lines by comparing line-level perplexity against file distribution; catches injected dead code LLMs produce.
- **Technique:** Token-level perplexity per line, z-score against file; anomalies = dead/bolted-on code.
- **Applicability to quantum-loop:** Post-story hook: run DePA on changed files, route high-z lines to quality-reviewer agent for pruning. Complements ts-prune/knip by catching code that looks live but isn't reachable.
- **Port effort:** Medium — needs small LM runner, could use local Qwen-0.5B.

### 5.2 Industry Tools Baseline (Knip, ts-prune, line/tsr, fallow)
- **Citation:** Not a paper but acknowledged as the industry baseline referenced in the literature (e.g., TreeDiff, LLM-code surveys).
- **Core claim:** Mark-and-sweep static analysis over exports is fast and reliable for TypeScript.
- **Technique:** Build dependency graph over export/import symbols; unreachable = dead.
- **Applicability to quantum-loop:** Add `lib/deadcode.sh` that runs knip or tsr in the verify phase; this is the simplest Iron-Law check to add.
- **Port effort:** Very low — 50-line wrapper.

---

## Cluster 6: Code Review Automation (Multi-Agent / Multi-Perspective)

### 6.1 From Industry Claims to Empirical Reality: Code Review Agents in PRs
- **Citation:** Chowdhury, Banik, Ferdous, Shamim. arXiv:2604.03196 (2026).
- **Core claim:** CRA-only PRs merge at 45.2% vs. 68.4% human-only (−23 pp); 60.2% of closed CRA-only PRs have signal-to-noise in the 0-30% range; 12/13 CRAs score <60% signal quality.
- **Technique:** Measures actionability via signal-to-noise (fraction of comments mapping to a real defect).
- **Applicability to quantum-loop:** Quality-reviewer agent should self-score its comments against a signal rubric (does each comment name a defect with evidence?), and the orchestrator should drop comments below a signal threshold. Warns against over-reliance on reviewer alone.
- **Port effort:** Low — rubric prompt + threshold filter.

### 6.2 Towards Practical Defect-Focused Automated Code Review (ICML 2025 Spotlight)
- **Citation:** arXiv:2505.17928 (2025). Deployed on C++ codebase with ~400M DAUs.
- **Core claim:** 2× improvement over vanilla LLM review, 10× over prior baselines, via (1) code slicing for context, (2) multi-role LLM for Key Bug Inclusion, (3) FAR-reduction filter, (4) human-interaction prompt design.
- **Technique:** Four-stage industrial pipeline; KBI-then-FAR two-pass design.
- **Applicability to quantum-loop:** Quality-reviewer should adopt a two-pass design: first a KBI agent (find bugs, accept high recall), then a FAR filter (remove noisy/non-actionable) before returning comments.
- **Port effort:** Medium — separate reviewer into two sub-agents.

### 6.3 MARS: Toward More Efficient Multi-Agent Collaboration for LLM Reasoning
- **Citation:** arXiv:2509.20502 (2025).
- **Core claim:** Author + independent reviewers + meta-reviewer matches Multi-Agent-Debate quality at ~50% token/latency cost.
- **Technique:** Reviewers operate independently (no cross-talk); meta-reviewer consolidates decisions, comments, confidence scores; author revises only if meta-reviewer rejects.
- **Applicability to quantum-loop:** Replace the current single quality-reviewer with (spec-reviewer, code-quality-reviewer, type-auditor, conflict-auditor) voting independently, then a meta-reviewer (orchestrator role) aggregating — pattern already matches `agents/` directory.
- **Port effort:** Low — stitching existing agents together.

### 6.4 RevAgent: Issue-Oriented Agent Framework for Code Review Comments
- **Citation:** arXiv:2511.00517 (2025).
- **Core claim:** Three-stage generation/discrimination/training with category-specific agents beats flat review.
- **Technique:** Category-specific agents (security, correctness, readability, perf) generate candidate comments; critic agent discriminates.
- **Applicability to quantum-loop:** Extend quality-reviewer into category-specific agents (matches existing bottleneck-analyzer, type-auditor, duplication-detector, conflict-auditor).
- **Port effort:** Low — compose existing agent zoo.

---

## Cluster 7: Intent Alignment / Spec Faithfulness in Long Pipelines

### 7.1 Spec-Driven Development: From Code to Contract in the Age of AI Coding Assistants
- **Citation:** arXiv:2602.00180 (Feb 2026).
- **Core claim:** Defines three rigor levels — spec-first, spec-anchored, spec-as-source — and compares tools (Kiro, Spec Kit, Tessl, BDD frameworks).
- **Technique:** Rigor taxonomy + concrete criteria for each level; spec-anchored requires regeneration on spec change.
- **Applicability to quantum-loop:** Quantum-loop is spec-first today. Moving toward spec-anchored would auto-regenerate task DAGs whenever `docs/plans/*-design.md` or PRDs change. This addresses intent drift directly.
- **Port effort:** Medium — add spec-hash tracking + invalidation.

### 7.2 Understanding Specification-Driven Code Generation with LLMs (CURRANTE)
- **Citation:** arXiv:2601.03878 (SANER 2026 Registered Report).
- **Core claim:** Human-in-the-loop spec → tests → function workflow reduces errors up to 50%; current pipelines are one-way (no spec ↔ code back-channel).
- **Technique:** Three-stage IDE extension; test step is mandatory between spec and code.
- **Applicability to quantum-loop:** ql-plan must emit tests before ql-execute; tests become spec-faithfulness oracles rather than post-hoc checks.
- **Port effort:** Low — already aligns with TDD-first testFirst flag in quantum.json.

### 7.3 Constitutional Spec-Driven Development
- **Citation:** arXiv:2602.02584 (2026).
- **Core claim:** Embedding non-negotiable constraints (e.g., security principles) in the spec reduces security defects 73% vs. unconstrained AI generation.
- **Technique:** Constitutional constraints at spec layer, enforced by construction in generated code.
- **Applicability to quantum-loop:** Add a `constitution` field to quantum.json (e.g., "no secrets in code," "no mutation," "all inputs validated"); check at spec-reviewer stage.
- **Port effort:** Low.

### 7.4 Agent Drift: Quantifying Behavioral Degradation
- **Citation:** Rath. arXiv:2601.04170 (Jan 2026).
- **Core claim:** Introduces semantic/coordination/behavioral drift taxonomy + Agent Stability Index (ASI) over 12 dimensions; mitigations: episodic memory consolidation, drift-aware routing, adaptive behavioral anchoring.
- **Technique:** ASI composite metric; anchoring periodically re-grounds agents to original intent.
- **Applicability to quantum-loop:** Every N stories, orchestrator should inject a re-grounding step (re-read PRD + quantum.json.success criteria) before selecting next story.
- **Port effort:** Low — orchestrator tick.

### 7.5 Technical Report: Evaluating Goal Drift in Language Model Agents
- **Citation:** Arike et al. arXiv:2505.02709 (May 2025, AIES).
- **Core claim:** Claude 3.5 Sonnet maintains goal adherence for 100K+ tokens, but all models drift under pressure; drift correlates with context length and pattern-matching susceptibility.
- **Technique:** Trading-simulation eval; measures tendency of agents to deviate under competing objectives.
- **Applicability to quantum-loop:** Long pipelines (10+ stories) are quantum-loop's failure mode. Limit per-story context to <50K tokens; re-seed orchestrator context between stories; use structured quantum.json as the goal anchor.
- **Port effort:** Low — enforce context caps in spawn-*.sh.

---

## Cluster 8: Anti-Rationalization / Verification Gates

### 8.1 Measuring Chain-of-Thought Faithfulness by Unlearning Reasoning Steps (FUR)
- **Citation:** Tutek et al. arXiv:2502.14829 (Feb 2025).
- **Core claim:** FUR unlearns specific reasoning steps and measures effect on final answer; often the verbalized CoT is NOT parametrically faithful.
- **Technique:** Targeted unlearning to assess whether a step actually drove the decision.
- **Applicability to quantum-loop:** Inform Iron-Law design — agent claims of "I tested X" must produce fresh artifacts, not re-verbalized reasoning. CLAUDE.md already emphasizes this; paper provides theoretical backing.
- **Port effort:** Low — belief-check via artifact-first gate.

### 8.2 Plan Verification for LLM-Based Embodied Task Completion Agents
- **Citation:** Hariharan et al. arXiv:2509.02761 (2025).
- **Core claim:** Iterative Judge-LLM critiques and Planner-LLM applies revisions; 90% recall, 100% precision, 96.5% convergence in ≤3 iterations over irrelevant/contradictory/missing steps.
- **Technique:** Two-role critique loop with bounded iterations.
- **Applicability to quantum-loop:** ql-plan should have a built-in Judge pass on the generated story DAG, catching irrelevant/missing/contradictory stories before execution.
- **Port effort:** Low — wire dag-validator agent post-plan.

### 8.3 SemGuard: Real-Time Semantic Evaluator for Correcting LLM Code
- **Citation:** arXiv:2509.24507 (2025).
- **Core claim:** Semantic errors (compile-but-wrong) = >60% of faults on DeepSeek-Coder-6.7B and QwenCoder-7B; SemGuard catches them at decode time without running tests (−19.86% semantic-error rate, +48.92% Pass@1 on LiveCodeBench with CodeLlama-7B).
- **Technique:** Lightweight line-level semantic classifier embedded in decode loop; triggers rollback and regeneration.
- **Applicability to quantum-loop:** Harder to retrofit onto Claude but same shape: after each file write, run a cheap classifier to flag line-level semantic anomalies (e.g., calling a function with wrong arity), block commit.
- **Port effort:** Medium-high — requires local classifier; alternative: static type-check between edits.

### 8.4 TraceCoder: Trace-Driven Multi-Agent Debugging (ICSE 2026)
- **Citation:** arXiv:2602.06875 (2026).
- **Core claim:** +34.43% Pass@1 over baselines via observe-analyze-repair loop with instrumentation + causal trace reasoning + historical-lesson learning + rollback.
- **Technique:** Three-agent split (Instrument, Analyze, Repair) with a lesson-memory and a monotonic rollback enforcer.
- **Applicability to quantum-loop:** A direct template for the verify + fix loop. Lessons memory maps to codebasePatterns in quantum.json. Rollback as strict improvement (never backslide) matches the Iron Law.
- **Port effort:** Medium — refactor verify phase into the three sub-agents.

---

## Cluster 9: Planning & Decomposition Quality for Agents

### 9.1 Plan-and-Act: Improving Planning of Agents for Long-Horizon Tasks (ICML 2025)
- **Citation:** arXiv:2503.09572 (2025).
- **Core claim:** Planner/Executor separation + synthetic plan-trajectory training achieves 57.58% WebArena-Lite, 81.36% WebVoyager. Adding any Planner jumps base 9.85% → 29.63%.
- **Technique:** Separation of concerns; Planner produces structured high-level plans; Executor translates to env actions.
- **Applicability to quantum-loop:** Validates the spec/plan/execute separation. Most valuable insight: Plan quality dominates — invest in ql-plan refinement rather than ql-execute.
- **Port effort:** Already aligned.

### 9.2 HiPlan: Hierarchical Planning for LLM Agents with Adaptive Global-Local Guidance
- **Citation:** arXiv:2508.19076 (2025).
- **Core claim:** Decompose complex tasks into milestone action guides + step-wise hints; milestone library from expert demos enables structured reuse.
- **Technique:** Two-level plan (milestones + hints); library learned from past expert trajectories.
- **Applicability to quantum-loop:** "codebasePatterns" in quantum.json = milestone library. Add a `milestones` field per story for mid-story anchors; hint library drives the next iteration.
- **Port effort:** Low.

### 9.3 GoalAct: Global Planning and Hierarchical Execution
- **Citation:** arXiv:2504.16563 (2025).
- **Core claim:** +12.22% avg success-rate via continuously-updated global planning + hierarchical skills (search/code/write).
- **Technique:** Global plan re-planned each iteration; task decomposed into high-level skills invoked hierarchically.
- **Applicability to quantum-loop:** Orchestrator should re-validate the story DAG after each merge (not just on init), enabling replanning when assumptions change.
- **Port effort:** Medium — dynamic DAG mutation.

---

## Cluster 10: Observation / Interpretability for Agent Runs

### 10.1 CodeTracer: Towards Traceable Agent States
- **Citation:** arXiv:2604.11641 (April 2026).
- **Core claim:** Parses heterogeneous agent run artifacts into hierarchical trace tree with persistent memory; localizes failure onset and downstream propagation; replaying diagnostics recovers failed runs under matched budgets.
- **Technique:** CodeTraceBench covers 4 frameworks × multiple code-task types, supervised at stage + step level.
- **Applicability to quantum-loop:** The `lib/monitor-*.sh` output is currently flat. Convert to a hierarchical trace tree (JSON) with failure-onset pointers; feed to orchestrator for targeted retry. Directly addresses "review gaps that miss cross-story semantic issues" since cross-story analysis needs structured traces.
- **Port effort:** Medium — structured log format + parser.

### 10.2 AgentRR: LLM Agents with Record & Replay
- **Citation:** Feng et al. arXiv:2505.17716 (May 2025).
- **Core claim:** Record traces → summarize to multi-level "experience" → replay on similar tasks; includes check-function mechanism for completeness/safety during replay.
- **Technique:** Record-Summarize-Replay three-step with check-functions.
- **Applicability to quantum-loop:** Successful stories become replay templates for similar stories; on orchestrator re-entry after a failure, replay the verified prefix instead of re-planning from scratch.
- **Port effort:** Medium — commit-replay infrastructure.

### 10.3 AgentTrace: Structured Logging for Agent Observability
- **Citation:** arXiv:2602.10133 (2026).
- **Core claim:** Low-overhead runtime instrumentation capturing operational/cognitive/contextual surfaces for debug/benchmark/security/monitoring.
- **Technique:** Three-surface structured logs (actions, reasoning, context).
- **Applicability to quantum-loop:** Extend monitor-*.sh to log the three surfaces separately so cross-story semantic reviewers can correlate across worktrees.
- **Port effort:** Low-medium.

---

# Top 15 Techniques Ranked by Impact × Portability

Ranking heuristic: directness to quantum-loop gaps (wiring/merge/dup/dead/review-gaps/drift) × integration cost inverted.

### Tier S — Do Immediately

1. **SSAT + Skeleton-First Phase (Zhao et al. 2511.03404)** — Add a "skeleton" story type that emits interfaces/types/empty exports first. Downstream stories fill bodies against a stable SSAT. **Directly fixes wiring issues + duplicate type drift.**
 - Recipe: New story-type `skeleton` in quantum.json; runner writes interfaces + empty exports; orchestrator blocks body-fill stories until skeleton story passes.

2. **Conflict Grading Pre-Merge (ConGra 2409.14121)** — Grade conflicts by AST-operation complexity before attempting auto-resolve.
 - Recipe: In `lib/merge-semantic.sh`, run a 50-line grader that returns `{category, complexity_1_to_5}`; routes to git-merge (1-2), LLM-merge (3-4), human-escalate (5).

3. **Structured Quality-Reviewer: KBI-then-FAR (2505.17928)** — Split reviewer into high-recall Key Bug Inclusion then FAR filter.
 - Recipe: `agents/quality-reviewer-*.md` becomes two agents; orchestrator chains them. Measures signal-to-noise per PR.

4. **Actionability Signal-to-Noise Gate (2604.03196)** — Require every review comment to cite evidence; drop comments below threshold.
 - Recipe: In `ql-review`, each comment must have `{file, line, evidence_type, severity}`; orchestrator rejects comments without evidence.

5. **Trajectory Length Heuristic (2511.00197 + TRAJEVAL 2603.24631)** — Failed stories run long; kill and retry early.
 - Recipe: In `lib/resilience.sh`, track tool-call count per phase (search/read/edit); kill when >P95 of passed stories.

### Tier A — High Value, Moderate Effort

6. **DAG Dynamic Refinement (Flash-Searcher 2509.25301)** — Allow mid-run DAG updates when discoveries change dependencies.
 - Recipe: Orchestrator listens for `<quantum>DAG_UPDATE</quantum>` from runners; dag-validator re-checks before applying.

7. **Semantic Intent Graph + Drift Monitor (SCF 2604.16339)** — Per-story Semantic Intent Graph; check incoming merges against peer intents.
 - Recipe: `lib/intent-graph.sh` extracts `{objects, verbs, constraints}` from acceptance criteria; conflict-auditor agent compares against merged peers.

8. **MARS Parallel Review + Meta-Reviewer (2509.20502)** — Run spec-reviewer, code-quality, type-auditor, conflict-auditor independently; orchestrator aggregates.
 - Recipe: `agents/` already has the pieces; wire them as parallel independent calls in `ql-review` with a meta-step.

9. **Two-Stage Semantic Clone Detection (HyClone 2508.01357)** — LLM screen → execution validation for duplicate consolidation.
 - Recipe: `agents/duplication-detector.md` already exists; upgrade to two-stage: filter by embedding similarity, then run LLM-generated equivalence tests on both snippets.

10. **TraceCoder Observe-Analyze-Repair (2602.06875)** — Three-role verify loop with lesson memory + rollback.
 - Recipe: Refactor ql-verify into (Instrument, Analyze, Repair) sub-agents; `codebasePatterns` = lessons memory; enforce monotonic rollback on each retry.

### Tier B — High Value, Bigger Lift

11. **Spec-Anchored Regeneration (2602.00180)** — When PRD/plan changes, regenerate affected tasks.
 - Recipe: Hash PRD + design docs; orchestrator invalidates downstream stories on hash change.

12. **Plan-Judge Pass (2509.02761)** — Iterative Judge-LLM critiques the story DAG pre-execution (irrelevant/contradictory/missing).
 - Recipe: `agents/dag-validator.md` already exists; add 3-iteration bound with failure categories.

13. **Re-Grounding Every N Stories (2601.04170 + 2505.02709)** — Prevent goal drift by periodic re-grounding from PRD.
 - Recipe: Orchestrator ticks; every N=5 stories, inject PRD re-read + ASI check before next story selection.

14. **Constitutional Constraints (2602.02584)** — Non-negotiable rules at spec layer.
 - Recipe: `quantum.json.constitution` array; spec-reviewer refuses specs that violate constraints; e.g., immutability, input validation, no secrets.

15. **Dead-Code Post-Generation Pass (ts-prune/knip + DePA 2502.20246)** — Cheap orphan detection in ql-verify.
 - Recipe: `lib/deadcode.sh` wraps knip/tsr; DePA-style z-score pass on new lines; fail verify on orphan exports OR high-anomaly lines in changed files.

---

# Executive Summary (10 Bullets)

1. **Skeleton-first multi-agent code generation (SSAT, 2511.03404)** is the single highest-leverage fix for quantum-loop's wiring failures; add a skeleton story-type that emits stable interfaces before body-fill stories run.
2. **Conflict grading before auto-resolve (ConGra, 2409.14121)** lets quantum-loop route easy conflicts to git-merge and only invoke LLM-merge on complex cases, cutting cost and false-resolve risk.
3. **Code Review Agents (CRAs) cannot replace humans — 45% vs. 68% merge rate (Chowdhury et al., 2604.03196)**; quantum-loop's review-gate must enforce evidence-backed comments and drop low-signal output to stay useful.
4. **Two-pass KBI-then-FAR reviewer (ICML 2025 spotlight, 2505.17928)** delivers 2× over vanilla LLM review; quantum-loop should split quality-reviewer into recall-maxed bug-finder + precision-maxed filter.
5. **Semantic Intent Divergence is the formally-named root cause of multi-agent failures (SCF, 2604.16339)**; quantum-loop needs a Semantic Intent Graph per story and a Drift Monitor comparing intents at merge time.
6. **Agent drift is real across long pipelines (2601.04170 + 2505.02709)**; mitigate with periodic re-grounding, context caps <50K tokens, and quantum.json as a persistent anchor.
7. **Flash-Searcher (2509.25301) and GoalAct (2504.16563)** show dynamic DAG refinement yields +accuracy and −steps; quantum-loop should allow mid-run DAG mutation via an orchestrator-gated signal.
8. **Trajectory signatures (2511.00197 + TRAJEVAL 2603.24631)** can detect failing stories 20-30% earlier — track step count, search/read/edit ratios, and kill outliers before retry budget is wasted.
9. **HyClone (2508.01357)** and canonicalization findings (2511.01176) give a concrete two-stage pattern (LLM-screen + execution-validate) for quantum-loop's duplication-detector agent with 10× recall gains on semantic clones.
10. **TraceCoder (ICSE 2026, 2602.06875)** is the closest template for quantum-loop's verify phase: Observe-Analyze-Repair with lesson memory and strict rollback — matches the Iron-Law and fits existing codebasePatterns field.

---

## Sources

- [Agentless — arXiv:2407.01489](https://arxiv.org/abs/2407.01489)
- [Live-SWE-agent — arXiv:2511.13646](https://arxiv.org/abs/2511.13646)
- [Understanding Code Agent Behaviour — arXiv:2511.00197](https://arxiv.org/abs/2511.00197)
- [TRAJEVAL — arXiv:2603.24631](https://arxiv.org/abs/2603.24631)
- [Flash-Searcher — arXiv:2509.25301](https://arxiv.org/abs/2509.25301)
- [Prompt2DAG — arXiv:2509.13487](https://arxiv.org/abs/2509.13487)
- [ProjectGen / SSAT — arXiv:2511.03404](https://arxiv.org/abs/2511.03404)
- [KGACG — arXiv:2510.19868](https://arxiv.org/abs/2510.19868)
- [ConGra — arXiv:2409.14121](https://arxiv.org/abs/2409.14121)
- [Semantic Consensus Framework — arXiv:2604.16339](https://arxiv.org/abs/2604.16339)
- [SAGA / Rethinking Verification — arXiv:2507.06920](https://arxiv.org/abs/2507.06920)
- [HyClone — arXiv:2508.01357](https://arxiv.org/abs/2508.01357)
- [LLM Code Clone Empirical — arXiv:2511.01176](https://arxiv.org/abs/2511.01176)
- [Code Refactoring LLM — arXiv:2511.21788](https://arxiv.org/abs/2511.21788)
- [DePA Dead Code — arXiv:2502.20246](https://arxiv.org/abs/2502.20246)
- [Code Review Agents Empirical — arXiv:2604.03196](https://arxiv.org/abs/2604.03196)
- [Defect-Focused Code Review — arXiv:2505.17928](https://arxiv.org/abs/2505.17928)
- [MARS — arXiv:2509.20502](https://arxiv.org/abs/2509.20502)
- [RevAgent — arXiv:2511.00517](https://arxiv.org/abs/2511.00517)
- [Spec-Driven Development — arXiv:2602.00180](https://arxiv.org/abs/2602.00180)
- [CURRANTE SDD — arXiv:2601.03878](https://arxiv.org/abs/2601.03878)
- [Constitutional SDD — arXiv:2602.02584](https://arxiv.org/abs/2602.02584)
- [Agent Drift — arXiv:2601.04170](https://arxiv.org/abs/2601.04170)
- [Goal Drift Eval — arXiv:2505.02709](https://arxiv.org/abs/2505.02709)
- [CoT Faithfulness FUR — arXiv:2502.14829](https://arxiv.org/abs/2502.14829)
- [Plan Verification — arXiv:2509.02761](https://arxiv.org/abs/2509.02761)
- [SemGuard — arXiv:2509.24507](https://arxiv.org/abs/2509.24507)
- [TraceCoder — arXiv:2602.06875](https://arxiv.org/abs/2602.06875)
- [Plan-and-Act — arXiv:2503.09572](https://arxiv.org/abs/2503.09572)
- [HiPlan — arXiv:2508.19076](https://arxiv.org/abs/2508.19076)
- [GoalAct — arXiv:2504.16563](https://arxiv.org/abs/2504.16563)
- [CodeTracer — arXiv:2604.11641](https://arxiv.org/abs/2604.11641)
- [AgentRR — arXiv:2505.17716](https://arxiv.org/abs/2505.17716)
- [AgentTrace — arXiv:2602.10133](https://arxiv.org/abs/2602.10133)
- [AutoCodeRover — arXiv:2404.05427](https://arxiv.org/abs/2404.05427)
