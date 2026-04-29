# Module: Step 5 / 5B — Generate Execution Observations + GitHub Issue (user-confirmed)

**Activation:** runs after main loop exits (always-on).

After the main loop exits (COMPLETE, BLOCKED, or max iterations), generate an observations document.

### Step 5: Local observations doc

1. **File path:** `docs/post-mortems/YYYY-MM-DD-<branchName>-observations.md`
2. **Content:**
   - **Header:** Date, story counts (passed/failed/blocked/total), execution mode (sequential/parallel), number of iterations, approximate wall-clock time
   - **Failure summary table:** For each failed or blocked story, show story ID, title, failure phase, error message, retry count
   - **Patterns observed:** Recurring failure modes (same root cause in 2+ stories), what worked well, suggested improvements for the pipeline
   - **Contract Effectiveness:** Summary of how type contracts performed during execution. Include these 7 metrics:

     | Metric | Description |
     |--------|-------------|
     | Contracts defined | N types — total number of contract categories defined in `quantum.json.contracts` |
     | Materialized | N (multi-consumer only) — contracts that were written to shared files for import by multiple stories |
     | Divergence prevented | N — types where all consuming agents imported from the materialized contract file instead of inventing their own |
     | Divergence detected by L5 audit | N (consolidated) — type divergences discovered by the Layer 5 post-merge audit and successfully consolidated |
     | False positives (L5) | N — cases where L5 flagged a name collision but the types represent different concepts (same name, different semantics — not consolidated) |
     | Missed | N — divergences not caught by contracts or L5, discovered only in post-merge review or integration testing |
     | Promoted to permanent contracts | N — contract entries that proved valuable enough to be added to the project's permanent type definitions |

     **How metrics are computed:**
     - **Contracts defined:** Count the keys in `quantum.json.contracts` (each key is a contract category/type).
     - **Materialized:** Count entries in `execution.materializedContracts` — these are contracts that were written to shared files because multiple stories consume them.
     - **Divergence prevented:** For each materialized contract, check whether all consuming stories imported from the materialized file (rather than defining their own version). Count the contracts where all consumers used the shared file.
     - **Divergence detected by L5 audit:** Count entries in `execution.discoveredContracts` where `consolidated: true` — these are type divergences the Layer 5 audit found and merged into a single definition.
     - **False positives (L5):** Count entries in `execution.discoveredContracts` where `consolidated: false` — these are name collisions flagged by L5 that turned out to be distinct concepts (same identifier, different semantics).
     - **Missed:** Count entries in story `retries.failureLog` arrays where `phase` is `"merge_typecheck"` or `"merge_conflict"` — these represent type divergences that escaped both contracts and L5, surfacing only at merge time.
     - **Promoted to permanent contracts:** Count contracts that were added to the project's permanent type definitions during this execution (tracked in progress entries with action `"contract_promoted"`).

     **This section appears even if all values are 0.** A run with all-zero contract metrics indicates no shared types were defined for this feature, which is itself useful information for future planning.

   - **Module Timing:** Performance metrics for each hardening module. Throughout execution, the orchestrator accumulates timing data from module log messages (each module logs `[TAG] Completed in Nms`). Report a table:

     | Module | Total Invocations | Total Time (ms) | Avg Time (ms) |
     |--------|-------------------|------------------|----------------|
     | BARREL-REGEN | N | N | N |
     | DEP-MANIFEST | N | N | N |
     | MERGE-STRATEGY | N | N | N |
     | KNOWN-FAILURES | N | N | N |
     | WORKTREE | N | N | N |

     **How to accumulate timing data:** Parse log output for lines matching `\[(BARREL-REGEN|DEP-MANIFEST|MERGE-STRATEGY|KNOWN-FAILURES|WORKTREE)\].*Completed in (\d+)ms`. For KNOWN-FAILURES, aggregate across baseline, snapshot, and delta operations. For WORKTREE, aggregate across cleanup and register operations.

     **Performance flag:** If any module's Total Time exceeds **10,000ms (10s)**, flag it in the observations:
     ```
     WARNING: Module <NAME> exceeded 10s total execution time (<actual>ms across <N> invocations).
     Consider profiling or optimizing this module for large codebases.
     ```

     **This section appears even if all values are 0** (indicating no modules were invoked, e.g., sequential execution).

   - **Raw data:** Full progress log and failure logs in collapsed `<details>` sections

3. **Commit:** `git add <file> && git commit -m "docs: execution observations for <branchName>"`

This document is **always** generated locally. It provides a record for continuous pipeline improvement.

### Step 5B: File GitHub Issue (user-confirmed)

Only propose filing a GitHub issue when observations contain **any of:**
- Blocked stories (exhausted all retries)
- Recurring failure patterns (same root cause in 2+ stories)
- Stale story detections

**Process:**
1. Use `AskUserQuestion` tool: "I found N issues worth reporting. Would you like me to file a GitHub issue on andyzengmath/quantum-loop with these observations?"
2. **Only file if the user confirms.** Default is No.
3. Issue command: `gh issue create --repo andyzengmath/quantum-loop --title "Execution observations: <branchName> (<date>)" --body "<observations doc content>" --label "execution-feedback"`
4. If `gh` is not available or the command fails: skip silently — the local doc is the primary artifact.
