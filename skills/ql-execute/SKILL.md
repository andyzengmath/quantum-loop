---
name: ql-execute
description: Run the autonomous execution loop. Reads quantum.json, queries the dependency DAG, implements stories with TDD and two-stage review gates. Supports parallel execution via native worktree isolation. Use after /quantum-loop:plan has created quantum.json. Triggers on: execute, run loop, start building, ql-execute.
---

# Quantum-Loop: Execute

Run the autonomous execution loop to implement all stories in quantum.json.

## Prerequisites

Before starting:
1. `quantum.json` must exist (created by `/quantum-loop:plan`)
2. The project must be a git repository
3. Project build tools must be available (npm, pip, cargo, etc.)

If prerequisites are not met, inform the user and stop.

## Execution

Read and follow the orchestrator agent instructions in `agents/orchestrator.md`.

The orchestrator will:
1. Read quantum.json state and validate the dependency DAG
2. Query for eligible stories (pending/retriable with all dependencies passed)
3. **If 1 story eligible:** execute it sequentially (implement, quality checks, review, commit)
4. **If 2+ stories eligible:** spawn parallel implementer subagents in isolated worktrees
5. Handle retries, cascade blocking, and error recovery
6. Loop until all stories pass (COMPLETE) or no stories are executable (BLOCKED)

## Autonomous CLI Alternative

For unattended execution outside Claude Code (Linux/Mac):
```bash
./quantum-loop.sh --max-iterations 20
./quantum-loop.sh --parallel --max-parallel 4
```

On Windows, use `/ql-execute` instead of the shell script for reliable execution.

## Signals

| Signal | Meaning |
|--------|---------|
| `<quantum>COMPLETE</quantum>` | All stories passed |
| `<quantum>BLOCKED</quantum>` | No executable stories remain |
| `<quantum>STORY_PASSED</quantum>` | One story completed (more remain) |
| `<quantum>STORY_FAILED</quantum>` | One story failed (will retry if attempts remain) |
