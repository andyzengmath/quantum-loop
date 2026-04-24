# PR-ready: `ql/ambiguity-gate-2026-04` → `ql/orchestrator-wire-2026-04` (stacked on #28)

**Date**: 2026-04-23
**Branch**: `ql/ambiguity-gate-2026-04` (2 commits ahead of PR #28)
**Base**: Depends on PR #28 landing first (which depends on PR #27).
**Stack**: #27 → #28 → **this PR** → master

---

## One-line description

Two P2 polish items motivated by session observations: ambiguity-gated brainstorm (OMC deep-interview) and orphan-subprocess reaping (user-reported issue).

---

## Commits (2)

| # | Commit | Phase | Description |
|---|--------|-------|-------------|
| 2 | `fdc8ed9` | 20 | Orphan-subprocess reaping (P2.11) |
| 1 | `3c1eb0e` | 19 | Ambiguity-gated brainstorm (P2.8) |

Total: ~2400 lines added across `lib/ambiguity.sh`, `lib/reaper.sh`, `lib/spawn.sh` fix, `quantum-loop.sh` trap wiring, 2 skill prompts, 2 new test suites.

---

## Phase 19 — Ambiguity-Gated Brainstorm (P2.8)

Blocks `/ql-brainstorm` from producing a design doc until ambiguity score falls below threshold (default 20). Port of the OMC deep-interview pattern.

- **Scoring** (self-assessed by agent each round): goal 40%, constraints 30%, criteria 30%, each 0-10 → composite 0-100.
- **Challenge mode escalation** by round × score: normal → contrarian → simplifier → ontologist.
- **Ontology stability tracking** — if vocabulary thrashes across rounds (stability < 0.5), force ontologist mode regardless of round.
- **Handoff integration** — records final score into `.handoffs/brainstorm.md`'s `ambiguity` field so `/ql-spec` can verify the gate passed.

`lib/ambiguity.sh` (~120 lines) + `tests/test_ambiguity.sh` (49 assertions).

## Phase 20 — Orphan-Subprocess Reaping (P2.11)

Fixes a user-reported issue: dead/orphan `claude` subprocesses accumulating after interrupted runs. Research combined Anthropic's current docs + POSIX/Git Bash specifics.

### Root causes identified

1. **Subshell-PID capture** in `lib/spawn.sh`:
   ```bash
   (cd "$wt" && claude --print -p "$prompt") &
   pid=$!   # ← SUBSHELL PID, not claude.exe
   ```
2. **MSYS/Windows dual-PID space** — `kill $MSYS_PID` on Git Bash often no-ops against native `claude.exe`. Need `/proc/<pid>/winpid` translation + `taskkill //F //T`.
3. **No durable tracking** — terminal close bypasses the runtime SIGINT trap; Agent-tool grandchildren aren't captured in `AGENT_PIDS[]` at all.

### Fixes

1. **`exec` prefix in `lib/spawn.sh`** — `$!` now captures real claude PID (Bash Reference Manual §3.7.4).
2. **New `lib/reaper.sh` (~200 lines)** — platform-aware kill machinery:
   - `detect_platform` → `posix-setsid` / `posix-plain` / `msys` / `cygwin`
   - `_msys_to_winpid` via `/proc/<pid>/winpid`
   - `reap_agent` uses `taskkill //F //T` on Git Bash, `kill -- -PGID` on POSIX
   - `reap_orphans` scans pidfiles, drops dead entries, kills live-but-stale (default > 1h)
3. **Durable pidfile** `.ql-agent-pids/<story>.pid` in TSV format: `<msys> <winpid> <start_epoch> <cmd>`. Start-epoch defeats PID reuse.
4. **`quantum-loop.sh` trap** delegates to `reap_agent` per story ID (was: `kill` subshell PIDs).
5. **Startup reap** — `reap_orphans` runs before new agents spawn, cleaning prior-run leftovers.

### Anthropic docs (researched during this PR)

- **No** `--pid-file` / `--detach` flag on `claude -p`.
- Hooks (`SessionEnd`, `Stop`, `WorktreeRemove`) are observability-only — no PID access, no SIGINT hook.
- Known bugs: `#45717` (SIGTERM propagation), `#37127` (SIGTERM-before-SIGKILL missing), `#625` (Agent SDK session-file race).
- **Explicit Anthropic recommendation: manage subprocess lifecycle outside the SDK via OS primitives.** This PR follows that guidance.

`lib/reaper.sh` + `tests/test_reaper.sh` (25 assertions).

---

## Test regression

**17 suites green, ~520 individual assertions across all phases.**

| Suite | Count | Phase |
|---|---:|---|
| test_reaper | 25 | 20 (NEW) |
| test_ambiguity | 49 | 19 (NEW) |
| test_phase_skip | 28 | 18 |
| test_orchestrator_wiring | 30 | 17 |
| test_watchdog | 32 | 16 |
| test_handoff | 38 | 15 |
| test_commit_trailers | 34 | 14 |
| test_dispatch_set | 29 | 12 |
| test_deep_review | 31 | 8 |
| test_wave_boundary | 19 | 11 |
| test_deslop | 22 | 9 |
| test_intent_check | 19 | 7 |
| test_claim_check_integration | 17 | 5 |
| test_dogfood_e2e | 17 | 10 |
| test_spawn | 37 | baseline |
| test_resilience | 43 | baseline |
| test_runner_integration | 45 | baseline |

Evidence: `.omc/phase-19-evidence/` and `.omc/phase-20-evidence/`.

---

## Known limitations (honest)

- **Reaper taskkill path isn't unit-tested** against a live Windows binary — would require spawning real `claude.exe`. The POSIX path is exercised via `sleep` fixtures; Git Bash path is exercised only at runtime.
- **Watchdog migration deferred** — Phase 16's `lib/watchdog.sh` still calls a legacy `kill_agent_process`. It should migrate to `reap_agent` in a follow-up so both sources share the same platform-aware kill.
- **Agent-tool grandchildren** (subagents spawning more claude via Bash tool) aren't captured in the pidfile since quantum-loop.sh doesn't control those spawns. `reap_orphans` catches them after `$REAPER_STALE_SECS` (default 1h). True fix requires Anthropic to expose a PID hook — currently unavailable.

---

## Pending user action

- [ ] Merge review — depends on PR #27 and PR #28 landing first.

No further shared-state actions required from me.
