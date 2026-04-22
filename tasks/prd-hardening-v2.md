# PRD: Hardening Layer v2 — Comprehensive Post-Mortem Fixes

## 1. Introduction/Overview

The quantum-loop orchestrator's parallel execution mode completed a 19-story cross-repo research feature, but the 2026-03-28 post-mortem revealed 7 systemic issues: Windows/OneDrive long-path failures (~3 hours wasted), quantum.json state corruption during git stash/pop, duplicate type definitions across parallel stories, lossy `ours`/`theirs` merge resolution, lost agent progress on session restart, git index.lock contention from `git add -A`, and worktree accumulation from previous sessions. This feature adds 3 new modules (`init-guard.sh`, `merge-semantic.sh`, `resilience.sh`), modifies 4 existing modules, and updates agent prompts to address all 7 issues comprehensively.

## 2. Goals

- Detect and warn about OneDrive/long-path environments at orchestrator init, automatically routing worktrees to short paths
- Eliminate quantum.json corruption by excluding it from git stash operations during merges
- Reduce code loss during merge conflict resolution by introducing AST-aware 3-way merge for TypeScript and Python files, with `diff3` and rule-based fallbacks
- Preserve agent progress across session restarts via per-task WIP commits with squash-on-merge
- Eliminate git index.lock contention by scoping `git add` to specific files on the main branch
- Clean up orphaned `.ql-wt/` directories and stale git worktree references at session init
- Materialize contract types that appear in fileConflicts (even single-consumer) to prevent parallel type duplication
- Consolidate crash-recovery.sh into a unified resilience.sh module
- Maintain full backward compatibility — quantum.json files without new fields work as today
- All new modules have unit tests; integration tests validate cross-module flows; live validation confirms end-to-end behavior

## 3. User Stories

### US-001: Create init-guard.sh — environment detection and warnings

**Description:** As the orchestrator, I want a pre-flight environment check at init time so that long-path issues are detected early and worktrees are automatically routed to safe short paths.

**Acceptance Criteria:**
- [ ] File exists at `lib/init-guard.sh`
- [ ] Sources `lib/common.sh` following the existing pattern in other lib scripts
- [ ] Exports function `detect_environment(repo_root)` that returns a pipe-delimited string of warning codes (e.g., `onedrive_long_path|tmpdir_not_writable`) or empty string if no warnings
- [ ] `detect_environment` checks: (a) repo path length > 150 chars, (b) repo path contains "OneDrive" (case-insensitive), (c) `$TMPDIR` or `/tmp` is writable (test with `mktemp`), (d) OS is Windows (via `uname` or `MSYSTEM` env var)
- [ ] Exports function `warn_long_path(repo_root)` that logs `[INIT-GUARD] WARN: Repo path contains 'OneDrive' (<N> chars). Worktrees will use short paths under /tmp/ql-wt-*.` when OneDrive is detected, or a generic long-path warning otherwise
- [ ] Exports function `prune_stale_refs(repo_root)` that runs `git worktree prune` with retry once after 2s on failure. Returns count of pruned refs on stdout. Logs `[INIT-GUARD] Pruned <N> stale worktree references`
- [ ] Exports function `cleanup_orphan_dirs(repo_root)` that scans `<repo_root>/.ql-wt/` for directories not registered in `git worktree list`. For each orphan: checks `git status` for uncommitted changes; if clean, removes with `rm -rf`; if dirty, logs `[INIT-GUARD] WARN: .ql-wt/<dir> has uncommitted work — preserving for manual inspection` and skips
- [ ] Exports function `run_preflight(repo_root, json_path)` that orchestrates all checks, writes results to `execution.initGuard` in quantum.json (`ranAt`, `warnings` array, `shortPathBase`, `prunedWorktrees`, `cleanedOrphans`), and logs summary `[INIT-GUARD] Pre-flight complete. <N> blockers, <M> warnings.`
- [ ] If `$TMPDIR`/`/tmp` is not writable, `run_preflight` sets `execution.initGuard.forceSequential = true` and logs `[INIT-GUARD] CRITICAL: temp directory not writable — forcing sequential execution`
- [ ] `run_preflight` is idempotent — if `execution.initGuard.ranAt` already exists for this session (within 1 hour), skips and returns 0
- [ ] Typecheck/lint passes (shellcheck on init-guard.sh)

---

### US-002: Create resilience.sh — WIP commits, squash-on-merge, and crash recovery

**Description:** As the orchestrator, I want agents to make WIP commits after each task so that session restarts don't lose progress, and I want squash-on-merge to keep the feature branch history clean.

**Acceptance Criteria:**
- [ ] File exists at `lib/resilience.sh`
- [ ] Sources `lib/common.sh` and `lib/json-atomic.sh`
- [ ] Absorbs all functionality from `lib/crash-recovery.sh` — the function `recover_orphaned_worktrees(json_path, repo_root)` is present and works identically to the current implementation
- [ ] `lib/crash-recovery.sh` is removed. A comment at the top of `resilience.sh` notes: `# Supersedes lib/crash-recovery.sh (merged in hardening-v2)`
- [ ] Exports function `wip_commit(worktree_path, story_id, task_id, task_title)` that runs `git add -A && git commit -m "wip: <story_id> <task_id> - <task_title>"` in the worktree. Returns 0 on success, 1 if nothing to commit (empty diff). Logs `[RESILIENCE] WIP commit: wip: <story_id> <task_id> - <task_title>`
- [ ] `wip_commit` is called only when: (a) the task modified or created files (`git status --porcelain` is non-empty), OR (b) the task took longer than 120 seconds (tracked via start/end timestamps passed as optional 5th/6th args)
- [ ] Exports function `get_completed_tasks(worktree_path, story_id)` that reads git log for `wip:` commits matching the story_id and returns a newline-separated list of task IDs. Returns empty string if no WIP commits found
- [ ] Exports function `squash_and_merge(worktree_branch, repo_root, story_id, story_title, json_path)` that:
  - Counts commits on `worktree_branch` not on the current branch
  - If 0 or 1 commits: delegates to existing `classify_and_merge()` from merge-strategy.sh (regular `--no-ff` merge)
  - If 2+ commits: runs `git merge --squash <worktree_branch>` then `git commit -m "feat: <story_id> - <story_title>"`
  - On merge conflict during squash: delegates to `classify_and_merge()` for conflict resolution
  - Returns 0 on success, 1 on failure
  - Logs `[RESILIENCE] Squash-merged <N> commits from <worktree_branch>` or `[RESILIENCE] Single-commit merge for <worktree_branch> — using --no-ff`
- [ ] Exports function `detect_resumable_work(json_path, repo_root, story_id)` that checks if a stale story's worktree has WIP commits. Returns `resumable:<last_wip_sha>:<completed_task_ids>` if WIP commits exist, or `fresh` if no WIP commits. Logs `[RESILIENCE] Story <story_id> has <N> WIP commits — resumable from <task_id>`
- [ ] All functions handle missing/empty arguments with error messages to stderr and return 1
- [ ] Typecheck/lint passes (shellcheck on resilience.sh)

---

### US-003: Create merge-semantic.sh — AST-aware 3-way merge

**Description:** As the merge strategy module, I want an AST-aware 3-way merge capability so that parallel stories adding different symbols to the same file don't lose code via `ours`/`theirs` resolution.

**Acceptance Criteria:**
- [ ] File exists at `lib/merge-semantic.sh`
- [ ] Sources `lib/common.sh`
- [ ] At module load time, detects available tooling and sets flags: `TSMORPH_AVAILABLE` (true if `npx ts-morph` or global `ts-morph` is accessible), `LIBCST_AVAILABLE` (true if `python -c "import libcst"` succeeds), `DIFF3_AVAILABLE` (true if `command -v diff3` succeeds)
- [ ] Logs available tooling at load: `[MERGE-SEMANTIC] Available: ts-morph=<yes/no>, libcst=<yes/no>, diff3=<yes/no>`
- [ ] Exports function `can_semantic_merge(file_path)` that returns 0 if the file can be semantically merged (TypeScript with ts-morph available, Python with libcst available, or any text file with diff3 available), 1 otherwise
- [ ] Exports function `semantic_merge(base_file, ours_file, theirs_file, output_file)` that:
  - For TypeScript (`.ts`, `.tsx`): uses a Python script with `ts-morph` (via `npx ts-morph-merge` or inline Node.js script) to parse base/ours/theirs ASTs, identify top-level declarations (functions, classes, interfaces, type aliases, const/let/var declarations, export statements) added or modified in each side, merge non-overlapping additions, and flag true conflicts (same declaration name modified differently on both sides)
  - For Python (`.py`): uses `libcst` to parse and diff at the top-level statement/class/function level with the same logic
  - Fallback for other text files: uses `diff3 -m <ours_file> <base_file> <theirs_file> > <output_file>` and checks exit code (0 = clean merge, 1 = conflicts remain)
  - Returns 0 if merge succeeded (output_file has no conflict markers), 1 if true conflicts remain
  - Logs: `[MERGE-SEMANTIC] Merged <file>: kept <N> declarations from ours + <M> from theirs (<K> true conflicts)` or `[MERGE-SEMANTIC] diff3 merge of <file>: <clean/conflicts>`
- [ ] Semantic merge operates at the **top-level declaration level only** — does not attempt to merge changes within a function body or class method. If both sides modify the same top-level declaration, it's a true conflict (return 1)
- [ ] If AST parse fails on any of the 3 inputs (base/ours/theirs), returns 1 with log: `[MERGE-SEMANTIC] Parse failed for <file> — falling back to rule-based resolution`
- [ ] Exports function `get_semantic_merge_status()` that returns a comma-separated string of available backends (e.g., `ts-morph,diff3` or `none`)
- [ ] All functions are idempotent and do not modify base/ours/theirs input files
- [ ] Typecheck/lint passes (shellcheck on merge-semantic.sh)

---

### US-004: Modify merge-strategy.sh — quantum.json stash exclusion and semantic merge delegation

**Description:** As the merge strategy module, I want to exclude quantum.json from git stash operations and delegate to semantic merge before falling back to `ours`/`theirs`.

**Acceptance Criteria:**
- [ ] `classify_and_merge()` in `lib/merge-strategy.sh` backs up quantum.json with `cp quantum.json quantum.json.merge-bak` before any stash operation
- [ ] `classify_and_merge()` uses `git stash push -m "ql-auto-stash-..." -- ':!quantum.json'` (pathspec exclusion) instead of bare `git stash push` to exclude quantum.json from the stash
- [ ] After merge completes (success or abort), quantum.json is restored from the backup: `cp quantum.json.merge-bak quantum.json && rm quantum.json.merge-bak`
- [ ] If quantum.json.merge-bak does not exist (no backup was made, e.g., working dir was clean), restoration is skipped gracefully
- [ ] When a conflict is classified as `ours` or `theirs`, and `merge-semantic.sh` is available (`MERGE_SEMANTIC_AVAILABLE` flag), `resolve_conflict()` first attempts `can_semantic_merge(file_path)` and if true, calls `semantic_merge(base, ours, theirs, output)`. If semantic merge returns 0, stages the output file. If it returns 1, falls back to the original `ours`/`theirs` action
- [ ] For semantic merge, base/ours/theirs versions are extracted using `git show :1:<file>`, `git show :2:<file>`, `git show :3:<file>` (merge stage numbers) into temp files
- [ ] Sources `lib/merge-semantic.sh` at module load with graceful fallback: `MERGE_SEMANTIC_AVAILABLE=true; source "$LIB_DIR/merge-semantic.sh" 2>/dev/null || MERGE_SEMANTIC_AVAILABLE=false`
- [ ] Existing test suite `tests/test_merge_strategy.sh` still passes without modification
- [ ] Typecheck/lint passes (shellcheck on merge-strategy.sh)

---

### US-005: Modify monitor.sh — squash-on-merge integration

**Description:** As the agent monitor, I want to use squash-on-merge for worktree branches with multiple commits so that WIP commits don't appear on the feature branch.

**Acceptance Criteria:**
- [ ] `merge_worktree_branch()` in `lib/monitor.sh` sources `lib/resilience.sh` at module load with graceful fallback: `RESILIENCE_AVAILABLE=true; source "$LIB_DIR/resilience.sh" 2>/dev/null || RESILIENCE_AVAILABLE=false`
- [ ] When `RESILIENCE_AVAILABLE` is true and `quantum.json` exists, `merge_worktree_branch()` delegates to `squash_and_merge()` instead of directly calling `classify_and_merge()` or bare `git merge`
- [ ] When `RESILIENCE_AVAILABLE` is false, behavior is identical to current implementation (no regression)
- [ ] `squash_and_merge()` receives the story_id and story_title extracted from quantum.json via Python one-liner (following existing patterns in monitor.sh)
- [ ] The fallback bare git merge path (when merge-strategy.sh is unavailable) is unchanged
- [ ] Existing test suite `tests/test_monitor_merge.sh` and `tests/test_monitor_merge_delegation.sh` still pass
- [ ] Typecheck/lint passes (shellcheck on monitor.sh)

---

### US-006: Modify materialize.sh — smart materialization threshold

**Description:** As the orchestrator, I want contract types that appear in fileConflicts to be materialized even if they have only one consumer, so that parallel stories don't create competing type definitions.

**Acceptance Criteria:**
- [ ] `generate_definition_file()` (or the calling logic in the orchestrator) materializes a contract type when EITHER: (a) `consumers.length >= 2` (existing behavior), OR (b) the type's `definitionFile` path appears in ANY `fileConflicts` entry in quantum.json
- [ ] The fileConflicts check reads `fileConflicts` from quantum.json. For each entry, it checks if any story's `filePaths` overlap with the contract's `definitionFile`. If so, the type is materialized regardless of consumer count
- [ ] Types with `consumers.length >= 1` that do NOT appear in fileConflicts are still skipped (preserving existing behavior for most types)
- [ ] Log distinguishes the reason: `[MATERIALIZE] <TypeName> → <definitionFile> (multi-consumer)` vs `[MATERIALIZE] <TypeName> → <definitionFile> (file-conflict prevention)`
- [ ] Existing test suite `tests/test_materialize.sh` still passes
- [ ] Typecheck/lint passes (shellcheck on materialize.sh)

---

### US-007: Scope git add in orchestrator commits

**Description:** As the orchestrator running on the main feature branch, I want to use `git add <specific files>` instead of `git add -A` so that untracked worktree directories don't cause index.lock contention.

**Acceptance Criteria:**
- [ ] In `agents/orchestrator.md`, all instances of `git add -A` for main-branch operations (contract materialization commits, wiring fix commits, type audit commits) are replaced with `git add <specific files>` where the file list is derived from the operation that just ran
- [ ] In `lib/spawn.sh`, the `build_agent_prompt()` function's step 6 is unchanged — agents in worktrees continue to use `git add -A` since worktrees are isolated and the scope is safe
- [ ] In `agents/implementer.md`, the commit instructions continue to use `git add -A` for worktree-mode commits (already isolated)
- [ ] In `CLAUDE.md`, the parallel mode commit instruction continues to use `git add -A` for worktree commits
- [ ] In `agents/orchestrator.md`, the contract materialization commit (Step 3B.1B) uses `git add <materialized_files>` (already correct per current code — verify and preserve)
- [ ] In `agents/orchestrator.md`, the wiring fix commit (Step 3C) uses `git add <wired_files>` instead of `git add -A`
- [ ] In `agents/type-auditor.md`, the commit after type consolidation uses `git add <consolidated_files>` instead of `git add -A`
- [ ] Typecheck/lint passes (shellcheck on any modified .sh files)

---

### US-008: Update orchestrator.md — init-guard and resilience integration

**Description:** As the orchestrator agent, I want instructions for running init-guard at startup, using squash-on-merge for WIP branches, and handling quantum.json stash exclusion.

**Acceptance Criteria:**
- [ ] Step 1 (Initialize) includes sourcing `lib/init-guard.sh` with graceful fallback, following the existing pattern for other modules at line 186-189
- [ ] Step 1 includes calling `run_preflight(repo_root, json_path)` after branch verification but before DAG query
- [ ] Step 1 includes: if `execution.initGuard.forceSequential` is true, skip parallel mode and force Step 3A for all stories
- [ ] Step 1B (Detect Stale Stories) includes calling `detect_resumable_work()` from resilience.sh for each stale story. If resumable, the re-spawn prompt includes `completedTasks` so the agent skips already-done tasks
- [ ] Step 3B (Parallel Execution) merge section references `squash_and_merge()` as the primary merge path when resilience.sh is available
- [ ] Step 3B.3 (merge section) documents quantum.json stash exclusion: "quantum.json is excluded from git stash via pathspec. If merge-strategy.sh handles this automatically, no manual stash is needed."
- [ ] `execution.initGuard` is documented in the quantum.json field reference section (if one exists) or in Step 1 inline
- [ ] `execution.resilience` fields (`wipCommitsEnabled`, `squashOnMerge`) are documented with defaults
- [ ] All changes are additive — no existing orchestrator behavior is removed or altered

---

### US-009: Update implementer.md and spawn.sh — WIP commit instructions

**Description:** As an implementer agent, I want instructions to make WIP commits after each completed task so that my progress survives session restarts.

**Acceptance Criteria:**
- [ ] `agents/implementer.md` adds a "WIP Commits (Worktree Mode)" section after the existing "Environment Setup (Worktree Mode)" section
- [ ] The WIP Commits section instructs: "After each task that creates or modifies files, OR any task that took longer than 2 minutes, commit your work: `git add -A && git commit -m 'wip: <STORY_ID> <TASK_ID> - <task title>'`. This preserves progress if the session is interrupted. The orchestrator will squash these into a single commit on merge."
- [ ] The WIP Commits section includes: "If you are re-spawned and your prompt includes `completedTasks: [T-001, T-002]`, skip those tasks — they are already committed from a previous attempt. Start from the first task NOT in the list."
- [ ] `lib/spawn.sh` `build_agent_prompt()` adds an optional `completed_tasks` parameter. When non-empty, the prompt includes: `Previously completed tasks (already committed, DO NOT re-implement): <task_list>. Start from the next task.`
- [ ] The existing final commit instruction (`git add -A && git commit -m "feat: ..."`) remains unchanged — this is the final "story complete" commit after all tasks pass
- [ ] `agents/implementer.md` clarifies that WIP commits do NOT require passing tests — only the final commit requires quality gates
- [ ] Typecheck/lint passes (shellcheck on spawn.sh)

---

### US-010: Unit tests for init-guard.sh

**Description:** As a developer, I want comprehensive unit tests for the init-guard module so that environment detection and cleanup logic is verified.

**Acceptance Criteria:**
- [ ] File exists at `tests/test_init_guard.sh`
- [ ] Follows the existing test pattern: PASS/FAIL counters, `assert_eq`/`assert_contains` helpers, temp directory setup/teardown, sources `lib/init-guard.sh`
- [ ] Tests `detect_environment()`: (a) returns `onedrive_long_path` for a path containing "OneDrive" and > 150 chars, (b) returns empty for a short path like `/tmp/test-repo`, (c) returns `long_path` for a 160-char path without OneDrive
- [ ] Tests `warn_long_path()`: verifies log output contains `[INIT-GUARD] WARN` and the repo path length
- [ ] Tests `prune_stale_refs()`: creates a git repo with a stale worktree ref (worktree dir deleted but ref remains), verifies prune removes it, verifies return count
- [ ] Tests `cleanup_orphan_dirs()`: (a) creates `.ql-wt/US-001/` not in `git worktree list` with no uncommitted changes — verifies it's removed, (b) creates `.ql-wt/US-002/` with uncommitted file — verifies it's preserved with warning log
- [ ] Tests `run_preflight()` idempotency: runs twice, verifies second run returns 0 without re-running checks
- [ ] All tests pass with exit 0 when init-guard.sh is correct
- [ ] Final line prints `Results: <PASS>/<TOTAL> passed (<FAIL> failed)` and exits with code 1 if any failures

---

### US-011: Unit tests for resilience.sh

**Description:** As a developer, I want unit tests for the resilience module covering WIP commits, squash-on-merge, crash recovery, and resumable work detection.

**Acceptance Criteria:**
- [ ] File exists at `tests/test_resilience.sh`
- [ ] Follows existing test pattern (PASS/FAIL counters, temp git repos)
- [ ] Tests `wip_commit()`: (a) creates a file in a worktree, calls `wip_commit`, verifies commit message format matches `wip: US-001 T-001 - <title>`, (b) calls `wip_commit` with no changes — verifies return code 1 and no new commit
- [ ] Tests `wip_commit()` time-based trigger: passes start_time and end_time args with >120s gap, verifies commit is created even if no files changed (commit message still created as empty wip marker)
- [ ] Tests `get_completed_tasks()`: creates 3 WIP commits for US-001 (T-001, T-002, T-003), verifies function returns `T-001\nT-002\nT-003`
- [ ] Tests `squash_and_merge()` with multiple WIP commits: creates a worktree branch with 3 WIP commits + 1 final commit, merges, verifies feature branch has exactly 1 new merge commit (squashed)
- [ ] Tests `squash_and_merge()` with single commit: creates a worktree branch with 1 commit, merges, verifies `--no-ff` merge (not squash)
- [ ] Tests `recover_orphaned_worktrees()`: identical to existing tests in `tests/test_crash_recovery.sh` (verifies backward compatibility of the absorbed function)
- [ ] Tests `detect_resumable_work()`: (a) stale story with WIP commits returns `resumable:<sha>:<task_ids>`, (b) stale story with no WIP commits returns `fresh`
- [ ] All tests pass with exit 0

---

### US-012: Unit tests for merge-semantic.sh

**Description:** As a developer, I want unit tests for the semantic merge module covering AST merge, diff3 fallback, and graceful degradation.

**Acceptance Criteria:**
- [ ] File exists at `tests/test_merge_semantic.sh`
- [ ] Follows existing test pattern
- [ ] Tests `can_semantic_merge()`: (a) returns 0 for `.ts` file when diff3 is available, (b) returns 1 for `.go` file when only diff3 is available (diff3 handles all text files, so this actually returns 0 — test should reflect actual behavior), (c) returns 1 for binary file
- [ ] Tests `semantic_merge()` with diff3 fallback: creates base/ours/theirs versions of a text file where ours adds line A and theirs adds line B in different locations. Verifies output contains both lines A and B
- [ ] Tests `semantic_merge()` with true conflict via diff3: creates base/ours/theirs where both modify the same line. Verifies return code 1
- [ ] Tests `get_semantic_merge_status()`: verifies it returns a comma-separated string containing at least `diff3` (assuming diff3 is available on the test system)
- [ ] Tests graceful degradation: temporarily sets `DIFF3_AVAILABLE=false` and `TSMORPH_AVAILABLE=false` and `LIBCST_AVAILABLE=false`, verifies `can_semantic_merge()` returns 1 for all files
- [ ] If `ts-morph` is available on the test system: tests TypeScript AST merge where ours adds `interface Foo` and theirs adds `interface Bar` to the same file. Verifies output contains both interfaces
- [ ] If `ts-morph` is NOT available: test is skipped with `SKIP: ts-morph not available` (not a failure)
- [ ] All tests pass with exit 0

---

### US-013: Extended tests for merge-strategy.sh — stash exclusion and semantic delegation

**Description:** As a developer, I want tests verifying that quantum.json is excluded from stash during merges and that semantic merge is attempted before ours/theirs fallback.

**Acceptance Criteria:**
- [ ] Tests are added to existing `tests/test_merge_strategy.sh` (not a new file)
- [ ] Test "quantum.json stash exclusion": creates a repo with dirty quantum.json, runs `classify_and_merge()`, verifies quantum.json content is unchanged after merge (not corrupted by stash/pop)
- [ ] Test "quantum.json backup/restore": creates a repo, modifies quantum.json before merge, runs `classify_and_merge()` which encounters a conflict, verifies quantum.json.merge-bak is created during merge and cleaned up after
- [ ] Test "semantic merge delegation": mocks `can_semantic_merge` to return 0 and `semantic_merge` to return 0, creates a conflict classified as `ours`, verifies `semantic_merge` was called before `git checkout --ours`
- [ ] Test "semantic merge fallback": mocks `semantic_merge` to return 1 (true conflict), verifies the original `ours` action is used as fallback
- [ ] All existing tests in `test_merge_strategy.sh` continue to pass
- [ ] All tests pass with exit 0

---

### US-014: Extended tests for materialize.sh — fileConflicts-based materialization

**Description:** As a developer, I want tests verifying that single-consumer contract types appearing in fileConflicts are now materialized.

**Acceptance Criteria:**
- [ ] Tests are added to existing `tests/test_materialize.sh` (not a new file)
- [ ] Test "single-consumer type in fileConflicts is materialized": creates quantum.json with a single-consumer type whose `definitionFile` appears in a `fileConflicts` entry. Verifies the type IS materialized (file written to disk)
- [ ] Test "single-consumer type NOT in fileConflicts is skipped": creates quantum.json with a single-consumer type whose `definitionFile` does NOT appear in any `fileConflicts` entry. Verifies the type is NOT materialized
- [ ] Test "multi-consumer type still materialized": verifies existing behavior unchanged — a type with 2+ consumers is materialized regardless of fileConflicts
- [ ] Log output for fileConflicts-based materialization contains `(file-conflict prevention)` not `(multi-consumer)`
- [ ] All existing tests in `test_materialize.sh` continue to pass
- [ ] All tests pass with exit 0

---

### US-015: Integration test — init to merge flow

**Description:** As a developer, I want an integration test that validates the full flow from init-guard through worktree creation, WIP commits, squash merge, and typecheck gate.

**Acceptance Criteria:**
- [ ] File exists at `tests/integration/test_init_to_merge.sh`
- [ ] Creates a temp git repo with a quantum.json containing 1 story with 3 tasks
- [ ] Runs `run_preflight()` and verifies `execution.initGuard` is populated in quantum.json
- [ ] Creates a worktree via `create_worktree()`
- [ ] Simulates 3 tasks: creates a file per task, calls `wip_commit()` after each
- [ ] Verifies worktree branch has 3 WIP commits + 1 final commit
- [ ] Runs `squash_and_merge()` to merge worktree branch into main
- [ ] Verifies main branch has exactly 1 new commit (squashed) with message `feat: US-001 - ...`
- [ ] Verifies all 3 task files are present in the merged result
- [ ] Cleans up worktree and verifies `.ql-wt/` is empty
- [ ] All tests pass with exit 0

---

### US-016: Integration test — semantic merge conflict resolution

**Description:** As a developer, I want an integration test that verifies semantic merge preserves code from both sides when two branches add different declarations to the same file.

**Acceptance Criteria:**
- [ ] File exists at `tests/integration/test_semantic_merge_conflict.sh`
- [ ] Creates a temp git repo with a base TypeScript file containing `export interface Base { id: string }`
- [ ] Creates branch-a that adds `export interface Foo { name: string }` to the same file
- [ ] Creates branch-b that adds `export interface Bar { count: number }` to the same file
- [ ] Merges branch-a into main (clean merge)
- [ ] Attempts to merge branch-b into main (conflict expected on the shared file)
- [ ] If `diff3` is available: verifies the merged output contains BOTH `interface Foo` and `interface Bar` and `interface Base`
- [ ] If neither diff3 nor ts-morph is available: verifies fallback to `ours`/`theirs` (existing behavior), test passes with SKIP note
- [ ] All tests pass with exit 0

---

### US-017: Integration test — crash recovery with WIP commits

**Description:** As a developer, I want an integration test that simulates a session restart and verifies the orchestrator can detect and resume from WIP commits.

**Acceptance Criteria:**
- [ ] File exists at `tests/integration/test_crash_recovery_wip.sh`
- [ ] Creates a temp git repo with quantum.json containing 1 story (US-001) with 5 tasks
- [ ] Creates a worktree, makes 3 WIP commits (T-001, T-002, T-003), then "crashes" (does NOT make final commit, does NOT signal completion)
- [ ] Marks US-001 as `in_progress` with `startedAt` in quantum.json
- [ ] Runs `detect_resumable_work()` — verifies it returns `resumable` with T-001, T-002, T-003 as completed tasks
- [ ] Simulates re-spawn by calling `build_agent_prompt()` with `completed_tasks="T-001 T-002 T-003"` and verifies the prompt contains "Previously completed tasks" with those IDs
- [ ] Verifies the worktree branch still has the 3 WIP commits intact
- [ ] All tests pass with exit 0

---

### US-018: Integration test — quantum.json stash isolation

**Description:** As a developer, I want an integration test that verifies quantum.json is never corrupted during merge operations.

**Acceptance Criteria:**
- [ ] File exists at `tests/integration/test_stash_isolation.sh`
- [ ] Creates a temp git repo with quantum.json containing story statuses
- [ ] Modifies quantum.json (simulating orchestrator state update) so it's dirty
- [ ] Creates a worktree branch with changes that will conflict with main
- [ ] Runs `classify_and_merge()` to merge the worktree branch
- [ ] After merge (success or abort), reads quantum.json and verifies: (a) it is valid JSON, (b) story statuses match the pre-merge state (not reverted to an older version), (c) no stash artifacts remain (`git stash list` is empty or does not contain `ql-auto-stash`)
- [ ] Runs the test again with quantum.json in .gitignore — verifies same behavior
- [ ] Runs the test again with quantum.json tracked (git add quantum.json) — verifies backup/restore preserves content
- [ ] All tests pass with exit 0

## 4. Functional Requirements

FR-1: The init-guard module SHALL detect repo paths longer than 150 characters and paths containing "OneDrive" (case-insensitive), logging a warning with the path length and short-path fallback location.

FR-2: The init-guard module SHALL run `git worktree prune` at orchestrator initialization with retry-once-on-failure (2s delay), logging the count of pruned references.

FR-3: The init-guard module SHALL scan `.ql-wt/` for orphaned directories not registered in `git worktree list`, removing clean orphans and preserving dirty ones with a warning log.

FR-4: The init-guard module SHALL write results to `execution.initGuard` in quantum.json and skip re-execution if already run within the current session (1-hour TTL).

FR-5: The init-guard module SHALL set `execution.initGuard.forceSequential = true` when the temp directory is not writable, forcing the orchestrator to use sequential execution.

FR-6: The resilience module SHALL provide `wip_commit()` that creates a git commit with message format `wip: <story_id> <task_id> - <title>` when files changed OR task duration exceeded 120 seconds.

FR-7: The resilience module SHALL provide `squash_and_merge()` that uses `git merge --squash` for branches with 2+ commits and delegates to `classify_and_merge()` for single-commit branches.

FR-8: The resilience module SHALL provide `detect_resumable_work()` that identifies stale stories with WIP commits and returns the list of completed task IDs.

FR-9: The resilience module SHALL absorb all functionality from `crash-recovery.sh`, maintaining backward-compatible function signatures for `recover_orphaned_worktrees()`.

FR-10: The merge-semantic module SHALL attempt AST-aware 3-way merge at the **top-level declaration level** for TypeScript (via ts-morph) and Python (via libcst) files before falling back to `diff3`, then to rule-based `ours`/`theirs`.

FR-11: The merge-semantic module SHALL detect available tooling at load time and set `TSMORPH_AVAILABLE`, `LIBCST_AVAILABLE`, and `DIFF3_AVAILABLE` flags, logging the results.

FR-12: The merge-semantic module SHALL return 1 (true conflict) when both sides modify the same top-level declaration name, without attempting to merge within the declaration body.

FR-13: The merge-strategy module SHALL exclude quantum.json from git stash operations by using pathspec exclusion (`-- ':!quantum.json'`) and backing up quantum.json with `cp` before merge, restoring after completion.

FR-14: The merge-strategy module SHALL attempt semantic merge (via `merge-semantic.sh`) before applying `ours` or `theirs` resolution for any conflicted file where `can_semantic_merge()` returns true.

FR-15: The monitor module SHALL delegate to `squash_and_merge()` from resilience.sh when available, falling back to the existing merge path when resilience.sh is not loaded.

FR-16: The materialize module SHALL materialize single-consumer contract types when their `definitionFile` path appears in any `fileConflicts` entry in quantum.json, in addition to the existing multi-consumer threshold.

FR-17: The orchestrator's main-branch git operations (contract materialization, wiring fixes, type audit) SHALL use `git add <specific files>` instead of `git add -A`. Worktree-mode agent commits continue to use `git add -A` (scoped to isolated worktree).

FR-18: The orchestrator agent prompt SHALL include init-guard integration at Step 1, resilience integration at Steps 1B and 3B, and updated stash exclusion documentation at Step 3B.3.

FR-19: The implementer agent prompt SHALL include WIP commit instructions for worktree mode, with support for skipping previously completed tasks when re-spawned after a crash.

FR-20: The spawn module SHALL accept an optional `completed_tasks` parameter and include it in the agent prompt when non-empty.

FR-21: When semantic merge tooling (ts-morph, libcst, diff3) is unavailable, the system SHALL log a warning at init and add `semantic_merge_unavailable` to `execution.initGuard.warnings`. Merge resolution falls back silently to existing `ours`/`theirs` behavior.

FR-22: All new and modified modules SHALL pass shellcheck without errors.

FR-23: `lib/crash-recovery.sh` SHALL be removed after its functionality is absorbed into `lib/resilience.sh`.

## 5. Non-Goals (Out of Scope)

1. **Cleaning up `.claude/worktrees/agent-*` directories** — these are managed by the Claude Code platform, not quantum-loop. The 48 stale worktrees from Claude Code's Agent tool are a platform issue.
2. **Semantic merge for Go, Rust, or other languages** — only TypeScript and Python get AST-aware merge. Other languages use `diff3` fallback or rule-based resolution.
3. **Statement-level AST merge** — merge granularity is top-level declarations only. Merging within function bodies or class methods is out of scope.
4. **Moving the repo off OneDrive** — the init-guard warns and auto-relocates worktrees, but doesn't move the repo itself.
5. **Changing the worktree isolation model** — worktrees remain the parallel execution mechanism. No switch to Docker containers, separate clones, or other isolation approaches.
6. **Modifying quantum.json schema validation** — new fields are additive and optional. No JSON schema enforcement is added.
7. **Post-merge integration test automation** — the testing strategy includes integration tests for the new modules, but automated post-merge verification of all merged features working together remains a manual step in live validation.

## 6. Design Considerations

**Module loading pattern:** All 3 new modules follow the established graceful-fallback pattern used by existing modules:
```bash
MODULE_AVAILABLE=true
source "$LIB_DIR/module.sh" 2>/dev/null || MODULE_AVAILABLE=false
```
This ensures the orchestrator works even if new modules are absent (e.g., when running an older quantum.json with a newer orchestrator).

**AST tooling installation:** `ts-morph` and `libcst` are NOT installed by quantum-loop. They must be pre-installed in the project's environment. The semantic merge module detects their availability and degrades gracefully. This follows the principle that quantum-loop is a plugin, not a package manager.

**crash-recovery.sh deprecation:** The file is removed in this batch. Any external code that sources it directly will break. This is acceptable because crash-recovery.sh was only used internally by the orchestrator agent prompt (not by external callers).

**Stash pathspec exclusion:** `git stash push -- ':!quantum.json'` requires Git >= 2.13. The minimum Git version for quantum-loop is already >= 2.20 (for worktree support), so this is safe.

## 7. Technical Considerations

**Dependencies:**
- Git >= 2.20 (existing requirement)
- Python 3.x (existing requirement for json-atomic.sh and other modules)
- `diff3` — ships with Git for Windows (in `/usr/bin/diff3` via MSYS2). Verified available on target platform.
- `ts-morph` (optional) — Node.js package for TypeScript AST manipulation. Used via `npx` or global install.
- `libcst` (optional) — Python package for Python CST manipulation. Used via `python -c "import libcst"`.
- `jq` (existing requirement for crash-recovery.sh, now resilience.sh)

**Performance:**
- `run_preflight()` adds ~2-5 seconds to orchestrator init (one-time per session)
- WIP commits add ~1-2 seconds per task (git add + commit in worktree)
- Semantic merge via diff3 adds ~0.5 seconds per conflicted file
- Semantic merge via ts-morph/libcst adds ~3-5 seconds per conflicted file (AST parsing)
- Squash merge adds negligible overhead vs regular merge

**Backward compatibility:**
- All new quantum.json fields are optional with sensible defaults
- Missing `execution.initGuard` → preflight runs from scratch
- Missing `execution.resilience` → WIP commits enabled, squash enabled (defaults)
- Missing `lastWipCommit`/`completedTasks` on stories → treated as fresh starts

## 8. Success Metrics

- **Zero quantum.json corruption** across 3+ parallel execution runs
- **Zero `index.lock` contention errors** in orchestrator logs
- **Semantic merge resolves 50%+ of conflicts** that previously required `ours`/`theirs` (measured by comparing conflict resolution logs between runs)
- **WIP recovery saves 80%+ of completed task work** on session restart (measured by `completedTasks` count vs total tasks on re-spawn)
- **Init-guard detects OneDrive paths** in 100% of runs on the current development machine
- **All 21+ existing tests pass** after changes (zero regressions)
- **All new unit and integration tests pass** (18 stories worth of new test coverage)

## 9. Open Questions

1. **diff3 on Windows Git Bash:** Verified that diff3 ships with Git for Windows (MSYS2 `/usr/bin/diff3`). No longer an open question — resolved.
2. **ts-morph invocation method:** Should we use `npx ts-morph` (slower, requires node_modules) or write an inline Node.js script that imports ts-morph? Leaning toward inline script for speed. Decision can be made during implementation.
3. **WIP commit for no-op tasks:** When a task takes >2 minutes but produces no file changes, the WIP commit would be empty. Git rejects empty commits by default. Options: (a) use `--allow-empty`, (b) skip WIP for truly empty tasks. Leaning toward (b) — skip if no changes AND duration < 120s; commit with `--allow-empty` if duration >= 120s as a progress marker.

## Lifecycle Checklist

- [x] **First-run behavior:** New modules detect absence of `execution.initGuard`, `execution.resilience`, `lastWipCommit`, `completedTasks` fields and use defaults. No migration needed.
- [x] **Returning-user behavior:** `run_preflight()` checks `initGuard.ranAt` TTL to avoid re-running. WIP commits from previous sessions are detected by `detect_resumable_work()`.
- [x] **Update behavior:** Adding new modules to an existing quantum-loop installation requires no migration. New fields are additive. `crash-recovery.sh` removal is the only breaking change — orchestrator.md references are updated in US-008.
- [x] **Error recovery:** Each new function has explicit error returns (1) and stderr logging. Semantic merge failures fall back to rule-based. Init-guard failures are non-blocking (except forceSequential). WIP commit failures are non-blocking (agent continues).
- [x] **No-data/empty state:** Empty `fileConflicts` → materialization threshold unchanged. No WIP commits → squash_and_merge falls back to regular merge. No orphan dirs → cleanup is a no-op. No AST tools → semantic merge disabled with warning.
- [x] **Uninstall/disable:** Removing any new module causes its `_AVAILABLE` flag to be false. Orchestrator falls back to existing behavior. quantum.json fields become inert (ignored if modules are absent). No cleanup needed.
