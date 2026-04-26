---
name: narrative-report-v2
description: Narrative handoff for quantum-loop improvement research v2 — what shipped since 2026-04-21, what's still open, recommended next-cycle Stage-2 shortlist. Produced by /research-pipeline 2026-04-26.
date: 2026-04-26
prior_run: idea-stage/PIPELINE_REPORT.md (2026-04-21)
this_run: idea-stage/PIPELINE_REPORT_v2.md (2026-04-26)
---

# Quantum-Loop Improvement Research v2 — Narrative Report

## Problem statement and core claim

**Problem**: the 2026-04-21 IDEA_REPORT prescribed a 5-tier improvement plan (P0 → P4) for quantum-loop, the BUILD layer of the AI-native-rebuild three-layer stack. Five days later, ~80% of that plan has shipped — P0 consolidation, all 7 P1 skills, all 10 P3 academic libs, 5 of the top P2 patterns, plus the first dogfood feature (`--audit`). Every measurement target is green. The question is no longer "what's broken?" but "what now?".

**Core claim**: The next-cycle highest-leverage move is **(a) an 8-item P5.A cleanup bundle** that polishes the freshly-shipped surface (OMC coupling, watchdog wiring, runner manifests, PRD hash-pinning, Sprint-Contract handoff, inline self-review, cheapest-capable-model routing) **plus (b) a single P5.B1 structural feature — per-role provider routing with resolved-routing snapshot — that closes P2.9 fully, ports OMC v4.12 as a tested upstream mechanism, and exercises multi-runner dispatch as a "bigger dogfood than --audit"**. Total scope: ~10-12 days, lands as v0.6.0.

## Method summary

Three-stream parallel research run via `/research-pipeline` (refresh mode) on 2026-04-26:

1. **Agent A — Codebase state audit** (Explore subagent): file:line analysis of the 10 skills, 36 libs, 1550-line orchestrator, plus dogfood-followups commit `c2068ff`. Output: `idea-stage/STATE_AUDIT_2026-04-26.md`. 564s wall, ~99K tokens.
2. **Agent B — Competitor delta** (general-purpose with web): post-2026-04-21 releases of Superpowers, OMC, GSD, gstack + investigation of `sst/opencode` + new harness landscape. Output: `idea-stage/COMPETITOR_DELTA_2026-04-26.md` (2,497 words). 830s wall, ~148K tokens.
3. **Agent C — Literature delta** (general-purpose with web): arXiv April-May 2026 papers across multi-agent SWE / harness scaffolds / tournament agent search / cross-provider critic / long-horizon drift / operability. Output: `idea-stage/LITERATURE_DELTA_2026-04-26.md` (2,195 words, 24 NEW papers, 5 clusters). 651s wall, ~137K tokens.

Synthesis: `idea-stage/IDEA_REPORT_v2.md` (FINAL) + `idea-stage/PIPELINE_REPORT_v2.md` (FINAL) + this narrative.

Stage 2 (implementation) deferred to next-cycle pending user Gate-1 choice. Stages 3, 4, 6 not applicable.

## Key results (with evidence)

### What shipped since 2026-04-21 (verified)

39 numbered phases across 8 PRs (#27 → #60) between 2026-04-22 and 2026-04-26:

| Tier | Items | Status | Evidence |
|---|---|---|---|
| P0 (consolidation) | 5 items | ✅ all shipped | CHANGELOG v0.4.1; `find -name "*-CPC-*" \| wc -l = 0`; `git branch -a \| wc -l = 6`; 81 archive tags |
| P1 (review/intent gap) | 7 skills | ✅ all shipped | 4 NEW skills: ql-deep-review, ql-deslop, ql-intent-check, ql-housekeep |
| P2 (external polish) | 10 patterns | ✅ 9 shipped | P2.1 wave-boundary, P2.2 over-building, P2.3 handoffs, P2.4 phase-skip, P2.5 self-review, P2.6 watchdog (lib only), P2.7 commit-trailers, P2.8 ambiguity, P2.9 dispatch logic, P2.11 reaper. **P2.10 tournament still missing.** |
| P3 (academic wedges) | 11 libs | ✅ all shipped | constitution, KBI-FAR, trajectory, hyclone, conflict-grade, tracecoder, reground, skeleton/SSAT, intent-graph, dead-code |
| P4 (AI-native ecosystem) | 6 items | ❌ blocked | Upstream Logical_inference graph-cli + soliton AgentInstruction[] schema not yet shipped |

**Dogfood**: `--audit` flag in v0.5.1 was the first real `/ql-brainstorm → /ql-spec → /ql-plan → /ql-execute` self-use. 3 findings emerged in PR #56, all fixed in PR #60 / commit `c2068ff` (ql-spec rigid question count → 2-8 adaptive; conflict-auditor false-HIGH on DAG-serialized → new "none" severity Rule 0; CLAUDE.md Git Bash/MSYS platform notes added).

### What's still open (verified)

| Item | Source | Why |
|---|---|---|
| **P2.9 cross-provider critic CLI flag** | Agent A | Dispatch logic in `lib/deep-review.sh:304` ships at tier-7 CRITICAL; no operator-facing `--critic=auto\|codex\|gemini\|none` flag |
| **Watchdog orchestrator wiring** | Agent A | `lib/watchdog.sh` ships with 32 unit tests but orchestrator has no Step 3B.3 calls |
| **Deslop language-autodetect fallback** | Agent A | Silently skips when knip/ts-prune/vulture absent |
| **OpenCode/Devin/Kiro/Goose/Cline runner manifests** | §4.4 | CHANGELOG v0.4.1 claims 12 runners; `runners/` has 7 |
| **P2.10 Tournament selection** | §1.3 | Completely unstarted (deferred for cost reasons) |
| **P4.x AI-native ecosystem** | §1.5 | Blocked on upstream |
| **Soliton bidirectional loop (P4.6)** | §1.5 | One-way reviewer-name ping; structured retry-input consumption deferred |

### NEW gaps from complexity / coupling smells

| Gap | Risk |
|---|---|
| OMC tight coupling (`lib/deep-review.sh:298-304` hardcodes 5 oh-my-claudecode:* reviewers + omc:ask-codex-critic) | quantum-loop now requires OMC; "borrow patterns" has become "depend on agents from" |
| Orchestrator at 1550 lines with 17+ wiring points | change-amplification risk |
| 36 libs with cross-coupling unclear (18 → 36 in 5 days) | refactoring/pruning risk |
| Test asymmetry: POSIX paths covered, MSYS taskkill path not unit-tested | latent regression on most-likely-broken platform |

### NEW signals from agents B + C (consensus: review is the bottleneck)

Three independent sources confirm:
- **Agent A**: P2.9 CLI gap + deslop fallback gap (reviewer surface)
- **Agent B**: Superpowers v5 spec-review-BEFORE-impl + OMC v4.12 per-role provider routing + Claude Code `/ultrareview` (industry has converged on multi-perspective review as the choke point)
- **Agent C**: 3 NEW arXiv reviewer benchmarks (CR-Bench / c-CRAB / CRA empirical), AgentV-RL bidirectional, AdverMCTS Attacker (literature has formalized the same pattern)

**Net implication**: P5 prioritization weights reviewer-tier work strongly.

### Strategic positioning (NEW from agents B + C)

- "Harness engineering" is now a named research field. **Hermes Agent (108k stars, NousResearch)** ships a 5-component framework with that exact name. **Anthropic published a 3-agent harness blueprint (2026-03-24)**. **Cursor 3 ships a Marketplace** (2026-04-02). **Claude Managed Agents** is moving the harness layer up-stack.
- **Quantum-loop fits the Hermes taxonomy** (instructions / constraints / feedback / memory / orchestration) with substantive depth advantages (DAG + intent-graph + claim-check + 1,400 tests + Iron Law + dogfood evidence).
- **6-12 months before harness-layer commoditization** per Anthropic Managed Agents trajectory. Need explicit positioning now.
- **Position for SWE-bench Pro (Claude Opus 4.5 leads at 45.9%) and HORIZON-class benchmarks**, not Verified — Verified is contamination-suspect (2512.10218). Pro and HORIZON reward orchestration where quantum-loop lives.
- **"LLM choice dominates framework choice"** (Beyond Resolution Rates 2604.02547, 9,374 trajectories) — invest in the orchestration layer (DAG / merge / conflict / trajectory / reviewer), not custom prompt-stacks. **This explicitly validates quantum-loop's M4 strategy.**

## Recommended Stage-2 (Gate-1 decision)

**Option A (recommended default)**: 10-item bundle, ~10-12 days

| Phase | Item | Effort | Risk | Closes |
|:-:|---|:-:|:-:|---|
| 1 | P5.A1 Watchdog wiring | 1d | LOW | Silent stuck-agent failure |
| 2 | P5.A2 Cross-provider critic CLI flag + fallback | 1d | LOW | P2.9 operator flag |
| 3 | P5.A3 Deslop autodetect fallback | 1d | LOW | Silent skip |
| 4 | P5.A4 Runner manifests (5 missing) | 1d | LOW | Public-claim drift |
| 5 | P5.A5 PRD hash-pinning (RAGShield L1) | 0.5d | LOW | Spec-anchored regen |
| 6 | P5.A6 Sprint-Contract handoff format | 1d | LOW | Spec faithfulness |
| 7 | P5.A7 Inline self-review checklists | 1d | LOW | 25min → 30sec on routine |
| 8 | P5.A8 Cheapest-capable-model routing | 1d | LOW | Cost / latency |
| 9 | **P5.B1 Per-role provider routing + snapshot (bigger dogfood)** | 3-5d | MEDIUM | **P2.9 full closure** |
| 10 | Dogfood retrospective + IDEA_REPORT_v3 | 0.5d | LOW | Next-cycle planning |

**Alternative options** (per `IDEA_REPORT_v2.md §9.2`): B (P5.A only, 1 week), C (P5.B1+B2+B3 reviewer-tier closure, 2 weeks), D (P5.C1+C2 frontier, 2-3 weeks), E (P5.C5 GEPA self-evolution, 3-4 weeks), F (user redirects).

## Limitations and remaining follow-up items

### Limitations of this Stage-1 pass

1. **Stage 2 not executed.** This is research, not code. Implementation requires user Gate-1 choice.
2. **Agent A direct file write failed** (environment issue); summary persisted from chat by parent orchestrator. STATE_AUDIT_2026-04-26.md is reconstituted, not directly authored.
3. **Initial draft incorrectly listed P2.9 as missing** (verified dispatch logic exists at `lib/deep-review.sh:304`); agent A refined to "dispatch shipped, CLI flag missing" — final report reflects the correct nuance.
4. **No public OpenAI/Cognition/Google DeepMind agent-harness preprint** in the April-May window — closest are AgentV-RL (verifier ensembles) and c-CRAB (cross-provider review benchmark). Coverage may be incomplete.
5. **Agent C honest gap**: no explicit "use N providers and vote" cross-provider critic paper yet published.

### Deferred decisions (for user input)

1. **Gate-1**: which Stage-2 bundle (A/B/C/D/E/F) to execute next?
2. **Bigger-dogfood scope**: is P5.B1 (per-role provider routing) the right candidate, or should the next dogfood target a different P5 item?
3. **OMC coupling stance**: graceful degrade (P5.A2 path) or full provider-agnostic registry (larger refactor)?
4. **SWE-bench Pro benchmarking**: should P5 include a CI smoke-test against quantum-loop ↔ HORIZON?

## Handoff to next stage

**If Stage 2 proceeds with Option A**:
- Run `/quantum-loop:ql-spec` on `idea-stage/IDEA_REPORT_v2.md §9` → produces a PRD for the 10-item bundle
- Run `/quantum-loop:ql-plan` → writes a new `quantum.json` with phases 1-10 as stories
- Run `/quantum-loop:ql-execute` → ships v0.6.0 in ~1-2 weeks

**If user redirects** (Option F): capture the redirected scope as a new design doc + re-run the pipeline.

**If `AUTO_WRITE=false`** (default for engineering work): this narrative is the end of the autonomous pipeline portion. Stage 6 (paper writing) skipped. Future paper framing — "Quantum-Loop: a self-using DAG harness for parallel LLM coding agents" — remains a candidate but is out of scope for this run.

---

## Companion artifacts (this run, 2026-04-26)

- `idea-stage/STATE_AUDIT_2026-04-26.md` — agent A codebase audit
- `idea-stage/COMPETITOR_DELTA_2026-04-26.md` — agent B post-2026-04-21 competitor delta (Superpowers v5, OMC v4.12, sst/opencode, Hermes, Cursor 3, Claude Code 2.1.x, Karpathy CLAUDE.md)
- `idea-stage/LITERATURE_DELTA_2026-04-26.md` — agent C 24-paper literature delta (5 clusters, top-10 recipes)
- `idea-stage/IDEA_REPORT_v2.md` — synthesized P5-tier ranked recommendations + Stage-2 shortlist (FINAL)
- `idea-stage/PIPELINE_REPORT_v2.md` — full pipeline run report (FINAL)
- `NARRATIVE_REPORT_v2.md` — this file (handoff summary)

The prior `NARRATIVE_REPORT.md` (2026-04-21) remains as historical reference.
