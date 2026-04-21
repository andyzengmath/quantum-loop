# Quantum-Loop Audit — State of the Codebase

**Date:** 2026-04-21
**Scope:** Pipeline readiness for the next improvement-research cycle.
**Branch audited:** `master` (HEAD `a421263`).

---

## 1. Skills inventory (`skills/ql-*/SKILL.md`)

All six pipeline skills are present. Every skill directory now ships **two** copies of `SKILL.md` — the original and a `SKILL-CPC-andyz-ZH84K.md` variant. The CPC variants are **newer and larger** (e.g., `skills/ql-plan/SKILL-CPC-andyz-ZH84K.md` is 31 KB / Mar 25, vs. `skills/ql-plan/SKILL.md` at 8.5 KB / Feb 26). The plain files are stale pre-hardening-v1 skeletons and should be treated as abandoned — the skill runtime is expected to load the CPC variant.

| Skill | File | Purpose | Emits | Reads | Anti-rationalization guards |
|---|---|---|---|---|---|
| `ql-brainstorm` | `skills/ql-brainstorm/SKILL.md:1-144` | Socratic design exploration. One question at a time, 2–3 approach options, section-by-section approval. | `docs/plans/YYYY-MM-DD-<topic>-design.md` | `CLAUDE.md`, `package.json`, prior design docs, `quantum.json` | 7-row table at `:89-102`, four hard gates at `:104-108` (no approaches until 3 questions, no design until approach selected, no save until each section approved, no implementation). |
| `ql-spec` | `skills/ql-spec/SKILL.md:1-172` | Generate a 9-section PRD with lettered-option questions, verifiable ACs, numbered FRs. | `tasks/prd-<feature>.md` | Design doc in `docs/plans/`, `quantum.json`, project config | 6-row anti-rationalization table at `:148-157`, pre-save checklist at `:159-171` (≥5 Qs, ≥3 non-goals, every AC machine-verifiable). |
| `ql-plan` | `skills/ql-plan/SKILL-CPC-andyz-ZH84K.md` (31 KB, current) / `SKILL.md:1-207` (stale) | Produce `quantum.json` with DAG + 2–5 min tasks, contracts, `fileConflicts`, DAG validation. | `quantum.json`, invokes `dag-validator` agent | PRD, `references/dag-validation.md`, `references/contract-shapes.md` | Plain `SKILL.md:197-206` has a 6-row table (no tasks without file paths, no skipping cycle detection). CPC variant adds `testFirst` mandate, contract-candidate scan, DAG-validator invocation. |
| `ql-execute` | `skills/ql-execute/SKILL.md:1-49` | Thin wrapper — delegates to `agents/orchestrator.md`. | Orchestrator signals (`<quantum>…`). | `agents/orchestrator.md`, `quantum.json` | None in the skill itself; guards live in the orchestrator agent. |
| `ql-review` | `skills/ql-review/SKILL.md:1-135` | Two-stage review orchestration: spec compliance then code quality, sequential only. | Combined review report; mutates `quantum.json` review fields. | PRD, `agents/spec-reviewer.md`, `agents/quality-reviewer.md`, git `BASE_SHA..HEAD_SHA` | 6-row table at `:125-134` (never skip Stage 1, never parallelize Stage 1/2). |
| `ql-verify` | `skills/ql-verify/SKILL.md:1-128` | Iron-Law gate: IDENTIFY → RUN → READ → VERIFY → CLAIM. | Verification evidence (command output, exit code, timestamp). | Task-level verification commands from `quantum.json`. | Language red-flags at `:81-86`, behavioral red-flags at `:88-94`, 12-row anti-rationalization table at `:96-110`. |

**Finding F1 (Housekeeping)**: CPC-variant duplicates exist in every skill directory and in `agents/`, `lib/`, plus root-level `quantum-loop-CPC-andyz-ZH84K.{sh,ps1}` / `quantum-CPC-andyz-ZH84K.json`. The plain files are orphaned — they lack all hardening added since Feb 26. Any caller that loads `SKILL.md` rather than `SKILL-CPC-andyz-ZH84K.md` will run a degraded pipeline.

---

## 2. Agent inventory (`agents/*.md`)

| Agent | Variant | Trigger | Inputs | Outputs | Key responsibilities |
|---|---|---|---|---|---|
| `orchestrator` | plain `agents/orchestrator.md` (8.9 KB, Feb 25) AND `-CPC…` (54.8 KB, Mar 30) | `/ql-execute`; the only writer of `quantum.json`. | `quantum.json`, PRD, git state. | Spawn commands, signal updates, commit, progress entries. | Init (with init-guard in CPC variant), DAG query (`Step 2`), sequential (`Step 3A`) vs parallel (`Step 3B`) dispatch, two-stage review gate, completion/blocked reporting. |
| `implementer` | plain (5.1 KB) AND `-CPC…` (13.6 KB). | Spawned per story by orchestrator. | Assigned story ID, `quantum.json`, PRD, `codebasePatterns`, contracts (CPC variant only). | Code + commit on worktree branch, `<quantum>STORY_PASSED/FAILED</quantum>`. | TDD loop (RED/GREEN/REFACTOR), wiring verification, quality checks, optional WIP commits (CPC variant). |
| `spec-reviewer` | plain (4.9 KB) AND `-CPC…` (5.6 KB). | Stage 1 of the review gate. | Story ID, PRD path, BASE/HEAD SHAs. | JSON verdict per AC, `wiring_verification` check (CPC variant). | Read diff; check every AC and FR; flag scope creep; `pass` vs `fix_and_re_review`. |
| `quality-reviewer` | plain (5.6 KB) AND `-CPC…` (7.5 KB). | Stage 2 (only if Stage 1 passed). | Story ID, SHAs, description. | JSON verdict with critical/important/minor issues. | 7 review dimensions (plain) / 8 incl. "Coding Standards Compliance" + coverage gate (CPC variant). |
| `dag-validator` | `agents/dag-validator.md:1-190` | Invoked by `ql-plan` after DAG generation. | `quantum.json` path, PRD path. | Modified `quantum.json`, stubs, `dagValidation` block, DAG Health Report. | Coordinator for three specialists; idempotency check, plan-size routing (<5 / 5-15 / 16+), applies bottleneck+duplication fixes, recomputes `fileConflicts`, cycle detection, timeout handling. |
| `bottleneck-analyzer` | `agents/bottleneck-analyzer.md:1-129` | Spawned by `dag-validator`. | Stories with `dependsOn`, `storyType`, `priority`. | JSON `bottlenecks` array with `extracted`/`warning` fixes. | Kahn's algorithm wave assignment; detect linear chains >2, single-story waves, fan-out blockers; propose `-A` stubs only for `types-only` blockers. |
| `conflict-auditor` | `agents/conflict-auditor.md:1-134` | Spawned by `dag-validator` after restructuring. | Stories with task `filePaths`, wave assignments, barrel-file patterns. | JSON `fileConflicts` array with severity (`high`/`medium`/`low`). | Build file→stories map; classify by barrel file, shared-type dirs, config manifests, same-wave overlap. |
| `duplication-detector` | `agents/duplication-detector.md:1-137` | Spawned by `dag-validator`. | Stories (title + description + ACs + tasks), stop-words, Jaccard threshold. | `duplicationRisks` + `dismissed`. | Jaccard pre-filter then LLM semantic check; N-way group stub creation with `-A` suffix. |
| `type-auditor` | `agents/type-auditor.md:1-96` | Spawned by wave-end `lib/type-audit.sh` when grep detects cross-file duplicates. | `TYPE_NAME`, `FILE_PATHS`, `OWNER_STORY`, `WAVE`, `CONTRACTS`. | Consolidated shared-types file + commit, or `AUDIT_FALSE_POSITIVE` / `AUDIT_FAILED`. | Choose authoritative definition (contract → owner → most complete), consolidate, update imports, run typecheck. |

**Finding F2 (Agent duplication)**: `orchestrator`, `implementer`, `spec-reviewer`, `quality-reviewer` each ship two `.md` files with the same YAML-frontmatter `name:`, so which file Claude Code actually loads is undefined behavior. Newer agents (`dag-validator`, `bottleneck-analyzer`, `conflict-auditor`, `duplication-detector`, `type-auditor`) have **no** CPC duplicate.

---

## 3. Library inventory (`lib/*.sh`)

| File | LOC | One-line purpose | Smell / duplication |
|---|---|---|---|
| `common.sh` | 19 (`:1-19`) | `_validate_story_id` regex guard; `_to_native_path` helper (inferred from callers). | Trivial. `common-CPC-andyz-ZH84K.sh` (33 LOC) duplicates it. |
| `dag-query.sh` | 89 (`:1-89`) | `get_executable_stories()` and `detect_cycles()` via jq. | `dag-query-CPC-andyz-ZH84K.sh` is 174 LOC (~2× — contains more extensive functionality). |
| `json-atomic.sh` | 152 | `write_quantum_json()` with validate + atomic `mv`, `cleanup_stale_tmp()`. | CPC variant at 181 LOC. |
| `worktree.sh` | 84 (`:1-84`) | `create_worktree`, `remove_worktree`, `list_worktrees`. | CPC variant at 563 LOC (massive divergence — the plain version is missing features from 2026-03-25 hardening). |
| `spawn.sh` | 92 (`:1-92`) | `build_agent_prompt`, `build_autonomous_command`, `spawn_autonomous`. | CPC variant at 129 LOC. Plain version calls `claude --print` hardcoded (`:61`), no multi-runner support yet. |
| `monitor.sh` | 167 | `detect_signal`, `check_agent_status`, `merge_worktree_branch`, `check_agent_timeout`. | CPC variant at 417 LOC (much larger — integrates merge-strategy & typecheck gate). Plain `merge_worktree_branch` at `:85-…` is the naive `git merge --no-edit` path called out as the Pattern 2 weakness in the 2026-03-18 research. |
| `crash-recovery.sh` | 103 | `recover_orphaned_worktrees()`. | **Superseded** by `resilience.sh` (header comment at `resilience.sh:3` says "Supersedes lib/crash-recovery.sh"). Not yet deleted — dead code. |
| `resilience.sh` | 353 | WIP commits, squash-on-merge, crash recovery, resumable-work detection (hardening-v2). | Re-implements `recover_orphaned_worktrees`; duplicates logic from `crash-recovery.sh`. |
| `materialize.sh` | 600 | Language detection, `infer_shared_types_dir`, contract materialization before each wave. | Large but self-contained. |
| `type-audit.sh` | 355 | `grep_duplicate_definitions` per language; spawns `type-auditor` agent when duplicates found. | Clean. |
| `merge-strategy.sh` | 563 (`:1-…`) | `get_merge_context`, `classify_conflict`, `resolve_conflict`, `classify_and_merge` with rule-based ours/theirs/regenerate/escalate. | Large; source guards at `:11` prevent double-load. Depends on barrel-regen + dep-manifest + merge-semantic optional. |
| `merge-semantic.sh` | 459 | AST-aware 3-way merge (ts-morph / libcst / diff3 fallback). | Useful only when optional tooling installed; `MERGE_SEMANTIC_AVAILABLE` flag at load time. |
| `barrel-regen.sh` | 343 | Detect and regenerate barrel/index files for TS/JS/Python/Rust. | Clean. |
| `dep-manifest.sh` | 309 | `detect_package_manager`, `protect_manifest`, `run_install`, `verify_lockfile`. | Clean. |
| `known-failures.sh` | 742 | Baseline + wave snapshots, `delta_check`, `format_agent_context`, test-runner detection. | Largest library module — good candidate for further decomposition. |
| `init-guard.sh` | 334 | Environment pre-flight: OneDrive/long-path, tmpdir writable, Windows detection, prune stale worktree refs, orphan `.ql-wt/` cleanup. | Clean. |
| `signal-heuristics.sh` | 106 | `parse_agent_output` — infers STORY_PASSED/FAILED from output + exit code + commit evidence for non-Claude runners. | Clean. |
| `runner.sh` | 336 | `runner_load`, `runner_build_cmd`, `runner_spawn`, instruction-file ensurance for multi-runner support. | Clean. |

**Finding F3 (lib duplication)**: Six files have `-CPC-andyz-ZH84K` copies (`common`, `dag-query`, `json-atomic`, `worktree`, `spawn`, `monitor`). The CPC variant of `worktree.sh` is ~6.7× the size of the plain version. Scripts sourcing `lib/worktree.sh` (e.g., `quantum-loop.sh`) get the degraded version. `crash-recovery.sh` is explicitly dead code per `resilience.sh:3`.

---

## 4. Recent design docs (`docs/plans/`)

| Date | Doc | Addresses | Shipped? |
|---|---|---|---|
| 2026-02-18 | `2026-02-18-parallel-execution-design.md` | Original DAG-driven worktree engine (dual backend: Task subagents & bash processes). Lines `:116-161` describe the orchestrator/agent/merge-on-pass architecture. | **Yes** — backbone of current system. `lib/worktree.sh`, `lib/monitor.sh`, `lib/spawn.sh`, `agents/orchestrator.md` Step 3B. |
| 2026-02-27 | `2026-02-27-cross-story-integration-design.md` | 7 enhancements: file-conflict detection in `ql-plan`, consumer-verification pattern, cross-story integration review, Stage-3 LSP review, edge-case reference doc (`:10-25`). | **Partial** — documented, but per 2026-03-09 gap audit many pieces missing (`contracts` etc. hadn't shipped at that point). CPC-variant skills/agents now include these. |
| 2026-03-09 | `2026-03-09-post-mortem-fixes-design.md` | 3-layer plan adding `contracts`, `wiring_verification`, `consumedBy`, `startedAt`, `coverageThreshold`; stale-story detector; final verification sweep; auto-generated post-mortems (`:13-49`). | **Partial** — schema fields visible in CPC variants. No explicit evidence in `skills/ql-plan/SKILL.md` (plain version). `wiring_verification` and `consumedBy` exist only in CPC-SKILL. Stale detection in `resilience.sh`, but post-mortem generator not obviously implemented. |
| 2026-03-18 | `2026-03-18-worktree-isolation-fix-design.md` | Progressive Materialization — 5 layers: structural contracts, selective materialization, escalate-on-conflict merge, post-merge typecheck, wave-end type audit (`:35-45`). | **Mostly yes** — `lib/materialize.sh`, `lib/type-audit.sh`, `agents/type-auditor.md`, `lib/merge-strategy.sh` implement L1–L5. Post-merge typecheck gate requires CPC-`monitor.sh`. |
| 2026-03-24 | `2026-03-24-dag-intelligence-design.md` | Parallel specialist validation (bottleneck + duplication + conflict auditor) coordinated by `dag-validator` (`:170-266`). | **Yes** — all four agents present in `agents/`. Invocation hook lives in CPC `ql-plan` SKILL only. |
| 2026-03-25 | `2026-03-25-modular-hardening-design.md` | 7 modules: barrel-regen, dep-manifest, merge-strategy, known-failures, worktree lifecycle, interface cascade, `contractBreaking` flag (`:238-262`). | **Largely yes** — `lib/barrel-regen.sh`, `lib/dep-manifest.sh`, `lib/merge-strategy.sh`, `lib/known-failures.sh` all exist with stated line counts. Worktree-lifecycle logic folded into `resilience.sh` + `init-guard.sh` rather than a dedicated `lib/worktree-lifecycle.sh`. |
| 2026-03-28 | `2026-03-28-hardening-v2-design.md` | Targeted patches + new modules `init-guard.sh`, `merge-semantic.sh`, `resilience.sh`; WIP commits; quantum.json stash exclusion (`:109-167`). | **Yes** — all three new `lib/*.sh` files exist. Integrated into CPC-`orchestrator.md` (see `orchestrator-CPC-andyz-ZH84K.md:25-48`). |
| 2026-04-01 | `2026-04-01-multi-runner-support-design.md` | Universal runner adapter (`lib/runner.sh` + `runners/*.json` manifests) for Claude/Codex/Copilot/Cursor/Gemini/Amp/Aider + signal heuristics (`:242-272`). | **Partial** — `lib/runner.sh`, `lib/signal-heuristics.sh`, `runners/` dir, `schemas/` dir all present. The plain `lib/spawn.sh:61` still hardcodes `claude --print`; integration lives only in CPC-`spawn.sh`. |

**Observation**: The design cadence is ~1 doc / 10 days since Feb. Each post-mortem triggers a design which then produces new `lib/*.sh` + agent prompts. Shipped code is consistently on the CPC-variant track, while the plain track stopped updating after Feb 25.

---

## 5. Post-mortems (`docs/post-mortems/`)

### 5a. `2026-03-09-math-research-agent.md` (real failure catalog, 34 stories / 80 tasks)

| # | Failure mode | Root cause | Fix status |
|---|---|---|---|
| 1 | `persona-handler.ts` and `write-handler.ts` fully implemented but never imported by `panel.ts`; 5/24 message types silently broken (`:9-13`). | Wiring instructions in task descriptions but agents skipped and review gates didn't verify. | **~80% addressed** per gap audit — behavioral checks in implementer, but no machine-verifiable `wiring_verification` field in plain `ql-plan`. |
| 2 | Google secret key `'google-api-key'` vs `'google'` in sibling stories (`:36-41`). | Parallel agents had no coordination mechanism for shared constants. | **~50% addressed** — CPC-variant `ql-plan` generates `contracts.secret_keys`, CPC-`implementer` reads contracts. Plain pipeline still has the gap. |
| 3 | Immutability-rule violations passed review (`:64-70`). | Quality-reviewer not given codebase patterns. | **~10% addressed** — CPC-`quality-reviewer` adds dimension 8 (Coding Standards Compliance). Plain reviewer still 7-dimension. |
| 4 | `BranchCard.tsx`/`PersonaSelector.tsx` created but `ResearchTab.tsx` inlined replacements (`:92-97`). | Independent stories; consumer didn't know component existed. | **~80% addressed** via Stage-3 LSP review + dead-code scan; `consumedBy` field still absent from plain `ql-plan`. |
| 5 | US-004 stuck `in_progress` with 0 retries while other 33 passed (`:115-119`). | Transient failure left state inconsistent; no stale detector. | **Partial** — `resilience.sh` detects resumable work; `init-guard.sh` prunes stale worktree refs. `startedAt` field appears in CPC orchestrator only. |
| 6 | PRD missed "restore active provider on startup" lifecycle (`:142-148`). | Brainstorm/spec never forced a lifecycle question. | **Unfixed** — plain `ql-brainstorm` still has 6 Phase-1 question categories, no lifecycle prompt. CPC variant adds #7 LIFECYCLE. |
| 7 | EntityDetector/PaperManager/TexParser had 0 tests despite TDD mandate (`:162-171`). | Tasks had `testFirst: false`, no coverage gate. | **Unfixed in plain** — CPC-`ql-plan` adds testFirst mandate; CPC-`quality-reviewer` adds coverage gate. |

### 5b. `2026-03-09-gap-audit.md`

Issue-by-issue scorecard (`:95-105`). Confirmed: P0 issues #1/#2 have working mitigations; P1 issue #5 (stale detection) is the most dangerous open gap at time of writing. **Most of its action items are only in CPC files**, not the plain shipped pipeline.

### 5c. `2026-03-09-ql-test-feature-observations.md` and `2026-03-18-ql-test-feature-observations.md`

Both are *stub* post-mortems (only 15 lines each) showing `0 passed, 1 failed (of 1 total)` with an empty Progress Log. They document that the auto-generated observations feature was wired up but the data-harvesting logic wasn't implemented — each file is a table with no rows. **Flag as WIP**.

### 5d. `2026-03-18-worktree-isolation-research.md` (deep-research doc, ~250 lines)

Research rather than failure replay. Key taxonomy:

- **Pattern 1 — Type divergence** (7/10 observed issues): agents agree on a type name but create incompatible structures. Cause: `contracts.shared_types` stored names, not shapes (`:19-21`).
- **Pattern 2 — Destructive merge** (2/10): `git merge --no-edit` in `lib/monitor.sh:106` treats all file types identically, deletes previously-merged content (`:48-54`).
- **Pattern 3 — `as any` bypass** (1/10): agent has no choice because B's interface doesn't exist yet at A's branch time (`:59-63`).

Survey of community tooling (Clash, parallel-cc, Overstory, Mux, Agent Teams) confirms no platform-level solution exists. Recommends the 5-layer defense now implemented as the 2026-03-18 design doc.

---

## 6. Known issues — current gaps by category

### Wiring issues
- **G1** Plain `ql-plan/SKILL.md` does not emit `wiring_verification` or `consumedBy` fields — only the CPC variant does. Any install that loads plain `SKILL.md` regresses to the 2026-02 behavior that caused 100% of the Math Research bugs (`2026-03-09-math-research-agent.md:12-19`).
- **G2** Plain `spec-reviewer.md:1-138` has no `wiring_verification` grep check (that step is only in `spec-reviewer-CPC-andyz-ZH84K.md`). So the machine-verifiable import check, explicitly recommended as a P0 fix, is conditional on which file ships.
- **G3** The orchestrator's "post-merge import smoke test" from the 2026-02-27 design (`:65-74`) is described in the CPC-orchestrator but not in the plain `orchestrator.md`.

### Conflicts (file / import / type)
- **G4** `lib/monitor.sh:85-…` `merge_worktree_branch()` (plain variant, 167 LOC) is still `git merge --no-edit` with stash — the exact file called out in `2026-03-18-worktree-isolation-research.md:48-54` as Pattern 2's weakest link. File-type-aware classification lives in `lib/merge-strategy.sh` (563 LOC) and CPC-`monitor.sh` (417 LOC), but these are only used when the orchestrator sources them and the scripts that invoke monitor.sh are the plain versions.
- **G5** `lib/materialize.sh` selectively materializes only multi-consumer types (threshold `consumers ≥ 2`). The 2026-03-28 hardening-v2 plan proposed lowering to `consumers ≥ 1` but flagged a worktree-creation-speed concern (`2026-03-28:251-254`). Unclear which threshold is actually active at runtime.
- **G6** `conflict-auditor.md:63-81` classifies barrel files and shared-types dirs as `severity: "high"`, but the plain `ql-plan` SKILL never triggers `dag-validator` (which owns the auditor). So `fileConflicts` enrichment is gated on the CPC plan track.

### Duplicate code
- **G7** `lib/type-audit.sh` + `agents/type-auditor.md` only run when triggered by the CPC-orchestrator's wave-end hook. Plain `orchestrator.md:80-118` has no wave-end audit step — so when the plain track runs, duplicate-type detection is absent.
- **G8** `duplication-detector` semantic check depends on `jaccardThreshold` default `0.3` (`duplication-detector.md:42`). 2026-03-24 design `:422` flagged this as "a single default" and unconfigurable per-project. False negatives silently pass.
- **G9** **Self-inflicted duplication** in the quantum-loop repo: plain `crash-recovery.sh:22-52` and `resilience.sh:31-…` both implement `recover_orphaned_worktrees()`. Header on `resilience.sh:3` says it supersedes `crash-recovery.sh`, but the file remains. Any sourcing path that loads `crash-recovery.sh` first wins.

### Dead code / orphans
- **G10** All six plain `lib/*.sh` files that have CPC variants (`common.sh`, `dag-query.sh`, `json-atomic.sh`, `worktree.sh`, `spawn.sh`, `monitor.sh`) are abandoned — they lack hardening-v2 and multi-runner integration. Which version is loaded depends on how the plugin is installed; this is observable non-determinism.
- **G11** `crash-recovery.sh` — explicitly superseded but not removed.
- **G12** Plain `agents/orchestrator.md:115-160` documents Step 3B parallel execution but never calls `init-guard.sh`, `resilience.sh`, `known-failures.sh`, or `materialize.sh`. All the hardening is bolted into the CPC orchestrator (`orchestrator-CPC-andyz-ZH84K.md:25-48`) instead of merged.
- **G13** `.claude-plugin/marketplace-CPC-andyz-ZH84K.json`, `.claude-plugin/plugin-CPC-andyz-ZH84K.json`, `-CPC-andyz-ZH84K.gitignore`, `CHANGELOG-CPC-andyz-ZH84K.md`, `CLAUDE-CPC-andyz-ZH84K.md`, `README-CPC-andyz-ZH84K.md`, `quantum-loop-CPC-andyz-ZH84K.{sh,ps1}`, `quantum-CPC-andyz-ZH84K.json`, `quantum.json-CPC-andyz-ZH84K.example` are all untracked in `git status` — they look like an in-progress rebrand/fork that was never either merged down onto the plain names or cleaned up.

### Review gaps (what the two-stage gate does NOT catch)
- **G14** Per-story focus. `agents/spec-reviewer.md:34-59` checks one story in isolation — it never compares two merged worktrees. Cross-story inconsistency (the `'google'` vs `'google-api-key'` class) is structurally invisible here.
- **G15** `agents/quality-reviewer.md:20-92` evaluates only the diff `BASE_SHA..HEAD_SHA` and warns against reviewing unchanged code (`:151-155`). So a regression caused by a merge of previously-clean code (Pattern 2) is by design out of scope.
- **G16** No post-merge regression test step in the plain review. `ql-review/SKILL.md:43-80` performs Stages 1 & 2 and stops; the design documents a Stage 3 "cross-story integration review" (`2026-02-27:89-104`) but it does not exist in `skills/ql-review/SKILL.md`. The CPC variant adds it, but the plain-file pipeline lacks it.
- **G17** Review gates accept passing tests as sufficient — they do not check whether acceptance criteria map to specific tests (the "test covers AC" gap documented in post-mortem #7).

### Intent preservation
- **G18** Information decays at each pipeline stage. Brainstorm saves `docs/plans/…-design.md` free-form; `ql-spec` re-asks clarifying questions and rewrites the design into 9 PRD sections; `ql-plan` then translates ACs into tasks. Each stage can paraphrase. No doc asserts that PRD ACs literally appear in `quantum.json.acceptanceCriteria` verbatim.
- **G19** `ql-plan` CPC variant adds a "contracts" inference step, but there is no equivalent "non-goals" extraction — explicit scope boundaries from PRD section 5 are not propagated into quantum.json. Agents have no machine-visible "do-not" list.
- **G20** Every design doc ends with "Run `/quantum-loop:ql-spec` to generate a formal PRD" (e.g., `2026-02-18:232`, `2026-03-25:672`). None of the designs were actually turned into a PRD that was executed through the pipeline — the team skips the spec/plan stages on their own feature work, so the pipeline has never dogfooded its own hardening.
- **G21** Stub post-mortems at `2026-03-09-ql-test-feature-observations.md:1-15` and `2026-03-18-ql-test-feature-observations.md:1-15` show the post-mortem generator emits a file but never populates the Progress Log. Failure rationale that used to live in retries.failureLog is not surfaced to future iterations. This directly undermines the "add learnings to codebasePatterns" loop.

---

## 7. Summary of structural risks

1. **Two pipelines coexist in one repo.** Plain files (Feb 15 / Feb 25) are missing all hardening; CPC-variant files (Mar–Apr) carry all post-mortem fixes. Whichever the runtime loads first wins. No doc clarifies the intended promotion path. (Findings F1, F2, F3, G1–G2, G10, G12, G13.)
2. **Merge layer is still the weakest link on the plain track.** The research doc is explicit: the one-line `git merge --no-edit` causes Pattern 2 destructive merges. Plain `lib/monitor.sh:85` still matches that description verbatim. (G4.)
3. **Review gate is story-local by design.** Neither Stage 1 nor Stage 2 can observe cross-story divergence or post-merge regressions; the proposed Stage-3 gate ships only in CPC-review. (G14–G16.)
4. **Intent-preservation signals are missing at every stage boundary.** PRD non-goals, lifecycle considerations, acceptance-criteria verbatim text, and codebase-pattern learnings all degrade in transit. The Iron Law catches verification lies, not information lies. (G18–G21.)

---
