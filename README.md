# Quantum-Loop

**Your AI agent writes code. Quantum-Loop makes sure it writes the *right* code.**

A Claude Code plugin that turns a one-line feature description into verified, reviewed, autonomously-implemented code -- through structured specs, dependency-aware execution, and mandatory verification gates that prevent AI agents from cutting corners.

> Named after [Loop Quantum Gravity](https://en.wikipedia.org/wiki/Loop_quantum_gravity): spacetime is built from discrete, verified loops. So is your codebase.

---

## The Problem

AI coding agents are fast. They're also confidently wrong. They skip tests, ignore specs, claim "it should work" without checking, and produce code that drifts from requirements with each iteration.

**Quantum-Loop solves this with three principles:**

1. **Structured specs before code** -- No implementation until requirements are formal, granular, and machine-verifiable
2. **Dependency-aware execution** -- Stories execute from a DAG, not a flat list. Failures don't cascade into unrelated work
3. **No claims without evidence** -- The Iron Law: every "it works" requires fresh command output proving it

---

## How It Works

```
/quantum-loop:brainstorm → /quantum-loop:spec → /quantum-loop:plan → /quantum-loop:execute
         │                        │                     │                      │
      Socratic               9-section            quantum.json          Autonomous loop
      dialogue                 PRD                with DAG               with gates
         │                        │                     │                      │
         ▼                        ▼                     ▼                      ▼
      design.md              prd-*.md            Stories with          Verified, reviewed,
      (approved)            (verifiable           2-5 min tasks         committed code
                             criteria)
```

Each phase produces an artifact consumed by the next. Skip a phase and the next one catches it. The execution loop runs until every story passes both review gates -- or tells you exactly why it can't.

---

## Quick Start

### Install

**Option 1: From marketplace** (recommended)
```bash
# In Claude Code, run these two commands:
/plugin marketplace add andyzengmath/quantum-loop
/plugin install quantum-loop@quantum-loop
```

**Option 2: Local testing** (no marketplace needed)
```bash
git clone https://github.com/andyzengmath/quantum-loop.git
claude --plugin-dir ./quantum-loop
```

After installation, restart Claude Code. All commands are namespaced under `quantum-loop:`.

### Run

```bash
# Step 1: Explore the idea (Socratic Q&A, 2-3 approaches, section-by-section approval)
/quantum-loop:brainstorm Add a task priority system with filtering

# Step 2: Generate formal spec (5-8 lettered questions, respond "1A, 2C, 3B")
/quantum-loop:spec

# Step 3: Create execution plan (dependency DAG, granular tasks, verification commands)
/quantum-loop:plan

# Step 4a: Execute interactively
/quantum-loop:execute

# Step 4b: Or run autonomously (fresh AI context per story)
./quantum-loop.sh --max-iterations 20
```

---

## What Makes It Different

### vs. Plain AI Coding

| | Plain AI | Quantum-Loop |
|--|---------|-------------|
| Requirements | "Build me X" | 9-section PRD with verifiable acceptance criteria |
| Execution | One big prompt | Dependency DAG, one story per context window |
| Verification | "Looks right" | Iron Law: fresh evidence for every claim |
| Review | None | Two-stage: spec compliance, then code quality |
| Failure | Start over | Retry with failure log, skip to independent stories |

### vs. Ralph

Quantum-Loop builds on [Ralph](https://github.com/snarktank/ralph)'s autonomous loop architecture and adds what it's missing:

| | Ralph | Quantum-Loop |
|--|-------|-------------|
| Story status | Boolean (`passes: true`) | 5 states (pending → in_progress → passed/failed/blocked) |
| Dependencies | Linear priority only | DAG-based execution |
| Error recovery | Silent failure | Retry counter + structured failure logs |
| Code review | None | Two-stage mandatory gates |
| Verification | "Typecheck passes" | Iron Law + anti-rationalization guards |
| Design phase | None | Socratic brainstorming |
| Progress | Free-form text | Structured JSON |

### vs. Superpowers

Quantum-Loop takes [Superpowers](https://github.com/obra/superpowers)' discipline and makes it autonomous:

| | Superpowers | Quantum-Loop |
|--|------------|-------------|
| State format | None (session-only) | Machine-readable quantum.json |
| Execution | Manual or batched | Autonomous bash loop |
| Persistence | None | Cross-session via quantum.json |
| Requirements | Informal design docs | Formal PRD with numbered FRs |
| Dependencies | None | Explicit DAG |
| Task tracking | In-session only | Survives restarts |

---

## The Six Skills

| Command | What it does | Output |
|---------|-------------|--------|
| `/quantum-loop:brainstorm` | Socratic exploration: one question at a time, 2-3 approaches with trade-offs, section-by-section design approval | `docs/plans/YYYY-MM-DD-<topic>-design.md` |
| `/quantum-loop:spec` | 5-8 lettered-option questions, generates 9-section PRD with user stories and verifiable acceptance criteria | `tasks/prd-<feature>.md` |
| `/quantum-loop:plan` | Analyzes dependencies, builds DAG, decomposes stories into 2-5 minute tasks with exact file paths and commands | `quantum.json` |
| `/quantum-loop:execute` | Runs the autonomous loop: pick story from DAG → TDD → quality checks → spec review → code review → commit | Updated `quantum.json` |
| `/quantum-loop:verify` | Standalone Iron Law gate: identify command → run fresh → read output → verify claim → only then assert | Verification report |
| `/quantum-loop:review` | Two-stage review: Stage 1 (spec compliance) must pass before Stage 2 (code quality) begins | Review report |

---

## Key Concepts

### Dependency DAG

Stories execute based on a dependency graph. A database schema story runs before the API story that reads from it, which runs before the UI story that displays it. Independent stories don't block each other.

```
US-001 (schema) ──→ US-002 (UI) ──→ US-004 (integration)
                ──→ US-003 (API) ──↗
```

If US-002 fails, US-003 still executes (it only depends on US-001).

### 5-State Story Tracking

```
pending ──→ in_progress ──→ passed
                │
                ▼
             failed ──→ (retry) ──→ in_progress
                │
                ▼ (retries exhausted)
             blocked
```

### Two-Stage Review Gate

```
Implementation complete
        │
        ▼
  Stage 1: Spec Compliance ──── FAIL → fix → re-review
        │
      PASS
        │
        ▼
  Stage 2: Code Quality ─────── FAIL → fix → re-review
        │
      PASS
        │
        ▼
     Commit
```

Stage 2 never runs if Stage 1 fails. Code that doesn't match the spec is waste -- no matter how well-written.

### The Iron Law

```
NO COMPLETION CLAIMS WITHOUT FRESH VERIFICATION EVIDENCE.
```

The verification skill catches hedging language ("should work", "probably passes"), stale evidence ("passed earlier"), and partial checks ("linter passed so it's fine"). Every claim needs a fresh command run with full output.

### Anti-Rationalization Engineering

Every skill includes a table of excuses AI agents use to skip steps, paired with rebuttals:

| The agent says... | The truth is... |
|------------------|-----------------|
| "This is too simple to need brainstorming" | Simple projects have the most unexamined assumptions |
| "Skip TDD, it's obvious" | Obvious code has the most unexamined edge cases |
| "Tests passed, so the feature works" | Tests might not cover the acceptance criteria |
| "I'll fix it later" | "Later" means "never" in autonomous execution |

---

## quantum.json

The machine-readable state file that survives across sessions:

```json
{
  "project": "MyApp",
  "branchName": "ql/task-priority",
  "stories": [
    {
      "id": "US-001",
      "title": "Add priority field to database",
      "status": "passed",
      "dependsOn": [],
      "tasks": [
        { "id": "T-001", "title": "Write migration test", "testFirst": true, "status": "passed" },
        { "id": "T-002", "title": "Create migration", "testFirst": false, "status": "passed" }
      ],
      "review": {
        "specCompliance": { "status": "passed" },
        "codeQuality": { "status": "passed" }
      },
      "retries": { "attempts": 0, "maxAttempts": 3 }
    }
  ],
  "progress": [...],
  "codebasePatterns": ["Use IF NOT EXISTS for migrations"]
}
```

See [`quantum.json.example`](quantum.json.example) for the full schema with 3 stories and 10 tasks.

---

## Architecture

```
quantum-loop/
├── skills/
│   ├── brainstorm/    # Socratic design exploration
│   ├── spec/          # PRD generation
│   ├── plan/          # quantum.json creation
│   ├── execute/       # Autonomous loop orchestration
│   ├── verify/        # Iron Law verification
│   └── review/        # Two-stage code review
├── agents/
│   ├── implementer    # TDD implementation per story
│   ├── spec-reviewer  # Acceptance criteria check
│   └── quality-reviewer # Code quality check
├── quantum-loop.sh    # Autonomous bash loop
└── CLAUDE.md          # Agent template per iteration
```

**`quantum-loop.sh`** drives autonomous execution:
1. Reads quantum.json state
2. Selects next story from dependency DAG (jq query)
3. Spawns fresh Claude Code instance with CLAUDE.md
4. Processes completion signals (`<quantum>STORY_PASSED</quantum>`, etc.)
5. Handles retries and cascade blocking
6. Exits: `0` (all passed), `1` (blocked), `2` (max iterations)

---

## Acknowledgments

Quantum-Loop stands on the shoulders of two pioneering Claude Code plugins:

- **[Ralph](https://github.com/snarktank/ralph)** by snarktank -- The autonomous agent loop architecture, PRD-to-JSON pipeline, fresh-context-per-iteration design, and story-sizing discipline that makes autonomous execution possible.
- **[Superpowers](https://github.com/obra/superpowers)** by Jesse Vincent -- The Iron Law of verification, anti-rationalization engineering, two-stage review, Socratic brainstorming, and the radical idea that AI agents need guardrails against their own tendencies.

---

## Contributing

Issues and PRs welcome. If you find a new way AI agents rationalize skipping steps, add it to the anti-rationalization tables.

## License

[MIT](LICENSE)
