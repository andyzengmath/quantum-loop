---
name: ql-housekeep
description: Detect repo-hygiene issues that accumulate during long-running autonomous development (merge-conflict markers, orphan worktrees, CPC-variant duplicates, stale branches, version-manifest drift). Detection-only by default — reports findings, never deletes or modifies without explicit user confirmation.
allowed-tools: Read, Grep, Glob, Bash
---

# ql-housekeep — repo hygiene detector

## Purpose

`ql-housekeep` surfaces the hygiene failures that accumulate when an autonomous development pipeline runs for weeks without human sweep. It is a **detector**, not an actuator. Auto-fix is explicitly out of scope.

This skill exists because `idea-stage/AUDIT_QL.md` catalogued eight categories of hygiene failure on master. The first job of the next pipeline iteration is to not produce that state again.

## When to use

- Before starting a new `/ql-brainstorm` cycle on a repo that has been running parallel execution for weeks.
- As a gate in `ql-execute` between waves if you suspect accumulated drift.
- Manually, when you want a structured view of "what is wrong with the repo right now that the runtime cannot see".

## What it detects

### 1. Merge-conflict markers in tracked files

Pattern: `^<<<<<<<` or `^=======$` or `^>>>>>>>`. These are the signature of an abandoned git merge that was committed without resolution.

Command:
```bash
grep -rn --include='*.md' --include='*.sh' --include='*.ts' --include='*.js' \
  --include='*.py' --include='*.json' --include='*.yml' --include='*.yaml' \
  -E '^<<<<<<<|^=======$|^>>>>>>>' .
```

### 2. Orphan git worktrees

Directories under `.claude/worktrees/agent-*` or `.ql-wt/<story-id>/` that git no longer tracks.

Command:
```bash
for d in .claude/worktrees/agent-* .ql-wt/*; do
  [ -d "$d" ] || continue
  git worktree list | grep -q "$d" || echo "$d"
done
```

### 3. CPC-variant duplicate files

Pattern: files matching `*-CPC-andyz-ZH84K.*`. These are OneDrive-renamed copies that indicate a parallel-hardening fork. If detected, the project likely has two pipelines coexisting — see `idea-stage/AUDIT_QL.md` for promotion protocol.

Command:
```bash
find . -path ./node_modules -prune -o -name '*-CPC-andyz-*' -print
```

### 4. Superseded-but-not-deleted files

Files whose header docstring says "supersedes X" where X still exists. Currently catches:
- `lib/crash-recovery.sh` (superseded by `lib/resilience.sh:3`)

Command (case-insensitive `Supersedes` / `supersedes`):
```bash
for f in lib/*.sh; do
  sup=$(grep -oiE 'supersedes lib/[a-z_-]+\.sh' "$f" 2>/dev/null | head -1 | awk '{print $NF}')
  [ -n "$sup" ] && [ -f "$sup" ] && echo "DEAD: $sup (superseded by $f)"
done
```

### 5. Stale branches

- `worktree-agent-*` branches that are no longer referenced by any live worktree.
- `ql/*` and `fix/*` branches whose tip commits are strict ancestors of master OR have been inactive > 90 days.

Command:
```bash
git branch -a --format='%(refname:short) %(committerdate:short) %(upstream:track)' \
  | awk '$1 ~ /^(ql|fix|worktree-agent)/' \
  | sort -k2
```

### 6. Plugin version / CHANGELOG drift

`.claude-plugin/plugin.json.version` must match `.claude-plugin/marketplace.json.version` and must have a corresponding entry in `CHANGELOG.md`.

Command:
```bash
plugin_v=$(jq -r .version .claude-plugin/plugin.json 2>/dev/null)
market_v=$(jq -r '.plugins[0].version // .version' .claude-plugin/marketplace.json 2>/dev/null)
[ "$plugin_v" = "$market_v" ] || echo "version mismatch: plugin=$plugin_v market=$market_v"
grep -q "^## \[$plugin_v\]" CHANGELOG.md 2>/dev/null || echo "CHANGELOG missing entry for v$plugin_v"
```

### 7. Stale `quantum.json`

`quantum.json.updatedAt` older than 30 days with the project in active development suggests the team isn't dogfooding.

Command:
```bash
last=$(jq -r '.updatedAt // empty' quantum.json 2>/dev/null)
if [ -n "$last" ]; then
  age_days=$(( ($(date +%s) - $(date -d "$last" +%s)) / 86400 ))
  [ "$age_days" -gt 30 ] && echo "quantum.json not updated in $age_days days"
fi
```

### 8. Duplicate test files (same logical test in two files)

Pattern: two test files whose paths differ only by a suffix that indicates a fork (`-CPC-*`, `.bak`, `.old`, ` copy`).

Command:
```bash
find tests -type f -name '*.sh' \
  | sed -E 's/(-CPC-[^/]+|\.bak|\.old| copy)?\.sh$//' \
  | sort | uniq -d
```

## Anti-rationalization guards

| The agent says… | The truth is… |
|-----------------|---------------|
| "These orphan worktrees must be live runs" | Live worktrees appear in `git worktree list`. If they don't, they're orphans. |
| "Deleting the CPC-variant could lose work" | That's why this skill does NOT delete. It REPORTS. Promotion is a separate user-confirmed action (see `docs/plans/2026-04-21-p0-consolidation-design.md`). |
| "The merge-conflict markers are inside a docstring example" | Then they wouldn't pass lint or test. The code is not doing conditional-skip. |
| "The supersedes comment is ambiguous" | Read the file, confirm, then report. Never silently swallow detection. |
| "CHANGELOG is a nice-to-have" | Users rely on CHANGELOG to know what changed between versions. An empty CHANGELOG means the team has abandoned the compact with downstream. |

## How to run

The skill produces a structured report to stdout. No flags required.

```bash
# In Claude Code:
/quantum-loop:ql-housekeep
```

The skill will:
1. Run each detector in turn.
2. Emit a section per category with findings.
3. Summarize as a `findings[]` JSON block at the end.
4. Return an exit code: 0 = clean, 1 = findings present.

## What it does NOT do

- Delete files.
- Rename files.
- Prune branches.
- Remove worktrees.
- Modify CHANGELOG or plugin manifests.
- Commit anything.

Fixes are the user's job, potentially driven by the consolidation design in `docs/plans/2026-04-21-p0-consolidation-design.md`.

## Output format

```json
{
  "timestamp": "<ISO 8601>",
  "branch": "<current branch>",
  "summary": {
    "conflict_markers": 0,
    "orphan_worktrees": 0,
    "cpc_variants": 0,
    "superseded_files": 0,
    "stale_branches": 0,
    "version_drift": false,
    "stale_quantum_json": false,
    "duplicate_test_files": 0
  },
  "findings": [
    {
      "category": "conflict_markers",
      "severity": "high",
      "file": "README.md",
      "lines": [368, 372, 399],
      "detail": "<content snippet>"
    }
  ],
  "recommended_next_steps": [
    "Review idea-stage/AUDIT_QL.md before taking action",
    "Do not delete anything without user confirmation",
    "See docs/plans/2026-04-21-p0-consolidation-design.md for a full consolidation protocol"
  ]
}
```

## Integration with other skills

- **`ql-brainstorm`**: Reads prior `ql-housekeep` output to warn about hygiene before inviting new design work.
- **`ql-execute`**: Between waves, runs `ql-housekeep` as a lightweight check; warns user but does not auto-fix.
- **`ql-review`**: Post-merge review phase inspects whether the merge introduced any of categories 1, 3, 4, 8.

## Known limitations

- Detection patterns are intentionally conservative — false negatives preferred over false positives because this drives user action.
- Category 5 (stale branches) uses simple heuristics; borderline cases should be manually classified.
- The skill does not detect content-level duplicate code across stories; that is the job of `agents/duplication-detector.md`.
