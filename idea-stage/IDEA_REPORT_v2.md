---
name: quantum-loop-improvement-ideas-v2
description: Refresh of IDEA_REPORT.md after the v0.4.x → v0.5.1 shipping burst. What shipped, what's still open, where the next horizon lies.
date: 2026-04-26
pipeline: research-pipeline (Stage 1, refresh of 2026-04-21 run)
status: FINAL — all 3 agent inputs received and folded in 2026-04-26
prior_pipeline_status: substantially_closed
inputs_received:
  - idea-stage/STATE_AUDIT_2026-04-26.md (agent A)
  - idea-stage/COMPETITOR_DELTA_2026-04-26.md (agent B)
  - idea-stage/LITERATURE_DELTA_2026-04-26.md (agent C)
inputs_authoritative:
  - idea-stage/IDEA_REPORT.md (prior, 2026-04-21)
  - idea-stage/AUDIT_QL.md (prior, G1-G21 catalog)
  - CHANGELOG.md (v0.0.1 → v0.5.1)
  - .omc/plans/2026-04-22-bug-and-gap-fix-plan.md (the meta-plan that drove the burst)
  - .omc/PR_READY.md, PR_READY_WIRE.md, PR_READY_AMBIGUITY.md (PR-by-PR shipping log)
  - tasks/prd-bug-gap-fix-2026-04-22.md, tasks/prd-audit-flag.md
  - docs/plans/2026-04-24-audit-flag-design.md
---

# Quantum-Loop Improvement Ideas v2 — Post-v0.5.1 Refresh

## 0. The two-line summary

The 2026-04-21 IDEA_REPORT shipped almost completely in 5 days (April 22 → April 26). P0 consolidation, all 7 P1 skills, 5 of the top P2 patterns, all 10 P3 academic libs, plus the first dogfood feature (`--audit`) — every measurement target met, 54/54 test suites green. **Three independent agent investigations (state-audit / competitor-delta / literature-delta) converge on the same finding: the reviewer is now the bottleneck, not the coder** (3 new arXiv reviewer benchmarks + Superpowers v5 spec-review subagent + OMC v4.12 per-role provider routing + Claude Code `/ultrareview` + agent A's CLI-flag gap). The recommended next-cycle Stage-2 ships an 8-item cleanup bundle plus **per-role provider routing with resolved-routing snapshot (P5.B1, ports OMC v4.12)** — closes P2.9 fully, exercises multi-runner dispatch as a "bigger dogfood than --audit", and lands ~10-12 days of work as v0.6.0.

## 1. What shipped since 2026-04-21

The April 22-26 burst landed across 8 PRs covering 21 numbered phases plus 17 follow-up phases for P3 wedges. CHANGELOG entries from v0.4.1 → v0.5.1 are coherent and the dogfood evidence under `.omc/phase-10-evidence/` shows 17 final test logs all green.

### 1.1 P0 consolidation — fully shipped

| Prior P0 item | Status | Evidence |
|---|---|---|
| P0.1 CPC → canonical promotion | ✅ | `find . -name "*-CPC-*" \| wc -l` = 0 (target met). Phase 2 commit `92b5085` promoted ~32 file pairs in one batch. |
| P0.2 ql/* branch consolidation | ✅ (revised) | `git branch -a \| wc -l` = 6 (target ≤15). Phase 4 archived 9 ql/* branches as no-op merges. 81 archive tags preserved. |
| P0.3 fix/resolve-merge-conflicts + CHANGELOG backfill | ✅ | 0 conflict markers in README; CHANGELOG covers v0.0.1 → v0.5.1 (19 entries). Plugin version reconciled to 0.5.1 across all manifests. |
| P0.4 ql-housekeep skill | ✅ | `skills/ql-housekeep/SKILL.md` shipped on `ql/research-p0-bundle`. Now used as routine pre-pipeline check. |
| P0.5 Dogfood the pipeline | ✅ | `--audit` shipped via complete `/ql-brainstorm → /ql-spec → /ql-plan → /ql-execute` cycle. Retrospective PRD + dogfood quantum.json under `.omc/phase-10-evidence/`. |

### 1.2 P1 user-stated gap closure — fully shipped

| Prior P1 item | Status | Shipped as |
|---|---|---|
| P1.1 Stage-3 cross-story + post-merge holistic review | ✅ | `lib/wave-boundary.sh` + Stage-3 in `ql-deep-review`. Cross-story constant scan, typecheck, test suite, barrel + dep-manifest regen all run at wave boundaries. |
| P1.2 Multi-perspective review aggregator | ✅ | `skills/ql-deep-review/SKILL.md` + `lib/deep-review.sh` (KBI-FAR pipeline). Risk-tiered dispatch from 2 → 7 reviewers across LOW/MEDIUM/HIGH/CRITICAL. |
| P1.3 Risk-adaptive reviewer dispatch | ✅ (Phase 12) | `lib/deep-review.sh` `compute_risk_score` + `tier_of_score` (0-100 → tier → reviewer set). |
| P1.4 Intent-drift audit (`ql-intent-check`) | ✅ (Phase 7) | `skills/ql-intent-check/SKILL.md` + `lib/intent-graph.sh`. `userIntent` snapshot at brainstorm exit; `/ql-verify` gates on drift verdict. |
| P1.5 Completion-claim linter + polite-stop ban | ✅ (Phase 5) | `lib/claim-check.sh` wired into `lib/runner.sh`. Hedge-phrase + stale-evidence + approval-without-commit detectors. |
| P1.6 Post-implementation AI-slop cleanup | ✅ (Phase 9) | `skills/ql-deslop/SKILL.md` + `lib/deslop.sh`. Scope fence to story `filePaths`; baseline+compare+rollback on regression; `--no-deslop` opt-out. |
| P1.7 Post-mortem Progress-Log generator repair | ✅ (Phase 6) | Generator emits populated row table; lessons promoted to `quantum.json.codebasePatterns`. |

### 1.3 P2 external-harness adoption — partially shipped

| Prior P2 item | Status | Notes |
|---|---|---|
| P2.1 Wave-based DAG with explicit sync-point validation | ✅ | Implemented as wave-boundary scan + dag-validator integration. |
| P2.2 Spec-reviewer over-building hunter | ✅ (Phase 13) | Spec-reviewer prompt now explicitly checks for EXTRA features beyond requested. |
| P2.3 Stage-handoff documents | ✅ (Phase 15) | `lib/handoff.sh`. Each skill writes `.handoffs/<stage>.md`. Survives compaction. |
| P2.4 Phase-skipping via artifact detection | ✅ (Phase 18) | `lib/phase-skip.sh` with sha256 fingerprints per stage; identical re-invocations short-circuit. |
| P2.5 Implementer self-review checklist | ✅ (Phase 14) | Implementer runs Completeness/Quality/Discipline/Testing self-audit before STORY_PASSED. |
| P2.6 Task watchdog + circuit breaker | ✅ (Phase 16) | `lib/watchdog.sh`. Age tiers 5/10/30 min + same-error circuit breaker. |
| P2.7 Commit trailer protocol | ✅ (Phase 14) | `lib/commit-trailers.sh`. `Constraint:`/`Rejected:`/`Directive:`/`Confidence:`/`Scope-risk:`/`Not-tested:`. |
| P2.8 Ambiguity-gated brainstorm | ✅ (Phase 19) | `lib/ambiguity.sh`. Goal/constraints/criteria scoring; challenge-mode escalation; ontology stability. |
| **P2.9 Cross-provider critic** | ✅ | CRITICAL tier (81-100) of `ql-deep-review` invokes `omc ask codex --agent-prompt critic` per `lib/deep-review.sh:304` and `agents/orchestrator.md:1285`. **Earlier draft of this report incorrectly listed as missing — corrected.** |
| **P2.10 Tournament selection** | ❌ DEFERRED | Confirmed absent. No "tournament" / "approach_family" / "best-of-N" patterns in repo. PR_READY_WIRE.md explicitly defers ("high cost for the common case"). |
| P2.11 Orphan-subprocess reaping | ✅ (Phase 20) | `lib/reaper.sh`. Platform-aware kill (POSIX setsid / MSYS taskkill), durable pidfiles. |

### 1.4 P3 academic wedges — fully shipped (v0.5.0)

All 10 ranked recipes from `LITERATURE_SURVEY.md` Tier-S/A landed as separate libs with consistent contract (no shell flags at source time, CLI block enables strict mode, env-var tunables, readonly arrays guarded against re-source):

| Lib | P3 ID | Paper | Shipped |
|---|---|---|---|
| `lib/skeleton.sh` | P3.1 SSAT | arXiv:2303.06689 + 2511.03404 | ✅ Phase 31 |
| `lib/conflict-grade.sh` | P3.2 ConGra | arXiv:2409.14121 | ✅ Phase 26 |
| `lib/deep-review.sh` (far_filter) | P3.3 KBI-FAR | arXiv:2505.17928 | ✅ Phase 23 |
| Same lib (actionability gate) | P3.4 | arXiv:2604.03196 | ✅ Phase 23 |
| `lib/trajectory.sh` | P3.5 trajectory kill | arXiv:2511.00197 + 2603.24631 | ✅ Phase 24 |
| `lib/intent-graph.sh` | P3.6 SCF | arXiv:2604.16339 + 2604.11209 | ✅ Phase 32 |
| `lib/hyclone.sh` | P3.7 HyClone | arXiv:2508.01357 | ✅ Phase 25 |
| `lib/tracecoder.sh` | P3.8 OAR | arXiv:2602.06875 | ✅ Phase 27 |
| `lib/reground.sh` | P3.9 reground | arXiv:2603.00492 | ✅ Phase 28 |
| `lib/dead-code.sh` | P3.10 DePA-style | arXiv:2604.07291 + arXiv:2502.20246 | ✅ Phase 33 |
| `lib/constitution.sh` | P3.11 Constitutional | arXiv:2602.02584 | ✅ Phase 22 |

All 11 wired into the orchestrator at 17+ integration points (`agents/orchestrator.md`). Wiring assertions tracked by `test_orchestrator_wiring.sh` (30 assertions covering Steps 1C / 3A.1 sub-5 / 3A.3 / 3A.5C-E / 3A.6 / 3B.3 / 3C.NEG0 / 3C.NEG1 / 4B.5).

### 1.5 P4 AI-native-rebuild integration — still blocked

| P4 item | Status |
|---|---|
| P4.1 Consume FeaturePartition + ContextPack from Logical_inference | ❌ Blocked on upstream graph-cli ship |
| P4.2 Emit EvidenceBundle per merged PR | ❌ Schema v0.1 exists; no emitter wired |
| P4.3 SLSA v1.0 + in-toto attestations | ❌ Roadmap only |
| P4.4 Behavioral-replay harness (`skills/ql-replay`) | ❌ Not started |
| P4.5 Feature-partition-aware PR chunking | ❌ Not started |
| P4.6 Soliton AgentInstruction[] feedback loop | ❌ One-way ping only — `lib/deep-review.sh:298,302` references `soliton:synthesizer` as a reviewer name string but does NOT consume soliton's structured `AgentInstruction[]` retry-input. The "close-the-loop" half is missing. |

## 2. What's still open from the prior plan

| Item | Tier | Status | Rationale |
|---|---|---|---|
| **P2.10 Tournament selection + re-benchmark-on-merge** | P2 | DEFERRED | Cost-prohibitive default; opt-in per-story future option |
| **P4.1-P4.5 AI-native ecosystem integration** | P4 | BLOCKED | Upstream Logical_inference graph-cli + soliton AgentInstruction[] not yet shipped |
| **P4.6 Soliton bidirectional feedback** | P4 | PARTIAL | One-way reviewer-name ping exists; structured retry-input consumption missing |
| **OpenCode / Devin / Kiro / Goose runner manifests** | (new) | GAP | CHANGELOG v0.4.1 lists these as supported runners but `runners/` only has 7 manifests (aider, amp, claude, codex, copilot, cursor, gemini). 5 claimed runners have no manifest. |
| **Watchdog → reaper migration** | (honest follow-up) | OPEN | PR_READY_AMBIGUITY.md flagged: `lib/watchdog.sh:4` still references `kill_agent_process`; should migrate to `reap_agent`. Dual code paths. |
| **Reaper Windows-binary unit test** | (honest follow-up) | OPEN | Taskkill path exercised only at runtime; no live `claude.exe` fixture. |
| **Agent-tool grandchildren PID capture** | (Anthropic dependency) | OPEN | Subagents spawning more claude via Bash tool aren't tracked in pidfile; reap_orphans catches after `$REAPER_STALE_SECS`. True fix requires Anthropic to expose PID hook. |

## 3. Dogfood findings — what real self-use revealed

The audit-flag dogfood (PR #56, May 24-26 cycle) exercised the full pipeline end-to-end on a small feature. Three findings emerged in the PR body and were acted on in PR #60 / commit `c2068ff`:

### 3.1 ql-spec question count was rigid (FIXED)
Old rule: "Minimum 5 questions, maximum 8." Padding to hit the floor produced release-ops / non-goal questions the design doc already answered. **Fix**: 2-8 adaptive based on residual ambiguity; "count-quality test" added per question.

### 3.2 conflict-auditor missed DAG-serialized conflicts (FIXED)
Old rules tagged 2+ stories editing the same file as `medium`/`high` even when an explicit `dependsOn` chain prevented concurrent edits. **Fix**: new Rule 0 — if every pair in the conflict set has direct-or-transitive `dependsOn`, classify as `none` (informational). 4-story audit-flag feature had previously triggered a false high.

### 3.3 Git Bash / MSYS platform gotchas (FIXED)
Heredoc CRLF endings, subshell exit-code capture under `set -uo pipefail`, `local -n` 4.3+ requirement, lexicographic vs `sort -V` on `phase-N` dirs. All four were real bugs hit during #56 / #59 execution. CLAUDE.md now has a Platform Notes section (commit `c2068ff`).

**Meta-finding**: dogfooding a 4-story trivial feature found 3 real issues. Larger features with parallel waves will likely surface more — the dogfood loop is now the system's primary self-improvement source.

## 4. NEW gaps surfaced by complexity / coupling smells

These are problems the prior IDEA_REPORT did not name because they only emerge from the freshly-shipped breadth. Validated by spot-grep; agent A is doing the deeper structural audit.

### 4.1 Heavy OMC dependency (NEW)
`lib/deep-review.sh` lines 298-304 hardcode reviewer names from the `oh-my-claudecode:*` namespace (`code-reviewer`, `security-reviewer`, `test-engineer`, `critic`, `architect`) plus `omc:ask-codex-critic`. Quantum-loop now requires OMC to be installed for `ql-deep-review` to work.
- **Risk**: prior survey treated OMC as "borrow patterns from"; we shipped as "depend on agents from". Materially different coupling level.
- **Mitigation candidates**: (a) provider-agnostic agent registry with fallback, (b) opt-in OMC-rich path with graceful degrade to built-in reviewers, (c) explicit feature gate on `omc:` runtime detection.

### 4.2 Orchestrator agent at 1285+ lines with 17+ wiring points (NEW)
The orchestrator now owns: init-guard, watchdog, reaper, reground, skeleton preview, tracecoder OAR wrapper, dead-code scan, intent-graph drift, skeleton diff, commit trailers, trajectory monitor, hyclone wave-boundary, conflict-grade routing, wave-boundary cross-story, deep-review tier dispatch, phase-skip fingerprints, claim-check transitive, deslop scope-fence — each at distinct steps (1C / 3A.1 / 3A.3 / 3A.5B-E / 3A.6 / 3B.3 / 3C.NEG0 / 3C.NEG1 / 4B.5).
- **Risk**: change amplification. A small wiring tweak can break multiple downstream gates. `test_orchestrator_wiring.sh` has 30 assertions to prevent silent regressions, but the prompt-side complexity is opaque.
- **Mitigation candidates**: (a) factor prompt into named "phase modules" with explicit contracts, (b) generate orchestrator from a manifest, (c) pull integration registration into a small `lib/wirings.sh` table.

### 4.3 36 lib modules with cross-coupling unclear (NEW)
The lib count went from 18 → 36 in 5 days. Some libs are truly leaf (constitution, conflict-grade, dead-code) but others (deep-review, deslop, wave-boundary) reach across multiple peers. Coupling map not documented.
- **Risk**: refactoring or pruning risk; Phase 17 PR_READY explicitly flagged "intentionally NOT wired in orchestrator: handoff.sh (skill-side ownership), claim-check.sh (already transitive via runner.sh)" — these intentional non-wirings need durable documentation, otherwise next iteration re-wires them.
- **Mitigation candidates**: (a) auto-generate `docs/lib-coupling.md` from `source` statements, (b) declare lib responsibilities in a header comment grammar a parser can extract.

### 4.4 OpenCode/Devin/Kiro/Goose runner gap (small)
CHANGELOG v0.4.1 line 76 lists 12 supported runners. `runners/` has 7 manifests. The 5 missing manifests (opencode, devin, kiro, goose, cline) violate the public claim.
- **Risk**: marketing/credibility; users invoking unmanifested runners get cryptic failures.
- **Mitigation candidates**: (a) ship 5 stub manifests with `experimental: true`, (b) trim CHANGELOG claim to match shipped state.

### 4.5 Watchdog wiring missing + reaper dual paths (UPGRADED — agent A)
Agent A (state audit, 2026-04-26) confirmed: `lib/watchdog.sh` ships with ~32 unit-test assertions but the orchestrator does NOT call into it. PR_READY_WIRE.md claimed Step 3B.3 wired watchdog "alongside trajectory" but agent A's read of the actual `agents/orchestrator.md` could not locate the call sites. Compounding: `lib/watchdog.sh:4` still references the legacy `kill_agent_process` from `lib/monitor.sh`; modern platform-aware path is `lib/reaper.sh`.
- **Risk**: silent failure mode — circuit-breaker logic exists in lib but never fires at runtime; long-running stuck agents won't get killed by the documented mechanism.
- **Mitigation**: 2-3 step additions to orchestrator.md to wire watchdog age tiers + circuit breaker; migrate watchdog's internal calls from `kill_agent_process` to `reap_agent`. ~1 day total.

### 4.7 Claim-check transitive-only (NEW — agent A)
Agent A noted: `lib/claim-check.sh` exists with 17 integration tests, intentionally transitive via `lib/runner.sh` per PR_READY_WIRE.md ("intentionally NOT wired in orchestrator"). This is by design but reduces orchestrator visibility — future maintainers reading orchestrator.md may not realize hedge-phrase rejection is happening.
- **Risk**: low (it works); medium (documentation-discoverability)
- **Mitigation**: comment block in orchestrator.md citing PR_READY_WIRE rationale; link to lib/claim-check.sh.

### 4.6 Test coverage of platform-specific paths is asymmetric
PR_READY_AMBIGUITY explicitly flagged "Reaper taskkill path isn't unit-tested against a live Windows binary." The test suite exercises POSIX paths via `sleep` fixtures but the MSYS path runs only at runtime. Latent regression risk on the most-likely-broken platform.
- **Mitigation**: cross-platform test fixture or smoke test in CI.

## 5. Fresh competitor signals (agent B output — DONE)

Full report: `idea-stage/COMPETITOR_DELTA_2026-04-26.md` (deeper than prior survey because the window saw extraordinary movement).

### 5.1 Five-bullet summary

1. **Superpowers v4.2 → v5.0.7** (two majors + seven patches). Three mechanisms matter: **mandatory subagent-driven dev with cheapest-capable-model routing** (Haiku for impl after detailed plans), **spec-review subagent that fires AFTER planning but BEFORE impl** (audits TBD/incompleteness; quantum-loop's spec-reviewer is post-impl), **inline self-review checklists** that replaced subagent loops and cut review time **~25 min → ~30 sec**.
2. **OMC v4.11.3 → v4.13.4** (8 patches/minors). Headline: **v4.12.0 per-role provider routing with resolved-routing snapshots** (planner=Claude / critic=Codex / executor=Gemini, choice captured for reproducibility) — **closes quantum-loop's P2.9 directly** as a port. Also: v4.13.0 autoresearch-as-a-skill migration (skill = composition unit pattern); v4.13.1 cursor-agent as 4th tmux worker; topic-scoped artifacts.
3. **sst/opencode (user's "oh-my-opencode") is now a first-class skills target.** Native `skill` tool auto-discovers from `.claude/skills/`, `.opencode/skills/`, `.agents/skills/`. Superpowers IS already ported (since 2025-11-24). **Near-zero-cost expansion target for quantum-loop** (4f).
4. **NEW harness landscape**:
   - **NousResearch/hermes-agent (108k stars, first OSS agent crossing 100k in 2026)** — names "Harness Engineering" as a framework with 5 components (instructions / constraints / feedback / memory / orchestration). Quantum-loop fits this taxonomy.
   - **Hermes self-evolution (DSPy + GEPA, ICLR 2026 oral)** — "Reflective" prompt evolution: reads execution traces to understand WHY failures occur, proposes targeted improvements at $2-10 per run, no GPU. **Distinct from OMC self-improve tournament** — GEPA evolves *meta-skills*, not implementations.
   - **Cursor 3 (2026-04-02)** — Agents Window, Marketplace, parallel agents across local/cloud/SSH/worktree, RL-trained self-summarization 5000 → 1000 tokens.
   - **Claude Code 2.1.119 (2026-04-24)** — `/ultrareview` parallel multi-agent code review (direct prior-art for quantum-loop's review gate), `/effort xhigh`, plugin auto-update to highest satisfying git tag, native binary CLI.
   - **forrestchang/andrej-karpathy-skills (88k stars in 1 week)** — 4-principle CLAUDE.md (Think Before Coding / Simplicity First / Surgical Changes / Goal-Driven Execution) is now de facto canon. Quantum-loop's CLAUDE.md aligns.
5. **Strategic positioning shift**: "harness engineering" is now a named field with public industry frameworks (Hermes, Anthropic 3-agent harness, Cursor 3 Marketplace, OMC). Quantum-loop has substantive depth advantages (DAG + intent-graph + claim-check + 1,400 tests) but the field is moving fast — P5 work needs explicit strategy now.

### 5.2 Top-7 from agent B

1. **Spec-review subagent BEFORE impl** (Superpowers v5.0.0) — S effort
2. **Cheapest-capable-model routing per subagent** (Superpowers v5.0.0) — S effort
3. **Per-role provider routing with resolved-routing snapshot** (OMC v4.12.0) → **closes P2.9** — M effort
4. **GEPA-style skill self-evolution** (Hermes, ICLR 2026) → partially closes P2.10 — L effort
5. **`/ultrareview` parallel multi-agent code review** (Claude Code 2.1.x) — M effort
6. **Inline self-review checklists for routine gates** (Superpowers v5.0.6) — S effort
7. **sst/opencode runner support** for quantum-loop skills (§3, §4d) — S effort

### 5.3 Honorable mentions (small, useful)

- **EnterPlanMode intercept** (Superpowers v4.3.0) — route Claude Code `/plan` through ql brainstorm/spec
- **Whole-pass plan review** (Superpowers v5.0.4) — replace chunk-by-chunk
- **Topic-scoped self-improve artifacts** (OMC v4.13.1) — scope `.ql-wt/` and quantum.json derivatives by topic
- **Hermes 5-component framework** as quantum-loop's documentation taxonomy
- **Cursor 3 prompt-side compression** — summarize iteration log when threshold exceeded

## 6. Fresh literature signals (agent C output — DONE)

Full report: `idea-stage/LITERATURE_DELTA_2026-04-26.md` (24 NEW papers, 5 thematic clusters, top-10 recipes).

### 6.1 Five executive bullets

1. **The April-2026 cohort moves from "build the agent" to "evaluate / govern the agent."** Three new reviewer benchmarks (CR-Bench 2603.11078, c-CRAB 2603.23448, CRA empirical 2604.03196) + two long-horizon failure benchmarks (HORIZON 2604.11978, SLUMP 2603.17104). **Review noise and cross-step intent drift are the binding constraints, not raw generation skill.**
2. **A new sub-genre — "tournament agent search" — is now publishable.** AgentGA (2604.14655) introduces deterministic 1:1 elite tournaments over "agent-seed space" with 1,135 validated parent-child runs. **Direct fit for quantum-loop's P2.10 gap.**
3. **Anthropic shipped a public three-agent harness blueprint** (engineering blog, 2026-03-24): Planner / Generator / Evaluator with structured **Sprint-Contract handoffs**. Closest production analogue to quantum-loop's six-skill pipeline. **Two specific imports**: (a) Sprint-Contract JSON between ql-plan and ql-execute, (b) Playwright functional-eval as third independent signal.
4. **Cross-model verifier ensembles became table-stakes.** AgentV-RL (2604.16004) forward+backward verifiers; AgentForge (2604.13120) Docker-sandboxed before propagation; AdverMCTS (2604.10449) Solver-vs-Attacker. **All three are templates for P2.9.**
5. **SWE-bench: position for Pro, not Verified.** Verified is now contamination-suspect (2512.10218); Pro leader is 45.9% (Claude Opus 4.5). The Verified-vs-Pro gap doubled this month. **Pro and HORIZON-class benchmarks reward the orchestration layer where quantum-loop lives.**

### 6.2 Cross-cluster synthesis (4 themes mapped to gaps)

1. **The reviewer is the bottleneck, not the coder.** (D3.x) → P2.9 cross-provider critic. Action: split quality-reviewer into KBI/FAR + bidirectional (forward+backward) verifier + Attacker agent. Estimated **+20 pp signal-to-noise**.
2. **Tournaments / lineages will become the dominant scaling axis.** (D2.x) → P2.10 tournament/re-benchmark. Action: archive + 1:1 elite tournament; pair with `oh-my-claudecode:self-improve`.
3. **Long-horizon drift is now formally measurable.** (D4.x) → existing `lib/intent-graph.sh` + `lib/trajectory.sh`. Action: ship a quantum-loop ↔ HORIZON evaluator script as CI smoke test.
4. **Operational reliability — rate limits, replay, provenance — is first-class research.** (D5.x) → P4 ecosystem + dogfood. Action: ship `bin/quantum-proxy.sh` (HiveMind), hash-pin PRDs (RAGShield L1), publish as Skilldex package.

### 6.3 Top-10 recipes ranked (from agent C)

| # | Recipe | Source | Gap | Effort |
|---|---|---|---|---|
| 1 | **1:1 elite tournament over agent-seed archives.** Per-story `archive/`; failed re-runs use parent archive in prompt; child competes 1:1 vs same-lineage elite. | AgentGA 2604.14655 | P2.10 | M |
| 2 | **Bidirectional reviewer.** New `agents/inverse-spec-reviewer.md` derives implied-spec from code and diffs against ACs. | AgentV-RL 2604.16004 | P2.9 | S-M |
| 3 | **Adversarial test generator ("Attacker") agent.** New story-type `stress-test`: 3-5 corner-case tests for any merged story. Targets Bash heredoc/CRLF class. | AdverMCTS 2604.10449 | dogfood | M |
| 4 | **HiveMind-style provider proxy.** `bin/quantum-proxy.sh`: admission control + AIMD + per-runner token budget. | HiveMind 2604.17111 | dogfood scaling | M |
| 5 | **Per-task sandboxed verification.** Promote test runs from after-story to after-task; block file-write commit if sandbox fails. | AgentForge 2604.13120 + SolidCoder 2604.19825 | Iron-Law | M |
| 6 | **PRD hash-pinning (RAGShield Level-1).** Each story gets `prdSha`; orchestrator invalidates downstream stories on hash change. | RAGShield 2604.00387 | spec-anchored regen | S |
| 7 | **Pre-commit belief-audit gate.** Regenerate intent from diff before commit; reject if diverges from quantum.json ACs. | SAVeR 2604.08401 | drift mitigation | M |
| 8 | **Sprint-Contract handoff artefact.** Per-story JSON written by ql-plan, consumed by ql-execute and ql-review. Mirrors Anthropic Generator↔Evaluator contract. | Anthropic 2026-03-24 | spec faithfulness | S-M |
| 9 | **Repeated-evaluation voting** for `criticality: high` stories: 3× parallel re-runs, majority-vote on diff equivalence, require unanimous review-pass. | CUA Reliability 2604.17849 | dogfood reliability | M |
| 10 | **Publish quantum-loop as Skilldex package + benchmark vs c-CRAB.** Fixes long-tail Anthropic skills/MCP integration. | Skilldex 2604.16911 + c-CRAB 2603.23448 | P4 ecosystem | S |

### 6.4 Strategic positioning insight (Beyond Resolution Rates 2604.02547)

**"LLM choice dominates framework choice"** once the LLM is strong (9,374 trajectories / 19 agents / 14 LLMs studied). Implication: quantum-loop should invest in the **orchestration layer** (DAG, merge, conflict grader, trajectory monitor) where moats compound — NOT in custom prompt-stacks the next model will obsolete. Validates the M4 complexity-moat strategy explicitly.

### 6.5 Honestly-flagged gaps (agent C)

- No explicit "use N providers and vote" cross-provider critic paper yet published; closest are AgentV-RL (D3.3) and c-CRAB (D3.2)
- No new OpenAI / Cognition / Google DeepMind agent-harness preprint in the window — Cognition trail goes quiet after Devin 2.x

## 7. Ranked improvement ideas — next-cycle (P5 tier, FINAL)

Cross-validated against agents A, B, C. **The reviewer is the bottleneck** is a 3-source signal (A: cross-provider gap; B: Superpowers v5 + OMC v4.12 + Claude Code `/ultrareview`; C: 3 new reviewer benchmarks + bidirectional + Attacker). P5 prioritization reflects this.

### Tier P5.A — Cleanup bundle (~1 week, S effort each, LOW risk)

| ID | Idea | Source | Closes |
|---|---|---|---|
| **P5.A1** | **Watchdog orchestrator wiring** — wire Step 3B.3 age-tier (5/10/30 min) + circuit breaker; migrate watchdog's internal calls from `kill_agent_process` to `reap_agent`. | Agent A weakness #1 | Silent-failure mode in stuck-agent detection |
| **P5.A2** | **Cross-provider critic CLI flag + fallback** — `--critic=auto\|codex\|gemini\|none` with availability detection; fallback when codex/gemini absent. | Agent A weakness #2 | P2.9 operator-facing flag |
| **P5.A3** | **Deslop language-autodetect regex fallback** — when knip/ts-prune/vulture absent, use `lib/dead-code.sh` regex paths. | Agent A weakness #3 | Silent-skip when tooling missing |
| **P5.A4** | **Runner manifest gap close** — ship `opencode/devin/kiro/goose/cline.json` manifests; trim CHANGELOG claim to match actual support. | §4.4 + Agent B #7 | Public-claim drift |
| **P5.A5** | **PRD hash-pinning (RAGShield L1)** — add `prdSha` per story in quantum.json; orchestrator invalidates downstream stories on hash change. | Agent C #6 | Spec-anchored regen |
| **P5.A6** | **Sprint-Contract handoff format** — extend `lib/handoff.sh` with per-story JSON written by ql-plan, consumed by ql-execute and ql-review. Mirrors Anthropic Generator↔Evaluator. | Agent C #8 + B Anthropic blog | Spec faithfulness across stages |
| **P5.A7** | **Inline self-review checklists for routine gates** — replace subagent dispatch on routine typecheck/lint/test/file-org with structured inline checklists in implementer/verifier prompts. Reserve subagents for adversarial review. | Agent B #6 (Superpowers v5.0.6) | 25min → 30sec on routine review |
| **P5.A8** | **Cheapest-capable-model routing per task** — story-schema `complexity` field (task count × dependsOn depth × security tags); route trivial impls to Haiku/Sonnet. | Agent B #2 (Superpowers v5.0.0) | Cost + latency |

### Tier P5.B — High-leverage structural (~1-2 weeks, medium risk)

| ID | Idea | Source | Closes |
|---|---|---|---|
| **P5.B1** | **Per-role provider routing with resolved-routing snapshot** — port OMC v4.12.0 mechanism: `quantum.json.routing` captures planner/critic/executor provider choices for reproducibility. | Agent B #3 (OMC v4.12.0) | **Closes P2.9 fully** |
| **P5.B2** | **Bidirectional reviewer (forward + backward verifier)** — new `agents/inverse-spec-reviewer.md` derives implied-spec from code and diffs against ACs. Wired in parallel with existing spec-reviewer. | Agent C #2 (AgentV-RL 2604.16004) | Reviewer recall (+25.2% over SoTA at 4B per paper) |
| **P5.B3** | **`/ultrareview` parallel multi-agent review pattern** — extend ql-deep-review to dispatch N parallel reviewers (security + architecture + style + cross-story-conflict) with hash-aggregator (file+line+message). | Agent B #5 (Claude Code 2.1.x) | Stage-3 multi-perspective depth |
| **P5.B4** | **Spec-review subagent BEFORE impl** — fires after ql-plan, before ql-execute. Reads spec + plan for TBDs / vague criteria / missing deps. Loops back if found. **Distinct from current post-impl spec-reviewer.** | Agent B #1 (Superpowers v5.0.0) | Catches drift before stories run (cheaper than post-impl detection) |
| **P5.B5** | **AgentGA 1:1 elite tournament for measurable stories** — per-story `archive/`; failed re-runs use parent archive in prompt; child competes 1:1 vs same-lineage elite (NOT random pairings). Opt-in per story via `criticality: tournament`. | Agent C #1 (AgentGA 2604.14655) | **Closes P2.10** (deferred for cost reasons; opt-in keeps cost bounded) |

### Tier P5.C — Frontier (~3-6 weeks, exploratory)

| ID | Idea | Source | Notes |
|---|---|---|---|
| **P5.C1** | **Adversarial test generator ("Attacker") agent** — new story-type `stress-test`; 3-5 corner-case tests for any merged story; failures route back to author. | Agent C #3 (AdverMCTS 2604.10449) | Targets dogfood Bash heredoc/CRLF class bugs |
| **P5.C2** | **HiveMind-style provider proxy** — `bin/quantum-proxy.sh`: admission control + AIMD backpressure + per-runner token budget. | Agent C #4 (HiveMind 2604.17111) | 72-100% → 0-18% failure rate at scale |
| **P5.C3** | **Per-task sandboxed verification** — promote test runs from after-story to after-task; block file-write commit if sandbox fails. | Agent C #5 (AgentForge + SolidCoder) | Iron-Law tightening |
| **P5.C4** | **Pre-commit belief-audit gate** — regenerate intent from diff before commit; reject if diverges from quantum.json ACs. | Agent C #7 (SAVeR 2604.08401) | Drift mitigation |
| **P5.C5** | **GEPA-style skill self-evolution** — after every N successful runs, GEPA over quantum-loop's own skills. Harvest traces → eval dataset → mutations → constraint-filter → PR. | Agent B #4 (Hermes, ICLR 2026 oral) | Partially closes P2.10 (META-skill, not impl) |
| **P5.C6** | **Repeated-evaluation voting for high-stakes stories** — `criticality: high` re-runs 3× via parallel runner; majority-vote on diff equivalence; require unanimous review-pass. | Agent C #9 (CUA Reliability 2604.17849) | Reliability under stochasticity |
| **P5.C7** | **Publish quantum-loop as Skilldex package + benchmark vs c-CRAB** — fixes long-tail Anthropic skills/MCP integration. | Agent C #10 (Skilldex + c-CRAB) | P4 ecosystem partial |
| **P5.C8** | **Bigger dogfood than --audit** — exercise pipeline on a non-trivial feature (≥8 stories, multiple waves). Recommended candidate: P5.B1 itself (per-role provider routing) — touches dispatch, schema, runner registry, deep-review. | Cross-cycle | Surfaces parallel-wave issues that audit-flag was too small to find |

## 8. Anti-recommendations (explicit "do not do this")

- **Do not** invest in P4 ecosystem code until upstream Logical_inference graph-cli + soliton AgentInstruction[] are released. Build integration glue then, not now.
- **Do not** add new lib modules until 4.3 (coupling map) is in place. The current rate of lib growth (18 → 36 in 5 days) is not sustainable without explicit responsibility/dependency tracking.
- **Do not** ship Live-SWE-agent-style runtime self-evolution patterns (arXiv:2511.13646). The orchestrator is already complex; agents mutating their own scaffold on this base is an incident generator. Defer until 4.2 (orchestrator factor) lands.
- **Do not** dogfood another *trivial* feature next. The audit-flag was a 4-story linear chain; the next dogfood must stress parallel waves and cross-story contracts to find the real issues.
- **Do not** widen OMC coupling further. Every new `oh-my-claudecode:*` reference compounds 4.1.

## 9. Recommended Stage-2 shortlist (FINAL)

**Recommended Stage-2 bundle (1-2 weeks)**: ship P5.A entire (8 items, all S-effort) + **P5.B1 per-role provider routing with snapshot** as the bigger dogfood. Rationale:

- **P5.A bundle** addresses 4 weaknesses agent A surfaced + 4 quick literature/competitor wins. All S-effort, single-day each, low risk. Together they polish v0.5.1 to v0.6.0.
- **P5.B1 (per-role provider routing)** is the highest-leverage single feature: it closes P2.9 fully, uses OMC v4.12 as a tested upstream mechanism, exercises multi-runner/dispatch/schema/deep-review (good "bigger dogfood" candidate), and produces visible operator-facing capability. Estimated 3-5 days plus cross-runner integration tests.

**Why NOT B5 (AgentGA tournament) or C5 (GEPA) yet**: both are higher-leverage long-term but require more ground work — AgentGA needs a story-archive schema; GEPA needs trace harvesting + eval construction. Sequence them after P5.A + P5.B1 land and after a "bigger dogfood" surfaces real failure modes.

**Why NOT B4 (spec-review-before-impl) yet**: Superpowers ships it but quantum-loop's existing spec-reviewer is post-impl and the wave-boundary cross-story scan partially compensates. Adding pre-impl spec-review is a B2-cycle ROI question — defer to next round after measuring drift in current state.

### 9.1 Stage-2 detailed shortlist (final)

| Phase | Item | Effort | Risk | Closes |
|:-:|---|:-:|:-:|---|
| 1 | P5.A1 Watchdog wiring | 1d | LOW | Silent stuck-agent failure |
| 2 | P5.A2 Cross-provider critic CLI flag + fallback | 1d | LOW | P2.9 operator flag |
| 3 | P5.A3 Deslop autodetect fallback | 1d | LOW | Silent skip |
| 4 | P5.A4 Runner manifests (5 missing) | 1d | LOW | Public-claim drift |
| 5 | P5.A5 PRD hash-pinning | 0.5d | LOW | Spec-anchored regen |
| 6 | P5.A6 Sprint-Contract handoff format | 1d | LOW | Spec faithfulness |
| 7 | P5.A7 Inline self-review checklists | 1d | LOW | 25min → 30sec on routine |
| 8 | P5.A8 Cheapest-capable-model routing | 1d | LOW | Cost / latency |
| 9 | **P5.B1 Per-role provider routing + snapshot (bigger dogfood)** | 3-5d | MEDIUM | **P2.9 full closure** |
| 10 | Dogfood retrospective + IDEA_REPORT_v3 | 0.5d | LOW | Next-cycle planning |

**Total**: ~10-12 days = 2-3 weeks at single-developer pace, or 1 week with parallel waves on P5.A items 1-4 and 5-8 grouped.

### 9.2 Alternative shortlist (user override option)

| Option | Bundle | Why |
|---|---|---|
| **A (recommended above)** | P5.A entire + P5.B1 | Highest near-term leverage; closes P2.9; reasonable scope |
| B | P5.A only | If user wants pure cleanup before any new feature |
| C | P5.B1 + P5.B2 + P5.B3 | If user wants reviewer-tier closure (P2.9 + bidirectional + ultrareview) |
| D | P5.C1 + P5.C2 | If user wants frontier (Attacker + HiveMind proxy) |
| E | P5.C5 (GEPA self-evolution) only | If user wants the highest-novelty research wedge |
| F | Skip Stage-2; user redirects | — |

## 10. Measurement plan — next cycle

Building on `IDEA_REPORT.md §6` measurements (all currently green per v0.5.1 audit):

| Metric | Current | Target |
|---|---:|---:|
| Local branches | 1 (master only) | ≤ 5 |
| Orphan worktrees | 0 | 0 |
| CPC-pattern files | 0 | 0 |
| README conflict markers | 0 | 0 |
| Test suites green | 54/54 (~1,400 tests) | 100% |
| Plugin version coherence | 0.5.1 across all manifests | aligned |
| `quantum.json.updatedAt` days stale | 2 (current) | ≤ 7 |
| `codebasePatterns` entries from this cycle | TBD | ≥ 3 |

**New metrics to add for the next cycle:**

| Metric | Why | Source |
|---|---|---|
| OMC-namespace references in lib/ + skills/ | tracks coupling reduction (4.1) | `grep -c oh-my-claudecode lib/*.sh skills/**/*.md` |
| Lib import depth (max chain) | tracks coupling map (4.3) | static analysis of `source` statements |
| Orchestrator integration-point count | tracks complexity (4.2) | `test_orchestrator_wiring.sh` assertion count |
| Runner manifest coverage (manifested / claimed) | tracks 4.4 | manual count vs CHANGELOG list |
| Dogfood feature size (stories / waves) | tracks 4.7 (next cycle) | next dogfood manifest |

## 11. Strategic context (UPDATED post-agents)

Quantum-loop remains the **BUILD layer** of the AI-native-rebuild three-layer stack (UNDERSTAND = Logical_inference, BUILD = quantum-loop, REVIEW = soliton). Its asserted moats — M1 EvidenceBundle (still TODO; partial via RAGShield L1 in P5.A5), M4 complexity moat (DAG + parallel worktree + Iron Law + anti-rationalization, now stronger after P3 + P2 polish) — remain on the strategic roadmap.

**Strategic shift since v1**: quantum-loop is now genuinely self-using. The v0.5.1 cycle dogfooded the pipeline end-to-end and 3 real issues were caught and fixed within 2 days. M4 moat is **empirically validated, not rhetorical**.

**NEW strategic context from agent B**: "harness engineering" is now a named research field. Hermes Agent (108k stars) ships a 5-component framework with that exact name (instructions / constraints / feedback / memory / orchestration). Anthropic published a 3-agent harness blueprint (2026-03-24). Cursor 3 ships a Marketplace. **Quantum-loop fits the Hermes taxonomy with substantive depth advantages** (DAG + intent-graph + claim-check + 1,400 tests + Iron Law + dogfood evidence) but the field is moving fast — quantum-loop has **6-12 months before the harness layer is commoditised** (per Anthropic Managed Agents trajectory). P5 work needs explicit positioning.

**NEW strategic context from agent C**: "LLM choice dominates framework choice" once LLM is strong (Beyond Resolution Rates 2604.02547, 9,374 trajectories studied). Implication: **invest in the orchestration layer** (DAG / merge / conflict grader / trajectory monitor / reviewer-stack) where moats compound — NOT in custom prompt-stacks the next model will obsolete. **This explicitly validates quantum-loop's M4 strategy.**

**Position for SWE-bench Pro, not Verified.** Verified is contamination-suspect (2512.10218 + 2506.12286); Pro leader is 45.9% (Claude Opus 4.5). Pro and HORIZON-class benchmarks reward orchestration. **Recommend running quantum-loop ↔ HORIZON evaluator script as next-cycle CI smoke test** (not in P5.A but listed as P5.C7 frontier).

**Biggest near-term strategic risks**:
1. **OMC coupling without graceful fallback** (§4.1) — fixed by P5.A2 + P5.B1 (ports OMC v4.12 explicitly with snapshot capture rather than implicitly depending).
2. **Harness layer commoditization** in 6-12 months — mitigation is to ship the differentiating mechanisms (P5.B1 + P5.C5 + P5.C7) ahead of the curve and lock in evaluation/governance differentiation now (per Anthropic Managed Agents signal).
3. **Reviewer noise compounding without bidirectional check** — P5.B2 closes this with AgentV-RL backward verifier.

---

## Section status (this file)

All agent inputs received and folded in 2026-04-26. Promoting `IDEA_REPORT_v2_DRAFT.md` → `IDEA_REPORT_v2.md` is the next step.

| Section | Status |
|---|---|
| 0 Two-line summary | FINAL |
| 1 What shipped since 2026-04-21 | FINAL (verified against CHANGELOG + commits + grep) |
| 2 What's still open from prior plan | FINAL |
| 3 Dogfood findings | FINAL (verified via commit `c2068ff`) |
| 4 NEW gaps from complexity smells | FINAL (agent A findings folded in §4.5 / §4.7) |
| 5 Fresh competitor signals | FINAL (agent B output folded in) |
| 6 Fresh literature signals | FINAL (agent C output folded in) |
| 7 Ranked P5-tier ideas | FINAL (cross-validated A/B/C) |
| 8 Anti-recommendations | FINAL |
| 9 Stage-2 shortlist | FINAL (P5.A + P5.B1 recommended) |
| 10 Measurement plan | FINAL |
| 11 Strategic context | FINAL (updated with agents B + C) |

**Companion artefacts produced this run** (`/idea-stage/`):
- `STATE_AUDIT_2026-04-26.md` (agent A)
- `COMPETITOR_DELTA_2026-04-26.md` (agent B)
- `LITERATURE_DELTA_2026-04-26.md` (agent C)
- `IDEA_REPORT_v2.md` (this file, after drop of _DRAFT suffix)
- `PIPELINE_REPORT_v2.md` (companion run report)
