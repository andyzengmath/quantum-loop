# Updating the quantum-loop Plugin Version

## The Problem

Claude Code's plugin cache is **not invalidated on uninstall/reinstall**. This is a known bug:

- [#14061](https://github.com/anthropics/claude-code/issues/14061): `/plugin update` does not invalidate plugin cache
- [#29074](https://github.com/anthropics/claude-code/issues/29074): Plugin cache not cleared on uninstall/reinstall, wrong version loaded

This means that after bumping the version in `plugin.json` and pushing to GitHub, users running `/plugin uninstall` + `/plugin install` will still get the old cached version.

## How Plugin Versioning Works (Intended)

- Claude Code reads the `version` field from `.claude-plugin/plugin.json` (not git tags)
- The cache directory is at `~/.claude/plugins/cache/quantum-loop/quantum-loop/<version>/`
- `claude plugin update <name>` should fetch the latest version — but doesn't reliably due to the cache bug

## For Maintainers: Releasing a New Version

### 1. Bump version in all manifest files

```bash
# These 3 files must all have the same version:
.claude-plugin/plugin.json        # "version": "X.Y.Z"
.claude-plugin/marketplace.json   # "version": "X.Y.Z" (appears twice: metadata + plugins)
.cursor-plugin/plugin.json        # "version": "X.Y.Z"
```

### 2. Update CHANGELOG.md and README.md

### 3. Commit, push, and create GitHub release

```bash
git add -A && git commit -m "docs: bump to vX.Y.Z, update CHANGELOG"
git push origin master
gh release create vX.Y.Z --title "vX.Y.Z — <summary>" --notes "<release notes>"
```

## For Users: Updating to a New Version

### The correct workaround (until the cache bug is fixed)

```bash
# 1. Nuke the plugin cache
rm -rf ~/.claude/plugins/cache/quantum-loop

# 2. Restart Claude Code, then reinstall
/plugin marketplace add andyzengmath/quantum-loop
/plugin install quantum-loop
```

### What does NOT work reliably

```bash
# These do NOT clear the cache — you'll get the old version:
/plugin uninstall quantum-loop
/plugin install quantum-loop

# This also doesn't work due to the cache bug:
/plugin update quantum-loop
```

### Verify the update

After reinstalling, ask Claude Code:

```
What version is the quantum-loop plugin?
```

Or check directly:

```bash
cat ~/.claude/plugins/cache/quantum-loop/quantum-loop/*/.claude-plugin/plugin.json | grep version
```

## Why This Happens

Claude Code caches plugin files in `~/.claude/plugins/cache/` at install time. The cache is keyed by a directory name that includes the version string. When you uninstall and reinstall, Claude Code is supposed to clear this cache and re-fetch from GitHub — but it doesn't. The stale cache directory persists and gets reused, so the old version's files are loaded even though the remote has a newer version.

The `plugin.json` version field is the sole source of truth for version detection. Git tags are not consulted. The cache directory name may not match the actual version inside `plugin.json` due to this bug.
