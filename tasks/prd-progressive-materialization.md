# PRD: Progressive Materialization — 5-Layer Defense Against Worktree Isolation Type Divergence

**Feature:** Progressive Materialization
**Design Doc:** `docs/plans/2026-03-18-worktree-isolation-fix-design.md`
**Research:** `docs/post-mortems/2026-03-18-worktree-isolation-research.md`
**Triggered by:** `Logical_inference/docs/post-mortems/2026-03-18-quantum-loop-execution-observations.md`
**Date:** 2026-03-18

---

## Section 1: Introduction/Overview

Parallel worktree execution in quantum-loop causes type divergence, destructive merges, and interface bypasses because isolated agents cannot see each other's work. The March 18 post-mortem revealed 10 post-merge issues (3 CRITICAL, 7 IMPORTANT) across 29 stories — 70% caused by parallel isolation. This feature implements a 5-layer defense system: structural contracts in ql-plan (L1), selective contract materialization before each wave (L2), escalate-on-conflict merge strategy (L3), post-merge typecheck gate (L4), and wave-end type audit with feedback loop (L5). All 5 layers ship as one release.

---

## Section 2: Goals

- Eliminate type divergence caused by parallel agents creating incompatible definitions of shared types (Pattern 1 — 70% of post-merge issues)
- Eliminate destructive merges that silently delete valid content from shared files (Pattern 2 — 20% of post-merge issues)
- Eliminate `as any` bypasses caused by agents unable to import interfaces that don't exist yet (Pattern 3 — 10% of post-merge issues)
- Make the system self-healing: types missed by the planner are discovered at wave-end and materialized for subsequent waves
- Auto-promote discovered contracts to `contracts.shared_types` at execution end so future runs benefit
- Support TypeScript, Python, and Go from day one with auto-detection from project files
- Maintain full backward compatibility: existing quantum.json files without new fields degrade gracefully to current behavior
- Infer shared types directory from project structure (detect existing `types/`, `interfaces/`, or similar directories)

---

## Section 3: User Stories

### US-001: Extend contracts schema with shape, definition, and ownership fields
**Description:** As a pipeline user, I want shared type contracts to include structural shapes and verbatim definitions so that parallel agents know both the name AND the structure of shared types.

**Acceptance Criteria:**
- [ ] `quantum.json.example` contains at least one `shared_types` entry with all new fields: `definitionFile`, `owner`, `consumers`, `shape`, `definition`
- [ ] `shape` contains `methods` array (each: `{name, params: [{name, type}], returns}`) and `properties` array (each: `{name, type, readonly?}`)
- [ ] `definition` is a string containing verbatim code (e.g., a TypeScript interface)
- [ ] `owner` is a story ID string
- [ ] `consumers` is an array of story ID strings
- [ ] All new fields are optional — entries with only `value` and `pattern` (existing format) remain valid
- [ ] JSON is valid (parseable by `jq .` and `node -e "JSON.parse(...)"`)
- [ ] Typecheck/lint passes

---

### US-002: Add typecheckCommand field to quantum.json schema
**Description:** As a pipeline user, I want to specify (or auto-detect) a typecheck command so that post-merge type validation works across languages.

**Acceptance Criteria:**
- [ ] `quantum.json.example` contains a top-level `typecheckCommand` field set to a string (e.g., `"tsc --noEmit"`)
- [ ] Field is optional — absent means auto-detect
- [ ] Documentation comment in example explains auto-detect behavior: tsconfig.json → `tsc --noEmit`, pyproject.toml with pyright → `pyright`, mypy config → `mypy .`, go.mod → `go vet ./...`
- [ ] JSON is valid
- [ ] Typecheck/lint passes

---

### US-003: Add execution metadata fields for materialization and audit tracking
**Description:** As a pipeline operator, I want the `execution` object in quantum.json to track which contracts were materialized and which were discovered by the audit, so the feedback loop works across waves.

**Acceptance Criteria:**
- [ ] `quantum.json.example`'s `_execution_example` section contains `materializedContracts` (string array) and `discoveredContracts` (object keyed by type name)
- [ ] Each `discoveredContracts` entry has: `discoveredInWave` (number), `sourceFiles` (string array), `consolidated` (boolean), `consolidatedFile` (string)
- [ ] `baselineTypecheckErrors` (number) is included in the execution example
- [ ] JSON is valid
- [ ] Typecheck/lint passes

---

### US-004: Update ql-plan to generate structural contracts
**Description:** As a planner, I want `/ql-plan` to detect shared types across stories and generate `shape`, `definition`, `owner`, and `consumers` fields so that downstream layers can materialize and validate them.

**Acceptance Criteria:**
- [ ] When 2+ stories reference the same type concept in their descriptions or acceptance criteria, ql-plan generates a `contracts.shared_types` entry with `shape` and `definition` fields
- [ ] The planner detects project language from `tsconfig.json` (TypeScript), `pyproject.toml`/`setup.py` (Python), or `go.mod` (Go)
- [ ] For TypeScript: `definition` contains an `export interface` or `export type` declaration
- [ ] For Python: `definition` contains a `class X(Protocol)` or `@dataclass class X` declaration
- [ ] For Go: `definition` contains a `type X interface` or `type X struct` declaration
- [ ] `owner` is set to the story that primarily implements the type
- [ ] `consumers` lists all other stories that reference the type
- [ ] `definitionFile` path is inferred from project structure: if a `types/`, `interfaces/`, or `shared/` directory exists, use it; otherwise default to `src/shared/types/<kebab-name>.<ext>`
- [ ] Stories with no shared types produce no `shape`/`definition` fields (backward compat)
- [ ] Typecheck/lint passes

---

### US-005: Create contract-shapes reference for ql-plan
**Description:** As a planner agent, I want a reference document with language-specific examples of contract shapes so that I generate accurate definitions for TypeScript, Python, and Go projects.

**Acceptance Criteria:**
- [ ] File exists at `skills/ql-plan/references/contract-shapes.md`
- [ ] Contains at least one complete example for each language: TypeScript (interface + type), Python (Protocol + dataclass), Go (interface + struct)
- [ ] Each example shows both the `shape` JSON and the corresponding `definition` string
- [ ] Contains language detection heuristics (which project files to check)
- [ ] Contains guidance on when to generate `definition` (multi-consumer) vs shape-only (advisory)
- [ ] Follows skill-creator progressive disclosure pattern: referenced from ql-plan SKILL.md, only loaded when shared types detected
- [ ] Typecheck/lint passes

---

### US-006: Create lib/materialize.sh with detect_language()
**Description:** As the orchestrator, I need a `detect_language()` function that identifies the project's primary language from config files, so that contract materialization and typecheck auto-detection work correctly.

**Acceptance Criteria:**
- [ ] File exists at `lib/materialize.sh`
- [ ] Sources `lib/common.sh` for shared utilities
- [ ] `detect_language(repo_root)` outputs one of: `typescript`, `python`, `go`, `unknown`
- [ ] Detection priority: `tsconfig.json` → typescript, `pyproject.toml` OR `setup.py` → python, `go.mod` → go
- [ ] If multiple config files exist, uses `definitionFile` extension as tiebreaker
- [ ] Returns `unknown` if no config files found
- [ ] All tests in `tests/test_materialize.sh` pass for `detect_language()`: 4 cases (ts, py, go, unknown)
- [ ] Typecheck/lint passes

---

### US-007: Implement materialize_contracts() and generate_definition_file()
**Description:** As the orchestrator, I need to materialize shared type contracts as real code files before each wave, so that parallel agents can import from a single authoritative source.

**Acceptance Criteria:**
- [ ] `materialize_contracts(json_path, repo_root, wave_num)` reads `contracts.shared_types` and `execution.discoveredContracts` from quantum.json
- [ ] Only materializes types where `consumers` array has length >= 2
- [ ] Single-consumer types are NOT materialized (logged as skipped)
- [ ] `generate_definition_file(type_entry, language, repo_root)`:
  - When `definition` field is present: writes content verbatim to `definitionFile` path
  - When `definition` absent but `shape` present: generates from shape using language-specific template
  - When neither present: skips with warning log
- [ ] If `definitionFile` already exists with matching content: skips (idempotent)
- [ ] If `definitionFile` already exists with DIFFERENT content: does NOT overwrite; logs `[MATERIALIZE] SKIP <TypeName> — file already exists with different content`
- [ ] Creates parent directories if they don't exist (`mkdir -p`)
- [ ] After writing all files: runs `git add <files> && git commit -m "chore: materialize contracts for Wave <N>"`
- [ ] Returns newline-separated list of materialized type names on stdout
- [ ] Updates `execution.materializedContracts` array in quantum.json
- [ ] All tests in `tests/test_materialize.sh` pass for materialization: 7 cases
- [ ] Typecheck/lint passes

---

### US-008: Implement shared types directory inference
**Description:** As the materializer, I need to infer the correct directory for shared type files from the project's existing structure, rather than hardcoding a path.

**Acceptance Criteria:**
- [ ] `infer_shared_types_dir(repo_root, language)` checks for existing directories in priority order:
  1. `src/shared/types/` (TypeScript convention)
  2. `src/types/` (common alternative)
  3. `src/interfaces/` (common alternative)
  4. `types/` (project-root convention)
  5. `shared/` (Python/Go convention)
- [ ] If none exist, creates `src/shared/types/` (TypeScript), `src/shared/` (Python), or `internal/shared/` (Go)
- [ ] The inferred path is used as the default when `definitionFile` is not explicitly set in the contract
- [ ] When `definitionFile` IS set in the contract, it takes precedence (no inference)
- [ ] Function is idempotent — does not create directories until materialization actually writes a file
- [ ] Typecheck/lint passes

---

### US-009: Extend merge_worktree_branch() with conflict classification
**Description:** As the orchestrator, I need merge conflicts on shared files to be explicitly escalated (story failed) instead of silently resolved, so that destructive merges are prevented.

**Acceptance Criteria:**
- [ ] Successful merges (no conflicts) behave identically to today — returns 0
- [ ] On merge conflict: captures the list of conflicting files via `git diff --name-only --diff-filter=U`
- [ ] Aborts the merge (`git merge --abort`) — no partial merges left behind
- [ ] Returns 1 with the conflicting file list on stdout (existing behavior, unchanged)
- [ ] The conflict file list is available for the caller to log in `retries.failureLog[].error`
- [ ] The caller (orchestrator) marks the story as failed with `phase: "merge_conflict"`
- [ ] All tests in `tests/test_merge_escalation.sh` pass: 4 cases (no conflict, story file conflict, barrel export conflict, conflict list captured)
- [ ] Typecheck/lint passes

---

### US-010: Implement post_merge_typecheck() with auto-detect and baseline
**Description:** As the orchestrator, I need a post-merge typecheck that catches cross-story type incompatibilities by running a project-wide typecheck after each successful merge, reverting on failure.

**Acceptance Criteria:**
- [ ] `post_merge_typecheck(repo_root, json_path)` added to `lib/monitor.sh`
- [ ] If `typecheckCommand` is set in quantum.json: uses that command
- [ ] If `typecheckCommand` is absent: auto-detects from project files (same priority as `detect_language()`: tsconfig.json → `tsc --noEmit`, pyright config → `pyright`, mypy config → `mypy .`, go.mod → `go vet ./...`)
- [ ] If no command found: logs `[TYPECHECK] No typecheck command configured or detected. Skipping.` and returns 0
- [ ] If command not found in PATH (exit 127): logs warning, returns 0 (does not fail story for missing tooling)
- [ ] Reads `execution.baselineTypecheckErrors` from quantum.json
- [ ] If baseline is not set: runs typecheck, stores error count as baseline, returns 0 (first-run initialization)
- [ ] On subsequent runs: if error count > baseline → reverts merge via `git revert -m 1 HEAD --no-edit`, returns 1
- [ ] If error count <= baseline → returns 0 (merge didn't make things worse)
- [ ] Typecheck timeout: 120 seconds. If exceeded, kills process, logs warning, returns 0 (does not block pipeline on slow typechecks)
- [ ] Returns the typecheck stdout/stderr for the caller to include in failure logs
- [ ] All tests in `tests/test_typecheck_gate.sh` pass: 7 cases
- [ ] Typecheck/lint passes

---

### US-011: Create lib/type-audit.sh with grep_duplicate_definitions()
**Description:** As the orchestrator, I need a fast grep-based scan for duplicate type definitions across files changed in a wave, so that type divergence is detected before the next wave starts.

**Acceptance Criteria:**
- [ ] File exists at `lib/type-audit.sh`
- [ ] Sources `lib/common.sh` and `lib/materialize.sh` (for `detect_language()`)
- [ ] `grep_duplicate_definitions(repo_root, changed_files_list)` scans only the provided files (not the entire repo)
- [ ] Language-specific patterns:
  - TypeScript: `export (interface|type|class) (\w+)`
  - Python: `class (\w+)\(Protocol\)`, `class (\w+)\(BaseModel\)`, `@dataclass` followed by `class (\w+)`
  - Go: `type (\w+) (interface|struct)`
- [ ] Groups definitions by name
- [ ] Returns JSON array of duplicates: `[{"name": "Foo", "files": ["a.ts", "b.ts"]}]`
- [ ] Returns empty array `[]` when no duplicates found
- [ ] Only flags names with 2+ definition sites from different stories
- [ ] All tests in `tests/test_type_audit.sh` pass: 6 cases (TS, Python, Go patterns; no duplicates; wave-scoped only; discoveredContracts written)
- [ ] Typecheck/lint passes

---

### US-012: Implement audit_wave_types() with agent escalation and feedback loop
**Description:** As the orchestrator, I need the wave-end audit to spawn a type-auditor agent when duplicates are found, consolidate them, and feed discoveries back into contracts for subsequent waves.

**Acceptance Criteria:**
- [ ] `audit_wave_types(json_path, repo_root, wave_num)` calls `grep_duplicate_definitions()` with files changed in the current wave
- [ ] If no duplicates: logs `[AUDIT] Grep found 0 duplicate type definitions. Skipping agent audit.` and returns 0
- [ ] If duplicates found: logs the duplicate names and file locations
- [ ] Spawns a type-auditor agent (or self-performs if agents unavailable) with:
  - The duplicate type names and their file paths
  - The contract shape from quantum.json (if exists for that type name)
  - Instruction to consolidate, update imports, run typecheck, and commit
- [ ] The auditor agent inherits the parent orchestrator's model (no separate model config)
- [ ] After auditor completes: runs full test suite. If tests fail, reverts auditor's commit and logs `[AUDIT] Consolidation of <TypeName> broke tests. Reverted.`
- [ ] `update_contracts_for_next_wave(json_path, discovered)` writes each discovered type to `execution.discoveredContracts` with `discoveredInWave`, `sourceFiles`, `consolidated`, `consolidatedFile`
- [ ] On next wave, `materialize_contracts()` reads `discoveredContracts` in addition to `contracts.shared_types`
- [ ] Typecheck/lint passes

---

### US-013: Create type-auditor agent
**Description:** As the wave-end audit system, I need a short-lived agent that can read two conflicting type definitions, pick the authoritative one, write a consolidated version to a shared file, and update all imports.

**Acceptance Criteria:**
- [ ] File exists at `agents/type-auditor.md`
- [ ] Frontmatter has `name: type-auditor` and `description` that includes triggering context (spawned when grep detects duplicate type definitions)
- [ ] Tools list: `["Read", "Write", "Edit", "Bash", "Grep", "Glob"]`
- [ ] Instructions specify authority priority: (1) contract shape if exists, (2) owner story's version, (3) most complete definition
- [ ] Instructions require: write consolidated type to shared types directory, update all imports in consuming files, run typecheck to verify, commit with `"fix: consolidate <TypeName> from wave N"`
- [ ] Instructions specify: if the two definitions are semantically distinct (different concepts with the same name), log as false positive and do NOT consolidate
- [ ] Agent prompt is concise (<100 lines) following skill-creator minimal context principle
- [ ] Typecheck/lint passes

---

### US-014: Update orchestrator with pre-wave materialization step
**Description:** As the orchestrator agent, I need to materialize contracts before spawning each wave's agents, so that all worktrees branch from a commit that includes the shared type files.

**Acceptance Criteria:**
- [ ] `agents/orchestrator.md` Step 3B (Parallel Execution) has a new sub-step before 3B.2 (Spawn Agents): "3B.1B: Materialize Contracts"
- [ ] The step calls `materialize_contracts()` (or equivalent inline logic for the orchestrator agent)
- [ ] The step runs AFTER marking stories as `in_progress` but BEFORE spawning any agents
- [ ] The commit from materialization is the base for all worktree branches in the wave
- [ ] If materialization produces no files (no multi-consumer contracts): step is a no-op, logged as `[MATERIALIZE] No multi-consumer contracts to materialize for Wave N`
- [ ] For subsequent waves: also materializes `execution.discoveredContracts` entries
- [ ] Typecheck/lint passes

---

### US-015: Update orchestrator with post-merge typecheck gate
**Description:** As the orchestrator agent, I need to run a project-wide typecheck after each successful merge and revert on failure, so that cross-story type incompatibilities are caught immediately.

**Acceptance Criteria:**
- [ ] `agents/orchestrator.md` Step 3B.3 (Monitor Loop) section "On STORY_PASSED" includes a typecheck step after merge and before inline review
- [ ] Sequence: merge → typecheck → test suite → inline review
- [ ] On typecheck failure: revert merge (`git revert -m 1 HEAD`), mark story failed with `phase: "merge_typecheck"`, include typecheck error output in `retries.failureLog`
- [ ] First wave initializes `execution.baselineTypecheckErrors` (run typecheck before any merges)
- [ ] On typecheck success: log `[TYPECHECK] Post-merge typecheck: PASSED`
- [ ] If no typecheck command available: log skip warning, proceed to test suite
- [ ] Typecheck/lint passes

---

### US-016: Update orchestrator with wave-end type audit
**Description:** As the orchestrator agent, I need to run a type audit after each wave completes and feed discoveries back into contracts for the next wave.

**Acceptance Criteria:**
- [ ] `agents/orchestrator.md` Step 3C (Integration Check) has a new sub-step: "3C.0: Type Audit"
- [ ] Runs BEFORE the existing dead code detection (3C.1) and pipeline connectivity (3C.2)
- [ ] Calls `audit_wave_types()` (or equivalent inline logic)
- [ ] If auditor agent consolidates types: the commit is included in the wave's integration check
- [ ] After audit: logs contract effectiveness metrics (`[AUDIT] Wave N: X duplicates found, Y consolidated, Z false positives`)
- [ ] Typecheck/lint passes

---

### US-017: Update orchestrator with auto-promotion of discovered contracts
**Description:** As the orchestrator, I need to promote `execution.discoveredContracts` to permanent `contracts.shared_types` at execution end, so that future runs benefit from runtime discoveries.

**Acceptance Criteria:**
- [ ] At Step 4 (Final Integration Gate) or Step 5 (Generate Observations), after all stories pass:
  - Read `execution.discoveredContracts`
  - For each entry where `consolidated: true`: add to `contracts.shared_types` with `value`, `definitionFile` (from `consolidatedFile`), and `consumers` (from `sourceFiles` context)
  - Do NOT add entries where `consolidated: false` (false positives)
- [ ] The promotion is a quantum.json write, not a separate commit (included in the observations commit)
- [ ] Log: `[CONTRACTS] Promoted N discovered types to permanent contracts: <names>`
- [ ] If no discovered contracts: step is a no-op
- [ ] Typecheck/lint passes

---

### US-018: Update implementer agent to import from materialized contracts
**Description:** As an implementer agent, I need to check for materialized contract files and import from them instead of creating my own type definitions.

**Acceptance Criteria:**
- [ ] `agents/implementer.md` "Read Contracts" section is extended with a new sub-step after reading contract values:
  - "For each contract with a `definitionFile`: check if the file exists. If yes, import from it — do NOT create your own definition of the same type."
- [ ] The instruction applies in both sequential and parallel mode
- [ ] If the materialized file does NOT exist (e.g., sequential mode without materialization, or the file was deleted): fall back to creating the type, matching the contract's `shape` if available
- [ ] Anti-rationalization: "I can write a better version" is not valid when a materialized contract file exists
- [ ] Typecheck/lint passes

---

### US-019: Update orchestrator post-mortem with Contract Effectiveness section
**Description:** As a pipeline user, I want the execution observations document to include a "Contract Effectiveness" section so I can measure how well the contract system worked.

**Acceptance Criteria:**
- [ ] `agents/orchestrator.md` Step 5 (Generate Execution Observations) includes a new section in the observation doc template:
  ```
  ## Contract Effectiveness
  - Contracts defined: N types
  - Materialized: N (multi-consumer only)
  - Divergence prevented: N (types where all agents imported from materialized file)
  - Divergence detected by L5 audit: N (consolidated)
  - False positives (L5): N (same name, different concept — not consolidated)
  - Missed (discovered in post-merge review): N
  - Promoted to permanent contracts: N
  ```
- [ ] Metrics are computed from `execution.materializedContracts`, `execution.discoveredContracts`, and story failure logs with `phase: "merge_typecheck"` or `phase: "merge_conflict"`
- [ ] Section appears even if all values are 0 (indicates no shared types in this run)
- [ ] Typecheck/lint passes

---

### US-020: Write unit tests for lib/materialize.sh
**Description:** As a developer, I want comprehensive tests for the materialization functions so that regressions are caught early.

**Acceptance Criteria:**
- [ ] File exists at `tests/test_materialize.sh`
- [ ] Tests `detect_language()` with 4 cases: tsconfig.json → typescript, pyproject.toml → python, go.mod → go, none → unknown
- [ ] Tests `materialize_contracts()`: 2 multi-consumer types → 2 files written
- [ ] Tests single-consumer type → NOT materialized
- [ ] Tests `generate_definition_file()` with `definition` field → verbatim content
- [ ] Tests file-already-exists with same content → skipped (idempotent)
- [ ] Tests file-already-exists with different content → NOT overwritten, warning logged
- [ ] Tests `discoveredContracts` are included in materialization
- [ ] Tests git commit created with correct message format
- [ ] Tests `infer_shared_types_dir()` finds existing directories in priority order
- [ ] All tests pass when run with `bash tests/test_materialize.sh`
- [ ] Typecheck/lint passes

---

### US-021: Write unit tests for merge escalation and typecheck gate
**Description:** As a developer, I want comprehensive tests for the L3 and L4 functions so that merge behavior regressions are caught.

**Acceptance Criteria:**
- [ ] File exists at `tests/test_merge_escalation.sh`
- [ ] Tests merge with no conflicts → returns 0
- [ ] Tests merge with conflict → returns 1, conflict files on stdout
- [ ] Tests merge conflict → merge is aborted (no partial merge state)
- [ ] File exists at `tests/test_typecheck_gate.sh`
- [ ] Tests passing typecheck → returns 0
- [ ] Tests failing typecheck (errors > baseline) → reverts merge, returns 1
- [ ] Tests pre-existing errors equal to baseline → passes
- [ ] Tests auto-detect with tsconfig.json → runs `tsc --noEmit`
- [ ] Tests no config files → skips with warning, returns 0
- [ ] Tests explicit `typecheckCommand` overrides auto-detect
- [ ] Tests command not found (exit 127) → skips with warning, returns 0
- [ ] Tests baseline initialization on first run → stores count, returns 0
- [ ] All tests pass when run with `bash tests/test_merge_escalation.sh` and `bash tests/test_typecheck_gate.sh`
- [ ] Typecheck/lint passes

---

### US-022: Write unit tests for lib/type-audit.sh
**Description:** As a developer, I want comprehensive tests for the wave-end type audit so that duplicate detection regressions are caught.

**Acceptance Criteria:**
- [ ] File exists at `tests/test_type_audit.sh`
- [ ] Tests `grep_duplicate_definitions()` with 2 TS files defining `interface Foo` → returns duplicate
- [ ] Tests 0 duplicates → returns empty array
- [ ] Tests only scans provided file list (not entire repo)
- [ ] Tests Python pattern: `class Foo(Protocol)` detected
- [ ] Tests Go pattern: `type Foo interface` detected
- [ ] Tests `update_contracts_for_next_wave()` writes to `execution.discoveredContracts`
- [ ] All tests pass when run with `bash tests/test_type_audit.sh`
- [ ] Typecheck/lint passes

---

## Section 4: Functional Requirements

```
FR-1:  The system shall extend contracts.shared_types entries to support optional fields:
       definitionFile (string), owner (string), consumers (string[]),
       shape ({methods: [], properties: []}), definition (string).

FR-2:  The system shall support a top-level typecheckCommand field in quantum.json.
       When absent, the system shall auto-detect from project config files.

FR-3:  The system shall track materialized and discovered contracts in the
       execution runtime metadata of quantum.json.

FR-4:  The ql-plan skill shall detect shared types across stories and generate
       shape + definition fields when 2+ stories reference the same type concept.

FR-5:  The ql-plan skill shall detect the project language from tsconfig.json
       (TypeScript), pyproject.toml/setup.py (Python), or go.mod (Go).

FR-6:  The ql-plan skill shall generate definition strings in the detected
       language: TypeScript export interface, Python Protocol/dataclass, Go interface/struct.

FR-7:  The materializer shall write contract definition files to disk only for
       types with consumers.length >= 2.

FR-8:  The materializer shall infer the shared types directory from existing
       project structure (types/, interfaces/, shared/) before falling back to
       a language-specific convention.

FR-9:  The materializer shall NOT overwrite existing files with different content.
       It shall skip with a warning log.

FR-10: The materializer shall read both contracts.shared_types AND
       execution.discoveredContracts when materializing for a wave.

FR-11: The materializer shall commit materialized files before agents are spawned,
       so worktrees branch from the post-materialization commit.

FR-12: On merge conflict, the orchestrator shall abort the merge and mark the
       story as failed with phase "merge_conflict".

FR-13: After each successful merge, the system shall run a project-wide typecheck.
       If error count exceeds the baseline, the merge shall be reverted.

FR-14: The baseline typecheck error count shall be captured before the first wave.
       Any error count > baseline triggers a revert.

FR-15: If no typecheck command is available (not configured and not detected),
       the post-merge typecheck shall be skipped with a warning.

FR-16: After all agents in a wave complete, the system shall run a grep-based
       scan for duplicate type definitions in files changed during that wave.

FR-17: If duplicates are found, the system shall spawn a type-auditor agent to
       assess compatibility and consolidate if the definitions represent the
       same concept.

FR-18: The type-auditor agent shall inherit the parent orchestrator's model.

FR-19: After the auditor commits, the system shall run the full test suite.
       If tests fail, the consolidation commit shall be reverted.

FR-20: Discovered contracts shall be written to execution.discoveredContracts
       and materialized for subsequent waves.

FR-21: At execution end, discovered contracts with consolidated: true shall be
       auto-promoted to permanent contracts.shared_types.

FR-22: The implementer agent shall check for materialized contract files and
       import from them instead of creating its own type definitions.

FR-23: The execution observations document shall include a "Contract Effectiveness"
       section with metrics on materialization, detection, and false positives.

FR-24: All new fields shall be optional. Existing quantum.json files without
       the new fields shall work identically to current behavior.
```

---

## Section 5: Non-Goals (Out of Scope)

1. **Smart merge conflict resolution** — The system escalates conflicts (fails the story), it does not attempt AST-based merging, AI-assisted merging, or barrel-export combining. Retry with full context is the resolution strategy.
2. **Real-time inter-agent communication** — Agents in worktrees cannot message each other during execution. Coordination happens through pre-wave materialization and post-wave auditing, not via MCP channels or shared mailboxes.
3. **External tool integration** — This feature does not depend on Clash, parallel-cc, Overstory, or any external tool. It is a pure quantum-loop solution using git, grep, and existing Claude Code primitives.
4. **Exhaustive language support** — v1 supports TypeScript, Python, and Go. Other languages (Rust, Java, Ruby, etc.) are not implemented but the architecture is extensible via `detect_language()` and the language template pattern.
5. **Modifying the sequential execution path** — All 5 layers operate in parallel mode. Sequential execution is unchanged except that implementer agents now check for materialized contract files (US-018), which is a no-op if no files exist.
6. **Changing the DAG dependency model** — `dependsOn` remains story-level, not type-level. The contract system is a supplement to the DAG, not a replacement.

---

## Section 6: Design Considerations

**Architecture:** See `docs/plans/2026-03-18-worktree-isolation-fix-design.md` for the full architecture diagram, execution flow, and feedback loop specification.

**Skill-creator methodology:** New components (`lib/materialize.sh`, `lib/type-audit.sh`, `agents/type-auditor.md`, `skills/ql-plan/references/contract-shapes.md`) follow the Anthropic skill-creator process:
- `lib/materialize.sh` and `lib/type-audit.sh` are low-freedom scripts (deterministic, specific)
- `agents/type-auditor.md` is a high-freedom agent (flexible judgment on semantic compatibility)
- `references/contract-shapes.md` follows the progressive disclosure pattern (loaded only when shared types detected)

**Shared types directory inference priority:**
1. `src/shared/types/` → `src/types/` → `src/interfaces/` → `types/` → `shared/`
2. If none exist, create based on language: `src/shared/types/` (TS), `src/shared/` (Py), `internal/shared/` (Go)

---

## Section 7: Technical Considerations

**Dependencies:** No new external dependencies. Uses `jq` (already required), `grep` (standard), and `git` (already required).

**Backward compatibility:** All new quantum.json fields are optional. The system detects their absence and degrades:
- No `shape`/`definition` → L2 skips materialization for that type
- No `typecheckCommand` → L4 auto-detects or skips
- No `execution.baselineTypecheckErrors` → first typecheck run initializes it
- No `execution.discoveredContracts` → L5 feedback loop starts empty

**Performance impact:**
- L2 (materialization): ~2-5 seconds per wave (file writes + git commit). Negligible vs. agent runtime.
- L4 (typecheck): depends on project size. 120-second timeout prevents blocking.
- L5 (grep scan): <1 second for typical wave sizes. Agent escalation adds ~30-60 seconds when triggered.

**File locking:** `materialize_contracts()` uses the existing `json-atomic.sh` pattern (write to temp, mv) for quantum.json updates. No new locking mechanisms needed.

---

## Section 8: Success Metrics

- **Post-merge type divergence issues: 0** (down from 7/10 in the March 18 post-mortem)
- **Destructive merge data loss: 0** (down from 2/10)
- **`as any` casts introduced by parallel agents: 0** (down from 1/10)
- **Contract accuracy rate: >80%** (planner-defined shapes match final implementation)
- **L5 detection rate: >90%** (types missed by planner are caught by wave-end audit)
- **False positive rate: <20%** (same-name-different-concept detections that don't need consolidation)
- **Retry overhead: <10%** (stories failed by L3/L4 that succeed on retry without consuming total retries budget)

---

## Section 9: Open Questions

1. **Typecheck timeout value:** 120 seconds is proposed. Should this be configurable in quantum.json (e.g., `typecheckTimeout`)? Large monorepos may need more time.
2. **Contract shape depth for generics:** The `shape` format supports basic types (`string`, `Map<string, string>`) but how should complex generics (`Promise<Result<T, E>>`) be represented? The `definition` string handles this, but the structured `shape` may not.
3. **Multi-language monorepos:** If a project has both `tsconfig.json` and `pyproject.toml`, the materializer uses `definitionFile` extension as tiebreaker. Should it materialize the same type in both languages?
4. **Wave boundary timing:** L5 audit runs after ALL agents in a wave complete. If one agent is significantly slower, all others wait. Should there be a "partial wave audit" for early completers?

---

## Lifecycle Checklist

- [x] **First-run behavior:** First wave initializes `execution.baselineTypecheckErrors`. First run without contracts produces no materialization (no-op). System degrades to current behavior.
- [x] **Returning-user behavior:** Discovered contracts are auto-promoted to `contracts.shared_types`. Next `/ql-execute` on the same branch benefits immediately. Next `/ql-plan` run can reference promoted contracts.
- [x] **Update behavior:** All new fields are optional. quantum.json files created before this feature work without modification. New fields are additive — no migration needed.
- [x] **Error recovery:** L3 escalates merge conflicts (story retries). L4 reverts type-error merges (story retries). L5 auditor failures are reverted (duplicate persists for next wave). Every failure mode has a fallback.
- [x] **No-data/empty state:** No contracts → no materialization → no audit → system behaves exactly like today. Zero overhead when feature is not used.
- [x] **Uninstall/disable:** Removing the new fields from quantum.json returns to pre-feature behavior. Materialized files remain in the repo (harmless — they're valid type definitions). No orphaned state.
