---
name: ql-deslop
description: Post-review AI-slop cleanup pass. After quality review approves a story/feature, scans only the changed files for: duplicate code, dead code, needless abstraction, boundary violations, missing tests. Proposes deletions with regression-test gate — rolls back on regression. Mandatory unless explicitly skipped via --no-deslop. Borrowed from OMC Ralph 7.5 + 7.6.
allowed-tools: Read, Grep, Glob, Bash, Edit, Write
---

# ql-deslop — post-review AI-slop cleanup

## Purpose

Review approval does not mean the code is clean. LLM-authored code routinely introduces:
- **Duplication** of helpers / types / imports under slightly different names.
- **Dead code** — functions added but never called; exports that no consumer uses.
- **Needless abstraction** — factory for one caller; wrapper that only aliases; configurable field never varied.
- **Boundary violations** — private functions accessed via string names; cross-module reaches that skip the public API.
- **Missing tests** — paths and branches not exercised by any test.

Per Schreiber & Tippe 2025, 12.1% of AI-generated files contain ≥1 CWE, and per Zhong et al. 2026 (278k conversations) AI suggestions increase cyclomatic complexity 10-50× more than human edits. Without an explicit cleanup step, every autonomous run accumulates slop.

`ql-deslop` adds an explicit cleanup pass AFTER the story's review gate passes but BEFORE the merge to the feature branch. Borrowed directly from OMC Ralph Steps 7.5 (deslop) + 7.6 (regression re-verify).

## When to use

- Automatically, as a mandatory step between `ql-review` PASS and the `git merge` in `ql-execute`.
- Manually, at any point after a story is implemented, to clean up before review.
- After absorbing a foreign branch (CPC promotion, cherry-pick) — the absorbed work may carry slop.

## Opt-out

Single flag: `--no-deslop`. Used only when:
- The story is a pure test addition (nothing to clean).
- The deslop pass itself was run earlier in the same wave on the same files.
- The user explicitly demands skip (rare; recorded in commit trailer `Deslop: skipped | <reason>`).

## Scope — strict file-list only

The deslop pass operates on `git diff --name-only BASE_SHA..HEAD_SHA` — the EXACT files the story touched. It never broadens scope silently. Reaching into unchanged files is an anti-pattern and is explicitly forbidden.

## Smell taxonomy — 5 categories

### 1. Duplication

Detectors:
- Identifier similarity across changed files: extract top-level symbol names; flag near-duplicates (e.g., `parseRequest` / `parseReq` / `handleParse`) via Levenshtein or canonical-alpha-rename + exact match (per HyClone arXiv:2508.01357).
- Function-body AST hash: for each function in the diff, compute tree-sitter AST hash after alpha-renaming; flag duplicates across files.
- Import redundancy: same module imported as different names in sibling files.

Action: extract common code into a shared lib; update callers; delete the duplicates.

### 2. Dead code

Detectors:
- Language-specific reachability analysis:
  - TypeScript/JavaScript: `knip` or `ts-prune` on the changed-files subset.
  - Python: `vulture` on the changed-files subset.
  - Go: `staticcheck -checks=U1000` on the changed-files subset.
  - Rust: `cargo udeps` on the changed-files subset.
- DePA line-level perplexity (optional; per arXiv:2502.20246): high-z anomalies flagged for manual inspection.

Action: delete the unused export / function / variable. Re-run tests.

### 3. Needless abstraction

Detectors:
- Single-caller factories: factory returns type T, only one call site exists → inline the factory.
- Identity wrappers: function that only calls another function with same arguments → inline or delete.
- Never-varied config: options object with fields that are always set to the same literal → remove the option.
- One-member interface implemented by one class → inline unless specified as a contract.

Action: propose refactoring with regression-test gate.

### 4. Boundary violations

Detectors:
- Name mangling: access via `module["_privateFn"]`, reflection-style private access.
- Path traversal: imports that reach up too many levels (`../../../../other-module/internal`).
- Test imports from production: test files reaching into non-exported implementation details.

Action: reshape through the public API, or promote the private API if genuinely needed externally.

### 5. Missing tests

Detectors:
- AC ↔ test mapping: every AC in the PRD should have a specific test referenced by its ID (`AC-3 → tests/feature.test.ts::test_ac_3`). Missing maps surface as findings.
- Coverage gap on new public functions: any new exported function with <1 test invocation.
- Branch-coverage gap on control-flow-heavy changes.

Action: write the missing test BEFORE deleting alleged dead code (deletion is safe only when the test suite exercises the surviving behavior).

## Single-pass discipline

Each deslop invocation runs ONE pass from the taxonomy at a time:

- **Pass 1 — dead code** (fastest, lowest risk).
- **Pass 2 — duplication** (refactor; highest payoff for parallel-story artifacts).
- **Pass 3 — naming / error-handling consistency** (cosmetic but compound over time).
- **Pass 4 — test reinforcement** (add AC↔test maps + branch coverage).

Running multiple passes in one agent invocation risks intra-pass interference (deletion invalidates duplication analysis; refactoring invalidates test mappings). Each pass commits independently with a `Deslop:` trailer.

## Regression gate (the 7.6 step)

After each pass's edits:
1. Run the project's full test command (`npm test` / `bash tests/*.sh` / project-specific per `runners/<tool>.json`).
2. Run the project's lint command.
3. Run the project's typecheck command.
4. Run the project's build command if defined.

If ANY of these regress compared to the pre-deslop baseline:
- **Roll back the pass's edits** (`git restore . && git checkout BASE_SHA -- <changed-files>`).
- Record the regression in `progress.txt` with the specific test or lint failure.
- Emit `<quantum>DESLOP_ROLLED_BACK</quantum>` with the failure details.
- Do NOT proceed to the next pass until the user inspects (the regression likely signals that the "slop" being cleaned was actually load-bearing).

If all regression checks pass, commit the pass's edits with trailer:
```
Deslop-pass: 1 (dead-code)
Deslop-deletions: 3 | src/foo.ts:handleOldV1 src/bar.ts:legacyParse src/baz.ts:unusedExport
Regression-tests: 28 passed, 0 failed (matches baseline)
```

## Protect behavior first (regression test synthesis)

For removing anything whose tests do NOT currently exercise it, first SYNTHESIZE a regression test. Snapshot the current behavior before deletion. If the alleged dead code is actually reachable via a path the existing tests miss, the synthesized test fails and deletion is cancelled.

## Reviewer-only mode (writer/reviewer separation)

Invocation flag: `--review`. When passed:
- Agent can EMIT findings with proposed deletions.
- Agent CANNOT write edits.
- The same pass cannot both identify and apply deletions — another pass (without `--review`) must apply after a human reviewer approves.

This separation is mandatory for high-impact cleanup (large delete counts; cross-module moves).

## Output

Per-pass structured report at `quantum.deslop[<story-id>].pass_<n>`:

```json
{
  "story_id": "US-042",
  "pass": 1,
  "pass_name": "dead-code",
  "scope_files": ["src/foo.ts", "src/bar.ts", "src/baz.ts"],
  "findings": [
    {
      "smell": "unused-export",
      "file": "src/foo.ts",
      "line_start": 42, "line_end": 48,
      "symbol": "handleOldV1",
      "confidence": 95,
      "action": "delete",
      "regression_test_added": false
    }
  ],
  "edits_applied": true,
  "regression_check": "passed",
  "commit": "<sha>"
}
```

## Anti-rationalization guards

| The agent says… | The truth is… |
|-----------------|---------------|
| "The tests passed, so this code must be live" | Tests pass with OR without dead code. Use reachability analysis, not test-pass state, for dead-code detection. |
| "This abstraction will be useful later" | YAGNI. Delete now; re-introduce if a second caller ever appears. |
| "Two functions look similar but surely have different intent" | Alpha-rename both to canonical form and diff. If the tree-sitter AST is identical, they have the same intent. Extract. |
| "The file is bigger than `BASE_SHA..HEAD_SHA`; I'll clean up adjacent areas too" | NO. Scope stays to the diff. Adjacent cleanup is a separate story. |
| "The regression check is pedantic, let's skip when changes are small" | The 7.6 step is mandatory. Small changes are the ones where slop is hardest to see and easiest to silently break. |
| "I'll do all 4 passes in one go to save time" | Intra-pass interference is real. Commit each pass separately. |

## Integration with existing skills

- **`ql-review`** (per-story): MUST pass before ql-deslop runs. Deslop never cleans failing code — fix first.
- **`ql-verify`**: runs the regression check; deslop reuses ql-verify's infrastructure.
- **`ql-execute`**: orchestrator invokes ql-deslop between `review passed` and `git merge` (opt-out via `--no-deslop`).
- **`ql-deep-review`**: runs AFTER ql-deslop (whole-feature review of the post-cleanup state).
- **`lib/known-failures.sh`**: records deslop rollbacks so future iterations learn which cleanups are risky.

## Known limitations

- **Single-language reach**: reachability analyzers (knip, ts-prune, vulture, etc.) are language-specific. Polyglot repos need per-language wiring.
- **Cross-file dead code**: functions exported and called only by test files are ambiguous (live for tests, dead for production). Configurable threshold: default "test-only reachability is still live."
- **Refactoring proposals require LLM judgment**: the taxonomy is mechanical but the proposed fix often needs structural reasoning. Pass 2 can invoke a separate refactoring agent rather than inline the logic.
- **Regression test synthesis can fail**: if the agent cannot write a passing regression test that exercises the alleged dead code, either (a) the code really is dead, OR (b) the code is hard to test. The skill treats (a) as "confirmed delete" and (b) as "manual inspection."

## How to invoke

```
/quantum-loop:ql-deslop                 # runs all 4 passes on current story's diff
/quantum-loop:ql-deslop --pass=1        # just the dead-code pass
/quantum-loop:ql-deslop --review        # findings only, no edits
/quantum-loop:ql-deslop --story=US-042  # explicit story scope
/quantum-loop:ql-deslop --no-rollback   # commit each pass even on regression (debug use only)
```
