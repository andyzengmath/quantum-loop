# IDEA_REPORT_v43 — what's open after v0.10.9 (wave plan COMPLETE)

**Date:** 2026-05-02
**Source:** v0.10.9 ships wave-plan cycle-4 FINAL (N44 + N40-47 closeout investigation).
**Branch:** `ql/v0.10.9-bundle` (release tag v0.10.9 — pending)
**Predecessor:** `idea-stage/IDEA_REPORT_v42.md`

## Wave plan COMPLETE — 4 cycles shipped

| Cycle | Version | Stories | Outcome |
|-------|---------|---------|---------|
| 1 | v0.10.6 | N50 + Trap RETURN | ✓ shipped 2026-05-02 |
| 2 | v0.10.7 | copilot-rate-limit + N49 closure | ✓ shipped 2026-05-02 |
| 3 | v0.10.8 | N48 + ANSI passthrough | ✓ shipped 2026-05-02 |
| 4 | v0.10.9 | N44 + N40-47 closeout | ✓ shipped 2026-05-02 (this cycle) |

## Closed in v0.10.9

### US-001: N44 — CSV/PIPELINE_REPORT count reconciliation

**Verdict:** **CLOSED-implicit.**

**Audit findings:**
- v0.8.0's PIPELINE_REPORT_v22 reported "design=2 (0/0/1/1), prd=2 (0/0/1/1), plan=2 (0/0/1/1) — 3 MEDIUM and 3 LOW total" (= 6 findings claimed).
- Underlying CSV rows for v0.8.0 timeframe (`metrics/pre-impl-review-findings.csv`):
  - `2026-04-28T19:18:01Z,design,docs/plans/2026-04-28-v0.8.0-bundle-design.md,1,0,0,0,1`
  - `2026-04-28T19:18:04Z,prd,tasks/prd-v0.8.0-bundle.md,1,0,0,0,1`
  - `2026-04-28T19:18:05Z,plan,quantum.json,1,0,0,0,1`
  - **CSV totals for v0.8.0: 3 findings (1 design LOW + 1 prd LOW + 1 plan LOW = `count=1, 0/0/0/1` per stage).**
- v22's claim was a one-shot reporting over-count (likely cumulative across multiple cycles or fabricated; not reproducible).
- v0.8.1's PIPELINE_REPORT_v23 onwards correctly reflect CSV: "design=1, prd=1, plan=1" matches CSV row counts. No subsequent PIPELINE_REPORT (v24-v42) repeats the over-count pattern.

**Closure rationale:** The report-writer pattern that caused v22's over-count is no longer in use. Recent reports (v23+) describe findings in plain language anchored to specific CSV rows. **No code fix needed; data is authoritative.**

### US-002: N40/N41/N38/N45/N43/N46/N47 closeout investigation

| Finding | Origin | Severity | Verdict | Rationale |
|---------|--------|---------:|---------|-----------|
| **N40** orchestrator.md ≤700-line target | v0.8.0 (post-1743→1007 reduction) | LOW | **CLOSED-obsolete** | "Defer indefinitely unless context-window pressure resurfaces" per origin (`IDEA_REPORT_v22:30-32`). Current `agents/orchestrator.md` = 1007 lines (unchanged through v0.10.x). No context-window pressure observed in 30+ subsequent cycles. v0.10.x cycles routinely complete in fresh sessions without context exhaustion. Cosmetic AC compliance only; substantive value already delivered. |
| **N41** coordinator.md→orchestrator.md migration doc | v0.8.0 dogfood | LOW | **CLOSED-implicit** | v0.9.x shipped `--coordinator` as primary dispatch path. `CLAUDE.md` documents coordinator helpers (`QL_COORDINATOR_TIMEOUT_S`, `lib/coordinator-guard.sh`, `lib/quantum-validate.sh`) under "Coordinator-related" section. Migration story is embedded in operator docs and `agents/coordinator.md`. The dual-path framing is gone (coordinator is the path; legacy is fallback). |
| **N38** codex CLI flag drift detection automation | v0.7.x | LOW | **CLOSED-implicit** | v0.7.10 N35 introduced multi-runner dispatch test layer (`tests/test_codex_dispatch.sh`, `tests/test_runner_dispatch.sh`) that empirically catches CLI flag drift via real-task end-to-end probes. Worked example documented in `CLAUDE.md` Process references: codex `-q` → `exec` subcommand migration was caught by this layer. Implicit closure via test infrastructure; no further automation needed. |
| **N43** Parallel-with-dispatch wrap pattern | v0.8.1 | MEDIUM | **DEFERRED-future** | Real architectural work: spawn runner in background, poll commits in foreground, kill runner if STALE pre-respawn. Background-process supervision in shell is fragile on Git Bash. Legitimate v0.11.x+ candidate when context-window pressure or stuck-agent failure mode resurfaces. Currently no operational pressure; current post-dispatch wrap is reactive but reachable. Re-tier remains MEDIUM. |
| **N45** External-helper working-tree noise | v0.7.10/v0.8.0 boundary | LOW | **CLOSED-obsolete** | No recurrence observed in any v0.9.x or v0.10.x cycle. The boundary stashes (`wip-pre-v0.8.0-external-edits`, `v0.8.1-pre: external-helper edits 2026-04-29`) were cleaned during v0.8.x. Operational hygiene issue is no longer reproducible. |
| **N46** QL_RESPAWN_CMD respawn-output not re-parsed | v0.8.1 US-006 acknowledged-limitation | MEDIUM | **DEFERRED-future** | Real architectural work: capture respawn stdout/stderr, re-feed through `runner_parse_output`, update `SIGNAL_RESULT`/`SIGNAL_CONFIDENCE` before falling into post-wrap case-statement. Operator-facing UX bug (successful respawn rc=0 still marks story failed). v0.11.x+ candidate when an operator with `QL_RESPAWN_CMD` configured reports the symptom. Re-tier remains MEDIUM. |
| **N47** branch-cleanup hygiene | v0.7.x onward | LOW | **DEFERRED-operator** | Operator-decision-pending. Not an implementation issue. 22+ local branches accumulated v0.7.x..v0.10.9. Operator can run `git branch | grep ql/ | xargs git branch -D` after release tags are pushed. Documented as standing-backlog operator chore. |

### Summary verdicts

- **CLOSED in v0.10.9:** N44 (implicit), N40 (obsolete), N41 (implicit), N38 (implicit), N45 (obsolete) = 5 items.
- **DEFERRED-future:** N43 (MEDIUM), N46 (MEDIUM) = 2 items, both legitimate v0.11.x+ candidates.
- **DEFERRED-operator:** N47 (LOW) = 1 item, awaits operator branch-cleanup decision.

## v0.11.0 (OPERATOR-GATED)

**Reserved for the FIRST actual `--coordinator` dispatch on the live repo.** Wave plan dogfood subjects (N50, N49, N48, copilot-rate-limit, ANSI sanitization, trap RETURN, N44) are all closed and ready to be exercised through a real operator-run multi-agent dispatch when scope arrives.

## v0.11.x backlog (post-wave)

| Item | Severity | Path |
|------|----------|------|
| N43 — Parallel-with-dispatch wrap pattern | MEDIUM | v0.11.x architectural cycle |
| N46 — QL_RESPAWN_CMD respawn-output re-parse | MEDIUM | v0.11.x architectural cycle (operator-symptom-driven) |
| N48 stub-coordinator test coverage | MEDIUM (sub-threshold) | v0.11.0 dogfood (need real-coordinator violation case) |
| OSC sequence body residue | LOW | future hardening; non-exploitable |
| Retry-After multi-line edge cases | LOW | future hardening |
| N47 — branch cleanup | operator | operator-decision-pending |

## Recurring observations

- **37 consecutive LOW G30 self-validations** (v0.6.5..v0.10.9).
- **Bundle size sequence: ...3-4-4-4-4.** v0.10.9 = 4 stories.
- **Manual-takeover streak: PARTIALLY BROKEN through v0.10.9** — 11 consecutive cycles with 1 operator gate (at v0.10.6 wave plan approval).
- **p013 (operator-staged kickoff): 17 applications.**
- **p014 (composite review trio): 18 review applications.** 6 review-gate catches in 18 applications (~33% hit-rate; v0.10.9 review itself produced the 6th catch — see `PIPELINE_REPORT_v43.md:51`).
- **p015 (post-cycle 3-agent doc-vs-code audit): 3 applications, canonized at 2.**
- **p016 (dogfood-driven LOW sweep wave): 4/4 cycles complete.** Eligible for canonization — see canonization decision below.

## p016 canonization decision

**Canonized at v0.10.9.** Pattern: when a wave plan unbundles N-finding LOW backlog into per-cycle small features (4 cycles × 4 stories ≈ 16 stories total), and each cycle ships first-attempt PASS with no score-≥85 inline fixes deferred, the wave plan is reproducible.

**Empirical evidence (v0.10.6..v0.10.9):**
- 4 cycles, 16 stories total, all first-attempt PASS.
- 4 review trios (12 reviewers total: architect + code-reviewer + security per cycle); 2 score-≥85 inline fixes across the wave (v0.10.6 cross-ref MEDIUM at code-reviewer 88; v0.10.7 Retry-After MEDIUM at code-reviewer 88 + architect 88); rest below threshold or deferred.
- 2/4 review trios produced inline-fixable score-≥85 findings (50% trio-level hit rate; stable with p014's career trio-level hit rate of 5/18 ≈ 28%).
- 36 → 37 consecutive LOW G30 across the wave (no severity-rubric escalation).
- Manual-takeover streak preserved (1 operator gate at wave-plan approval; cycles ran autonomously on /loop cron).

**p016 definition:** "Dogfood-driven LOW-sweep wave — when LOW backlog accumulates, batch-decompose it into a 3-5 cycle wave plan; each cycle becomes a small feature shipping 3-5 stories of related LOW closures. Every cycle is its own complete patch (PRD → code → review → ship), preserving p013/p014/p015 invariants."

## v0.10.9 → v0.11.0 transition

```
v0.10.6 (wave-cycle-1: N50 + Trap RETURN) ✓
v0.10.7 (wave-cycle-2: copilot-rate-limit + N49 closure) ✓
v0.10.8 (wave-cycle-3: N48 + ANSI sanitization) ✓
v0.10.9 (wave-cycle-4: N44 + N40-47 closeout) ✓ ← THIS CYCLE
v0.11.0 (operator-gated --coordinator dispatch) ← NEXT (no autonomous path)
```

**Operator decision required for v0.11.0 entry:** stage a real feature for `--coordinator` dispatch, OR continue patch-tier work (v0.10.10+) on DEFERRED-future items if N43/N46 architecturally feasible without operator presence.
