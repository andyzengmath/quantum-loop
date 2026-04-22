# Design: Multi-Runner Support (Universal CLI Orchestrator)

**Date:** 2026-04-01
**Status:** Approved
**Approach:** Runner Adapter Library (Hybrid JSON manifest + shell hook overrides)
**Related Issue:** https://github.com/andyzengmath/quantum-loop/issues/19

## Overview

### What We're Building and Why

**Quantum-loop multi-runner support** — a runner adapter layer that lets quantum-loop orchestrate any coding CLI, not just Claude Code.

**The problem:** Today quantum-loop is hardcoded to Claude Code (and partially `amp`). Users who prefer Codex or Copilot CLI can't use quantum-loop's DAG-based orchestration, TDD enforcement, or review gates. This limits adoption and locks the project to a single ecosystem.

**The solution:** A `lib/runner.sh` library backed by JSON manifests (`runners/*.json`) that abstracts tool-specific invocation details behind a common interface. Each manifest declares:
- Binary name and how to check availability
- Headless/non-interactive flags
- Prompt delivery method (flag, positional arg, or stdin pipe)
- Auto-approve flags for autonomous mode
- Instruction file convention (CLAUDE.md vs AGENTS.md vs GEMINI.md)

Optional shell hook overrides (`runners/hooks/<tool>-hooks.sh`) handle tool-specific quirks that don't fit in JSON (e.g., codex sandbox limitations, copilot's `--autopilot` flag).

**V1 scope:**
- **Guaranteed:** Claude Code (existing behavior, zero changes)
- **Tested (proof of concept):** Codex (first non-Claude runner, fully tested)
- **Experimental (config-only):** Copilot CLI, Cursor, Gemini, Amp (migrated), Aider

**Signal reliability for non-Claude runners:**
- Prompt preamble injection with signal protocol (applied only to non-Claude runners)
- Output heuristic fallback: if no `<quantum>` signal found, scan for commit evidence + test results to infer pass/fail

**Instruction files:** `CLAUDE.md` remains the single source of truth. Before spawning a non-Claude agent, the orchestrator copies it to `AGENTS.md` (or `GEMINI.md`, etc.) if one doesn't already exist.

### Ecosystem Context (April 2026)

Research identified 13+ terminal-based coding agent CLIs. All share the same three primitives (headless mode, auto-approve, prompt delivery) with different flag syntax. This validates the manifest-driven abstraction.

| Tool | Binary | Headless | Auto-Approve | Prompt | Instruction File |
|---|---|---|---|---|---|
| Claude Code | `claude` | `--print` | `--dangerously-skip-permissions` | `-p "..."` | `CLAUDE.md` |
| Codex | `codex` | `-q` | `--approval-mode full-auto` | positional | `AGENTS.md` |
| Copilot CLI | `copilot` | (implicit w/ `-p`) | `--allow-all` | `-p "..."` | `AGENTS.md` + `CLAUDE.md` |
| Cursor | `agent` | `-p` | `--force` | `-p "..."` | `.cursorrules` + `AGENTS.md` |
| Gemini CLI | `gemini` | `-p` | `--approval-mode=yolo` | `-p "..."` | `GEMINI.md` |
| Aider | `aider` | `-m` | `--yes-always` | `-m "..."` | `CONVENTIONS.md` |
| Cline CLI | `cline` | non-TTY | `-y` / `--yolo` | positional | `.clinerules/` |
| Continue | `cn` | `-p` | `--auto` | `-p "..."` | `config.yaml` |
| Amp | `amp` | `-x` | `--dangerously-allow-all` | stdin pipe | `AGENTS.md` |
| Devin | `devin` | `-p` | `--permission-mode bypass` | positional | `devin rules` |
| Kiro CLI | `kiro-cli` | `--no-interactive` | `--trust-all-tools` | positional | `~/.kiro/steering/` |
| Goose | `goose run` | `-t` | mode flag | `-t "..."` | `.goosehints` |
| OpenCode | `opencode` | `opencode run` | env var | positional | Markdown commands |

## User Experience

### CLI Interface (No Breaking Changes)

```bash
# Existing (unchanged)
./quantum-loop.sh                           # defaults to claude
./quantum-loop.sh --tool claude             # explicit claude

# New runners
./quantum-loop.sh --tool codex              # OpenAI Codex
./quantum-loop.sh --tool copilot            # GitHub Copilot CLI
./quantum-loop.sh --tool cursor             # Cursor (experimental)
./quantum-loop.sh --tool gemini             # Google Gemini CLI (experimental)

# Parallel mode works with any runner
./quantum-loop.sh --tool codex --parallel --max-parallel 4

# PowerShell
.\quantum-loop.ps1 -Tool codex
```

### Validation Flow at Startup

1. Check if `runners/<tool>.json` exists — if not, error with "Unknown runner. Available: claude, codex, copilot, cursor, gemini, amp, aider"
2. Read manifest to get binary name
3. Check if binary is installed (`command -v`) — if not, error with install instructions from the manifest
4. If non-Claude runner, check/create instruction file from `CLAUDE.md`
5. Print runner info in the startup banner:
   ```
   Tool:        codex (via runners/codex.json)
   Binary:      codex (v0.118.0)
   Tier:        tested
   Instruction: AGENTS.md (auto-generated from CLAUDE.md)
   ```

### Experimental Runner Warnings

```
WARNING: 'cursor' is an experimental runner.
  Signal detection uses heuristic fallback.
  Report issues: https://github.com/andyzengmath/quantum-loop/issues
  Continue? [Y/n]
```

Suppressed with `--non-interactive` flag (already exists).

### Adding a Custom Runner (Zero Code Changes)

```bash
# User creates runners/my-tool.json with the required fields
# Then runs:
./quantum-loop.sh --tool my-tool
```

### Error Messages for Runner-Specific Failures

```
[RUNNER] codex exited without quantum signal.
[RUNNER] Heuristic fallback: found commit evidence, test output shows 0 failures.
[RUNNER] Inferring STORY_PASSED (confidence: high)
```

vs.

```
[RUNNER] codex exited without quantum signal.
[RUNNER] Heuristic fallback: no commit found, no test evidence.
[RUNNER] Inferring STORY_FAILED (confidence: low)
[RUNNER] Tip: Codex's sandbox blocks network. If tests need npm install, run it before launching.
```

## Data Model

### Runner Manifest Schema (`runners/<tool>.json`)

```json
{
  "$schema": "../schemas/runner.schema.json",
  "name": "codex",
  "displayName": "OpenAI Codex CLI",
  "binary": "codex",
  "version": ">=0.118.0",
  "installHint": "npm install -g @openai/codex",
  "tier": "tested",

  "invocation": {
    "promptDelivery": "positional",
    "promptFlag": null,
    "headlessFlags": ["-q"],
    "autoApproveFlags": ["--approval-mode", "full-auto"],
    "outputFlags": ["--json"],
    "extraFlags": [],
    "stdinPipe": false
  },

  "instructionFile": {
    "native": "AGENTS.md",
    "fallbackFrom": "CLAUDE.md",
    "autoGenerate": true
  },

  "signals": {
    "preambleInjection": true,
    "heuristicFallback": true
  },

  "quirks": {
    "sandboxBlocksNetwork": true,
    "noExplicitCwd": true,
    "notes": "Codex full-auto mode uses a sandboxed environment with network disabled. Tasks requiring npm install or API calls may fail."
  }
}
```

### Field Definitions

| Field | Type | Description |
|---|---|---|
| `name` | string | Runner identifier (used with `--tool`) |
| `binary` | string | Executable name checked via `command -v` |
| `tier` | `"guaranteed"` \| `"tested"` \| `"experimental"` | Support level |
| `invocation.promptDelivery` | `"flag"` \| `"positional"` \| `"stdin"` | How the prompt reaches the tool |
| `invocation.promptFlag` | string \| null | Flag name if `promptDelivery` is `"flag"` (e.g., `-p`) |
| `invocation.headlessFlags` | string[] | Flags for non-interactive output |
| `invocation.autoApproveFlags` | string[] | Flags for autonomous execution |
| `invocation.stdinPipe` | boolean | If true, prompt is piped via stdin |
| `instructionFile.native` | string | What instruction file the tool reads |
| `instructionFile.fallbackFrom` | string | Source file to copy if native doesn't exist |
| `instructionFile.autoGenerate` | boolean | Auto-create native from fallbackFrom |
| `signals.preambleInjection` | boolean | Inject signal protocol into prompt |
| `signals.heuristicFallback` | boolean | Scan output for commit/test evidence if no signal |
| `quirks` | object | Tool-specific notes and flags |

### Tier System

| Tier | Meaning | Startup Behavior |
|---|---|---|
| `guaranteed` | Fully tested, zero regressions | No warnings |
| `tested` | Works but less battle-tested | Info banner |
| `experimental` | Config included, community-maintained | Warning + confirmation prompt |

### Claude's Manifest (Reference Implementation)

```json
{
  "name": "claude",
  "displayName": "Claude Code",
  "binary": "claude",
  "tier": "guaranteed",
  "invocation": {
    "promptDelivery": "flag",
    "promptFlag": "-p",
    "headlessFlags": ["--print"],
    "autoApproveFlags": ["--dangerously-skip-permissions"],
    "outputFlags": [],
    "extraFlags": [],
    "stdinPipe": false
  },
  "instructionFile": {
    "native": "CLAUDE.md",
    "fallbackFrom": null,
    "autoGenerate": false
  },
  "signals": {
    "preambleInjection": false,
    "heuristicFallback": false
  },
  "quirks": {}
}
```

### V1 Manifests Shipped

| Runner | Tier | Status |
|---|---|---|
| `claude` | guaranteed | Existing behavior, unchanged |
| `codex` | tested | Fully tested proof-of-concept |
| `copilot` | experimental | Config included, community-validated |
| `cursor` | experimental | Config included, beta tool |
| `gemini` | experimental | Config included, discovered during research |
| `amp` | experimental | Existing support migrated to manifest |
| `aider` | experimental | Config included, no MCP (limitation noted) |

## Architecture

### Component Diagram

```
quantum-loop.sh / quantum-loop.ps1
        |
        +-- lib/runner.sh              <-- NEW: Runner abstraction layer
        |     +-- runner_load()             Load & validate runner manifest
        |     +-- runner_build_cmd()        Build tool-specific command string
        |     +-- runner_spawn()            Spawn agent (sequential or parallel)
        |     +-- runner_parse_output()     Parse output + heuristic fallback
        |     +-- runner_ensure_instructions()  Auto-generate AGENTS.md if needed
        |
        +-- runners/                   <-- NEW: Runner manifest directory
        |     +-- claude.json               Guaranteed tier
        |     +-- codex.json                Tested tier
        |     +-- copilot.json              Experimental tier
        |     +-- cursor.json               Experimental tier
        |     +-- gemini.json               Experimental tier
        |     +-- amp.json                  Experimental tier (migrated)
        |     +-- aider.json                Experimental tier
        |
        +-- runners/hooks/             <-- NEW: Optional shell hook overrides
        |     +-- codex-hooks.sh            Sandbox workarounds
        |     +-- copilot-hooks.sh          Autopilot flag handling
        |
        +-- lib/spawn.sh              <-- MODIFIED: Delegates to runner_spawn()
        +-- lib/signal-heuristics.sh   <-- NEW: Output parsing for non-Claude runners
        +-- schemas/
              +-- runner.schema.json   <-- NEW: JSON Schema for validation
```

### Flow: Sequential Mode

1. `quantum-loop.sh --tool codex`
2. `runner_load("codex")` — read `runners/codex.json`, validate against schema, check `command -v codex`, print tier warning if experimental
3. `runner_ensure_instructions("codex")` — native=`AGENTS.md`, fallbackFrom=`CLAUDE.md`. If `AGENTS.md` missing && `CLAUDE.md` exists, copy with `.ql-generated` marker
4. Select story from DAG (unchanged)
5. `runner_build_cmd("codex", "$STORY_ID", "$PROMPT")` — read manifest invocation fields, prepend signal preamble if enabled, build: `codex -q --approval-mode full-auto "<preamble + prompt>"`. Source hooks if present.
6. Execute command, capture OUTPUT
7. `runner_parse_output("codex", "$OUTPUT")` — grep for `<quantum>` signal. If not found and heuristicFallback enabled: check git log for commit, check test output patterns, infer signal with confidence level
8. Process signal (unchanged)

### Flow: Parallel Mode

1. `quantum-loop.sh --tool codex --parallel`
2. `runner_load("codex")` (same as sequential)
3. For each eligible story in wave:
   a. Create worktree (unchanged)
   b. `runner_ensure_instructions()` in worktree
   c. `runner_spawn("codex", "$STORY_ID", "$WORKTREE_PATH")` — build command via `runner_build_cmd()`, spawn as background process: `(cd $WT && $CMD > .ql-agent-output.txt 2>&1) &`, return PID
4. Monitor loop polls `.ql-agent-output.txt` (unchanged)
5. On completion: `runner_parse_output()` on each agent's output

### Key Design Decisions

1. **Claude path is a pass-through.** When `--tool claude`, the manifest has `preambleInjection: false` and `heuristicFallback: false`. The command built is identical to today's hardcoded command. Zero behavior change.

2. **Hook overrides are optional.** `runners/hooks/<tool>-hooks.sh` is sourced only if it exists. It can define `pre_spawn()` and `post_output()` functions. If no hooks file, the JSON manifest drives everything.

3. **Instruction file generation is idempotent.** `runner_ensure_instructions()` only copies if the target doesn't exist AND a source exists. Never overwrites user-maintained files. A `.ql-generated` marker at the top distinguishes auto-generated files.

4. **Heuristic fallback is defense-in-depth.** Preamble injection is the first line of defense. Heuristics only fire if no signal is detected. They produce a confidence level so the orchestrator can decide trust.

5. **Schema validation at startup.** `runner_load()` validates the manifest against `schemas/runner.schema.json` using `jq`. Bad manifests fail fast.

## Edge Cases & Error Handling

### Runner Discovery & Validation

| Scenario | Handling |
|---|---|
| `--tool foo` but `runners/foo.json` missing | Error: "Unknown runner 'foo'. Available: claude, codex, copilot, cursor, gemini, amp, aider" |
| Manifest fails JSON schema validation | Error with specific field: "runners/codex.json: missing required field 'invocation.promptDelivery'" |
| Binary not installed | Error with install hint from manifest |
| Binary installed but wrong version | Warning only (no version enforcement in v1) |

### Instruction File Edge Cases

| Scenario | Handling |
|---|---|
| `CLAUDE.md` exists, `AGENTS.md` missing, tool needs `AGENTS.md` | Auto-copy with `.ql-generated` header |
| Both `CLAUDE.md` and `AGENTS.md` exist (user-maintained) | Use existing `AGENTS.md` as-is, never overwrite |
| Neither `CLAUDE.md` nor `AGENTS.md` exists | Error: "No instruction file found. quantum-loop requires CLAUDE.md" |
| User deletes auto-generated `AGENTS.md` between iterations | Re-generated next iteration (idempotent) |
| Worktree parallel mode | `runner_ensure_instructions()` runs inside each worktree after creation |

### Signal Detection Edge Cases

| Scenario | Handling |
|---|---|
| Claude emits signal normally | Direct match, no heuristics, identical to today |
| Non-Claude emits signal (preamble worked) | Direct match, heuristics not invoked |
| Non-Claude emits NO signal, commit exists, tests pass | Heuristic: STORY_PASSED (confidence: high) |
| Non-Claude emits NO signal, commit exists, no test evidence | Heuristic: STORY_PASSED (confidence: medium), log warning |
| Non-Claude emits NO signal, no commit, no test evidence | Heuristic: STORY_FAILED (confidence: high) |
| Non-Claude emits BOTH PASSED and FAILED | Last signal wins, log warning |
| Signal with extra whitespace | Relaxed regex: `<quantum>\s*STORY_(PASSED\|FAILED\|COMPLETE\|BLOCKED)\s*</quantum>` |
| Agent process crashes (exit code != 0) | STORY_FAILED regardless of output |
| Agent process hangs (timeout exceeded) | Existing stale detection kills process, STORY_FAILED with phase: "timeout" |

### Tool-Specific Quirks

| Quirk | Tool | Handling |
|---|---|---|
| Sandbox blocks network | Codex | `codex-hooks.sh` logs warning about running npm install before launch |
| `--autopilot` continuation | Copilot | `copilot-hooks.sh` adds `--autopilot --no-ask-user` flags |
| Beta hanging bug | Cursor | Manifest `quirks.staleTimeoutOverride: 10` for shorter timeout |
| Stdin-only prompt delivery | Amp | `runner_build_cmd()` handles `stdinPipe: true` with pipe |
| No MCP support | Aider | Manifest `quirks.noMcp: true`, logged at startup |
| `GEMINI.md` instruction file | Gemini | `instructionFile.native: "GEMINI.md"`, auto-copied from CLAUDE.md |

### Backward Compatibility

| Concern | Guarantee |
|---|---|
| `--tool claude` (explicit) | Identical command. Zero diff. |
| `--tool` omitted (default) | Defaults to `claude`. Same as today. |
| `--tool amp` (existing) | Migrated to `runners/amp.json`. Same stdin pipe behavior. |
| `quantum-loop.ps1` | Reads same `runners/` manifests. PowerShell builds equivalent commands. |
| `templates/quantum-loop.sh` | Updated to use manifests. Falls back to hardcoded claude if `runners/` directory missing. |

## Testing Strategy

### Layer 1: Unit Tests (`tests/test_runner.sh`)

- `test_runner_load_valid` — loads claude.json, validates all fields
- `test_runner_load_missing` — error for nonexistent manifest
- `test_runner_load_invalid_schema` — error for missing required fields
- `test_runner_build_cmd_claude` — exact match to current hardcoded command
- `test_runner_build_cmd_codex` — positional prompt with codex flags
- `test_runner_build_cmd_copilot` — flag prompt with copilot flags
- `test_runner_build_cmd_stdin` — pipe command for amp
- `test_runner_build_cmd_preamble` — non-Claude gets signal preamble
- `test_runner_build_cmd_no_preamble` — Claude does NOT get preamble
- `test_runner_ensure_instructions_creates` — copies CLAUDE.md to AGENTS.md with marker
- `test_runner_ensure_instructions_no_overwrite` — never overwrites user file
- `test_runner_ensure_instructions_idempotent` — running twice doesn't duplicate marker

### Layer 2: Signal Parsing (`tests/test_signal_heuristics.sh`)

- `test_parse_exact_signal` — exact match works
- `test_parse_relaxed_whitespace` — whitespace tolerance
- `test_parse_no_signal_commit_exists` — heuristic PASSED (high)
- `test_parse_no_signal_no_commit` — heuristic FAILED (high)
- `test_parse_no_signal_commit_no_tests` — heuristic PASSED (medium)
- `test_parse_both_signals` — last one wins
- `test_parse_crash_exit_code` — non-zero exit = FAILED
- `test_heuristic_skipped_for_claude` — Claude never uses heuristics

### Layer 3: Integration (`tests/test_runner_integration.sh`)

- `test_tool_flag_accepts_all_manifests` — all runners pass validation
- `test_tool_flag_rejects_unknown` — unknown runner shows error with list
- `test_default_tool_is_claude` — default behavior unchanged
- `test_startup_banner_shows_runner` — runner info in banner
- `test_experimental_warning` — experimental runners show warning
- `test_experimental_no_warning_noninteractive` — `--non-interactive` suppresses
- `test_claude_command_unchanged` — **CI gate**: exact command match to current hardcoded

### Layer 4: Hook Override (`tests/test_runner_hooks.sh`)

- `test_hook_sourced_when_exists` — hooks file is loaded
- `test_no_hook_no_error` — missing hooks file is fine
- `test_hook_can_modify_command` — hooks can append flags

### Layer 5: Manifest Validation (`tests/test_runner_manifests.sh`)

- `test_all_manifests_valid_json` — all runners/*.json parse
- `test_all_manifests_have_required_fields` — schema compliance
- `test_claude_manifest_matches_hardcoded` — regression gate

### Not Tested in V1

- Actual agent execution with non-Claude runners (requires real API keys)
- Model behavior (non-deterministic — heuristic fallback is the safety net)
- PowerShell runner tests (follow-up)

## Open Questions

- Should `runners/` be a top-level directory or nested under `lib/runners/`? Current design uses top-level for discoverability.
- Should the preamble injection template be configurable per-runner, or is a single universal preamble sufficient?
- For the `templates/quantum-loop.sh` (user-facing), should we embed a minimal runner implementation or require the full `runners/` directory?
- How should we handle runner manifest versioning if the schema evolves? (e.g., `"schemaVersion": 1`)

## Next Steps

Run `/quantum-loop:spec` to generate a formal Product Requirements Document from this design.
