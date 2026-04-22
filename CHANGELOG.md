# Changelog

All notable changes to this project will be documented in this file.

Format: [Semantic Versioning](https://semver.org/). Bump per PR:
- **Patch** (0.0.x): bug fixes, doc updates
- **Minor** (0.x.0): new features, backward-compatible
- **Major** (x.0.0): breaking changes

## [0.4.1] - 2026-04-01

### Added
- **Multi-runner support** — universal runner adapter lets quantum-loop drive Claude, Codex, Copilot, Cursor, Gemini, Aider, Cline, Amp, Devin, Kiro, Goose, and OpenCode through a shared manifest contract. Design doc: `docs/plans/2026-04-01-multi-runner-support-design.md`.
- **Runner JSON schema** (`schemas/runner.schema.json`) + validator (`schemas/validate.sh`) for manifest linting.
- **Runner library** (`lib/runner.sh`) with load / ensure_instructions / command_builder / hook helpers. Manifests under `runners/*.json`.
- **Signal protocol preamble** injected into non-Claude runners so they emit `<quantum>STORY_PASSED/FAILED/COMPLETE/BLOCKED</quantum>` markers in a shared format.
- **Signal heuristic fallback** (`lib/signal-heuristics.sh`) — if no explicit `<quantum>` signal is present, infer from commit evidence, test results, and hedge-phrase filters.
- **Instruction-file auto-copy** — replicates `CLAUDE.md` to each runner's convention (`AGENTS.md`, `GEMINI.md`, etc.).
- **Runner manifests**: `claude.json` (guaranteed), `codex.json` (tested end-to-end), plus experimental manifests for `amp`, `aider`, `copilot`, `cursor`, `gemini`.
- Sequential mode, PowerShell mode, and `templates/quantum-loop.sh` all wired to the runner framework.
- 22-test signal-heuristic suite and an integration test-suite for Codex CLI dispatch.

### Fixed
- Sequential-mode status updates no longer lose state on runner switch.
- Heuristic false-positive filter for ambiguous runner output.
- Runner name + template argument validation hardened against injection.

## [0.3.7] - 2026-03-30

### Added
- **Hardening-v2: init-guard + AST-aware merge + resilience** — design doc `docs/plans/2026-03-28-hardening-v2-design.md`.
- **`lib/init-guard.sh`** — environment pre-flight: OneDrive / long-path detection, tmpdir writability check, orphan worktree prune.
- **`lib/merge-semantic.sh`** — AST-aware 3-way merge (ts-morph for TypeScript, libcst for Python, diff3 fallback) routed via `lib/merge-strategy.sh`.
- **`lib/resilience.sh`** — WIP commits per task, squash-on-merge at story boundary, crash recovery via `lastWipCommit` + `completedTasks` fields. Supersedes `lib/crash-recovery.sh` (to be removed).
- **Stash exclusion for `quantum.json`** during merges to prevent schema corruption.
- Integration tests covering init → merge flow, crash recovery with WIP commits, semantic merge conflict, quantum.json stash isolation.

### Fixed
- Stash-ordering race in `merge-strategy.sh`.
- Trap cleanup on early abort paths in `resilience.sh`.
- stderr redirect typo on ts-morph merge fallback path.

## [0.3.6] - 2026-03-25

### Added
- **Modular Hardening (7 independent modules)** — design doc `docs/plans/2026-03-25-modular-hardening-design.md`.
- **`lib/barrel-regen.sh`** — auto-regenerate barrel exports (`_barrel.ts` / `__init__.py` / etc.) post-merge so new story files become consumer-importable.
- **`lib/dep-manifest.sh`** — detect dependency-manifest changes (npm / pip / go / cargo) and run appropriate install post-merge.
- **`lib/known-failures.sh`** — baseline + delta tracking of test failures per wave. Alerts on **new** regressions, not pre-existing red.
- **Worktree lifecycle** — `worktree.sh` extended with lifecycle-tracking functions; `execution.worktreeTracking` fields `{activeWorktrees, cleanedThisSession, maxWorktrees}`.
- **Category-based merge strategy** (`lib/merge-strategy.sh`) — routes conflicts by file kind: `dependency_manifest → ours+install`, `barrel_export → regenerate`, `new_story_file → theirs`, `shared_infrastructure → ours`, `contract_stub → theirs`, default escalate.
- **Interface cascade guard** extending the L5 type audit.
- **`contractBreaking` flag + `fixes` field** in ql-plan for intentional breaking changes.
- Unit tests for barrel-regen, dep-manifest, known-failures, worktree lifecycle, merge-strategy, plus integration tests for known-failures lifecycle and escalation retry.

## [0.3.5] - 2026-03-24

### Added
- **DAG Intelligence — parallel specialist validators** — design doc `docs/plans/2026-03-24-dag-intelligence-design.md`.
- **`dag-validator` coordinator agent** that spawns three specialists in parallel:
  - **`bottleneck-analyzer`** — Kahn's-algorithm wave assignment; detects sequential bottlenecks.
  - **`duplication-detector`** — Jaccard keyword pre-filter + LLM semantic check for overlapping stories.
  - **`conflict-auditor`** — computes complete `fileConflicts` from `filePaths` intersections with severity classification.
- **`storyType` field** on stories (feature / refactor / fix / test / docs / skeleton / integration).
- **`dagValidation` block** + `severity` field in `quantum.json` schema.
- `dag-validation.md` reference doc.
- `ql-plan` integrates `dag-validator` invocation before plan confirmation; shows DAG Health Report.

### Fixed
- PR-review findings from soliton review (prompt hardening, context-window optimization).

## [0.3.4] - 2026-03-18

### Added
- **Progressive Materialization (5-layer type-divergence defense)** — design doc `docs/plans/2026-03-18-worktree-isolation-fix-design.md`.
- **`lib/materialize.sh`** — detects language; materializes real interface files for contracts consumed by ≥2 stories (threshold configurable). Smart-materialization threshold logic added in this release.
- **`lib/type-audit.sh`** — grep-based duplicate-definition detection at wave boundary; spawns `type-auditor` agent on hits and feeds findings back into contracts.
- **Post-merge typecheck gate** — auto-detects project typechecker (tsc, pyright, mypy, etc.) and reverts on failure.
- **Auto-promotion of discovered contracts** — orchestrator promotes wave-end audited types into `materializedContracts`.
- **`typecheckCommand` field** in `quantum.json` schema; new execution-metadata fields for materialization and audit tracking.
- **Shared-types directory inference** + `contract-shapes` reference doc for `ql-plan`.
- **Contract Effectiveness section** in orchestrator post-mortem output.
- Extended `merge_worktree_branch()` with conflict classification.
- Unit tests for `materialize.sh`, `type-audit.sh`, merge escalation, typecheck gate.

### Fixed
- Command-injection hardening in merged scripts.
- Path-traversal checks in materialization paths.
- Merge revert safety when a post-merge gate fails.
- L5 audit feedback loop, error counting, Python pattern recognition.

## [0.3.3] - 2026-03-11

### Fixed
- **File-conflict-aware DAG scheduling** — new `filter_file_conflicts()` in `dag-query.sh` prevents spawning parallel agents that share file paths. Uses greedy priority-ordered selection with exact-match comparison. Wired into both dispatch sites in `quantum-loop.sh` (initial wave + mid-wave top-up). Also detects cross-wave conflicts by seeding with in_progress stories' files.
- **Worktree nesting prevention** — new `_resolve_repo_root()` helper in `worktree.sh` resolves nested worktree paths to the top-level repo root via `git rev-parse --git-common-dir`. Used by all three public functions (create, remove, list). Falls back gracefully on Git < 2.31 and warns when resolution fails inside `.ql-wt/` paths.
- **Windows long-path fallback** — `create_worktree` detects paths > 200 chars and falls back to a repo-namespaced temp directory (`/tmp/ql-wt-<hash>/`). Re-checks fallback length with emergency `/tmp` last resort. `remove_worktree` and `list_worktrees` check both locations.
- **Editable install race condition** — PYTHONPATH injection guidance added to `implementer.md`, `orchestrator.md`, and `spawn.sh` (both src-layout and flat-layout variants). Agents no longer run `pip install -e .` in parallel worktrees.
- **Worktree cleanup on Windows** — retry loop (3 attempts, 2s delay) for file locks from OneDrive sync / `__pycache__`. `rm -rf` fallback only runs when `git worktree remove` actually fails. `git worktree prune` runs after cleanup.
- **Unescaped shell expansions** — `orchestrator.md` prompt template now uses `\$(pwd)` and `\$PYTHONPATH` (matching `spawn.sh` pattern) to prevent premature expansion.
- **echo → printf** — `detect_cycles` in `dag-query.sh` now uses `printf` matching project convention.

### Added
- **Inline review gate for parallel mode** (Step 3B.4) — orchestrator runs spec compliance + code quality checks after each worktree merge, matching sequential mode's quality bar. Defers to wave-end when accumulated diff exceeds 2000 lines.
- **Full-feature code review** (Step 4B) — holistic review of entire branch diff after all stories pass. Checks cross-story consistency (naming, duplicates, type mismatches), architecture coherence (PRD goals, data flow, backward compatibility), and security (secrets, TODOs, error handling).
- **quantum.json merge guidance** — documented stash/merge/restore pattern and recommended `.gitignore` best practice.
- **Input validation** — `filter_file_conflicts()` validates file path and eligible array before processing.
- **Cross-repo collision prevention** — `_short_path_base()` uses repo-root hash to namespace `/tmp` worktrees per repository.
- 14 new tests: `filter_file_conflicts` (8 tests covering filePaths overlap, fileConflicts entries, empty/null, three-way conflict, transitive chains, similar paths), `_resolve_repo_root` (3 tests: identity, from-worktree, nested-create), `_short_path_base` (2 tests: determinism, cross-repo uniqueness), PYTHONPATH in spawn prompt (4 assertions). **79 total tests, all passing.**

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
