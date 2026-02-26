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

### TDD Flag Rules
Set `testFirst: true` when:
- The task implements business logic
- The task adds an API endpoint
- The task creates a data transformation
- The task adds user-facing behavior

Set `testFirst: false` when:
- The task creates config files (migrations, package.json changes)
- The task is pure scaffolding (empty component skeleton)
- The task modifies only type definitions
- The task is the test itself (when test and implementation are separate tasks)

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
