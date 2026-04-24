---
name: ql-intent-check
description: Intent-drift audit for quantum-loop. Compares the user's original intent (immutable snapshot) against downstream artifacts (design.md → PRD → quantum.json ACs → implementation) to detect semantic divergence. Flags drift with file:line evidence. Use before merge or when specs feel "rewritten."
allowed-tools: Read, Grep, Glob, Bash
---

# ql-intent-check — intent-drift audit

## Purpose

Long pipelines (brainstorm → spec → plan → execute → review) paraphrase. Each stage re-reads an upstream artifact and rewrites it in its own format. Over 5 stages and 20+ agent invocations, the user's original intent can drift significantly — ACs silently reinterpreted, non-goals forgotten, constraints softened.

Academic backing:
- **Semantic Consensus Framework (SCF, arXiv:2604.16339)**: formally names "Semantic Intent Divergence" as the root cause of multi-agent SWE failures. Prescribes per-agent Semantic Intent Graph + Drift Monitor.
- **Agent Drift (arXiv:2601.04170)**: introduces Agent Stability Index (ASI) and shows all models drift under pressure.
- **Goal Drift in LM Agents (arXiv:2505.02709)**: Claude 3.5 Sonnet holds goals for 100K tokens but drifts under competing objectives.

`ql-intent-check` operationalizes a lean version of SCF's Drift Monitor for quantum-loop's pipeline.

## Immutable intent snapshot

The first time `/ql-brainstorm` runs, it MUST store the user's verbatim first-message text at `quantum.json.userIntent`:

```json
{
  "userIntent": {
    "text": "<verbatim first-message text from user>",
    "timestamp": "<ISO 8601>",
    "source_message_id": "<optional session ID>"
  }
}
```

This field is **immutable** — it is written once and never updated. Subsequent clarifications live in `userClarifications[]` (append-only). The snapshot is the ground-truth anchor for drift detection.

If `quantum.json.userIntent` is missing, this skill emits a WARNING and degrades to "compare stage-to-stage" mode (less precise but still useful).

## Stages audited

1. **Intent → Design**: `userIntent.text` vs `docs/plans/<date>-<topic>-design.md`.
2. **Design → PRD**: design.md vs `tasks/prd-<feature>.md`.
3. **PRD → Plan**: PRD vs `quantum.json.stories[].acceptanceCriteria`.
4. **Plan → Implementation**: AC text vs commit messages + test names + code comments.
5. **Implementation → Review**: commit content vs `ql-review` output.

At each stage, compute:
- **Objects carried**: nouns / domain entities present in both sides (Jaccard over extracted noun-phrases).
- **Verbs carried**: action phrases.
- **Constraints carried**: numeric thresholds, time bounds, technology mandates, non-goals.
- **Novelty introduced**: new objects/verbs/constraints present downstream but absent upstream.

## Detection rules

### Rule 1 — Objects dropped without justification

An object present in the user's first message that does NOT appear in any downstream artifact is a potential drop. Check against an explicit "de-scoped" list (should live in PRD §5 Non-goals). If not listed as de-scoped, emit a **MEDIUM** finding.

### Rule 2 — Constraints softened or dropped

Numeric thresholds or hard constraints present in intent but weakened downstream. E.g., user says "must complete in under 100ms"; PRD AC says "target 200ms". Emit a **HIGH** finding unless explicitly re-negotiated (a `userClarifications[]` entry rewrites the constraint).

### Rule 3 — Objects introduced without upstream source

An object present in the PRD or quantum.json that appears nowhere upstream. Often the sign of an implementer inventing scope. Emit a **MEDIUM** finding; user confirms whether scope-expansion was intentional.

### Rule 4 — Non-goals violated

PRD §5 non-goals list vs actual commit files. If a commit touches a path explicitly marked non-goal, emit a **CRITICAL** finding.

### Rule 5 — AC paraphrase mismatch

Every PRD acceptance-criterion (`AC-N`) should appear verbatim (or with trivial lexical variation) in a `quantum.json.stories[].acceptanceCriteria[]` entry. Lexical mismatch above a threshold → **HIGH** finding.

### Rule 6 — Test coverage gap per AC

Every AC should map to at least one test (file + symbol) that explicitly exercises it. Missing mapping → **MEDIUM** finding. The AC itself must also specify the verification command per the quantum-loop `testFirst` convention.

### Rule 7 — Implementation scope creep

Commit diffs touching files outside the PRD-declared `files_changed` whitelist. Two sub-cases:
- Test files: OK by default.
- Production files: **HIGH** finding unless the PRD ACs authorize it (grep AC text for the file path or a covering abstraction).

## Input

- `quantum.json` (must exist; `userIntent` field is preferred but optional).
- Current branch state.
- Optional: `--since-commit=<sha>` to scope to a recent window.

## Output

Emits JSON at `quantum.intentDrift[<feature-id>]`:

```json
{
  "timestamp": "<ISO 8601>",
  "base_sha": "<first-commit>",
  "head_sha": "<last-commit>",
  "has_immutable_intent": true,
  "stages_audited": ["intent→design", "design→prd", "prd→plan", "plan→impl"],
  "findings": [
    {
      "id": "DRIFT-001",
      "rule": "Rule 2 — Constraint softened",
      "severity": "high",
      "original": "must complete in under 100ms",
      "source": "userIntent.text",
      "downstream": "target 200ms",
      "downstream_location": "tasks/prd-feature.md:44",
      "clarification_id_if_any": null,
      "suggested_action": "Either (a) add a userClarifications entry explaining the re-negotiation, or (b) tighten PRD AC to ≤100ms and re-plan."
    }
  ],
  "summary": {
    "critical": 0,
    "high": 1,
    "medium": 3,
    "low": 0,
    "info": 0
  },
  "verdict": "DRIFT_DETECTED_REVIEW_REQUIRED"
}
```

Verdicts:
- `NO_DRIFT` — zero findings.
- `MINOR_DRIFT` — only low/info findings.
- `DRIFT_DETECTED_REVIEW_REQUIRED` — any medium or higher.
- `CRITICAL_DRIFT_BLOCKS_MERGE` — ≥1 critical.

## Anti-rationalization guards

| The agent says… | The truth is… |
|-----------------|---------------|
| "The user's intent is implicit in the PRD" | No. PRD is a paraphrase of the intent. Keep the verbatim intent separately and audit against it. |
| "Scope-creep is a feature, the user will appreciate it" | Rule 3 explicitly requires user confirmation. Silently expanded scope is expanded review burden and possible rework. |
| "Non-goals are aspirational, violating them isn't critical" | Non-goals are contracts. Violating them is a CRITICAL finding by Rule 4. |
| "AC paraphrase is fine, they mean the same thing" | If they truly mean the same thing, the original should pass the AC. If they don't quite, the paraphrase hides a semantic slip. Rule 5 applies. |

## How to invoke

```
/quantum-loop:ql-intent-check
```

Optional arguments:
```
/quantum-loop:ql-intent-check --feature=<prd-id>
/quantum-loop:ql-intent-check --since-commit=<sha>
/quantum-loop:ql-intent-check --fail-on=high    # exit non-zero if any high-or-above finding
```

## Integration with existing skills

- **`ql-brainstorm`**: MUST write `quantum.json.userIntent` on first run (immutable). Schema extension below.
- **`ql-spec`**: MUST preserve the PRD `§5 Non-goals` section verbatim.
- **`ql-plan`**: MUST preserve AC text verbatim into `quantum.json.stories[].acceptanceCriteria`.
- **`ql-execute`**: optionally runs this skill mid-pipeline (after every N merged stories) to detect drift early.
- **`ql-deep-review`**: consumes the intent-drift signal as its risk-score input.

## Required quantum.json schema extension

Propose the following additive fields:

```json
{
  "userIntent": {
    "text": "<verbatim>",
    "timestamp": "<ISO 8601>",
    "source_message_id": "<session ref>"
  },
  "userClarifications": [
    {
      "id": "CLAR-001",
      "timestamp": "<ISO 8601>",
      "text": "<verbatim>",
      "re-negotiates": ["<intent sentence>" or "AC-3"]
    }
  ],
  "intentDrift": {
    "<feature-id>": { /* output from this skill */ }
  }
}
```

These additions are optional for existing quantum.json files (backward-compatible), but REQUIRED for new plans after this skill is in production.

## Known limitations (honest)

- **Lexical drift detection is shallow**. Advanced semantic-intent-graph extraction (per SCF 2604.16339) is Tier-B work, not shipped here.
- **Verb extraction is heuristic**. English-centric; degrades on Chinese or mixed-language projects. Users with Chinese PRDs should treat findings as hints.
- **Rule 7 scope-creep check** over-fires on refactoring commits. Consider `noqa`-style annotations on legitimate cross-cut commits.
- **The immutable-intent snapshot assumption is fragile**. If the user's first message is brief ("build me a todo app"), the snapshot is too lean for rule-1/2/3 detection. In those cases, Rule 4 (non-goals) and Rule 5 (AC paraphrase) still provide value.
