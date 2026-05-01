# ADR-001: Outer-loop architecture (cron-triggered `/loop` is canonical)

**Status:** ACCEPTED
**Date:** 2026-05-01
**Cycle:** v0.9.5 / US-003
**Source:** `idea-stage/v0.10.0-design-spike-2026-05-01.md` § Spike 2

## Context

The quantum-loop project has shipped 4 patch/minor releases (v0.9.0 through v0.9.4) closing per-wave coordinator dispatch + validation + hardening + housekeeping. The "outer iteration loop" — `for ITERATION in $(seq 1 "$MAX_ITERATIONS"); do ... done` at `quantum-loop.sh:~1447` — runs N waves per invocation, bounded by `--max-iterations` (default 50).

`idea-stage/IDEA_REPORT_v30.md` (post-v0.9.0 retrospective) recommended a "daemon-style runner" replacement of the for-loop iteration mechanism for v0.10.0. The architect's post-v0.9.3 audit (`idea-stage/v0.9.x-arc-audit-2026-04-30.md`) flagged the term as unscoped and inflicted a design spike (`idea-stage/v0.10.0-design-spike-2026-05-01.md` § Spike 2) to clarify what "daemon-style" should mean concretely.

**The spike found that the autonomous Claude Code `/loop` cron pattern (which has driven v0.9.3 and v0.9.4 end-to-end with zero manual takeover) already solves the original motivating problem ("operator must manually re-run quantum-loop.sh after MAX_ITERATIONS").** The "daemon-style runner" framing was a stale aspiration that outlived its motivating problem.

## Decision

**The Claude Code `/loop` cron pattern is the canonical outer-loop architecture for the quantum-loop project. No persistent-daemon implementation will be built.**

Operator workflow:
- Use `/loop <interval> <prompt>` to schedule autonomous re-invocation of `quantum-loop.sh` (or any orchestrating prompt) at a chosen cadence.
- Each cron firing is a fresh process — no PID lockfile, no signal handling, no MSYS dual-PID complexity.
- State persists between firings via `quantum.json` (gitignored; per-iteration mutations).
- Stop semantics: cancel the cron via `CronDelete` or `/loop` cancellation.

## Consequences

### Positive
- **Zero new infrastructure.** No PID management, no signal handling, no cross-platform signal bugs.
- **Cross-platform robust.** Identical behavior on Git Bash (Windows), Linux, and macOS.
- **Empirically proven.** Drove v0.9.3 + v0.9.4 end-to-end (`idea-stage/PIPELINE_REPORT_v30.md` + `v31.md`).
- **Trivial stop semantics.** Cancel the cron — no cleanup ceremony.
- **Scope contains.** v0.10.0 effort estimate dropped from "significant architectural work" to "patch-tier housekeeping" once daemon was deemed over-engineering.

### Negative / Trade-offs
- **External-scheduler dependency.** Requires Claude Code's `/loop` (or equivalent CronCreate). If Claude Code deprecates `/loop`, alternative scheduler needed.
- **No internalized scheduler.** Operator can't `nohup quantum-loop.sh &` and walk away — they must use the scheduler.
- **No live status surface.** No daemon means no "what's the daemon doing right now" introspection beyond `git log` + `quantum.json` reads. Acceptable for development tooling.

### Neutral
- The bounded `for ITERATION in $(seq 1 "$MAX_ITERATIONS")` loop stays. Each invocation completes N iterations or exits via `<quantum>COMPLETE</quantum>` / `<quantum>BLOCKED</quantum>` / `<quantum>MAX_ITERATIONS</quantum>`.

## Alternatives Considered

### A. Persistent daemon process (rejected)
A long-running bash process (`while true` or `systemd` unit) replacing the `for` loop. Requires PID lockfile, SIGTERM/SIGINT/SIGHUP traps, mid-iteration kill safety, transactional `quantum.json` updates. Cross-platform fragile (MSYS signal delivery is a known pain point per `lib/reaper.sh:14-19`).

**Rejection rationale:** ~3 stories of new code (PID management, signal handling, cross-platform regression tests) for zero demonstrated operational benefit over the cron pattern. Adds maintenance burden in a known-fragile area.

### B. Inotify / filesystem watcher (rejected)
Watch `quantum.json` for changes; trigger iteration on write.

**Rejection rationale:** `inotifywait` is Linux-only; Windows has no bash equivalent. Self-triggering loop (the parent loop also writes `quantum.json`) requires debounce. Disqualified by cross-platform requirement.

### D. Hybrid (`while true` wrapper around bounded for-loop) (deferred)
Internalize the cron pattern: thin outer `while true` calls the existing bounded loop, sleeps, re-enters. Eliminates scheduler dependency.

**Deferral rationale:** Marginal value over Option B. Still needs PID lockfile for stop semantics. Reconsider only if cron pattern fails operationally.

## Triggers for Revisit

This ADR should be re-opened if:
1. **Claude Code `/loop` is deprecated** — alternative scheduler decision needed.
2. **Demonstrated operational failure of the cron pattern** — e.g., race condition between cron firings, missed firings causing pipeline stall, scheduler-induced corruption of `quantum.json`.
3. **Operator requirement for live introspection** — "what's the daemon doing right now" surface that current `git log` + `quantum.json` reads cannot satisfy.
4. **Multi-machine / distributed dispatch** — if quantum-loop ever runs across machines, daemon-style coordination might become necessary.

Until any of these triggers fire, the cron pattern is canonical.

## References

- `idea-stage/v0.10.0-design-spike-2026-05-01.md` § Spike 2 — full architecture options comparison (A/B/C/D).
- `idea-stage/v0.9.x-arc-audit-2026-04-30.md` § "Latent risks for v0.10.0" item 2 — original architect flag.
- `idea-stage/IDEA_REPORT_v30.md:52` — origin of "daemon-style runner" term.
- `idea-stage/PIPELINE_REPORT_v30.md` § "Manual-takeover streak" — empirical proof cron pattern works (v0.9.3).
- `idea-stage/PIPELINE_REPORT_v31.md` § "Manual-takeover streak" — empirical proof cron pattern works (v0.9.4).
- `quantum-loop.sh:~1447-1838` — the bounded for-loop that stays.
- `lib/reaper.sh:14-19` — MSYS dual-PID complexity that a persistent daemon would have to solve.
