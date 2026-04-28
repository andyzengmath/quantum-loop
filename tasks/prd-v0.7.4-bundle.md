# PRD: v0.7.4 — patch-tier (N25 + routing E2E + sensitive-path fixture + worktree re-test + multi-runner foundation + G22 third pass + retrospective)

**Status:** Approved
**Date:** 2026-04-28
**Design doc:** `docs/plans/2026-04-28-v0.7.4-bundle-design.md`
**Source:** Operator combined scope #1/2/3/4/6/7 (session backlog) + IDEA_REPORT_v14
**Branch (planned):** `ql/v0.7.4-bundle`
**Target version:** 0.7.4 (patch bump from 0.7.3)
**Total effort estimate:** ~90 min (worktree-parallel Wave 0 + sequential Wave 1)

## Section 1: Introduction / Overview

7 stories shipping operator-defined combined scope (#1/2/3/4/6/7). Patch-tier framing — none of the items introduce a new architectural boundary individually. **First end-to-end dogfood of the quantum-loop skill pipeline at v0.7.x scale**: `/ql-brainstorm` → `/ql-spec` → `/ql-plan` → `/ql-execute --worktree` → `/soliton:pr-review` + `copilot:copilot-rescue`. Ninth multi-cycle populated-CSV run (27 → 30 rows).

## Section 2: Goals

- Close N25 from IDEA_REPORT_v14.
- Add provider-routing E2E test coverage.
- Add bundle-level sensitive-path dispatch fixture (vs N19 synthetic).
- Re-test worktree-isolation fix (5-layer architecture per memory `project_worktree_isolation`).
- Land multi-runner-manifest foundation (no actual runner integrations).
- Capture G22 third calibration pass with v0.7.4 advisory hook data (30 rows).
- Maintain 0-retry execution record.
- Bump plugin version 0.7.3 → 0.7.4.
- G30 self-validation re-run (expected: 9th LOW classification).
- Document dogfood-pipeline observations in retrospective (per-story dual-review delta soliton vs copilot-rescue).

## Section 3: User Stories

### US-001: N25 — QL_RESPAWN_CMD real-CLI smoke test

**Description:** As a developer maintaining the orchestrator-liveness lib, I want a smoke test that exercises `QL_RESPAWN_CMD` with a real `claude` CLI invocation so that auto-respawn confidence scales beyond the echo-stub Tests 8/10.

**Acceptance Criteria:**
- [ ] `tests/test_orchestrator_liveness.sh` adds Test 11 detecting `claude` via `command -v claude`.
- [ ] If `claude` is absent: skip-pass with stderr WARN; increment TOTAL +1 (counts as 1 PASS-skip); emit deferred-finding to `.handoffs/n25-deferred.md` with timestamp + machine info.
- [ ] If `claude` is present: set `QL_RESPAWN_CMD="claude --version"`, trigger stale path, assert rc=0 AND stdout contains regex `[0-9]+\.[0-9]+`.
- [ ] Wall-clock ≤15s ceiling.
- [ ] Existing 27 assertions remain green.
- [ ] Typecheck/lint passes (shellcheck-clean if available).

### US-002: Provider-routing E2E

**Description:** As a developer using per-role provider routing (`quantum.json.routing` snapshot), I want end-to-end test coverage of `lib/runner.sh::route_for_role` so that role-to-runner dispatch is regression-guarded.

**Acceptance Criteria:**
- [ ] NEW `tests/test_routing_e2e.sh` with 4 tests:
  - Test 1: known role returns expected runner (e.g., `implementer → claude`).
  - Test 2: 3 roles routed to 3 different runners (claude/codex/gemini stub).
  - Test 3: unknown role falls back to default runner with stderr WARN.
  - Test 4: empty/missing routing snapshot emits stderr ERROR + rc=1.
- [ ] Inline capture: this v0.7.4 cycle's `/ql-execute` records routing decisions in `quantum.json.execution.routingDecisions[]` (which agent invoked for which role per story).
- [ ] Retrospective US-007 cites the inline routing decisions.
- [ ] Typecheck/lint passes.

### US-003: Sensitive-path bundle test fixture

**Description:** As a developer maintaining the deep-review dispatch gate, I want a bundle-level fixture that constructs a real diff with sensitive paths (vs N19's synthetic patch) so that the MEDIUM/HIGH branches are exercised end-to-end including the diff-construction step.

**Acceptance Criteria:**
- [ ] `tests/test_deep_review_dispatch.sh` adds Test 9: synthesize a quantum.json with `tasks[].filePaths` including `auth/login.js` AND `config/.env`.
- [ ] Test 9 invokes `should_dispatch_deep_review` on the resulting diff path.
- [ ] Asserts tier=MEDIUM, score≥30, dispatch list has ≥3 reviewer agent names.
- [ ] Existing 19 assertions remain green; +3 new assertions (tier, score, dispatch-list-contains-reviewer).
- [ ] Typecheck/lint passes.

### US-004: Worktree-isolation re-test

**Description:** As a developer relying on parallel worktree execution, I want a re-test that verifies the 5-layer type-divergence architecture (memory `project_worktree_isolation`) plus a new edge-case test for concurrent shared-lib edits.

**Acceptance Criteria:**
- [ ] `tests/test_worktree_isolation.sh` (existing): runs cleanly under `bash tests/run_all.sh`.
- [ ] New Test N+1: spawn 2 concurrent worktrees both editing `lib/handoff.sh` with conflicting type signatures; verify type-auditor agent surfaces the conflict at wave-end OR (if agent-spawn is unavailable in CI) verify the static-analyzer surfaces it via `bash lib/type-auditor.sh check`.
- [ ] Skip-pass with WARN on Git Bash if `git worktree add --detach` fails (very old git).
- [ ] Existing assertions remain green.
- [ ] Typecheck/lint passes.

### US-005: Multi-runner-manifest foundation

**Description:** As a developer planning multi-runner support (issue #19 / memory `project_multi_runner`), I want a manifest schema + parser/validator/lister library so that v0.8.0 can build runner integrations on a stable foundation.

**Acceptance Criteria:**
- [ ] NEW `lib/multi-runner-manifest.sh` defines 3 functions:
  - `parse_manifest <path>` — reads YAML, emits JSON envelope to stdout, rc=0 on success / rc=1 + stderr ERROR on parse failure.
  - `validate_manifest <json>` — checks required fields (`name`, `command`, `version_flag`); emits stderr WARN per missing field; rc=0 if all present, rc=1 otherwise.
  - `list_runners <json>` — emits agent names array (one per line).
- [ ] NEW `runners/manifest.example.yaml` with 3 example runners (claude / codex / gemini-cli) — required fields populated.
- [ ] NEW `tests/test_multi_runner_manifest.sh` with 6 tests: parse-valid / parse-malformed-yaml / validate-missing-name / validate-ok / list-runners / cli-mode invocation.
- [ ] Library contract: NO shell flags at source time (mirrors `lib/handoff.sh`, `lib/finding-persist.sh`).
- [ ] Typecheck/lint passes.

### US-006: G22 third calibration pass

**Description:** As an operator tracking the severity rubric calibration, I want a third snapshot incorporating v0.7.4 advisory hook data (30 rows / ~64 findings) plus an updated bundle-tier comparison.

**Acceptance Criteria:**
- [ ] NEW `references/severity-rubric-calibration-v0.7.4.md` with:
  - Updated empirical tables from `bash references/severity-rubric-calibration-parse.sh` (30 rows minimum).
  - Bundle-tier comparison (still 1 minor / 8 patch — ratio worsens since v0.7.4 is patch-tier).
  - Plan-review MEDIUM trigger watch: explicitly note whether v0.7.4's plan-review hook emitted MEDIUM (first time in 9 cycles if it does).
  - Updated drift analysis with v0.7.4 column added to v0.7.0/v0.7.2 historical drift table.
- [ ] `CLAUDE.md` Process references updated v0.7.2 → v0.7.4 calibration doc.
- [ ] Grep verification: new doc contains "bundle-tier", "plan-review MEDIUM", "9-cycle".
- [ ] Typecheck/lint passes.

### US-007: Retrospective + IDEA_REPORT_v15 + version bump 0.7.3 → 0.7.4

**Description:** As an operator maintaining the v0.7.x release track, I want a retrospective that captures dogfood-pipeline observations + version bump artifacts.

**Acceptance Criteria:**
- [ ] `idea-stage/PIPELINE_REPORT_v15.md` documents v0.7.4 dogfood: 7 stories, outcomes, wave plan, G30 result, test-suite delta, dogfood pipeline observations (which skills auto-fired, manual-takeover events), per-story dual-review delta (soliton vs copilot-rescue findings).
- [ ] `idea-stage/IDEA_REPORT_v15.md` lists what's open after v0.7.4.
- [ ] `quantum-loop.sh --audit` output captured.
- [ ] G30 self-validation captured; `automated:true` recorded.
- [ ] CHANGELOG [0.7.4] entry covering all 6 substantive items + dogfood note.
- [ ] All 4 plugin manifest version fields bumped 0.7.3 → 0.7.4 (3 manifests).
- [ ] Typecheck/lint passes.

## Section 4: Functional Requirements

- **FR-1:** `tests/test_orchestrator_liveness.sh` Test 11 exercises QL_RESPAWN_CMD with real claude CLI when available; skip-passes when absent.
- **FR-2:** `tests/test_routing_e2e.sh` exists and exercises 4 routing scenarios (known/multi-role/unknown/missing).
- **FR-3:** `tests/test_deep_review_dispatch.sh` Test 9 exercises real bundle-level sensitive-path detection.
- **FR-4:** `tests/test_worktree_isolation.sh` runs clean + new edge-case test.
- **FR-5:** `lib/multi-runner-manifest.sh` exists with parse/validate/list functions; CLI-mode supported.
- **FR-6:** `references/severity-rubric-calibration-v0.7.4.md` exists with bundle-tier comparison + plan-review MEDIUM trigger note.
- **FR-7:** Plugin version 0.7.4 across 3 manifests; CHANGELOG [0.7.4] present.

## Section 5: Non-Goals (≥3 required)

- **NG-1:** Auto-discovery for multi-runner-manifest (deferred to v0.8.0+).
- **NG-2:** Actual runner integrations (codex/gemini implementer agents) — schema only in v0.7.4.
- **NG-3:** Auto-respawn integration with real claude in production mode beyond Test 11 smoke (operators still set QL_RESPAWN_CMD manually).
- **NG-4:** Plan-review rubric language edits (defer to v0.8.0 if MEDIUM still doesn't trigger).
- **NG-5:** Bumping to 0.8.0 — patch-tier per operator framing.
- **NG-6:** New codebasePatterns harvest — p001-p011 carry over unchanged.

## Section 6: Design Considerations (N/A)

CLI-only changes; no UI/UX surfaces.

## Section 7: Technical Considerations

- Cross-platform: bash 4.3+ on Git Bash + Linux.
- YAML parsing: prefer `yq` if available, fall back to `python3 -c 'import yaml'`, finally fall back to handcrafted shell parser for trivial schema (3-field-per-runner only).
- Worktree mode for `/ql-execute`: tests `git worktree add --detach` availability in pre-flight.
- No env var changes to existing keys; no schema changes to quantum.json (routing snapshot already exists).

## Section 8: Success Metrics

- All 7 stories first-attempt PASS.
- CSV at ≥30 rows.
- Test count: 27 → 27+(1 N25)+(4 routing-e2e)+(3 sensitive-path)+(1 worktree-edge)+(6 multi-runner) = 42 assertions across affected files.
- 9th consecutive LOW G30 classification.
- Dogfood pipeline observations document at least 3 distinct findings (skill drift / soliton-vs-copilot delta / wave parallelization success).

## Section 9: Open Questions

- Will plan-review MEDIUM trigger on the multi-wave shape this cycle? (tracked, non-blocking)
- Will worktree mode succeed end-to-end without manual takeover? (tracked, non-blocking — manual takeover is established fallback)

## Lifecycle Checklist (mandatory)

- **First-run behavior:** N/A (no user-facing first-run). Internal: each new test file starts with header comment + `set -uo pipefail`.
- **Returning-user behavior:** N/A (no persistent user state). Internal: existing tests preserve green; new tests pass cleanly.
- **Update behavior:** Plugin version 0.7.3 → 0.7.4 across 3 manifests + CHANGELOG. No migration needed.
- **Error recovery:** Each new test has skip-pass for missing-tool scenarios (`claude`, `git worktree add --detach`, etc.).
- **No-data/empty state:** US-002 Test 4 explicitly covers empty/missing routing snapshot.
- **Uninstall/disable:** N/A (additive only — no removed functionality).

## Next Steps

Run `/quantum-loop:plan` to generate `quantum.json` with DAG structure for the 7 stories.
