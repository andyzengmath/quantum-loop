# PRD: `quantum-loop.sh --audit` flag

**Status:** Draft
**Date:** 2026-04-24
**Design doc:** `docs/plans/2026-04-24-audit-flag-design.md`

## Section 1: Introduction / Overview

Add a read-only `--audit` flag to `quantum-loop.sh` that prints the six measurement metrics from `idea-stage/IDEA_REPORT.md §6` and returns a machine-actionable exit code. The flag lets developers and CI jobs confirm repo hygiene (branch count, orphan worktrees, README conflicts, CPC variants, test-suite status) without memorizing the individual `git` / `find` / `grep` commands.

The implementation lives inline in `quantum-loop.sh` (per design Approach 2), structured as a small `do_audit()` driver + six `_audit_<metric>()` helpers so each metric is unit-testable in isolation.

## Section 2: Goals

- Operator can run `./quantum-loop.sh --audit` and get a one-screen repo-hygiene snapshot in under 5 seconds.
- Exit code is 0 iff every metric meets its threshold; 1 if any metric is off-target; 2 on misuse (invalid flag combination or bad env var).
- All six metrics from IDEA_REPORT §6 are individually reported — never silently skipped.
- Thresholds are override-able via `QL_AUDIT_*` env vars matching the repo's existing env-tunable convention (`TYPECHECK_TIMEOUT`, `TRAJECTORY_*`, `REGROUND_INTERVAL`).
- Failure output includes a drill-down line per off-target metric so the operator knows *what* is off, not just *that* something is off.
- 100% unit-test coverage per helper + at least one integration test exercising the full flag end-to-end.
- Zero changes to existing `quantum-loop.sh` behavior — the flag is a pure addition.

## Section 3: User Stories

### US-001: Audit driver infrastructure

**Description:** As an operator, I want the `--audit` flag wired into `quantum-loop.sh`'s arg-loop with a skeleton `do_audit()` driver and the exclusive-flag guard, so subsequent stories can plug in per-metric helpers without re-touching the arg-parsing layer.

**Acceptance Criteria:**
- [ ] `quantum-loop.sh` has a `QL_AUDIT_TEST_MODE` sentinel near the top: `[[ "${QL_AUDIT_TEST_MODE:-0}" == "1" ]] && return 0 2>/dev/null`.
- [ ] `--audit` arg-loop case added; delegates to `do_audit()` and exits with its return value.
- [ ] `do_audit()` function defined (may be stub that returns 0 with a single `"placeholder|0|0|OK|"` row).
- [ ] `_audit_format_row()` helper implemented per design row shape (`name|value|target|status|drill` → rendered line with optional drill-down).
- [ ] Exclusive-flag guard: running `--audit` combined with any other flag (e.g., `--audit --parallel`) prints `Error: --audit is exclusive and takes no other arguments` to stderr and exits 2.
- [ ] `tests/test_audit.sh` created (empty skeleton with `setup_audit_repo()` fixture helper ready for later stories).
- [ ] Test: running `bash quantum-loop.sh --audit` in a clean tmp repo exits 0 and prints at least the `=== Quantum-loop audit ===` header.
- [ ] Test: running `bash quantum-loop.sh --audit --parallel` exits 2 and stderr contains `--audit is exclusive`.
- [ ] Typecheck/lint passes.

### US-002: Git-based metrics (branches + conflicts)

**Description:** As an operator, I want `_audit_branches_local`, `_audit_branches_remote`, and `_audit_readme_conflicts` implemented and wired into `do_audit()`, so I can see the git-related hygiene signals from §6 in the audit output.

**Acceptance Criteria:**
- [ ] `_audit_branches_local()` emits one pipe row; value = count from `git branch | grep -v '^\*\|master$\|HEAD'` (or equivalent exclusion). Target respects `QL_AUDIT_BRANCH_MAX` (default 10). Drill = first 5 branch names + `(+N)` when over.
- [ ] `_audit_branches_remote()` emits one pipe row; value = count from `git branch -r | grep -v 'HEAD\|origin/master'`. Uses same threshold var.
- [ ] `_audit_readme_conflicts()` emits one pipe row; value = `grep -c "^<<<<<<<\|^=======\|^>>>>>>>" README.md 2>/dev/null` (guarded). Target is `QL_AUDIT_CONFLICT_MAX` (default 0). Drill = first 3 line numbers.
- [ ] `do_audit()` calls the three helpers in order and renders rows via `_audit_format_row()`.
- [ ] Running `--audit` on a clean repo prints all three metrics with status OK and exits 0.
- [ ] Running `--audit` on a repo with 12 extra local branches prints `branches-local` with `FAIL — 2 over` and drill containing branch names; exits 1.
- [ ] Unit test per helper: seeded tmp-repo, source script with `QL_AUDIT_TEST_MODE=1`, invoke helper, assert pipe-row shape.
- [ ] Integration test: env-override `QL_AUDIT_BRANCH_MAX=20` with 12 branches seeded → exit 0.
- [ ] Typecheck/lint passes.

### US-003: Filesystem + evidence metrics (orphans + CPC + test-suites)

**Description:** As an operator, I want `_audit_orphan_worktrees`, `_audit_cpc_files`, and `_audit_test_suites` implemented and wired, so the filesystem-level hygiene signals from §6 round out the audit output.

**Acceptance Criteria:**
- [ ] `_audit_orphan_worktrees()` emits pipe row; value = `ls -d .claude/worktrees/agent-* 2>/dev/null | wc -l`. Target `QL_AUDIT_ORPHAN_MAX` (default 0). Drill = first 3 dir names.
- [ ] `_audit_cpc_files()` emits pipe row; value = `find . -maxdepth 3 -name "*-CPC-*" -not -path "./.git/*" | wc -l`. Target `QL_AUDIT_CPC_MAX` (default 0). Drill = first 3 file paths.
- [ ] `_audit_test_suites()` greps the most-recent `.omc/phase-*-evidence/*.log` for `=== Results: <P>/<T> passed, <F> failed ===`. Value = `<P>/<T> passed`. Status OK iff `<F> == 0` across all logs.
- [ ] When no `.omc/phase-*-evidence/` directory exists, `_audit_test_suites` reports value `unknown`, status FAIL, drill `no evidence logs found — run tests first`.
- [ ] Unit test per helper using seeded tmp fixtures (`mkdir .claude/worktrees/agent-foo`, touch `plugin-CPC-xyz.json`, write a canonical evidence log).
- [ ] Integration test: repo with CPC files + orphan worktree dir + all-green evidence log → exit 1 (because CPC & orphans fail), output contains drill-down for both offenders.
- [ ] Integration test: repo with NO `.omc/phase-*-evidence/` → test-suites row shows `unknown` / FAIL / `no evidence logs found`.
- [ ] Typecheck/lint passes.

### US-004: `--help` integration + format regression test

**Description:** As an operator, I want `--audit` documented in the `--help` output with a one-line description, and a regression test locking the exact output format so future edits can't silently change the shape CI scripts depend on.

**Acceptance Criteria:**
- [ ] `--help` output includes a line like `  --audit                 Print §6 measurement metrics and exit (read-only).` in the flag list.
- [ ] `_audit_format_row()` has a direct unit test: given sample pipe rows for OK and FAIL cases, assert the rendered output matches the design doc's UX section format exactly (pass column widths, separator chars, `└─` drill-down prefix).
- [ ] Full-flow integration test (happy path): seed a clean repo + canonical evidence log → exit 0, output contains each metric name + OK + `Summary: 6/6 metrics on target.`
- [ ] Full-flow integration test (all-fail): seed a repo with 15 branches + CPC files + orphan worktree + README conflict markers + red evidence log → exit 1, output shows FAIL for each offending metric and `Summary: N/6 metrics off target.` with correct N.
- [ ] Running `bash quantum-loop.sh --help | grep -- --audit` prints a match.
- [ ] Typecheck/lint passes.

## Section 4: Functional Requirements

- **FR-1:** The system shall accept a `--audit` flag on `quantum-loop.sh`.
- **FR-2:** The system shall reject `--audit` combined with any other flag and exit with status 2.
- **FR-3:** The system shall print exactly six metric rows: `branches-local`, `branches-remote`, `orphan-worktrees`, `readme-conflicts`, `cpc-files`, `test-suites`.
- **FR-4:** Each row shall be one line in the format `<name>: <value> (target <target>) <OK|FAIL>`.
- **FR-5:** When a metric's status is FAIL, the system shall emit an indented drill-down line beginning `└─` listing up to the first 3 offending items followed by `(+N)` where N is the remaining count.
- **FR-6:** The system shall read thresholds from env vars `QL_AUDIT_BRANCH_MAX`, `QL_AUDIT_ORPHAN_MAX`, `QL_AUDIT_CONFLICT_MAX`, `QL_AUDIT_CPC_MAX`, `QL_AUDIT_TEST_GLOB`; each defaults to the value specified in IDEA_REPORT §6 (10 / 0 / 0 / 0 / `tests/test_*.sh`).
- **FR-7:** The system shall exit 0 if every metric's status is OK; exit 1 if any metric's status is FAIL.
- **FR-8:** The system shall complete a full audit on a clean repo in under 5 seconds (excluding cold git index load).
- **FR-9:** The system shall NOT run the project's test suite; the `test-suites` metric is derived from the most recent `.omc/phase-*-evidence/*.log` files.
- **FR-10:** When no `.omc/phase-*-evidence/` directory exists, the `test-suites` metric shall report value `unknown` with status FAIL and drill `no evidence logs found — run tests first`.
- **FR-11:** The system shall validate `QL_AUDIT_TEST_GLOB` against `^[A-Za-z0-9._/*-]+$`; on mismatch, print `Error: invalid QL_AUDIT_TEST_GLOB` to stderr and exit 2.
- **FR-12:** The system shall NOT write or modify any files during an audit run.
- **FR-13:** The `--audit` flag shall appear in `--help` output with a one-line description.
- **FR-14:** The system shall include a `QL_AUDIT_TEST_MODE` sentinel early in `quantum-loop.sh` that allows unit tests to source the script without triggering the main arg-loop.
- **FR-15:** When run from inside a worktree (`.ql-wt/<story>`), the system shall print a single stderr warning line and proceed normally (no abort).

## Section 5: Non-Goals (Out of Scope)

- **NG-1:** JSON output format — v1 is human-readable only. A `--audit-json` variant is a candidate for v2 if CI needs structured output.
- **NG-2:** ANSI / color output — plain text only so logs and CI pipes stay clean.
- **NG-3:** Integration with `soliton:pr-review` or `ql-deep-review` — the audit is a standalone operator tool, not a reviewer signal source.
- **NG-4:** Historical trend tracking — each run is stateless. No log file, no delta with a prior run.
- **NG-5:** Auto-fixing detected issues — diagnostic only. Fixing stale branches / orphan worktrees / CPC files is deliberately the operator's job.
- **NG-6:** Running under non-bash shells (sh / zsh / fish) — `quantum-loop.sh` already requires bash; the audit path doesn't lower that bar.
- **NG-7:** Re-running the project's test suite — too slow for an audit. Test-suite status is derived from cached evidence logs.
- **NG-8:** Multi-repo audit — single repo only.

## Section 6: Design Considerations

UI: command-line output only. The UX section of the design doc locks the exact line shape, column alignment, and drill-down `└─` prefix. Any future re-alignment must be a conscious decision surfaced in a design-doc update, not a silent edit.

## Section 7: Technical Considerations

- **Shell compatibility:** bash 4+ (consistent with the rest of `lib/*.sh`).
- **External tools:** `git`, `grep`, `find`, `wc`, `ls`, `awk` — all already hard requirements for quantum-loop.
- **`set -euo pipefail` safety:** all helpers wrap git calls in `{ cmd 2>/dev/null ; } || true` (not the `grep -c ... || echo 0` anti-pattern fixed in PR #24).
- **Performance:** each helper completes in under 1 second on repos with ≤10k objects. Test-suites helper uses `grep` over cached logs — avoids re-running any subprocess.
- **Security:** only user-controlled input is `QL_AUDIT_TEST_GLOB`; validated at entry (FR-11). All other env vars are integer-coerced via `(( ))` comparison so non-numeric values fail closed.

## Section 8: Success Metrics

- Running `./quantum-loop.sh --audit` on `master` at HEAD prints all six metrics with status OK in under 5 seconds.
- CI job added in a follow-up release runs `--audit` after merge; exit code 0 → green badge, exit 1 → actionable diff comment.
- `test_audit.sh` adds 11 tests; full suite (`tests/test_*.sh`) remains green.
- Wiring assertions in `test_orchestrator_wiring.sh` unchanged (this feature is orthogonal to the orchestrator agent markdown).

## Section 9: Open Questions

None at this time.

## Lifecycle Checklist

- **First-run behavior** — On first invocation, metrics compute from current repo state. No config initialization needed; defaults kick in automatically.
- **Returning-user behavior** — Stateless. Each run is independent. Results change only when the repo state changes.
- **Update behavior** — Metric list is fixed in v1. Adding a new metric = new helper + new default threshold + bumped minor version. Existing env-var consumers continue to work; removing a metric would be a breaking change.
- **Error recovery** — Invalid env-var input → exit 2 with clear error (FR-11). Missing git binary / missing README / missing `.omc/` → graceful degradation with `unknown` / FAIL where applicable (FR-10 for test-suites; git binary absence handled via `|| true` guards).
- **No-data / empty state** — Fresh clone with no tests run: `test-suites` reports `unknown` with drill. Fresh repo with no branches beyond master: every count is 0, all OK. No "first-time welcome" output — tool is diagnostic, not interactive.
- **Uninstall / disable** — N/A: the flag is a pure addition. Removing the code deletes the flag; no persisted state to clean up, no dependent features.
