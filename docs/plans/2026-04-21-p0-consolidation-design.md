# 2026-04-21 — P0 Consolidation Design

**Status**: drafted by `/research-pipeline` Stage-2; awaiting user confirmation before destructive ops
**Source analysis**: `idea-stage/IDEA_REPORT.md`, `idea-stage/AUDIT_QL.md`, `idea-stage/WORKING_NOTES.md`
**Branch**: `ql/research-p0-bundle` (created from master)

## Problem statement

Quantum-loop master is a regressed baseline relative to the project's actual state of work. Independent audit (`idea-stage/AUDIT_QL.md`) demonstrates that:

1. **Two complete parallel pipelines coexist in one repo.** Plain `skills/*/SKILL.md`, `agents/*.md`, and `lib/*.sh` (Feb 15–26) predate every post-mortem fix. `*-CPC-andyz-ZH84K.*` variants (Mar 18 – Mar 30) carry all hardening from the 7 recent design docs. Runtime loading order determines which pipeline the user runs — this is observable non-determinism.

2. **~991 commits of post-v0.2.0 work sit unmerged** on `ql/*` branches: multi-runner 256, hardening-v2 226, modular-hardening 185, dag-intelligence 148, progressive-materialization 126, post-mortem-fixes 50. No single branch is a clean integration of the full intended feature set.

3. **Surface-level self-discipline failures** compound the above:
   - README.md had 3 unresolved merge-conflict markers (fixed on this branch).
   - CHANGELOG.md stops at v0.2.0 while plugin.json is v0.4.1 — two minor releases undocumented.
   - 89 git branches, 45 orphan `.claude/worktrees/agent-*` directories (re-verified 2026-04-21 by `git branch -a | wc -l` and `ls -d .claude/worktrees/agent-* | wc -l`).
   - `lib/crash-recovery.sh` explicitly superseded by `lib/resilience.sh:3` but not removed.
   - `quantum.json` is frozen on the Feb 2026 US-001 story — the project has never dogfooded its own pipeline on any of the 7 hardening cycles since.

## Goals (in priority order)

1. **Restore a single canonical pipeline.** One `SKILL.md` per skill, one `*.md` per agent, one `*.sh` per library module. CPC-variants either promoted-over-plain or deleted with documented rationale.
2. **Produce an integration branch** that carries the intended post-hardening-v2 behavior. Tested, reviewable, mergeable to master as one reviewable unit.
3. **Dogfood**: the entire P0 consolidation is itself planned via `/ql-spec` + `/ql-plan` → executed via `/ql-execute`. First real project self-use.
4. **Repo hygiene automation** (`ql-housekeep` skill) so the same state cannot accumulate again.

## Non-goals

- **No new pipeline capability** in P0. Stage-3 review, intent-drift audit, multi-perspective aggregator, slop cleanup — all are P1+, deferred to a follow-on cycle.
- **No AI-native-rebuild integration** (EvidenceBundle / ContextPack / SLSA). These are strategic P4 items blocked on upstream deps.
- **No academic-wedge implementation** (SSAT, SCF). Research-grade; defer.
- **No branch archaeology to recover lost ideas**. If something was worth keeping, it's on a branch name we can identify from git log.

## Approach — four sub-phases

### Phase P0.A — Safe surface fixes (this branch, no destructive ops)

Already applied on `ql/research-p0-bundle`:
- README.md merge-conflict markers removed (equivalent to `fix/resolve-merge-conflicts`, commit `a067948`).
- This design doc created.
- `ql-housekeep` skill added (detection-only).

Pending in this sub-phase:
- CHANGELOG.md backfill for v0.3.x and v0.4.x (no semver lie; document what plugin.json claims).
- Inventory diff report: which plain files differ from CPC variants, by delta size.

Ship criterion: branch mergeable as a docs-only PR. Zero risk.

### Phase P0.B — CPC → canonical promotion (requires user confirmation)

For each pair `X` + `X-CPC-andyz-ZH84K`:
1. `git diff` plain vs CPC.
2. Confirm CPC is intended authoritative (newer, includes hardening per AUDIT §6).
3. Delete plain orphan, rename CPC → plain via `git mv` (if both tracked) or `mv` (for untracked working-tree files).
4. Verify the pipeline still loads and the test suite still passes.

Applies to (count from AUDIT):
- **6 skills**: `ql-brainstorm`, `ql-spec`, `ql-plan`, `ql-execute`, `ql-review`, `ql-verify`.
- **4 agents**: `orchestrator`, `implementer`, `spec-reviewer`, `quality-reviewer`.
- **6 libs**: `common.sh`, `dag-query.sh`, `json-atomic.sh`, `worktree.sh`, `spawn.sh`, `monitor.sh`.
- **3 tests**: `test_crash_recovery`, `test_dag_query`, `test_spawn`.
- **Root-level (10)**: `.gitignore`, `.claude-plugin/plugin.json`, `.claude-plugin/marketplace.json`, `CHANGELOG.md`, `CLAUDE.md`, `README.md`, `quantum-loop.sh`, `quantum-loop.ps1`, `quantum.json`, `quantum.json.example`, `templates/quantum-loop.sh`.

Ship criterion: `master` has one file per name; full test suite passes on ql/research-p0-bundle.

**Destructive ops gate**: user must confirm before P0.B proceeds.

### Phase P0.C — Dead-code + branch + worktree cleanup

1. Delete `lib/crash-recovery.sh` — `resilience.sh:3` declares it superseded.
2. Remove `.claude/worktrees/agent-*` directories (45 of them) — these are abandoned worktree artifacts, not live trees.
3. Prune git branches: `worktree-agent-*`, merged `fix/*`, superseded `ql/*` once P0.D completes.
4. Audit remaining `ql/*` branches: document in `archive/` each branch's theme + key commit SHA + decision (merged / superseded / archived-as-reference / deleted).

**Destructive ops gate**: each deletion preceded by a `git tag archive/pre-p0-<date>-<branch>` so any branch can be recovered via `git checkout archive/...`.

### Phase P0.D — Integration branch consolidation

Create `ql/integrate-2026-04-21` from post-P0.B master state; cherry-pick or merge in dependency order:

1. `ql/post-mortem-fixes` (oldest substantive hardening; 50 commits).
2. `ql/progressive-materialization` (126 commits; builds on post-mortem contract plumbing).
3. `ql/modular-hardening` (185 commits; modular merge-hardening foundation).
4. `ql/dag-intelligence` (148 commits; DAG validator + bottleneck/conflict/duplication/type auditors).
5. `ql/hardening-v2` (226 commits; late-stage merge hardening).
6. `ql/multi-runner` (256 commits; universal CLI orchestrator; largest, latest).

Expected conflict categories (per `agents/conflict-auditor.md` severity model):
- **HIGH**: barrel files (`skills/*/SKILL.md`, `agents/*.md`) — multiple branches touch same file.
- **MEDIUM**: `lib/*.sh` shared across branches.
- **LOW**: test fixtures, documentation.

Resolution strategy: prefer newer CPC-variant content where P0.B has already promoted; prefer hardening-v2 for `lib/merge-*.sh`; prefer multi-runner for `lib/runner.sh` + `runners/`.

**Merge-abort recovery**: if any single merge step produces >3 unrelated conflicts, abort via `git merge --abort`, tag the partial state via `git tag archive/p0d-partial-<step>-<YYYYMMDD>`, escalate to user with: (a) the aborted step, (b) the conflict summary, (c) a recommendation to either retry in a different order, drop that branch entirely, or perform manual conflict resolution in a worktree before resuming. Do not proceed to the next step until user decides.

Ship criterion: integration branch tip has all 29 unit + 10 integration tests green; `plugin.json` / `marketplace.json` / `CHANGELOG.md` / `README.md` reconciled; dogfood metric: a fresh `quantum.json` tracked the P0 work start-to-finish.

## Acceptance criteria (verifiable)

- [ ] README.md has 0 merge-conflict markers.
- [ ] No `*-CPC-andyz-ZH84K.*` files tracked in git after P0.B.
- [ ] `lib/crash-recovery.sh` is absent after P0.C.
- [ ] `.claude/worktrees/agent-*` directory count = 0 after P0.C.
- [ ] `git branch -a | wc -l` ≤ 15 after P0.C.
- [ ] CHANGELOG.md has an entry for every version in `plugin.json`.
- [ ] `quantum.json.updatedAt` is within 7 days of the integration merge.
- [ ] `codebasePatterns` has ≥1 entry documenting a lesson learned during P0 execution.
- [ ] `bash tests/*.sh` exits 0 on the integration branch tip.
- [ ] Sample run of `/ql-execute` on a trivial story succeeds end-to-end on the integration branch.

## Risks

| Risk | Likelihood | Mitigation |
|------|-----------|-----------|
| CPC-variant assumed authoritative is actually regressed on some dimension | low | Phase P0.B diffs every pair before promotion; any non-trivial semantic difference triggers human review. |
| `ql/*` integration produces a tangled merge-conflict swamp | high | Do integration in the declared order above; land each merge as a discrete commit with conflict-resolution notes; abort if >3 unrelated conflicts accumulate in one step. |
| Deletions lose genuinely active work | low | Tag-before-delete policy; all destructive ops require confirmation. |
| User's current working-tree untracked files are disturbed | medium | Do not run `git clean`; do not use `git reset --hard` on master; keep work on `ql/research-p0-bundle`. |
| Test suite reveals CPC-variant has latent bugs the plain variant doesn't | medium | Roll back promotion for affected file; open a fix-story against that file on a new branch; surface to user. |

## Rollout

1. **Phase P0.A lands as a standalone PR** (branch `ql/research-p0-bundle` into master). Pure docs + detection skill; no runtime change.
2. **Phase P0.B lands as a second PR** (post-confirmation) with file promotions.
3. **Phase P0.C lands as a third PR** with deletions, after P0.B is merged.
4. **Phase P0.D lands as the main integration PR** once A+B+C are on master.

## Metrics / what success looks like

Per `idea-stage/IDEA_REPORT.md §6`:

| Metric | Pre-P0 (now) | Post-P0 target |
|--------|-------------:|---------------:|
| Branch count (`git branch -a \| wc -l`) | 89 | ≤ 15 |
| Orphan `.claude/worktrees/agent-*` | 45 | 0 |
| README merge-conflict markers | 3 (fixed in P0.A) | 0 |
| CPC-variant files | ~20 | 0 |
| `lib/crash-recovery.sh` present | yes | no |
| CHANGELOG entries ≥ plugin.json version | no | yes |
| `quantum.json` last-updated | 2026-02-18 | ≤ 7d ago |
| Test suite green on master | unknown | yes (bash tests/*.sh) |

## Why this is worth doing first (one-sentence justification)

Without P0, every user-requested improvement to the parallel-execution pipeline, review pipeline, or intent-preservation layer would be designed against a runtime whose behavior depends on which of two coexistent file trees the installer happens to load first — a defect too fundamental to paper over with additional mechanism.

## Next action

Run `/quantum-loop:ql-spec` on this design to generate `tasks/prd-p0-consolidation.md`, then `/quantum-loop:ql-plan` to generate a new `quantum.json` describing the P0 work as user stories. This is the dogfood step.
