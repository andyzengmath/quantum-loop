# Test wall-clock baselines (platform-conditional)

**Audience:** PRD authors choosing test-time ACs; retrospective writers comparing dogfood timings.

**Why this exists:** v0.6.7's US-001 specified `<60s` for `bash tests/test_audit.sh` wall-clock. Actual Git Bash wall-clock is ~3–4 min, dominated by per-process subprocess startup overhead in tests that fork `bash quantum-loop.sh --audit`. The `<60s` target was unmeetable on Git Bash and shipped as an AC miss only because the load-bearing intent ("completes without hanging") was met. Future PRDs should reference the table below instead of unconditioned absolute targets.

## Baselines (measured 2026-04-28 on Git Bash 5.x / Windows 11; Linux/CI estimates)

| Command | Git Bash | Linux/CI | Note |
|---|---|---|---|
| `bash tests/test_audit.sh` | ~3–4 min | ~30–60 s | Dominated by `bash quantum-loop.sh --audit` subprocess loops (~30 invocations × ~1 s startup). |
| `bash tests/run_all.sh` | ~17 min | ~3–5 min | Sequential; 76+ test files. The wall-clock bottleneck is per-test bash startup, not in-test logic. |
| `bash tests/run_all.sh --parallel 4` | ~5–8 min | ~1–2 min | xargs -P 4 dispatch via the `--__one` self-recursive entry-point. ~3.6× speedup vs sequential observed in v0.6.6 G31 smoke benchmark. |
| `bash tests/test_run_all.sh` | ~30 s | ~5 s | Small fixture-driven (3-test fixtures + 1 single-test fixture). |
| `bash tests/test_deep_review_dispatch.sh` | ~10–20 s | ~3–5 s | Pure bash + jq; no subprocess fork loops. |
| `bash tests/test_orchestrator_self_monitor.sh` | ~5 s | ~2 s | Grep-only against agents/orchestrator.md prose. |

**Dominant cost on Git Bash:** ~1 s of fork+exec overhead per `bash` subprocess invocation. The native Linux/CI cost is ~50 ms per fork (~20× faster). This is why audit-suite tests that subprocess-invoke `quantum-loop.sh --audit` dominate; pure-bash tests (no fork) run nearly as fast on Git Bash as Linux.

## Recommendation for PRD authors

For test-time ACs:

- Prefer **relative targets**: "completes within 2× of the v0.6.X baseline measured in this reference."
- Or **platform-conditional**: "Git Bash: <8 min. Linux/CI: <2 min."
- Avoid **absolute targets** (e.g., `<60s`) unless the test is in the pure-bash category and platform is fixed.

For retrospective comparisons:

- Note the host platform when reporting wall-clock measurements. A 200 % drift on Git Bash may mean a 50 % drift on Linux.
- If the operator runs `tests/run_all.sh --parallel 4` on Git Bash and observes >12 min, that's drift worth investigating (50 % over the ~8 min ceiling). Below 8 min is normal.

## Out-of-scope for v0.6.8 — queued for v0.6.9 N9-followup

A meta-test that runs each baseline command with `time` and emits a WARNING (not FAIL) if the measured time exceeds the documented baseline by > 50 % was suggested by v0.6.8 design-review but deferred. Adding it inline would scope-creep v0.6.8 and double the cycle's wall-clock during test runs. Hand-update is acceptable for now — operators refresh the baselines during retrospectives that observe drift.

## Update procedure

When refreshing this table during a retrospective:

1. Run the command on the host platform with `time`:
   ```bash
   time bash tests/run_all.sh --parallel 4
   ```
2. Round to the nearest minute (>=1 min) or 5 s (<1 min).
3. Update the table row.
4. Note the date in this section's heading.
5. If the new value differs >50 % from the prior baseline, investigate before committing — could indicate a real regression or environment shift.
