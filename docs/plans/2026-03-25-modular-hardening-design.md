# Design: Modular Hardening — 7 Independent Fixes for Parallel Execution Post-Mortem Issues

**Date:** 2026-03-25
**Status:** Approved
**Approach:** Modular Hardening (Approach B)
**Source:** `Logical_inference/docs/post-mortems/quantum-loop-multi-language-indexing-2026-03-25.md`
**Post-mortem issues addressed:** All 7 — barrel file conflicts (#1), dependency file re-creation (#2), npm install state (#3), stale worktree accumulation (#4), interface cascade (#5), merge strategy formalization (#6), pre-existing failures tracking (#7)

## Design Parameters

| Decision | Choice |
|---|---|
| Scope | All 7 post-mortem issues in a single design/spec/execution cycle |
| Barrel files | `fileConflicts` prevention (DAG intelligence) + auto-regenerate barrels as post-merge safety net |
| Dependency management | Language-agnostic — detect npm/pip/poetry/go mod/cargo |
| Worktree cleanup | Focus on current-run cleanup (long single sessions) |
| Known failures | Hybrid — delta-based for orchestrator merge decisions + named failures passed to agents as context |
| Architecture | 7 independent modules plugged into existing orchestrator hook points |

## Overview

**What we're building:** Seven independent hardening modules that plug into the existing quantum-loop orchestrator at defined hook points, addressing all issues from the 2026-03-25 multi-language indexing post-mortem: barrel file auto-regeneration, dependency manifest protection, worktree lifecycle management, formalized merge strategy, known-failures tracking, interface cascade prevention, and dependency file re-creation guards.

**Why:** The multi-language indexing execution (22 stories, 6 waves, 4 concurrent agents) succeeded — 100% first-attempt pass rate — but required ~20 manual merge conflict resolutions, 4 post-merge fix commits, and 1 post-execution fix. The orchestrator currently has no automated handling for these recurring patterns. Each execution accumulates the same manual intervention debt. These 7 modules eliminate that debt.

**How it fits into existing architecture:**

| Hook Point | Modules |
|---|---|
| Pre-wave (before agent spawn) | M5: Known-failures snapshot, M7: Worktree cleanup |
| Post-agent (after agent completes, before merge) | M4: Category-based merge strategy |
| Post-merge (after successful merge) | M1: Barrel auto-regeneration, M2: Dependency manifest protection, M6: Known-failures delta check |
| Post-wave (after all agents in wave finish) | M7: Worktree cleanup (merged), M3: Interface cascade guard (extends existing L5 audit) |

**Files involved:** `lib/barrel-regen.sh` (new), `lib/dep-manifest.sh` (new), `lib/merge-strategy.sh` (new), `lib/known-failures.sh` (new), `lib/worktree-lifecycle.sh` (new), `agents/orchestrator.md` (modified — 7 new hook calls), `quantum.json.example` (modified — new execution fields), `skills/ql-plan/SKILL.md` (modified — `contractBreaking` flag).

## User Experience

### What changes for the user during `/ql-execute`

The user's workflow remains `/ql-plan` -> review -> `/ql-execute`. No new commands or configuration. The 7 modules surface through new log messages at existing lifecycle points.

### New log messages by phase

**Pre-wave:**
```
[WORKTREE] Cleaned 8 stale worktrees from previous waves (62 -> 54)
[WORKTREE] Active: 0, Limit: 4, Available slots: 4

[KNOWN-FAILURES] Capturing baseline test snapshot for Wave 3...
[KNOWN-FAILURES] Baseline: 648 pass, 5 fail, 2 skip
[KNOWN-FAILURES] Known failing tests: test_import_analyzer[alias], test_import_analyzer[circular], ...
```

**Post-agent (merge phase):**
```
[MERGE-STRATEGY] US-014 merge — classifying 4 conflicting files:
  package.json          -> OURS (dependency manifest)
  parsers/index.ts      -> REGENERATE (barrel export)
  src/CppParser.ts      -> THEIRS (new story file)
  GrammarLoader.ts      -> OURS (shared infrastructure, merged in Wave 1)
[MERGE-STRATEGY] Resolved 4 conflicts automatically

[BARREL-REGEN] Regenerated parsers/index.ts (7 exports)
[BARREL-REGEN] Regenerated analyzers/index.ts (5 exports)

[DEP-MANIFEST] package.json preserved (--ours). Running post-merge install...
[DEP-MANIFEST] npm install completed (added 2 packages: tree-sitter-cpp, tree-sitter-java)
```

**Post-merge (known-failures delta):**
```
[KNOWN-FAILURES] Post-merge delta for US-014: 648 pass (+0), 5 fail (+0), 2 skip (+0)
[KNOWN-FAILURES] No new failures introduced — PASS

[KNOWN-FAILURES] Post-merge delta for US-003: 640 pass (-8), 13 fail (+8), 2 skip (+0)
[KNOWN-FAILURES] 8 NEW failures detected (not in baseline):
  test_python_parser[class_def], test_python_parser[async_func], ...
[KNOWN-FAILURES] These are EXPECTED — US-004 will fix them (interface change story)
```

**Post-wave:**
```
[WORKTREE] Removing 4 merged worktrees from Wave 3...
[WORKTREE] Active: 0, Total removed this session: 12
```

### New failure mode

```
[MERGE-STRATEGY] US-028 — conflict on src/shared/types/index.ts
  Category: BARREL (auto-regenerable)
  Action: Regenerated barrel with both sides' exports
  Result: SUCCESS (no manual intervention needed)
```

Compare to today, where the orchestrator either silently takes `--theirs`/`--ours` (risking data loss) or escalates every conflict. The merge strategy now makes an informed, category-based decision.

### Information passed to agents

Agents receive one new block in their spawn prompt:

```
Known failing tests (pre-existing, not caused by your story):
  - test_import_analyzer[alias] (failing since Wave 1, expected fix: US-004)
  - test_import_analyzer[circular] (failing since Wave 1, expected fix: US-004)
If you see ONLY these failures, they are not your fault — proceed normally.
If you see NEW failures not on this list, they ARE your responsibility — fix them.
```

This is informational context, not a hard gate. The orchestrator's delta-based check is the enforcement mechanism.

## Data Model

### quantum.json Schema Changes

Three new fields in the `execution` object, plus a new top-level `knownFailures` field.

#### New: `execution.worktreeTracking`

Tracks active worktrees for cleanup. Written by the orchestrator at spawn and merge time.

```json
"execution": {
  "worktreeTracking": {
    "activeWorktrees": [
      {
        "path": ".ql-wt/US-014",
        "branch": "ql-wt-US-014",
        "storyId": "US-014",
        "createdAt": "2026-03-25T10:30:00Z",
        "wave": 3
      }
    ],
    "cleanedThisSession": 12,
    "maxWorktrees": 4
  }
}
```

| Field | Type | Description |
|---|---|---|
| `activeWorktrees[]` | array | Currently live worktrees. Entries added at spawn, removed after merge+cleanup. |
| `cleanedThisSession` | number | Running count of worktrees removed during this execution. For observability. |
| `maxWorktrees` | number | Mirrors `maxParallel`. Cleanup triggers when `activeWorktrees.length` approaches this. |

#### New: `execution.mergeStrategy`

Configurable per-file-category merge rules. Auto-populated with sensible defaults, user can override in quantum.json before execution.

```json
"execution": {
  "mergeStrategy": {
    "rules": [
      {"category": "dependency_manifest", "pattern": "package.json|package-lock.json|Cargo.toml|Cargo.lock|pyproject.toml|poetry.lock|go.mod|go.sum|requirements*.txt", "action": "ours", "postAction": "install"},
      {"category": "barrel_export", "pattern": "**/index.ts|**/index.js|**/__init__.py|**/mod.rs", "action": "regenerate"},
      {"category": "new_story_file", "pattern": null, "action": "theirs", "condition": "file_not_on_ours"},
      {"category": "shared_infrastructure", "pattern": null, "action": "ours", "condition": "file_merged_in_earlier_wave"},
      {"category": "contract_stub", "pattern": null, "action": "theirs", "condition": "file_in_materializedContracts"}
    ],
    "defaultAction": "escalate"
  }
}
```

| Field | Type | Description |
|---|---|---|
| `rules[]` | array | Ordered list of merge rules. First match wins. |
| `rules[].category` | string | Human-readable label for logging |
| `rules[].pattern` | string or null | Glob/regex for filename matching. `null` means the rule uses `condition` instead. |
| `rules[].action` | enum | `"ours"`, `"theirs"`, `"regenerate"`, `"escalate"` |
| `rules[].postAction` | string or null | Optional command to run after merge: `"install"` triggers dependency install |
| `rules[].condition` | string or null | Semantic condition when `pattern` is null. Evaluated by the orchestrator at merge time. |
| `defaultAction` | string | What to do when no rule matches. `"escalate"` = fail story and retry next wave. |

#### New: `knownFailures`

Top-level field (sibling to `stories`, `contracts`, etc.) tracking test failures across waves.

```json
"knownFailures": {
  "baseline": {
    "capturedAt": "2026-03-25T10:00:00Z",
    "wave": 0,
    "passCount": 295,
    "failCount": 0,
    "skipCount": 2,
    "failingTests": []
  },
  "current": {
    "updatedAt": "2026-03-25T12:30:00Z",
    "wave": 3,
    "passCount": 640,
    "failCount": 8,
    "skipCount": 2,
    "failingTests": [
      {
        "name": "test_import_analyzer[alias]",
        "failingSince": 2,
        "introducedBy": "US-003",
        "expectedFix": "US-004",
        "error": "TypeError: parse() returned Promise, expected AST"
      }
    ]
  },
  "flakyThreshold": 1,
  "fullSuiteTimeout": 60
}
```

| Field | Type | Description |
|---|---|---|
| `baseline` | object | Snapshot taken before Wave 1. Represents the "clean" state of the branch. |
| `baseline.failingTests[]` | string[] | Test names already failing before quantum-loop started. |
| `current` | object | Updated after each merge. Represents the running state. |
| `current.failingTests[]` | array | Each entry tracks: test name, which wave it started failing, which story introduced it, which story is expected to fix it (if known from the DAG). |
| `current.failingTests[].expectedFix` | string or null | Story ID that the orchestrator infers will fix this test based on dependency analysis. `null` if unknown. |
| `flakyThreshold` | number | Number of new failures below which delta check treats as noise. Default: 1. |
| `fullSuiteTimeout` | number | Seconds. If full test suite exceeds this, `delta_check` runs only affected test files. Default: 60. |

**Delta check logic:** After each merge, the orchestrator compares `current.failCount` to `previous.failCount`. If `failCount` increases AND the new failing tests are NOT in `current.failingTests` (i.e., they weren't already known), the merge introduced regressions.

#### No changes to existing fields

`stories`, `contracts`, `progress`, `codebasePatterns`, `fileConflicts`, `coverageThreshold`, `staleThresholdMinutes` — all unchanged. The new modules read these but don't modify their schema.

#### Backward compatibility

All new fields are optional. An existing quantum.json without `knownFailures`, `execution.worktreeTracking`, or `execution.mergeStrategy` works as today — modules degrade gracefully:
- No `mergeStrategy` -> falls back to current behavior (`escalate` for all conflicts)
- No `knownFailures` -> agents don't receive known-failure context, delta check is skipped
- No `worktreeTracking` -> cleanup uses `git worktree list` as fallback (less precise but functional)

## Architecture

### Module Overview

Seven modules, each a standalone shell script in `lib/`, called from the orchestrator at defined hook points.

```
Pre-wave phase
  +-- M7: lib/worktree-lifecycle.sh -> cleanup_stale_worktrees()
  +-- M5: lib/known-failures.sh     -> capture_baseline() | capture_wave_snapshot()
  +-- (existing) lib/materialize.sh  -> materialize_contracts()

Agent execution phase
  +-- (unchanged — agents spawned with known-failures context in prompt)

Post-agent phase (per completed agent, before review gate)
  +-- M4: lib/merge-strategy.sh      -> classify_and_merge()
  +-- M1: lib/barrel-regen.sh        -> regenerate_barrels()
  +-- M2: lib/dep-manifest.sh        -> protect_and_install()
  +-- M6: lib/known-failures.sh      -> delta_check()
  +-- (existing) lib/monitor.sh      -> post_merge_typecheck()
  +-- (existing) orchestrator inline -> review gate (3A.5 / 3B.4)

Post-wave phase
  +-- M7: lib/worktree-lifecycle.sh -> cleanup_merged_worktrees()
  +-- (existing) lib/type-audit.sh  -> audit_wave_types()
  +-- (existing) orchestrator       -> integration check (3C)
```

### Module Details

#### M1: `lib/barrel-regen.sh` — Barrel Auto-Regeneration

Called after each successful merge when the merge touched a barrel/index file.

```
barrel-regen.sh
+-- detect_barrel_files(repo_root)
|   +-- Scans for: **/index.ts, **/index.js, **/__init__.py, **/mod.rs
|   +-- Returns: array of barrel file paths
+-- regenerate_barrel(barrel_path, language)
|   +-- TS/JS: scan directory for .ts/.js files (excluding index),
|   |         generate "export * from './Filename'" for each
|   +-- Python: scan directory for .py files (excluding __init__),
|   |          generate "from .module import *" for each
|   +-- Rust: scan directory for .rs files (excluding mod),
|   |         generate "pub mod filename;" for each
|   +-- Preserves: manual exports not matching auto-gen pattern
|         (lines with comments like "// manual" are kept)
+-- should_regenerate(barrel_path, merge_diff)
    +-- Returns true if barrel_path appears in conflict files
```

**Key design decision:** Regeneration scans the *directory contents after merge*, not the git diff. This means both sides' new files are included regardless of how the conflict was resolved. Manual exports (marked with a comment) are preserved.

#### M2: `lib/dep-manifest.sh` — Dependency Manifest Protection

Called after merge when a dependency manifest was in the conflict set.

```
dep-manifest.sh
+-- detect_package_manager(repo_root)
|   +-- package.json       -> npm/yarn/pnpm
|   +-- Cargo.toml         -> cargo
|   +-- pyproject.toml     -> pip/poetry
|   +-- go.mod             -> go
|   +-- requirements*.txt  -> pip
+-- protect_manifest(repo_root, conflict_files)
|   +-- For each manifest in conflict_files:
|   |   git checkout --ours <manifest>
|   |   git add <manifest>
|   +-- Log: "[DEP-MANIFEST] Protected <file> with --ours"
+-- run_install(repo_root, package_manager)
|   +-- npm/yarn/pnpm -> npm install / yarn install / pnpm install
|   +-- cargo         -> cargo fetch
|   +-- pip/poetry    -> pip install -e . / poetry install
|   +-- go            -> go mod tidy
|   +-- Timeout: 120s (configurable)
+-- verify_lockfile(repo_root)
    +-- Checks lockfile exists and is non-empty after install
```

**Why `--ours` for manifests:** The main branch has accumulated dependencies from all previously merged stories. The worktree branch may have a stale snapshot. Taking `--ours` preserves all accumulated deps, then `run_install()` picks up any new deps the agent's story needs (they're in the merged source code's import statements, so the install resolves them).

#### M3: Interface Cascade Guard

This extends the existing contract system rather than being a new module. Added to `agents/orchestrator.md` as planning-time metadata:

- During `/ql-plan`, stories that change shared interfaces are flagged with `"contractBreaking": true`
- The orchestrator serializes contract-breaking stories with their immediate consumers (they run in adjacent waves, not the same wave)
- Stories with `contractBreaking: true` add their updated interface to `contracts.shared_types` as part of their commit, so the next wave's materialization picks it up

This is a metadata annotation + scheduling rule, not a separate script.

#### M4: `lib/merge-strategy.sh` — Category-Based Merge Strategy

The core merge module. Called instead of the current bare `git merge` for every agent merge.

```
merge-strategy.sh
+-- classify_conflict(file_path, merge_context)
|   +-- Check mergeStrategy.rules in order (first match wins):
|   |   1. Pattern match against file_path
|   |   2. Condition evaluation (file_not_on_ours, file_merged_in_earlier_wave)
|   |   3. Default action if no rule matches
|   +-- Returns: {category, action, postAction}
+-- resolve_conflict(file_path, classification)
|   +-- "ours"       -> git checkout --ours <file> && git add <file>
|   +-- "theirs"     -> git checkout --theirs <file> && git add <file>
|   +-- "regenerate" -> delegate to barrel-regen.sh or similar
|   +-- "escalate"   -> abort merge, fail story
+-- classify_and_merge(worktree_branch, repo_root, json_path)
|   +-- Attempt: git merge <branch> --no-commit
|   +-- If clean merge: git commit, return success
|   +-- If conflicts:
|   |   1. List conflicting files: git diff --name-only --diff-filter=U
|   |   2. For each: classify_conflict() -> resolve_conflict()
|   |   3. If any file escalated: git merge --abort, return failure
|   |   4. If all resolved: git commit, return success
|   +-- Log every classification decision
+-- get_merge_context(json_path)
    +-- Reads execution.materializedContracts (for contract_stub condition)
    +-- Reads progress[] (for file_merged_in_earlier_wave condition)
    +-- Returns context object for condition evaluation
```

**Why `--no-commit`:** This lets us inspect conflicts before committing. If any file escalates, we abort cleanly with no partial merge state.

#### M5 + M6: `lib/known-failures.sh` — Known Failures Tracking

Single script with two entry points: pre-wave snapshot and post-merge delta check.

```
known-failures.sh
+-- capture_baseline(repo_root, json_path)
|   +-- Run full test suite, parse output for pass/fail/skip counts
|   +-- Extract failing test names (pytest: from -v output; jest: from --verbose)
|   +-- Write to knownFailures.baseline in quantum.json
|   +-- Called once before Wave 1
+-- capture_wave_snapshot(repo_root, json_path, wave_num)
|   +-- Run full test suite, parse output
|   +-- Update knownFailures.current
|   +-- For each NEW failure (not in previous snapshot):
|   |   - Identify introducing story from git blame on the test's dependency
|   |   - Infer expectedFix from DAG (story that depends on introducer + touches same files)
|   +-- Called at start of each wave (after previous wave merges)
+-- delta_check(repo_root, json_path, story_id)
|   +-- Run full test suite after a single merge
|   +-- Compare fail count to knownFailures.current
|   +-- If new failures found:
|   |   - Check if they appear in current.failingTests (known)
|   |   - If known: PASS with log "[KNOWN-FAILURES] N known failures present"
|   |   - If unknown: FAIL with log listing new failure names
|   +-- Returns: {passed: bool, newFailures: string[], knownFailures: string[]}
+-- format_agent_context(json_path)
|   +-- Reads knownFailures.current.failingTests
|   +-- Returns formatted string block for agent spawn prompt
+-- detect_test_runner(repo_root)
    +-- jest/vitest  -> parse --verbose JSON output
    +-- pytest       -> parse -v output or --tb=short
    +-- go test      -> parse -v output
    +-- Returns: {runner, parseCommand}
```

**Performance concern:** Running the full test suite after every single merge could be slow. Mitigation: if the test suite takes >60s, `delta_check` runs only the test files that import from files changed in the merge (using dependency tracing from import statements). Full suite runs at wave-end only.

#### M7: `lib/worktree-lifecycle.sh` — Worktree Lifecycle Management

Handles cleanup at two points: pre-wave (stale from previous waves) and post-wave (just-merged).

```
worktree-lifecycle.sh
+-- cleanup_stale_worktrees(json_path, repo_root)
|   +-- Read execution.worktreeTracking.activeWorktrees
|   +-- For each: check if story status is "passed" or "failed"
|   |   (story finished but worktree wasn't cleaned — stale)
|   +-- For stale entries:
|   |   git worktree remove --force <path>
|   |   git branch -d <branch> 2>/dev/null
|   |   Remove entry from activeWorktrees
|   +-- Fallback (no tracking data): git worktree list --porcelain
|   |   Match paths containing ".ql-wt/", remove those not in active stories
|   +-- Update cleanedThisSession counter
+-- cleanup_merged_worktrees(json_path, repo_root, completed_story_ids)
|   +-- For each story that just completed (passed or failed):
|   |   git worktree remove <path>
|   |   git branch -d <branch>
|   |   Remove from activeWorktrees
|   +-- Called at wave-end after all merges
+-- register_worktree(json_path, story_id, path, branch, wave)
|   +-- Add entry to activeWorktrees (called at spawn time)
+-- pre_spawn_check(json_path, max_worktrees)
    +-- If activeWorktrees.length >= max_worktrees:
    |   Run cleanup_stale_worktrees() first
    +-- If still at limit: log warning, wait for a slot
    +-- Returns: true if a slot is available
```

**Why `--force` for stale cleanup:** Stale worktrees may have uncommitted changes from crashed agents. Since the story already failed/passed (merged from another path), the worktree contents are irrelevant. Force removal is safe.

### Changes to Existing Files

| File | Change | Details |
|---|---|---|
| `agents/orchestrator.md` | Add 7 hook calls | Insert calls at pre-wave, post-agent, post-wave phases. ~30 lines of new pseudocode. |
| `agents/orchestrator.md` | Modify agent spawn prompt | Add `format_agent_context()` output to the known-failures block. |
| `agents/orchestrator.md` | Modify Step 3B.3 merge | Replace bare `git merge` with `classify_and_merge()`. |
| `quantum.json.example` | Add new fields | `knownFailures`, `execution.worktreeTracking`, `execution.mergeStrategy` with documented defaults. |
| `skills/ql-plan/SKILL.md` | Add `contractBreaking` flag | Instruct planner to flag interface-changing stories. |

### Dependency Between Modules

```
M4 (merge-strategy) --depends-on--> M1 (barrel-regen)     [calls regenerate for "regenerate" action]
M4 (merge-strategy) --depends-on--> M2 (dep-manifest)     [calls protect_and_install for "install" postAction]
M6 (delta-check)    --depends-on--> M5 (baseline capture)  [reads knownFailures written by M5]
M7 (worktree)       --independent
M3 (interface guard) --independent  [metadata only, no script]
```

Only two dependency clusters: {M4, M1, M2} and {M5, M6}. These map naturally to two parallel implementation tracks.

## Edge Cases & Error Handling

### M1: Barrel regeneration edge cases

**Non-standard barrel files.** Some projects have barrel files with logic beyond re-exports (e.g., `index.ts` that applies decorators, wraps exports in a namespace, or conditionally exports based on environment).

**Handling:** `regenerate_barrel()` checks if the file contains any non-export statements (import/export only = pure barrel). If non-export content is found, skip regeneration and log: `[BARREL-REGEN] SKIP <file> — contains non-export logic, manual resolution needed`. Fall through to the merge strategy's `defaultAction` (escalate). This avoids destroying hand-written logic.

**Empty directories after merge.** If a story deletes a file that was the only export in a barrel, regeneration produces an empty barrel.

**Handling:** If the regenerated barrel would have 0 exports, write an empty file with a comment: `// No exports — directory is empty`. This is valid syntax in all supported languages and avoids breaking upstream imports that reference the barrel (they'll get empty imports, which is a lint issue but not a crash).

### M2: Dependency install failures

**Install command fails.** The agent's story added a dependency that doesn't exist in the registry, or there's a version conflict.

**Handling:** `run_install()` captures exit code and stderr. On failure:
1. Log: `[DEP-MANIFEST] Install failed: <stderr snippet>`
2. Do NOT fail the story — the install failure is likely because the agent added a dep that conflicts with `--ours` resolution
3. Attempt recovery: `git checkout --theirs <manifest>` for just the `dependencies`/`devDependencies` section, re-run install
4. If recovery also fails: log warning, continue. The post-merge test suite will catch missing deps as import errors.

**Multiple package managers.** A monorepo might have both `package.json` and `pyproject.toml`.

**Handling:** `detect_package_manager()` returns ALL detected managers, not just the first. `run_install()` runs each in sequence. Each is independent — a Python install failure doesn't block a Node install.

### M4: Merge strategy — condition evaluation ambiguity

**`file_merged_in_earlier_wave` — how to determine this.** The condition requires knowing if a file was touched by a previously merged story in this execution.

**Handling:** Scan `progress[]` entries for `filesChanged` arrays. Build a set of all files modified in earlier waves. If the conflicting file is in this set, the condition matches. If `progress[]` doesn't have `filesChanged` (older quantum.json format), fall back to `git log --name-only <first_wave_sha>..HEAD` to reconstruct the list.

**`file_not_on_ours` — file exists in theirs but not ours.** Straightforward: `git ls-tree HEAD -- <file>` returns nothing.

**Handling:** If the file doesn't exist on HEAD but does on the worktree branch, this is a new file from the story. Action: `theirs`. Edge case: two parallel stories both create the same new file (neither is on HEAD). Both match `file_not_on_ours`. The first to merge takes `theirs`. The second to merge sees the file NOW exists on HEAD — condition no longer matches, falls through to `defaultAction: escalate`. This is correct behavior — the second story's version needs manual reconciliation or retry.

**Rule ordering conflicts.** A file might match multiple rules (e.g., `package.json` matches both `dependency_manifest` and `file_not_on_ours` if it was just created).

**Handling:** First match wins. The `rules` array is ordered by specificity — `dependency_manifest` (pattern-based) comes before `new_story_file` (condition-based). The user can reorder rules in quantum.json if needed.

### M5/M6: Known failures — test output parsing

**Unparseable test output.** The test runner produces output in an unexpected format (custom reporter, non-standard flags).

**Handling:** `detect_test_runner()` tries structured output first (jest `--json`, pytest `--tb=line -q`). If parsing fails (JSON parse error or unexpected format):
1. Fall back to regex: count lines matching `FAIL`, `PASS`, `ERROR`
2. If regex also fails: set `knownFailures.current = null` and log `[KNOWN-FAILURES] Could not parse test output — delta check disabled for this wave`
3. Delta check becomes a no-op. The system degrades to today's behavior (no known-failure tracking).

**Test suite is non-deterministic.** Flaky tests appear and disappear between runs, making delta checks unreliable.

**Handling:** The delta check uses a threshold: if `newFailureCount <= flakyThreshold` (default: 1), treat it as noise and PASS with a warning: `[KNOWN-FAILURES] 1 new failure — below flaky threshold, treating as noise`. For the post-mortem's flaky property-based test (#2 in issues), this means it won't trigger false merge rejections.

**Test suite takes too long for per-merge delta checks.**

**Handling:** If the full suite takes >60s (configurable via `fullSuiteTimeout`), `delta_check()` runs only affected test files (files importing from changed modules). The full suite runs at wave-end only.

### M6: Known failures — `expectedFix` inference

**The inferred `expectedFix` story is wrong.** The orchestrator guesses US-004 will fix the failures introduced by US-003, but US-004 doesn't actually fix them.

**Handling:** `expectedFix` is advisory only — it's passed to agents as context but doesn't affect the delta check logic. If US-004 merges and the failures persist, the delta check sees `failCount` didn't decrease but also didn't increase (same known failures). It passes. The failures remain in `current.failingTests` with `expectedFix` cleared to `null`. The post-wave observations document flags them as unresolved: `[KNOWN-FAILURES] 3 failures remain unresolved after expected fix story US-004 merged`.

### M7: Worktree cleanup — concurrent access

**Orchestrator tries to remove a worktree while an agent is still writing.**

**Handling:** `cleanup_merged_worktrees()` is only called at wave-end, after ALL agents have completed (passed or failed) and their output has been collected. This is the existing synchronization point (Step 3C). An agent that is still running is by definition still in the current wave — its worktree won't be in the `completed_story_ids` list. `cleanup_stale_worktrees()` (pre-wave) only removes worktrees whose story status is `passed` or `failed` — an `in_progress` story's worktree is never touched.

**`git worktree remove` fails.** The worktree directory is locked by another process (antivirus, IDE indexer, etc.).

**Handling:** On failure, retry once after 2 seconds. If still fails: log `[WORKTREE] Could not remove <path> — skipping (will retry next wave)`. Leave the entry in `activeWorktrees`. The `pre_spawn_check()` at next wave will try again. After 3 failed removal attempts for the same worktree, log a user-visible warning: `[WORKTREE] WARNING: <path> could not be removed after 3 attempts. Manual cleanup may be needed.`

### Cross-module: Module load failure

**A `lib/*.sh` script doesn't exist or has a syntax error.**

**Handling:** The orchestrator sources each script with error checking:
```bash
if ! source "$PLUGIN_ROOT/lib/merge-strategy.sh" 2>/dev/null; then
    log "[WARN] merge-strategy.sh not available — using default merge behavior"
fi
```
Each module's absence degrades to today's behavior. No module is required for basic execution to work. This matches the existing pattern where `lib/materialize.sh` and `lib/type-audit.sh` are optional enhancements.

## Testing Strategy

### Test Organization

Tests follow the existing pattern: shell-based tests in `tests/`, one file per module, plus integration tests for cross-module interactions.

### Tier 1: Unit Tests

**M1: `tests/test_barrel_regen.sh`**

| Test | Input | Expected |
|---|---|---|
| TS barrel with 3 `.ts` files in directory | Directory containing `Foo.ts`, `Bar.ts`, `Baz.ts` | Generated `index.ts` with 3 `export * from` lines, sorted alphabetically |
| Python barrel with 2 `.py` files | Directory containing `foo.py`, `bar.py` | Generated `__init__.py` with 2 `from .module import *` lines |
| Barrel with manual exports preserved | Existing `index.ts` with `export { custom } from './special' // manual` | Regenerated file keeps the `// manual` line, adds auto-generated lines |
| Non-pure barrel skipped | `index.ts` containing `const config = ...` beyond exports | Returns skip, logs "contains non-export logic" |
| Empty directory | Directory with no source files | Writes barrel with `// No exports` comment |
| `should_regenerate` returns false | Barrel not in merge conflict file list | Returns false, no regeneration |

**M2: `tests/test_dep_manifest.sh`**

| Test | Input | Expected |
|---|---|---|
| `detect_package_manager` — npm | Repo with `package.json` | Returns `"npm"` |
| `detect_package_manager` — multiple | Repo with `package.json` + `pyproject.toml` | Returns `["npm", "pip"]` |
| `detect_package_manager` — none | Repo with no manifest files | Returns empty array |
| `protect_manifest` — single conflict | `package.json` in conflict list | Runs `git checkout --ours package.json`, adds file |
| `run_install` — npm success | Valid `package.json` | Runs `npm install`, returns 0 |
| `run_install` — npm failure with recovery | Install fails, `--theirs` deps section works | Recovers, returns 0 with warning |
| `run_install` — timeout | Install takes >120s | Killed, logged, returns non-zero |
| `verify_lockfile` — exists | `package-lock.json` present and non-empty | Returns 0 |

**M4: `tests/test_merge_strategy.sh`**

| Test | Input | Expected |
|---|---|---|
| `classify_conflict` — pattern match | `package.json` against default rules | Returns `{category: "dependency_manifest", action: "ours", postAction: "install"}` |
| `classify_conflict` — barrel match | `src/parsers/index.ts` | Returns `{category: "barrel_export", action: "regenerate"}` |
| `classify_conflict` — condition: new file | File not on HEAD, exists on worktree branch | Returns `{category: "new_story_file", action: "theirs"}` |
| `classify_conflict` — condition: shared infra | File in `progress[].filesChanged` from earlier wave | Returns `{category: "shared_infrastructure", action: "ours"}` |
| `classify_conflict` — no match | Unknown file, no rule matches | Returns `{category: "unknown", action: "escalate"}` |
| `classify_and_merge` — clean merge | No conflicts | Merges and commits, returns 0 |
| `classify_and_merge` — all resolved | 3 conflicts, all classified as ours/theirs/regenerate | Resolves all, commits, returns 0 |
| `classify_and_merge` — one escalates | 3 conflicts, 1 classifies as escalate | Aborts merge, returns 1, no partial state |
| Rule ordering — first match wins | File matches both `dependency_manifest` and `file_not_on_ours` | Uses `dependency_manifest` (earlier in rules) |

**M5/M6: `tests/test_known_failures.sh`**

| Test | Input | Expected |
|---|---|---|
| `capture_baseline` — clean suite | 100 pass, 0 fail | Writes baseline with `failCount: 0`, empty `failingTests` |
| `capture_baseline` — pre-existing failures | 95 pass, 5 fail | Writes baseline with `failCount: 5`, 5 entries in `failingTests` |
| `capture_wave_snapshot` — no change | Same pass/fail counts as baseline | Updates `current`, no new entries |
| `capture_wave_snapshot` — new failures | 3 new failures vs previous snapshot | Adds 3 entries with `failingSince`, inferred `introducedBy` |
| `delta_check` — no regressions | Fail count unchanged after merge | Returns `{passed: true}` |
| `delta_check` — known failures present | 5 failures, all in `current.failingTests` | Returns `{passed: true, knownFailures: [...]}` |
| `delta_check` — new regression | 1 unknown failure not in `current.failingTests` | Returns `{passed: false, newFailures: [...]}` |
| `delta_check` — flaky threshold | 1 new failure, `flakyThreshold: 1` | Returns `{passed: true}` with flaky warning |
| `format_agent_context` — with known failures | 3 entries in `current.failingTests` | Formatted string block listing test names and expected fixes |
| `format_agent_context` — empty | No known failures | Returns empty string (no block added to prompt) |
| `detect_test_runner` — jest | `package.json` with jest config | Returns `{runner: "jest", parseCommand: "npx jest --json"}` |
| `detect_test_runner` — pytest | `pyproject.toml` with pytest section | Returns `{runner: "pytest", parseCommand: "pytest -v --tb=line -q"}` |
| Unparseable output fallback | Garbled test output | Sets `current = null`, logs warning, delta check becomes no-op |

**M7: `tests/test_worktree_lifecycle.sh`**

| Test | Input | Expected |
|---|---|---|
| `cleanup_stale_worktrees` — 2 stale | 2 worktrees whose stories are `passed` | Both removed, `cleanedThisSession += 2` |
| `cleanup_stale_worktrees` — none stale | All tracked worktrees for `in_progress` stories | No removals |
| `cleanup_stale_worktrees` — no tracking data | `worktreeTracking` absent | Falls back to `git worktree list`, removes `.ql-wt/` entries |
| `cleanup_merged_worktrees` — 3 completed | 3 story IDs that just passed/failed | All 3 worktrees removed, entries cleared |
| `register_worktree` | Story ID, path, branch, wave | Entry added to `activeWorktrees` |
| `pre_spawn_check` — slots available | 2 active, max 4 | Returns true |
| `pre_spawn_check` — at limit | 4 active, max 4 | Runs stale cleanup first, then re-checks |
| `git worktree remove` fails | Locked worktree | Retry once, then skip with warning. Entry stays in tracking. |
| 3 consecutive removal failures | Same worktree fails 3 times across waves | User-visible warning logged |

**M3: Interface cascade guard** — No standalone test file. Tested via planner output validation:

| Test | Input | Expected |
|---|---|---|
| Story with interface change flagged | Planner sees `parse()` return type change | Story gets `contractBreaking: true` in quantum.json |
| Contract-breaking story serialized | US-003 (`contractBreaking`) and US-005 (consumer) both eligible | US-003 scheduled in Wave N, US-005 held to Wave N+1 |

### Tier 2: Integration Tests

| Test file | Modules | Scenario |
|---|---|---|
| `tests/integration/test_merge_with_barrel.sh` | M4 -> M1 | Merge strategy classifies `index.ts` as `regenerate`, barrel-regen produces correct output with both sides' exports |
| `tests/integration/test_merge_with_deps.sh` | M4 -> M2 | Merge strategy takes `--ours` for `package.json`, dep-manifest runs install, new deps from merged story resolved |
| `tests/integration/test_known_failures_lifecycle.sh` | M5 -> M6 | Baseline captured before Wave 1. US-003 introduces 8 failures. Delta check after US-003 merge detects them as new. Snapshot updated. Delta check after US-014 merge sees them as known. US-004 merges, failures resolve, snapshot updated. |
| `tests/integration/test_worktree_full_cycle.sh` | M7 | Register 4 worktrees. Complete 2 stories. Post-wave cleanup removes 2. Pre-wave cleanup for next wave finds 0 stale. |
| `tests/integration/test_escalate_then_retry.sh` | M4 -> M7 | Story fails with `escalate` on unknown file conflict. Worktree cleaned. Story retries next wave, merge succeeds (conflict no longer exists). |
| `tests/integration/test_known_failures_agent_context.sh` | M5 -> M6 | Capture baseline with 2 failures. Verify `format_agent_context()` output is included in agent spawn prompt. Agent sees the known-failures block. |

### Tier 3: End-to-End Validation

After all modules are implemented, run quantum-loop on a controlled test project with deliberate traps:

**Test project:** Small TypeScript project, 6 stories, designed to trigger each module.

| Story pair | Trap | Module exercised | Expected behavior |
|---|---|---|---|
| US-A + US-B | Both add exports to `parsers/index.ts` | M1, M4 | Merge strategy classifies as `regenerate`. Barrel auto-regenerated with both exports. |
| US-C | Changes `IParser.parse()` return type | M3 | Flagged `contractBreaking`, consumers deferred to next wave. |
| US-D | Adds `tree-sitter-java` to `package.json` | M2, M4 | Manifest protected with `--ours`, post-merge `npm install` picks up new dep. |
| US-E + US-F | Both run in parallel, US-E fails | M7 | US-E's worktree cleaned at wave-end. US-F's worktree cleaned after merge. 0 stale worktrees remain. |
| US-C -> US-D | US-C introduces 3 test failures that US-D fixes | M5, M6 | Baseline captured. Delta check after US-C detects 3 new failures, adds to known list. Delta check after US-D sees them resolve. |

**Success criteria:**
- 0 manual merge interventions (all conflicts auto-resolved by M4)
- 0 post-merge fix commits (barrel, deps, interface issues all handled by modules)
- All 6 stories pass (some via retry for escalated conflicts)
- `knownFailures` accurately tracks the 3 temporary failures through their lifecycle
- 0 stale worktrees remain after execution
- Observations document includes accurate metrics for each module

### What NOT to test

- **Every language combination for barrel regen** — Test TypeScript thoroughly, Python as secondary. Rust barrel regen is a smoke test only.
- **Real npm/pip install behavior** — Integration tests mock the install command. Tier 3 e2e covers real installs.
- **Orchestrator prompt formatting** — The known-failures context block is a string concatenation. Test that `format_agent_context()` returns the right string; don't test that the agent actually reads it.

## Open Questions

- Should barrel regeneration sort exports alphabetically, or preserve the order from the directory listing (filesystem-dependent)? Current design: alphabetical for determinism.
- Should the `flakyThreshold` be per-wave or global? A test that flakes in every wave might warrant a higher threshold. Current design: global.
- Should `protect_manifest` attempt a smarter merge (JSON-aware merge for `package.json` that combines both sides' `dependencies` objects) instead of `--ours` + re-install? This would be more precise but language-specific.
- What is the right retry behavior when `git worktree remove` fails on Windows due to file locking? Current design: retry once after 2s, then defer. Windows-specific handling (e.g., closing file handles) may be needed.

## Next Steps

Run `/quantum-loop:spec` to generate a formal Product Requirements Document from this design.
