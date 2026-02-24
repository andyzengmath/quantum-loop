---
name: ql-spec
description: Generate a structured Product Requirements Document (PRD) with user stories, acceptance criteria, and functional requirements. Use when you have an approved design and need formal requirements, or when starting from scratch. Triggers on: create spec, write prd, spec out, requirements for, ql-spec.
---

# Quantum-Loop: Spec

You are generating a formal Product Requirements Document (PRD). This document will be consumed by `/quantum-loop:plan` to produce machine-readable tasks for autonomous execution. Write for junior developers or AI agents -- be explicit, unambiguous, and verifiable.

## Step 1: Gather Context

1. Check for an approved design document in `docs/plans/`. If one exists, load it as primary context.
2. Check for existing quantum.json to understand any in-progress features.
3. Read project files (package.json, README, existing code structure) to understand the tech stack.

## Step 2: Ask Clarifying Questions

Ask 5-8 clarifying questions. Format each with LETTERED OPTIONS so the user can respond with shorthand like "1A, 2C, 3B, 4D, 5A".

Focus questions on areas where the design doc (if any) is ambiguous or incomplete:

- **Problem/Goal:** What specific problem does this solve?
- **Core Functionality:** What are the key user actions?
- **Scope Boundaries:** What should it explicitly NOT do?
- **Success Criteria:** How do we know it's done?
- **Technical Constraints:** What must it integrate with?
- **Data Requirements:** What data needs to be stored, fetched, or transformed?
- **Error Scenarios:** What happens when things go wrong?
- **Priority:** What is the MVP vs. nice-to-have?

### Question Format

```
1. What is the primary goal of this feature?
   A. Improve user onboarding experience
   B. Increase task completion rate
   C. Reduce support tickets for X
   D. Other: [please specify]

2. How should priority levels be structured?
   A. Three levels (High / Medium / Low)
   B. Four levels (Critical / High / Medium / Low)
   C. Numeric (1-5 scale)
   D. Custom labels defined by user
```

### Question Rules
- Minimum 5 questions, maximum 8
- Every question MUST have lettered options (A, B, C, D)
- At least one question must probe NON-GOALS (what it should NOT do)
- At least one question must probe ERROR SCENARIOS
- Do NOT ask implementation questions (framework choice, library selection)
- If a design doc exists, do NOT re-ask questions already answered there

## Step 3: Generate the PRD

Based on the user's answers, generate a PRD with ALL 9 sections below. No section may be omitted.

### Section 1: Introduction/Overview
Brief description (2-3 sentences) of the feature and the problem it solves.

### Section 2: Goals
Specific, measurable objectives as a bullet list. Each goal should be verifiable.

### Section 3: User Stories

Format:
```markdown
### US-001: [Title]
**Description:** As a [user], I want [feature] so that [benefit].

**Acceptance Criteria:**
- [ ] Specific verifiable criterion 1
- [ ] Specific verifiable criterion 2
- [ ] Typecheck/lint passes
- [ ] [UI stories only] Verify in browser
```

#### Story Sizing Rules
Each story must be completable in ONE context window (one AI agent session). Rules of thumb:
- If you cannot describe the change in 2-3 sentences, it's too big. Split it.
- One story = one database change, OR one API endpoint, OR one UI component. Not all three.

#### Right-sized stories (GOOD):
- Add a database column and migration
- Add a single API endpoint with validation
- Create one UI component
- Add filter logic to an existing query
- Write integration test for an endpoint

#### Too-large stories (BAD):
- "Build the entire priority system" (multiple stories)
- "Add priority to tasks with UI and API" (spans all layers)
- "Implement filtering, sorting, and searching" (three features)

### Section 4: Functional Requirements
Numbered list with unambiguous requirements:
```
FR-1: The system shall store task priority as an enum ('high' | 'medium' | 'low').
FR-2: The system shall default new tasks to 'medium' priority.
FR-3: The API shall accept an optional 'priority' query parameter on GET /tasks.
```

### Section 5: Non-Goals (Out of Scope)
Explicit list of what this feature will NOT include. This section is mandatory and must have at least 3 items.

### Section 6: Design Considerations (Optional)
UI/UX requirements, mockup references, existing component reuse.

### Section 7: Technical Considerations (Optional)
Constraints, dependencies, integration points, performance requirements.

### Section 8: Success Metrics
Measurable outcomes (e.g., "Reduce time to find high-priority tasks by 50%").

### Section 9: Open Questions
Remaining areas needing clarification. If none, state "None at this time."

## Step 4: Save the PRD

Save to: `tasks/prd-<feature-name>.md` (kebab-case filename).

Inform the user:
> "PRD saved to `tasks/prd-<feature-name>.md`. When you're ready to create the execution plan, run `/quantum-loop:plan`."

Do NOT start implementing. Do NOT create quantum.json. That is `/quantum-loop:plan`'s job.

## Acceptance Criteria Quality Standards

### GOOD acceptance criteria (verifiable):
- "Add `status` column to tasks table with default 'pending'"
- "Filter dropdown has options: All, Active, Completed"
- "Clicking delete shows confirmation dialog before deleting"
- "API returns 400 with message 'Invalid priority' for unknown values"
- "Page loads in under 2 seconds with 1000 tasks"

### BAD acceptance criteria (vague -- FORBIDDEN):
- "Works correctly"
- "User can do X easily"
- "Good UX"
- "Handles edge cases"
- "Performs well"
- "Is secure"
- "Looks nice"

Every criterion must answer: "How would a machine verify this?"

## Anti-Rationalization Guards

| Excuse | Reality |
|--------|---------|
| "Fewer than 5 questions is enough" | Shallow questions produce ambiguous specs. Ask at least 5. |
| "This story is slightly too big but it's fine" | Too-big stories fail during autonomous execution. Split ruthlessly. |
| "The acceptance criteria are obvious" | Obvious to you is ambiguous to an AI agent. Be explicit. |
| "Non-goals aren't needed for this feature" | Unbounded scope is the root of scope creep. Always define boundaries. |
| "I'll skip the design considerations section" | All 9 sections are mandatory. Mark optional sections as "N/A" if truly not applicable. |
| "These criteria are verifiable enough" | If a machine can't test it, it's not verifiable. Rewrite. |

## Pre-Save Checklist

Before saving the PRD, verify:
- [ ] Asked at least 5 clarifying questions with lettered options
- [ ] Incorporated user's answers into the PRD
- [ ] Every user story fits in one context window
- [ ] Every acceptance criterion is machine-verifiable
- [ ] Every story includes "Typecheck/lint passes" criterion
- [ ] UI stories include "Verify in browser" criterion
- [ ] Functional requirements are numbered (FR-N) and unambiguous
- [ ] Non-goals section has at least 3 items
- [ ] Stories follow dependency order (data → backend → UI)
- [ ] Saved to `tasks/prd-<feature-name>.md`
