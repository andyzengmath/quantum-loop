# Literature Delta: 2026-04-21 -> 2026-04-26

**Window:** 2026-04-01 to 2026-05-15 (April 2026 / `2604.*` arXiv submissions).
**Baseline:** `idea-stage/LITERATURE_SURVEY.md` (35 papers; cutoff 2026-04-21).
**Goal:** Surface only NEW work mapped to v0.5.1 gaps — P2.9 cross-provider critic,
P2.10 tournament/re-benchmark, P4 ecosystem integration, dogfood operational issues.

---

## Executive Summary (5 bullets)

1. **The April-2026 cohort moves from "build the agent" to "evaluate / govern the agent."**
   Three reviewer benchmarks (CR-Bench 2603.11078, c-CRAB 2603.23448, CRA empirical
   2604.03196 — the last is in the prior survey) and two long-horizon failure benchmarks
   (HORIZON 2604.11978, SLUMP 2603.17104). Review noise and cross-step intent drift are
   the binding constraints, not raw generation skill.
2. **A new sub-genre — "tournament agent search" — is now publishable.** AgentGA
   (2604.14655) introduces deterministic 1:1 elite tournaments over "agent-seed space"
   with 1,135 validated parent-child runs. Combined with `oh-my-claudecode:self-improve`,
   this directly fills quantum-loop's P2.10 gap.
3. **Anthropic shipped a public three-agent harness blueprint** (engineering blog,
   2026-03-24): Planner / Generator / Evaluator with structured Sprint-Contract handoffs
   and (now obsolete in Opus 4.6) explicit context reset. Closest production analogue to
   quantum-loop's six-skill pipeline.
4. **Cross-model verifier ensembles became table-stakes.** AgentV-RL (2604.16004) uses
   forward+backward verifier agents; AgentForge (2604.13120) requires sandbox execution
   before propagation (40 % SWE-Bench Lite); AdverMCTS (2604.10449) adds an Attacker agent
   to break pseudo-correctness. All three are templates for P2.9.
5. **SWE-bench: no new research-lab top-N in this window.** Live-SWE-agent (2511.13646)
   remains the public Verified leader at 79.2 %; vendor-leaderboard top is 93.9 % Verified
   vs only 45.9 % Pro for the same model — the Verified-vs-Pro gap doubled this month and
   contamination concerns sharpened (2512.10218, 2506.12286, 2506.17208).

---

## Cluster D1 — Multi-agent SWE harnesses & scaffolds (NEW)

**D1.1 Inside the Scaffold (Rombaut, 2604.03515, v2 2026-04-10).** Source-code taxonomy
across 13 OSS coding agents; 5 reusable loop primitives (ReAct, generate-test-repair,
plan-execute, multi-attempt retry, tree search); 11/13 compose multiple primitives.
Validates quantum-loop's layered design; cite from README. **Effort: S.**

**D1.2 Semi-Executable Stack (Feldt et al., 2604.15468, 2026-04-16).** Six-layer
reference model + "preserve-vs-purify" heuristic. Vocabulary, not algorithm. **Effort: S.**

**D1.3 Rethinking SE for Agentic AI (Alenezi, 2604.10599, 2026-04-12).** Engineer roles
shift to orchestration / verification / human-AI collaboration. Theoretical backing for
quantum-loop's `--audit` flag and Iron-Law gate. **Effort: S.**

**D1.4 AgentForge (Kumar, Ali et al., 2604.13120, 2026-04-13).** Five-role pipeline
(Planner, Coder, Tester, Debugger, Critic) with mandatory Docker sandbox before
propagation. **40.0 % on SWE-Bench Lite.** Insight: promote test-must-pass from
*per-story* to *per-task*. **Effort: M.**

**D1.5 Anthropic Harness Design (engineering blog, 2026-03-24).** Planner -> Generator ->
Evaluator with Sprint-Contract handshake and Playwright-based functional eval. Two
imports for quantum-loop: (a) Sprint-Contract JSON between ql-plan and ql-execute, (b)
functional eval as a third independent signal alongside spec/quality reviewers.
**Effort: M.**

---

## Cluster D2 — Tournament / evolutionary agents (NEW; fills P2.10)

**D2.1 AgentGA (Tan, Chin, Zhang, 2604.14655, 2026-04-16).** Deterministic 1:1 elite
tournaments over agent-seed (prompt + parent archive); modified-Hedge online operator
allocation; **74.52 % vs 54.15 % AIDE on Weco-Kaggle Lite**. Critical insight: tournament
must be 1:1 vs the same lineage's elite — random pairings destroy diversity. Direct fit
for P2.10. **Effort: M.**

**D2.2 MARS² (Li, Wang et al., 2604.14564, 2026-04-16).** Heterogeneous agents over a
learnable tree-structured search space; path-level group advantage; tree-consistent
reward shaping. Path-level (full-trajectory) reward is the right shape for a future
quantum-loop story-scoring function. **Effort: L.**

**D2.3 SelfEvolve (Fahim, Adebayo, Ferrari, 2604.16314, revised April).** Runtime
self-extension: dispatcher / test-gen / code-synth / sandboxed exec / context memory.
**92.7 %** on 11 self-extension tasks; **+62 %** over AutoGen/MetaGPT/AgentCoder. Maps to
a quantum-loop story-type "extend-lib" with sandboxed test gating. **Effort: L.**

---

## Cluster D3 — Reviewer signal-to-noise / cross-provider critic (fills P2.9)

**D3.1 CR-Bench (Pereira et al., 2603.11078, 2026-03-10).** First fine-grained code-review
agent benchmark; documents the explicit issue-resolution-vs-spurious-finding trade-off.
Use as calibration target for quantum-loop's quality-reviewer. **Effort: S.**

**D3.2 c-CRAB Code Review Agent Benchmark (Zhang, Pan et al., 2603.23448, v3 2026-04-07).**
Tests Devin / Claude Code / Codex / PR-agent. **All four combined solve only ~40 %**;
agent reviewers and humans focus on systematically different aspects. Direct evidence
that a *cross-provider critic* (different models cover different surfaces) raises recall.
**Effort: S.**

**D3.3 AgentV-RL (Zhang, Fu et al., 2604.16004, 2026-04-17).** Forward agent traces
premise -> conclusion; backward agent verifies conclusion against premises. **+25.2 %
over SoTA ORMs at 4B.** A bidirectional reviewer pattern on top of KBI-then-FAR. quantum-
loop's spec-reviewer is forward-only; adding a backward pass (code -> implied spec)
catches scope creep. **Effort: M.**

**D3.4 AdverMCTS (Li, Liu et al., 2604.10449, 2026-04-12).** Solver vs Attacker MCTS
minimax; Attacker evolves corner cases. Pairs with HyClone — Attacker as separate critic
generating adversarial tests. Directly addresses dogfood-surfaced Bash heredoc/CRLF bug
class. **Effort: M.**

**D3.5 SolidCoder (Lee, Huang, 2604.19825, 2026-04-20).** "Don't imagine — execute":
forces edge-case enumeration during planning; replaces imagined traces with sandboxed
runs; property-based oracles. **95.7 % HumanEval, 77.0 % CodeContests** (GPT-4o). Adopt
as TDD-first prompt template: each test must declare its property + one corner case
before implementation. **Effort: S.**

**D3.6 Verify Before You Fix (Gajjar, 2604.10800, 2026-04-12).** Universal AST + GraphSAGE
+Qwen2.5-Coder fusion; mandates execution-grounded *exploitability* check before fix.
**12.27 % failure rate, 69.74 % E2E resolution.** Same shape as Iron Law. **Effort: S.**

---

## Cluster D4 — Long-horizon faithfulness / drift (NEW evidence)

**D4.1 HORIZON / Long-Horizon Task Mirage (Wang et al., 2604.11978, 2026-04-13).** 3,100+
trajectories; trajectory-grounded LLM-as-judge for failure attribution (κ=0.84). Use as
external smoke test for quantum-loop's `lib/trajectory.sh` heuristic. **Effort: M.**

**D4.2 SLUMP / Faithfulness Loss (2603.17104).** Defines faithfulness Loss Under eMergent
sPecification = drop in faithfulness when spec is disclosed progressively vs once.
quantum-loop's PRD-then-execute IS the good baseline. Cite as design justification.
**Effort: S.**

**D4.3 SAVeR / Verify Before You Commit (Yuan et al., 2604.08401, 2026-04-09).**
Diverse-belief generation -> adversarial audit -> constraint-guided minimal repair,
*before* commit. Direct template for a pre-commit belief-audit gate (regenerate intent
from diff; reject if it diverges from acceptance criteria). **Effort: M.**

**D4.4 Beyond Resolution Rates (Mehtiyev, Assunção, 2604.02547, 2026-04-02).** 9,374
trajectories / 19 agents / 8 frameworks / 14 LLMs. **LLM choice dominates framework
choice** once the LLM is strong; agents that gather context before editing succeed more.
12 "easy" tasks were never solved due to weak architectural reasoning. Critical
positioning: invest in DAG / merge / conflict grader / trajectory monitor — not in a
custom prompt-stack the next model will obsolete. **Effort: S (positioning).**

**D4.5 Beyond the 'Diff' / Agentic Entropy (Casserini et al., 2604.16323, v2 2026-04-21).**
Coins "agentic entropy" = systemic drift diff-based methods miss; calls for *intent-level
telemetry*. quantum-loop's `lib/intent-graph.sh` already is intent-level telemetry — cite
as terminology. **Effort: S.**

---

## Cluster D5 — Operability, replay, supply chain (dogfood-relevant)

**D5.1 SWE-chat (Baumann, Padmakumar et al., 2604.20779, 2026-04-22).** 6k sessions / 63k
prompts / 355k tool calls. Bimodal usage (41 % "vibe coding", 23 % humans-only). **Only
44 % of agent-produced code survives into commits**; agent code has *more* security
vulnerabilities than human code. The 56 % attrition is what an Iron-Law harness must
drive down. **Effort: S.**

**D5.2 Stateless Decision Memory / DPM (Srinivasan, 2604.20158, 2026-04-22).** Append-only
event log + task-conditioned projection at decision time; **7-15× faster** under tight
budgets, **+0.52 factual precision** at 20× compression. quantum.json is already
append-only — DPM validates the design and adds task-conditioned projection as the next
step. **Effort: S-M.**

**D5.3 On the Reliability of Computer Use Agents (Gonzalez-Pumariega et al., 2604.17849,
2026-04-20).** Three failure axes: execution stochasticity, spec ambiguity, behavior
variability. Recommends repeated evaluation + interactive clarification + stable
strategies. Pairs with AgentGA (D2.1). **Effort: M.**

**D5.4 HiveMind (Agyemang et al., 2604.17111, 2026-04-18).** Transparent HTTP proxy with
admission control, AIMD backpressure, circuit-breaking, token budgets, priority queues.
**Reduces failure 72-100 % -> 0-18 %, <3 ms overhead.** Drop-in solution for parallel-
worktree rate-limit failures. Could ship as `bin/quantum-proxy.sh`. **Effort: M.**

**D5.5 Skilldex (Saha, Hemanth, 2604.16911, 2026-04-18).** Compiler-style skill validator
+ skillset abstraction + 3-tier hierarchical scope. Direct fit for quantum-loop's existing
ql-* skill family. P4 ecosystem: publish quantum-loop as a Skilldex package. **Effort: S.**

**D5.6 Cerisier (2604.13638, 2026-04-21).** Iris/Coq-mechanised program logic for
attestation. Foundation for a *future* SLSA-style evidence bundle for quantum-loop runs.
**Effort: L.**

**D5.7 RAGShield (2604.00387, 2026-04-01).** SLSA + C2PA-style attestation across 4 levels.
Adopting Level-1 (PRD hash-pinning) is trivial — gives a "this story implemented against
PRD@<sha>" provenance line in quantum.json. **Effort: S.**

---

## SWE-bench leaderboard delta (2026-04-21 -> 2026-04-26)

No new research-lab leaderboard claim in this 5-day window. Public state:

| Benchmark | Top public | Score | Notes |
|---|---|---|---|
| Verified (vendor) | Claude Mythos Preview | 93.9 % | Contamination concern (2512.10218, 2506.12286) |
| Verified (research) | Live-SWE-agent | 79.2 % | arXiv:2511.13646 — still SoTA |
| Pro | Claude Opus 4.5 | 45.9 % | The "real" frontier |
| Pro | Claude Sonnet 4.5 | 43.6 % | |
| Pro | Gemini 3 Pro | 43.3 % | |
| Live | All known agents | <19.25 % | per 2506.17208 |

**New meta-benchmarks landed in the window:** HORIZON (2604.11978) for long-horizon
failure attribution; CR-Bench / c-CRAB / CRA empirical — three independent reviewer
benchmarks within 30 days. **Implication:** the "+1 pp Verified" race is contaminated;
Pro and HORIZON-class benchmarks reward the orchestration layer where quantum-loop
lives. Position for Pro, not Verified.

---

## Industry / lab signals (April-May 2026)

- **Anthropic — Three-Agent Harness** (engineering, 2026-03-24). See D1.5.
- **Anthropic — Claude Managed Agents** (April 2026). Hosted-agent abstraction is moving
  up-stack; quantum-loop has 6-12 months before the harness layer is commoditised. Lock
  in evaluation/governance differentiation now.
- **Anthropic — Agent-Based Code Review for Claude Code** (InfoQ 2026-04). Reinforces
  D3.x: review is the next battleground.
- **No public OpenAI / Cognition / Google DeepMind agent-harness preprint** in this window.
  The Cognition trail goes quiet after Devin 2.x early-2026 announcements.

---

## Cross-cluster synthesis (4 themes)

1. **The reviewer is the bottleneck, not the coder.** (D3.x). Maps to **P2.9 cross-
   provider critic.** Action: split quality-reviewer into KBI/FAR + bidirectional
   (forward+backward) verifier + Attacker agent. Estimated +20 pp signal-to-noise.
2. **Tournaments / lineages will become the dominant scaling axis.** (D2.x). Maps to
   **P2.10 tournament/re-benchmark.** Action: archive + 1:1 elite tournament; pair with
   `oh-my-claudecode:self-improve`.
3. **Long-horizon drift is now formally measurable.** (D4.x). Maps to existing
   `lib/intent-graph.sh` + `lib/trajectory.sh`. Action: ship a quantum-loop <-> HORIZON
   evaluator script as CI smoke test.
4. **Operational reliability — rate limits, replay, provenance — is first-class research
   now.** (D5.x). Maps to **P4 ecosystem** + dogfood. Action: ship `bin/quantum-proxy.sh`
   (HiveMind), hash-pin PRDs (RAGShield-Level 1), publish as Skilldex package.

---

## Top-10 ranked recipes from this delta

Ranking: directness × portability ÷ effort. Effort: S = <1 story, M = 1-3 stories,
L = 4+ stories.

| # | Recipe | Source | Gap | Effort |
|---|---|---|---|---|
| 1 | **1:1 elite tournament over agent-seed archives.** Per-story `archive/` dir; failed-story re-runs use parent archive in prompt; child competes 1:1 vs same-lineage elite. | AgentGA 2604.14655 | P2.10 | M |
| 2 | **Bidirectional reviewer.** New `agents/inverse-spec-reviewer.md` derives implied-spec from code and diffs against acceptance criteria. Wired in parallel with existing spec-reviewer. | AgentV-RL 2604.16004 | P2.9 | S-M |
| 3 | **Adversarial test generator ("Attacker") agent.** New story-type `stress-test`: 3-5 corner-case tests for any merged story; failures route back to author. Targets dogfood Bash heredoc/CRLF class bugs. | AdverMCTS 2604.10449 | dogfood | M |
| 4 | **HiveMind-style provider proxy.** `bin/quantum-proxy.sh`: admission control + AIMD + per-runner token budget. Reduces parallel-worktree failure rate. | HiveMind 2604.17111 | dogfood scaling | M |
| 5 | **Per-task sandboxed verification.** Promote test runs from after-story to after-task; block file-write commit if sandbox fails. | AgentForge 2604.13120, SolidCoder 2604.19825 | Iron-Law | M |
| 6 | **PRD hash-pinning (RAGShield Level-1).** Each story gets `prdSha`; orchestrator invalidates downstream stories on hash change. | RAGShield 2604.00387 | spec-anchored regen | S |
| 7 | **Pre-commit belief-audit gate.** Regenerate intent from diff before commit; reject if diverges from quantum.json acceptance criteria. | SAVeR 2604.08401 | drift mitigation | M |
| 8 | **Sprint-Contract handoff artefact.** Per-story JSON written by ql-plan and consumed by ql-execute *and* ql-review; mirrors Anthropic Generator <-> Evaluator contract. | Anthropic 2026-03-24 | spec faithfulness | S-M |
| 9 | **Repeated-evaluation voting for high-stakes stories.** `criticality: high` stories re-run 3× via parallel runner; majority-vote on diff equivalence; require unanimous review-pass. | CUA Reliability 2604.17849 | dogfood reliability | M |
| 10 | **Publish quantum-loop as Skilldex package + run reviewer against c-CRAB.** Fixes long-tail integration with Anthropic skills/MCP. | Skilldex 2604.16911, c-CRAB 2603.23448 | P4 ecosystem | S |

---

## Sources (confirmed arXiv IDs)

- [Inside the Scaffold — 2604.03515](https://arxiv.org/abs/2604.03515)
- [Semi-Executable Stack — 2604.15468](https://arxiv.org/abs/2604.15468)
- [Rethinking SE for Agentic AI — 2604.10599](https://arxiv.org/abs/2604.10599)
- [AgentForge — 2604.13120](https://arxiv.org/abs/2604.13120)
- [Anthropic Harness Design (blog 2026-03-24)](https://www.anthropic.com/engineering/harness-design-long-running-apps)
- [AgentGA — 2604.14655](https://arxiv.org/abs/2604.14655)
- [MARS² — 2604.14564](https://arxiv.org/abs/2604.14564)
- [SelfEvolve — 2604.16314](https://arxiv.org/abs/2604.16314)
- [CR-Bench — 2603.11078](https://arxiv.org/abs/2603.11078)
- [c-CRAB — 2603.23448](https://arxiv.org/abs/2603.23448)
- [AgentV-RL — 2604.16004](https://arxiv.org/abs/2604.16004)
- [AdverMCTS — 2604.10449](https://arxiv.org/abs/2604.10449)
- [SolidCoder — 2604.19825](https://arxiv.org/abs/2604.19825)
- [Verify Before You Fix — 2604.10800](https://arxiv.org/abs/2604.10800)
- [HORIZON / Long-Horizon Task Mirage — 2604.11978](https://arxiv.org/abs/2604.11978)
- [SLUMP — 2603.17104](https://arxiv.org/abs/2603.17104)
- [SAVeR — 2604.08401](https://arxiv.org/abs/2604.08401)
- [Beyond Resolution Rates — 2604.02547](https://arxiv.org/abs/2604.02547)
- [Agentic Entropy — 2604.16323](https://arxiv.org/abs/2604.16323)
- [SWE-chat — 2604.20779](https://arxiv.org/abs/2604.20779)
- [DPM / Stateless Decision Memory — 2604.20158](https://arxiv.org/abs/2604.20158)
- [Reliability of CUAs — 2604.17849](https://arxiv.org/abs/2604.17849)
- [HiveMind — 2604.17111](https://arxiv.org/abs/2604.17111)
- [Skilldex — 2604.16911](https://arxiv.org/abs/2604.16911)
- [Cerisier — 2604.13638](https://arxiv.org/abs/2604.13638)
- [RAGShield — 2604.00387](https://arxiv.org/abs/2604.00387)
- [SWE-Bench Pro leaderboard (Morph)](https://www.morphllm.com/swe-bench-pro)
- [Live-SWE-agent — 2511.13646](https://arxiv.org/abs/2511.13646)

**Searched but no confirmed source:** an OpenAI/Cognition April-2026 agent-harness arxiv
paper; an explicit "use 3 different providers and vote" cross-provider-critic paper —
closest are AgentV-RL (D3.3) and c-CRAB (D3.2).
