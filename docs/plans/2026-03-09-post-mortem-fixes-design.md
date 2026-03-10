# Design: Post-Mortem Fixes — All 7 Issues

**Date:** 2026-03-09
**Status:** Approved
**Approach:** Layer Cake (3 independent layers)
**Source:** `docs/post-mortems/2026-03-09-math-research-agent.md`
**Gap audit:** `docs/post-mortems/2026-03-09-gap-audit.md`

## Overview

Implements the remaining fixes from the Math Research Agent post-mortem across all 7 issues, delivered in 3 independent layers:

**Layer 1 — Schema + ql-plan** (quantum.json changes + generation logic)
- Add 5 new fields to quantum.json: `contracts`, `wiring_verification`, `consumedBy`, `startedAt`, `coverageThreshold`
- Update `ql-plan` to generate correct values for all new fields
- Update `quantum.json.example` as the canonical schema reference

**Layer 2 — Agent protocols** (behavioral changes to .md agent/skill files)
- Quality-reviewer reads project coding standards + enforces `codebasePatterns`
- Implementer reads `contracts` before implementing
- Spec-reviewer checks `wiring_verification` assertions
- Coverage gate in quality-reviewer (configurable threshold)
- Lifecycle checklist in `ql-brainstorm` and `ql-spec`
- `testFirst: true` mandate in `ql-plan` with burden-of-proof for `false`

**Layer 3 — Scripts + orchestrator** (runtime enforcement)
- `startedAt` timestamp written by caller before dispatching agents
- Stale story detector in `quantum-loop.sh`, `quantum-loop.ps1`, and orchestrator agent
- Final verification sweep before COMPLETE (in scripts, not just orchestrator docs)
- Stale detection in CLAUDE.md Step 3 (defensive check)
- Execution post-mortem auto-generation with optional GitHub issue filing

**Files to modify:**

| Layer | File | Changes |
|-------|------|---------|
| 1 | `quantum.json.example` | Add all 5 new fields |
| 1 | `skills/ql-plan/SKILL.md` | Generate contracts, wiring_verification, consumedBy, coverageThreshold; testFirst mandate |
| 2 | `agents/quality-reviewer.md` | Read coding standards + codebasePatterns; coverage gate |
| 2 | `agents/spec-reviewer.md` | Check wiring_verification assertions |
| 2 | `agents/implementer.md` | Read contracts before implementing; respect consumedBy |
| 2 | `skills/ql-brainstorm/SKILL.md` | Add lifecycle question |
| 2 | `skills/ql-spec/SKILL.md` | Add lifecycle checklist |
| 3 | `agents/orchestrator.md` | Write startedAt, stale detection, final sweep, post-mortem generation, optional GitHub issue |
| 3 | `quantum-loop.sh` | Write startedAt, stale detection, final verification sweep, post-mortem generation |
| 3 | `quantum-loop.ps1` | Write startedAt, stale detection, post-mortem generation |
| 3 | `templates/quantum-loop.sh` | Write startedAt, stale detection |
| 3 | `CLAUDE.md` | Defensive check for in_progress in Step 3 |

**Not changing:** `lib/*.sh` (crash-recovery already works), `references/edge-cases.md` (already exists).

**New test files:**

| File | Tests |
|------|-------|
| `tests/test_stale_detection.sh` | Stale story detection (mock time, verify state transitions) |
| `tests/test_started_at.sh` | startedAt written before spawn, cleared after completion |
| `tests/test_final_sweep.sh` | Final verification sweep runs before COMPLETE, blocks on failure |
| `tests/test_observations.sh` | Post-mortem doc generated, contains expected sections |

## Schema Changes (quantum.json)

Five new fields added to the quantum.json schema:

### `contracts` (top-level object)

Documents cross-story agreements that parallel agents must respect. Keyed by contract type, each entry maps a logical name to its canonical value.

```json
"contracts": {
  "secret_keys": {
    "openai": "openai-api-key",
    "anthropic": "anthropic-api-key",
    "google": "google-api-key"
  },
  "env_vars": {
    "api_base_url": "API_BASE_URL",
    "debug_mode": "DEBUG"
  },
  "shared_types": {
    "priority": "TaskPriority = 'high' | 'medium' | 'low'",
    "status": "TaskStatus = 'pending' | 'active' | 'done'"
  }
}
```

Contract categories are freeform (the planner decides what needs coordination). Common categories: `secret_keys`, `env_vars`, `shared_types`, `api_routes`, `event_names`, `css_classes`.

### `coverageThreshold` (top-level number, optional)

```json
"coverageThreshold": 80
```

When present, the quality-reviewer runs the project's coverage tool and fails the story if coverage for changed files drops below this number. When absent, coverage is reported but doesn't block.

### `wiring_verification` (per-task object, optional)

Added to tasks that create new modules which must be imported elsewhere:

```json
{
  "id": "T-003",
  "title": "Create PersonaHandler module",
  "wiring_verification": {
    "file": "src/webview/panel.ts",
    "must_contain": ["import { registerPersonaHandlers }", "registerPersonaHandlers("]
  }
}
```

The `must_contain` array lists strings that MUST appear in `file` after the task completes. Verified by grep — no agent judgment required.

### `consumedBy` (per-task array of story IDs, optional)

Declares that the output of this task is consumed by another story. Prevents the consumer from inlining a duplicate.

```json
{
  "id": "T-005",
  "title": "Implement BranchCard component",
  "filePaths": ["src/components/BranchCard.tsx"],
  "consumedBy": ["US-023"]
}
```

When present:
- The implementer of US-023 is told: "BranchCard.tsx already exists from T-005. Import it — do NOT create an inline replacement."
- The dead code scan exempts this export if the consuming story hasn't run yet.

### `startedAt` (per-story ISO 8601 timestamp, runtime-only)

Written by the caller (script or orchestrator) immediately before dispatching an agent. Not generated by ql-plan — this is a runtime field.

```json
{
  "id": "US-004",
  "status": "in_progress",
  "startedAt": "2026-03-07T01:30:00Z"
}
```

Used by the stale detector: if `status === "in_progress"` and `now - startedAt > staleThresholdMinutes` (default 20), reset to `"failed"` and increment retry count.

### Updated quantum.json.example structure (new fields marked with ★)

```
{
  "project": "...",
  "branchName": "...",
  "prdPath": "...",
  "coverageThreshold": 80,              ★
  "contracts": { ... },                  ★
  "stories": [
    {
      "id": "US-001",
      "status": "pending",
      "startedAt": null,                 ★ (runtime, set by caller)
      "tasks": [
        {
          "id": "T-001",
          "wiring_verification": { ... }, ★ (optional)
          "consumedBy": ["US-003"],       ★ (optional)
          ...
        }
      ]
    }
  ]
}
```

## ql-plan Generation Logic

Changes to `skills/ql-plan/SKILL.md` for generating the new schema fields and enforcing the testFirst mandate.

### Contracts Generation (new step after dependency DAG)

After building the dependency DAG, the planner scans for shared state across stories:

1. **Identify contract candidates:** Any value that appears in 2+ stories' acceptance criteria or task descriptions — secret names, env vars, route paths, type names, event names, CSS class names.
2. **Create a `contracts` object** grouping them by category.
3. **Cross-reference:** For each contract value, annotate which stories reference it (as a comment in the plan, not in the schema — keeps it lightweight).

Guidance to the planner:

> If two or more stories reference the same logical entity (a secret key, an API route, a type name), you MUST add it to `contracts`. When in doubt, add it — an unused contract entry costs nothing. A missing one causes cross-story bugs.

### wiring_verification Generation

When a task creates a new module/function/class that must be imported by an existing file:

1. The planner sets `wiring_verification.file` to the file that should contain the import.
2. The planner sets `wiring_verification.must_contain` to an array of strings: the import statement and at least one call site.

Rule: **Any task whose description contains "create", "add", or "implement" a new module/handler/component SHOULD have a `wiring_verification`** unless the wiring is handled by a dependent story (in which case use `consumedBy` instead).

### consumedBy Generation

When Story A creates a component/function that Story B (a dependent) should import:

1. The planner adds `consumedBy: ["US-XXX"]` to the creator task.
2. The planner adds to Story B's first task description: `"Import <component> from <path> (created by <Story A ID>). Do NOT create an inline replacement."`

Rule: **If a task's output is listed in a dependent story's acceptance criteria, it MUST have `consumedBy`.** This is the structural counterpart to the existing Consumer Verification Pattern.

### coverageThreshold Generation

The planner asks the user during the question phase (or infers from project config):

> "What test coverage threshold should be enforced? (default: 80%, enter 0 to disable)"

Written as a top-level field. If the project already has a coverage config (`.nycrc`, `jest.config`, `pyproject.toml [tool.coverage]`), the planner reads that value instead of asking.

### testFirst Mandate (strengthened)

Replace the current guidance (lines 111-122) with a mandate:

**Default: `testFirst: true` for ALL tasks** unless the task falls into one of these exempt categories:
- Config/scaffold files (`.env`, `tsconfig.json`, `Dockerfile`, CI yaml)
- Pure type definitions (`.d.ts`, type-only files)
- Documentation-only tasks
- The test task itself

**For any exempt task**, the planner MUST add a `notes` field explaining why: `"notes": "testFirst: false — pure scaffold, no testable logic"`.

**Anti-rationalization:** "If a task has an `if`, a loop, a data transformation, or calls an external API, it is NOT config. Set `testFirst: true`."

### Contracts Example in ql-plan Output

```json
"contracts": {
  "secret_keys": {
    "openai": "openai-api-key",
    "google": "google-api-key"
  },
  "api_routes": {
    "tasks_list": "GET /api/tasks",
    "tasks_create": "POST /api/tasks"
  },
  "shared_types": {
    "priority": "'high' | 'medium' | 'low'"
  }
}
```

## Agent Protocol Changes

Changes to the 4 agent `.md` files and 2 skill `.md` files for behavioral enforcement.

### quality-reviewer.md — 3 changes

**Change 1: Add coding standards to Inputs section (lines 11-17)**

Add two new inputs after the existing ones:

```
5. CODING_STANDARDS: Read the project's coding standards from:
   - CLAUDE.md (project root)
   - .claude/rules/*.md (if directory exists)
   - codebasePatterns array in quantum.json
   These are MANDATORY review criteria, not suggestions.
```

**Change 2: Add "Coding Standards Compliance" as review dimension #8**

After the existing 7 dimensions (Error Handling, Type Safety, Code Organization, Architecture, Test Quality, Security, Performance), add:

```
8. **Coding Standards Compliance**
   - Read codebasePatterns from quantum.json — verify each rule against the diff
   - Read project CLAUDE.md and .claude/rules/ — check for violations
   - Common patterns to enforce: immutability, naming conventions, file size limits, no console.log
   - Severity: violations of explicitly documented rules are CRITICAL, not MEDIUM
```

**Change 3: Add coverage gate**

After all 8 review dimensions, add a coverage check:

```
## Coverage Gate

If quantum.json contains a `coverageThreshold` field:
1. Run the project's coverage tool on changed files (detect tool from project config: c8, nyc, pytest-cov, go test -cover, JaCoCo)
2. If coverage for files changed in this story < coverageThreshold: flag as CRITICAL
3. If coverageThreshold is absent: report coverage in review summary but do not block

Include in review output:
- Coverage percentage for changed files
- Which files are below threshold (if any)
```

### spec-reviewer.md — 1 change

**Add wiring_verification check to spec compliance review:**

After checking each acceptance criterion against the implementation, add:

```
## Wiring Verification

For each task in the story that has a `wiring_verification` field:
1. Read `wiring_verification.file`
2. For each string in `wiring_verification.must_contain`:
   - grep for the exact string in the file
   - If NOT found: flag as CRITICAL spec failure — "Task <T-ID> requires '<string>' in <file>, but it is missing"
3. This check is mechanical (grep), not judgmental. Missing = fail. Present = pass.
```

### implementer.md — 2 changes

**Change 1: Read contracts before implementing (add after Step 1: Read State)**

```
## Read Contracts

If quantum.json contains a `contracts` section:
1. Read the entire contracts object
2. When implementing any value that matches a contract category (secret key name, env var, API route, type definition, event name):
   - Use the EXACT value from contracts — do not invent your own
   - If the contract doesn't cover your case, use a consistent naming pattern and note it in your progress entry so the orchestrator can add it to contracts
3. Anti-rationalization: "I know a better name" is not a valid reason to deviate from a contract. Consistency across stories matters more than local preference.
```

**Change 2: Respect consumedBy (add to Integration Wiring Check)**

```
## Respect consumedBy

Before creating any new component, function, or module:
1. Check if another task in the current story or a dependency has `consumedBy` pointing to YOUR story
2. If yes: import and use the existing implementation — do NOT create an inline replacement
3. Grep for the component name in the codebase first. If it already exists, import it.
```

### ql-brainstorm/SKILL.md — 1 change

**Add lifecycle question to Phase 1 question list (after question #6 "EXISTING SOLUTIONS"):**

```
7. LIFECYCLE: What happens beyond the happy path?
   A) This is a one-shot tool — no returning users or state to preserve
   B) Users will return — I need to consider first-run vs returning-user experience
   C) This integrates into an existing system — I need to consider upgrade/migration behavior
   D) Multiple of the above — let me explain
```

### ql-spec/SKILL.md — 1 change

**Add lifecycle checklist to the Pre-Save Checklist (after existing items):**

```
## Lifecycle Checklist (mandatory for user-facing features)

Before saving the PRD, explicitly address each scenario. Write "N/A" with justification if a scenario doesn't apply — do not silently skip.

- [ ] **First-run behavior:** What happens on first use? Onboarding? Default state?
- [ ] **Returning-user behavior:** What happens when settings/data already exist?
- [ ] **Update behavior:** What happens when the feature is updated after users have existing data?
- [ ] **Error recovery:** What happens after a crash, timeout, or partial failure?
- [ ] **No-data / empty state:** What does the user see with zero items?
- [ ] **Uninstall/disable:** Is cleanup needed? Orphaned data?
```

## Scripts + Orchestrator Runtime Changes

Changes to `quantum-loop.sh`, `quantum-loop.ps1`, `templates/quantum-loop.sh`, `agents/orchestrator.md`, and `CLAUDE.md` for stale detection and final verification sweep.

### startedAt — Written by Caller Before Dispatch

**In `quantum-loop.sh` (parallel mode):**

Before spawning each agent in `spawn_agent()`, write `startedAt` to quantum.json:

```bash
# Write startedAt before spawning (atomic JSON update)
local now=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
json_atomic_update ".stories[] | select(.id == \"$story_id\") | .startedAt = \"$now\""
```

**In `quantum-loop.sh` (sequential mode):**

Same pattern — write `startedAt` before the `claude --print` call in the main loop.

**In `quantum-loop.ps1`:**

```powershell
$now = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
# Write startedAt via jq before spawning
```

**In `templates/quantum-loop.sh`:**

Same pattern as the root script's sequential mode.

**In `agents/orchestrator.md`:**

Before dispatching an implementer subagent (both sequential and parallel paths), write `startedAt`:

```
Before dispatching: set story.startedAt = new Date().toISOString() in quantum.json
```

### Stale Story Detector

**Detection logic (same in all 4 locations):**

```
At the start of each iteration / wave:
1. Query all stories where status === "in_progress"
2. For each, compute: elapsed = now - startedAt
3. If elapsed > STALE_THRESHOLD (default 20 minutes):
   a. Set status = "failed"
   b. Increment retries.attempts
   c. Add to retries.failureLog:
      { "attempt": N, "timestamp": now, "error": "Stale: in_progress for >20min with no completion signal", "phase": "stale_detection" }
   d. Clear startedAt to null
   e. Log: "Stale story detected: <story_id> was in_progress for <elapsed>min. Reset to failed for retry."
4. If retries.attempts >= retries.maxAttempts: set status to "blocked"
```

**In `quantum-loop.sh`:**

Add `detect_stale_stories()` function, called at the top of the main loop (both sequential and parallel paths), after crash recovery but before DAG query. Uses `jq` + `date` to compute elapsed time.

**In `quantum-loop.ps1`:**

Add `Detect-StaleStories` function with equivalent PowerShell logic using `[datetime]::Parse()` and `(Get-Date).ToUniversalTime()`.

**In `templates/quantum-loop.sh`:**

Add simplified version using `node -e` (the templates script uses Node, not jq).

**In `agents/orchestrator.md`:**

Add stale detection step between crash recovery and DAG query:

```
## Step 1B: Detect Stale Stories

Before querying the DAG, check for stories stuck in_progress:
1. For each story with status "in_progress", check startedAt
2. If startedAt is older than 20 minutes, treat as failed (same as agent timeout)
3. This catches the case where an agent exits silently after marking a story in_progress
```

### Final Verification Sweep Before COMPLETE

Currently `agents/orchestrator.md` Step 4 documents this but the scripts don't implement it. Add to all scripts:

**In `quantum-loop.sh` (both modes) — before printing COMPLETE:**

```bash
# Final verification sweep
echo "Running final verification sweep..."

# 1. Full test suite
if ! run_test_suite; then
  echo "FINAL SWEEP FAILED: test suite"
  # Create fix iteration instead of declaring COMPLETE
  exit 1
fi

# 2. Import smoke test (detect from project type)
if [ -f "package.json" ]; then
  entry=$(jq -r '.main // "index.js"' package.json)
  node -e "require('./$entry')" 2>/dev/null || echo "WARNING: import smoke test failed"
elif [ -f "setup.py" ] || [ -f "pyproject.toml" ]; then
  python -c "import $(detect_main_module)" 2>/dev/null || echo "WARNING: import smoke test failed"
fi

echo "Final sweep passed. Declaring COMPLETE."
```

**In `quantum-loop.ps1`:**

Equivalent PowerShell: run the test suite before declaring complete.

**In `templates/quantum-loop.sh`:**

Same — run test suite before COMPLETE. The templates version already uses Node, so the smoke test is straightforward.

### CLAUDE.md Step 3 — Defensive Check

Add to Step 3 (Select Story), after the eligibility rules:

```
**Defensive check:** If you encounter a story with status "in_progress" that was NOT
assigned to you, do NOT modify it. Log a warning:
"WARNING: Story <ID> is in_progress but not assigned to this agent. Skipping — the
orchestrator's stale detector will handle it."

If you are in worktree mode and your assigned story is already "in_progress" with a
startedAt older than 10 minutes, this is likely a retry after a stale detection.
Proceed normally — implement from scratch.
```

## Execution Post-Mortem Auto-Generation

After `ql-execute` completes (whether all stories pass, some are blocked, or max iterations are reached), the orchestrator and scripts automatically generate a post-mortem observation document and optionally push it as a GitHub issue.

### What Gets Observed

During execution, the orchestrator/scripts already track data in quantum.json's `progress` array and `retries.failureLog`. The post-mortem harvests this into a structured report:

**Failure patterns:**
- Stories that failed and why (grouped by `phase`: test, lint, typecheck, stale_detection, review)
- Stories that exhausted retries — what kept failing?
- Stories that were blocked — which dependency chain broke?

**Cross-story issues:**
- Merge conflicts encountered during parallel execution
- Contract violations detected by integration review
- Dead code flagged by Stage 3 review
- Wiring failures caught by `wiring_verification` checks

**Coverage and quality:**
- Stories where coverage dropped below threshold
- `codebasePatterns` added during this run (new learnings)
- Review gate pass/fail rates (how often did stories pass first try vs need fixes?)

**Timing anomalies:**
- Stale stories detected (agent silent exits)
- Stories that took significantly longer than the 2-5 minute target
- Total wall-clock time vs story count

### Document Format

Saved to `docs/post-mortems/YYYY-MM-DD-<branch-name>-observations.md`:

```markdown
# Execution Observations: <branch-name>

**Date:** YYYY-MM-DD
**Stories:** X passed, Y failed, Z blocked out of N total
**Execution mode:** sequential | parallel (max N agents)
**Total iterations:** N
**Wall-clock time:** ~Xm

## Failure Summary

| Story | Failures | Final Status | Root Cause |
|-------|----------|-------------|------------|
| US-004 | 2 attempts | passed (retry) | TypeScript error in handler registration |
| US-007 | 3 attempts | blocked | Persistent test failure in edge case |

## Patterns Observed

### Recurring Failure Modes
- [e.g., "3 of 5 failures were wiring issues — modules created but not imported"]
- [e.g., "2 stories failed with contract mismatches on secret key names"]

### What Worked Well
- [e.g., "Cross-story integration review caught type mismatch between US-003 and US-005"]

### Suggested Improvements
- [e.g., "Consider adding 'database-connection-string' to contracts — US-002 and US-006 used different env var names"]

## Raw Data

<details>
<summary>Progress log</summary>
[Full progress array from quantum.json]
</details>

<details>
<summary>Failure logs</summary>
[All retries.failureLog entries]
</details>
```

### Where It Runs

**In `agents/orchestrator.md` — new Step 5: Generate Observations**

After Step 4 (final integration gate), whether the outcome is COMPLETE, BLOCKED, or max iterations:

```
## Step 5: Generate Execution Observations

1. Read the full quantum.json progress array and all retries.failureLog entries
2. Categorize failures by phase and pattern
3. Identify recurring themes (same error across stories, same file causing conflicts)
4. Note timing anomalies and stale detections
5. Save to docs/post-mortems/YYYY-MM-DD-<branchName>-observations.md
6. git add and commit: "docs: execution observations for <branchName>"
```

**In `quantum-loop.sh` and `quantum-loop.ps1` — after exit:**

The scripts can't generate the rich analysis (they're bash/PowerShell), so they take a simpler approach: dump story summary stats, failure table, and raw progress/failure data into the markdown file, then `git add` and `git commit`.

### GitHub Issue (Optional, User-Confirmed)

**In `agents/orchestrator.md` only** (scripts prompt interactively):

```
## Step 5B: File GitHub Issue (user-confirmed)

If the observations document contains:
- Any story that exhausted retries (blocked)
- Any recurring failure pattern (same root cause in 2+ stories)
- Any stale story detection

Then ASK the user:
  "I found N issues worth reporting. Would you like me to file a GitHub issue
   on andyzengmath/quantum-loop with these observations?"

Only file if the user confirms. Use:
  gh issue create \
    --repo andyzengmath/quantum-loop \
    --title "Execution observations: <branchName> (<date>)" \
    --body "$(cat docs/post-mortems/<file>.md)" \
    --label "execution-feedback"

If gh is not available or the command fails, skip silently — the local doc is the primary artifact.
```

**In scripts:**

```bash
read -p "File observations as GitHub issue on quantum-loop? [y/N] " confirm
```

Defaults to No. If running with `--non-interactive` or piped input, skips entirely.

## Testing Strategy

### Layer 1 Testing (Schema + ql-plan)

**quantum.json.example validation:**
- Valid JSON with no syntax errors
- All 5 new fields present with correct types (`contracts` is object, `coverageThreshold` is number, `wiring_verification` is object with `file` string and `must_contain` array, `consumedBy` is array of strings, `startedAt` is string or null)
- Existing fields unchanged — no regressions

**ql-plan generation logic:**
- Run the updated ql-plan on a sample PRD and verify:
  - `contracts` section populated when 2+ stories share values
  - `wiring_verification` present on tasks that create new modules
  - `consumedBy` present when Story A's output feeds Story B
  - `testFirst: true` is the default; any `false` has a `notes` justification
  - `coverageThreshold` present (from user input or project config)

### Layer 2 Testing (Agent protocols)

**quality-reviewer:**
- Give it a diff that violates a `codebasePatterns` rule (e.g., direct mutation) — verify it flags as CRITICAL
- Give it a diff with changed files below `coverageThreshold` — verify it flags
- Give it a clean diff with no violations — verify it passes

**spec-reviewer:**
- Give it a story with `wiring_verification` where the target file is missing the import — verify CRITICAL failure
- Give it a story with `wiring_verification` where imports are present — verify pass

**implementer:**
- Give it a story where `contracts.secret_keys.google` = `"google-api-key"` — verify it uses that exact string, not an invention
- Give it a story whose ID appears in another task's `consumedBy` — verify it imports rather than inlines

**ql-brainstorm / ql-spec:**
- Run ql-brainstorm on a user-facing feature — verify lifecycle question (#7) appears
- Run ql-spec on a user-facing feature — verify lifecycle checklist appears in Pre-Save and all items are addressed (or marked N/A)

### Layer 3 Testing (Scripts + orchestrator)

**startedAt:**
- Start a story — verify `startedAt` is written to quantum.json before agent spawns
- Verify `startedAt` is ISO 8601 UTC format

**Stale detection:**
- Manually set a story to `in_progress` with `startedAt` 25 minutes ago — run the loop — verify it resets to `failed` with `"phase": "stale_detection"` in failureLog
- Verify retry count increments
- Verify a story at maxAttempts gets set to `blocked`

**Final verification sweep:**
- Set all stories to `passed` but break the test suite — verify scripts do NOT declare COMPLETE
- Set all stories to `passed` with passing tests — verify COMPLETE

**CLAUDE.md defensive check:**
- Set a story to `in_progress` with stale `startedAt` — run an agent — verify it logs a warning and doesn't touch the story

**Post-mortem generation:**
- Run a full execution with at least 1 failure — verify `docs/post-mortems/` file is created
- Verify the file contains failure summary, patterns, and raw data
- Verify `gh issue create` is NOT called without user confirmation

### Shell test additions (`tests/`)

| File | Tests |
|------|-------|
| `tests/test_stale_detection.sh` | Stale story detection in quantum-loop.sh (mock time, verify state transitions) |
| `tests/test_started_at.sh` | startedAt written before spawn, cleared after completion |
| `tests/test_final_sweep.sh` | Final verification sweep runs before COMPLETE, blocks on failure |
| `tests/test_observations.sh` | Post-mortem doc generated, contains expected sections |

### Real-world validation

After all layers are implemented, run the updated quantum-loop on a small project (3-5 stories) and observe:
- Contracts respected across parallel stories
- wiring_verification catches a deliberately unwired module
- Stale detection recovers a deliberately killed agent
- Post-mortem doc generated with useful observations

## Open Questions

- Should `contracts` support validation patterns (regex) in addition to exact string values? (e.g., secret keys must match `^[a-z-]+$`)
- Should the stale threshold (20 min) be configurable in quantum.json? (e.g., `"staleThresholdMinutes": 20`)
- Should the post-mortem auto-generation be opt-out (always generate, `--no-observations` to skip) or opt-in (`--observations` to enable)?

## Next Steps

Run `/quantum-loop:ql-spec` to generate a formal Product Requirements Document from this design.
