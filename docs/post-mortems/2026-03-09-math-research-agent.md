# Quantum-Loop Pipeline Improvements

**Date:** 2026-03-09
**Context:** Post-mortem from implementing the Math Research Agent (34 stories, 80 tasks) via quantum-loop autonomous execution. Issues discovered during 4-agent parallel code review.

---

## 1. Wiring Tasks Are Still the #1 Failure Mode

**What happened:** `persona-handler.ts` and `write-handler.ts` were fully implemented with correct code, but never imported/registered in `panel.ts`. 5 of 24 message types were silently broken.

**Root cause:** The quantum.json task descriptions included wiring instructions ("Import and call registerPersonaHandlers in panel.ts constructor"), but the implementer agents skipped that step and the review gates didn't verify it.

**Proposed fixes:**

1. Add an automated wiring verification task as the last task of any story that creates a new module. This task should run a grep-based check rather than relying on the agent to self-report.

2. The review gate's spec compliance check should include: "For each new export, verify it is imported somewhere." A simple `grep -r "import.*from.*{new-file}"` would catch this.

3. Add a `wiring_verification` field to quantum.json tasks:

```json
{
  "wiring_verification": {
    "file": "src/webview/panel.ts",
    "must_contain": "import { registerPersonaHandlers }"
  }
}
```

**Priority:** P0 (highest bang-for-buck fix)

---

## 2. Cross-Story Consistency Bugs Aren't Caught

**What happened:** Google's secret key was `'google-api-key'` in `onboarding.ts` (US-007) but `'google'` in `google.ts` (US-006). Implemented by separate agents with no coordination.

**Root cause:** Parallel stories that share a contract (like a secret key name) have no mechanism to coordinate. Each agent only sees its own story's acceptance criteria.

**Proposed fixes:**

1. Add a "contracts" section to quantum.json that documents cross-story agreements:

```json
"contracts": {
  "secret_keys": {
    "openai": "openai",
    "anthropic": "anthropic-api-key",
    "google": "google-api-key"
  }
}
```

2. The implementer agent should be instructed to read contracts before implementing.

3. Add a cross-story integration check after parallel stories merge -- a lightweight agent that greps for known contract values and verifies consistency.

**Priority:** P0

---

## 3. Review Gates Passed Code That Violates Coding Standards

**What happened:** Multiple handlers mutated `currentTree.nodes[nodeId]` and `currentTree.attachedPapers` directly, violating the immutability coding standard. Both spec-compliance and code-quality review gates marked these as "passed."

**Root cause:** The review gates check against the story's acceptance criteria (which don't mention immutability). Project-wide coding standards aren't weighted heavily enough in the review prompt.

**Proposed fixes:**

1. The `quality-reviewer` agent should be given explicit access to the project's coding standards (inject the rules file into the review prompt).

2. Add a configurable linting step between implementation and review. For example, a custom eslint rule that flags `obj.prop = value` patterns on certain types.

3. Add a `codebasePatterns` field in quantum.json that the reviewer must check:

```json
"codebasePatterns": [
  {
    "rule": "immutability",
    "check": "No direct property assignment on DialogueTree or DialogueNode objects"
  }
]
```

**Priority:** P1

---

## 4. Dead Code Created by Parallel Agents

**What happened:** `BranchCard.tsx` and `PersonaSelector.tsx` were created as standalone components but never imported by `ResearchTab.tsx`. The ResearchTab implementer built inline equivalents instead.

**Root cause:** Independent stories created a component and its consumer separately. The consumer agent didn't know the component existed or chose to inline it.

**Proposed fixes:**

1. After all stories pass, run a dead code detection pass (`ts-prune` or "find all exports, check if they're imported").

2. In task descriptions, when a story creates a component that another story should use, explicitly state: "This component WILL BE imported by US-XXX. Do not inline a replacement."

3. Add a `consumedBy` relationship to the `filePaths` field:

```json
{
  "filePaths": ["webview-ui/src/components/BranchCard.tsx"],
  "consumedBy": ["US-023"]
}
```

**Priority:** P1

---

## 5. Stale Story Left in Limbo Without Retry

**What happened:** US-004 (OpenAI Provider) was left `in_progress` with 0 retry attempts while all other 33 stories were marked `passed`. The code was actually implemented -- the status just wasn't updated.

**Root cause:** Likely a transient failure or timeout during the execution loop that left the story in limbo without triggering the retry mechanism.

**Proposed fixes:**

1. Add a stale story detector at the end of the execution loop: any story with `status: "in_progress"` and all tasks `status: "pending"` for longer than N minutes should be retried automatically.

2. The orchestrator's final sweep should verify: "For every story marked `passed`, do the tests actually pass?" Run a quick verification before declaring COMPLETE.

3. Add a `startedAt` timestamp to stories so the orchestrator can detect abandoned work:

```json
{
  "status": "in_progress",
  "startedAt": "2026-03-07T01:30:00Z"
}
```

**Priority:** P1

---

## 6. PRD Gaps Not Caught Until Code Review

**What happened:** The PRD never specified "restore active provider from settings on startup for returning users." The `@math` chat participant was broken for returning users -- discovered only during post-implementation code review.

**Root cause:** The brainstorm/spec/plan pipeline focused on feature functionality but missed operational lifecycle concerns.

**Proposed fixes:**

1. Add a lifecycle checklist to the `ql-spec` skill that forces explicit consideration of:
   - First-run behavior
   - Returning-user behavior (settings already configured)
   - Extension update behavior
   - No-workspace behavior
   - Error recovery behavior
   - Uninstall/reinstall behavior

2. The `ql-brainstorm` phase should include a question: "What happens when the user returns to the tool after initial setup?"

**Priority:** P2

---

## 7. Test Coverage Gaps Despite TDD Mandate

**What happened:** EntityDetector, PaperManager, and TexParser had zero dedicated test files despite TDD being a stated requirement with 80% coverage target.

**Root cause:** The quantum.json tasks for these modules had `testFirst: false`. The review gates didn't enforce the coverage target.

**Proposed fixes:**

1. The `ql-plan` skill should default `testFirst: true` for ALL non-config tasks, requiring explicit justification in the `notes` field for any `testFirst: false`.

2. Add a coverage gate to the review process: run `npx c8` or `nyc` and fail if coverage drops below the target for files changed in the story.

3. The orchestrator should track cumulative coverage and flag stories that add code without tests.

**Priority:** P2

---

## Summary

| Priority | Improvement | Effort | Impact |
|----------|-------------|--------|--------|
| P0 | Automated wiring verification (grep-based) | Low | Prevents the #1 failure mode (2 critical bugs) |
| P0 | Cross-story contracts in quantum.json | Low | Prevents cross-agent consistency bugs |
| P1 | Inject coding standards into quality-reviewer | Low | Catches immutability and style violations |
| P1 | Stale story detection + auto-retry | Medium | Prevents abandoned stories |
| P1 | Dead code detection after all stories pass | Low | Catches unused components |
| P2 | Coverage gate in review process | Medium | Enforces TDD mandate |
| P2 | Lifecycle checklist in ql-spec | Low | Catches operational gaps in PRD |
| P2 | `consumedBy` / `wiring_verification` fields | Medium | Structural fix for wiring |

### Key Takeaway

The quantum-loop pipeline excels at decomposing and implementing individual stories in parallel. The gap is at the **seams between stories** -- wiring, shared contracts, and lifecycle concerns that no single story owns. The highest-impact improvements are cheap, grep-based verification checks that run automatically after implementation.
