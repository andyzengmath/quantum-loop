# Competitor Survey: Coding-Agent Harnesses & Plugins

**Date:** 2026-04-21
**Author:** quantum-loop research agent
**Purpose:** Identify features from external coding-agent harnesses/plugins that quantum-loop should adopt.

**Quantum-loop positioning:** BUILD layer of an AI-native subsidiary stack.
Pipeline: brainstorm → spec → plan (DAG) → parallel-worktree execute → two-stage review gate.

**Known gaps driving this survey:**
- Cross-story wiring issues in parallel execution
- Merge conflicts
- Duplicate code / dead code
- Review gates that miss cross-story semantic issues
- Intent drift across stages

---

## 1. Superpowers (obra/superpowers, 52.4k stars)

**Sources:**
- Local: `C:\Users\andyzeng\.claude\plugins\cache\superpowers-marketplace\superpowers\4.0.3\`
- GitHub: https://github.com/obra/superpowers
- Latest release notes (v4.1.0, v4.1.1, v4.2.0): https://github.com/obra/superpowers/blob/main/RELEASE-NOTES.md

### Overview
Agentic skills framework that enforces a structured dev workflow: brainstorm → worktree → write-plan → subagent-driven-development → tests → code review → finish-branch. Skills fire automatically based on triggers; Claude must invoke via Skill tool, not just read the file.

### Core mechanisms
- **Skill tool enforcement** — `using-superpowers` skill uses MANDATORY FIRST-RESPONSE PROTOCOL with rationalization-blocking language ("If even 1% chance a skill applies, you MUST read it"). v4.0.3 added: explicit skill-request tests for "by-name" invocations (e.g., "subagent-driven-development, please").
- **DOT flowcharts as executable specifications** — rewrote key skills with GraphViz flowcharts as the authoritative process definition; prose is supporting content. `writing-skills` documents "The Description Trap" (short descriptions override detailed flowcharts).
- **Two-stage review in subagent-driven-development (v4.0.0)** — separate spec-compliance reviewer (reads actual code, does NOT trust implementer) THEN code-quality reviewer only after spec passes. Review is a LOOP until approved. Spec reviewer explicitly checks for OVER-building as well as under-building.
- **Self-review checklist** — implementer self-reviews before handoff (Completeness / Quality / Discipline / Testing checklist).
- **Testing anti-patterns reference** (v4.0.0) — bundles: testing mock behavior instead of real behavior, adding test-only methods, incomplete mocks, mocking without understanding dependencies.
- **Systematic-debugging with bundled techniques** — root-cause-tracing, defense-in-depth, condition-based-waiting, and `find-polluter.sh` bisection script.
- **Verification-before-completion iron law** — "NO COMPLETION CLAIMS WITHOUT FRESH VERIFICATION EVIDENCE" + rationalization prevention table ("Should work now" → RUN the verification).
- **Worktree flow** — `using-git-worktrees` auto-detects project conventions (`.worktrees` vs `worktrees`), verifies `.gitignore` status, runs project setup (`npm install`/`cargo build`/`pip install`/`go mod download`), verifies clean baseline via tests before handing off.
- **Finishing-a-development-branch** — presents exactly 4 options (merge locally / push+PR / keep / discard); requires typed `discard` confirmation for destructive action.

### What's NEW in 4.x (vs spec covered in v4.0.3 local)
- **v4.2.0** (2026-02-05) — "Worktree isolation now required before implementation" across both subagent-driven-development AND executing-plans workflows. Main branch protection softened to allow explicit user consent rather than hard prohibition. Codex tool mapping moved to progressive-disclosure reference documentation.
- **v4.1.x** (2026-01-23) — OpenCode switched to native skills system. "Removed 'execute 3 tasks then stop for review' pattern. Plans now execute continuously, stopping only for blockers." Deleted unused `lib/skills-core.js`. Deprecation notices added to slash commands.
- **Explicit subagent completion states** — DONE, DONE_WITH_CONCERNS, BLOCKED, NEEDS_CONTEXT — enables smarter orchestration.

### Features quantum-loop lacks
- Two-stage review with EXPLICIT over-building detection in spec reviewer (ql has two-stage but doesn't force the "did they build extra things?" check)
- Implementer self-review checklist BEFORE handoff
- Skill-triggered, anti-rationalization language patterns ("Skip any step = lying, not verifying")
- Testing anti-patterns reference bundled with TDD
- `find-polluter.sh` bisection script for flaky tests
- DOT flowcharts as canonical process spec
- Condition-based-waiting patterns instead of arbitrary timeouts
- Four-option finishing flow with destructive-action typed confirmation

---

## 2. Ralph (snarktank/ralph, and also the OMC implementation)

**Sources:**
- Local: `C:\Users\andyzeng\.claude\plugins\cache\ralph-marketplace\ralph-skills\1.0.0\`
- OMC ralph skill: `C:\Users\andyzeng\.claude\plugins\cache\omc\oh-my-claudecode\4.11.3\skills\ralph\SKILL.md`

### Overview
PRD-driven persistence loop. Fresh agent per iteration with no memory; all state in `prd.json` + `progress.txt`. Reviewer verification against specific acceptance criteria before completion.

### Core mechanisms

**Base Ralph (snarktank, amp-focused):**
- `prd.json` format with `userStories[]` (id, title, description, acceptanceCriteria[], priority, passes, notes) — essentially identical structure to quantum-loop's existing `quantum.json`
- **Story sizing rule:** "Each story must be completable in ONE iteration (one context window)" + "If you cannot describe the change in 2-3 sentences, it is too big"
- **Acceptance criteria must be verifiable** — explicit good/bad examples: "Add `status` column to tasks table" vs "Works correctly"
- **Mandatory "Typecheck passes"** as final criterion for every story; "Tests pass" when applicable; "Verify in browser using dev-browser skill" for UI stories
- **`progress.txt` with Codebase Patterns section** at the top — consolidates most important learnings across iterations. Each iteration APPENDS (never replaces). Includes thread URL so future iterations can `read_thread`.
- **Archive on branch change** — `ralph.sh` archives previous `prd.json`+`progress.txt` to `archive/YYYY-MM-DD-feature-name/` when branch changes.
- **AGENTS.md updates** — mid-implementation, update nearby AGENTS.md with genuinely reusable knowledge (not story-specific details).
- **Browser testing required for frontend** — uses `dev-browser` skill; story NOT complete until visually verified.
- **Stop signal** — `<promise>COMPLETE</promise>` tag. Loop config: `--tool amp|claude` + `max_iterations`.

**OMC Ralph (advanced):**
- **PRD scaffold refinement** — Step 1 forbids generic criteria like "Implementation is complete"; explicitly REQUIRES rewriting to task-specific verifiable criteria before proceeding. Explicit "PRD theater" anti-pattern.
- **Tiered reviewer selection** — STANDARD tier (arch-medium/Sonnet) for <5 files/<100 lines; THOROUGH tier (Opus) for >20 files or security/architectural. `--critic=architect|critic|codex` flag.
- **Cross-provider critic** (`--critic=codex`) — runs `omc ask codex --agent-prompt critic` with prd.json criteria + related-file context + explicit optimality question ("Is there a meaningfully simpler approach?").
- **"Review all code related to the changes"** — critic prompt mandates reviewing callers, callees, shared types, adjacent modules, not only modified files.
- **Mandatory Deslop Pass (Step 7.5)** — after review approval, invokes `ai-slop-cleaner` unconditionally (unless `--no-deslop`) scoped to Ralph session's changed files.
- **Regression re-verification (Step 7.6)** — after deslop, re-run all relevant tests/build/lint; if fails, roll back cleaner changes or fix until post-deslop regression passes.
- **"Polite-stop anti-pattern" prohibition** — explicitly bans treating approval as a reporting moment; the loop MUST proceed from 7 → 7.5 → 7.6 → 8 in the same turn.
- **Rationalization guard list** — "Claiming completion without PRD verification", "Keeping generic acceptance criteria", etc.

### Features quantum-loop lacks
- PRD scaffold refinement anti-pattern enforcement ("PRD theater")
- Mandatory deslop pass (post-review AI-slop cleanup, scoped to session)
- Regression re-verification AFTER deslop
- Tiered reviewer selection based on change size / risk
- Cross-provider critic option (codex critic reviewing Claude's work)
- "Review all code related to the changes" mandate for critics
- `progress.txt` Codebase Patterns section (ql has codebasePatterns but as array, not curated top-section of progress log)
- Mid-implementation AGENTS.md updates

---

## 3. oh-my-claudecode (OMC, 4.11.3)

**Sources:**
- Local: `C:\Users\andyzeng\.claude\plugins\cache\omc\oh-my-claudecode\4.11.3\`
- Key skills read: autopilot, ultrawork, ralph, team, deep-interview, sciomc, ai-slop-cleaner, self-improve, omc-reference
- Changelog: `CHANGELOG.md` (v4.11.3: 7 bug fixes)

### Overview
Opinionated 20-skill orchestration plugin with 20+ specialist agents and extensive cross-provider support (Claude + Codex CLI + Gemini CLI). Heavy focus on multi-phase autonomous execution with explicit quality gates.

### Core mechanisms (distinctive features)

**Composability stack:**
```
autopilot (full lifecycle)
  └ ralph (persistence + verification)
      └ ultrawork (parallel execution only)
```
Explicitly documented. Each layer adds one orthogonal concern.

**`/autopilot` — 6-phase pipeline:**
- Phase 0: Expansion (Analyst Opus → Architect Opus → spec.md)
- Phase 1: Planning (Architect → plan, Critic validates)
- Phase 2: Execution (Ralph + Ultrawork with model tiers: Haiku/Sonnet/Opus)
- Phase 3: QA (UltraQA mode: build, lint, test, fix; 5 cycles max; STOPS if same error 3 times — "fundamental issue")
- Phase 4: **Validation (parallel 3-agent review: architect + security-reviewer + code-reviewer; ALL must approve; fix + re-validate on rejection)**
- Phase 5: Cleanup (removes all `.omc/state/*-state.json` files)

**3-stage pipeline composition:** `deep-interview → ralplan --consensus --direct → autopilot`. Each stage is a quality gate (clarity, feasibility, correctness). Autopilot DETECTS prior artifacts and SKIPS redundant phases (e.g., if `.omc/plans/ralplan-*.md` exists, skip Phase 0+1 entirely). **Phase skipping based on artifact detection is a powerful pattern quantum-loop lacks.**

**`/deep-interview` — mathematical ambiguity gating:**
- Socratic Q&A with ambiguity scored across weighted dimensions (goal 40%/constraints 30%/criteria 30% for greenfield; 35/25/25/15 with added context for brownfield)
- Threshold-based gate (default 20%); refuses execution until below threshold
- **Ontology stability tracking** — extracts entities each round; tracks stable/changed/new/removed; `stability_ratio` must converge before completion
- **Challenge agent modes** — Contrarian (round 4+), Simplifier (round 6+), Ontologist (round 8+ if ambiguity > 0.3); activated via prompt-injection, not separate agents
- **Targets WEAKEST dimension** with each question; must explain WHY that dimension is the bottleneck
- **Gathers codebase facts via `explore` agent BEFORE asking user about them** — cites file:line evidence in questions ("I found JWT auth middleware in src/auth/. Should this feature extend that path or diverge?")
- One question at a time (never batch); AskUserQuestion tool
- `--autoresearch` mode: skip bridge, launch autoresearch directly with mission + evaluator

**`/team` — N coordinated agents with native Claude Code team tooling:**
- Stages: `team-plan → team-prd → team-exec → team-verify → team-fix` (loop)
- **Stage-specific agent routing** — different specialist agents per stage (planner/analyst for plan, executor/designer/debugger for exec, verifier+security-reviewer+code-reviewer for verify)
- **Handoff documents** — each stage writes `.omc/handoffs/<stage>.md` with Decided/Rejected/Risks/Files/Remaining — accumulates for next stage. Solves context loss on lead compaction.
- **Pre-assign owners** (`TaskUpdate` before worker spawn) to avoid race on task claim
- **Inter-agent messaging** — `SendMessage` DM + broadcast; teammates auto-arrive as new conversation turns
- **Task watchdog policy** — max in-progress age 5min → status check; 10min stuck → reassign to another worker; 2+ failures from one worker → stop assigning
- **Hybrid workers** — Claude teammates + Codex CLI + Gemini CLI workers (each with different strengths)
- **Git-worktree per worker** + merge coordination (`checkMergeConflicts`, `mergeWorkerBranch --no-ff`, `mergeAllWorkerBranches`)
- **Circuit breaker** and **fix-loop cap** (`max_fix_loops`) prevent infinite loops
- Blocking shutdown protocol with `request_id` correlation; orphan-scan script

**`/sciomc` — parallel scientist workflow:**
- Decompose research goal into 3-7 independent stages (LOW/MEDIUM/HIGH tier); fire in parallel (max 20 concurrent)
- **Structured finding tags** — `[FINDING:id]…[/FINDING]`, `[EVIDENCE:finding-id]…[/EVIDENCE]`, `[CONFIDENCE:HIGH|MED|LOW]`, `[STAGE_COMPLETE:n]`, `[VERIFIED]`/`[CONFLICTS:list]`
- **Cross-validation stage** — explicitly checks for contradictions, missing connections, gaps, evidence quality across stages
- **Quality validation** — every finding must have evidence + confidence + reproducible source; findings without evidence are OPINIONS not findings
- **Evidence windows** — include file:line context (e.g., `lines 45-52 (context: 40-57)`)

**`/self-improve` — evolutionary improvement engine:**
- **Tournament selection** per iteration: N parallel planners → architect review → critic review (harness rules H001/H002/H003) → N parallel executors → benchmark → tournament → winner merges
- **"Ranked-candidate loop with re-benchmark-on-merge"** — candidate is actually merged, re-benchmarked to confirm improvement holds, reverted if regression
- **Archive losers** with git tags (`archive/round_n_executor_id`) before deletion
- **Sealed files list** — `validate.sh` enforces benchmark code cannot be self-modified
- **Trust confirmation gate** — cannot skip; records consent before running
- **Stale worktree cleanup** runs every iteration (handles crash recovery from orphaned worktrees)
- **Approach family taxonomy** (H003 rule): no two plans with same `approach_family` tag in same round, no family streak ≥3
- **Plateau + circuit breaker counters** — plateau tracks stagnating wins, circuit breaker tracks consecutive no-winner rounds
- **Structured state tracking** — `iteration_state.json`, `research_briefs/`, `plan_archive/`, `merge_reports/`, `tracking/raw_data.json`
- **Visualization** — `plot_progress.py` generates progress.png every iteration

**`/ai-slop-cleaner` — post-implementation cleanup:**
- Explicit slop taxonomy: Duplication / Dead code / Needless abstraction / Boundary violations / Missing tests
- Single-smell passes (Pass 1 dead code → Pass 2 duplicates → Pass 3 naming/error-handling → Pass 4 test reinforcement)
- **Protect behavior first** — write regression tests BEFORE editing; if tests can't come first, record verification plan explicitly
- **Reviewer-only `--review` mode** — writer/reviewer separation enforced for high-impact cleanup (same pass can't write + self-approve)
- Bounded scope (file-list or session-changed-files only; never silently broadens)

**`/ccg` (Claude-Codex-Gemini) synthesis lane:**
- Query Codex via `/ask codex` + Gemini via `/ask gemini` in parallel; Claude synthesizes
- Used for tri-model consensus on hard problems

**Specialist agents (20+ defined):**
- `critic` — adversarial final gate with pre-commitment predictions, pre-mortem analysis, self-audit phase, Realist Check phase (downgrade findings if mitigating factors exist), ADVERSARIAL mode escalation if pattern of issues found
- `architect` — read-only, cites file:line for every claim, requires root cause (not symptoms), 4-phase protocol for non-obvious bugs, 3-failure circuit breaker ("question architecture rather than try variations")
- `analyst`, `planner`, `executor`, `verifier`, `tracer`, `security-reviewer`, `code-reviewer`, `test-engineer`, `designer`, `writer`, `qa-tester`, `scientist`, `document-specialist`, `git-master`, `code-simplifier`, `debugger`, `explore`

**Other distinctive features:**
- **Notepad system** — `notepad_read/write_priority/write_working/write_manual` MCP tools for scratch memory distinct from project memory
- **Project memory** — `project_memory_add_directive` (forward-looking instructions) vs `project_memory_add_note` (facts)
- **State MCP tools** — `state_read/write/clear/list_active/get_status` with 30min TTL, mode exclusivity ("mode exclusivity: refuse to start if autopilot/ralph/ultrawork active")
- **Commit protocol with git trailers** — `Constraint:`, `Rejected:`, `Directive:`, `Confidence:`, `Scope-risk:`, `Not-tested:` — preserves decision context
- **Cancel protocol** — `/omc:cancel` with linked-mode cascading cleanup (team+ralph)
- **Notification integrations** — Telegram/Discord/Slack via `/configure-notifications`
- **Runtime V2** (event-driven team runtime) — flag-gated, uses events.jsonl instead of done.json polling

### Features quantum-loop lacks
Too many to list exhaustively. Highest-leverage:
- Phase-skipping via artifact detection (auto-detect prior specs/plans, skip redundant stages)
- Ambiguity-gated interview (mathematical threshold before execution)
- Ontology convergence tracking
- Challenge-agent modes (Contrarian/Simplifier/Ontologist at round thresholds)
- Stage-handoff documents that accumulate across pipeline
- Tournament selection with re-benchmark-on-merge + revert-on-regression
- Approach-family taxonomy + diversity enforcement
- Adversarial critic with self-audit + Realist Check + escalation
- Structured finding tags with mandatory evidence+confidence
- Ai-slop-cleaner with smell taxonomy + single-pass discipline
- State MCP tools with mode-exclusivity
- Git trailer commit protocol
- Task watchdog + circuit breaker
- Mode composition (ralph wraps ultrawork; team+ralph links)
- Polite-stop anti-pattern enforcement

---

## 4. oh-my-openagent / multi-provider orchestration

**Finding:** "oh-my-openagent" doesn't appear as a major named project in search. However, OMC already provides the cross-provider orchestration tricks worth extracting.

### Cross-provider orchestration tricks from OMC + related
- **`omc ask <claude|codex|gemini>`** — unified router for querying each provider
- **`/ccg` (Claude-Codex-Gemini)** — parallel tri-model synthesis lane
- **Cross-provider critic** — `--critic=codex` has Claude's work reviewed by Codex with structured prompt including prd.json criteria + related files + optimality question
- **Hybrid team workers** — Claude agents + Codex CLI (via tmux) + Gemini CLI (via tmux) within one team
- **Tool-substitution mapping** — superpowers-codex maps `Task` → manual fallback, `TodoWrite` → `update_plan`, etc., so the same skill library runs across providers

---

## 5. gsd (gsd-build/get-shit-done) & gstack (garrytan/gstack)

### gsd — 48k stars, spec-driven pipeline for Claude Code / OpenCode / Gemini / Codex / Cursor / Windsurf / Cline
**Sources:** https://github.com/gsd-build/get-shit-done, https://docs.bswen.com/blog/2026-04-21-what-is-gsd/

### Overview
Meta-prompting + context engineering + spec-driven development system that solves "context rot" in long AI-assisted projects. v1.34.2 shipped 2026-04-06; 1,693 commits across 47 releases since Dec 2025.

### Core mechanisms
- **6-phase cycle per milestone:** Discuss → Plan → Execute → Verify → Ship → Complete. Repeats until milestone done.
- **Discuss phase** — captures implementation preferences BEFORE planning (by feature type: visual/API/content/organizational); output feeds directly to planner so planner "knows what decisions are locked"
- **State files:** `PROJECT.md` (vision), `REQUIREMENTS.md` (scoped v1/v2 with phase traceability), `ROADMAP.md` (phases→requirements→completion), `STATE.md` ("decisions, blockers, position — memory across sessions"), phase-specific artifacts `CONTEXT.md`, `RESEARCH.md`, `PLAN.md`, `SUMMARY.md`
- **Wave-based dependency execution** — plans grouped into waves based on XML-specified dependencies; within wave = parallel, across waves = sequential. "User model and product model (Wave 1) → Orders and Cart APIs (Wave 2, depend on models) → Checkout UI (Wave 3, depends on both APIs)" — this is quantum-loop's DAG pattern but with EXPLICIT waves computed from dependencies.
- **Planner→Checker loop** — planning stage has check agent that verifies plans achieve phase goals before execution begins (loop until pass)
- **Atomic commits per task** — enables git bisect + clean reversion
- **Fresh 200k-context per executor** — keeps main orchestrator at 30-40% utilization
- **Session handoff** — `/gsd-pause-work` creates `HANDOFF.json`; `/gsd-resume-work` restores. Works across Claude Code, OpenCode, Gemini, Codex, Kilo, Cline, Copilot, Cursor, Windsurf, Antigravity, Augment, Trae.
- **Verifier-to-debugger handoff** — verification failures spawn debug agents that diagnose; verified fix plans ready for re-execution (no manual debugging)
- **Feature-type-aware discuss phase** — different gray areas surfaced for visual vs API vs content vs organizational features

### gstack — Garry Tan's 23-tool Claude Code setup (10k+ stars in 48 hours in 2026)
**Sources:** https://github.com/garrytan/gstack, https://gstacks.org/

### Overview
Opinionated skill pack with 9 specialist roles (CEO, Designer, Eng Manager, Release Manager, Doc Engineer, QA, plan-reviewer, code-reviewer, ship-commander) as slash commands. Tan averaged 10k lines / 100 PRs per week over 50 days with this setup.

### Distinctive patterns
- **Role-per-specialist-command** — `/ceo`, `/designer`, `/qa`, etc. — each encapsulates a role's checklist
- **"AI slop" catcher** — designer role specifically catches visual AI-slop (misaligned, inconsistent styling)
- **Engineering retrospective** as explicit slash command
- **One-command shipping** — `/ship` does commit + PR + announce

### Features quantum-loop could borrow
- Wave-based DAG execution (explicit dependency-grouped parallel waves)
- Planner→Checker inner loop before execution
- Fresh-context-per-executor discipline with orchestrator utilization budget (<40%)
- Feature-type-aware requirements gathering (different questions for visual/API/content/organizational)
- Session handoff file (`HANDOFF.json`) for cross-session resumption
- Verifier→debugger auto-handoff
- Role-per-specialist slash commands

---

## 6. Other serious alternatives

### 6a. Aider (paul-gauthier/aider)
**Sources:** https://aider.chat, https://aider.chat/docs/usage/modes.html, https://aider.chat/2024/09/26/architect.html
- **Architect mode** — splits reasoning from editing: main model proposes solution (as architect), editor model converts proposal to file-edit instructions. With o1-preview as architect + DeepSeek/o1-mini as editor, achieved SOTA 85% on benchmarks.
- **Multi-file edits with automatic git tracking** — every change is a git commit
- **100+ languages, repo-map** that feeds into prompts
- **Linting + testing integrated** — auto-run on edits

**quantum-loop could borrow:**
- Architect/editor split (planner proposes, different agent converts to file edits) — reduces single-agent cognitive load
- Auto-commit per edit (ql already has this via worktree flow; aider makes it more granular)
- Repo-map generation as context primitive

### 6b. OpenHands (All-Hands-AI)
**Sources:** https://openhands.dev, https://arxiv.org/abs/2407.16741, https://github.com/OpenHands/OpenHands
- **v1.6.0 (2026-03-30)** — Kubernetes support + Planning Mode beta
- **Agent is a swarm of small smart agents** — can define agents in code, run locally or scale to 1000s in cloud
- **Code-review-as-feature** — summarizes PRs, applies feedback, fixes tests, pushes changes — "code reviews from hours to minutes"
- **Raised $18.8M Series A in 2026** — shipping fast

**quantum-loop could borrow:**
- Kubernetes-scale runner configuration (for remote parallel worktree execution)
- Agent-defined-in-code approach (reusable agent specs across projects)
- PR-feedback-applier bot as an explicit pipeline stage (reviewer comments → auto-address → push)

### 6c. SWE-agent (princeton-nlp/SWE-agent)
**Sources:** https://github.com/SWE-agent/SWE-agent, https://arxiv.org/abs/2405.15793, NeurIPS 2024
- **Agent-Computer Interface (ACI)** — custom interface for agents: file editing, repo navigation, test execution, error analysis. Distinct from "give the agent a shell"; much more constrained.
- **Mini-SWE-Agent** — 100 lines of Python, 65% on SWE-bench verified
- **SWE-smith** — training data generator (10k+ trajectories)
- **7-phase maintenance pipeline:** Preprocessing → Issue Reproduction → Issue Localization → Task Decomposition → Patch Generation → Patch Verification → Ranking
- **SWE-EVO benchmark (2025-12)** — long-horizon software evolution scenarios (100+ commits, refactoring across time)

**quantum-loop could borrow:**
- Explicit "Issue Reproduction" and "Issue Localization" phases before patch generation (quantum-loop's Spec phase could formalize these)
- Patch ranking (select best of N patches, not just run first to pass tests)
- Long-horizon benchmark harness (SWE-EVO-style scenarios) to validate ql across multiple commits

### 6d. Cursor background agents (Cursor 3, April 2026)
**Sources:** https://cursor.com/blog/agent-best-practices, https://releasebot.io/updates/cursor
- **Up to 8 parallel agents per user**, each in isolated cloud VM with terminal+browser+full-desktop
- **Automatic git worktrees per agent** — editing/building/testing without stepping on each other
- **Local-to-cloud agent handoff** — start local, continue in cloud
- **Agents surfaced in single sidebar** — mobile, web, desktop, Slack, GitHub, Linear all one pane
- **20x scaled RL for agent reliability** + self-summarization for long-session context + 60% latency reduction
- **~70-80% one-shot task completion** (vs Codex 40-60%) per Cursor's testing
- **Cursor 3 shifted primary model from file editing to managing parallel coding agents** (Anysphere)

**quantum-loop could borrow:**
- Isolated VM-per-agent (not just worktree) for reviewer agents (prevents cross-contamination)
- Cross-surface agent tracking (slack/mobile/GitHub/linear hooks for notifications when stories pass/fail)
- "Orchestrator-first UI" mental model (managing agents beats editing files for 80% of workflows)
- Self-summarization for cross-iteration context compression

### 6e. Devin (Cognition AI)
**Sources:** https://cognition.ai/blog/devin-review, https://cognition.ai/blog/devin-can-now-manage-devins, https://cognition.ai/blog/introducing-devin-2-2, https://docs.devin.ai/release-notes/2026
- **Compound AI system** — swarm of specialized models:
  - Planner (high-reasoning)
  - Coder (code-specialized)
  - **Critic (adversarial, reviews before execution, catches security + logic errors)**
- **"Devin can now Manage Devins"** — main Devin delegates to managed Devins in parallel; each managed Devin has its own isolated VM, narrow focus, its own shell, own test runner. Main coordinates: scopes work, assigns, monitors, resolves conflicts, compiles results.
- **Self-review loop** — "plans, codes, reviews its own output, catches issues, and fixes them all before you ever open the PR"
- **Integrated with Windsurf** (Devin-in-Windsurf)

**quantum-loop could borrow:**
- Adversarial critic runs BEFORE execution (not just after) to pre-empt known issue classes
- Manager-Devin pattern: orchestrator doesn't implement, only coordinates managed workers
- Per-worker isolated VM with own test runner (not just worktree)
- Internal self-review loop that catches issues before PR is opened

### 6f. Cline (cline/cline)
**Sources:** https://cline.bot, https://vibecoding.app/blog/cline-review-2026, https://marketplace.visualstudio.com/items?itemName=saoudrizwan.claude-dev
- **Plan/Act modes** — Plan mode is READ-ONLY exploration; Act mode requires explicit user approval for every edit/command
- **Human-in-the-loop approval per action** — every file edit or command waits for Approve/Reject
- **MCP integration** — extensive; 5M+ developers
- **Browser automation** — Cline interacts with running application
- **Multi-provider** — Anthropic/OpenAI/Google/Bedrock/Ollama/OpenAI-compatible

**quantum-loop could borrow:**
- Explicit Plan/Act separation (read-only planning phase before any writes)
- Per-action approval mode (opt-in) for high-risk stories
- Browser automation for UI stories (ql's dev-browser verification gap)

### 6g. Roo Code (RooCodeInc/Roo-Code) — Cline fork
**Sources:** https://roocode.com, https://github.com/RooCodeInc/Roo-Code
- **Orchestrator mode** — coordinates complex tasks by delegating to specialized modes (Architect, Code, Debug, Custom) at the right time
- **Whenever coordination is required, Roo switches into Orchestrator role** → decides what next → which mode handles it
- **Multi-agent modes within single IDE** — 5.0 user rating in 2026 reviews
- **Customization-first** — "The customizer"

**quantum-loop could borrow:**
- Explicit Orchestrator role as a mode (quantum-loop has orchestrator agent; making it a MODE with mode-switch semantics is cleaner)
- Specialist-mode-switching mental model (Architect/Code/Debug/Custom as discrete modes)

### 6h. ComposioHQ/agent-orchestrator
**Sources:** https://github.com/ComposioHQ/agent-orchestrator
- **Each issue gets its own agent in isolated git worktree + own branch + own PR**
- **Autonomous CI fix** — "CI fails → agent gets the logs and fixes it" with configurable retry (2 retries in example config)
- **Autonomous review-comment addressing** — `changes-requested` reaction sends feedback back to agent for remediation
- **Agent-agnostic** — supports Claude Code, Codex, Aider
- **Runtime-agnostic** — tmux or Docker
- **Tracker-agnostic** — GitHub, Linear, etc.
- **Only notify human when judgment needed** — PRs approved with passing CI → notify to merge; unresolved review comments after 30min → escalate

**quantum-loop could borrow:**
- One-agent-per-issue isolation (ql does this per-story; issue-level could be coarser grain)
- Autonomous CI-fix loop (up to N retries before escalation)
- Autonomous review-comment-addresser (external reviewer comments → auto-address)
- Timed escalation to human (30min stuck → notify)
- Agent-agnostic abstraction (ql should formalize this; currently Claude-only)

### 6i. auto-swe / cw / Continue
Briefly noted but not deeply investigated — these exist in the open-source agent space but did not surface as dominant in 2026 coverage relative to the above. Not scoring them separately.

---

## Cross-Tool Feature Matrix

Legend: ✅ has it, ⚠️ partial, ❌ missing, — not applicable

| Feature Category                                 | Superpowers | Ralph (snark) | OMC Ralph | OMC Autopilot | OMC Team | OMC Self-improve | GSD | gstack | Aider | OpenHands | SWE-agent | Cursor BG | Devin | Cline | Roo Code | Composio Orch | **quantum-loop** |
|--------------------------------------------------|-------------|---------------|-----------|---------------|----------|------------------|-----|--------|-------|-----------|-----------|-----------|-------|-------|----------|---------------|------------------|
| Parallel worktree execution                      | ✅          | ❌            | ❌        | ✅            | ✅       | ✅               | ✅  | ⚠️     | ❌    | ✅        | ❌        | ✅        | ✅    | ❌    | ❌       | ✅            | ✅               |
| DAG / dependency management                      | ❌          | ⚠️ (priority)  | ⚠️        | ⚠️            | ✅       | ❌               | ✅ (waves) | ❌ | ❌ | ❌        | ⚠️        | ❌        | ❌    | ❌    | ❌       | ❌            | ✅ (dependsOn)    |
| Wave-based parallel-within-dependency-respected  | ❌          | ❌            | ❌        | ❌            | ✅       | ❌               | ✅  | ❌     | ❌    | ❌        | ❌        | ❌        | ❌    | ❌    | ❌       | ❌            | ⚠️                |
| Two-stage review (spec + quality)                | ✅          | ⚠️            | ✅        | ✅ (3-agent)  | ✅       | ✅               | ⚠️  | ⚠️     | ❌    | ⚠️        | ❌        | ❌        | ✅    | ❌    | ❌       | ❌            | ✅                |
| Multi-perspective review (security/ops/etc.)     | ⚠️          | ❌            | ✅        | ✅            | ✅       | ✅               | ❌  | ⚠️     | ❌    | ❌        | ❌        | ❌        | ⚠️    | ❌    | ❌       | ❌            | ❌                |
| Adversarial critic w/ self-audit + realist check | ❌          | ❌            | ⚠️        | ⚠️            | ⚠️       | ⚠️               | ❌  | ❌     | ❌    | ❌        | ❌        | ❌        | ✅    | ❌    | ❌       | ❌            | ❌                |
| Cross-provider critic (codex reviews Claude)     | ❌          | ❌            | ✅        | ⚠️            | ✅       | ❌               | ✅  | ❌     | ❌    | ❌        | ❌        | ❌        | ❌    | ❌    | ❌       | ⚠️            | ❌                |
| Ambiguity-gated interview                        | ⚠️ (brainstorm) | ❌        | ❌        | ⚠️            | ❌       | ❌               | ⚠️  | ❌     | ❌    | ❌        | ❌        | ❌        | ❌    | ❌    | ❌       | ❌            | ⚠️                |
| Ontology convergence tracking                    | ❌          | ❌            | ❌        | ❌            | ❌       | ❌               | ❌  | ❌     | ❌    | ❌        | ❌        | ❌        | ❌    | ❌    | ❌       | ❌            | ❌                |
| Post-implementation dead-code/slop cleanup       | ❌          | ❌            | ✅ (deslop) | ⚠️           | ⚠️       | ❌               | ❌  | ⚠️     | ❌    | ❌        | ❌        | ❌        | ❌    | ❌    | ❌       | ❌            | ❌                |
| Regression re-verification after cleanup         | ❌          | ❌            | ✅        | ❌            | ❌       | ✅               | ⚠️  | ❌     | ❌    | ❌        | ❌        | ❌        | ❌    | ❌    | ❌       | ❌            | ❌                |
| Fresh-context-per-task discipline                | ✅          | ✅            | ✅        | ✅            | ✅       | ✅               | ✅  | ✅     | ❌    | ✅        | ✅        | ✅        | ✅    | ❌    | ⚠️       | ✅            | ✅                |
| PRD/spec scaffold refinement ("no PRD theater")  | ⚠️          | ⚠️            | ✅        | ✅            | ✅       | ✅               | ✅  | ❌     | ❌    | ❌        | ❌        | ❌        | ❌    | ❌    | ❌       | ❌            | ⚠️                |
| Stage-handoff documents (accumulating)           | ❌          | ⚠️ (progress) | ⚠️        | ⚠️            | ✅       | ⚠️               | ✅  | ❌     | ❌    | ❌        | ❌        | ❌        | ⚠️    | ❌    | ❌       | ❌            | ❌                |
| Phase-skipping via artifact detection            | ❌          | ❌            | ⚠️        | ✅            | ⚠️       | ❌               | ✅  | ❌     | ❌    | ❌        | ❌        | ❌        | ❌    | ❌    | ❌       | ❌            | ❌                |
| Task watchdog / stuck-worker detection           | ❌          | ❌            | ⚠️        | ⚠️            | ✅       | ✅               | ⚠️  | ❌     | ❌    | ❌        | ❌        | ✅        | ✅    | ❌    | ❌       | ✅            | ❌                |
| Circuit breaker (3x same error → stop)           | ⚠️          | ⚠️            | ⚠️        | ✅            | ✅       | ✅               | ⚠️  | ❌     | ❌    | ❌        | ❌        | ❌        | ⚠️    | ❌    | ❌       | ⚠️            | ⚠️ (maxAttempts) |
| Tournament selection / best-of-N patches         | ❌          | ❌            | ❌        | ❌            | ❌       | ✅               | ❌  | ❌     | ❌    | ❌        | ✅ (rank) | ❌        | ❌    | ❌    | ❌       | ❌            | ❌                |
| Re-benchmark-on-merge + revert-on-regression     | ❌          | ❌            | ❌        | ❌            | ❌       | ✅               | ❌  | ❌     | ❌    | ❌        | ❌        | ❌        | ❌    | ❌    | ❌       | ❌            | ❌                |
| Skill-tool enforcement with rationalization guard | ✅         | ❌            | ✅        | ✅            | ✅       | ✅               | ⚠️  | ❌     | ❌    | ❌        | ❌        | ❌        | ❌    | ❌    | ❌       | ❌            | ⚠️                |
| Self-review checklist before handoff             | ✅          | ❌            | ⚠️        | ✅            | ✅       | ✅               | ✅  | ❌     | ❌    | ❌        | ❌        | ❌        | ✅    | ❌    | ❌       | ❌            | ⚠️                |
| Structured finding tags (EVIDENCE+CONFIDENCE)    | ⚠️          | ❌            | ⚠️        | ⚠️            | ⚠️       | ✅               | ✅  | ❌     | ❌    | ❌        | ❌        | ❌        | ❌    | ❌    | ❌       | ❌            | ❌                |
| Commit trailer protocol (Rejected, Constraint…)  | ❌          | ❌            | ✅        | ✅            | ✅       | ✅               | ⚠️  | ❌     | ⚠️    | ❌        | ❌        | ❌        | ❌    | ❌    | ❌       | ❌            | ❌                |
| Architect mode (reasoning/editor split)          | ❌          | ❌            | ❌        | ⚠️            | ⚠️       | ❌               | ❌  | ❌     | ✅    | ❌        | ❌        | ❌        | ✅    | ❌    | ⚠️       | ❌            | ❌                |
| Plan/Act mode separation                         | ⚠️          | ❌            | ❌        | ⚠️            | ⚠️       | ❌               | ✅  | ❌     | ❌    | ✅        | ❌        | ❌        | ❌    | ✅    | ✅       | ❌            | ⚠️ (brainstorm→exec) |
| Browser automation for UI verification           | ❌          | ✅            | ❌        | ❌            | ❌       | ❌               | ⚠️  | ✅     | ❌    | ❌        | ❌        | ✅        | ⚠️    | ✅    | ❌       | ❌            | ❌                |
| Auto-address reviewer comments on external PRs   | ❌          | ❌            | ❌        | ❌            | ❌       | ❌               | ❌  | ❌     | ❌    | ✅        | ❌        | ⚠️        | ⚠️    | ❌    | ❌       | ✅            | ❌                |
| Autonomous CI-failure fix loop                   | ⚠️          | ⚠️            | ✅        | ✅            | ✅       | ⚠️               | ✅  | ⚠️     | ⚠️    | ✅        | ✅        | ✅        | ✅    | ❌    | ❌       | ✅            | ⚠️                |
| Multi-provider (Claude + Codex + Gemini)         | ✅          | ⚠️            | ✅        | ✅            | ✅       | ❌               | ✅  | ❌     | ✅    | ✅        | ✅        | ⚠️        | ❌    | ✅    | ✅       | ✅            | ❌                |
| Notification hooks (Slack/Discord/Telegram)      | ❌          | ❌            | ⚠️        | ⚠️            | ⚠️       | ❌               | ❌  | ❌     | ❌    | ✅        | ❌        | ✅        | ✅    | ❌    | ❌       | ✅            | ❌                |
| State mode-exclusivity (no 2 loops at once)      | ❌          | ❌            | ✅        | ✅            | ✅       | ✅               | ⚠️  | ❌     | ❌    | ❌        | ❌        | ⚠️        | ⚠️    | ❌    | ❌       | ❌            | ❌                |

---

## Top 15 Features Quantum-Loop Should Borrow

Ranked by leverage (impact × feasibility × alignment with known gaps).

### 1. **Post-implementation AI-slop-cleaner + regression re-verification** (from OMC Ralph 7.5/7.6)
**Solves:** Duplicate code, dead code, bloat across stories.
**Mechanism:** After review approves a story, MANDATORY cleanup pass scoped ONLY to that story's changed files with smell taxonomy (duplicate/dead/needless-abstraction/boundary/missing-tests). Then re-run regression. If fails, roll back cleaner changes or fix until passes. Opt-out via `--no-deslop` flag only.
**Gap hit:** Duplicate code, dead code (explicit known gaps).

### 2. **Two-stage review enhanced: spec reviewer explicitly checks for OVER-building** (from Superpowers)
**Solves:** Stories that implement extra features beyond spec (drift from intent).
**Mechanism:** Spec reviewer prompt explicitly looks for: missing requirements + EXTRA features not requested + misinterpretations. "Did they build things that weren't requested? Did they over-engineer?" Current ql spec-reviewer may miss over-building.
**Gap hit:** Intent drift across stages.

### 3. **Wave-based parallel execution with explicit dependency→wave compilation** (from GSD, Team)
**Solves:** Cross-story wiring issues, merge conflicts.
**Mechanism:** Group stories into waves based on `dependsOn` DAG; stories in same wave run parallel, waves run sequential. Explicit wave boundaries = sync points where wiring between stories can be validated.
**Gap hit:** Cross-story wiring issues, merge conflicts.

### 4. **Cross-provider critic for final gate** (from OMC Ralph `--critic=codex`)
**Solves:** Intent drift, semantic issues missed by Claude self-review.
**Mechanism:** Final review can be done by DIFFERENT provider (Codex or Gemini) with prompt including: full acceptance criteria + files changed + list of RELATED files (callers, callees, shared types, adjacent modules) + explicit optimality question. Different provider = different failure modes = higher catch rate.
**Gap hit:** Review gates that miss semantic issues; intent drift.

### 5. **Adversarial critic with self-audit + Realist Check + ADVERSARIAL-mode escalation** (from OMC critic agent)
**Solves:** Review gates that miss issues.
**Mechanism:** Pre-commitment predictions before reading (activates deliberate search), multi-perspective review (security/new-hire/ops OR executor/stakeholder/skeptic for plans), explicit gap analysis ("what's MISSING?"), self-audit phase (move low-confidence findings to Open Questions), Realist Check (pressure-test CRITICAL/MAJOR severity with "mitigating factors"), escalate to ADVERSARIAL mode if >1 CRITICAL or >3 MAJOR found.
**Gap hit:** Review gates miss issues.

### 6. **Ambiguity-gated spec refinement (deep-interview style)** (from OMC deep-interview)
**Solves:** Intent drift across stages, vague acceptance criteria.
**Mechanism:** Mathematical ambiguity scoring across dimensions (goal/constraints/criteria + context for brownfield) with weighted threshold (default 20%). Refuses to proceed to plan stage until below threshold. Ontology stability tracking (same entities in N consecutive rounds = stable). Challenge modes (Contrarian at round 4, Simplifier at round 6, Ontologist at round 8).
**Gap hit:** Intent drift; specs that don't lock decisions.

### 7. **Stage-handoff documents that accumulate across pipeline** (from OMC Team)
**Solves:** Context loss when lead/orchestrator compacts; intent drift across stages.
**Mechanism:** Each stage writes `.handoffs/<stage>.md` with fields: Decided / Rejected / Risks / Files / Remaining. Lead reads previous handoff BEFORE spawning next stage's agents. Handoffs accumulate (plan→prd→exec visible to verify stage). Survives cancellation for resume.
**Gap hit:** Intent drift across stages.

### 8. **Phase-skipping via artifact detection** (from OMC Autopilot)
**Solves:** Wasted work re-doing prior stages; pipeline composability.
**Mechanism:** Each stage checks for prior-stage artifacts (e.g., autopilot detects `.omc/plans/ralplan-*.md` and SKIPS Phase 0+1 entirely). Enables composing `deep-interview → ralplan → autopilot` without re-running anything.
**Gap hit:** Pipeline composability; lets users drop in at any stage with prior state.

### 9. **Implementer self-review checklist before reporting completion** (from Superpowers, OMC Team)
**Solves:** Low-quality handoffs that waste reviewer cycles.
**Mechanism:** Implementer self-reviews with structured checklist (Completeness/Quality/Discipline/Testing) BEFORE reporting done. Fixes obvious issues locally. Reviewer gets cleaner work.
**Gap hit:** Review efficiency.

### 10. **Task watchdog + circuit breaker** (from OMC Team, Self-improve)
**Solves:** Stuck workers, infinite retry loops.
**Mechanism:** Max in-progress age 5min → status check. 10min stuck → reassign. 2+ failures from same worker → stop assigning. Same error 3x → "fundamental issue", stop autonomously. quantum-loop has `retries.maxAttempts` but doesn't have temporal watchdog or cross-story failure pattern detection.
**Gap hit:** Reliability under long runs.

### 11. **Structured finding tags with mandatory evidence+confidence** (from OMC sciomc, self-improve)
**Solves:** Review reports with opinions masquerading as findings.
**Mechanism:** Every finding must have `[EVIDENCE:id]` (file:line + content with context window) AND `[CONFIDENCE:HIGH|MED|LOW]`. Findings without evidence are REJECTED as opinions. Enables cross-validation stage that checks for contradictions/gaps/evidence quality.
**Gap hit:** Review quality; makes cross-story conflict detection mechanizable.

### 12. **Commit trailer protocol for decision preservation** (from OMC)
**Solves:** Intent drift across stages; forgotten tradeoffs.
**Mechanism:** Every commit carries git trailers: `Constraint:`, `Rejected: option | reason`, `Directive:`, `Confidence:`, `Scope-risk:`, `Not-tested:`. Makes decisions grep-able. `git log --grep="Rejected:"` surfaces what was considered-and-rejected.
**Gap hit:** Intent drift; codebase-patterns tracking.

### 13. **Tournament selection with re-benchmark-on-merge for any story with measurable criteria** (from OMC Self-improve)
**Solves:** Locking in best-of-N solutions; stories with multiple valid approaches.
**Mechanism:** For stories where multiple approaches are viable, spawn N parallel executors with different `approach_family` tags (enforced diversity). After execution, rank by score/tests-passing. Merge best. Re-benchmark on merged state. If re-benchmark shows regression → revert merge, try next candidate. Archive losers with git tags before deletion.
**Gap hit:** Single-candidate lock-in where better solutions exist.

### 14. **Autonomous CI / review-comment fix loop** (from OMC Autopilot Phase 3, Composio, OpenHands)
**Solves:** Human-in-the-loop bottleneck after PR creation.
**Mechanism:** After PR is created, monitor CI. On failure, pull logs, spawn fix-agent, push fix, retry. On reviewer comments, spawn comment-addresser agent. Escalate to human ONLY after N failures or 30min no-progress.
**Gap hit:** Post-merge feedback loop (quantum-loop stops at story-passed; doesn't handle external CI/review).

### 15. **Rationalization-blocking skill enforcement language + prohibited "polite stops"** (from Superpowers + OMC Ralph)
**Solves:** Agents skipping stages with rationalizations ("I know what that means" / "just this once" / approving = stopping for report).
**Mechanism:** Two patterns from the best-in-class:
  - Superpowers' "Skip any step = lying, not verifying" + rationalization table with "Should work now" → RUN THE VERIFICATION
  - OMC Ralph's explicit ban on "polite-stop anti-pattern": "Treating an APPROVED verdict as 'time to summarise and wait for user acknowledgment' is a polite-stop anti-pattern"
Apply to quantum-loop's Step 5/6/7: make "REVIEW PASSED = proceed to commit in the same turn" an explicit iron law, not a soft suggestion.
**Gap hit:** Process skipping; "almost done" claims.

---

## Appendix: Notable Minor Features to Consider

- **`find-polluter.sh` bisection script** (Superpowers) for flaky-test root-cause
- **Condition-based-waiting patterns** instead of arbitrary timeouts (Superpowers systematic-debugging bundle)
- **Per-story progress.txt append-never-replace** with curated Codebase Patterns at top (Ralph)
- **Archive previous runs on branch change** (Ralph `ralph.sh`)
- **Pre-assign task owners to avoid claim races** (OMC Team)
- **Shutdown protocol with request_id correlation + orphan-scan** (OMC Team)
- **DOT flowcharts as canonical skill specs** (Superpowers v4.0.0)
- **Plan/Act mode separation** (Cline / Roo Code) — read-only plan before any writes
- **Role-per-specialist slash commands** (gstack)
- **Atomic commits per task for bisectability** (GSD)
- **Evidence windows in finding citations** — include lines 45-52 with context 40-57 (OMC sciomc)
- **Sealed files list with enforcement script** (OMC Self-improve `validate.sh`)

---

## Sources

### Local plugin caches consulted
- `C:\Users\andyzeng\.claude\plugins\cache\superpowers-marketplace\superpowers\4.0.3\` (README, RELEASE-NOTES, 14 skills)
- `C:\Users\andyzeng\.claude\plugins\cache\omc\oh-my-claudecode\4.11.3\` (CHANGELOG, 36 skills, 19 agents)
- `C:\Users\andyzeng\.claude\plugins\cache\ralph-marketplace\ralph-skills\1.0.0\` (SKILL.md, prd.json.example, prompt.md, ralph.sh)
- `C:\Users\andyzeng\.claude\plugins\cache\everything-claude-code\everything-claude-code\1.2.0\` (README, skills/iterative-retrieval, continuous-learning-v2, eval-harness)

### Web sources
- [Superpowers GitHub](https://github.com/obra/superpowers) / [Release Notes](https://github.com/obra/superpowers/blob/main/RELEASE-NOTES.md)
- [OpenHands Platform](https://openhands.dev/) / [arXiv paper](https://arxiv.org/abs/2407.16741) / [v1.6.0 notes](https://github.com/OpenHands/OpenHands)
- [Aider Modes](https://aider.chat/docs/usage/modes.html) / [Architect mode post](https://aider.chat/2024/09/26/architect.html)
- [SWE-agent](https://github.com/SWE-agent/SWE-agent) / [arXiv](https://arxiv.org/abs/2405.15793) / [mini-SWE-Agent](https://github.com/SWE-agent/mini-swe-agent/) / [SWE-EVO benchmark](https://arxiv.org/html/2512.18470v5)
- [Cursor Agent best practices](https://cursor.com/blog/agent-best-practices) / [Cursor 3 launch](https://www.infoq.com/news/2026/04/cursor-3-agent-first-interface/) / [Background Agents guide](https://ameany.io/cursor-background-agents/)
- [Cognition Devin Blog](https://cognition.ai/blog/devin-review) / [Managing Devins](https://cognition.ai/blog/devin-can-now-manage-devins) / [Devin 2.2](https://cognition.ai/blog/introducing-devin-2-2) / [Docs 2026 release](https://docs.devin.ai/release-notes/2026)
- [Cline](https://cline.bot) / [2026 review](https://vibecoding.app/blog/cline-review-2026) / [VS Code Marketplace](https://marketplace.visualstudio.com/items?itemName=saoudrizwan.claude-dev)
- [Roo Code](https://roocode.com) / [GitHub](https://github.com/RooCodeInc/Roo-Code) / [Roo vs Cline 2026](https://www.qodo.ai/blog/roo-code-vs-cline/)
- [ComposioHQ agent-orchestrator](https://github.com/ComposioHQ/agent-orchestrator)
- [GSD (Get Shit Done)](https://github.com/gsd-build/get-shit-done) / [48k-star blog post](https://www.augmentcode.com/learn/gsd-stars-spec-driven-dev-claude-code) / [Context engineering post](https://docs.bswen.com/blog/2026-04-21-gsd-context-engineering/)
- [gstack (Garry Tan's setup)](https://github.com/garrytan/gstack) / [gstacks.org](https://gstacks.org/) / [Toolworthy review](https://www.toolworthy.ai/tool/gstack)
- [AddyOsmani: Code Agent Orchestra](https://addyosmani.com/blog/code-agent-orchestra/) / [Future of agentic coding](https://addyosmani.com/blog/future-agentic-coding/)

