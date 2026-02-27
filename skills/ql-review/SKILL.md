---
name: ql-review
description: "Part of the quantum-loop autonomous development pipeline (brainstorm \u2192 spec \u2192 plan \u2192 execute \u2192 review \u2192 verify). Two-stage code review. Spec compliance first, then code quality. Use after implementation or before merge. Triggers on: review code, code review, check implementation, ql-review."
---

# Quantum-Loop: Review

You orchestrate a two-stage code review. Stage 1 (spec compliance) MUST pass before Stage 2 (code quality) begins. This order is absolute.

## Why Two Stages?

Code that doesn't match the spec is waste -- no matter how well-written. Checking spec compliance first prevents spending review effort on code that needs to be rewritten anyway.

## Usage Modes

### Mode 1: Within /quantum-loop:execute (automated)
Called automatically by the execution loop after a story's quality checks pass.
Receives story context from quantum.json.

### Mode 2: Standalone (user-invoked)
User invokes `/quantum-loop:review` directly to review recent changes.

## Standalone Workflow

### Step 1: Determine Review Scope

If the user specifies a story ID, use it. Otherwise:

1. Check for `quantum.json` -- if exists, identify the most recent `in_progress` story
2. If no quantum.json, use the current branch's diff from main/master:
   ```bash
   git merge-base HEAD main
   ```

Determine BASE_SHA and HEAD_SHA for the review range.

### Step 2: Identify the Spec

1. If quantum.json exists: read the PRD path and story acceptance criteria
2. If no quantum.json: ask the user what requirements this code should meet
3. If no spec exists at all: skip Stage 1, proceed directly to Stage 2 with a warning

### Step 3: Stage 1 -- Spec Compliance Review

Dispatch the `spec-reviewer` agent with:
- STORY_ID
- PRD_PATH
- BASE_SHA
- HEAD_SHA

Wait for the review result.

**If Stage 1 PASSES:**
- Log result to quantum.json (if available)
- Proceed to Stage 2

**If Stage 1 FAILS:**
- Present the issues to the user (or to the execution loop)
- List every unsatisfied acceptance criterion with evidence
- Do NOT proceed to Stage 2
- If within /quantum-loop:execute: return failure with issues list

### Step 4: Stage 2 -- Code Quality Review

Only reached if Stage 1 passed.

Dispatch the `quality-reviewer` agent with:
- STORY_ID
- BASE_SHA
- HEAD_SHA
- DESCRIPTION (brief summary of what was implemented)

Wait for the review result.

**If Stage 2 PASSES:**
- Log result to quantum.json (if available)
- Report success

**If Stage 2 FAILS:**
- Present categorized issues (Critical / Important / Minor)
- Critical issues must be fixed
- 3+ Important issues must be fixed
- Minor issues are noted but don't block

## Handling Review Feedback

### Within /quantum-loop:execute (automated)
1. If review fails, the implementer gets ONE attempt to fix the issues
2. After fixing, both review stages run again from scratch
3. If second attempt also fails, story is marked as failed

### Standalone (user-invoked)
1. Present the full review report
2. User decides which issues to fix
3. User can re-invoke `/quantum-loop:review` after fixing

## Output Format

Present the combined review report:

```markdown
## Review Report: [Story ID or Branch Name]

### Stage 1: Spec Compliance
**Status:** PASSED / FAILED

[If failed: list unsatisfied criteria]
[If passed: "All N acceptance criteria satisfied."]

### Stage 2: Code Quality
**Status:** PASSED / FAILED / SKIPPED (if Stage 1 failed)

**Strengths:**
- [List from quality reviewer]

**Issues:**
- [Critical] [description] -- [file:line]
- [Important] [description] -- [file:line]
- [Minor] [description] -- [file:line]

### Recommendation
[Pass / Fix and re-review / specific guidance]
```

## Stage 3: Cross-Story Integration Review

This stage runs when:
- All stories in a dependency chain have passed Stages 1 and 2
- OR when all stories are complete (final gate before COMPLETE)
- OR when explicitly invoked: `/quantum-loop:ql-review --integration`

### Checks (use LSP tools when available, fall back to grep)

1. **Call chain tracing:** For every function created by an upstream story, verify it is **called** (not just imported) in downstream stories.
   - PREFERRED: LSP "Find References" — returns only actual call sites
   - FALLBACK: `grep -rn "function_name" --include="*.py" | grep -v test`
   - Must appear in at least one non-test call site outside its defining file

2. **Type consistency:** Check that return types from upstream stories match parameter types expected downstream.
   - PREFERRED: LSP "Hover" on call sites to verify argument types
   - FALLBACK: Read source of caller and callee, compare manually
   - Flag: list-vs-string, Optional-vs-required, scalar-vs-collection mismatches

3. **Dead code scan:** Every new export must have a caller outside its own file and tests.
   - PREFERRED: LSP "Find References" returns 0 results = dead code
   - FALLBACK: grep for function name, exclude test files

4. **Import resolution:** Verify every import statement resolves to an actual file/module.
   - PREFERRED: LSP diagnostics for "unresolved import" errors (instant)
   - FALLBACK: `python -c "import main_module"` or equivalent runtime test

### On Integration Failure
- List specific unwired functions and type mismatches
- Suggest the exact wiring fix (which file, which line, what call to add)
- The orchestrator or user implements the fix

### Output Format (Stage 3)
```markdown
### Stage 3: Cross-Story Integration
**Status:** PASSED / FAILED

**Call chains verified:**
- US-007 validate_plan_item() → called in pipeline.py:45 ✓
- US-008 generate_stage2() → called in pipeline.py:78 ✓

**Unwired functions:**
- US-007 validate_plan_item() → NOT called in any pipeline code ✗
  Fix: Add `validated = validate_plan_item(item, schema)` to pipeline.py:52

**Type mismatches:**
- US-009 returns List[str] but US-013 expects JSON string at pipeline.py:90
```

## Anti-Rationalization Guards

| Excuse | Reality |
|--------|---------|
| "Skip Stage 1, the code clearly matches the spec" | You don't know until you check systematically. Run Stage 1. |
| "Skip Stage 2, it's a small change" | Small changes are where subtle bugs hide. Run Stage 2. |
| "Run both stages in parallel to save time" | Stage 2 is wasted effort if Stage 1 fails. Sequential is correct. |
| "The Critical issue isn't really critical" | If it's security, data loss, or crashes, it's Critical. Period. |
| "Three Important issues is harsh" | Quality compounds. Three Important issues signal a pattern problem. |
| "The reviewer is wrong" | Verify their claim against the code. If they're wrong, explain why with evidence. Don't dismiss. |
