---
name: ql-deep-review
description: Multi-perspective post-implementation review aggregator for quantum-loop. Invokes 2-7 reviewer agents in parallel based on risk score, applies actionability filter, dedups, aggregates with evidence requirements. Use AFTER the per-story two-stage review gates pass and before merging a whole-feature PR to master. Complements ql-review (per-story) with whole-feature review.
allowed-tools: Read, Write, Edit, Grep, Glob, Bash, Agent
---

# ql-deep-review — whole-feature post-implementation review

## Purpose

quantum-loop's built-in two-stage review gate (`ql-review`: spec-compliance → code-quality) operates on ONE story at a time inside ONE worktree. It does not detect:

1. **Cross-story divergence** (e.g., story A uses `'google'` as a secret key while story B uses `'google-api-key'` for the same constant).
2. **Post-merge regressions** (test that was green in isolation breaks after integration).
3. **Drift from original user intent** (paraphrase chain from intent → design → PRD → plan → code).
4. **Low-signal comments** that look like findings but lack evidence (CRA actionability is 0.9-19.2% per Chowdhury 2604.03196; human baseline is ~60%).

`ql-deep-review` closes these gaps with a whole-feature review that runs AFTER all stories in a wave / feature pass the per-story gate.

## When to use

- After `ql-execute` emits `COMPLETE` for a wave and before merging the feature branch to master.
- After cherry-picking or merging a foreign branch whose conflict-resolution changed semantics.
- Manually, when suspicion of cross-story drift is high (e.g., follow-on work after a long autonomous run).

## What it does NOT do

- **Does not** replace the per-story two-stage gate. Run `ql-review` per story, then this.
- **Does not** auto-fix findings. Produces a structured report; user or orchestrator drives action.
- **Does not** block merge autonomously. Emits a verdict + confidence; user decides.

## Risk scoring (0-100)

Risk factors and weights (inspired by soliton's risk-adaptive dispatch):

| Factor | Weight | Measurement |
|--------|:------:|-------------|
| Blast radius | 25 | count of files touched in wave × (max transitive callers of any touched symbol ÷ 100) |
| Change complexity | 15 | `difftastic` or `cloc` diff line count; tree-sitter function edit count |
| Sensitive paths | 20 | glob match: `auth/`, `payment/`, `*.env*`, `*secret*`, `*password*`, `*token*` |
| File size / scope | 10 | total LOC touched / number of files |
| AI-authored signal | 10 | git commit trailer `Co-Authored-By: Claude`, uniform-style heuristic |
| Test coverage gap | 10 | production files touched without corresponding test edits |
| Intent-drift signal | 10 | `ql-intent-check` CRITICAL findings count (optional input) |

Score → dispatch tier:
- **0-30 LOW**: 2 reviewers (code-reviewer, synthesizer). Target turnaround 2-3 min.
- **31-60 MEDIUM**: 4 reviewers (+security-reviewer, test-engineer). 4-6 min.
- **61-80 HIGH**: 6 reviewers (+critic, architect). 6-10 min.
- **81-100 CRITICAL**: 7 reviewers (+cross-provider critic using codex or gemini via `/ask`). 10-15 min plus manual inspection.

## Reviewer agents (dispatched per tier)

All agents are invoked via the `Agent` tool in parallel. Each receives:
- `BASE_SHA..HEAD_SHA` — whole-feature diff scope
- `PRD_PATH` — path to the feature PRD
- `STORY_LIST` — JSON list of stories executed with their IDs and status
- `INTENT_SNAPSHOT` — verbatim user intent (from `quantum.json.userIntent` if present)
- `CHANGED_FILES` — file-list manifest

### Tier-core reviewers (always dispatched)

- **`oh-my-claudecode:code-reviewer`** — severity-rated findings (CRITICAL / HIGH / MEDIUM / LOW) with line-level evidence.
- **`soliton:synthesizer`** — risk-adaptive PR-style review; contributes a reviewer-side risk score and a READY_TO_MERGE / NEEDS_REWORK / BLOCKED verdict.

### Tier-MEDIUM additions

- **`oh-my-claudecode:security-reviewer`** — OWASP Top 10 + secret exposure + input validation; hard-dispatched when sensitive-paths factor > 0.
- **`oh-my-claudecode:test-engineer`** — test-quality audit: AC-to-test mapping, over-mock detection (Hora & Robbes 2026), missing edge cases.

### Tier-HIGH additions

- **`oh-my-claudecode:critic`** — multi-perspective adversarial critique; self-audit + Realist Check.
- **`oh-my-claudecode:architect`** — architectural review: SOLID, layering, cross-cutting concerns.

### Tier-CRITICAL additions

- **Cross-provider critic** — via `omc ask codex --agent-prompt critic` (Codex reviews Claude's output) OR `omc ask gemini`. Different failure modes → higher catch rate.

## Actionability filter (the Chowdhury 2604.03196 fix)

Every finding returned by a reviewer MUST include:
1. `file` (string, path)
2. `line` or `line_start` + `line_end` (integer)
3. `evidence_type`: one of `code-reference` / `command-output` / `spec-citation` / `test-failure` / `diff-hunk`
4. `severity`: `critical` / `high` / `medium` / `low` / `info`
5. `confidence`: 0-100

Findings missing any required field are moved to a `suppressed[]` array with reason "no actionable evidence." Surface count to the user; do not silently drop.

## Synthesis

### Dedup

Group findings by `(file, line_start, severity)`; merge identical claims from different reviewers by concatenating `agents` array. Increases confidence when multiple reviewers agree (per MARS 2509.20502).

### Conflict detection

Two findings on the same `(file, line)` with opposed verdicts (e.g., one says "introduce abstraction", another says "remove abstraction") are flagged in a `conflicts[]` block for user arbitration.

### Hallucination check

For every finding that cites a file / symbol / API:
- Verify the file exists: `[ -f "$file" ]`.
- Verify the symbol is reachable (grep for declaration).
- Verify commands in `suggested_fix` actually match project toolchain.
Findings that fail this check move to `suppressed[]` with reason "reviewer hallucinated target."

### Meta-review

The orchestrator (or this skill's own synthesis step) produces:
- **Overall verdict**: `APPROVE` / `APPROVE_WITH_COMMENTS` / `REQUEST_CHANGES` / `BLOCKS_MERGE`.
- **Critical blockers** (severity=critical with confidence ≥80).
- **High-priority issues** (severity=high with confidence ≥70).
- **Kudos** (explicitly captured positive signals — what was done well).
- **Suppressed findings count** (transparency about what was dropped).

## Output format

Emits a single JSON artifact at `quantum.reviews[<feature-id>].deepReview`:

```json
{
  "feature_id": "<prd-id or feature-slug>",
  "base_sha": "<before-first-story-commit>",
  "head_sha": "<after-last-story-commit>",
  "files_changed": 12,
  "stories_included": ["US-001", "US-002", ...],
  "timestamp": "<ISO 8601>",
  "risk_score": 47,
  "tier": "MEDIUM",
  "reviewers_dispatched": ["code-reviewer", "synthesizer", "security-reviewer", "test-engineer"],
  "findings": [
    {
      "id": "F-001",
      "agents": ["code-reviewer", "synthesizer"],
      "severity": "high",
      "confidence": 88,
      "category": "correctness",
      "file": "src/auth/session.ts",
      "line_start": 42, "line_end": 48,
      "evidence_type": "code-reference",
      "description": "<what>",
      "suggested_fix": "<how>",
      "cites": ["PRD AC-3", "tests/auth.test.ts:100"]
    }
  ],
  "conflicts": [],
  "suppressed": [{"agent": "architect", "reason": "no line citation", "count": 2}],
  "kudos": ["Clean separation of concerns in the new token-refresh flow"],
  "verdict": "APPROVE_WITH_COMMENTS",
  "blockers": [],
  "high_priority": ["F-001", "F-003"]
}
```

Also emits a human-readable markdown summary to `docs/reviews/<feature-id>-deep-review.md`.

## Anti-rationalization guards

| The agent says… | The truth is… |
|-----------------|---------------|
| "We already did per-story review, this is redundant" | Per-story review is story-LOCAL. Cross-story + whole-feature review catches different defects. Both are required. |
| "Risk score is LOW, skip the deep review" | Run LOW-tier anyway (2 reviewers, 2-3 min). The cost is a rounding error on a multi-hour autonomous run. |
| "Reviewer didn't cite evidence but it's clearly right" | Without evidence the finding is an opinion. Suppress it. Low-signal findings lower the whole reviewer distribution per Chowdhury 2604.03196. |
| "Conflict between two reviewers means one is wrong — pick the stronger" | No. Log the conflict and let the user arbitrate. Silent pick is a different failure mode. |
| "APPROVE_WITH_COMMENTS means done" | Comments still need addressing before merge unless user explicitly waives them. Treat "approve with comments" as "conditional approve." |
| "Hallucination check failed on one finding — suppress the whole report" | Suppress just the hallucinated finding. Rest of the report is valid. |

## How to invoke

```
/quantum-loop:ql-deep-review
```

With optional arguments:
```
/quantum-loop:ql-deep-review --tier=CRITICAL          # Force tier escalation
/quantum-loop:ql-deep-review --exclude=architect      # Skip one reviewer
/quantum-loop:ql-deep-review --feature=<prd-id>       # Explicit feature scope
```

## Integration with existing skills

- **`ql-review`** (per-story): runs per story inside each worktree. Different scope.
- **`ql-verify`** (Iron Law): runs as the last check inside a story's implementer agent. Different granularity.
- **`ql-execute`**: after emitting `COMPLETE`, should invoke `ql-deep-review` before handing the merged branch back to the user (opt-in via `--deep-review` flag).
- **`ql-intent-check`**: feeds the "intent-drift signal" risk factor. Can be run independently first to pre-populate the signal.
- **`ql-housekeep`**: pre-flight hygiene check; findings here are inputs to the reviewer dispatch context.

## Known limitations (honest)

- **Latency**: tier HIGH or CRITICAL can take 10-15 min. Acceptable at the end of a multi-hour autonomous run; not suitable for interactive dev loops.
- **Cost**: seven parallel reviewers × ~10K tokens each ≈ 70K input tokens per CRITICAL review. Budget-aware.
- **Reviewer drift**: the reviewer agents themselves can hallucinate. The hallucination check catches the coarse cases; subtle hallucinations (e.g., incorrect semantic claims about framework behavior) slip through.
- **Evidence rubric is language-agnostic**: some languages (Rust, OCaml) have richer evidence channels (borrow-checker output) this rubric doesn't exploit yet.
