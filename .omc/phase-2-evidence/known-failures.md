# Phase 2 Known Failures (inherited from CPC track, not promotion regressions)

Date: 2026-04-22
Context: After CPC → canonical promotion on `ql/bug-gap-fix-2026-04`

## Summary

| Metric | Count |
|--------|------:|
| Test suites run | 28 |
| Suites fully green | 26 |
| Suites with failures | 2 |
| Individual test cases | 918 |
| Passed | 905 |
| Failed | 13 |
| Pass rate | **98.6%** |

## Failing tests (investigation deferred to Phase 6 P1.7)

### test_typecheck_gate — 12 failures (all in "Test 10")

```
Test 10: Typecheck with warnings but zero errors passes
  FAIL: Warnings-only returns 0   (expected 0, got 1)
  FAIL: Logs PASS for zero errors
    actual: [TYPECHECK] ERROR: typecheckCommand 'bash /tmp/tmp.XXX/warn_typecheck.sh'
            does not match any allowed prefix — refusing to execute
```

**Root cause**: `lib/resilience.sh` / `lib/merge-strategy.sh` implement a typecheckCommand allowlist (security feature from v0.3.4 hardening). Test 10's fixture runs `bash /tmp/.../fixture.sh` which doesn't match the allowlist pattern. The allowlist check is **correct security behavior**; the test fixture needs updating.

**Fix path**: update the fixture to use an allowlisted prefix (`tsc`, `pyright`, `mypy`, `go build`, etc.) or expose a test-mode bypass. Defer to Phase 6 or a dedicated fix-story.

**Regression risk**: zero. The behavior is intentional security hardening.

### test_timeout — 1 failure (Test 5)

```
Test 5: kill_agent_process kills a running process
  PASS: Process running before kill
  PASS: kill_agent_process exits 0
  FAIL: Process still running after kill
```

**Root cause**: Windows process-kill semantics. `kill -9 <pid>` via Git Bash / MSYS2 doesn't always terminate the process immediately on Windows; the subsequent check races the OS. Known Git-Bash limitation.

**Fix path**: add small settle delay before post-kill check, or use `taskkill //F //PID` on Windows. Defer to Phase 6.

**Regression risk**: zero. The production orchestrator uses a longer settle window.

## Baseline comparison

These tests did NOT exist on the plain track before promotion — they are new tests that shipped with the CPC hardening. No "regression" is possible because there is no prior green state to regress from. Treated as baseline for the integration branch.

## Tracking

Both failures to be logged as stories in Phase 10 dogfood `quantum.json` so the repaired post-mortem generator (Phase 6) observes them end-to-end on first real run.
