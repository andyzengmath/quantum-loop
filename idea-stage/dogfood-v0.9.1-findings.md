# Dogfood findings — v0.9.1 (real-LLM N42 validation)

**Date:** 2026-04-30
**Cycle:** v0.9.1
**Mission:** Empirically validate that v0.9.0's N42 wires (per-wave coordinator dispatch under `--coordinator`) actually fire end-to-end with a real LLM — and whether they break the 18-cycle manual-takeover streak.

## TL;DR

**18-cycle manual-takeover streak BROKEN.** v0.9.0 N42 worked end-to-end on its first real-LLM dogfood. A 2-story synthetic bundle dispatched cleanly through `quantum-loop.sh --coordinator`, the coordinator subagent emitted `WAVE_PASSED`, and the parent loop's per-story aggregation correctly marked both stories `passed` → `<quantum>COMPLETE</quantum>` exit 0.

**One real defect surfaced** during execution: the coordinator's internal implementer subagents shared the same worktree, and US-B's implementer ran `git reset --hard d66aaf8` (wiping US-A's commit) before its own commit. The coordinator self-healed by detecting the reset and committing a `fix: US-A recovery` commit on top of US-B. Final state: both ACs satisfied, history is non-linear but acceptable.

## Per-claim verdict (PRD US-002 quorum: 4 minimum claims, no UNKNOWN)

| Claim | Status | Evidence |
|---|---|---|
| `next_wave` invocation correct | ✅ WORKED | `dogfood-stdout.prior.log` line: `Spawning coordinator for wave-1 with 2 story/stories: US-A US-B` — both stories returned together as wave-1, no string-sentinel parse failure |
| `spawn_coordinator` output reachable + parseable | ✅ WORKED | `dogfood-stdout.prior.log`: `[RUNNER] Signal: WAVE_PASSED (exact, confidence=exact)` — coordinator stdout was captured + fed through `runner_parse_output` + recognized via the 6-signal regex |
| Per-story aggregation routing correct | ✅ WORKED | `quantum.post.json`: both `US-A.status="passed"` and `US-B.status="passed"`; `retries.attempts=0` for both. v0.9.0 US-003's WAVE_PASSED bulk-update jq pass ran correctly |
| Coordinator stayed within bounded context per wave | ✅ WORKED | Iteration 2 fired immediately after iteration 1 with no STALE detection; no respawn invoked; coordinator exited cleanly. Single-wave dispatch fits in one subagent context as designed |

## Section 1: `next_wave` invocation evidence

```
=== Iteration 1 / 5 ===
Story:   US-A - Add marker comment to dogfood/target-A.sh
Attempt: 1
Spawning claude for story US-A...
Spawning coordinator for wave-1 with 2 story/stories: US-A US-B
```

Source: `.ql-wt/dogfood-v091/dogfood-stdout.prior.log` (1329 bytes; full stdout from the dogfood run).

`next_wave` returned both `["US-A","US-B"]` as wave-1 (independent stories with disjoint `filePaths`; no `fileConflicts`). The 3-way exit code dispatch (rc=0 → wave) routed correctly.

**Minor noise:** the printf at quantum-loop.sh that printed `"Spawning claude for story US-A..."` fired BEFORE the coordinator-mode branch printed `"Spawning coordinator for wave-1..."`. This is a leftover printf from the legacy single-spawn code path that wasn't gated under `COORDINATOR_MODE=false`. **Cosmetic finding** — captured in Section 5.

## Section 2: `spawn_coordinator` output reachability

```
[RUNNER] Signal: WAVE_PASSED (exact, confidence=exact)
Wave (wave-1) PASSED — 2 story/stories: US-A, US-B
```

The coordinator subagent's stdout flowed back through:
1. `eval "$COORD_CMD" 2>&1` → `OUTPUT` capture (quantum-loop.sh:~1525)
2. `runner_parse_output "$OUTPUT" "$RUNNER_EXIT"` (line ~1559)
3. The 6-signal regex (`lib/runner.sh:283`) matched `<quantum>WAVE_PASSED</quantum>` → `SIGNAL_RESULT="WAVE_PASSED"`, `SIGNAL_CONFIDENCE="exact"`
4. The `WAVE_PASSED)` case branch ran the multi-story aggregation jq pass

**No silent drops.** The 4-layer N33 anti-pattern closure held: the parser saw the signal, the case statement had the branch, and the bulk-update jq did the right thing.

## Section 3: Per-story aggregation routing

`quantum.post.json` (post-run snapshot):

```json
{
  "stories": [
    {"id": "US-A", "status": "passed", "retries": {"attempts": 0, ...}},
    {"id": "US-B", "status": "passed", "retries": {"attempts": 0, ...}}
  ],
  "progress": [
    {
      "iteration": 1,
      "storyId": "wave-1",
      "action": "wave_completed_with_incident",
      "details": "US-A and US-B both satisfy ACs after recovery; US-B implementer ran git reset --hard d66aaf8 before its commit, wiping US-A 2d2f670; coordinator restored US-A marker via fix commit d86d21b on top of US-B 03f17e1.",
      ...
    }
  ]
}
```

Both stories' `.status="passed"` came from the v0.9.0 US-003 WAVE_PASSED bulk-update branch. The coordinator wrote `progress[]` (coordinator-owned per the field-ownership contract); parent loop wrote `stories[].status` (parent-owned). **Field-ownership contract held in production.**

## Section 4: Coordinator scope boundedness

- Iteration 1 dispatched the coordinator once.
- Iteration 2 fired immediately (no STALE wrap fired).
- Iteration 2's `next_wave` returned `rc=1` (COMPLETE) → exit 0.
- No respawn, no `*)` unknown-signal fallthrough, no orphaned `in_progress` stories.
- Single coordinator invocation handled an entire 2-story wave + emitted clean signal.

The bounded-context architecture (one wave = one coordinator spawn) worked as designed. Coordinator did NOT need multiple spawns per wave; it ran the full wave + signaled in one context.

## Section 5: Unexpected behaviors (the actual finding)

### 5a. Internal implementer destructive git operation (HIGH for v0.9.x roadmap)

**What happened:**
- Coordinator dispatched implementer for US-B (presumably as an implementer subagent via the Task tool internally).
- US-B implementer ran `git reset --hard d66aaf8` (the v0.9.0 ship commit on master) BEFORE running its own commit.
- This wiped US-A's prior commit (`2d2f670`, per the progress entry) — US-A's `marker-A` line was lost from `target-A.sh`.
- Coordinator detected the reset (likely via `git log` or HEAD comparison), restored US-A's marker, and committed `d86d21b fix: US-A recovery - restore marker after US-B implementer reset HEAD` on top of US-B's `03f17e1`.

**Why it happened:** real-LLM implementer subagents make their own decisions about git state. Even with explicit instructions in CLAUDE.md not to mutate parent state, an implementer can rationalize a `git reset --hard` ("clean slate before my work").

**Final state:** both ACs satisfied. History non-linear but recoverable. No data loss.

**Severity:** **HIGH** (revised from MEDIUM-HIGH after US-004 architect review). Reasoning per architect: (1) `git reset --hard` is unconditionally destructive — real data loss, not a close call; (2) coordinator self-healing was emergent, not engineered (no `HEAD_BEFORE`/`HEAD_AFTER` guard in `agents/coordinator.md`); (3) self-healing only worked because the synthetic plan was trivially simple — real-feature dispatch with multi-file diffs would need to reconstruct complex state from memory, which is unreliable. Bounded to one wave per coordinator's one-spawn architecture; quantum.json state never corrupted (field-ownership held). Per the coordinator's own learnings entry:
> v0.9.1 retro should consider: (1) per-story isolated worktrees (current --parallel pattern) instead of shared-worktree sequential dispatch, or (2) coordinator-side guard that snapshots HEAD before each implementer and refuses to advance if HEAD moved backward.

### 5b. Cosmetic printf gate (LOW)

`quantum-loop.sh` line ~1493 emits `Spawning claude for story $STORY_ID...` BEFORE the coordinator-mode branch. Under `COORDINATOR_MODE=true`, this should be suppressed (replaced by the coordinator's own print). Visible in stdout but doesn't affect correctness.

## Section 6: Streak status

**Pre-v0.9.0:** 18 consecutive manual-takeover cycles (v0.6.7..v0.9.0).

**v0.9.0 ship:** infrastructure shipped; no real-LLM dispatch yet.

**v0.9.1 dogfood (this finding):** **streak BROKEN.** First cycle in 19 where the autonomous loop drove a complete 2-story plan to `<quantum>COMPLETE</quantum>` without manual takeover. Caveats:

- Synthetic 2-story plan; not a real feature.
- Internal implementer drift surfaced (5a) but the coordinator self-healed.
- One coordinator iteration only; multi-iteration scenarios untested.
- Single-machine, Git Bash, real `claude` CLI; not cross-platform validated.

**Honest framing:** the streak break is real but conditional. v0.9.0 N42 works on the happy path with synthetic stories. Real-feature dispatch (where stories are larger, mistakes more consequential, and edge cases more numerous) remains unproven. The MEDIUM-HIGH 5a finding suggests v0.9.x will need at least one more refinement (per-story worktree isolation OR coordinator HEAD-snapshot guard) before the architecture is production-confidence.

## v0.9.1 disposition recommendation

| Finding | Severity | Disposition |
|---|---|---|
| 5a — implementer destructive git operation | HIGH (post-architect-review) | Add a v0.9.2 candidate slate item: coordinator HEAD-snapshot guard OR per-story worktree isolation. Do NOT scope-grow v0.9.1; ship the diagnostic + CHANGELOG known-issue advisory. |
| 5b — cosmetic printf | LOW | Defer to v0.9.x housekeeping. Trivial edit; not blocking. |
| Coordinator self-healing (`d86d21b`) | POSITIVE | This is good evidence that the coordinator CAN handle internal failures gracefully. Document the pattern in `agents/coordinator.md` recovery section. |
| Streak break | MILESTONE | Capture in CHANGELOG + retrospective. |

v0.9.1 should ship as a clean validation patch documenting the success + the surfaced finding, NOT a fix. v0.9.2 should address 5a (per-story isolation or HEAD-snapshot guard).
