# Sprint-Contract handoff format (P5.A6 / US-006)

The Sprint-Contract is the per-story serialized decision-context written by `/ql-plan` (via `agents/dag-validator.md`) and consumed by `/ql-execute` (`agents/implementer.md`) and `/ql-review` (`agents/spec-reviewer.md` + `agents/quality-reviewer.md`).

It mirrors Anthropic's 2026-03-24 Generator-Evaluator contract pattern: the Generator (planner) writes a structured contract that the Evaluator (implementer/reviewer) consumes instead of re-reading the entire PRD. This reduces handoff drift between pipeline stages.

## File path

```
.handoffs/sprint-<storyId>.json
```

One file per story. Written by `lib/handoff.sh:write_sprint_contract`. Consumed by `lib/handoff.sh:read_sprint_contract`.

## Required fields

| Field | Type | Description |
|---|---|---|
| `storyId` | string | The story ID this contract is for (e.g., `"US-001"`) |
| `prdSha` | string | sha256 of the PRD content at planning time (RAGShield Level-1, US-005). Implementer validates this matches the current PRD before proceeding. |
| `acs` | string[] | Acceptance criteria, copied verbatim from the PRD. The implementer maps each task to one or more ACs. |
| `contracts` | object | Subset of `quantum.json.contracts` relevant to this story (env_vars, shared_types, api_routes the story consumes). |
| `files` | string[] | Files the story is allowed to modify, derived from `tasks[].filePaths`. |
| `expectedTests` | string[] | Test commands/patterns the implementer must produce or extend. **G9 / US-002 (v0.6.3):** filtered to commands matching the test-pattern regex — non-test commands move to `otherCommands`. **G14 / US-003 (v0.7.0):** the regex value is defined exactly once at `lib/handoff.sh::SPRINT_CONTRACT_TEST_REGEX` and consumed via `jq --arg pattern "$SPRINT_CONTRACT_TEST_REGEX"`. |
| `otherCommands` | string[] (optional, default `[]`) | Non-test commands from the per-task `commands` array (typecheck, lint, build, install). Sibling of `expectedTests`. Added in v0.6.3 (G9 / US-002). Existing readers that ignore unknown fields are unaffected. |
| `plannedBy` | string | Identifier of the planner agent (e.g., `"dag-validator"` or `"planner-stub"`). |
| `plannedAt` | string | ISO 8601 timestamp of contract creation. |

## Example

```json
{
  "storyId": "US-001",
  "prdSha": "a1355266605d5e1d...",
  "acs": [
    "agents/orchestrator.md Step 3B.3 includes 3 explicit watchdog calls",
    "lib/watchdog.sh internal call sites no longer reference kill_agent_process"
  ],
  "contracts": {
    "env_vars": {},
    "shared_types": {}
  },
  "files": [
    "agents/orchestrator.md",
    "lib/watchdog.sh",
    "tests/test_watchdog_wiring.sh"
  ],
  "expectedTests": [
    "tests/test_watchdog_wiring.sh"
  ],
  "plannedBy": "dag-validator",
  "plannedAt": "2026-04-26T03:30:00Z"
}
```

## Lifecycle

1. **`/ql-plan` exit** — `agents/dag-validator.md` writes one sprint-contract per story to `.handoffs/sprint-<storyId>.json` via `write_sprint_contract`.
2. **`/ql-execute` start** — `agents/implementer.md` reads the sprint-contract via `read_sprint_contract` and validates `prdSha` matches the current PRD. On mismatch the story is marked `stale` (per US-005's RAGShield check).
3. **`/ql-review`** — `agents/spec-reviewer.md` and `agents/quality-reviewer.md` read the sprint-contract for AC reference instead of re-reading the full PRD.

## Backward compatibility

- Stories without a sprint-contract on disk: `read_sprint_contract` emits `{}` and a one-line warning to stderr; consuming agents fall back to re-reading the PRD directly.
- Sprint-contracts missing required fields: `write_sprint_contract` warns to stderr but still writes the file. Consumers detect missing fields with `jq -e 'has("<field>")'` and degrade gracefully.

## See also

- `lib/handoff.sh` — implementation
- `tests/test_sprint_contract.sh` — write/read round-trip + schema tests
- `lib/json-atomic.sh:compute_prd_sha` — sha256 helper used to set `prdSha` (US-005)
