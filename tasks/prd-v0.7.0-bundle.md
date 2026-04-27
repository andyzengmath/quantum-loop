# PRD: v0.7.0 — pre-impl-review maturation (G12-G17)

**Status:** Approved
**Date:** 2026-04-26
**Design doc:** `docs/plans/2026-04-26-v0.7.0-bundle-design.md`
**Source:** `idea-stage/IDEA_REPORT_v4.md` §G12 / G13 / G14 / G15 / G16 / G17 (six gaps surfaced by v0.6.3 dogfood)
**Branch (planned):** `ql/v0.7.0-bundle`
**Target version:** 0.7.0 (minor bump from 0.6.3; opens "review-system maturation" arc)
**Total effort estimate:** ~3-5 days (single-developer; ~2-3 days with parallel waves)

## Section 1: Introduction / Overview

This release matures the three advisory pre-impl-review stages shipped in v0.6.3 (design / PRD / plan) by giving them a parser, persistence layer, severity rubric, and `--audit` coverage metric. It also extracts a 4-way duplicated regex into a single source of truth and codifies the CHANGELOG-ownership convention that v0.6.3 dogfood used implicitly.

The 7-story bundle is **minor-tier** (no breaking changes; all new mechanisms are additive and opt-in/non-blocking). New persistence files default to gitignored snapshots + a committable aggregate ledger.

Per user framing (Option α from IDEA_REPORT_v4): instrument before expanding. The v0.7.x track will graduate one or more pre-impl-review stages from advisory to blocking — but only after this bundle's data foundation has accumulated at least 1 release of baseline.

## Section 2: Goals

- Close G12 (finding parser), G13 (finding persistence), G14 (sprint-contract regex DRY), G15 (CHANGELOG-ownership convention), G16 (severity rubric), G17 (audit coverage metric) from `IDEA_REPORT_v4.md`.
- Maintain 0-retry execution record (v0.6.0 baseline; held at v0.6.3).
- Bump plugin version 0.6.3 → 0.7.0 across all 3 manifests in lockstep.
- Backward compatibility: existing v0.6.x quantum.json files load and run unchanged.
- After v0.7.0 ships, the very NEXT pipeline run (v0.7.1) is the first to populate `metrics/pre-impl-review-findings.csv` end-to-end (because the orchestrator that ran v0.7.0 itself was on v0.6.3 master HEAD).

## Section 3: User Stories

### US-001: G12 — `lib/finding-synth.sh` parser

**Description:** As an operator running `/ql-brainstorm`, `/ql-spec`, or `/ql-plan`, I want a single library function that parses the spec-reviewer's `FINDING_START..FINDING_END` stderr blocks into a structured JSON array, so that downstream tooling can count, persist, and aggregate findings instead of treating them as opaque text.

**Acceptance Criteria:**
- [ ] New `lib/finding-synth.sh` defines three functions:
  - `parse_findings(stage_name)` reads stdin and emits a JSON array of `{category, severity, file, line, evidence, suggestion}` objects to stdout.
  - `summarize_findings(stage_name, findings_json)` emits `{stage, count, by_severity:{critical,high,medium,low}, by_category:{...}}` JSON.
  - `format_summary_line(summary_json)` emits the existing `[REVIEW] <stage>-review complete: <N> findings (<crit>/<high>/<med>/<low>)` text format used by spec-reviewer modes.
- [ ] All three functions are source-friendly (no shell flags at source time, strict mode only in the CLI-entry block per `lib/handoff.sh` convention).
- [ ] Malformed FINDING blocks (missing `FINDING_END`, unparseable severity) produce a one-line warning to stderr but do NOT crash; parser continues with the remaining well-formed blocks.
- [ ] CLI subcommand mode: `bash lib/finding-synth.sh parse design < <(...)`, `bash lib/finding-synth.sh summarize design '<json>'`, `bash lib/finding-synth.sh format '<summary>'`.
- [ ] New `tests/test_finding_synth.sh` with ≥12 assertions:
  - Empty stdin → empty array `[]`, count 0.
  - 1 well-formed block → 1-element array with all 6 fields populated.
  - 4 mixed-severity blocks → 4 entries; summary counts correct (1/1/2/0 by severity).
  - Malformed block (no `FINDING_END`) → stderr warning + remaining blocks parsed.
  - format_summary_line round-trip with a known summary produces the exact text format.
- [ ] Typecheck/lint passes.
- [ ] No skill changes in this story (US-002 wires the parser).

### US-002: G13 — persist parsed findings + aggregate ledger

**Description:** As a maintainer tracking pre-impl-review baseline data, I want every advisory review run to (a) write a per-run snapshot of parsed findings to `.handoffs/<stage>-review-findings.json` and (b) append a summary row to `metrics/pre-impl-review-findings.csv`, so that v0.7.x has the data needed to calibrate severity and eventually promote stages from advisory to blocking.

**Acceptance Criteria:**
- [ ] New `lib/finding-persist.sh` defines:
  - `persist_review_findings(stage, source_path, summary_json, findings_json)` — writes both the snapshot JSON and the CSV append.
  - `read_review_findings(stage)` — reads `.handoffs/<stage>-review-findings.json`, emits `{}` on missing-file with stderr warning (graceful per `read_sprint_contract` convention).
- [ ] Snapshot path: `.handoffs/<stage>-review-findings.json` where `<stage>` is one of `design`, `prd`, `plan`. Schema: `{stage, timestamp, source_path, summary, findings}`.
- [ ] Snapshot is overwritten on each run of the same stage (idempotent for snapshot).
- [ ] Aggregate ledger: `metrics/pre-impl-review-findings.csv`. Columns: `timestamp,stage,source_path,count,critical,high,medium,low`. Append-only.
- [ ] CSV file is created on first write (with header row); subsequent writes append data rows only.
- [ ] CSV append uses an atomic-append guard (`flock -x` if available, or rename-replace fallback) to tolerate concurrent SKILL invocations.
- [ ] `.handoffs/*-review-findings.json` added to `.gitignore`.
- [ ] `metrics/` directory NOT gitignored (the CSV is committed baseline data).
- [ ] `skills/ql-brainstorm/SKILL.md` Phase 4d block extended: capture stderr to a temp log; source `lib/finding-synth.sh` + `lib/finding-persist.sh`; parse + persist after the spec-reviewer returns. The advisory contract (no abort on findings) is preserved.
- [ ] `skills/ql-spec/SKILL.md` post-prd-review block extended identically for `prd` stage.
- [ ] `skills/ql-plan/SKILL.md` Step 9 plan-review block extended identically for `plan` stage.
- [ ] New `tests/test_finding_persist.sh` with ≥14 assertions:
  - Snapshot write creates `.handoffs/design-review-findings.json` with valid schema; re-run overwrites.
  - CSV write creates `metrics/pre-impl-review-findings.csv` with header on first invocation.
  - 3-stage end-to-end (design + prd + plan) produces 3 snapshots + 3 CSV rows.
  - Re-running design stage overwrites snapshot but appends a NEW CSV row.
  - Missing `metrics/` dir is created automatically.
  - `read_review_findings` on missing file returns `{}` + stderr warning (no crash).
- [ ] Existing `tests/test_handoff.sh` 38 assertions remain green.
- [ ] Existing `tests/test_spec_review_design.sh`, `test_spec_review_prd.sh`, `test_spec_review_plan.sh` (13-14 each) remain green.
- [ ] Typecheck/lint passes.

### US-003: G14 — `SPRINT_CONTRACT_TEST_REGEX` constant

**Description:** As a maintainer of the Sprint-Contract code, I want the test-pattern regex to live in exactly one place (`lib/handoff.sh`), so a future regex change requires touching one file instead of four.

**Acceptance Criteria:**
- [ ] `lib/handoff.sh` defines `SPRINT_CONTRACT_TEST_REGEX` as a `readonly` shell constant near the top (right after the canonical `HANDOFF_STAGE_ORDER` block), guarded against double-source.
- [ ] Constant value: `'(test_|\.test\.|spec|pytest|^bash tests/|^npm test)'` (verbatim from current inline copies).
- [ ] Constant is documented inline with a 3-line comment explaining its purpose and listing all consumers.
- [ ] `agents/orchestrator.md` Step 2.5 updated: source `lib/handoff.sh`, then pass the constant to jq via `--arg pattern "$SPRINT_CONTRACT_TEST_REGEX"` and use `test($pattern)` in the jq filter (instead of the inline regex literal).
- [ ] `skills/ql-plan/SKILL.md` Step 8 updated identically.
- [ ] `tests/test_sprint_contract.sh` Test 6 inline regex blocks (lines 166, 196, 226 / 167, 197, 227) replaced with `--arg pattern "$SPRINT_CONTRACT_TEST_REGEX"` injection (after sourcing `lib/handoff.sh`).
- [ ] `tests/test_sprint_contract_ql_plan.sh` updated identically.
- [ ] `references/sprint-contract.md` `expectedTests` row updated: bracketed reference replaced with `"see lib/handoff.sh::SPRINT_CONTRACT_TEST_REGEX"`.
- [ ] New assertion in `tests/test_sprint_contract.sh`: `grep -cE 'test_\|\\\\\\.test\\\\\\.\|spec\|pytest' agents/orchestrator.md skills/ql-plan/SKILL.md` returns 0 (no inline duplicates remain).
- [ ] New assertion: `grep -q 'SPRINT_CONTRACT_TEST_REGEX' lib/handoff.sh && grep -q 'SPRINT_CONTRACT_TEST_REGEX' agents/orchestrator.md && grep -q 'SPRINT_CONTRACT_TEST_REGEX' skills/ql-plan/SKILL.md` succeeds.
- [ ] Existing 16 sprint-contract assertions remain green.
- [ ] Existing 13 `test_sprint_contract_ql_plan.sh` assertions remain green.
- [ ] Typecheck/lint passes.

### US-004: G16 — severity rubric + cross-link

**Description:** As an operator reading pre-impl-review findings, I want a documented severity rubric per mode, so I can calibrate how `critical` differs from `high` when `design-review`'s severity competes with `quality-reviewer`'s severity downstream.

**Acceptance Criteria:**
- [ ] New `references/finding-severity.md` contains 3 mode sections:
  - `## design-review`
  - `## prd-review`
  - `## plan-review`
- [ ] Each mode section contains a 4-row severity table (columns: Severity, Rubric, Example) with rows for `critical`, `high`, `medium`, `low`. Each row's example must be mode-specific (a real category from that mode's existing checklist).
- [ ] Each mode section in `agents/spec-reviewer.md` (the existing `## Mode: design-review`, `## Mode: prd-review`, `## Mode: plan-review` blocks) gains one cross-link line ABOVE its `### Output format` subsection: `> See [references/finding-severity.md](../references/finding-severity.md#<mode>) for severity calibration.`
- [ ] Cross-links use anchor IDs that match the `## <mode>` headings in `references/finding-severity.md` (kebab-case, no `## ` prefix).
- [ ] New `tests/test_finding_severity.sh` with ≥8 assertions:
  - `references/finding-severity.md` exists.
  - All 3 mode sections present.
  - Each mode section has all 4 severity rows.
  - Each mode section has at least one example per severity row (non-empty example column).
  - All 3 modes in `agents/spec-reviewer.md` have the cross-link line.
- [ ] Existing 14+13+13 assertions in `test_spec_review_design.sh`/`test_spec_review_prd.sh`/`test_spec_review_plan.sh` remain green.
- [ ] Typecheck/lint passes.

### US-005: G17 — `--audit` pre-impl-review-coverage metric

**Description:** As an operator running `bash quantum-loop.sh --audit`, I want a 7th metric row reporting how many of the 3 advisory pre-impl-review stages have run in the last 7 days, so I have visibility into whether my pipeline is actually exercising the advisory checks.

**Acceptance Criteria:**
- [ ] New helper `_audit_pre_impl_review_coverage` in `quantum-loop.sh`:
  - If `metrics/pre-impl-review-findings.csv` is missing → emits row with WARN status: `pre-impl-review-coverage|0/3 stages|yellow|WARN|no metrics CSV`.
  - If CSV exists but no rows newer than 7 days → emits row with WARN status: `pre-impl-review-coverage|0/3 stages|yellow|WARN|no recent runs`.
  - If 1-2 distinct stages in last 7 days → emits row with WARN status: `pre-impl-review-coverage|N/3 stages|yellow|WARN|missing some stages`.
  - If all 3 distinct stages in last 7 days → emits row with OK status: `pre-impl-review-coverage|3/3 stages|green|OK|`.
- [ ] Helper is wired into `do_audit`'s `ROWS+=(...)` array (after the existing 6 metric helpers; this metric becomes the 7th row).
- [ ] `--audit` summary line `Summary: <ok>/<total> metrics on target.` updates to reflect the new total of 7 metrics.
- [ ] `do_audit`'s exit code is 1 if any FAIL OR if pre-impl-review-coverage is WARN with `metrics/` non-existent (otherwise WARN does not fail the audit, matching existing convention).
- [ ] Cross-platform date math: helper uses both GNU `date -d '7 days ago'` AND BSD `date -v-7d` fallback paths (Git Bash / MSYS / macOS BSD coverage). Falls back to epoch 0 on platforms where neither works.
- [ ] `tests/test_audit.sh` extended with ≥6 new assertions covering all 4 states (missing CSV, no recent rows, partial coverage, full coverage).
- [ ] Existing `test_audit.sh` assertions remain green.
- [ ] `quantum-loop.ps1` parity addition (if PS1 has an audit shim — verify; if not, document the divergence in CHANGELOG).
- [ ] Typecheck/lint passes.

### US-006: G15 — CHANGELOG ownership convention

**Description:** As a planner using `dag-validator`, I want a documented convention that >1 story touching `CHANGELOG.md` triggers a warning (because the v0.6.x dogfood pattern is to defer all CHANGELOG edits to a single retrospective story per release), so future planners don't collide-edit through the conflict-auditor's default `severity: none` classification.

**Acceptance Criteria:**
- [ ] `agents/dag-validator.md` adds a documented convention paragraph (in or near §5c fileConflicts Recomputation): when >1 story has `CHANGELOG.md` in `tasks[].filePaths`, the conflict is classified `severity: warning` (NOT `severity: none`) and the Health Report includes: `WARNING: <N> stories touch CHANGELOG.md — consolidate to a single retrospective story per the v0.6.3 convention.`
- [ ] `agents/conflict-auditor.md` (or wherever severity classification is documented) updated to add the rule: `CHANGELOG.md → severity: warning when stories.length > 1`.
- [ ] New `tests/test_changelog_ownership.sh` with ≥6 assertions:
  - 0 stories touching CHANGELOG → no warning.
  - 1 story touching CHANGELOG → no warning.
  - 2 stories touching CHANGELOG → warning emitted.
  - Warning text matches the documented convention (substring match on "consolidate to a single retrospective story").
  - `agents/dag-validator.md` contains the convention paragraph (grep check).
  - `agents/conflict-auditor.md` (or shared doc) contains the classification rule.
- [ ] No existing tests should break.
- [ ] Typecheck/lint passes.

### US-007: Dogfood retrospective + IDEA_REPORT_v5 + version bump

**Description:** As a project maintainer, I want a structured retrospective after Phase 6 captures findings from running v0.7.0 through the pipeline, an IDEA_REPORT_v5 mapping what's still open after v0.7.0, and plugin version bumped 0.6.3 → 0.7.0 across all 3 manifests.

**Acceptance Criteria:**
- [ ] `idea-stage/PIPELINE_REPORT_v5.md` documents v0.7.0 dogfood: total wall-clock, wave timings, cross-story-contract events, v0.7.0-specific note that `metrics/pre-impl-review-findings.csv` is empty after this run (because the orchestrator was still on v0.6.3 master HEAD when running v0.7.0), test-suite delta vs v0.6.3.
- [ ] `idea-stage/IDEA_REPORT_v5.md` lists what's still open after v0.7.0: P5.B2 (bidirectional reviewer), P5.B3 (`/ultrareview`), P5.B5 (AgentGA tournament), P5.C* frontier, plus any NEW gaps surfaced this run. Explicitly notes that **v0.7.1's first run will be the first end-to-end populated CSV** and that promoting any pre-impl-review stage from advisory→blocking should wait until ≥1 release of CSV data accumulates.
- [ ] `quantum-loop.sh --audit` re-run after Phase 6 merges; output captured to `.omc/phase-N-evidence/v0.7.0-audit.log`; should report 7/7 metrics with pre-impl-review-coverage at WARN (`0/3 stages, no recent runs`) — this is correct behavior, not a regression.
- [ ] `CHANGELOG.md` updated with v0.7.0 entry covering 6 user-facing stories (G12-G17).
- [ ] `.claude-plugin/plugin.json` (`version` field) bumped 0.6.3 → 0.7.0.
- [ ] `.claude-plugin/marketplace.json` (BOTH `metadata.version` AND `plugins[0].version` fields) bumped 0.6.3 → 0.7.0.
- [ ] `.cursor-plugin/plugin.json` bumped 0.6.3 → 0.7.0.
- [ ] Typecheck/lint passes (no test required; this story is documentation + version-bump only).

## Section 4: Functional Requirements

- **FR-1:** `lib/finding-synth.sh` exposes `parse_findings`, `summarize_findings`, `format_summary_line` (source-callable + CLI-callable).
- **FR-2:** Parser tolerates malformed FINDING blocks with stderr warning, no crash.
- **FR-3:** `lib/finding-persist.sh` exposes `persist_review_findings`, `read_review_findings`.
- **FR-4:** Per-run snapshot at `.handoffs/<stage>-review-findings.json` (gitignored); aggregate ledger at `metrics/pre-impl-review-findings.csv` (committed).
- **FR-5:** Snapshot is overwritten on re-run; CSV is append-only with atomic-append guard.
- **FR-6:** All 3 SKILLs (`ql-brainstorm`, `ql-spec`, `ql-plan`) wire the parse → persist pipeline at their existing post-review hooks; advisory contract preserved (no skill abort on findings).
- **FR-7:** `lib/handoff.sh` defines `SPRINT_CONTRACT_TEST_REGEX` constant; all 4 call sites (orchestrator.md Step 2.5, ql-plan SKILL.md Step 8, test_sprint_contract.sh, test_sprint_contract_ql_plan.sh) reference it instead of inlining.
- **FR-8:** `references/sprint-contract.md` documents the constant location instead of inlining the regex.
- **FR-9:** `references/finding-severity.md` defines per-mode severity rubric (3 modes × 4 severities, with examples).
- **FR-10:** `agents/spec-reviewer.md` mode sections cross-link the rubric.
- **FR-11:** `quantum-loop.sh --audit` reports `pre-impl-review-coverage` as a 7th metric row with 4 states (missing-csv WARN, no-recent-runs WARN, partial-coverage WARN, full-coverage OK).
- **FR-12:** `agents/dag-validator.md` documents CHANGELOG-ownership convention; `agents/conflict-auditor.md` (or equivalent) classifies multi-story CHANGELOG touches as `severity: warning`.
- **FR-13:** Plugin version bumped 0.6.3 → 0.7.0 across `.claude-plugin/plugin.json`, `.claude-plugin/marketplace.json` (both fields), `.cursor-plugin/plugin.json`.

## Section 5: Non-Goals (Out of Scope)

- **NG-1:** Promoting any pre-impl-review stage from advisory to BLOCKING — explicitly deferred to v0.7.x after ≥1 release of CSV data accumulates.
- **NG-2:** P5.B2 bidirectional reviewer — needs G13's persistence baseline first; deferred to v0.7.1+.
- **NG-3:** P5.B3 `/ultrareview` parallel pattern — composes on B2; deferred.
- **NG-4:** P5.B5 AgentGA tournament — cost-quality tradeoff needs P5.C1 baseline; deferred.
- **NG-5:** P5.C frontier (HiveMind, GEPA, Skilldex, Attacker, etc.) — all deferred.
- **NG-6:** P4 AI-native ecosystem integration — blocked on upstream.
- **NG-7:** Schema migration for existing v0.6.x snapshots — none exist (all v0.6.x advisory findings were ephemeral); v0.7.0 starts fresh.
- **NG-8:** CSV rotation / archival — current usage is ≤3 rows per release; defer to v0.8.x if file exceeds 10K rows.
- **NG-9:** Severity-rubric examples calibrated against historical findings — examples are mode-specific category names from existing checklists, not statistical-quartile-derived. Calibration happens after baseline data accumulates.
- **NG-10:** Cross-platform PS1 audit parity if `quantum-loop.ps1` has no audit shim — divergence documented in CHANGELOG, not blocked-on.

## Section 6: Design Considerations

UI: command-line only. The new persistence layer surfaces in two places:
1. Per-run snapshots at `.handoffs/*-review-findings.json` (operator-inspectable via `cat`/`jq`).
2. Aggregate CSV at `metrics/pre-impl-review-findings.csv` (committable; readable in any spreadsheet tool).

The new `--audit` row appears in the existing audit table layout — no new UI surface.

The severity rubric doc (`references/finding-severity.md`) is markdown — no UI implications.

Schema additions are all backward-compatible (new files, no edits to existing schemas).

## Section 7: Technical Considerations

- **Shell compatibility:** bash 4.3+ (consistent with v0.6.x). `flock` for atomic CSV append where available; rename-replace fallback elsewhere.
- **External tools:** `git`, `grep`, `find`, `wc`, `ls`, `awk`, `jq`, `sha256sum`/`shasum`, `flock` (optional) — all already required.
- **`set -euo pipefail` safety:** new helpers wrap subprocess calls in `{ cmd 2>/dev/null ; } || true` per project convention; CLI subcommand entry points enable strict mode at the bottom of the file (not at source time).
- **Performance:** parser must complete in < 100ms on a typical reviewer stderr (≤50 findings, ≤10K bytes). Persistence write must complete in < 50ms. Audit metric must complete in < 200ms even with 1K-row CSV.
- **Security:** stage argument validated against fixed enum (`{design,prd,plan}`) to prevent path injection. CSV append paths validated against `metrics/` prefix.
- **Cross-platform:** all new tests must exercise both POSIX and Git Bash / MSYS paths per CLAUDE.md Platform Notes — especially CRLF in heredoc-fed JSON parsing (US-001).
- **bash 4.3+ namerefs:** US-001's parser may use `local -n` for cleaner accumulation. Document in function comment per CLAUDE.md convention.

## Section 8: Success Metrics

- All 7 user stories pass with verifiable evidence.
- `bash tests/*.sh` exits 0 with ≥1,700 total assertions (was ~1,640 in v0.6.3; +60-80 from new tests).
- `quantum-loop.sh --audit` after Phase 6 merges still reports all 7 metrics; pre-impl-review-coverage is WARN at `0/3 stages` (correct: orchestrator that ran v0.7.0 was on v0.6.3 HEAD).
- Plugin version bumped to 0.7.0 across all 3 manifests.
- IDEA_REPORT_v5 lists what's open after v0.7.0 (clear roadmap to v0.7.1).
- 0-retry execution record maintained.
- v0.7.0+1 dogfood (the next release after v0.7.0) is the first to produce ≥1 row in `metrics/pre-impl-review-findings.csv` end-to-end.

## Section 9: Open Questions

None. Bundle composition + framing fully resolved by user-confirmed Option α.

## Lifecycle Checklist

- **First-run behavior** — All new mechanisms are advisory or read-only. First post-v0.7.0 run produces empty `metrics/` (correct); first post-v0.7.0 `--audit` reports `0/3 stages WARN` (correct).
- **Returning-user behavior** — Operators who already disabled pre-impl-review via `QL_SKIP_PRE_IMPL_REVIEW=design,prd,plan` continue to see no findings; CSV remains empty for them. No persistence overhead when reviews are skipped.
- **Update behavior** — Schema additions are pure additions (new lib files, new persistence files, new audit row, new doc). No migration of existing v0.6.x state.
- **Error recovery** — Parser tolerates malformed input. Persistence creates missing dirs. CSV append uses atomic guard. Audit metric tolerates missing CSV (reports WARN, doesn't crash).
- **No-data / empty state** — Empty CSV → audit reports WARN. Missing snapshot → `read_review_findings` returns `{}` + warning. None of these are errors.
- **Uninstall / disable** — All new mechanisms are opt-out via the existing `QL_SKIP_PRE_IMPL_REVIEW` env var (one-shot per stage) or by reverting the SKILL hooks. The `metrics/` directory and `.handoffs/*-review-findings.json` files are safe to delete; nothing else depends on them.

## Next Steps

Run `/quantum-loop:ql-plan` on this PRD to generate `quantum.json` with the wave DAG, contracts, and `fileConflicts`. Then `/quantum-loop:ql-execute` to ship.
