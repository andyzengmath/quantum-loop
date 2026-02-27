# Quantum-Loop

**Your AI agent writes code. Quantum-Loop makes sure it writes the *right* code.**

A Claude Code plugin that turns a one-line feature description into verified, reviewed, autonomously-implemented code -- through structured specs, dependency-aware execution, parallel worktree agents, and mandatory verification gates that prevent AI agents from cutting corners.

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
/quantum-loop:ql-brainstorm → /quantum-loop:ql-spec → /quantum-loop:ql-plan → /quantum-loop:ql-execute
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

**Option 1: Plugin marketplace** (requires Claude Code >= 1.0.33)
```bash
# In Claude Code:
/plugin marketplace add andyzengmath/quantum-loop
/plugin install quantum-loop@quantum-loop
```

**Option 2: Local plugin flag** (any version)
```bash
git clone https://github.com/andyzengmath/quantum-loop.git
claude --plugin-dir ./quantum-loop
```

**Option 3: Manual config** (if the above don't work)

Clone the repo, then edit three files in `~/.claude/`:

1. Add quantum-loop to an existing marketplace's `.claude-plugin/marketplace.json`:
   ```json
   {
     "name": "quantum-loop",
     "source": { "source": "url", "url": "https://github.com/andyzengmath/quantum-loop.git" },
     "description": "Spec-driven autonomous development loop",
     "version": "0.2.2",
     "strict": true
   }
   ```
2. Add to `plugins/installed_plugins.json`:
   ```json
   "quantum-loop@<marketplace-name>": [{
     "scope": "user",
     "installPath": "/path/to/quantum-loop",
     "version": "0.2.2",
     "installedAt": "2026-02-18T00:00:00.000Z",
     "lastUpdated": "2026-02-18T00:00:00.000Z"
   }]
   ```
3. Add to `settings.json` under `enabledPlugins`:
   ```json
   "quantum-loop@<marketplace-name>": true
   ```

After any install method, restart Claude Code. Commands use the `quantum-loop:` prefix (e.g., `/quantum-loop:ql-brainstorm`) or the short form (`/ql-brainstorm`).

### Run

```bash
# Step 1: Explore the idea (Socratic Q&A, 2-3 approaches, section-by-section approval)
/quantum-loop:ql-brainstorm Add a task priority system with filtering

# Step 2: Generate formal spec (5-8 lettered questions, respond "1A, 2C, 3B")
/quantum-loop:ql-spec

# Step 3: Create execution plan (dependency DAG, granular tasks, verification commands)
/quantum-loop:ql-plan

# Step 4a: Execute interactively (auto-detects parallelism)
/quantum-loop:ql-execute

# Step 4b: Or run autonomously -- sequential (one story at a time)
./quantum-loop.sh --max-iterations 20

# Step 4c: Or run autonomously -- parallel (independent stories run concurrently)
./quantum-loop.sh --parallel --max-parallel 4 --max-iterations 20

# Step 4d: Windows autonomous (native PowerShell, no bash required)
.\quantum-loop.ps1 -MaxIterations 20 -SkipPermissions
```

---

## What Makes It Different

### vs. Plain AI Coding

| | Plain AI | Quantum-Loop |
|--|---------|-------------|
| Requirements | "Build me X" | 9-section PRD with verifiable acceptance criteria |
| Execution | One big prompt | Dependency DAG, one story per context window |
| Parallelism | None | Independent stories run concurrently in isolated worktrees |
| Verification | "Looks right" | Iron Law: fresh evidence for every claim |
| Review | None | Two-stage: spec compliance, then code quality |
| Failure | Start over | Retry with failure log, skip to independent stories |

### vs. Ralph

Quantum-Loop builds on [Ralph](https://github.com/snarktank/ralph)'s autonomous loop architecture and adds: DAG-based dependencies, parallel worktree execution, 5-state story tracking, two-stage review gates, structured retry/failure logs, and an in-process orchestrator agent.

### vs. Superpowers

Quantum-Loop takes [Superpowers](https://github.com/obra/superpowers)' verification discipline (Iron Law, anti-rationalization guards, two-stage review) and adds: machine-readable state (quantum.json), DAG-driven execution, cross-session persistence, parallel execution, and autonomous overnight runs.

---

## The Six Skills

| Command | What it does | Output |
|---------|-------------|--------|
| `/quantum-loop:ql-brainstorm` | Socratic exploration: one question at a time, 2-3 approaches with trade-offs, section-by-section design approval | `docs/plans/YYYY-MM-DD-<topic>-design.md` |
| `/quantum-loop:ql-spec` | 5-8 lettered-option questions, generates 9-section PRD with user stories and verifiable acceptance criteria | `tasks/prd-<feature>.md` |
| `/quantum-loop:ql-plan` | Analyzes dependencies, builds DAG, decomposes stories into 2-5 minute tasks with exact file paths and commands | `quantum.json` |
| `/quantum-loop:ql-execute` | Runs the autonomous loop: picks stories from DAG, runs independent stories in parallel via worktree agents, TDD → quality checks → spec review → code review → commit | Updated `quantum.json` |
| `/quantum-loop:ql-verify` | Standalone Iron Law gate: identify command → run fresh → read output → verify claim → only then assert | Verification report |
| `/quantum-loop:ql-review` | Two-stage review: Stage 1 (spec compliance) must pass before Stage 2 (code quality) begins | Review report |

---

## Key Concepts

### Dependency DAG

Stories execute based on a dependency graph. A database schema story runs before the API story that reads from it, which runs before the UI story that displays it. Independent stories don't block each other.

```
US-001 (schema) ──→ US-002 (UI) ──→ US-004 (integration)
                ──→ US-003 (API) ──↗
```

If US-002 fails, US-003 still executes (it only depends on US-001).

### Parallel Execution

When multiple stories have all dependencies satisfied, Quantum-Loop runs them concurrently in isolated git worktrees:

```
Wave 1:  US-001 (schema)   ─── worktree ─── [PASSED] ── merge
         US-005 (config)   ─── worktree ─── [PASSED] ── merge

Wave 2:  US-002 (UI)       ─── worktree ─── [PASSED] ── merge    (unblocked by US-001)
         US-003 (API)      ─── worktree ─── [FAILED] ── retry    (unblocked by US-001)

Wave 3:  US-003 (API)      ─── worktree ─── [PASSED] ── merge    (retry succeeded)
         US-004 (tests)    ─── worktree ─── [PASSED] ── merge    (unblocked by US-002 + US-003)
```

**How it works:**
1. The orchestrator queries the DAG for all stories with satisfied dependencies
2. Each story gets an isolated git worktree (`.ql-wt/<story-id>/`)
3. A fresh Claude Code agent is spawned per worktree with the story ID in its prompt
4. Agents implement the story, commit their changes (`git add -A && git commit`), then signal completion
5. The orchestrator verifies changes are committed (safety commit if agent forgot), then merges the worktree branch into the feature branch
6. The DAG is re-queried after every completion to spawn newly unblocked stories
7. On merge conflict or failure, the story is retried in the next wave

**Agents are fully isolated:** each works in its own worktree directory. Only the orchestrator reads/writes `quantum.json`. Agents must commit before signaling — the orchestrator includes a safety commit as a fallback, but uncommitted work in a removed worktree is lost. Agents that timeout (default 15 min) or crash are killed, their stories marked failed, and worktrees cleaned up.

**Two execution modes:**

| Mode | Trigger | Agent type |
|------|---------|------------|
| Interactive | `/ql-execute` (auto-detects 2+ executable stories) | Background Task subagents |
| Autonomous | `./quantum-loop.sh --parallel` | Background `claude --print` processes |

Without `--parallel` or with only one executable story, execution remains sequential -- full backward compatibility.

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
│   ├── ql-brainstorm/    # Socratic design exploration
│   ├── ql-spec/          # PRD generation
│   ├── ql-plan/          # quantum.json creation
│   ├── ql-execute/       # Thin dispatcher -> orchestrator agent
│   ├── ql-verify/        # Iron Law verification
│   └── ql-review/        # Two-stage code review
├── agents/
│   ├── orchestrator      # Execution lifecycle manager (DAG, dispatch, review, commit)
│   ├── implementer       # TDD implementation per story
│   ├── spec-reviewer     # Acceptance criteria check
│   └── quality-reviewer  # Code quality check
├── lib/                  # Shell libraries for parallel orchestration
│   ├── common.sh         # Shared validation utilities
│   ├── dag-query.sh      # DAG query + cycle detection
│   ├── worktree.sh       # Git worktree lifecycle (create/remove/list)
│   ├── spawn.sh          # Agent spawning (autonomous mode)
│   ├── monitor.sh        # Agent polling, signal detection, merge-on-pass
│   ├── json-atomic.sh    # Atomic quantum.json writes (tmp + mv)
│   └── crash-recovery.sh # Orphaned worktree cleanup on startup
├── tests/                # Shell test suites (110 tests)
│   ├── test_dag_query.sh
│   ├── test_worktree.sh
│   ├── test_spawn.sh
│   ├── test_monitor_merge.sh
│   ├── test_timeout.sh
│   ├── test_json_atomic.sh
│   └── test_crash_recovery.sh
├── quantum-loop.sh       # Autonomous bash loop (sequential + parallel)
└── CLAUDE.md             # Agent template (parallel-aware)
```

**`quantum-loop.sh`** drives autonomous execution:

**Sequential mode** (default):
1. Reads quantum.json state
2. Selects next story from dependency DAG (jq query)
3. Spawns fresh Claude Code instance with CLAUDE.md
4. Processes completion signals (`<quantum>STORY_PASSED</quantum>`, etc.)
5. Handles retries and cascade blocking
6. Exits: `0` (all passed), `1` (blocked), `2` (max iterations)

**Parallel mode** (`--parallel`):
1. Recovers orphaned worktrees from any interrupted previous run
2. Queries DAG for all independently executable stories
3. Creates isolated git worktree per story (`.ql-wt/<story-id>/`)
4. Spawns background `claude --print` process per worktree (up to `--max-parallel`)
5. Monitors agents: polls for signals, enforces 15-min timeout, detects crashes
6. On pass: safety-commits any uncommitted changes, merges worktree branch into feature branch, re-queries DAG, spawns newly unblocked stories
7. On failure/timeout/crash: marks story failed, cleans up worktree, retries next wave
8. Exits: `0` (all passed), `1` (blocked), `2` (max iterations)

### CLI Reference

```
./quantum-loop.sh [OPTIONS]

Options:
  --max-iterations N   Maximum iterations before stopping (default: 20)
  --max-retries N      Max retry attempts per story (default: 3)
  --tool TOOL          AI tool: "claude" (default) or "amp"
  --parallel           Enable parallel execution of independent stories
  --max-parallel N     Max concurrent agents in parallel mode (default: 4)
  --help               Show help message
```

### Crash Recovery

If a parallel run is interrupted (Ctrl+C, power loss, etc.), the next run automatically:
- Detects orphaned worktrees listed in `execution.activeWorktrees`
- Removes them with `git worktree remove --force`
- Resets affected story statuses from `in_progress` back to `pending`
- Logs: "Recovered N orphaned worktrees from interrupted parallel execution"

### Windows Users

Three options for Windows, in order of recommendation:

**Option 1: `/ql-execute` (interactive, recommended)**
```bash
# In Claude Code:
/quantum-loop:ql-execute
```
Invokes the orchestrator agent inside Claude Code with full tool access and native worktree isolation for parallel execution. Most reliable option.

**Option 2: `quantum-loop.ps1` (autonomous overnight, native PowerShell)**
```powershell
.\quantum-loop.ps1 -MaxIterations 20 -SkipPermissions
.\quantum-loop.ps1 -MaxIterations 50 -SkipPermissions -Model "claude-sonnet-4-5-20250514"
```
Native PowerShell sequential loop -- no bash, no WSL, no Git Bash. Spawns fresh `claude --print` per story. Requires `jq` installed. Sequential only (no parallel).

**Option 3: WSL2 + `quantum-loop.sh` (autonomous overnight, full feature set)**
```bash
# In WSL2 Ubuntu:
wsl
cd /mnt/c/Users/you/project
./quantum-loop.sh --parallel --max-parallel 4 --max-iterations 20
```
Full feature set including parallel mode. [WSL2 setup guide](https://learn.microsoft.com/en-us/windows/wsl/install). Requires `jq` and `claude` CLI installed inside WSL2.

The bash script's parallel mode (`--parallel`) is **not recommended** with Git Bash on Windows due to OneDrive file locking and background process management issues. Use WSL2 or the PowerShell script instead.

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
