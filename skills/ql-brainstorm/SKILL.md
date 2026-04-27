---
name: ql-brainstorm
description: "Part of the quantum-loop autonomous development pipeline (brainstorm \u2192 spec \u2192 plan \u2192 execute \u2192 review \u2192 verify). Deep Socratic exploration of a feature idea before implementation. Asks questions one at a time, proposes 2-3 alternative approaches with trade-offs, presents design section-by-section for approval, and saves an approved design document. Use when starting a new feature, exploring an idea, or before writing a spec. Triggers on: brainstorm, explore idea, design this, think through, ql-brainstorm."
---

# Quantum-Loop: Brainstorm

You are conducting a structured design exploration. Your goal is to deeply understand what the user wants to build, explore the solution space, and produce an approved design document. You must NEVER start implementing.

## Phase 0: Phase-skip check (Phase 18 / P2.4)

Before asking any question, check whether a prior `/ql-brainstorm` run already covered this exact input:

```bash
# Inputs that define "same brainstorm": verbatim user intent + any existing design doc
INTENT_TEXT=$(jq -r '.userIntent.text // ""' quantum.json 2>/dev/null)
DESIGN=$(ls docs/plans/*-design.md 2>/dev/null | tail -1)  # most recent if multiple
ARGS=()
[[ -n "$INTENT_TEXT" ]] && ARGS+=("inline:$INTENT_TEXT")
[[ -n "$DESIGN" ]]      && ARGS+=("$DESIGN")

if bash lib/phase-skip.sh skip brainstorm . "${ARGS[@]}"; then
  echo "[SKIP] brainstorm is up-to-date — inputs unchanged since last run."
  echo "Re-reading .handoffs/brainstorm.md for downstream context."
  bash lib/handoff.sh read brainstorm | jq '.'
  # Return control to caller. No re-questioning, no design regeneration.
  exit 0
fi
```

If skip returns non-zero (no record, or any input changed), proceed to Phase 1. After the design is approved and Phase 4c writes the handoff, also record the fingerprint:

```bash
FP=$(jq -cn --arg ip "inline://$INTENT_TEXT" --arg ih "$(bash lib/phase-skip.sh inline "$INTENT_TEXT" | tr -d '\n')" \
            --arg dp "$DESIGN" --arg dh "$(bash lib/phase-skip.sh hash "$DESIGN" | tr -d '\n')" \
  '{artifacts: [{path: $ip, sha256: $ih}, {path: $dp, sha256: $dh}]}')
bash lib/phase-skip.sh record brainstorm "$FP" . >/dev/null
```

## Phase 0B: Ambiguity gate (Phase 19 / P2.8, OMC deep-interview)

The skill MUST NOT produce a design doc until the ambiguity score falls below the gate threshold. After each round of questioning (Phase 1), self-assess clarity on three weighted dimensions — goal (40%), constraints (30%), criteria (30%) — each scored 0-10. Compute the composite via `lib/ambiguity.sh`:

```bash
# After round N of questioning, self-assess clarity 0-10 on each dimension:
GOAL_CLARITY=<0-10>        # "Can I state what this feature does in one sentence?"
CONSTRAINTS_CLARITY=<0-10> # "Can I list every constraint (time/tech/compliance)?"
CRITERIA_CLARITY=<0-10>    # "Can I list every success / acceptance criterion?"

SCORE=$(bash lib/ambiguity.sh score "$GOAL_CLARITY" "$CONSTRAINTS_CLARITY" "$CRITERIA_CLARITY")
MODE=$(bash lib/ambiguity.sh mode "$ROUND" "$SCORE")

if bash lib/ambiguity.sh gate "$SCORE"; then
  echo "[AMBIGUITY] score=$SCORE  <20 — gate passes, proceed to Phase 4 (design)."
else
  echo "[AMBIGUITY] score=$SCORE  challenge-mode=$MODE — more questions required."
  # Apply the challenge mode before the next question:
  #   normal      — continue clarifying questions as usual
  #   contrarian  — challenge every assumption with an opposing view; force justification
  #   simplifier  — push "what is the minimum that solves 80% of this?"
  #   ontologist  — refuse to proceed until every named object has a precise definition
fi
```

**Ontology stability tracking**: each round, extract the substantive tokens from the accumulated Q&A via `bash lib/ambiguity.sh extract "$ROUND_TEXT"`. Diff against the prior round's token set via `bash lib/ambiguity.sh diff "$PRIOR" "$CURRENT"` (emits `{added, removed, carried, stability}`). **Thrashing ontology** (stability < 0.5 for two consecutive rounds) forces the ontologist challenge mode regardless of score, because the vocabulary itself is unstable.

Record the final score in `.handoffs/brainstorm.md` as part of the Phase 4c handoff write, so downstream skills can verify the gate passed:

```json
{
  "decided":  [...],
  "ambiguity": { "final_score": 12, "rounds": 4, "final_mode": "normal" },
  "notes":    "..."
}
```

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
  7. LIFECYCLE: What happens beyond the happy path?
     - A) One-shot tool (run once, get output, done)
     - B) Returning users (state persists, users come back)
     - C) Integrates into an existing system (middleware, plugin, library)
     - D) Multiple of the above

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

### Phase 4b: Snapshot user intent (required for ql-intent-check)

If `quantum.json` exists (the user is extending an in-progress pipeline), and it does NOT already contain a `userIntent` field, write the user's **verbatim first-message text** into `quantum.json.userIntent` as an immutable snapshot. If `quantum.json` does not yet exist, capture the verbatim text into the design doc's front-matter so `/quantum-loop:spec` can propagate it.

Required shape (see `skills/ql-intent-check/SKILL.md` §"Immutable intent snapshot"):

```json
{
  "userIntent": {
    "text": "<verbatim first-message text>",
    "timestamp": "<ISO 8601 at write time>",
    "source_message_id": null
  },
  "userClarifications": []
}
```

**Write rules**:
- The `text` MUST be the exact verbatim text the user wrote in their first brainstorm turn — no paraphrasing, no summary.
- If `userIntent.text` is already populated, DO NOT overwrite. This field is immutable.
- Use `lib/json-atomic.sh` helpers (`write_quantum_json`) to avoid partial-write races.

Inform the user:
> "Design saved to `docs/plans/YYYY-MM-DD-<topic>-design.md`. User intent snapshot stored in quantum.json. When you're ready to create a formal spec, run `/quantum-loop:spec`."

### Phase 4c: Write stage handoff (Phase 15 / P2.3)

Before exiting, write a stage-handoff document at `.handoffs/brainstorm.md` so downstream skills (`/ql-spec`, `/ql-plan`, `/ql-execute`, reviewers) can read it even after this session's context is compacted.

Use `lib/handoff.sh`:

```bash
bash lib/handoff.sh write brainstorm "$(cat <<'JSON'
{
  "decided":   ["<each approved-section decision, verbatim>"],
  "rejected":  ["<each alternative considered and NOT chosen, with reason>"],
  "risks":     ["<each risk surfaced during brainstorm>"],
  "files":     ["docs/plans/YYYY-MM-DD-<topic>-design.md"],
  "remaining": ["<any open question left for /ql-spec to resolve>"],
  "notes":     "<free-form tail: unanswered questions, follow-ups>"
}
JSON
)"
```

Every downstream skill opens with `bash lib/handoff.sh all | jq '.'` — so any decision you record here is durable even across session boundaries.

## Phase 4d: Post-exit design-review (P5.B4 / US-006 / v0.6.3 — advisory)

After Phase 4c writes the brainstorm handoff, run the spec-reviewer in `design-review` mode against the just-saved design doc. The review is **advisory** in v0.6.3 — findings emit to stderr; the skill does NOT abort regardless of what's flagged.

```bash
DESIGN_PATH=$(ls docs/plans/*-design.md 2>/dev/null | tail -1)

# Opt-out gate: QL_SKIP_PRE_IMPL_REVIEW=design (or comma-separated, e.g. design,prd)
SKIP_LIST="${QL_SKIP_PRE_IMPL_REVIEW:-}"
if [[ -n "$DESIGN_PATH" ]] && \
   ! printf '%s' "$SKIP_LIST" | tr ',' '\n' | grep -qx "design"; then
  echo "[QL-BRAINSTORM] Running spec-reviewer in design-review mode (advisory)..." >&2
  # Dispatch the spec-reviewer subagent with MODE=design-review and the design doc path.
  # Findings are emitted to stderr in FINDING_START..FINDING_END format.
  # The skill continues regardless of what's reported — set QL_SKIP_PRE_IMPL_REVIEW=design
  # to disable this stage entirely.
  MODE=design-review DESIGN_PATH="$DESIGN_PATH" \
    claude --headless "agents/spec-reviewer.md design-review mode against $DESIGN_PATH" 2>&1 || true
else
  echo "[QL-BRAINSTORM] design-review skipped (QL_SKIP_PRE_IMPL_REVIEW=design or no design doc)" >&2
fi
```

Inform the user the design-review ran (one-line summary). If `QL_SKIP_PRE_IMPL_REVIEW=design` was set, mention that the stage was bypassed.

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
