# Design: Cross-Story Integration Layer

**Date:** 2026-02-27
**Status:** Approved
**Approach:** Enhanced Existing + Reference Doc (Approach C)

## Overview

7 enhancements to quantum-loop's existing skills and agents, informed by real-world failure data from a 14-story pipeline implementation where 100% of bugs were cross-story integration issues or edge cases, and 0% were caught by per-story review gates.

**Files to modify:**
| File | Changes |
|------|---------|
| `skills/ql-plan/SKILL.md` | File-touch conflict detection, consumer verification pattern, edge case test guidance |
| `agents/orchestrator.md` | Cross-story integration review (after chains + final), post-merge import smoke test |
| `agents/implementer.md` | Edge case testing guidance, reference doc pointer |
| `skills/ql-review/SKILL.md` | Cross-story integration review mode (Stage 3) with LSP support |
| `skills/ql-verify/SKILL.md` | Import chain verification |
| `references/edge-cases.md` | **New file** — language-specific testing gotchas |

**Not changing:** quantum-loop.sh, templates/, lib/*.sh, CLAUDE.md

## ql-plan Enhancements

### File-Touch Conflict Detection (Step 5 validation)

After building the dependency DAG, scan for parallel stories that modify the same files:

- If two parallel stories (neither depends on the other) share `filePaths` entries, flag the conflict
- Add a "merge reconciliation" task to the later story that reconciles changes after both complete
- Example: US-007 and US-008 both modify generator.py → Add task to US-008: "Reconcile generator.py changes from US-007"
- Does NOT force sequential execution — allows parallel but plans for the merge

### Consumer Verification Pattern

Extend the Integration Wiring Rule:

- When Story A creates a function that Story B (a dependent) should call:
  - Story A's acceptance criteria: "function exists and passes unit tests"
  - Story B's acceptance criteria MUST include: "pipeline calls `<function>` for every `<input>`"
- Bad: US-007 AC says "validate_plan_item rejects invalid items" (only tests the function)
- Good: US-013 AC says "pipeline calls validate_plan_item() for every generated plan item"
- Key shift: validation of wiring moves from creator story to consumer story's acceptance criteria

### Edge Case Test Guidance

When testFirst is true, instruct the agent to include:
- Boundary values: None/null, empty string, NaN, zero, negative
- Type variations: scalar vs collection vs complex object (e.g., DataFrame)
- Collision scenarios: same identifier from different sources
- Scale tests: 1 item, 10 items, 100+ items (context pollution shows at scale)
- Reference `references/edge-cases.md` for language-specific patterns

## Orchestrator Enhancements

### Cross-Story Integration Review (after dependency chains)

When all stories in a dependency chain have merged, trace call chains across story boundaries:

1. For each function exported by upstream stories, verify it is called (not just imported) in downstream stories using LSP "Find References" (fallback: grep)
2. Check type consistency — if Story A returns a list and Story B expects a JSON string, flag it. Use LSP "Hover" when available.
3. If issues found: fix inline, re-run tests, commit

### Final Integration Gate (before COMPLETE)

Before declaring COMPLETE:

1. Import smoke test: verify the project's main module imports cleanly
   - Python: `python -c "import <main_module>"`
   - Node: `node -e "require('./<entry_point>')"`
   - Go: `go build ./...`
2. Full test suite (all tests, not per-story)
3. Dead code scan: every new function/class has at least one call site outside its own file and tests. Use LSP "Find References" when available.
4. If any check fails: create a fix task, implement inline, re-test, commit. Do NOT output COMPLETE until all checks pass.

## Implementer Edge Case Guidance

Added between TDD instructions and Integration Wiring Check:

- Boundary values: None/null/undefined, empty collections, NaN, zero, negative
- Type variations: scalar vs collection vs framework-specific types
- Collision scenarios: same identifier from different sources, duplicate entries
- Scale: 1, 10, 100+ items
- Pointer to `references/edge-cases.md` for language-specific gotchas
- Anti-rationalization: "The field data shows 100% of post-implementation bugs were edge cases that passed happy-path tests"

## Review and Verify with LSP

### ql-review Stage 3: Cross-Story Integration Review

Runs when all stories in a dependency chain have passed Stages 1-2, or when all stories are complete:

1. **Call chain tracing:** LSP "Find References" on each new function (fallback: grep). Must have call sites outside own file and tests.
2. **Type consistency:** LSP "Hover" on call sites to verify argument types match (fallback: manual source comparison)
3. **Import resolution:** LSP diagnostics for "unresolved import" errors (fallback: runtime import test)
4. **Dead code scan:** "Find References" returns 0 results = dead code (fallback: grep excluding tests)

### ql-verify: Import Chain Verification

Before claiming a feature complete:
1. All imports resolve (runtime entry point import)
2. All new functions have call sites outside tests
3. Full test suite passes
4. No type mismatches across story boundaries

## Reference Document: Edge Cases

New file `references/edge-cases.md` with:
- General patterns (all languages): null, empty, boundary numbers, collision, scale
- Python: NaN comparison, Path.stem collision, DataFrame str(), mutable defaults, extend() without dedup
- JavaScript: typeof null, NaN !== NaN, type coercion, JSON.parse edge cases
- Go: nil slice vs empty, nil map panic, goroutine leak, defer in loop, string is bytes
- Rust: unwrap panic, integer overflow, String vs &str, Vec::drain

Read by implementer on demand during TDD tasks.

## Testing Strategy

- Syntax: valid markdown + YAML frontmatter
- Internal consistency: step numbering, no stale cross-references
- Cross-file consistency: terms match across skills/agents
- Real-world validation: run updated quantum-loop on a project, observe agent behavior
- Anti-regression: code reviewer agent verifies no conflict markers, stale refs, or version mismatches

## Design Decisions (resolved from PR review feedback)

- **File-touch reconciliation timing:** The reconciliation task is written into quantum.json at plan time (not runtime). It is the last task of the higher-priority story. Conflicts are stored in `quantum.json` metadata (`fileConflicts` array) so users see risks before execution.
- **Cross-story review trigger:** Only fires when a COMPLETE dependency chain has all stories passed. Partial chains (with failed/pending stories) are skipped.
- **Edge case reference loading:** The implementer ALWAYS reads `references/edge-cases.md` at the start of every testFirst task — not on-demand/conditional. This prevents agents from forgetting to check.
- **LSP availability:** All LSP-based checks have grep fallbacks. LSP is preferred but not required.
- **CI validation:** Future improvement — add markdownlint + frontmatter schema check as a GitHub Action. Not in this PR.

## Next Steps

Run `/quantum-loop:ql-spec` to generate a formal PRD, or implement directly since the changes are well-scoped documentation updates.
