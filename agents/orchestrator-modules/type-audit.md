# Module: 3C.0 — Type Audit (Layer 5)

**Activation:** runs at every wave boundary (uses `lib/type-audit.sh` directly; degrades gracefully when functions absent).

Before checking for dead code, scan the wave's changed files for duplicate type definitions. This catches type divergence that slipped past L1-L4 and feeds discoveries back into contracts for subsequent waves.

**Step 1: Collect changed files from the current wave**

```bash
# Get all files changed by stories merged in this wave
WAVE_FILES=$(git diff --name-only <WAVE_BASE_SHA>..HEAD)
```

**Step 2: Scan for duplicate type definitions**

Run `grep_duplicate_definitions()` (from `lib/type-audit.sh`) on the changed files:

```bash
# Returns JSON array: [{"name": "Foo", "files": ["a.ts", "b.ts"]}, ...]
DUPLICATES=$(grep_duplicate_definitions "$REPO_ROOT" "$WAVE_FILES")
```

**Step 3: Handle results**

- **If no duplicates found:**
  Log: `[AUDIT] Grep found 0 duplicate type definitions. Skipping agent audit.`
  Proceed directly to 3C.1.

- **If duplicates found:**
  1. Log the duplicate names and file locations:
     ```
     [AUDIT] Found duplicate type definitions:
       - Foo: a.ts, b.ts
       - Bar: c.py, d.py
     ```
  2. Spawn a **type-auditor** agent with:
     - The duplicate type names and their file paths
     - The contract shape from `quantum.json` `contracts.shared_types` (if an entry exists for that type name)
     - Instruction to: consolidate the duplicate into a single authoritative definition, update all imports in consuming files, run typecheck to verify, and commit with `"fix: consolidate <TypeName> from wave N"`
  3. The type-auditor agent inherits the parent orchestrator's model (no separate model config).

**Step 4: Validate auditor results**

After the auditor completes its consolidation commit:
- Run the full test suite to verify no regressions.
- **If tests pass:** The consolidation commit is accepted and included in the wave's integration check.
- **If tests fail:** Revert the auditor's commit and log:
  ```
  [AUDIT] Consolidation of <TypeName> broke tests. Reverted.
  ```
  The duplicate persists — it will be retried in a future wave or addressed manually.

**Step 5: Update contracts for next wave**

Call `update_contracts_for_next_wave()` (from `lib/type-audit.sh`) for each discovered type:
- Writes each discovered type to `execution.discoveredContracts` with:
  - `discoveredInWave`: current wave number
  - `sourceFiles`: list of files where the duplicate was found
  - `consolidated`: boolean (true if auditor succeeded, false if reverted or false positive)
  - `consolidatedFile`: path to the consolidated file (if consolidated)
- On the next wave, `materialize_contracts()` reads `execution.discoveredContracts` in addition to `contracts.shared_types`, ensuring newly discovered types are materialized for subsequent agents.

**Step 6: Log contract effectiveness metrics**

```
[AUDIT] Wave N: X duplicates found, Y consolidated, Z false positives
```

Where:
- **X** = total duplicate type names detected by grep
- **Y** = types successfully consolidated by the auditor (tests passed after consolidation)
- **Z** = types the auditor identified as false positives (same name, different concept — not consolidated)
