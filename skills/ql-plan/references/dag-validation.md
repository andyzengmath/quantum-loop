# DAG Validation Reference

Configuration and rules for the dag-validator coordinator and its specialist agents. Load this reference before performing any DAG validation step.

---

## Standard Stop-Words

The following terms are excluded from keyword extraction during duplication detection. These words appear frequently in story titles and descriptions but carry no implementation-specific meaning. Removing them prevents false-positive Jaccard similarity matches.

- implement
- create
- add
- build
- test
- update
- module
- component
- function
- class
- handle
- setup
- configure
- write
- define
- use
- make
- get
- set
- run
- ensure
- support
- include
- provide
- allow

When extracting keywords from story titles, descriptions, and acceptance criteria, strip all terms in this list before computing similarity.

---

## Project-Configurable Stop-Words

Projects may define additional stop-words that are domain-specific and should be excluded from duplication analysis. These are specified via the `dagValidation.stopWords` array in `quantum.json`.

Example configuration:

```json
{
  "dagValidation": {
    "stopWords": ["widget", "dashboard", "endpoint", "migration"]
  }
}
```

When this array is present, the duplication-detector concatenates it with the standard stop-words list above before keyword extraction. Duplicate entries are ignored. The combined list is case-insensitive: `"Widget"` and `"widget"` are treated as the same term.

If the `dagValidation.stopWords` field is absent or empty, only the standard stop-words are used.

---

## Jaccard Threshold

The duplication-detector uses Jaccard similarity to identify story pairs with overlapping technical keywords. Jaccard similarity is defined as:

```
J(A, B) = |A intersection B| / |A union B|
```

Where `A` and `B` are the sets of technical keywords extracted from two stories (after stop-word removal).

**Default threshold:** `0.3`

Story pairs with `J(A, B) > 0.3` are flagged for Phase 2 LLM semantic verification. Pairs at or below the threshold are not flagged.

**Override:** Projects can adjust the threshold via `dagValidation.jaccardThreshold` in `quantum.json`:

```json
{
  "dagValidation": {
    "jaccardThreshold": 0.25
  }
}
```

**Guidance on threshold selection:**

| Threshold | Behavior |
|---|---|
| `< 0.2` | Aggressive: flags many pairs, higher false-positive rate, more LLM calls |
| `0.25 - 0.35` | Balanced: catches most genuine overlaps with manageable false positives |
| `> 0.4` | Conservative: only flags strong overlaps, may miss subtle duplication |

If `dagValidation.jaccardThreshold` is absent, the default `0.3` is used.

---

## Bottleneck Heuristics

The bottleneck-analyzer detects three classes of structural inefficiency in the dependency DAG. Each heuristic runs independently and produces a report entry.

### 1. Linear Chain Detection

A linear chain is a sequence of stories where each story depends on exactly one predecessor, and each predecessor has exactly one downstream consumer, forming a strict A -> B -> C path with no branching.

**Trigger:** Flag chains of length > 2 (three or more stories in strict sequence).

**Why it matters:** Linear chains prevent any parallelism. If stories in the chain only share type dependencies (not logic dependencies), the chain can be shortened by extracting shared types into a stub.

**Example DAG:**

```
US-001 --> US-002 --> US-003 --> US-004
```

All four stories are strictly sequential. This is a linear chain of length 4.

**Expected detection output:**

```json
{
  "type": "linear_chain",
  "chain": ["US-001", "US-002", "US-003", "US-004"],
  "length": 4,
  "fix": "Examine dependencies between US-001 and US-004. If US-002 and US-003 depend on US-001 only for shared types, extract a types-only stub (US-001-A) and allow US-002, US-003, US-004 to depend on the stub in parallel."
}
```

### 2. Single-Story Wave Detection

A wave is a set of stories that can execute in parallel (all their dependencies are satisfied). A single-story wave contains only one story, meaning no parallelism is achieved in that execution round.

**Trigger:** Flag any wave containing exactly 1 story.

**Why it matters:** Single-story waves are serialization points. If the solo story could be merged into an adjacent wave (by relaxing a dependency), total execution time decreases.

**Example DAG:**

```
Wave 1:  US-001, US-002, US-003  (3 stories in parallel)
Wave 2:  US-004                   (1 story -- bottleneck)
Wave 3:  US-005, US-006           (2 stories in parallel)
```

Wave 2 is a single-story wave.

**Expected detection output:**

```json
{
  "type": "single_story_wave",
  "wave": 2,
  "story": "US-004",
  "fix": "Check if US-004's dependency on Wave 1 stories can be narrowed to a types-only stub, allowing US-004 to run in Wave 1."
}
```

### 3. Fan-Out Blocker Detection

A fan-out blocker is a story that has 5 or more direct downstream dependents. If this story is delayed or fails, it blocks a large portion of the plan.

**Trigger:** Flag stories where `downstream_count >= 5`.

**Why it matters:** Fan-out blockers are high-risk serialization points. If the blocker provides only types or configuration, extracting a lightweight stub can unblock dependents earlier.

**Example DAG:**

```
         US-001
        /  |  |  \  \
  US-002 US-003 US-004 US-005 US-006
```

US-001 blocks 5 downstream stories.

**Expected detection output:**

```json
{
  "type": "fan_out_blocker",
  "blocker": "US-001",
  "downstream": ["US-002", "US-003", "US-004", "US-005", "US-006"],
  "downstreamCount": 5,
  "fix": "If US-001 has storyType 'types-only', extract a stub (US-001-A) containing only the type definitions. Consumers depend on US-001-A instead. If US-001 has storyType 'logic', report warning only -- logic dependencies cannot be safely stubbed."
}
```

---

## Severity Classification

The conflict-auditor classifies each file conflict by severity based on the file type and the wave relationship of the conflicting stories.

| Severity | Criteria | Examples |
|---|---|---|
| **high** | Barrel/index files, shared type definition files, project config files | `index.ts`, `index.js`, `index.tsx`, `index.jsx`, `__init__.py`, `mod.rs`, `lib.rs`, `doc.go`, `types.ts`, `shared/types/*.ts`, `quantum.json`, `tsconfig.json`, `package.json`, `pyproject.toml` |
| **medium** | Source files touched by 2+ stories scheduled in the same wave | `src/auth/login.ts` modified by US-002 and US-003, both in Wave 1 |
| **low** | Source files touched by 2+ stories scheduled in different waves | `src/utils/format.ts` modified by US-001 (Wave 1) and US-005 (Wave 3) |

**Resolution rules by severity:**

- **high:** The dag-validator injects synthetic `dependsOn` edges so conflicting stories never execute in the same wave. The highest-priority story (lowest priority number) runs first; all other stories in the conflict group depend on it.
- **medium:** The dag-validator reports the conflict in the DAG Health Report. The orchestrator uses merge-conflict resolution at wave boundaries.
- **low:** Informational only. Logged in the DAG Health Report for awareness. No structural changes.

---

## Plan Size Thresholds

The dag-validator coordinator adjusts its execution strategy based on the number of stories in the plan. Smaller plans do not benefit from the overhead of parallel specialist agents.

| Story Count | Strategy | Rationale |
|---|---|---|
| **< 5 stories** | Skip bottleneck analysis. Run duplication-detector and conflict-auditor sequentially within the coordinator. | Too few stories for meaningful parallelism gains. Bottleneck restructuring on 3-4 stories risks over-engineering. |
| **5 - 15 stories** | Run all three specialists (bottleneck-analyzer, duplication-detector, conflict-auditor) sequentially within the coordinator. | Moderate plan size benefits from all analyses, but the overhead of parallel agent spawning is not justified. |
| **16+ stories** | Spawn all three specialists as parallel subagents. | Large plans benefit from parallel execution. Each specialist operates on the full stories array independently, and the coordinator merges their results after all three complete. |

The coordinator reads `stories.length` from quantum.json and selects the strategy before invoking any specialist. The threshold boundaries are inclusive on the lower end: a plan with exactly 5 stories uses the "5 - 15" strategy; a plan with exactly 16 stories uses the "16+" strategy.

---

## Barrel File Patterns

Barrel files (also called index files or re-export files) aggregate exports from a directory into a single entry point. Because multiple stories frequently need to add exports to the same barrel file, these files are high-severity conflict targets.

The conflict-auditor uses the following patterns to identify barrel files per language:

| Language | Barrel File Names |
|---|---|
| **TypeScript** | `index.ts`, `index.js`, `index.tsx`, `index.jsx` |
| **Python** | `__init__.py` |
| **Rust** | `mod.rs`, `lib.rs` |
| **Go** | `doc.go` |

**Detection rule:** When the conflict-auditor encounters a file in the `fileConflicts` set whose basename matches any pattern in the table above, it automatically classifies the conflict as severity `"high"`, regardless of the wave relationship between the conflicting stories.

**Why barrel files are always high severity:**

1. **Merge conflict probability is near 100%.** Two agents adding exports to the same barrel file will almost always produce conflicting diffs (adjacent or overlapping lines).
2. **Semantic merge is insufficient.** Even if lines do not textually conflict, the order of exports or the combination of re-exports may cause runtime issues (circular dependencies, initialization order).
3. **Prevention is cheaper than resolution.** Injecting a synthetic `dependsOn` edge ensures barrel file modifications are serialized, eliminating the merge conflict entirely.

The barrel file pattern list is language-specific. If a project uses multiple languages, all relevant patterns are active simultaneously. The conflict-auditor detects the project language(s) from config files in the repository root (see `contract-shapes.md` for language detection rules).
