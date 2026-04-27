---
name: ql-spec
description: "Part of the quantum-loop autonomous development pipeline (brainstorm \u2192 spec \u2192 plan \u2192 execute \u2192 review \u2192 verify). Generate a structured Product Requirements Document (PRD) with user stories, acceptance criteria, and functional requirements. Use when you have an approved design and need formal requirements, or when starting from scratch. Triggers on: create spec, write prd, spec out, requirements for, ql-spec."
---

# Quantum-Loop: Spec

You are generating a formal Product Requirements Document (PRD). This document will be consumed by `/quantum-loop:plan` to produce machine-readable tasks for autonomous execution. Write for junior developers or AI agents -- be explicit, unambiguous, and verifiable.

## Phase 0: Phase-skip check (Phase 18 / P2.4)

Before asking any clarifying question, check whether a prior `/ql-spec` run already converted the same design + brainstorm handoff into a PRD:

```bash
DESIGN=$(ls docs/plans/*-design.md 2>/dev/null | tail -1)
BS_HANDOFF=".handoffs/brainstorm.md"
ARGS=()
[[ -n "$DESIGN" ]]         && ARGS+=("$DESIGN")
[[ -f "$BS_HANDOFF" ]]     && ARGS+=("$BS_HANDOFF")

if bash lib/phase-skip.sh skip spec . "${ARGS[@]}"; then
  echo "[SKIP] spec is up-to-date — design + brainstorm handoff unchanged."
  bash lib/handoff.sh read spec | jq '.'
  exit 0
fi
```

After saving the PRD and writing `.handoffs/spec.md`, record the fingerprint so the next identical invocation can skip:

```bash
PRD=$(ls -t tasks/prd-*.md | head -1)
DESIGN_H=$(bash lib/phase-skip.sh hash "$DESIGN")
BS_H=$(bash lib/phase-skip.sh hash "$BS_HANDOFF")
FP=$(jq -cn --arg dp "$DESIGN" --arg dh "$DESIGN_H" --arg bp "$BS_HANDOFF" --arg bh "$BS_H" \
  '{artifacts: [{path: $dp, sha256: $dh}, {path: $bp, sha256: $bh}]}')
bash lib/phase-skip.sh record spec "$FP" . >/dev/null
```

## Prerequisite: read prior-stage handoffs (Phase 15 / P2.3)

Before doing anything else, ingest every prior-stage handoff so decisions, rejected alternatives, and risks carry forward even across context compaction:

```bash
bash lib/handoff.sh all | jq '.'
bash lib/handoff.sh read brainstorm | jq '.'
```

Treat `brainstorm.decided` as binding (already agreed — do not re-litigate), `brainstorm.rejected` as closed alternatives (do not re-propose them), `brainstorm.remaining` as the exact backlog your PRD MUST resolve, and `brainstorm.risks` as mandatory §Risks entries in the PRD.

## Step 1: Gather Context

1. Check for an approved design document in `docs/plans/`. If one exists, load it as primary context.
2. Check for existing quantum.json to understand any in-progress features.
3. Read project files (package.json, README, existing code structure) to understand the tech stack.
4. Re-read `.handoffs/brainstorm.md`'s `remaining` list — it IS the starting backlog of clarifying questions.

## Step 2: Ask Clarifying Questions

Ask **2-8 clarifying questions** — count adaptive to remaining ambiguity (see Question Rules below). Format each with LETTERED OPTIONS so the user can respond with shorthand like "1A, 2C, 3B, 4D, 5A".

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
- **Question count is adaptive to remaining ambiguity, not a hard minimum.**
  - If there is **no design doc** and the feature is non-trivial: ask **5-8** questions.
  - If a **design doc exists** and answers most of Phase 1's concerns: ask only what the design doc leaves ambiguous — typically **2-4** questions. Padding beyond that produces release-ops / non-goal-confirmation questions that don't belong in a PRD.
  - Absolute floor: **ask at least 2** questions so the user has a chance to correct course before the PRD is saved. Absolute ceiling: **8**.
- Every question MUST have lettered options (A, B, C, D)
- At least one question MUST probe NON-GOALS (what it should NOT do)
- At least one question MUST probe ERROR SCENARIOS
- Do NOT ask implementation questions (framework choice, library selection)
- If a design doc exists, do NOT re-ask questions already answered there
- **Count-quality test:** before each question, ask yourself "is this question answered in the design doc, or would its answer materially change the PRD?" If neither, don't ask it — shallow padding is worse than fewer questions.

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
| "I'll pad questions to hit 5" | Padding past real ambiguity produces release-ops / non-goal-confirmation questions that don't belong in a PRD. If the design doc answers most of Phase 1, ask only what remains genuinely open — 2-4 is fine. The floor is 2, not 5. |
| "This story is slightly too big but it's fine" | Too-big stories fail during autonomous execution. Split ruthlessly. |
| "The acceptance criteria are obvious" | Obvious to you is ambiguous to an AI agent. Be explicit. |
| "Non-goals aren't needed for this feature" | Unbounded scope is the root of scope creep. Always define boundaries. |
| "I'll skip the design considerations section" | All 9 sections are mandatory. Mark optional sections as "N/A" if truly not applicable. |
| "These criteria are verifiable enough" | If a machine can't test it, it's not verifiable. Rewrite. |

## Pre-Save Checklist

Before saving the PRD, verify:
- [ ] Asked 2-8 clarifying questions with lettered options (count adapted to remaining ambiguity — see Question Rules)
- [ ] Incorporated user's answers into the PRD
- [ ] Every user story fits in one context window
- [ ] Every acceptance criterion is machine-verifiable
- [ ] Every story includes "Typecheck/lint passes" criterion
- [ ] UI stories include "Verify in browser" criterion
- [ ] Functional requirements are numbered (FR-N) and unambiguous
- [ ] Non-goals section has at least 3 items
- [ ] Stories follow dependency order (data → backend → UI)
- [ ] Saved to `tasks/prd-<feature-name>.md`

### Lifecycle Checklist (mandatory for user-facing features)

For each item below, either address it in the PRD or mark it "N/A" with a justification. **Silent skipping is forbidden** — every item must have an explicit resolution.

- [ ] **First-run behavior:** What happens the first time a user encounters this feature? (empty states, onboarding, defaults)
- [ ] **Returning-user behavior:** What changes when the user comes back? (persisted state, updated data, version differences)
- [ ] **Update behavior:** What happens when the feature is updated after initial deployment? (migrations, backward compatibility, data transformations)
- [ ] **Error recovery:** What happens when things go wrong? (network failures, invalid data, partial state, retry logic)
- [ ] **No-data/empty state:** What does the user see when there is no data to display? (empty lists, missing config, uninitialized state)
- [ ] **Uninstall/disable:** What happens when the feature is removed or disabled? (cleanup, orphaned data, dependent features)

## Exit: write stage handoff (Phase 15 / P2.3)

Before returning control, persist a stage handoff at `.handoffs/spec.md` so `/ql-plan`, `/ql-execute`, and downstream reviewers can read your decisions even across session compaction:

```bash
bash lib/handoff.sh write spec "$(cat <<'JSON'
{
  "decided":   ["<each AC that converges a prior brainstorm.remaining item>", "<scope-boundary picks>"],
  "rejected":  ["<any alternative framing of an AC you considered and dropped, with reason>"],
  "risks":     ["<each §Risks entry of the PRD>"],
  "files":     ["tasks/prd-<feature>.md"],
  "remaining": ["<any question you could not resolve — flag for /ql-plan>"],
  "notes":     "<free-form: how this PRD re-grounds against userIntent, any re-negotiation logged>"
}
JSON
)"
```

The `decided` array MUST NOT contradict `brainstorm.decided`; any re-negotiation MUST also land as a new `quantum.json.userClarifications[]` entry so `/ql-intent-check` sees it as explicit.

## Post-exit prd-review (P5.B4 / US-007 / v0.6.3 — advisory)

After the handoff is written, run the spec-reviewer in `prd-review` mode against the just-saved PRD. The review is **advisory** in v0.6.3 — findings emit to stderr; the skill does NOT abort regardless of what's flagged.

```bash
PRD_PATH=$(bash lib/handoff.sh read spec 2>/dev/null | jq -r '.files[0] // empty' 2>/dev/null)
[[ -z "$PRD_PATH" || "$PRD_PATH" == "null" ]] && PRD_PATH=$(ls tasks/prd-*.md 2>/dev/null | tail -1)

# Opt-out gate: QL_SKIP_PRE_IMPL_REVIEW=prd (or comma-separated, e.g. design,prd).
SKIP_LIST="${QL_SKIP_PRE_IMPL_REVIEW:-}"
if [[ -n "$PRD_PATH" ]] && \
   ! printf '%s' "$SKIP_LIST" | tr ',' '\n' | grep -qx "prd"; then
  echo "[QL-SPEC] Running spec-reviewer in prd-review mode (advisory)..." >&2
  MODE=prd-review PRD_PATH="$PRD_PATH" \
    claude --headless "agents/spec-reviewer.md prd-review mode against $PRD_PATH" 2>&1 || true
else
  echo "[QL-SPEC] prd-review skipped (QL_SKIP_PRE_IMPL_REVIEW=prd or no PRD)" >&2
fi
```

The reviewer emits findings via `FINDING_START..FINDING_END` blocks to stderr. The skill exits 0 regardless. Operators can chain skips (`QL_SKIP_PRE_IMPL_REVIEW=design,prd` to bypass both stages).
