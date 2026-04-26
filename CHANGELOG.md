# Changelog

All notable changes to this project will be documented in this file.

Format: [Semantic Versioning](https://semver.org/). Bump per PR:
- **Patch** (0.0.x): bug fixes, doc updates
- **Minor** (0.x.0): new features, backward-compatible
- **Major** (x.0.0): breaking changes

## [0.6.2] - 2026-04-26

### Fixed

Two follow-up items from the v0.6.x cycle's `/soliton:pr-review` post-merge findings (IDEA_REPORT_v3 §G10 + score-100 .cursor-plugin gap):

- **G10 — `lib/json-atomic.sh` PRD-sha migration shim** (`compute_prd_sha_legacy` + `verify_prd_sha`). Before v0.6.1, `compute_prd_sha` did not normalize CRLF; Windows users with `autocrlf=true` who ran `/ql-plan` under v0.6.0 stored CRLF-era hashes. After upgrading to v0.6.1, the same PRD now hashes differently — every story's `prdSha` would be marked `stale` and force a full `/ql-plan` re-run. v0.6.2 adds a transparent migration: `verify_prd_sha` tries the new (LF-normalized) hash first; on mismatch, falls back to the legacy (v0.6.0) hash; if THAT matches, the orchestrator's Step 1.1 updates the stored value in-place with a single one-line "MIGRATE" log message and no re-plan. Real drift still marks the story stale as before. 3 new tests added (match / migrate / drift paths) + 1 orchestrator-wiring test.
- **`.cursor-plugin/plugin.json` version catch-up bump 0.5.1 → 0.6.2** — the v0.6.0 + v0.6.1 cycle bumped `.claude-plugin/plugin.json` and `.claude-plugin/marketplace.json` but the Cursor manifest was missed. PR #58 established the convention of moving all three plugin manifests in lockstep on every release; `/soliton:pr-review` flagged this at score 100 on PR #61 but the fix landed here. Cursor marketplace consumers will now see v0.6.2 in sync with the Claude side.

### Backward compatibility

The migration path is transparent: existing v0.6.0/v0.6.1 `quantum.json` files load and run without operator action. The first orchestrator pass after upgrade silently rewrites legacy `prdSha` values to the new format. Stories without a `prdSha` field continue to behave exactly as before (back-compat warning logged once).

## [0.6.1] - 2026-04-26

### Fixed

Three correctness bugs surfaced by `soliton:pr-review` on the v0.6.0 bundle (1 at-threshold + 2 below-threshold; all confirmed as real cross-environment hazards rather than nits):

- **`lib/runner.sh:write_routing_snapshot` orphan `.tmp` cleanup** — the inline `jq ... > "$qj.tmp" && mv ...` pattern left a 0-byte `$qj.tmp` on jq failure, inconsistent with `lib/json-atomic.sh:write_quantum_json`'s canonical `rm -f "$tmp_path"` failure-branch cleanup. Now the function captures the jq exit code and removes the tmp file before propagating, mirroring the canonical pattern.
- **`lib/json-atomic.sh:compute_prd_sha` CRLF cross-platform sha mismatch** — the `rstrip(b' \t\n\r')` only stripped trailing whitespace; on Windows with `autocrlf=true`, internal `\r\n` bytes throughout a CRLF-checked-out PRD were retained, producing a different sha256 than the same file on Linux/LF. Every story's `prdSha` would false-positive as `status: "stale"` in cross-platform setups. Now normalizes `\r\n` → `\n` before hashing.
- **`quantum-loop.sh` `--critic` / `--planner` / `--executor` space-form `$2` guards** — under `set -euo pipefail`, a trailing flag (e.g. `--critic` at end-of-args) crashed with bash's `unbound variable` error; a flag-following pattern (e.g. `--critic --parallel`) consumed the next flag as a value and emitted a generic enum error. Each space-form now guards `[[ $# -lt 2 || "${2:-}" == --* ]]` and emits a user-friendly `Error: --<flag> requires a value (...)` exit-2 message.

No new tests required — these fixes are tightening existing code paths exercised by `tests/test_per_role_routing.sh` (26), `tests/test_prd_hash_pinning.sh` (12), and `tests/test_runner_integration.sh` baseline. Test count and assertion totals unchanged from v0.6.0.

## [0.6.0] - 2026-04-26

### Added

P5.A cleanup bundle (8 items) + P5.B1 per-role provider routing + P5.Z1 dogfood retrospective. Bigger dogfood than v0.5.1's --audit (10 stories, 5 waves, multi-runner dispatch). Closes P2.9 fully via OMC v4.12 mechanism port.

- **`agents/orchestrator.md` Step 3B.3 watchdog wiring** (US-001) — 3 explicit calls (poll, circuit, reset on STORY_PASSED) with reap_agent migration for platform-aware kills via taskkill on Windows.
- **`--critic=auto|codex|gemini|claude|none`** (US-002) — operator-facing critic provider flag with availability detection and fallback (subsumed by --planner/--critic/--executor in US-009).
- **`lib/deslop.sh` regex fallback** (US-003) — when knip/ts-prune/vulture/cargo-udeps/staticcheck are absent, dispatches to `lib/dead-code.sh` with normalized `{file, line, kind, severity}` schema.
- **5 new runner manifests** (US-004) — `runners/{opencode,devin,kiro,goose,cline}.json`, all `experimental: true`. `opencode.json` includes skill_discovery_paths quirk for Superpowers v5 plugin pattern compatibility.
- **`prdSha` field per story** (US-005) — RAGShield Level-1 drift detection (arXiv:2604.00387). `lib/json-atomic.sh:compute_prd_sha` produces a stable sha256; orchestrator Step 1.1 hash-check marks mismatched stories `status: "stale"` for re-plan.
- **Sprint-Contract handoff** (US-006) — per-story `.handoffs/sprint-<storyId>.json` written by `/ql-plan` and consumed by `/ql-execute` + `/ql-review`. Mirrors Anthropic's 2026-03-24 Generator-Evaluator contract pattern. Schema documented in `references/sprint-contract.md`.
- **Inline self-review checklists** (US-007) — `[INLINE-REVIEW] typecheck OK / lint OK / all assigned tests pass / file-org follows project conventions` tokens in implementer prompt before STORY_PASSED. Subagent dispatch reserved for adversarial review (cross-story conflict, intent drift, security). 25min -> 30s on routine path per Superpowers v5.0.6.
- **`complexity` field per story + `runner_select_model`** (US-008) — formula `min(100, task_count*10 + dependsOn_depth*15 + (security_tag ? 30 : 0) + filePaths_count*2)`. Routes <=30 -> haiku, 31-60 -> sonnet, 61+ -> opus. Story-level `model:'<override>'` wins.
- **`--planner / --critic / --executor` per-role routing** (US-009) — ports OMC v4.12 mechanism. `lib/runner.sh:resolve_routing` resolves each role with availability check + fallback to claude. Snapshot persisted to `quantum.json.routing` for replay determinism. Closes P2.9 fully.
- **`idea-stage/PIPELINE_REPORT_v3.md` + `idea-stage/IDEA_REPORT_v3.md`** (US-010) — v0.6.0 dogfood findings: 9/9 user-facing stories first-attempt PASS across 5 waves (5 parallel + 2 parallel + 3 sequential). 5 NEW codebasePatterns logged. P5.B2-B5 + P5.C frontier remain open for v0.7+. Test-suite delta: ~+110 new assertions, zero regressions.

### Test-suite delta

110+ new assertions across 8 new test files. Zero regressions in pre-existing suites:
- `tests/test_watchdog_wiring.sh` (9), `tests/test_cross_provider_critic_flag.sh` (13), `tests/test_deslop_regex_fallback.sh` (7)
- `tests/test_runner_manifests.sh` extended +28 assertions, `tests/test_complexity_routing.sh` (19)
- `tests/test_prd_hash_pinning.sh` (12), `tests/test_sprint_contract.sh` (11)
- `tests/test_per_role_routing.sh` (26), `tests/test_per_role_routing_integration.sh` (6)
- `tests/test_orchestrator_wiring.sh` extended +7 assertions for inline-checklist tokens

### Dogfood milestone (v0.6.0)

The pipeline executed its largest fan-out yet: **5-story parallel wave-0** with worktree isolation, zero file-conflict resolution failures. The DAG validator's Rule 0 fileConflicts severity=none classification held perfectly across all 10 conflicts. 5 NEW codebasePatterns surfaced (cross-module rename doc-comment scanning, jq validator gaps, PATH manipulation in tests, test-guard carve-outs, set -uo pipefail return-1 termination). All retrospective material captured in `idea-stage/PIPELINE_REPORT_v3.md` + `idea-stage/IDEA_REPORT_v3.md`.

## [0.5.1] - 2026-04-24

### Added

- **`quantum-loop.sh --audit`** (#56) — read-only repo-hygiene check that prints the six IDEA_REPORT §6 measurement metrics with drill-down on failures. Exit 0 all-OK, exit 1 any off-target, exit 2 misuse. Env-tunable thresholds via `QL_AUDIT_BRANCH_MAX` / `QL_AUDIT_ORPHAN_MAX` / `QL_AUDIT_CONFLICT_MAX` / `QL_AUDIT_CPC_MAX`.
- **`docs/plans/2026-04-24-audit-flag-design.md`** + **`tasks/prd-audit-flag.md`** (#57) — pipeline artifacts from dogfooding `/ql-brainstorm` + `/ql-spec` on the audit feature. Preserves the IDEA_REPORT §6 → design → PRD → shipped-feature traceback.

### Dogfood milestone

First real pipeline self-use. The `/ql-brainstorm` → `/ql-spec` → `/ql-plan` → `/ql-execute` cycle drove a complete 4-story feature end-to-end. Findings captured in #56 PR body for follow-up skill refinements (question-count rigidity in ql-spec, placeholder-drift across stories, file-conflict serialization heuristics).

## [0.5.0] - 2026-04-24

### Added — P3 academic-wedge libraries (10 libs)

All ten wedges from `idea-stage/IDEA_REPORT.md` §P3 landed with a consistent contract pattern (no shell flags at source time, CLI block enables strict mode, env-var tunables, readonly arrays guarded against re-source).

- **`lib/constitution.sh`** (P3.11, arXiv:2602.02584) — regex-based invariants on generated code: hardcoded-secret scan, SQL-injection pattern, input-validation presence, immutable-schema rule.
- **`lib/deep-review.sh` `far_filter`** (P3.3/P3.4, arXiv:2505.17928 + arXiv:2604.03196) — KBI→FAR reviewer split with agreement boost, confidence cutoff, known-false-positive regex suppression.
- **`lib/trajectory.sh`** (P3.5, arXiv:2511.00197) — tool-shape thrashing detection: `parse_trajectory` / `classify_trajectory` (productive | searching | thrashing | stuck) / `should_early_kill`.
- **`lib/hyclone.sh`** (P3.7, arXiv:2508.01357) — Stage-1 semantic-clone fingerprint: alpha-normalize + sha256 + `find_clones` grouping.
- **`lib/conflict-grade.sh`** (P3.2, ConGra arXiv:2409.14121) — per-hunk conflict severity grading 1-5 + routing to `auto-git | diff3 | llm-merge | escalate`.
- **`lib/tracecoder.sh`** (P3.8, arXiv:2602.06875) — Observe-Analyze-Repair primitives: `observe` / `extract_error_markers` / `build_analysis_context` / `should_repair`.
- **`lib/reground.sh`** (P3.9, arXiv:2603.00492) — session-level drift mitigation: re-inject PRD + progress + iron-law reminder every N stories.
- **`lib/skeleton.sh`** (P3.1 SSAT, arXiv:2303.06689) — signature-level API surface: `extract_skeleton` / `skeleton_text` / `skeleton_diff` across TS/JS/Python/Go/Rust.
- **`lib/intent-graph.sh`** (P3.6, arXiv:2604.11209) — formal semantic-intent extraction: `(verb, object)` triples from stories + code with bidirectional drift reporting.
- **`lib/dead-code.sh`** (P3.10, arXiv:2604.07291) — regex-based unused-import + unused-private-helper detection across TS/JS/Python/Go/Rust.

### Added — Orchestrator wirings (8 integration points)

Every new lib wired into the orchestrator via grep-assertion-covered integration points. `test_orchestrator_wiring.sh` grew from 40 → 106 assertions, none can silently unwire a lib.

- **Step 1C** (reground) — periodic re-grounding, gate on `REGROUND_INTERVAL` stories.
- **Step 3A.1 sub-5** (skeleton) — pre-task API-surface preview.
- **Step 3A.3** (tracecoder) — Observe-Analyze-Repair wrapper on typecheck/lint/test gates.
- **Step 3A.5C** (dead-code) — post-generation advisory unused-import/private scan.
- **Step 3A.5D** (intent-graph) — post-generation advisory verb-object drift check.
- **Step 3A.5E** (skeleton) — post-task skeleton-diff drift report.
- **Step 3A.6** (trailers) — advisory trailers appended to commit message for durability in `git log`.
- **Step 3B.3** (trajectory) — monitor-loop tick alongside watchdog; kill path via `reap_agent`.
- **Step 3C.NEG0** (hyclone) — wave-boundary cross-story clone detection.
- **`lib/merge-strategy.sh`** (conflict-grade) — grade 5 short-circuits to escalation; grades 1-4 logged alongside category routing.

### Fixed

- **String-unsafe comment stripper** in `lib/hyclone.sh` and `lib/conflict-grade.sh` — awk passes now track string state so `//`, `/*`, `#` inside a string literal are preserved verbatim (e.g., `"http://x"`, `"/regex/"`, `"/* not a comment */"`).
- **Trajectory wiring log-path mismatch** — orchestrator now reads `.ql-wt/$sid/.ql-agent-output.txt` (spawn.sh convention) instead of the non-existent `.ql-wt/$sid/agent.log`.
- **TraceCoder wiring pseudocode** — removed undefined `GATE_CMD[$gate]` / `mark_story_failed` / `apply_focused_fix` identifiers; replaced with prose agent-action comments matching the pattern used elsewhere (watchdog mark-failed, etc.).
- **test_typecheck_gate 12 failures** — added `TYPECHECK_EXTRA_ALLOWED_PREFIXES` env var to extend the security allowlist for test fixtures without weakening the runtime gate.
- **Advisory trailers dead code** — Steps 3A.5B/C/D/E each set a trailer variable but none were appended to the 3A.6 commit. `git log` grep workflow was unusable. Now each trailer is guarded-appended to `COMMIT_MSG` before commit.

### Measurement targets (per IDEA_REPORT §6)

| Target | Goal | Achieved |
|--------|------|----------|
| CPC variant files | 0 | ✓ 0 |
| README conflict markers | 0 | ✓ 0 |
| Orphan `.claude/worktrees/agent-*` | 0 | ✓ 0 |
| Remote branch count | ≤10 | ✓ 1 (master) |
| Local branch count | ≤10 | ✓ 1 (master) |
| Archive tags preserved | — | 49 |
| Master test suites green | 100% | ✓ 54/54 (~1,400 tests) |

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
