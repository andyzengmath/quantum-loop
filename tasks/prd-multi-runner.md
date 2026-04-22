# PRD: Multi-Runner Support (Universal CLI Orchestrator)

**Related Issue:** https://github.com/andyzengmath/quantum-loop/issues/19
**Design Doc:** `docs/plans/2026-04-01-multi-runner-support-design.md`

---

## 1. Introduction/Overview

Quantum-loop is currently hardcoded to Claude Code (and partially `amp`) for agent execution. This PRD adds a runner adapter layer that lets quantum-loop orchestrate any coding CLI — Codex, Copilot CLI, Gemini CLI, and beyond — through JSON manifest files and optional shell hook overrides. Users switch runners with `--tool codex` and can add custom runners by dropping a JSON file in `runners/`. Claude Code remains the guaranteed default with zero behavior changes.

---

## 2. Goals

- Enable quantum-loop to work with any terminal-based coding agent CLI via a declarative manifest system
- Ship 7 runner manifests: Claude (guaranteed), Codex (tested), Copilot/Cursor/Gemini/Amp/Aider (experimental)
- Maintain zero regression for existing Claude Code users — the refactored path must produce identical commands
- Provide robust signal detection for non-Claude runners via preamble injection + heuristic fallback
- Achieve full parity across `quantum-loop.sh` (sequential + parallel), `quantum-loop.ps1`, and `templates/quantum-loop.sh`
- Update README and marketplace.json to reflect multi-runner capabilities

---

## 3. User Stories

### US-001: Runner JSON Schema and Validation

**Description:** As a contributor, I want a formal JSON schema for runner manifests so that invalid configurations fail fast at startup with clear error messages.

**Acceptance Criteria:**
- [ ] `schemas/runner.schema.json` exists and defines all required fields: `name`, `displayName`, `binary`, `tier`, `invocation` (with `promptDelivery`, `headlessFlags`, `autoApproveFlags`), `instructionFile`, `signals`
- [ ] `tier` field is an enum of `"guaranteed"`, `"tested"`, `"experimental"`
- [ ] `invocation.promptDelivery` field is an enum of `"flag"`, `"positional"`, `"stdin"`
- [ ] `invocation.promptFlag` is required when `promptDelivery` is `"flag"`, nullable otherwise
- [ ] Schema includes `$schema` self-reference, `description` annotations for each field, and `additionalProperties: false` on all objects
- [ ] `jq` can validate a manifest against the schema (validation function documented in code comments)
- [ ] Typecheck/lint passes (shellcheck on any shell scripts)

---

### US-002: Runner Load Function

**Description:** As a developer, I want a `runner_load()` function in `lib/runner.sh` that reads and validates a runner manifest so that the orchestrator can dynamically configure itself for any runner.

**Acceptance Criteria:**
- [ ] `lib/runner.sh` exists with `runner_load(tool_name)` function
- [ ] `runner_load("codex")` reads `runners/codex.json` relative to `$SCRIPT_DIR`
- [ ] Returns error with message "Unknown runner 'foo'. Available: ..." listing all `.json` files in `runners/` (minus extension) when manifest not found
- [ ] Validates required fields exist using `jq`: `name`, `binary`, `tier`, `invocation.promptDelivery`, `invocation.headlessFlags`, `invocation.autoApproveFlags`
- [ ] Returns error with specific field name when validation fails: "runners/codex.json: missing required field 'invocation.promptDelivery'"
- [ ] Checks `command -v $binary` and returns error with `installHint` from manifest when binary not found
- [ ] Sets shell variables: `RUNNER_NAME`, `RUNNER_BINARY`, `RUNNER_TIER`, `RUNNER_PROMPT_DELIVERY`, `RUNNER_PROMPT_FLAG`, `RUNNER_HEADLESS_FLAGS`, `RUNNER_AUTO_APPROVE_FLAGS`, `RUNNER_STDIN_PIPE`, `RUNNER_INSTRUCTION_NATIVE`, `RUNNER_INSTRUCTION_FALLBACK`, `RUNNER_PREAMBLE_INJECTION`, `RUNNER_HEURISTIC_FALLBACK`
- [ ] Sources `lib/common.sh` for shared utilities
- [ ] Typecheck/lint passes (shellcheck)

---

### US-003: Runner Command Builder

**Description:** As a developer, I want a `runner_build_cmd()` function that constructs the correct shell command for any runner based on its manifest so that the orchestrator doesn't need tool-specific branching.

**Acceptance Criteria:**
- [ ] `runner_build_cmd(prompt)` function exists in `lib/runner.sh`
- [ ] For `promptDelivery: "flag"`: outputs `$BINARY $HEADLESS_FLAGS $AUTO_APPROVE_FLAGS $PROMPT_FLAG "$prompt"`
- [ ] For `promptDelivery: "positional"`: outputs `$BINARY $HEADLESS_FLAGS $AUTO_APPROVE_FLAGS "$prompt"`
- [ ] For `promptDelivery: "stdin"`: outputs `printf '%s' "$prompt" | $BINARY $HEADLESS_FLAGS $AUTO_APPROVE_FLAGS`
- [ ] When `RUNNER_PREAMBLE_INJECTION` is true, prepends the signal protocol preamble to `$prompt`
- [ ] When `RUNNER_PREAMBLE_INJECTION` is false (Claude), prompt is passed unmodified
- [ ] If `runners/hooks/$RUNNER_NAME-hooks.sh` exists, sources it and calls `pre_spawn()` if defined (passing the built command as argument)
- [ ] The built command for `runner_load("claude")` followed by `runner_build_cmd("$PROMPT")` produces `claude --dangerously-skip-permissions --print -p "$PROMPT"` — byte-for-byte identical to the current hardcoded command in `quantum-loop.sh:779`
- [ ] Typecheck/lint passes (shellcheck)

---

### US-004: Instruction File Auto-Generation

**Description:** As a user running a non-Claude agent, I want the orchestrator to automatically create the correct instruction file (AGENTS.md, GEMINI.md) from CLAUDE.md so that non-Claude runners can read the quantum-loop protocol.

**Acceptance Criteria:**
- [ ] `runner_ensure_instructions()` function exists in `lib/runner.sh`
- [ ] When `RUNNER_INSTRUCTION_NATIVE` differs from `RUNNER_INSTRUCTION_FALLBACK` and the native file does not exist and the fallback file exists: copies fallback to native
- [ ] The generated file starts with a comment: `<!-- .ql-generated: Auto-generated from CLAUDE.md by quantum-loop. Do not edit manually. -->`
- [ ] When the native file already exists (user-maintained), it is NOT overwritten — function returns 0 silently
- [ ] When neither native nor fallback exists, returns error: "No instruction file found. quantum-loop requires CLAUDE.md"
- [ ] Function is idempotent: running twice produces identical output, does not duplicate the marker comment
- [ ] Works inside worktree directories (accepts optional path argument, defaults to current directory)
- [ ] Typecheck/lint passes (shellcheck)

---

### US-005: Signal Protocol Preamble

**Description:** As a developer, I want a preamble template containing the full quantum-loop protocol (signals, worktree rules, TDD, commit format) that gets injected into prompts for non-Claude runners so that they understand the expected output contract.

**Acceptance Criteria:**
- [ ] `runners/preamble.md` exists containing the full protocol: 4 signal formats (`STORY_PASSED`, `STORY_FAILED`, `COMPLETE`, `BLOCKED`), worktree isolation rules, TDD conventions (RED/GREEN/REFACTOR), commit format (`feat: <Story ID> - <Title>`), and the Iron Law
- [ ] `runner_inject_preamble(prompt)` function in `lib/runner.sh` reads `runners/preamble.md` and prepends it to the prompt separated by `\n\n---\n\n`
- [ ] When `RUNNER_PREAMBLE_INJECTION` is false, `runner_inject_preamble()` returns the prompt unchanged
- [ ] The preamble includes: "YOU MUST output exactly one of these signals before exiting" with the 4 formats
- [ ] The preamble is under 2000 tokens (approximately 8000 characters) to avoid consuming excessive context
- [ ] Typecheck/lint passes (shellcheck)

---

### US-006: Signal Heuristic Fallback

**Description:** As a developer, I want a heuristic output parser that infers story pass/fail from commit evidence and test output when a non-Claude runner fails to emit a quantum signal so that stories are not incorrectly left in limbo.

**Acceptance Criteria:**
- [ ] `lib/signal-heuristics.sh` exists with `parse_agent_output(output, exit_code, worktree_path)` function
- [ ] If `exit_code != 0`, returns `STORY_FAILED` with confidence `high` regardless of output content
- [ ] If output contains `<quantum>STORY_PASSED</quantum>` (with relaxed whitespace regex `<quantum>\s*STORY_PASSED\s*</quantum>`), returns `STORY_PASSED` with confidence `exact`
- [ ] If output contains `<quantum>STORY_FAILED</quantum>` (relaxed), returns `STORY_FAILED` with confidence `exact`
- [ ] If output contains `<quantum>COMPLETE</quantum>` (relaxed), returns `COMPLETE` with confidence `exact`
- [ ] If output contains `<quantum>BLOCKED</quantum>` (relaxed), returns `BLOCKED` with confidence `exact`
- [ ] If both PASSED and FAILED signals found, the LAST occurrence wins. Logs: `"[RUNNER] WARNING: Multiple conflicting signals detected. Using last: <signal>"`
- [ ] Heuristic fallback (no signal found): checks `git -C "$worktree_path" log -1 --format=%s 2>/dev/null` for commit matching `feat:` pattern → evidence_commit=true/false
- [ ] Heuristic fallback: scans output for test pass patterns (`0 failures`, `0 failed`, `tests passed`, `All tests passed`) → evidence_tests=true/false
- [ ] Heuristic fallback: scans output for error patterns (`FATAL`, `panic`, `unhandled`, `Error:`, `FAILED`) → evidence_errors=true/false
- [ ] Decision matrix: commit+tests+no_errors → PASSED(high); commit+no_tests+no_errors → PASSED(medium); no_commit → FAILED(high); commit+errors → FAILED(high)
- [ ] When confidence is `medium`, logs: `"[RUNNER] Heuristic inference: STORY_PASSED (confidence: medium) — no test evidence found"`
- [ ] When confidence is `low` (should not happen with current matrix but future-proofing), treats as FAILED
- [ ] `runner_parse_output(output, exit_code, worktree_path)` wrapper in `lib/runner.sh` calls `parse_agent_output()` only when `RUNNER_HEURISTIC_FALLBACK` is true, otherwise only does exact signal match
- [ ] Typecheck/lint passes (shellcheck)

---

### US-007: Runner Hook System

**Description:** As a contributor adding a new runner, I want an optional shell hook override system so that tool-specific quirks can be handled without modifying the core runner library.

**Acceptance Criteria:**
- [ ] `runner_build_cmd()` checks for `runners/hooks/${RUNNER_NAME}-hooks.sh` and sources it if it exists
- [ ] Hook file can define `pre_spawn()` function — called after command is built but before execution. Receives the command string as `$1`. Can modify `RUNNER_EXTRA_FLAGS` variable to append flags
- [ ] Hook file can define `post_output()` function — called after output is captured. Receives output file path as `$1`. Can set `RUNNER_OVERRIDE_SIGNAL` to force a specific signal
- [ ] When no hook file exists, no error is produced and no functions are called
- [ ] When hook file exists but does not define `pre_spawn()` or `post_output()`, no error is produced
- [ ] `runners/hooks/codex-hooks.sh` exists with `pre_spawn()` that logs: `"[RUNNER] NOTE: Codex sandbox blocks network access in full-auto mode. Ensure dependencies are pre-installed."`
- [ ] `runners/hooks/copilot-hooks.sh` exists with `pre_spawn()` that appends `--autopilot --no-ask-user` to `RUNNER_EXTRA_FLAGS`
- [ ] Typecheck/lint passes (shellcheck)

---

### US-008: Claude Runner Manifest

**Description:** As a user, I want the Claude Code runner defined as a JSON manifest so that it serves as the reference implementation and proves the manifest system can replicate existing behavior.

**Acceptance Criteria:**
- [ ] `runners/claude.json` exists with all required schema fields
- [ ] `tier` is `"guaranteed"`
- [ ] `binary` is `"claude"`
- [ ] `invocation.promptDelivery` is `"flag"`, `invocation.promptFlag` is `"-p"`
- [ ] `invocation.headlessFlags` is `["--print"]`
- [ ] `invocation.autoApproveFlags` is `["--dangerously-skip-permissions"]`
- [ ] `signals.preambleInjection` is `false`
- [ ] `signals.heuristicFallback` is `false`
- [ ] `instructionFile.native` is `"CLAUDE.md"`, `instructionFile.autoGenerate` is `false`
- [ ] Manifest validates against `schemas/runner.schema.json`

---

### US-009: Codex Runner Manifest and Hooks

**Description:** As a Codex user (ref: issue #19), I want a tested runner manifest for Codex CLI so that I can use quantum-loop with GPT models.

**Acceptance Criteria:**
- [ ] `runners/codex.json` exists with all required schema fields
- [ ] `tier` is `"tested"`
- [ ] `binary` is `"codex"`
- [ ] `invocation.promptDelivery` is `"positional"`
- [ ] `invocation.headlessFlags` is `["-q"]`
- [ ] `invocation.autoApproveFlags` is `["--approval-mode", "full-auto"]`
- [ ] `signals.preambleInjection` is `true`
- [ ] `signals.heuristicFallback` is `true`
- [ ] `instructionFile.native` is `"AGENTS.md"`, `instructionFile.fallbackFrom` is `"CLAUDE.md"`, `instructionFile.autoGenerate` is `true`
- [ ] `quirks.sandboxBlocksNetwork` is `true` with explanatory `notes` field
- [ ] `installHint` is `"npm install -g @openai/codex"`
- [ ] `runners/hooks/codex-hooks.sh` exists with sandbox warning in `pre_spawn()`
- [ ] Manifest validates against `schemas/runner.schema.json`

---

### US-010: Experimental Runner Manifests

**Description:** As a user of Copilot CLI, Cursor, Gemini, Amp, or Aider, I want experimental runner manifests so that I can try quantum-loop with my preferred tool.

**Acceptance Criteria:**
- [ ] `runners/copilot.json` exists: binary `"copilot"`, tier `"experimental"`, promptDelivery `"flag"`, promptFlag `"-p"`, headlessFlags `[]`, autoApproveFlags `["--allow-all"]`, preambleInjection `true`, heuristicFallback `true`, instructionFile native `"AGENTS.md"`, installHint `"npm install -g @github/copilot"`
- [ ] `runners/cursor.json` exists: binary `"agent"`, tier `"experimental"`, promptDelivery `"flag"`, promptFlag `"-p"`, headlessFlags `[]`, autoApproveFlags `["--force"]`, preambleInjection `true`, heuristicFallback `true`, instructionFile native `"AGENTS.md"`, quirks `"betaHangingBug": true, "staleTimeoutOverride": 10`
- [ ] `runners/gemini.json` exists: binary `"gemini"`, tier `"experimental"`, promptDelivery `"flag"`, promptFlag `"-p"`, headlessFlags `[]`, autoApproveFlags `["--approval-mode=yolo"]`, preambleInjection `true`, heuristicFallback `true`, instructionFile native `"GEMINI.md"` with fallbackFrom `"CLAUDE.md"`, installHint `"npm install -g @google/gemini-cli"`
- [ ] `runners/amp.json` exists: binary `"amp"`, tier `"experimental"`, promptDelivery `"stdin"`, stdinPipe `true`, headlessFlags `[]`, autoApproveFlags `["--dangerously-allow-all"]`, preambleInjection `true`, heuristicFallback `true`, instructionFile native `"AGENTS.md"`
- [ ] `runners/aider.json` exists: binary `"aider"`, tier `"experimental"`, promptDelivery `"flag"`, promptFlag `"-m"`, headlessFlags `["--yes-always"]`, autoApproveFlags `[]`, preambleInjection `true`, heuristicFallback `true`, instructionFile native `"CONVENTIONS.md"`, quirks `"noMcp": true`
- [ ] `runners/hooks/copilot-hooks.sh` exists with `pre_spawn()` appending `--autopilot --no-ask-user` to `RUNNER_EXTRA_FLAGS`
- [ ] All 5 manifests validate against `schemas/runner.schema.json`

---

### US-011: Wire quantum-loop.sh Sequential Mode

**Description:** As a user, I want `quantum-loop.sh` to use the runner adapter for sequential execution so that `--tool codex` works end-to-end.

**Acceptance Criteria:**
- [ ] `quantum-loop.sh` sources `lib/runner.sh` at startup
- [ ] The `--tool` argument validation (currently line 88: hardcoded `claude`/`amp` check) is replaced with `runner_load("$TOOL")` call
- [ ] The startup banner (line 346) displays runner info: tool name, binary, tier, and instruction file status
- [ ] Experimental tier runners show warning: `"WARNING: '<tool>' is an experimental runner..."` with confirmation prompt in interactive mode. Suppressed with `--non-interactive`
- [ ] `runner_ensure_instructions()` is called after `runner_load()` succeeds
- [ ] The hardcoded `if [[ "$TOOL" == "claude" ]]` / `else` block (lines 778-784) is replaced with a single `runner_build_cmd()` call
- [ ] The output parsing after execution (lines 791+) is replaced with `runner_parse_output()` call that handles both exact signals and heuristic fallback
- [ ] When `--tool claude` (or no `--tool`), the actual shell command executed is byte-for-byte identical to the current: `claude --dangerously-skip-permissions --print -p "$(cat "$PROMPT_FILE")" -- "Implement story $STORY_ID..."`
- [ ] When `--tool codex`, the command executed is: `codex -q --approval-mode full-auto "<preamble + prompt>"`
- [ ] The default value of `$TOOL` remains `"claude"`
- [ ] Typecheck/lint passes (shellcheck on quantum-loop.sh)

---

### US-012: Wire lib/spawn.sh Parallel Mode

**Description:** As a user, I want parallel worktree execution to work with any runner so that `--tool codex --parallel` spawns Codex agents in worktrees.

**Acceptance Criteria:**
- [ ] `lib/spawn.sh` sources `lib/runner.sh`
- [ ] `build_autonomous_command(story_id, worktree_path)` uses `runner_build_cmd()` instead of hardcoded `claude --print -p`
- [ ] `spawn_autonomous(story_id, worktree_path)` uses the manifest-driven command instead of hardcoded `claude --dangerously-skip-permissions --print -p`
- [ ] `runner_ensure_instructions()` is called inside the worktree directory before spawning the agent
- [ ] The prompt from `build_agent_prompt()` has the signal preamble injected for non-Claude runners via `runner_inject_preamble()`
- [ ] When `RUNNER_NAME` is `"claude"`, the spawned command is identical to current: `cd "$worktree_path" && claude --dangerously-skip-permissions --print -p "$prompt"`
- [ ] The monitor loop in `quantum-loop.sh` uses `runner_parse_output()` (with heuristic fallback) when processing completed agent output files
- [ ] Typecheck/lint passes (shellcheck)

---

### US-013: Wire quantum-loop.ps1

**Description:** As a Windows user, I want `quantum-loop.ps1` to support multi-runner via the same `runners/*.json` manifests so that I have parity with the bash version.

**Acceptance Criteria:**
- [ ] `quantum-loop.ps1` accepts a `-Tool` parameter (string, default `"claude"`)
- [ ] At startup, reads `runners/<Tool>.json` using `Get-Content | ConvertFrom-Json`
- [ ] Validates that the binary exists via `Get-Command $binary -ErrorAction SilentlyContinue`
- [ ] If binary not found, errors with `installHint` from manifest
- [ ] Experimental tier shows warning with confirmation prompt (unless `-NonInteractive` switch present — add this parameter if it doesn't exist)
- [ ] Calls `runner_ensure_instructions` equivalent: if instruction native file missing and fallback exists, copies with `.ql-generated` marker
- [ ] Builds the command string based on `invocation.promptDelivery`: flag, positional, or stdin pipe — matching the same logic as `runner_build_cmd()` in bash
- [ ] For non-Claude runners, prepends `runners/preamble.md` content to the prompt
- [ ] The output parsing uses relaxed regex for signal detection + heuristic fallback (commit check via `git log -1`, test pattern scanning)
- [ ] When `-Tool claude`, the executed command is identical to current: `claude --print -p $promptContent -- "Implement story $storyId..."`
- [ ] Startup banner displays: Tool name, binary, tier
- [ ] Typecheck/lint passes (PSScriptAnalyzer if available)

---

### US-014: Wire templates/quantum-loop.sh

**Description:** As a user who curls the standalone template, I want `templates/quantum-loop.sh` to support `--tool` with manifest reading so that I get multi-runner support without installing the full plugin.

**Acceptance Criteria:**
- [ ] `templates/quantum-loop.sh` accepts `--tool TOOL` argument (default: `"claude"`)
- [ ] Reads `runners/<tool>.json` from a `runners/` directory relative to the script location
- [ ] If `runners/` directory doesn't exist, falls back to hardcoded Claude behavior with a warning: `"[RUNNER] runners/ directory not found. Using built-in claude runner."`
- [ ] When `runners/` exists, uses the same manifest-driven command building as `quantum-loop.sh`
- [ ] The signal preamble (`runners/preamble.md`) is read and injected for non-Claude runners
- [ ] Heuristic fallback is applied for non-Claude runners
- [ ] The template remains self-contained for Claude (no external dependencies beyond `jq` and `claude`/`node` for JSON)
- [ ] Typecheck/lint passes (shellcheck)

---

### US-015: Unit Tests for Runner Library

**Description:** As a developer, I want comprehensive unit tests for `lib/runner.sh` functions so that I can refactor with confidence.

**Acceptance Criteria:**
- [ ] `tests/test_runner.sh` exists using the project's existing test framework (shell assert functions)
- [ ] `test_runner_load_valid` — loads `runners/claude.json`, verifies `RUNNER_NAME=claude`, `RUNNER_BINARY=claude`, `RUNNER_TIER=guaranteed`
- [ ] `test_runner_load_missing` — `runner_load("nonexistent")` returns non-zero exit code and stderr contains "Unknown runner"
- [ ] `test_runner_load_invalid_schema` — manifest with missing `invocation.promptDelivery` returns non-zero with field name in error
- [ ] `test_runner_build_cmd_claude` — produces `claude --dangerously-skip-permissions --print -p "<prompt>"` (no preamble)
- [ ] `test_runner_build_cmd_codex` — produces `codex -q --approval-mode full-auto "<preamble + prompt>"` (positional)
- [ ] `test_runner_build_cmd_stdin` — produces pipe command for `stdinPipe: true` runners
- [ ] `test_runner_build_cmd_preamble_injected` — non-Claude prompt contains "YOU MUST output exactly one of these signals"
- [ ] `test_runner_build_cmd_no_preamble_claude` — Claude prompt does NOT contain preamble text
- [ ] `test_runner_ensure_instructions_creates` — creates AGENTS.md from CLAUDE.md with `.ql-generated` marker when AGENTS.md missing
- [ ] `test_runner_ensure_instructions_no_overwrite` — existing AGENTS.md is not modified
- [ ] `test_runner_ensure_instructions_idempotent` — running twice produces identical file
- [ ] All tests pass: `bash tests/test_runner.sh` exits 0

---

### US-016: Signal Heuristic Tests

**Description:** As a developer, I want tests for the signal heuristic fallback so that the inference logic is verified for all decision matrix paths.

**Acceptance Criteria:**
- [ ] `tests/test_signal_heuristics.sh` exists
- [ ] `test_parse_exact_signal_passed` — output with `<quantum>STORY_PASSED</quantum>` returns PASSED, confidence exact
- [ ] `test_parse_exact_signal_failed` — output with `<quantum>STORY_FAILED</quantum>` returns FAILED, confidence exact
- [ ] `test_parse_relaxed_whitespace` — output with `<quantum> STORY_PASSED </quantum>` returns PASSED
- [ ] `test_parse_crash_exit_code` — exit_code=1 returns FAILED regardless of output
- [ ] `test_parse_both_signals_last_wins` — output with PASSED then FAILED returns FAILED
- [ ] `test_heuristic_commit_and_tests` — no signal + commit evidence + test pass patterns → PASSED (high)
- [ ] `test_heuristic_commit_no_tests` — no signal + commit evidence + no test patterns → PASSED (medium)
- [ ] `test_heuristic_no_commit` — no signal + no commit evidence → FAILED (high)
- [ ] `test_heuristic_commit_with_errors` — no signal + commit + error patterns → FAILED (high)
- [ ] `test_heuristic_skipped_for_claude` — when `RUNNER_HEURISTIC_FALLBACK=false`, only exact signal matching, no heuristic
- [ ] All tests pass: `bash tests/test_signal_heuristics.sh` exits 0

---

### US-017: Integration Tests

**Description:** As a developer, I want end-to-end integration tests verifying the `--tool` flag behavior, startup banners, and claude regression so that we can gate PRs on these.

**Acceptance Criteria:**
- [ ] `tests/test_runner_integration.sh` exists
- [ ] `test_tool_flag_accepts_all_manifests` — `--tool claude`, `--tool codex`, `--tool copilot`, `--tool cursor`, `--tool gemini`, `--tool amp`, `--tool aider` all pass the validation stage (mock the binary check with PATH override)
- [ ] `test_tool_flag_rejects_unknown` — `--tool nope` exits non-zero with "Unknown runner" message listing available runners
- [ ] `test_default_tool_is_claude` — running without `--tool` sets `TOOL=claude`
- [ ] `test_startup_banner_shows_runner` — startup output contains "Tool:" line with runner name and tier
- [ ] `test_experimental_warning_interactive` — experimental runner in interactive mode outputs "WARNING" and "experimental"
- [ ] `test_experimental_no_warning_noninteractive` — experimental runner with `--non-interactive` does not output "WARNING"
- [ ] `test_claude_command_regression` — the exact command string built for `--tool claude` matches `claude --dangerously-skip-permissions --print -p` pattern (this is a CI gate)
- [ ] All tests pass: `bash tests/test_runner_integration.sh` exits 0

---

### US-018: Manifest Validation Tests

**Description:** As a developer, I want automated validation of all shipped runner manifests so that bad JSON or missing fields are caught before merge.

**Acceptance Criteria:**
- [ ] `tests/test_runner_manifests.sh` exists
- [ ] `test_all_manifests_valid_json` — every `runners/*.json` file parses with `jq . < file` exit 0
- [ ] `test_all_manifests_have_required_fields` — every manifest has `name`, `binary`, `tier`, `invocation.promptDelivery`, `invocation.headlessFlags`, `invocation.autoApproveFlags`, `instructionFile.native`, `signals.preambleInjection`, `signals.heuristicFallback`
- [ ] `test_claude_manifest_tier_guaranteed` — `runners/claude.json` has `tier: "guaranteed"`
- [ ] `test_codex_manifest_tier_tested` — `runners/codex.json` has `tier: "tested"`
- [ ] `test_experimental_manifests_tier` — copilot, cursor, gemini, amp, aider all have `tier: "experimental"`
- [ ] `test_hook_files_exist_for_manifests_with_hooks` — if manifest references quirks that need hooks, corresponding `runners/hooks/<name>-hooks.sh` exists
- [ ] All tests pass: `bash tests/test_runner_manifests.sh` exits 0

---

### US-019: README and Marketplace Update

**Description:** As a potential user, I want the README and marketplace metadata to reflect multi-runner support so that the feature is discoverable.

**Acceptance Criteria:**
- [ ] README.md "Quick Start" section includes `--tool` flag examples: `./quantum-loop.sh --tool codex`, `./quantum-loop.sh --tool copilot`
- [ ] README.md has a new "## Supported Runners" section listing all 7 runners with tier badges, binary names, and install commands
- [ ] README.md "Run" section shows PowerShell example with `-Tool`: `.\quantum-loop.ps1 -Tool codex`
- [ ] README.md includes a "### Adding a Custom Runner" subsection explaining the JSON manifest approach
- [ ] `.claude-plugin/marketplace.json` version is bumped to `"0.4.0"` (minor version bump for new feature)
- [ ] `.claude-plugin/marketplace.json` description includes "multi-runner" or "universal CLI orchestrator"
- [ ] `.claude-plugin/marketplace.json` keywords array includes `"multi-runner"`, `"codex"`, `"copilot"`, `"gemini"`
- [ ] No broken markdown links in README

---

## 4. Functional Requirements

```
FR-01: The system shall read runner configuration from JSON manifest files in the runners/ directory.
FR-02: The system shall validate runner manifests at startup and exit with descriptive error if validation fails.
FR-03: The system shall default to the "claude" runner when --tool is not specified.
FR-04: The system shall accept --tool <name> where <name> matches any .json file in runners/ (minus extension).
FR-05: The system shall check that the runner binary is installed via command -v and display installHint if missing.
FR-06: The system shall display a warning and confirmation prompt for experimental-tier runners in interactive mode.
FR-07: The system shall suppress experimental warnings when --non-interactive flag is set.
FR-08: The system shall auto-generate instruction files (AGENTS.md, GEMINI.md) from CLAUDE.md for non-Claude runners when the native instruction file does not exist.
FR-09: The system shall never overwrite a user-maintained instruction file (one without the .ql-generated marker).
FR-10: The system shall inject the signal protocol preamble into prompts for runners with signals.preambleInjection: true.
FR-11: The system shall NOT inject preamble for runners with signals.preambleInjection: false (Claude).
FR-12: The system shall detect quantum signals using relaxed regex allowing whitespace: <quantum>\s*SIGNAL\s*</quantum>.
FR-13: The system shall fall back to heuristic signal detection (commit evidence, test output, error patterns) for runners with signals.heuristicFallback: true when no exact signal is found.
FR-14: The system shall treat heuristic results with "low" confidence as STORY_FAILED.
FR-15: The system shall treat agent crash (non-zero exit code) as STORY_FAILED regardless of output.
FR-16: The system shall support three prompt delivery methods: flag, positional, stdin — as declared in manifests.
FR-17: The system shall source optional hook files (runners/hooks/<name>-hooks.sh) and call pre_spawn() and post_output() if defined.
FR-18: The system shall produce identical shell commands for --tool claude as the pre-refactor hardcoded commands.
FR-19: The system shall support multi-runner in sequential mode (quantum-loop.sh), parallel mode (lib/spawn.sh), PowerShell (quantum-loop.ps1), and templates (templates/quantum-loop.sh).
FR-20: The system shall display runner name, binary, tier, and instruction file status in the startup banner.
```

---

## 5. Non-Goals (Out of Scope)

1. **Actual execution testing with non-Claude models** — We test manifest loading, command building, and signal parsing. We do NOT test whether Codex/Copilot/Gemini reliably follows the preamble instructions. That is non-deterministic and model-dependent.
2. **Model selection flags** — This PRD does not add `--model` passthrough to runner commands. Users configure models via each tool's native config (e.g., `codex --model o3`).
3. **Runner auto-detection** — The system does not detect which CLIs are installed and suggest one. Users must explicitly pass `--tool`.
4. **MCP server configuration** — This PRD does not configure MCP servers for non-Claude runners. Each tool's MCP is managed via its native config.
5. **Version enforcement** — The `version` field in manifests is informational only. We do not check binary versions at startup (too fragile across platforms).
6. **Custom preamble templates per runner** — All non-Claude runners share the same `runners/preamble.md`. Per-runner templates are a future enhancement.
7. **GUI/TUI runner selector** — No interactive runner picker. `--tool` flag only.
8. **Parallel mode for PowerShell** — `quantum-loop.ps1` gets sequential multi-runner support only. Parallel PS1 is a separate future feature.

---

## 6. Design Considerations

- **Hybrid manifest + hooks architecture**: JSON manifests handle 90% of runner configuration. Shell hook overrides handle tool-specific quirks (Codex sandbox, Copilot autopilot flags) without polluting the core library.
- **Tier system communicates support quality**: `guaranteed` (Claude, fully tested), `tested` (Codex, proven but less battle-tested), `experimental` (community-maintained configs). This sets correct user expectations.
- **Instruction file auto-generation with `.ql-generated` marker**: Prevents overwriting user-maintained files while ensuring non-Claude runners can read the quantum-loop protocol. Idempotent by design.
- **Conservative heuristic policy (always FAILED on low confidence)**: Prevents false positives from wasting iteration budget. A retry on a false negative is cheaper than building on a false positive.

---

## 7. Technical Considerations

- **jq dependency**: Already required by quantum-loop. Used for manifest validation and field extraction.
- **shellcheck compliance**: All new shell scripts must pass shellcheck. This is enforced by existing CI.
- **Backward compatibility**: The refactored `quantum-loop.sh` must produce identical commands for `--tool claude`. This is enforced by `test_claude_command_regression`.
- **Existing quantum.json is from hardening-v2**: The multi-runner feature will create its own `quantum.json` on a new branch. No conflict.
- **PowerShell reads JSON natively**: `ConvertFrom-Json` replaces `jq` for PS1 manifest reading. No additional dependencies.
- **Template fallback**: `templates/quantum-loop.sh` gracefully degrades to hardcoded Claude when `runners/` directory is missing, preserving the curl-and-run experience.

---

## 8. Success Metrics

- `./quantum-loop.sh --tool claude` produces byte-for-byte identical commands to the pre-refactor version (regression gate)
- `./quantum-loop.sh --tool codex` successfully builds and executes the correct Codex command with preamble injection
- All 7 runner manifests pass schema validation
- All test suites pass (`test_runner.sh`, `test_signal_heuristics.sh`, `test_runner_integration.sh`, `test_runner_manifests.sh`)
- `quantum-loop.ps1 -Tool codex` builds the correct command
- `templates/quantum-loop.sh --tool codex` builds the correct command (or falls back gracefully)
- README multi-runner section is present and accurate

---

## 9. Open Questions

1. Should we add a `--list-runners` flag that lists all available runners with their tiers? (Low effort, nice UX)
2. Should the preamble template support variable interpolation (e.g., `{{STORY_ID}}`) or just be static text prepended to the prompt?
3. When Cursor exits beta, should we auto-promote it from `experimental` to `tested`? What triggers tier changes?
4. Should we add runner manifest caching (reading JSON on every iteration vs. once at startup)? Current design reads once at startup — is that sufficient?

---

## Lifecycle Checklist

- [x] **First-run behavior:** On first `--tool codex` invocation, the system auto-generates `AGENTS.md` from `CLAUDE.md` with a `.ql-generated` marker and logs the action. No manual setup required.
- [x] **Returning-user behavior:** `AGENTS.md` persists across invocations. If user customizes it (removes `.ql-generated` marker), it is never overwritten. New runners auto-generate their instruction files on first use.
- [x] **Update behavior:** Adding new runners requires only a new JSON file in `runners/`. Existing manifests are backward-compatible — new optional fields have defaults. Schema versioning is an open question.
- [x] **Error recovery:** Binary not found → clear error with install hint. Manifest invalid → specific field error. Signal not detected → heuristic fallback or FAILED. Agent crash → FAILED with exit code logged.
- [x] **No-data/empty state:** No `runners/` directory → template falls back to hardcoded Claude. No manifests match `--tool` → error listing available runners. No instruction file exists → error requiring CLAUDE.md.
- [x] **Uninstall/disable:** Removing `runners/` directory causes graceful fallback to Claude. Removing a manifest causes `--tool <name>` to error. No orphaned state — manifests are read-only config, not runtime data.
