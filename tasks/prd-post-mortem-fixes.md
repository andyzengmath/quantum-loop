# PRD: Post-Mortem Fixes — All 7 Issues

**Feature:** Post-mortem fixes from Math Research Agent execution
**Design Doc:** `docs/plans/2026-03-09-post-mortem-fixes-design.md`
**Gap Audit:** `docs/post-mortems/2026-03-09-gap-audit.md`
**Date:** 2026-03-09

---

## Section 1: Introduction/Overview

The Math Research Agent (34 stories, 80 tasks) exposed 7 categories of bugs in the quantum-loop pipeline, documented in `docs/post-mortems/2026-03-09-math-research-agent.md`. A gap audit against v0.3.0 revealed that issues #1 and #4 are ~80% addressed, #2 is ~50%, #5 is ~20%, and #3, #6, #7 are 0-10%. This feature closes all remaining gaps through schema changes, agent protocol updates, and script-level runtime enforcement, delivered in 3 independent layers.

---

## Section 2: Goals

- Close all 7 post-mortem issues to 100% coverage
- Add 5 new fields to quantum.json schema (`contracts`, `wiring_verification`, `consumedBy`, `startedAt`, `coverageThreshold`) with generation logic in ql-plan
- Make the quality-reviewer enforce project coding standards and configurable coverage thresholds
- Eliminate the "permanently invisible story" bug via stale detection in both scripts and orchestrator
- Add lifecycle awareness to the brainstorm and spec phases to prevent PRD gaps
- Auto-generate execution observation documents after every run for continuous pipeline improvement
- Maintain backward compatibility: existing quantum.json files without new fields continue to work

---

## Section 3: User Stories

### US-001: Add `contracts` field to quantum.json schema
**Description:** As a pipeline user, I want cross-story agreements documented in quantum.json so that parallel agents use consistent values for shared entities.

**Acceptance Criteria:**
- [ ] `quantum.json.example` contains a top-level `contracts` object with at least 2 example categories (`secret_keys`, `shared_types`)
- [ ] Each contract category maps logical names to canonical string values
- [ ] Contract values optionally support a `pattern` field with a regex for validation (e.g., `"pattern": "^[a-z][a-z0-9-]*$"`)
- [ ] Existing fields in `quantum.json.example` are unchanged
- [ ] JSON is valid (parseable by `jq .` and `node -e "JSON.parse(...)"`)

---

### US-002: Add `wiring_verification` field to quantum.json schema
**Description:** As a pipeline user, I want machine-verifiable wiring checks on tasks so that new modules are guaranteed to be imported by their consumers.

**Acceptance Criteria:**
- [ ] `quantum.json.example` contains at least one task with a `wiring_verification` object
- [ ] `wiring_verification` has `file` (string) and `must_contain` (array of strings) fields
- [ ] Tasks without `wiring_verification` are unaffected (field is optional)
- [ ] JSON is valid

---

### US-003: Add `consumedBy` and `coverageThreshold` fields to quantum.json schema
**Description:** As a pipeline user, I want to declare cross-story consumption relationships and coverage thresholds so that agents respect shared components and enforce test quality.

**Acceptance Criteria:**
- [ ] `quantum.json.example` contains at least one task with `consumedBy` (array of story ID strings)
- [ ] `quantum.json.example` contains a top-level `coverageThreshold` field (number)
- [ ] `quantum.json.example` contains a top-level `staleThresholdMinutes` field (number, default 20)
- [ ] Tasks without `consumedBy` are unaffected (field is optional)
- [ ] Missing `coverageThreshold` means coverage is reported but doesn't block
- [ ] Missing `staleThresholdMinutes` defaults to 20
- [ ] JSON is valid

---

### US-004: Update ql-plan to generate `contracts`
**Description:** As a planner, I want ql-plan to automatically identify and generate cross-story contracts so that shared values are documented before execution begins.

**Acceptance Criteria:**
- [ ] `skills/ql-plan/SKILL.md` contains a "Contracts Generation" step after the dependency DAG step
- [ ] The step instructs the planner to scan for values appearing in 2+ stories' acceptance criteria or task descriptions
- [ ] The step instructs the planner to group contract candidates by category (secret_keys, env_vars, shared_types, api_routes, event_names, css_classes)
- [ ] The step includes the rule: "When in doubt, add it — an unused contract entry costs nothing"
- [ ] The step includes optional `pattern` field guidance for regex validation
- [ ] No existing ql-plan steps are removed or reordered

---

### US-005: Update ql-plan to generate `wiring_verification` and `consumedBy`
**Description:** As a planner, I want ql-plan to generate wiring verification and consumption metadata so that the spec-reviewer and implementer can enforce them mechanically.

**Acceptance Criteria:**
- [ ] `skills/ql-plan/SKILL.md` contains a "wiring_verification Generation" rule
- [ ] The rule states: tasks that create new modules/handlers/components SHOULD have `wiring_verification` unless wiring is handled by a dependent story via `consumedBy`
- [ ] `skills/ql-plan/SKILL.md` contains a "consumedBy Generation" rule
- [ ] The rule states: if a task's output is listed in a dependent story's acceptance criteria, it MUST have `consumedBy`
- [ ] The consumedBy rule includes: the planner adds to the consumer story's first task description "Import <component> from <path> (created by <Story A ID>). Do NOT create an inline replacement."
- [ ] No existing ql-plan steps are removed or reordered

---

### US-006: Update ql-plan to generate `coverageThreshold` and strengthen `testFirst` mandate
**Description:** As a planner, I want ql-plan to enforce test coverage thresholds and default testFirst to true so that TDD is a mandate, not a suggestion.

**Acceptance Criteria:**
- [ ] `skills/ql-plan/SKILL.md` contains a "coverageThreshold Generation" step that instructs the planner to ask the user or infer from project config (`.nycrc`, `jest.config`, `pyproject.toml [tool.coverage]`)
- [ ] The current testFirst guidance (lines ~111-122) is replaced with a mandate: `testFirst: true` is the default for ALL tasks
- [ ] Exempt categories are limited to: config/scaffold files, pure type definitions, documentation-only tasks, the test task itself
- [ ] For any exempt task, the planner MUST add a `notes` field: `"testFirst: false — <reason>"`
- [ ] The anti-rationalization line is present: "If a task has an `if`, a loop, a data transformation, or calls an external API, it is NOT config. Set `testFirst: true`."
- [ ] No existing ql-plan steps are removed or reordered

---

### US-007: Inject coding standards into quality-reviewer
**Description:** As a reviewer, I want the quality-reviewer to read and enforce project coding standards so that immutability violations and style issues are caught before merge.

**Acceptance Criteria:**
- [ ] `agents/quality-reviewer.md` Inputs section lists a new input #5: CODING_STANDARDS — read from CLAUDE.md, `.claude/rules/*.md`, and `codebasePatterns` array in quantum.json
- [ ] A new review dimension #8 "Coding Standards Compliance" is added after the existing 7
- [ ] Dimension #8 instructs: read codebasePatterns from quantum.json, verify each rule against the diff
- [ ] Dimension #8 instructs: read project CLAUDE.md and `.claude/rules/` for additional rules
- [ ] Dimension #8 states: violations of explicitly documented rules are CRITICAL severity
- [ ] Existing 7 review dimensions are unchanged

---

### US-008: Add coverage gate to quality-reviewer
**Description:** As a reviewer, I want the quality-reviewer to enforce a configurable coverage threshold so that stories adding code without tests are blocked.

**Acceptance Criteria:**
- [ ] `agents/quality-reviewer.md` contains a "Coverage Gate" section after the review dimensions
- [ ] When `coverageThreshold` is present in quantum.json: reviewer runs the project's coverage tool on changed files
- [ ] Coverage tool detection order: c8 → nyc → pytest-cov → go test -cover → JaCoCo
- [ ] If coverage < threshold: flag as CRITICAL
- [ ] If `coverageThreshold` is absent: report coverage in summary but do not block
- [ ] If coverage tool cannot be found/run: warn and skip on first run. After the first successful coverage measurement in any story during this execution, treat missing coverage as CRITICAL for subsequent stories.
- [ ] Review output includes: coverage percentage for changed files, which files are below threshold

---

### US-009: Add wiring_verification check to spec-reviewer
**Description:** As a reviewer, I want the spec-reviewer to mechanically verify wiring assertions so that unwired modules are caught with zero agent judgment.

**Acceptance Criteria:**
- [ ] `agents/spec-reviewer.md` contains a "Wiring Verification" section
- [ ] For each task with a `wiring_verification` field: reviewer reads `wiring_verification.file` and greps for each string in `must_contain`
- [ ] Missing string = CRITICAL spec failure with message: "Task <T-ID> requires '<string>' in <file>, but it is missing"
- [ ] Present string = pass (no further judgment)
- [ ] Tasks without `wiring_verification` are unaffected
- [ ] Existing spec-reviewer checks are unchanged

---

### US-010: Update implementer to read contracts and respect consumedBy
**Description:** As an implementer agent, I want to read contracts before implementing and respect consumedBy declarations so that I use canonical values and don't duplicate existing components.

**Acceptance Criteria:**
- [ ] `agents/implementer.md` contains a "Read Contracts" section after Step 1 (Read State)
- [ ] The section instructs: read the `contracts` object, use EXACT values from contracts for any matching category
- [ ] The section instructs: if contract has a `pattern` field, validate that the value matches the regex
- [ ] The section instructs: if the contract doesn't cover the agent's case, note it in progress entry
- [ ] Anti-rationalization line present: "I know a better name" is not a valid reason to deviate
- [ ] If the agent disagrees with a contract value, it MUST halt and ask the orchestrator to confirm (propose-and-wait) rather than silently deviating
- [ ] `agents/implementer.md` contains a "Respect consumedBy" section in the Integration Wiring Check
- [ ] The section instructs: before creating a new component, check if another task has `consumedBy` pointing to YOUR story — if yes, import rather than inline
- [ ] Existing implementer steps are unchanged

---

### US-011: Add lifecycle question to ql-brainstorm
**Description:** As a brainstormer, I want ql-brainstorm to ask about lifecycle scenarios so that operational concerns are surfaced before the spec phase.

**Acceptance Criteria:**
- [ ] `skills/ql-brainstorm/SKILL.md` Phase 1 question list contains a new question #7: LIFECYCLE
- [ ] The question has 4 lettered options: A (one-shot tool), B (returning users), C (integrates into existing system), D (multiple of the above)
- [ ] The question appears after question #6 (EXISTING SOLUTIONS)
- [ ] Existing 6 questions are unchanged
- [ ] The question count guidance says "Ask 4-8 questions" (or is updated to accommodate 7 categories)

---

### US-012: Add lifecycle checklist to ql-spec
**Description:** As a spec writer, I want ql-spec to enforce a lifecycle checklist so that first-run, returning-user, update, error recovery, empty state, and uninstall scenarios are explicitly addressed.

**Acceptance Criteria:**
- [ ] `skills/ql-spec/SKILL.md` Pre-Save Checklist contains a "Lifecycle Checklist" subsection
- [ ] The checklist is marked "mandatory for user-facing features"
- [ ] 6 items: First-run behavior, Returning-user behavior, Update behavior, Error recovery, No-data/empty state, Uninstall/disable
- [ ] Each item must be addressed or marked "N/A" with justification — silent skipping is forbidden
- [ ] Existing Pre-Save Checklist items are unchanged

---

### US-013: Add `startedAt` timestamp to orchestrator and scripts
**Description:** As a pipeline operator, I want the caller (script or orchestrator) to write a `startedAt` timestamp before dispatching each agent so that stale stories can be detected.

**Acceptance Criteria:**
- [ ] `agents/orchestrator.md` writes `startedAt` (ISO 8601 UTC) to quantum.json before dispatching an implementer subagent (both sequential and parallel paths)
- [ ] `quantum-loop.sh` writes `startedAt` via `jq` before spawning each agent (both sequential and parallel modes)
- [ ] `quantum-loop.ps1` writes `startedAt` via `jq` before spawning each agent
- [ ] `templates/quantum-loop.sh` writes `startedAt` via `node -e` before spawning each agent
- [ ] `startedAt` is cleared (set to null) when a story transitions to `passed`, `failed`, or `blocked`
- [ ] Existing script logic is unchanged beyond the new writes
- [ ] No changes to `lib/*.sh` files (new functions go in the scripts themselves)

---

### US-014: Add stale story detection to orchestrator and scripts
**Description:** As a pipeline operator, I want stale stories (in_progress too long) automatically detected and retried so that silently-exited agents don't leave stories permanently invisible.

**Acceptance Criteria:**
- [ ] `agents/orchestrator.md` contains a "Step 1B: Detect Stale Stories" section between crash recovery and DAG query
- [ ] The stale threshold is read from quantum.json `staleThresholdMinutes` (default 20), overridable by CLI flag `--stale-timeout`
- [ ] Detection logic: if `status === "in_progress"` and `now - startedAt > threshold`, set `status = "failed"`, increment `retries.attempts`, add failureLog entry with `"phase": "stale_detection"`, clear `startedAt`
- [ ] If `retries.attempts >= retries.maxAttempts`: set status to `"blocked"`
- [ ] `quantum-loop.sh` contains a `detect_stale_stories()` function called at top of main loop (after crash recovery, before DAG query)
- [ ] `quantum-loop.ps1` contains equivalent `Detect-StaleStories` function
- [ ] `templates/quantum-loop.sh` contains equivalent using `node -e`
- [ ] `quantum-loop.sh` accepts `--stale-timeout N` CLI flag (default 20)
- [ ] `quantum-loop.ps1` accepts `-StaleTimeout N` parameter (default 20)
- [ ] No changes to `lib/*.sh` files

---

### US-015: Add CLAUDE.md defensive check for in_progress stories
**Description:** As an implementer agent, I want Step 3 to include a defensive check so that I don't accidentally interfere with another agent's in-progress work.

**Acceptance Criteria:**
- [ ] `CLAUDE.md` Step 3 (Select Story) contains a defensive check after the eligibility rules
- [ ] The check states: if a story is `in_progress` and NOT assigned to this agent, log a warning and skip it
- [ ] The check states: if in worktree mode and the assigned story is `in_progress` with `startedAt` older than 10 minutes, treat as retry and proceed normally
- [ ] Existing Step 3 eligibility rules are unchanged

---

### US-016: Add final verification sweep to scripts
**Description:** As a pipeline operator, I want the scripts to run a final test suite before declaring COMPLETE so that a broken build is never marked as done.

**Acceptance Criteria:**
- [ ] `quantum-loop.sh` runs the project's test suite before outputting COMPLETE (both sequential and parallel modes)
- [ ] If test suite fails: log "FINAL SWEEP FAILED: test suite", exit with error code (do NOT declare COMPLETE)
- [ ] `quantum-loop.sh` runs an import smoke test: `node -e "require(...)"` for Node projects, `python -c "import ..."` for Python projects, `go build ./...` for Go projects
- [ ] Import smoke test failure is a WARNING (logged but doesn't block COMPLETE)
- [ ] `quantum-loop.ps1` runs the test suite before declaring COMPLETE with equivalent logic
- [ ] `templates/quantum-loop.sh` runs the test suite before declaring COMPLETE
- [ ] No changes to `lib/*.sh` files

---

### US-017: Auto-generate execution observations document
**Description:** As a pipeline user, I want an observations document auto-generated after every execution so that failure patterns and improvement opportunities are captured for continuous improvement.

**Acceptance Criteria:**
- [ ] `agents/orchestrator.md` contains a "Step 5: Generate Execution Observations" section after Step 4
- [ ] The observations document is always generated locally to `docs/post-mortems/YYYY-MM-DD-<branchName>-observations.md`
- [ ] Document contains: header (date, story counts, execution mode, iterations, wall-clock time), failure summary table, patterns observed (recurring failure modes, what worked well, suggested improvements), raw data (progress log and failure logs in collapsed `<details>` sections)
- [ ] `quantum-loop.sh` generates the observations doc after the main loop exits (using `jq` to extract data)
- [ ] `quantum-loop.ps1` generates the observations doc after the main loop exits
- [ ] The generated doc is committed: `git add <file> && git commit -m "docs: execution observations for <branchName>"`
- [ ] No changes to `lib/*.sh` files

---

### US-018: Optional GitHub issue filing for execution observations
**Description:** As a pipeline user, I want to optionally file observations as a GitHub issue on the quantum-loop repo so that recurring issues feed back into pipeline improvements.

**Acceptance Criteria:**
- [ ] `agents/orchestrator.md` Step 5B asks the user (via `AskUserQuestion` tool) before filing: "I found N issues worth reporting. Would you like me to file a GitHub issue on andyzengmath/quantum-loop with these observations?"
- [ ] Issue is only filed if the user confirms
- [ ] Issue is only proposed when observations contain: blocked stories, recurring failure patterns (same root cause in 2+ stories), or stale story detections
- [ ] Issue uses: `gh issue create --repo andyzengmath/quantum-loop --title "Execution observations: <branchName> (<date>)" --body "<observations doc content>" --label "execution-feedback"`
- [ ] If `gh` is not available or the command fails: skip silently, the local doc is the primary artifact
- [ ] `quantum-loop.sh` prompts: `read -p "File observations as GitHub issue on quantum-loop? [y/N] "` — defaults to No
- [ ] If running non-interactively (piped input, `--non-interactive` flag): skip the prompt entirely
- [ ] `quantum-loop.ps1` prompts equivalently with `Read-Host` — defaults to No

---

### US-019: Shell tests for stale detection, startedAt, final sweep, and observations
**Description:** As a developer, I want shell tests covering the new runtime behavior so that regressions are caught.

**Acceptance Criteria:**
- [ ] `tests/test_stale_detection.sh` exists with tests: stale story (>threshold) resets to failed; retry count increments; maxAttempts triggers blocked; non-stale stories are untouched; configurable threshold respected
- [ ] `tests/test_started_at.sh` exists with tests: startedAt written before spawn (ISO 8601 UTC format); startedAt cleared after story completes (passed/failed/blocked)
- [ ] `tests/test_final_sweep.sh` exists with tests: COMPLETE blocked when test suite fails; COMPLETE allowed when test suite passes; import smoke test warning logged on failure but doesn't block
- [ ] `tests/test_observations.sh` exists with tests: observations doc created in docs/post-mortems/; doc contains expected sections (header, failure summary, raw data); doc committed to git; GitHub issue NOT filed without user confirmation
- [ ] All new tests pass when run via `bash tests/test_<name>.sh`
- [ ] Existing tests in `tests/` continue to pass (no regressions)

---

## Section 4: Functional Requirements

### Schema
- FR-1: quantum.json SHALL support a top-level `contracts` object mapping category names to key-value pairs of logical names and canonical string values
- FR-2: Contract values SHALL optionally include a `pattern` field containing a regex for validation
- FR-3: quantum.json tasks SHALL support an optional `wiring_verification` object with `file` (string) and `must_contain` (array of strings) fields
- FR-4: quantum.json tasks SHALL support an optional `consumedBy` field (array of story ID strings)
- FR-5: quantum.json SHALL support a top-level `coverageThreshold` field (number, optional)
- FR-6: quantum.json SHALL support a top-level `staleThresholdMinutes` field (number, default 20)
- FR-7: quantum.json stories SHALL support a `startedAt` field (ISO 8601 UTC string or null), written at runtime by the caller
- FR-8: All new fields SHALL be optional — existing quantum.json files without them SHALL continue to work

### Planning
- FR-9: ql-plan SHALL generate a `contracts` section when 2+ stories reference the same logical entity
- FR-10: ql-plan SHALL generate `wiring_verification` on tasks that create new modules to be imported by existing files
- FR-11: ql-plan SHALL generate `consumedBy` when a task's output is listed in a dependent story's acceptance criteria
- FR-12: ql-plan SHALL ask the user for `coverageThreshold` or infer it from project config files
- FR-13: ql-plan SHALL default `testFirst: true` for all tasks, with explicit `notes` justification required for `testFirst: false`

### Review
- FR-14: The quality-reviewer SHALL read coding standards from CLAUDE.md, `.claude/rules/*.md`, and `codebasePatterns` in quantum.json
- FR-15: The quality-reviewer SHALL treat violations of documented coding standards as CRITICAL severity
- FR-16: The quality-reviewer SHALL run the project's coverage tool when `coverageThreshold` is set and fail if coverage is below threshold
- FR-17: Coverage tool detection order SHALL be: c8 → nyc → pytest-cov → go test -cover → JaCoCo
- FR-18: If coverage tool is not found: skip on first run, treat as CRITICAL after first successful measurement in any story during the execution
- FR-19: The spec-reviewer SHALL grep for each `wiring_verification.must_contain` string in the target file and flag missing strings as CRITICAL

### Implementation
- FR-20: The implementer SHALL read the `contracts` section before implementing and use exact contract values
- FR-21: If an implementer disagrees with a contract value, it SHALL halt and propose the change to the orchestrator (propose-and-wait) rather than silently deviating
- FR-22: The implementer SHALL check `consumedBy` before creating new components and import existing ones rather than inlining replacements

### Runtime
- FR-23: The caller (script or orchestrator) SHALL write `startedAt` to quantum.json before dispatching each agent
- FR-24: `startedAt` SHALL be cleared when a story transitions to passed, failed, or blocked
- FR-25: At the start of each iteration/wave, the caller SHALL detect stories where `status === "in_progress"` and `now - startedAt > staleThresholdMinutes` and reset them to failed
- FR-26: The stale threshold SHALL be configurable via quantum.json `staleThresholdMinutes` field (default 20) and overridable by CLI flag (`--stale-timeout` / `-StaleTimeout`)
- FR-27: Scripts SHALL run the full test suite before declaring COMPLETE; failure SHALL prevent COMPLETE
- FR-28: Scripts SHALL run an import smoke test before COMPLETE; failure SHALL be a warning only

### Observations
- FR-29: After every execution (COMPLETE, BLOCKED, or max iterations), an observations document SHALL be generated to `docs/post-mortems/YYYY-MM-DD-<branchName>-observations.md`
- FR-30: The observations document SHALL contain: header with stats, failure summary table, pattern analysis, and raw data in collapsed sections
- FR-31: The observations document SHALL be committed to git automatically
- FR-32: GitHub issue filing SHALL only be proposed when observations contain blocked stories, recurring failures, or stale detections
- FR-33: GitHub issue filing SHALL require explicit user confirmation (default No)
- FR-34: Non-interactive script runs SHALL skip the GitHub issue prompt entirely

### Lifecycle
- FR-35: ql-brainstorm SHALL include a lifecycle question with options for one-shot, returning-user, integration, and multiple scenarios
- FR-36: ql-spec SHALL include a 6-item lifecycle checklist (first-run, returning-user, update, error recovery, empty state, uninstall/disable) mandatory for user-facing features

---

## Section 5: Non-Goals (Out of Scope)

1. **CI/CD integration** — No GitHub Actions, markdownlint, or automated schema validation pipelines
2. **Visual dashboard** — No TUI, web UI, or real-time progress visualization
3. **Changes to `lib/*.sh`** — All new functions (stale detection, startedAt, observations) go in the scripts themselves, not in the shared shell libraries
4. **quantum.json schema validator** — No JSON Schema file or runtime validation tool; the schema is documented by example
5. **Automated tooling installation** — The coverage gate and import smoke test use whatever tools the project already has; they do not install c8, nyc, etc.
6. **Backward-incompatible changes** — Existing quantum.json files without new fields must continue to work

---

## Section 6: Design Considerations

- All changes are to `.md` documentation files and `.sh`/`.ps1` scripts. No compiled code, no dependencies added.
- The 3-layer delivery (Schema → Agent protocols → Scripts) allows independent review and merge.
- The `contracts` field is freeform by design — the planner decides categories. This avoids a rigid schema that can't handle novel cross-story agreements.
- The `wiring_verification` check is intentionally mechanical (grep for exact string). No AI judgment means no AI rationalization.
- The propose-and-wait pattern for contract disagreements (FR-21) prevents silent deviation while still allowing legitimate corrections.

---

## Section 7: Technical Considerations

- **Backward compatibility:** All new quantum.json fields are optional. Scripts and agents check `if field exists` before using it.
- **Script dependencies:** `quantum-loop.sh` uses `jq` + `date` (bash 4+). `quantum-loop.ps1` uses `jq` + PowerShell 5.1+. `templates/quantum-loop.sh` uses `node` only. No new dependencies.
- **Stale detection timing:** The 20-minute default is 5 minutes longer than the agent timeout (15 min) to avoid false positives from slow-but-progressing agents. The CLI override allows tuning for projects with longer tasks.
- **Coverage tool ratchet:** The "skip first, enforce after" pattern (FR-18) prevents blocking on projects that don't have coverage tools yet, while ensuring coverage is enforced once the tool is confirmed available.
- **Observations commit:** The auto-commit of the observations doc happens after the feature branch work, so it doesn't interfere with the feature's commit history. It's a separate "docs:" commit.

---

## Section 8: Success Metrics

- **Wiring bugs eliminated:** Zero unwired module bugs in the next 3 pipeline runs (currently ~2 per run)
- **Contract consistency:** Zero cross-story constant/name mismatches in the next 3 parallel runs
- **Coding standard violations caught:** Quality-reviewer catches immutability and style violations that previously passed (manual spot-check on next run)
- **No stale stories:** Zero stories left permanently in `in_progress` state across 5 runs
- **Coverage enforced:** All stories in projects with `coverageThreshold` set meet the threshold or are explicitly flagged
- **Lifecycle gaps:** Next 3 PRDs generated via ql-spec include lifecycle checklist with all items addressed
- **Observations generated:** Every execution produces an observations doc in `docs/post-mortems/`

---

## Section 9: Open Questions

1. Should the observations document include a machine-readable summary (JSON block) in addition to the markdown, to enable automated trend analysis across runs?
2. Should the `contracts` field support inheritance — e.g., a base contract in a shared config that quantum.json extends?
3. What is the right behavior when two scripts (e.g., running in parallel terminals) both try to write `startedAt` for different stories simultaneously? The existing `json_atomic_update` (tmp + mv) should handle this, but it hasn't been tested for concurrent writes.
