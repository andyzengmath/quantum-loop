# Design: Progressive Materialization — 5-Layer Defense Against Worktree Isolation Type Divergence

**Date:** 2026-03-18
**Status:** Approved
**Approach:** Progressive Materialization (Approach C)
**Source:** `docs/post-mortems/2026-03-18-worktree-isolation-research.md`
**Triggered by:** `Logical_inference/docs/post-mortems/2026-03-18-quantum-loop-execution-observations.md`

## Design Parameters

| Decision | Choice |
|---|---|
| Scope | Full 5-layer defense |
| Language support | Language-agnostic from day one (detect from project files) |
| Contract shape format | Hybrid: structured JSON for validation + verbatim definition string for code gen |
| Merge conflict strategy | Escalate-on-conflict (fail story, retry with full context) |
| Typecheck command | Explicit field with auto-detect fallback |
| Wave-end audit | Grep-based scan, escalate to agent only if duplicates found |
| Skill creation | Use Anthropic's skill-creator methodology for new components |

## Overview

**What we're building:** A 5-layer defense system against type divergence, destructive merges, and interface bypasses caused by parallel worktree isolation in quantum-loop.

**Why:** Parallel execution via git worktrees is quantum-loop's core performance feature — 29 stories across 9 waves with 5 concurrent agents. But worktree isolation means agents can't see each other's work. The March 18 post-mortem revealed 10 post-merge issues (3 CRITICAL, 7 IMPORTANT), 70% caused by parallel isolation. This is a recurring, escalating problem — up from 2 cross-story bugs in the March 9 post-mortem.

**Approach: Progressive Materialization** — Contracts are enhanced with structural shapes and selectively materialized as real code files before each wave. Detection layers catch what prevention misses, and a feedback loop improves contracts across waves within a single run.

**The 5 layers:**

| Layer | Role | Phase |
|---|---|---|
| L1: Structural contracts in `ql-plan` | Define type shapes + definition strings at planning time | Prevention |
| L2: Selective contract materialization | Generate real interface files before each wave (only for multi-consumer types) | Prevention |
| L3: Escalate-on-conflict merge | Fail stories on shared-file merge conflicts instead of silent data loss | Resolution |
| L4: Post-merge typecheck gate | Run project-wide typecheck after each merge, revert on failure | Detection |
| L5: Wave-end type audit with feedback | Grep for duplicate types, spawn agent if found, feed discoveries back into contracts | Detection |

**Key design principle:** Each layer is independently valuable and can be shipped incrementally. L1 alone improves over today. L1+L2 eliminates the root cause for declared contracts. L3+L4 catch undeclared problems. L5 makes the system self-healing.

**Files affected:** `skills/ql-plan/SKILL.md`, `quantum.json.example`, `lib/monitor.sh`, `lib/materialize.sh` (new), `lib/type-audit.sh` (new), `agents/orchestrator.md`, `agents/implementer.md`, `agents/type-auditor.md` (new), `skills/ql-plan/references/contract-shapes.md` (new)

## User Experience

The 5-layer system is mostly invisible to the user. It operates inside the existing `/ql-plan` and `/ql-execute` workflow with no new commands or prompts. Here's what changes from the user's perspective:

### During `/ql-plan`

**Before (today):** The planner generates `contracts.shared_types` with name-only entries like `{"AliasRegistry": {"value": "AliasRegistry"}}`.

**After:** The planner generates richer contracts with shapes and definition strings when it detects 2+ stories referencing the same type. The user sees this in the plan output:

```
Contracts detected:
  shared_types:
    AliasRegistry (owner: US-012, consumers: US-007, US-013)
      → resolve(alias: string): string | null
      → register(alias: string, target: string): void
    FeatureCluster (owner: US-019, consumers: US-021)
      → nodes: Set<string>
      → entryPoints: EntryPoint[]
```

The user can review and approve/modify contracts as part of normal plan review. No new approval step.

### During `/ql-execute`

**New log messages the user sees:**

```
[MATERIALIZE] Generating 3 contract files for Wave 1...
  → src/shared/types/alias-registry.ts (AliasRegistry)
  → src/shared/types/feature-cluster.ts (FeatureCluster)
  → src/shared/types/entry-point.ts (EntryPoint)
[MATERIALIZE] Committed: "chore: materialize contracts for Wave 1"

[SPAWNED] US-007 - Phased AnalyzerRegistry (wave 1)
[SPAWNED] US-012 - ImportAnalyzer AliasRegistry (wave 1)
...

[MERGE] US-012 merged successfully
[TYPECHECK] Post-merge typecheck: PASSED

[MERGE] US-028 conflict on types/index.ts
[ESCALATE] US-028 marked failed (phase: merge_conflict) — will retry next wave

[WAVE-END] Type audit for Wave 1...
[AUDIT] Grep found 0 duplicate type definitions. Skipping agent audit.

[WAVE-END] Type audit for Wave 3...
[AUDIT] Grep found duplicate: "Feature" defined in src/api/types.ts AND src/frontend/types.ts
[AUDIT] Spawning type-audit agent to assess compatibility...
[AUDIT] Agent consolidated "Feature" into src/shared/types/feature.ts
[AUDIT] Updated contracts for Wave 4: added Feature shape
```

**New failure mode the user sees:**

```
[FAILED] US-028 - Build UI Dashboard
  Phase: merge_conflict
  Files: types/index.ts
  Action: Will retry in Wave 4 (now has full context of merged changes)
```

This is **better** than today, where the merge silently destroys content (Pattern 2). The user sees an explicit failure and retry instead of a silent corruption discovered only in post-merge review.

### After execution

The post-mortem observations document (already generated today) gains a new section:

```markdown
## Contract Effectiveness
- Contracts defined: 5 types
- Materialized: 3 (multi-consumer only)
- Divergence prevented: 2 (AliasRegistry, FeatureCluster)
- Divergence detected by L5 audit: 1 (Feature — consolidated)
- Missed (discovered in post-merge review): 0
```

### No new commands or configuration

The user's workflow remains: `/ql-plan` → review → `/ql-execute`. The only new optional field is `typecheckCommand` in quantum.json, which auto-detects if absent.

## Data Model

### quantum.json Schema Changes

Three areas of change: enhanced contracts, new top-level fields, and new runtime metadata.

#### Enhanced `contracts.shared_types` entries

Each shared type entry grows from name-only to name + shape + definition + ownership:

```json
"contracts": {
  "shared_types": {
    "AliasRegistry": {
      "value": "AliasRegistry",
      "pattern": "^AliasRegistry$",
      "definitionFile": "src/shared/types/alias-registry.ts",
      "owner": "US-012",
      "consumers": ["US-007", "US-013"],
      "shape": {
        "methods": [
          {"name": "resolve", "params": [{"name": "alias", "type": "string"}], "returns": "string | null"},
          {"name": "register", "params": [{"name": "alias", "type": "string"}, {"name": "target", "type": "string"}], "returns": "void"}
        ],
        "properties": [
          {"name": "entries", "type": "Map<string, string>", "readonly": true}
        ]
      },
      "definition": "export interface AliasRegistry {\n  resolve(alias: string): string | null;\n  register(alias: string, target: string): void;\n  readonly entries: Map<string, string>;\n}"
    }
  },
  "secret_keys": { "...existing format unchanged..." },
  "api_routes": { "...existing format unchanged..." }
}
```

**Field definitions:**

| Field | Type | Required | Description |
|---|---|---|---|
| `value` | string | Yes | Canonical type name (unchanged from today) |
| `pattern` | string | No | Regex validation (unchanged from today) |
| `definitionFile` | string | No | Path where the materialized interface file will be written. If absent, type is not materialized (L2 skips it). |
| `owner` | string | No | Story ID that is the primary implementer. The owner's implementation is authoritative. |
| `consumers` | string[] | No | Story IDs that import/use this type. Used to determine which contracts need materialization (2+ consumers = materialize). |
| `shape` | object | No | Structured representation: `methods[]` and `properties[]`. Used by L5 audit for compatibility checking. |
| `shape.methods[]` | object | No | Each: `{name, params: [{name, type}], returns}` |
| `shape.properties[]` | object | No | Each: `{name, type, readonly?}` |
| `definition` | string | No | Verbatim code string in the target language. The materializer writes this to `definitionFile`. |

**Backward compatibility:** All new fields are optional. Existing quantum.json files with name-only contracts continue to work — they just don't benefit from L2 materialization or L5 shape validation. The system degrades gracefully to today's behavior.

#### New top-level field `typecheckCommand`

```json
"typecheckCommand": "pyright --outputjson"
```

| Field | Type | Required | Default |
|---|---|---|---|
| `typecheckCommand` | string \| null | No | Auto-detect: `tsc --noEmit` if `tsconfig.json` exists, `pyright` if `pyrightconfig.json` or `pyproject.toml` with `[tool.pyright]`, `mypy .` if `mypy.ini` or `[tool.mypy]`, `go vet ./...` if `go.mod`. If no tool detected, `null` (skip with warning). |

#### New runtime metadata in `execution`

The `execution` object (already exists, written at runtime) gains fields for tracking materialization and audit state:

```json
"execution": {
  "mode": "parallel",
  "maxParallel": 4,
  "currentWave": 3,
  "activeWorktrees": [".ql-wt/US-007", ".ql-wt/US-012"],
  "materializedContracts": ["AliasRegistry", "FeatureCluster", "EntryPoint"],
  "discoveredContracts": {
    "Feature": {
      "discoveredInWave": 3,
      "sourceFiles": ["src/api/types.ts", "src/frontend/types.ts"],
      "consolidated": true,
      "consolidatedFile": "src/shared/types/feature.ts"
    }
  }
}
```

| Field | Type | Description |
|---|---|---|
| `materializedContracts` | string[] | Type names that were written to disk before the current wave |
| `discoveredContracts` | object | Types found by L5 audit that weren't in the original contracts. Keyed by type name. Used to materialize in subsequent waves. |

#### No changes to existing fields

These fields are unchanged: `stories`, `tasks`, `progress`, `codebasePatterns`, `fileConflicts`, `coverageThreshold`, `staleThresholdMinutes`, `wiring_verification`, `consumedBy`, `startedAt`. The new system builds on top of the March 9 design, not replacing it.

## Architecture

### Component Overview

The 5 layers map to specific files and execution phases:

```
ql-plan (planning time)
  └── L1: Enhanced contract generation in skills/ql-plan/SKILL.md
        ├── Detects shared types across stories
        ├── Generates shape + definition fields
        └── Language detection (tsconfig.json / pyproject.toml / go.mod)

ql-execute (runtime)
  ├── Pre-wave phase
  │   └── L2: Contract materialization in lib/materialize.sh (NEW)
  │         ├── Reads contracts.shared_types from quantum.json
  │         ├── Filters to multi-consumer types (consumers.length >= 2)
  │         ├── Writes definition string to definitionFile
  │         ├── Commits: "chore: materialize contracts for Wave N"
  │         └── All worktrees branch from this commit
  │
  ├── Post-merge phase (per story)
  │   ├── L3: Escalate-on-conflict in lib/monitor.sh (MODIFIED)
  │   │     ├── Existing merge_worktree_branch() unchanged on success
  │   │     ├── On conflict: classify conflicting files
  │   │     ├── Shared files (barrel exports, type files, registries) → FAIL story
  │   │     └── Log: phase "merge_conflict", list conflicting files
  │   │
  │   └── L4: Post-merge typecheck in lib/monitor.sh (MODIFIED)
  │         ├── After successful merge: run typecheckCommand
  │         ├── Auto-detect if not set (tsconfig → tsc, pyproject → pyright, etc.)
  │         ├── On failure: git revert -m 1 HEAD, mark story failed
  │         └── Log: phase "merge_typecheck", include error output
  │
  └── Wave-end phase
      └── L5: Type audit in lib/type-audit.sh (NEW)
            ├── Fast path: grep for duplicate type/interface/class/Protocol definitions
            ├── If no duplicates: skip (zero cost)
            ├── If duplicates found: spawn type-audit agent
            │     ├── Reads both definitions + contract shapes
            │     ├── Consolidates into shared file
            │     ├── Updates imports in consuming files
            │     └── Commits: "fix: consolidate <TypeName> from wave N"
            └── Feedback: writes discoveredContracts to execution metadata
                  └── Next wave's L2 materializes these too
```

### File Changes

| File | Change | Layer |
|---|---|---|
| `skills/ql-plan/SKILL.md` | Add structural contract generation step | L1 |
| `skills/ql-plan/references/contract-shapes.md` (NEW) | Language-specific shape generation guidance, examples per language | L1 |
| `quantum.json.example` | Add enhanced contract fields, typecheckCommand | L1 |
| `lib/materialize.sh` (NEW) | `materialize_contracts()`, `detect_language()`, `generate_definition_file()` | L2 |
| `lib/materialize.sh` | Language templates: TS interface, Python Protocol, Go interface | L2 |
| `lib/monitor.sh` | Extend `merge_worktree_branch()` with shared-file classification + escalation | L3 |
| `lib/monitor.sh` | Add `post_merge_typecheck()` with auto-detect fallback | L4 |
| `lib/type-audit.sh` (NEW) | `audit_wave_types()`, `grep_duplicate_definitions()`, `spawn_audit_agent()` | L5 |
| `agents/orchestrator.md` | Add materialization step, typecheck gate, wave-end audit, feedback loop | L2-L5 |
| `agents/implementer.md` | Add instruction to import from materialized contract files | L2 |
| `agents/type-auditor.md` (NEW) | Short-lived agent: reads duplicates, consolidates, updates imports | L5 |

### New Files — Skill Creator Process

Following the skill-creator methodology for the new components:

**`lib/materialize.sh`** — Low freedom (specific script). Contract materialization must be deterministic — the same quantum.json input must produce the same files every time. This is a bash script with language-detection logic and template expansion, not an agent skill.

```
lib/materialize.sh
├── detect_language(repo_root)         # Returns: typescript|python|go|unknown
├── materialize_contracts(json_path, repo_root, wave_num)
│   ├── Reads contracts.shared_types + execution.discoveredContracts
│   ├── Filters to entries with consumers.length >= 2
│   ├── For each: generate_definition_file()
│   ├── git add + commit
│   └── Returns list of materialized type names
└── generate_definition_file(type_entry, language, repo_root)
    ├── If definition field exists: write verbatim to definitionFile
    ├── If definition absent but shape exists: generate from shape using language template
    └── If neither: skip with warning
```

**`lib/type-audit.sh`** — Medium freedom (grep scan is deterministic, agent escalation is flexible).

```
lib/type-audit.sh
├── grep_duplicate_definitions(repo_root, wave_stories)
│   ├── Patterns per language:
│   │   TS:  "export (interface|type|class) (\w+)"
│   │   Py:  "class (\w+)\(Protocol\)|class (\w+)\(BaseModel\)|@dataclass\nclass (\w+)"
│   │   Go:  "type (\w+) (interface|struct)"
│   ├── Groups by name, filters to names with 2+ definition sites
│   └── Returns: array of {name, files[], wave_stories[]}
├── audit_wave_types(json_path, repo_root, wave_num)
│   ├── Calls grep_duplicate_definitions()
│   ├── If empty: log "0 duplicates", return
│   ├── If non-empty: spawn type-auditor agent
│   └── Write discoveredContracts to execution metadata
└── update_contracts_for_next_wave(json_path, discovered)
    └── Merges discoveredContracts into contracts.shared_types for L2
```

**`agents/type-auditor.md`** — A short-lived agent spawned only when L5 detects duplicates. Following the skill-creator principle of minimal context:

```markdown
---
name: type-auditor
description: "Short-lived agent that consolidates duplicate type definitions
  found across parallel stories. Spawned by the wave-end type audit when
  grep detects the same type name defined in 2+ files."
tools: ["Read", "Write", "Edit", "Bash", "Grep", "Glob"]
---

# Instructions (brief — this agent has a narrow scope)
1. Read the duplicate definitions provided in the prompt
2. Read the contract shape from quantum.json (if exists)
3. Choose the authoritative definition (prefer contract shape, then owner story, then most complete)
4. Write consolidated definition to the shared types directory
5. Update imports in all consuming files
6. Run typecheck to verify
7. Commit: "fix: consolidate <TypeName> from wave N"
```

**`skills/ql-plan/references/contract-shapes.md`** (NEW) — Reference file following the skill-creator's progressive disclosure pattern. Only loaded by the planner when it detects shared types. Contains:
- Language detection heuristics
- Examples of shape + definition for TypeScript, Python, Go
- Guidance on when to generate `definition` (2+ consumers) vs shape-only (advisory)

### Execution Flow — Detailed Sequence

```
1. /ql-plan generates quantum.json with enhanced contracts
2. /ql-execute starts
3. For each wave:
   a. L2: materialize_contracts() writes interface files, commits
   b. Orchestrator spawns agents (worktrees branch from post-materialization commit)
   c. Agents implement stories, importing from materialized files
   d. For each completed agent:
      i.   Attempt merge (existing merge_worktree_branch)
      ii.  L3: On conflict in shared file → fail story, skip to (d)
      iii. L4: post_merge_typecheck() → on failure, revert + fail story
      iv.  Inline review gate (existing Step 3B.4)
   e. L5: audit_wave_types() → grep scan
      i.   No duplicates → proceed to next wave
      ii.  Duplicates → spawn type-auditor agent → consolidate → commit
      iii. update_contracts_for_next_wave() → feeds into step 3a
4. Final integration gate (existing Step 4)
5. Post-mortem generation (existing Step 5, now includes Contract Effectiveness section)
```

### The Feedback Loop (L5 → L2)

This is the "progressive" part of Progressive Materialization. When L5 discovers a type that wasn't in the original contracts:

1. L5 writes it to `execution.discoveredContracts` with the consolidated definition
2. Before the next wave, L2's `materialize_contracts()` reads BOTH `contracts.shared_types` AND `execution.discoveredContracts`
3. The discovered type gets materialized for future waves
4. At execution end, the orchestrator optionally promotes `discoveredContracts` into the permanent `contracts.shared_types` (for future runs)

This means Wave 1 may have some undetected divergence, but Waves 2+ benefit from accumulated knowledge. The system learns within a single run.

## Edge Cases & Error Handling

### L1: Planner generates wrong contract shapes

**Scenario:** The planner defines `AliasRegistry.resolve()` returning `string`, but the correct return type should be `AliasEntry | null`.

**Impact:** All agents build against the wrong interface. Tests pass individually (each worktree's tests use the wrong type consistently), but the feature doesn't work correctly at integration time.

**Handling:** This is the "consistently wrong" case — intentionally accepted as better than "inconsistently wrong" (today). The existing review gates (spec compliance + code quality) should catch functional incorrectness. Additionally:
- The implementer agent is instructed: if a contract shape doesn't match the PRD's acceptance criteria, halt and log a warning rather than silently conforming
- The owner story (who implements the type) can extend the materialized interface — adding fields/methods is non-breaking. The contract is a minimum, not a maximum.
- Post-mortem observations track "contract accuracy" so the planner can improve over time

### L1: Planner misses a shared type entirely

**Scenario:** Two stories both need `FeatureMetrics` but the planner doesn't detect the shared concept — no contract is generated.

**Impact:** Classic Pattern 1 divergence. Two agents create incompatible `FeatureMetrics` types.

**Handling:** This is exactly what L5 exists for. The wave-end grep scan detects duplicate `FeatureMetrics` definitions, spawns the type-auditor agent to consolidate, and feeds the discovery back into contracts for subsequent waves. The system self-heals — it just costs one wave of divergence.

### L2: Materialized file conflicts with existing code

**Scenario:** The project already has `src/shared/types/alias-registry.ts` from a previous feature. The materializer tries to write to the same path.

**Handling:** Before writing, `generate_definition_file()` checks if the file exists:
- If it exists and content matches the definition: skip (already materialized, likely from a previous wave or run)
- If it exists with different content: **do not overwrite**. Log a warning: `[MATERIALIZE] SKIP AliasRegistry — file already exists with different content. Agents will use existing file.` The existing file becomes the de facto contract. This is safe — agents import it regardless.

### L2: Language detection fails

**Scenario:** The project has no `tsconfig.json`, `pyproject.toml`, or `go.mod`. Or it has multiple (a polyglot monorepo).

**Handling:**
- No language detected: Skip materialization entirely with warning. L3-L5 still operate as safety nets. The system degrades to today's behavior plus detection.
- Multiple languages detected: Use the language of the `definitionFile` path extension. If `definitionFile` ends in `.ts` → TypeScript, `.py` → Python, `.go` → Go. The planner is responsible for setting the right extension.
- `definition` field present: Use it verbatim regardless of detected language. The `definition` string is always authoritative over template generation.

### L3: Story fails due to merge conflict — retry behavior

**Scenario:** US-028 fails with `phase: "merge_conflict"` on `types/index.ts`. It retries in Wave 4.

**Handling:** By Wave 4, the conflicting changes from Wave 3 are already merged into HEAD. When the retry agent's worktree branches from HEAD, it sees the full state including the previously merged content. The conflict that caused the failure no longer exists — the agent implements against the current codebase. This is the core insight of escalate-on-conflict: **deferring to the next wave gives the agent full context for free.**

Edge case: The retry conflicts again (a different story in Wave 4 also touches the same file). The story fails again, retries consumed. After `maxAttempts` exhausted:
- Story marked `"blocked"`
- Post-mortem flags it as a recurring merge conflict
- Recommendation: add the file to `fileConflicts` in quantum.json to prevent co-scheduling

### L4: Typecheck command not available

**Scenario:** `typecheckCommand` is `null` (not set, auto-detect found nothing). Or the command exists but is not installed (e.g., `pyright` not in PATH).

**Handling:**
- `null` (no typecheck configured): Log `[TYPECHECK] No typecheck command configured or detected. Skipping post-merge typecheck.` Layer 4 is a no-op. L3 and L5 still operate.
- Command not found (exit code 127 or "command not found" in stderr): Log warning, skip typecheck for this merge. Do NOT fail the story for missing tooling — that's a setup issue, not a code issue.
- Command times out (>60 seconds): Kill and skip with warning. Large projects may have slow typechecks — blocking merges on a slow typecheck would stall the pipeline.

### L4: Typecheck fails on pre-existing errors

**Scenario:** The project already had type errors before quantum-loop started. Post-merge typecheck finds 50 errors, but only 2 are from the merged story.

**Handling:** The typecheck runs on the full project, but the revert decision should be based on **new** errors only:
1. Before the first wave, run typecheck and store the baseline error count: `execution.baselineTypecheckErrors`
2. After each merge, compare: if error count > baseline → revert. If error count <= baseline → pass (the merge didn't make things worse).
3. If baseline capture fails (typecheck broken from the start): skip L4 with warning.

### L5: Grep produces false positives

**Scenario:** Two files define `class Config` — one is `src/api/config.ts` (API config) and the other is `src/frontend/config.ts` (frontend config). Same name, completely unrelated types.

**Handling:** The grep scan flags this as a duplicate. The type-auditor agent is spawned and reads both definitions. The agent determines they are semantically different (different fields, different usage contexts) and marks them as **false positive** — no consolidation needed. The agent logs: `[AUDIT] "Config" in src/api/ and src/frontend/ are semantically distinct. No consolidation.`

To reduce false positives:
- Only scan files changed in the current wave (not the entire repo)
- Only flag names that appear in `contracts.shared_types` OR in 2+ stories' `tasks[].filePaths`
- Common names (`Config`, `Error`, `Response`, `Context`) get a higher bar — require 3+ definitions or explicit contract match

### L5: Type-auditor agent fails or produces bad consolidation

**Scenario:** The agent merges two type definitions incorrectly, or crashes mid-consolidation.

**Handling:**
- Agent crash: The consolidated file is not committed (agent didn't finish). Wave-end state is unchanged. The duplicate persists into the next wave, where L5 tries again. No harm done.
- Bad consolidation (typecheck fails after agent commits): L4 catches this on the next merge. The consolidation commit is reverted. The duplicate persists.
- Safeguard: After the auditor commits, run the full test suite. If tests fail, revert the auditor's commit and log: `[AUDIT] Consolidation of <TypeName> broke tests. Reverted. Manual resolution needed.`

### Concurrent wave transitions

**Scenario:** Wave 3 has 5 stories. Stories 1-3 finish and merge. Story 4 finishes while L5 audit is running for stories 1-3. Story 5 is still running.

**Handling:** L5 audit runs only when ALL stories in the wave have completed (passed, failed, or timed out). This is already the behavior described in `orchestrator.md` Step 3B: "When all agents in the wave finish, run the full Integration Check." L5 is added to this existing synchronization point. Stories that complete early wait at the wave boundary.

## Testing Strategy

### Test Categories

Testing follows 3 tiers: unit tests for individual functions, integration tests for layer interactions, and end-to-end validation on a real project.

### Tier 1: Unit Tests (shell scripts in `tests/`)

**L1: Contract shape generation** — tested via the ql-plan skill on sample PRDs.

| Test file | What it tests |
|---|---|
| `tests/test_contract_shapes.sh` | Given a sample quantum.json with 2 stories sharing a type, verify the planner outputs `shape`, `definition`, `owner`, `consumers`, and `definitionFile` fields |
| `tests/test_contract_shapes.sh` | Given stories with no shared types, verify no `shape`/`definition` fields are generated (backward compat) |
| `tests/test_contract_shapes.sh` | Given a Python project (pyproject.toml), verify `definition` contains a Python Protocol, not a TS interface |

**L2: Contract materialization** — tested via `lib/materialize.sh` functions.

| Test file | What it tests |
|---|---|
| `tests/test_materialize.sh` | `detect_language()`: tsconfig.json → "typescript", pyproject.toml → "python", go.mod → "go", none → "unknown" |
| `tests/test_materialize.sh` | `materialize_contracts()`: given quantum.json with 2 multi-consumer types, verify 2 files written to correct paths |
| `tests/test_materialize.sh` | `materialize_contracts()`: given a single-consumer type, verify it is NOT materialized |
| `tests/test_materialize.sh` | `generate_definition_file()`: when `definition` field present, file content matches verbatim |
| `tests/test_materialize.sh` | `generate_definition_file()`: when file already exists with different content, skip with warning (no overwrite) |
| `tests/test_materialize.sh` | `materialize_contracts()`: reads `execution.discoveredContracts` and materializes those too (feedback loop) |
| `tests/test_materialize.sh` | Git commit created with message matching "chore: materialize contracts for Wave N" |

**L3: Escalate-on-conflict merge** — tested via `lib/monitor.sh` functions.

| Test file | What it tests |
|---|---|
| `tests/test_merge_escalation.sh` | Merge with no conflicts: returns 0 (unchanged behavior) |
| `tests/test_merge_escalation.sh` | Merge with conflict on story-specific file (e.g., `src/feature/handler.ts`): returns 1, story failed with `phase: "merge_conflict"` |
| `tests/test_merge_escalation.sh` | Merge with conflict on barrel export (`index.ts`): returns 1, log identifies it as shared-file conflict |
| `tests/test_merge_escalation.sh` | Conflict file list is captured in `retries.failureLog[].error` |

**L4: Post-merge typecheck gate** — tested via `lib/monitor.sh` functions.

| Test file | What it tests |
|---|---|
| `tests/test_typecheck_gate.sh` | `post_merge_typecheck()` with passing typecheck: returns 0 |
| `tests/test_typecheck_gate.sh` | With failing typecheck (new errors above baseline): reverts merge, returns 1, logs `phase: "merge_typecheck"` |
| `tests/test_typecheck_gate.sh` | With pre-existing errors equal to baseline: passes (doesn't penalize inherited errors) |
| `tests/test_typecheck_gate.sh` | Auto-detect: tsconfig.json present → runs `tsc --noEmit` |
| `tests/test_typecheck_gate.sh` | Auto-detect: no config files → skips with warning, returns 0 |
| `tests/test_typecheck_gate.sh` | Explicit `typecheckCommand` in quantum.json overrides auto-detect |
| `tests/test_typecheck_gate.sh` | Command not found (exit 127): skips with warning, returns 0 (doesn't fail story for missing tooling) |

**L5: Wave-end type audit** — tested via `lib/type-audit.sh` functions.

| Test file | What it tests |
|---|---|
| `tests/test_type_audit.sh` | `grep_duplicate_definitions()`: given 2 files with `interface Foo`, returns `[{name: "Foo", files: [...]}]` |
| `tests/test_type_audit.sh` | Given 0 duplicates, returns empty array (fast path, no agent spawned) |
| `tests/test_type_audit.sh` | Only scans files changed in the current wave, not entire repo |
| `tests/test_type_audit.sh` | Python pattern: detects `class Foo(Protocol)` and `class Foo(BaseModel)` |
| `tests/test_type_audit.sh` | Go pattern: detects `type Foo interface` and `type Foo struct` |
| `tests/test_type_audit.sh` | `update_contracts_for_next_wave()`: writes to `execution.discoveredContracts` in quantum.json |

### Tier 2: Integration Tests

These test layer interactions — scenarios where multiple layers cooperate.

| Test | Layers | Scenario |
|---|---|---|
| `tests/integration/test_materialize_then_merge.sh` | L2 → L3 | Materialize contracts, spawn 2 mock worktrees that import from materialized files, merge both — verify no conflicts |
| `tests/integration/test_conflict_retry.sh` | L3 → L2 | Story fails with merge_conflict in Wave 1. Verify retry in Wave 2 sees the merged state and succeeds |
| `tests/integration/test_typecheck_after_merge.sh` | L3 → L4 | Successful merge introduces type error. Verify L4 catches it, reverts, and marks story failed |
| `tests/integration/test_audit_feedback_loop.sh` | L5 → L2 | L5 discovers duplicate type in Wave 2. Verify L2 materializes it before Wave 3 |
| `tests/integration/test_baseline_typecheck.sh` | L4 | Project with pre-existing type errors. Verify baseline captured and only new errors trigger revert |

### Tier 3: End-to-End Validation

After all layers are implemented, run quantum-loop on a controlled test project designed to trigger each failure pattern:

**Test project:** A small TypeScript project with 6 stories and deliberate traps:

| Story pair | Trap | Expected behavior |
|---|---|---|
| US-A + US-B | Both need `SharedConfig` type (declared in contracts) | L2 materializes `SharedConfig`. Both agents import it. No divergence. |
| US-C + US-D | Both need `EventPayload` type (NOT in contracts — planner missed it) | L5 detects duplicate after wave, spawns auditor, consolidates. Next wave has it materialized. |
| US-E + US-F | Both modify `types/index.ts` (barrel export) | L3 escalates conflict. US-F retries next wave, sees US-E's merged changes, succeeds. |

**Success criteria:**
- 0 type divergence issues in post-merge review
- All 6 stories pass (some via retry)
- Post-mortem Contract Effectiveness section shows: 1 materialized, 1 discovered by L5, 1 conflict escalated and resolved via retry
- No `as any` casts in final codebase

### What NOT to test

- **ql-plan's ability to detect shared types in arbitrary PRDs** — this is AI judgment, not deterministic logic. We test that the output format is correct, not that the AI makes perfect decisions. Real-world validation (Tier 3) covers this.
- **Type-auditor agent's consolidation quality** — agent behavior is non-deterministic. We test that the auditor is spawned when needed, and that bad consolidations are caught by L4's typecheck. The agent itself is tested by running it, not by unit-testing its prompt.
- **Every language combination** — Test TypeScript thoroughly (most common), Python for secondary coverage, Go as a smoke test. Don't build a test matrix for every language edge case.

## Open Questions

- Should the type-auditor agent be allowed to modify `contracts.shared_types` directly, or should it only write to `execution.discoveredContracts` and let the orchestrator promote them? (Current design: auditor writes to discoveredContracts only, orchestrator promotes.)
- Should the planner generate `definitionFile` paths using a convention (`src/shared/types/<kebab-name>.<ext>`) or let the user configure a shared types directory? (Current design: convention-based.)
- What is the right typecheck timeout? 60 seconds is proposed, but large monorepos may need more. Consider making it configurable via `typecheckTimeout` in quantum.json.
- Should `execution.discoveredContracts` be promoted to permanent `contracts.shared_types` at the end of execution? This would benefit future runs on the same branch but modifies the planning artifact.

## Next Steps

Run `/quantum-loop:spec` to generate a formal Product Requirements Document from this design.
