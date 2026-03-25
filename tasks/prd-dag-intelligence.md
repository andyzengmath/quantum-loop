# PRD: DAG Intelligence — Parallel Specialist Validation for ql-plan

## 1. Introduction/Overview

The quantum-loop planner (`ql-plan`) generates dependency DAGs that drive autonomous execution, but it produces DAGs with avoidable inefficiencies: sequential bottlenecks that waste wall-clock time, duplicate implementations across parallel stories, and incomplete `fileConflicts` that cause preventable merge conflicts. This feature adds a post-generation validation system using parallel specialist agents that detect these defects and auto-restructure the DAG before the user reviews it.

The system is triggered automatically as the final step of `ql-plan` and produces a DAG Health Report alongside the restructured `quantum.json`.

## 2. Goals

- Detect and restructure sequential bottlenecks in the dependency DAG, reducing total wave count
- Detect functional duplication across stories and extract shared utilities into stub stories before execution
- Auto-compute complete `fileConflicts` from task `filePaths` intersections with severity classification
- Enforce hard scheduling constraints for high-severity file conflicts via synthetic dependencies
- Provide a DAG Health Report that summarizes all findings and restructuring actions
- Run validation in under 2 minutes for plans with up to 30 stories
- Maintain idempotency: re-running on an already-validated plan is a no-op

## 3. User Stories

### US-001: Add `storyType` field to quantum.json schema

**Description:** As a planner agent, I want each story in quantum.json to have a `storyType` field so that downstream validators can distinguish types-only stories from logic stories without heuristic guessing.

**Acceptance Criteria:**
- [ ] `quantum.json.example` includes `storyType` field on story objects with allowed values: `"types-only"`, `"logic"`, `"config"`, `"test"`
- [ ] The `storyType` field is documented with a comment or adjacent description explaining each value
- [ ] Existing stories without `storyType` are handled gracefully (default to `"logic"` when absent)
- [ ] Typecheck/lint passes (shellcheck on any modified .sh files)

### US-002: Add `dagValidation` block and severity field to quantum.json schema

**Description:** As a dag-validator agent, I want a `dagValidation` top-level block in quantum.json to store validation results, and a `severity` field on `fileConflicts` entries, so that validation state is traceable and conflict severity is queryable.

**Acceptance Criteria:**
- [ ] `quantum.json.example` includes `dagValidation` top-level object with fields: `timestamp` (ISO 8601), `bottlenecks` (array), `duplicationRisks` (array), `fileConflictsComputed` (number), `stubsCreated` (array of story IDs)
- [ ] `quantum.json.example` `fileConflicts` entries include a `severity` field with allowed values: `"high"`, `"medium"`, `"low"`
- [ ] Both new fields are optional — existing quantum.json files without them remain valid
- [ ] Typecheck/lint passes

### US-003: Create `references/dag-validation.md` reference document

**Description:** As a dag-validator and its specialist agents, I want a reference document containing stop-word lists, Jaccard threshold configuration, bottleneck heuristics, and severity classification rules so that validation behavior is configurable without modifying agent prompts.

**Acceptance Criteria:**
- [ ] File exists at `skills/ql-plan/references/dag-validation.md`
- [ ] Contains a "Standard Stop-Words" section with a list of at least 15 common non-technical terms to exclude from duplication keyword comparison (e.g., "implement", "create", "add", "build", "test", "update", "module", "component", "function", "class", "handle", "setup", "configure", "write", "define")
- [ ] Contains a "Project-Configurable Stop-Words" section explaining how to add project-specific terms via a `dagValidation.stopWords` array in quantum.json
- [ ] Contains a "Jaccard Threshold" section documenting the default 0.3 threshold and how to override it via `dagValidation.jaccardThreshold` in quantum.json
- [ ] Contains a "Bottleneck Heuristics" section documenting: linear chain length > 2, single-story waves, fan-out blocker (5+ downstream)
- [ ] Contains a "Severity Classification" section documenting: high (barrel/index files, shared type files, config files), medium (same-wave source file overlap), low (different-wave source file overlap)
- [ ] Contains a "Plan Size Thresholds" section documenting: < 5 stories (skip bottleneck analysis), 5-15 (sequential specialists), 16+ (parallel specialists)
- [ ] Contains a "Barrel File Patterns" section listing recognized barrel file names per language: `index.ts`, `index.js`, `__init__.py`, `mod.rs`, `lib.rs`
- [ ] Typecheck/lint passes

### US-004: Create `conflict-auditor` specialist agent

**Description:** As a dag-validator coordinator, I want a conflict-auditor agent that computes complete `fileConflicts` from task `filePaths` intersections with severity classification so that no conflicting files are missed.

**Acceptance Criteria:**
- [ ] File exists at `agents/conflict-auditor.md`
- [ ] Agent frontmatter includes `name`, `description`, and `tools` fields
- [ ] Agent receives stories array with task `filePaths` as input
- [ ] Agent computes file-to-story mapping by iterating all tasks' `filePaths` arrays
- [ ] Agent filters to files appearing in 2+ stories
- [ ] Agent classifies severity per rules in `references/dag-validation.md`: "high" for barrel/index files, shared type files, config files; "medium" for same-wave overlap; "low" for different-wave overlap
- [ ] Agent returns structured JSON with `fileConflicts` array matching quantum.json schema plus `severity` field
- [ ] Agent handles empty `filePaths` arrays gracefully (skip stories with no paths)
- [ ] Typecheck/lint passes

### US-005: Create `bottleneck-analyzer` specialist agent

**Description:** As a dag-validator coordinator, I want a bottleneck-analyzer agent that detects sequential bottlenecks in the DAG and proposes restructuring so that unnecessary serialization is eliminated.

**Acceptance Criteria:**
- [ ] File exists at `agents/bottleneck-analyzer.md`
- [ ] Agent frontmatter includes `name`, `description`, and `tools` fields
- [ ] Agent receives stories array with `dependsOn` edges and `storyType` fields as input
- [ ] Agent builds adjacency list and computes wave assignment via topological sort
- [ ] Agent detects linear chains of length > 2 and reports them with story IDs
- [ ] Agent detects single-story waves and reports them
- [ ] Agent detects fan-out blockers (stories blocking 5+ downstream) and reports them
- [ ] For types-only dependencies (where the depended-on story has `storyType: "types-only"`): agent proposes extracting a shared types stub, modifying `dependsOn` so consumers depend on the stub instead
- [ ] For logic dependencies on fan-out blockers: agent reports a warning only (no auto-restructuring), per design decision
- [ ] Agent returns structured JSON with `bottlenecks` array containing `chain`, `fix`, `newStories[]`, `modifiedDependsOn[]`
- [ ] Proposed stub stories use the suffix convention: if extracted from US-003, stub ID is US-003-A
- [ ] Agent does NOT create circular dependencies (verified by caller)
- [ ] Typecheck/lint passes

### US-006: Create `duplication-detector` specialist agent

**Description:** As a dag-validator coordinator, I want a duplication-detector agent that identifies stories with overlapping implementation concerns using hybrid keyword + LLM analysis so that shared utilities are extracted before execution.

**Acceptance Criteria:**
- [ ] File exists at `agents/duplication-detector.md`
- [ ] Agent frontmatter includes `name`, `description`, and `tools` fields
- [ ] Agent receives stories array with titles, descriptions, acceptance criteria, and task descriptions as input
- [ ] Phase 1: Agent extracts technical keywords from each story, excluding stop-words from `references/dag-validation.md` (both standard and project-configurable)
- [ ] Phase 1: Agent computes Jaccard similarity for all story pairs and flags pairs with similarity > threshold (default 0.3, configurable via `dagValidation.jaccardThreshold`)
- [ ] Phase 2: For flagged pairs only, agent performs LLM semantic check asking whether both stories require implementing the same algorithm, data structure, or non-trivial logic
- [ ] Phase 2: If LLM confirms overlap, agent describes the shared concern and proposes a stub story
- [ ] Phase 2: If LLM rejects overlap, agent logs it as dismissed with reason
- [ ] For three-way (or N-way) duplication, agent creates a single shared stub with all N stories as consumers
- [ ] Agent returns structured JSON with `duplicationRisks` array containing `storyPairs`, `sharedConcern`, `proposedStub`, and `dismissed` entries
- [ ] Proposed stub stories use the suffix convention: derived from the lowest-numbered consumer story ID (e.g., US-008-A)
- [ ] Typecheck/lint passes

### US-007: Create `dag-validator` coordinator agent

**Description:** As the ql-plan skill, I want a dag-validator coordinator agent that spawns the three specialists, merges their reports, applies restructuring with cycle detection, creates stub stories, and writes the DAG Health Report so that the validation system works end-to-end.

**Acceptance Criteria:**
- [ ] File exists at `agents/dag-validator.md`
- [ ] Agent frontmatter includes `name`, `description`, and `tools` fields
- [ ] Agent receives `quantum.json` path and PRD path as input
- [ ] Agent reads plan size and applies thresholds from `references/dag-validation.md`: < 5 stories skips bottleneck analysis; 5-15 runs specialists sequentially; 16+ spawns specialists in parallel
- [ ] Agent applies restructuring in deterministic order: (1) bottleneck fixes, (2) duplication fixes, (3) fileConflicts recomputation
- [ ] After applying all restructuring, agent runs cycle detection via topological sort on the modified DAG
- [ ] If cycle detected: agent reverts the specific restructuring that caused it and logs the revert in the Health Report
- [ ] Agent creates stub stories with `STUB:` prefix in `notes` field, empty `tasks`, `acceptanceCriteria`, `filePaths`, and standard `retries` block
- [ ] Stub story IDs use suffix convention (e.g., US-003-A, US-008-A)
- [ ] Agent modifies `dependsOn` arrays of consuming stories to include stub dependencies
- [ ] For high-severity file conflicts: agent injects synthetic `dependsOn` edges between conflicting stories so they are never co-scheduled in the same wave (highest-priority story has no added dependency; lower-priority stories depend on the highest)
- [ ] Agent writes `dagValidation` block to quantum.json with timestamp, bottlenecks, duplicationRisks, fileConflictsComputed, stubsCreated
- [ ] Agent overwrites `fileConflicts` array in quantum.json with the conflict-auditor's complete results
- [ ] Agent returns list of stub story IDs and DAG Health Report text to caller
- [ ] Idempotency: if `dagValidation.timestamp` exists and quantum.json file modification time is not newer than the timestamp, agent skips validation and returns "Already validated"
- [ ] Agent handles specialist timeout (90 seconds per specialist): if a specialist fails, its analysis is skipped and the Health Report notes the skip
- [ ] Typecheck/lint passes

### US-008: Update `ql-plan` to tag `storyType` on stories

**Description:** As a user running `/ql-plan`, I want the planner to automatically tag each story with a `storyType` field so that the dag-validator can make informed restructuring decisions.

**Acceptance Criteria:**
- [ ] `skills/ql-plan/SKILL.md` includes a new section "Story Type Tagging" after the dependency analysis step
- [ ] The section instructs the planner to assign `storyType` to each story: `"types-only"` for stories that only define types/interfaces/schemas, `"config"` for scaffold/config-only stories, `"test"` for test-only stories, `"logic"` for all others
- [ ] The section includes examples of each type with rationale
- [ ] Anti-rationalization guard: "If a story has any task that implements business logic, API handlers, or data processing, it is `logic`, not `types-only`"
- [ ] Typecheck/lint passes

### US-009: Integrate `dag-validator` into `ql-plan` workflow

**Description:** As a user running `/ql-plan`, I want the dag-validator to run automatically after DAG generation and stub stories to be fleshed out by the planner so that I review a complete, optimized plan.

**Acceptance Criteria:**
- [ ] `skills/ql-plan/SKILL.md` includes a new final section "DAG Validation" after all existing steps
- [ ] The section instructs the planner to spawn the `dag-validator` agent with the quantum.json path and PRD path
- [ ] After the dag-validator returns, the planner checks for stub story IDs in the response
- [ ] If stubs exist: the planner re-invokes itself with a scoped prompt: "Flesh out these stub stories: [IDs]. Add tasks, acceptanceCriteria, and filePaths. Do NOT modify other stories."
- [ ] After flesh-out: the planner validates each stub has `tasks.length > 0` and `acceptanceCriteria.length > 0`
- [ ] If a stub fails validation: the planner removes the stub, reverts `dependsOn` modifications that referenced it, and logs the revert in the Health Report
- [ ] The planner removes the `STUB:` prefix from `notes` on successfully fleshed-out stubs
- [ ] The planner prints the DAG Health Report to the user as the final output before review
- [ ] If the dag-validator returns "Already validated" (idempotency), the planner skips the validation step and prints "Plan already validated on [timestamp]"
- [ ] Typecheck/lint passes

## 4. Functional Requirements

FR-1: The planner shall assign a `storyType` field to every story during generation, with allowed values `"types-only"`, `"logic"`, `"config"`, `"test"`.

FR-2: The dag-validator shall spawn specialist agents in parallel for plans with 16+ stories, sequentially for 5-15 stories, and skip bottleneck analysis for plans with < 5 stories.

FR-3: The bottleneck-analyzer shall detect linear dependency chains of length > 2, single-story waves, and fan-out blockers (stories blocking 5+ downstream).

FR-4: The bottleneck-analyzer shall propose types-only stub extraction for bottlenecks caused by types-only dependencies, and report-only warnings for logic dependencies.

FR-5: The duplication-detector shall exclude standard stop-words and project-configurable stop-words from keyword extraction before computing Jaccard similarity.

FR-6: The duplication-detector shall flag story pairs with Jaccard similarity > 0.3 (configurable) for LLM semantic verification.

FR-7: The duplication-detector shall only propose stub extraction when the LLM confirms overlapping implementation concerns.

FR-8: The conflict-auditor shall compute `fileConflicts` by intersecting all stories' task `filePaths` arrays, filtering to files in 2+ stories.

FR-9: The conflict-auditor shall classify each conflict as `"high"` (barrel/index files, shared type files, config files), `"medium"` (same-wave source file overlap), or `"low"` (different-wave source file overlap).

FR-10: The dag-validator shall apply restructuring in deterministic order: bottleneck fixes, then duplication fixes, then fileConflicts recomputation.

FR-11: The dag-validator shall run cycle detection after all restructuring and revert any change that introduces a cycle.

FR-12: The dag-validator shall inject synthetic `dependsOn` edges for high-severity file conflicts: lower-priority stories in the conflict group shall depend on the highest-priority story, preventing co-scheduling.

FR-13: The dag-validator shall create stub stories with suffix-convention IDs (e.g., US-003-A) and `STUB:` prefix in the `notes` field.

FR-14: The dag-validator shall skip validation if `dagValidation.timestamp` exists and the quantum.json file has not been modified since that timestamp.

FR-15: The planner shall re-invoke itself to flesh out stub stories after the dag-validator returns, and validate that each stub has non-empty `tasks` and `acceptanceCriteria`.

FR-16: The planner shall revert stub stories that fail the flesh-out validation, restoring the original `dependsOn` edges.

FR-17: The dag-validator shall handle specialist timeouts (90 seconds) gracefully, skipping the timed-out specialist's analysis and noting the skip in the Health Report.

## 5. Non-Goals (Out of Scope)

1. **Runtime duplication detection** — This feature operates at planning time only. The wave-end type audit (L5, already implemented) handles runtime duplication. We do not modify `lib/type-audit.sh`.

2. **Barrel file auto-generation** — The conflict-auditor flags barrel files as high-severity, but this feature does not implement post-merge barrel file generation. That is a separate orchestrator-level change.

3. **Machine-checkable assertions** — The post-mortem (#3, #6) proposes `requiredFiles` and `assertions` fields for runtime validation. This is a runtime enforcement concern outside the scope of planner intelligence.

4. **quantum.json location change** — The post-mortem (#4) proposes moving quantum.json out of the git tree. This is an infrastructure change independent of DAG validation.

5. **Worktree base divergence fix** — The post-mortem (#2) proposes synchronizing worktree base commits. This is an orchestrator spawn-time concern, not a planning concern.

6. **Modifying the orchestrator's scheduling algorithm** — The orchestrator already has file-conflict-aware filtering (Step 2.1). We inject synthetic dependencies at planning time so the existing orchestrator logic handles them without modification.

7. **Splitting logic stories automatically** — Per design decision, the bottleneck analyzer only auto-restructures types-only dependencies. Logic story fan-out blockers are reported as warnings for manual resolution.

## 6. Design Considerations

**Agent prompt design:** Each specialist agent has a narrow, focused prompt. The coordinator passes only the data each specialist needs (stories array subset, not full quantum.json) to minimize context and maximize quality.

**Stub ID convention:** Stubs use suffix IDs (US-003-A, US-003-B) derived from the story they were extracted from. This makes the extraction provenance visible in the DAG Health Report and quantum.json.

**Synthetic dependencies for high-severity conflicts:** Rather than modifying the orchestrator, we inject `dependsOn` edges at planning time. This means the orchestrator's existing DAG query and file-conflict-aware filtering handle high-severity conflicts automatically. The synthetic edges are permanent in quantum.json — they survive re-reads and restarts.

**Idempotency mechanism:** The dag-validator compares `dagValidation.timestamp` against the quantum.json file's modification time. If the file hasn't changed since the last validation, validation is skipped. This prevents redundant work when a user re-runs `ql-plan` without modifying the plan.

## 7. Technical Considerations

**Dependencies:** All four new agents (`dag-validator`, `bottleneck-analyzer`, `duplication-detector`, `conflict-auditor`) are `.md` files in the `agents/` directory. They use the standard Claude Code agent frontmatter format. No new shell scripts or libraries are required.

**Existing file modifications:** Only `skills/ql-plan/SKILL.md` and `quantum.json.example` are modified. All other changes are new files.

**Parallel agent spawning:** The dag-validator uses the Agent tool to spawn specialists. For 16+ story plans, all three are spawned in a single message with multiple Agent tool calls. For 5-15 story plans, they are invoked sequentially within the coordinator.

**Cycle detection algorithm:** The coordinator uses Kahn's algorithm (iterative topological sort). If the sorted output has fewer nodes than the total story count, a cycle exists. The coordinator identifies which restructuring introduced the cycle by checking which new edges connect to the cycle's nodes.

**File conflict severity requires wave knowledge:** The conflict-auditor needs wave assignment to classify "medium" (same wave) vs "low" (different wave). The coordinator provides wave assignments computed from the DAG's topological sort alongside the stories array.

## 8. Success Metrics

- The dag-validator would have detected all three planning defects from the 2026-03-24 post-mortem when run on the original 18-story plan: the US-001->US-002->US-003 bottleneck, the US-008/US-013 Louvain duplication, and the missing `index.ts` in `fileConflicts`
- `fileConflicts` coverage: 100% of files appearing in 2+ stories' `filePaths` are listed (zero false negatives on mechanical computation)
- Validation completes in < 2 minutes for plans with up to 30 stories
- Re-running validation on an unchanged plan takes < 5 seconds (idempotency)
- Zero cycles introduced in restructured DAGs (hard gate, never violated)
- Stub stories are successfully fleshed out by the planner in > 80% of cases

## 9. Open Questions

1. Should the Jaccard threshold (0.3) and specialist timeout (90s) be exposed as `ql-plan` question-phase prompts, or are they purely reference-doc configuration? Current decision: reference-doc only, configurable via `dagValidation` fields in quantum.json.

2. Should the DAG Health Report be saved as a separate file (e.g., `docs/plans/YYYY-MM-DD-dag-health-report.md`) in addition to the `dagValidation` block in quantum.json? Current decision: quantum.json only, but this could change if users want persistent reports.

3. The conflict-auditor needs wave assignments to classify medium vs low severity. Should the coordinator compute waves before spawning specialists (adding a sequential step), or should the conflict-auditor receive raw `dependsOn` and compute waves itself? Current decision: coordinator computes waves and passes them to the auditor.

### Lifecycle Checklist

- **First-run behavior:** N/A — this feature activates automatically during `ql-plan`. No onboarding or empty state. If no issues are found, the Health Report says "No issues found" and the plan is unchanged.
- **Returning-user behavior:** Idempotency check: if `dagValidation.timestamp` exists and quantum.json is unmodified, validation is skipped with a message "Plan already validated on [timestamp]."
- **Update behavior:** N/A — this is a planning-time tool, not a deployed service. New agent versions take effect on next `ql-plan` run. No migration needed.
- **Error recovery:** Specialist timeout or crash causes graceful degradation — the coordinator proceeds with available results. Failed stub flesh-out is reverted. Cycle detection reverts bad restructuring. The principle: the validator never makes the plan worse.
- **No-data/empty state:** Plans with < 5 stories skip bottleneck analysis. Plans with no `filePaths` on any task produce empty `fileConflicts`. Plans with no keyword overlap produce no duplication warnings. All handled gracefully.
- **Uninstall/disable:** Removing the four agent `.md` files and the `ql-plan` validation section restores original behavior. The `dagValidation` block in quantum.json is informational only — no runtime code reads it. Existing plans with `dagValidation` blocks are unaffected.
