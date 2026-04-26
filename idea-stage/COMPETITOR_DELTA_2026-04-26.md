# Competitor Delta Survey 2026-04-26

**Window:** 2026-04-21 → 2026-04-26 (delta-only; prior survey = COMPETITOR_SURVEY.md @ 2026-04-21)
**Author:** quantum-loop research agent
**Purpose:** What is NEW since the prior survey, ranked for adoption.

---

## Executive Summary (5 bullets)

- **Superpowers jumped two majors (v4.2.0 → v5.0.7)** between Feb 12 and Mar 31, 2026. Three mechanisms matter for ql: (1) **mandatory subagent-driven dev with cheapest-capable-model routing** (Haiku for impl after detailed plans), (2) a **spec-review subagent** that audits planning docs for TBDs/incompleteness before implementation, (3) **inline self-review checklists** that replaced subagent review loops and cut review time from ~25 min → ~30 sec. v5.0.4 also reduced max review iterations from 5 → 3 and consolidated chunk-by-chunk reviews into a single whole-pass.
- **OMC shipped 8 patch+minor releases (v4.11.4 → v4.13.4)** in the window. The headline is **autoresearch-as-a-skill migration (v4.13.0)** — autoresearch is now invokable as a skill rather than a top-level mode, enabling composition. v4.12.0 introduced **per-role provider routing with resolved-routing snapshots** (assign Codex to critic, Claude to executor, Gemini to planner — captured into a snapshot for reproducibility). v4.13.1 added **cursor-agent as 4th tmux worker type** alongside Claude/Codex/Gemini.
- **sst/opencode is now a first-class skills target.** Native `skill` tool auto-discovers from `.opencode/skills/`, `.claude/skills/`, `.agents/skills/`, and walks up to git root. Superpowers ships an installer that registers via OpenCode's plugin array. Built-in primary agents: `build`/`plan` (Tab-toggle); built-in subagents: `general`/`explore`. Latest: **v1.14.25 (2026-04-25)**.
- **NEW harness landscape:** (a) **Hermes Agent (NousResearch)** — 108k stars, "Harness Engineering" 5-component framework (instructions/constraints/feedback/memory/orchestration), self-evolution via DSPy + GEPA (Genetic-Pareto Prompt Evolution, ICLR 2026 oral) optimizing skills/prompts/code at $2-10 per run, no GPU. (b) **Cursor 3 (Apr 2 2026)** — Agents Window, Marketplace with Skills/Subagents/MCPs/Hooks/Rules, parallel agents across local/cloud/SSH/worktree, self-summarization compresses 5000 → 1000 tokens via RL. (c) **Claude Code 2.1.119 (Apr 23)** — `/ultrareview` parallel multi-agent code review, `/effort xhigh` for Opus 4.7, `--agent` honors `permissionMode`, plugin auto-update to highest satisfying git tag, native binary CLI. (d) **Karpathy-skills CLAUDE.md** — 88k stars in one week, the four-principle framework (Think Before Coding / Simplicity First / Surgical Changes / Goal-Driven Execution) is now de facto canon.
- **Top-7 ranked recommendations for ql's next phase:** (1) Spec-review subagent for planning-doc TBDs, (2) Cheapest-capable-model routing per task, (3) Per-role provider routing with snapshot reproducibility (closes P2.9), (4) GEPA-style skill self-evolution (new mechanism, partially closes P2.10), (5) `/ultrareview` parallel multi-agent review pattern, (6) Inline self-review checklists replacing subagent-loops (latency win), (7) sst/opencode skills compatibility for ql skills.

---

## 1. Superpowers (obra/superpowers) — v4.2.0 → v5.0.7

**Status:** Major version jump. Two majors and seven patches in window.

| Version | Date | Headline |
|---------|------|----------|
| v5.0.7 | 2026-03-31 | GitHub Copilot CLI support; OpenCode skills-path consistency |
| v5.0.6 | 2026-03-25 | **Inline self-review checklists replace subagent review loops (~25min → ~30sec)** |
| v5.0.4 | 2026-03-16 | **Single whole-pass plan review; max review iterations 5 → 3** |
| v5.0.2-5.0.5 | 2026-03-10..17 | Zero-dep brainstorm server; ESM/Windows fixes; Cursor plugin hooks |
| **v5.0.0** | **2026-03-09** | **Subagent-driven dev mandatory; cheapest-capable-model selection; spec-review subagent; visual brainstorming HTML companion; specs/plans dir restructure** |
| v4.3.0 | 2026-02-12 | Hard-gate brainstorm + DOT flow + EnterPlanMode intercept |

### v5.0.0 — substantive landmark

- **Mandatory subagent-driven development** with subagents defaulting to **cheapest model capable** of the task. With detailed plans from brainstorming, Claude Haiku often suffices for impl. Direct cost lever.
- **Spec-review subagent (NEW)** — fires AFTER planning but BEFORE impl. Reads spec/plan for TBD markers, vague criteria, incompleteness. Loops back if found. Distinct from ql's post-execution spec-reviewer.
- **Visual brainstorming companion** — local HTTP server serves HTML mockups; out of scope for CLI-only ql but interesting for future UI stories.
- **Directory restructure** to `docs/superpowers/{specs,plans}/` — namespace scaffolding under tool name.
- **SE guidance baked into brainstorming** — unit decomposition first, file-structure planning before task decomposition.
- Local CLAUDE.md/AGENTS.md override framework directives (ql aligns).
- Slash-command deprecation in favor of native skill tool.

### v5.0.4 / v5.0.6 — review-loop economics

- **v5.0.4**: chunk-by-chunk reviews are slower AND costlier than whole-pass. Max iters 5 → 3. Higher blocking thresholds eliminate minor-style noise.
- **v5.0.6**: inline self-review checklists replaced subagent loops; ~25min → ~30sec. Reserve subagents for *adversarial* review, not routine verification.

### v4.3.0 — process hardening

- Hard gate before impl; six-step checklist; GraphViz process flow; sync SessionStart hook; **EnterPlanMode intercept** routes any `/plan` invocation through brainstorm first.
- Theme: shift from "advisory language" to "enforceable constraints."

### Net new gaps for ql

1. Spec-review subagent BEFORE impl (ql's fires post-impl)
2. Cheapest-capable-model routing per task
3. Inline self-review checklists vs subagent-loops for routine gates
4. EnterPlanMode-style intercept on user-typed `/plan`
5. Whole-pass plan review (one-shot) vs chunk-by-chunk

---

## 2. oh-my-claudecode (OMC) — v4.11.3 → v4.13.4

**Status:** 10 releases in window. Confirmed via Yeachan-Heo/oh-my-claudecode releases.

| Version | Date | Headline |
|---------|------|----------|
| v4.13.2-4 | 2026-04-22..24 | HUD stdin scoping; portable shebangs; cancel-state clear; Codex MCP dedup |
| v4.13.1 | 2026-04-20 | **cursor-agent as 4th tmux worker**; self-improve artifacts scoped by topic |
| v4.13.0 | 2026-04-19 | **Autoresearch-as-a-skill migration** |
| v4.12.0-1 | 2026-04-16..18 | **Per-role provider routing with resolved-routing snapshots**; tier-alias alignment; Opus HIGH default → Opus 4.7 |
| v4.11.4-6 | 2026-04-09..13 | MiniMax provider; HUD spend display; release-skill rewrite |

### Substantive changes

- **v4.12.0 — per-role provider routing.** Assign different providers per role (planner=Claude, critic=Codex, executor=Gemini) captured into a **resolved-routing snapshot** for reproducibility. ql's multi-runner picks WHICH agent but not WHICH provider per role with snapshot. Direct upgrade path for ql's stage-3 dispatch and **closes P2.9**.
- **v4.13.0 — autoresearch-as-a-skill.** Autoresearch is now invokable as a skill, not a top-level mode. Lets any skill compose with autoresearch without mode-exclusivity collisions. Pattern: skills are the composition unit; modes are thin orchestrators over skills.
- **v4.13.1 — cursor-agent worker.** 4th tmux worker type, executor-only. Self-improve artifacts now **scoped by topic** so parallel `--topic foo` and `--topic bar` runs don't cross-contaminate.

### Net new gaps for ql

1. Per-role provider routing with resolved-routing snapshot (P2.9)
2. Skill-as-composition-unit discipline
3. Topic-scoped artifacts for parallel ql runs on the same repo

---

## 3. sst/opencode — newly canonical skills target

**Latest:** v1.14.25 (2026-04-25). Client/server TS monorepo (Turbo).

- **Primary agents** (Tab-toggle): `build` (full access) / `plan` (read-only, ask-before-edit/bash). System agents: Compaction/Title/Summary.
- **Subagents**: `general` (multi-step), `explore` (read-only). Manually invoked via `@general`.
- **Agent definition** via JSON or Markdown (`.opencode/agents/`). Fields: `mode`, `permissions` (per tool), `model`, `temperature`, `prompt`, `steps`.
- **Skills system Claude-compatible:** native `skill` tool auto-discovers from `.opencode/skills/`, `.claude/skills/`, `.agents/skills/`, walks up to git root, plus global config dirs. `SKILL.md` YAML frontmatter (name + description). Skills NOT auto-triggered — agent calls `skill({name})`. Permission gates per skill.
- **Superpowers IS ported** (since 2025-11-24): install via `plugin` array in `opencode.json`, restart → auto-install via Bun.

**Implication for ql:** ql skills already use same SKILL.md convention. Adding `opencode` as a ql runner target is near-zero-cost compatibility expansion.

---

## 4. NEW harness tools

### 4a. NousResearch/hermes-agent — 108k stars, "Harness Engineering" framework

**Single most novel mechanism in delta.** Released 2026-02. First open-source agent crossing 100k stars in 2026.

**5-component framework:** (1) **Instructions** (system prompt + skills), (2) **Constraints** (tools/permissions/guardrails), (3) **Feedback** (tests, lints, tool errors), (4) **Memory** (persistent SQLite + cross-session search), (5) **Orchestration** (sequential/concurrent tool calls + context compression).

**Closed-loop skill creation:** agent creates skills mid-session, improves during use, persists to disk, searches own past conversations. Runs on $5 VPS, GPU cluster, or serverless. Telegram/Discord/Slack/WhatsApp gateways.

### 4b. NousResearch/hermes-agent-self-evolution (DSPy + GEPA)

**GEPA = Genetic-Pareto Prompt Evolution** (ICLR 2026 oral). "Reflective" — reads execution traces to understand WHY failures occur, proposes targeted improvements.

**Loop:** read skill files/prompts → generate eval dataset from prior traces → GEPA proposes variants via mutations → evaluate vs real/synthetic data → constraint-filter (test-pass, size, semantic preservation) → select best → submit PR. **API-only, no GPU, $2-10 per run.**

Phase 1 (skill file optimization) shipped; Phases 2-5 = tool descriptions, system prompts, code evolution, pipelines. **Distinct from OMC self-improve tournament** (evolves *implementations*) — GEPA evolves the *meta-prompts and skills themselves*.

### 4c. Cursor 3 — agent-first IDE (2026-04-02)

- **Agents Window** — unified sidebar; parallel agents across local/cloud/SSH/worktree.
- **Marketplace** — plugins = Skills + Subagents + MCPs + Hooks + Rules. One-click install or private team marketplace. Partners: Amplitude/AWS/Figma/Linear/Stripe.
- **Self-summarization** — RL-trained context compression 5000+ → ~1000 tokens. Model-side trick ql can't replicate without RL, but prompt-side compress-on-demand is reproducible.
- Local-to-cloud session handoff via Composer 2. Design Mode for browser UI feedback. Agent Tabs side-by-side/grid.

### 4d. Anthropic Claude Code 2.1.x — explicitly dated within window

| Version | Date | Notable |
|---------|------|---------|
| v2.1.119 | 2026-04-24 | Forked subagents on external builds; `isolation:"worktree"` no longer reuses stale; bg subagents error after 10min |
| v2.1.115-118 | 2026-04-21..23 | Vim visual mode; `/skills` token-count sort; plugin auto-update to highest satisfying git tag; `/plan` works with existing plans |

Earlier-April highlights: v2.1.113 native binary CLI; new **`/ultrareview` parallel multi-agent code review** (direct prior-art for ql review gate); new `/effort xhigh` for Opus 4.7; `/less-permission-prompts` skill; **Auto mode** for Max subscribers; PowerShell tool rollout; 67% faster `/resume` on 40MB+ files.

### 4e. forrestchang/andrej-karpathy-skills — 88k stars in one week

Single CLAUDE.md with 4 principles (Think Before Coding / Simplicity First / Surgical Changes / Goal-Driven Execution). Identical to ql's global CLAUDE.md. Signal: this framing is becoming canonical — ql's PRD-with-acceptance-criteria approach aligns with the trend.

### 4f. Other notable trending repos (week of 2026-04-22)

- **thedotmack/claude-mem (65k)** — SQLite+ChromaDB vector memory; auto-injects context between sessions
- **codejunkie99/agentic-stack (1.25k)** — portable `.agent/` folder for cross-tool knowledge transfer
- **browser-use/browser-harness (4.4k)** — direct Chrome DevTools Protocol access; self-healing helpers

---

## 5. Updates to prior tools (1-2 lines each)

- **Aider** — `--auto-accept-architect` flag (default true); deterministic repo-map; architect+Gemini 2.5 Pro improvements. Not within 2026-04-21..26 specifically.
- **OpenHands** — v1.6.0 (2026-03-30): Kubernetes + **Planning Mode beta** (Plan↔Code toggle, generates PLAN.md, approval before writing code). V0 removal 2026-04-01. v1.7/v1.8 unconfirmed.
- **SWE-agent** — v1.0 (2026-02-13). mini-SWE-Agent and SWE-ReX touched 2026-04-20 but no specific April release confirmed. Cognition's SWE-1.5 model is distinct.
- **Cursor** — Cursor 3 (§4c). No additional 2026-04-21..26 release beyond changelog patches.
- **Devin** — No release in window; last entry 2026-04-22 (SSO picker, MCP OAuth warnings, repo-perm decoupling). Schedule/Manage Devins (March) covered in prior survey.
- **Cline** — Apr 2026: 20 Kanban-sidebar starter prompts (dependency chains, parallel execution); a 3-agent "arena" demo. Plan/Act+YOLO unchanged. No version-tagged April release surfaced.
- **Roo Code** — No notable update; 5-mode architecture (Architect/Code/Debug/Ask/Custom) unchanged.
- **Composio agent-orchestrator** — Latest visible @composio/ao@0.2.2 (March 29). No April 2026 release confirmed (data lags). Zero-friction `ao start`, npm rename to `@composio/ao`.

---

## 6. Top-7 features quantum-loop should adopt

Ranked by leverage (impact × feasibility × P2.9/P2.10/P4 alignment).

### #1 — Spec-review subagent for planning-doc completeness (Superpowers v5.0.0)

**Mechanism:** After ql's `spec` and `plan` skills but BEFORE any executor, a subagent reads spec+plan for TBD markers, vague criteria, missing deps, unspecified files. Loop back if found.
**Gap closed:** Catches drift BEFORE stories run; cheaper failures than current post-impl detection.
**Effort:** **S** — new skill + reviewer prompt + invoke from ql-plan exit.

### #2 — Cheapest-capable-model routing per subagent (Superpowers v5.0.0)

**Mechanism:** Score story complexity (task count, dependsOn depth, security tags) and route trivial impls to Haiku/Sonnet instead of always-Opus. Detailed plans make most impls Haiku-able.
**Gap closed:** Cost and latency.
**Effort:** **S** — story-schema `complexity` field + scoring rubric + read at dispatch.

### #3 — Per-role provider routing with resolved-routing snapshot (OMC v4.12.0) — **closes P2.9**

**Mechanism:** ql stage-3 dispatch supports `--planner=claude --critic=codex --executor=gemini` with resolved choices captured in `quantum.json.routing` for reproducibility. Different providers = different failure modes = higher catch rate.
**Gap closed:** P2.9 cross-provider critic.
**Effort:** **M** — multi-runner exists; add per-stage selection + snapshot write/read + cross-provider critic prompt (use OMC's `--critic=codex` as template).

### #4 — GEPA-style skill self-evolution loop (Hermes self-evolution, ICLR 2026)

**Mechanism:** After every N successful ql runs, run GEPA over ql's own skills. Harvest execution traces → generate eval dataset → GEPA proposes prompt mutations → evaluate → constraint-filter (frontmatter valid, no >2x growth) → submit PR.
**Gap closed:** Partially closes P2.10 — evolves META-skills (how stories are decomposed/reviewed) not just per-story implementations. Higher long-term leverage.
**Effort:** **L** — trace harvesting + eval construction + GEPA integration + PR gen. Phase 1 (skill files only) is the scoped first step.

### #5 — `/ultrareview` parallel multi-agent code review (Claude Code 2.1.x)

**Mechanism:** Review gate dispatches N parallel reviewers (security + arch + style + cross-story-conflict), aggregates with dedup by file+line+message hash, presents unified verdict.
**Gap closed:** Stage-3 wave-boundary review currently fires single-perspective; multi-perspective catches more semantic issues. Mirrors OMC autopilot Phase-4 3-agent approval.
**Effort:** **M** — extend ql's spec-reviewer/quality-reviewer split to N perspectives + aggregator.

### #6 — Inline self-review checklists for routine gates (Superpowers v5.0.6)

**Mechanism:** For ROUTINE gates (typecheck/lint/test/file-org), implementer self-reviews against structured checklist in final-step prompt. Reserve subagent review for ADVERSARIAL passes (cross-story conflict, intent drift). Superpowers: 25min → 30sec.
**Gap closed:** Latency and cost on routine review; frees subagent budget for adversarial passes.
**Effort:** **S** — modify ql-execute/ql-verify prompts; remove subagent dispatch for routine portion.

### #7 — sst/opencode runner support for ql skills (§3, §4d)

**Mechanism:** ql runner registry adds `opencode` as peer to `claude`/`codex`/`gemini`. Verify `.claude/skills/` and `.agents/skills/` paths auto-discover under opencode. Fork Superpowers' opencode plugin install pattern (plugin array in `opencode.json`).
**Gap closed:** Distribution — sst/opencode is major non-Anthropic harness with Claude-compatible skills.
**Effort:** **S** — registry entry + path-discovery test + docs. Hard work done by sst already.

---

## Honorable mentions

- **EnterPlanMode intercept** (Superpowers v4.3.0) — route Claude Code `/plan` through ql brainstorm/spec. **S** hook.
- **Whole-pass plan review** (Superpowers v5.0.4) — replace chunk-by-chunk with one-shot. **S**.
- **Topic-scoped self-improve artifacts** (OMC v4.13.1) — scope `.ql-wt/` and `quantum.json` derivatives by topic for parallel runs.
- **Hermes 5-component framework** as ql's documentation taxonomy: instructions/constraints/feedback/memory/orchestration.
- **Cursor 3 prompt-side compression** — when iteration log exceeds threshold, summarize before next iter.
- **Plugin auto-update to highest satisfying git tag** (Claude Code v2.1.116) — adopt when ql ships under marketplace.

---

## Confirmability notes

- **Confirmed:** All Superpowers releases (RELEASE-NOTES + per-version blog), all OMC releases (Yeachan-Heo/oh-my-claudecode releases page), Claude Code 2.1.115-2.1.119 (releasebot.io + GitHub releases), Cursor 3 launch date 2026-04-02 (cursor.com/blog/cursor-3 + InfoQ), Devin Schedule/Manage releases (cognition.ai blog dates), Hermes Agent (NousResearch repos + ICLR 2026 GEPA citation), sst/opencode skills system (opencode.ai/docs/skills + DeepWiki).
- **Unconfirmable in window:** Specific OpenHands v1.7/v1.8 release; specific SWE-agent April 2026 release version; specific Composio April 2026 release version (page lags). Marked "no notable update" / "unconfirmed" where applicable.
- **SWE-bench leaderboard:** Claude Mythos Preview leads SWE-bench Verified at 93.9% as of 2026-04-22. Harness for that score is **not publicly disclosed** — Anthropic gated. mini-SWE-agent remains the standardized minimal-harness reference (~65% on SWE-bench Verified, 100 lines of Python).

---

## Sources (delta-window)

- [Superpowers Releases](https://github.com/obra/superpowers/releases) / [Superpowers 5 launch post](https://blog.fsck.com/2026/03/09/superpowers-5/) / [v5.0.6 post](https://blog.fsck.com/releases/2026/03/25/superpowers-v5-0-6/) / [v5.0.4 post](https://blog.fsck.com/releases/2026/03/16/superpowers-v5-0-4/) / [v4.3.0 blog](https://blog.fsck.com/agent-blog/2026/02/12/superpowers-v4-3-0/)
- [OMC Yeachan-Heo Releases](https://github.com/Yeachan-Heo/oh-my-claudecode/releases) / [v4.12.0 tag](https://github.com/yeachan-heo/oh-my-claudecode/releases/tag/v4.12.0)
- [sst/opencode docs](https://opencode.ai/docs/) / [skills](https://opencode.ai/docs/skills/) / [agents](https://opencode.ai/docs/agents) / [Superpowers for OpenCode](https://blog.fsck.com/2025/11/24/Superpowers-for-OpenCode/) / [Skills System DeepWiki](https://deepwiki.com/sst/opencode/5.7-skills-system)
- [Hermes Agent](https://hermes-agent.nousresearch.com/) / [Hermes Agent Self-Evolution (DSPy+GEPA)](https://github.com/NousResearch/hermes-agent-self-evolution) / [GitHub Trending Weekly 2026-04-22](https://www.shareuhack.com/en/posts/github-trending-weekly-2026-04-22)
- [Cursor 3 launch](https://cursor.com/blog/cursor-3) / [Cursor Marketplace blog](https://cursor.com/blog/marketplace) / [Cursor docs/skills](https://cursor.com/docs/skills) / [InfoQ Cursor 3 piece](https://www.infoq.com/news/2026/04/cursor-3-agent-first-interface/)
- [Claude Code Releases](https://github.com/anthropics/claude-code/releases) / [Releasebot Claude Code April 2026](https://releasebot.io/updates/anthropic/claude-code)
- [Devin 2026 Release Notes](https://docs.devin.ai/release-notes/2026) / [Schedule Devins](https://cognition.ai/blog/devin-can-now-schedule-devins) / [Manage Devins](https://cognition.ai/blog/devin-can-now-manage-devins)
- [Karpathy-skills repo](https://github.com/forrestchang/andrej-karpathy-skills)
- [SWE-bench leaderboard](https://www.swebench.com/) / [Mythos Preview benchmarks](https://benchlm.ai/models/claude-mythos-preview)
- [OpenHands Product Update March 2026](https://openhands.dev/blog/openhands-product-update---march-2026)
- [Composio agent-orchestrator releases](https://github.com/ComposioHQ/agent-orchestrator/releases)
- [Aider release history](https://aider.chat/HISTORY.html)
- [Cline Plan/Act DeepWiki](https://deepwiki.com/cline/cline/3.4-plan-and-act-modes)
