# PRD: v0.6.3 — G-track cleanup + spec-review-pre-impl ×3

**Status:** Approved
**Date:** 2026-04-26
**Design doc:** `docs/plans/2026-04-26-v0.6.3-bundle-design.md`
**Source:** `idea-stage/IDEA_REPORT_v3.md` §G2/G3/G8/G9/G11 + §P5.B4 (expanded to design+PRD+plan)
**Branch (planned):** `ql/v0.6.3-bundle`
**Target version:** 0.6.3 (patch bump from 0.6.2)
**Total effort estimate:** ~5-7 days (single-developer; ~3-4 days with parallel waves)

## Section 1: Introduction / Overview

This release closes 5 follow-through items from the v0.6.0 / v0.6.1 / v0.6.2 cycles + adds spec-review-pre-impl checkpoints at 3 pipeline stages (design exit, PRD exit, plan exit) per the user-expanded P5.B4. The spec-review checkpoints are advisory-only in v0.6.3 to establish a baseline before promoting to blocking gates in a future release.

The 9-story bundle stays **patch-tier** (no breaking changes; new mechanisms are opt-in or fail-safe; schema additions are backward-compatible). Per user framing: ship cleanly without manufacturing a "bigger dogfood" stress vector.

## Section 2: Goals

- Close G2, G3, G8, G9, G11 from `IDEA_REPORT_v3.md` (5 polish items).
- Add 3 advisory spec-review checkpoints at design / PRD / plan exits, mirroring Superpowers v5.0.0's spec-review subagent pattern.
- Maintain 0-retry execution record (v0.6.0 set baseline).
- Bump plugin version 0.6.2 → 0.6.3 across all 3 manifests in lockstep.
- Backward compatibility: existing v0.6.x quantum.json files load and run unchanged.

## Section 3: User Stories

### US-001: G8 — critic fallback unification

**Description:** As an operator, when I pass `--critic=codex` and the codex binary is absent, I want a single deterministic answer (the `none` downgrade preserved from US-002's design intent), regardless of which code path or platform I'm on.

**Acceptance Criteria:**
- [ ] `quantum-loop.sh::parse_critic_arg` is removed (dead code).
- [ ] `lib/runner.sh::_availability_check` falls back to `none` for the critic role and `claude` for planner/executor roles (role-aware fallback).
- [ ] `quantum-loop.ps1` already falls back to `none` for critic; verify no change needed.
- [ ] `tests/test_cross_provider_critic_flag.sh` extended: with codex absent, `parse_role_arg critic codex` returns `none`. Existing 13 assertions remain green.
- [ ] CHANGELOG documents the bash-side semantics change as v0.6.3.
- [ ] Typecheck/lint passes.

### US-002: G9 — Sprint-Contract `expectedTests` filter

**Description:** As an implementer reading the Sprint-Contract, I want `expectedTests` to contain only test-pattern commands (so I know exactly what tests to write/extend), with non-test verification commands (typecheck/lint) in a separate `otherCommands` field.

**Acceptance Criteria:**
- [ ] `agents/orchestrator.md` Step 2.5 jq splits `.commands` by pattern: test-pattern → `expectedTests`; rest → `otherCommands`.
- [ ] Test-pattern: command string contains `test_`, `.test.`, `spec`, `pytest`, `bash tests/`, `npm test`, OR matches `tests/test_.*\.sh`.
- [ ] `references/sprint-contract.md` schema doc updated to include `otherCommands: string[]`.
- [ ] `tests/test_sprint_contract.sh` extended: feeding a story with mixed commands produces correct split.
- [ ] Existing 11 assertions in `test_sprint_contract.sh` remain green; new ones extend to ≥14.
- [ ] Backward-compat: existing readers ignore unknown `otherCommands` field. Implementer/reviewer prompts unchanged.
- [ ] Typecheck/lint passes.

### US-003: G11 — `write_routing_snapshot` canonicalization

**Description:** As a maintainer of `lib/runner.sh`, I want `write_routing_snapshot` to compose with `lib/json-atomic.sh::write_quantum_json` (instead of rolling its own `tmp+mv`), so the canonical validation gate + `cleanup_stale_tmp` coordination apply consistently.

**Acceptance Criteria:**
- [ ] `write_routing_snapshot` body refactored to: `content=$(jq ...) && write_quantum_json "$qj" "$content"`.
- [ ] Existing 26 assertions in `tests/test_per_role_routing.sh` remain green.
- [ ] New assertion: invalid routing JSON (e.g., `'{"planner":')`) fails via `write_quantum_json`'s validation gate, not via jq directly.
- [ ] No new files; pure refactor.
- [ ] Typecheck/lint passes.

### US-004: G3 — wire `write_sprint_contract` into `/ql-plan` exit

**Description:** As a planner, I want `/ql-plan` to write `.handoffs/sprint-<storyId>.json` for each story at exit (not lazily on first orchestrator run), so subsequent skills (review, verify) have the contract available before the orchestrator starts.

**Acceptance Criteria:**
- [ ] `skills/ql-plan/SKILL.md` adds a final step: after quantum.json is written + dag-validator completes, iterate stories and call `write_sprint_contract` per story.
- [ ] Idempotent — re-running `/ql-plan` overwrites `.handoffs/sprint-<storyId>.json`.
- [ ] New `tests/test_sprint_contract_ql_plan.sh`: simulate /ql-plan exit on a 3-story fixture; assert 3 `.handoffs/sprint-*.json` files appear with valid schema.
- [ ] Existing handoff tests (`test_handoff.sh` 38 assertions, `test_sprint_contract.sh` 11+) remain green.
- [ ] Typecheck/lint passes.

### US-005: G2 — `lib/api-rename.sh` helper

**Description:** As a developer renaming an API symbol across the codebase, I want a helper that scans both call sites AND doc comments, so I can confirm migrations are complete (avoiding the line-4 module-header miss that v0.6.0's US-001 dogfood encountered).

**Acceptance Criteria:**
- [ ] New `lib/api-rename.sh` with two functions:
  - `find_rename_targets(old_symbol, new_symbol, scope_glob)` emits `<file>:<line>:<context>` for every occurrence (code OR comment) of `old_symbol`.
  - `validate_rename_complete(old_symbol, scope_glob)` exits 0 if no occurrences remain, exits 1 with the file:line list otherwise.
- [ ] Both functions accept an optional `--exclude <glob>` flag to skip historical/CHANGELOG paths.
- [ ] New `tests/test_api_rename.sh`: synthetic 3-file fixture (1 call site, 1 doc comment, 1 string literal) — find_rename_targets emits all 3; validate_rename_complete fails until each is migrated.
- [ ] CHANGELOG documents the new helper as a developer tool (not a runtime dependency).
- [ ] Typecheck/lint passes.

### US-006: P5.B4-design — post-`/ql-brainstorm` spec-review

**Description:** As a planner, I want `spec-reviewer` invoked in a new `design-review` mode after `/ql-brainstorm` exits, reading the design doc and reporting structural gaps (missing sections, TBD markers, ambiguous goals, unstated non-goals, missing risks/mitigations) — advisory only in v0.6.3.

**Acceptance Criteria:**
- [ ] `agents/spec-reviewer.md` adds a `design-review` mode with explicit checklist: 8 sections expected (Overview / Stories at a glance / Wave plan / Per-story design / Architecture / Risk / Testing / Rollout); TBD/FIXME markers; "should work" / "TODO" hedge phrases; missing non-goals.
- [ ] `skills/ql-brainstorm/SKILL.md` adds a post-exit step: invoke spec-reviewer in `design-review` mode against the just-saved design doc; print findings to stderr.
- [ ] Findings are advisory: emitted to stderr, do NOT abort the skill.
- [ ] Operator can opt out via `QL_SKIP_PRE_IMPL_REVIEW=design`.
- [ ] New `tests/test_spec_review_design.sh`: synthetic design doc with 1 TBD + 1 vague goal → spec-reviewer flags both with file:line.
- [ ] Typecheck/lint passes.

### US-007: P5.B4-PRD — post-`/ql-spec` spec-review

**Description:** As a planner, I want `spec-reviewer` invoked in a new `prd-review` mode after `/ql-spec` exits, reading the PRD and reporting non-testable ACs, vague FRs, missing measurement methods, unspecified non-goals — advisory only in v0.6.3.

**Acceptance Criteria:**
- [ ] `agents/spec-reviewer.md` adds a `prd-review` mode with checklist: 9 standard PRD sections present; ACs have machine-verifiable criteria; FRs cite measurement methods; success metrics are quantifiable.
- [ ] `skills/ql-spec/SKILL.md` adds a post-exit step: invoke spec-reviewer in `prd-review` mode against the just-saved PRD; print findings to stderr.
- [ ] Advisory only; opt-out via `QL_SKIP_PRE_IMPL_REVIEW=prd`.
- [ ] New `tests/test_spec_review_prd.sh`: synthetic PRD with 1 vague AC ("works correctly") + 1 missing FR measurement → spec-reviewer flags both.
- [ ] Typecheck/lint passes.

### US-008: P5.B4-plan — post-`/ql-plan` spec-review

**Description:** As a planner, I want `spec-reviewer` invoked in a new `plan-review` mode after `/ql-plan` exits + dag-validator completes, reading quantum.json + PRD and reporting AC coverage gaps, command-test mismatches, missing wiring tasks — advisory only in v0.6.3.

**Acceptance Criteria:**
- [ ] `agents/spec-reviewer.md` adds a `plan-review` mode with checklist: every PRD AC is referenced by ≥1 story's `acceptanceCriteria`; every story with `testFirst:true` has at least one test command; every story creating a new module has a wiring task or a `consumedBy` field.
- [ ] `skills/ql-plan/SKILL.md` adds a post-exit step (after dag-validator + after US-004 sprint-contract write): invoke spec-reviewer in `plan-review` mode against quantum.json + PRD; print findings to stderr.
- [ ] Advisory only; opt-out via `QL_SKIP_PRE_IMPL_REVIEW=plan`.
- [ ] New `tests/test_spec_review_plan.sh`: synthetic quantum.json + PRD where 1 PRD AC is not represented in any story → spec-reviewer flags it with the missing AC text.
- [ ] Typecheck/lint passes.

### US-009: Dogfood retrospective + IDEA_REPORT_v4 + version bump

**Description:** As a project maintainer, I want a structured retrospective after Phase 8 captures findings from running v0.6.3 through the pipeline, an IDEA_REPORT_v4 mapping what's still open after v0.6.3, and plugin version bumped 0.6.2 → 0.6.3 across all three manifests.

**Acceptance Criteria:**
- [ ] `idea-stage/PIPELINE_REPORT_v4.md` documents v0.6.3 dogfood: total wall-clock, wave timings, cross-story-contract events, pre-impl review baseline (number of findings per stage), test-suite delta vs v0.6.2.
- [ ] `idea-stage/IDEA_REPORT_v4.md` lists what's still open after v0.6.3: P5.B2 (bidirectional reviewer), P5.B3 (`/ultrareview`), P5.B5 (AgentGA tournament), P5.C* frontier, plus any NEW gaps surfaced this run.
- [ ] `quantum-loop.sh --audit` re-run after Phase 8 merges; output captured; all metrics on target.
- [ ] CHANGELOG.md updated with v0.6.3 entry covering 8 user-facing stories.
- [ ] `.claude-plugin/plugin.json` + `.claude-plugin/marketplace.json` (both fields) + `.cursor-plugin/plugin.json` all bumped 0.6.2 → 0.6.3.
- [ ] Typecheck/lint passes (no test required; this story is documentation + version-bump only).

## Section 4: Functional Requirements

- **FR-1:** `parse_critic_arg` is removed; `--critic` arg-handler calls `parse_role_arg` exclusively.
- **FR-2:** `_availability_check` is role-aware: critic → none on miss; planner/executor → claude on miss.
- **FR-3:** Sprint-Contract has a new `otherCommands: string[]` field (optional, backward-compat).
- **FR-4:** Sprint-Contract `expectedTests` contains only test-pattern commands.
- **FR-5:** `write_routing_snapshot` calls `write_quantum_json` for atomic write + validation gate.
- **FR-6:** `/ql-plan` writes `.handoffs/sprint-<storyId>.json` per story at exit.
- **FR-7:** `lib/api-rename.sh` exposes `find_rename_targets` + `validate_rename_complete`.
- **FR-8:** `spec-reviewer` supports 3 new modes: `design-review`, `prd-review`, `plan-review`.
- **FR-9:** `/ql-brainstorm` invokes spec-reviewer in `design-review` mode at exit (advisory).
- **FR-10:** `/ql-spec` invokes spec-reviewer in `prd-review` mode at exit (advisory).
- **FR-11:** `/ql-plan` invokes spec-reviewer in `plan-review` mode at exit (advisory, post-dag-validator + post-sprint-contract-write).
- **FR-12:** `QL_SKIP_PRE_IMPL_REVIEW=design,prd,plan` env var disables individual stages (comma-separated).
- **FR-13:** Plugin version 0.6.2 → 0.6.3 across `.claude-plugin/plugin.json`, `.claude-plugin/marketplace.json` (both fields), `.cursor-plugin/plugin.json`.

## Section 5: Non-Goals (Out of Scope)

- **NG-1:** Pre-impl spec-review as a BLOCKING gate — explicitly advisory in v0.6.3; promotion to blocking is a future release.
- **NG-2:** P5.B2 bidirectional reviewer — deferred to v0.7.x.
- **NG-3:** P5.B3 `/ultrareview` parallel pattern — deferred.
- **NG-4:** P5.B5 AgentGA tournament — deferred.
- **NG-5:** P5.C frontier (HiveMind, GEPA, Skilldex, Attacker, etc.) — all deferred.
- **NG-6:** P4 AI-native ecosystem integration — blocked on upstream.
- **NG-7:** Schema migration for existing Sprint-Contract files — new `otherCommands` is additive only.
- **NG-8:** Bumping to 0.7.0 — bundle is patch-tier per user framing; new mechanisms are opt-in/advisory.

## Section 6: Design Considerations

UI: command-line only. The 3 new pre-impl review stages emit findings to stderr in the existing `FINDING_START..FINDING_END` block format; no new UI surfaces. Findings can be redirected: `bash quantum-loop.sh ... 2> review.log`.

Schema: 1 new optional Sprint-Contract field (`otherCommands`); backward-compat via "absent = empty array".

Env vars: 1 new (`QL_SKIP_PRE_IMPL_REVIEW`) for opt-out per stage.

## Section 7: Technical Considerations

- **Shell compatibility:** bash 4.3+ (consistent with v0.6.x).
- **External tools:** `git`, `grep`, `find`, `wc`, `ls`, `awk`, `jq`, `sha256sum`/`shasum` — already required.
- **`set -euo pipefail` safety:** all helpers wrap subprocess calls in `{ cmd 2>/dev/null ; } || true` per project convention.
- **Performance:** the 3 new pre-impl reviews each must complete in < 10 seconds on a typical design/PRD/plan size (≤ 10K characters input).
- **Security:** mode argument validated against fixed enum (`{design-review,prd-review,plan-review}`) to prevent injection.
- **Cross-platform:** all new tests must exercise both POSIX and Git Bash / MSYS paths per CLAUDE.md Platform Notes.

## Section 8: Success Metrics

- All 9 user stories pass with verifiable evidence.
- `bash tests/*.sh` exits 0 with ≥1,640 total assertions (was ~1,520 in v0.6.2; +120 from new tests).
- `quantum-loop.sh --audit` after Phase 8 merges still reports all 6 metrics on target.
- Plugin version bumped to 0.6.3 across all 3 manifests.
- IDEA_REPORT_v4 lists what's open after v0.6.3 (clear roadmap to v0.7.0).
- 0-retry execution record maintained from v0.6.0 baseline.

## Section 9: Open Questions

None. Bundle composition + framing fully resolved by user-confirmed answers.

## Lifecycle Checklist

- **First-run behavior** — All new pre-impl review modes are advisory; absent opt-out env var = enabled by default.
- **Returning-user behavior** — Existing v0.6.0 / v0.6.1 / v0.6.2 quantum.json + Sprint-Contract files load and run with one-line back-compat warnings on missing optional fields.
- **Update behavior** — Schema additions are additive only (`otherCommands` optional). Pre-impl reviews can be disabled per-stage via env var.
- **Error recovery** — Pre-impl reviews emit findings to stderr but never abort the pipeline. Spec-reviewer agent unavailability triggers a one-line warning + skip.
- **No-data / empty state** — `find_rename_targets` on a non-existent symbol returns 0 occurrences (exit 0); pre-impl reviews on minimal valid inputs return "no findings".
- **Uninstall / disable** — All new mechanisms are opt-out via env var or CLI flag. Removing the new lib helpers / modes affects no existing callers.

## Next Steps

Run `/quantum-loop:ql-plan` on this PRD to generate `quantum.json` with the wave DAG, contracts, and `fileConflicts`. Then `/quantum-loop:ql-execute` to ship.
