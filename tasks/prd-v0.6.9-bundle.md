# PRD: v0.6.9 — v0.6.8 follow-through (N6-followup, N13, N9-followup, N12)

**Status:** Approved
**Date:** 2026-04-28
**Design doc:** `docs/plans/2026-04-28-v0.6.9-bundle-design.md`
**Source:** `idea-stage/IDEA_REPORT_v9.md` v0.6.9 priority list
**Branch (planned):** `ql/v0.6.9-bundle`
**Target version:** 0.6.9 (patch bump from 0.6.8)
**Total effort estimate:** ~1-1.5 days

## Section 1: Introduction / Overview

This release closes the v0.6.8 followups (N6-followup orchestrator-liveness runtime helper; N9-followup baseline-drift bench-test) plus 2 LOW-priority items (N13 orchestrator-takeover SOP doc; N12 helper rename for clarity). Patch-tier; runtime + doc-additive (1 new lib helper, 1 new committed reference, 1 new bench file, 1 new test file).

**Fifth multi-cycle populated-CSV release** (12 → 15 rows).

## Section 2: Goals

- Close N6-followup, N13, N9-followup, N12 from `IDEA_REPORT_v9`.
- Maintain 0-retry execution record (held since v0.6.0; manual-takeover preserved across v0.6.7+v0.6.8).
- Bump plugin version 0.6.8 → 0.6.9.
- **Process milestone:** populate `metrics/pre-impl-review-findings.csv` with ≥3 new rows (total ≥15).
- **G30 self-validation re-run** against v0.6.9 diff.

## Section 3: User Stories

### US-001: N6-followup — `lib/orchestrator-liveness.sh` parent-side commit-poll helper

**Description:** As an operator running `/ql-execute` in unattended mode, I want a documented helper function that polls for new commits on a configurable timeout, so a parent agent or wrapper script can detect orchestrator stale and take recovery action (re-spawn or hand off).

**Acceptance Criteria:**
- [ ] New `lib/orchestrator-liveness.sh` defines `poll_orchestrator_commits(timeout_sec, interval_sec, base_sha)`.
- [ ] Defaults: timeout_sec=600 (10 min), interval_sec=60 (1 min), base_sha=$(git rev-parse HEAD).
- [ ] Returns 0 (live) when a new commit lands during the window; emits `[LIVENESS] new commit XXXXXXXX observed at +Ns` on stderr.
- [ ] Returns 1 (stale) when timeout elapses with no new commit; emits `[LIVENESS] STALE: no commits in Ns (base=XXXXXXXX)` on stderr.
- [ ] Library contract: no shell flags at source time (`set` only inside CLI/test mode at file bottom if any).
- [ ] `agents/orchestrator.md` Step 1 init block extension: brief subsection (~10 lines) noting that operators running `/ql-execute` in unattended mode can wrap the orchestrator with this helper. Helper invocation is operator-side; this v0.6.9 PR ships the helper and the prose pointer, NOT the SKILL-level wrapping (out of scope; v0.7.0 candidate).
- [ ] New `tests/test_orchestrator_liveness.sh` with 4+ structural assertions (deterministic, no timing-fragile race):
  - (1) Function defined after sourcing the lib.
  - (2) `poll_orchestrator_commits 2 1` in a tmp git repo with no new commits returns 1 within timeout_sec*3 = 6 s wall-clock ceiling (Git Bash sleep jitter can elongate to ~1.5× nominal on loaded hosts; 3× ceiling tolerates this without flakiness). Emits STALE log line on stderr.
  - (3) Pre-staged HEAD-advance: pre-create commit-A and commit-B; checkout A; backgrounded `(sleep 2 && git checkout B)`; `poll_orchestrator_commits 10 1` returns 0 with "new commit" log line. Wall-clock <30 s ceiling for the same jitter reasons.
  - (Test header documents: may flake on heavily-loaded Git Bash hosts where sleep jitter exceeds ~50% of nominal; re-run if flaky.)
  - (4) Default-arg behavior: function inspection or grep verifies the literal `${1:-600}` and `${2:-60}` defaults in the source.

### US-002: N13 — `references/orchestrator-takeover.md` (NEW)

**Description:** As a parent agent detecting orchestrator drift mid-cycle, I want a committed SOP documenting when to detect drift, what to verify, and how to take over without corrupting quantum.json state, so manual-takeover is reproducible across cycles.

**Acceptance Criteria:**
- [ ] New `references/orchestrator-takeover.md` (≥80 lines) with 4 sections:
  - § "When to detect drift": symptoms, citing v0.6.7 + v0.6.8 examples.
  - § "What to verify": git log, jq status query, git diff inspection.
  - § "How to take over without corrupting state": rules including the verification-failure-driven amendment rule (preserve orchestrator edits unless a check proves them broken; v0.6.7 Pattern C → Pattern A example).
  - § "Recovery from N6-followup STALE signal": when the liveness helper (`lib/orchestrator-liveness.sh::poll_orchestrator_commits`) returns 1 (stale), the parent AGENT (LLM) reads this doc to drive recovery. The helper itself emits stderr only and has no awareness of the takeover doc.
- [ ] Cross-linked from `CLAUDE.md` `## Process references` section (joining N7's soliton-finding-triage and N9's wallclock-baselines).
- [ ] New `tests/test_orchestrator_takeover_doc.sh`: asserts file exists + 4 sections + v0.6.7-or-v0.6.8 example + CLAUDE.md cross-link.
- [ ] ≥4 new assertions.

### US-003: N9-followup — `tests/bench_wallclock_baseline_drift.sh` (NEW)

**Description:** As a maintainer of the wall-clock baselines table, I want an opt-in bench that runs each documented baseline command with `time` and emits WARNINGs on >50% drift, so retrospectives have a fast signal for stale baselines.

**Acceptance Criteria:**
- [ ] New `tests/bench_wallclock_baseline_drift.sh` script (≥60 lines).
- [ ] File-naming uses `bench_*` prefix (NOT `test_*`) so `tests/run_all.sh`'s `tests/test_*.sh` glob deliberately skips it.
- [ ] Hardcoded BASELINES associative array (curated subset of the values from `references/test-wallclock-baselines.md`). Header comment documents that operators must update BOTH the bench script's BASELINES array AND the reference table when baselines drift — the operator is the parser; the bench does not auto-extract from the doc.
- [ ] For each baseline command: run with `time`, parse `real` line wall-clock seconds, compare against baseline; emit `WARN: <cmd> took Ns (baseline Xs, threshold Ys — drift > 50%)` if measured > 1.5× baseline.
- [ ] Script always exits 0 (informational only; never FAILs CI).
- [ ] Header comment documents: opt-in invocation (`bash tests/bench_wallclock_baseline_drift.sh`); v0.6.9 N9-followup origin; reason for `bench_*` prefix (run_all.sh skip).
- [ ] Smoke verification: running the script in current state emits 0 WARN lines (current baselines fit current measurements).

### US-004: N12 — helper rename in `tests/test_audit.sh`

**Description:** As a `tests/test_audit.sh` maintainer, I want the v0.6.8 helper pair renamed for sharper distinction, so future maintainers don't have to read both functions to understand which scope each returns.

**Acceptance Criteria:**
- [ ] `extract_function_comments` renamed to `extract_function_header_comments` in `tests/test_audit.sh`.
- [ ] `extract_function_full_comments` renamed to `extract_function_all_comments` in `tests/test_audit.sh`.
- [ ] All 4 call sites updated (Tests 36a, 36b, 37a, 37b — plus any inline references).
- [ ] No code-line edits beyond the rename + call-site updates; no awk-logic change.
- [ ] `bash tests/test_audit.sh` → 45/45 PASS unchanged.
- [ ] `grep -rE 'extract_function_(full_)?comments' tests/` returns 0 matches post-rename (old names purged).
- [ ] `grep -rE 'extract_function_(header|all)_comments' tests/` returns matches only in `tests/test_audit.sh`.

### US-005: Retrospective + IDEA_REPORT_v10 + version bump 0.6.8 → 0.6.9

**Description:** Standard retrospective + IDEA_REPORT_v10 + plugin version bump + G30 self-validation re-run.

**Acceptance Criteria:**
- [ ] `idea-stage/PIPELINE_REPORT_v10.md` documents v0.6.9 dogfood.
- [ ] PIPELINE_REPORT_v10 notes `metrics/pre-impl-review-findings.csv` has ≥15 rows.
- [ ] `idea-stage/IDEA_REPORT_v10.md` lists what's still open after v0.6.9.
- [ ] `quantum-loop.sh --audit` captured to `.omc/phase-N-evidence/v0.6.9-audit.log`.
- [ ] G30 self-validation captured to `.omc/phase-N-evidence/v0.6.9-deep-review-decision.log`; decision recorded in `quantum.json.reviews[v0.6.9-bundle].deepReview` with `automated:true`.
- [ ] CHANGELOG.md updated with v0.6.9 entry.
- [ ] All 4 plugin manifest version fields bumped 0.6.8 → 0.6.9.

## Section 4: Functional Requirements

- **FR-1:** `lib/orchestrator-liveness.sh::poll_orchestrator_commits` exists with documented signature + return semantics + log format.
- **FR-2:** `references/orchestrator-takeover.md` exists with 4 sections + v0.6.7/8 worked example + CLAUDE.md cross-link.
- **FR-3:** `tests/bench_wallclock_baseline_drift.sh` exists, uses `bench_*` prefix to skip `run_all.sh` glob, exits 0 unconditionally.
- **FR-4:** `tests/test_audit.sh` uses renamed helpers (`extract_function_header_comments` + `extract_function_all_comments`); old names purged.
- **FR-5:** `metrics/pre-impl-review-findings.csv` has ≥15 rows after v0.6.9 ships.
- **FR-6:** Plugin version bumped 0.6.8 → 0.6.9 across `.claude-plugin/plugin.json`, `.claude-plugin/marketplace.json` (both fields), `.cursor-plugin/plugin.json`.
- **FR-7:** v0.6.9's own diff classified by its own should_dispatch_deep_review rule; decision recorded in `quantum.json.reviews[v0.6.9-bundle].deepReview` with `automated:true`.

## Section 5: Non-Goals (Out of Scope)

- **NG-1:** `/ql-execute` SKILL wrapping of `poll_orchestrator_commits` — v0.7.0 candidate after the helper exists in v0.6.9.
- **NG-2:** `QL_LIVENESS_ON_STALE` env var — reserved name; not introduced in v0.6.9.
- **NG-3:** `tests/run_all.sh --skip <pattern>` flag — v0.7.0+ if needed; not required for v0.6.9 since `bench_*` prefix already skips.
- **NG-4:** G19 / G21 / G22 / G24 — same triage as prior cycles.
- **NG-5:** P5.B2/B3/B5 + P5.C frontier — same triage.
- **NG-6:** Schema migration. None needed.
- **NG-7:** Bumping to 0.7.0 — patch-tier per strict semver.

## Section 6: Design Considerations

UI: command-line + agent-prose-only. v0.6.9 changes surface in:
1. Operators wrapping `/ql-execute` (after merge — N6-followup helper available).
2. Parent agents detecting drift (N13 SOP doc).
3. Maintainers refreshing baselines (N9-followup bench).
4. Future test-audit maintainers (N12 cleaner names).

No new env vars. No new CLI flags. 1 new lib helper, 1 new reference doc, 1 new bench file, 1 new test file.

## Section 7: Technical Considerations

- **Shell compatibility:** bash 4.3+ (consistent with v0.6.x).
- **External tools:** unchanged from v0.6.8.
- **Quality gates:** all stories' implementations must pass typecheck/lint quality gates (orchestrator Step 5 — full `bash tests/run_all.sh` test suite excluding the new `bench_*` opt-in benchmark).
- **Cross-platform:** `lib/orchestrator-liveness.sh` uses `git rev-parse HEAD` (POSIX-portable) and `sleep` (Git Bash + Linux equivalent semantics within ±1s jitter).

## Section 8: Success Metrics

- All 5 user stories pass with verifiable evidence.
- `bash tests/test_audit.sh` → 45/45 PASS unchanged (US-004 mechanical rename).
- `bash tests/test_orchestrator_liveness.sh` → 4/4 PASS (US-001).
- `bash tests/test_orchestrator_takeover_doc.sh` → 4/4 PASS (US-002).
- `bash tests/bench_wallclock_baseline_drift.sh` → exit 0 with 0 WARN lines (US-003 smoke).
- `metrics/pre-impl-review-findings.csv` has ≥15 rows.
- Plugin version bumped to 0.6.9.
- IDEA_REPORT_v10 lists open backlog.
- 0-retry execution record maintained.
- G30 self-validation records `automated:true`.

## Section 9: Open Questions

None. Bundle composition fully resolved; all 3 advisory-design findings addressed inline.

## Lifecycle Checklist

- **First-run behavior** — Operators running `/ql-execute` (post-merge) can opt into liveness wrapping. Parent agents can read `references/orchestrator-takeover.md` during drift recovery. Maintainers refreshing baselines run `bench_wallclock_baseline_drift.sh` directly.
- **Returning-user behavior** — No env-var or CLI changes. v0.6.8 → v0.6.9 transparent.
- **Update behavior** — Pure additive. No schema, no migration.
- **Error recovery** — `poll_orchestrator_commits` returns 1 on STALE; caller decides. `bench_wallclock_baseline_drift.sh` exits 0 unconditionally (informational).
- **No-data / empty state** — `poll_orchestrator_commits` with no new commits during the window correctly returns 1.
- **Uninstall / disable** — All v0.6.9 changes are inert if operator doesn't invoke them. The `bench_*` prefix ensures the new bench file is opt-in.

## Next Steps

Trigger v0.6.4 prd-review hook (CSV row 14). Author quantum.json. Trigger plan-review hook (CSV row 15). Spawn dag-validator. Execute stories (manual takeover continues if orchestrator drifts). Post-merge: `/soliton:pr-review`, fix score-≥85 inline, squash-merge, tag v0.6.9.
