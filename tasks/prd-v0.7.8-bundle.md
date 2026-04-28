# PRD: v0.7.8 — patch-tier reactive (N36 + N37)

**Status:** Approved
**Branch:** `ql/v0.7.8-bundle`
**Target version:** 0.7.8

## Section 1: Overview

3-story compact reactive closing N36 (runner_load error-message UX) + N37 (yaml example deprecation note). 12th multi-cycle populated-CSV run.

## Section 2: Goals

- Close N36 + N37 from IDEA_REPORT_v18.
- Bump 0.7.7 → 0.7.8.

## Section 3: User Stories

### US-001: N36 — runner_load error-message hint

**ACs:**
- [ ] `lib/runner.sh` `runner_load` error path "Invalid runner name" appends a hint sentence: e.g., "Hint: pass the runner name (e.g., 'codex'), not the manifest path."
- [ ] Grep verification: `lib/runner.sh` contains "Hint: pass the runner name" (or similar).
- [ ] Existing tests remain green.

### US-002: N37 — yaml example deprecation note

**ACs:**
- [ ] `runners/manifest.example.yaml` header comment notes that `runners/*.json` is the authoritative per-runner manifest source; the yaml example is documentation only / explores aggregate manifest concepts.
- [ ] Grep verification: header includes `authoritative` or `documentation only`.

### US-003: Retrospective + IDEA_REPORT_v19 + 0.7.7 → 0.7.8

**ACs:**
- [ ] `idea-stage/PIPELINE_REPORT_v19.md` documents v0.7.8.
- [ ] `idea-stage/IDEA_REPORT_v19.md` lists open after v0.7.8.
- [ ] CHANGELOG `[0.7.8]` entry.
- [ ] All 4 manifest fields → 0.7.8.

## Section 4: FRs

- FR-1: runner_load emits the hint on invalid-name path.
- FR-2: yaml example header self-documents as advisory.
- FR-3: Plugin 0.7.8 + CHANGELOG entry.

## Section 5: Non-Goals

- NG-1: Removing `runners/manifest.example.yaml` outright (just deprecation note).
- NG-2: Refactoring `lib/multi-runner-manifest.sh` (v0.7.4) — separate cleanup scope.
- NG-3: Real-task dispatch (N35 deferred).

## Next Steps

Advisory hooks → execute → review → squash → tag v0.7.8.
