# Changelog

All notable changes to this project will be documented in this file.

Format: [Semantic Versioning](https://semver.org/). Bump per PR:
- **Patch** (0.0.x): bug fixes, doc updates
- **Minor** (0.x.0): new features, backward-compatible
- **Major** (x.0.0): breaking changes

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
