---
name: ql-plan
description: "Part of the quantum-loop autonomous development pipeline (brainstorm \u2192 spec \u2192 plan \u2192 execute \u2192 review \u2192 verify). Convert a PRD into machine-readable quantum.json with dependency DAG, granular 2-5 minute tasks, and execution metadata. Use after creating a spec with /quantum-loop:spec. Triggers on: create plan, convert to json, plan tasks, generate quantum json, ql-plan."
---

# Quantum-Loop: Plan

You are converting a Product Requirements Document (PRD) into a machine-readable `quantum.json` file that will drive autonomous execution. Every decision you make here determines whether the execution loop succeeds or fails.

## Phase 0: Phase-skip check (Phase 18 / P2.4)

Before reading the PRD, check whether a prior `/ql-plan` run already converted the same PRD + spec handoff into quantum.json:

```bash
PRD=$(ls -t tasks/prd-*.md 2>/dev/null | head -1)
SPEC_HANDOFF=".handoffs/spec.md"
ARGS=()
[[ -n "$PRD" ]]             && ARGS+=("$PRD")
[[ -f "$SPEC_HANDOFF" ]]    && ARGS+=("$SPEC_HANDOFF")

if bash lib/phase-skip.sh skip plan . "${ARGS[@]}"; then
  echo "[SKIP] plan is up-to-date — PRD + spec handoff unchanged."
  bash lib/handoff.sh read plan | jq '.'
  exit 0
fi
```

After writing quantum.json and `.handoffs/plan.md`, record the fingerprint:

```bash
PRD_H=$(bash lib/phase-skip.sh hash "$PRD")
SPEC_H=$(bash lib/phase-skip.sh hash "$SPEC_HANDOFF")
FP=$(jq -cn --arg pp "$PRD" --arg ph "$PRD_H" --arg sp "$SPEC_HANDOFF" --arg sh "$SPEC_H" \
  '{artifacts: [{path: $pp, sha256: $ph}, {path: $sp, sha256: $sh}]}')
bash lib/phase-skip.sh record plan "$FP" . >/dev/null
```

## Prerequisite: read prior-stage handoffs (Phase 15 / P2.3)

Before reading the PRD, ingest every prior-stage handoff so decisions, rejected alternatives, and risks carry forward across context compaction:

```bash
bash lib/handoff.sh all | jq '.'
bash lib/handoff.sh read brainstorm | jq '.'
bash lib/handoff.sh read spec | jq '.'
```

Treat `spec.decided` as binding (these are the ACs you MUST plan for), `spec.rejected` as closed (don't re-introduce), `spec.remaining` as explicit gaps you should surface to the user before finalizing the DAG, and the union of `brainstorm.risks ∪ spec.risks` as mandatory inputs to every story's risk consideration.

At the end of `/ql-plan`, write `.handoffs/plan.md`:

```bash
bash lib/handoff.sh write plan "$(cat <<'JSON'
{
  "decided":   ["<each DAG + wave decision>", "<contract materialization picks>"],
  "rejected":  ["<each alternative story split / ordering considered>"],
  "risks":     ["<carried from upstream + any new planning risks>"],
  "files":     ["quantum.json"],
  "remaining": ["<any AC you could not resolve into a concrete story>"],
  "notes":     "<notes on parallelism, file-conflict sets, contract choices>"
}
JSON
)"
```

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

### Interface Change Detection

When a story modifies the return type, parameter types, or function/method signatures of code consumed by other stories, it creates a **contract-breaking change**. These changes require explicit coordination to prevent regressions in parallel execution.

#### When to Set `contractBreaking: true`

Set `contractBreaking: true` on any story that:

1. **Changes a return type** of a function, method, or class consumed by another story
2. **Changes parameter types** (adding required parameters, removing parameters, or changing parameter types) of a shared function or method
3. **Changes a class/interface signature** (renaming methods, changing method visibility, altering inheritance) that other stories depend on

When `contractBreaking` is set, the story description **MUST** include an explanation of what interface changed and why. This explanation helps the execution engine and human reviewers understand the blast radius.

#### When to Set `fixes`

Set `fixes: ["US-XXX"]` on any story that is specifically designed to resolve regressions or breakage introduced by another story. The `fixes` field is an array of story IDs whose regressions this story addresses.

#### Scheduling Constraint

Stories with `contractBreaking: true` **MUST** have explicit `dependsOn` edges that prevent them from being co-scheduled (running in the same wave) with any story that consumes the changed interface. This ensures consumers always see the final version of the interface, not an in-flight breaking change.

**Rule:** For every consumer of the changed interface, either:
- The consumer `dependsOn` the contract-breaking story (consumer runs after), OR
- The contract-breaking story `dependsOn` the consumer (breaking change runs after consumer finishes with old interface)

#### Examples

**Example 1: Breaking change to a shared interface**

US-003 changes the return type of `IParser.parse()` from `string` to `ParseResult`. US-005 and US-008 both call `IParser.parse()`. This is a contract-breaking change because consumers expect the old return type.

```json
{
  "id": "US-003",
  "title": "Refactor IParser.parse() to return ParseResult",
  "description": "Changes IParser.parse() return type from string to ParseResult. This is contractBreaking because US-005 and US-008 consume IParser.parse() and expect the old return type.",
  "contractBreaking": true,
  "dependsOn": [],
  "storyType": "logic"
}
```

US-005 and US-008 must add `"US-003"` to their `dependsOn` arrays so they run after the breaking change lands.

**Example 2: Fixing regressions from a breaking change**

US-004 is created specifically to fix async regressions introduced by US-003's interface change. It patches call sites that were missed or broke unexpectedly.

```json
{
  "id": "US-004",
  "title": "Fix async regressions from IParser refactor",
  "description": "Fixes async call sites that broke when US-003 changed IParser.parse() return type.",
  "fixes": ["US-003"],
  "dependsOn": ["US-003"],
  "storyType": "logic"
}
```

**Example 3: Non-breaking change (no flag needed)**

US-007 adds an optional `verbose` parameter with a default value to `IParser.parse()`. Existing callers continue to work without modification because the parameter is optional.

```json
{
  "id": "US-007",
  "title": "Add optional verbose parameter to IParser.parse()",
  "description": "Adds optional verbose parameter with default false. Existing callers are unaffected.",
  "dependsOn": ["US-003"],
  "storyType": "logic"
}
```

Note: `contractBreaking` is **NOT** set because adding an optional parameter with a default value does not change the interface for existing consumers.

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

### reuseCandidates Generation (Track A / Q2 — reuse-first)

For each story, populate `reuseCandidates[]` with existing symbols the implementer should REUSE instead of reinventing. This extends `consumedBy` (intra-plan) to the whole existing codebase, attacking the "reinvent instead of reuse" + duplication slop classes.

1. **With the code graph** (preferred): run the `relational_envelope` verb keyed on the story's acceptance-criteria nouns/verbs → existing FUNCTION/CLASS nodes + near-duplicate candidates, with per-edge confidence tiers (surface EXTRACTED/INFERRED candidates as "must consider"; leave AMBIGUOUS advisory).
2. **Without a graph** (fallback): `bash lib/reuse-scan.sh scan "<comma-separated concept terms>" .` → existing symbol definitions whose names relate to the story (test files excluded).

Write the result as `reuseCandidates: [{symbol, file, line}]` on the story. The implementer (`agents/implementer.md`) must then reuse one or record a `noReuseJustification`; `lib/reuse-scan.sh gate` enforces it (advisory by default, blocking under `QL_QUALITY_BLOCKING`). Empty `reuseCandidates` (nothing relevant exists) is fine — the gate is a no-op.

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
      "reuseCandidates": [],
      "priority": 1,
      "status": "pending",
      "dependsOn": [],
      "surfaceBudget": { "maxNewFiles": 3, "maxNewLines": 200, "maxNewPublicSymbols": 8, "maxNewAbstractions": 2 },
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
- `reuseCandidates`: Existing symbols `[{symbol, file, line}]` the implementer should reuse before writing new code (Track A / Q2 reuse-first). Populated by the reuseCandidates Generation step below; empty is fine.
- `status`: Always "pending" for all stories and tasks when first created.
- `retries.maxAttempts`: Default 3. Increase for complex stories if needed.
- `surfaceBudget`: Per-story cap on NEW surface (Track A anti-slop gate): `maxNewFiles` / `maxNewLines` / `maxNewPublicSymbols` / `maxNewAbstractions`. Scale defaults with story size — a 2-5-minute task needs a small budget; tighten for focused stories. Enforced pre-review by `lib/surface-budget.sh` (a story over budget is failed back to re-plan / split, not reviewed) and validated by `lib/quantum-validate.sh` (blocking under `QL_VALIDATE_BLOCKING`). The `maxNewAbstractions` cap targets premature generality; small `maxNewLines` forces bounded diffs.

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

## Step 7: DAG Validation

After generating quantum.json, spawn the dag-validator agent to analyze the DAG for bottlenecks, duplication, and file conflicts. The validator runs automatically — no user action required.

### Spawning the dag-validator

Use the Agent tool to spawn the dag-validator agent with `subagent_type` set to the dag-validator agent definition. Pass two arguments: the quantum.json path and the PRD path. Wait for the agent to complete.

### Idempotency handling

If the dag-validator returns "Already validated on \<timestamp\>", skip the remaining validation steps. Print:

> "Plan already validated on \<timestamp\>. Skipping DAG validation."

### Receiving results

The dag-validator returns:

1. A list of stub story IDs (may be empty)
2. A DAG Health Report text string

### Stub flesh-out

If the dag-validator returned stub story IDs:

1. Re-read quantum.json (the validator has modified it)
2. For each stub ID, the story will have `STUB:` prefix in its `notes` field and empty `tasks`, `acceptanceCriteria`, and `filePaths`
3. Re-invoke the planner with a scoped prompt:

> "Flesh out these stub stories: [list IDs]. Read the PRD at [prdPath] and the existing quantum.json for context. For each stub, add tasks (with filePaths, commands, testFirst), acceptanceCriteria, and filePaths. Do NOT modify any other stories. Follow all task sizing, testFirst, and wiring rules from this skill."

4. Write the fleshed-out stories back to quantum.json

### Stub validation

After flesh-out, validate each stub:

- `tasks.length > 0`
- `acceptanceCriteria.length > 0`

If a stub passes validation: remove the `STUB:` prefix from its `notes` field.

### Revert on failure

If a stub fails validation (empty `tasks` or `acceptanceCriteria`):

1. Remove the stub story from the quantum.json `stories` array
2. For every other story whose `dependsOn` contains the stub ID, remove the stub ID from their `dependsOn` array
3. Log in the Health Report:

> "Stub \<ID\> could not be fleshed out — reverted to original DAG structure."

### Output

Print the complete DAG Health Report to the user. This is the last thing the user sees before reviewing quantum.json. Format with clear section headers:

- **Bottlenecks** — sequential chains and fan-out blockers detected
- **Duplication Risks** — overlapping implementation concerns between stories
- **File Conflicts** — files touched by multiple stories with severity classification
- **Stubs Created** — new shared-utility stories extracted by the validator

## Step 8: Sprint-Contract write per story (G3 / US-004 / v0.6.3)

This step runs **after dag-validator** completes (and after any stub flesh-out is finalized). Iterate `.stories[]` in quantum.json and write a per-story Sprint-Contract to `.handoffs/sprint-<storyId>.json`. This makes the planner's decision-context durable for downstream skills (`/ql-execute`, `/ql-review`) without re-parsing the full PRD per story. Mirrors Anthropic's 2026-03-24 Generator-Evaluator contract.

The step is **idempotent** — re-running `/ql-plan` overwrites existing sprint-contract files with the latest content (only `plannedAt` will differ). Backward-compat: if `lib/handoff.sh::write_sprint_contract` is unavailable (older repos), skip the step with a one-line warning.

**G14 / US-003 (v0.7.0):** the test-pattern regex is sourced from `lib/handoff.sh::SPRINT_CONTRACT_TEST_REGEX` (single source of truth) and passed to jq via `--arg pattern`.

```bash
source "$REPO_ROOT/lib/handoff.sh"
source "$REPO_ROOT/lib/json-atomic.sh"  # Mandatory: compute_prd_sha must produce the same
                                        # LF-normalized hash that the orchestrator's Step 1.1
                                        # validates against. A `sha256sum` fallback would yield
                                        # a divergent format and mark every story stale on first
                                        # orchestrator run.

PRD_PATH=$(jq -r '.prdPath' quantum.json)
PRD_SHA=$(compute_prd_sha "$PRD_PATH")

# Iterate stories[]. Strip CRLF defensively (CLAUDE.md Platform Notes: heredocs
# on Git Bash/MSYS produce CRLF; jq -r preserves them in some configurations).
while IFS= read -r sid; do
  sid="${sid%$'\r'}"
  [[ -z "$sid" ]] && continue
  CONTRACT=$(jq -n --arg id "$sid" --arg sha "$PRD_SHA" --arg ts "$(date -u +%FT%TZ)" \
    --arg pattern "$SPRINT_CONTRACT_TEST_REGEX" \
    --slurpfile q quantum.json '
      ($q[0].stories[] | select(.id == $id)) as $story |
      ($story.tasks // []) as $tasks |
      {
        storyId: $id,
        prdSha: $sha,
        acs: ($story.acceptanceCriteria // []),
        contracts: ($q[0].contracts // {}),
        files: [$tasks[].filePaths // []] | flatten | unique,
        expectedTests: ([$tasks[].commands // []] | flatten | map(select(test($pattern)))),
        otherCommands: ([$tasks[].commands // []] | flatten | map(select(test($pattern) | not))),
        plannedBy: "ql-plan",
        plannedAt: $ts
      }')
  write_sprint_contract "$sid" "$CONTRACT"
done < <(jq -r '.stories[].id' quantum.json)
```

Inform the user: `[QL-PLAN] Wrote N sprint-contract files to .handoffs/sprint-*.json`. The contracts are consumed by `agents/implementer.md` (`read_sprint_contract`) and the spec-reviewer / quality-reviewer subagents.

## Step 9: Post-exit plan-review (P5.B4 / US-008 / v0.6.3 — advisory)

This step runs **after Step 7 (dag-validator) and Step 8 (sprint-contract write)** complete. Invoke the spec-reviewer in `plan-review` mode against the just-finalized `quantum.json` cross-referenced against the PRD. The review is **advisory** — findings emit to stderr; the skill does NOT abort.

```bash
JSON_PATH="quantum.json"
PRD_PATH=$(jq -r '.prdPath' "$JSON_PATH" 2>/dev/null)

# Opt-out gate: QL_SKIP_PRE_IMPL_REVIEW=plan (or comma-chain like design,prd,plan).
SKIP_LIST="${QL_SKIP_PRE_IMPL_REVIEW:-}"
if [[ -n "$PRD_PATH" ]] && \
   ! printf '%s' "$SKIP_LIST" | tr ',' '\n' | grep -qx "plan"; then
  echo "[QL-PLAN] Running spec-reviewer in plan-review mode (advisory)..." >&2

  # G13 / US-002 (v0.7.0): capture the reviewer stderr, parse FINDING blocks
  # via lib/finding-synth.sh, and persist the parsed summary + per-run snapshot
  # via lib/finding-persist.sh. Advisory contract preserved — the skill never
  # aborts based on findings. The reviewed artifact for the plan stage is
  # quantum.json itself (cross-referenced against the PRD).
  REVIEW_LOG=$(mktemp)
  MODE=plan-review JSON_PATH="$JSON_PATH" PRD_PATH="$PRD_PATH" \
    claude --headless "agents/spec-reviewer.md plan-review mode against $JSON_PATH and $PRD_PATH" \
      2> "$REVIEW_LOG" || true

  # Source the parser + persister (no shell flags inherited; libs are flag-free at source).
  # shellcheck disable=SC1091
  source lib/finding-synth.sh
  # shellcheck disable=SC1091
  source lib/finding-persist.sh

  findings=$(parse_findings plan < "$REVIEW_LOG")
  summary=$(summarize_findings plan "$findings")
  persist_review_findings plan "$JSON_PATH" "$summary" "$findings" >/dev/null
  format_summary_line "$summary" >&2; echo >&2

  # Surface the reviewer's stderr (so operators still see FINDING blocks).
  cat "$REVIEW_LOG" >&2
  rm -f "$REVIEW_LOG"
else
  echo "[QL-PLAN] plan-review skipped (QL_SKIP_PRE_IMPL_REVIEW=plan or no PRD)" >&2
fi
```

Step ordering reference: dag-validator (Step 7) -> sprint-contract write (Step 8) -> plan-review (Step 9). Findings stream to stderr in `FINDING_START..FINDING_END` blocks.

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
