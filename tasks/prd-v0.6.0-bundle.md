# PRD: v0.6.0 — P5.A Cleanup Bundle + P5.B1 Per-Role Provider Routing

**Status:** Approved
**Date:** 2026-04-26
**Design doc:** `docs/plans/2026-04-26-v0.6.0-bundle-design.md`
**Source:** `idea-stage/IDEA_REPORT_v2.md` (Gate-1 Option A confirmed by user)
**Branch (planned):** `ql/v0.6.0-bundle`
**Target version:** 0.6.0
**Total effort estimate:** 10-12 days (1-2 weeks single-developer; ~1 week with parallel waves)

## Section 1: Introduction / Overview

This release closes the small remaining gaps surfaced by three independent agent investigations after the v0.5.1 ship: 8 polish items addressing watchdog wiring, cross-provider critic CLI, deslop fallback, runner manifests, PRD hash-pinning, Sprint-Contract handoff, inline self-review, and cheapest-capable-model routing — plus 1 structural feature (per-role provider routing with resolved-routing snapshot) that closes P2.9 fully and serves as the next "bigger dogfood" of the pipeline.

The 10-story bundle is explicitly chosen to stress parts of the pipeline that the v0.5.1 4-story linear `--audit` dogfood couldn't exercise: parallel waves, cross-story contracts, wave-boundary review, multi-runner dispatch.

## Section 2: Goals

- Close all 3 minor weaknesses agent A flagged (watchdog wiring, cross-provider critic CLI, deslop fallback).
- Close P2.9 fully via per-role provider routing port from OMC v4.12.0, eliminating the v0.5.0 OMC tight-coupling risk in `lib/deep-review.sh`.
- Ship 5 missing runner manifests so CHANGELOG v0.4.1 claims match shipped state.
- Add minimal RAGShield-L1 spec-anchored regen via PRD hash-pinning.
- Cut routine-review latency ~25 min → ~30 sec via inline self-review checklists.
- Enable cheapest-capable-model routing per task (cost + latency).
- Run a "bigger dogfood than --audit" (10 stories vs 4, 3 waves vs 1, multi-runner dispatch) and capture findings in IDEA_REPORT_v3.

## Section 3: User Stories

### US-001: Watchdog orchestrator wiring (P5.A1)

**Description:** As a quantum-loop operator running long parallel waves, I want stuck-agent detection (5/10/30-min age tiers + same-error circuit breaker) to actually fire at runtime, so that long-running degenerate agents are killed without my intervention.

**Acceptance Criteria:**
- [ ] `agents/orchestrator.md` Step 3B.3 includes 3 explicit watchdog calls: age-tier check, circuit-breaker check, circuit-breaker reset on success.
- [ ] `lib/watchdog.sh:4` and any other internal call sites no longer reference `kill_agent_process`; instead they reference `reap_agent` from `lib/reaper.sh`.
- [ ] New test `tests/test_watchdog_wiring.sh` asserts orchestrator references match expected functions (≥6 assertions).
- [ ] Existing `tests/test_watchdog.sh` (32 assertions) continues to pass unchanged.
- [ ] Typecheck/lint passes; `bash tests/test_watchdog*.sh` exits 0.

### US-002: Cross-provider critic CLI flag + fallback (P5.A2)

**Description:** As an operator, I want to override the tier-driven cross-provider critic dispatch via `--critic=auto|codex|gemini|claude|none`, with graceful fallback when the chosen provider's CLI is missing, so I have explicit control over the most expensive review tier.

**Acceptance Criteria:**
- [ ] `quantum-loop.sh` and `quantum-loop.ps1` accept `--critic=<value>` with values: `auto` (default), `codex`, `gemini`, `claude`, `none`.
- [ ] `auto` triggers existing tier-7 dispatch logic in `lib/deep-review.sh:304` unchanged.
- [ ] `none` skips cross-provider critic entirely.
- [ ] When `codex` or `gemini` selected and binary not on `$PATH`, log: `WARN: critic provider 'X' not available, falling back to 'none'` and continue.
- [ ] New test `tests/test_cross_provider_critic_flag.sh` covers (a) auto unchanged, (b) `--critic=none` skips, (c) absent provider → graceful degrade. ≥10 assertions.
- [ ] Typecheck/lint passes.

### US-003: Deslop language-autodetect regex fallback (P5.A3)

**Description:** As an operator on a system without `knip`/`ts-prune`/`vulture`/`cargo-udeps`, I want `ql-deslop` to fall back to regex-based detection (already shipped in `lib/dead-code.sh`) instead of silently skipping, so that stories on minimal systems still get slop cleanup.

**Acceptance Criteria:**
- [ ] `lib/deslop.sh:detect_language()` no longer returns `unsupported` when tooling absent. Instead it returns `regex-fallback` and dispatches to `lib/dead-code.sh` for unused-import + unused-private-helper detection.
- [ ] Output format normalized to deslop's expected `{file, line, kind, severity}` schema.
- [ ] New test `tests/test_deslop_regex_fallback.sh` mocks tooling absence; ≥5 assertions covering each language path.
- [ ] Existing `tests/test_deslop.sh` (22 assertions) continues to pass unchanged.
- [ ] Typecheck/lint passes.

### US-004: Runner manifests for 5 missing runners (P5.A4)

**Description:** As an operator picking a runner per CHANGELOG v0.4.1 line 76, I want `runners/{opencode,devin,kiro,goose,cline}.json` to exist (with `experimental: true`) so my invocation succeeds rather than failing cryptically.

**Acceptance Criteria:**
- [ ] 5 new files created: `runners/opencode.json`, `runners/devin.json`, `runners/kiro.json`, `runners/goose.json`, `runners/cline.json`.
- [ ] Each conforms to `schemas/runner.schema.json`; `bash schemas/validate.sh` exits 0.
- [ ] Each has `"experimental": true` field set.
- [ ] `runners/opencode.json` follows Superpowers' OpenCode plugin pattern: skill auto-discovery from `.opencode/skills/` and `.claude/skills/`.
- [ ] `tests/test_runner_manifests.sh` (extended) asserts manifest count = 12 and validates each.
- [ ] If any of the 5 prove infeasible (research surfaces fundamental incompatibility), CHANGELOG v0.4.1 line 76 trimmed accordingly with explanatory commit message.
- [ ] Typecheck/lint passes.

### US-005: PRD hash-pinning (RAGShield Level-1) (P5.A5)

**Description:** As a planner, I want each story in `quantum.json` to record `prdSha` (sha256 of the PRD file content at story-creation time), so that orchestrator can detect spec drift and mark affected stories `stale` for re-plan rather than running against a stale ACs basis.

**Acceptance Criteria:**
- [ ] `quantum.json.example` documents `prdSha` field (optional, top-level per story; backward-compat: absent = no check).
- [ ] `agents/dag-validator.md` computes and sets `prdSha` when creating story stubs.
- [ ] `agents/orchestrator.md` Step 1 includes pre-flight hash check: for each story with `prdSha` present, recompute current PRD hash; on mismatch, set story `status: "stale"` and log warning with file:line reference.
- [ ] New helper `lib/json-atomic.sh:compute_prd_sha()` produces a stable sha256 of PRD file content (excluding trailing whitespace per `git hash-object` convention).
- [ ] New test `tests/test_prd_hash_pinning.sh`: (a) matched hash → execute, (b) mismatched → status: stale, (c) missing field → backward-compat warning, no abort. ≥8 assertions.
- [ ] Typecheck/lint passes.

### US-006: Sprint-Contract handoff format (P5.A6)

**Description:** As an implementer / reviewer, I want a per-story Sprint-Contract JSON (Anthropic 2026-03-24 Generator↔Evaluator pattern) that captures `{ storyId, prdSha, acs, contracts, files, expectedTests, plannedBy, plannedAt }`, so that subsequent stages have a single canonical source of per-story intent rather than re-deriving from the PRD.

**Acceptance Criteria:**
- [ ] `lib/handoff.sh` exposes `write_sprint_contract <storyId>` and `read_sprint_contract <storyId>` functions.
- [ ] `/ql-plan` writes `.handoffs/sprint-<storyId>.json` per story at exit.
- [ ] `/ql-execute` (implementer) reads sprint-contract at story start and validates its `prdSha` matches current PRD before proceeding.
- [ ] `/ql-review` (spec-reviewer + quality-reviewer) reads sprint-contract for AC reference instead of re-reading the full PRD.
- [ ] Sprint-Contract JSON schema documented in `references/sprint-contract.md` (new file).
- [ ] New test `tests/test_sprint_contract.sh`: write/read round-trip, schema validation, missing-file warning. ≥8 assertions.
- [ ] Typecheck/lint passes.

### US-007: Inline self-review checklists for routine gates (P5.A7)

**Description:** As a story implementer, I want routine review (typecheck / lint / test / file-org) handled inline via a structured checklist in my own prompt, so that subagent-dispatch is reserved for **adversarial** review (cross-story conflict, intent drift, security) and total review time per story drops from ~25 min to ~30 sec for routine paths.

**Acceptance Criteria:**
- [ ] `agents/implementer.md` includes an explicit inline-review checklist before STORY_PASSED signal: typecheck OK, lint OK, all assigned tests pass, file-org follows project conventions.
- [ ] `agents/spec-reviewer.md` marks routine review sections as inline-only (skipped on subagent dispatch).
- [ ] `skills/ql-verify/SKILL.md` documents which checks are inline vs adversarial, with rationale.
- [ ] `tests/test_orchestrator_wiring.sh` extended (~6 new assertions) to verify inline checklist tokens present in implementer + verifier prompts.
- [ ] Manual measurement on 1 trivial story: routine path completes ≤ 60s wall-clock.
- [ ] Typecheck/lint passes.

### US-008: Cheapest-capable-model routing per task (P5.A8)

**Description:** As a quantum-loop operator paying for model usage, I want stories with low complexity scores to dispatch to Haiku and only complex stories to dispatch to Opus (current default), so that cost and latency drop on the simple cases without sacrificing quality on the complex ones.

**Acceptance Criteria:**
- [ ] `quantum.json.example` documents `complexity` field (optional, per story; computed score 0-100; backward-compat: absent = use orchestrator default).
- [ ] `agents/dag-validator.md` computes `complexity` per story: `min(100, task_count * 10 + dependsOn_depth * 15 + (has_security_tag ? 30 : 0) + filePaths_count * 2)`.
- [ ] `lib/runner.sh:runner_build_cmd` reads `complexity` and selects model: ≤ 30 → Haiku, 31-60 → Sonnet, 61+ → Opus (default behavior).
- [ ] Story-level `model: "<override>"` field overrides the score-derived choice when present.
- [ ] New test `tests/test_complexity_routing.sh`: score computation, threshold dispatch, story-level override, missing-field default. ≥12 assertions.
- [ ] Typecheck/lint passes.

### US-009: Per-role provider routing with resolved-routing snapshot (P5.B1)

**Description:** As an operator, I want to assign different providers per role (`--planner=claude --critic=codex --executor=claude`) with the resolved choices captured into `quantum.json.routing` for reproducibility, so that I can mix providers (closing P2.9 fully) and replay runs with the same provider mix.

**Acceptance Criteria:**
- [ ] `quantum-loop.sh` and `quantum-loop.ps1` accept `--planner=<provider>`, `--critic=<provider>` (subsumes P5.A2), `--executor=<provider>`.
- [ ] At run start, after auto-detection + availability checks, `quantum.json.routing` is written with resolved choices: `{ planner, critic, executor, resolvedAt: "<iso>", versions: { <provider>: "<cli-version>" } }`.
- [ ] On replay (orchestrator init), if `quantum.json.routing` exists and CLI flags absent, snapshot is used as default.
- [ ] If a role's provider becomes unavailable on replay, log warning + fall back to `claude` for that role; do not abort.
- [ ] `lib/runner.sh` consumes routing per role at dispatch time (replacing the hardcoded path in P5.A2 / `lib/deep-review.sh:304`).
- [ ] `agents/orchestrator.md` Step 1 reads snapshot; Step 5/6/7 dispatches per role using routing.
- [ ] `lib/deep-review.sh` consumes routing for critic dispatch.
- [ ] New test `tests/test_per_role_routing.sh`: resolution, snapshot capture, replay determinism, role-fallback. ≥20 assertions.
- [ ] Multi-runner integration test exercises (claude, codex) pair end-to-end on a 2-story toy `quantum.json`.
- [ ] Typecheck/lint passes.

### US-010: Dogfood retrospective + IDEA_REPORT_v3 (P5.Z1)

**Description:** As a project maintainer, I want a structured retrospective after Phase 9 captures findings from running the v0.6.0 bundle through the pipeline (parallel-wave issues, cross-story contract violations, handoff drift), and an IDEA_REPORT_v3 draft mapping what's still open after v0.6.0 (most likely: P5.B2-B5 + P5.C frontier).

**Acceptance Criteria:**
- [ ] `idea-stage/PIPELINE_REPORT_v3.md` documents the v0.6.0 dogfood run: total wall-clock, wave timings, cross-story-contract events, handoff issues if any, test-suite delta (additions, removals, runtime change).
- [ ] `idea-stage/IDEA_REPORT_v3.md` lists what's still open: P5.B2 (bidirectional reviewer), P5.B3 (`/ultrareview` parallel pattern), P5.B4 (spec-review-before-impl), P5.B5 (AgentGA tournament), P5.C* frontier, plus any NEW gaps surfaced by this run.
- [ ] `.omc/phase-N-evidence/v0.6.0-test-suite.log` captured.
- [ ] `quantum-loop.sh --audit` re-run after Phase 9 merges; output captured in retrospective; all metrics still target.
- [ ] CHANGELOG.md updated with v0.6.0 entry covering the 9 user-facing stories.
- [ ] Typecheck/lint passes (no test required; this story is documentation-only).

## Section 4: Functional Requirements

- **FR-1:** The system shall expose `--critic=auto|codex|gemini|claude|none` operator flag on `quantum-loop.sh` and `quantum-loop.ps1`.
- **FR-2:** The system shall expose `--planner=<provider>` and `--executor=<provider>` operator flags with the same provider enum.
- **FR-3:** The system shall record per-story `prdSha` (sha256 of PRD file content) in `quantum.json` and check it pre-flight at orchestrator Step 1.
- **FR-4:** The system shall record per-story `complexity` score in `quantum.json` and use it to select dispatch model when no story-level override is present.
- **FR-5:** The system shall write `.handoffs/sprint-<storyId>.json` per story at `/ql-plan` exit and consume it at `/ql-execute` and `/ql-review` start.
- **FR-6:** The system shall record `quantum.json.routing` snapshot at run start with `{ planner, critic, executor, resolvedAt, versions }`.
- **FR-7:** The system shall fall back to `claude` (or `none` for critic) with a warning log when a chosen provider's CLI is not on `$PATH`.
- **FR-8:** The system shall execute Wave 1 stories in parallel (P5.A1, P5.A3, P5.A4, P5.A8), Wave 2 stories in parallel (P5.A5, P5.A6, P5.A7), and Wave 3 stories sequentially (P5.A2, P5.B1, P5.Z1).
- **FR-9:** The system shall maintain backward compatibility: quantum.json files without `prdSha`, `complexity`, or `routing` shall load and execute with current default behavior, emitting at most a one-line warning.
- **FR-10:** The system shall ship `runners/{opencode,devin,kiro,goose,cline}.json` manifests, each conforming to `schemas/runner.schema.json` and validated by `bash schemas/validate.sh`.

## Section 5: Non-Goals (Out of Scope)

- **NG-1:** Bidirectional reviewer (P5.B2) — deferred to v0.7.x.
- **NG-2:** `/ultrareview` parallel multi-agent review pattern (P5.B3) — deferred.
- **NG-3:** Spec-review subagent BEFORE impl (P5.B4) — deferred.
- **NG-4:** AgentGA 1:1 elite tournament (P5.B5) — deferred.
- **NG-5:** Adversarial test generator (P5.C1), HiveMind proxy (P5.C2), per-task sandboxed verification (P5.C3), pre-commit belief-audit (P5.C4), GEPA self-evolution (P5.C5), repeated-evaluation voting (P5.C6), Skilldex package (P5.C7) — all deferred.
- **NG-6:** P4 AI-native ecosystem integration (any of P4.1-P4.6) — blocked on upstream.
- **NG-7:** SWE-bench Pro / HORIZON benchmark integration — flagged as positioning recommendation in IDEA_REPORT_v2 but deferred.
- **NG-8:** Lib coupling map auto-generation (§4.3 from IDEA_REPORT_v2) — deferred to a follow-on housekeeping cycle.
- **NG-9:** Orchestrator phase-module factor (§4.2 from IDEA_REPORT_v2) — too large for v0.6.0; tagged for future work.

## Section 6: Design Considerations

UI: command-line operator flags only (`--critic`, `--planner`, `--executor`). No interactive prompts. Output remains plain-text per CLAUDE.md project conventions. Snapshot file format is JSON, stable for diff-friendly review.

Schema: 3 new optional fields/blocks in `quantum.json` (`prdSha` per story, `complexity` per story, `routing` top-level). All optional. Backward-compatibility tested explicitly in US-005 / US-008 / US-009 acceptance criteria.

## Section 7: Technical Considerations

- **Shell compatibility:** bash 4.3+ (consistent with rest of `lib/*.sh`).
- **External tools:** `git`, `grep`, `find`, `wc`, `ls`, `awk`, `jq`, `sha256sum` (or `shasum -a 256` on macOS) — all already required.
- **`set -euo pipefail` safety:** all helpers wrap subprocess calls in `{ cmd 2>/dev/null ; } || true` per project convention; no `grep -c ... || echo 0` anti-pattern.
- **Performance:** PRD hash check at Step 1 must complete in < 100 ms on a 100KB PRD. Per-role dispatch lookup must be O(1) per story.
- **Security:** provider flags validated against fixed enum; no shell-injection paths. PRD hash uses `sha256sum`/`shasum` not user-controlled input. Routing snapshot writes go through `lib/json-atomic.sh:write_quantum_json` (atomic + validated).
- **Cross-platform:** all new tests must exercise both POSIX and Git Bash / MSYS paths per CLAUDE.md Platform Notes (heredoc CRLF, subshell exit-code capture, `local -n` 4.3+, `sort -V`).

## Section 8: Success Metrics

- All 10 user stories pass with verifiable evidence.
- `bash tests/*.sh` exits 0 with ≥1,520 total assertions (was ~1,400 in v0.5.1).
- `quantum-loop.sh --audit` after Phase 9 merges still reports all 6 metrics on target (no regression).
- Plugin version bumped to 0.6.0 across `.claude-plugin/plugin.json` + `marketplace.json` + `CHANGELOG.md`.
- IDEA_REPORT_v3 documents what's open after v0.6.0 (clear roadmap to v0.7.x).
- Wave timings for P5.A items 1-4 (Wave 1) and 5-7 (Wave 2) demonstrate genuine parallel speedup vs serial baseline (target: ≥ 2× for Wave 1; reported in P5.Z1).

## Section 9: Open Questions

None. Design doc + IDEA_REPORT_v2 + agent deltas resolve all substantive design questions.

## Lifecycle Checklist

- **First-run behavior** — All new flags are opt-in; absent flags = current v0.5.1 behavior.
- **Returning-user behavior** — Existing `quantum.json` files load with one-line warnings on missing optional fields; orchestrator falls back to defaults. No forced migrations.
- **Update behavior** — quantum.json schema is additive only; no field removals or repurposing. Operators upgrading from v0.5.x retain full backward compatibility.
- **Error recovery** — Provider unavailability (CLI not on `$PATH`) → graceful fallback to `claude` for executor/planner, `none` for critic. PRD hash mismatch → mark story `stale`, log warning, do not abort run.
- **No-data / empty state** — Fresh repo with no `quantum.json`: orchestrator emits standard "no plan present" message and exits 0. New routing block absent: orchestrator uses `--runner=<single>` (current default).
- **Uninstall / disable** — All new fields are optional; downgrading to v0.5.x ignores them silently. New runner manifests can be deleted without affecting other manifests.

## Next Steps

Run `/quantum-loop:ql-plan` on this PRD to generate `quantum.json` with the 3-wave DAG, contracts, and `fileConflicts`. Then `/quantum-loop:ql-execute` to ship.
