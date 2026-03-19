# Deep Research: Worktree Isolation Type Divergence in Quantum-Loop

**Date:** 2026-03-18
**Triggered by:** [2026-03-18-quantum-loop-execution-observations.md](../../Logical_inference/docs/post-mortems/2026-03-18-quantum-loop-execution-observations.md) (Graph Construction Feature Extraction, 29 stories, 9 waves, 5 concurrent agents)
**Scope:** Root cause analysis, external solution survey, and implementation roadmap

---

## Executive Summary

The worktree isolation problem in quantum-loop is a **known, unsolved problem across the entire multi-agent development ecosystem**. The post-mortem identifies the exact same failure patterns that Anthropic themselves hit when building a C compiler with parallel agents, and that community tools like Clash, parallel-cc, and Overstory were specifically built to address. The core issue: **quantum-loop's `contracts` field stores type *names* but not type *structures*, so parallel agents agree on what to call `AliasRegistry` but create incompatible definitions of what it contains.**

No single tool solves this today. The viable path is a layered defense combining changes to `ql-plan` (prevention), the orchestrator (detection), and the merge strategy (resolution).

---

## Key Findings

- **The contracts gap is structural, not incidental**: The current `contracts.shared_types` maps names to names (`"AliasRegistry": {"value": "AliasRegistry"}`). Three agents all used the name "AliasRegistry" but created three incompatible method signatures. Name contracts prevent the Issue #2 from March 9 (google vs google-api-key) but NOT the Issue pattern from March 18 (same name, different structure). [Post-mortem, quantum.json.example]

- **No platform-level solution exists yet**: Claude Code v2.1.76 (March 14, 2026) added `worktree.sparsePaths` and `ExitWorktree`, but nothing for shared type coordination. Agent Teams (research preview) explicitly warns against multiple agents editing the same file. Feature request #28300 proposes spec negotiation but is unimplemented. [Claude Code changelog, GitHub issues]

- **Community tools address detection but not prevention**: Clash (by clash-sh) does real-time three-way merge simulation across worktree pairs -- it would catch Pattern 2 (destructive merge) but not Pattern 1 (type divergence in different files). parallel-cc does AST-based semantic analysis which could catch structural divergence, but it's beta. [GitHub repos]

- **The merge strategy is the weakest link**: `git merge --no-edit` in `lib/monitor.sh:106` is a one-line operation with no file-type awareness. It treats barrel exports (index.ts), type definitions (.d.ts), and story-specific files identically. Pattern 2 (TocService removed, DataFlowAnalyzer deregistered) is a direct consequence. [lib/monitor.sh]

- **This is a recurring, escalating problem**: March 9 post-mortem had 2 cross-story consistency bugs. March 18 post-mortem has 10 issues (7 from parallel isolation). The problem scales with parallelism -- 5 concurrent agents produce more type divergence than the previous 4-agent runs. [Post-mortems]

- **Anthropic's own C compiler project hit the same wall**: Their engineering blog describes using simple file-based task locking with no formal interface contracts, and acknowledged that when "monolithic tasks couldn't decompose into independent components, all agents hit the same bugs simultaneously." [Anthropic engineering blog]

---

## Detailed Analysis

### Problem 1: Type Divergence (7/10 issues)

**Current defense**: `contracts.shared_types` + `consumedBy` + `wiring_verification`

**Why it fails**: Contracts store `{"AliasRegistry": {"value": "AliasRegistry"}}` -- a name, not a shape. Three agents all used the name but created:
- US-007: `AliasRegistry.lookup(name: string): Module`
- US-012: `AliasRegistry.resolve(alias: string): string`
- US-013: `AliasRegistry.getByModule(mod: Module): Alias[]`

The `consumedBy` field tells agent B that agent A will provide `AliasRegistry`, but doesn't tell B what the interface looks like. Agent B can't import something that doesn't exist yet (A hasn't finished), so B creates its own version.

**The fundamental tension**: In sequential execution, each story sees the previous story's committed code. In parallel execution, stories branch from the same base -- they literally cannot see each other's work. This is an inherent property of worktree isolation, not a bug.

### Problem 2: Destructive Merge (2/10 issues)

**Current defense**: `filter_file_conflicts()` in `lib/dag-query.sh` prevents parallel stories from touching the same files.

**Why it fails**: File-conflict filtering uses `tasks[].filePaths` declared in quantum.json. But agents also modify files not in their `filePaths` -- barrel exports (`types/index.ts`), shared registries, config files. These implicit file touches aren't declared, so the filter doesn't catch them.

The merge itself (`git merge --no-edit`) has no semantic awareness. When US-028's worktree branched, `types/index.ts` had Toc types. US-028 replaced the entire file with Feature types. The merge sees "US-028 modified this file" and takes their version, deleting the Toc types that were added by a story merged between US-028's branch point and now.

### Problem 3: `as any` Bypass (1/10 issues)

**Current defense**: None explicit. Quality reviewer may flag it, but agents are instructed not to modify files outside their story scope.

**Why it fails**: When agent A needs to pass data to an interface defined by agent B's story, and B hasn't finished yet, A's only options are: (1) create its own interface (Pattern 1), (2) cast to `as any` (Pattern 3), or (3) fail the story. All three are bad outcomes.

---

## Existing Solutions Landscape

| Tool/Feature | What It Does | Addresses Pattern 1? | Pattern 2? | Pattern 3? | Maturity |
|---|---|---|---|---|---|
| **Clash** (clash-sh) | Three-way merge simulation across worktree pairs, PreToolUse hook integration | No (file-level only) | Yes | No | Production |
| **parallel-cc** | AST-based semantic conflict detection + file claims | Partially (structural analysis) | Yes | No | Beta |
| **Overstory** | FIFO merge queue with 4-tier AI-assisted resolution | No | Yes (sequential merge) | No | Beta |
| **Mux** (Coder) | Git divergence dashboard | No (visual only) | No | No | Production |
| **Claude Code Agent Teams** | Shared task list, mailbox messaging | No (same directory, no worktrees) | N/A | No | Research preview |
| **quantum-loop contracts** | Name-level type contracts | Partially (names only, not shapes) | No | No | Implemented |
| **quantum-loop fileConflicts** | Declared file ownership | No | Partially (declared files only) | No | Implemented |
| **GitHub Feature #28300** | Spec negotiation protocol between agents | Yes (by design) | Yes | Yes | Proposed only |

---

## Areas of Consensus

All sources agree on these principles:

1. **Prevention > Detection > Resolution**: Defining shared interfaces before parallel work starts is cheaper than fixing divergence after.
2. **The DAG needs type-level dependencies, not just code-level**: `dependsOn` based on files is insufficient; you need dependencies based on shared types/interfaces.
3. **Post-merge validation must be project-wide**: Running `tsc --noEmit` only in the worktree catches local errors but misses cross-story incompatibilities that only manifest after merge.
4. **Merge strategies must be file-type-aware**: Barrel exports, type definitions, and story-specific implementation files need different merge behaviors.

---

## Areas of Debate

1. **Contract stories vs. generated .d.ts files**: R1 from the post-mortem proposes "contract stories" (zero-code stories that define interfaces). An alternative is generating `shared-types.d.ts` from an enhanced contracts section (R4). The trade-off: contract stories use the existing story pipeline but add overhead; generated files are lighter but require a new mechanism in the orchestrator.

2. **Real-time coordination vs. batch validation**: Feature request #28300 proposes agents communicating via MCP during execution (real-time). R5 proposes wave-end integration review (batch). Real-time catches problems earlier but adds complexity; batch is simpler but delays detection.

3. **Worktree isolation vs. shared-directory with file locking**: Claude Code Agent Teams uses shared directories with file ownership conventions. This avoids the merge problem entirely but introduces file-overwrite risks. Some community tools (agenttools/worktree) use coordination documents instead of worktrees.

---

## Proposed Solution: 5-Layer Defense

### Layer 1: Structural Contracts in `ql-plan` (Prevention)

**Change**: Extend `contracts.shared_types` from name-only to name+shape:

```json
"contracts": {
  "shared_types": {
    "AliasRegistry": {
      "value": "AliasRegistry",
      "definitionFile": "src/shared/types/alias-registry.ts",
      "shape": {
        "methods": ["resolve(alias: string): string | null", "register(alias: string, target: string): void"],
        "properties": ["entries: Map<string, string>"]
      },
      "owner": "US-012",
      "consumers": ["US-007", "US-013"]
    }
  }
}
```

**Why this works**: Agents see not just the name but the shape. When US-007 needs `AliasRegistry`, it knows the interface has `resolve()` returning `string | null`, not `lookup()` returning `Module`.

**Implementation**: Modify the `ql-plan` skill to generate `shape` fields when two or more stories reference the same type. The planner already knows all stories -- it can detect shared concepts and define their interfaces upfront.

### Layer 2: Wave-0 Contract Materialization (Prevention)

**Change**: Before spawning Wave 1, the orchestrator materializes contracts into actual code files:

```bash
# Before parallel execution starts
for each contract in contracts.shared_types where definitionFile is set:
  1. Generate a minimal .ts/.py file with just the interface/type/protocol
  2. Commit it: "chore: materialize contract for <TypeName>"
  3. All worktrees branch from this commit, so all agents see the same interfaces
```

**Why this works**: Agents import from a real file rather than creating their own definitions. The `consumedBy` mechanism now works because the type actually exists at branch time.

**Trade-off**: Adds a few seconds to startup and requires the planner to define interfaces with enough detail. If the planner gets the interface wrong, all agents build against a wrong contract (but at least they're consistently wrong, which is easier to fix than inconsistently wrong).

### Layer 3: File-Type-Aware Merge Strategy (Resolution)

**Change**: Replace the single-line merge in `lib/monitor.sh` with a multi-strategy merge:

```bash
merge_worktree_branch() {
  # Step 1: Attempt normal merge
  if git merge "$branch" --no-edit; then return 0; fi

  # Step 2: For each conflicting file, apply file-type-specific resolution
  for file in $(git diff --name-only --diff-filter=U); do
    case "$file" in
      */index.ts|*/index.js|*/__init__.py)
        # Barrel exports: combine both sides (keep HEAD, append new exports from theirs)
        git checkout --ours "$file"
        # Extract new exports from theirs and append
        combine_barrel_exports "$file" "$branch"
        ;;
      *.d.ts|*/types/*|*/interfaces/*)
        # Type definition files: keep HEAD, append new types from theirs
        git checkout --ours "$file"
        append_new_types "$file" "$branch"
        ;;
      *)
        # Story-specific files: use theirs (agent's version)
        git checkout --theirs "$file"
        ;;
    esac
    git add "$file"
  done

  git commit --no-edit
}
```

**Why this works**: Pattern 2 (TocService removed) happened because the merge treated `types/index.ts` like a story file. With file-type awareness, barrel exports always combine both sides.

### Layer 4: Post-Merge Type Validation Gate (Detection)

**Change**: After each worktree merge, run `tsc --noEmit` (or equivalent) on the **full project**, not just story files. This already exists as a recommendation in the orchestrator (Step 3B.3 "run the full test suite to catch semantic merge regressions") but the current implementation runs tests, not typechecks. Add an explicit typecheck:

```bash
# In merge completion handler (after Step 3B.3)
if ! tsc --noEmit 2>/tmp/tsc-merge-check.txt; then
  echo "[TYPE ERROR] Post-merge typecheck failed after merging $branch"
  cat /tmp/tsc-merge-check.txt
  git revert -m 1 HEAD  # Undo the merge
  # Mark story as failed with phase: "merge_typecheck"
fi
```

### Layer 5: Wave-End Cross-Story Type Audit (Detection)

**Change**: After all agents in a wave complete, before starting the next wave, run a lightweight audit:

```bash
# For each new type/interface created by agents in this wave:
# 1. Find all definitions (grep for 'interface X' or 'type X =' or 'class X')
# 2. If same name defined in 2+ files by 2+ stories -> FLAG
# 3. Compare structural compatibility (field names, method signatures)
# 4. If incompatible -> consolidate into the contract file, update imports
```

This catches Pattern 1 even when the merge succeeds (because the types are in different files, so git doesn't see a conflict).

---

## Implementation Priority

| Layer | Effort | Impact | Addresses | Recommendation |
|---|---|---|---|---|
| L1: Structural contracts in ql-plan | Medium | High | Pattern 1 (prevention) | **Do first** -- highest ROI |
| L3: File-type-aware merge | Medium | High | Pattern 2 (resolution) | **Do second** -- fixes the merge destructor |
| L4: Post-merge typecheck gate | Low | Medium | Patterns 1+2 (detection) | **Do third** -- cheap safety net |
| L2: Wave-0 contract materialization | High | Very High | Patterns 1+3 (prevention) | **Do fourth** -- most complex but eliminates root cause |
| L5: Wave-end type audit | Medium | Medium | Pattern 1 (detection) | **Do fifth** -- catches what L1-L4 miss |

---

## External Tools Worth Integrating

1. **Clash** (`clash-sh/clash`): Install as a PreToolUse hook in the orchestrator. Before any agent writes to a file, `clash check <file>` warns if another worktree has modified it. Addresses Pattern 2 during execution rather than at merge time. Production-ready, Rust CLI, low overhead.

2. **parallel-cc** (`frankbria/parallel-cc`): Its AST-based semantic analysis could be integrated as a wave-end check (Layer 5). Beta quality -- evaluate before depending on it.

---

## Gaps and Further Research

- **No tool exists for cross-worktree type-level coordination during execution**. All solutions are either pre-execution (define contracts) or post-execution (detect divergence at merge). A real-time MCP channel between worktree agents (as proposed in #28300) would be the ideal solution, but it doesn't exist yet.
- **The `ql-plan` planner's ability to define accurate interface shapes upfront is unproven**. If the planner defines wrong interfaces, all agents build against wrong contracts. A feedback loop (failed stories update contracts for the next wave) may be needed.
- **Python projects lack a `tsc --noEmit` equivalent**. For Python-heavy projects like Logical_inference, the post-merge typecheck (Layer 4) would need `pyright` or `mypy` with strict mode, which may not be configured. Consider adding a `typecheckCommand` field to quantum.json.
- **The `fileConflicts` declaration is manually authored during planning**. Undeclared file touches (barrel exports, shared registries) bypass the filter. An automated file-touch prediction based on story descriptions could improve this.

---

## Sources

1. Post-mortem: `2026-03-18-quantum-loop-execution-observations.md` -- Primary problem description
2. Post-mortem: `2026-03-09-math-research-agent.md` -- Previous parallel execution issues (Issue #2: cross-story consistency)
3. Gap audit: `2026-03-09-gap-audit.md` -- Implementation status of previous fixes
4. Claude Code Changelog (code.claude.com/docs/en/changelog) -- v2.1.49-v2.1.76 worktree features
5. GitHub Issue #28300 -- Multi-Agent Collaboration Feature Request (proposed spec negotiation)
6. GitHub Issue #28175 -- Agent Teams worktree bug (closed, duplicate of #23715)
7. Clash (github.com/clash-sh/clash) -- Three-way merge simulation across worktrees
8. parallel-cc (github.com/frankbria/parallel-cc) -- AST-based semantic conflict detection
9. Overstory (github.com/jayminwest/overstory) -- FIFO merge queue with AI resolution
10. Anthropic Engineering Blog: "Building a C Compiler" -- Multi-agent coordination lessons
11. GitHub Blog: "Multi-Agent Workflows That Don't Fail" -- Typed schemas for data consistency
12. quantum-loop source: `lib/monitor.sh`, `lib/dag-query.sh`, `agents/orchestrator.md`, `agents/implementer.md`
