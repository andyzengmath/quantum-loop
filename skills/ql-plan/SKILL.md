---
name: ql-plan
description: "Part of the quantum-loop autonomous development pipeline (brainstorm \u2192 spec \u2192 plan \u2192 execute \u2192 review \u2192 verify). Convert a PRD into machine-readable quantum.json with dependency DAG, granular 2-5 minute tasks, and execution metadata. Use after creating a spec with /quantum-loop:spec. Triggers on: create plan, convert to json, plan tasks, generate quantum json, ql-plan."
---

# Quantum-Loop: Plan

You are converting a Product Requirements Document (PRD) into a machine-readable `quantum.json` file that will drive autonomous execution. Every decision you make here determines whether the execution loop succeeds or fails.

## Step 1: Read the PRD

1. Look for the most recent PRD in `tasks/prd-*.md`
2. If multiple PRDs exist, ask the user which one to convert
3. Read the entire PRD, extracting:
   - User stories (US-NNN) with acceptance criteria
   - Functional requirements (FR-N)
   - Technical considerations and constraints
   - Non-goals (to prevent scope creep during execution)

Also read:
- Project files (package.json, pyproject.toml, etc.) for project name and tech stack
- Existing code structure to determine correct file paths for tasks

## Step 2: Analyze Dependencies

Build a dependency graph between stories. Dependencies follow natural layering:

```
1. Schema / Database changes (foundation)
2. Type definitions / Models (depends on schema)
3. Backend logic / API endpoints (depends on types)
4. UI components (depends on API)
5. Integration / Aggregate views (depends on components)
```

### Dependency Rules
- A story that reads from a table DEPENDS ON the story that creates that table
- A story that renders data DEPENDS ON the story that provides the API
- A story that tests integration DEPENDS ON all component stories
- If two stories touch unrelated parts of the codebase, they are INDEPENDENT (no dependency)

### Cycle Detection
After building the dependency graph, verify there are no cycles. If you detect a cycle:
1. STOP and inform the user
2. Explain which stories form the cycle
3. Ask how to break the cycle (usually by splitting a story)

### Contracts Generation (after dependency DAG)

After building the dependency graph, scan for values that appear in 2+ stories' acceptance criteria or task descriptions. These are **contract candidates** — shared constants that parallel agents must agree on.

1. **Identify candidates:** Look for repeated references to the same entity across stories — secret key names, environment variable names, type/class names, API route paths, event names, CSS class names
2. **Group by category:** Organize candidates into logical categories:
   - `secret_keys` — shared secret/config key names
   - `env_vars` — environment variable names
   - `shared_types` — type names, class names, enum values
   - `api_routes` — API endpoint paths
   - `event_names` — event/signal names
   - `css_classes` — shared CSS class names or design tokens
3. **Rule: When in doubt, add it** — an unused contract entry costs nothing; a missing contract causes cross-story mismatches that require manual fixes
4. **Optional `pattern` field:** For values with a naming convention, add a `pattern` regex so the implementer can validate at runtime (e.g., `"pattern": "^[a-z][a-z0-9-]*$"`)

Example contracts block:
```json
"contracts": {
  "secret_keys": {
    "openai": { "value": "openai-api-key", "pattern": "^[a-z][a-z0-9-]*$" },
    "db_password": { "value": "DATABASE_PASSWORD" }
  },
  "shared_types": {
    "priority_enum": { "value": "Priority" }
  }
}
```

Add the `contracts` object to quantum.json at the top level, after `codebasePatterns`.

For language-specific shape and definition examples, read `references/contract-shapes.md` when generating structural contracts for shared types.

### Structural Contract Generation (Enhanced)

After building the basic contracts block above, enhance `shared_types` entries with structural information so that downstream layers (materialization, type audit) can generate real code files.

#### Step 1: Detect Shared Types

Scan all stories' descriptions, acceptance criteria, and task descriptions for type names (classes, interfaces, structs, enums) that appear in **2 or more stories**. These are structural contract candidates.

For each shared type candidate:
1. **`shape`** — A structured representation of the type's interface:
   - `properties`: Array of `{name, type, readonly?}` entries
   - `methods`: Array of `{name, params: [{name, type}], returns}` entries
2. **`definition`** — A verbatim code string in the project's language (see Step 2 for language detection)
3. **`owner`** — The story ID that primarily implements/defines the type (usually the story that creates it as an output)
4. **`consumers`** — Array of story IDs that reference or depend on the type (all stories except the owner)
5. **`definitionFile`** — The file path where the type definition should live (see "Inferring `definitionFile` Paths" below)

**Anti-rationalization:** If 2+ stories reference a type by name, you MUST generate `shape` and `definition` fields. "It's only used lightly" or "the shape is obvious" are not valid reasons to skip structural contracts. The downstream materializer cannot generate a file without a `definition` or `shape`.

#### Step 2: Detect Project Language

Determine the project's primary language by checking for config files in the project root:

| Config File | Language | `definition` Style |
|---|---|---|
| `tsconfig.json` | TypeScript | `export interface X { ... }` or `export type X = { ... }` |
| `pyproject.toml` or `setup.py` | Python | `class X(Protocol): ...` or `@dataclass class X: ...` |
| `go.mod` | Go | `type X interface { ... }` or `type X struct { ... }` |

Detection priority: check in the order listed above. If multiple config files exist, use the `definitionFile` extension as a tiebreaker.

#### Step 3: Generate Language-Specific Definitions

Based on the detected language, generate the `definition` string:

**TypeScript:**
```
export interface TaskResult {
  id: string;
  status: "pending" | "passed" | "failed";
  output: string;
  errorMessage?: string;
}
```

**Python:**
```
from dataclasses import dataclass
from typing import Optional

@dataclass
class TaskResult:
    id: str
    status: str  # "pending" | "passed" | "failed"
    output: str
    error_message: Optional[str] = None
```

**Go:**
```
type TaskResult struct {
    ID           string `json:"id"`
    Status       string `json:"status"`
    Output       string `json:"output"`
    ErrorMessage string `json:"errorMessage,omitempty"`
}
```

#### Step 4: Reference for Examples

See `references/contract-shapes.md` for complete examples of `shape` JSON paired with `definition` strings for all three languages. Load this reference when shared types are detected — it contains guidance on when to generate `definition` (multi-consumer types) vs shape-only (advisory, single-consumer types).

#### Step 5: Inferring `definitionFile` Paths

When a contract entry does not have an explicit `definitionFile`, infer the path from the project's existing directory structure. Check directories in this priority order:

1. `src/shared/types/` — TypeScript convention (most specific)
2. `src/types/` — common alternative for TypeScript/general
3. `src/interfaces/` — common alternative for interface-heavy projects
4. `types/` — project-root convention (some projects keep types at root level)
5. `shared/` — Python and Go convention

**If a matching directory exists**, use it as the base path for the `definitionFile`. Append the type name in kebab-case with the appropriate language extension (`.ts`, `.py`, `.go`).

**If none of these directories exist**, default based on the detected language:
- **TypeScript:** `src/shared/types/<kebab-name>.ts`
- **Python:** `src/shared/<snake_name>.py`
- **Go:** `internal/shared/<snake_name>.go`

**If `definitionFile` IS explicitly set** in a contract entry (e.g., from user input or a previous run), it takes precedence over any inference. Do not override explicit paths.

#### Complete Enhanced Contract Example

Below is a complete example of a `contracts.shared_types` entry with all enhanced fields. This demonstrates a `TaskResult` type shared between US-003 (which implements it) and US-007/US-009 (which consume it), in a TypeScript project that has an existing `src/types/` directory:

```json
"contracts": {
  "shared_types": {
    "task_result": {
      "value": "TaskResult",
      "pattern": "^[A-Z][a-zA-Z]*$",
      "definitionFile": "src/types/task-result.ts",
      "owner": "US-003",
      "consumers": ["US-007", "US-009"],
      "shape": {
        "properties": [
          { "name": "id", "type": "string" },
          { "name": "status", "type": "'pending' | 'passed' | 'failed'" },
          { "name": "output", "type": "string" },
          { "name": "errorMessage", "type": "string", "readonly": false }
        ],
        "methods": []
      },
      "definition": "export interface TaskResult {\n  id: string;\n  status: 'pending' | 'passed' | 'failed';\n  output: string;\n  errorMessage?: string;\n}"
    }
  }
}
```

Key points:
- `definitionFile` was inferred from the existing `src/types/` directory (priority item 2), not hardcoded
- `owner` is the story that creates the type as its primary output
- `consumers` lists every other story that references the type
- `shape` provides a structured representation that downstream tools can use to generate code if `definition` is missing
- `definition` provides the verbatim code string in the detected language (TypeScript in this case)

#### Stories with No Shared Types

If no type names appear in 2+ stories, do NOT generate `shape` or `definition` fields. The basic contracts block (with `value` and optional `pattern`) is sufficient. This maintains backward compatibility — entries with only `value` and `pattern` remain valid.

### Story Type Tagging

After building the dependency DAG and contracts, assign a `storyType` field to every story. This field is used by the dag-validator to determine which restructuring is safe.

#### Allowed Values

| `storyType` | Description |
|---|---|
| `types-only` | Stories where ALL tasks create type definitions, interfaces, schemas, or `.d.ts` files with no runtime logic. |
| `config` | Scaffold/config-only stories: migrations, `package.json` changes, Dockerfile, CI yaml, pure markdown. |
| `test` | Stories that only add tests with no new source code. |
| `logic` | Everything else (the default). Any story with business logic, API handlers, data processing, or external API calls. |

#### Examples

**`types-only`** — `US-001: Define TaskResult interface`
Tasks only create `.ts` interface files (e.g., `src/types/task-result.ts`). No runtime logic, no function bodies, no side effects — purely structural type definitions.

**`config`** — `US-002: Set up database migration`
Tasks only create migration files, update `package.json` dependencies, or modify CI configuration. No `if` statements, no loops, no data transformations.

**`test`** — `US-004: Add unit tests for task filtering`
Tasks only add test files (e.g., `tests/task-filter.test.ts`). No new source modules are created — only test coverage for existing code.

**`logic`** — `US-003: Implement task filtering API`
Tasks contain `if`/`loop`/data logic, API route handlers, database queries, or calls to external services. This is the default and the most common type.

#### Anti-Rationalization Guard

> **If a story has any task that implements business logic, API handlers, data processing, or calls external APIs, it is `logic`, not `types-only`. When in doubt, use `logic`.**

Common traps:
- A story that creates an interface AND a helper function is `logic`, not `types-only` — the helper function is runtime code.
- A story that creates a schema file with validation logic (e.g., Zod schemas with `.refine()`) is `logic` — refinements execute at runtime.
- A story that creates config AND a small utility to read that config is `logic` — the utility is runtime code.

#### Default Behavior

If you are unsure, set `storyType` to `logic`. It is always safe to over-classify as `logic` — under-classifying as `types-only` can cause incorrect restructuring by the dag-validator, which may reorder stories that should not be reordered.

### wiring_verification Generation

Tasks that create new modules, handlers, or components **SHOULD** have a `wiring_verification` object unless wiring is handled by a dependent story via `consumedBy`.

**Rule:** If a task creates a new file (function, class, component, handler) that must be imported by an existing file, add:
```json
"wiring_verification": {
  "file": "path/to/caller.ts",
  "must_contain": ["import { NewThing }", "NewThing"]
}
```

- `file`: The existing file that should import/call the new code
- `must_contain`: Array of exact strings that must appear in that file after implementation

**Exception:** If the task's output will be consumed by a dependent story (the dependent story is responsible for the import), use `consumedBy` instead of `wiring_verification`. Both on the same task is redundant.

### consumedBy Generation

If a task's output is listed in a dependent story's acceptance criteria, the task **MUST** have a `consumedBy` field listing the consuming story IDs.

**Rule:** When Story A creates a component/module and Story B's acceptance criteria reference it:
1. Add `"consumedBy": ["US-B"]` to the task in Story A
2. Add to Story B's **first task** description: `"Import <component> from <path> (created by <Story A ID>). Do NOT create an inline replacement."`

This prevents the consumer story's agent from re-implementing something that already exists. The `consumedBy` field is the signal: "Don't build this yourself — it will exist when your dependencies are satisfied."

### coverageThreshold Generation

Set the top-level `coverageThreshold` field in quantum.json:
1. **Ask the user** for their desired coverage threshold, OR
2. **Infer from project config:** check `.nycrc`, `jest.config.*`, `pyproject.toml [tool.coverage]`, `.coveragerc`, `go test` flags for an existing threshold
3. **Default:** 80 (percent). Set to `null` to report coverage without blocking.

The quality-reviewer will enforce this threshold during review. If the project has no coverage tooling, the reviewer will skip enforcement on the first story and enforce after first successful measurement.

## Step 3: Decompose Stories into Tasks

For each story, break it into granular tasks. Each task should take 2-5 minutes for an AI agent.

### Task Requirements
Each task MUST specify:
- `id`: Sequential within the story (T-001, T-002, ...)
- `title`: Short imperative description
- `description`: Exact steps to perform. Include:
  - What to create/modify
  - Specific logic or behavior
  - How it connects to other code
- `filePaths`: Array of files this task creates or modifies
- `commands`: Array of verification commands with expected behavior
- `testFirst`: Boolean -- should a test be written first? (default: true for logic, false for config/scaffolding)
- `status`: Always "pending" when created

### Integration Wiring Rule (CRITICAL)

Every story that creates a new module, function, or component MUST include a final task that wires it into the existing codebase. Without this, parallel agents build components in isolation that are never called.

**Bad:** Story creates `extract_docx_images()` but never modifies `DocxLoader.load()` to call it.
**Good:** Story's last task is "Wire `extract_docx_images()` into `DocxLoader.load()` — add import, call the function after text extraction, pass results to chunk builder."

The wiring task MUST specify:
- Which existing file(s) to modify (the caller, not the new module)
- What import to add
- Where in the control flow to insert the call
- A verification command that proves the wiring works (e.g., an integration test or a pipeline run)

If a story creates something that will be wired by a DEPENDENT story, document this explicitly in the dependent story's first task: "Import and call `X` from the newly completed `US-NNN`."

### Consumer Verification Pattern

When Story A creates a function and Story B (dependent) should call it:
- Story A's acceptance criteria: "function exists, passes unit tests"
- Story B's acceptance criteria MUST include: "pipeline calls `<function>` for every `<input>`"

**Bad:** US-007 AC says "validate_plan_item rejects invalid items" (only tests the function in isolation)
**Good:** US-013 AC says "pipeline calls validate_plan_item() for every generated plan item" (verifies wiring)

The key shift: validation of wiring belongs on the **consumer** story, not the creator.

### Task Sizing Guide

**Right-sized (2-5 minutes):**
- Write a test for one function
- Implement one function to pass the test
- Add one column to a database migration
- Create one React component (no logic, just rendering)
- Add one API route handler
- **Wire a new module into an existing caller** (import + call + verify)

**Too large (split these):**
- "Build the component with all its logic and tests"
- "Create the API endpoint with validation and error handling"
- "Add the feature end-to-end"

**Too small (combine these):**
- "Create an empty file"
- "Add an import statement"
- "Fix a typo in a comment"

### testFirst Mandate

**`testFirst: true` is the default for ALL tasks.** TDD is a mandate, not a suggestion.

**Exempt categories** (the ONLY cases where `testFirst: false` is allowed):
- Config/scaffold files (migrations, package.json, tsconfig changes)
- Pure type definitions (interfaces, type aliases, enums with no logic)
- Documentation-only tasks (README, comments, markdown files)
- The test task itself (when test and implementation are separate tasks)

**For any exempt task**, the planner **MUST** add a `notes` field with justification:
```json
"testFirst": false,
"notes": "testFirst: false — pure type definition, no runtime logic"
```

**Anti-rationalization line:** If a task has an `if`, a loop, a data transformation, or calls an external API, it is NOT config. Set `testFirst: true`.

### Edge Case Test Requirements

When `testFirst: true`, the task description MUST instruct the agent to include tests for:
- **Boundary values:** None/null, empty string, NaN, zero, negative numbers
- **Type variations:** scalar vs collection vs framework-specific types (e.g., DataFrame vs dict)
- **Collision scenarios:** same identifier from different sources (e.g., same filename in different dirs)
- **Scale:** 1 item (minimum), 10 items (typical), 100+ items (context pollution shows at scale)

See `references/edge-cases.md` for language-specific patterns.

Field data shows 100% of post-implementation bugs were edge cases that passed happy-path tests.

## Step 4: Generate quantum.json

Assemble the complete quantum.json with this structure:

```json
{
  "project": "[Project name from package.json or user input]",
  "branchName": "ql/[feature-name-kebab-case]",
  "description": "[One-line feature description from PRD title]",
  "prdPath": "[Path to the PRD file]",
  "designPath": "[Path to design doc, or null]",
  "createdAt": "[ISO 8601 timestamp]",
  "updatedAt": "[ISO 8601 timestamp]",
  "stories": [
    {
      "id": "US-001",
      "title": "[Story title]",
      "description": "As a [user], I want [feature] so that [benefit]",
      "acceptanceCriteria": ["criterion 1", "criterion 2", "Typecheck passes"],
      "priority": 1,
      "status": "pending",
      "dependsOn": [],
      "tasks": [
        {
          "id": "T-001",
          "title": "[Task title]",
          "description": "[Exact steps]",
          "filePaths": ["path/to/file.ts"],
          "commands": ["npm test -- path/to/test.ts"],
          "testFirst": true,
          "status": "pending"
        }
      ],
      "review": {
        "specCompliance": { "status": "pending", "issues": [], "reviewedAt": null },
        "codeQuality": { "status": "pending", "issues": [], "reviewedAt": null }
      },
      "retries": { "attempts": 0, "maxAttempts": 3, "failureLog": [] },
      "notes": ""
    }
  ],
  "progress": [],
  "codebasePatterns": []
}
```

### Field Rules
- `branchName`: Always prefixed with `ql/`, followed by kebab-case feature name
- `priority`: Integer starting at 1. Used as tiebreaker when DAG allows multiple stories.
- `dependsOn`: Array of story IDs (e.g., `["US-001", "US-002"]`). Empty array for stories with no dependencies.
- `status`: Always "pending" for all stories and tasks when first created.
- `retries.maxAttempts`: Default 3. Increase for complex stories if needed.

## Step 5: Validate and Save

Before saving, verify:
- [ ] Every story from the PRD is represented
- [ ] Every acceptance criterion is preserved (not summarized or paraphrased)
- [ ] Dependency graph has no cycles
- [ ] Every story has at least one task
- [ ] Every task has file paths and verification commands
- [ ] All statuses are "pending"
- [ ] Branch name follows `ql/` prefix convention
- [ ] Priority numbers are sequential with no gaps
- [ ] Every story that creates a function has a consumer story with a wiring AC
- [ ] **File-touch conflict check:** No two parallel stories (neither depends on the other) share `filePaths` entries. If conflicts found:
  - Add a "Reconcile `<file>` changes from `<other-story>`" task as the **last task** of the **higher-priority** (later-executing) story
  - This task is written directly into `quantum.json` during plan generation — it is NOT added at runtime
  - The reconciliation task runs AFTER both stories have merged (it depends on the other story implicitly via execution order)
  - Add the conflict to `quantum.json` metadata: `"fileConflicts": [{"file": "generator.py", "stories": ["US-007", "US-008"]}]` so users see risks before execution
  - This does NOT force sequential execution — it allows parallel but plans for the merge

Save to: `quantum.json` in the project root.

If a previous `quantum.json` exists:
1. Check if it's for the same feature (same branchName)
2. If DIFFERENT feature: archive to `archive/YYYY-MM-DD-<old-branch>/quantum.json`
3. If SAME feature: ask user whether to overwrite or merge

## Step 6: Set Up Runner Scripts

After saving quantum.json, ensure the user can run autonomous execution:

1. Add to `.gitignore` if not already present: `.ql-wt/`, `.quantum-logs/`, `quantum.json.tmp`
2. Check if `quantum-loop.sh` already exists in the project root
3. If it does NOT exist, inform the user to get the runner scripts:

> "Plan saved to `quantum.json` with [N] stories and [M] total tasks. Dependencies: [describe the DAG briefly].
>
> **To execute:**
> - Interactive (recommended): `/quantum-loop:ql-execute`
> - Autonomous overnight (get runner scripts first):
>   ```bash
>   # Download runner scripts from the quantum-loop repo
>   curl -sO https://raw.githubusercontent.com/andyzengmath/quantum-loop/main/templates/quantum-loop.sh && chmod +x quantum-loop.sh
>   curl -sO https://raw.githubusercontent.com/andyzengmath/quantum-loop/main/templates/quantum-loop.ps1
>   # Then run:
>   ./quantum-loop.sh --max-iterations 20                    # Linux/Mac sequential
>   ./quantum-loop.sh --parallel --max-parallel 4            # Linux/Mac parallel
>   .\quantum-loop.ps1 -MaxIterations 20 -SkipPermissions    # Windows PowerShell
>   ```"

If `quantum-loop.sh` already exists, just inform:
> "Plan saved to `quantum.json` with [N] stories and [M] total tasks.
> Run `/quantum-loop:ql-execute` or `./quantum-loop.sh --max-iterations 20`."

## Anti-Rationalization Guards

| Excuse | Reality |
|--------|---------|
| "Tasks don't need file paths, the agent will figure it out" | Vague tasks produce vague implementations. Specify exact paths. |
| "This task is 10 minutes but it's not worth splitting" | If it exceeds 5 minutes, the agent may run out of context. Split it. |
| "Dependencies are obvious, I don't need to specify them" | What's obvious to you is invisible to a stateless agent. Specify all dependencies. |
| "All tasks should be testFirst" | Config and scaffolding tasks don't need tests first. Be intentional. |
| "Verification commands aren't needed for this task" | Every task needs a way to verify it worked. No exceptions. |
| "I'll skip cycle detection" | Circular dependencies cause infinite loops in the execution engine. Always check. |
| "The wiring will happen naturally" | It won't. Parallel agents can't see each other's work. Every story needs an explicit wiring task that modifies the CALLER, not just the new module. |
| "Creating the module is enough, someone will import it" | Nobody will. If no task says "add import X to file Y and call it at line Z", it stays dead code forever. |
