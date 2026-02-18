---
name: plan
description: "Convert a PRD into machine-readable quantum.json with dependency DAG, granular 2-5 minute tasks, and execution metadata. Use after creating a spec. Triggers on: create plan, convert to json, plan tasks, generate quantum json."
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

### Task Sizing Guide

**Right-sized (2-5 minutes):**
- Write a test for one function
- Implement one function to pass the test
- Add one column to a database migration
- Create one React component (no logic, just rendering)
- Add one API route handler
- Wire one component into a page

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

Inform the user:
> "Plan saved to `quantum.json` with [N] stories and [M] total tasks. Dependencies: [describe the DAG briefly]. When you're ready to start building, run `/quantum-loop:execute`."

## Anti-Rationalization Guards

| Excuse | Reality |
|--------|---------|
| "Tasks don't need file paths, the agent will figure it out" | Vague tasks produce vague implementations. Specify exact paths. |
| "This task is 10 minutes but it's not worth splitting" | If it exceeds 5 minutes, the agent may run out of context. Split it. |
| "Dependencies are obvious, I don't need to specify them" | What's obvious to you is invisible to a stateless agent. Specify all dependencies. |
| "All tasks should be testFirst" | Config and scaffolding tasks don't need tests first. Be intentional. |
| "Verification commands aren't needed for this task" | Every task needs a way to verify it worked. No exceptions. |
| "I'll skip cycle detection" | Circular dependencies cause infinite loops in the execution engine. Always check. |
