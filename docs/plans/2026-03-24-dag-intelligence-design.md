# Design: DAG Intelligence — Parallel Specialist Validation for ql-plan

**Date:** 2026-03-24
**Status:** Approved
**Approach:** Parallel Specialists (Approach B)
**Source:** `Logical_inference/docs/post-mortems/quantum-loop-observations-2026-03-24.md`
**Post-mortem issues addressed:** #5 (sequential bottleneck), #8 (duplicate implementation), #9 (incomplete fileConflicts), partially #1 (barrel file conflicts), #10 (wave-end duplication gap)

## Overview

**What we're building:** A post-generation DAG validation system for `ql-plan` that detects and fixes three classes of planning defects — sequential bottlenecks, functional duplication across stories, and incomplete `fileConflicts` — using parallel specialist agents coordinated by a `dag-validator` agent.

**Why:** The 2026-03-24 post-mortem on an 18-story, 8-wave execution revealed that the planner produces DAGs with avoidable inefficiencies: two single-story waves added ~12 minutes of idle time (#5), two stories independently implemented identical Louvain algorithms wasting ~100 lines (#8), and `fileConflicts` missed the most-conflicting file in the project causing ~10 manual merge resolutions (#9). These are all detectable at planning time before any agent is spawned.

**How it fits into the existing flow:**

```
Today:    ql-plan -> [user reviews quantum.json] -> ql-execute

Proposed: ql-plan -> dag-validator (spawns 3 parallel specialists)
                  -> restructure DAG + create stubs
                  -> re-invoke planner for stubs only
                  -> [user reviews quantum.json + DAG Health Report]
                  -> ql-execute
```

**Key constraint:** The validation system only modifies `quantum.json` — it does not touch source code. All changes are DAG restructuring (dependency edges, story ordering, extracted stubs) and metadata annotations (`fileConflicts`, duplication warnings). The user sees the restructured DAG during their normal plan review step and can revert any specific change.

**Files involved:** `agents/dag-validator.md` (new), `agents/bottleneck-analyzer.md` (new), `agents/duplication-detector.md` (new), `agents/conflict-auditor.md` (new), `skills/ql-plan/SKILL.md` (modified), `skills/ql-plan/references/dag-validation.md` (new reference).

## User Experience

**What changes for the user during `/ql-plan`:**

Today, `ql-plan` generates `quantum.json` and the user reviews it. After this change, the user sees one additional output block before their review — a **DAG Health Report** — and the DAG they review may have been restructured.

**New output the user sees after plan generation:**

```
[DAG-VALIDATOR] Analyzing plan (18 stories, 47 tasks)...
  [BOTTLENECK]  Analyzing dependency chains...
  [DUPLICATION]  Scanning for shared algorithms...
  [CONFLICTS]   Computing fileConflicts from filePaths...

[DAG-VALIDATOR] Analysis complete.

-- DAG Health Report -----------------------------------------------

Bottlenecks found: 1
  ! Linear chain: US-001 -> US-002 -> US-003 (3 sequential waves)
    Fix applied: Extracted US-001B "Shared types stub" from US-001.
    US-002 and US-003 now depend on US-001B instead of US-001.
    Impact: Waves reduced from 8 -> 6, max parallelism 3 -> 4.

Duplication risks: 1
  ! US-008 (DomainInferencer) and US-013 (CrossRepoAnalyzer)
    Both reference: "community detection", "Louvain algorithm"
    LLM confirmed: semantically overlapping implementation
    Fix applied: Created stub US-000 "Shared Louvain utility"
    US-008 and US-013 now depend on US-000.

fileConflicts auto-computed: 4 pairs
  + src/features/v2/index.ts  (US-003, US-005, US-007, US-009, US-011)
  + demo/pipeline.ts          (US-012, US-014)
  + src/graph/wiki-types.ts   (US-008, US-013)
  + src/shared/types/index.ts (US-001, US-003, US-005)

Stubs requiring planner flesh-out: 2
  -> US-001B: Shared types stub (fleshed out)
  -> US-000: Shared Louvain utility (fleshed out)

----------------------------------------------------------------
```

**User interaction at review time:**

The user reviews `quantum.json` as today — nothing changes about the review step itself. The restructured DAG and new stub stories are already in `quantum.json`. If the user disagrees with a restructuring:

- They can manually edit `quantum.json` to revert (e.g., remove the stub story and restore the original dependency)
- Or they can tell Claude: "Revert the bottleneck fix on US-001, keep the duplication extraction"

**No new commands or flags.** The validation runs automatically as the final step of `ql-plan`. If the validator finds nothing to fix, the report says "No issues found" and the flow is identical to today.

**During `/ql-execute`:** No UX changes. Stub stories that were fleshed out by the planner execute like any other story. The only visible difference is potentially fewer waves and fewer merge conflicts.

## Data Model

**No new fields in `quantum.json`.** This design reuses existing schema structures. The changes are about what gets *populated* and one new metadata block in the plan output.

### Auto-computed `fileConflicts`

Today, `fileConflicts` is manually enumerated by the planner:

```json
"fileConflicts": [
  {"files": ["demo/pipeline.ts"], "stories": ["US-012", "US-014"]}
]
```

After this change, the conflict auditor computes it mechanically by intersecting all stories' task `filePaths` arrays. Same schema, just complete:

```json
"fileConflicts": [
  {"files": ["demo/pipeline.ts"], "stories": ["US-012", "US-014"]},
  {"files": ["src/features/v2/index.ts"], "stories": ["US-003", "US-005", "US-007", "US-009", "US-011"]},
  {"files": ["src/graph/wiki-types.ts"], "stories": ["US-008", "US-013"]},
  {"files": ["src/shared/types/index.ts"], "stories": ["US-001", "US-003", "US-005"]}
]
```

### Stub stories

Extracted stub stories use the existing story schema with a `stubSource` marker in the `notes` field so the planner knows to flesh them out:

```json
{
  "id": "US-000",
  "title": "Shared Louvain community detection utility",
  "priority": 1,
  "status": "pending",
  "dependsOn": ["US-001"],
  "notes": "STUB: extracted by dag-validator from US-008 + US-013 duplication. Planner must flesh out tasks and acceptance criteria.",
  "tasks": [],
  "acceptanceCriteria": [],
  "filePaths": [],
  "retries": {"maxAttempts": 3, "attempts": 0, "failureLog": []}
}
```

After the planner fleshes it out, `tasks`, `acceptanceCriteria`, and `filePaths` are populated and `notes` is updated to remove the `STUB:` prefix.

### DAG Health Report

Stored as a new top-level field `dagValidation` in `quantum.json` for traceability:

```json
"dagValidation": {
  "timestamp": "2026-03-24T14:30:00Z",
  "bottlenecks": [
    {
      "chain": ["US-001", "US-002", "US-003"],
      "fix": "extracted US-001B as shared types stub",
      "wavesReduced": {"before": 8, "after": 6}
    }
  ],
  "duplicationRisks": [
    {
      "stories": ["US-008", "US-013"],
      "keywords": ["community detection", "Louvain algorithm"],
      "fix": "extracted US-000 as shared utility stub"
    }
  ],
  "fileConflictsComputed": 4,
  "stubsCreated": ["US-000", "US-001B"]
}
```

This field is informational only — no runtime code reads it. It exists so the user can review what the validator changed and so post-mortem generation can report on validator effectiveness.

### Dependency updates on downstream stories

When the validator extracts a stub (e.g., US-000 from US-008 + US-013), it also modifies the `dependsOn` arrays of the consuming stories:

- **Before:** `US-008.dependsOn: ["US-001"]`, `US-013.dependsOn: ["US-008"]`
- **After:** `US-008.dependsOn: ["US-001", "US-000"]`, `US-013.dependsOn: ["US-008", "US-000"]`

No new fields needed — this is a value change on existing `dependsOn` arrays.

## Architecture

### Component Overview

```
ql-plan SKILL.md (modified)
  |-- Existing: Generate DAG, stories, tasks, contracts
  |-- New inline: Auto-compute fileConflicts from filePaths intersections
  +-- New final step: Spawn dag-validator agent
        |
        |-- Spawns 3 specialists in parallel:
        |   |-- bottleneck-analyzer agent
        |   |-- duplication-detector agent
        |   +-- conflict-auditor agent
        |
        |-- Collects 3 structured reports
        |-- Applies changes in order:
        |   1. Bottleneck restructuring (modifies DAG shape)
        |   2. Duplication extraction (creates stubs, adds dependencies)
        |   3. fileConflicts recomputation (on the restructured DAG)
        |
        |-- Writes restructured quantum.json + dagValidation metadata
        +-- Returns stub story IDs to ql-plan

  ql-plan re-invokes planner for stub stories only
  +-- Planner fills tasks, acceptanceCriteria, filePaths for each stub
```

### Agent Responsibilities

**`dag-validator`** (coordinator) — `agents/dag-validator.md`
- Receives: `quantum.json` path, PRD path
- Spawns the three specialists as parallel subagents
- Collects their reports
- Applies restructuring in deterministic order (bottleneck -> duplication -> conflicts)
- Resolves contradictions: if bottleneck restructuring creates a new story that shares `filePaths` with existing stories, the conflict recomputation catches it automatically since it runs last
- Creates stub stories with `STUB:` marker in notes
- Writes updated `quantum.json` and `dagValidation` block
- Returns: list of stub story IDs + DAG Health Report text

**`bottleneck-analyzer`** (specialist) — `agents/bottleneck-analyzer.md`
- Receives: stories array with `dependsOn` edges
- Builds adjacency list, computes wave assignment via topological sort
- Detects: linear chains of length > 2, waves with only 1 story, stories that block 5+ downstream stories
- For each bottleneck, proposes a restructuring:
  - If a story's only dependency is a "types-only" story -> suggest extracting shared types into a stub that can run in Wave 1
  - If a single story blocks N stories -> suggest splitting into parallel subtasks
  - If a chain A -> B -> C exists where B doesn't actually consume A's code output (only its types) -> suggest relaxing the dependency to a shared types stub
- Returns: structured JSON report with `chain`, `fix`, `newStories[]`, `modifiedDependsOn[]`

**`duplication-detector`** (specialist) — `agents/duplication-detector.md`
- Receives: stories array with titles, descriptions, acceptance criteria, task descriptions
- Phase 1 (keyword pre-filter): Extracts technical terms from each story. Computes Jaccard similarity on term sets for all story pairs. Flags pairs with similarity > 0.3.
- Phase 2 (LLM semantic check): For flagged pairs only, asks: "Do these two stories require implementing the same algorithm, data structure, or non-trivial logic? If yes, describe the shared concern."
- For each confirmed duplication, proposes extraction: new stub story with title derived from the shared concern, both original stories gain the stub as a dependency
- Returns: structured JSON report with `storyPairs`, `sharedConcern`, `proposedStub`

**`conflict-auditor`** (specialist) — `agents/conflict-auditor.md`
- Receives: stories array with task `filePaths`
- Computes intersection: for every file path, collects which stories touch it
- Filters to files touched by 2+ stories
- Classifies conflict severity:
  - **High:** barrel/index files, shared type files, config files (likely to conflict on every parallel wave)
  - **Medium:** source files touched by 2 stories in the same wave
  - **Low:** source files touched by 2 stories in different waves (merge order resolves naturally)
- Returns: structured JSON report with `fileConflicts[]` array (same schema as quantum.json) plus severity annotations

### Orchestration Sequence

```
1. ql-plan generates quantum.json (existing flow)
2. ql-plan inline: compute preliminary fileConflicts from filePaths
3. ql-plan spawns dag-validator agent
4. dag-validator spawns 3 specialists in parallel
5. All 3 return reports (~30s wall time)
6. dag-validator applies restructuring:
   a. Bottleneck fixes -> may add stub stories, modify dependsOn
   b. Duplication fixes -> may add stub stories, modify dependsOn
   c. Conflict auditor results -> overwrite fileConflicts (recomputed on restructured DAG)
7. dag-validator writes quantum.json + dagValidation
8. dag-validator returns stub IDs + health report to ql-plan
9. ql-plan re-invokes planner with: "Flesh out these stub stories: [IDs].
   Here is the PRD and the existing quantum.json for context.
   Add tasks, acceptanceCriteria, and filePaths. Do NOT modify other stories."
10. Planner fills stubs, writes final quantum.json
11. User reviews (existing flow)
```

### File Map

| File | Status | Role |
|---|---|---|
| `agents/dag-validator.md` | NEW | Coordinator agent |
| `agents/bottleneck-analyzer.md` | NEW | Specialist: DAG shape analysis |
| `agents/duplication-detector.md` | NEW | Specialist: semantic duplication scan |
| `agents/conflict-auditor.md` | NEW | Specialist: fileConflicts computation |
| `skills/ql-plan/SKILL.md` | MODIFIED | Add validation step after DAG generation |
| `skills/ql-plan/references/dag-validation.md` | NEW | Reference doc for validation heuristics |

## Edge Cases & Error Handling

### Bottleneck analyzer finds no bottlenecks

**Scenario:** All waves have 2+ stories, no linear chains > 2, no single story blocking 5+ downstream.

**Handling:** Analyzer returns an empty `bottlenecks` array. The coordinator skips restructuring step (a) and proceeds. The DAG Health Report shows "Bottlenecks found: 0". This is the happy path — no cost beyond the analysis time.

### Duplication detector flags a false positive

**Scenario:** Keyword pre-filter flags US-004 ("build graph visualizer") and US-009 ("build dependency graph") as duplicates because both mention "graph." LLM semantic check confirms they're unrelated — one renders SVG, the other computes DAG edges.

**Handling:** The LLM phase exists specifically for this. If the LLM says "no shared implementation concern," the pair is dropped from the report. The Health Report shows it as a dismissed candidate: `"Dismissed: US-004 + US-009 (keyword overlap on 'graph', semantically distinct)."` No DAG modification.

### Duplication detector misses a true positive

**Scenario:** Two stories both need rate limiting but describe it differently — "throttle API calls" vs "enforce request quotas." Keywords don't overlap enough (Jaccard < 0.3), so the pair is never sent to LLM.

**Handling:** This is an accepted limitation of the hybrid approach. The keyword threshold (0.3) is a tunable parameter in `references/dag-validation.md`. If post-mortems repeatedly show missed duplications, the threshold can be lowered or additional synonym expansion added. The wave-end type audit (L5, already implemented) remains the runtime safety net for duplication that slips through planning.

### Bottleneck restructuring creates a circular dependency

**Scenario:** The analyzer proposes extracting US-001B from US-001, and making US-002 depend on US-001B instead of US-001. But US-001B itself depends on US-002 (because the shared types reference a type that US-002 defines).

**Handling:** After applying all restructuring, the coordinator runs a cycle detection pass (topological sort on the modified DAG). If a cycle is detected:
1. Revert the specific restructuring that introduced the cycle
2. Log in the Health Report: `"Reverted: US-001B extraction would create cycle US-001B -> US-002 -> US-001B"`
3. The original bottleneck remains — it's reported but unfixed

This is a hard gate. The coordinator never writes a DAG with cycles to `quantum.json`.

### Stub story creation collides with existing story IDs

**Scenario:** The validator wants to create US-000 but that ID already exists.

**Handling:** The coordinator generates stub IDs by finding the lowest unused ID. It reads all existing story IDs, computes `max(numeric_suffix) + 1` for new stories, and uses a suffix convention: `US-019-A`, `US-019-B` for extracted stubs. This avoids collision with both existing and future planner-generated IDs.

### Planner fails to flesh out a stub

**Scenario:** The planner is re-invoked for stubs but produces empty or malformed output for one stub.

**Handling:** After the planner returns, `ql-plan` validates each stub: `tasks.length > 0` and `acceptanceCriteria.length > 0`. If a stub fails validation:
1. Remove the stub story from `quantum.json`
2. Revert the `dependsOn` modifications that referenced it
3. Log in Health Report: `"Stub US-000 could not be fleshed out — reverted to original DAG structure"`
4. The underlying duplication/bottleneck remains but the DAG is valid

The principle: a failed validation step always reverts cleanly to the pre-validation DAG. The validator never makes the plan worse.

### Specialist agent crashes or times out

**Scenario:** One of the three parallel specialists crashes mid-analysis (e.g., context overflow on a 50-story plan).

**Handling:** The coordinator waits for all three with a timeout (90 seconds per specialist). If a specialist fails:
- Its analysis is skipped
- The coordinator proceeds with the reports from the other two
- Health Report notes: `"! bottleneck-analyzer timed out — bottleneck analysis skipped for this plan"`
- The DAG still benefits from the other two analyses

No specialist is required for the plan to proceed. All three are independently valuable — graceful degradation.

### Very small plans (< 5 stories)

**Scenario:** A plan has only 3 stories. Running 3 parallel specialist agents is overkill.

**Handling:** The coordinator checks story count before spawning specialists:
- **< 5 stories:** Skip bottleneck analysis (too few stories for meaningful parallelism gains). Run duplication and conflict auditor only, sequentially within the coordinator (no sub-spawn).
- **5-15 stories:** Run all three, but sequentially within the coordinator to avoid agent spawn overhead exceeding analysis time.
- **16+ stories:** Full parallel specialist spawn.

These thresholds are configurable in `references/dag-validation.md`.

## Testing Strategy

### Tier 1: Unit Tests per Specialist

**Bottleneck Analyzer**

| Test | Input | Expected Output |
|---|---|---|
| Linear chain detection | Stories: A->B->C->D (chain of 4) | Flags chain `[A,B,C,D]`, proposes extraction |
| No bottleneck | Stories: A, B, C all independent | Empty `bottlenecks` array |
| Single-story wave detection | DAG where Wave 2 has only 1 story, Waves 1,3 have 3+ | Flags the single-story wave |
| Fan-out blocker | Story A blocks B,C,D,E,F (5+ downstream) | Flags A as fan-out blocker, proposes split |
| Types-only dependency relaxation | B depends on A, but A only produces type definitions | Proposes extracting types stub so B can run in parallel with A |
| Already optimal DAG | 4 waves, all with 3+ stories, no chains > 2 | "No bottlenecks found" |

**Duplication Detector**

| Test | Input | Expected Output |
|---|---|---|
| Keyword match triggers LLM | US-008 mentions "Louvain", "community detection"; US-013 mentions "Louvain", "graph clustering" | Jaccard > 0.3, LLM confirms overlap, proposes stub |
| Keyword match, LLM rejects | US-004 "build graph visualizer", US-009 "build dependency graph" | Jaccard > 0.3 on "graph"+"build", LLM says semantically distinct, dismissed |
| No keyword overlap | All stories have distinct technical vocabularies | No pairs flagged, no LLM calls |
| Three-way duplication | US-008, US-013, US-017 all mention "rate limiting" | All three pairs flagged; single shared stub created with all three as consumers |
| Threshold tuning | Two stories share 1 keyword out of 10 each (Jaccard ~0.1) | Below 0.3 threshold, not flagged |

**Conflict Auditor**

| Test | Input | Expected Output |
|---|---|---|
| Index.ts in 5 stories | 5 stories all list `src/features/v2/index.ts` in `filePaths` | `fileConflicts` entry with severity "high" |
| No overlapping files | Each story touches unique files | Empty `fileConflicts` array |
| Two stories, same wave | US-003 and US-005 both touch `config.ts`, assigned to Wave 2 | Severity "medium" (same wave) |
| Two stories, different waves | US-003 (Wave 1) and US-012 (Wave 5) share `pipeline.ts` | Severity "low" (merge order resolves) |
| Barrel file classification | File named `index.ts`, `index.py`, `__init__.py`, or `mod.rs` | Auto-classified as severity "high" regardless of story count |

### Tier 2: Coordinator Integration Tests

| Test | Scenario | Expected Behavior |
|---|---|---|
| All three specialists return results | Bottleneck: 1 fix, Duplication: 1 stub, Conflicts: 3 pairs | All applied in order. Stub appears in stories. `fileConflicts` recomputed on restructured DAG. `dagValidation` has all three sections populated. |
| Bottleneck fix creates new conflict | Extracted stub US-001B touches `types/index.ts` which 3 other stories also touch | Conflict auditor (running last) catches it. `fileConflicts` includes the new entry. |
| Cycle detection after restructuring | Bottleneck fix introduces A->B->A cycle | Fix reverted. Health Report logs the revert. Original bottleneck remains. DAG is cycle-free. |
| One specialist times out | Duplication detector exceeds 90s | Coordinator proceeds with bottleneck + conflict results only. Health Report notes: "duplication analysis skipped (timeout)". |
| All specialists return empty | No bottlenecks, no duplication, no conflicts | `dagValidation` written with all-empty arrays. Health Report: "No issues found." quantum.json unchanged except for `dagValidation` block. |
| Small plan bypass | 3-story plan | No sub-agents spawned. Coordinator runs conflict computation inline. Bottleneck and duplication analysis skipped. |
| Stub ID collision | Existing stories US-001 through US-018 | New stubs get IDs US-019-A, US-019-B. No collision. |

### Tier 3: Stub Flesh-Out Tests

| Test | Scenario | Expected Behavior |
|---|---|---|
| Planner successfully fills stub | Stub US-000 "Shared Louvain utility" with PRD context | `tasks.length > 0`, `acceptanceCriteria.length > 0`, `filePaths.length > 0`, `notes` no longer has `STUB:` prefix |
| Planner returns empty stub | Stub too vague for planner to flesh out | Stub removed from quantum.json, `dependsOn` references reverted, Health Report notes the revert |
| Multiple stubs fleshed out | 2 stubs from bottleneck + 1 from duplication | All 3 validated independently. Partial failure (1 of 3 fails) reverts only the failed stub |

### Tier 4: End-to-End Validation

Replay the actual 2026-03-24 Hierarchical Feature Extraction plan through the validator:

**Setup:** Take the original `quantum.json` from the Logical_inference execution (18 stories, 8 waves) and feed it to the dag-validator.

**Expected results:**
- Bottleneck analyzer flags the US-001->US-002->US-003 chain and the two single-story waves
- Duplication detector flags US-008 + US-013 (both mention community detection / Louvain)
- Conflict auditor computes `src/features/v2/index.ts` in 5+ stories (the file the post-mortem says was missed)
- Waves reduced from 8 -> fewer (target: 6)
- One shared utility stub created for the Louvain algorithm

**Success criteria:**
- All three issues from the post-mortem (#5, #8, #9) would have been caught
- No cycles introduced
- Stub stories are valid and flesh-able
- Total validation time < 2 minutes

### What NOT to Test

- **Planner's initial DAG quality** — We're validating the DAG, not generating it. The planner's AI judgment is tested by running real plans.
- **LLM semantic accuracy** — The duplication detector's LLM phase is non-deterministic. We test that the LLM is called on the right pairs, not that it always gives the right answer. False negatives are caught by runtime L5 audit.
- **Orchestrator behavior with restructured DAGs** — The orchestrator already handles any valid quantum.json. Our job is to produce a valid one.

## Open Questions

- Should the Jaccard similarity threshold (0.3) for duplication pre-filtering be configurable per-project, or is a single default sufficient? Post-mortem data from future runs will inform this.
- Should the bottleneck analyzer consider story estimated complexity (task count, file count) when deciding whether a single-story wave is worth optimizing? A 1-story wave with 8 tasks may not be a bottleneck if the story is genuinely large.
- Should the conflict-auditor's severity classifications influence the orchestrator's wave scheduling (e.g., never co-schedule stories with "high" severity conflicts), or is the annotation purely informational for human review?
- What is the right specialist timeout? 90 seconds is proposed, but very large plans (50+ stories) with many story pairs for duplication checking may need more. Consider making it configurable.

## Next Steps

Run `/quantum-loop:ql-spec` to generate a formal Product Requirements Document from this design.
