# Changelog

All notable changes to this project will be documented in this file.

Format: [Semantic Versioning](https://semver.org/). Bump per PR:
- **Patch** (0.0.x): bug fixes, doc updates
- **Minor** (0.x.0): new features, backward-compatible
- **Major** (x.0.0): breaking changes

## [0.3.2] - 2026-03-10

### Fixed
- **Mandatory worktree isolation** — `isolation: "worktree"` is now documented as MANDATORY for parallel execution, with specific failure modes listed (bash contention, file conflicts, quantum.json races)
- **Correct tool naming** — orchestrator now references "Agent tool" (not "Task tool") with exact parameter names (`subagent_type`, `isolation`, `mode`, `run_in_background`)
- **Atomic quantum.json updates** — new Step 3B.1 batches all `in_progress` status writes into a single atomic update before spawning agents
- **Monitor loop** — changed from polling to waiting for Claude Code completion notifications
- **State management discipline** — only the orchestrator writes quantum.json; Edit tool banned (use Python/jq); multi-story updates batched into one write
- **Implementer parallel mode** — implementer agents in worktrees no longer edit quantum.json (stale copy); report via output message instead
- **Anti-rationalization guards** — 2 new entries blocking "skip worktree" and "worktrees won't work on this OS" excuses

## [0.3.1] - 2026-03-09

### Added
- **Cross-story contracts** — `contracts` field in quantum.json for shared values (secret keys, env vars, types) across parallel stories. ql-plan generates them; implementer reads and enforces them with propose-and-wait on disagreements.
- **Wiring verification** — `wiring_verification` field on tasks with grep-based mechanical check in spec-reviewer. No agent judgment: missing string = fail, present = pass.
- **`consumedBy` field** — declares cross-story consumption so implementers import existing components instead of inlining duplicates.
- **Coverage gate** — configurable `coverageThreshold` in quantum.json; quality-reviewer runs coverage tool and fails stories below threshold (tool detection: c8 → nyc → pytest-cov → go test → JaCoCo).
- **Coding standards enforcement** — quality-reviewer reads CLAUDE.md, `.claude/rules/`, and `codebasePatterns`; violations of documented rules are CRITICAL severity.
- **Stale story detection** — `startedAt` timestamp + `staleThresholdMinutes` (default 20, CLI-overridable). Implemented in orchestrator, quantum-loop.sh, quantum-loop.ps1, and templates/quantum-loop.sh.
- **Final verification sweep** — scripts run full test suite + import smoke test before declaring COMPLETE. Test failure blocks COMPLETE.
- **Execution observations** — auto-generated post-mortem doc after every run with failure summary, patterns, and raw data. Optional GitHub issue filing with user confirmation.
- **CLAUDE.md defensive check** — Step 3 warns and skips stories that are in_progress but not assigned to the current agent.
- **Lifecycle awareness** — ql-brainstorm question #7 (LIFECYCLE) and ql-spec Pre-Save lifecycle checklist (first-run, returning-user, update, error recovery, empty state, uninstall).
- **`testFirst` mandate** — ql-plan defaults `testFirst: true` for all tasks; exempt tasks require `notes` justification.
- Shell tests for stale detection, startedAt, final sweep, and observations (4 new test files, 14 tests)

### Fixed
- **Atomic in_progress + startedAt write** — single jq operation prevents crash window where story is in_progress without startedAt
- **startedAt cleared on all exit paths** — BLOCKED, unrecognized signal, timeout, merge conflict, non-zero exit, and crash recovery
- **Null-guard failureLog** — observations jq uses `(.retries.failureLog // [])[]` to handle null vs empty array

## [0.3.0] - 2026-02-27

### Added
- **Cross-story integration review** — Stage 3 in ql-review traces call chains across story boundaries using LSP (grep fallback). Runs after dependency chains complete and as a final gate before COMPLETE.
- **Final integration gate** — orchestrator runs import smoke test, full test suite, and dead code scan before declaring COMPLETE
- **File-touch conflict detection** — ql-plan Step 5 flags parallel stories modifying the same file, adds reconciliation tasks, stores conflicts in `quantum.json` metadata (`fileConflicts`)
- **Consumer verification pattern** — wiring acceptance criteria belong on the consumer story, not the creator
- **Edge case test requirements** — boundary values, type variations, collision scenarios, scale tests required for all testFirst tasks
- **Edge case reference doc** — `references/edge-cases.md` with Python, JS, Go, Rust testing gotchas. Implementer reads it at the start of every testFirst task.
- **Import chain verification** — ql-verify requires integration evidence for multi-story features
- **Cursor marketplace manifest** — `.cursor-plugin/plugin.json` for cross-platform publishing

### Changed
- Orchestrator Step 4 split into Step 4 (Final Integration Gate) and Step 5 (Completion)
- Implementer always reads `references/edge-cases.md` for testFirst tasks (not on-demand)

## [0.2.0] - 2026-02-25

### Added
- **Orchestrator agent** (`agents/orchestrator.md`) — manages full execution lifecycle inside Claude Code with DAG query, sequential/parallel dispatch, two-stage review, retry logic
- **Native PowerShell script** (`quantum-loop.ps1`) — Windows overnight runs without bash/WSL
- **SkillsMP compatibility** — `name` field in all SKILL.md frontmatter
- **ql-plan runner copy** — copies quantum-loop.sh/ps1 into project after planning

### Fixed
- **Lost work in parallel mode** — agents must commit before signaling; orchestrator adds safety commit before merge
- **Merge failure on dirty tree** — stash working tree before merge, pop after
- **Stale worktree branches** — delete existing branch before `git worktree add -b`

### Changed
- Simplified `skills/ql-execute/SKILL.md` from ~300 lines to ~50 line dispatcher
- `CLAUDE.md` parallel mode: agents explicitly told to commit before signaling
- `lib/spawn.sh` prompt includes commit instruction

## [0.1.0] - 2026-02-19

### Added
- Parallel execution via DAG-driven worktree agents
- 7 shell library modules (`lib/`) for DAG query, worktree lifecycle, agent spawning, monitoring, atomic JSON writes, crash recovery
- 7 test suites with 110 tests
- `--parallel` and `--max-parallel` flags for `quantum-loop.sh`
- `/ql-execute` parallel orchestration via Task subagents
- Crash recovery for orphaned worktrees
- `CLAUDE.md` parallel mode instructions

## [0.0.1] - 2026-02-18

### Added
- Initial release
- 6 skills: brainstorm, spec, plan, execute, verify, review
- 3 agents: implementer, spec-reviewer, quality-reviewer
- `quantum-loop.sh` sequential autonomous loop
- `CLAUDE.md` agent template
- Dependency DAG execution
- Two-stage review gates (spec compliance + code quality)
- Iron Law verification
- Anti-rationalization guards
