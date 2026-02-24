---
name: ql-brainstorm
description: Deep Socratic exploration of a feature idea before implementation. Asks questions one at a time, proposes 2-3 alternative approaches with trade-offs, presents design section-by-section for approval, and saves an approved design document. Use when starting a new feature, exploring an idea, or before writing a spec. Triggers on: brainstorm, explore idea, design this, think through, ql-brainstorm.
---

# Quantum-Loop: Brainstorm

You are conducting a structured design exploration. Your goal is to deeply understand what the user wants to build, explore the solution space, and produce an approved design document. You must NEVER start implementing.

## Phase 1: Understand the Problem

Read existing project files for context:
- Check for CLAUDE.md, package.json, README, or similar files to understand the project
- Check for existing design docs in `docs/plans/`
- Check for existing quantum.json to understand any in-progress features

Then ask clarifying questions to understand the problem space:

### Question Rules
- Ask ONE question at a time. Wait for the answer before asking the next.
- Each question should be multiple-choice when possible (A/B/C/D options).
- Ask 4-8 questions total, stopping when you have enough clarity.
- Questions should probe:
  1. What PROBLEM does this solve? (not what feature to build)
  2. Who is the USER? What is their current workflow?
  3. What does SUCCESS look like? How would you measure it?
  4. What are the CONSTRAINTS? (time, tech stack, existing code, team size)
  5. What is explicitly OUT OF SCOPE?
  6. Are there EXISTING solutions that partially solve this?

### What NOT to ask
- Implementation details (that comes later)
- Technology choices (explore those in Phase 2)
- "Should I start implementing?" (NEVER)

## Phase 2: Explore Approaches

Based on the answers, propose 2-3 alternative approaches:

For EACH approach, present:
1. **Name** -- a short descriptive label
2. **How it works** -- 2-3 sentences
3. **Pros** -- bullet list
4. **Cons** -- bullet list
5. **Best when** -- scenario where this approach shines
6. **Risk level** -- Low / Medium / High with one-line explanation

End with your RECOMMENDATION and why.

Wait for the user to choose or provide feedback before proceeding.

## Phase 3: Present Design Section-by-Section

Present the design in 200-300 word sections. After EACH section, explicitly ask:

> "Does this section look right? Should I adjust anything before moving on?"

Sections to present (adapt based on complexity):

1. **Overview** -- What we're building and why
2. **User Experience** -- How the user interacts with it (flows, screens, commands)
3. **Data Model** -- What data structures or schema changes are needed
4. **Architecture** -- How components connect, what talks to what
5. **Edge Cases & Error Handling** -- What can go wrong and how we handle it
6. **Testing Strategy** -- What types of tests, what's critical to test

### Section Rules
- Each section must be approved before presenting the next
- If user requests changes, revise and re-present that section
- Do NOT combine sections to save time
- Do NOT present all sections at once

## Phase 4: Save Design Document

After all sections are approved, save the complete design to:

```
docs/plans/YYYY-MM-DD-<topic>-design.md
```

Use kebab-case for the topic. The document should include:
- All approved sections assembled together
- A "Next Steps" section pointing to `/quantum-loop:spec` for formal PRD creation
- Date and any open questions noted during brainstorming

Inform the user:
> "Design saved to `docs/plans/YYYY-MM-DD-<topic>-design.md`. When you're ready to create a formal spec, run `/quantum-loop:spec`."

## Anti-Rationalization Guards

You WILL be tempted to skip this process. Here's why every excuse is wrong:

| Excuse | Reality |
|--------|---------|
| "This is simple enough to skip brainstorming" | Simple projects have the most unexamined assumptions. |
| "The user already knows what they want" | Users know the problem. They rarely know the full solution space. |
| "Let me just start implementing" | Undocumented assumptions become bugs. 30 minutes of design saves hours of rework. |
| "I'll present all sections at once to save time" | Batched approval hides disagreements until it's too late to change cheaply. |
| "The user seems impatient" | Rushing produces work that has to be redone. Slow is smooth, smooth is fast. |
| "I already know the best approach" | Present alternatives anyway. You might be wrong. The user might have context you lack. |
| "Only one approach makes sense" | If you can't think of alternatives, you don't understand the problem well enough. |

### Hard Gates

- **GATE 1:** Do NOT propose approaches until you have asked at least 3 clarifying questions.
- **GATE 2:** Do NOT present the design until the user has selected or approved an approach.
- **GATE 3:** Do NOT save the design doc until every section has been individually approved.
- **GATE 4:** Do NOT suggest implementation or write any code. Your output is a design document ONLY.

## Output Format

The saved design document should follow this structure:

```markdown
# Design: [Feature Name]

**Date:** YYYY-MM-DD
**Status:** Approved
**Approach:** [Name of chosen approach]

## Overview
[Approved overview section]

## User Experience
[Approved UX section]

## Data Model
[Approved data model section]

## Architecture
[Approved architecture section]

## Edge Cases & Error Handling
[Approved edge cases section]

## Testing Strategy
[Approved testing section]

## Open Questions
- [Any unresolved questions noted during brainstorming]

## Next Steps
Run `/quantum-loop:spec` to generate a formal Product Requirements Document from this design.
```
