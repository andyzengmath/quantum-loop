# Finding-severity rubric (G16 / US-004 / v0.7.0)

The advisory pre-impl-review modes shipped in v0.6.3 (`design-review`, `prd-review`, `plan-review`, see `agents/spec-reviewer.md`) emit `FINDING_START..FINDING_END` blocks with one of four severities: `critical | high | medium | low`. Without a rubric, the same problem can land at different severities across modes, and operators can't compare a `design-review` `critical` to a downstream `quality-reviewer` `critical`.

This document is the rubric. The three pre-impl modes share the four-band scale; each mode's row gives a mode-specific example drawn from that mode's existing checklist categories (see `agents/spec-reviewer.md`).

The rubric is consumed in two places:
- `agents/spec-reviewer.md` -- each mode's `## Mode: <mode>` section cross-links the relevant rubric section.
- Future v0.7.x calibration work -- once `metrics/pre-impl-review-findings.csv` (G13) accumulates ≥1 release of baseline data, the rubric quartiles can be tightened against actual finding distributions.

Severity decisions are advisory only in v0.7.0. Promotion of any pre-impl stage from advisory to blocking is explicitly deferred per the PRD's NG-1.

---

## design-review

`design-review` runs after `/ql-brainstorm` writes `docs/plans/YYYY-MM-DD-<topic>-design.md`. Findings target structural gaps in the design doc itself, not the eventual implementation.

| Severity | Rubric                                                                                                                              | Example                                                                                            |
|----------|-------------------------------------------------------------------------------------------------------------------------------------|----------------------------------------------------------------------------------------------------|
| critical | Missing top-level section that gates downstream work; without it, `ql-spec` cannot produce a coherent PRD.                          | `missing-section`: no `## Stories` or `## Wave plan` section -- planner has no anchor.             |
| high     | Section present but contains a hedge or unfinished thought that, if shipped to PRD, becomes a vacuous AC.                           | `hedge-phrase`: "should work for most cases" in the architecture section.                          |
| medium   | Marker indicating known-incomplete content that the author intended to revisit but did not.                                          | `tbd-marker`: literal `TBD` / `FIXME` / `XXX` in a section body.                                   |
| low      | Convention drift that doesn't block downstream stages but adds review friction (e.g. missing optional structural element).            | `missing-non-goals`: no `## Non-Goals` section to anchor the over-building audit.                   |

---

## prd-review

`prd-review` runs after `/ql-spec` writes `tasks/prd-<feature>.md`. Findings target machine-verifiability of acceptance criteria and functional requirements.

| Severity | Rubric                                                                                                                              | Example                                                                                            |
|----------|-------------------------------------------------------------------------------------------------------------------------------------|----------------------------------------------------------------------------------------------------|
| critical | Missing PRD section the planner needs to build a wave DAG; without it, story granularity cannot be derived.                         | `missing-section`: no `## User Stories` or `## Functional Requirements`.                           |
| high     | AC or FR worded so vaguely it cannot be tested deterministically -- "works correctly", "as expected", "is fast" with no threshold.   | `non-testable-ac`: "Performance is acceptable" -- no command, file:line, or threshold to verify.   |
| medium   | FR present but missing a measurement method (no test command, no observable, no threshold).                                          | `vague-fr`: `FR-3: System handles errors gracefully` with no test pointer.                         |
| low      | Success metric narrative-only ("users will be happier") rather than numeric / count / ratio.                                          | `non-quantifiable-metric`: "Operator satisfaction improves" -- no quantifiable measurement.        |

---

## plan-review

`plan-review` runs after `/ql-plan` finalizes `quantum.json` (after dag-validator and sprint-contract write). Findings target plan-vs-PRD coverage gaps and dead-code risks.

| Severity | Rubric                                                                                                                              | Example                                                                                            |
|----------|-------------------------------------------------------------------------------------------------------------------------------------|----------------------------------------------------------------------------------------------------|
| critical | A PRD acceptance criterion has zero coverage in any story's `acceptanceCriteria[]` -- the feature ships missing the AC entirely.    | `ac-coverage-gap`: PRD AC "Snapshot is overwritten on re-run" not referenced by any story.         |
| high     | A new module / exported symbol has no consumer story (no wiring task, no `consumedBy`) -- built but never called.                   | `non-consumed-export`: `lib/finding-persist.sh` created with no story importing or calling it.     |
| medium   | A `testFirst: true` task has no `commands[]` entry matching `SPRINT_CONTRACT_TEST_REGEX` -- TDD intent without a test command.       | `testfirst-no-test-command`: task says testFirst but only `commands: ["tsc --noEmit"]`.            |
| low      | New module's tasks lack an explicit "wiring" task description even when `consumedBy` is correctly set -- callable but undocumented. | `missing-wiring-task`: parser exists, consumer story imports it, but no task narrates the call site.|

---

## See also

- `agents/spec-reviewer.md` -- the three `## Mode: <mode>` blocks that emit findings against this rubric.
- `lib/finding-synth.sh` -- parser that consumes the `severity:` field per finding.
- `lib/finding-persist.sh` -- persistence layer that aggregates per-severity counts into `metrics/pre-impl-review-findings.csv` (US-002 / G13).
- `tasks/prd-v0.7.0-bundle.md` §NG-9 -- examples are checklist-derived, not statistical-quartile-derived. Calibration follows after baseline data accumulates.
