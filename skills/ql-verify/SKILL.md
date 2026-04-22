---
name: ql-verify
description: "Part of the quantum-loop autonomous development pipeline (brainstorm \u2192 spec \u2192 plan \u2192 execute \u2192 review \u2192 verify). Iron Law verification gate. Requires fresh evidence before any completion claim. Use before claiming work is done, before committing, or before marking a story as passed. Triggers on: verify, check, prove it works, ql-verify."
---

# Quantum-Loop: Verify

## The Iron Law

```
NO COMPLETION CLAIMS WITHOUT FRESH VERIFICATION EVIDENCE.
```

This is not a guideline. This is not a best practice. This is a law. There are zero exceptions.

## The 5-Step Gate Function

Every claim that something "works", "passes", or "is done" must pass through these 5 steps:

### Step 1: IDENTIFY
What command or check proves the claim?

Examples:
- "Tests pass" → `npm test` or `pytest`
- "Build succeeds" → `npm run build` or `tsc --noEmit`
- "Lint clean" → `eslint .` or `ruff check`
- "Feature works" → specific test command + manual check
- "Bug is fixed" → test that reproduces the original bug

### Step 2: RUN
Execute the complete command. Right now. Fresh. Not from memory or cache.

Rules:
- Run the FULL command, not a subset
- Run it in the current state of the code, not from before your changes
- Do not use cached results from a previous run
- Do not skip the command because "it passed last time"

### Step 3: READ
Read the ENTIRE output. Not just the last line.

Check:
- Exit code (0 = success, non-zero = failure)
- Total number of tests (passed, failed, skipped)
- Warning messages (warnings can hide real problems)
- Specific error messages (not just "X tests passed")

### Step 4: VERIFY
Does the output ACTUALLY confirm the claim?

Common traps:
- "15 tests passed" but 3 were skipped → those 3 might be the important ones
- "Build succeeded" but with warnings → warnings might indicate runtime failures
- "0 errors" from linter but build still fails → linter ≠ compiler
- "Test passed" but the test itself is wrong → test may not test what you think

### Step 5: CLAIM
ONLY NOW may you state that something works, passes, or is done.

Your claim must include:
- The exact command you ran
- The key output (pass count, exit code)
- Timestamp (when you ran it)

## Verification Requirements by Claim Type

| Claim | Required Evidence |
|-------|-------------------|
| "Tests pass" | `0 failures` AND `0 errors` in fresh test run output |
| "Linter clean" | `0 errors` AND `0 warnings` in fresh lint output |
| "Build succeeds" | Exit code 0 from fresh build command |
| "Bug is fixed" | Test reproducing original symptom now passes |
| "Feature works" | All acceptance criteria verified with specific evidence |
| "Story is done" | ALL of the above that apply + spec compliance review passed |
| "Typecheck passes" | Exit code 0 from `tsc --noEmit` or equivalent |

## Red Flags -- STOP Immediately

If you notice ANY of these, you are about to violate the Iron Law:

### Language Red Flags
- Using "should" → "Tests **should** pass" means you haven't run them
- Using "probably" → "This **probably** works" means you don't know
- Using "seems to" → "It **seems to** be working" means you haven't verified
- Using "I believe" → "I **believe** this is correct" means you're guessing
- Using "based on" → "**Based on** the changes, it should work" means you haven't checked

### Behavioral Red Flags
- Expressing satisfaction before running verification ("Great!", "Perfect!", "Done!")
- Trusting a subagent's report without independent verification
- Relying on a previous run instead of a fresh one
- Checking only part of the test suite
- Skipping verification because "the change was small"

## Anti-Rationalization Table

| Excuse | Reality |
|--------|---------|
| "It should work now" | RUN the verification. "Should" is not evidence. |
| "I'm confident this is correct" | Confidence ≠ evidence. Run the command. |
| "Just this once we can skip" | No exceptions. The Iron Law has zero exceptions. |
| "The linter passed, so it works" | Linter ≠ compiler ≠ runtime. Each checks different things. |
| "The agent said it succeeded" | Verify independently. Agents can hallucinate success. |
| "I already tested this earlier" | Earlier ≠ now. Code changed since then. Run it fresh. |
| "This change is too small to break anything" | Small changes cause the hardest-to-debug failures. Verify. |
| "Partial check is enough" | Partial proves nothing. Run the full verification. |
| "The test I wrote passes, so the feature works" | Your test might be wrong. Check it tests the right thing. |
| "Manual testing confirmed it" | Manual testing is not reproducible evidence. Run automated checks. |
| "It's just a type change, typecheck is enough" | Type changes can break runtime behavior. Run tests too. |
| "Different words but same idea, so rule doesn't apply" | Spirit over letter. If you're rationalizing, you're violating. |

## Integration with /quantum-loop:execute

When called from the execution loop, this skill:
1. Receives the claim type and story context
2. Identifies the verification commands from the task definition in quantum.json
3. Runs all commands fresh
4. Reports results back to the execution loop
5. Updates quantum.json with verification evidence

## Standalone Usage

When invoked directly by the user:
1. Ask what claim needs verification
2. Identify the appropriate commands
3. Run the 5-step gate function
4. Report results with full evidence

## Integration Verification (for multi-story features)

Before claiming a feature is complete, verify:

1. **All imports resolve:** Run the project's entry point import
   - Python: `python -c "import <main_module>"`
   - Node: `node -e "require('./<entry_point>')"`
   - Go: `go build ./...`
2. **All new functions have call sites outside tests:** Use LSP "Find References" or grep
3. **Full test suite passes:** Not just per-story tests — ALL tests
4. **No type mismatches across story boundaries:** Use LSP "Hover" or manual inspection

This is part of the Iron Law: "it passes unit tests" is NOT evidence that the feature works. Integration evidence is required. "Each story passed its review" is NOT evidence that the stories work together.
