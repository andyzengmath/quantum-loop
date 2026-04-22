# PRD: Modular Hardening — 7 Independent Fixes for Parallel Execution Post-Mortem Issues

## 1. Introduction/Overview

The quantum-loop orchestrator's parallel execution mode (worktree-isolated agents) works — 22/22 stories passed first attempt in the multi-language indexing run — but required ~20 manual merge conflict resolutions, 4 post-merge fix commits, and 1 post-execution fix. This feature adds 7 independent modules to the orchestrator that automate merge conflict resolution by file category, barrel file regeneration, dependency manifest protection, worktree lifecycle tracking, known test failure tracking, and interface cascade prevention. The modules plug into existing orchestrator hook points (pre-wave, post-agent, post-merge, post-wave) and degrade gracefully if absent.

## 2. Goals

- Eliminate manual merge intervention by auto-resolving conflicts based on file category (dependency manifests, barrel exports, new files, shared infrastructure)
- Auto-regenerate barrel/index files after merges to prevent the most common conflict type (~15 of ~20 conflicts in the post-mortem)
- Protect dependency manifests (`package.json`, `pyproject.toml`, `Cargo.toml`, `go.mod`) from destructive `--theirs` merges that drop accumulated dependencies
- Track and clean up worktrees within the current execution session, preventing filesystem limit exhaustion (62 stale worktrees in post-mortem)
- Track known test failures across waves so agents can distinguish pre-existing failures from regressions they caused
- Prevent interface-breaking stories from running in parallel with their consumers via `contractBreaking` scheduling metadata
- Log wall-clock timing for each module invocation so the observations document can report performance impact
- Maintain full backward compatibility — existing quantum.json files without the new fields work as today

## 3. User Stories

### US-001: Add modular hardening fields to quantum.json schema

**Description:** As an orchestrator, I want `knownFailures`, `execution.worktreeTracking`, and `execution.mergeStrategy` fields in quantum.json so that the 7 hardening modules have a well-defined schema to read and write.

**Acceptance Criteria:**
- [ ] `quantum.json.example` includes a `knownFailures` top-level object with fields: `baseline` (object with `capturedAt`, `wave`, `passCount`, `failCount`, `skipCount`, `failingTests` array), `current` (same shape plus `updatedAt`), `flakyThreshold` (number, default 1), `fullSuiteTimeout` (number, default 60)
- [ ] `knownFailures.current.failingTests[]` entries have fields: `name` (string), `failingSince` (number — wave number), `introducedBy` (string — story ID or null), `expectedFix` (string — story ID or null), `error` (string — error message snippet)
- [ ] `quantum.json.example` includes `execution.worktreeTracking` with fields: `activeWorktrees` (array of objects with `path`, `branch`, `storyId`, `createdAt`, `wave`), `cleanedThisSession` (number), `maxWorktrees` (number)
- [ ] `quantum.json.example` includes `execution.mergeStrategy` with `rules` array (each entry: `category`, `pattern`, `action`, `postAction`, `condition`) and `defaultAction` field
- [ ] Default `mergeStrategy.rules` include 5 rules in order: `dependency_manifest` (ours+install), `barrel_export` (regenerate), `new_story_file` (theirs, condition: file_not_on_ours), `shared_infrastructure` (ours, condition: file_merged_in_earlier_wave), `contract_stub` (theirs, condition: file_in_materializedContracts)
- [ ] `quantum.json.example` story objects include optional `contractBreaking` (boolean) and `fixes` (array of story IDs) fields, with documentation
- [ ] All new fields are documented with inline comments explaining purpose and allowed values
- [ ] All new fields are optional — a quantum.json without them remains valid for existing orchestrator logic
- [ ] Typecheck/lint passes (shellcheck on any modified .sh files)

---

### US-002: Create barrel auto-regeneration module

**Description:** As an orchestrator performing post-merge cleanup, I want a barrel regeneration module that scans directories and regenerates index/barrel files so that parallel stories adding exports to the same barrel don't cause merge conflicts.

**Acceptance Criteria:**
- [ ] File exists at `lib/barrel-regen.sh`
- [ ] Sources `lib/common.sh` following the existing pattern in other lib scripts
- [ ] Exports function `detect_barrel_files(repo_root)` that scans for `**/index.ts`, `**/index.js`, `**/__init__.py`, `**/mod.rs` and returns newline-separated file paths
- [ ] Exports function `regenerate_barrel(barrel_path, language)` that:
  - For TypeScript/JavaScript: scans the directory for `.ts`/`.js` files (excluding `index.*`), generates sorted `export * from './Filename'` lines
  - For Python: scans for `.py` files (excluding `__init__.py`), generates sorted `from .module import *` lines
  - For Rust: scans for `.rs` files (excluding `mod.rs`), generates sorted `pub mod filename;` lines
  - Preserves lines with `// manual` or `# manual` comment markers (explicit preservation)
  - Preserves lines that do not match the auto-generated export pattern (fallback preservation — e.g., custom `export { named }` or `import` statements)
  - Writes the regenerated content to the barrel file
- [ ] Exports function `should_regenerate(barrel_path, conflict_files)` that returns 0 (true) if `barrel_path` appears in the space-separated `conflict_files` list, 1 (false) otherwise
- [ ] If the regenerated barrel would have 0 auto-generated exports, writes a valid empty file with language-appropriate comment: `// No exports` or `# No exports`
- [ ] Logs each action: `[BARREL-REGEN] Regenerated <path> (N exports)` or `[BARREL-REGEN] SKIP <path> — contains non-export logic`
- [ ] Logs wall-clock time: `[BARREL-REGEN] Completed in Nms`
- [ ] Non-pure barrels (files containing statements beyond imports/exports) are skipped with a log message, not regenerated
- [ ] All functions are idempotent — running regenerate_barrel twice produces identical output
- [ ] Typecheck/lint passes (shellcheck on barrel-regen.sh)

---

### US-003: Create dependency manifest protection module

**Description:** As an orchestrator performing post-merge cleanup, I want a dependency manifest protection module that preserves the main branch's manifest with `--ours` and runs the appropriate package install command, so that accumulated dependencies are never lost during merges.

**Acceptance Criteria:**
- [ ] File exists at `lib/dep-manifest.sh`
- [ ] Sources `lib/common.sh` following the existing pattern
- [ ] Exports function `detect_package_manager(repo_root)` that detects and returns ALL package managers present (newline-separated): `npm` (package.json), `yarn` (yarn.lock), `pnpm` (pnpm-lock.yaml), `cargo` (Cargo.toml), `pip` (requirements*.txt), `poetry` (poetry.lock + pyproject.toml), `go` (go.mod). Returns empty string if none detected.
- [ ] Exports function `protect_manifest(repo_root, conflict_files)` that:
  - Identifies which conflict files are dependency manifests by matching against known manifest filenames: `package.json`, `package-lock.json`, `yarn.lock`, `pnpm-lock.yaml`, `Cargo.toml`, `Cargo.lock`, `pyproject.toml`, `poetry.lock`, `go.mod`, `go.sum`, `requirements.txt`, `requirements-dev.txt`
  - For each matching file: runs `git checkout --ours <file> && git add <file>`
  - Returns the count of protected files on stdout
  - Logs: `[DEP-MANIFEST] Protected <file> with --ours`
- [ ] Exports function `run_install(repo_root, package_manager)` that runs the install command for the detected manager: `npm install` / `yarn install` / `pnpm install` / `cargo fetch` / `pip install -e .` / `poetry install` / `go mod tidy`
- [ ] `run_install` has a 120-second timeout. On timeout: kills the process, logs `[DEP-MANIFEST] Install timed out after 120s`, returns non-zero
- [ ] `run_install` on failure: logs the error, attempts recovery by running `git checkout --theirs <manifest>` for the `dependencies` section only, re-runs install. If recovery also fails: logs warning, returns non-zero (does NOT fail the story — post-merge test suite will catch missing deps)
- [ ] Exports function `verify_lockfile(repo_root, package_manager)` that checks the lockfile exists and is non-empty after install. Returns 0 on success, 1 on failure.
- [ ] When multiple package managers are detected, `run_install` is called for each in sequence. One failure does not block others.
- [ ] Logs wall-clock time: `[DEP-MANIFEST] Install completed in Nms`
- [ ] Typecheck/lint passes (shellcheck)

---

### US-004: Extend worktree.sh with lifecycle tracking functions

**Description:** As an orchestrator managing parallel agents, I want lifecycle tracking functions in worktree.sh so that worktrees are registered at spawn, cleaned after merge, and stale worktrees from earlier waves are pruned before spawning new ones.

**Acceptance Criteria:**
- [ ] Functions are added to the existing `lib/worktree.sh` file (not a new file)
- [ ] Exports function `register_worktree(json_path, story_id, path, branch, wave)` that adds an entry to `execution.worktreeTracking.activeWorktrees` in quantum.json using atomic JSON write (Python or jq, following `lib/json-atomic.sh` patterns)
- [ ] Exports function `cleanup_stale_worktrees(json_path, repo_root)` that:
  - Reads `execution.worktreeTracking.activeWorktrees` from quantum.json
  - For each entry: reads the corresponding story's status from quantum.json
  - If story status is `"passed"` or `"failed"` (story finished but worktree still exists): removes the worktree via the existing `remove_worktree()` function, removes the entry from `activeWorktrees`
  - If `worktreeTracking` is absent: falls back to `list_worktrees()` + `git worktree list --porcelain`, removes `.ql-wt/` entries not matching any `in_progress` story
  - Updates `cleanedThisSession` counter
  - Logs: `[WORKTREE] Cleaned N stale worktrees` or `[WORKTREE] No stale worktrees found`
- [ ] Exports function `cleanup_merged_worktrees(json_path, repo_root, completed_story_ids)` that:
  - Takes a space-separated list of story IDs that just completed (passed or failed)
  - Calls the existing `remove_worktree()` for each
  - Removes entries from `activeWorktrees`
  - Logs: `[WORKTREE] Removing N merged worktrees from Wave M`
- [ ] Exports function `pre_spawn_check(json_path, max_worktrees)` that:
  - Checks if `activeWorktrees.length >= max_worktrees`
  - If at limit: runs `cleanup_stale_worktrees()` first
  - If still at limit after cleanup: logs `[WORKTREE] WARNING: at worktree limit (N/N), waiting for slot`
  - Returns 0 if a slot is available, 1 if still at limit
- [ ] Worktree removal failures are handled: retry once after 2s, then skip with warning. After 3 consecutive failures for the same worktree across waves, log user-visible warning: `[WORKTREE] WARNING: <path> could not be removed after 3 attempts. Manual cleanup may be needed.`
- [ ] Logs wall-clock time for bulk cleanup operations
- [ ] Existing `create_worktree()`, `remove_worktree()`, `list_worktrees()` functions are unchanged — no signature or behavior changes
- [ ] Existing `tests/test_worktree.sh` tests continue to pass
- [ ] Typecheck/lint passes (shellcheck on worktree.sh)

---

### US-005: Create known failures tracking module

**Description:** As an orchestrator, I want a known-failures module that captures test baselines before Wave 1, snapshots after each wave, checks for regressions after each merge, and formats known-failure context for agent spawn prompts, so that merge decisions and agent behavior are informed by accurate failure state.

**Acceptance Criteria:**
- [ ] File exists at `lib/known-failures.sh`
- [ ] Sources `lib/common.sh` following the existing pattern
- [ ] Exports function `detect_test_runner(repo_root)` that returns the test runner name and parse command:
  - `jest` or `vitest` (detected from package.json): parse via `--json` flag
  - `pytest` (detected from pyproject.toml/pytest.ini/setup.cfg): parse via `-v --tb=line -q`
  - `go test` (detected from go.mod): parse via `-v` output
  - Returns `runner` and `parseCommand` as colon-separated string: `jest:npx jest --json`
  - Returns empty string if no test runner detected
- [ ] Exports function `capture_baseline(repo_root, json_path)` that:
  - Runs the full test suite using the detected test runner
  - Parses output for pass/fail/skip counts and failing test names
  - Writes to `knownFailures.baseline` in quantum.json: `capturedAt`, `wave: 0`, `passCount`, `failCount`, `skipCount`, `failingTests` (array of test name strings)
  - Also initializes `knownFailures.current` as a copy of baseline
  - Logs: `[KNOWN-FAILURES] Baseline: N pass, M fail, K skip`
  - If test output is unparseable: falls back to regex counting lines matching FAIL/PASS/ERROR. If that also fails: sets `knownFailures.baseline = null`, logs `[KNOWN-FAILURES] Could not parse test output — tracking disabled`
- [ ] Exports function `capture_wave_snapshot(repo_root, json_path, wave_num)` that:
  - Runs the full test suite, parses output
  - Updates `knownFailures.current` with new counts
  - For each NEW failure (name not in previous `current.failingTests`): adds entry with `name`, `failingSince: wave_num`, `introducedBy` (inferred from git blame on the failing test's imports — story ID if available, null otherwise), `expectedFix` (from story `fixes` field if declared in quantum.json, else heuristic: next dependent story touching same files, else null), `error` (first line of failure output)
  - For failures that RESOLVED (name was in previous snapshot but not in current): removes them from `current.failingTests`
  - Logs: `[KNOWN-FAILURES] Wave N: X pass (+/-delta), Y fail (+/-delta), Z skip (+/-delta)`
- [ ] Exports function `delta_check(repo_root, json_path, story_id)` that:
  - Runs the test suite (full suite if under `fullSuiteTimeout` seconds, affected-files-only if over)
  - Compares results to `knownFailures.current`
  - If new failures found AND count exceeds `flakyThreshold`: returns 1 with `newFailures` list on stdout
  - If new failures found AND count <= `flakyThreshold`: returns 0 with warning: `[KNOWN-FAILURES] N new failure(s) below flaky threshold — treating as noise`
  - If all failures are in `current.failingTests` (known): returns 0 with `[KNOWN-FAILURES] N known failures present — PASS`
  - If no failures: returns 0
  - Logs wall-clock time: `[KNOWN-FAILURES] Delta check completed in Nms`
- [ ] Exports function `format_agent_context(json_path)` that:
  - Reads `knownFailures.current.failingTests`
  - Returns a formatted string block suitable for inclusion in agent spawn prompts:
    ```
    Known failing tests (pre-existing, not caused by your story):
      - <test_name> (failing since Wave N, expected fix: <story_id>)
    If you see ONLY these failures, they are not your fault — proceed normally.
    If you see NEW failures not on this list, they ARE your responsibility — fix them.
    ```
  - Returns empty string if no known failures exist
- [ ] Affected-files-only mode: when full suite exceeds `fullSuiteTimeout`, `delta_check` traces imports from files changed in the merge and runs only test files that transitively depend on changed files
- [ ] Typecheck/lint passes (shellcheck)

---

### US-006: Create category-based merge strategy module

**Description:** As an orchestrator merging worktree branches, I want a merge strategy module that classifies conflicting files by category and applies the appropriate resolution (ours/theirs/regenerate/escalate), so that merge conflicts are resolved automatically based on configurable rules.

**Acceptance Criteria:**
- [ ] File exists at `lib/merge-strategy.sh`
- [ ] Sources `lib/common.sh`, `lib/barrel-regen.sh`, and `lib/dep-manifest.sh`
- [ ] Exports function `get_merge_context(json_path)` that reads from quantum.json:
  - `execution.materializedContracts` (for `file_in_materializedContracts` condition)
  - `progress[].filesChanged` arrays (for `file_merged_in_earlier_wave` condition)
  - `execution.mergeStrategy.rules` (for rule definitions)
  - Returns context as a set of environment variables or a temp file
- [ ] Exports function `classify_conflict(file_path, merge_context)` that:
  - Evaluates `mergeStrategy.rules` in array order (first match wins)
  - For pattern-based rules: matches `file_path` against the `pattern` field (glob/regex)
  - For condition-based rules: evaluates the condition:
    - `file_not_on_ours`: `git ls-tree HEAD -- <file>` returns empty
    - `file_merged_in_earlier_wave`: file appears in `progress[].filesChanged`
    - `file_in_materializedContracts`: file path matches a `definitionFile` in `execution.materializedContracts`
  - Returns category, action, and postAction as colon-separated string: `dependency_manifest:ours:install`
  - If no rule matches: returns `unknown:escalate:`
- [ ] Exports function `resolve_conflict(file_path, action, post_action, repo_root)` that:
  - `"ours"`: runs `git checkout --ours <file> && git add <file>`
  - `"theirs"`: runs `git checkout --theirs <file> && git add <file>`
  - `"regenerate"`: calls `regenerate_barrel()` from barrel-regen.sh, then `git add <file>`
  - `"escalate"`: returns 1 (signals caller to abort merge)
  - After resolution, if `post_action` is `"install"`: calls `protect_manifest()` and `run_install()` from dep-manifest.sh
  - Returns 0 on success, 1 on escalation
- [ ] Exports function `classify_and_merge(worktree_branch, repo_root, json_path)` that:
  - Runs `git merge <branch> --no-ff --no-commit`
  - If clean merge (exit 0): runs `git commit --no-edit`, returns 0
  - If conflicts (exit 1):
    1. Lists conflicting files: `git diff --name-only --diff-filter=U`
    2. Calls `get_merge_context(json_path)`
    3. For each conflicting file: `classify_conflict()` then `resolve_conflict()`
    4. If ANY file escalates: runs `git merge --abort`, returns 1
    5. If ALL files resolved: runs `git commit --no-edit`, returns 0
  - Logs every classification decision: `[MERGE-STRATEGY] <file> -> <category> (<action>)`
  - Logs summary: `[MERGE-STRATEGY] Resolved N/M conflicts automatically` or `[MERGE-STRATEGY] Escalated — N unresolvable conflicts`
  - Logs wall-clock time: `[MERGE-STRATEGY] Merge completed in Nms`
- [ ] If `execution.mergeStrategy` is absent from quantum.json: falls back to `defaultAction: "escalate"` for all conflicts (equivalent to today's behavior of aborting on any conflict)
- [ ] Typecheck/lint passes (shellcheck)

---

### US-007: Integrate merge-strategy into monitor.sh

**Description:** As an orchestrator, I want `merge_worktree_branch()` in monitor.sh to delegate to the merge-strategy module so that all merges benefit from category-based conflict resolution without changing the orchestrator's call site.

**Acceptance Criteria:**
- [ ] `lib/monitor.sh` sources `lib/merge-strategy.sh` with a graceful fallback: `source "$MONITOR_LIB_DIR/merge-strategy.sh" 2>/dev/null || MERGE_STRATEGY_AVAILABLE=false`
- [ ] `merge_worktree_branch(repo_root, worktree_branch)` function signature is UNCHANGED (same parameters, same return code semantics)
- [ ] If `merge-strategy.sh` is available and `quantum.json` exists: delegates to `classify_and_merge(worktree_branch, repo_root, json_path)` where `json_path` is `"$repo_root/quantum.json"`
- [ ] If `merge-strategy.sh` is NOT available: falls back to the existing bare `git merge` implementation (current behavior preserved exactly)
- [ ] On clean merge (no conflicts): behavior is identical to today — returns 0
- [ ] On conflicting merge with all conflicts resolved by merge-strategy: returns 0 (today this would return 1)
- [ ] On conflicting merge with any escalated conflict: returns 1 and prints `CONFLICT: <filename>` lines to stdout (same format as today, for `retries.failureLog` compatibility)
- [ ] Existing `tests/test_monitor_merge.sh` tests continue to pass (the no-conflict and all-conflict-abort paths are unchanged)
- [ ] New test in `tests/test_merge_strategy_integration.sh` verifies the delegation path: merge with a barrel conflict is auto-resolved when merge-strategy.sh is present
- [ ] Typecheck/lint passes (shellcheck)

---

### US-008: Unit tests for barrel auto-regeneration module

**Description:** As a developer, I want comprehensive unit tests for barrel-regen.sh so that barrel regeneration behavior is verified for all supported languages and edge cases.

**Acceptance Criteria:**
- [ ] File exists at `tests/test_barrel_regen.sh`
- [ ] Follows the existing test pattern in the project (setup/teardown with temp directories, assertion functions from common test utilities if any)
- [ ] Tests `regenerate_barrel` for TypeScript: directory with `Foo.ts`, `Bar.ts`, `Baz.ts` produces `index.ts` with 3 `export * from` lines sorted alphabetically
- [ ] Tests `regenerate_barrel` for Python: directory with `foo.py`, `bar.py` produces `__init__.py` with 2 `from .module import *` lines sorted alphabetically
- [ ] Tests `regenerate_barrel` for Rust: directory with `foo.rs`, `bar.rs` produces `mod.rs` with 2 `pub mod` lines sorted alphabetically
- [ ] Tests manual export preservation: existing `index.ts` with `export { custom } from './special' // manual` retains the manual line after regeneration
- [ ] Tests fallback preservation: existing `index.ts` with `export { named } from './lib'` (non-matching auto-gen pattern) is preserved alongside auto-generated lines
- [ ] Tests non-pure barrel skip: `index.ts` containing `const config = {}` beyond exports is skipped with appropriate log message
- [ ] Tests empty directory: produces barrel with `// No exports` comment
- [ ] Tests `should_regenerate`: returns 0 (true) when barrel path is in conflict list, 1 (false) when not
- [ ] Tests `detect_barrel_files`: finds barrel files in nested directories
- [ ] Tests idempotency: running `regenerate_barrel` twice produces identical output
- [ ] All tests pass when run with `bash tests/test_barrel_regen.sh`
- [ ] Typecheck/lint passes (shellcheck)

---

### US-009: Unit tests for dependency manifest protection module

**Description:** As a developer, I want comprehensive unit tests for dep-manifest.sh so that dependency detection, protection, and install behavior is verified for all supported package managers.

**Acceptance Criteria:**
- [ ] File exists at `tests/test_dep_manifest.sh`
- [ ] Tests `detect_package_manager` for npm (package.json present), pip (requirements.txt present), multiple managers (package.json + pyproject.toml), and no managers (empty repo)
- [ ] Tests `protect_manifest` with a single manifest in conflict list: verifies `git checkout --ours` is called and file is staged
- [ ] Tests `protect_manifest` with no manifests in conflict list: returns 0, no git operations
- [ ] Tests `run_install` success path for npm: verifies `npm install` is invoked
- [ ] Tests `run_install` timeout: mocks a hanging process, verifies it's killed after 120s and returns non-zero
- [ ] Tests `run_install` failure with recovery: first install fails, theirs recovery succeeds
- [ ] Tests `run_install` failure without recovery: both attempts fail, returns non-zero with warning (does not fail the story)
- [ ] Tests `verify_lockfile` with existing non-empty lockfile (pass) and missing lockfile (fail)
- [ ] Tests multiple package manager handling: both npm and pip detected, install runs for each independently
- [ ] All tests pass when run with `bash tests/test_dep_manifest.sh`
- [ ] Typecheck/lint passes (shellcheck)

---

### US-010: Unit tests for worktree lifecycle functions

**Description:** As a developer, I want unit tests for the lifecycle tracking functions added to worktree.sh so that registration, cleanup, and pre-spawn checking are verified.

**Acceptance Criteria:**
- [ ] File exists at `tests/test_worktree_lifecycle.sh`
- [ ] Tests `register_worktree`: adds entry to `activeWorktrees` in a test quantum.json with correct fields (path, branch, storyId, createdAt, wave)
- [ ] Tests `cleanup_stale_worktrees` with 2 stale worktrees (story status "passed"): both removed, `cleanedThisSession` incremented by 2
- [ ] Tests `cleanup_stale_worktrees` with 0 stale worktrees (all stories "in_progress"): no removals
- [ ] Tests `cleanup_stale_worktrees` fallback: `worktreeTracking` absent from quantum.json, falls back to `git worktree list`
- [ ] Tests `cleanup_merged_worktrees` with 3 completed story IDs: all worktrees removed, entries cleared from tracking
- [ ] Tests `pre_spawn_check` with slots available (2 active, max 4): returns 0
- [ ] Tests `pre_spawn_check` at limit (4 active, max 4): triggers stale cleanup first, then re-checks
- [ ] Tests removal failure handling: `git worktree remove` fails, retries once after 2s, skips with warning
- [ ] Existing `tests/test_worktree.sh` continues to pass (no regressions to create/remove/list functions)
- [ ] All tests pass when run with `bash tests/test_worktree_lifecycle.sh`
- [ ] Typecheck/lint passes (shellcheck)

---

### US-011: Unit tests for known failures tracking module

**Description:** As a developer, I want comprehensive unit tests for known-failures.sh so that baseline capture, wave snapshots, delta checks, and agent context formatting are verified.

**Acceptance Criteria:**
- [ ] File exists at `tests/test_known_failures.sh`
- [ ] Tests `detect_test_runner` for jest (package.json with jest config), pytest (pyproject.toml with pytest section), go test (go.mod), and no runner (empty repo)
- [ ] Tests `capture_baseline` with clean suite (0 failures): writes baseline with `failCount: 0`, empty `failingTests`
- [ ] Tests `capture_baseline` with pre-existing failures (5 failures): writes baseline with `failCount: 5`, 5 entries in `failingTests`
- [ ] Tests `capture_baseline` with unparseable output: sets baseline to null, logs warning
- [ ] Tests `capture_wave_snapshot` with no change from baseline: updates `current`, no new failure entries
- [ ] Tests `capture_wave_snapshot` with 3 new failures: adds 3 entries with `failingSince`, `introducedBy`, `expectedFix`
- [ ] Tests `capture_wave_snapshot` with resolved failures: removes resolved entries from `current.failingTests`
- [ ] Tests `delta_check` with no regressions (fail count unchanged): returns 0
- [ ] Tests `delta_check` with known failures present (all in `current.failingTests`): returns 0 with log
- [ ] Tests `delta_check` with new regression (1 unknown failure above `flakyThreshold`): returns 1 with `newFailures` on stdout
- [ ] Tests `delta_check` with flaky threshold (1 new failure, `flakyThreshold: 1`): returns 0 with warning
- [ ] Tests `format_agent_context` with 3 known failures: returns formatted string block with test names and expected fixes
- [ ] Tests `format_agent_context` with no failures: returns empty string
- [ ] All tests pass when run with `bash tests/test_known_failures.sh`
- [ ] Typecheck/lint passes (shellcheck)

---

### US-012: Unit tests for merge strategy module

**Description:** As a developer, I want comprehensive unit tests for merge-strategy.sh so that file classification, conflict resolution, and the full merge flow are verified for all rule categories.

**Acceptance Criteria:**
- [ ] File exists at `tests/test_merge_strategy.sh`
- [ ] Tests `classify_conflict` pattern match: `package.json` classifies as `dependency_manifest:ours:install`
- [ ] Tests `classify_conflict` barrel match: `src/parsers/index.ts` classifies as `barrel_export:regenerate:`
- [ ] Tests `classify_conflict` condition `file_not_on_ours`: file not on HEAD classifies as `new_story_file:theirs:`
- [ ] Tests `classify_conflict` condition `file_merged_in_earlier_wave`: file in progress[].filesChanged classifies as `shared_infrastructure:ours:`
- [ ] Tests `classify_conflict` no match: unknown file with no matching rule classifies as `unknown:escalate:`
- [ ] Tests rule ordering: file matching both `dependency_manifest` and `file_not_on_ours` uses `dependency_manifest` (earlier in rules array)
- [ ] Tests `classify_and_merge` clean merge: no conflicts, merges and commits, returns 0
- [ ] Tests `classify_and_merge` all resolved: 3 conflicts all classified as ours/theirs/regenerate, resolves all, commits, returns 0
- [ ] Tests `classify_and_merge` one escalates: 3 conflicts, 1 classifies as escalate, aborts merge, returns 1 with no partial state
- [ ] Tests `classify_and_merge` with no mergeStrategy in quantum.json: escalates all conflicts (backward-compatible default)
- [ ] All tests pass when run with `bash tests/test_merge_strategy.sh`
- [ ] Typecheck/lint passes (shellcheck)

---

### US-013: Add contractBreaking flag and fixes field to ql-plan

**Description:** As a planner, I want instructions to flag interface-breaking stories with `contractBreaking: true` and annotate stories with a `fixes` field listing which stories' regressions they resolve, so that the orchestrator can serialize contract-breaking stories and the known-failures module can infer `expectedFix` accurately.

**Acceptance Criteria:**
- [ ] `skills/ql-plan/SKILL.md` includes a new section "Interface Change Detection" that instructs the planner to:
  - Set `contractBreaking: true` on any story that changes the return type, parameter types, or signature of a function/class/interface consumed by other stories
  - Set `fixes: ["US-XXX"]` on any story that is explicitly designed to resolve regressions introduced by another story (e.g., a migration story that follows a breaking change)
- [ ] The section includes 2-3 examples showing when to flag `contractBreaking` and when to use `fixes`
- [ ] The section instructs the planner to add a comment in the story description when `contractBreaking: true` explaining what interface changes and which consumers are affected
- [ ] The section instructs that `contractBreaking` stories should NOT run in the same wave as their consumers — the planner should add explicit `dependsOn` edges if needed to prevent co-scheduling
- [ ] Typecheck/lint passes (shellcheck on any modified .sh files)

---

### US-014: Integrate all modules into orchestrator agent

**Description:** As an orchestrator, I want all 7 hardening module hook calls integrated into my execution flow at the correct lifecycle points (pre-wave, post-agent, post-merge, post-wave, agent spawn prompt), so that the modules are invoked automatically during `/ql-execute`.

**Acceptance Criteria:**
- [ ] `agents/orchestrator.md` Step 3B.1 (pre-wave) includes:
  - Call `cleanup_stale_worktrees()` before marking stories as in_progress
  - Call `pre_spawn_check()` before each agent spawn
  - Log: sourcing instructions for `lib/worktree.sh` with graceful fallback
- [ ] `agents/orchestrator.md` Step 3B.1 (pre-wave, before first wave only) includes:
  - Call `capture_baseline()` from known-failures.sh to establish test baseline
  - Log: `[KNOWN-FAILURES] Capturing baseline...`
- [ ] `agents/orchestrator.md` Step 3B.1 (pre-wave, every wave) includes:
  - Call `capture_wave_snapshot()` for waves 2+ to update known-failure state
- [ ] `agents/orchestrator.md` Step 3B.2 (spawn agents) includes:
  - Call `register_worktree()` after each worktree is created
  - Include output of `format_agent_context()` in the agent spawn prompt (the known-failures block)
- [ ] `agents/orchestrator.md` Step 3B.3 (merge) includes:
  - Replace the existing bare merge with a call to `classify_and_merge()` (via monitor.sh's updated `merge_worktree_branch()`)
  - After successful merge: call `delta_check()` from known-failures.sh
  - If `delta_check` returns non-zero (new regressions above flaky threshold): revert merge, mark story failed with `phase: "merge_regression"`
- [ ] `agents/orchestrator.md` post-wave includes:
  - Call `cleanup_merged_worktrees()` with the list of completed story IDs
- [ ] `agents/orchestrator.md` DAG query (Step 2) includes:
  - If a story has `contractBreaking: true` and any of its consumers are also eligible: hold the consumers to the next wave. Log: `[DAG] Held back US-XXX (consumer of contract-breaking US-YYY)`
- [ ] All module sourcing uses graceful fallback pattern: `source "$LIB_DIR/<module>.sh" 2>/dev/null || <MODULE>_AVAILABLE=false`
- [ ] Each module hook call is wrapped in an availability check: `if [[ "$<MODULE>_AVAILABLE" != "false" ]]; then ... fi`
- [ ] Step 5 (observations) includes module timing metrics section documenting wall-clock time for each module across all waves
- [ ] Typecheck/lint passes

---

### US-015: Integration tests for merge modules (M4, M1, M2)

**Description:** As a developer, I want integration tests that verify the merge strategy correctly delegates to barrel-regen and dep-manifest modules during actual git merge scenarios.

**Acceptance Criteria:**
- [ ] File exists at `tests/integration/test_merge_with_barrel.sh`
- [ ] Test sets up a git repo with two branches that both add exports to the same `index.ts` barrel file
- [ ] Merge via `classify_and_merge()` classifies the conflict as `barrel_export:regenerate`, barrel-regen produces output with BOTH sides' exports
- [ ] Final `index.ts` contains all exports from both branches, sorted alphabetically
- [ ] File exists at `tests/integration/test_merge_with_deps.sh`
- [ ] Test sets up a git repo with two branches: main has `package.json` with dep A, worktree branch adds dep B
- [ ] Merge via `classify_and_merge()` takes `--ours` for `package.json`, runs `npm install` (or mock equivalent)
- [ ] Final state: dep A preserved (not dropped), dep B available via installed source code imports
- [ ] Both test files pass when run with bash
- [ ] Typecheck/lint passes (shellcheck)

---

### US-016: Integration tests for known failures lifecycle (M5, M6)

**Description:** As a developer, I want integration tests that verify the full known-failures lifecycle: baseline capture, regression detection, known-failure passthrough, and resolution tracking.

**Acceptance Criteria:**
- [ ] File exists at `tests/integration/test_known_failures_lifecycle.sh`
- [ ] Test sets up a project with a test suite (simple script-based tests or mock jest/pytest output)
- [ ] Captures baseline (0 failures). Simulates a merge that introduces 3 test failures. `delta_check` detects them as NEW failures and returns non-zero. `capture_wave_snapshot` adds them to `knownFailures.current`
- [ ] Simulates a second merge (different story). `delta_check` sees the 3 failures as KNOWN and returns 0.
- [ ] Simulates a third merge that fixes the 3 failures. `capture_wave_snapshot` removes them from `current.failingTests`
- [ ] File exists at `tests/integration/test_known_failures_agent_context.sh`
- [ ] Captures baseline with 2 pre-existing failures. Verifies `format_agent_context()` returns a formatted block containing both test names
- [ ] Both test files pass when run with bash
- [ ] Typecheck/lint passes (shellcheck)

---

### US-017: Integration tests for worktree lifecycle and escalation retry (M7, M4)

**Description:** As a developer, I want integration tests that verify the worktree full lifecycle (register, cleanup) and the escalate-then-retry flow where a story fails due to merge escalation and succeeds on retry in the next wave.

**Acceptance Criteria:**
- [ ] File exists at `tests/integration/test_worktree_full_cycle.sh`
- [ ] Test registers 4 worktrees. Marks 2 stories as "passed". Calls `cleanup_merged_worktrees()` for the 2 completed stories. Verifies: 2 worktrees removed, 2 remain in `activeWorktrees`, `cleanedThisSession` is 2.
- [ ] Calls `cleanup_stale_worktrees()` — finds 0 stale (remaining 2 are "in_progress"). Verifies no additional removals.
- [ ] File exists at `tests/integration/test_escalate_then_retry.sh`
- [ ] Test sets up a merge scenario where one file has an unresolvable conflict (no matching rule, defaults to escalate). `classify_and_merge()` returns 1, merge is aborted.
- [ ] Simulates the retry: the previously conflicting content is already on HEAD (from the other story's merge). The retry merge has no conflicts. `classify_and_merge()` returns 0.
- [ ] Both test files pass when run with bash
- [ ] Typecheck/lint passes (shellcheck)

## 4. Functional Requirements

FR-1: The merge strategy module SHALL classify conflicting files by matching against an ordered rules array in `execution.mergeStrategy.rules`, where the first matching rule determines the resolution action.

FR-2: The merge strategy module SHALL support four resolution actions: `"ours"` (keep HEAD version), `"theirs"` (keep worktree branch version), `"regenerate"` (delegate to barrel-regen module), and `"escalate"` (abort merge, fail story for retry).

FR-3: The merge strategy module SHALL use `git merge --no-ff --no-commit` to inspect conflicts before committing, and `git merge --abort` if any file escalates, leaving no partial merge state.

FR-4: The barrel regeneration module SHALL scan directory contents after merge (not the git diff) to include all source files from both branches regardless of conflict resolution.

FR-5: The barrel regeneration module SHALL preserve lines marked with `// manual` or `# manual` comments, AND lines that do not match the auto-generated export pattern (fallback preservation).

FR-6: The barrel regeneration module SHALL skip non-pure barrels (files containing statements beyond imports/exports) and log a skip message.

FR-7: The dependency manifest module SHALL always use `git checkout --ours` for recognized manifest files during merge conflicts, preserving accumulated dependencies from earlier story merges.

FR-8: The dependency manifest module SHALL run the appropriate package install command after protecting the manifest, with a 120-second timeout.

FR-9: The dependency manifest module SHALL detect ALL package managers present in the project and run install for each independently.

FR-10: The worktree lifecycle functions SHALL be added to the existing `lib/worktree.sh` without changing the signatures or behavior of existing `create_worktree()`, `remove_worktree()`, `list_worktrees()` functions.

FR-11: The worktree tracking system SHALL register worktrees at spawn time and remove entries after merge or cleanup, maintaining an accurate count in `execution.worktreeTracking.activeWorktrees`.

FR-12: The `pre_spawn_check()` function SHALL trigger stale worktree cleanup if the active count equals `maxWorktrees`, before returning a slot-availability result.

FR-13: The known-failures module SHALL capture a test baseline before Wave 1 with pass/fail/skip counts and failing test names.

FR-14: The known-failures module SHALL update the failure snapshot after each wave, tracking which wave introduced each failure and which story is expected to fix it.

FR-15: The `delta_check()` function SHALL compare post-merge test results against the current known-failures snapshot, returning non-zero only if NEW failures appear above the `flakyThreshold`.

FR-16: The `format_agent_context()` function SHALL produce a human-readable block of known failing test names with metadata, suitable for inclusion in agent spawn prompts.

FR-17: The `expectedFix` field SHALL be populated from the story's `fixes` array (planner-annotated) when available, falling back to a heuristic (next dependent story touching same files), falling back to null.

FR-18: The planner SHALL flag stories that change shared interfaces with `contractBreaking: true`, and the orchestrator SHALL hold consumers of contract-breaking stories to the next wave.

FR-19: Every module SHALL log its wall-clock execution time for inclusion in the observations document.

FR-20: Every module SHALL degrade gracefully if absent — the orchestrator sources each script with a fallback flag and skips module calls when the flag indicates unavailability.

FR-21: All new quantum.json fields SHALL be optional — existing files without them trigger module-specific defaults or no-ops, not errors.

## 5. Non-Goals (Out of Scope)

- **Cross-session worktree cleanup.** This feature only cleans up worktrees created during the current `/ql-execute` session. Worktrees left over from previous sessions on different branches require manual cleanup or a separate housekeeping command.
- **Custom git merge drivers.** The merge strategy uses `git checkout --ours/--theirs` and barrel regeneration. It does not configure `.gitattributes` or custom merge drivers.
- **Non-git version control systems.** The merge strategy, worktree lifecycle, and known-failures modules assume git. Mercurial, SVN, and other VCS are not supported.
- **GUI or interactive merge resolution.** All conflict resolution is automated. If a conflict cannot be classified, the story is escalated (failed and retried), not presented to the user for manual resolution.
- **Test runner plugin development.** The known-failures module parses output from jest, vitest, pytest, and `go test`. Custom test runners or reporters require the user to configure `knownFailures.testCommand` manually (not implemented in this PRD).
- **Automatic retry budget adjustment.** If modules cause frequent escalations (story failures due to unresolvable conflicts), the retry budget (`retries.maxAttempts`) is not automatically increased. The user adjusts it manually.

## 6. Design Considerations

**File organization:** New scripts go in `lib/` following the existing pattern (source `common.sh`, export named functions, shellcheck-clean). Tests go in `tests/` (one file per module). Integration tests go in `tests/integration/` (new subdirectory).

**Existing code integration:** M7 extends `lib/worktree.sh` (answer 1A). M4 creates `lib/merge-strategy.sh` as a new file, and `lib/monitor.sh` calls into it (answer 2B — layered approach). All other modules are new standalone files.

**Barrel export preservation:** Uses a two-tier approach (answer 4D): explicit `// manual` markers are preserved first, then any remaining lines not matching the auto-gen pattern are preserved as fallback. This handles both intentionally marked lines and unexpected non-standard exports.

**Known-failures `expectedFix`:** Uses planner annotation when available (story `fixes` field), falls back to heuristic inference (answer 5D). The `fixes` field is set during `/ql-plan`, the heuristic runs at capture_wave_snapshot time.

## 7. Technical Considerations

**Performance:** All modules always run (answer 3A — correctness over speed). Each module logs wall-clock time so the observations document can report performance impact. If test suite runtime makes `delta_check` prohibitive (>60s), it automatically switches to affected-files-only mode. The observations doc flags modules that exceeded 10s total across all invocations.

**Windows compatibility:** The existing `lib/worktree.sh` already handles Windows file locking with retry logic. New lifecycle functions inherit this. `barrel-regen.sh` uses `find` and `sort` which work on Git Bash for Windows.

**Atomicity:** All quantum.json writes use the existing `lib/json-atomic.sh` pattern (Python or jq one-liner, single write) to prevent corruption from concurrent reads.

**Backward compatibility:** All 7 modules are strictly additive. An orchestrator without the new lib scripts falls back to today's behavior. A quantum.json without the new fields triggers module-specific no-ops.

**Dependencies between modules:** Two clusters: {M4, M1, M2} (merge strategy calls barrel-regen and dep-manifest) and {M5, M6} (delta check reads baseline from known-failures). M7 and M3 are independent. This maps to two parallel implementation tracks.

## 8. Success Metrics

- Zero manual merge conflict resolutions during a parallel execution run with 10+ stories (compare to ~20 in the post-mortem)
- Zero post-merge fix commits for barrel exports, dependency manifests, or interface cascades (compare to 4 in the post-mortem)
- Zero stale worktrees remaining after execution completes (compare to 62 in the post-mortem)
- Known-failures tracking accurately distinguishes pre-existing failures from new regressions in at least one multi-wave execution
- All 7 modules degrade gracefully — removing any single `lib/*.sh` file does not crash the orchestrator
- Module timing overhead is documented in the observations report for every execution

## 9. Open Questions

- Should barrel regeneration sort exports alphabetically or preserve filesystem order? Current decision: alphabetical for determinism across platforms.
- Should `flakyThreshold` be per-wave or global? Current decision: global. A per-wave threshold could adapt to increasingly flaky suites but adds complexity.
- What is the right timeout for `git worktree remove` retries on Windows? Current decision: 2s between retries, 3 max attempts. May need adjustment based on OneDrive sync behavior.
- Should the `tests/integration/` subdirectory be a new convention or should integration tests stay flat in `tests/`? Current decision: new subdirectory to distinguish unit from integration tests.

## Lifecycle Checklist

- [x] **First-run behavior:** First execution without `knownFailures`, `worktreeTracking`, or `mergeStrategy` in quantum.json — all modules detect absent fields and fall back to no-op or defaults. No initialization step required from the user.
- [x] **Returning-user behavior:** N/A — quantum-loop executions are independent. Each `/ql-execute` run initializes its own `execution.*` fields fresh. `knownFailures` is reset at baseline capture.
- [x] **Update behavior:** All new fields are optional and additive. Existing quantum.json files continue to work. The orchestrator's module-sourcing fallback pattern ensures an old orchestrator without new lib scripts still functions.
- [x] **Error recovery:** Each module degrades gracefully on failure: barrel-regen skips non-pure barrels, dep-manifest continues on install failure, worktree cleanup retries and skips on persistent failure, known-failures disables tracking on unparseable output, merge-strategy escalates unclassifiable conflicts.
- [x] **No-data/empty state:** No test suite detected → known-failures is disabled. No mergeStrategy → all conflicts escalate (today's behavior). No worktreeTracking → cleanup uses `git worktree list` fallback.
- [x] **Uninstall/disable:** Removing any `lib/*.sh` script triggers the orchestrator's graceful fallback (`source ... || MODULE_AVAILABLE=false`). No orphaned data — `execution.*` fields are transient runtime state, not persisted across runs.
